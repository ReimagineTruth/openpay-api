import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const jsonResponse = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

const getPaypalBaseUrl = () => {
  const env = (Deno.env.get("PAYPAL_ENV") || "sandbox").toLowerCase();
  return env === "live" ? "https://api-m.paypal.com" : "https://api-m.sandbox.paypal.com";
};

const getAccessToken = async (clientId: string, secret: string) => {
  const tokenUrl = `${getPaypalBaseUrl()}/v1/oauth2/token`;
  const auth = btoa(`${clientId}:${secret}`);
  const res = await fetch(tokenUrl, {
    method: "POST",
    headers: {
      Authorization: `Basic ${auth}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data?.error_description || "PayPal auth failed");
  return data.access_token as string;
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { status: 200, headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !supabaseServiceKey) throw new Error("Server configuration error");

    const clientId = Deno.env.get("PAYPAL_CLIENT_ID");
    const secret = Deno.env.get("PAYPAL_SECRET");
    if (!clientId || !secret) throw new Error("PayPal is not configured");

    const supabase: any = createClient(supabaseUrl, supabaseServiceKey);
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) throw new Error("Missing auth token");
    const token = authHeader.replace("Bearer ", "");
    const authResult = await supabase.auth.getUser(token);
    const user = authResult?.data?.user;
    if (authResult?.error || !user) throw new Error("Unauthorized");

    const body = await req.json().catch(() => ({}));
    const orderId = String((body as any).orderId || "").trim();
    if (!orderId) throw new Error("Missing orderId");

    const accessToken = await getAccessToken(clientId, secret);
    const captureRes = await fetch(`${getPaypalBaseUrl()}/v2/checkout/orders/${orderId}/capture`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
    });
    const captureData = await captureRes.json();
    if (!captureRes.ok) throw new Error(captureData?.message || "PayPal capture failed");

    return jsonResponse({ status: captureData.status, id: captureData.id, data: captureData });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Unexpected error";
    return jsonResponse({ error: message }, 400);
  }
});
