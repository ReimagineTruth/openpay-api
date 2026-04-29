# Pi Network A2U Withdrawal Deployment Guide

## Overview
This guide will help you deploy the complete Pi Network A2U (App-to-User) withdrawal system that has been implemented following the official Pi Node.js SDK documentation.

## Prerequisites
- Supabase project with appropriate permissions
- Pi Network API credentials (API Key and Wallet Private Seed)
- Node.js and npm installed locally
- Supabase CLI installed (`npm install -g supabase`)

## Step 1: Deploy Database Schema

Run the complete SQL schema to create all necessary tables and functions:

```sql
-- Execute the pi-withdrawal-complete-schema.sql file in your Supabase project
-- You can do this via:
-- 1. Supabase Dashboard > SQL Editor
-- 2. Supabase CLI: supabase db push
-- 3. psql command line
```

The schema includes:
- `pi_withdrawals` table for withdrawal tracking
- `user_pi_balances` table for balance management
- `pi_transaction_log` table for audit trails
- RPC functions for balance checking and history
- Database triggers for automatic balance updates
- Row Level Security (RLS) policies

## Step 2: Deploy Edge Function

Deploy the Pi withdrawal Edge Function:

```bash
# Deploy the function
npx supabase functions deploy pi-withdrawal

# Or using Supabase CLI
supabase functions deploy pi-withdrawal
```

## Step 3: Configure Environment Variables

Set the required environment variables in your Supabase project:

### Via Supabase Dashboard:
1. Go to Project Settings > Edge Functions
2. Add these secrets:

**Required Pi Network Variables:**
- `PI_API_KEY`: `fudrvmlzm7ucqu94smlgeudrryccqxpymkr1vqk6nw0yoli8ikirbzrn9siv4hi9`
- `PI_WALLET_PRIVATE_SEED`: `SDZWK2Z4JA3KTQIGAEUSKWFLZBDILJAWLUNAUFHURFIF5BWNNH3PB5Y3`

**Pi Network Horizon Configuration:**
- `PI_BACKEND_HORIZON_MAINNET_URL`: `https://api.mainnet.minepi.com`
- `PI_BACKEND_HORIZON_MAINNET_PASSPHRASE`: `Pi Network`
- `PI_BACKEND_HORIZON_TESTNET_URL`: `https://api.testnet.minepi.com`
- `PI_BACKEND_HORIZON_TESTNET_PASSPHRASE`: `Pi Testnet`
- `PI_BACKEND_PLATFORM_BASE_URL`: `https://api.minepi.com`

### Via CLI:
```bash
# Core Pi Network credentials
supabase secrets set PI_API_KEY="fudrvmlzm7ucqu94smlgeudrryccqxpymkr1vqk6nw0yoli8ikirbzrn9siv4hi9"
supabase secrets set PI_WALLET_PRIVATE_SEED="SDZWK2Z4JA3KTQIGAEUSKWFLZBDILJAWLUNAUFHURFIF5BWNNH3PB5Y3"

# Horizon configuration
supabase secrets set PI_BACKEND_HORIZON_MAINNET_URL="https://api.mainnet.minepi.com"
supabase secrets set PI_BACKEND_HORIZON_MAINNET_PASSPHRASE="Pi Network"
supabase secrets set PI_BACKEND_HORIZON_TESTNET_URL="https://api.testnet.minepi.com"
supabase secrets set PI_BACKEND_HORIZON_TESTNET_PASSPHRASE="Pi Testnet"
supabase secrets set PI_BACKEND_PLATFORM_BASE_URL="https://api.minepi.com"
```

## Step 4: Verify Pi Network Credentials

Ensure you have valid Pi Network credentials:

1. **API Key**: Get from your Pi Network developer dashboard
2. **Wallet Private Seed**: 
   - Must start with 'S'
   - Should be kept secure and never exposed in frontend
   - Generate from your Pi Network app wallet

## Step 5: Test the Implementation

### Test Balance Checking:
```javascript
// In browser console on your withdrawal page
const { data } = await supabase.rpc('get_user_pi_balance');
console.log(data);
```

### Test Withdrawal Flow:
1. Navigate to `/pi-withdrawal` in your app
2. Enter a test amount (e.g., 1 PI)
3. Add a memo
4. Click "Withdraw"
5. Check browser console for any errors
6. Check Edge Function logs in Supabase Dashboard

## Step 6: Monitor and Debug

### Check Edge Function Logs:
```bash
# View function logs
supabase functions logs pi-withdrawal
```

### Common Issues and Solutions:

#### Issue: "Failed to send a request to the Edge Function"
**Solution**: 
- Ensure the Edge Function is deployed: `supabase functions list`
- Check function logs for errors
- Verify environment variables are set

#### Issue: "Pi Network credentials not configured"
**Solution**:
- Verify environment variables are set correctly
- Check that the wallet private seed starts with 'S'
- Ensure API key is valid and not expired

#### Issue: "Insufficient balance" errors
**Solution**:
- Check that user has balance in `user_pi_balances` table
- Verify database triggers are working correctly
- Check for frozen funds from pending withdrawals

#### Issue: "Daily withdrawal limit exceeded"
**Solution**:
- Check `daily_withdrawal_limit` in `user_pi_balances` table
- Verify `daily_reset_at` timestamp is correct
- Manual reset: `UPDATE user_pi_balances SET daily_withdrawn = 0 WHERE user_uid = 'user_id';`

## Step 7: Production Considerations

### Security:
- Never expose Pi Network credentials in frontend code
- Use Supabase RLS policies properly
- Monitor Edge Function logs for suspicious activity

### Performance:
- Monitor database performance with withdrawal volume
- Consider caching balance checks for high-traffic apps
- Implement rate limiting on Edge Function if needed

### Monitoring:
- Set up alerts for failed withdrawals
- Monitor Pi Network API rate limits
- Track withdrawal success rates

## Step 8: Replace Mock Implementation (Optional)

The current Edge Function uses the real Pi Network SDK. If you need to test without real Pi transactions, you can temporarily replace the implementation with the mock version:

```typescript
// In supabase/functions/pi-withdrawal/index.ts
// Replace the PiNetwork initialization with mock for testing
```

## Troubleshooting Checklist

- [ ] Database schema deployed successfully
- [ ] Edge Function deployed without errors
- [ ] Environment variables set correctly
- [ ] Pi Network credentials are valid
- [ ] User has proper balance in database
- [ ] RLS policies are working
- [ ] Edge Function logs show no errors
- [ ] Frontend can call RPC functions
- [ ] Withdrawal flow completes successfully

## Support

If you encounter issues:

1. Check Supabase Edge Function logs
2. Verify Pi Network API status
3. Review database schema deployment
4. Test individual components separately
5. Check environment variable configuration

## Next Steps

After successful deployment:
1. Monitor withdrawal activity
2. Set up automated testing
3. Implement additional error handling
4. Add withdrawal notifications
5. Consider implementing withdrawal limits and cooldowns
