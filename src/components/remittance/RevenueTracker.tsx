import { useState, useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { TrendingUp, DollarSign, Calendar, Download, Filter, BarChart3, PieChart, Activity } from "lucide-react";
import { format, startOfDay, endOfDay, subDays, startOfMonth, endOfMonth } from "date-fns";
import { useCurrency } from "@/contexts/CurrencyContext";
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, BarChart, Bar, PieChart as RechartsPieChart, Cell, Legend } from "recharts";

interface MerchantStore {
  id: string;
  store_name: string;
  business_type: string;
}

interface RevenueData {
  id: string;
  merchant_id: string;
  transaction_id: string;
  revenue_type: string;
  amount: number;
  currency_code: string;
  description: string;
  created_at: string;
}

interface TransactionData {
  id: string;
  merchant_id: string;
  transaction_type: string;
  amount: number;
  fee_amount: number;
  status: string;
  created_at: string;
}

interface RevenueTrackerProps {
  selectedStore: MerchantStore | null;
}

const RevenueTracker: React.FC<RevenueTrackerProps> = ({ selectedStore }) => {
  const { format: formatCurrency } = useCurrency();
  const [revenueData, setRevenueData] = useState<RevenueData[]>([]);
  const [transactionData, setTransactionData] = useState<TransactionData[]>([]);
  const [loading, setLoading] = useState(true);
  const [dateRange, setDateRange] = useState("7days");
  const [revenueType, setRevenueType] = useState("all");

  useEffect(() => {
    if (selectedStore) {
      loadRevenueData();
      loadTransactionData();
    }
  }, [selectedStore, dateRange, revenueType]);

  const loadRevenueData = async () => {
    if (!selectedStore) return;

    try {
      setLoading(true);
      const { startDate, endDate } = getDateRange(dateRange);

      const { data, error } = await (supabase as any)
        .from("remittance_merchant_revenue")
        .select("*")
        .eq("merchant_id", selectedStore.id)
        .gte("created_at", startDate.toISOString())
        .lte("created_at", endDate.toISOString())
        .order("created_at", { ascending: true });

      if (error) throw error;
      setRevenueData((data || []) as RevenueData[]);
    } catch (error) {
      console.error("Error loading revenue data:", error);
    } finally {
      setLoading(false);
    }
  };

  const loadTransactionData = async () => {
    if (!selectedStore) return;

    try {
      const { startDate, endDate } = getDateRange(dateRange);

      const { data, error } = await supabase
        .from("remittance_transactions")
        .select("*")
        .eq("merchant_id", selectedStore.id)
        .eq("status", "completed")
        .gte("created_at", startDate.toISOString())
        .lte("created_at", endDate.toISOString())
        .order("created_at", { ascending: true });

      if (error) throw error;
      setTransactionData(data || []);
    } catch (error) {
      console.error("Error loading transaction data:", error);
    }
  };

  const getDateRange = (range: string) => {
    const now = new Date();
    let startDate: Date;
    let endDate: Date = endOfDay(now);

    switch (range) {
      case "today":
        startDate = startOfDay(now);
        break;
      case "7days":
        startDate = subDays(startOfDay(now), 6);
        break;
      case "30days":
        startDate = subDays(startOfDay(now), 29);
        break;
      case "90days":
        startDate = subDays(startOfDay(now), 89);
        break;
      case "month":
        startDate = startOfMonth(now);
        endDate = endOfMonth(now);
        break;
      default:
        startDate = subDays(startOfDay(now), 6);
    }

    return { startDate, endDate };
  };

  const calculateTotalRevenue = () => {
    const filteredRevenue = revenueData.filter(r => 
      revenueType === "all" || r.revenue_type === revenueType
    );
    return filteredRevenue.reduce((sum, r) => sum + r.amount, 0);
  };

  const calculateTotalTransactions = () => {
    return transactionData.length;
  };

  const calculateTotalVolume = () => {
    return transactionData.reduce((sum, tx) => sum + tx.amount, 0);
  };

  const calculateAverageTransaction = () => {
    if (transactionData.length === 0) return 0;
    return calculateTotalVolume() / transactionData.length;
  };

  const getDailyRevenueData = () => {
    const dailyData: { [key: string]: { date: string; revenue: number; transactions: number } } = {};
    
    // Initialize all dates in range
    const { startDate, endDate } = getDateRange(dateRange);
    const currentDate = new Date(startDate);
    while (currentDate <= endDate) {
      const dateKey = format(currentDate, "MMM dd");
      dailyData[dateKey] = { date: dateKey, revenue: 0, transactions: 0 };
      currentDate.setDate(currentDate.getDate() + 1);
    }

    // Fill with actual data
    revenueData.forEach(r => {
      if (revenueType === "all" || r.revenue_type === revenueType) {
        const dateKey = format(new Date(r.created_at), "MMM dd");
        if (dailyData[dateKey]) {
          dailyData[dateKey].revenue += r.amount;
        }
      }
    });

    transactionData.forEach(tx => {
      const dateKey = format(new Date(tx.created_at), "MMM dd");
      if (dailyData[dateKey]) {
        dailyData[dateKey].transactions += 1;
      }
    });

    return Object.values(dailyData);
  };

  const getTransactionTypeData = () => {
    const typeData: { [key: string]: number } = {};
    
    transactionData.forEach(tx => {
      const type = tx.transaction_type.replace("_", " ");
      typeData[type] = (typeData[type] || 0) + tx.amount;
    });

    return Object.entries(typeData).map(([name, value]) => ({ name, value }));
  };

  const getRevenueTypeData = () => {
    const typeData: { [key: string]: number } = {};
    
    revenueData.forEach(r => {
      const type = r.revenue_type;
      typeData[type] = (typeData[type] || 0) + r.amount;
    });

    const COLORS = ['#0088FE', '#00C49F', '#FFBB28', '#FF8042'];
    return Object.entries(typeData).map(([name, value], index) => ({
      name,
      value,
      color: COLORS[index % COLORS.length]
    }));
  };

  if (!selectedStore) {
    return (
      <div className="text-center py-12">
        <BarChart3 className="mx-auto h-12 w-12 text-muted-foreground mb-4" />
        <h3 className="text-lg font-medium mb-2">No Store Selected</h3>
        <p className="text-muted-foreground">Select a store to view revenue analytics</p>
      </div>
    );
  }

  const dailyData = getDailyRevenueData();
  const transactionTypeData = getTransactionTypeData();
  const revenueTypeData = getRevenueTypeData();

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold">Revenue Analytics</h2>
          <p className="text-muted-foreground">{selectedStore.store_name} - Financial Overview</p>
        </div>
        <div className="flex gap-2">
          <Select value={dateRange} onValueChange={setDateRange}>
            <SelectTrigger className="w-40">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="today">Today</SelectItem>
              <SelectItem value="7days">Last 7 Days</SelectItem>
              <SelectItem value="30days">Last 30 Days</SelectItem>
              <SelectItem value="90days">Last 90 Days</SelectItem>
              <SelectItem value="month">This Month</SelectItem>
            </SelectContent>
          </Select>
          <Select value={revenueType} onValueChange={setRevenueType}>
            <SelectTrigger className="w-40">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All Revenue</SelectItem>
              <SelectItem value="fee">Fee Revenue</SelectItem>
              <SelectItem value="commission">Commission</SelectItem>
              <SelectItem value="bonus">Bonus</SelectItem>
            </SelectContent>
          </Select>
        </div>
      </div>

      {/* Key Metrics */}
      <div className="grid grid-cols-4 gap-4">
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-2">
              <DollarSign className="h-5 w-5 text-green-600" />
              <div>
                <p className="text-sm text-muted-foreground">Total Revenue</p>
                <p className="text-lg font-bold">{formatCurrency(calculateTotalRevenue())}</p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-2">
              <Activity className="h-5 w-5 text-blue-600" />
              <div>
                <p className="text-sm text-muted-foreground">Transactions</p>
                <p className="text-lg font-bold">{calculateTotalTransactions()}</p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-2">
              <TrendingUp className="h-5 w-5 text-purple-600" />
              <div>
                <p className="text-sm text-muted-foreground">Total Volume</p>
                <p className="text-lg font-bold">{formatCurrency(calculateTotalVolume())}</p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-2">
              <BarChart3 className="h-5 w-5 text-orange-600" />
              <div>
                <p className="text-sm text-muted-foreground">Avg Transaction</p>
                <p className="text-lg font-bold">{formatCurrency(calculateAverageTransaction())}</p>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Charts */}
      <Tabs defaultValue="revenue" className="space-y-4">
        <TabsList>
          <TabsTrigger value="revenue">Revenue Trend</TabsTrigger>
          <TabsTrigger value="transactions">Transaction Types</TabsTrigger>
          <TabsTrigger value="sources">Revenue Sources</TabsTrigger>
        </TabsList>

        <TabsContent value="revenue">
          <Card>
            <CardHeader>
              <CardTitle>Revenue Trend</CardTitle>
              <CardDescription>Daily revenue and transaction volume</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="h-80">
                <ResponsiveContainer width="100%" height="100%">
                  <LineChart data={dailyData}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis dataKey="date" />
                    <YAxis />
                    <Tooltip 
                      formatter={(value, name) => [
                        name === "revenue" ? formatCurrency(Number(value)) : value,
                        name === "revenue" ? "Revenue" : "Transactions"
                      ]}
                    />
                    <Legend />
                    <Line 
                      type="monotone" 
                      dataKey="revenue" 
                      stroke="#8884d8" 
                      strokeWidth={2}
                      name="revenue"
                    />
                    <Line 
                      type="monotone" 
                      dataKey="transactions" 
                      stroke="#82ca9d" 
                      strokeWidth={2}
                      name="transactions"
                    />
                  </LineChart>
                </ResponsiveContainer>
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="transactions">
          <Card>
            <CardHeader>
              <CardTitle>Transaction Types</CardTitle>
              <CardDescription>Volume by transaction type</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="h-80">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={transactionTypeData}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis dataKey="name" />
                    <YAxis />
                    <Tooltip formatter={(value) => [formatCurrency(Number(value)), "Volume"]} />
                    <Bar dataKey="value" fill="#8884d8" />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="sources">
          <Card>
            <CardHeader>
              <CardTitle>Revenue Sources</CardTitle>
              <CardDescription>Revenue breakdown by type</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="h-80">
                <ResponsiveContainer width="100%" height="100%">
                  <RechartsPieChart>
                    <Pie
                      data={revenueTypeData}
                      cx="50%"
                      cy="50%"
                      labelLine={false}
                      label={({ name, percent }) => `${name} ${(percent * 100).toFixed(0)}%`}
                      outerRadius={80}
                      fill="#8884d8"
                      dataKey="value"
                    >
                      {revenueTypeData.map((entry, index) => (
                        <Cell key={`cell-${index}`} fill={entry.color} />
                      ))}
                    </Pie>
                    <Tooltip formatter={(value) => [formatCurrency(Number(value)), "Revenue"]} />
                    <Legend />
                  </RechartsPieChart>
                </ResponsiveContainer>
              </div>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>

      {/* Recent Revenue */}
      <Card>
        <CardHeader>
          <CardTitle>Recent Revenue</CardTitle>
          <CardDescription>Latest revenue transactions</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-3">
            {revenueData
              .filter(r => revenueType === "all" || r.revenue_type === revenueType)
              .slice(-10)
              .reverse()
              .map((revenue) => (
                <div key={revenue.id} className="flex items-center justify-between p-3 border rounded-lg">
                  <div className="flex items-center gap-3">
                    <div className="w-8 h-8 rounded-full bg-green-100 flex items-center justify-center">
                      <DollarSign className="h-4 w-4 text-green-600" />
                    </div>
                    <div>
                      <p className="font-medium">{revenue.description}</p>
                      <p className="text-sm text-muted-foreground">
                        {format(new Date(revenue.created_at), "MMM d, yyyy h:mm a")}
                      </p>
                    </div>
                  </div>
                  <div className="text-right">
                    <p className="font-semibold">{formatCurrency(revenue.amount)}</p>
                    <Badge variant="outline" className="capitalize">
                      {revenue.revenue_type}
                    </Badge>
                  </div>
                </div>
              ))}
          </div>
        </CardContent>
      </Card>
    </div>
  );
};

export default RevenueTracker;
