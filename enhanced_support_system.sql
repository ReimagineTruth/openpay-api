-- Complete Support System Fix and Enhancement
-- This script fixes the attachment_url error and enhances support functionality

-- 1. Fix missing attachment_url column
ALTER TABLE public.support_messages
  ADD COLUMN IF NOT EXISTS attachment_url TEXT;

-- 2. Add additional columns for enhanced support like PayPal
ALTER TABLE public.support_messages
  ADD COLUMN IF NOT EXISTS attachment_type TEXT,
  ADD COLUMN IF NOT EXISTS message_status TEXT DEFAULT 'sent' CHECK (message_status IN ('sent', 'delivered', 'read', 'failed')),
  ADD COLUMN IF NOT EXISTS priority TEXT DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
  ADD COLUMN IF NOT EXISTS category TEXT DEFAULT 'general' CHECK (category IN ('general', 'topup', 'withdrawal', 'technical', 'account', 'security', 'fraud'));

-- 3. Create storage bucket for support attachments if it doesn't exist
INSERT INTO storage.buckets (id, name, public)
VALUES ('support-attachments', 'support-attachments', true)
ON CONFLICT (id) DO NOTHING;

-- 4. Add enhanced policies for support attachments
DO $$
BEGIN
  -- Drop existing policies if they exist to avoid conflicts
  DROP POLICY IF EXISTS "Support attachments read" ON storage.objects;
  DROP POLICY IF EXISTS "Support attachments insert" ON storage.objects;
  
  -- Create new policies
  CREATE POLICY "Support attachments read"
    ON storage.objects
    FOR SELECT TO authenticated
    USING (bucket_id = 'support-attachments');
    
  CREATE POLICY "Support attachments insert"
    ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'support-attachments');
END $$;

-- 5. Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_support_messages_status ON public.support_messages (message_status);
CREATE INDEX IF NOT EXISTS idx_support_messages_priority ON public.support_messages (priority);
CREATE INDEX IF NOT EXISTS idx_support_messages_category ON public.support_messages (category);

-- 6. Create a function for automatic message status updates
CREATE OR REPLACE FUNCTION public.mark_message_read()
RETURNS TRIGGER AS $$
BEGIN
  -- Update message status to 'read' when conversation is accessed
  UPDATE public.support_messages 
  SET message_status = 'read', read_at = now()
  WHERE conversation_id = NEW.conversation_id 
    AND sender_role = 'agent' 
    AND message_status != 'read';
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 7. Create trigger for automatic read status (optional)
DROP TRIGGER IF EXISTS on_conversation_access ON public.support_conversations;
CREATE TRIGGER on_conversation_access
  AFTER UPDATE ON public.support_conversations
  FOR EACH ROW
  EXECUTE FUNCTION public.mark_message_read();

-- 8. Add support agent availability status
ALTER TABLE public.support_agents
  ADD COLUMN IF NOT EXISTS is_available BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS last_active_at TIMESTAMPTZ DEFAULT now();

-- 9. Create support categories table for better organization
CREATE TABLE IF NOT EXISTS public.support_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  icon TEXT,
  color TEXT DEFAULT '#007bff',
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 10. Insert default support categories
INSERT INTO public.support_categories (name, description, icon, color) VALUES
  ('general', 'General inquiries and help', 'help-circle', '#007bff'),
  ('topup', 'Top-up and payment issues', 'credit-card', '#28a745'),
  ('withdrawal', 'Withdrawal and transfer issues', 'bank-note', '#ffc107'),
  ('technical', 'Technical problems and bugs', 'alert-circle', '#dc3545'),
  ('account', 'Account management and security', 'user', '#6f42c1'),
  ('security', 'Security concerns and fraud', 'shield', '#e83e8c'),
  ('fraud', 'Fraud reports and disputes', 'triangle', '#fd7e14')
ON CONFLICT (name) DO NOTHING;

-- 11. Create support ticket priorities table
CREATE TABLE IF NOT EXISTS public.support_priorities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  level TEXT NOT NULL UNIQUE CHECK (level IN ('low', 'normal', 'high', 'urgent')),
  description TEXT,
  color TEXT DEFAULT '#6c757d',
  auto_assign_hours INTEGER DEFAULT 24,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 12. Insert default priorities
INSERT INTO public.support_priorities (level, description, color, auto_assign_hours) VALUES
  ('low', 'Low priority - response within 48 hours', '#28a745', 48),
  ('normal', 'Normal priority - response within 24 hours', '#007bff', 24),
  ('high', 'High priority - response within 4 hours', '#ffc107', 4),
  ('urgent', 'Urgent - immediate response required', '#dc3545', 1)
ON CONFLICT (level) DO NOTHING;

-- 13. Enable RLS on new tables
ALTER TABLE public.support_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_priorities ENABLE ROW LEVEL SECURITY;

-- 14. Add RLS policies for new tables
DO $$
BEGIN
  -- Support categories policies
  CREATE POLICY "Anyone can read support categories" ON public.support_categories
    FOR SELECT TO authenticated USING (true);
    
  CREATE POLICY "Agents can manage support categories" ON public.support_categories
    FOR ALL TO authenticated USING (public.is_support_agent(auth.uid()));
    
  -- Support priorities policies  
  CREATE POLICY "Anyone can read support priorities" ON public.support_priorities
    FOR SELECT TO authenticated USING (true);
    
  CREATE POLICY "Agents can manage support priorities" ON public.support_priorities
    FOR ALL TO authenticated USING (public.is_support_agent(auth.uid()));
END $$;

-- 15. Refresh schema cache to ensure all changes are recognized
NOTIFY pgrst, 'reload schema';

-- 16. Verify the table structure
SELECT 
  column_name, 
  data_type, 
  is_nullable,
  column_default
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'support_messages' 
  AND column_name IN ('attachment_url', 'attachment_type', 'message_status', 'priority', 'category')
ORDER BY column_name;
