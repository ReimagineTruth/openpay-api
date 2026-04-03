import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import ReactMarkdown from "react-markdown";
import {
  Send, Bot, User, Sparkles, PieChart, Shield, Wallet, Store, Coins,
  AlertTriangle, Plus, Menu, ChevronRight, X, UserCircle, CreditCard,
  ArrowLeftRight, History, FileText
} from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet";
import BrandLogo from "@/components/BrandLogo";
import SplashScreen from "@/components/SplashScreen";

type Message = {
  id: string;
  role: "user" | "assistant";
  content: string;
  timestamp: string;
};

type SpendingCategory = {
  name: string;
  amount: number;
  percentage: number;
  color: string;
};

type BudgetAlert = {
  category: string;
  spent: number;
  limit: number;
  percentage: number;
};

type FinancialInsight = {
  type: string;
  title: string;
  description: string;
  value?: string;
  trend?: "up" | "down" | "stable";
};

const QUICK_TOPICS = [
  { icon: "💰", label: "Check Balance", prompt: "What is my current balance and account summary?" },
  { icon: "💸", label: "Send Money", prompt: "How do I send money to another user?" },
  { icon: "💳", label: "Top-up", prompt: "What are my top-up options?" },
  { icon: "💱", label: "Currency", prompt: "What currencies do you support and how do I exchange?" },
  { icon: "🏪", label: "Merchant", prompt: "How do I become a merchant and set up my store?" },
  { icon: "🔗", label: "Payment Links", prompt: "How do I create and share payment links?" },
  { icon: "⛏️", label: "Mining", prompt: "How does Pi Network mining work on OpenPay?" },
  { icon: "💎", label: "Staking", prompt: "How do I stake and earn rewards?" },
  { icon: "🔐", label: "Security", prompt: "How do I set up 2FA and secure my account?" },
  { icon: "📱", label: "POS System", prompt: "How do I set up the Point of Sale system?" },
  { icon: "🧾", label: "Invoices", prompt: "How do I create and send invoices?" },
  { icon: "🆔", label: "KYC", prompt: "How do I complete identity verification?" },
  { icon: "💻", label: "Smart Contract API", prompt: "How does the Smart Contract API work for third-party integrations?" },
  { icon: "👥", label: "Affiliate", prompt: "How does the affiliate/referral program work?" },
  { icon: "💬", label: "Support", prompt: "How do I contact customer support?" },
];

