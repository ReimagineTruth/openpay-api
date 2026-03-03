-- Mining System Setup - Safe Version (Step 3)
-- Run this after Step 2 completes successfully

-- Enable RLS and create policies
ALTER TABLE public.mining_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mining_rewards ENABLE ROW LEVEL SECURITY;

-- Create policies (drop existing first to avoid conflicts)
DROP POLICY IF EXISTS "Users can view their own mining sessions" ON public.mining_sessions;
CREATE POLICY "Users can view their own mining sessions"
ON public.mining_sessions FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view their own mining rewards" ON public.mining_rewards;
CREATE POLICY "Users can view their own mining rewards"
ON public.mining_rewards FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Enable Realtime (ignore if already exists)
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.mining_sessions;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.mining_rewards;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

SELECT 'Step 3 completed: Policies and realtime enabled successfully!' as status;
SELECT 'Mining system setup completed successfully!' as final_status;
