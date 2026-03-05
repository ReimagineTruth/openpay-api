import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const jsonResponse = (body: Record<string, unknown>, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

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

    const body = await req.json();
    const {
      receiver_id,
      receiver_email,
      amount,
      note,
      currency_code,
      sender_amount,
      sender_currency_code,
      receiver_amount,
      receiver_currency_code,
    } = body;
    const parsedAmount = Number(amount);
    if (!Number.isFinite(parsedAmount) || parsedAmount <= 0) throw new Error("Invalid amount");

    let receiverId = receiver_id;

    if (receiver_email && receiver_email !== "__by_id__") {
      const receiverAuth = await supabase.auth.admin.listUsers();
      const users = receiverAuth?.data?.users || receiverAuth?.users || [];
      const receiver = users.find((u: any) => u.email === receiver_email);
      if (!receiver) throw new Error("Recipient not found");
      receiverId = receiver.id;
    }

    if (!receiverId) throw new Error("No recipient specified");
    if (receiverId === user.id) throw new Error("Cannot send to yourself");

    const transferPayload = {
      p_sender_id: user.id,
      p_receiver_id: receiverId,
      p_amount: parsedAmount,
      p_note: note || "",
      p_currency_code: typeof currency_code === "string" ? currency_code : "OUSD",
      p_sender_amount: typeof sender_amount === "number" ? sender_amount : null,
      p_sender_currency_code: typeof sender_currency_code === "string" ? sender_currency_code : null,
      p_receiver_amount: typeof receiver_amount === "number" ? receiver_amount : null,
      p_receiver_currency_code: typeof receiver_currency_code === "string" ? receiver_currency_code : null,
    };

    let transactionId: unknown = null;
    let transferError: unknown = null;

    const primary = await supabase.rpc("transfer_funds", transferPayload);
    transactionId = primary.data;
    transferError = primary.error;

    if (transferError) {
      const msg = (transferError as any)?.message || "";
      const shouldFallback = /function transfer_funds|does not exist|schema cache/i.test(msg);
      if (shouldFallback) {
        const legacy = await supabase.rpc("transfer_funds", {
          p_sender_id: user.id,
          p_receiver_id: receiverId,
          p_amount: parsedAmount,
          p_note: note || "",
        });
        transactionId = legacy.data;
        transferError = legacy.error;
      }
    }

    if (transferError) {
      const msg =
        (transferError as any)?.message ||
        (transferError as any)?.details ||
        "Transfer failed";
      throw new Error(msg);
    }

    return jsonResponse({ success: true, transaction_id: transactionId });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Unexpected error";
    return jsonResponse({ error: message }, 400);
  }
});
