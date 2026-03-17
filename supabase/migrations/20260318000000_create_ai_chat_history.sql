-- 20260318000000_create_ai_chat_history.sql
-- Create table for OpenPay AI chat history and user interactions

-- Create AI chat history table
CREATE TABLE IF NOT EXISTS public.ai_chat_history (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
  content TEXT NOT NULL,
  type TEXT DEFAULT 'text' CHECK (type IN ('text', 'insight', 'payment', 'alert')),
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_ai_chat_history_user_id ON public.ai_chat_history(user_id);
CREATE INDEX IF NOT EXISTS idx_ai_chat_history_created_at ON public.ai_chat_history(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_chat_history_user_created ON public.ai_chat_history(user_id, created_at DESC);

-- Enable Row Level Security
ALTER TABLE public.ai_chat_history ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view own AI chat history"
  ON public.ai_chat_history
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own AI chat messages"
  ON public.ai_chat_history
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own AI chat messages"
  ON public.ai_chat_history
  FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own AI chat messages"
  ON public.ai_chat_history
  FOR DELETE
  USING (auth.uid() = user_id);

-- Create function to clean up old chat history (older than 90 days)
CREATE OR REPLACE FUNCTION public.cleanup_old_ai_chat_history()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM public.ai_chat_history
  WHERE created_at < now() - interval '90 days';
END;
$$;

-- Grant necessary permissions
GRANT ALL ON public.ai_chat_history TO authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_old_ai_chat_history() TO service_role;

-- Create AI user preferences table
CREATE TABLE IF NOT EXISTS public.ai_user_preferences (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
  ai_notifications_enabled BOOLEAN DEFAULT true,
  budget_alerts_enabled BOOLEAN DEFAULT true,
  spending_insights_enabled BOOLEAN DEFAULT true,
  payment_confirmations_required BOOLEAN DEFAULT true,
  daily_spending_limit NUMERIC(12,2) DEFAULT 10000.00,
  monthly_budget_limit NUMERIC(12,2) DEFAULT 50000.00,
  preferred_currency TEXT DEFAULT 'PHP',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS for preferences
ALTER TABLE public.ai_user_preferences ENABLE ROW LEVEL SECURITY;

-- RLS Policies for preferences
CREATE POLICY "Users can view own AI preferences"
  ON public.ai_user_preferences
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can update own AI preferences"
  ON public.ai_user_preferences
  FOR ALL
  USING (auth.uid() = user_id);

-- Grant permissions
GRANT ALL ON public.ai_user_preferences TO authenticated;

-- Create function to get user AI preferences
CREATE OR REPLACE FUNCTION public.get_my_ai_preferences()
RETURNS TABLE (
  ai_notifications_enabled BOOLEAN,
  budget_alerts_enabled BOOLEAN,
  spending_insights_enabled BOOLEAN,
  payment_confirmations_required BOOLEAN,
  daily_spending_limit NUMERIC,
  monthly_budget_limit NUMERIC,
  preferred_currency TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COALESCE(aup.ai_notifications_enabled, true) as ai_notifications_enabled,
    COALESCE(aup.budget_alerts_enabled, true) as budget_alerts_enabled,
    COALESCE(aup.spending_insights_enabled, true) as spending_insights_enabled,
    COALESCE(aup.payment_confirmations_required, true) as payment_confirmations_required,
    COALESCE(aup.daily_spending_limit, 10000.00) as daily_spending_limit,
    COALESCE(aup.monthly_budget_limit, 50000.00) as monthly_budget_limit,
    COALESCE(aup.preferred_currency, 'PHP') as preferred_currency
  FROM public.ai_user_preferences aup
  WHERE aup.user_id = auth.uid()
  LIMIT 1;
  
  -- If no preferences exist, return defaults
  IF NOT FOUND THEN
    RETURN QUERY
    SELECT 
      true as ai_notifications_enabled,
      true as budget_alerts_enabled,
      true as spending_insights_enabled,
      true as payment_confirmations_required,
      10000.00 as daily_spending_limit,
      50000.00 as monthly_budget_limit,
      'PHP' as preferred_currency;
  END IF;
END;
$$;

-- Create function to update AI preferences
CREATE OR REPLACE FUNCTION public.update_my_ai_preferences(
  p_ai_notifications_enabled BOOLEAN DEFAULT NULL,
  p_budget_alerts_enabled BOOLEAN DEFAULT NULL,
  p_spending_insights_enabled BOOLEAN DEFAULT NULL,
  p_payment_confirmations_required BOOLEAN DEFAULT NULL,
  p_daily_spending_limit NUMERIC DEFAULT NULL,
  p_monthly_budget_limit NUMERIC DEFAULT NULL,
  p_preferred_currency TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.ai_user_preferences (
    user_id,
    ai_notifications_enabled,
    budget_alerts_enabled,
    spending_insights_enabled,
    payment_confirmations_required,
    daily_spending_limit,
    monthly_budget_limit,
    preferred_currency
  ) VALUES (
    auth.uid(),
    p_ai_notifications_enabled,
    p_budget_alerts_enabled,
    p_spending_insights_enabled,
    p_payment_confirmations_required,
    p_daily_spending_limit,
    p_monthly_budget_limit,
    p_preferred_currency
  )
  ON CONFLICT (user_id) DO UPDATE SET
    ai_notifications_enabled = COALESCE(p_ai_notifications_enabled, ai_user_preferences.ai_notifications_enabled),
    budget_alerts_enabled = COALESCE(p_budget_alerts_enabled, ai_user_preferences.budget_alerts_enabled),
    spending_insights_enabled = COALESCE(p_spending_insights_enabled, ai_user_preferences.spending_insights_enabled),
    payment_confirmations_required = COALESCE(p_payment_confirmations_required, ai_user_preferences.payment_confirmations_required),
    daily_spending_limit = COALESCE(p_daily_spending_limit, ai_user_preferences.daily_spending_limit),
    monthly_budget_limit = COALESCE(p_monthly_budget_limit, ai_user_preferences.monthly_budget_limit),
    preferred_currency = COALESCE(p_preferred_currency, ai_user_preferences.preferred_currency),
    updated_at = now();
    
  RETURN true;
END;
$$;

-- Grant permissions for preference functions
GRANT EXECUTE ON FUNCTION public.get_my_ai_preferences() TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_my_ai_preferences(
  BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, NUMERIC, NUMERIC, TEXT
) TO authenticated;

NOTIFY pgrst, 'reload schema';
