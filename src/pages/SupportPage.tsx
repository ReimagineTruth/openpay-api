import { useEffect, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { ArrowLeft, MessageCircle, Send, ExternalLink, HelpCircle, Search, LifeBuoy, MessageSquare } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import BrandLogo from "@/components/BrandLogo";
import { toast } from "sonner";

const SupportPage = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [activeTab, setActiveTab] = useState<"home" | "messages" | "help" | "telegram">("home");
  const [telegramMessage, setTelegramMessage] = useState("");
  const [telegramUsername, setTelegramUsername] = useState("");
  const [isSendingTelegram, setIsSendingTelegram] = useState(false);
  const [telegramHistory, setTelegramHistory] = useState<Array<{
    id: string;
    message: string;
    timestamp: string;
    status: "sent" | "delivered" | "failed";
  }>>([]);

  useEffect(() => {
    const tab = searchParams.get("tab");
    if (tab === "home" || tab === "messages" || tab === "help" || tab === "telegram") {
      setActiveTab(tab);
    }
  }, [searchParams]);

  const handleTabChange = (tab: typeof activeTab) => {
    setActiveTab(tab);
    navigate(`/support?tab=${tab}`);
  };

  const sendTelegramMessage = async () => {
    const message = telegramMessage.trim();
    if (!message) {
      toast.error("Please enter a message");
      return;
    }

    setIsSendingTelegram(true);
    try {
      // Open Telegram chat with pre-filled message
      const telegramUrl = `https://t.me/openpayofficial/1?text=${encodeURIComponent(message)}`;
      window.open(telegramUrl, "_blank", "noopener,noreferrer");
      
      // Add to local history
      const newMessage = {
        id: Date.now().toString(),
        message,
        timestamp: new Date().toISOString(),
        status: "sent" as const
      };
      setTelegramHistory(prev => [newMessage, ...prev]);
      setTelegramMessage("");
      toast.success("Opening Telegram support...");
    } catch (error) {
      toast.error("Failed to open Telegram support");
    } finally {
      setIsSendingTelegram(false);
    }
  };

  const copyTelegramLink = () => {
    const link = "https://t.me/openpayofficial/1";
    navigator.clipboard.writeText(link).then(() => {
      toast.success("Telegram link copied");
    }).catch(() => {
      toast.error("Failed to copy link");
    });
  };

  return (
    <div className="min-h-screen bg-gradient-to-b from-[#f1f6ff] to-background px-4 pt-4 pb-6">
      <div className="mx-auto w-full max-w-6xl">
        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <button onClick={() => navigate(-1)} className="flex h-8 w-8 items-center justify-center rounded-full border border-border">
              <ArrowLeft className="h-4 w-4" />
            </button>
            <BrandLogo className="h-7 w-7" />
            <div>
              <p className="text-sm font-semibold text-foreground">OpenPay Support</p>
              <p className="text-xs text-muted-foreground">How can we help?</p>
            </div>
          </div>
        </div>

        {/* Tab Navigation */}
        <div className="mb-6">
          <div className="inline-flex rounded-full bg-secondary/60 p-1">
            <button
              onClick={() => handleTabChange("home")}
              className={`rounded-full px-4 py-1.5 text-xs font-semibold ${
                activeTab === "home" ? "bg-white text-foreground shadow-sm" : "text-muted-foreground"
              }`}
            >
              Home
            </button>
            <button
              onClick={() => handleTabChange("messages")}
              className={`rounded-full px-4 py-1.5 text-xs font-semibold ${
                activeTab === "messages" ? "bg-white text-foreground shadow-sm" : "text-muted-foreground"
              }`}
            >
              Messages
            </button>
            <button
              onClick={() => handleTabChange("help")}
              className={`rounded-full px-4 py-1.5 text-xs font-semibold ${
                activeTab === "help" ? "bg-white text-foreground shadow-sm" : "text-muted-foreground"
              }`}
            >
              Help
            </button>
            <button
              onClick={() => handleTabChange("telegram")}
              className={`rounded-full px-4 py-1.5 text-xs font-semibold flex items-center gap-1 ${
                activeTab === "telegram" ? "bg-white text-foreground shadow-sm" : "text-muted-foreground"
              }`}
            >
              <MessageSquare className="h-3 w-3" />
              Telegram
            </button>
          </div>
        </div>

        {/* Tab Content */}
        <div className="min-h-[60vh]">
          {activeTab === "home" && (
            <div className="mx-auto w-full max-w-3xl space-y-3">
              <button 
                onClick={() => handleTabChange("messages")} 
                className="w-full rounded-xl border border-border p-4 text-left transition hover:bg-secondary/50"
              >
                <div className="flex items-center gap-3">
                  <MessageCircle className="h-5 w-5 text-paypal-blue" />
                  <div>
                    <p className="text-sm font-semibold text-foreground">Send us a message</p>
                    <p className="text-xs text-muted-foreground">Chat with our support team directly</p>
                  </div>
                </div>
              </button>
              
              <button 
                onClick={() => handleTabChange("telegram")} 
                className="w-full rounded-xl border border-border p-4 text-left transition hover:bg-secondary/50"
              >
                <div className="flex items-center gap-3">
                  <MessageSquare className="h-5 w-5 text-blue-500" />
                  <div>
                    <p className="text-sm font-semibold text-foreground">Telegram Support</p>
                    <p className="text-xs text-muted-foreground">Get instant help on Telegram</p>
                  </div>
                </div>
              </button>
              
              <button 
                onClick={() => handleTabChange("help")} 
                className="w-full rounded-xl border border-border p-4 text-left transition hover:bg-secondary/50"
              >
                <div className="flex items-center gap-3">
                  <HelpCircle className="h-5 w-5 text-green-600" />
                  <div>
                    <p className="text-sm font-semibold text-foreground">Browse Help Center</p>
                    <p className="text-xs text-muted-foreground">Find answers to common questions</p>
                  </div>
                </div>
              </button>
            </div>
          )}

          {activeTab === "telegram" && (
            <div className="mx-auto w-full max-w-4xl">
              <div className="rounded-2xl border border-border bg-white p-6">
                <div className="mb-6 text-center">
                  <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-blue-500">
                    <MessageSquare className="h-8 w-8 text-white" />
                  </div>
                  <h2 className="text-xl font-bold text-foreground mb-2">Telegram Support</h2>
                  <p className="text-sm text-muted-foreground mb-4">
                    Get instant support from our team on Telegram. We typically respond within minutes.
                  </p>
                  <div className="flex justify-center gap-4 mb-6">
                    <Button
                      onClick={() => window.open("https://t.me/openpayofficial/1", "_blank", "noopener,noreferrer")}
                      className="flex items-center gap-2 bg-blue-500 hover:bg-blue-600"
                    >
                      <MessageSquare className="h-4 w-4" />
                      Open Telegram
                    </Button>
                    <Button
                      variant="outline"
                      onClick={copyTelegramLink}
                      className="flex items-center gap-2"
                    >
                      <ExternalLink className="h-4 w-4" />
                      Copy Link
                    </Button>
                  </div>
                </div>

                {/* Quick Message Form */}
                <div className="border-t border-border pt-6">
                  <h3 className="text-lg font-semibold text-foreground mb-4">Send Quick Message</h3>
                  <div className="space-y-4">
                    <div>
                      <label className="text-sm font-medium text-foreground mb-2 block">
                        Your Message
                      </label>
                      <textarea
                        value={telegramMessage}
                        onChange={(e) => setTelegramMessage(e.target.value)}
                        placeholder="Describe your issue or question..."
                        className="w-full min-h-[100px] rounded-lg border border-border p-3 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-blue-500"
                      />
                    </div>
                    <Button
                      onClick={sendTelegramMessage}
                      disabled={isSendingTelegram || !telegramMessage.trim()}
                      className="w-full flex items-center gap-2 bg-blue-500 hover:bg-blue-600"
                    >
                      {isSendingTelegram ? (
                        <>
                          <div className="h-4 w-4 animate-spin rounded-full border-2 border-white border-t-transparent" />
                          Sending...
                        </>
                      ) : (
                        <>
                          <Send className="h-4 w-4" />
                          Send via Telegram
                        </>
                      )}
                    </Button>
                  </div>
                </div>

                {/* Message History */}
                {telegramHistory.length > 0 && (
                  <div className="mt-6 border-t border-border pt-6">
                    <h3 className="text-lg font-semibold text-foreground mb-4">Recent Messages</h3>
                    <div className="space-y-3 max-h-[200px] overflow-y-auto">
                      {telegramHistory.map((msg) => (
                        <div key={msg.id} className="rounded-lg border border-border p-3">
                          <div className="flex items-start justify-between gap-3">
                            <div className="flex-1">
                              <p className="text-sm text-foreground">{msg.message}</p>
                              <p className="text-xs text-muted-foreground mt-1">
                                {new Date(msg.timestamp).toLocaleString()}
                              </p>
                            </div>
                            <div className={`px-2 py-1 rounded text-xs font-medium ${
                              msg.status === "sent" ? "bg-green-100 text-green-800" :
                              msg.status === "delivered" ? "bg-blue-100 text-blue-800" :
                              "bg-red-100 text-red-800"
                            }`}>
                              {msg.status}
                            </div>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            </div>
          )}

          {activeTab === "messages" && (
            <div className="text-center py-12">
              <MessageCircle className="mx-auto h-12 w-12 text-muted-foreground mb-4" />
              <h2 className="text-xl font-semibold text-foreground mb-2">Support Messages</h2>
              <p className="text-sm text-muted-foreground mb-4">
                Use the support widget for detailed conversations with attachments.
              </p>
              <Button
                onClick={() => window.dispatchEvent(new CustomEvent("open-support-widget", { detail: { tab: "messages" } }))}
                className="bg-paypal-blue hover:bg-[#004dc5]"
              >
                Open Support Chat
              </Button>
            </div>
          )}

          {activeTab === "help" && (
            <div className="text-center py-12">
              <HelpCircle className="mx-auto h-12 w-12 text-muted-foreground mb-4" />
              <h2 className="text-xl font-semibold text-foreground mb-2">Help Center</h2>
              <p className="text-sm text-muted-foreground mb-4">
                Browse our FAQ and guides for instant answers.
              </p>
              <Button
                onClick={() => window.dispatchEvent(new CustomEvent("open-support-widget", { detail: { tab: "help" } }))}
                className="bg-paypal-blue hover:bg-[#004dc5]"
              >
                Browse Help Articles
              </Button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default SupportPage;
