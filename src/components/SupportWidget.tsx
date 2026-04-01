import { useEffect, useMemo, useState } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import { ArrowLeft, HelpCircle, Image as ImageIcon, MessageCircle, Search, Send, X } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import BrandLogo from "@/components/BrandLogo";
import { toast } from "sonner";

type SupportConversation = {
  id: string;
  user_id: string;
  status: string;
  last_message_at: string | null;
  priority?: string;
  category?: string;
  ticket_id?: string | null;
  created_at: string;
};

type SupportMessage = {
  id: string;
  conversation_id: string;
  sender_id: string;
  sender_role: "user" | "agent";
  message: string;
  attachment_url?: string | null;
  attachment_type?: string | null;
  message_status?: string;
  priority?: string;
  category?: string;
  created_at: string;
  read_at?: string | null;
};

type SupportFaqCategory = {
  id: string;
  title: string;
  description: string;
};

type SupportFaqItem = {
  id: string;
  category_id: string | null;
  question: string;
  answer: string;
  priority?: string;
  category_name?: string;
};

type SupportCategory = {
  id: string;
  name: string;
  description: string;
  icon?: string;
  color?: string;
  is_active?: boolean;
};

type SupportPriority = {
  id: string;
  level: string;
  description: string;
  color?: string;
  auto_assign_hours?: number;
};

type SupportConversationRow = SupportConversation & {
  profile?: { full_name?: string | null; username?: string | null; account_number?: string | null } | null;
};
const SUPPORT_WIDGET_DRAFT_KEY = "openpay_support_widget_draft_v1";

const fileToDataUrl = (file: File) =>
  new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result || ""));
    reader.onerror = () => reject(new Error("Failed to read image"));
    reader.readAsDataURL(file);
  });

