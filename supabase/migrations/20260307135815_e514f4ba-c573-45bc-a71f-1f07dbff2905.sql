-- Create complete_account_onboarding RPC function
CREATE OR REPLACE FUNCTION public.complete_account_onboarding(
  p_full_name text,
  p_username text,
  p_profile_image_url text DEFAULT NULL,
  p_security_pin text DEFAULT NULL
)
RETURNS TABLE(success boolean, message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_existing_username uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT false, 'Not authenticated'::text;
    RETURN;
  END IF;

  IF length(trim(p_full_name)) < 1 THEN
    RETURN QUERY SELECT false, 'Full name is required'::text;
    RETURN;
  END IF;

  IF p_username !~ '^[a-z0-9_]{3,20}$' THEN
    RETURN QUERY SELECT false, 'Username must be 3-20 lowercase letters, numbers, or underscore'::text;
    RETURN;
  END IF;

  SELECT id INTO v_existing_username
  FROM profiles
  WHERE lower(username) = lower(p_username) AND id != v_user_id
  LIMIT 1;

  IF v_existing_username IS NOT NULL THEN
    RETURN QUERY SELECT false, 'Username is already taken'::text;
    RETURN;
  END IF;

  UPDATE profiles
  SET full_name = trim(p_full_name),
      username = p_username,
      avatar_url = COALESCE(p_profile_image_url, avatar_url)
  WHERE id = v_user_id;

  INSERT INTO user_preferences (user_id, onboarding_completed, onboarding_step, profile_full_name, profile_username)
  VALUES (v_user_id, true, 99, trim(p_full_name), p_username)
  ON CONFLICT (user_id) DO UPDATE
  SET onboarding_completed = true,
      onboarding_step = 99,
      profile_full_name = trim(p_full_name),
      profile_username = p_username,
      updated_at = now();

  INSERT INTO user_accounts (user_id, account_number, account_name, account_username)
  VALUES (
    v_user_id,
    'OPY-' || substr(replace(v_user_id::text, '-', ''), 1, 12),
    trim(p_full_name),
    p_username
  )
  ON CONFLICT (user_id) DO UPDATE
  SET account_name = trim(p_full_name),
      account_username = p_username,
      updated_at = now();

  RETURN QUERY SELECT true, 'Onboarding completed successfully'::text;
END;
$$;

CREATE OR REPLACE FUNCTION public.upload_profile_image(
  p_image_url text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE profiles
  SET avatar_url = p_image_url
  WHERE id = auth.uid();
END;
$$;