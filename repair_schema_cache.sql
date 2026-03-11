-- Repair script to ensure original_amount columns exist and refresh schema cache
-- Run this in the Supabase SQL Editor

-- 1. Ensure columns exist for payment_requests
ALTER TABLE public.payment_requests
  ADD COLUMN IF NOT EXISTS original_amount NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS original_currency_code TEXT;

-- 2. Ensure columns exist for invoices
ALTER TABLE public.invoices
  ADD COLUMN IF NOT EXISTS original_amount NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS original_currency_code TEXT;

-- 3. Refresh schema cache (PostgREST)
NOTIFY pgrst, 'reload schema';

-- 4. Verify columns
DO $$
BEGIN
    RAISE NOTICE 'Schema repair completed. Please check if columns original_amount and original_currency_code are now visible.';
END $$;
