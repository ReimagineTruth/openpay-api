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
import { Store, Plus, Edit, Trash2, Globe, Phone, Mail, MapPin, Clock, FileText, Camera, CheckCircle, XCircle, AlertCircle } from "lucide-react";
import { toast } from "sonner";
import { QRCodeSVG } from "qrcode.react";

interface MerchantStore {
  id: string;
  store_name: string;
  store_description?: string;
  business_type: string;
  license_number?: string;
  license_expiry?: string;
  address: string;
  city: string;
  country: string;
  postal_code?: string;
  phone: string;
  email?: string;
  website?: string;
  logo_url?: string;
  is_active: boolean;
  is_verified: boolean;
  verification_status: string;
  verification_documents?: string[];
  operating_hours?: Record<string, any>;
  created_at: string;
  updated_at: string;
}

interface MerchantFee {
  id: string;
  merchant_id: string;
  transaction_type: string;
  fee_type: string;
  fee_value: number;
  min_fee?: number;
  max_fee?: number;
  currency_code: string;
  is_active: boolean;
}

const businessTypes = [
  { value: "bank", label: "Bank" },
  { value: "money_transfer", label: "Money Transfer Service" },
  { value: "pawnshop", label: "Pawnshop" },
  { value: "convenience_store", label: "Convenience Store" },
  { value: "supermarket", label: "Supermarket" },
  { value: "pharmacy", label: "Pharmacy" },
  { value: "electronics", label: "Electronics Store" },
  { value: "other", label: "Other" },
];

const countries = [
  { code: "US", name: "United States", flag: "🇺🇸" },
  { code: "PH", name: "Philippines", flag: "🇵🇭" },
  { code: "IN", name: "India", flag: "🇮🇳" },
  { code: "MX", name: "Mexico", flag: "🇲🇽" },
  { code: "GB", name: "United Kingdom", flag: "🇬🇧" },
  { code: "CA", name: "Canada", flag: "🇨🇦" },
  { code: "AU", name: "Australia", flag: "🇦🇺" },
  { code: "JP", name: "Japan", flag: "🇯🇵" },
];

interface MerchantStoreManagerProps {
  onStoreSelect?: (store: MerchantStore) => void;
}

