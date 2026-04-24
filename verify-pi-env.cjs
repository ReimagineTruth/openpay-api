/**
 * Pi Network Environment Verification Script
 * Run this script to verify that Pi Network environment variables are properly configured
 */

// Load environment variables from .env file
require('dotenv').config();

console.log('=== Pi Network Environment Verification ===\n');

// Check required environment variables
const requiredVars = [
  {
    name: 'PI_API_KEY',
    description: 'Pi Network API Key',
    required: true
  },
  {
    name: 'VITE_PI_WALLET_PRIVATE_SEED', 
    description: 'Pi Network Wallet Private Seed',
    required: true,
    pattern: /^S/
  },
  {
    name: 'VITE_PI_SANDBOX',
    description: 'Pi Network Sandbox Mode',
    required: false,
    defaultValue: 'false'
  }
];

let allConfigured = true;

requiredVars.forEach(({ name, description, required, pattern, defaultValue }) => {
  const value = process.env[name];
  const isSet = value !== undefined && value !== '';
  
  console.log(`${name}:`);
  console.log(`  Description: ${description}`);
  console.log(`  Status: ${isSet ? '✅ SET' : '❌ NOT SET'}`);
  
  if (isSet) {
    if (name === 'VITE_PI_WALLET_PRIVATE_SEED') {
      const startsWithS = value.startsWith('S');
      const length = value.length;
      console.log(`  Starts with 'S': ${startsWithS ? '✅ YES' : '❌ NO'}`);
      console.log(`  Length: ${length} characters`);
      console.log(`  Preview: ${value.substring(0, 10)}...${value.substring(value.length - 5)}`);
    } else if (name === 'PI_API_KEY') {
      console.log(`  Preview: ${value.substring(0, 10)}...${value.substring(value.length - 5)}`);
    } else {
      console.log(`  Value: ${value}`);
    }
  } else if (required) {
    console.log(`  ⚠️  REQUIRED: This variable must be set for Pi Network withdrawals to work`);
    allConfigured = false;
  } else if (defaultValue) {
    console.log(`  Default: ${defaultValue}`);
  }
  console.log('');
});

// Summary
console.log('=== Summary ===');
if (allConfigured) {
  console.log('✅ All required Pi Network environment variables are configured!');
  console.log('🎉 Pi Network withdrawal service should work properly.');
} else {
  console.log('❌ Some required environment variables are missing.');
  console.log('📝 Please update your .env file with the missing variables.');
  console.log('');
  console.log('Example .env configuration:');
  console.log('PI_API_KEY="your_actual_pi_api_key_here"');
  console.log('VITE_PI_WALLET_PRIVATE_SEED="S_YOUR_ACTUAL_WALLET_PRIVATE_SEED"');
  console.log('VITE_PI_SANDBOX="false"');
}

// Check if .env file exists
const fs = require('fs');
const envPath = '.env';
if (fs.existsSync(envPath)) {
  console.log(`\n✅ .env file exists at: ${envPath}`);
} else {
  console.log(`\n❌ .env file not found at: ${envPath}`);
  console.log('📝 Please copy .env.example to .env and configure your variables');
}

console.log('\n=== Pi Network Configuration Complete ===');
