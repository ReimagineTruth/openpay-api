-- Complete merchant transfer functionality with dashboard visibility controls
-- This migration enhances the existing transfer to merchant wallet feature

-- Add missing transfer_type column to merchant_balance_transfers if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'merchant_balance_transfers' 
    AND column_name = 'transfer_type'
  ) THEN
    ALTER TABLE public.merchant_balance_transfers 
    ADD COLUMN transfer_type TEXT NOT NULL DEFAULT 'transfer_in' 
    CHECK (transfer_type IN ('transfer_in', 'transfer_out', 'wallet_to_savings', 'savings_to_wallet'));
  END IF;
END $$;

-- Create user preferences table for dashboard feature visibility
CREATE TABLE IF NOT EXISTS public.user_dashboard_preferences (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  show_merchant_transfer_feature BOOLEAN NOT NULL DEFAULT true,
  show_merchant_balance_details BOOLEAN NOT NULL DEFAULT true,
  show_merchant_activity_feed BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.user_dashboard_preferences ENABLE ROW LEVEL SECURITY;

-- RLS policies for user_dashboard_preferences
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' 
    AND tablename = 'user_dashboard_preferences' 
    AND policyname = 'Users can view own dashboard preferences'
  ) THEN
    CREATE POLICY "Users can view own dashboard preferences"
      ON public.user_dashboard_preferences
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' 
    AND tablename = 'user_dashboard_preferences' 
    AND policyname = 'Users can insert own dashboard preferences'
  ) THEN
    CREATE POLICY "Users can insert own dashboard preferences"
      ON public.user_dashboard_preferences
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' 
    AND tablename = 'user_dashboard_preferences' 
    AND policyname = 'Users can update own dashboard preferences'
  ) THEN
    CREATE POLICY "Users can update own dashboard preferences"
      ON public.user_dashboard_preferences
      FOR UPDATE TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

-- Create trigger for updated_at
DROP TRIGGER IF EXISTS trg_user_dashboard_preferences_updated_at ON public.user_dashboard_preferences;
CREATE TRIGGER trg_user_dashboard_preferences_updated_at
BEFORE UPDATE ON public.user_dashboard_preferences
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

-- Enhanced RPC function for personal to merchant transfer
CREATE OR REPLACE FUNCTION public.transfer_my_personal_wallet_to_merchant(
  p_amount NUMERIC,
  p_mode TEXT DEFAULT 'live',
  p_note TEXT DEFAULT ''
)
RETURNS TABLE (
  transfer_id UUID,
  personal_wallet_balance NUMERIC,
  merchant_available_balance NUMERIC,
  transfer_type TEXT,
  status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, 'live')));
  v_amount NUMERIC(12,2) := ROUND(COALESCE(p_amount, 0)::NUMERIC, 2);
  v_personal_wallet_balance NUMERIC(12,2);
  v_merchant_available NUMERIC(12,2);
  v_transfer_id UUID;
  v_gross NUMERIC(14,2) := 0;
  v_refunded NUMERIC(14,2) := 0;
  v_transferred NUMERIC(14,2) := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  -- Lock the user's personal wallet
  SELECT balance INTO v_personal_wallet_balance
  FROM public.wallets
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_personal_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'Personal wallet not found';
  END IF;

  IF v_personal_wallet_balance < v_amount THEN
    RAISE EXCEPTION 'Insufficient personal wallet balance';
  END IF;

  -- Calculate current merchant available balance
  SELECT
    COALESCE(SUM(CASE WHEN mp.status = 'succeeded' THEN ROUND(mp.amount / COALESCE(NULLIF(sc.usd_rate, 0), 1), 2) ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN mp.status = 'refunded' THEN ROUND(mp.amount / COALESCE(NULLIF(sc.usd_rate, 0), 1), 2) ELSE 0 END), 0)
  INTO v_gross, v_refunded
  FROM public.merchant_payments mp
  LEFT JOIN public.supported_currencies sc
    ON sc.iso_code = UPPER(COALESCE(mp.currency, 'USD'))
  WHERE mp.merchant_user_id = v_user_id
    AND mp.key_mode = v_mode;

  SELECT COALESCE(SUM(mbt.amount), 0)
  INTO v_transferred
  FROM public.merchant_balance_transfers mbt
  WHERE mbt.merchant_user_id = v_user_id
    AND mbt.key_mode = v_mode;

  v_merchant_available := v_gross - v_refunded - v_transferred;

  -- Deduct from personal wallet
  UPDATE public.wallets
  SET balance = v_personal_wallet_balance - v_amount,
      updated_at = NOW()
  WHERE user_id = v_user_id;

  -- Add to merchant balance transfers
  v_transfer_id := gen_random_uuid();

  INSERT INTO public.merchant_balance_transfers (
    id,
    merchant_user_id,
    key_mode,
    destination,
    amount,
    currency,
    transfer_type,
    note,
    created_at
  ) VALUES (
    v_transfer_id,
    v_user_id,
    v_mode,
    'wallet',
    v_amount,
    'USD',
    'transfer_in',
    COALESCE(p_note, 'Transfer from personal wallet'),
    NOW()
  );

  -- Create activity record
  INSERT INTO public.merchant_activity (
    id,
    merchant_user_id,
    activity_type,
    amount,
    currency,
    status,
    note,
    source,
    created_at
  ) VALUES (
    gen_random_uuid(),
    v_user_id,
    'transfer_from_personal_wallet',
    v_amount,
    'OUSD',
    'completed',
    COALESCE(p_note, 'Transfer from personal wallet'),
    'Dashboard',
    NOW()
  );

  -- Return updated balances
  SELECT 
    v_transfer_id,
    v_personal_wallet_balance - v_amount,
    v_merchant_available + v_amount,
    'transfer_in',
    'completed'
  INTO transfer_id, personal_wallet_balance, merchant_available_balance, transfer_type, status;

  RETURN NEXT;
