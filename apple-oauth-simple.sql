-- Simple Apple OAuth Setup for OpenPay
-- Run this in Supabase SQL Editor

-- 1. Configure Apple OAuth Provider
UPDATE auth.providers 
SET config = '{
  "client_id": "YOUR_APPLE_CLIENT_ID",
  "client_secret": "YOUR_APPLE_CLIENT_SECRET", 
  "redirect_uri": "http://localhost:8081/auth/callback",
  "scope": "name email"
}'
WHERE name = 'apple';

-- 2. Enable Apple provider if not exists
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
  '{"client_id": "YOUR_APPLE_CLIENT_ID", "client_secret": "YOUR_APPLE_CLIENT_SECRET", "redirect_uri": "http://localhost:8081/auth/callback", "scope": "name email"}',
  NOW(),
  NOW()
) ON CONFLICT (id) DO UPDATE SET
  config = EXCLUDED.config,
  updated_at = NOW();

-- 3. Verify setup
SELECT * FROM auth.providers WHERE name = 'apple';
