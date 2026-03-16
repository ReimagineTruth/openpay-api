-- Quick test to verify the transfer function is working
-- Run this after applying the migration

-- Test 1: Check if function exists
SELECT 
  'Function exists check' as test_name,
  CASE 
    WHEN COUNT(*) > 0 THEN 'PASS'
    ELSE 'FAIL'
  END as status
FROM pg_proc 
WHERE proname = 'transfer_my_personal_wallet_to_merchant' 
  AND pronamespace = 'public'::regnamespace;

-- Test 2: Check function signature
SELECT 
  'Function signature check' as test_name,
  pg_get_function_arguments(oid) as arguments,
  pg_get_function_result(oid) as return_type
FROM pg_proc 
WHERE proname = 'transfer_my_personal_wallet_to_merchant' 
  AND pronamespace = 'public'::regnamespace;

-- Test 3: Check permissions
SELECT 
  'Permissions check' as test_name,
  grantee,
  privilege_type
FROM information_schema.role_routine_grants 
WHERE routine_name = 'transfer_my_personal_wallet_to_merchant'
  AND routine_schema = 'public';

-- Test 4: Check required tables
SELECT 
  table_name,
  CASE 
    WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = t.table_name AND table_schema = 'public') THEN 'EXISTS'
    ELSE 'MISSING'
  END as status
FROM (VALUES 
  ('wallets'),
  ('merchant_balance_transfers'),
  ('merchant_activity'),
  ('merchant_payments'),
  ('supported_currencies')
) AS t(table_name);
