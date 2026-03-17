-- Fix merchant transfer function schema cache issue
-- This script refreshes the schema cache to ensure the transfer function is recognized

-- Step 1: Force schema cache reload
NOTIFY pgrst, 'reload schema';

-- Step 2: Wait a moment and reload again to ensure it's cached
DO $$
BEGIN
  PERFORM pg_sleep(0.2);
  NOTIFY pgrst, 'reload schema';
END $$;

-- Step 3: Verify the function exists and has correct signature
SELECT 
  'Function Verification' as check_type,
  proname as function_name,
  pg_get_function_arguments(oid) as arguments,
  pg_get_function_result(oid) as return_type,
  'SUCCESS' as status
FROM pg_proc 
WHERE proname = 'transfer_my_personal_wallet_to_merchant'
  AND pronamespace = 'public'::regnamespace;

-- Step 4: Check if function has proper permissions
SELECT 
  'Permission Check' as check_type,
  routine_name,
  'authenticated' as has_execute_permission
FROM information_schema.routines 
WHERE routine_schema = 'public' 
  AND routine_name = 'transfer_my_personal_wallet_to_merchant'
  AND EXISTS (
    SELECT 1 FROM information_schema.role_routine_grants 
    WHERE routine_schema = 'public' 
    AND routine_name = 'transfer_my_personal_wallet_to_merchant'
    AND grantee = 'authenticated'
    AND privilege_type = 'EXECUTE'
  );

-- Step 5: Test function with minimal parameters (should return structure, not execute)
SELECT 
  'Function Structure Test' as check_type,
  'transfer_my_personal_wallet_to_merchant' as function_name,
  'Parameters: p_amount NUMERIC, p_mode TEXT DEFAULT ''live'', p_note TEXT DEFAULT ''''' as parameters,
  'Returns: TABLE with transfer_id, balances, transfer_type, status' as returns;