const SupportWidget = () => {
  const location = useLocation();
  const navigate = useNavigate();
  const hiddenScrollbarClass = "[scrollbar-width:none] [-ms-overflow-style:none] [&::-webkit-scrollbar]:hidden";
  const [open, setOpen] = useState(false);
  const [activeTab, setActiveTab] = useState<"home" | "messages" | "help">("home");
  const [userId, setUserId] = useState<string | null>(null);
  const [isAgent, setIsAgent] = useState(false);
  const [conversation, setConversation] = useState<SupportConversation | null>(null);
  const [messages, setMessages] = useState<SupportMessage[]>([]);
  const [messageDraft, setMessageDraft] = useState("");
  const [attachmentFile, setAttachmentFile] = useState<File | null>(null);
  const [attachmentDataUrl, setAttachmentDataUrl] = useState<string | null>(null);
  const [attachmentName, setAttachmentName] = useState<string>("");
  const [attachmentType, setAttachmentType] = useState<string>("");
  const [attachmentPreview, setAttachmentPreview] = useState<string | null>(null);
  const [uploadingAttachment, setUploadingAttachment] = useState(false);
  const [aiReplying, setAiReplying] = useState(false);
  const [faqCategories, setFaqCategories] = useState<SupportFaqCategory[]>([]);
  const [faqItems, setFaqItems] = useState<SupportFaqItem[]>([]);
  const [helpQuery, setHelpQuery] = useState("");
  const [allConversations, setAllConversations] = useState<SupportConversationRow[]>([]);
  const [selectedConversationId, setSelectedConversationId] = useState<string | null>(null);
  const [supportTicketId, setSupportTicketId] = useState<string | null>(null);
  const [supportCategories, setSupportCategories] = useState<SupportCategory[]>([]);
  const [supportPriorities, setSupportPriorities] = useState<SupportPriority[]>([]);
  const [selectedCategory, setSelectedCategory] = useState<string>("general");
  const [selectedPriority, setSelectedPriority] = useState<string>("normal");
  const [showTicketForm, setShowTicketForm] = useState(false);
  const [ticketSubject, setTicketSubject] = useState("");
  const [ticketDescription, setTicketDescription] = useState("");
  const [imageViewerUrl, setImageViewerUrl] = useState<string | null>(null);
  const isSupportPage = location.pathname === "/support";

  useEffect(() => {
    if (typeof window === "undefined") return;
    try {
      const raw = window.sessionStorage.getItem(SUPPORT_WIDGET_DRAFT_KEY);
      if (!raw) return;
      const saved = JSON.parse(raw) as {
        open?: boolean;
        activeTab?: "home" | "messages" | "help";
        messageDraft?: string;
        selectedConversationId?: string | null;
        attachmentDataUrl?: string | null;
        attachmentName?: string;
        attachmentType?: string;
      };
      if (saved.open === true || saved.open === false) setOpen(Boolean(saved.open));
      if (saved.activeTab === "home" || saved.activeTab === "messages" || saved.activeTab === "help") {
        setActiveTab(saved.activeTab);
      }
      if (typeof saved.messageDraft === "string") setMessageDraft(saved.messageDraft);
      if (typeof saved.selectedConversationId === "string" || saved.selectedConversationId === null) {
        setSelectedConversationId(saved.selectedConversationId);
      }
      if (typeof saved.attachmentDataUrl === "string" && saved.attachmentDataUrl) {
        setAttachmentDataUrl(saved.attachmentDataUrl);
        setAttachmentName(String(saved.attachmentName || "support-image.jpg"));
        setAttachmentType(String(saved.attachmentType || "image/jpeg"));
      }
    } catch {
      // no-op
    }
  }, []);

  useEffect(() => {
    if (typeof window === "undefined") return;
    try {
      const draftData = JSON.stringify({
        open,
        activeTab,
        messageDraft,
        selectedConversationId,
        attachmentDataUrl,
        attachmentName,
        attachmentType,
      });
      // Only save if it's not too large for sessionStorage (limit is usually ~5MB)
      if (draftData.length < 4000000) {
        window.sessionStorage.setItem(SUPPORT_WIDGET_DRAFT_KEY, draftData);
      }
    } catch (e) {
      console.warn("Failed to save support widget draft to sessionStorage:", e);
    }
  }, [open, activeTab, messageDraft, selectedConversationId, attachmentDataUrl, attachmentName, attachmentType]);

  useEffect(() => {
    const boot = async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;
      setUserId(user.id);

      const { data: profile } = await supabase
        .from("profiles")
        .select("username")
        .eq("id", user.id)
        .maybeSingle();
      const isAgentUser = ["openpay", "wainfoundation"].includes(String(profile?.username || "").toLowerCase());
      if (isAgentUser) setIsAgent(true);

      const { data: convoRows } = await supabase
        .from("support_conversations")
        .select("id, user_id, status, last_message_at, created_at")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false })
        .limit(1);
      const existing = (convoRows || [])[0] as SupportConversation | undefined;
      if (existing) {
        setConversation(existing);
        setSelectedConversationId(existing.id);
      }

      const { data: ticketRows } = await supabase
        .from("support_tickets")
        .select("id, status, created_at")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false })
        .limit(1);
      const latestTicket = (ticketRows || [])[0] as { id?: string } | undefined;
      if (latestTicket?.id) {
        setSupportTicketId(String(latestTicket.id));
      }

      const { data: catRows } = await supabase
        .from("support_faq_categories")
        .select("id, title, description")
        .order("sort_order", { ascending: true });
      setFaqCategories((catRows || []) as SupportFaqCategory[]);

      const { data: itemRows } = await supabase
        .from("support_faq_items")
        .select("id, category_id, question, answer");
      setFaqItems((itemRows || []) as SupportFaqItem[]);

      // Load support categories and priorities
      const { data: catData } = await (supabase as any)
        .from("support_categories")
        .select("id, name, description, icon, color, is_active")
        .eq("is_active", true)
        .order("name");
      setSupportCategories((catData || []) as SupportCategory[]);

      const { data: priorityData } = await supabase
        .from("support_priorities")
        .select("id, level, description, color, auto_assign_hours")
        .order("auto_assign_hours");
      setSupportPriorities((priorityData || []) as SupportPriority[]);
    };
    void boot();
  }, []);

  useEffect(() => {
    const handler = (event: Event) => {
      const detail = (event as CustomEvent<{ tab?: "home" | "messages" | "help" }>).detail;
      const tab = detail?.tab === "home" || detail?.tab === "help" ? detail.tab : "messages";
      setActiveTab(tab);
      navigate(`/support?tab=${tab}`);
    };
    window.addEventListener("open-support-widget", handler as EventListener);
    return () => window.removeEventListener("open-support-widget", handler as EventListener);
  }, [navigate]);

  useEffect(() => {
    if (!open || isSupportPage) return;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = previousOverflow;
    };
  }, [open, isSupportPage]);

  useEffect(() => {
    if (!isSupportPage) return;
    const params = new URLSearchParams(location.search);
    const tab = params.get("tab");
    if (tab === "home" || tab === "messages" || tab === "help") {
      setActiveTab(tab);
      return;
    }
    setActiveTab("messages");
  }, [isSupportPage, location.search]);

  useEffect(() => {
    if (!isAgent) return;
    const loadInbox = async () => {
      try {
        const { data, error } = await supabase
          .from("support_conversations")
          .select("id, user_id, status, last_message_at, created_at")
          .order("last_message_at", { ascending: false })
          .limit(30);
        if (error) throw error;

        const convoRows = (data || []) as SupportConversation[];
        const userIds = Array.from(new Set(convoRows.map((row) => row.user_id).filter(Boolean)));

        const profilesResponse = userIds.length
          ? await supabase.from("profiles").select("id, full_name, username").in("id", userIds)
          : { data: [] as Array<{ id: string; full_name: string | null; username: string | null }>, error: null };
        const accountsResponse = userIds.length
          ? await supabase.from("user_accounts").select("user_id, account_number").in("user_id", userIds)
          : { data: [] as Array<{ user_id: string; account_number: string | null }>, error: null };

        const profiles = profilesResponse.data || [];
        const accounts = accountsResponse.error ? [] : accountsResponse.data || [];

        const profileMap = new Map(
          profiles.map((row) => [
            row.id,
            { full_name: row.full_name || null, username: row.username || null, account_number: null as string | null },
          ]),
        );
        for (const account of accounts) {
          const existing = profileMap.get(account.user_id) || { full_name: null, username: null, account_number: null as string | null };
          profileMap.set(account.user_id, { ...existing, account_number: account.account_number || null });
        }
        const merged = convoRows.map((row) => ({
          ...row,
          profile: profileMap.get(row.user_id) || null,
        }));
        setAllConversations(merged);
      } catch (error) {
        const message = error instanceof Error ? error.message : "Failed to load support conversations";
        toast.error(message);
      }
    };
    void loadInbox();
  }, [isAgent]);

  useEffect(() => {
    const loadMessages = async (conversationId: string) => {
      const { data } = await supabase
        .from("support_messages")
        .select("id, conversation_id, sender_id, sender_role, message, attachment_url, attachment_type, message_status, priority, category, created_at, read_at")
        .eq("conversation_id", conversationId)
        .order("created_at", { ascending: true });
      setMessages((data || []) as SupportMessage[]);
    };
    if (selectedConversationId) void loadMessages(selectedConversationId);
  }, [selectedConversationId]);

  useEffect(() => {
    if (attachmentDataUrl) {
      setAttachmentPreview(attachmentDataUrl);
      return;
    }
    if (!attachmentFile) {
      setAttachmentPreview(null);
      return;
    }
    const previewUrl = URL.createObjectURL(attachmentFile);
    setAttachmentPreview(previewUrl);
    return () => URL.revokeObjectURL(previewUrl);
  }, [attachmentDataUrl, attachmentFile]);

  const filteredFaqs = useMemo(() => {
    const query = helpQuery.trim().toLowerCase();
    if (!query) return faqItems;
    return faqItems.filter((item) => item.question.toLowerCase().includes(query) || item.answer.toLowerCase().includes(query));
  }, [faqItems, helpQuery]);

  const ensureConversation = async () => {
    if (conversation || !userId) return conversation;
    const { data, error } = await supabase
      .from("support_conversations")
      .insert({ user_id: userId })
      .select("id, user_id, status, last_message_at, created_at")
      .single();
    if (error) {
      toast.error(error.message || "Failed to start conversation");
      return null;
    }
    setConversation(data as SupportConversation);
    setSelectedConversationId((data as SupportConversation).id);
    return data as SupportConversation;
  };

  const ensureSupportTicket = async (initialMessage: string) => {
    if (!userId) return null;
    const fallbackMessage = initialMessage.trim() || "Support request";

    if (supportTicketId) {
      const { error } = await supabase
        .from("support_tickets")
        .update({ status: "open", message: fallbackMessage })
        .eq("id", supportTicketId)
        .eq("user_id", userId);
      if (error) {
        toast.error(error.message || "Failed to update support ticket");
        return null;
      }
      return supportTicketId;
    }

    const { data, error } = await supabase
      .from("support_tickets")
      .insert({
        user_id: userId,
        subject: "Support chat request",
        message: fallbackMessage,
        status: "open",
      })
      .select("id")
      .single();
    if (error) {
      toast.error(error.message || "Failed to create support ticket");
      return null;
    }
    const nextId = String((data as { id?: string } | null)?.id || "");
    if (!nextId) {
      toast.error("Failed to create support ticket");
      return null;
    }
    setSupportTicketId(nextId);
    return nextId;
  };

  const sendMessage = async () => {
    const text = messageDraft.trim();
    if (!userId) return;
    if (!text && !attachmentFile && !attachmentDataUrl) return;
    const ticketMessage = text || (attachmentFile || attachmentDataUrl ? "Image attachment in support chat" : "Support request");
    if (!isAgent) {
      const ticketId = await ensureSupportTicket(ticketMessage);
      if (!ticketId) return;
    }

    const convo = isAgent ? null : await ensureConversation();
    const conversationId = isAgent ? selectedConversationId : convo?.id;
    if (!conversationId) {
      toast.error("Select a conversation to reply.");
      return;
    }
    let attachmentUrl = "";
    if (attachmentFile || attachmentDataUrl) {
      setUploadingAttachment(true);
      try {
        const uploadFile =
          attachmentFile ||
          (() => {
            const bytes = atob((attachmentDataUrl || "").split(",")[1] || "");
            const array = new Uint8Array(bytes.length);
            for (let i = 0; i < bytes.length; i += 1) array[i] = bytes.charCodeAt(i);
            const mime = attachmentType || "image/jpeg";
            return new File([array], attachmentName || "support-image.jpg", { type: mime });
          })();
        const safeName = uploadFile.name.replace(/[^a-zA-Z0-9._-]/g, "_");
        const filePath = `${userId}/${Date.now()}-${safeName}`;
        const { error: uploadError } = await supabase.storage
          .from("support-attachments")
          .upload(filePath, uploadFile, { upsert: true, contentType: uploadFile.type });
        if (uploadError) {
          throw new Error(uploadError.message || "Upload failed");
        }
        const { data: publicData } = supabase.storage.from("support-attachments").getPublicUrl(filePath);
        attachmentUrl = publicData?.publicUrl || "";
        if (!attachmentUrl) {
          throw new Error("Failed to get attachment URL");
        }
      } catch (error) {
        toast.error(error instanceof Error ? error.message : "Failed to upload image");
        setUploadingAttachment(false);
        return;
      } finally {
        setUploadingAttachment(false);
      }
    }

    const { error } = await supabase
      .from("support_messages")
      .insert({
        conversation_id: conversationId,
        sender_id: userId,
        sender_role: isAgent ? "agent" : "user",
        message: text || (attachmentUrl ? "Image attached" : ""),
        attachment_url: attachmentUrl || null,
        attachment_type: attachmentFile?.type || attachmentType || null,
        message_status: "sent",
        priority: selectedPriority,
        category: selectedCategory,
      });
    if (error) {
      toast.error(error.message || "Failed to send message");
      return;
    }
    setMessageDraft("");
    setAttachmentFile(null);
    setAttachmentDataUrl(null);
    setAttachmentName("");
    setAttachmentType("");
    setMessages((prev) => [
      ...prev,
      {
        id: typeof crypto !== "undefined" && crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).substring(2),
        conversation_id: conversationId,
        sender_id: userId,
        sender_role: isAgent ? "agent" : "user",
        message: text || (attachmentUrl ? "Image attached" : ""),
        attachment_url: attachmentUrl || null,
        attachment_type: attachmentFile?.type || attachmentType || null,
        message_status: "sent",
        priority: selectedPriority,
        category: selectedCategory,
        created_at: new Date().toISOString(),
      },
    ]);
    const { error: convoUpdateError } = await supabase
      .from("support_conversations")
      .update({ 
        last_message_at: new Date().toISOString(),
        priority: selectedPriority,
        category: selectedCategory
      })
      .eq("id", conversationId);
    if (convoUpdateError) {
      toast.error(convoUpdateError.message || "Message sent but failed to refresh conversation");
    }

    if (isAgent) return;

    setAiReplying(true);
    try {
      if (!convo) {
        throw new Error("Conversation not found");
      }
      const { data: aiData, error: aiError } = await supabase.functions.invoke("support-ai-chat", {
        body: {
          conversation_id: convo.id,
          message: text,
        },
      });
      if (aiError) {
        toast.error(aiError.message || "AI support is temporarily unavailable.");
        return;
      }

      const aiReply = typeof aiData?.reply === "string" ? aiData.reply.trim() : "";
      if (!aiReply) return;
      setMessages((prev) => [
        ...prev,
        {
          id: typeof crypto !== "undefined" && crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).substring(2),
          conversation_id: convo.id,
          sender_id: "openpay-ai",
          sender_role: "agent",
          message: aiReply,
          created_at: new Date().toISOString(),
        },
      ]);
    } catch (error) {
      const message = error instanceof Error ? error.message : "AI support is temporarily unavailable.";
      toast.error(message);
    } finally {
      setAiReplying(false);
    }
  };

  const selectConversation = (id: string) => {
    setSelectedConversationId(id);
    setActiveTab("messages");
  };
  const selectedConversation = allConversations.find((row) => row.id === selectedConversationId) || null;

  const allowSupportButton =
    location.pathname.startsWith("/menu") ||
    location.pathname.startsWith("/merchant-onboarding");

  return (
    <>
      {allowSupportButton && (
        <button
          onClick={() => navigate("/support?tab=messages")}
          className="fixed bottom-24 right-4 z-[90] flex h-12 w-12 items-center justify-center rounded-full bg-paypal-blue text-white shadow-lg shadow-black/20 md:bottom-6 md:right-6"
          aria-label="Open support"
        >
          <HelpCircle className="h-6 w-6" />
        </button>
      )}

      {(open || isSupportPage) && (
        <div className={isSupportPage ? "min-h-screen bg-gradient-to-b from-[#f1f6ff] to-background px-0 pt-0 pb-0 sm:px-4 sm:pt-4 sm:pb-6" : "fixed inset-0 z-[100]"}>
          {!isSupportPage ? <div className="absolute inset-0 bg-black/30 md:hidden" onClick={() => setOpen(false)} /> : null}
          <div
            className={
              isSupportPage
                ? "mx-auto flex min-h-screen w-full flex-col rounded-none border-0 bg-white shadow-none sm:min-h-[calc(100vh-2.5rem)] sm:max-w-6xl sm:rounded-3xl sm:border sm:border-border sm:shadow-sm"
                : "absolute inset-0 flex flex-col rounded-none bg-white shadow-2xl md:inset-auto md:bottom-6 md:right-6 md:h-[min(760px,calc(100vh-8rem))] md:w-[380px] md:max-w-[90vw] md:rounded-2xl md:border md:border-border"
            }
          >
            <div className="flex items-center justify-between border-b border-border px-4 py-3">
              <div className="flex items-center gap-2">
                {isSupportPage ? (
                  <button onClick={() => navigate(-1)} className="flex h-8 w-8 items-center justify-center rounded-full border border-border">
                    <ArrowLeft className="h-4 w-4" />
                  </button>
                ) : null}
                <BrandLogo className="h-7 w-7" />
                <div>
                  <p className="text-sm font-semibold text-foreground">OpenPay Support</p>
                  <p className="text-xs text-muted-foreground">How can we help?</p>
                </div>
              </div>
              {!isSupportPage ? (
                <button onClick={() => setOpen(false)} className="flex h-8 w-8 items-center justify-center rounded-full border border-border">
                  <X className="h-4 w-4" />
                </button>
              ) : null}
            </div>

            {isSupportPage ? (
              <div className="border-b border-border px-4 py-2">
                <div className="inline-flex rounded-full bg-secondary/60 p-1">
                  <button
                    onClick={() => setActiveTab("home")}
                    className={`rounded-full px-4 py-1.5 text-xs font-semibold ${activeTab === "home" ? "bg-white text-foreground shadow-sm" : "text-muted-foreground"}`}
                  >
                    Home
                  </button>
                  <button
                    onClick={() => setActiveTab("messages")}
                    className={`rounded-full px-4 py-1.5 text-xs font-semibold ${activeTab === "messages" ? "bg-white text-foreground shadow-sm" : "text-muted-foreground"}`}
                  >
                    Messages
                  </button>
                  <button
                    onClick={() => setActiveTab("help")}
                    className={`rounded-full px-4 py-1.5 text-xs font-semibold ${activeTab === "help" ? "bg-white text-foreground shadow-sm" : "text-muted-foreground"}`}
                  >
                    Help
                  </button>
                </div>
              </div>
            ) : null}

            <div className={`flex-1 min-h-0 px-4 pt-3 ${isSupportPage ? "pb-4" : ""}`}>
              {activeTab === "home" && (
                <div className={`space-y-3 ${isSupportPage ? "mx-auto w-full max-w-3xl pt-3" : ""}`}>
                  <button onClick={() => setActiveTab("messages")} className="w-full rounded-xl border border-border p-3 text-left">
                    <p className="text-sm font-semibold text-foreground">Send us a message</p>
                    <p className="text-xs text-muted-foreground">We'll be back online later today</p>
                  </button>
                  <button onClick={() => setActiveTab("help")} className="w-full rounded-xl border border-border p-3 text-left">
                    <p className="text-sm font-semibold text-foreground">Search for help</p>
                    <p className="text-xs text-muted-foreground">Browse FAQs and guides</p>
                  </button>
                </div>
              )}

              {activeTab === "messages" && (
                <div className="mt-2 flex h-full min-h-0 flex-1 flex-col">
                  {isAgent && (
                    <div className={`mb-2 ${isSupportPage ? "max-h-40 md:max-h-48" : "max-h-32"} overflow-y-auto rounded-lg border border-border bg-white ${hiddenScrollbarClass}`}>
                      {allConversations.map((row) => (
                        <button
                          key={row.id}
                          onClick={() => selectConversation(row.id)}
                          className={`flex w-full items-center justify-between px-3 py-2 text-left text-xs ${selectedConversationId === row.id ? "bg-blue-50 text-blue-700" : "text-foreground"}`}
                        >
                          <span className="flex flex-col">
                            <span>{row.profile?.username ? `@${row.profile.username}` : row.user_id.slice(0, 8)}</span>
                            <span className="text-[10px] text-muted-foreground">{row.profile?.account_number || "No account number"}</span>
                          </span>
                          <span className="text-[10px] text-muted-foreground">{row.last_message_at ? new Date(row.last_message_at).toLocaleDateString() : ""}</span>
                        </button>
                      ))}
                      {!allConversations.length && <p className="px-3 py-2 text-xs text-muted-foreground">No conversations yet.</p>}
                    </div>
                  )}
                  {isAgent && selectedConversation ? (
                    <div className="mb-2 rounded-lg border border-border bg-secondary/20 px-3 py-2 text-xs">
                      <p className="font-semibold text-foreground">
                        {selectedConversation.profile?.username ? `@${selectedConversation.profile.username}` : selectedConversation.user_id.slice(0, 8)}
                      </p>
                      <p className="text-muted-foreground">
                        Account: {selectedConversation.profile?.account_number || "Not available"}
                      </p>
                    </div>
                  ) : null}
                  <div className={`min-h-0 flex-1 overflow-y-auto rounded-lg border border-border ${isSupportPage ? "bg-[#f8fbff]" : "bg-white"} p-3 text-sm ${hiddenScrollbarClass}`}>
                    {messages.length === 0 ? (
                      <p className="text-xs text-muted-foreground">No messages yet.</p>
                    ) : (
                      messages.map((msg) => (
                        <div key={msg.id} className={`mb-2 flex ${msg.sender_role === "agent" ? "justify-start" : "justify-end"}`}>
                          <div className={`max-w-[82%] rounded-2xl px-3 py-2 text-xs shadow-sm ${msg.sender_role === "agent" ? "bg-white text-foreground border border-border/70" : "bg-paypal-blue text-white"}`}>
                            {msg.message}
                            {msg.attachment_url ? (
                              <div className="mt-2 overflow-hidden rounded-lg border border-white/20 bg-white/10">
                                <button
                                  type="button"
                                  className="block w-full"
                                  onClick={() => setImageViewerUrl(msg.attachment_url || null)}
                                >
                                  <img src={msg.attachment_url} alt="Support attachment" className="max-h-48 w-full object-cover" />
                                </button>
                                <button
                                  type="button"
                                  onClick={() => setImageViewerUrl(msg.attachment_url || null)}
                                  className="w-full border-t border-white/20 px-2 py-1.5 text-left text-[11px] font-semibold text-white/90"
                                >
                                  View image
                                </button>
                              </div>
                            ) : null}
                          </div>
                        </div>
                      ))
                    )}
                  </div>
                  <div className="mt-2 flex items-center gap-2">
                    <Input value={messageDraft} onChange={(e) => setMessageDraft(e.target.value)} placeholder="Send us a message" className="h-9 rounded-full" />
                    <label className="flex h-9 w-9 items-center justify-center rounded-full border border-border text-foreground">
                      <input
                        type="file"
                        accept="image/*"
                        className="hidden"
                        onChange={async (event) => {
                          const file = event.target.files?.[0] ?? null;
                          if (!file) {
                            setAttachmentFile(null);
                            setAttachmentDataUrl(null);
                            setAttachmentName("");
                            setAttachmentType("");
                            return;
                          }
                          setAttachmentFile(file);
                          setAttachmentName(file.name);
                          setAttachmentType(file.type);
                          try {
                            const dataUrl = await fileToDataUrl(file);
                            setAttachmentDataUrl(dataUrl);
                          } catch (error) {
                            toast.error(error instanceof Error ? error.message : "Failed to load image");
                          }
                        }}
                      />
                      <ImageIcon className="h-4 w-4" />
                    </label>
                    <Button
                      onClick={sendMessage}
                      disabled={aiReplying || uploadingAttachment || (!messageDraft.trim() && !attachmentFile && !attachmentDataUrl)}
                      className="h-9 rounded-full bg-paypal-blue text-white hover:bg-[#004dc5]"
                    >
                      <Send className="h-4 w-4" />
                    </Button>
                  </div>
                  {attachmentPreview ? (
                    <div className="mt-2 rounded-lg border border-border p-2">
                      <div className="flex items-center justify-between">
                        <p className="text-xs text-muted-foreground">Image attached</p>
                        <button
                          type="button"
                          onClick={() => {
                            setAttachmentFile(null);
                            setAttachmentDataUrl(null);
                            setAttachmentName("");
                            setAttachmentType("");
                          }}
                          className="text-xs font-semibold text-paypal-blue"
                        >
                          Remove
                        </button>
                      </div>
                      <button type="button" className="mt-2 block w-full" onClick={() => setImageViewerUrl(attachmentPreview)}>
                        <img src={attachmentPreview} alt="Attachment preview" className="max-h-40 w-full rounded-md object-cover" />
                      </button>
                      <button
                        type="button"
                        onClick={() => setImageViewerUrl(attachmentPreview)}
                        className="mt-2 w-full text-xs font-semibold text-paypal-blue"
                      >
                        View full image
                      </button>
                    </div>
                  ) : null}
                </div>
              )}

              {activeTab === "help" && (
                <div className={`mt-2 flex h-full min-h-0 flex-1 flex-col ${isSupportPage ? "mx-auto w-full max-w-4xl" : ""}`}>
                  <div className="relative">
                    <Search className="absolute left-3 top-2.5 h-4 w-4 text-muted-foreground" />
                    <Input value={helpQuery} onChange={(e) => setHelpQuery(e.target.value)} placeholder="Search for help" className="h-9 rounded-full pl-9" />
                  </div>
                  <div className={`mt-3 min-h-0 flex-1 space-y-3 overflow-y-auto pb-3 ${hiddenScrollbarClass}`}>
                    {faqCategories.map((cat) => (
                      <div key={cat.id} className="rounded-lg border border-border p-3">
                        <p className="text-sm font-semibold text-foreground">{cat.title}</p>
                        <p className="text-xs text-muted-foreground">{cat.description}</p>
                        <div className="mt-2 space-y-2">
                          {filteredFaqs.filter((item) => item.category_id === cat.id).slice(0, 5).map((item) => (
                            <div key={item.id} className="rounded-md border border-border px-3 py-2 text-xs">
                              <p className="font-semibold text-foreground">{item.question}</p>
                              <p className="mt-1 text-muted-foreground">{item.answer}</p>
                            </div>
                          ))}
                        </div>
                      </div>
                    ))}
                    {!faqCategories.length && <p className="text-xs text-muted-foreground">No FAQs yet.</p>}
                  </div>
                </div>
              )}
            </div>

            {!isSupportPage ? (
              <div className="mt-3 border-t border-border px-4 py-2">
                <div className="flex items-center justify-between text-xs text-muted-foreground">
                  <button onClick={() => setActiveTab("home")} className={`flex items-center gap-1 ${activeTab === "home" ? "text-foreground" : ""}`}>
                    <HelpCircle className="h-4 w-4" /> Home
                  </button>
                  <button onClick={() => setActiveTab("messages")} className={`flex items-center gap-1 ${activeTab === "messages" ? "text-foreground" : ""}`}>
                    <MessageCircle className="h-4 w-4" /> Messages
                  </button>
                  <button onClick={() => setActiveTab("help")} className={`flex items-center gap-1 ${activeTab === "help" ? "text-foreground" : ""}`}>
                    <Search className="h-4 w-4" /> Help
                  </button>
                </div>
              </div>
            ) : null}
          </div>
        </div>
      )}
      <Dialog open={Boolean(imageViewerUrl)} onOpenChange={(openState) => { if (!openState) setImageViewerUrl(null); }}>
        <DialogContent className="w-[95vw] max-w-5xl rounded-3xl p-4 sm:p-6">
          <DialogTitle className="text-lg font-bold text-foreground">Support image</DialogTitle>
          <DialogDescription className="text-sm text-muted-foreground">
            Full-size preview of the attached image.
          </DialogDescription>
          {imageViewerUrl ? (
            <div className="mt-2 overflow-hidden rounded-2xl border border-border bg-black/90">
              <img src={imageViewerUrl} alt="Support attachment full size" className="max-h-[78vh] w-full object-contain" />
            </div>
          ) : (
            <p className="text-sm text-muted-foreground">No image available.</p>
          )}
        </DialogContent>
      </Dialog>
    </>
  );
};

export default SupportWidget;
