import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const jsonResponse = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

const parseAllowlist = (raw: string | undefined) =>
  (raw ?? "")
    .split(",")
    .map((item) => item.trim().toLowerCase())
    .filter(Boolean);

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !supabaseServiceKey) {
      return jsonResponse({ error: "Server configuration error" }, 500);
    }

    const supabase: any = createClient(supabaseUrl, supabaseServiceKey);

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return jsonResponse({ error: "Missing auth token" }, 401);
    }

    const token = authHeader.replace("Bearer ", "");
    const authResult = await supabase.auth.getUser(token);
    const user = authResult?.data?.user;

    if (authResult?.error || !user) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    if (!user.email) {
      return jsonResponse({ error: "Email sign-in required" }, 403);
    }

    const adminAllowlist = parseAllowlist(Deno.env.get("ADMIN_DASHBOARD_EMAILS"));
    if (adminAllowlist.length > 0 && !adminAllowlist.includes(user.email.toLowerCase())) {
      return jsonResponse({ error: "Access denied for this account" }, 403);
    }

    const body = await req.json().catch(() => ({})) as Record<string, unknown>;
    const action = body.action as string | undefined;

    if (action === "review_self_send") {
      const transactionId = String(body.transaction_id || "");
      const decision = String(body.decision || "").toLowerCase();
      const reason = String(body.reason || "");

      if (!transactionId) return jsonResponse({ error: "transaction_id is required" }, 400);
      if (decision !== "approve" && decision !== "reject") {
        return jsonResponse({ error: "decision must be approve or reject" }, 400);
      }

      const { data: reviewResult, error: reviewError } = await supabase.rpc("admin_refund_self_send", {
        p_transaction_id: transactionId,
        p_decision: decision,
        p_reason: reason,
        p_admin_email: user.email,
      });
      if (reviewError) return jsonResponse({ error: reviewError.message }, 400);

      return jsonResponse({ success: true, data: reviewResult });
    }

    const requestedLimit = Number(body.limit);
    const requestedOffset = Number(body.offset);
    const limit = Number.isFinite(requestedLimit) ? Math.max(1, Math.min(200, requestedLimit)) : 50;
    const offset = Number.isFinite(requestedOffset) ? Math.max(0, requestedOffset) : 0;

    const historyQuery: any = await supabase
      .from("ledger_events")
      .select("*", { count: "exact" })
      .order("occurred_at", { ascending: false })
      .range(offset, offset + limit - 1);

    const historyRows = historyQuery.data as Record<string, unknown>[] | null;
    const historyError = historyQuery.error;
    const totalHistoryEvents = historyQuery.count;

    if (historyError) return jsonResponse({ error: historyError.message }, 400);

    const userIds = Array.from(
      new Set(
        (historyRows ?? [])
          .flatMap((row: Record<string, unknown>) => [row.actor_user_id, row.related_user_id])
          .filter(Boolean)
      ),
    ) as string[];

    let profiles: Record<string, unknown>[] | null = [];
    let profilesError: { message: string } | null = null;

    if (userIds.length > 0) {
      const profilesQuery: any = await supabase.from("profiles").select("id, full_name, username").in("id", userIds);
      profiles = profilesQuery.data as Record<string, unknown>[] | null;
      profilesError = profilesQuery.error;
    }

    if (profilesError) return jsonResponse({ error: profilesError.message }, 400);

    const profileById = new Map(
      (profiles ?? []).map((p: Record<string, unknown>) => [
        p.id as string,
        {
          full_name: (p.full_name as string) || "",
          username: (p.username as string) || "",
        },
      ]),
    );

    const normalizedHistory = (historyRows ?? []).map((row: Record<string, unknown>) => ({
      ...row,
      actor_profile: profileById.get(row.actor_user_id as string) ?? null,
      related_profile: profileById.get(row.related_user_id as string) ?? null,
    }));

    const usersCountQuery: any = await supabase
      .from("profiles")
      .select("id", { count: "exact", head: true });

    const totalUsers = usersCountQuery.count;
    const usersCountError = usersCountQuery.error;

    if (usersCountError) return jsonResponse({ error: usersCountError.message }, 400);

    const pageAmountSum = normalizedHistory.reduce((sum: number, row: any) => sum + Number(row.amount || 0), 0);

    return jsonResponse({
      success: true,
      data: {
        summary: {
          total_history_events: totalHistoryEvents ?? 0,
          total_users: totalUsers ?? 0,
          page_amount_sum: pageAmountSum,
          page_limit: limit,
          page_offset: offset,
        },
        history: normalizedHistory,
      },
    });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Unexpected error";
    return jsonResponse({ error: message }, 500);
  }
});
