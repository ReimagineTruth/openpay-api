-- Quick verification script for transfer functionality
-- Run this to verify all components are in place

-- Check if required tables exist
SELECT 
    'Tables Check' as check_type,
    table_name,
    EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = t.table_name
    ) as exists
FROM (VALUES 
    ('merchant_balance_transfers'),
    ('user_dashboard_preferences'),
    ('merchant_activity'),
    ('wallets'),
    ('supported_currencies')
) AS t(table_name);

-- Check if required functions exist
SELECT 
    'Functions Check' as check_type,
    routine_name,
    EXISTS (
        SELECT 1 FROM information_schema.routines 
        WHERE routine_schema = 'public' 
        AND routine_name = f.routine_name
    ) as exists
FROM (VALUES 
    ('transfer_my_personal_wallet_to_merchant'),
    ('get_my_dashboard_preferences'),
    ('update_my_dashboard_preferences'),
    ('get_my_merchant_transfer_history')
) AS f(routine_name);

-- Check if transfer_type column exists in merchant_balance_transfers
SELECT 
    'Column Check' as check_type,
    'transfer_type column in merchant_balance_transfers' as description,
    EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'merchant_balance_transfers'
        AND column_name = 'transfer_type'
    ) as exists;

-- Test function signature (this should work if function exists)
SELECT 
    'Function Signature Test' as check_type,
    proname as function_name,
    proargtypes as argument_types
FROM pg_proc 
WHERE proname = 'transfer_my_personal_wallet_to_merchant'
  AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
