-- 20260303150000_fix_mining_session_management.sql
-- Fix mining session management to prevent restarts and ensure proper countdown tracking

-- Add ad verification tracking to mining sessions
ALTER TABLE public.mining_sessions 
ADD COLUMN IF NOT EXISTS ad_verified BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS pi_browser_used BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS last_sync_at TIMESTAMPTZ DEFAULT now();

-- Add unique constraint to prevent duplicate active sessions
ALTER TABLE public.mining_sessions 
ADD CONSTRAINT unique_active_session 
UNIQUE (user_id, is_active) 
DEFERRABLE INITIALLY DEFERRED;

-- Create improved function to start mining session with better validation
CREATE OR REPLACE FUNCTION public.start_mining_session(p_device_fingerprint TEXT, p_ip_address TEXT, p_ad_verified BOOLEAN DEFAULT false, p_pi_browser_used BOOLEAN DEFAULT false)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_active_session_id UUID;
  v_expires_at TIMESTAMPTZ := now() + INTERVAL '24 hours';
  v_stale_sessions INTEGER;
BEGIN
  -- Check for existing active session
  SELECT id INTO v_active_session_id
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true AND expires_at > now();

  IF v_active_session_id IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Mining session already active', 'session_id', v_active_session_id);
  END IF;

  -- Count and deactivate any stale sessions
  UPDATE public.mining_sessions
  SET is_active = false, last_sync_at = now()
  WHERE user_id = v_user_id AND is_active = true
  RETURNING 1 INTO v_stale_sessions;

  -- Start new session with ad verification tracking
  INSERT INTO public.mining_sessions (
    user_id, 
    expires_at, 
    device_fingerprint, 
    ip_address,
    ad_verified,
    pi_browser_used,
    last_sync_at
  )
  VALUES (
    v_user_id, 
    v_expires_at, 
    p_device_fingerprint, 
    p_ip_address,
    p_ad_verified,
    p_pi_browser_used,
    now()
  )
  RETURNING id INTO v_active_session_id;

  RETURN jsonb_build_object(
    'success', true, 
    'session_id', v_active_session_id, 
    'expires_at', v_expires_at,
    'ad_verified', p_ad_verified,
    'pi_browser_used', p_pi_browser_used,
    'stale_sessions_deactivated', v_stale_sessions
  );
END;
$$;

-- Create improved function to claim mining rewards with better session management
CREATE OR REPLACE FUNCTION public.claim_mining_rewards()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_session RECORD;
  v_base_reward NUMERIC := 0.10;
  v_referral_bonus_rate NUMERIC := 0.10; -- 10% per active referral
  v_max_bonus_rate NUMERIC := 1.00; -- 100% max bonus
  v_active_referrals INTEGER;
  v_total_reward NUMERIC;
  v_bonus_reward NUMERIC;
  v_already_claimed BOOLEAN;
