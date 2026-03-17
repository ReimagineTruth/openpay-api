-- 20260317220000_add_mining_ad_tracking.sql
-- Add ad tracking support for mining sessions to track multiple ads requirement

-- Add ad tracking columns to mining_sessions table
ALTER TABLE public.mining_sessions
  ADD COLUMN IF NOT EXISTS ads_watched INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS required_ads INTEGER DEFAULT 2,
  ADD COLUMN IF NOT EXISTS ad_progress_updated_at TIMESTAMPTZ;

-- Create a separate table to track individual ad completions
CREATE TABLE IF NOT EXISTS public.mining_ad_completions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id UUID REFERENCES public.mining_sessions(id) ON DELETE SET NULL,
  ad_id TEXT NOT NULL,
  ad_provider TEXT DEFAULT 'pi_network',
  completed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  verified_at TIMESTAMPTZ,
  is_verified BOOLEAN NOT NULL DEFAULT false,
  verification_data JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Add indexes for ad tracking
CREATE INDEX IF NOT EXISTS idx_mining_ad_completions_user ON public.mining_ad_completions(user_id);
CREATE INDEX IF NOT EXISTS idx_mining_ad_completions_session ON public.mining_ad_completions(session_id);
CREATE INDEX IF NOT EXISTS idx_mining_ad_completions_completed_at ON public.mining_ad_completions(completed_at);
CREATE INDEX IF NOT EXISTS idx_mining_ad_completions_verified ON public.mining_ad_completions(is_verified) WHERE is_verified = true;

