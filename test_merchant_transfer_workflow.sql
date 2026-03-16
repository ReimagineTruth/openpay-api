-- Test script for Transfer to Merchant Wallet Workflow
-- This script tests the complete functionality of the merchant transfer feature

-- Test 1: Verify dashboard preferences table exists and has data
SELECT 
    'Dashboard Preferences Table Check' as test_name,
    COUNT(*) as preference_count,
    COUNT(DISTINCT user_id) as unique_users
FROM public.user_dashboard_preferences;

-- Test 2: Verify merchant_balance_transfers has the transfer_type column
SELECT 
    'Transfer Type Column Check' as test_name,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'merchant_balance_transfers' 
    AND column_name = 'transfer_type';

-- Test 3: Test the transfer function with a small amount (this will fail if user doesn't exist, but that's expected)
-- Note: This test requires an authenticated user session to run properly
-- SELECT public.transfer_my_personal_wallet_to_merchant(1.00, 'sandbox', 'Test transfer');

-- Test 4: Verify RPC functions exist and have proper permissions
SELECT 
    'RPC Functions Check' as test_name,
    routine_name,
    security_type
FROM information_schema.routines 
WHERE routine_schema = 'public' 
    AND routine_name IN (
        'transfer_my_personal_wallet_to_merchant',
        'get_my_dashboard_preferences', 
        'update_my_dashboard_preferences',
        'get_my_merchant_transfer_history'
    )
    AND routine_type = 'FUNCTION';

-- Test 5: Check merchant_balance_transfers table structure
SELECT 
    'Merchant Balance Transfers Structure' as test_name,
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns 
WHERE table_name = 'merchant_balance_transfers'
ORDER BY ordinal_position;

-- Test 6: Verify RLS policies are in place
SELECT 
    'RLS Policies Check' as test_name,
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual
FROM pg_policies 
WHERE tablename IN ('user_dashboard_preferences', 'merchant_balance_transfers')
ORDER BY tablename, policyname;

-- Test 7: Test dashboard preferences function (requires authenticated user)
-- SELECT * FROM public.get_my_dashboard_preferences();

-- Test 8: Check if supported_currencies table exists for currency conversion
SELECT 
    'Supported Currencies Check' as test_name,
    EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_name = 'supported_currencies' 
        AND table_schema = 'public'
    ) as table_exists;

-- Test 9: Verify merchant_activity table exists for activity tracking
SELECT 
    'Merchant Activity Table Check' as test_name,
    EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_name = 'merchant_activity' 
        AND table_schema = 'public'
    ) as table_exists;

-- Test 10: Sample data validation (if any transfers exist)
SELECT 
    'Sample Transfer Data' as test_name,
    COUNT(*) as transfer_count,
    SUM(amount) as total_amount,
    COUNT(DISTINCT merchant_user_id) as unique_merchants
FROM public.merchant_balance_transfers
WHERE created_at >= CURRENT_DATE - INTERVAL '7 days';

-- Instructions for manual testing:
/*
1. Run the SQL migration first: 20260316060000_complete_merchant_transfer_workflow.sql
2. Verify all tables and functions exist using the queries above
3. Test the UI workflow:
   - Login as a user with sufficient wallet balance
   - Navigate to Dashboard
   - The "Transfer to Merchant Wallet" feature should be visible
   - Enter an amount and click "Transfer to Merchant"
   - Verify the transfer completes successfully
   - Check that transfer history appears
   - Hide the feature using the EyeOff button
   - Verify it appears in the "Hidden Features" section
   - Re-enable it from the hidden features section
4. Test edge cases:
   - Insufficient balance
   - Invalid amounts (negative, zero)
   - Empty amount field
   - Network errors
5. Verify database records:
   - Check merchant_balance_transfers table for new records
   - Check merchant_activity table for activity logs
   - Check user_dashboard_preferences for preference updates
*/
