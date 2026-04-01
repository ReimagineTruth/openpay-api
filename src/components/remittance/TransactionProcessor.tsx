import { useState, useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { ArrowRightLeft, DollarSign, User, Phone, Mail, Globe, Receipt, CheckCircle, Clock, AlertCircle, Search, Filter, Download, QrCode } from "lucide-react";
import { toast } from "sonner";
import { format } from "date-fns";
import { QRCodeSVG } from "qrcode.react";
import { useCurrency } from "@/contexts/CurrencyContext";

interface MerchantStore {
  id: string;
  store_name: string;
  business_type: string;
  address: string;
  city: string;
  country: string;
  phone: string;
  email?: string;
}

interface MerchantFee {
  transaction_type: string;
  fee_type: string;
  fee_value: number;
  min_fee?: number;
  max_fee?: number;
  currency_code: string;
}

interface RemittanceTransaction {
  id: string;
  merchant_id: string;
  transaction_type: string;
  customer_name?: string;
  customer_phone?: string;
  customer_email?: string;
  amount: number;
  currency_code: string;
  fee_amount: number;
  net_amount: number;
  exchange_rate?: number;
  target_currency?: string;
  target_amount?: number;
  recipient_name?: string;
  recipient_phone?: string;
  recipient_bank?: string;
  recipient_account?: string;
  status: string;
  reference_number: string;
  notes?: string;
  created_at: string;
  processed_at?: string;
}

interface TransactionProcessorProps {
  selectedStore: MerchantStore | null;
}

const TransactionProcessor: React.FC<TransactionProcessorProps> = ({ selectedStore }) => {
  const { format: formatCurrency } = useCurrency();
  const [transactions, setTransactions] = useState<RemittanceTransaction[]>([]);
  const [fees, setFees] = useState<MerchantFee[]>([]);
  const [loading, setLoading] = useState(false);
  const [showTransactionDialog, setShowTransactionDialog] = useState(false);
  const [showDetailsDialog, setShowDetailsDialog] = useState(false);
  const [selectedTransaction, setSelectedTransaction] = useState<RemittanceTransaction | null>(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState("all");

  // Transaction form state
  const [transactionForm, setTransactionForm] = useState({
    transaction_type: "cash_in",
    customer_name: "",
    customer_phone: "",
    customer_email: "",
    amount: "",
    currency_code: "USD",
    target_currency: "USD",
    exchange_rate: "1",
    recipient_name: "",
    recipient_phone: "",
    recipient_bank: "",
    recipient_account: "",
    notes: "",
  });

  useEffect(() => {
    if (selectedStore) {
      loadTransactions();
      loadFees();
    }
  }, [selectedStore]);

  const loadTransactions = async () => {
    if (!selectedStore) return;

    try {
      const { data, error } = await (supabase as any)
        .from("remittance_transactions")
        .select("*")
        .eq("merchant_id", selectedStore.id)
        .order("created_at", { ascending: false });

      if (error) throw error;
      setTransactions((data || []) as RemittanceTransaction[]);
    } catch (error) {
      console.error("Error loading transactions:", error);
      toast.error("Failed to load transactions");
    }
  };

  const loadFees = async () => {
    if (!selectedStore) return;

    try {
      const { data, error } = await (supabase as any)
        .from("remittance_merchant_fees")
        .select("*")
        .eq("merchant_id", selectedStore.id)
        .eq("is_active", true);

      if (error) throw error;
      setFees((data || []) as MerchantFee[]);
    } catch (error) {
      console.error("Error loading fees:", error);
    }
  };

  const calculateFee = (amount: number, transactionType: string): number => {
    const fee = fees.find(f => f.transaction_type === transactionType);
    if (!fee) return amount * 0.015; // Default 1.5%

    if (fee.fee_type === "percentage") {
      let calculatedFee = amount * fee.fee_value / 100;
      if (fee.min_fee && calculatedFee < fee.min_fee) calculatedFee = fee.min_fee;
      if (fee.max_fee && calculatedFee > fee.max_fee) calculatedFee = fee.max_fee;
      return calculatedFee;
    } else if (fee.fee_type === "fixed") {
      return fee.fee_value;
    } else {
      return amount * fee.fee_value / 100;
    }
  };

  const handleCreateTransaction = async () => {
    if (!selectedStore) return;

    try {
      setLoading(true);

      const amount = parseFloat(transactionForm.amount);
      if (!amount || amount <= 0) {
        toast.error("Please enter a valid amount");
        return;
      }

      const feeAmount = calculateFee(amount, transactionForm.transaction_type);
      const netAmount = transactionForm.transaction_type === "cash_in" ? amount : amount - feeAmount;

      // Generate reference number
      const referenceNumber = `REM${Date.now()}${Math.floor(Math.random() * 1000).toString().padStart(3, '0')}`;

      const transactionData = {
        merchant_id: selectedStore.id,
        transaction_type: transactionForm.transaction_type,
        customer_name: transactionForm.customer_name || null,
        customer_phone: transactionForm.customer_phone || null,
        customer_email: transactionForm.customer_email || null,
        amount,
        currency_code: transactionForm.currency_code,
        fee_amount: feeAmount,
        net_amount: netAmount,
        exchange_rate: parseFloat(transactionForm.exchange_rate) || 1,
        target_currency: transactionForm.target_currency,
        target_amount: transactionForm.target_currency !== transactionForm.currency_code ? 
          netAmount * (parseFloat(transactionForm.exchange_rate) || 1) : netAmount,
        recipient_name: transactionForm.recipient_name || null,
        recipient_phone: transactionForm.recipient_phone || null,
        recipient_bank: transactionForm.recipient_bank || null,
        recipient_account: transactionForm.recipient_account || null,
        status: "pending",
        reference_number: referenceNumber,
        notes: transactionForm.notes || null,
      };

      const { data, error } = await (supabase as any)
        .from("remittance_transactions")
        .insert(transactionData)
        .select()
        .single();

      if (error) throw error;

      // Update merchant revenue
      await (supabase as any).rpc("update_merchant_revenue", {
        p_merchant_id: selectedStore.id,
        p_transaction_id: (data as any).id,
        p_fee_amount: feeAmount,
      });

      toast.success(`Transaction created: ${referenceNumber}`);
      setShowTransactionDialog(false);
      resetTransactionForm();
      loadTransactions();
    } catch (error) {
      console.error("Error creating transaction:", error);
      toast.error("Failed to create transaction");
    } finally {
      setLoading(false);
    }
  };

  const handleProcessTransaction = async (transactionId: string, newStatus: string) => {
    try {
      const { error } = await (supabase as any)
        .from("remittance_transactions")
        .update({
          status: newStatus,
          processed_at: newStatus === "completed" ? new Date().toISOString() : null,
        })
        .eq("id", transactionId);

      if (error) throw error;

      toast.success(`Transaction ${newStatus}`);
      loadTransactions();
    } catch (error) {
      console.error("Error updating transaction:", error);
      toast.error("Failed to update transaction");
    }
  };

  const resetTransactionForm = () => {
    setTransactionForm({
      transaction_type: "cash_in",
      customer_name: "",
      customer_phone: "",
      customer_email: "",
      amount: "",
      currency_code: "USD",
      target_currency: "USD",
      exchange_rate: "1",
      recipient_name: "",
      recipient_phone: "",
      recipient_bank: "",
      recipient_account: "",
      notes: "",
    });
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case "completed": return "bg-green-100 text-green-800";
      case "processing": return "bg-blue-100 text-blue-800";
      case "pending": return "bg-yellow-100 text-yellow-800";
      case "failed": return "bg-red-100 text-red-800";
      case "cancelled": return "bg-gray-100 text-gray-800";
      default: return "bg-gray-100 text-gray-800";
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case "completed": return <CheckCircle className="h-4 w-4" />;
      case "processing": return <Clock className="h-4 w-4" />;
      case "pending": return <AlertCircle className="h-4 w-4" />;
      case "failed": return <AlertCircle className="h-4 w-4" />;
      case "cancelled": return <AlertCircle className="h-4 w-4" />;
      default: return <Clock className="h-4 w-4" />;
    }
  };

  const filteredTransactions = transactions.filter(tx => {
    const matchesSearch = tx.reference_number.toLowerCase().includes(searchQuery.toLowerCase()) ||
                         (tx.customer_name && tx.customer_name.toLowerCase().includes(searchQuery.toLowerCase())) ||
                         (tx.recipient_name && tx.recipient_name.toLowerCase().includes(searchQuery.toLowerCase()));
    const matchesStatus = statusFilter === "all" || tx.status === statusFilter;
    return matchesSearch && matchesStatus;
  });

  const generateTransactionQR = (transaction: RemittanceTransaction) => {
    return JSON.stringify({
      type: "remittance_transaction",
      transaction_id: transaction.id,
      reference_number: transaction.reference_number,
      merchant: selectedStore?.store_name,
      amount: transaction.amount,
      currency: transaction.currency_code,
      status: transaction.status,
    });
  };

  if (!selectedStore) {
    return (
      <div className="text-center py-12">
        <Store className="mx-auto h-12 w-12 text-muted-foreground mb-4" />
        <h3 className="text-lg font-medium mb-2">No Store Selected</h3>
        <p className="text-muted-foreground">Select a store to start processing transactions</p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold">Transactions</h2>
          <p className="text-muted-foreground">{selectedStore.store_name} - {selectedStore.address}</p>
        </div>
        <Button onClick={() => setShowTransactionDialog(true)}>
          <DollarSign className="mr-2 h-4 w-4" />
          New Transaction
        </Button>
      </div>

      {/* Quick Stats */}
      <div className="grid grid-cols-4 gap-4">
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-2">
              <DollarSign className="h-5 w-5 text-green-600" />
              <div>
                <p className="text-sm text-muted-foreground">Today's Revenue</p>
                <p className="text-lg font-bold">
                  {formatCurrency(
                    transactions
                      .filter(tx => tx.status === "completed" && 
                                   new Date(tx.created_at).toDateString() === new Date().toDateString())
                      .reduce((sum, tx) => sum + tx.fee_amount, 0)
                  )}
                </p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-2">
              <CheckCircle className="h-5 w-5 text-blue-600" />
              <div>
                <p className="text-sm text-muted-foreground">Completed</p>
                <p className="text-lg font-bold">
                  {transactions.filter(tx => tx.status === "completed").length}
                </p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-2">
              <Clock className="h-5 w-5 text-yellow-600" />
              <div>
                <p className="text-sm text-muted-foreground">Pending</p>
                <p className="text-lg font-bold">
                  {transactions.filter(tx => tx.status === "pending").length}
                </p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-2">
              <Receipt className="h-5 w-5 text-purple-600" />
              <div>
                <p className="text-sm text-muted-foreground">Total Today</p>
                <p className="text-lg font-bold">
                  {transactions.filter(tx => 
                    new Date(tx.created_at).toDateString() === new Date().toDateString()
                  ).length}
                </p>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Search and Filter */}
      <div className="flex gap-4">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="Search by reference, customer, or recipient..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="pl-10"
          />
        </div>
        <Select value={statusFilter} onValueChange={setStatusFilter}>
          <SelectTrigger className="w-40">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Status</SelectItem>
            <SelectItem value="pending">Pending</SelectItem>
            <SelectItem value="processing">Processing</SelectItem>
            <SelectItem value="completed">Completed</SelectItem>
            <SelectItem value="failed">Failed</SelectItem>
            <SelectItem value="cancelled">Cancelled</SelectItem>
          </SelectContent>
        </Select>
      </div>

      {/* Transactions List */}
      <div className="space-y-3">
        {filteredTransactions.map((transaction) => (
          <Card key={transaction.id} className="cursor-pointer hover:shadow-md transition-shadow">
            <CardContent className="p-4">
              <div className="flex items-start justify-between">
                <div className="flex-1">
                  <div className="flex items-center gap-2 mb-2">
                    <span className="font-mono text-sm font-semibold">{transaction.reference_number}</span>
                    <Badge className={getStatusColor(transaction.status)}>
                      {getStatusIcon(transaction.status)}
                      <span className="ml-1">{transaction.status}</span>
                    </Badge>
                    <Badge variant="outline" className="capitalize">
                      {transaction.transaction_type.replace("_", " ")}
                    </Badge>
                  </div>
                  
                  <div className="grid grid-cols-2 gap-4 text-sm">
                    <div>
                      <p className="text-muted-foreground">Amount: {formatCurrency(transaction.amount)}</p>
                      <p className="text-muted-foreground">Fee: {formatCurrency(transaction.fee_amount)}</p>
                      <p className="text-muted-foreground">Net: {formatCurrency(transaction.net_amount)}</p>
                    </div>
                    <div>
                      {transaction.customer_name && <p className="text-muted-foreground">Customer: {transaction.customer_name}</p>}
                      {transaction.recipient_name && <p className="text-muted-foreground">Recipient: {transaction.recipient_name}</p>}
                      <p className="text-muted-foreground">{format(new Date(transaction.created_at), "MMM d, yyyy h:mm a")}</p>
                    </div>
                  </div>

                  {transaction.notes && (
                    <p className="text-sm text-muted-foreground mt-2 italic">"{transaction.notes}"</p>
                  )}
                </div>

                <div className="flex flex-col gap-2">
                  <Dialog>
                    <DialogTrigger asChild>
                      <Button variant="outline" size="sm">
                        <QrCode className="h-3 w-3" />
                      </Button>
                    </DialogTrigger>
                    <DialogContent>
                      <DialogHeader>
                        <DialogTitle>Transaction QR Code</DialogTitle>
                        <DialogDescription>
                          Scan for transaction details
                        </DialogDescription>
                      </DialogHeader>
                      <div className="flex flex-col items-center space-y-4">
                        <div className="p-4 bg-white rounded-lg">
                          <QRCodeSVG
                            value={generateTransactionQR(transaction)}
                            size={200}
                            level="H"
                          />
                        </div>
                        <div className="text-center">
                          <p className="font-medium">{transaction.reference_number}</p>
                          <p className="text-sm text-muted-foreground">{formatCurrency(transaction.amount)}</p>
                          <p className="text-sm text-muted-foreground">{transaction.status}</p>
                        </div>
                      </div>
                    </DialogContent>
                  </Dialog>

                  {transaction.status === "pending" && (
                    <div className="flex gap-1">
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => handleProcessTransaction(transaction.id, "processing")}
                      >
                        Process
                      </Button>
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => handleProcessTransaction(transaction.id, "completed")}
                      >
                        Complete
                      </Button>
                    </div>
                  )}

                  {transaction.status === "processing" && (
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => handleProcessTransaction(transaction.id, "completed")}
                    >
                      Complete
                    </Button>
                  )}

                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => {
                      setSelectedTransaction(transaction);
                      setShowDetailsDialog(true);
                    }}
                  >
                    Details
                  </Button>
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* New Transaction Dialog */}
      <Dialog open={showTransactionDialog} onOpenChange={setShowTransactionDialog}>
        <DialogContent className="max-w-2xl max-h-[80vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>New Transaction</DialogTitle>
            <DialogDescription>
              Create a new {transactionForm.transaction_type.replace("_", " ")} transaction
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="text-sm font-medium mb-2 block">Transaction Type</label>
                <Select value={transactionForm.transaction_type} onValueChange={(value) => setTransactionForm({ ...transactionForm, transaction_type: value })}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="cash_in">Cash In</SelectItem>
                    <SelectItem value="cash_out">Cash Out</SelectItem>
                    <SelectItem value="transfer">Transfer</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div>
                <label className="text-sm font-medium mb-2 block">Currency</label>
                <Select value={transactionForm.currency_code} onValueChange={(value) => setTransactionForm({ ...transactionForm, currency_code: value })}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="USD">USD</SelectItem>
                    <SelectItem value="PHP">PHP</SelectItem>
                    <SelectItem value="INR">INR</SelectItem>
                    <SelectItem value="MXN">MXN</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>

            <div className="grid grid-cols-3 gap-4">
              <div>
                <label className="text-sm font-medium mb-2 block">Customer Name</label>
                <Input
                  value={transactionForm.customer_name}
                  onChange={(e) => setTransactionForm({ ...transactionForm, customer_name: e.target.value })}
                  placeholder="Customer name"
                />
              </div>
              <div>
                <label className="text-sm font-medium mb-2 block">Customer Phone</label>
                <Input
                  value={transactionForm.customer_phone}
                  onChange={(e) => setTransactionForm({ ...transactionForm, customer_phone: e.target.value })}
                  placeholder="Phone number"
                />
              </div>
              <div>
                <label className="text-sm font-medium mb-2 block">Customer Email</label>
                <Input
                  type="email"
                  value={transactionForm.customer_email}
                  onChange={(e) => setTransactionForm({ ...transactionForm, customer_email: e.target.value })}
                  placeholder="Email address"
                />
              </div>
            </div>

            <div>
              <label className="text-sm font-medium mb-2 block">Amount *</label>
              <Input
                type="number"
                step="0.01"
                value={transactionForm.amount}
                onChange={(e) => setTransactionForm({ ...transactionForm, amount: e.target.value })}
                placeholder="0.00"
              />
              {transactionForm.amount && parseFloat(transactionForm.amount) > 0 && (
                <div className="mt-2 text-sm text-muted-foreground">
                  Fee: {formatCurrency(calculateFee(parseFloat(transactionForm.amount), transactionForm.transaction_type))} | 
                  Net: {formatCurrency(parseFloat(transactionForm.amount) - calculateFee(parseFloat(transactionForm.amount), transactionForm.transaction_type))}
                </div>
              )}
            </div>

            {(transactionForm.transaction_type === "transfer" || transactionForm.transaction_type === "cash_out") && (
              <>
                <div className="grid grid-cols-3 gap-4">
                  <div>
                    <label className="text-sm font-medium mb-2 block">Target Currency</label>
                    <Select value={transactionForm.target_currency} onValueChange={(value) => setTransactionForm({ ...transactionForm, target_currency: value })}>
                      <SelectTrigger>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="USD">USD</SelectItem>
                        <SelectItem value="PHP">PHP</SelectItem>
                        <SelectItem value="INR">INR</SelectItem>
                        <SelectItem value="MXN">MXN</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                  <div>
                    <label className="text-sm font-medium mb-2 block">Exchange Rate</label>
                    <Input
                      type="number"
                      step="0.0001"
                      value={transactionForm.exchange_rate}
                      onChange={(e) => setTransactionForm({ ...transactionForm, exchange_rate: e.target.value })}
                      placeholder="1.0000"
                    />
                  </div>
                  <div>
                    <label className="text-sm font-medium mb-2 block">Target Amount</label>
                    <Input
                      type="number"
                      step="0.01"
                      value={transactionForm.amount && transactionForm.exchange_rate ? 
                        (parseFloat(transactionForm.amount) * parseFloat(transactionForm.exchange_rate)).toFixed(2) : ""}
                      readOnly
                      className="bg-muted"
                    />
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="text-sm font-medium mb-2 block">Recipient Name</label>
                    <Input
                      value={transactionForm.recipient_name}
                      onChange={(e) => setTransactionForm({ ...transactionForm, recipient_name: e.target.value })}
                      placeholder="Recipient name"
                    />
                  </div>
                  <div>
                    <label className="text-sm font-medium mb-2 block">Recipient Phone</label>
                    <Input
                      value={transactionForm.recipient_phone}
                      onChange={(e) => setTransactionForm({ ...transactionForm, recipient_phone: e.target.value })}
                      placeholder="Recipient phone"
                    />
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="text-sm font-medium mb-2 block">Bank</label>
                    <Input
                      value={transactionForm.recipient_bank}
                      onChange={(e) => setTransactionForm({ ...transactionForm, recipient_bank: e.target.value })}
                      placeholder="Bank name"
                    />
                  </div>
                  <div>
                    <label className="text-sm font-medium mb-2 block">Account Number</label>
                    <Input
                      value={transactionForm.recipient_account}
                      onChange={(e) => setTransactionForm({ ...transactionForm, recipient_account: e.target.value })}
                      placeholder="Account number"
                    />
                  </div>
                </div>
              </>
            )}

            <div>
              <label className="text-sm font-medium mb-2 block">Notes</label>
              <Textarea
                value={transactionForm.notes}
                onChange={(e) => setTransactionForm({ ...transactionForm, notes: e.target.value })}
                placeholder="Transaction notes (optional)"
                rows={3}
              />
            </div>

            <div className="flex gap-2 pt-4">
              <Button onClick={handleCreateTransaction} disabled={loading} className="flex-1">
                {loading ? "Creating..." : "Create Transaction"}
              </Button>
              <Button variant="outline" onClick={() => setShowTransactionDialog(false)}>
                Cancel
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Transaction Details Dialog */}
      <Dialog open={showDetailsDialog} onOpenChange={setShowDetailsDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Transaction Details</DialogTitle>
          </DialogHeader>
          {selectedTransaction && (
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <span className="text-sm text-muted-foreground">Reference Number</span>
                  <p className="font-mono font-semibold">{selectedTransaction.reference_number}</p>
                </div>
                <div>
                  <span className="text-sm text-muted-foreground">Status</span>
                  <Badge className={getStatusColor(selectedTransaction.status)}>
                    {selectedTransaction.status}
                  </Badge>
                </div>
                <div>
                  <span className="text-sm text-muted-foreground">Transaction Type</span>
                  <p className="capitalize">{selectedTransaction.transaction_type.replace("_", " ")}</p>
                </div>
                <div>
                  <span className="text-sm text-muted-foreground">Created</span>
                  <p>{format(new Date(selectedTransaction.created_at), "MMM d, yyyy h:mm a")}</p>
                </div>
                <div>
                  <span className="text-sm text-muted-foreground">Amount</span>
                  <p className="font-semibold">{formatCurrency(selectedTransaction.amount)}</p>
                </div>
                <div>
                  <span className="text-sm text-muted-foreground">Fee</span>
                  <p>{formatCurrency(selectedTransaction.fee_amount)}</p>
                </div>
                <div>
                  <span className="text-sm text-muted-foreground">Net Amount</span>
                  <p className="font-semibold">{formatCurrency(selectedTransaction.net_amount)}</p>
                </div>
                {selectedTransaction.processed_at && (
                  <div>
                    <span className="text-sm text-muted-foreground">Processed</span>
                    <p>{format(new Date(selectedTransaction.processed_at), "MMM d, yyyy h:mm a")}</p>
                  </div>
                )}
              </div>

              {selectedTransaction.customer_name && (
                <div>
                  <span className="text-sm text-muted-foreground">Customer</span>
                  <p>{selectedTransaction.customer_name}</p>
                  {selectedTransaction.customer_phone && <p className="text-sm">{selectedTransaction.customer_phone}</p>}
                  {selectedTransaction.customer_email && <p className="text-sm">{selectedTransaction.customer_email}</p>}
                </div>
              )}

              {selectedTransaction.recipient_name && (
                <div>
                  <span className="text-sm text-muted-foreground">Recipient</span>
                  <p>{selectedTransaction.recipient_name}</p>
                  {selectedTransaction.recipient_phone && <p className="text-sm">{selectedTransaction.recipient_phone}</p>}
                  {selectedTransaction.recipient_bank && <p className="text-sm">{selectedTransaction.recipient_bank}</p>}
                  {selectedTransaction.recipient_account && <p className="text-sm">****{selectedTransaction.recipient_account.slice(-4)}</p>}
                </div>
              )}

              {selectedTransaction.notes && (
                <div>
                  <span className="text-sm text-muted-foreground">Notes</span>
                  <p className="italic">"{selectedTransaction.notes}"</p>
                </div>
              )}

              <div className="flex gap-2 pt-4">
                <Button variant="outline" className="flex-1">
                  <Download className="mr-2 h-4 w-4" />
                  Download Receipt
                </Button>
                {selectedTransaction.status === "pending" && (
                  <Button
                    variant="outline"
                    onClick={() => handleProcessTransaction(selectedTransaction.id, "completed")}
                  >
                    <CheckCircle className="mr-2 h-4 w-4" />
                    Complete
                  </Button>
                )}
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default TransactionProcessor;
