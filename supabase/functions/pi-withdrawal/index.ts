// Pi Network A2U Withdrawal Edge Function
// Implements the A2U flow per https://github.com/pi-apps/pi-nodejs
// We do NOT use the `pi-backend` npm package because it depends on Node-only
// libs that don't load cleanly under Deno via esm.sh. Instead we call the Pi
// Platform API directly with fetch and sign the Stellar payment with
// @stellar/stellar-sdk, which works in Deno.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
// @ts-ignore - esm.sh bundled build works in Deno edge runtime
import StellarSdk from "https://esm.sh/stellar-sdk@11.3.0?bundle&target=deno";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const PI_PLATFORM_BASE =
  Deno.env.get("PI_BACKEND_PLATFORM_BASE_URL") || "https://api.minepi.com";

// Pi Network is built on Stellar. We auto-detect mainnet vs testnet from the
// `network` field of the created payment (returned by the Pi Platform API).
const HORIZON = {
  "Pi Network": {
    url:
      Deno.env.get("PI_BACKEND_HORIZON_MAINNET_URL") ||
      "https://api.mainnet.minepi.com",
    passphrase:
      Deno.env.get("PI_BACKEND_HORIZON_MAINNET_PASSPHRASE") || "Pi Network",
  },
  "Pi Testnet": {
    url:
      Deno.env.get("PI_BACKEND_HORIZON_TESTNET_URL") ||
      "https://api.testnet.minepi.com",
    passphrase:
      Deno.env.get("PI_BACKEND_HORIZON_TESTNET_PASSPHRASE") || "Pi Testnet",
  },
} as const;

type PiPayment = {
  identifier: string;
  user_uid: string;
  amount: number;
  memo: string;
  metadata: Record<string, unknown>;
  from_address: string;
  to_address: string;
  direction: "user_to_app" | "app_to_user";
  network: "Pi Network" | "Pi Testnet";
  status: {
    developer_approved: boolean;
    transaction_verified: boolean;
    developer_completed: boolean;
    cancelled: boolean;
    user_cancelled: boolean;
  };
  transaction: null | { txid: string; verified: boolean; _link: string };
};

function piHeaders(apiKey: string) {
  return {
    Authorization: `Key ${apiKey}`,
    "Content-Type": "application/json",
  };
}

