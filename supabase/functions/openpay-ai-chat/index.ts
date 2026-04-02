import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const LOVABLE_API_KEY = Deno.env.get("LOVABLE_API_KEY");
    if (!LOVABLE_API_KEY) throw new Error("AI service is not configured");

    const { message, context } = await req.json();
    if (!message) throw new Error("message is required");

    const systemPrompt = `You are OpenPay AI, a comprehensive smart financial assistant for the OpenPay fintech platform. You have complete knowledge of all OpenPay features.

## OpenPay Platform Features:

### Core Banking: Wallet management, send/receive money, top-up (PayPal, cards, Apple Pay, Google Pay, Venmo, USDT, USDC, Solana Pay), currency exchange, virtual cards, transaction history.

### Merchant Services: Merchant portal, POS system, payment links & buttons, QR code payments, invoice system, product catalog management.

### Earning & Rewards: Pi Network mining, staking rewards, affiliate/referral program, Pi Ad Network.

### Security & Support: 2FA, KYC verification, dispute resolution, fraud detection, notifications, help center.

### Technical: Multi-currency (PHP, USD, etc.), blockchain integration (Solana), developer APIs, mobile & web apps.

## Current User Context:
${context || "No additional context available."}

## Guidelines:
- Be helpful, clear, and concise
- Use US Dollar ($) for amounts
- Provide step-by-step instructions when helpful
- Suggest related features when appropriate
- Prioritize security best practices
- If asked about payments, guide users through the process`;

    const response = await fetch("https://ai.gateway.lovable.dev/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${LOVABLE_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "google/gemini-3-flash-preview",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: message },
        ],
      }),
    });

    if (!response.ok) {
      if (response.status === 429) {
        return new Response(JSON.stringify({ error: "AI is busy. Please try again in a moment." }), {
          status: 429,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      if (response.status === 402) {
        return new Response(JSON.stringify({ error: "AI credits exhausted. Please try again later." }), {
          status: 402,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      const errText = await response.text();
      console.error("AI gateway error:", response.status, errText);
      throw new Error("AI service temporarily unavailable");
    }

    const data = await response.json();
    const reply = data.choices?.[0]?.message?.content || "I couldn't generate a response. Please try again.";

    return new Response(JSON.stringify({ reply }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    const msg = error instanceof Error ? error.message : "Unexpected error";
    console.error("openpay-ai-chat error:", msg);
    return new Response(JSON.stringify({ error: msg }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
