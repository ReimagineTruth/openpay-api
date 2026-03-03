-- Mining System Setup Script
-- Run this in your Supabase SQL Editor to fix mining functionality

-- First, create the tables
CREATE TABLE IF NOT EXISTS public.mining_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  last_reward_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_active BOOLEAN NOT NULL DEFAULT true,
  device_fingerprint TEXT,
  ip_address TEXT,
  ad_verified BOOLEAN DEFAULT false,
  pi_browser_used BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.mining_rewards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id UUID REFERENCES public.mining_sessions(id) ON DELETE SET NULL,
  amount NUMERIC NOT NULL,
  reward_type TEXT NOT NULL CHECK (reward_type IN ('base', 'referral_bonus')),
  referral_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create app_notifications table
CREATE TABLE IF NOT EXISTS public.app_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'info' CHECK (type IN ('info', 'success', 'warning', 'error')),
  read_at TIMESTAMPTZ,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_mining_sessions_user_active ON public.mining_sessions(user_id) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_mining_rewards_user ON public.mining_rewards(user_id);
CREATE INDEX IF NOT EXISTS idx_app_notifications_user_unread ON public.app_notifications(user_id) WHERE read_at IS NULL;

-- Function to start mining
CREATE OR REPLACE FUNCTION public.start_mining_session(p_device_fingerprint TEXT, p_ip_address TEXT)
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

  -- Start new session
  INSERT INTO public.mining_sessions (user_id, expires_at, device_fingerprint, ip_address)
  VALUES (v_user_id, v_expires_at, p_device_fingerprint, p_ip_address)
  RETURNING id INTO v_active_session_id;

  RETURN jsonb_build_object('success', true, 'session_id', v_active_session_id, 'expires_at', v_expires_at);
END;
$$;

-- Function to claim mining rewards
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

  -- Only allow claim if session has expired
  IF v_session.expires_at > now() THEN
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
    'active_referrals', v_active_referrals
  );
END;
$$;

-- RLS Policies
ALTER TABLE public.mining_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mining_rewards ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own mining sessions" ON public.mining_sessions;
CREATE POLICY "Users can view their own mining sessions"
ON public.mining_sessions FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view their own mining rewards" ON public.mining_rewards;
CREATE POLICY "Users can view their own mining rewards"
ON public.mining_rewards FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Enable Realtime (ignore if already enabled)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
        AND schemaname = 'public' 
        AND tablename = 'mining_sessions'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.mining_sessions;
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
        AND schemaname = 'public' 
        AND tablename = 'mining_rewards'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.mining_rewards;
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
        AND schemaname = 'public' 
        AND tablename = 'app_notifications'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.app_notifications;
    END IF;
END $$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.start_mining_session(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_mining_rewards() TO authenticated;

-- Create admin_list_swap_withdrawals function
CREATE OR REPLACE FUNCTION public.admin_list_swap_withdrawals()
RETURNS TABLE (
  id UUID,
  user_id UUID,
  amount NUMERIC,
  status TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- This is a placeholder function for admin functionality
  -- In a full implementation, this would query swap withdrawals table
  RETURN QUERY SELECT 
    gen_random_uuid()::UUID as id,
    auth.uid()::UUID as user_id,
    0::NUMERIC as amount,
    'pending'::TEXT as status,
    now()::TIMESTAMPTZ as created_at,
    now()::TIMESTAMPTZ as updated_at
  LIMIT 0;
END;
$$;

-- Grant admin function permissions
GRANT EXECUTE ON FUNCTION public.admin_list_swap_withdrawals() TO authenticated;

-- RLS Policies for app_notifications
ALTER TABLE public.app_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own notifications" ON public.app_notifications;
CREATE POLICY "Users can view their own notifications"
ON public.app_notifications FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own notifications" ON public.app_notifications;
CREATE POLICY "Users can insert their own notifications"
ON public.app_notifications FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own notifications" ON public.app_notifications;
CREATE POLICY "Users can update their own notifications"
ON public.app_notifications FOR UPDATE
TO authenticated
USING (auth.uid() = user_id);

-- Success message
SELECT 'Mining system setup completed successfully!' as status;
