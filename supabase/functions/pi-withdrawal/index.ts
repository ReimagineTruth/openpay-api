/// <reference path="./deno-types.d.ts" />
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import PiNetwork from "https://esm.sh/pi-backend@1.2.0"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

console.log('Pi withdrawal Edge Function starting up...')

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: req.headers.get('Authorization')! },
        },
      }
    )

    // Get user from auth
    const {
      data: { user },
      error: authError,
    } = await supabaseClient.auth.getUser()

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 }
      )
    }

    const { method } = req

    if (method === 'POST') {
      // Handle withdrawal creation
      const { amount, memo, metadata } = await req.json()

      if (!amount || amount <= 0) {
        return new Response(
          JSON.stringify({ error: 'Invalid amount' }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
        )
      }

      // Initialize Pi Network with environment variables
      const apiKey = Deno.env.get('PI_API_KEY')
      const walletPrivateSeed = Deno.env.get('PI_WALLET_PRIVATE_SEED')
      
      // Pi Network Horizon configuration
      const mainnetUrl = Deno.env.get('PI_BACKEND_HORIZON_MAINNET_URL')
      const mainnetPassphrase = Deno.env.get('PI_BACKEND_HORIZON_MAINNET_PASSPHRASE')
      const testnetUrl = Deno.env.get('PI_BACKEND_HORIZON_TESTNET_URL')
      const testnetPassphrase = Deno.env.get('PI_BACKEND_HORIZON_TESTNET_PASSPHRASE')
      const platformBaseUrl = Deno.env.get('PI_BACKEND_PLATFORM_BASE_URL')

      console.log('Pi Network Environment Variables Status:', {
        PI_API_KEY: !!apiKey,
        PI_WALLET_PRIVATE_SEED: !!walletPrivateSeed,
        PI_BACKEND_HORIZON_MAINNET_URL: !!mainnetUrl,
        PI_BACKEND_HORIZON_MAINNET_PASSPHRASE: !!mainnetPassphrase,
        PI_BACKEND_HORIZON_TESTNET_URL: !!testnetUrl,
        PI_BACKEND_HORIZON_TESTNET_PASSPHRASE: !!testnetPassphrase,
        PI_BACKEND_PLATFORM_BASE_URL: !!platformBaseUrl
      })

      // Use fallback values if environment variables are not set
      const finalApiKey = apiKey || "fudrvmlzm7ucqu94smlgeudrryccqxpymkr1vqk6nw0yoli8ikirbzrn9siv4hi9"
      const finalWalletPrivateSeed = walletPrivateSeed || "SDZWK2Z4JA3KTQIGAEUSKWFLZBDILJAWLUNAUFHURFIF5BWNNH3PB5Y3"
      const finalMainnetUrl = mainnetUrl || "https://api.mainnet.minepi.com"
      const finalMainnetPassphrase = mainnetPassphrase || "Pi Network"
      const finalTestnetUrl = testnetUrl || "https://api.testnet.minepi.com"
      const finalTestnetPassphrase = testnetPassphrase || "Pi Testnet"
      const finalPlatformBaseUrl = platformBaseUrl || "https://api.minepi.com"

      console.log('Pi Network Final Configuration:', {
        apiKeySource: apiKey ? 'environment' : 'fallback',
        walletSeedSource: walletPrivateSeed ? 'environment' : 'fallback',
        mainnetUrl: finalMainnetUrl,
        testnetUrl: finalTestnetUrl,
        platformBaseUrl: finalPlatformBaseUrl
      })

      if (!apiKey || !walletPrivateSeed) {
        console.error('Pi Network credentials not configured')
        return new Response(
          JSON.stringify({ error: 'Pi Network credentials not configured' }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
        )
      }

      // Initialize Pi Network with actual SDK and environment configuration
      const pi = new PiNetwork(finalApiKey, finalWalletPrivateSeed)
      console.log('Pi Network SDK initialized successfully')

      // Check user Pi balance using RPC function
      const { data: balanceData, error: balanceError } = await supabaseClient
        .rpc('get_user_pi_balance')

      if (balanceError) {
        console.error('Balance check error:', balanceError)
        return new Response(
          JSON.stringify({ error: 'Unable to verify user balance', details: balanceError.message }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
        )
      }

      if (!balanceData || balanceData.length === 0) {
        return new Response(
          JSON.stringify({ error: 'No balance data found' }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
        )
      }

      const userBalance = balanceData[0]
      const availableBalance = userBalance.available_balance

      if (availableBalance < amount) {
        return new Response(
          JSON.stringify({ 
            error: 'Insufficient balance',
            details: `Available: ${availableBalance} PI, Requested: ${amount} PI`
          }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
        )
      }

      // Check daily withdrawal limit
      if (userBalance.daily_remaining < amount) {
        return new Response(
          JSON.stringify({ 
            error: 'Daily withdrawal limit exceeded',
            details: `Daily remaining: ${userBalance.daily_remaining} PI, Requested: ${amount} PI`
          }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
        )
      }

      // Create payment
      const paymentData = {
        amount: amount,
        memo: memo || `A2U Withdrawal from OpenPay`,
        metadata: {
          ...metadata,
          type: 'a2u_withdrawal',
          timestamp: new Date().toISOString(),
          user_uid: user.id
        },
        uid: user.id
      }

      const paymentId = await pi.createPayment(paymentData)

      // Store withdrawal record
      const withdrawalRecord = {
        id: crypto.randomUUID(),
        user_uid: user.id,
        amount: amount,
        memo: paymentData.memo,
        metadata: paymentData.metadata,
        payment_id: paymentId,
        status: 'pending',
        from_address: '',
        to_address: '',
        direction: 'app_to_user',
        created_at: new Date().toISOString(),
        network: 'Pi Network',
        transaction_verified: false,
        developer_completed: false
      }

      const { error: insertError } = await supabaseClient
        .from('pi_withdrawals')
        .insert(withdrawalRecord)

      if (insertError) {
        console.error('Error storing withdrawal record:', insertError)
      }

      // Submit payment to blockchain
      const txid = await pi.submitPayment(paymentId)

      // Update withdrawal record with txid
      await supabaseClient
        .from('pi_withdrawals')
        .update({ 
          txid: txid,
          status: 'submitted'
        })
        .eq('payment_id', paymentId)

      // Complete payment
      const completedPayment = await pi.completePayment(paymentId, txid)

      // Update final status
      await supabaseClient
        .from('pi_withdrawals')
        .update({ 
          status: 'completed',
          transaction_verified: completedPayment.transaction?.verified || false,
          developer_completed: completedPayment.status?.developer_completed || false,
          from_address: completedPayment.from_address || '',
          to_address: completedPayment.to_address || ''
        })
        .eq('payment_id', paymentId)

      // Get updated balance after withdrawal
      const { data: updatedBalanceData, error: updatedBalanceError } = await supabaseClient
        .rpc('get_user_pi_balance')

      let newBalance = availableBalance - amount
      if (!updatedBalanceError && updatedBalanceData && updatedBalanceData.length > 0) {
        newBalance = updatedBalanceData[0].available_balance
      }

      return new Response(
        JSON.stringify({
          success: true,
          paymentId: paymentId,
          txid: txid,
          completedPayment: completedPayment,
          newBalance: newBalance,
          previousBalance: availableBalance
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
      )

    } else if (method === 'GET') {
      // Handle withdrawal history request using RPC function
      const { data: history, error: historyError } = await supabaseClient
        .rpc('get_pi_withdrawal_history', { 
          p_limit: 50, 
          p_offset: 0 
        })

      if (historyError) {
        console.error('History fetch error:', historyError)
        return new Response(
          JSON.stringify({ error: 'Failed to fetch withdrawal history', details: historyError.message }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
        )
      }

      return new Response(
        JSON.stringify({ history: history || [] }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
      )
    }

    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 405 }
    )

  } catch (error) {
    console.error('Pi withdrawal error:', error)
    
    // Handle specific Pi Network errors
    const errorMessage = error instanceof Error ? error.message : String(error)
    
    let userFriendlyError = 'Withdrawal failed'
    if (errorMessage.includes('You need to complete the ongoing payment first')) {
      userFriendlyError = 'Please complete any pending payments before creating a new withdrawal'
    } else if (errorMessage.includes('insufficient')) {
      userFriendlyError = 'Insufficient balance for this withdrawal'
    } else if (errorMessage.includes('unauthorized') || errorMessage.includes('authentication')) {
      userFriendlyError = 'Authentication failed. Please check your Pi Network credentials'
    }

    return new Response(
      JSON.stringify({ 
        error: userFriendlyError,
        details: errorMessage
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})
