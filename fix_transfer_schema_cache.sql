-- Fix transfer function schema cache issue
-- Run this script directly in your Supabase SQL editor to fix the transfer function

-- First, drop the function completely to clear any cached references
DROP FUNCTION IF EXISTS public.transfer_my_personal_wallet_to_merchant(NUMERIC, TEXT, TEXT) CASCADE;

-- Recreate the function with explicit schema cache refresh
CREATE OR REPLACE FUNCTION public.transfer_my_personal_wallet_to_merchant(
  p_amount NUMERIC,
  p_mode TEXT DEFAULT 'live',
  p_note TEXT DEFAULT ''
)
RETURNS TABLE (
  transfer_id UUID,
  personal_wallet_balance NUMERIC,
  merchant_available_balance NUMERIC
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
    amount,
    transfer_type,
    note,
    created_at
  ) VALUES (
    v_transfer_id,
    v_user_id,
    v_mode,
    v_amount,
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
    v_merchant_available + v_amount
  INTO personal_wallet_balance, merchant_available_balance;

  RETURN NEXT;
END;
$$;

-- Grant permissions with explicit cache refresh
REVOKE ALL ON FUNCTION public.transfer_my_personal_wallet_to_merchant(NUMERIC, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transfer_my_personal_wallet_to_merchant(NUMERIC, TEXT, TEXT) TO authenticated, service_role;

-- Force schema cache refresh
NOTIFY pgrst, 'reload schema';

-- Add comment to help with debugging
COMMENT ON FUNCTION public.transfer_my_personal_wallet_to_merchant(NUMERIC, TEXT, TEXT) IS 'Transfer funds from personal wallet to merchant wallet. Fixed schema cache issue.';

-- Verify function exists
SELECT 
  proname as function_name,
  pg_get_function_arguments(oid) as arguments,
  pg_get_function_result(oid) as return_type
FROM pg_proc 
WHERE proname = 'transfer_my_personal_wallet_to_merchant' 
  AND pronamespace = 'public'::regnamespace;