-- Update the start_mining_session function to handle ad progress
CREATE OR REPLACE FUNCTION public.start_mining_session(
  p_device_fingerprint TEXT,
  p_ip_address TEXT,
  p_ad_verified BOOLEAN DEFAULT false,
  p_pi_browser_used BOOLEAN DEFAULT false,
  p_ads_watched INTEGER DEFAULT 0,
  p_required_ads INTEGER DEFAULT 2
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_pi_uid TEXT;
  v_active_session_id UUID;
  v_claimable_session_id UUID;
  v_expires_at TIMESTAMPTZ := now() + INTERVAL '24 hours';
  v_stale_sessions INTEGER := 0;
  v_ads_completed INTEGER := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized' USING ERRCODE = '42501';
  END IF;

  SELECT NULLIF(BTRIM(u.raw_user_meta_data->>'pi_uid'), '')
  INTO v_pi_uid
  FROM auth.users u
  WHERE u.id = v_user_id;

  IF v_pi_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Pi authentication required. Sign in with Pi Auth in Pi Browser.');
  END IF;

  IF COALESCE(p_pi_browser_used, false) IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Pi Browser is required to start mining.');
  END IF;

  -- Check ad progress requirement
  IF COALESCE(p_ads_watched, 0) < COALESCE(p_required_ads, 2) THEN
    RETURN jsonb_build_object(
      'error', 'More ads required to start mining',
      'ads_watched', COALESCE(p_ads_watched, 0),
      'required_ads', COALESCE(p_required_ads, 2),
      'remaining_ads', COALESCE(p_required_ads, 2) - COALESCE(p_ads_watched, 0)
    );
  END IF;

  SELECT id INTO v_active_session_id
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true AND expires_at > now();

  IF v_active_session_id IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Mining session already active', 'session_id', v_active_session_id);
  END IF;

  SELECT id INTO v_claimable_session_id
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true AND expires_at <= now()
  ORDER BY expires_at DESC
  LIMIT 1;

  IF v_claimable_session_id IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Mining session complete. Claim rewards before starting again.', 'session_id', v_claimable_session_id);
  END IF;

  -- Count verified ads for this user in the last hour
  SELECT COUNT(*) INTO v_ads_completed
  FROM public.mining_ad_completions
  WHERE user_id = v_user_id 
    AND is_verified = true 
    AND completed_at > now() - INTERVAL '1 hour';

  -- Double-check ad requirement with database verification
  IF v_ads_completed < COALESCE(p_required_ads, 2) THEN
    RETURN jsonb_build_object(
      'error', 'Ad verification incomplete. Please complete all required ads.',
      'verified_ads', v_ads_completed,
      'required_ads', COALESCE(p_required_ads, 2)
    );
  END IF;

  UPDATE public.mining_sessions
  SET is_active = false, last_sync_at = now()
  WHERE user_id = v_user_id AND is_active = true;

  GET DIAGNOSTICS v_stale_sessions = ROW_COUNT;

  INSERT INTO public.mining_sessions (
    user_id,
    expires_at,
    device_fingerprint,
    ip_address,
    ad_verified,
    pi_browser_used,
    ads_watched,
    required_ads,
    ad_progress_updated_at,
    last_sync_at
  )
  VALUES (
    v_user_id,
    v_expires_at,
    p_device_fingerprint,
    p_ip_address,
    true,
    true,
    p_ads_watched,
    p_required_ads,
    now(),
    now()
  )
  RETURNING id INTO v_active_session_id;

  RETURN jsonb_build_object(
    'success', true,
    'session_id', v_active_session_id,
    'expires_at', v_expires_at,
    'ad_verified', true,
    'pi_browser_used', true,
    'ads_watched', p_ads_watched,
    'required_ads', p_required_ads,
    'verified_ads', v_ads_completed,
    'stale_sessions_deactivated', v_stale_sessions
  );
END;
$$;

-- Function to record ad completion
CREATE OR REPLACE FUNCTION public.record_mining_ad_completion(
  p_ad_id TEXT,
  p_ad_provider TEXT DEFAULT 'pi_network',
  p_verification_data JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_completion_id UUID;
  v_total_ads INTEGER := 0;
  v_required_ads INTEGER := 2;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized' USING ERRCODE = '42501';
  END IF;

  -- Record the ad completion
  INSERT INTO public.mining_ad_completions (
    user_id,
    ad_id,
    ad_provider,
    verification_data,
    verified_at
  )
  VALUES (
    v_user_id,
    p_ad_id,
    p_ad_provider,
    p_verification_data,
    now()
  )
  RETURNING id INTO v_completion_id;

  -- Count verified ads for this user in the last hour
  SELECT COUNT(*) INTO v_total_ads
  FROM public.mining_ad_completions
  WHERE user_id = v_user_id 
    AND is_verified = true 
    AND completed_at > now() - INTERVAL '1 hour';

  RETURN jsonb_build_object(
    'success', true,
    'completion_id', v_completion_id,
    'ads_completed', v_total_ads,
    'required_ads', v_required_ads,
    'remaining_ads', GREATEST(0, v_required_ads - v_total_ads),
    'can_start_mining', v_total_ads >= v_required_ads
  );
END;
$$;

-- Function to get user's ad progress
CREATE OR REPLACE FUNCTION public.get_mining_ad_progress()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_total_ads INTEGER := 0;
  v_required_ads INTEGER := 2;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized' USING ERRCODE = '42501';
  END IF;

  -- Count verified ads for this user in the last hour
  SELECT COUNT(*) INTO v_total_ads
  FROM public.mining_ad_completions
  WHERE user_id = v_user_id 
    AND is_verified = true 
    AND completed_at > now() - INTERVAL '1 hour';

  RETURN jsonb_build_object(
    'ads_completed', v_total_ads,
    'required_ads', v_required_ads,
    'remaining_ads', GREATEST(0, v_required_ads - v_total_ads),
    'progress_percentage', ROUND((v_total_ads::FLOAT / v_required_ads::FLOAT) * 100),
    'can_start_mining', v_total_ads >= v_required_ads
  );
END;
$$;

-- Update function permissions
REVOKE ALL ON FUNCTION public.start_mining_session(TEXT, TEXT, BOOLEAN, BOOLEAN, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.start_mining_session(TEXT, TEXT, BOOLEAN, BOOLEAN, INTEGER, INTEGER) TO authenticated;

REVOKE ALL ON FUNCTION public.record_mining_ad_completion(TEXT, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_mining_ad_completion(TEXT, TEXT, JSONB) TO authenticated;

REVOKE ALL ON FUNCTION public.get_mining_ad_progress() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_mining_ad_progress() TO authenticated;

REVOKE ALL ON TABLE public.mining_ad_completions FROM PUBLIC;
GRANT SELECT, INSERT ON TABLE public.mining_ad_completions TO authenticated;

NOTIFY pgrst, 'reload schema';
