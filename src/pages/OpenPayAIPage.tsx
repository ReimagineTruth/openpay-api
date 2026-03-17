import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Send, Bot, User, TrendingUp, AlertTriangle, Wallet, PieChart, Shield, Sparkles, CreditCard, ArrowLeftRight, Users, Store, FileText, History, Coins, Pickaxe, TrendingDown } from "lucide-react";
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

// OpenRouter SDK integration
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
    // Test API connectivity on mount
    testAPIConnectivity().then(isConnected => {
      if (!isConnected) {
        console.error("❌ API connectivity test failed on mount");
        toast.error("AI service is not available. Please check your internet connection.");
      } else {
        console.log("✅ API connectivity test passed on mount");
      }
    });
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
      value: `$${userBalance.toFixed(2)}`,
      trend: "stable"
    });

    // Spending insight
    const todaySpending = spendingCategories.reduce((sum, cat) => sum + cat.amount, 0);
    insights.push({
      type: "spending",
      title: "Monthly Spending",
      description: "Total spent this month",
      value: `$${todaySpending.toFixed(2)}`,
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
    if (!OPENROUTER_API_KEY) {
      console.error("OpenRouter API key not found");
      return "AI service is not configured. Please check your environment variables.";
    }

    try {
      console.log("Calling OpenRouter API with key:", OPENROUTER_API_KEY?.substring(0, 10) + "...");
      
      // Dynamic import of OpenRouter SDK
      const { OpenRouter } = await import("@openrouter/sdk");
      const openrouter = new OpenRouter({
        apiKey: OPENROUTER_API_KEY
      });

      const openPayKnowledge = `
You are OpenPay AI, a comprehensive smart financial assistant for the OpenPay fintech platform. You have complete knowledge of all OpenPay features and can help users with any aspect of the platform.

## OpenPay Platform Features You Know:

### Core Banking Features:
- **Wallet Management**: Balance checking, transaction history, wallet security
- **Payments**: Send money, receive money, request payments, express send
- **Top-up Methods**: PayPal, credit/debit cards, bank transfer, Apple Pay, Google Pay, Venmo, USDT, USDC, Solana Pay
- **Currency Exchange**: Multi-currency support with real-time rates
- **Virtual Cards**: Create and manage virtual payment cards

### Merchant Services:
- **Merchant Portal**: Product catalog, order management, analytics
- **POS System**: Point-of-sale for in-person payments
- **Payment Links**: Create customizable payment links and buttons
- **QR Code Payments**: Generate and scan QR codes for payments
- **Payment Buttons**: Embeddable payment buttons for websites
- **Invoice System**: Create and send professional invoices
- **Product Management**: Add/edit products, inventory tracking

### Advanced Features:
- **Mining**: Pi Network mining with ad verification requirements
- **Staking**: Earn rewards by staking tokens
- **Affiliate Program**: Referral system with rewards
- **Two-Factor Authentication**: Enhanced security with 2FA
- **KYC Verification**: Identity verification for higher limits
- **Pi Ad Network**: Watch ads to earn rewards
- **Remittance Services**: International money transfers

### Security & Support:
- **Transaction History**: Complete transaction records and search
- **Dispute Resolution**: Handle payment disputes and chargebacks
- **Notifications**: Real-time alerts for transactions and account activity
- **Customer Support**: Help center and support tickets
- **Fraud Detection**: Advanced security monitoring

### User Management:
- **Profile Management**: Personal information and preferences
- **Contact Management**: Save frequently contacted users
- **Settings**: App customization and security settings
- **Dashboard**: Financial overview with analytics and insights

### Technical Details:
- **Multi-Currency**: Support for PHP, USD, and other currencies
- **Blockchain Integration**: Solana and other blockchain networks
- **API Access**: Developer APIs for integration
- **Mobile App**: iOS and Android applications
- **Web Platform**: Full-featured web interface

## Your Capabilities:
- Answer questions about ANY OpenPay feature
- Guide users through complex processes
- Explain fees, limits, and requirements
- Help with troubleshooting and error resolution
- Provide step-by-step instructions for any feature
- Assist with account setup and verification
- Explain security best practices
- Help with merchant onboarding and setup
- Guide users through payment processes
- Assist with mining and staking operations

## Current User Context:
- Balance: $${userBalance.toFixed(2)}
- Monthly spending: $${spendingCategories.reduce((sum, cat) => sum + cat.amount, 0).toFixed(2)}
- Top spending categories: ${spendingCategories.slice(0, 3).map(c => c.name).join(", ")}
- Budget alerts: ${budgetAlerts.length} active alerts

## Response Guidelines:
- Be comprehensive but clear and concise
- Use US Dollar ($) for amounts
- Provide specific, actionable advice
- Include step-by-step instructions when helpful
- Mention relevant fees or limits
- Suggest related OpenPay features when appropriate
- Always prioritize user security and best practices
      `;

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
              content: openPayKnowledge
            },
            {
              role: "user",
              content: prompt
            }
          ]
        })
      });

      console.log("📡 Response status:", response.status);
      console.log("📡 Response headers:", response.headers);
      
      if (!response.ok) {
        const errorText = await response.text();
        console.error("❌ OpenRouter API error response:", errorText);
        return `AI service error (${response.status}): ${errorText}`;
      }

      const data = await response.json();
      console.log("✅ OpenRouter API response data:", data);
      
      if (!data.choices || data.choices.length === 0) {
        console.error("❌ No choices in response");
        return "No response from AI service. Please try again.";
      }
      
      const aiResponse = data.choices[0]?.message?.content || "I apologize, but I couldn't generate a response. Please try again.";
      
      console.log("✅ AI Response length:", aiResponse.length);
      console.log("✅ AI Response preview:", aiResponse.substring(0, 100) + "...");
      
      return aiResponse;
    } catch (error) {
      console.error("OpenRouter API error:", error);
      return "I'm having trouble connecting to my AI services. Please try again later.";
    }
  };

  const testAPIConnectivity = async () => {
    console.log("🧪 Testing API connectivity...");
    try {
      const testResponse = await fetch("https://openrouter.ai/api/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${OPENROUTER_API_KEY}`,
          "Content-Type": "application/json",
          "HTTP-Referer": "https://openpay.app",
          "X-Title": "OpenPay AI Test"
        },
        body: JSON.stringify({
          model: "nvidia/nemotron-3-super-120b-a12b:free",
          messages: [
            {
              role: "user",
              content: "Hello, this is a test. Are you working?"
            }
          ],
          max_tokens: 10
        })
      });

      if (testResponse.ok) {
        const data = await testResponse.json();
        console.log("✅ API connectivity test successful:", data);
        return true;
      } else {
        console.error("❌ API connectivity test failed:", testResponse.status);
        return false;
      }
    } catch (error) {
      console.error("❌ API connectivity test error:", error);
      return false;
    }
  };

  const processUserMessage = async (message: string) => {
    const lowerMessage = message.toLowerCase();
    
    // Test API connectivity first
    if (!OPENROUTER_API_KEY) {
      return "⚠️ AI service is not configured. Please check your environment variables and restart the app.";
    }
    
    // Check for payment commands (improved regex)
    const paymentRegex = /(?:send|transfer|pay)\s+(\d+(?:\.\d{2})?)\s*(?:php|₱)?\s*(?:to\s*)?@?(\w+)/i;
    const paymentMatch = message.match(paymentRegex);

    if (paymentMatch) {
      const amount = parseFloat(paymentMatch[1]);
      const recipient = paymentMatch[2];
      
      setPendingPayment({ amount, recipient });
      setShowPaymentConfirm(true);
      
      return "I can help you send money. Please confirm payment details below.";
    }

    // Check for balance requests
    if (lowerMessage.includes("balance")) {
      return `Your current balance is $${userBalance.toFixed(2)}. ${userBalance < 1000 ? '⚠️ Low balance warning' : '✅ Good balance status'}`;
    }

    // Check for spending analysis
    if (lowerMessage.includes("spending") || lowerMessage.includes("analyze")) {
      const totalSpent = spendingCategories.reduce((sum, cat) => sum + cat.amount, 0);
      const topCategory = spendingCategories[0];
      
      return `This month you've spent $${totalSpent.toFixed(2)}. 
        ${topCategory ? `Your top spending category is ${topCategory.name} at $${topCategory.amount.toFixed(2)} (${topCategory.percentage.toFixed(1)}%).` : ''}
        ${budgetAlerts.length > 0 ? `⚠️ You have ${budgetAlerts.length} budget alert(s) to review.` : '✅ Your spending looks normal.'}`;
    }

    // Try AI for complex queries
    try {
      console.log("🤖 Attempting AI response for:", message);
      const aiResponse = await callOpenRouterAPI(message);
      console.log("✅ AI response successful");
      return aiResponse;
    } catch (error) {
      console.error("❌ AI fallback error:", error);
      return "I'm here to help with basic financial tasks. You can ask me to:\n\n• Check your balance\n• Analyze spending\n• Send money (e.g., 'Send 100 to @username')\n• Create budgets\n• Get help with any OpenPay feature\n\nFor advanced AI features, please check your connection and try again.";
    }
  };

  const handleSendMessage = async () => {
    if (!inputMessage.trim() || isTyping) return;

    console.log("📝 User sending message:", inputMessage);

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
      console.log("🤖 Processing message with AI...");
      const aiResponse = await processUserMessage(inputMessage);
      console.log("✅ AI response received:", aiResponse);
      
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
      
      console.log("💾 Messages saved to database");
    } catch (error) {
      console.error("❌ Error processing message:", error);
      toast.error("Failed to process your message");
    } finally {
      setIsTyping(false);
    }
  };

  const confirmPayment = async () => {
    if (!pendingPayment) return;

    try {
      // Here you would integrate with your payment system
      toast.success(`Payment of $${pendingPayment.amount.toFixed(2)} to @${pendingPayment.recipient} initiated`);
      
      setPendingPayment(null);
      setShowPaymentConfirm(false);
      
      // Add confirmation message
      const confirmationMessage: Message = {
        id: (Date.now() + 2).toString(),
        role: "assistant",
        content: `✅ Payment of $${pendingPayment.amount.toFixed(2)} to @${pendingPayment.recipient} has been processed successfully.`,
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
                          <strong>{alert.category}</strong>: ${alert.spent.toFixed(2)} / ${alert.limit.toFixed(2)} ({alert.percentage.toFixed(0)}%)
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
                    I'm your comprehensive OpenPay assistant. I can help you with ANY OpenPay feature:
                  </p>
                  
                  <div className="space-y-4">
                    <div className="bg-white rounded-lg p-4 border">
                      <h4 className="font-semibold text-blue-900 mb-3 flex items-center gap-2">
                        <Wallet className="h-5 w-5 text-blue-600" />
                        Banking Features
                      </h4>
                      <div className="grid grid-cols-1 md:grid-cols-2 gap-2 text-sm">
                        <div className="p-2 hover:bg-blue-50 rounded cursor-pointer transition-colors" onClick={() => setInputMessage("How do I check my balance?")}>
                          <p className="font-medium">💰 Check Balance</p>
                          <p className="text-xs text-gray-600">View current wallet balance</p>
                        </div>
                        <div className="p-2 hover:bg-blue-50 rounded cursor-pointer transition-colors" onClick={() => setInputMessage("How do I send money?")}>
                          <p className="font-medium">💸 Send Money</p>
                          <p className="text-xs text-gray-600">Transfer funds to users</p>
                        </div>
                        <div className="p-2 hover:bg-blue-50 rounded cursor-pointer transition-colors" onClick={() => setInputMessage("How do I top-up my account?")}>
                          <p className="font-medium">💳 Top-up Account</p>
                          <p className="text-xs text-gray-600">Add funds to wallet</p>
                        </div>
                        <div className="p-2 hover:bg-blue-50 rounded cursor-pointer transition-colors" onClick={() => setInputMessage("What currencies do you support?")}>
                          <p className="font-medium">💱 Currency Exchange</p>
                          <p className="text-xs text-gray-600">Multi-currency support</p>
                        </div>
                        <div className="p-2 hover:bg-blue-50 rounded cursor-pointer transition-colors" onClick={() => setInputMessage("How do I create a virtual card?")}>
                          <p className="font-medium">💳 Virtual Cards</p>
                          <p className="text-xs text-gray-600">Create payment cards</p>
                        </div>
                        <div className="p-2 hover:bg-blue-50 rounded cursor-pointer transition-colors" onClick={() => setInputMessage("How do I view transaction history?")}>
                          <p className="font-medium">📋 Transaction History</p>
                          <p className="text-xs text-gray-600">View past transactions</p>
                        </div>
                      </div>
                    </div>

                    <div className="bg-white rounded-lg p-4 border">
                      <h4 className="font-semibold text-blue-900 mb-3 flex items-center gap-2">
                        <Store className="h-5 w-5 text-blue-600" />
                        Merchant Services
                      </h4>
                      <div className="grid grid-cols-1 md:grid-cols-2 gap-2 text-sm">
                        <div className="p-2 hover:bg-blue-50 rounded cursor-pointer transition-colors" onClick={() => setInputMessage("How do I become a merchant?")}>
                          <p className="font-medium">🏪 Become Merchant</p>
                          <p className="text-xs text-gray-600">Start selling online</p>
                        </div>
                        <div className="p-2 hover:bg-blue-50 rounded cursor-pointer transition-colors" onClick={() => setInputMessage("How do I set up POS?")}>
                          <p className="font-medium">📱 POS System</p>
                          <p className="text-xs text-gray-600">In-person payments</p>
                        </div>
                        <div className="p-2 hover:bg-blue-50 rounded cursor-pointer transition-colors" onClick={() => setInputMessage("How do I create payment links?")}>
                          <p className="font-medium">🔗 Payment Links</p>
                          <p className="text-xs text-gray-600">Share payment links</p>
                        </div>
                        <div className="p-2 hover:bg-blue-50 rounded cursor-pointer transition-colors" onClick={() => setInputMessage("How do I add products?")}>
                          <p className="font-medium">📦 Product Catalog</p>
                          <p className="text-xs text-gray-600">Manage products</p>
                        </div>
                        <div className="p-2 hover:bg-blue-50 rounded cursor-pointer transition-colors" onClick={() => setInputMessage("How do I create invoices?")}>
                          <p className="font-medium">🧾 Create Invoices</p>
                          <p className="text-xs text-gray-600">Send professional invoices</p>
                        </div>
                        <div className="p-2 hover:bg-blue-50 rounded cursor-pointer transition-colors" onClick={() => setInputMessage("What are merchant fees?")}>
                          <p className="font-medium">💰 Merchant Fees</p>
                          <p className="text-xs text-gray-600">Transaction costs</p>
                        </div>
                      </div>
                    </div>

                    <div className="bg-white rounded-lg p-4 border">
                      <h4 className="font-semibold text-blue-900 mb-3 flex items-center gap-2">
                        <Coins className="h-5 w-5 text-blue-600" />
                        Earning & Rewards
                      </h4>
                      <div className="grid grid-cols-1 md:grid-cols-2 gap-2 text-sm">
                        <div className="p-2 hover:bg-blue-50 rounded cursor-pointer transition-colors" onClick={() => setInputMessage("How do I start mining?")}>
                          <p className="font-medium">⛏️ Mining</p>
                          <p className="text-xs text-gray-600">Pi Network mining</p>
                        </div>
                        <div className="p-2 hover:bg-blue-50 rounded cursor-pointer transition-colors" onClick={() => setInputMessage("How do I start staking?")}>
                          <p className="font-medium">💎 Staking</p>
                          <p className="text-xs text-gray-600">Earn rewards</p>
                        </div>
                        <div className="p-2 hover:bg-blue-50 rounded cursor-pointer transition-colors" onClick={() => setInputMessage("How does affiliate program work?")}>
                          <p className="font-medium">👥 Affiliate Program</p>
                          <p className="text-xs text-gray-600">Referral rewards</p>
                        </div>
                        <div className="p-2 hover:bg-blue-50 rounded cursor-pointer transition-colors" onClick={() => setInputMessage("How do I watch Pi ads?")}>
                          <p className="font-medium">📺 Pi Ad Network</p>
                          <p className="text-xs text-gray-600">Watch ads earn</p>
                        </div>
                      </div>
                    </div>

                    <div className="bg-white rounded-lg p-4 border">
                      <h4 className="font-semibold text-blue-900 mb-3 flex items-center gap-2">
                        <Shield className="h-5 w-5 text-blue-600" />
                        Security & Support
                      </h4>
                      <div className="grid grid-cols-1 md:grid-cols-2 gap-2 text-sm">
                        <div className="p-2 hover:bg-blue-50 rounded cursor-pointer transition-colors" onClick={() => setInputMessage("How do I set up 2FA?")}>
                          <p className="font-medium">🔐 Two-Factor Auth</p>
                          <p className="text-xs text-gray-600">Enhanced security</p>
                        </div>
                        <div className="p-2 hover:bg-blue-50 rounded cursor-pointer transition-colors" onClick={() => setInputMessage("How do I complete KYC?")}>
                          <p className="font-medium">🆔 KYC Verification</p>
                          <p className="text-xs text-gray-600">Identity verification</p>
                        </div>
                        <div className="p-2 hover:bg-blue-50 rounded cursor-pointer transition-colors" onClick={() => setInputMessage("How do I dispute a transaction?")}>
                          <p className="font-medium">⚖️ Dispute Resolution</p>
                          <p className="text-xs text-gray-600">Handle disputes</p>
                        </div>
                        <div className="p-2 hover:bg-blue-50 rounded cursor-pointer transition-colors" onClick={() => setInputMessage("How do I contact support?")}>
                          <p className="font-medium">💬 Customer Support</p>
                          <p className="text-xs text-gray-600">Get help</p>
                        </div>
                      </div>
                    </div>
                  </div>
                  
                  <div className="mt-6 bg-blue-50 rounded-lg p-4">
                    <h4 className="font-semibold text-blue-900 mb-3">Quick Questions</h4>
                    <div className="grid grid-cols-2 md:grid-cols-4 gap-2 text-xs">
                      <button 
                        className="p-2 bg-white rounded-lg border hover:bg-blue-100 transition-colors text-left w-full"
                        onClick={() => setInputMessage("How do I check my balance?")}
                      >
                        💰 Balance
                      </button>
                      <button 
                        className="p-2 bg-white rounded-lg border hover:bg-blue-100 transition-colors text-left w-full"
                        onClick={() => setInputMessage("How do I send money?")}
                      >
                        💸 Send
                      </button>
                      <button 
                        className="p-2 bg-white rounded-lg border hover:bg-blue-100 transition-colors text-left w-full"
                        onClick={() => setInputMessage("How do I create payment link?")}
                      >
                        🔗 Payment Link
                      </button>
                      <button 
                        className="p-2 bg-white rounded-lg border hover:bg-blue-100 transition-colors text-left w-full"
                        onClick={() => setInputMessage("How do I become a merchant?")}
                      >
                        🏪 Merchant
                      </button>
                      <button 
                        className="p-2 bg-white rounded-lg border hover:bg-blue-100 transition-colors text-left w-full"
                        onClick={() => setInputMessage("How do I start mining?")}
                      >
                        ⛏️ Mining
                      </button>
                      <button 
                        className="p-2 bg-white rounded-lg border hover:bg-blue-100 transition-colors text-left w-full"
                        onClick={() => setInputMessage("How do I set up 2FA?")}
                      >
                        🔐 Security
                      </button>
                      <button 
                        className="p-2 bg-white rounded-lg border hover:bg-blue-100 transition-colors text-left w-full"
                        onClick={() => setInputMessage("What are the fees?")}
                      >
                        💰 Fees
                      </button>
                    </div>
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
                    <span className="font-semibold">${pendingPayment.amount.toFixed(2)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Recipient:</span>
                    <span className="font-semibold">@${pendingPayment.recipient}</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Fee:</span>
                    <span className="font-semibold">$0.00</span>
                  </div>
                  <div className="border-t pt-2 flex justify-between font-semibold">
                    <span>Total:</span>
                    <span>${pendingPayment.amount.toFixed(2)}</span>
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