END;
$$;

-- RPC function to get/update dashboard preferences
CREATE OR REPLACE FUNCTION public.get_my_dashboard_preferences()
RETURNS TABLE (
  show_merchant_transfer_feature BOOLEAN,
  show_merchant_balance_details BOOLEAN,
  show_merchant_activity_feed BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_prefs public.user_dashboard_preferences;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Insert default preferences if they don't exist
  INSERT INTO public.user_dashboard_preferences (user_id)
  VALUES (v_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT * INTO v_prefs
  FROM public.user_dashboard_preferences
  WHERE user_id = v_user_id;

  RETURN QUERY
  SELECT 
    v_prefs.show_merchant_transfer_feature,
    v_prefs.show_merchant_balance_details,
    v_prefs.show_merchant_activity_feed;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_my_dashboard_preferences(
  p_show_merchant_transfer_feature BOOLEAN DEFAULT NULL,
  p_show_merchant_balance_details BOOLEAN DEFAULT NULL,
  p_show_merchant_activity_feed BOOLEAN DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  UPDATE public.user_dashboard_preferences
  SET 
    show_merchant_transfer_feature = COALESCE(p_show_merchant_transfer_feature, show_merchant_transfer_feature),
    show_merchant_balance_details = COALESCE(p_show_merchant_balance_details, show_merchant_balance_details),
    show_merchant_activity_feed = COALESCE(p_show_merchant_activity_feed, show_merchant_activity_feed),
    updated_at = NOW()
  WHERE user_id = v_user_id;

  RETURN FOUND;
END;
$$;

-- RPC function to get merchant transfer history
CREATE OR REPLACE FUNCTION public.get_my_merchant_transfer_history(
  p_mode TEXT DEFAULT 'live',
  p_limit INTEGER DEFAULT 50
)
RETURNS TABLE (
  transfer_id UUID,
  transfer_type TEXT,
  destination TEXT,
  amount NUMERIC,
  currency TEXT,
  note TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, 'live')));
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  RETURN QUERY
  SELECT 
    mbt.id,
    mbt.transfer_type,
    mbt.destination,
    mbt.amount,
    mbt.currency,
    mbt.note,
    mbt.created_at
  FROM public.merchant_balance_transfers mbt
  WHERE mbt.merchant_user_id = v_user_id
    AND mbt.key_mode = v_mode
  ORDER BY mbt.created_at DESC
  LIMIT GREATEST(1, LEAST(p_limit, 100));
END;
$$;

-- Grant permissions
REVOKE ALL ON FUNCTION public.transfer_my_personal_wallet_to_merchant(NUMERIC, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transfer_my_personal_wallet_to_merchant(NUMERIC, TEXT, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_my_dashboard_preferences() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_dashboard_preferences() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.update_my_dashboard_preferences(BOOLEAN, BOOLEAN, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_my_dashboard_preferences(BOOLEAN, BOOLEAN, BOOLEAN) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_my_merchant_transfer_history(TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_merchant_transfer_history(TEXT, INTEGER) TO authenticated, service_role;

-- Initialize dashboard preferences for existing users
INSERT INTO public.user_dashboard_preferences (user_id)
SELECT id FROM auth.users
WHERE NOT EXISTS (
  SELECT 1 FROM public.user_dashboard_preferences 
  WHERE user_dashboard_preferences.user_id = auth.users.id
);
