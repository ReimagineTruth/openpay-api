-- Complete Pi Network A2U Withdrawal Database Schema
-- This file creates all necessary tables, indexes, and RLS policies for Pi withdrawals

-- ============================================
-- 1. Pi Withdrawals Table
-- ============================================

CREATE TABLE IF NOT EXISTS public.pi_withdrawals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_uid UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount NUMERIC(20,8) NOT NULL CHECK (amount > 0),
  memo TEXT NOT NULL DEFAULT '',
  metadata JSONB DEFAULT '{}',
  payment_id TEXT NOT NULL UNIQUE,
  txid TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'submitted', 'completed', 'failed', 'cancelled')),
  from_address TEXT DEFAULT '',
  to_address TEXT DEFAULT '',
  direction TEXT NOT NULL DEFAULT 'app_to_user' CHECK (direction IN ('app_to_user', 'user_to_app')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  network TEXT NOT NULL DEFAULT 'Pi Network' CHECK (network IN ('Pi Network', 'Pi Testnet')),
  transaction_verified BOOLEAN NOT NULL DEFAULT false,
  developer_completed BOOLEAN NOT NULL DEFAULT false,
  fee_amount NUMERIC(20,8) DEFAULT 0,
  fee_currency TEXT DEFAULT 'PI',
  blockchain_confirmed_at TIMESTAMPTZ,
  error_message TEXT,
  retry_count INTEGER DEFAULT 0,
  max_retries INTEGER DEFAULT 3
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_pi_withdrawals_user_uid ON public.pi_withdrawals(user_uid);
CREATE INDEX IF NOT EXISTS idx_pi_withdrawals_status ON public.pi_withdrawals(status);
CREATE INDEX IF NOT EXISTS idx_pi_withdrawals_payment_id ON public.pi_withdrawals(payment_id);
CREATE INDEX IF NOT EXISTS idx_pi_withdrawals_txid ON public.pi_withdrawals(txid);
CREATE INDEX IF NOT EXISTS idx_pi_withdrawals_created_at ON public.pi_withdrawals(created_at DESC);

-- Enable Row Level Security
ALTER TABLE public.pi_withdrawals ENABLE ROW LEVEL SECURITY;

-- RLS Policies for pi_withdrawals
CREATE POLICY "Users can view own withdrawals" ON public.pi_withdrawals
  FOR SELECT TO authenticated
  USING (user_uid = auth.uid());

CREATE POLICY "Users can insert own withdrawals" ON public.pi_withdrawals
  FOR INSERT TO authenticated
  WITH CHECK (user_uid = auth.uid());

CREATE POLICY "Users can update own withdrawals" ON public.pi_withdrawals
  FOR UPDATE TO authenticated
  USING (user_uid = auth.uid())
  WITH CHECK (user_uid = auth.uid());

-- ============================================
-- 2. User Pi Balances Table
-- ============================================

CREATE TABLE IF NOT EXISTS public.user_pi_balances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_uid UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  pi_balance NUMERIC(20,8) NOT NULL DEFAULT 0 CHECK (pi_balance >= 0),
  frozen_balance NUMERIC(20,8) NOT NULL DEFAULT 0 CHECK (frozen_balance >= 0),
  total_withdrawn NUMERIC(20,8) NOT NULL DEFAULT 0 CHECK (total_withdrawn >= 0),
  total_deposited NUMERIC(20,8) NOT NULL DEFAULT 0 CHECK (total_deposited >= 0),
  last_withdrawal_at TIMESTAMPTZ,
  last_deposit_at TIMESTAMPTZ,
  withdrawal_count INTEGER NOT NULL DEFAULT 0,
  deposit_count INTEGER NOT NULL DEFAULT 0,
  daily_withdrawal_limit NUMERIC(20,8) NOT NULL DEFAULT 1000,
  daily_withdrawn NUMERIC(20,8) NOT NULL DEFAULT 0,
  daily_reset_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '1 day'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_user_pi_balances_user_uid ON public.user_pi_balances(user_uid);
CREATE INDEX IF NOT EXISTS idx_user_pi_balances_daily_reset_at ON public.user_pi_balances(daily_reset_at);

-- Enable RLS
ALTER TABLE public.user_pi_balances ENABLE ROW LEVEL SECURITY;

-- RLS Policies for user_pi_balances
CREATE POLICY "Users can view own Pi balance" ON public.user_pi_balances
  FOR SELECT TO authenticated
  USING (user_uid = auth.uid());

CREATE POLICY "Users can insert own Pi balance" ON public.user_pi_balances
  FOR INSERT TO authenticated
  WITH CHECK (user_uid = auth.uid());

CREATE POLICY "Users can update own Pi balance" ON public.user_pi_balances
  FOR UPDATE TO authenticated
  USING (user_uid = auth.uid())
  WITH CHECK (user_uid = auth.uid());

-- ============================================
-- 3. Pi Transaction Log Table
-- ============================================

CREATE TABLE IF NOT EXISTS public.pi_transaction_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  withdrawal_id UUID REFERENCES public.pi_withdrawals(id) ON DELETE CASCADE,
  transaction_type TEXT NOT NULL CHECK (transaction_type IN ('payment_created', 'payment_submitted', 'payment_completed', 'payment_failed', 'payment_cancelled')),
  transaction_data JSONB DEFAULT '{}',
  blockchain_data JSONB DEFAULT '{}',
  api_response JSONB DEFAULT '{}',
  processing_time_ms INTEGER,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_pi_transaction_log_withdrawal_id ON public.pi_transaction_log(withdrawal_id);
CREATE INDEX IF NOT EXISTS idx_pi_transaction_log_transaction_type ON public.pi_transaction_log(transaction_type);
CREATE INDEX IF NOT EXISTS idx_pi_transaction_log_created_at ON public.pi_transaction_log(created_at DESC);

-- Enable RLS
ALTER TABLE public.pi_transaction_log ENABLE ROW LEVEL SECURITY;

-- RLS Policies for pi_transaction_log (indirect through withdrawals)
CREATE POLICY "Users can view own transaction logs" ON public.pi_transaction_log
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.pi_withdrawals 
      WHERE pi_withdrawals.id = pi_transaction_log.withdrawal_id 
      AND pi_withdrawals.user_uid = auth.uid()
    )
  );

