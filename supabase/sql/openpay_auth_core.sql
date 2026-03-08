-- ============================================================
-- OpenPay Auth Core Schema (Signup / Signin / User Account)
-- Intended for Supabase Postgres (auth.users managed by Supabase).
-- Run this in the Supabase SQL Editor on a NEW project.
-- Re-runnable: uses IF NOT EXISTS / guarded policy creation.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------- Shared updated_at trigger ----------
CREATE OR REPLACE FUNCTION public.set_common_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- ---------- profiles ----------
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT NOT NULL DEFAULT '',
  username TEXT UNIQUE,
  avatar_url TEXT,
  referral_code TEXT,
  referred_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'profiles'
      AND policyname = 'Anyone authenticated can view profiles'
  ) THEN
    CREATE POLICY "Anyone authenticated can view profiles"
      ON public.profiles
      FOR SELECT TO authenticated
      USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'profiles'
      AND policyname = 'Users can update own profile'
  ) THEN
    CREATE POLICY "Users can update own profile"
      ON public.profiles
      FOR UPDATE TO authenticated
      USING (id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'profiles'
      AND policyname = 'Users can insert own profile'
  ) THEN
    CREATE POLICY "Users can insert own profile"
      ON public.profiles
      FOR INSERT TO authenticated
      WITH CHECK (id = auth.uid());
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_profiles_updated_at ON public.profiles;
CREATE TRIGGER trg_profiles_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_no_self_referral;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_no_self_referral
  CHECK (referred_by_user_id IS NULL OR referred_by_user_id <> id);

-- Case-insensitive uniqueness for referral_code
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_referral_code_unique
ON public.profiles (LOWER(referral_code))
WHERE referral_code IS NOT NULL;

-- ---------- wallets ----------
CREATE TABLE IF NOT EXISTS public.wallets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  balance NUMERIC(12,2) NOT NULL DEFAULT 0.00 CHECK (balance >= 0),
  welcome_bonus_claimed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'wallets'
      AND policyname = 'Users can view own wallet'
  ) THEN
    CREATE POLICY "Users can view own wallet"
      ON public.wallets
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'wallets'
      AND policyname = 'Users can update own wallet'
  ) THEN
    CREATE POLICY "Users can update own wallet"
      ON public.wallets
      FOR UPDATE TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

-- ---------- user_preferences (onboarding state) ----------
CREATE TABLE IF NOT EXISTS public.user_preferences (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  hide_balance BOOLEAN NOT NULL DEFAULT false,
  usage_agreement_accepted BOOLEAN NOT NULL DEFAULT false,
  onboarding_completed BOOLEAN NOT NULL DEFAULT false,
  onboarding_step INTEGER NOT NULL DEFAULT 0 CHECK (onboarding_step >= 0),
  reference_code TEXT NULL,
  profile_full_name TEXT NULL,
  profile_username TEXT NULL,
  security_settings JSONB NOT NULL DEFAULT '{}'::jsonb,
  merchant_onboarding_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  qr_print_settings JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_preferences'
      AND policyname = 'Users can view own preferences'
  ) THEN
    CREATE POLICY "Users can view own preferences"
      ON public.user_preferences
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_preferences'
      AND policyname = 'Users can insert own preferences'
  ) THEN
    CREATE POLICY "Users can insert own preferences"
      ON public.user_preferences
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_preferences'
      AND policyname = 'Users can update own preferences'
  ) THEN
    CREATE POLICY "Users can update own preferences"
      ON public.user_preferences
      FOR UPDATE TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_user_preferences_updated_at ON public.user_preferences;
CREATE TRIGGER trg_user_preferences_updated_at
BEFORE UPDATE ON public.user_preferences
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

-- ---------- user_accounts (OpenPay account identity used on dashboard) ----------
CREATE TABLE IF NOT EXISTS public.user_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  account_number TEXT NOT NULL UNIQUE,
  account_name TEXT NOT NULL DEFAULT '',
  account_username TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.user_accounts ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_accounts'
      AND policyname = 'Users can view own account'
  ) THEN
    CREATE POLICY "Users can view own account"
      ON public.user_accounts
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_accounts'
      AND policyname = 'Users can insert own account'
  ) THEN
    CREATE POLICY "Users can insert own account"
      ON public.user_accounts
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_accounts'
      AND policyname = 'Users can update own account'
  ) THEN
    CREATE POLICY "Users can update own account"
      ON public.user_accounts
      FOR UPDATE TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_user_accounts_updated_at ON public.user_accounts;
CREATE TRIGGER trg_user_accounts_updated_at
BEFORE UPDATE ON public.user_accounts
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

