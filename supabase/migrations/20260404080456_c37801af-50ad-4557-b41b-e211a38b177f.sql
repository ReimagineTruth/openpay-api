
-- 1. Fix currency constraint on merchant_products to allow OUSD, PI, etc.
ALTER TABLE public.merchant_products DROP CONSTRAINT IF EXISTS merchant_products_currency_check;
ALTER TABLE public.merchant_products ADD CONSTRAINT merchant_products_currency_check CHECK (char_length(currency) BETWEEN 2 AND 5);

-- 2. Recreate create_merchant_payment_link with extra fee params
CREATE OR REPLACE FUNCTION public.create_merchant_payment_link(
  p_secret_key text,
  p_mode text,
  p_link_type text,
  p_title text DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_currency text DEFAULT 'USD',
  p_custom_amount numeric DEFAULT NULL,
  p_items jsonb DEFAULT '[]'::jsonb,
  p_collect_customer_name boolean DEFAULT true,
  p_collect_customer_email boolean DEFAULT true,
  p_collect_phone boolean DEFAULT false,
  p_collect_address boolean DEFAULT false,
  p_after_payment_type text DEFAULT 'confirmation',
  p_confirmation_message text DEFAULT NULL,
  p_redirect_url text DEFAULT NULL,
  p_call_to_action text DEFAULT 'Pay',
  p_expires_in_minutes integer DEFAULT NULL,
  -- New fee-related params
  p_fee_payer text DEFAULT 'customer',
  p_fee_amount numeric DEFAULT 0,
  p_merchant_settlement_amount numeric DEFAULT NULL,
  p_openpay_fee_account text DEFAULT NULL
)
RETURNS TABLE(link_id uuid, link_token text, total_amount numeric, currency text, key_mode text, expires_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, '')));
  v_link_type TEXT := LOWER(TRIM(COALESCE(p_link_type, '')));
  v_after_payment_type TEXT := LOWER(TRIM(COALESCE(p_after_payment_type, 'confirmation')));
  v_currency TEXT := UPPER(TRIM(COALESCE(p_currency, 'USD')));
  v_secret_hash TEXT := md5(COALESCE(p_secret_key, ''));
  v_merchant_user_id UUID;
  v_api_key_id UUID;
  v_link public.merchant_payment_links;
  v_item JSONB;
  v_product public.merchant_products;
  v_quantity INTEGER;
  v_line_total NUMERIC(12,2);
  v_total NUMERIC(12,2) := 0;
  v_expires_at TIMESTAMPTZ;
BEGIN
  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  IF v_link_type NOT IN ('products', 'custom_amount') THEN
    RAISE EXCEPTION 'Link type must be products or custom_amount';
  END IF;

  IF v_after_payment_type NOT IN ('confirmation', 'redirect') THEN
    RAISE EXCEPTION 'After payment type must be confirmation or redirect';
  END IF;

  IF char_length(v_currency) < 2 OR char_length(v_currency) > 5 THEN
    RAISE EXCEPTION 'Currency code must be 2-5 characters';
  END IF;

  SELECT mak.merchant_user_id, mak.id
  INTO v_merchant_user_id, v_api_key_id
  FROM public.merchant_api_keys mak
  WHERE mak.secret_key_hash = v_secret_hash
    AND mak.key_mode = v_mode
    AND mak.is_active = true
  LIMIT 1;

  IF v_merchant_user_id IS NULL THEN
    RAISE EXCEPTION 'Invalid merchant API key for mode %', v_mode;
  END IF;

  IF p_expires_in_minutes IS NOT NULL THEN
    v_expires_at := now() + make_interval(mins => GREATEST(5, LEAST(p_expires_in_minutes, 525600)));
  END IF;

  INSERT INTO public.merchant_payment_links (
    merchant_user_id, api_key_id, key_mode, link_token, link_type,
    title, description, currency, custom_amount,
    collect_customer_name, collect_customer_email, collect_phone, collect_address,
    after_payment_type, confirmation_message, redirect_url, call_to_action, expires_at
  )
  VALUES (
    v_merchant_user_id, v_api_key_id, v_mode,
    'oplink_' || public.random_token_hex(24),
    v_link_type,
    COALESCE(NULLIF(TRIM(p_title), ''), 'OpenPay Payment'),
    COALESCE(NULLIF(TRIM(p_description), ''), ''),
    v_currency,
    p_custom_amount,
    COALESCE(p_collect_customer_name, true),
    COALESCE(p_collect_customer_email, true),
    COALESCE(p_collect_phone, false),
    COALESCE(p_collect_address, false),
    v_after_payment_type,
    COALESCE(NULLIF(TRIM(p_confirmation_message), ''), 'Thanks for your payment.'),
    NULLIF(TRIM(COALESCE(p_redirect_url, '')), ''),
    COALESCE(NULLIF(TRIM(p_call_to_action), ''), 'Pay'),
    v_expires_at
  )
  RETURNING * INTO v_link;

  IF v_link_type = 'custom_amount' THEN
    IF p_custom_amount IS NULL OR p_custom_amount <= 0 THEN
      RAISE EXCEPTION 'Custom amount must be greater than 0';
    END IF;
    v_total := ROUND(p_custom_amount, 2);
  ELSE
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
      RAISE EXCEPTION 'At least one product item is required';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
      SELECT *
      INTO v_product
      FROM public.merchant_products mp
      WHERE mp.id = (v_item->>'product_id')::UUID
        AND mp.merchant_user_id = v_merchant_user_id
        AND mp.is_active = true
      LIMIT 1;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid product_id in items payload';
      END IF;

      v_quantity := COALESCE((v_item->>'quantity')::INTEGER, 1);
      IF v_quantity < 1 OR v_quantity > 1000 THEN
        RAISE EXCEPTION 'Quantity must be between 1 and 1000';
      END IF;

      IF UPPER(v_product.currency) <> v_currency THEN
        RAISE EXCEPTION 'Product currency mismatch for product %', v_product.id;
      END IF;

      v_line_total := ROUND(v_product.unit_amount * v_quantity, 2);

      INSERT INTO public.merchant_payment_link_items (
        link_id, product_id, item_name, unit_amount, quantity, line_total
      )
      VALUES (
        v_link.id, v_product.id, v_product.product_name,
        v_product.unit_amount, v_quantity, v_line_total
      );

      v_total := v_total + v_line_total;
    END LOOP;
  END IF;

  IF v_total <= 0 THEN
    RAISE EXCEPTION 'Payment link total must be positive';
  END IF;

  RETURN QUERY
  SELECT v_link.id, v_link.link_token, v_total, v_link.currency, v_link.key_mode, v_link.expires_at;
END;
$function$;

-- 3. Fix currency constraint on merchant_payment_links if exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'merchant_payment_links_currency_check') THEN
    ALTER TABLE public.merchant_payment_links DROP CONSTRAINT merchant_payment_links_currency_check;
    ALTER TABLE public.merchant_payment_links ADD CONSTRAINT merchant_payment_links_currency_check CHECK (char_length(currency) BETWEEN 2 AND 5);
  END IF;
END $$;