BEGIN
  -- Get the most recent session (active or expired but unclaimed)
  SELECT * INTO v_session
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true
  ORDER BY 
    CASE WHEN expires_at > now() THEN 0 ELSE 1 END, -- Active sessions first
    expires_at DESC -- Most recent first
  LIMIT 1;

  IF v_session IS NULL THEN
    -- Check for expired but unclaimed session
    SELECT * INTO v_session
    FROM public.mining_sessions
    WHERE user_id = v_user_id AND is_active = true AND expires_at <= now()
    ORDER BY expires_at DESC
    LIMIT 1;
    
    IF v_session IS NULL THEN
      RETURN jsonb_build_object('error', 'No mining session found to claim');
    END IF;
  END IF;

  -- Check if already rewarded for this session
  SELECT EXISTS(SELECT 1 FROM public.mining_rewards WHERE session_id = v_session.id AND reward_type = 'base') 
  INTO v_already_claimed;

  IF v_already_claimed THEN
    -- Deactivate the already claimed session
    UPDATE public.mining_sessions 
    SET is_active = false, last_sync_at = now() 
    WHERE id = v_session.id;
    RETURN jsonb_build_object('error', 'Reward already claimed for this session');
  END IF;

  -- Only allow claim if session has expired
  IF v_session.expires_at > now() THEN
    RETURN jsonb_build_object('error', 'Mining still in progress. Come back after 24 hours.');
  END IF;

  -- Calculate active referrals (those who have an active mining session)
  SELECT COUNT(DISTINCT r.referred_user_id) INTO v_active_referrals
  FROM public.referral_rewards r
  JOIN public.mining_sessions ms ON ms.user_id = r.referred_user_id
  WHERE r.referrer_id = v_user_id
    AND ms.is_active = true
    AND ms.expires_at > now();

  v_bonus_reward := LEAST(v_base_reward * v_active_referrals * v_referral_bonus_rate, v_base_reward * v_max_bonus_rate);
  v_total_reward := v_base_reward + v_bonus_reward;

  -- Record rewards in a transaction
  INSERT INTO public.mining_rewards (user_id, session_id, amount, reward_type)
  VALUES (v_user_id, v_session.id, v_base_reward, 'base');

  IF v_bonus_reward > 0 THEN
    INSERT INTO public.mining_rewards (user_id, session_id, amount, reward_type)
    VALUES (v_user_id, v_session.id, v_bonus_reward, 'referral_bonus');
  END IF;

  -- Update wallet balance
  UPDATE public.wallets
  SET balance = balance + v_total_reward,
      updated_at = now()
  WHERE user_id = v_user_id;

  -- Deactivate session and update sync
  UPDATE public.mining_sessions
  SET is_active = false, 
      last_sync_at = now()
  WHERE id = v_session.id;

  RETURN jsonb_build_object(
    'success', true, 
    'base_reward', v_base_reward, 
    'bonus_reward', v_bonus_reward, 
    'total_reward', v_total_reward,
    'active_referrals', v_active_referrals,
    'session_expired', v_session.expires_at <= now(),
    'ad_verified', v_session.ad_verified,
    'pi_browser_used', v_session.pi_browser_used
  );
END;
$$;

-- Create function to sync mining state (for dashboard consistency)
CREATE OR REPLACE FUNCTION public.sync_mining_state()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_active_session RECORD;
  v_claimable_session RECORD;
BEGIN
  -- Get active session
  SELECT * INTO v_active_session
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true AND expires_at > now()
  ORDER BY expires_at DESC
  LIMIT 1;

  -- If no active session, check for claimable expired session
  IF v_active_session IS NULL THEN
    SELECT * INTO v_claimable_session
    FROM public.mining_sessions
    WHERE user_id = v_user_id AND is_active = true AND expires_at <= now()
    ORDER BY expires_at DESC
    LIMIT 1;
  END IF;

  -- Update last sync timestamp
  IF v_active_session IS NOT NULL THEN
    UPDATE public.mining_sessions 
    SET last_sync_at = now() 
    WHERE id = v_active_session.id;
  ELSIF v_claimable_session IS NOT NULL THEN
    UPDATE public.mining_sessions 
    SET last_sync_at = now() 
    WHERE id = v_claimable_session.id;
  END IF;

  RETURN jsonb_build_object(
    'active_session', v_active_session,
    'claimable_session', v_claimable_session,
    'synced_at', now()
  );
END;
$$;

-- Create index for better performance
CREATE INDEX IF NOT EXISTS idx_mining_sessions_user_active_expires 
ON public.mining_sessions(user_id, is_active, expires_at DESC);

CREATE INDEX IF NOT EXISTS idx_mining_sessions_last_sync 
ON public.mining_sessions(last_sync_at);

-- Update RLS policies to include new columns
DROP POLICY IF EXISTS "Users can view their own mining sessions" ON public.mining_sessions;
CREATE POLICY "Users can view their own mining sessions"
ON public.mining_sessions FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Ensure grants are correct
GRANT EXECUTE ON FUNCTION public.start_mining_session(TEXT, TEXT, BOOLEAN, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_mining_rewards() TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_mining_state() TO authenticated;
