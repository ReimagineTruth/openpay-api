-- Fix missing attachment_url column in support_messages table
-- This addresses the error: "Could not find the 'attachment_url' column of 'support_messages' in the schema cache"

-- Add the missing attachment_url column if it doesn't exist
ALTER TABLE public.support_messages
  ADD COLUMN IF NOT EXISTS attachment_url TEXT;

-- Create storage bucket for support attachments if it doesn't exist
INSERT INTO storage.buckets (id, name, public)
VALUES ('support-attachments', 'support-attachments', true)
ON CONFLICT (id) DO NOTHING;

-- Add policies for support attachments if they don't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'Support attachments read'
  ) THEN
    CREATE POLICY "Support attachments read"
      ON storage.objects
      FOR SELECT TO authenticated
      USING (bucket_id = 'support-attachments');
  END IF;
  
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'Support attachments insert'
  ) THEN
    CREATE POLICY "Support attachments insert"
      ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'support-attachments');
  END IF;
END $$;

-- Refresh schema cache to ensure the new column is recognized
NOTIFY pgrst, 'reload schema';

-- Verify the column was added
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'support_messages'
  AND column_name = 'attachment_url';
