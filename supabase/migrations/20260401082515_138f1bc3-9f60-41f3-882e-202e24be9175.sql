-- Enable RLS on openpay_runtime_settings
ALTER TABLE public.openpay_runtime_settings ENABLE ROW LEVEL SECURITY;

-- Service role only policy
CREATE POLICY "Service role manages settings" 
ON public.openpay_runtime_settings 
FOR ALL TO service_role 
USING (true) 
WITH CHECK (true);