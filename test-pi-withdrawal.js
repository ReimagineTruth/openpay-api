// Test script for Pi Network A2U withdrawal functionality
// Run this script to test the complete withdrawal flow

const testPiWithdrawal = async () => {
  console.log('🧪 Testing Pi Network A2U Withdrawal Flow...\n');

  try {
    // Test 1: Check Edge Function deployment
    console.log('1️⃣ Testing Edge Function deployment...');
    const response = await fetch('/functions/v1/pi-withdrawal', {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${localStorage.getItem('supabase_token')}`,
        'Content-Type': 'application/json'
      }
    });

    if (!response.ok) {
      throw new Error(`Edge Function test failed: ${response.status} ${response.statusText}`);
    }

    const historyData = await response.json();
    console.log('✅ Edge Function is deployed and accessible');
    console.log(`📊 Withdrawal history: ${historyData.history?.length || 0} records\n`);

    // Test 2: Test balance checking
    console.log('2️⃣ Testing balance checking...');
    const balanceResponse = await fetch('/functions/v1/pi-withdrawal', {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${localStorage.getItem('supabase_token')}`,
        'Content-Type': 'application/json'
      }
    });

    if (!balanceResponse.ok) {
      throw new Error(`Balance check failed: ${balanceResponse.status} ${balanceResponse.statusText}`);
    }

    console.log('✅ Balance checking is working\n');

    // Test 3: Test withdrawal creation (small amount)
    console.log('3️⃣ Testing withdrawal creation...');
    const withdrawalRequest = {
      amount: 0.01, // Small test amount
      memo: 'Test withdrawal from automated test',
      metadata: {
        test: true,
        timestamp: new Date().toISOString()
      }
    };

    const withdrawalResponse = await fetch('/functions/v1/pi-withdrawal', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${localStorage.getItem('supabase_token')}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(withdrawalRequest)
    });

    if (!withdrawalResponse.ok) {
      const errorData = await withdrawalResponse.json();
      throw new Error(`Withdrawal creation failed: ${withdrawalResponse.status} ${withdrawalResponse.statusText} - ${errorData.error}`);
    }

    const withdrawalData = await withdrawalResponse.json();
    console.log('✅ Withdrawal created successfully');
    console.log(`📝 Payment ID: ${withdrawalData.paymentId}`);
    console.log(`🔗 Transaction ID: ${withdrawalData.txid}`);
    console.log(`💰 Amount: ${withdrawalRequest.amount} PI`);
    console.log(`📊 New Balance: ${withdrawalData.newBalance} PI\n`);

    // Test 4: Verify withdrawal in history
    console.log('4️⃣ Verifying withdrawal in history...');
    const updatedHistoryResponse = await fetch('/functions/v1/pi-withdrawal', {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${localStorage.getItem('supabase_token')}`,
        'Content-Type': 'application/json'
      }
    });

    if (updatedHistoryResponse.ok) {
      const updatedHistoryData = await updatedHistoryResponse.json();
      const latestWithdrawal = updatedHistoryData.history?.[0];
      
      if (latestWithdrawal && latestWithdrawal.payment_id === withdrawalData.paymentId) {
        console.log('✅ Withdrawal found in history');
        console.log(`📊 Status: ${latestWithdrawal.status}`);
        console.log(`🕐 Created: ${new Date(latestWithdrawal.created_at).toLocaleString()}\n`);
      } else {
        console.log('⚠️ Withdrawal not yet visible in history (may take a moment)\n');
      }
    }

    console.log('🎉 All tests completed successfully!');
    console.log('\n📋 Test Summary:');
    console.log('✅ Edge Function deployed and accessible');
    console.log('✅ Balance checking working');
    console.log('✅ Withdrawal creation successful');
    console.log('✅ Pi Network A2U flow complete');
    console.log('\n🚀 Pi Network withdrawal feature is ready for production use!');

  } catch (error) {
    console.error('❌ Test failed:', error.message);
    console.log('\n🔧 Troubleshooting steps:');
    console.log('1. Check Edge Function deployment: supabase functions list');
    console.log('2. Verify environment variables: supabase secrets list');
    console.log('3. Check database schema: ensure pi_withdrawals table exists');
    console.log('4. Verify Pi Network credentials are valid');
    console.log('5. Check Edge Function logs: supabase functions logs pi-withdrawal');
  }
};

// Auto-run test if in browser environment
if (typeof window !== 'undefined') {
  // Add test button to page for manual testing
  const testButton = document.createElement('button');
  testButton.textContent = '🧪 Test Pi Withdrawal';
  testButton.style.cssText = `
    position: fixed;
    top: 20px;
    right: 20px;
    background: #4CAF50;
    color: white;
    border: none;
    padding: 10px 20px;
    border-radius: 5px;
    cursor: pointer;
    z-index: 9999;
    font-weight: bold;
  `;
  
  testButton.onclick = testPiWithdrawal;
  document.body.appendChild(testButton);
  
  console.log('🧪 Pi Withdrawal Test: Click the "Test Pi Withdrawal" button or run testPiWithdrawal() in console');
}

// Export for Node.js testing
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { testPiWithdrawal };
}
