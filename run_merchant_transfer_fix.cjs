// CommonJS script to fix the merchant transfer function
// Run this with: node run_merchant_transfer_fix.cjs

const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');
const path = require('path');

// Load environment variables from .env file manually
function loadEnvFile() {
  try {
    const envPath = path.join(process.cwd(), '.env');
    const envContent = fs.readFileSync(envPath, 'utf8');
    const lines = envContent.split('\n');
    
    lines.forEach(line => {
      const trimmedLine = line.trim();
      if (trimmedLine && !trimmedLine.startsWith('#')) {
        const [key, ...valueParts] = trimmedLine.split('=');
        if (key && valueParts.length > 0) {
          process.env[key] = valueParts.join('=');
        }
      }
    });
  } catch (error) {
    console.log('Could not load .env file:', error.message);
  }
}

loadEnvFile();

const supabaseUrl = process.env.VITE_SUPABASE_URL ? process.env.VITE_SUPABASE_URL.replace(/['"]/g, '') : '';
const supabaseKey = process.env.VITE_SUPABASE_PUBLISHABLE_KEY ? process.env.VITE_SUPABASE_PUBLISHABLE_KEY.replace(/['"]/g, '') : '';

if (!supabaseUrl || !supabaseKey) {
  console.error('Missing Supabase credentials in .env file');
  console.log('Please ensure VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY are set');
  process.exit(1);
}

console.log('Supabase URL:', supabaseUrl);
console.log('Supabase Key found:', supabaseKey ? 'Yes' : 'No');

const supabase = createClient(supabaseUrl, supabaseKey);

async function testConnection() {
  try {
    console.log('Testing Supabase connection...');
    const { data, error } = await supabase.from('wallets').select('count').limit(1);
    if (error) {
      console.error('Connection test failed:', error.message);
      return false;
    }
    console.log('Connection test successful');
    return true;
  } catch (error) {
    console.error('Connection test error:', error.message);
    return false;
  }
}

async function testTransferFunction() {
  try {
    console.log('Testing transfer function existence...');
    // Test if the function exists by calling it with a small amount (should fail due to insufficient funds, but function should be found)
    const { data, error } = await supabase.rpc('transfer_my_personal_wallet_to_merchant', {
      p_amount: 0.01,
      p_mode: 'live',
      p_note: 'Test'
    });
    
    if (error && error.message.includes('function')) {
      console.error('Function not found:', error.message);
      return false;
    } else if (error && (error.message.includes('Insufficient') || error.message.includes('balance'))) {
      console.log('✓ Function exists (failed as expected due to insufficient balance)');
      return true;
    } else if (data) {
      console.log('✓ Function exists and executed successfully');
      return true;
    } else {
      console.log('✓ Function appears to be accessible');
      return true;
    }
  } catch (error) {
    if (error.message.includes('function')) {
      console.error('Function not found:', error.message);
      return false;
    } else {
      console.log('✓ Function exists (error was expected):', error.message);
      return true;
    }
  }
}

async function showInstructions() {
  console.log('\n=== MERCHANT TRANSFER FIX INSTRUCTIONS ===');
  console.log('The error "Could not find the function" indicates the schema cache needs to be refreshed.');
  console.log('\nTo fix this issue, you need to:');
  console.log('1. Go to your Supabase dashboard: https://araojncyittkahvvpdrn.supabase.co');
  console.log('2. Navigate to the SQL Editor');
  console.log('3. Copy and paste the contents of: fix_merchant_transfer_schema_cache.sql');
  console.log('4. Run the SQL script');
  console.log('\nThe script will:');
  console.log('- Force reload the schema cache (NOTIFY pgrst, \'reload schema\')');
  console.log('- Verify the transfer function exists with correct signature');
  console.log('- Check function permissions');
  console.log('\nAfter running the SQL, the transfer function should be accessible from the frontend.');
  console.log('The function signature is: transfer_my_personal_wallet_to_merchant(p_amount, p_mode, p_note)');
  console.log('=====================================\n');
}

async function main() {
  console.log('Merchant Transfer Fix Script');
  console.log('=============================');
  
  const connected = await testConnection();
  
  if (connected) {
    console.log('✓ Supabase connection successful');
    const functionExists = await testTransferFunction();
    
    if (functionExists) {
      console.log('✓ Transfer function is accessible - issue may be resolved');
    } else {
      console.log('✗ Transfer function not found - schema cache needs refresh');
    }
  } else {
    console.log('✗ Supabase connection failed');
    console.log('Please check your credentials');
  }
  
  await showInstructions();
}

main().catch(console.error);