-- ============================================
-- 4. Triggers and Functions
-- ============================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
DROP TRIGGER IF EXISTS trg_pi_withdrawals_updated_at ON public.pi_withdrawals;
CREATE TRIGGER trg_pi_withdrawals_updated_at
  BEFORE UPDATE ON public.pi_withdrawals
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_user_pi_balances_updated_at ON public.user_pi_balances;
CREATE TRIGGER trg_user_pi_balances_updated_at
  BEFORE UPDATE ON public.user_pi_balances
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- Function to handle Pi balance updates
CREATE OR REPLACE FUNCTION public.update_pi_balance_on_withdrawal()
RETURNS TRIGGER AS $$
DECLARE
  v_balance_record public.user_pi_balances%ROWTYPE;
  v_new_balance NUMERIC(20,8);
  v_current_date DATE := current_date;
BEGIN
  -- Get or create user balance record
  INSERT INTO public.user_pi_balances (user_uid, pi_balance)
  VALUES (NEW.user_uid, 1000) -- Default balance
  ON CONFLICT (user_uid) 
  DO UPDATE SET
    updated_at = now()
  RETURNING * INTO v_balance_record;

  -- Reset daily withdrawal if needed
  IF v_balance_record.daily_reset_at <= now() THEN
    UPDATE public.user_pi_balances
    SET 
      daily_withdrawn = 0,
      daily_reset_at = (current_date + interval '1 day')::timestamp,
      updated_at = now()
    WHERE user_uid = NEW.user_uid;
    
    v_balance_record.daily_withdrawn := 0;
  END IF;

  -- Check daily limit
  IF (v_balance_record.daily_withdrawn + NEW.amount) > v_balance_record.daily_withdrawal_limit THEN
    RAISE EXCEPTION 'Daily withdrawal limit exceeded. Limit: %PI, Attempted: %PI', 
      v_balance_record.daily_withdrawal_limit, 
      v_balance_record.daily_withdrawn + NEW.amount;
  END IF;

  -- Calculate new balance
  v_new_balance := v_balance_record.pi_balance - NEW.amount;
  
  IF v_new_balance < 0 THEN
    RAISE EXCEPTION 'Insufficient balance. Current: %PI, Attempted: %PI', 
      v_balance_record.pi_balance, NEW.amount;
  END IF;

  -- Update balance record
  UPDATE public.user_pi_balances
  SET 
    pi_balance = v_new_balance,
    frozen_balance = frozen_balance + NEW.amount,
    total_withdrawn = total_withdrawn + NEW.amount,
    last_withdrawal_at = now(),
    withdrawal_count = withdrawal_count + 1,
    daily_withdrawn = daily_withdrawn + NEW.amount,
    updated_at = now()
  WHERE user_uid = NEW.user_uid;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for balance updates on withdrawal creation