const CHAT_URL = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/openpay-ai-chat`;

const OpenPayAIPage = () => {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [messages, setMessages] = useState<Message[]>([]);
  const [inputMessage, setInputMessage] = useState("");
  const [isTyping, setIsTyping] = useState(false);
  const [userBalance, setUserBalance] = useState(0);
  const [monthlySpending, setMonthlySpending] = useState(0);
  const [spendingCategories, setSpendingCategories] = useState<SpendingCategory[]>([]);
  const [budgetAlerts, setBudgetAlerts] = useState<BudgetAlert[]>([]);
  const [insights, setInsights] = useState<FinancialInsight[]>([]);
  const [pendingPayment, setPendingPayment] = useState<any>(null);
  const [showPaymentConfirm, setShowPaymentConfirm] = useState(false);
  const [showTopicMenu, setShowTopicMenu] = useState(false);
  const [userProfile, setUserProfile] = useState<any>(null);
  const [userAccount, setUserAccount] = useState<any>(null);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const [userId, setUserId] = useState<string | null>(null);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  };

  useEffect(() => { scrollToBottom(); }, [messages]);
  useEffect(() => { loadUserData(); }, []);

  const loadUserData = async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) { navigate("/auth"); return; }
      setUserId(user.id);
      await Promise.all([
        loadBalance(user.id),
        loadSpendingAnalysis(user.id),
        loadProfile(user.id),
        loadAccount(user.id),
      ]);
    } catch (error) {
      console.error("Error loading user data:", error);
      toast.error("Failed to load AI assistant");
    } finally {
      setLoading(false);
    }
  };

  const loadProfile = async (uid: string) => {
    const { data } = await supabase.from("profiles").select("*").eq("id", uid).maybeSingle();
    if (data) setUserProfile(data);
  };

  const loadAccount = async (uid: string) => {
    const { data } = await supabase.from("user_accounts").select("*").eq("user_id", uid).maybeSingle();
    if (data) setUserAccount(data);
  };

  const loadBalance = async (uid: string) => {
    const { data } = await (supabase as any).from("wallets").select("balance").eq("user_id", uid).maybeSingle();
    if (data) setUserBalance(data.balance || 0);
  };

  const loadSpendingAnalysis = async (uid: string) => {
    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    const { data: transactions } = await supabase
      .from("transactions").select("amount, note, created_at, status")
      .eq("sender_id", uid).eq("status", "completed").gte("created_at", thirtyDaysAgo);
    if (transactions) analyzeSpending(transactions);
  };

  const analyzeSpending = (transactions: any[]) => {
    const cats = [
      { name: "Food & Dining", keywords: ["food", "restaurant", "dining", "coffee"], color: "#ef4444" },
      { name: "Transport", keywords: ["transport", "uber", "grab", "taxi", "gas"], color: "#3b82f6" },
      { name: "Shopping", keywords: ["shop", "store", "mall", "purchase"], color: "#8b5cf6" },
      { name: "Bills", keywords: ["bill", "utility", "electric", "water", "internet"], color: "#f59e0b" },
      { name: "Entertainment", keywords: ["movie", "game", "entertainment"], color: "#10b981" },
      { name: "Others", keywords: [], color: "#6b7280" },
    ];
    const spending: Record<string, number> = {};
    let total = 0;
    transactions.forEach((tx) => {
      const note = (tx.note || "").toLowerCase();
      let found = false;
      for (const c of cats) {
        if (c.keywords.some((k) => note.includes(k))) { spending[c.name] = (spending[c.name] || 0) + tx.amount; found = true; break; }
      }
      if (!found) spending["Others"] = (spending["Others"] || 0) + tx.amount;
      total += tx.amount;
    });
    setMonthlySpending(total);
    const catData = Object.entries(spending).map(([name, amount]) => ({
      name, amount, percentage: total > 0 ? (amount / total) * 100 : 0,
      color: cats.find((c) => c.name === name)?.color || "#6b7280",
    }));
    setSpendingCategories(catData.sort((a, b) => b.amount - a.amount));
    const alerts = catData.filter((c) => c.percentage > 30).map((c) => ({
      category: c.name, spent: c.amount, limit: c.amount * 3, percentage: c.percentage,
    }));
    setBudgetAlerts(alerts);
  };

  useEffect(() => {
    const ins: FinancialInsight[] = [
      { type: "balance", title: "Current Balance", description: "Available funds in your wallet", value: `$${userBalance.toFixed(2)}`, trend: "stable" as const },
      { type: "spending", title: "Monthly Spending", description: "Total spent this month", value: `$${monthlySpending.toFixed(2)}`, trend: monthlySpending > 10000 ? "up" as const : "stable" as const },
    ];
    if (budgetAlerts.length > 0) {
      ins.push({ type: "alert", title: "Budget Alert", description: `${budgetAlerts.length} category(ies) exceeding limits`, trend: "up" });
    }
    setInsights(ins);
  }, [userBalance, monthlySpending, budgetAlerts]);

  const buildContext = () => {
    const parts = [`Balance: $${userBalance.toFixed(2)}`, `Monthly spending: $${monthlySpending.toFixed(2)}`];
    if (spendingCategories.length) parts.push(`Top categories: ${spendingCategories.slice(0, 3).map((c) => c.name).join(", ")}`);
    if (budgetAlerts.length) parts.push(`Budget alerts: ${budgetAlerts.length}`);
    if (userProfile) {
      parts.push(`User: ${userProfile.full_name || "N/A"}`);
      if (userProfile.username) parts.push(`Username: @${userProfile.username}`);
      if (userProfile.referral_code) parts.push(`Referral code: ${userProfile.referral_code}`);
    }
    if (userAccount) {
      parts.push(`Account #: ${userAccount.account_number}`);
      if (userAccount.account_username) parts.push(`Account username: ${userAccount.account_username}`);
    }
    return parts.join(", ");
  };

  const streamAI = async (prompt: string) => {
    const resp = await fetch(CHAT_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY}`,
      },
      body: JSON.stringify({ message: prompt, context: buildContext(), stream: true }),
    });

    if (!resp.ok || !resp.body) {
      if (resp.status === 429) { toast.error("AI is busy. Please try again in a moment."); return null; }
      if (resp.status === 402) { toast.error("AI credits exhausted. Please try again later."); return null; }
      const errData = await resp.json().catch(() => ({}));
      throw new Error(errData.error || "AI service unavailable");
    }
    return resp.body;
  };

  const handleSendMessage = async (overrideMessage?: string) => {
    const text = overrideMessage || inputMessage.trim();
    if (!text || isTyping) return;

    const userMsg: Message = { id: Date.now().toString(), role: "user", content: text, timestamp: new Date().toISOString() };
    setMessages((prev) => [...prev, userMsg]);
    setInputMessage("");
    setIsTyping(true);
    setShowTopicMenu(false);

    // Check payment command
    const payMatch = text.match(/(?:send|transfer|pay)\s+(\d+(?:\.\d{2})?)\s*(?:php|₱)?\s*(?:to\s*)?@?(\w+)/i);
    if (payMatch) {
      const amount = parseFloat(payMatch[1]);
      const recipient = payMatch[2];
      setPendingPayment({ amount, recipient });
      setShowPaymentConfirm(true);
      const confirmMsg: Message = { id: (Date.now() + 1).toString(), role: "assistant", content: `I can help you send **$${amount.toFixed(2)}** to **@${recipient}**. Please confirm the payment details.`, timestamp: new Date().toISOString() };
      setMessages((prev) => [...prev, confirmMsg]);
      setIsTyping(false);
      return;
    }

    try {
      const body = await streamAI(text);
      if (!body) { setIsTyping(false); return; }

      const reader = body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";
      let assistantContent = "";
      const assistantId = (Date.now() + 1).toString();

      // Add empty assistant message
      setMessages((prev) => [...prev, { id: assistantId, role: "assistant", content: "", timestamp: new Date().toISOString() }]);

      let streamDone = false;
      while (!streamDone) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });

        let nlIdx: number;
        while ((nlIdx = buffer.indexOf("\n")) !== -1) {
          let line = buffer.slice(0, nlIdx);
          buffer = buffer.slice(nlIdx + 1);
          if (line.endsWith("\r")) line = line.slice(0, -1);
          if (line.startsWith(":") || line.trim() === "") continue;
          if (!line.startsWith("data: ")) continue;
          const jsonStr = line.slice(6).trim();
          if (jsonStr === "[DONE]") { streamDone = true; break; }
          try {
            const parsed = JSON.parse(jsonStr);
            const content = parsed.choices?.[0]?.delta?.content;
            if (content) {
              assistantContent += content;
              setMessages((prev) => prev.map((m) => m.id === assistantId ? { ...m, content: assistantContent } : m));
            }
          } catch {
            buffer = line + "\n" + buffer;
            break;
          }
        }
      }

      // Final flush
      if (buffer.trim()) {
        for (let raw of buffer.split("\n")) {
          if (!raw || raw.startsWith(":") || raw.trim() === "") continue;
          if (raw.endsWith("\r")) raw = raw.slice(0, -1);
          if (!raw.startsWith("data: ")) continue;
          const jsonStr = raw.slice(6).trim();
          if (jsonStr === "[DONE]") continue;
          try {
            const parsed = JSON.parse(jsonStr);
            const content = parsed.choices?.[0]?.delta?.content;
            if (content) {
              assistantContent += content;
              setMessages((prev) => prev.map((m) => m.id === assistantId ? { ...m, content: assistantContent } : m));
            }
          } catch { /* ignore */ }
        }
      }

      if (!assistantContent) {
        setMessages((prev) => prev.map((m) => m.id === assistantId ? { ...m, content: "I couldn't generate a response. Please try again." } : m));
      }
    } catch (error: any) {
      console.error("AI error:", error);
      toast.error(error.message || "Failed to get AI response");
      const errMsg: Message = { id: (Date.now() + 1).toString(), role: "assistant", content: "I'm having trouble connecting to AI services. Please try again.", timestamp: new Date().toISOString() };
      setMessages((prev) => [...prev, errMsg]);
    } finally {
      setIsTyping(false);
    }
  };

  const startNewChat = () => {
    setMessages([]);
    setInputMessage("");
    setPendingPayment(null);
    setShowPaymentConfirm(false);
  };

  const confirmPayment = async () => {
    if (!pendingPayment) return;
    toast.success(`Payment of $${pendingPayment.amount.toFixed(2)} to @${pendingPayment.recipient} initiated`);
    const confirmMsg: Message = { id: (Date.now() + 2).toString(), role: "assistant", content: `✅ Payment of **$${pendingPayment.amount.toFixed(2)}** to **@${pendingPayment.recipient}** has been processed successfully.`, timestamp: new Date().toISOString() };
    setMessages((prev) => [...prev, confirmMsg]);
    setPendingPayment(null);
    setShowPaymentConfirm(false);
    if (userId) await loadBalance(userId);
  };

  if (loading) return <SplashScreen />;

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-background">
      {/* Header */}
      <div className="bg-background border-b border-border/70 px-4 py-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <BrandLogo className="h-8 w-8" />
            <div>
              <h1 className="text-lg font-semibold text-foreground">OpenPay AI</h1>
              <p className="text-xs text-muted-foreground">Your Smart Financial Assistant</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Button variant="ghost" size="sm" onClick={startNewChat} title="New Chat">
              <Plus className="h-4 w-4 mr-1" /> New
            </Button>
            <Button variant="outline" size="sm" onClick={() => navigate("/menu")}>Back</Button>
          </div>
        </div>
      </div>

      <div className="flex flex-col lg:flex-row h-[calc(100vh-64px)]">
        {/* Sidebar */}
        <div className="hidden lg:block lg:w-80 bg-background border-r border-border/70 p-4 overflow-y-auto">
          <SidebarContent
            insights={insights}
            spendingCategories={spendingCategories}
            budgetAlerts={budgetAlerts}
            userProfile={userProfile}
            userAccount={userAccount}
            userBalance={userBalance}
          />
        </div>

        {/* Mobile sidebar via sheet */}
        <div className="lg:hidden flex items-center gap-2 px-4 py-2 bg-background border-b border-border/40">
          <Sheet>
            <SheetTrigger asChild>
              <Button variant="ghost" size="sm"><UserCircle className="h-4 w-4 mr-1" /> Account</Button>
            </SheetTrigger>
            <SheetContent side="left" className="w-80 p-4 overflow-y-auto">
              <SheetHeader><SheetTitle>Account & Insights</SheetTitle></SheetHeader>
              <div className="mt-4">
                <SidebarContent
                  insights={insights}
                  spendingCategories={spendingCategories}
                  budgetAlerts={budgetAlerts}
                  userProfile={userProfile}
                  userAccount={userAccount}
                  userBalance={userBalance}
                />
              </div>
            </SheetContent>
          </Sheet>
          <Button variant="ghost" size="sm" onClick={() => setShowTopicMenu(true)}>
            <Menu className="h-4 w-4 mr-1" /> Topics
          </Button>
        </div>

        {/* Chat Area */}
        <div className="flex-1 flex flex-col">
          <ScrollArea className="flex-1 p-4">
            <div className="max-w-3xl mx-auto space-y-4">
              {messages.length === 0 && (
                <WelcomeScreen onSelect={(prompt) => handleSendMessage(prompt)} />
              )}

              {messages.map((message) => (
                <div key={message.id} className={`flex ${message.role === "user" ? "justify-end" : "justify-start"}`}>
                  <div className={`max-w-[85%] rounded-2xl px-4 py-3 ${message.role === "user" ? "bg-primary text-primary-foreground" : "bg-background border border-border/70"}`}>
                    <div className="flex items-start gap-2">
                      {message.role === "assistant" && <Bot className="h-5 w-5 text-primary mt-0.5 flex-shrink-0" />}
                      <div className="flex-1 min-w-0">
                        {message.role === "assistant" ? (
                          <div className="prose prose-sm dark:prose-invert max-w-none text-sm [&>p]:mb-2 [&>ul]:mb-2 [&>ol]:mb-2">
                            <ReactMarkdown>{message.content || "..."}</ReactMarkdown>
                          </div>
                        ) : (
                          <p className="text-sm whitespace-pre-wrap">{message.content}</p>
                        )}
                        <p className="text-xs opacity-60 mt-1">{new Date(message.timestamp).toLocaleTimeString()}</p>
                      </div>
                      {message.role === "user" && <User className="h-5 w-5 mt-0.5 flex-shrink-0" />}
                    </div>
                  </div>
                </div>
              ))}

              {isTyping && messages[messages.length - 1]?.role !== "assistant" && (
                <div className="flex justify-start">
                  <div className="bg-background border border-border/70 rounded-2xl px-4 py-3">
                    <div className="flex items-center gap-2">
                      <Bot className="h-5 w-5 text-primary" />
                      <div className="flex gap-1">
                        <div className="w-2 h-2 bg-muted-foreground/40 rounded-full animate-bounce" />
                        <div className="w-2 h-2 bg-muted-foreground/40 rounded-full animate-bounce" style={{ animationDelay: "0.1s" }} />
                        <div className="w-2 h-2 bg-muted-foreground/40 rounded-full animate-bounce" style={{ animationDelay: "0.2s" }} />
                      </div>
                    </div>
                  </div>
                </div>
              )}
              <div ref={messagesEndRef} />
            </div>
          </ScrollArea>

          {/* Input */}
          <div className="bg-background border-t border-border/70 p-4">
            <div className="max-w-3xl mx-auto">
              <div className="flex gap-2">
                <Button variant="ghost" size="icon" className="flex-shrink-0 hidden lg:flex" onClick={() => setShowTopicMenu(true)} title="Topic Menu">
                  <Menu className="h-5 w-5" />
                </Button>
                <Input
                  value={inputMessage}
                  onChange={(e) => setInputMessage(e.target.value)}
                  placeholder="Ask me anything about your finances..."
                  onKeyDown={(e) => e.key === "Enter" && !e.shiftKey && handleSendMessage()}
                  disabled={isTyping}
                  className="flex-1"
                />
                <Button onClick={() => handleSendMessage()} disabled={isTyping || !inputMessage.trim()} className="bg-primary hover:bg-primary/90">
                  <Send className="h-4 w-4" />
                </Button>
              </div>
              <div className="flex items-center gap-2 mt-2 text-xs text-muted-foreground">
                <Shield className="h-3 w-3" />
                <span>All payments require your confirmation • Powered by AI</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Topic Menu Dialog */}
      <Dialog open={showTopicMenu} onOpenChange={setShowTopicMenu}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><Menu className="h-5 w-5" /> Choose a Topic</DialogTitle>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-2 max-h-[60vh] overflow-y-auto">
            {QUICK_TOPICS.map((topic, i) => (
              <button
                key={i}
                className="flex items-center gap-2 p-3 rounded-lg border border-border hover:bg-accent transition-colors text-left"
                onClick={() => handleSendMessage(topic.prompt)}
              >
                <span className="text-lg">{topic.icon}</span>
                <span className="text-sm font-medium">{topic.label}</span>
              </button>
            ))}
          </div>
        </DialogContent>
      </Dialog>

      {/* Payment Confirmation */}
      <Dialog open={showPaymentConfirm} onOpenChange={setShowPaymentConfirm}>
        <DialogContent>
          <DialogHeader><DialogTitle>Confirm Payment</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <Alert><AlertDescription>Please review the payment details before confirming:</AlertDescription></Alert>
            {pendingPayment && (
              <div className="bg-muted p-4 rounded-lg space-y-2">
                <div className="flex justify-between"><span>Amount:</span><span className="font-semibold">${pendingPayment.amount.toFixed(2)}</span></div>
                <div className="flex justify-between"><span>Recipient:</span><span className="font-semibold">@{pendingPayment.recipient}</span></div>
                <div className="flex justify-between"><span>Fee:</span><span className="font-semibold">$0.00</span></div>
                <div className="border-t pt-2 flex justify-between font-semibold"><span>Total:</span><span>${pendingPayment.amount.toFixed(2)}</span></div>
              </div>
            )}
            <div className="flex gap-2">
              <Button variant="outline" onClick={() => setShowPaymentConfirm(false)}>Cancel</Button>
              <Button onClick={confirmPayment} className="bg-primary hover:bg-primary/90">Confirm Payment</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};

/* ── Sidebar Content ── */
function SidebarContent({ insights, spendingCategories, budgetAlerts, userProfile, userAccount, userBalance }: {
  insights: FinancialInsight[];
  spendingCategories: SpendingCategory[];
  budgetAlerts: BudgetAlert[];
  userProfile: any;
  userAccount: any;
  userBalance: number;
}) {
  return (
    <div className="space-y-4">
      {/* User Profile Card */}
      {userProfile && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm flex items-center gap-2">
              <UserCircle className="h-4 w-4 text-primary" /> My Profile
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-xs">
            <div className="flex justify-between"><span className="text-muted-foreground">Name</span><span className="font-medium">{userProfile.full_name || "Not set"}</span></div>
            {userProfile.username && <div className="flex justify-between"><span className="text-muted-foreground">Username</span><span className="font-medium">@{userProfile.username}</span></div>}
            {userProfile.referral_code && <div className="flex justify-between"><span className="text-muted-foreground">Referral</span><span className="font-medium">{userProfile.referral_code}</span></div>}
            {userAccount && (
              <>
                <div className="flex justify-between"><span className="text-muted-foreground">Account #</span><span className="font-medium">{userAccount.account_number}</span></div>
                {userAccount.account_username && <div className="flex justify-between"><span className="text-muted-foreground">Acct User</span><span className="font-medium">{userAccount.account_username}</span></div>}
              </>
            )}
          </CardContent>
        </Card>
      )}

      {/* Quick Insights */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm flex items-center gap-2">
            <Sparkles className="h-4 w-4 text-primary" /> Quick Insights
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          {insights.map((insight, i) => (
            <div key={i} className="flex items-center justify-between">
              <div className="flex-1">
                <p className="text-xs font-medium">{insight.title}</p>
                <p className="text-xs text-muted-foreground">{insight.description}</p>
              </div>
              <div className="text-right">
                {insight.value && <p className="text-sm font-semibold">{insight.value}</p>}
                {insight.trend && (
                  <Badge variant={insight.trend === "up" ? "destructive" : insight.trend === "down" ? "secondary" : "default"} className="text-xs">
                    {insight.trend}
                  </Badge>
                )}
              </div>
            </div>
          ))}
        </CardContent>
      </Card>

      {/* Spending */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm flex items-center gap-2">
            <PieChart className="h-4 w-4 text-primary" /> Spending Categories
          </CardTitle>
        </CardHeader>
        <CardContent>
          {spendingCategories.length > 0 ? (
            <div className="space-y-2">
              {spendingCategories.map((cat, i) => (
                <div key={i} className="space-y-1">
                  <div className="flex justify-between text-xs">
                    <span>{cat.name}</span>
                    <span className="font-medium">${cat.amount.toFixed(2)} ({cat.percentage.toFixed(0)}%)</span>
                  </div>
                  <div className="w-full bg-muted rounded-full h-1.5">
                    <div className="h-1.5 rounded-full" style={{ width: `${cat.percentage}%`, backgroundColor: cat.color }} />
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-xs text-muted-foreground">No spending data yet this month.</p>
          )}
        </CardContent>
      </Card>

      {/* Budget Alerts */}
      {budgetAlerts.length > 0 && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm flex items-center gap-2">
              <AlertTriangle className="h-4 w-4 text-orange-600" /> Budget Alerts
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {budgetAlerts.map((alert, i) => (
              <Alert key={i} className="p-2">
                <AlertDescription className="text-xs">
                  <strong>{alert.category}</strong>: ${alert.spent.toFixed(2)} / ${alert.limit.toFixed(2)} ({alert.percentage.toFixed(0)}%)
                </AlertDescription>
              </Alert>
            ))}
          </CardContent>
        </Card>
      )}
    </div>
  );
}

/* ── Welcome Screen ── */
function WelcomeScreen({ onSelect }: { onSelect: (prompt: string) => void }) {
  const sections = [
    {
      icon: <Wallet className="h-5 w-5 text-primary" />, title: "Banking Features",
      items: [
        { icon: "💰", label: "Check Balance", desc: "View wallet balance", prompt: "What is my current balance?" },
        { icon: "💸", label: "Send Money", desc: "Transfer funds", prompt: "How do I send money?" },
        { icon: "💳", label: "Top-up", desc: "Add funds", prompt: "How do I top-up my account?" },
        { icon: "💱", label: "Currency Exchange", desc: "Multi-currency", prompt: "What currencies do you support?" },
        { icon: "💳", label: "Virtual Cards", desc: "Payment cards", prompt: "How do I create a virtual card?" },
        { icon: "📋", label: "History", desc: "Past transactions", prompt: "Show my transaction history" },
      ],
    },
    {
      icon: <Store className="h-5 w-5 text-primary" />, title: "Merchant Services",
      items: [
        { icon: "🏪", label: "Become Merchant", desc: "Start selling", prompt: "How do I become a merchant?" },
        { icon: "📱", label: "POS System", desc: "In-person pay", prompt: "How do I set up POS?" },
        { icon: "🔗", label: "Payment Links", desc: "Share links", prompt: "How do I create payment links?" },
        { icon: "📦", label: "Product Catalog", desc: "Manage products", prompt: "How do I add products?" },
        { icon: "🧾", label: "Invoices", desc: "Send invoices", prompt: "How do I create invoices?" },
        { icon: "💰", label: "Fees", desc: "Transaction costs", prompt: "What are merchant fees?" },
      ],
    },
    {
      icon: <Coins className="h-5 w-5 text-primary" />, title: "Earning & Rewards",
      items: [
        { icon: "⛏️", label: "Mining", desc: "Pi mining", prompt: "How does mining work?" },
        { icon: "💎", label: "Staking", desc: "Earn rewards", prompt: "How do I start staking?" },
        { icon: "👥", label: "Affiliate", desc: "Referral program", prompt: "How does affiliate work?" },
        { icon: "📺", label: "Pi Ads", desc: "Watch & earn", prompt: "How do I watch Pi ads?" },
      ],
    },
    {
      icon: <Shield className="h-5 w-5 text-primary" />, title: "Security & Support",
      items: [
        { icon: "🔐", label: "2FA", desc: "Enhanced security", prompt: "How do I set up 2FA?" },
        { icon: "🆔", label: "KYC", desc: "Identity verify", prompt: "How do I complete KYC?" },
        { icon: "⚖️", label: "Disputes", desc: "Handle disputes", prompt: "How do I dispute a transaction?" },
        { icon: "💬", label: "Support", desc: "Get help", prompt: "How do I contact support?" },
      ],
    },
  ];

  return (
    <div className="text-center py-6">
      <Bot className="h-12 w-12 text-primary mx-auto mb-4" />
      <h3 className="text-lg font-semibold mb-1">Welcome to OpenPay AI!</h3>
      <p className="text-muted-foreground mb-6 text-sm">I can help you with ANY OpenPay feature. Pick a topic or type a question:</p>

      <div className="space-y-4 text-left">
        {sections.map((section, si) => (
          <div key={si} className="bg-background rounded-lg p-4 border border-border">
            <h4 className="font-semibold mb-3 flex items-center gap-2">{section.icon} {section.title}</h4>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-1.5 text-sm">
              {section.items.map((item, ii) => (
                <button key={ii} className="p-2 hover:bg-accent rounded-lg cursor-pointer transition-colors text-left w-full flex items-center gap-2" onClick={() => onSelect(item.prompt)}>
                  <span>{item.icon}</span>
                  <div>
                    <p className="font-medium text-xs">{item.label}</p>
                    <p className="text-xs text-muted-foreground">{item.desc}</p>
                  </div>
                  <ChevronRight className="h-3 w-3 ml-auto text-muted-foreground" />
                </button>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

export default OpenPayAIPage;
