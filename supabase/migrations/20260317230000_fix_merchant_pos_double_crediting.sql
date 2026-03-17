-- 20260317230000_fix_merchant_pos_double_crediting.sql
-- Fix double crediting issue in POS payments where merchants receive funds in both personal and merchant wallets
-- Ensure only merchant wallet gets credited for POS payments

-- Drop existing function to recreate with fix
DROP FUNCTION IF EXISTS public.complete_merchant_checkout_with_transaction(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT);

-- Recreate function with proper wallet crediting logic
CREATE OR REPLACE FUNCTION public.complete_merchant_checkout_with_transaction(
  p_session_token TEXT,
  p_transaction_id UUID,
  p_note TEXT DEFAULT '',
  p_customer_name TEXT DEFAULT NULL,
  p_customer_email TEXT DEFAULT NULL,
  p_customer_phone TEXT DEFAULT NULL,
  p_customer_address TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buyer_user_id UUID := auth.uid();
  v_session public.merchant_checkout_sessions;
  v_tx public.transactions;
  v_existing_tx UUID;
  v_payment_link_id UUID;
  v_payment_link_token TEXT;
  v_customer_name TEXT := NULLIF(TRIM(COALESCE(p_customer_name, '')), '');
  v_customer_email TEXT := NULLIF(TRIM(COALESCE(p_customer_email, '')), '');
  v_customer_phone TEXT := NULLIF(TRIM(COALESCE(p_customer_phone, '')), '');
  v_customer_address TEXT := NULLIF(TRIM(COALESCE(p_customer_address, '')), '');
  v_merchant_wallet_balance NUMERIC(12,2);
BEGIN
  IF v_buyer_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_transaction_id IS NULL THEN
    RAISE EXCEPTION 'Transaction id is required';
  END IF;

  SELECT *
  INTO v_session
  FROM public.merchant_checkout_sessions mcs
  WHERE mcs.session_token = TRIM(COALESCE(p_session_token, ''))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Checkout session not found';
  END IF;

  IF v_session.status = 'paid' THEN
    SELECT mp.transaction_id
    INTO v_existing_tx
    FROM public.merchant_payments mp
    WHERE mp.session_id = v_session.id
    LIMIT 1;

    UPDATE public.merchant_checkout_sessions mcs
    SET customer_name = COALESCE(v_customer_name, mcs.customer_name),
        customer_email = COALESCE(v_customer_email, mcs.customer_email),
        metadata = COALESCE(mcs.metadata, '{}'::jsonb) || jsonb_strip_nulls(
          jsonb_build_object(
            'customer_phone', v_customer_phone,
            'customer_address', v_customer_address
          )
        ),
        updated_at = now()
    WHERE mcs.id = v_session.id;

    RETURN COALESCE(v_existing_tx, p_transaction_id);
  END IF;

  IF v_session.status <> 'open' THEN
    RAISE EXCEPTION 'Checkout session is not open';
  END IF;

  IF v_session.expires_at < now() THEN
    UPDATE public.merchant_checkout_sessions
    SET status = 'expired'
    WHERE id = v_session.id;
    RAISE EXCEPTION 'Checkout session expired';
  END IF;

  IF v_session.merchant_user_id = v_buyer_user_id THEN
    RAISE EXCEPTION 'Merchant cannot pay own checkout';
  END IF;

  SELECT *
  INTO v_tx
  FROM public.transactions t
  WHERE t.id = p_transaction_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transaction not found';
  END IF;

  IF v_tx.status <> 'completed' THEN
    RAISE EXCEPTION 'Transaction is not completed';
  END IF;

  IF v_tx.sender_id <> v_buyer_user_id THEN
    RAISE EXCEPTION 'Transaction sender does not match buyer';
  END IF;

  -- CRITICAL FIX: Ensure transaction receiver is ONLY the merchant, not both merchant and buyer
  IF v_tx.receiver_id <> v_session.merchant_user_id THEN
    RAISE EXCEPTION 'Transaction receiver does not match merchant';
  END IF;

  IF ABS(COALESCE(v_tx.amount, 0) - COALESCE(v_session.total_amount, 0)) > 0.02 THEN
    RAISE EXCEPTION 'Transaction amount does not match checkout amount';
  END IF;

  v_payment_link_id := NULLIF((v_session.metadata->>'payment_link_id')::UUID, NULL);
  v_payment_link_token := NULLIF(TRIM(COALESCE(v_session.metadata->>'payment_link_token', '')), '');

  -- Insert merchant payment record
  INSERT INTO public.merchant_payments (
    session_id,
    merchant_user_id,
    buyer_user_id,
    transaction_id,
    amount,
    currency,
    api_key_id,
    key_mode,
    payment_link_id,
    payment_link_token,
    status
  )
  VALUES (
    v_session.id,
    v_session.merchant_user_id,
    v_buyer_user_id,
    v_tx.id,
    v_session.total_amount,
    v_session.currency,
    v_session.api_key_id,
    v_session.key_mode,
    v_payment_link_id,
    v_payment_link_token,
    'succeeded'
  )
  ON CONFLICT (session_id) DO NOTHING;

  -- CRITICAL FIX: Credit ONLY the merchant's wallet, not both wallets
  -- Get merchant's current wallet balance
  SELECT balance INTO v_merchant_wallet_balance
  FROM public.wallets
  WHERE user_id = v_session.merchant_user_id
  FOR UPDATE;

  IF v_merchant_wallet_balance IS NULL THEN
    -- Create merchant wallet if it doesn't exist
    INSERT INTO public.wallets (user_id, balance, updated_at)
    VALUES (v_session.merchant_user_id, 0, now());
    
    -- Get the newly created balance
    SELECT balance INTO v_merchant_wallet_balance
    FROM public.wallets
    WHERE user_id = v_session.merchant_user_id
    FOR UPDATE;
  END IF;

  -- Credit ONLY the merchant's wallet with the payment amount
  UPDATE public.wallets
  SET balance = balance + v_session.total_amount,
      updated_at = now()
  WHERE user_id = v_session.merchant_user_id;

  -- Update checkout session as paid
  UPDATE public.merchant_checkout_sessions mcs
  SET status = 'paid',
      paid_at = now(),
      customer_name = COALESCE(v_customer_name, mcs.customer_name),
      customer_email = COALESCE(v_customer_email, mcs.customer_email),
      metadata = COALESCE(mcs.metadata, '{}'::jsonb) || jsonb_strip_nulls(
        jsonb_build_object(
          'customer_phone', v_customer_phone,
          'customer_address', v_customer_address
        )
      ),
      updated_at = now()
    WHERE mcs.id = v_session.id;

  IF COALESCE(TRIM(p_note), '') <> '' THEN
    UPDATE public.transactions
    SET note = CONCAT(COALESCE(note, ''), ' | ', TRIM(p_note))
    WHERE id = v_tx.id;
  END IF;

  RETURN v_tx.id;
END;
$$;

-- Update function permissions
REVOKE ALL ON FUNCTION public.complete_merchant_checkout_with_transaction(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_merchant_checkout_with_transaction(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
