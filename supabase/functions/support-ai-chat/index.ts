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

const sanitizeText = (value: unknown, max = 2000) =>
  String(value ?? "").replace(/\s+/g, " ").trim().slice(0, max);

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !supabaseServiceKey) throw new Error("Server configuration error");

    const supabase: any = createClient(supabaseUrl, supabaseServiceKey);
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) throw new Error("Missing auth token");
    const token = authHeader.replace("Bearer ", "");
    const authResult = await supabase.auth.getUser(token);
    const user = authResult?.data?.user;
    if (authResult?.error || !user) throw new Error("Unauthorized");

    const body = await req.json();
    const conversationId = sanitizeText(body?.conversation_id, 80);
    const userMessage = sanitizeText(body?.message, 1200);
    if (!conversationId || !userMessage) throw new Error("conversation_id and message are required");

    const { data: conversation, error: convoError } = await supabase
      .from("support_conversations").select("id, user_id").eq("id", conversationId).maybeSingle();
    if (convoError || !conversation) throw new Error("Conversation not found");

    const { data: isAgentResult } = await supabase.rpc("is_support_agent", { p_user_id: user.id });
    const isAgent = Boolean(isAgentResult);
    if (!isAgent && conversation.user_id !== user.id) throw new Error("Unauthorized conversation");

    const { data: faqRows } = await supabase.from("support_faq_items").select("question, answer").limit(12);
    const faqContext = (faqRows || [])
      .map((row: any) => `Q: ${sanitizeText(row.question, 200)}\nA: ${sanitizeText(row.answer, 400)}`)
      .join("\n\n");

    const openRouterKey = Deno.env.get("OPENROUTER_API_KEY");
    const model = Deno.env.get("OPENROUTER_MODEL") || "upstage/solar-pro-3:free";
    let aiReply = "";

    if (openRouterKey) {
      const aiRes = await fetch("https://openrouter.ai/api/v1/chat/completions", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${openRouterKey}`,
          "Content-Type": "application/json",
          "HTTP-Referer": "https://openpay.app",
          "X-Title": "OpenPay Support",
        },
        body: JSON.stringify({
          model, temperature: 0.2, max_tokens: 450,
          messages: [
            { role: "system", content: "You are OpenPay support assistant. Give short, accurate answers about OpenPay wallet, merchant portal, checkout, QR, virtual card, payments, refunds, and account help. If unsure, say you need a live support agent. Never invent policy. Keep answer under 8 lines." },
            { role: "system", content: faqContext || "No FAQ context available." },
            { role: "user", content: userMessage },
          ],
        }),
      });

      if (aiRes.ok) {
        const aiPayload = await aiRes.json();
        aiReply = sanitizeText(aiPayload?.choices?.[0]?.message?.content, 2400);
      } else {
        console.error("OpenRouter error:", await aiRes.text());
      }
    }

    if (!aiReply) {
      const fallbackFromFaq = (faqRows || []).find((row: any) => {
        const question = sanitizeText(row.question, 200).toLowerCase();
        const msg = userMessage.toLowerCase();
        return msg.split(" ").some((t: string) => t.length > 4 && question.includes(t));
      });
      aiReply = fallbackFromFaq
        ? `${sanitizeText(fallbackFromFaq.answer, 500)}\n\nIf this does not solve it, open Messages and include your screenshot/transaction ID.`
        : "Thanks for contacting OpenPay support. I can help with wallet, checkout, merchant portal, and transfers. If this issue is urgent, use Messages and include screenshot plus transaction ID.";
    }

    const { data: agentProfile } = await supabase
      .from("profiles").select("id").in("username", ["openpay", "wainfoundation"]).limit(1).maybeSingle();
    const senderId = agentProfile?.id || user.id;

    const { error: insertError } = await supabase.from("support_messages").insert({
      conversation_id: conversationId, sender_id: senderId, sender_role: "agent", message: aiReply,
    });
    if (insertError) throw new Error(insertError.message);

    await supabase.from("support_conversations").update({ last_message_at: new Date().toISOString() }).eq("id", conversationId);

    return jsonResponse({ reply: aiReply });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Unexpected error";
    return jsonResponse({ error: message }, 400);
  }
});