DROP TRIGGER IF EXISTS trg_update_pi_balance_on_withdrawal ON public.pi_withdrawals;
CREATE TRIGGER trg_update_pi_balance_on_withdrawal
  AFTER INSERT ON public.pi_withdrawals
  FOR EACH ROW
  EXECUTE FUNCTION public.update_pi_balance_on_withdrawal();

-- Function to unfreeze balance on successful completion
CREATE OR REPLACE FUNCTION public.unfreeze_balance_on_completion()
RETURNS TRIGGER AS $$
BEGIN
  -- Only proceed if status is 'completed'
  IF NEW.status != 'completed' OR OLD.status = 'completed' THEN
    RETURN NEW;
  END IF;

  -- Unfreeze the amount
  UPDATE public.user_pi_balances
  SET 
    frozen_balance = frozen_balance - NEW.amount,
    updated_at = now()
  WHERE user_uid = NEW.user_uid;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for unfreezing balance on completion
DROP TRIGGER IF EXISTS trg_unfreeze_balance_on_completion ON public.pi_withdrawals;
CREATE TRIGGER trg_unfreeze_balance_on_completion
  AFTER UPDATE ON public.pi_withdrawals
  FOR EACH ROW
  EXECUTE FUNCTION public.unfreeze_balance_on_completion();

-- Function to refund balance on failed withdrawal
CREATE OR REPLACE FUNCTION public.refund_balance_on_failure()
RETURNS TRIGGER AS $$
BEGIN
  -- Only proceed if status changed to 'failed' or 'cancelled'
  IF NOT (NEW.status IN ('failed', 'cancelled')) OR OLD.status IN ('failed', 'cancelled') THEN
    RETURN NEW;
  END IF;

  -- Refund the amount back to available balance
  UPDATE public.user_pi_balances
  SET 
    pi_balance = pi_balance + NEW.amount,
    frozen_balance = frozen_balance - NEW.amount,
    updated_at = now()
  WHERE user_uid = NEW.user_uid;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for refunding balance on failure
DROP TRIGGER IF EXISTS trg_refund_balance_on_failure ON public.pi_withdrawals;
CREATE TRIGGER trg_refund_balance_on_failure
  AFTER UPDATE ON public.pi_withdrawals
  FOR EACH ROW
  EXECUTE FUNCTION public.refund_balance_on_failure();

-- ============================================
-- 5. RPC Functions for Pi Operations
-- ============================================

