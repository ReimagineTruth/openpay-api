# PowerShell script for Pi Network environment variables deployment
# Run this script to set up all required environment variables for Supabase Edge Functions

Write-Host "🚀 Setting up Pi Network environment variables for Supabase Edge Functions..." -ForegroundColor Green

# Check if supabase CLI is installed
try {
    $supabaseVersion = supabase --version
    Write-Host "✅ Supabase CLI found: $supabaseVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ Supabase CLI not found. Please install it first:" -ForegroundColor Red
    Write-Host "npm install -g supabase" -ForegroundColor Yellow
    exit 1
}

Write-Host "`n📝 Setting Pi Network credentials..." -ForegroundColor Cyan

# Core Pi Network credentials
Write-Host "Setting PI_API_KEY..." -ForegroundColor Yellow
supabase secrets set PI_API_KEY="fudrvmlzm7ucqu94smlgeudrryccqxpymkr1vqk6nw0yoli8ikirbzrn9siv4hi9"

Write-Host "Setting PI_WALLET_PRIVATE_SEED..." -ForegroundColor Yellow
supabase secrets set PI_WALLET_PRIVATE_SEED="SDZWK2Z4JA3KTQIGAEUSKWFLZBDILJAWLUNAUFHURFIF5BWNNH3PB5Y3"

# Pi Network Horizon configuration
Write-Host "Setting PI_BACKEND_HORIZON_MAINNET_URL..." -ForegroundColor Yellow
supabase secrets set PI_BACKEND_HORIZON_MAINNET_URL="https://api.mainnet.minepi.com"

Write-Host "Setting PI_BACKEND_HORIZON_MAINNET_PASSPHRASE..." -ForegroundColor Yellow
supabase secrets set PI_BACKEND_HORIZON_MAINNET_PASSPHRASE="Pi Network"

Write-Host "Setting PI_BACKEND_HORIZON_TESTNET_URL..." -ForegroundColor Yellow
supabase secrets set PI_BACKEND_HORIZON_TESTNET_URL="https://api.testnet.minepi.com"

Write-Host "Setting PI_BACKEND_HORIZON_TESTNET_PASSPHRASE..." -ForegroundColor Yellow
supabase secrets set PI_BACKEND_HORIZON_TESTNET_PASSPHRASE="Pi Testnet"

Write-Host "Setting PI_BACKEND_PLATFORM_BASE_URL..." -ForegroundColor Yellow
supabase secrets set PI_BACKEND_PLATFORM_BASE_URL="https://api.minepi.com"

Write-Host "✅ All Pi Network environment variables set successfully!" -ForegroundColor Green

# Verify the secrets were set
Write-Host "`n🔍 Verifying environment variables..." -ForegroundColor Cyan
supabase secrets list

Write-Host "`n🎯 Next steps:" -ForegroundColor Magenta
Write-Host "1. Deploy the Edge Function: supabase functions deploy pi-withdrawal" -ForegroundColor White
Write-Host "2. Test the withdrawal functionality" -ForegroundColor White
Write-Host "3. Check logs: supabase functions logs pi-withdrawal" -ForegroundColor White

Write-Host "`n🚀 Pi Network environment setup complete!" -ForegroundColor Green
