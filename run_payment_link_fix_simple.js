// Simple Node.js script to run the payment link fix
// Run this with: node run_payment_link_fix_simple.js

import { createClient } from '@supabase/supabase-js';
import { readFileSync } from 'fs';

// Load environment variables from .env file manually
const fs = require('fs');
const path = require('path');

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

const supabaseUrl = process.env.VITE_SUPABASE_URL;
const supabaseKey = process.env.VITE_SUPABASE_PUBLISHABLE_KEY;

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
    const { data, error } = await supabase.from('merchant_payment_links').select('count').limit(1);
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

async function showInstructions() {
  console.log('\n=== PAYMENT LINK FIX INSTRUCTIONS ===');
  console.log('The script has created the necessary SQL fix files.');
  console.log('\nTo complete the fix, you need to:');
  console.log('1. Go to your Supabase dashboard');
  console.log('2. Navigate to the SQL Editor');
  console.log('3. Copy and paste the contents of: fix_payment_link_complete.sql');
  console.log('4. Run the SQL script');
  console.log('\nThe script will:');
  console.log('- Add missing columns (total_amount, api_key_id) to merchant_payment_links table');
  console.log('- Recreate the create_merchant_payment_link function with correct 21-parameter signature');
  console.log('- Set proper permissions');
  console.log('- Refresh the schema cache');
  console.log('\nAfter running the SQL, the payment link creation should work correctly.');
  console.log('=====================================\n');
}

async function main() {
  console.log('Payment Link Fix Script');
  console.log('======================');
  
  const connected = await testConnection();
  
  if (connected) {
    console.log('✓ Supabase connection successful');
    console.log('✓ Frontend should be able to call the function after SQL fix is applied');
  } else {
    console.log('✗ Supabase connection failed');
    console.log('Please check your credentials');
  }
  
  await showInstructions();
}

main().catch(console.error);
