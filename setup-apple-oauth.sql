-- Apple OAuth Setup for OpenPay
-- Run this SQL in your Supabase SQL Editor

-- 1. Enable Apple OAuth Provider
-- This SQL enables the Apple provider in auth.providers

INSERT INTO auth.providers (
  id,
  name,
  type,
  config,
  created_at,
  updated_at
) VALUES (
  'apple',
  'apple',
  'oauth',
  '{"client_id": "YOUR_APPLE_CLIENT_ID", "client_secret": "YOUR_APPLE_CLIENT_SECRET", "redirect_uri": "http://localhost:8081/auth/callback"}',
  NOW(),
  NOW()
) ON CONFLICT (id) DO UPDATE SET
  config = EXCLUDED.config,
  updated_at = NOW();

-- 2. Update Apple OAuth Configuration
-- Replace YOUR_APPLE_CLIENT_ID and YOUR_APPLE_CLIENT_SECRET with your actual Apple credentials

UPDATE auth.providers 
SET config = '{
  "client_id": "YOUR_APPLE_CLIENT_ID",
  "client_secret": "YOUR_APPLE_CLIENT_SECRET", 
  "redirect_uri": "http://localhost:8081/auth/callback",
  "scope": "name email"
}'
WHERE name = 'apple';

-- 3. Create function to handle Apple user creation
CREATE OR REPLACE FUNCTION handle_apple_user()
RETURNS TRIGGER AS $$
BEGIN
  -- This trigger runs when a new user signs up via Apple
  -- You can add custom logic here like:
  -- - Creating a profile record
  -- - Setting default values
  -- - Sending welcome emails
  
  INSERT INTO public.profiles (id, full_name, username, referral_code)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    COALESCE(NEW.raw_user_meta_data->>'username', 'apple_user_' || substr(NEW.id, 1, 8)),
    substr(md5(NEW.id || extract(epoch from now())::text), 1, 8)
  )
  ON CONFLICT (id) DO NOTHING;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Create trigger for Apple sign-ups
DROP TRIGGER IF EXISTS on_auth_user_created_apple ON auth.users;
CREATE TRIGGER on_auth_user_created_apple
  AFTER INSERT ON auth.users
  FOR EACH ROW
  WHEN (NEW.raw_user_meta_data->>'provider' = 'apple')
  EXECUTE FUNCTION handle_apple_user();

-- 5. Add Apple provider tracking to profiles
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS auth_provider TEXT DEFAULT 'email';

UPDATE public.profiles 
SET auth_provider = raw_user_meta_data->>'provider'
FROM auth.users 
WHERE auth.users.id = profiles.id;

-- 6. Create view for Apple users analytics
CREATE OR REPLACE VIEW apple_users AS
SELECT 
  p.id,
  p.full_name,
  p.username,
  p.email,
  p.auth_provider,
  p.created_at,
  u.raw_user_meta_data->>'apple_id' as apple_id
FROM public.profiles p
JOIN auth.users u ON p.id = u.id
WHERE p.auth_provider = 'apple';

-- 7. Enable RLS (Row Level Security) for the view
ALTER VIEW apple_users OWNER TO postgres;
GRANT SELECT ON apple_users TO authenticated;
GRANT SELECT ON apple_users TO service_role;

-- 8. Create function to get Apple user statistics
CREATE OR REPLACE FUNCTION get_apple_user_stats()
RETURNS TABLE(
  total_apple_users BIGINT,
  apple_signups_today BIGINT,
  apple_signups_this_week BIGINT,
  apple_signups_this_month BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COUNT(*) as total_apple_users,
    COUNT(*) FILTER (WHERE created_at >= CURRENT_DATE) as apple_signups_today,
    COUNT(*) FILTER (WHERE created_at >= CURRENT_DATE - INTERVAL '7 days') as apple_signups_this_week,
    COUNT(*) FILTER (WHERE created_at >= CURRENT_DATE - INTERVAL '30 days') as apple_signups_this_month
  FROM apple_users;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 9. Add Apple OAuth callback logging
CREATE TABLE IF NOT EXISTS auth.oauth_logs (
  id BIGSERIAL PRIMARY KEY,
  provider TEXT NOT NULL,
  user_id UUID REFERENCES auth.users(id),
  event_type TEXT NOT NULL, -- 'signin', 'signup', 'error'
  event_data JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 10. Create trigger to log Apple OAuth events
CREATE OR REPLACE FUNCTION log_apple_oauth_events()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO auth.oauth_logs (provider, user_id, event_type, event_data)
    VALUES ('apple', NEW.id, 'signup', row_to_json(NEW));
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    -- Log sign-in events when last_sign_in_at changes
    IF OLD.last_sign_in_at IS DISTINCT FROM NEW.last_sign_in_at THEN
      INSERT INTO auth.oauth_logs (provider, user_id, event_type, event_data)
      VALUES ('apple', NEW.id, 'signin', json_build_object('email', NEW.email, 'last_sign_in_at', NEW.last_sign_in_at));
    END IF;
    RETURN NEW;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS log_apple_oauth_trigger ON auth.users;
CREATE TRIGGER log_apple_oauth_trigger
  AFTER INSERT OR UPDATE ON auth.users
  FOR EACH ROW
  WHEN (NEW.raw_user_meta_data->>'provider' = 'apple')
  EXECUTE FUNCTION log_apple_oauth_events();

-- 11. Production redirect URI setup (uncomment for production)
-- UPDATE auth.providers 
-- SET config = '{
--   "client_id": "YOUR_APPLE_CLIENT_ID",
--   "client_secret": "YOUR_APPLE_CLIENT_SECRET", 
--   "redirect_uri": "https://yourdomain.com/auth/callback",
--   "scope": "name email"
-- }'
-- WHERE name = 'apple';

-- 12. Verification queries
-- Check Apple provider configuration
SELECT * FROM auth.providers WHERE name = 'apple';

-- Check Apple users
SELECT COUNT(*) as apple_user_count FROM apple_users;

-- Check recent Apple OAuth logs
SELECT * FROM auth.oauth_logs WHERE provider = 'apple' ORDER BY created_at DESC LIMIT 5;
