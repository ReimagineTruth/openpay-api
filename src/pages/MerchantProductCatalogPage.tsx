import { useEffect, useMemo, useState } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import { Bell, Code, Copy, ExternalLink, FileText, Link2, Menu, MessageCircle, Plus, QrCode, Share2, ShoppingCart, Store, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { QRCodeCanvas, QRCodeSVG } from "qrcode.react";

import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import SplashScreen from "@/components/SplashScreen";
import { supabase } from "@/integrations/supabase/client";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";

type MerchantProductRow = {
  id: string;
  product_code: string;
  product_name: string;
  product_description: string | null;
  unit_amount: number;
  currency: string;
  is_active: boolean;
  created_at: string;
};

type MerchantProductStats = {
  product_id: string;
  total_sales: number;
  total_revenue: number;
  total_purchases: number;
};

const MerchantProductCatalogPage = () => {
  const navigate = useNavigate();
  const location = useLocation();
  const [loading, setLoading] = useState(true);
  const [products, setProducts] = useState<MerchantProductRow[]>([]);
  const [unreadNotifications, setUnreadNotifications] = useState(0);
  const [statsByProduct, setStatsByProduct] = useState<Record<string, MerchantProductStats>>({});
  const [activeProduct, setActiveProduct] = useState<MerchantProductRow | null>(null);
  const [showCreateLinkModal, setShowCreateLinkModal] = useState(false);
  const [showShareModal, setShowShareModal] = useState(false);
  const [deleteProductOpen, setDeleteProductOpen] = useState(false);
  const [deleteProductTarget, setDeleteProductTarget] = useState<MerchantProductRow | null>(null);
  const [mode, setMode] = useState<"sandbox" | "live">("sandbox");
  const [secretKey, setSecretKey] = useState("");
  const [creatingLink, setCreatingLink] = useState(false);
  const [createdUrl, setCreatedUrl] = useState("");
  const [shareTab, setShareTab] = useState<"direct" | "embed" | "qr">("direct");

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) {
        navigate("/sign-in?mode=signin");
        return;
      }

      const { data, error } = await supabase
        .from("merchant_products")
        .select("id, product_code, product_name, product_description, unit_amount, currency, is_active, created_at")
        .eq("merchant_user_id", user.id)
        .order("created_at", { ascending: false });

      if (error) {
        toast.error(error.message || "Failed to load products");
        setProducts([]);
      } else {
        setProducts((data || []) as MerchantProductRow[]);
      }

      const { data: statsRows } = await supabase
        .from("merchant_product_stats")
        .select("product_id, total_sales, total_revenue, total_purchases")
        .eq("merchant_user_id", user.id);
      const { count: unreadCount } = await (supabase as any)
        .from("app_notifications")
        .select("id", { count: "exact", head: true })
        .eq("user_id", user.id)
        .is("read_at", null);
      const mapped: Record<string, MerchantProductStats> = {};
      (statsRows || []).forEach((row) => {
        if (!row?.product_id) return;
        mapped[String(row.product_id)] = {
          product_id: String(row.product_id),
          total_sales: Number(row.total_sales || 0),
          total_revenue: Number(row.total_revenue || 0),
          total_purchases: Number(row.total_purchases || 0),
        };
      });
      setStatsByProduct(mapped);
      setUnreadNotifications(Number(unreadCount || 0));

      setLoading(false);

      const state = location.state as { createLinkFor?: string } | null;
      if (state?.createLinkFor) {
        const target = (data || []).find((row) => String(row.id) === String(state.createLinkFor));
        if (target) {
          setActiveProduct(target as MerchantProductRow);
          setShowCreateLinkModal(true);
        }
        navigate(location.pathname, { replace: true, state: null });
      }
    };

    load();
  }, [location.pathname, location.state, navigate]);

  const productCountLabel = useMemo(() => {
    const count = products.length;
    return `${count} product${count === 1 ? "" : "s"}`;
  }, [products.length]);

  const formatLinkUrl = (token: string) =>
    typeof window === "undefined" ? "" : `${window.location.origin}/payment-link/${encodeURIComponent(token)}`;
  const formatCreatedDate = (raw: string) => {
    try {
      return new Date(raw).toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" });
    } catch {
      return raw;
    }
  };

  const handleCopy = async (value: string, label: string) => {
    if (!value) return;
    try {
      await navigator.clipboard.writeText(value);
      toast.success(`${label} copied`);
    } catch {
      toast.error("Copy failed");
    }
  };

  const confirmDeleteProduct = async () => {
    if (!deleteProductTarget) return;
    const { error } = await supabase.from("merchant_products").delete().eq("id", deleteProductTarget.id);
    if (error) {
      toast.error(error.message || "Failed to delete product");
      return;
    }
    setProducts((current) => current.filter((p) => String(p.id) !== String(deleteProductTarget.id)));
    setStatsByProduct((current) => {
      const next = { ...current };
      delete next[String(deleteProductTarget.id)];
      return next;
    });
    if (activeProduct?.id === deleteProductTarget.id) setActiveProduct(null);
    toast.success("Product deleted");
    setDeleteProductOpen(false);
    setDeleteProductTarget(null);
  };

  const createProductPaymentLink = async (product: MerchantProductRow) => {
    if (!secretKey.trim()) {
      toast.error("Secret key is required");
      return;
    }
    setCreatingLink(true);
    const { data, error } = await (supabase as any).rpc("create_merchant_payment_link", {
      p_secret_key: secretKey.trim(),
      p_mode: mode,
      p_link_type: "products",
      p_title: product.product_name,
      p_description: product.product_description || "",
      p_currency: product.currency.toUpperCase(),
      p_custom_amount: null,
      p_items: [{ product_id: product.id, quantity: 1 }],
      p_collect_customer_name: true,
      p_collect_customer_email: true,
      p_collect_phone: false,
      p_collect_address: false,
      p_after_payment_type: "confirmation",
      p_confirmation_message: "Thanks for your payment.",
      p_redirect_url: null,
      p_call_to_action: "Pay",
      p_expires_in_minutes: null,
    });
    setCreatingLink(false);
    if (error) {
      toast.error(error.message || "Failed to create payment link");
      return;
    }
    const row = Array.isArray(data) ? data[0] : data;
    const token = row?.link_token || "";
    if (!token) {
      toast.error("Payment link token missing");
      return;
    }
    const url = formatLinkUrl(token);
    setCreatedUrl(url);
    setShowCreateLinkModal(false);
    setShowShareModal(true);
  };

  const openCreateModal = (product: MerchantProductRow, preferredTab: "direct" | "embed" | "qr" = "direct") => {
    setActiveProduct(product);
    setShareTab(preferredTab);
    setShowCreateLinkModal(true);
  };

  const shareEmbedCode = createdUrl
    ? `<iframe src="${createdUrl}" width="100%" height="720" frameborder="0" style="border:1px solid #d9e6ff;border-radius:12px;max-width:560px;" allow="payment *"></iframe>`
    : "";

  if (loading) return <SplashScreen message="Loading product catalog..." />;

  return (
    <div className="min-h-screen bg-background">
      <div className="mx-auto w-full max-w-[1120px] px-4 py-4 sm:px-6 sm:py-6">
        <div className="flex items-center justify-between gap-3">
          <button
            type="button"
            className="paypal-surface rounded-full p-2 text-foreground"
            aria-label="Open menu"
            onClick={() => navigate("/menu")}
          >
            <Menu className="h-5 w-5" />
          </button>

          <div className="flex items-center gap-2">
            <ShoppingCart className="h-7 w-7 text-foreground" />
            <p className="text-2xl font-black leading-none tracking-tight text-foreground sm:text-4xl">Product Catalog</p>
          </div>

          <div className="flex items-center gap-2">
            <button
              className="paypal-surface rounded-full p-2 text-foreground"
              aria-label="Open Merchant POS"
              onClick={() => navigate("/merchant-pos")}
            >
              <Store className="h-5 w-5" />
            </button>
            <button
              className="paypal-surface rounded-full p-2 text-foreground"
              aria-label="API docs"
              onClick={() => navigate("/openpay-api-docs")}
            >
              <FileText className="h-5 w-5" />
            </button>
            <button
              className="paypal-surface rounded-full p-2 text-foreground"
              aria-label="Messages"
              onClick={() => navigate("/contacts")}
            >
              <MessageCircle className="h-5 w-5" />
            </button>
            <button
              className="paypal-surface relative rounded-full p-2 text-foreground"
              aria-label="Notifications"
              onClick={() => navigate("/notifications")}
            >
              <Bell className="h-5 w-5" />
              {unreadNotifications > 0 && (
                <span className="absolute right-1 top-1 h-2.5 w-2.5 rounded-full bg-red-500" aria-hidden="true" />
              )}
            </button>
          </div>
        </div>

        <div className="mt-8 flex flex-wrap items-center justify-between gap-3">
          <div>
            <h1 className="text-4xl font-semibold text-foreground">Product catalog</h1>
            <p className="mt-2 text-base text-muted-foreground">{productCountLabel}</p>
          </div>
          <button
            type="button"
            onClick={() => navigate("/merchant-products/create")}
            className="inline-flex h-11 items-center gap-2 rounded-full bg-paypal-blue px-5 text-base font-semibold text-white hover:bg-[#004dc5] sm:h-12 sm:text-lg"
          >
            <Plus className="h-5 w-5" />
            Create
          </button>
        </div>

        <div className="paypal-surface mt-6 overflow-hidden rounded-2xl">
          {products.length === 0 && (
            <p className="px-6 py-8 text-base text-muted-foreground">No products yet.</p>
          )}

          {products.map((product, index) => (
            <div key={product.id || index} className="border-b border-border/70 px-6 py-5 last:border-b-0">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div className="flex items-center gap-3 text-sm">
                  <span className={`rounded px-2 py-1 text-xs font-semibold uppercase tracking-wide ${product.is_active ? "bg-paypal-success/15 text-paypal-success" : "bg-secondary text-muted-foreground"}`}>
                    {product.is_active ? "Active" : "Inactive"}
                  </span>
                  <span className="text-muted-foreground">{formatCreatedDate(product.created_at)}</span>
                </div>
                <div className="flex shrink-0 items-center gap-2">
                  <button
                    type="button"
                    onClick={() => openCreateModal(product, "direct")}
                    className="rounded p-1.5 text-muted-foreground hover:bg-secondary"
                    aria-label="Create payment link"
                  >
                    <Link2 className="h-4 w-4" />
                  </button>
                  <button
                    type="button"
                    onClick={() => openCreateModal(product, "direct")}
                    className="rounded p-1.5 text-muted-foreground hover:bg-secondary"
                    aria-label="Share link"
                  >
                    <Share2 className="h-4 w-4" />
                  </button>
                  <button
                    type="button"
                    onClick={() => openCreateModal(product, "embed")}
                    className="rounded p-1.5 text-muted-foreground hover:bg-secondary"
                    aria-label="Embed button"
                  >
                    <Code className="h-4 w-4" />
                  </button>
                   <button
                     type="button"
                     onClick={() => openCreateModal(product, "qr")}
                     className="rounded p-1.5 text-muted-foreground hover:bg-secondary"
                     aria-label="QR code"
                   >
                     <QrCode className="h-4 w-4" />
                   </button>
                   <button
                     type="button"
                     onClick={() => {
                       setDeleteProductTarget(product);
                       setDeleteProductOpen(true);
                     }}
                     className="rounded p-1.5 text-muted-foreground hover:bg-secondary"
                     aria-label="Delete product"
                   >
                     <Trash2 className="h-4 w-4" />
                   </button>
                 </div>
               </div>

              <p className="mt-3 text-2xl font-semibold text-foreground">{product.product_name}</p>
              <p className="mt-1 text-sm text-muted-foreground">{product.product_code}</p>
              <p className="mt-2 text-sm text-muted-foreground">
                Price: {Number(product.unit_amount || 0).toFixed(2)} {product.currency.toUpperCase()} - Total sales: {statsByProduct[product.id]?.total_sales ?? 0} - Total revenue: {Number(statsByProduct[product.id]?.total_revenue ?? 0).toFixed(2)} - {statsByProduct[product.id]?.total_purchases ?? 0} purchases
              </p>
            </div>
          ))}
        </div>
      </div>

      <Dialog open={showCreateLinkModal} onOpenChange={setShowCreateLinkModal}>
        <DialogContent className="rounded-3xl sm:max-w-lg">
          <DialogTitle className="text-lg font-bold text-foreground">Create checkout link</DialogTitle>
          <DialogDescription className="text-sm text-muted-foreground">
            Generate a shareable checkout link for this product.
          </DialogDescription>
          <div className="mt-3 space-y-3 text-sm">
            <div className="rounded-2xl border border-border bg-secondary/20 p-3">
              <p className="text-xs text-muted-foreground">Product</p>
              <p className="font-semibold text-foreground">{activeProduct?.product_name || "Product"}</p>
              <p className="text-xs text-muted-foreground">
                {Number(activeProduct?.unit_amount || 0).toFixed(2)} {activeProduct?.currency?.toUpperCase() || "USD"}
              </p>
            </div>
            <label className="block text-xs text-muted-foreground">
              Mode
              <select
                value={mode}
                onChange={(e) => setMode(e.target.value as "sandbox" | "live")}
                className="mt-1 h-11 w-full rounded-xl border border-border bg-white px-3 text-sm text-foreground"
              >
                <option value="sandbox">sandbox</option>
                <option value="live">live</option>
              </select>
            </label>
            <label className="block text-xs text-muted-foreground">
              Secret key
              <input
                value={secretKey}
                onChange={(e) => setSecretKey(e.target.value)}
                placeholder={`osk_${mode}_...`}
                className="mt-1 h-11 w-full rounded-xl border border-border px-3 text-sm text-foreground"
              />
            </label>
          </div>
          <div className="mt-4 flex gap-2">
            <Button
              className="flex-1 h-11 rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5]"
              onClick={() => activeProduct && createProductPaymentLink(activeProduct)}
              disabled={!activeProduct || creatingLink}
            >
              {creatingLink ? "Creating..." : "Create link"}
            </Button>
            <Button variant="outline" className="h-11 rounded-2xl" onClick={() => setShowCreateLinkModal(false)}>
              Cancel
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={showShareModal} onOpenChange={setShowShareModal}>
        <DialogContent className="rounded-3xl sm:max-w-3xl">
          <DialogTitle className="text-lg font-bold text-foreground">Share checkout link</DialogTitle>
          <DialogDescription className="text-sm text-muted-foreground">
            Use the link, embed, or QR to add this product to your website.
          </DialogDescription>
          <div className="mt-3 flex flex-wrap gap-2 rounded-xl border border-border bg-secondary/30 p-1">
            {(["direct", "embed", "qr"] as const).map((tab) => (
              <button
                key={tab}
                type="button"
                onClick={() => setShareTab(tab)}
                className={`rounded-lg px-3 py-2 text-sm ${shareTab === tab ? "bg-card font-semibold text-foreground shadow-sm" : "text-muted-foreground hover:text-foreground"}`}
              >
                {tab === "direct" ? "Direct link" : tab === "embed" ? "Embed" : "QR code"}
              </button>
            ))}
          </div>

          {shareTab === "direct" && (
            <div className="mt-4 rounded-2xl border border-border p-3">
              <p className="text-sm font-semibold text-foreground">Checkout link</p>
              <div className="mt-2 flex items-center gap-2 rounded-full border border-border bg-secondary/40 px-3 py-2">
                <p className="flex-1 truncate text-sm text-foreground">{createdUrl}</p>
                <Button className="h-9 rounded-full bg-paypal-blue px-4 text-white hover:bg-[#004dc5]" onClick={() => void handleCopy(createdUrl, "Checkout link")}>
                  <Copy className="mr-1 h-4 w-4" />
                  Copy
                </Button>
                <Button variant="outline" className="h-9 rounded-full px-4" onClick={() => window.open(createdUrl, "_blank")}>
                  <ExternalLink className="mr-1 h-4 w-4" />
                  Open
                </Button>
              </div>
            </div>
          )}

          {shareTab === "embed" && (
            <div className="mt-4 rounded-2xl border border-border p-3">
              <p className="text-sm font-semibold text-foreground">Embed code</p>
              <pre className="mt-2 overflow-x-auto rounded-xl bg-slate-950 p-3 text-xs text-slate-100"><code>{shareEmbedCode}</code></pre>
              <Button className="mt-2 h-9 rounded-full bg-paypal-blue px-4 text-white hover:bg-[#004dc5]" onClick={() => void handleCopy(shareEmbedCode, "Embed code")}>
                <Copy className="mr-1 h-4 w-4" />
                Copy code
              </Button>
            </div>
          )}

          {shareTab === "qr" && (
            <div className="mt-4 rounded-2xl border border-border p-3">
              <p className="text-sm font-semibold text-foreground">QR Code</p>
              <p className="mt-1 text-xs text-muted-foreground">Customers can scan to pay instantly.</p>
              <div className="mt-3 flex justify-center rounded-xl bg-card p-4">
                <QRCodeSVG value={createdUrl} size={240} includeMargin level="H" />
              </div>
              <div className="mt-2 hidden">
                <QRCodeCanvas id="product-link-qr-download" value={createdUrl} size={720} includeMargin level="H" />
              </div>
              <div className="mt-3 flex gap-2">
                <Button
                  className="h-9 rounded-full bg-paypal-blue px-4 text-white hover:bg-[#004dc5]"
                  onClick={() => {
                    const sourceCanvas = document.getElementById("product-link-qr-download") as HTMLCanvasElement | null;
                    if (!sourceCanvas) {
                      toast.error("QR image not ready");
                      return;
                    }
                    const dataUrl = sourceCanvas.toDataURL("image/png");
                    const link = document.createElement("a");
                    link.href = dataUrl;
                    link.download = "openpay-product-qr.png";
                    link.click();
                    toast.success("QR download started");
                  }}
                >
                  Download QR
                </Button>
                <Button variant="outline" className="h-9 rounded-full px-4" onClick={() => void handleCopy(createdUrl, "Checkout link")}>
                  Copy link
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>

      <AlertDialog
        open={deleteProductOpen}
        onOpenChange={(open) => {
          setDeleteProductOpen(open);
          if (!open) setDeleteProductTarget(null);
        }}
      >
        <AlertDialogContent className="rounded-3xl">
          <AlertDialogHeader>
            <AlertDialogTitle>Delete product?</AlertDialogTitle>
            <AlertDialogDescription>
              Delete "{deleteProductTarget?.product_name || deleteProductTarget?.product_code || "this product"}"? Existing payments will keep working, but future checkouts cannot use this product.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={confirmDeleteProduct}>Delete</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
};

export default MerchantProductCatalogPage;