async function piCreatePayment(
  apiKey: string,
  body: { amount: number; memo: string; metadata: Record<string, unknown>; uid: string },
): Promise<PiPayment> {
  const r = await fetch(`${PI_PLATFORM_BASE}/v2/payments`, {
    method: "POST",
    headers: piHeaders(apiKey),
    body: JSON.stringify({ payment: body }),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`createPayment failed: ${r.status} ${text}`);
  return JSON.parse(text) as PiPayment;
}

async function piGetPayment(apiKey: string, paymentId: string): Promise<PiPayment> {
  const r = await fetch(`${PI_PLATFORM_BASE}/v2/payments/${paymentId}`, {
    headers: piHeaders(apiKey),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`getPayment failed: ${r.status} ${text}`);
  return JSON.parse(text) as PiPayment;
}

async function piCompletePayment(
  apiKey: string,
  paymentId: string,
  txid: string,
): Promise<PiPayment> {
  const r = await fetch(
    `${PI_PLATFORM_BASE}/v2/payments/${paymentId}/complete`,
    {
      method: "POST",
      headers: piHeaders(apiKey),
      body: JSON.stringify({ txid }),
    },
  );
  const text = await r.text();
  if (!r.ok) throw new Error(`completePayment failed: ${r.status} ${text}`);
  return JSON.parse(text) as PiPayment;
}

async function piCancelPayment(apiKey: string, paymentId: string) {
  const r = await fetch(
    `${PI_PLATFORM_BASE}/v2/payments/${paymentId}/cancel`,
    { method: "POST", headers: piHeaders(apiKey) },
  );
  if (!r.ok) {
    const t = await r.text();
    throw new Error(`cancelPayment failed: ${r.status} ${t}`);
  }
  return await r.json();
}

async function piGetIncompletePayments(apiKey: string): Promise<PiPayment[]> {
  const r = await fetch(
    `${PI_PLATFORM_BASE}/v2/payments/incomplete_server_payments`,
    { headers: piHeaders(apiKey) },
  );
  if (!r.ok) return [];
  const data = await r.json();
  return (data?.incomplete_server_payments ?? []) as PiPayment[];
}

async function submitStellarPayment(
  payment: PiPayment,
  walletPrivateSeed: string,
): Promise<string> {
  const cfg = HORIZON[payment.network];
  if (!cfg) throw new Error(`Unsupported network: ${payment.network}`);

  const server = new StellarSdk.Horizon.Server(cfg.url);
  const sourceKey = StellarSdk.Keypair.fromSecret(walletPrivateSeed);
  const fromAddress = sourceKey.publicKey();

  if (payment.from_address && payment.from_address !== fromAddress) {
    throw new Error(
      `Pi payment.from_address (${payment.from_address}) does not match app wallet (${fromAddress}).`,
    );
  }

  const account = await server.loadAccount(fromAddress);
  const fee = await server.fetchBaseFee();

  const tx = new StellarSdk.TransactionBuilder(account, {
    fee: String(fee),
    networkPassphrase: cfg.passphrase,
  })
    .addOperation(
      StellarSdk.Operation.payment({
        destination: payment.to_address,
        asset: StellarSdk.Asset.native(),
        amount: payment.amount.toString(),
      }),
    )
    .addMemo(StellarSdk.Memo.text(payment.identifier))
    .setTimeout(180)
    .build();

  tx.sign(sourceKey);
  const result = await server.submitTransaction(tx);
  // @ts-ignore stellar-sdk returns hash on success
  return result.hash as string;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      {
        global: {
          headers: { Authorization: req.headers.get("Authorization")! },
        },
      },
    );

    const {
      data: { user },
      error: authError,
    } = await supabaseClient.auth.getUser();

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 401,
      });
    }

    const apiKey = Deno.env.get("PI_API_KEY");
    const walletPrivateSeed = Deno.env.get("PI_WALLET_PRIVATE_SEED");

    if (req.method === "GET") {
      const { data: history, error: historyError } = await supabaseClient.rpc(
        "get_pi_withdrawal_history",
        { p_limit: 50, p_offset: 0 },
      );
      if (historyError) {
        return new Response(
          JSON.stringify({
            error: "Failed to fetch withdrawal history",
            details: historyError.message,
          }),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 500,
          },
        );
      }
      return new Response(JSON.stringify({ history: history || [] }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      });
    }

    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 405,
      });
    }

    if (!apiKey || !walletPrivateSeed) {
      console.error("Pi Network credentials not configured");
      return new Response(
        JSON.stringify({
          error:
            "Pi Network credentials not configured. Set PI_API_KEY and PI_WALLET_PRIVATE_SEED secrets.",
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 500,
        },
      );
    }
    if (!walletPrivateSeed.startsWith("S")) {
      return new Response(
        JSON.stringify({
          error: "PI_WALLET_PRIVATE_SEED is invalid (must start with 'S').",
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 500,
        },
      );
    }

    const { amount, memo, metadata } = await req.json();
    if (!amount || amount <= 0) {
      return new Response(JSON.stringify({ error: "Invalid amount" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    // Balance + daily limit checks
    const { data: balanceData, error: balanceError } = await supabaseClient.rpc(
      "get_user_pi_balance",
    );
    if (balanceError || !balanceData || balanceData.length === 0) {
      return new Response(
        JSON.stringify({
          error: "Unable to verify user balance",
          details: balanceError?.message,
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        },
      );
    }
    const userBalance = balanceData[0];
    const availableBalance = Number(userBalance.available_balance);
    if (availableBalance < amount) {
      return new Response(
        JSON.stringify({
          error: "Insufficient balance",
          details: `Available: ${availableBalance} PI, Requested: ${amount} PI`,
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        },
      );
    }
    if (Number(userBalance.daily_remaining) < amount) {
      return new Response(
        JSON.stringify({
          error: "Daily withdrawal limit exceeded",
          details: `Daily remaining: ${userBalance.daily_remaining} PI`,
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        },
      );
    }

    // Handle any incomplete server payments first to avoid the
    // "ongoing payment" error from Pi Platform.
    const incomplete = await piGetIncompletePayments(apiKey);
    for (const p of incomplete) {
      try {
        if (p.transaction?.txid) {
          await piCompletePayment(apiKey, p.identifier, p.transaction.txid);
        } else {
          await piCancelPayment(apiKey, p.identifier);
        }
      } catch (e) {
        console.error("Failed to clear incomplete payment", p.identifier, e);
      }
    }

    // 1) Create A2U payment
    const created = await piCreatePayment(apiKey, {
      amount: Number(amount),
      memo: memo || "A2U Withdrawal from OpenPay",
      metadata: {
        ...(metadata ?? {}),
        type: "a2u_withdrawal",
        timestamp: new Date().toISOString(),
        user_uid: user.id,
      },
      uid: user.id,
    });
    const paymentId = created.identifier;

    // 2) Persist initial record
    await supabaseClient.from("pi_withdrawals").insert({
      id: crypto.randomUUID(),
      user_uid: user.id,
      amount,
      memo: created.memo,
      metadata: created.metadata,
      payment_id: paymentId,
      status: "pending",
      from_address: created.from_address || "",
      to_address: created.to_address || "",
      direction: "app_to_user",
      created_at: new Date().toISOString(),
      network: created.network,
      transaction_verified: false,
      developer_completed: false,
    });

    // 3) Submit on-chain via Stellar
    // We need the resolved payment with to_address — `created` already has it.
    const payment = created.to_address
      ? created
      : await piGetPayment(apiKey, paymentId);
    const txid = await submitStellarPayment(payment, walletPrivateSeed);

    await supabaseClient
      .from("pi_withdrawals")
      .update({ txid, status: "submitted" })
      .eq("payment_id", paymentId);

    // 4) Complete payment in Pi server
    const completed = await piCompletePayment(apiKey, paymentId, txid);

    await supabaseClient
      .from("pi_withdrawals")
      .update({
        status: "completed",
        transaction_verified: completed.transaction?.verified || false,
        developer_completed: completed.status?.developer_completed || false,
        from_address: completed.from_address || "",
        to_address: completed.to_address || "",
      })
      .eq("payment_id", paymentId);

    const { data: updatedBalanceData } = await supabaseClient.rpc(
      "get_user_pi_balance",
    );
    const newBalance =
      updatedBalanceData?.[0]?.available_balance ?? availableBalance - amount;

    return new Response(
      JSON.stringify({
        success: true,
        paymentId,
        txid,
        completedPayment: completed,
        newBalance,
        previousBalance: availableBalance,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      },
    );
  } catch (error) {
    const errorMessage =
      error instanceof Error ? error.message : String(error);
    console.error("Pi withdrawal error:", errorMessage);

    let userFriendlyError = "Withdrawal failed";
    if (errorMessage.includes("ongoing payment")) {
      userFriendlyError =
        "There is an ongoing payment. Please retry in a moment.";
    } else if (errorMessage.toLowerCase().includes("insufficient")) {
      userFriendlyError = "Insufficient balance for this withdrawal";
    } else if (
      errorMessage.toLowerCase().includes("unauthorized") ||
      errorMessage.toLowerCase().includes("authentication")
    ) {
      userFriendlyError =
        "Authentication failed. Please check your Pi Network credentials";
    }

    return new Response(
      JSON.stringify({ error: userFriendlyError, details: errorMessage }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500,
      },
    );
  }
});
