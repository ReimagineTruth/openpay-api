import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const jsonResponse = (body: Record<string, unknown>, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    if (!supabaseUrl || !supabaseServiceKey) throw new Error("Server configuration error");
    const supabase: any = createClient(supabaseUrl, supabaseServiceKey);

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) throw new Error("Missing auth token");
    const token = authHeader.replace("Bearer ", "");
    const authResult = await supabase.auth.getUser(token);
    const user = authResult?.data?.user;
    if (authResult?.error || !user) throw new Error("Unauthorized");

    const body = await req.json().catch(() => ({}));
    const action = String((body as any).action || "credit");
    const amount = (body as any).amount;
    const amountUsd = (body as any).amountUsd;
    const paymentId = (body as any).paymentId;
    const txid = (body as any).txid;
    const targetAccountNumber = String((body as any).targetAccountNumber || "").trim().toUpperCase();
    const targetUsername = String((body as any).targetUsername || "").trim().replace(/^@+/, "").toLowerCase();
    const parsedAmount = Number(amount);
    const parsedAmountUsd = Number.isFinite(Number(amountUsd)) && Number(amountUsd) > 0 ? Number(amountUsd) : parsedAmount;
    if (!paymentId || typeof paymentId !== "string") throw new Error("Missing paymentId");

    const piApiKey = Deno.env.get("PI_API_KEY");
    if (!piApiKey) throw new Error("PI_API_KEY is not configured");

    const callPi = async (endpoint: string, method: "GET" | "POST", payload?: Record<string, unknown>): Promise<Record<string, unknown>> => {
      const response = await fetch(`https://api.minepi.com/v2${endpoint}`, {
        method,
        headers: { Authorization: `Key ${piApiKey}`, "Content-Type": "application/json" },
        body: payload ? JSON.stringify(payload) : undefined,
      });
      const raw = await response.text();
      let data: Record<string, unknown> = {};
      try { data = raw ? JSON.parse(raw) : {}; } catch { data = { raw }; }
      if (!response.ok) throw new Error((data.error as string) || `Pi API failed with status ${response.status}`);
      return data;
    };

    if (action === "approve") {
      await callPi(`/payments/${paymentId}/approve`, "POST");
      return jsonResponse({ success: true, action, paymentId });
    }

    if (action === "complete") {
      await callPi(`/payments/${paymentId}/complete`, "POST", txid ? { txid } : undefined);
      return jsonResponse({ success: true, action, paymentId, txid: txid || null });
    }

    if (!Number.isFinite(parsedAmount) || parsedAmount <= 0) throw new Error("Invalid amount");

    if (txid) {
      try { await callPi(`/payments/${paymentId}/complete`, "POST", { txid }); } catch { /* idempotent */ }
    }

    type PiPayment = { amount?: number | string; direction?: string; user_uid?: string; status?: any; transaction?: { txid?: string } };
    let piPayment: PiPayment | null = null;
    for (let attempt = 0; attempt < 3; attempt++) {
      piPayment = await callPi(`/payments/${paymentId}`, "GET") as PiPayment;
      const st = piPayment.status || {};
      if (st.developer_completed && st.transaction_verified) break;
      if (attempt < 2) await sleep(350);
    }

    if (!piPayment) throw new Error("Unable to verify Pi payment");

    const piAmount = Number(piPayment?.amount);
    const piDirection = String(piPayment?.direction || "");
    const status = piPayment.status || {};
    const piTxid = piPayment.transaction?.txid ? String(piPayment.transaction.txid) : null;

    if (piDirection !== "user_to_app") throw new Error("Invalid payment direction");
    if (status.cancelled || status.user_cancelled) throw new Error("Payment is cancelled");
    if (!status.developer_completed || !status.transaction_verified) throw new Error("Payment is not completed/verified yet. Please retry.");
    if (!Number.isFinite(piAmount) || Math.abs(piAmount - parsedAmount) > 0.000001) throw new Error("Payment amount mismatch");
    if (txid && piTxid && txid !== piTxid) throw new Error("Payment txid mismatch");

    const { data: authUserData } = await supabase.auth.admin.getUserById(user.id);
    const linkedPiUid = authUserData?.user?.user_metadata?.pi_uid as string | undefined;
    const paymentPiUid = piPayment?.user_uid ? String(piPayment.user_uid) : "";
    if (linkedPiUid && paymentPiUid && linkedPiUid !== paymentPiUid) throw new Error("Payment user does not match linked Pi account");

    if (targetAccountNumber || targetUsername) {
      const { data: profile, error: profileError } = await supabase.from("profiles").select("full_name, username").eq("id", user.id).maybeSingle();
      if (profileError) throw profileError;
      const profileRow = profile as any;
      const fallbackAccountNumber = `OP${String(user.id).replace(/-/g, "").toUpperCase()}`;
      const fallbackAccountUsername = String(profileRow?.username || "").trim().replace(/^@+/, "").toLowerCase() || "openpay";
      const fallbackAccountName = String(profileRow?.full_name || "").trim() || "OpenPay User";

      const { error: accountUpsertError } = await supabase
        .from("user_accounts")
        .upsert({ user_id: user.id, account_number: fallbackAccountNumber, account_username: fallbackAccountUsername, account_name: fallbackAccountName }, { onConflict: "user_id" })
        .select("account_number, account_username")
        .single();
      if (accountUpsertError) throw accountUpsertError;
    }

    const creditInsertRes = await supabase.from("pi_payment_credits").insert({ payment_id: paymentId, user_id: user.id, amount: parsedAmount, txid: piTxid || txid || null, status: "completed" });
    const creditLogError = creditInsertRes?.error;
    if (creditLogError) {
      if (creditLogError.code === "23505" || creditLogError.message?.toLowerCase().includes("duplicate")) {
        return jsonResponse({ success: true, paymentId, alreadyCredited: true });
      }
      throw creditLogError;
    }

    const { data: wallet, error: walletError } = await supabase.from("wallets").select("*").eq("user_id", user.id).single();
    if (walletError) throw walletError;
    const walletRow = wallet as any;

    const walletUpdateRes = await supabase.from("wallets").update({ balance: (walletRow?.balance || 0) + parsedAmount, updated_at: new Date().toISOString() }).eq("user_id", user.id);
    if (walletUpdateRes?.error) throw walletUpdateRes.error;

    const { data: transactionRow, error: transactionError } = await supabase
      .from("transactions")
      .insert({
        sender_id: user.id,
        receiver_id: user.id,
        amount: parsedAmount,
        note: `Wallet top up (PI -> OPEN USD) | ${parsedAmount.toFixed(2)} PI = ${parsedAmountUsd.toFixed(2)} OPEN USD`,
        status: "completed",
      })
      .select("id")
      .single();

    if (transactionError) {
      await supabase.from("wallets").update({ balance: (walletRow?.balance || 0), updated_at: new Date().toISOString() }).eq("user_id", user.id);
      await supabase.from("pi_payment_credits").delete().eq("payment_id", paymentId);
      throw transactionError;
    }

    const txRow = transactionRow as any;
    return jsonResponse({ success: true, paymentId, transaction_id: txRow?.id || null });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Unexpected error";
    return jsonResponse({ error: message }, 400);
  }
});
