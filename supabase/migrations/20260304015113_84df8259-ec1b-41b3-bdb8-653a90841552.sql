
-- Create mining_sessions table
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

-- Create mining_rewards table
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

-- Enable RLS
ALTER TABLE public.mining_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mining_rewards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_notifications ENABLE ROW LEVEL SECURITY;

-- Mining sessions policies
CREATE POLICY "Users can view their own mining sessions" ON public.mining_sessions FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- Mining rewards policies
CREATE POLICY "Users can view their own mining rewards" ON public.mining_rewards FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- App notifications policies
CREATE POLICY "Users can view their own notifications" ON public.app_notifications FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own notifications" ON public.app_notifications FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own notifications" ON public.app_notifications FOR UPDATE TO authenticated USING (auth.uid() = user_id);

-- Enable Realtime
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'mining_sessions') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.mining_sessions;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'mining_rewards') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.mining_rewards;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'app_notifications') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.app_notifications;
    END IF;
END $$;

-- Function: start_mining_session
CREATE OR REPLACE FUNCTION public.start_mining_session(
  p_device_fingerprint TEXT DEFAULT '',
  p_ip_address TEXT DEFAULT '',
  p_ad_verified BOOLEAN DEFAULT false,
  p_pi_browser_used BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_active_session_id UUID;
  v_expires_at TIMESTAMPTZ := now() + INTERVAL '24 hours';
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT id INTO v_active_session_id
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true AND expires_at > now();

  IF v_active_session_id IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Mining session already active', 'session_id', v_active_session_id);
  END IF;

  -- Deactivate stale sessions
  UPDATE public.mining_sessions SET is_active = false WHERE user_id = v_user_id AND is_active = true;

  -- Start new session
  INSERT INTO public.mining_sessions (user_id, expires_at, device_fingerprint, ip_address, ad_verified, pi_browser_used)
  VALUES (v_user_id, v_expires_at, p_device_fingerprint, p_ip_address, p_ad_verified, p_pi_browser_used)
  RETURNING id INTO v_active_session_id;

  RETURN jsonb_build_object('success', true, 'session_id', v_active_session_id, 'expires_at', v_expires_at);
END;
$$;

-- Function: claim_mining_rewards
CREATE OR REPLACE FUNCTION public.claim_mining_rewards()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_session RECORD;
  v_base_reward NUMERIC := 0.10;
  v_referral_bonus_rate NUMERIC := 0.10;
  v_max_bonus_rate NUMERIC := 1.00;
  v_active_referrals INTEGER;
  v_total_reward NUMERIC;
  v_bonus_reward NUMERIC;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT * INTO v_session
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true
  ORDER BY expires_at DESC
  LIMIT 1;

  IF v_session IS NULL THEN
    RETURN jsonb_build_object('error', 'No active or completed mining session found');
  END IF;

  IF EXISTS (SELECT 1 FROM public.mining_rewards WHERE session_id = v_session.id AND reward_type = 'base') THEN
     UPDATE public.mining_sessions SET is_active = false WHERE id = v_session.id;
     RETURN jsonb_build_object('error', 'Reward already claimed for this session');
  END IF;

  IF v_session.expires_at > now() THEN
     RETURN jsonb_build_object('error', 'Mining still in progress. Come back after 24 hours.');
  END IF;

  SELECT COUNT(DISTINCT r.referred_user_id) INTO v_active_referrals
  FROM public.referral_rewards r
  JOIN public.mining_sessions ms ON ms.user_id = r.referred_user_id
  WHERE r.referrer_user_id = v_user_id
    AND ms.is_active = true
    AND ms.expires_at > now();

  v_bonus_reward := LEAST(v_base_reward * v_active_referrals * v_referral_bonus_rate, v_base_reward * v_max_bonus_rate);
  v_total_reward := v_base_reward + v_bonus_reward;

  INSERT INTO public.mining_rewards (user_id, session_id, amount, reward_type)
  VALUES (v_user_id, v_session.id, v_base_reward, 'base');

  IF v_bonus_reward > 0 THEN
    INSERT INTO public.mining_rewards (user_id, session_id, amount, reward_type)
    VALUES (v_user_id, v_session.id, v_bonus_reward, 'referral_bonus');
  END IF;

  UPDATE public.wallets SET balance = balance + v_total_reward, updated_at = now() WHERE user_id = v_user_id;

  UPDATE public.mining_sessions SET is_active = false WHERE id = v_session.id;

  RETURN jsonb_build_object(
    'success', true,
    'base_reward', v_base_reward,
    'bonus_reward', v_bonus_reward,
    'total_reward', v_total_reward,
    'active_referrals', v_active_referrals
  );
END;
$$;

-- Function: sync_mining_state (deactivates expired sessions)
CREATE OR REPLACE FUNCTION public.sync_mining_state()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- No-op for now; sessions are managed via start/claim functions
  -- This exists so client calls don't error out
  RETURN;
END;
$$;

-- Function: withdraw_mining_earnings
CREATE OR REPLACE FUNCTION public.withdraw_mining_earnings(p_min_payout NUMERIC DEFAULT 5)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_total NUMERIC;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT COALESCE(SUM(amount), 0) INTO v_total
  FROM public.mining_rewards
  WHERE user_id = v_user_id;

  IF v_total < p_min_payout THEN
    RETURN jsonb_build_object('error', 'Minimum payout not reached', 'total', v_total, 'min', p_min_payout);
  END IF;

  -- Mining rewards are already credited to wallet via claim_mining_rewards
  RETURN jsonb_build_object('success', true, 'total', v_total);
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.start_mining_session(TEXT, TEXT, BOOLEAN, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_mining_rewards() TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_mining_state() TO authenticated;
GRANT EXECUTE ON FUNCTION public.withdraw_mining_earnings(NUMERIC) TO authenticated;
