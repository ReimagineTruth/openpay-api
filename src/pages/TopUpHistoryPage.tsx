import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { ArrowLeft, RefreshCw, ExternalLink, MessageSquare, CheckCircle, XCircle, Clock, DollarSign, Calendar, User, FileText, HelpCircle, AlertCircle } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import BrandLogo from "@/components/BrandLogo";
import { toast } from "sonner";

type TopUpRequest = {
  id: string;
  user_id: string;
  provider: string;
  amount: number;
  openpay_account_name: string;
  openpay_account_username: string;
  openpay_account_number: string;
  reference_code: string;
  proof_url: string;
  status: string;
  admin_note: string;
  transfer_transaction_id?: string | null;
  reviewed_by?: string | null;
  reviewed_at?: string | null;
  created_at: string;
  updated_at: string;
};

const TopUpHistoryPage = () => {
  const navigate = useNavigate();
  const [topUpRequests, setTopUpRequests] = useState<TopUpRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [selectedRequest, setSelectedRequest] = useState<TopUpRequest | null>(null);
  const [showProofDialog, setShowProofDialog] = useState(false);
  const [showSupportDialog, setShowSupportDialog] = useState(false);

  useEffect(() => {
    loadTopUpHistory();
  }, []);

  const loadTopUpHistory = async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) {
        toast.error("Please login to view top-up history");
        return;
      }

      const { data, error } = await supabase
        .from("user_topup_requests")
        .select("*")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false });

      if (error) throw error;
      setTopUpRequests(data || []);
    } catch (error) {
      console.error("Error loading top-up history:", error);
      toast.error("Failed to load top-up history");
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  const handleRefresh = () => {
    setRefreshing(true);
    loadTopUpHistory();
  };

  const openTelegramSupport = () => {
    window.open("https://t.me/openpayofficial", "_blank", "noopener,noreferrer");
  };

  const copyTelegramLink = () => {
    navigator.clipboard.writeText("https://t.me/openpayofficial").then(() => {
      toast.success("Telegram link copied");
    }).catch(() => {
      toast.error("Failed to copy link");
    });
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case "approved":
        return "text-green-600 bg-green-50 border-green-200";
      case "rejected":
        return "text-red-600 bg-red-50 border-red-200";
      case "pending":
        return "text-yellow-600 bg-yellow-50 border-yellow-200";
      default:
        return "text-gray-600 bg-gray-50 border-gray-200";
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case "approved":
        return <CheckCircle className="h-4 w-4" />;
      case "rejected":
        return <XCircle className="h-4 w-4" />;
      case "pending":
        return <Clock className="h-4 w-4" />;
      default:
        return <AlertCircle className="h-4 w-4" />;
    }
  };

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleString("en-US", {
      year: "numeric",
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit"
    });
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-b from-[#f1f6ff] to-background px-4 pt-4 pb-6">
        <div className="mx-auto w-full max-w-4xl">
          <div className="flex items-center justify-center py-12">
            <div className="h-8 w-8 animate-spin rounded-full border-2 border-paypal-blue border-t-transparent" />
            <span className="ml-2 text-sm text-muted-foreground">Loading top-up history...</span>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-b from-[#f1f6ff] to-background px-4 pt-4 pb-6">
      <div className="mx-auto w-full max-w-4xl">
        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <button onClick={() => navigate(-1)} className="flex h-8 w-8 items-center justify-center rounded-full border border-border">
              <ArrowLeft className="h-4 w-4" />
            </button>
            <BrandLogo className="h-7 w-7" />
            <div>
              <p className="text-sm font-semibold text-foreground">Top-Up History</p>
              <p className="text-xs text-muted-foreground">Track your top-up requests</p>
            </div>
          </div>
          <Button
            onClick={handleRefresh}
            disabled={refreshing}
            variant="outline"
            className="flex items-center gap-2"
          >
            <RefreshCw className={`h-4 w-4 ${refreshing ? "animate-spin" : ""}`} />
            Refresh
          </Button>
        </div>

        {/* Stats Cards */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          <div className="rounded-xl border border-border bg-white p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-xs text-muted-foreground">Total Requests</p>
                <p className="text-2xl font-bold text-foreground">{topUpRequests.length}</p>
              </div>
              <FileText className="h-8 w-8 text-blue-500" />
            </div>
          </div>
          <div className="rounded-xl border border-border bg-white p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-xs text-muted-foreground">Pending</p>
                <p className="text-2xl font-bold text-yellow-600">
                  {topUpRequests.filter(r => r.status === "pending").length}
                </p>
              </div>
              <Clock className="h-8 w-8 text-yellow-500" />
            </div>
          </div>
          <div className="rounded-xl border border-border bg-white p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-xs text-muted-foreground">Approved</p>
                <p className="text-2xl font-bold text-green-600">
                  {topUpRequests.filter(r => r.status === "approved").length}
                </p>
              </div>
              <CheckCircle className="h-8 w-8 text-green-500" />
            </div>
          </div>
        </div>

        {/* Telegram Support Banner */}
        <div className="rounded-xl border border-blue-200 bg-blue-50 p-4 mb-6">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <MessageSquare className="h-6 w-6 text-blue-600" />
              <div>
                <p className="text-sm font-semibold text-blue-900">Need help with your top-up?</p>
                <p className="text-xs text-blue-700">Get instant support on Telegram</p>
              </div>
            </div>
            <div className="flex gap-2">
              <Button
                onClick={openTelegramSupport}
                className="bg-blue-600 hover:bg-blue-700 text-white"
              >
                <MessageSquare className="h-4 w-4 mr-1" />
                Telegram
              </Button>
              <Button
                variant="outline"
                onClick={copyTelegramLink}
                className="border-blue-200 text-blue-700 hover:bg-blue-100"
              >
                <ExternalLink className="h-4 w-4 mr-1" />
                Copy Link
              </Button>
            </div>
          </div>
        </div>

        {/* Top-Up Requests List */}
        <div className="space-y-4">
          {topUpRequests.length === 0 ? (
            <div className="rounded-xl border border-border bg-white p-8 text-center">
              <FileText className="mx-auto h-12 w-12 text-muted-foreground mb-4" />
              <h3 className="text-lg font-semibold text-foreground mb-2">No Top-Up Requests</h3>
              <p className="text-sm text-muted-foreground mb-4">
                You haven't made any top-up requests yet.
              </p>
              <Button
                onClick={() => navigate("/menu")}
                className="bg-paypal-blue hover:bg-[#004dc5]"
              >
                Make a Top-Up
              </Button>
            </div>
          ) : (
            topUpRequests.map((request) => (
              <div key={request.id} className="rounded-xl border border-border bg-white p-4">
                <div className="flex items-start justify-between mb-3">
                  <div className="flex items-center gap-2">
                    <div className={`px-2 py-1 rounded-full text-xs font-medium border flex items-center gap-1 ${getStatusColor(request.status)}`}>
                      {getStatusIcon(request.status)}
                      {request.status.charAt(0).toUpperCase() + request.status.slice(1)}
                    </div>
                    <span className="text-xs text-muted-foreground">
                      {formatDate(request.created_at)}
                    </span>
                  </div>
                  <div className="flex items-center gap-1">
                    <DollarSign className="h-4 w-4 text-green-600" />
                    <span className="text-lg font-bold text-foreground">${request.amount}</span>
                  </div>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-3 text-sm">
                  <div className="flex items-center gap-2">
                    <User className="h-4 w-4 text-muted-foreground" />
                    <span className="text-muted-foreground">Provider:</span>
                    <span className="font-medium text-foreground">{request.provider}</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <FileText className="h-4 w-4 text-muted-foreground" />
                    <span className="text-muted-foreground">Reference:</span>
                    <span className="font-medium text-foreground">{request.reference_code}</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <User className="h-4 w-4 text-muted-foreground" />
                    <span className="text-muted-foreground">Account:</span>
                    <span className="font-medium text-foreground">{request.openpay_account_number}</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <Calendar className="h-4 w-4 text-muted-foreground" />
                    <span className="text-muted-foreground">Username:</span>
                    <span className="font-medium text-foreground">@{request.openpay_account_username}</span>
                  </div>
                </div>

                {request.admin_note && (
                  <div className="mt-3 p-2 rounded-lg bg-gray-50 border border-gray-200">
                    <p className="text-xs text-muted-foreground mb-1">Admin Note:</p>
                    <p className="text-sm text-foreground">{request.admin_note}</p>
                  </div>
                )}

                <div className="flex items-center justify-between mt-4 pt-3 border-t border-border">
                  <div className="text-xs text-muted-foreground">
                    {request.reviewed_at && (
                      <span>Reviewed: {formatDate(request.reviewed_at)}</span>
                    )}
                  </div>
                  <div className="flex gap-2">
                    {request.proof_url && (
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => {
                          setSelectedRequest(request);
                          setShowProofDialog(true);
                        }}
                        className="text-xs"
                      >
                        <ExternalLink className="h-3 w-3 mr-1" />
                        View Proof
                      </Button>
                    )}
                    {request.status === "rejected" && (
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => setShowSupportDialog(true)}
                        className="text-xs text-red-600 border-red-200 hover:bg-red-50"
                      >
                        <HelpCircle className="h-3 w-3 mr-1" />
                        Get Help
                      </Button>
                    )}
                  </div>
                </div>
              </div>
            ))
          )}
        </div>

        {/* Proof Dialog */}
        <Dialog open={showProofDialog} onOpenChange={setShowProofDialog}>
          <DialogContent className="max-w-2xl">
            <DialogTitle>Top-Up Proof</DialogTitle>
            <DialogDescription>
              Payment proof for the top-up request
            </DialogDescription>
            {selectedRequest?.proof_url && (
              <div className="mt-4">
                <img 
                  src={selectedRequest.proof_url} 
                  alt="Top-up proof" 
                  className="w-full rounded-lg border border-border"
                />
                <div className="mt-3 text-sm text-muted-foreground">
                  <p><strong>Amount:</strong> ${selectedRequest.amount}</p>
                  <p><strong>Provider:</strong> {selectedRequest.provider}</p>
                  <p><strong>Reference:</strong> {selectedRequest.reference_code}</p>
                  <p><strong>Date:</strong> {formatDate(selectedRequest.created_at)}</p>
                </div>
              </div>
            )}
          </DialogContent>
        </Dialog>

        {/* Support Dialog */}
        <Dialog open={showSupportDialog} onOpenChange={setShowSupportDialog}>
          <DialogContent className="max-w-md">
            <DialogTitle>Need Help?</DialogTitle>
            <DialogDescription>
              If your top-up was rejected, you can get help from our support team.
            </DialogDescription>
            <div className="mt-4 space-y-3">
              <Button
                onClick={openTelegramSupport}
                className="w-full bg-blue-600 hover:bg-blue-700"
              >
                <MessageSquare className="h-4 w-4 mr-2" />
                Contact Support on Telegram
              </Button>
              <Button
                variant="outline"
                onClick={copyTelegramLink}
                className="w-full"
              >
                <ExternalLink className="h-4 w-4 mr-2" />
                Copy Telegram Link
              </Button>
              <Button
                variant="outline"
                onClick={() => navigate("/support")}
                className="w-full"
              >
                <HelpCircle className="h-4 w-4 mr-2" />
                Visit Support Center
              </Button>
            </div>
          </DialogContent>
        </Dialog>
      </div>
    </div>
  );
};

export default TopUpHistoryPage;