-- ---------- OpenPay account number helpers ----------
CREATE OR REPLACE FUNCTION public.generate_openpay_account_number(p_user_id UUID)
RETURNS TEXT
LANGUAGE sql
AS $$
  SELECT 'OP' || UPPER(REPLACE(p_user_id::TEXT, '-', ''));
$$;

CREATE OR REPLACE FUNCTION public.upsert_my_user_account()
RETURNS public.user_accounts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_profile_name TEXT;
  v_profile_username TEXT;
  v_account public.user_accounts;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT full_name, COALESCE(username, '')
  INTO v_profile_name, v_profile_username
  FROM public.profiles
  WHERE id = v_user_id;

  INSERT INTO public.user_accounts (user_id, account_number, account_name, account_username)
  VALUES (
    v_user_id,
    public.generate_openpay_account_number(v_user_id),
    COALESCE(NULLIF(TRIM(v_profile_name), ''), 'OpenPay User'),
    COALESCE(NULLIF(TRIM(v_profile_username), ''), 'openpay')
  )
  ON CONFLICT (user_id) DO UPDATE
  SET account_name = EXCLUDED.account_name,
      account_username = EXCLUDED.account_username
  RETURNING * INTO v_account;

  RETURN v_account;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_my_user_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_my_user_account() TO authenticated, service_role;

-- ---------- Signup trigger: create profile + wallet + preferences + account ----------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  requested_username TEXT;
  final_username TEXT;
  requested_referral_code TEXT;
  referred_by_id UUID;
  base_referral_code TEXT;
  final_referral_code TEXT;
  referral_suffix INTEGER := 0;
  desired_full_name TEXT;
BEGIN
  requested_username := NULLIF(BTRIM(NEW.raw_user_meta_data->>'username'), '');
  desired_full_name := COALESCE(NEW.raw_user_meta_data->>'full_name', '');

  IF requested_username IS NOT NULL THEN
    final_username := requested_username;
    IF EXISTS (SELECT 1 FROM public.profiles p WHERE p.username = final_username) THEN
      final_username := requested_username || '_' || REPLACE(SUBSTRING(NEW.id::text, 1, 8), '-', '');
    END IF;
  END IF;

  requested_referral_code := LOWER(NULLIF(BTRIM(NEW.raw_user_meta_data->>'referral_code'), ''));
  IF requested_referral_code IS NOT NULL THEN
    SELECT p.id
    INTO referred_by_id
    FROM public.profiles p
    WHERE LOWER(p.referral_code) = requested_referral_code
      AND p.id <> NEW.id
    LIMIT 1;
  END IF;

  base_referral_code := LOWER(
    REGEXP_REPLACE(
      COALESCE(NULLIF(BTRIM(final_username), ''), 'user_' || REPLACE(SUBSTRING(NEW.id::text, 1, 8), '-', '')),
      '[^a-z0-9_]',
      '',
      'g'
    )
  );
  IF base_referral_code IS NULL OR base_referral_code = '' THEN
    base_referral_code := 'user_' || REPLACE(SUBSTRING(NEW.id::text, 1, 8), '-', '');
  END IF;

  final_referral_code := base_referral_code;
  WHILE EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE LOWER(p.referral_code) = final_referral_code
  ) LOOP
    referral_suffix := referral_suffix + 1;
    final_referral_code := base_referral_code || referral_suffix::text;
  END LOOP;

  INSERT INTO public.profiles (id, full_name, username, avatar_url, referral_code, referred_by_user_id)
  VALUES (
    NEW.id,
    desired_full_name,
    final_username,
    NULLIF(BTRIM(NEW.raw_user_meta_data->>'avatar_url'), ''),
    final_referral_code,
    referred_by_id
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.wallets (user_id, balance, welcome_bonus_claimed_at)
  VALUES (NEW.id, 1.00, now())
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.user_preferences (user_id, reference_code, profile_full_name, profile_username)
  VALUES (NEW.id, final_referral_code, desired_full_name, final_username)
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.user_accounts (user_id, account_number, account_name, account_username)
  VALUES (
    NEW.id,
    public.generate_openpay_account_number(NEW.id),
    COALESCE(NULLIF(BTRIM(desired_full_name), ''), 'OpenPay User'),
    COALESCE(NULLIF(BTRIM(final_username), ''), 'openpay_user_' || REPLACE(SUBSTRING(NEW.id::text, 1, 8), '-', ''))
  )
  ON CONFLICT (user_id) DO UPDATE
  SET account_name = EXCLUDED.account_name,
      account_username = EXCLUDED.account_username;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();

NOTIFY pgrst, 'reload schema';

