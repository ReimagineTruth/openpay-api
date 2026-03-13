-- Updated Mining System Script with Ad Support
-- Run this in your Supabase SQL Editor to fix mining functionality with ad verification

-- Update the start_mining_session function to support ad verification
CREATE OR REPLACE FUNCTION public.start_mining_session(p_device_fingerprint TEXT, p_ip_address TEXT, p_ad_verified BOOLEAN DEFAULT false, p_pi_browser_used BOOLEAN DEFAULT false)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_active_session_id UUID;
  v_expires_at TIMESTAMPTZ := now() + INTERVAL '24 hours';
BEGIN
  -- Check for existing active session
  SELECT id INTO v_active_session_id
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true AND expires_at > now();

  IF v_active_session_id IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Mining session already active', 'session_id', v_active_session_id);
  END IF;

  -- Deactivate any stale sessions
  UPDATE public.mining_sessions
  SET is_active = false
  WHERE user_id = v_user_id AND is_active = true;

  -- Start new session with ad verification support
  INSERT INTO public.mining_sessions (user_id, expires_at, device_fingerprint, ip_address, ad_verified, pi_browser_used)
  VALUES (v_user_id, v_expires_at, p_device_fingerprint, p_ip_address, p_ad_verified, p_pi_browser_used)
  RETURNING id INTO v_active_session_id;

  -- Return success with session info
  RETURN jsonb_build_object(
    'success', true, 
    'session_id', v_active_session_id, 
    'expires_at', v_expires_at,
    'ad_verified', p_ad_verified,
    'pi_browser_used', p_pi_browser_used
  );
END;
$$;

-- Create function to sync mining state (for better reliability)
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
  -- Get current active session
  SELECT * INTO v_active_session
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true AND expires_at > now()
  ORDER BY expires_at DESC
  LIMIT 1;

  -- Get claimable session (expired but still marked active)
  SELECT * INTO v_claimable_session
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true AND expires_at <= now()
  ORDER BY expires_at DESC
  LIMIT 1;

  -- Return both sessions
  RETURN jsonb_build_object(
    'activeSession', CASE WHEN v_active_session.id IS NOT NULL THEN 
      jsonb_build_object(
        'id', v_active_session.id,
        'user_id', v_active_session.user_id,
        'started_at', v_active_session.started_at,
        'expires_at', v_active_session.expires_at,
        'is_active', v_active_session.is_active,
        'ad_verified', v_active_session.ad_verified,
        'pi_browser_used', v_active_session.pi_browser_used,
        'created_at', v_active_session.created_at
      )::JSONB 
    ELSE NULL::JSONB END,
    'claimableSession', CASE WHEN v_claimable_session.id IS NOT NULL THEN 
      jsonb_build_object(
        'id', v_claimable_session.id,
        'user_id', v_claimable_session.user_id,
        'started_at', v_claimable_session.started_at,
        'expires_at', v_claimable_session.expires_at,
        'is_active', v_claimable_session.is_active,
        'ad_verified', v_claimable_session.ad_verified,
        'pi_browser_used', v_claimable_session.pi_browser_used,
        'created_at', v_claimable_session.created_at
      )::JSONB 
    ELSE NULL::JSONB END
  );
END;
$$;

-- Create function to get mining dashboard data
CREATE OR REPLACE FUNCTION public.get_mining_dashboard()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_active_session RECORD;
  v_total_rewards NUMERIC;
  v_session_count INTEGER;
BEGIN
  -- Get current active session
  SELECT * INTO v_active_session
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true AND expires_at > now()
  ORDER BY expires_at DESC
  LIMIT 1;

  -- Get total rewards
  SELECT COALESCE(SUM(amount), 0) INTO v_total_rewards
  FROM public.mining_rewards
  WHERE user_id = v_user_id;

  -- Get session count
  SELECT COUNT(*) INTO v_session_count
  FROM public.mining_sessions
  WHERE user_id = v_user_id;

  -- Return dashboard data
  RETURN jsonb_build_object(
    'activeSession', CASE WHEN v_active_session.id IS NOT NULL THEN 
      jsonb_build_object(
        'id', v_active_session.id,
        'expires_at', v_active_session.expires_at,
        'ad_verified', v_active_session.ad_verified,
        'pi_browser_used', v_active_session.pi_browser_used
      )::JSONB 
    ELSE NULL::JSONB END,
    'totalRewards', v_total_rewards,
    'sessionCount', v_session_count
  );
END;
$$;

-- Update claim function to handle ad-verified sessions properly
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
BEGIN
  -- Get active session or expired but unclaimed session
  SELECT * INTO v_session
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true
  ORDER BY expires_at DESC
  LIMIT 1;

  IF v_session IS NULL THEN
    RETURN jsonb_build_object('error', 'No active or completed mining session found');
  END IF;

  -- Check if already rewarded for this session
  IF EXISTS (SELECT 1 FROM public.mining_rewards WHERE session_id = v_session.id AND reward_type = 'base') THEN
     -- If already rewarded, just deactivate and return error
     UPDATE public.mining_sessions SET is_active = false WHERE id = v_session.id;
     RETURN jsonb_build_object('error', 'Reward already claimed for this session');
  END IF;

  -- Allow claim if session has expired OR if ad was verified (for immediate claims)
  IF v_session.expires_at > now() AND v_session.ad_verified = false THEN
     RETURN jsonb_build_object('error', 'Mining still in progress. Come back after 24 hours.');
  END IF;

  -- Calculate active referrals (those who have an active mining session)
  SELECT COUNT(DISTINCT r.referred_user_id) INTO v_active_referrals
  FROM public.referral_rewards r
  JOIN public.mining_sessions ms ON ms.user_id = r.referred_user_id
  WHERE r.referrer_user_id = v_user_id
   AND ms.is_active = true
   AND ms.expires_at > now();

  v_bonus_reward := LEAST(v_base_reward * v_active_referrals * v_referral_bonus_rate, v_base_reward * v_max_bonus_rate);
  v_total_reward := v_base_reward + v_bonus_reward;

  -- Record rewards
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

  -- Deactivate session
  UPDATE public.mining_sessions
  SET is_active = false
  WHERE id = v_session.id;

  RETURN jsonb_build_object(
    'success', true, 
    'base_reward', v_base_reward, 
    'bonus_reward', v_bonus_reward, 
    'total_reward', v_total_reward,
    'active_referrals', v_active_referrals,
    'ad_verified', v_session.ad_verified
  );
END;
$$;

-- Grant permissions for new functions
GRANT EXECUTE ON FUNCTION public.sync_mining_state() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_mining_dashboard() TO authenticated;

-- Success message
SELECT 'Mining system updated with ad verification support!' as status;
