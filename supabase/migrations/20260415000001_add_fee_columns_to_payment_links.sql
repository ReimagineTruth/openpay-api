-- Add fee handling columns to merchant_payment_links table
-- This allows storing who pays fees and fee amounts

ALTER TABLE public.merchant_payment_links 
ADD COLUMN IF NOT EXISTS fee_payer TEXT DEFAULT NULL CHECK (fee_payer IS NULL OR fee_payer IN ('customer', 'merchant'));

ALTER TABLE public.merchant_payment_links 
ADD COLUMN IF NOT EXISTS fee_amount NUMERIC(12,2) DEFAULT NULL CHECK (fee_amount IS NULL OR fee_amount >= 0);

ALTER TABLE public.merchant_payment_links 
ADD COLUMN IF NOT EXISTS merchant_settlement_amount NUMERIC(12,2) DEFAULT NULL CHECK (merchant_settlement_amount IS NULL OR merchant_settlement_amount >= 0);

ALTER TABLE public.merchant_payment_links 
ADD COLUMN IF NOT EXISTS openpay_fee_account TEXT DEFAULT NULL;
