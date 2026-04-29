// Verification script for Pi Network environment variables
// Run this script to verify that all environment variables are properly configured

const verifyPiEnvironment = async () => {
  console.log('🔍 Verifying Pi Network Environment Variables...\n');

  try {
    // Test 1: Check Edge Function deployment
    console.log('1️⃣ Checking Edge Function deployment...');
    const response = await fetch('/functions/v1/pi-withdrawal', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${localStorage.getItem('supabase_token')}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        amount: 0.01,
        memo: 'Environment verification test'
      })
    });

    const responseText = await response.text();
    console.log('Response status:', response.status);
    console.log('Response text:', responseText);

    if (!response.ok) {
      const errorData = JSON.parse(responseText);
      
      if (errorData.error === 'Pi Network credentials not configured') {
        console.log('❌ Pi Network credentials not configured in Edge Function');
        console.log('\n🔧 To fix this issue:');
        console.log('1. Run the deployment script:');
        console.log('   - PowerShell: .\\deploy-pi-env.ps1');
        console.log('   - Bash: ./deploy-pi-env.sh');
        console.log('2. Or manually set secrets:');
        console.log('   supabase secrets set PI_API_KEY="fudrvmlzm7ucqu94smlgeudrryccqxpymkr1vqk6nw0yoli8ikirbzrn9siv4hi9"');
        console.log('   supabase secrets set PI_WALLET_PRIVATE_SEED="SDZWK2Z4JA3KTQIGAEUSKWFLZBDILJAWLUNAUFHURFIF5BWNNH3PB5Y3"');
        console.log('3. Deploy the Edge Function:');
        console.log('   supabase functions deploy pi-withdrawal');
        return false;
      }
      
      console.log('❌ Edge Function error:', errorData.error);
      return false;
    }

    const data = JSON.parse(responseText);
    console.log('✅ Edge Function is working correctly!');
    console.log(`📝 Payment ID: ${data.paymentId}`);
    console.log(`🔗 Transaction ID: ${data.txid}`);
    console.log(`💰 Amount processed: ${data.amount || '0.01'} PI`);
    
    if (data.newBalance !== undefined) {
      console.log(`📊 New balance: ${data.newBalance} PI`);
    }

    console.log('\n🎉 All environment variables are properly configured!');
    console.log('\n📋 Verification Summary:');
    console.log('✅ PI_API_KEY: Configured');
    console.log('✅ PI_WALLET_PRIVATE_SEED: Configured');
    console.log('✅ Edge Function: Deployed and working');
    console.log('✅ Pi Network SDK: Initialized successfully');
    console.log('✅ A2U Flow: Working correctly');

    return true;

  } catch (error) {
    console.error('❌ Verification failed:', error.message);
    console.log('\n🔧 Troubleshooting steps:');
    console.log('1. Check if you are logged in to Supabase');
    console.log('2. Verify Edge Function is deployed: supabase functions list');
    console.log('3. Check environment variables: supabase secrets list');
    console.log('4. Check Edge Function logs: supabase functions logs pi-withdrawal');
    return false;
  }
};

// Function to check environment variables status
const checkEnvStatus = async () => {
  console.log('🔍 Checking environment variables status...\n');
  
  try {
    // This will show the logs from the Edge Function
    const response = await fetch('/functions/v1/pi-withdrawal', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${localStorage.getItem('supabase_token')}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        amount: 0.001,
        memo: 'Environment status check'
      })
    });

    const responseText = await response.text();
    
    // Look for environment variable status in the logs
    if (responseText.includes('PI_API_KEY') && responseText.includes('PI_WALLET_PRIVATE_SEED')) {
      console.log('✅ Environment variables are being checked in Edge Function');
      
      if (responseText.includes('environment')) {
        console.log('✅ Environment variables are set from environment');
      } else {
        console.log('⚠️ Using fallback values - environment variables not set');
      }
    } else {
      console.log('❌ Cannot determine environment variable status');
    }
    
  } catch (error) {
    console.error('❌ Status check failed:', error.message);
  }
};

// Auto-run verification if in browser environment
if (typeof window !== 'undefined') {
  // Add verification button to page
  const verifyButton = document.createElement('button');
  verifyButton.textContent = '🔍 Verify Pi Environment';
  verifyButton.style.cssText = `
    position: fixed;
    top: 20px;
    left: 20px;
    background: #2196F3;
    color: white;
    border: none;
    padding: 10px 20px;
    border-radius: 5px;
    cursor: pointer;
    z-index: 9999;
    font-weight: bold;
  `;
  
  verifyButton.onclick = verifyPiEnvironment;
  document.body.appendChild(verifyButton);
  
  // Add status check button
  const statusButton = document.createElement('button');
  statusButton.textContent = '📊 Check Env Status';
  statusButton.style.cssText = `
    position: fixed;
    top: 70px;
    left: 20px;
    background: #FF9800;
    color: white;
    border: none;
    padding: 10px 20px;
    border-radius: 5px;
    cursor: pointer;
    z-index: 9999;
    font-weight: bold;
  `;
  
  statusButton.onclick = checkEnvStatus;
  document.body.appendChild(statusButton);
  
  console.log('🔍 Pi Environment Verification:');
  console.log('- Click "Verify Pi Environment" to test complete setup');
  console.log('- Click "Check Env Status" to check environment variable status');
  console.log('- Or run verifyPiEnvironment() in console');
}

// Export for Node.js testing
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { verifyPiEnvironment, checkEnvStatus };
}
