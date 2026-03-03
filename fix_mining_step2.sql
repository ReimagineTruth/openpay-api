-- Mining System Setup - Safe Version (Step 2)
-- Run this after Step 1 completes successfully

-- Create functions
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

CREATE OR REPLACE FUNCTION public.claim_mining_rewards()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
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
     UPDATE public.mining_sessions SET is_active = false WHERE id = v_session.id;
     RETURN jsonb_build_object('error', 'Reward already claimed for this session');
  END IF;

  -- Only allow claim if session has expired
  IF v_session.expires_at > now() THEN
     RETURN jsonb_build_object('error', 'Mining still in progress. Come back after 24 hours.');
  END IF;

  -- Calculate active referrals
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

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.start_mining_session(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_mining_rewards() TO authenticated;

SELECT 'Step 2 completed: Functions created successfully!' as status;
