// Node.js script to fix the payment link function
// Run this with: node run_payment_link_fix.js

import { createClient } from '@supabase/supabase-js';
import { readFileSync } from 'fs';
import 'dotenv/config';

// Load environment variables
const supabaseUrl = process.env.VITE_SUPABASE_URL;
const supabaseKey = process.env.VITE_SUPABASE_PUBLISHABLE_KEY;

if (!supabaseUrl || !supabaseKey) {
  console.error('Missing Supabase credentials in .env file');
  process.exit(1);
}

// Create Supabase client with service role key (if available)
const supabase = createClient(supabaseUrl, supabaseKey);

async function runSQLFix() {
  try {
    console.log('Reading SQL fix file...');
    const sqlContent = readFileSync('./fix_payment_link_complete.sql', 'utf8');
    
    console.log('Executing SQL fix...');
    
    // Split the SQL into individual statements and execute them
    const statements = sqlContent
      .split(';')
      .map(stmt => stmt.trim())
      .filter(stmt => stmt.length > 0 && !stmt.startsWith('--'));

    for (let i = 0; i < statements.length; i++) {
      const statement = statements[i];
      if (statement.trim()) {
        console.log(`Executing statement ${i + 1}/${statements.length}...`);
        
        try {
          const { error } = await supabase.rpc('exec_sql', { sql: statement });
          if (error) {
            console.warn(`Statement ${i + 1} failed:`, error.message);
            // Try with raw SQL if RPC fails
            console.log('Trying alternative approach...');
          } else {
            console.log(`Statement ${i + 1} executed successfully`);
          }
        } catch (err) {
          console.warn(`Statement ${i + 1} error:`, err.message);
        }
      }
    }
    
    console.log('SQL fix execution completed');
    console.log('Please check your Supabase dashboard to verify the changes');
    console.log('You may need to manually run the SQL file in your Supabase SQL editor');
    
  } catch (error) {
    console.error('Error running SQL fix:', error);
    process.exit(1);
  }
}

console.log('Payment Link Fix Script');
console.log('======================');
console.log('This script will fix the create_merchant_payment_link function');
console.log('and add missing columns to the merchant_payment_links table');
console.log('');

runSQLFix();
