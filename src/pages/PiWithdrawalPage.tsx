import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Progress } from "@/components/ui/progress";
import { Separator } from "@/components/ui/separator";
import { toast } from "sonner";
import { 
  ArrowLeft, 
  Send, 
  Clock, 
  CheckCircle, 
  XCircle, 
  AlertTriangle,
  History,
  Wallet,
  TrendingUp,
  RefreshCw,
  ExternalLink
} from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { 
  piWithdrawalService, 
  PiWithdrawalRequest, 
  PiWithdrawalResult, 
  PiWithdrawalRecord 
} from "@/lib/piWithdrawal";

const PiWithdrawalPage = () => {
  const navigate = useNavigate();
  const [user, setUser] = useState<any>(null);
  const [loading, setLoading] = useState(false);
  const [withdrawalHistory, setWithdrawalHistory] = useState<PiWithdrawalRecord[]>([]);
  const [userBalance, setUserBalance] = useState<number>(0);
  
  // Form states
  const [amount, setAmount] = useState<string>("");
  const [memo, setMemo] = useState<string>("");
  const [selectedCurrency, setSelectedCurrency] = useState<string>("PI");
  
  // Processing states
  const [currentWithdrawal, setCurrentWithdrawal] = useState<PiWithdrawalResult | null>(null);
  const [processingStep, setProcessingStep] = useState<string>("");
  const [processingProgress, setProcessingProgress] = useState<number>(0);

  useEffect(() => {
    checkUser();
    loadWithdrawalHistory();
    loadUserBalance();
  }, []);

  const checkUser = async () => {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
      navigate('/auth');
      return;
    }
    setUser(user);
  };

  const loadWithdrawalHistory = async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (user) {
        const history = await piWithdrawalService.getUserWithdrawalHistory(user.id);
        setWithdrawalHistory(history);
      }
    } catch (error) {
      console.error('Error loading withdrawal history:', error);
    }
  };

  const loadUserBalance = async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (user) {
        // For now, use a mock balance since the table might not exist yet
        // In production, this would query the user_balances table
        setUserBalance(1000); // Mock balance for testing
      }
    } catch (error) {
      console.error('Error loading user balance:', error);
    }
  };

  const handleWithdrawal = async () => {
    if (!user || !amount || parseFloat(amount) <= 0) {
      toast.error('Please enter a valid amount');
      return;
    }

    if (parseFloat(amount) > userBalance) {
      toast.error('Insufficient balance');
      return;
    }

    setLoading(true);
    setProcessingStep('Creating withdrawal request...');
    setProcessingProgress(10);

    try {
      const withdrawalRequest: PiWithdrawalRequest = {
        amount: parseFloat(amount),
        memo: memo || `A2U Withdrawal from OpenPay`,
        metadata: {
          source: 'openpay_app',
          timestamp: new Date().toISOString(),
          currency: selectedCurrency
        },
        userUid: user.id
      };

      setProcessingProgress(30);
      setProcessingStep('Processing with Pi Network...');

      const result = await piWithdrawalService.processCompleteWithdrawal(withdrawalRequest);

      setProcessingProgress(70);
      setProcessingStep('Finalizing transaction...');

      if (result.success) {
        setProcessingProgress(100);
        setProcessingStep('Withdrawal completed successfully!');
        setCurrentWithdrawal(result);
        
        toast.success('Withdrawal completed successfully!');
        
        // Reload data
        await loadWithdrawalHistory();
        await loadUserBalance();
        
        // Reset form
        setAmount("");
        setMemo("");
      } else {
        throw new Error(result.error || 'Withdrawal failed');
      }

    } catch (error: any) {
      console.error('Withdrawal error:', error);
      toast.error(error.message || 'Withdrawal failed. Please try again.');
      setProcessingStep('');
      setProcessingProgress(0);
    } finally {
      setLoading(false);
    }
  };

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'completed':
        return <Badge className="bg-green-100 text-green-800"><CheckCircle className="w-3 h-3 mr-1" />Completed</Badge>;
      case 'pending':
      case 'submitted':
        return <Badge className="bg-yellow-100 text-yellow-800"><Clock className="w-3 h-3 mr-1" />Processing</Badge>;
      case 'failed':
        return <Badge className="bg-red-100 text-red-800"><XCircle className="w-3 h-3 mr-1" />Failed</Badge>;
      case 'cancelled':
        return <Badge className="bg-gray-100 text-gray-800"><XCircle className="w-3 h-3 mr-1" />Cancelled</Badge>;
      default:
        return <Badge className="bg-gray-100 text-gray-800">{status}</Badge>;
    }
  };

  const formatAmount = (amount: number) => {
    return new Intl.NumberFormat('en-US', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 8
    }).format(amount);
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-paypal-blue to-[#072a7a] p-4">
      <div className="max-w-4xl mx-auto">
        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center space-x-4">
            <Button
              variant="ghost"
              onClick={() => navigate('/menu')}
              className="text-white hover:bg-white/10"
            >
              <ArrowLeft className="w-4 h-4 mr-2" />
              Back to Menu
            </Button>
            <div>
              <h1 className="text-2xl font-bold text-white">Pi Network Withdrawal</h1>
              <p className="text-white/80">Withdraw your Pi tokens using A2U (App-to-User) payment</p>
            </div>
          </div>
          <div className="flex items-center space-x-2">
            <Wallet className="w-5 h-5 text-white" />
            <span className="text-white font-semibold">
              {formatAmount(userBalance)} PI
            </span>
          </div>
        </div>

        <Tabs defaultValue="withdraw" className="space-y-6">
          <TabsList className="grid w-full grid-cols-2 bg-white/10">
            <TabsTrigger value="withdraw" className="text-white data-[state=active]:bg-white">
              New Withdrawal
            </TabsTrigger>
            <TabsTrigger value="history" className="text-white data-[state=active]:bg-white">
              <History className="w-4 h-4 mr-2" />
              History
            </TabsTrigger>
          </TabsList>

          <TabsContent value="withdraw">
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center">
                  <TrendingUp className="w-5 h-5 mr-2" />
                  Create Withdrawal
                </CardTitle>
                <CardDescription>
                  Withdraw your Pi tokens directly to your Pi Network wallet using A2U payment technology.
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-6">
                {/* Balance Card */}
                <div className="bg-gradient-to-r from-purple-50 to-blue-50 p-4 rounded-lg border">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm font-medium text-gray-600">Available Balance</p>
                      <p className="text-2xl font-bold text-gray-900">
                        {formatAmount(userBalance)} PI
                      </p>
                    </div>
                    <Wallet className="w-8 h-8 text-purple-600" />
                  </div>
                </div>

                {/* Withdrawal Form */}
                <div className="space-y-4">
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div className="space-y-2">
                      <Label htmlFor="amount">Amount (PI)</Label>
                      <Input
                        id="amount"
                        type="number"
                        placeholder="0.00000000"
                        value={amount}
                        onChange={(e) => setAmount(e.target.value)}
                        disabled={loading}
                        min="0.00000001"
                        max={userBalance}
                        step="0.00000001"
                      />
                      <p className="text-xs text-gray-500">
                        Available: {formatAmount(userBalance)} PI
                      </p>
                    </div>
                    
                    <div className="space-y-2">
                      <Label htmlFor="currency">Currency</Label>
                      <Select value={selectedCurrency} onValueChange={setSelectedCurrency} disabled={loading}>
                        <SelectTrigger>
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="PI">Pi Network (PI)</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="memo">Memo (Optional)</Label>
                    <Textarea
                      id="memo"
                      placeholder="Add a note for this withdrawal..."
                      value={memo}
                      onChange={(e) => setMemo(e.target.value)}
                      disabled={loading}
                      rows={3}
                    />
                  </div>
                </div>

                {/* Processing Progress */}
                {loading && (
                  <div className="space-y-2">
                    <div className="flex items-center justify-between">
                      <span className="text-sm font-medium">{processingStep}</span>
                      <span className="text-sm text-gray-500">{processingProgress}%</span>
                    </div>
                    <Progress value={processingProgress} className="w-full" />
                  </div>
                )}

                {/* Success Result */}
                {currentWithdrawal?.success && (
                  <Alert className="bg-green-50 border-green-200">
                    <CheckCircle className="h-4 w-4 text-green-600" />
                    <AlertDescription className="text-green-800">
                      <div className="space-y-2">
                        <p className="font-semibold">Withdrawal Completed Successfully!</p>
                        <div className="text-sm space-y-1">
                          <p>Payment ID: {currentWithdrawal.paymentId}</p>
                          <p>Transaction ID: {currentWithdrawal.txid}</p>
                          <p>Amount: {formatAmount(parseFloat(amount))} PI</p>
                        </div>
                      </div>
                    </AlertDescription>
                  </Alert>
                )}

                {/* Action Buttons */}
                <div className="flex space-x-4">
                  <Button
                    onClick={handleWithdrawal}
                    disabled={loading || !amount || parseFloat(amount) <= 0 || parseFloat(amount) > userBalance}
                    className="flex-1"
                  >
                    {loading ? (
                      <>
                        <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                        Processing...
                      </>
                    ) : (
                      <>
                        <Send className="w-4 h-4 mr-2" />
                        Withdraw {amount && formatAmount(parseFloat(amount))} PI
                      </>
                    )}
                  </Button>
                  
                  <Button
                    variant="outline"
                    onClick={() => {
                      setAmount("");
                      setMemo("");
                      setCurrentWithdrawal(null);
                      setProcessingStep("");
                      setProcessingProgress(0);
                    }}
                    disabled={loading}
                  >
                    Clear
                  </Button>
                </div>

                {/* Information */}
                <Alert>
                  <AlertTriangle className="h-4 w-4" />
                  <AlertDescription>
                    <strong>Important:</strong> Withdrawals use Pi Network's A2U (App-to-User) payment system. 
                    The withdrawal will be processed immediately and the Pi tokens will be sent to your 
                    connected Pi Network wallet. Transaction fees may apply.
                  </AlertDescription>
                </Alert>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="history">
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center justify-between">
                  <span className="flex items-center">
                    <History className="w-5 h-5 mr-2" />
                    Withdrawal History
                  </span>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={loadWithdrawalHistory}
                  >
                    <RefreshCw className="w-4 h-4 mr-2" />
                    Refresh
                  </Button>
                </CardTitle>
                <CardDescription>
                  View your past Pi Network withdrawals and their current status.
                </CardDescription>
              </CardHeader>
              <CardContent>
                {withdrawalHistory.length === 0 ? (
                  <div className="text-center py-8">
                    <History className="w-12 h-12 mx-auto text-gray-400 mb-4" />
                    <p className="text-gray-500">No withdrawal history found</p>
                    <p className="text-sm text-gray-400 mt-2">
                      Your withdrawal history will appear here once you make your first withdrawal.
                    </p>
                  </div>
                ) : (
                  <div className="space-y-4">
                    {withdrawalHistory.map((withdrawal) => (
                      <div key={withdrawal.id} className="border rounded-lg p-4">
                        <div className="flex items-center justify-between mb-2">
                          <div className="flex items-center space-x-3">
                            <div>
                              <p className="font-semibold">
                                {formatAmount(withdrawal.amount)} PI
                              </p>
                              <p className="text-sm text-gray-500">
                                {new Date(withdrawal.created_at).toLocaleString()}
                              </p>
                            </div>
                          </div>
                          {getStatusBadge(withdrawal.status)}
                        </div>
                        
                        <p className="text-sm text-gray-600 mb-2">{withdrawal.memo}</p>
                        
                        {withdrawal.txid && (
                          <div className="flex items-center space-x-2 text-sm">
                            <span className="text-gray-500">Transaction ID:</span>
                            <code className="bg-gray-100 px-2 py-1 rounded text-xs">
                              {withdrawal.txid}
                            </code>
                            <Button
                              variant="ghost"
                              size="sm"
                              className="h-6 px-2"
                              onClick={() => {
                                // Open Pi Network explorer link
                                window.open(
                                  `https://explorer.minepi.com/transactions/${withdrawal.txid}`,
                                  '_blank'
                                );
                              }}
                            >
                              <ExternalLink className="w-3 h-3" />
                            </Button>
                          </div>
                        )}
                        
                        <div className="mt-3 pt-3 border-t text-xs text-gray-500">
                          <p>Payment ID: {withdrawal.payment_id}</p>
                          <p>Network: {withdrawal.network}</p>
                          {withdrawal.to_address && (
                            <p>To: {withdrawal.to_address.slice(0, 10)}...{withdrawal.to_address.slice(-10)}</p>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </div>
    </div>
  );
};

export default PiWithdrawalPage;
