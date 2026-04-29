#!/bin/bash

# Deployment script for Pi Network environment variables
# Run this script to set up all required environment variables for Supabase Edge Functions

echo "🚀 Setting up Pi Network environment variables for Supabase Edge Functions..."

# Check if supabase CLI is installed
if ! command -v supabase &> /dev/null; then
    echo "❌ Supabase CLI not found. Please install it first:"
    echo "npm install -g supabase"
    exit 1
fi

echo "📝 Setting Pi Network credentials..."

# Core Pi Network credentials
echo "Setting PI_API_KEY..."
supabase secrets set PI_API_KEY="fudrvmlzm7ucqu94smlgeudrryccqxpymkr1vqk6nw0yoli8ikirbzrn9siv4hi9"

echo "Setting PI_WALLET_PRIVATE_SEED..."
supabase secrets set PI_WALLET_PRIVATE_SEED="SDZWK2Z4JA3KTQIGAEUSKWFLZBDILJAWLUNAUFHURFIF5BWNNH3PB5Y3"

# Pi Network Horizon configuration
echo "Setting PI_BACKEND_HORIZON_MAINNET_URL..."
supabase secrets set PI_BACKEND_HORIZON_MAINNET_URL="https://api.mainnet.minepi.com"

echo "Setting PI_BACKEND_HORIZON_MAINNET_PASSPHRASE..."
supabase secrets set PI_BACKEND_HORIZON_MAINNET_PASSPHRASE="Pi Network"

echo "Setting PI_BACKEND_HORIZON_TESTNET_URL..."
supabase secrets set PI_BACKEND_HORIZON_TESTNET_URL="https://api.testnet.minepi.com"

echo "Setting PI_BACKEND_HORIZON_TESTNET_PASSPHRASE..."
supabase secrets set PI_BACKEND_HORIZON_TESTNET_PASSPHRASE="Pi Testnet"

echo "Setting PI_BACKEND_PLATFORM_BASE_URL..."
supabase secrets set PI_BACKEND_PLATFORM_BASE_URL="https://api.minepi.com"

echo "✅ All Pi Network environment variables set successfully!"

# Verify the secrets were set
echo ""
echo "🔍 Verifying environment variables..."
supabase secrets list

echo ""
echo "🎯 Next steps:"
echo "1. Deploy the Edge Function: supabase functions deploy pi-withdrawal"
echo "2. Test the withdrawal functionality"
echo "3. Check logs: supabase functions logs pi-withdrawal"

echo ""
echo "🚀 Pi Network environment setup complete!"
