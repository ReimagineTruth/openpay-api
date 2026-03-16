-- Complete fix for create_merchant_payment_link function and schema cache
-- This script addresses the parameter mismatch causing the schema cache error

-- First, let's see what signature the function currently has
DO $$
DECLARE
    func_exists BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM information_schema.routines 
        WHERE routine_schema = 'public' 
        AND routine_name = 'create_merchant_payment_link'
    ) INTO func_exists;
    
    IF func_exists THEN
        RAISE NOTICE 'Dropping existing create_merchant_payment_link function to recreate with correct signature';
        DROP FUNCTION IF EXISTS public.create_merchant_payment_link(
            TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, JSONB, 
            BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, TEXT, TEXT, TEXT, TEXT, INTEGER
        );
        DROP FUNCTION IF EXISTS public.create_merchant_payment_link(
            TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, JSONB, 
            BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, TEXT, TEXT, TEXT, TEXT, INTEGER,
            NUMERIC, TEXT, NUMERIC, TEXT
        );
    END IF;
END $$;

-- Create the function with the exact signature the frontend expects
CREATE OR REPLACE FUNCTION public.create_merchant_payment_link(
  p_secret_key TEXT,
  p_mode TEXT,
  p_link_type TEXT,
  p_title TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_currency TEXT DEFAULT 'USD',
  p_custom_amount NUMERIC DEFAULT NULL,
  p_items JSONB DEFAULT '[]'::jsonb,
  p_collect_customer_name BOOLEAN DEFAULT true,
  p_collect_customer_email BOOLEAN DEFAULT true,
  p_collect_phone BOOLEAN DEFAULT false,
  p_collect_address BOOLEAN DEFAULT false,
  p_after_payment_type TEXT DEFAULT 'confirmation',
  p_confirmation_message TEXT DEFAULT NULL,
  p_redirect_url TEXT DEFAULT NULL,
  p_call_to_action TEXT DEFAULT 'Pay',
  p_expires_in_minutes INTEGER DEFAULT NULL,
  p_fee_payer TEXT DEFAULT NULL,
  p_fee_amount NUMERIC DEFAULT NULL,
  p_merchant_settlement_amount NUMERIC DEFAULT NULL,
  p_openpay_fee_account TEXT DEFAULT NULL
)
RETURNS TABLE (
  link_id UUID,
  link_token TEXT,
  total_amount NUMERIC,
  currency TEXT,
  key_mode TEXT,
  expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, '')));
  v_link_type TEXT := LOWER(TRIM(COALESCE(p_link_type, '')));
  v_after_payment_type TEXT := LOWER(TRIM(COALESCE(p_after_payment_type, 'confirmation')));
  v_currency TEXT := UPPER(TRIM(COALESCE(p_currency, 'USD')));
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
  -- Input validation
  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  IF v_link_type NOT IN ('products', 'custom_amount') THEN
    RAISE EXCEPTION 'Link type must be products or custom_amount';
  END IF;

  IF v_after_payment_type NOT IN ('confirmation', 'redirect') THEN
    RAISE EXCEPTION 'After payment type must be confirmation or redirect';
  END IF;

  IF char_length(v_currency) < 2 OR char_length(v_currency) > 10 THEN
    RAISE EXCEPTION 'Currency must be between 2 and 10 characters';
  END IF;

  -- Authenticate merchant via API key
  SELECT mak.merchant_user_id, mak.id
  INTO v_merchant_user_id, v_api_key_id
  FROM public.merchant_api_keys mak
  WHERE (mak.secret_key_hash = md5(p_secret_key) OR mak.secret_key_hash = encode(digest(p_secret_key, 'sha256'), 'hex'))
    AND mak.key_mode = v_mode
    AND mak.is_active = true
  LIMIT 1;

  IF v_merchant_user_id IS NULL THEN
    RAISE EXCEPTION 'Invalid merchant API key for mode %', v_mode;
  END IF;

  -- Handle expiration
  IF p_expires_in_minutes IS NOT NULL THEN
    v_expires_at := now() + (GREATEST(5, LEAST(p_expires_in_minutes, 525600)) || ' minutes')::INTERVAL;
  END IF;

  -- Create the payment link
  INSERT INTO public.merchant_payment_links (
    merchant_user_id,
    api_key_id,
    key_mode,
    link_token,
    link_type,
    title,
    description,
    currency,
    custom_amount,
    collect_customer_name,
    collect_customer_email,
    collect_phone,
    collect_address,
    after_payment_type,
    confirmation_message,
    redirect_url,
    call_to_action,
    expires_at
  )
  VALUES (
    v_merchant_user_id,
    v_api_key_id,
    v_mode,
    'oplink_' || COALESCE(encode(gen_random_bytes(24), 'hex'), public.random_token_hex(24)),
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

  -- Handle items and calculate total
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
        link_id,
        product_id,
        item_name,
        unit_amount,
        quantity,
        line_total
      )
      VALUES (
        v_link.id,
        v_product.id,
        v_product.product_name,
        v_product.unit_amount,
        v_quantity,
        v_line_total
      );

      v_total := v_total + v_line_total;
    END LOOP;
  END IF;

  IF v_total <= 0 THEN
    RAISE EXCEPTION 'Link total must be positive';
  END IF;

  -- Update the link with calculated total
  UPDATE public.merchant_payment_links
  SET total_amount = v_total
  WHERE id = v_link.id
  RETURNING * INTO v_link;

  -- Update API key last used timestamp
  UPDATE public.merchant_api_keys
  SET last_used_at = now()
  WHERE id = v_api_key_id;

  -- Return the result
  RETURN QUERY
  SELECT v_link.id, v_link.link_token, v_link.total_amount, v_link.currency, v_link.key_mode, v_link.expires_at;
END;
$$;

-- Set proper permissions for the exact function signature
REVOKE ALL ON FUNCTION public.create_merchant_payment_link(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, JSONB, 
  BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, TEXT, TEXT, TEXT, TEXT, INTEGER,
  TEXT, NUMERIC, NUMERIC, TEXT
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_merchant_payment_link(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, JSONB, 
  BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, TEXT, TEXT, TEXT, TEXT, INTEGER,
  TEXT, NUMERIC, NUMERIC, TEXT
) TO authenticated, service_role;

-- Force schema cache refresh
NOTIFY pgrst, 'reload schema';

-- Verify the function was created correctly
DO $$
DECLARE
    func_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO func_count
    FROM information_schema.routines 
    WHERE routine_schema = 'public' 
    AND routine_name = 'create_merchant_payment_link';
    
    IF func_count > 0 THEN
        RAISE NOTICE 'SUCCESS: create_merchant_payment_link function has been recreated with the correct signature';
        RAISE NOTICE 'Schema cache refresh notification sent to PostgREST';
    ELSE
        RAISE EXCEPTION 'ERROR: Function was not created successfully';
    END IF;
END $$;
