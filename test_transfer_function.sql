-- Test script to verify the transfer function works
-- Run this after applying the fix_transfer_schema_cache.sql script

-- Test 1: Check if function exists and has correct signature
SELECT 
  proname as function_name,
  pg_get_function_arguments(oid) as arguments,
  pg_get_function_result(oid) as return_type
FROM pg_proc 
WHERE proname = 'transfer_my_personal_wallet_to_merchant' 
  AND pronamespace = 'public'::regnamespace;

-- Test 2: Check if required tables exist
SELECT 
  'merchant_balance_transfers' as table_name,
  EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'merchant_balance_transfers' AND table_schema = 'public') as exists
UNION ALL
SELECT 
  'merchant_activity' as table_name,
  EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'merchant_activity' AND table_schema = 'public') as exists
UNION ALL
SELECT 
  'wallets' as table_name,
  EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'wallets' AND table_schema = 'public') as exists
UNION ALL
SELECT 
  'merchant_payments' as table_name,
  EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'merchant_payments' AND table_schema = 'public') as exists
UNION ALL
SELECT 
  'supported_currencies' as table_name,
  EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'supported_currencies' AND table_schema = 'public') as exists;

-- Test 3: Check function permissions
SELECT 
  grantee,
  privilege_type,
  is_grantable
FROM information_schema.role_routine_grants 
WHERE routine_name = 'transfer_my_personal_wallet_to_merchant'
  AND routine_schema = 'public';
