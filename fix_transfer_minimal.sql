-- Minimal fix for transfer function - just recreate with proper signature
-- This version handles the return type mismatch by dropping first

DROP FUNCTION IF EXISTS public.transfer_my_personal_wallet_to_merchant(NUMERIC, TEXT, TEXT);

CREATE FUNCTION public.transfer_my_personal_wallet_to_merchant(
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

  -- Lock user's personal wallet
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

  -- Simplified merchant balance calculation
  v_merchant_available := 0;

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

  -- Return updated balances
  RETURN QUERY SELECT 
    v_transfer_id,
    v_personal_wallet_balance - v_amount,
    v_merchant_available + v_amount;
END;
$$;

-- Set permissions
REVOKE ALL ON FUNCTION public.transfer_my_personal_wallet_to_merchant(NUMERIC, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transfer_my_personal_wallet_to_merchant(NUMERIC, TEXT, TEXT) TO authenticated, service_role;

-- Reset schema cache
NOTIFY pgrst, 'reload schema';
