import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import BottomNav from "@/components/BottomNav";
import { Send, ArrowLeftRight, CircleDollarSign, FileText, Wallet, Activity, HelpCircle, Info, Scale, LogOut, Clapperboard, ShieldAlert, FileCheck, Lock, Users, Store, BookOpen, Download, Megaphone, Smartphone, CreditCard, ShieldCheck, Handshake, Monitor, Copy, X, TrendingUp, Pickaxe, Coins, Pointer, UserCheck, History, MessageSquare, Bot } from "lucide-react";
import { toast } from "sonner";
import { clearAllAppSecurityUnlocks } from "@/lib/appSecurity";
import { canAccessRemittanceMerchant, isRemittanceUiEnabled } from "@/lib/remittanceAccess";
import { Dialog, DialogContent } from "@/components/ui/dialog";
import BrandLogo from "@/components/BrandLogo";
import { QRCodeSVG } from "qrcode.react";

type BeforeInstallPromptEvent = Event & {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed"; platform: string }>;
};

const MenuPage = () => {
  const OPENPAY_APK_URL = "https://mega.nz/file/pFsECZjD#Lwdlo7tjgprWpU-N7UzKOy_aolGk5t4pgzHXA4VLm7M";
  const OPENPAY_DESKTOP_EXE_URL = String(import.meta.env.VITE_OPENPAY_DESKTOP_EXE_URL || "").trim();
  const navigate = useNavigate();
  const remittanceUiEnabled = isRemittanceUiEnabled();
  const [installPrompt, setInstallPrompt] = useState<BeforeInstallPromptEvent | null>(null);
  const [canInstall, setCanInstall] = useState(false);
  const [showApkModal, setShowApkModal] = useState(false);
  const [welcomeClaimedAt, setWelcomeClaimedAt] = useState<string | null>(null);
  const [claimingWelcome, setClaimingWelcome] = useState(false);
  const [hasRemittanceAccess, setHasRemittanceAccess] = useState(false);
  const [canOpenAdminDashboard, setCanOpenAdminDashboard] = useState(false);
  const [canOpenMasterTopUp, setCanOpenMasterTopUp] = useState(false);

  useEffect(() => {
    const handler = (event: Event) => {
      event.preventDefault();
      setInstallPrompt(event as BeforeInstallPromptEvent);
      setCanInstall(true);
    };
    window.addEventListener("beforeinstallprompt", handler);
    return () => window.removeEventListener("beforeinstallprompt", handler);
  }, []);

  useEffect(() => {
    const loadWelcomeStatus = async () => {
      const {
        data: { user },
      } = await supabase.auth.getUser();
      if (!user) return;

      const { data: profile } = await supabase
        .from("profiles")
        .select("username")
        .eq("id", user.id)
        .single();
      const normalizedUsername = String(profile?.username || "")
        .trim()
        .toLowerCase()
        .replace(/^@/, "");
      const isWainFoundation = normalizedUsername === "wainfoundation";
      setCanOpenAdminDashboard(normalizedUsername === "openpay" || isWainFoundation);
      setCanOpenMasterTopUp(isWainFoundation);
      if (remittanceUiEnabled) {
        setHasRemittanceAccess(canAccessRemittanceMerchant(user.id, profile?.username || null));
      }

      const { data: wallet } = await supabase
        .from("wallets")
        .select("welcome_bonus_claimed_at")
        .eq("user_id", user.id)
        .single();
      setWelcomeClaimedAt(wallet?.welcome_bonus_claimed_at || null);
    };
    loadWelcomeStatus();
  }, [remittanceUiEnabled]);

  const handleInstall = async () => {
    if (!installPrompt) {
      window.open(OPENPAY_APK_URL, "_blank", "noopener,noreferrer");
      return;
    }
    await installPrompt.prompt();
    const choice = await installPrompt.userChoice;
    setCanInstall(choice.outcome === "accepted" ? false : true);
    if (choice.outcome === "accepted") {
      setInstallPrompt(null);
      return;
    }
    window.open(OPENPAY_APK_URL, "_blank", "noopener,noreferrer");
  };

  const handleDesktopExe = () => {
    if (!OPENPAY_DESKTOP_EXE_URL) {
      toast.message("OpenPay Desktop EXE coming soon");
      return;
    }
    window.open(OPENPAY_DESKTOP_EXE_URL, "_blank", "noopener,noreferrer");
  };

  const handleOpenApkModal = () => {
    setShowApkModal(true);
  };

  const handleDownloadApk = () => {
    window.open(OPENPAY_APK_URL, "_blank", "noopener,noreferrer");
  };

  const handleCopyApkLink = async () => {
    try {
      await navigator.clipboard.writeText(OPENPAY_APK_URL);
      toast.success("APK link copied");
    } catch {
      toast.error("Copy failed");
    }
  };

  const handleCopyMegaKey = async () => {
    const megaKey = "Lwdlo7tjgprWpU-N7UzKOy_aolGk5t4pgzHXA4VLm7M";
    try {
      await navigator.clipboard.writeText(megaKey);
      toast.success("Mega key copied");
    } catch {
      toast.error("Copy failed");
    }
  };

  const handleLogout = async () => {
    clearAllAppSecurityUnlocks();
    await supabase.auth.signOut();
    toast.success("Logged out");
    navigate("/auth");
  };

  const handleClaimWelcome = async () => {
    setClaimingWelcome(true);
    const { data, error } = await supabase.rpc("claim_welcome_bonus");
    setClaimingWelcome(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    const claimed = (data as { claimed?: boolean } | null)?.claimed;
    if (claimed) {
      toast.success("Welcome bonus claimed");
    } else {
      toast.message("Welcome bonus already claimed");
    }

    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;
    const { data: wallet } = await supabase
      .from("wallets")
      .select("welcome_bonus_claimed_at")
      .eq("user_id", user.id)
      .single();
    setWelcomeClaimedAt(wallet?.welcome_bonus_claimed_at || null);
  };

  const sections = [
    {
      title: "Transactions",
      layout: "grid-top",
      items: [
        { icon: Send, label: "Express Send", action: () => navigate("/send") },
        { icon: ArrowLeftRight, label: "Transfer", action: () => navigate("/topup") },
        { icon: ArrowLeftRight, label: "Swap", action: () => navigate("/swap-withdrawal") },
        { icon: CircleDollarSign, label: "Request", action: () => navigate("/request-payment") },
        { icon: FileText, label: "Invoice", action: () => navigate("/send-invoice") },
        { icon: History, label: "Top-Up History", action: () => navigate("/topup-history") },
      ],
    },
    {
      title: "Secure banking",
      layout: "grid-card",
      color: "bg-green-50 dark:bg-green-950/30",
      textColor: "text-green-900 dark:text-green-100",
      items: [
        { icon: Wallet, label: "Wallet", action: () => navigate("/dashboard") },
        { icon: TrendingUp, label: "Analytics", action: () => navigate("/dashboard?section=analytics") },
        { icon: Bot, label: "OpenPay AI", action: () => navigate("/ai") },
        { icon: Users, label: "User profile", action: () => navigate("/profile") },
        { icon: ShieldCheck, label: "Two-Factor Auth", action: () => navigate("/two-factor") },
        { icon: UserCheck, label: "KYC Verification", action: () => navigate("/kyc") },
        { icon: CreditCard, label: "Virtual Card", action: () => navigate("/virtual-card") },
        { icon: ArrowLeftRight, label: "Currency converter", action: () => navigate("/currency-converter") },
        { icon: Pickaxe, label: "Mining", action: () => navigate("/mining") },
        { icon: Coins, label: "Staking", action: () => navigate("/staking") },
      ],
    },
    {
      title: "Merchant services",
      layout: "grid-card",
      color: "bg-blue-50 dark:bg-blue-950/30",
      textColor: "text-blue-900 dark:text-blue-100",
        items: [
          { icon: Store, label: "Merchant Portal", action: () => navigate("/merchant-onboarding") },
          { icon: Store, label: "Product Catalog", action: () => navigate("/merchant-products") },
          { icon: Store, label: "Merchant POS", action: () => navigate("/merchant-pos") },
          { icon: FileText, label: "Payment Link Creator", action: () => navigate("/payment-links/create") },
          { icon: Pointer, label: "Buttons", subtitle: "OpenPay", action: () => navigate("/buttons") },
          ...(remittanceUiEnabled
            ? [{
                icon: Store,
              label: "Remittance Center",
              action: () => {
                if (hasRemittanceAccess) {
                  navigate("/remittance-merchant");
                  return;
                }
                toast.message("Coming soon");
              },
              disabled: !hasRemittanceAccess,
              subtitle: hasRemittanceAccess ? "Developer access enabled" : "Under development",
            }]
          : []),
      ],
    },
    {
      title: "Earning & Rewards",
      layout: "grid-card",
      color: "bg-orange-50 dark:bg-orange-950/30",
      textColor: "text-orange-900 dark:text-orange-100",
      items: [
        { icon: Users, label: "Affiliate", action: () => navigate("/affiliate") },
        { icon: Clapperboard, label: "Pi Ad Network", action: () => navigate("/pi-ads") },
        {
          icon: CircleDollarSign,
          label: welcomeClaimedAt ? "Bonus Claimed" : "Claim $1",
          action: () => handleClaimWelcome(),
          disabled: Boolean(welcomeClaimedAt) || claimingWelcome,
        },
        { icon: Megaphone, label: "Announcements", action: () => navigate("/announcements") },
        { icon: Megaphone, label: "Blog", action: () => window.open("https://www.openpy.space/blog", "_blank", "noopener,noreferrer") },
      ],
    },
    {
      title: "Activity & Records",
      layout: "grid-card",
      color: "bg-gray-50 dark:bg-gray-900/50",
      textColor: "text-gray-900 dark:text-gray-100",
      items: [
        { icon: Activity, label: "Activity", action: () => navigate("/activity") },
        { icon: BookOpen, label: "OpenLedger", action: () => navigate("/ledger") },
        { icon: ShieldAlert, label: "Disputes", action: () => navigate("/disputes") },
        { icon: HelpCircle, label: "Help Center", action: () => navigate("/help-center") },
        { icon: MessageSquare, label: "Telegram Support", action: () => window.open("https://t.me/openpayofficial", "_blank", "noopener,noreferrer") },
        { icon: Megaphone, label: "Announcements", action: () => navigate("/announcements") },
        { icon: Megaphone, label: "Blog", action: () => window.open("https://www.openpy.space/blog", "_blank", "noopener,noreferrer") },
        { icon: Smartphone, label: "Official Page", action: () => navigate("/openpay-official") },
        { icon: Store, label: "Guide", action: () => navigate("/openpay-guide") },
        { icon: Handshake, label: "Open Partner", action: () => navigate("/open-partner") },
      ],
    },
    {
      title: "Utility & Apps",
      layout: "grid-card",
      color: "bg-purple-50 dark:bg-purple-950/30",
      textColor: "text-purple-900 dark:text-purple-100",
      items: [
        { icon: Smartphone, label: "OpenApp Utilities", action: () => navigate("/openapp") },
        { icon: Monitor, label: "Pi Browser", action: () => navigate("/openpay-desktop") },
        { icon: Monitor, label: "Desktop EXE", action: () => handleDesktopExe() },
        { icon: Download, label: "Install APK", action: () => handleOpenApkModal() },
        { icon: Smartphone, label: "Tablet APK", action: () => handleOpenApkModal() },
        { icon: Smartphone, label: "iOS App", action: () => toast.message("Coming soon"), disabled: true },
      ],
    },
    {
      title: "Legal & Docs",
      layout: "grid-card",
      color: "bg-slate-50 dark:bg-slate-900/50",
      textColor: "text-slate-900 dark:text-slate-100",
      items: [
        { icon: BookOpen, label: "Documentation", action: () => navigate("/openpay-documentation") },
        { icon: FileText, label: "OUSD Whitepaper", action: () => navigate("/whitepaper") },
        { icon: FileText, label: "Pi Whitepaper", action: () => navigate("/pi-whitepaper") },
        { icon: FileText, label: "MiCA Whitepaper", action: () => navigate("/pi-mica-whitepaper") },
        { icon: ShieldCheck, label: "Regulatory", action: () => navigate("/regulatory-status") },
        { icon: ShieldCheck, label: "GDPR", action: () => navigate("/gdpr") },
        { icon: Info, label: "About", action: () => navigate("/about-openpay") },
        { icon: FileCheck, label: "Terms", action: () => navigate("/terms") },
        { icon: Lock, label: "Privacy", action: () => navigate("/privacy") },
        { icon: Scale, label: "Legal", action: () => navigate("/legal") },
      ],
    },
    {
      title: "API & Developer",
      layout: "grid-card",
      color: "bg-indigo-50 dark:bg-indigo-950/30",
      textColor: "text-indigo-900 dark:text-indigo-100",
      items: [
        { icon: BookOpen, label: "API Docs", action: () => navigate("/openpay-api-docs") },
        { icon: BookOpen, label: "POS Docs", action: () => navigate("/openpay-pos-docs") },
        { icon: BookOpen, label: "Merchant Docs", action: () => navigate("/openpay-merchant-portal-docs") },
        { icon: BookOpen, label: "Smart Contract API", action: () => navigate("/smart-contract-api") },
        { icon: BookOpen, label: "Developer Dashboard", action: () => navigate("/developer-dashboard") },
      ],
    },
    ...(canOpenAdminDashboard
      ? [{
          title: "Admin Control",
          layout: "grid-card",
          color: "bg-red-50 dark:bg-red-950/30",
          textColor: "text-red-900 dark:text-red-100",
          items: [
            { icon: ShieldCheck, label: "Dashboard", action: () => navigate("/admin-dashboard") },
            { icon: ShieldCheck, label: "KYC Review", action: () => navigate("/admin-kyc-review") },
            { icon: ShieldCheck, label: "Withdrawals", action: () => navigate("/admin-swap-withrawals") },
            { icon: ShieldCheck, label: "Loans", action: () => navigate("/admin-loan-applications") },
            { icon: ShieldCheck, label: "Top Ups", action: () => navigate("/admin-topup-requests") },
            ...(canOpenMasterTopUp
              ? [{ icon: ShieldCheck, label: "Master Top Up", action: () => navigate("/master-topup") }]
              : []),
          ],
        }]
      : []),
  ];

  return (
    <div className="min-h-screen bg-[#0a3fa9] px-4 pt-8 pb-10 text-white">
      <div className="px-4 pt-8">
        <h1 className="text-3xl font-bold text-white mb-8">Services</h1>
        
        {sections.map((section) => (
          <div key={section.title} className="mb-8 animate-in-up">
            {section.layout === "grid-top" ? (
              <div className="flex justify-between items-start gap-2 mb-4 px-1">
                {section.items.map(({ icon: Icon, label, action, disabled }) => (
                  <button
                    key={label}
                    onClick={action}
                    disabled={disabled}
                    className={`flex flex-col items-center gap-2 flex-1 transition ios-active ${
                      disabled ? "opacity-40 cursor-not-allowed" : "hover:scale-105"
                    }`}
                  >
                    <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-[#0a3fa9] shadow-sm border border-[#0a3fa9]/20">
                      <Icon className="h-6 w-6 text-white" />
                    </div>
                    <span className="text-[11px] font-bold text-center leading-tight text-white dark:text-white/70">{label}</span>
                  </button>
                ))}
              </div>
            ) : (
              <div className="ios-glass overflow-hidden rounded-[2.5rem] border border-border/40 dark:border-white/5 shadow-xl shadow-black/5">
                <div className={`px-6 py-4 ${section.color || "bg-secondary/10"}`}>
                  <h2 className={`text-lg font-black tracking-tight ${section.textColor || "text-white"}`}>{section.title}</h2>
                </div>
                <div className="p-4 grid grid-cols-4 gap-y-8 gap-x-2">
                  {section.items.map(({ icon: Icon, label, action, disabled, subtitle }) => (
                    <button
                      key={label}
                      onClick={action}
                      disabled={disabled}
                      className={`flex flex-col items-center gap-2 transition ios-active ${
                        disabled ? "opacity-40 cursor-not-allowed" : "hover:scale-105"
                      }`}
                    >
                      <div className="flex h-14 w-14 items-center justify-center rounded-[1.25rem] bg-[#0a3fa9] shadow-sm border border-[#0a3fa9]/20">
                        <Icon className="h-7 w-7 text-white" />
                      </div>
                      <div className="flex flex-col items-center gap-0.5 px-1">
                        <span className="text-[10px] font-bold text-center leading-tight text-white dark:text-white/40 line-clamp-2">{label}</span>
                        {subtitle && <span className="text-[8px] text-white dark:text-white/60 text-center leading-tight line-clamp-1">{subtitle}</span>}
                      </div>
                    </button>
                  ))}
                </div>
              </div>
            )}
          </div>
        ))}

        <button
          onClick={handleLogout}
          className="mt-4 w-full flex items-center justify-center gap-3 rounded-2xl bg-red-50 py-4 text-red-600 font-bold transition hover:bg-red-100"
        >
          <LogOut className="h-5 w-5" />
          <span>Log Out</span>
        </button>
      </div>

      <BottomNav active="menu" />

      <Dialog open={showApkModal} onOpenChange={setShowApkModal}>
        <DialogContent className="rounded-3xl p-0 sm:max-w-2xl [&>button]:hidden">
          <div className="relative bg-white px-6 py-6 text-foreground">
            <button
              type="button"
              onClick={() => setShowApkModal(false)}
              className="absolute right-4 top-4 rounded-full p-1 text-foreground/70 hover:bg-black/5"
              aria-label="Close APK modal"
            >
              <X className="h-5 w-5" />
            </button>

            <div className="mx-auto flex max-w-md flex-col items-center text-center">
              <BrandLogo className="h-16 w-16 rounded-2xl" />
              <p className="mt-2 text-3xl font-bold">OpenPay</p>
              <p className="mt-6 text-xl text-foreground/85">
                Scan this QR to open OpenPay on your Android phone or tablet, then download and install the APK.
              </p>

              <div className="mt-5 rounded-2xl bg-white p-2">
                <QRCodeSVG
                  value={OPENPAY_APK_URL}
                  size={180}
                  bgColor="#ffffff"
                  fgColor="#000000"
                  includeMargin
                />
              </div>

              <button
                type="button"
                onClick={() => void handleCopyApkLink()}
                className="mt-4 h-12 w-full rounded-xl bg-gray-700 px-4 text-lg font-semibold text-white hover:bg-gray-600"
              >
                <span className="inline-flex items-center gap-2">
                  <Copy className="h-4 w-4 text-white" />
                  Copy download link
                </span>
              </button>

              <button
                type="button"
                onClick={() => void handleCopyMegaKey()}
                className="mt-3 h-12 w-full rounded-xl bg-gray-700 px-4 text-lg font-semibold text-white hover:bg-gray-600"
              >
                <span className="inline-flex items-center gap-2">
                  <Copy className="h-4 w-4 text-white" />
                  If Mega asks key, copy Mega key
                </span>
              </button>

              <button
                type="button"
                onClick={handleDownloadApk}
                className="mt-6 h-12 w-full rounded-xl bg-neutral-200 px-4 text-lg font-semibold hover:bg-neutral-300"
              >
                <span className="inline-flex items-center gap-2">
                  <Download className="h-4 w-4" />
                  Download Android Phone/Tablet APK
                </span>
              </button>

              <p className="mt-4 text-sm text-foreground/80">
                If download is blocked in Pi Browser, copy the link and open it in another browser on phone or tablet.
              </p>
              {canInstall && (
                <button
                  type="button"
                  onClick={() => void handleInstall()}
                  className="mt-3 h-11 w-full rounded-xl border border-neutral-300 px-4 text-base font-semibold hover:bg-neutral-100"
                >
                  Use browser install prompt
                </button>
              )}
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default MenuPage;