const MerchantStoreManager: React.FC<MerchantStoreManagerProps> = ({ onStoreSelect }) => {
  const [stores, setStores] = useState<MerchantStore[]>([]);
  const [fees, setFees] = useState<MerchantFee[]>([]);
  const [loading, setLoading] = useState(true);
  const [showAddStoreDialog, setShowAddStoreDialog] = useState(false);
  const [showFeeDialog, setShowFeeDialog] = useState(false);
  const [selectedStore, setSelectedStore] = useState<MerchantStore | null>(null);
  const [editingStore, setEditingStore] = useState<MerchantStore | null>(null);
  const [editingFee, setEditingFee] = useState<MerchantFee | null>(null);

  // Form states
  const [storeForm, setStoreForm] = useState({
    store_name: "",
    store_description: "",
    business_type: "",
    license_number: "",
    license_expiry: "",
    address: "",
    city: "",
    country: "",
    postal_code: "",
    phone: "",
    email: "",
    website: "",
    operating_hours: {},
  });

  const [feeForm, setFeeForm] = useState({
    transaction_type: "cash_in",
    fee_type: "percentage",
    fee_value: "",
    min_fee: "",
    max_fee: "",
    currency_code: "USD",
  });

  useEffect(() => {
    loadStores();
    loadFees();
  }, []);

  const loadStores = async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;

      const { data, error } = await supabase
        .from("remittance_merchants")
        .select("*")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false });

      if (error) throw error;
      setStores((data || []) as any);
    } catch (error) {
      console.error("Error loading stores:", error);
      toast.error("Failed to load stores");
    } finally {
      setLoading(false);
    }
  };

  const loadFees = async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;

      const { data, error } = await supabase
        .from("remittance_merchant_fees")
        .select("*")
        .in("merchant_id", stores.map(s => s.id))
        .eq("is_active", true);

      if (error) throw error;
      setFees(data || []);
    } catch (error) {
      console.error("Error loading fees:", error);
    }
  };

  const handleSaveStore = async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;

      const storeData = {
        ...storeForm,
        user_id: user.id,
        license_expiry: storeForm.license_expiry || null,
        operating_hours: storeForm.operating_hours || {},
      };

      if (editingStore) {
        const { error } = await supabase
          .from("remittance_merchants")
          .update(storeData)
          .eq("id", editingStore.id);

        if (error) throw error;
        toast.success("Store updated successfully");
      } else {
        const { error } = await supabase
          .from("remittance_merchants")
          .insert(storeData);

        if (error) throw error;
        toast.success("Store created successfully");
      }

      setShowAddStoreDialog(false);
      setEditingStore(null);
      setStoreForm({
        store_name: "",
        store_description: "",
        business_type: "",
        license_number: "",
        license_expiry: "",
        address: "",
        city: "",
        country: "",
        postal_code: "",
        phone: "",
        email: "",
        website: "",
        operating_hours: {},
      });
      loadStores();
    } catch (error) {
      console.error("Error saving store:", error);
      toast.error("Failed to save store");
    }
  };

  const handleSaveFee = async () => {
    try {
      if (!selectedStore) return;

      const feeData = {
        ...feeForm,
        merchant_id: selectedStore.id,
        fee_value: parseFloat(feeForm.fee_value),
        min_fee: feeForm.min_fee ? parseFloat(feeForm.min_fee) : null,
        max_fee: feeForm.max_fee ? parseFloat(feeForm.max_fee) : null,
      };

      if (editingFee) {
        const { error } = await supabase
          .from("remittance_merchant_fees")
          .update(feeData)
          .eq("id", editingFee.id);

        if (error) throw error;
        toast.success("Fee updated successfully");
      } else {
        const { error } = await supabase
          .from("remittance_merchant_fees")
          .insert(feeData);

        if (error) throw error;
        toast.success("Fee created successfully");
      }

      setShowFeeDialog(false);
      setEditingFee(null);
      setFeeForm({
        transaction_type: "cash_in",
        fee_type: "percentage",
        fee_value: "",
        min_fee: "",
        max_fee: "",
        currency_code: "USD",
      });
      loadFees();
    } catch (error) {
      console.error("Error saving fee:", error);
      toast.error("Failed to save fee");
    }
  };

  const handleDeleteStore = async (storeId: string) => {
    try {
      const { error } = await supabase
        .from("remittance_merchants")
        .delete()
        .eq("id", storeId);

      if (error) throw error;
      toast.success("Store deleted successfully");
      loadStores();
    } catch (error) {
      console.error("Error deleting store:", error);
      toast.error("Failed to delete store");
    }
  };

  const handleEditStore = (store: MerchantStore) => {
    setEditingStore(store);
    setStoreForm({
      store_name: store.store_name,
      store_description: store.store_description || "",
      business_type: store.business_type,
      license_number: store.license_number || "",
      license_expiry: store.license_expiry || "",
      address: store.address,
      city: store.city,
      country: store.country,
      postal_code: store.postal_code || "",
      phone: store.phone,
      email: store.email || "",
      website: store.website || "",
      operating_hours: store.operating_hours || {},
    });
    setShowAddStoreDialog(true);
  };

  const handleEditFee = (fee: MerchantFee) => {
    setEditingFee(fee);
    setFeeForm({
      transaction_type: fee.transaction_type,
      fee_type: fee.fee_type,
      fee_value: fee.fee_value.toString(),
      min_fee: fee.min_fee?.toString() || "",
      max_fee: fee.max_fee?.toString() || "",
      currency_code: fee.currency_code,
    });
    setShowFeeDialog(true);
  };

  const getVerificationStatusColor = (status: string) => {
    switch (status) {
      case "verified": return "bg-green-100 text-green-800";
      case "pending": return "bg-yellow-100 text-yellow-800";
      case "rejected": return "bg-red-100 text-red-800";
      default: return "bg-gray-100 text-gray-800";
    }
  };

  const getVerificationStatusIcon = (status: string) => {
    switch (status) {
      case "verified": return <CheckCircle className="h-4 w-4" />;
      case "pending": return <AlertCircle className="h-4 w-4" />;
      case "rejected": return <XCircle className="h-4 w-4" />;
      default: return <AlertCircle className="h-4 w-4" />;
    }
  };

  const generateQRCode = (store: MerchantStore) => {
    const qrData = JSON.stringify({
      type: "remittance_merchant",
      merchant_id: store.id,
      store_name: store.store_name,
      address: store.address,
      phone: store.phone,
      country: store.country,
    });
    return qrData;
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold">Merchant Stores</h2>
          <p className="text-muted-foreground">Manage your remittance stores and fee settings</p>
        </div>
        <Button onClick={() => setShowAddStoreDialog(true)}>
          <Plus className="mr-2 h-4 w-4" />
          Add Store
        </Button>
      </div>

      {/* Stores List */}
      <div className="grid gap-4">
        {stores.map((store) => (
          <Card key={store.id} className="cursor-pointer hover:shadow-md transition-shadow">
            <CardHeader>
              <div className="flex items-start justify-between">
                <div className="flex items-center gap-3">
                  <div className="w-12 h-12 rounded-full bg-paypal-blue/10 flex items-center justify-center">
                    <Store className="h-6 w-6 text-paypal-blue" />
                  </div>
                  <div>
                    <CardTitle className="text-lg">{store.store_name}</CardTitle>
                    <CardDescription>
                      {businessTypes.find(bt => bt.value === store.business_type)?.label}
                    </CardDescription>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <Badge className={getVerificationStatusColor(store.verification_status)}>
                    {getVerificationStatusIcon(store.verification_status)}
                    <span className="ml-1">{store.verification_status}</span>
                  </Badge>
                  <Badge variant={store.is_active ? "default" : "secondary"}>
                    {store.is_active ? "Active" : "Inactive"}
                  </Badge>
                </div>
              </div>
            </CardHeader>
            <CardContent>
              <div className="space-y-3">
                <div className="flex items-center gap-2 text-sm text-muted-foreground">
                  <MapPin className="h-4 w-4" />
                  <span>{store.address}, {store.city}</span>
                  <span>{countries.find(c => c.code === store.country)?.flag}</span>
                </div>
                <div className="flex items-center gap-2 text-sm text-muted-foreground">
                  <Phone className="h-4 w-4" />
                  <span>{store.phone}</span>
                </div>
                {store.email && (
                  <div className="flex items-center gap-2 text-sm text-muted-foreground">
                    <Mail className="h-4 w-4" />
                    <span>{store.email}</span>
                  </div>
                )}
                
                {/* Store Fees */}
                <div className="pt-3 border-t">
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-sm font-medium">Fee Settings</span>
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => {
                        setSelectedStore(store);
                        setShowFeeDialog(true);
                      }}
                    >
                      <Edit className="h-3 w-3" />
                    </Button>
                  </div>
                  <div className="grid grid-cols-3 gap-2 text-xs">
                    {["cash_in", "cash_out", "transfer"].map((type) => {
                      const fee = fees.find(f => f.merchant_id === store.id && f.transaction_type === type);
                      return (
                        <div key={type} className="p-2 bg-muted rounded">
                          <p className="font-medium capitalize">{type.replace("_", " ")}</p>
                          <p className="text-muted-foreground">
                            {fee ? `${fee.fee_type === "percentage" ? fee.fee_value + "%" : "$" + fee.fee_value}` : "Not set"}
                          </p>
                        </div>
                      );
                    })}
                  </div>
                </div>

                {/* Actions */}
                <div className="flex gap-2 pt-3 border-t">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => onStoreSelect?.(store)}
                  >
                    Select Store
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => handleEditStore(store)}
                  >
                    <Edit className="h-3 w-3" />
                  </Button>
                  <Dialog>
                    <DialogTrigger asChild>
                      <Button variant="outline" size="sm">
                        <Globe className="h-3 w-3" />
                      </Button>
                    </DialogTrigger>
                    <DialogContent>
                      <DialogHeader>
                        <DialogTitle>Store QR Code</DialogTitle>
                        <DialogDescription>
                          Scan this QR code to access this store
                        </DialogDescription>
                      </DialogHeader>
                      <div className="flex flex-col items-center space-y-4">
                        <div className="p-4 bg-white rounded-lg">
                          <QRCodeSVG
                            value={generateQRCode(store)}
                            size={200}
                            level="H"
                          />
                        </div>
                        <div className="text-center">
                          <p className="font-medium">{store.store_name}</p>
                          <p className="text-sm text-muted-foreground">{store.address}</p>
                          <p className="text-sm text-muted-foreground">{store.phone}</p>
                        </div>
                      </div>
                    </DialogContent>
                  </Dialog>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => handleDeleteStore(store.id)}
                  >
                    <Trash2 className="h-3 w-3" />
                  </Button>
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Add/Edit Store Dialog */}
      <Dialog open={showAddStoreDialog} onOpenChange={setShowAddStoreDialog}>
        <DialogContent className="max-w-2xl max-h-[80vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{editingStore ? "Edit Store" : "Add New Store"}</DialogTitle>
            <DialogDescription>
              {editingStore ? "Update your store information" : "Add a new remittance store"}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="text-sm font-medium mb-2 block">Store Name *</label>
                <Input
                  value={storeForm.store_name}
                  onChange={(e) => setStoreForm({ ...storeForm, store_name: e.target.value })}
                  placeholder="Enter store name"
                />
              </div>
              <div>
                <label className="text-sm font-medium mb-2 block">Business Type *</label>
                <Select value={storeForm.business_type} onValueChange={(value) => setStoreForm({ ...storeForm, business_type: value })}>
                  <SelectTrigger>
                    <SelectValue placeholder="Select business type" />
                  </SelectTrigger>
                  <SelectContent>
                    {businessTypes.map((type) => (
                      <SelectItem key={type.value} value={type.value}>
                        {type.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>

            <div>
              <label className="text-sm font-medium mb-2 block">Description</label>
              <Textarea
                value={storeForm.store_description}
                onChange={(e) => setStoreForm({ ...storeForm, store_description: e.target.value })}
                placeholder="Describe your store"
                rows={3}
              />
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="text-sm font-medium mb-2 block">License Number</label>
                <Input
                  value={storeForm.license_number}
                  onChange={(e) => setStoreForm({ ...storeForm, license_number: e.target.value })}
                  placeholder="Business license number"
                />
              </div>
              <div>
                <label className="text-sm font-medium mb-2 block">License Expiry</label>
                <Input
                  type="date"
                  value={storeForm.license_expiry}
                  onChange={(e) => setStoreForm({ ...storeForm, license_expiry: e.target.value })}
                />
              </div>
            </div>

            <div>
              <label className="text-sm font-medium mb-2 block">Address *</label>
              <Input
                value={storeForm.address}
                onChange={(e) => setStoreForm({ ...storeForm, address: e.target.value })}
                placeholder="Street address"
              />
            </div>

            <div className="grid grid-cols-3 gap-4">
              <div>
                <label className="text-sm font-medium mb-2 block">City *</label>
                <Input
                  value={storeForm.city}
                  onChange={(e) => setStoreForm({ ...storeForm, city: e.target.value })}
                  placeholder="City"
                />
              </div>
              <div>
                <label className="text-sm font-medium mb-2 block">Country *</label>
                <Select value={storeForm.country} onValueChange={(value) => setStoreForm({ ...storeForm, country: value })}>
                  <SelectTrigger>
                    <SelectValue placeholder="Select country" />
                  </SelectTrigger>
                  <SelectContent>
                    {countries.map((country) => (
                      <SelectItem key={country.code} value={country.code}>
                        <div className="flex items-center gap-2">
                          <span>{country.flag}</span>
                          <span>{country.name}</span>
                        </div>
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div>
                <label className="text-sm font-medium mb-2 block">Postal Code</label>
                <Input
                  value={storeForm.postal_code}
                  onChange={(e) => setStoreForm({ ...storeForm, postal_code: e.target.value })}
                  placeholder="Postal code"
                />
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="text-sm font-medium mb-2 block">Phone *</label>
                <Input
                  value={storeForm.phone}
                  onChange={(e) => setStoreForm({ ...storeForm, phone: e.target.value })}
                  placeholder="Phone number"
                />
              </div>
              <div>
                <label className="text-sm font-medium mb-2 block">Email</label>
                <Input
                  type="email"
                  value={storeForm.email}
                  onChange={(e) => setStoreForm({ ...storeForm, email: e.target.value })}
                  placeholder="Email address"
                />
              </div>
            </div>

            <div>
              <label className="text-sm font-medium mb-2 block">Website</label>
              <Input
                value={storeForm.website}
                onChange={(e) => setStoreForm({ ...storeForm, website: e.target.value })}
                placeholder="https://example.com"
              />
            </div>

            <div className="flex gap-2 pt-4">
              <Button onClick={handleSaveStore} className="flex-1">
                {editingStore ? "Update Store" : "Create Store"}
              </Button>
              <Button variant="outline" onClick={() => setShowAddStoreDialog(false)}>
                Cancel
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Fee Settings Dialog */}
      <Dialog open={showFeeDialog} onOpenChange={setShowFeeDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Fee Settings</DialogTitle>
            <DialogDescription>
              Configure transaction fees for {selectedStore?.store_name}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="text-sm font-medium mb-2 block">Transaction Type</label>
                <Select value={feeForm.transaction_type} onValueChange={(value) => setFeeForm({ ...feeForm, transaction_type: value })}>
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
                <label className="text-sm font-medium mb-2 block">Fee Type</label>
                <Select value={feeForm.fee_type} onValueChange={(value) => setFeeForm({ ...feeForm, fee_type: value })}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="percentage">Percentage</SelectItem>
                    <SelectItem value="fixed">Fixed Amount</SelectItem>
                    <SelectItem value="tiered">Tiered</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>

            <div>
              <label className="text-sm font-medium mb-2 block">
                Fee Value {feeForm.fee_type === "percentage" ? "(%)" : "(Amount)"}
              </label>
              <Input
                type="number"
                step={feeForm.fee_type === "percentage" ? "0.01" : "0.01"}
                value={feeForm.fee_value}
                onChange={(e) => setFeeForm({ ...feeForm, fee_value: e.target.value })}
                placeholder={feeForm.fee_type === "percentage" ? "1.5" : "5.00"}
              />
            </div>

            {feeForm.fee_type === "percentage" && (
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="text-sm font-medium mb-2 block">Minimum Fee</label>
                  <Input
                    type="number"
                    step="0.01"
                    value={feeForm.min_fee}
                    onChange={(e) => setFeeForm({ ...feeForm, min_fee: e.target.value })}
                    placeholder="1.00"
                  />
                </div>
                <div>
                  <label className="text-sm font-medium mb-2 block">Maximum Fee</label>
                  <Input
                    type="number"
                    step="0.01"
                    value={feeForm.max_fee}
                    onChange={(e) => setFeeForm({ ...feeForm, max_fee: e.target.value })}
                    placeholder="100.00"
                  />
                </div>
              </div>
            )}

            <div>
              <label className="text-sm font-medium mb-2 block">Currency</label>
              <Select value={feeForm.currency_code} onValueChange={(value) => setFeeForm({ ...feeForm, currency_code: value })}>
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

            <div className="flex gap-2 pt-4">
              <Button onClick={handleSaveFee} className="flex-1">
                {editingFee ? "Update Fee" : "Create Fee"}
              </Button>
              <Button variant="outline" onClick={() => setShowFeeDialog(false)}>
                Cancel
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default MerchantStoreManager;
