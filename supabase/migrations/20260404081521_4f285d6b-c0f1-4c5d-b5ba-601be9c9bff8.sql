
-- 1. Drop the OLD ambiguous function (without fee params - 17 args)
DROP FUNCTION IF EXISTS public.create_merchant_payment_link(text, text, text, text, text, text, numeric, jsonb, boolean, boolean, boolean, boolean, text, text, text, text, integer);

-- 2. Fix double-credit bug in pay_merchant_checkout_with_wallet
-- Previously it credited BOTH merchant AND openpay with full amount (double credit!)
-- Fix: merchant gets (amount - fee), openpay gets fee only
CREATE OR REPLACE FUNCTION public.pay_merchant_checkout_with_wallet(
  p_session_token text,
  p_note text DEFAULT '',
  p_customer_name text DEFAULT NULL,
  p_customer_email text DEFAULT NULL,
  p_customer_phone text DEFAULT NULL,
  p_customer_address text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_buyer_user_id UUID := auth.uid();
  v_openpay_user_id UUID;
  v_session public.merchant_checkout_sessions;
  v_existing_tx UUID;
  v_tx_id UUID;
  v_sender_balance NUMERIC(12,2);
  v_merchant_balance NUMERIC(12,2);
  v_openpay_balance NUMERIC(12,2);
  v_currency_rate NUMERIC(20,8) := 1;
  v_wallet_amount NUMERIC(12,2) := 0;
  v_fee_amount NUMERIC(12,2) := 0;
  v_merchant_credit NUMERIC(12,2) := 0;
  v_customer_name TEXT := NULLIF(TRIM(COALESCE(p_customer_name, '')), '');
  v_customer_email TEXT := NULLIF(TRIM(COALESCE(p_customer_email, '')), '');
  v_customer_phone TEXT := NULLIF(TRIM(COALESCE(p_customer_phone, '')), '');
  v_customer_address TEXT := NULLIF(TRIM(COALESCE(p_customer_address, '')), '');
  v_buyer_email TEXT;
  v_payment_link_id UUID;
  v_payment_link_token TEXT;
BEGIN
  IF v_buyer_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT email INTO v_buyer_email
  FROM auth.users
  WHERE id = v_buyer_user_id;

  v_openpay_user_id := public.get_openpay_settlement_user_id();

  SELECT *
  INTO v_session
  FROM public.merchant_checkout_sessions mcs
  WHERE mcs.session_token = TRIM(COALESCE(p_session_token, ''))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Checkout session not found';
  END IF;

  -- Idempotency: if already paid, return existing tx
  IF v_session.status = 'paid' THEN
    SELECT mp.transaction_id
    INTO v_existing_tx
    FROM public.merchant_payments mp
    WHERE mp.session_id = v_session.id
    LIMIT 1;
    RETURN v_existing_tx;
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

  -- Convert from session currency to wallet (USD-based)
  SELECT sc.usd_rate
  INTO v_currency_rate
  FROM public.supported_currencies sc
  WHERE sc.iso_code = UPPER(COALESCE(v_session.currency, 'USD'))
    AND sc.is_active = true
  LIMIT 1;

  v_currency_rate := COALESCE(NULLIF(v_currency_rate, 0), 1);
  v_wallet_amount := ROUND(COALESCE(v_session.total_amount, 0) / v_currency_rate, 2);

  IF v_wallet_amount <= 0 THEN
    RAISE EXCEPTION 'Checkout amount must be greater than zero';
  END IF;

  -- Calculate fee split: fee goes to OpenPay, remainder to merchant
  v_fee_amount := ROUND(COALESCE(v_session.fee_amount, 0) / v_currency_rate, 2);
  IF v_fee_amount < 0 THEN v_fee_amount := 0; END IF;
  IF v_fee_amount > v_wallet_amount THEN v_fee_amount := v_wallet_amount; END IF;
  v_merchant_credit := v_wallet_amount - v_fee_amount;

  -- Lock wallets
  SELECT balance INTO v_sender_balance
  FROM public.wallets WHERE user_id = v_buyer_user_id FOR UPDATE;
  IF v_sender_balance IS NULL THEN RAISE EXCEPTION 'Buyer wallet not found'; END IF;

  SELECT balance INTO v_merchant_balance
  FROM public.wallets WHERE user_id = v_session.merchant_user_id FOR UPDATE;
  IF v_merchant_balance IS NULL THEN RAISE EXCEPTION 'Merchant wallet not found'; END IF;

  SELECT balance INTO v_openpay_balance
  FROM public.wallets WHERE user_id = v_openpay_user_id FOR UPDATE;
  IF v_openpay_balance IS NULL THEN RAISE EXCEPTION 'OpenPay settlement wallet not found'; END IF;

  IF v_sender_balance < v_wallet_amount THEN
    RAISE EXCEPTION 'Insufficient balance';
  END IF;

  -- Debit buyer the full amount
  UPDATE public.wallets
  SET balance = v_sender_balance - v_wallet_amount, updated_at = now()
  WHERE user_id = v_buyer_user_id;

  -- Credit merchant ONLY (amount - fee)
  UPDATE public.wallets
  SET balance = v_merchant_balance + v_merchant_credit, updated_at = now()
  WHERE user_id = v_session.merchant_user_id;

  -- Credit OpenPay ONLY the fee
  IF v_fee_amount > 0 THEN
    UPDATE public.wallets
    SET balance = v_openpay_balance + v_fee_amount, updated_at = now()
    WHERE user_id = v_openpay_user_id;
  END IF;

  -- Create transaction record
  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_buyer_user_id,
    v_session.merchant_user_id,
    v_wallet_amount,
    CONCAT(
      'Merchant checkout ', v_session.session_token,
      CASE WHEN COALESCE(TRIM(p_note), '') <> '' THEN CONCAT(' | ', TRIM(p_note)) ELSE '' END
    ),
    'completed'
  )
  RETURNING id INTO v_tx_id;

  -- Record payment link reference if present
  v_payment_link_id := NULLIF((v_session.metadata->>'payment_link_id')::TEXT, '')::UUID;
  v_payment_link_token := NULLIF(TRIM(COALESCE(v_session.metadata->>'payment_link_token', '')), '');

  -- Record merchant payment
  INSERT INTO public.merchant_payments (
    session_id, merchant_user_id, buyer_user_id, transaction_id,
    amount, currency, api_key_id, key_mode,
    payment_link_id, payment_link_token, status
  )
  VALUES (
    v_session.id, v_session.merchant_user_id, v_buyer_user_id, v_tx_id,
    v_session.total_amount, v_session.currency, v_session.api_key_id,
    v_session.key_mode, v_payment_link_id, v_payment_link_token, 'succeeded'
  )
  ON CONFLICT (session_id) DO NOTHING;

  -- Mark session paid
  UPDATE public.merchant_checkout_sessions
  SET status = 'paid',
      paid_at = now(),
      customer_name = COALESCE(v_customer_name, customer_name),
      customer_email = COALESCE(v_customer_email, customer_email)
  WHERE id = v_session.id;

  -- Ledger events
  INSERT INTO public.ledger_events (source_table, source_id, event_type, actor_user_id, related_user_id, amount, status, note, payload)
  VALUES
    ('transactions', v_tx_id, 'merchant_checkout_debit', v_buyer_user_id, v_session.merchant_user_id, v_wallet_amount, 'completed',
     CONCAT('Checkout payment for session ', v_session.session_token),
     jsonb_build_object('session_id', v_session.id, 'currency', v_session.currency, 'fee', v_fee_amount)),
    ('transactions', v_tx_id, 'merchant_checkout_credit', v_session.merchant_user_id, v_buyer_user_id, v_merchant_credit, 'completed',
     CONCAT('Merchant credit for session ', v_session.session_token),
     jsonb_build_object('session_id', v_session.id, 'fee_deducted', v_fee_amount));

  -- Notifications
  INSERT INTO public.app_notifications (user_id, type, title, message, metadata)
  VALUES
    (v_session.merchant_user_id, 'merchant_payment', 'Payment received',
     CONCAT('You received ', v_merchant_credit, ' OUSD from checkout ', v_session.session_token),
     jsonb_build_object('transaction_id', v_tx_id, 'amount', v_merchant_credit)),
    (v_buyer_user_id, 'payment', 'Payment sent',
     CONCAT('You paid ', v_wallet_amount, ' OUSD for checkout ', v_session.session_token),
     jsonb_build_object('transaction_id', v_tx_id, 'amount', v_wallet_amount));

  RETURN v_tx_id;
END;
$function$;
