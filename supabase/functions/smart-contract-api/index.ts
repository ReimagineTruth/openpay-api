import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-api-key, x-client-id, x-target-path",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const url = new URL(req.url);
  const headerPath = req.headers.get("x-target-path") || "";
  const urlPath = url.pathname.replace(/^\/smart-contract-api\/?/, "").replace(/\/$/, "");
  const path = headerPath || urlPath;

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    if (!supabaseUrl || !serviceKey) throw new Error("Server configuration error");
    const supabase = createClient(supabaseUrl, serviceKey);

    // Public endpoints (no auth required)
    if (path === "health") {
      return json({ status: "ok", version: "1.0.0", timestamp: new Date().toISOString() });
    }
    if (path === "currencies") {
      const { data: currencies } = await supabase
        .from("supported_currencies")
        .select("iso_code, display_code, display_name, symbol, flag, usd_rate")
        .eq("is_active", true);
      return json({ currencies: currencies || [] });
    }

    // Pi RPC proxy — forwards JSON-RPC calls to Pi Testnet/Mainnet RPC server
    if (path === "pi-rpc" || path === "pi-rpc/testnet" || path === "pi-rpc/mainnet") {
      if (req.method !== "POST") return json({ error: "POST required for JSON-RPC" }, 405);

      const network = path.includes("mainnet") ? "mainnet" : "testnet";
      const rpcUrl = network === "mainnet"
        ? "https://rpc.minepi.com"
        : "https://rpc.testnet.minepi.com";

      const body = await req.json();

      // Validate JSON-RPC structure
      if (!body.jsonrpc || !body.method) {
        return json({ error: "Invalid JSON-RPC request. Required: jsonrpc, method" }, 400);
      }

      // Block dangerous methods
      const blockedMethods = ["sendTransaction", "submitTransaction"];
      if (blockedMethods.includes(body.method)) {
        return json({ error: `Method '${body.method}' is not allowed through the proxy. Submit transactions directly.` }, 403);
      }

      try {
        const rpcResponse = await fetch(rpcUrl, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        });
        const rpcData = await rpcResponse.text();
        return new Response(rpcData, {
          status: rpcResponse.status,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      } catch (rpcErr: unknown) {
        const msg = rpcErr instanceof Error ? rpcErr.message : "RPC request failed";
        return json({ error: msg, network, rpc_url: rpcUrl }, 502);
      }
    }

    // Authenticate via client_id + API key OR Bearer token
    const clientId = req.headers.get("x-client-id") || "";
    const apiKey = req.headers.get("x-api-key") || "";
    const authHeader = req.headers.get("authorization") || "";

    let appId: string | null = null;
    let userId: string | null = null;

    if (clientId && apiKey) {
      const { data: app } = await supabase
        .from("developer_apps")
        .select("id, user_id, is_active, rate_limit_per_minute, scopes")
        .eq("client_id", clientId)
        .eq("is_active", true)
        .single();

      if (!app) return json({ error: "Invalid client credentials" }, 401);
      appId = app.id;

      if (authHeader.startsWith("Bearer ")) {
        const { data: authZ } = await supabase
          .from("oauth_authorizations")
          .select("user_id, scopes, expires_at, revoked_at")
          .eq("app_id", appId)
          .is("revoked_at", null)
          .single();

        if (authZ && new Date(authZ.expires_at) > new Date()) {
          userId = authZ.user_id;
        }
      }
    } else if (authHeader.startsWith("Bearer ")) {
      const token = authHeader.replace("Bearer ", "");
      const { data: { user }, error } = await supabase.auth.getUser(token);
      if (error || !user) return json({ error: "Unauthorized" }, 401);
      userId = user.id;
    } else {
      return json({ error: "Authentication required. Provide x-client-id + x-api-key or Bearer token." }, 401);
    }

    // Log API access for third-party apps
    if (appId) {
      await supabase.from("api_access_logs").insert({
        app_id: appId,
        user_id: userId,
        endpoint: path,
        method: req.method,
        status_code: 200,
        ip_address: req.headers.get("x-forwarded-for") || "unknown",
      });
    }

    // Route handling
    switch (path) {
      case "balance": {
        if (!userId) return json({ error: "User authorization required" }, 403);
        const { data: wallet } = await supabase
          .from("wallets")
          .select("balance")
          .eq("user_id", userId)
          .single();
        return json({
          user_id: userId,
          balance: wallet?.balance ?? 0,
          currency: "OUSD",
          timestamp: new Date().toISOString(),
        });
      }

      case "profile": {
        if (!userId) return json({ error: "User authorization required" }, 403);
        const { data: profile } = await supabase
          .from("profiles")
          .select("full_name, username, avatar_url, referral_code, created_at")
          .eq("id", userId)
          .single();
        const { data: account } = await supabase
          .from("user_accounts")
          .select("account_number, account_name, account_username")
          .eq("user_id", userId)
          .single();
        return json({
          user_id: userId,
          profile: profile || {},
          account: account || {},
        });
      }

      case "transactions": {
        if (!userId) return json({ error: "User authorization required" }, 403);
        const limit = Math.min(Number(url.searchParams.get("limit") || "50"), 100);
        const offset = Number(url.searchParams.get("offset") || "0");
        const { data: txs } = await supabase
          .from("transactions")
          .select("id, sender_id, receiver_id, amount, note, status, created_at")
          .or(`sender_id.eq.${userId},receiver_id.eq.${userId}`)
          .order("created_at", { ascending: false })
          .range(offset, offset + limit - 1);
        return json({
          transactions: txs || [],
          pagination: { limit, offset, count: txs?.length || 0 },
        });
      }

      case "send": {
        if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
        if (!userId) return json({ error: "User authorization required" }, 403);
        const body = await req.json();
        const { receiver_id, amount, note } = body;
        if (!receiver_id || !amount) return json({ error: "receiver_id and amount required" }, 400);
        const parsedAmount = Number(amount);
        if (!Number.isFinite(parsedAmount) || parsedAmount <= 0) return json({ error: "Invalid amount" }, 400);
        if (receiver_id === userId) return json({ error: "Cannot send to yourself" }, 400);

        const { data: txId, error: txErr } = await supabase.rpc("transfer_funds", {
          p_sender_id: userId,
          p_receiver_id: receiver_id,
          p_amount: parsedAmount,
          p_note: note || "",
          p_currency_code: "OUSD",
        });
        if (txErr) return json({ error: txErr.message }, 400);
        return json({ success: true, transaction_id: txId });
      }

      case "invoices": {
        if (!userId) return json({ error: "User authorization required" }, 403);
        if (req.method === "POST") {
          const body = await req.json();
          const { recipient_id, amount, description, due_date } = body;
          if (!recipient_id || !amount) return json({ error: "recipient_id and amount required" }, 400);
          const { data: inv, error: invErr } = await supabase
            .from("invoices")
            .insert({ sender_id: userId, recipient_id, amount, description: description || "", due_date })
            .select()
            .single();
          if (invErr) return json({ error: invErr.message }, 400);
          return json({ success: true, invoice: inv });
        }
        const { data: invoices } = await supabase
          .from("invoices")
          .select("*")
          .or(`sender_id.eq.${userId},recipient_id.eq.${userId}`)
          .order("created_at", { ascending: false })
          .limit(50);
        return json({ invoices: invoices || [] });
      }

      case "ledger": {
        const limit = Math.min(Number(url.searchParams.get("limit") || "50"), 100);
        const { data: events } = await supabase
          .from("ledger_events")
          .select("id, event_type, amount, status, note, occurred_at, source_table")
          .order("occurred_at", { ascending: false })
          .limit(limit);
        return json({ events: events || [] });
      }

      case "apps/register": {
        if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
        if (!userId) return json({ error: "Authentication required" }, 401);
        const body = await req.json();
        const { app_name, app_description, app_url, redirect_uris, scopes } = body;
        if (!app_name) return json({ error: "app_name required" }, 400);

        const secretBytes = new Uint8Array(32);
        crypto.getRandomValues(secretBytes);
        const clientSecret = "ops_" + Array.from(secretBytes).map(b => b.toString(16).padStart(2, "0")).join("");
        const secretLast4 = clientSecret.slice(-4);

        const encoder = new TextEncoder();
        const hashBuffer = await crypto.subtle.digest("SHA-256", encoder.encode(clientSecret));
        const secretHash = Array.from(new Uint8Array(hashBuffer)).map(b => b.toString(16).padStart(2, "0")).join("");

        const { data: app, error: appErr } = await supabase
          .from("developer_apps")
          .insert({
            user_id: userId,
            app_name,
            app_description: app_description || "",
            app_url: app_url || "",
            redirect_uris: redirect_uris || [],
            scopes: scopes || ["read:balance", "read:profile"],
            client_secret_hash: secretHash,
            client_secret_last4: secretLast4,
          })
          .select("id, client_id, app_name, scopes, created_at")
          .single();

        if (appErr) return json({ error: appErr.message }, 400);
        return json({
          success: true,
          app: { ...app, client_secret: clientSecret },
          message: "Save your client_secret now. It will not be shown again.",
        });
      }

      case "lookup": {
        if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
        const body = await req.json();
        const { username, account_number } = body;
        if (!username && !account_number) return json({ error: "username or account_number required" }, 400);

        if (username) {
          const { data: profile } = await supabase
            .from("profiles")
            .select("id, full_name, username, avatar_url")
            .eq("username", username)
            .single();
          if (!profile) return json({ error: "User not found" }, 404);
          return json({ user: profile });
        }
        const { data: acct } = await supabase
          .from("user_accounts")
          .select("user_id, account_name, account_username, account_number")
          .eq("account_number", account_number)
          .single();
        if (!acct) return json({ error: "Account not found" }, 404);
        return json({ account: acct });
      }

      default:
        return json({
          error: "Unknown endpoint",
          available: [
            "GET /health", "GET /balance", "GET /profile", "GET /transactions",
            "POST /send", "GET|POST /invoices", "GET /ledger", "GET /currencies",
            "POST /apps/register", "POST /lookup",
            "POST /pi-rpc", "POST /pi-rpc/testnet", "POST /pi-rpc/mainnet"
          ],
        }, 404);
    }
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : "Unexpected error";
    return json({ error: msg }, 500);
  }
});
