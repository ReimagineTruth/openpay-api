import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Send, Bot, User, TrendingUp, AlertTriangle, Wallet, PieChart, Shield, Sparkles } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Alert, AlertDescription } from "@/components/ui/alert";
import BrandLogo from "@/components/BrandLogo";
import SplashScreen from "@/components/SplashScreen";

// OpenRouter API integration
const OPENROUTER_API_KEY = import.meta.env.VITE_OPENROUTER_API_KEY;

type Message = {
  id: string;
  role: "user" | "assistant";
  content: string;
  timestamp: string;
  type?: "text" | "insight" | "payment" | "alert";
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
  type: "balance" | "spending" | "budget" | "prediction" | "alert";
  title: string;
  description: string;
  value?: string;
  trend?: "up" | "down" | "stable";
};

const OpenPayAIPage = () => {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [messages, setMessages] = useState<Message[]>([]);
  const [inputMessage, setInputMessage] = useState("");
  const [isTyping, setIsTyping] = useState(false);
  const [userBalance, setUserBalance] = useState(0);
  const [spendingCategories, setSpendingCategories] = useState<SpendingCategory[]>([]);
  const [budgetAlerts, setBudgetAlerts] = useState<BudgetAlert[]>([]);
  const [insights, setInsights] = useState<FinancialInsight[]>([]);
  const [pendingPayment, setPendingPayment] = useState<any>(null);
  const [showPaymentConfirm, setShowPaymentConfirm] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const [userId, setUserId] = useState<string | null>(null);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages]);

  useEffect(() => {
    loadUserData();
  }, []);

  const loadUserData = async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) {
        navigate("/auth");
        return;
      }
      
      setUserId(user.id);
      await Promise.all([
        loadBalance(user.id),
        loadSpendingAnalysis(user.id),
        loadInsights(user.id),
        loadChatHistory(user.id)
      ]);
    } catch (error) {
      console.error("Error loading user data:", error);
      toast.error("Failed to load AI assistant");
    } finally {
      setLoading(false);
    }
  };

  const loadBalance = async (userId: string) => {
    const { data } = await supabase
      .from("wallets")
      .select("balance")
      .eq("user_id", userId)
      .single();
    
    if (data) {
      setUserBalance(data.balance || 0);
    }
  };

  const loadSpendingAnalysis = async (userId: string) => {
    // Get transactions from last 30 days
    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    
    const { data: transactions } = await supabase
      .from("transactions")
      .select("amount, note, created_at, status")
      .eq("sender_id", userId)
      .eq("status", "completed")
      .gte("created_at", thirtyDaysAgo);

    if (transactions) {
      analyzeSpending(transactions);
    }
  };

  const analyzeSpending = (transactions: any[]) => {
    const categories = [
      { name: "Food & Dining", keywords: ["food", "restaurant", "dining", "coffee", "meal"], color: "#ef4444" },
      { name: "Transport", keywords: ["transport", "uber", "grab", "taxi", "gas", "fuel"], color: "#3b82f6" },
      { name: "Shopping", keywords: ["shop", "store", "mall", "purchase", "buy"], color: "#8b5cf6" },
      { name: "Bills & Utilities", keywords: ["bill", "utility", "electric", "water", "internet"], color: "#f59e0b" },
      { name: "Entertainment", keywords: ["movie", "game", "entertainment", "subscription"], color: "#10b981" },
      { name: "Others", keywords: [], color: "#6b7280" }
    ];

    const categorizedSpending: { [key: string]: number } = {};
    let totalSpent = 0;

    transactions.forEach(tx => {
      const note = (tx.note || "").toLowerCase();
      let categorized = false;
      
      for (const category of categories) {
        if (category.keywords.some(keyword => note.includes(keyword))) {
          categorizedSpending[category.name] = (categorizedSpending[category.name] || 0) + tx.amount;
          categorized = true;
          break;
        }
      }
      
      if (!categorized) {
        categorizedSpending["Others"] = (categorizedSpending["Others"] || 0) + tx.amount;
      }
      
      totalSpent += tx.amount;
    });

    const categoryData = Object.entries(categorizedSpending).map(([name, amount]) => ({
      name,
      amount,
      percentage: totalSpent > 0 ? (amount / totalSpent) * 100 : 0,
      color: categories.find(c => c.name === name)?.color || "#6b7280"
    }));

    setSpendingCategories(categoryData.sort((a, b) => b.amount - a.amount));
  };

  const loadInsights = async (userId: string) => {
    const insights: FinancialInsight[] = [];
    
    // Balance insight
    insights.push({
      type: "balance",
      title: "Current Balance",
      description: "Available funds in your wallet",
      value: `₱${userBalance.toFixed(2)}`,
      trend: "stable"
    });

    // Spending insight
    const todaySpending = spendingCategories.reduce((sum, cat) => sum + cat.amount, 0);
    insights.push({
      type: "spending",
      title: "Monthly Spending",
      description: "Total spent this month",
      value: `₱${todaySpending.toFixed(2)}`,
      trend: todaySpending > 10000 ? "up" : "stable"
    });

    // Budget alerts
    const alerts = spendingCategories
      .filter(cat => cat.percentage > 30)
      .map(cat => ({
        category: cat.name,
        spent: cat.amount,
        limit: cat.amount * 3, // Estimate 3x as monthly limit
        percentage: cat.percentage
      }));

    setBudgetAlerts(alerts);

    if (alerts.length > 0) {
      insights.push({
        type: "alert",
        title: "Budget Alert",
        description: `${alerts.length} category(ies) exceeding recommended limits`,
        trend: "up"
      });
    }

    // Prediction
    const dailyAverage = todaySpending / 30;
    const daysUntilZero = userBalance / dailyAverage;
    
    if (daysUntilZero < 7) {
      insights.push({
        type: "prediction",
        title: "Low Balance Warning",
        description: `You may run out of balance in ${Math.ceil(daysUntilZero)} days`,
        trend: "down"
      });
    }

    setInsights(insights);
  };

  const loadChatHistory = async (userId: string) => {
    const { data } = await (supabase as any)
      .from("ai_chat_history")
      .select("*")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(50);

    if (data) {
      const history = data.map((msg: any) => ({
        id: msg.id,
        role: msg.role as "user" | "assistant",
        content: msg.content,
        timestamp: msg.created_at,
        type: msg.type || "text"
      }));
      setMessages(history.reverse());
    }
  };

  const saveMessage = async (message: Message) => {
    if (!userId) return;
    
    await (supabase as any)
      .from("ai_chat_history")
      .insert({
        user_id: userId,
        role: message.role,
        content: message.content,
        type: message.type || "text",
        created_at: message.timestamp
      });
  };

  const callOpenRouterAPI = async (prompt: string) => {
    try {
      const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${OPENROUTER_API_KEY}`,
          "Content-Type": "application/json",
          "HTTP-Referer": "https://openpay.app",
          "X-Title": "OpenPay AI"
        },
        body: JSON.stringify({
          model: "nvidia/nemotron-3-super-120b-a12b:free",
          messages: [
            {
              role: "system",
              content: `You are OpenPay AI, a smart financial assistant. Help users manage money, analyze spending, create budgets, and execute payments safely. 
              
              Rules:
              - Be friendly, professional, and clear
              - For payment requests, always ask for confirmation
              - Provide specific financial insights
              - Use Philippine Peso (₱) for amounts
              - Analyze spending patterns and give actionable advice
              - Alert about unusual spending or low balance
              
              Current user data:
              - Balance: ₱${userBalance.toFixed(2)}
              - Monthly spending: ₱${spendingCategories.reduce((sum, cat) => sum + cat.amount, 0).toFixed(2)}
              - Top spending categories: ${spendingCategories.slice(0, 3).map(c => c.name).join(", ")}`
            },
            {
              role: "user",
              content: prompt
            }
          ],
          stream: false
        })
      });

      const data = await response.json();
      return data.choices[0]?.message?.content || "Sorry, I couldn't process your request.";
    } catch (error) {
      console.error("OpenRouter API error:", error);
      return "I'm having trouble connecting to my AI services. Please try again later.";
    }
  };

  const processUserMessage = async (message: string) => {
    // Check for payment commands
    const paymentRegex = /send|transfer|pay\s+(\d+(?:\.\d{2})?)\s*(?:php|₱)?\s*(?:to\s*)?@?(\w+)/i;
    const paymentMatch = message.match(paymentRegex);

    if (paymentMatch) {
      const amount = parseFloat(paymentMatch[1]);
      const recipient = paymentMatch[2];
      
      setPendingPayment({ amount, recipient });
      setShowPaymentConfirm(true);
      
      return "I can help you send money. Please confirm the payment details below.";
    }

    // Check for balance requests
    if (message.toLowerCase().includes("balance")) {
      return `Your current balance is ₱${userBalance.toFixed(2)}. ${userBalance < 1000 ? '⚠️ Low balance warning' : '✅ Good balance status'}`;
    }

    // Check for spending analysis
    if (message.toLowerCase().includes("spending") || message.toLowerCase().includes("analyze")) {
      const totalSpent = spendingCategories.reduce((sum, cat) => sum + cat.amount, 0);
      const topCategory = spendingCategories[0];
      
      return `This month you've spent ₱${totalSpent.toFixed(2)}. 
        ${topCategory ? `Your top spending category is ${topCategory.name} at ₱${topCategory.amount.toFixed(2)} (${topCategory.percentage.toFixed(1)}%).` : ''}
        ${budgetAlerts.length > 0 ? `⚠️ You have ${budgetAlerts.length} budget alert(s) to review.` : '✅ Your spending looks normal.'}`;
    }

    // Default to AI for complex queries
    return await callOpenRouterAPI(message);
  };

  const handleSendMessage = async () => {
    if (!inputMessage.trim() || isTyping) return;

    const userMessage: Message = {
      id: Date.now().toString(),
      role: "user",
      content: inputMessage,
      timestamp: new Date().toISOString()
    };

    setMessages(prev => [...prev, userMessage]);
    setInputMessage("");
    setIsTyping(true);

    try {
      const aiResponse = await processUserMessage(inputMessage);
      
      const assistantMessage: Message = {
        id: (Date.now() + 1).toString(),
        role: "assistant",
        content: aiResponse,
        timestamp: new Date().toISOString(),
        type: pendingPayment ? "payment" : "text"
      };

      setMessages(prev => [...prev, assistantMessage]);
      
      // Save both messages
      await Promise.all([
        saveMessage(userMessage),
        saveMessage(assistantMessage)
      ]);

    } catch (error) {
      console.error("Error processing message:", error);
      toast.error("Failed to process your message");
    } finally {
      setIsTyping(false);
    }
  };

  const confirmPayment = async () => {
    if (!pendingPayment) return;

    try {
      // Here you would integrate with your payment system
      toast.success(`Payment of ₱${pendingPayment.amount.toFixed(2)} to @${pendingPayment.recipient} initiated`);
      
      setPendingPayment(null);
      setShowPaymentConfirm(false);
      
      // Add confirmation message
      const confirmationMessage: Message = {
        id: (Date.now() + 2).toString(),
        role: "assistant",
        content: `✅ Payment of ₱${pendingPayment.amount.toFixed(2)} to @${pendingPayment.recipient} has been processed successfully.`,
        timestamp: new Date().toISOString(),
        type: "text"
      };
      
      setMessages(prev => [...prev, confirmationMessage]);
      await saveMessage(confirmationMessage);
      
      // Refresh balance
      if (userId) {
        await loadBalance(userId);
      }
      
    } catch (error) {
      toast.error("Payment failed. Please try again.");
    }
  };

  if (loading) {
    return <SplashScreen />;
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-white">
      {/* Header */}
      <div className="bg-white border-b border-border/70 px-4 py-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <BrandLogo className="h-8 w-8" />
            <div>
              <h1 className="text-lg font-semibold text-foreground">OpenPay AI</h1>
              <p className="text-xs text-muted-foreground">Your Smart Financial Assistant</p>
            </div>
          </div>
          <Button variant="outline" size="sm" onClick={() => navigate("/menu")}>
            Back
          </Button>
        </div>
      </div>

      <div className="flex flex-col lg:flex-row h-[calc(100vh-80px)]">
        {/* Insights Sidebar */}
        <div className="lg:w-80 bg-white border-r border-border/70 p-4 overflow-y-auto">
          <div className="space-y-4">
            {/* Quick Stats */}
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-sm flex items-center gap-2">
                  <Sparkles className="h-4 w-4 text-blue-600" />
                  Quick Insights
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                {insights.map((insight, index) => (
                  <div key={index} className="flex items-center justify-between">
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

            {/* Spending Categories */}
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-sm flex items-center gap-2">
                  <PieChart className="h-4 w-4 text-blue-600" />
                  Spending Categories
                </CardTitle>
              </CardHeader>
              <CardContent>
                <div className="space-y-2">
                  {spendingCategories.slice(0, 5).map((category, index) => (
                    <div key={index} className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <div 
                          className="w-3 h-3 rounded-full" 
                          style={{ backgroundColor: category.color }}
                        />
                        <span className="text-xs">{category.name}</span>
                      </div>
                      <div className="text-right">
                        <p className="text-xs font-medium">₱{category.amount.toFixed(2)}</p>
                        <p className="text-xs text-muted-foreground">{category.percentage.toFixed(1)}%</p>
                      </div>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>

            {/* Budget Alerts */}
            {budgetAlerts.length > 0 && (
              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-sm flex items-center gap-2">
                    <AlertTriangle className="h-4 w-4 text-orange-600" />
                    Budget Alerts
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <div className="space-y-2">
                    {budgetAlerts.map((alert, index) => (
                      <Alert key={index} className="p-2">
                        <AlertDescription className="text-xs">
                          <strong>{alert.category}</strong>: ₱{alert.spent.toFixed(2)} / ₱{alert.limit.toFixed(2)} ({alert.percentage.toFixed(0)}%)
                        </AlertDescription>
                      </Alert>
                    ))}
                  </div>
                </CardContent>
              </Card>
            )}
          </div>
        </div>

        {/* Chat Area */}
        <div className="flex-1 flex flex-col bg-gray-50">
          <ScrollArea className="flex-1 p-4">
            <div className="max-w-3xl mx-auto space-y-4">
              {messages.length === 0 && (
                <div className="text-center py-8">
                  <Bot className="h-12 w-12 text-blue-600 mx-auto mb-4" />
                  <h3 className="text-lg font-semibold mb-2">Welcome to OpenPay AI!</h3>
                  <p className="text-muted-foreground mb-4">
                    I'm your smart financial assistant. Ask me anything about:
                  </p>
                  <div className="grid grid-cols-2 gap-2 text-sm text-left max-w-md mx-auto">
                    <div className="p-2 bg-white rounded-lg border">💰 Check my balance</div>
                    <div className="p-2 bg-white rounded-lg border">📊 Analyze spending</div>
                    <div className="p-2 bg-white rounded-lg border">📋 Create budget</div>
                    <div className="p-2 bg-white rounded-lg border">💸 Send money</div>
                  </div>
                </div>
              )}

              {messages.map((message) => (
                <div
                  key={message.id}
                  className={`flex ${message.role === "user" ? "justify-end" : "justify-start"}`}
                >
                  <div
                    className={`max-w-[80%] rounded-2xl px-4 py-3 ${
                      message.role === "user"
                        ? "bg-blue-600 text-white"
                        : "bg-white border border-border/70"
                    }`}
                  >
                    <div className="flex items-start gap-2">
                      {message.role === "assistant" && (
                        <Bot className="h-5 w-5 text-blue-600 mt-0.5 flex-shrink-0" />
                      )}
                      <div className="flex-1">
                        <p className="text-sm whitespace-pre-wrap">{message.content}</p>
                        <p className="text-xs opacity-70 mt-1">
                          {new Date(message.timestamp).toLocaleTimeString()}
                        </p>
                      </div>
                      {message.role === "user" && (
                        <User className="h-5 w-5 text-white mt-0.5 flex-shrink-0" />
                      )}
                    </div>
                  </div>
                </div>
              ))}

              {isTyping && (
                <div className="flex justify-start">
                  <div className="bg-white border border-border/70 rounded-2xl px-4 py-3">
                    <div className="flex items-center gap-2">
                      <Bot className="h-5 w-5 text-blue-600" />
                      <div className="flex gap-1">
                        <div className="w-2 h-2 bg-gray-400 rounded-full animate-bounce" />
                        <div className="w-2 h-2 bg-gray-400 rounded-full animate-bounce delay-100" />
                        <div className="w-2 h-2 bg-gray-400 rounded-full animate-bounce delay-200" />
                      </div>
                    </div>
                  </div>
                </div>
              )}
              <div ref={messagesEndRef} />
            </div>
          </ScrollArea>

          {/* Input Area */}
          <div className="bg-white border-t border-border/70 p-4">
            <div className="max-w-3xl mx-auto">
              <div className="flex gap-2">
                <Input
                  value={inputMessage}
                  onChange={(e) => setInputMessage(e.target.value)}
                  placeholder="Ask me anything about your finances..."
                  onKeyPress={(e) => e.key === "Enter" && handleSendMessage()}
                  disabled={isTyping}
                  className="flex-1"
                />
                <Button 
                  onClick={handleSendMessage} 
                  disabled={isTyping || !inputMessage.trim()}
                  className="bg-blue-600 hover:bg-blue-700"
                >
                  <Send className="h-4 w-4" />
                </Button>
              </div>
              <div className="flex items-center gap-2 mt-2 text-xs text-muted-foreground">
                <Shield className="h-3 w-3" />
                <span>All payments require your confirmation</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Payment Confirmation Dialog */}
      <Dialog open={showPaymentConfirm} onOpenChange={setShowPaymentConfirm}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Confirm Payment</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <Alert>
              <AlertDescription>
                Please review the payment details before confirming:
              </AlertDescription>
            </Alert>
            
            {pendingPayment && (
              <div className="bg-gray-50 p-4 rounded-lg">
                <div className="space-y-2">
                  <div className="flex justify-between">
                    <span>Amount:</span>
                    <span className="font-semibold">₱{pendingPayment.amount.toFixed(2)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Recipient:</span>
                    <span className="font-semibold">@{pendingPayment.recipient}</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Fee:</span>
                    <span className="font-semibold">₱0.00</span>
                  </div>
                  <div className="border-t pt-2 flex justify-between font-semibold">
                    <span>Total:</span>
                    <span>₱{pendingPayment.amount.toFixed(2)}</span>
                  </div>
                </div>
              </div>
            )}
            
            <div className="flex gap-2">
              <Button variant="outline" onClick={() => setShowPaymentConfirm(false)}>
                Cancel
              </Button>
              <Button onClick={confirmPayment} className="bg-blue-600 hover:bg-blue-700">
                Confirm Payment
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default OpenPayAIPage;