-- Function to get user Pi balance
CREATE OR REPLACE FUNCTION public.get_user_pi_balance()
RETURNS TABLE (
  pi_balance NUMERIC(20,8),
  frozen_balance NUMERIC(20,8),
  available_balance NUMERIC(20,8),
  daily_withdrawal_limit NUMERIC(20,8),
  daily_withdrawn NUMERIC(20,8),
  daily_remaining NUMERIC(20,8),
  total_withdrawn NUMERIC(20,8),
  withdrawal_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_balance_record public.user_pi_balances%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Get or create balance record
  INSERT INTO public.user_pi_balances (user_uid, pi_balance)
  VALUES (v_user_id, 1000) -- Default balance
  ON CONFLICT (user_uid) 
  DO UPDATE SET
    updated_at = now()
  RETURNING * INTO v_balance_record;

  -- Reset daily limit if needed
  IF v_balance_record.daily_reset_at <= now() THEN
    UPDATE public.user_pi_balances
    SET 
      daily_withdrawn = 0,
      daily_reset_at = (current_date + interval '1 day')::timestamp,
      updated_at = now()
    WHERE user_uid = v_user_id;
    
    v_balance_record.daily_withdrawn := 0;
  END IF;

  RETURN QUERY
  SELECT 
    v_balance_record.pi_balance,
    v_balance_record.frozen_balance,
    v_balance_record.pi_balance - v_balance_record.frozen_balance,
    v_balance_record.daily_withdrawal_limit,
    v_balance_record.daily_withdrawn,
    v_balance_record.daily_withdrawal_limit - v_balance_record.daily_withdrawn,
    v_balance_record.total_withdrawn,
    v_balance_record.withdrawal_count;
END;
$$;

-- Function to get withdrawal history
CREATE OR REPLACE FUNCTION public.get_pi_withdrawal_history(
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  amount NUMERIC(20,8),
  memo TEXT,
  status TEXT,
  payment_id TEXT,
  txid TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  network TEXT,
  transaction_verified BOOLEAN,
  fee_amount NUMERIC(20,8)
)
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

  RETURN QUERY
  SELECT 
    pw.id,
    pw.amount,
    pw.memo,
    pw.status,
    pw.payment_id,
    pw.txid,
    pw.created_at,
    pw.updated_at,
    pw.network,
    pw.transaction_verified,
    pw.fee_amount
  FROM public.pi_withdrawals pw
  WHERE pw.user_uid = v_user_id
  ORDER BY pw.created_at DESC
  LIMIT GREATEST(1, LEAST(p_limit, 100))
  OFFSET GREATEST(0, p_offset);
END;
$$;

-- Grant permissions for RPC functions
REVOKE ALL ON FUNCTION public.get_user_pi_balance() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_user_pi_balance() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_pi_withdrawal_history(INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_pi_withdrawal_history(INTEGER, INTEGER) TO authenticated, service_role;

-- ============================================
-- 6. Initialize Default Data
-- ============================================

-- Insert default Pi balances for existing users
INSERT INTO public.user_pi_balances (user_uid, pi_balance)
SELECT 
  id as user_uid,
  1000 as pi_balance -- Default balance
FROM auth.users
WHERE NOT EXISTS (
  SELECT 1 FROM public.user_pi_balances 
  WHERE user_pi_balances.user_uid = auth.users.id
);

-- ============================================
-- 7. Views for Reporting
-- ============================================

-- View for withdrawal statistics
CREATE OR REPLACE VIEW public.pi_withdrawal_stats AS
SELECT 
  DATE_TRUNC('day', created_at) as date,
  COUNT(*) as total_withdrawals,
  SUM(amount) as total_amount,
  AVG(amount) as avg_amount,
  COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed_withdrawals,
  SUM(CASE WHEN status = 'completed' THEN amount ELSE 0 END) as completed_amount,
  COUNT(CASE WHEN status = 'failed' THEN 1 END) as failed_withdrawals,
  SUM(CASE WHEN status = 'failed' THEN amount ELSE 0 END) as failed_amount
FROM public.pi_withdrawals
GROUP BY DATE_TRUNC('day', created_at)
ORDER BY date DESC;

-- ============================================
-- 8. Cleanup Functions
-- ============================================

-- Function to clean up old transaction logs
CREATE OR REPLACE FUNCTION public.cleanup_old_transaction_logs(p_days_old INTEGER DEFAULT 30)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted_count INTEGER;
BEGIN
  DELETE FROM public.pi_transaction_log
  WHERE created_at < now() - (p_days_old || ' days')::interval;
  
  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  RETURN v_deleted_count;
END;
$$;

-- Grant permissions for cleanup function
REVOKE ALL ON FUNCTION public.cleanup_old_transaction_logs(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cleanup_old_transaction_logs(INTEGER) TO service_role;

-- ============================================
-- Schema Complete
-- ============================================

-- Log completion
DO $$
BEGIN
  RAISE NOTICE 'Pi Network A2U withdrawal schema created successfully';
  RAISE NOTICE 'Tables: pi_withdrawals, user_pi_balances, pi_transaction_log';
  RAISE NOTICE 'RPC Functions: get_user_pi_balance, get_pi_withdrawal_history';
  RAISE NOTICE 'Views: pi_withdrawal_stats';
  RAISE NOTICE 'Triggers: Balance management, status updates';
END $$;
