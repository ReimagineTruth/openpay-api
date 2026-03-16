-- Create merchant_activity table for tracking merchant operations
CREATE TABLE IF NOT EXISTS public.merchant_activity (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  activity_type TEXT NOT NULL,
  amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'OUSD',
  status TEXT NOT NULL DEFAULT 'pending',
  note TEXT,
  source TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_merchant_activity_user_created ON public.merchant_activity(merchant_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_merchant_activity_type ON public.merchant_activity(activity_type);

-- Grant permissions
ALTER TABLE public.merchant_activity ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view their own merchant activity" ON public.merchant_activity;
CREATE POLICY "Users can view their own merchant activity" ON public.merchant_activity
  FOR ALL USING (auth.uid() = merchant_user_id);

GRANT ALL ON public.merchant_activity TO authenticated;
GRANT SELECT ON public.merchant_activity TO service_role;
