-- Daily interest accrual for user savings
-- Adds last_interest_accrued_date and an RPC to accrue once per day

ALTER TABLE public.user_savings_accounts
ADD COLUMN IF NOT EXISTS last_interest_accrued_date DATE;

CREATE OR REPLACE FUNCTION public.accrue_my_savings_interest()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_row public.user_savings_accounts;
  v_today DATE := CURRENT_DATE;
  v_daily_rate NUMERIC;
  v_interest NUMERIC(12,2);
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  v_row := public.upsert_my_savings_account();

  IF COALESCE(v_row.last_interest_accrued_date, DATE '1900-01-01') = v_today THEN
    RETURN jsonb_build_object(
      'credited', false,
      'interest', 0,
      'balance', v_row.balance,
      'date', v_today
    );
  END IF;

  IF COALESCE(v_row.balance, 0) <= 0 THEN
    UPDATE public.user_savings_accounts
    SET last_interest_accrued_date = v_today
    WHERE user_id = v_user_id;
    RETURN jsonb_build_object(
      'credited', false,
      'interest', 0,
      'balance', v_row.balance,
      'date', v_today
    );
  END IF;

  v_daily_rate := (COALESCE(v_row.apy, 4.50) / 100.0) / 365.0;
  v_interest := ROUND(v_row.balance * v_daily_rate, 2);

  IF v_interest <= 0 THEN
    UPDATE public.user_savings_accounts
    SET last_interest_accrued_date = v_today
    WHERE user_id = v_user_id;
    RETURN jsonb_build_object(
      'credited', false,
      'interest', 0,
      'balance', v_row.balance,
      'date', v_today
    );
  END IF;

  UPDATE public.user_savings_accounts
  SET balance = v_row.balance + v_interest,
      last_interest_accrued_date = v_today,
      updated_at = now()
  WHERE user_id = v_user_id
  RETURNING * INTO v_row;

  RETURN jsonb_build_object(
    'credited', true,
    'interest', v_interest,
    'balance', v_row.balance,
    'date', v_today
  );
END;
$$;

REVOKE ALL ON FUNCTION public.accrue_my_savings_interest() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accrue_my_savings_interest() TO authenticated, service_role;
