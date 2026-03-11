import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Link, useNavigate, useLocation } from "react-router-dom";
import BottomNav from "@/components/BottomNav";
import { Bell, Check, ChevronDown, ChevronUp, CircleDollarSign, Coins, Copy, CreditCard, Eye, EyeOff, ExternalLink, FileText, HandCoins, PiggyBank, QrCode, RefreshCw, Settings, Store, TrendingUp, Users, Pickaxe, LayoutGrid, ArrowLeftRight } from "lucide-react";
import { format, differenceInSeconds } from "date-fns";
import CurrencySelector from "@/components/CurrencySelector";
import { PI_TO_USD, useCurrency } from "@/contexts/CurrencyContext";
import BrandLogo from "@/components/BrandLogo";
import TransactionReceipt, { type ReceiptData } from "@/components/TransactionReceipt";
import { loadAppSecuritySettings, saveAppSecuritySettings } from "@/lib/appSecurity";
import { toast } from "sonner";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";
import { Button } from "@/components/ui/button";
import { getAppCookie, loadUserPreferences, setAppCookie, upsertUserPreferences } from "@/lib/userPreferences";
import { isRemittanceUiEnabled } from "@/lib/remittanceAccess";
import { isSolanaPayEnabled } from "@/lib/solanaPayAccess";
import { playUiSound } from "@/lib/appSounds";
import { isPlaceholderOpenPayAccount } from "@/lib/openpayIdentity";

interface Transaction {
  id: string;
  sender_id: string;
  receiver_id: string;
  amount: number;
  note: string;
  status: string;
  created_at: string;
  other_name?: string;
  other_username?: string;
  other_avatar_url?: string | null;
  is_sent?: boolean;
  is_topup?: boolean;
  currency_code?: string;
  sender_amount?: number;
  receiver_amount?: number;
  sender_currency_code?: string;
  receiver_currency_code?: string;
}

interface UserAccount {
  account_number: string;
  account_name: string;
  account_username: string;
}

type DashboardSection = "wallet" | "savings" | "credit" | "loans" | "cards" | "buy" | "swap" | "mining" | "analytics";
type MerchantMode = "sandbox" | "live";
type BuyOnrampProvider =
  | "Pi Payment"
  | "Ewallet QR PH"
  | "USDT"
  | "USDC"
  | "Solana Pay"
  | "PayPal"
  | "Apple Pay"
  | "Debit Card"
  | "Credit Card"
  | "Google Pay"
  | "Stripe"
  | "Venmo"
  | "TransFi"
  | "Onramp Money"
  | "Banxa";
type BuyPaymentMethod =
  | "Pi Payment"
  | "Ewallet"
  | "USDT"
  | "USDC"
  | "Solana Pay"
  | "Debit Card"
  | "Credit Card"
  | "Apple Pay"
  | "Google Pay"
  | "PayPal"
  | "Stripe"
  | "Venmo";
const JQRPH_ICON_URL = "https://upload.wikimedia.org/wikipedia/commons/thumb/3/35/QR_Ph_Logo.svg/960px-QR_Ph_Logo.svg.png?20250310160234";
const PI_PAYMENT_ICON_URL = "https://i.ibb.co/jk8XtTPj/pi-network-pi-icons-pi-logo-design-illustration-trendy-and-modern-crypto-currency-pi-symbol-for-logo.png";
const PAYPAL_ICON_URL = "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b5/PayPal.svg/1920px-PayPal.svg.png";
const APPLE_PAY_ICON_URL =
  "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b0/Apple_Pay_logo.svg/1920px-Apple_Pay_logo.svg.png";
const GOOGLE_PAY_ICON_URL =
  "https://upload.wikimedia.org/wikipedia/commons/thumb/f/f2/Google_Pay_Logo.svg/1920px-Google_Pay_Logo.svg.png";
const STRIPE_ICON_URL =
  "https://upload.wikimedia.org/wikipedia/commons/thumb/b/ba/Stripe_Logo%2C_revised_2016.svg/1920px-Stripe_Logo%2C_revised_2016.svg.png";
const VENMO_ICON_URL =
  "https://upload.wikimedia.org/wikipedia/commons/thumb/4/45/Venmo_Logo.svg/1920px-Venmo_Logo.svg.png";
const VISA_ICON_URL = "https://i.ibb.co/G3FGwngR/Visa-Inc-logo-2021-present-svg.png";
const MASTERCARD_ICON_URL = "https://i.ibb.co/9kkZmFDq/Mastercard-2019-logo-svg.png";
const USDT_ICON_URL = "https://cryptologos.cc/logos/tether-usdt-logo.png?v=040";
const USDC_ICON_URL = "https://cryptologos.cc/logos/usd-coin-usdc-logo.png?v=040";
const SOLANA_PAY_ICON_URL = "https://cryptologos.cc/logos/solana-sol-logo.png?v=040";
const TRANSFI_ICON_URL = "https://logo.clearbit.com/transfi.com";
const ONRAMP_MONEY_ICON_URL = "https://logo.clearbit.com/onramp.money";
const BANXA_ICON_URL = "https://logo.clearbit.com/banxa.com";
const E_WALLET_PHP_PER_OUSD = 57;
const PI_TO_OUSD = PI_TO_USD;
const OUSD_TO_PI = 1 / PI_TO_OUSD;

interface SavingsDashboard {
  wallet_balance: number;
  savings_balance: number;
  apy: number;
}

const formatHMS = (seconds: number) => {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  return `${h.toString().padStart(2, "0")}:${m.toString().padStart(2, "0")}:${s
    .toString()
    .padStart(2, "0")}`;
};

interface SavingsTransferActivity {
  id: string;
  direction: "wallet_to_savings" | "savings_to_wallet";
  amount: number;
  note: string;
  created_at: string;
}

interface LoanDashboard {
  id: string;
  principal_amount: number;
  outstanding_amount: number;
  monthly_payment_amount: number;
  monthly_fee_rate: number;
  term_months: number;
  paid_months: number;
  credit_score: number;
  status: string;
  next_due_date: string;
  created_at: string;
}

interface LoanApplication {
  id: string;
  requested_amount: number;
  requested_term_months: number;
  credit_score_snapshot: number;
  full_name: string;
  contact_number: string;
  address_line: string;
  city: string;
  country: string;
  openpay_account_number: string;
  openpay_account_username: string;
  agreement_accepted: boolean;
  status: "pending" | "approved" | "rejected" | "cancelled";
  admin_note: string;
  created_at: string;
  reviewed_at: string | null;
}

interface LoanPaymentHistoryRow {
  id: string;
  loan_id: string;
  amount: number;
  principal_component: number;
  fee_component: number;
  payment_method: "wallet" | "pi";
  payment_reference: string | null;
  note: string;
  created_at: string;
}

interface MerchantActivityEntry {
  activity_id: string;
  activity_type: string;
  amount: number;
  currency: string;
  status: string;
  note: string;
  created_at: string;
  source: string;
}

interface MerchantActivityRpcRow {
  activity_id?: string | null;
  activity_type?: string | null;
  amount?: number | string | null;
  currency?: string | null;
  status?: string | null;
  note?: string | null;
  created_at?: string | null;
  source?: string | null;
}

interface MerchantBalanceSnapshot {
  gross_volume: number;
  refunded_total: number;
  transferred_total: number;
  available_balance: number;
  wallet_balance: number;
  savings_balance: number;
}

const getGreeting = () => {
  const hour = new Date().getHours();
  if (hour < 12) return "Good morning";
  if (hour < 18) return "Good afternoon";
  return "Good evening";
};

const getInitials = (name: string) =>
  (name || "Unknown").split(" ").filter(Boolean).map((n) => n[0]).join("").slice(0, 2).toUpperCase();

const toPreviewText = (value: string, max = 68) => {
  const raw = String(value || "").trim();
  if (!raw) return "";

  const shortenToken = (token: string, keepStart = 10, keepEnd = 6) => {
    if (token.length <= keepStart + keepEnd + 3) return token;
    return `${token.slice(0, keepStart)}...${token.slice(-keepEnd)}`;
  };

  const tokenShortened = raw
    .replace(/\bopsess_[a-zA-Z0-9_-]+\b/g, (m) => shortenToken(m))
    .replace(/\boplink_[a-zA-Z0-9_-]+\b/g, (m) => shortenToken(m))
    .replace(/\bhttps?:\/\/[^\s]+/gi, (m) => shortenToken(m, 22, 10));

  if (tokenShortened.length <= max) return tokenShortened;
  return `${tokenShortened.slice(0, max - 3)}...`;
};

const formatCurrencyValue = (
  amount: number,
  code: string,
  currencies: Array<{ code: string; symbol?: string; rate?: number }>,
  mode: "compact" | "comma",
) => {
  const upper = String(code || "OUSD").toUpperCase();
  const meta = currencies.find((c) => c.code === upper);
  const symbol = meta?.symbol || (upper === "PI" ? "PI " : "$");
  const baseAmount = Number(amount || 0);
  const convertedAmount =
    upper === "OUSD"
      ? baseAmount
      : upper === "PI"
        ? baseAmount / PI_TO_OUSD
        : (() => {
            const target = currencies.find((c) => c.code === upper);
            if (!target || typeof target.rate !== "number") return baseAmount;
            return (baseAmount / PI_TO_OUSD) * target.rate;
          })();
  const abs = Math.abs(convertedAmount);
  const formatted = new Intl.NumberFormat(undefined, {
    notation: mode === "compact" ? "compact" : "standard",
    minimumFractionDigits: mode === "compact" ? 0 : 2,
    maximumFractionDigits: 2,
  }).format(abs);
  return `${symbol}${formatted}`;
};

const convertAmountToOusd = (
  amount: number,
  amountCode: string,
  currencies: Array<{ code: string; rate?: number }>,
) => {
  const upper = String(amountCode || "OUSD").toUpperCase();
  const rawAmount = Number(amount || 0);
  if (upper === "OUSD") return rawAmount;
  if (upper === "PI") return rawAmount * PI_TO_OUSD;
  const rate = currencies.find((c) => c.code === upper)?.rate;
  if (!rate) return rawAmount;
  return (rawAmount / rate) * PI_TO_OUSD;
};

const normalizeAmountInput = (value: string, maxDecimals = 2) => {
  const cleaned = value.replace(/,/g, "").replace(/[^\d.]/g, "");
  const [intPart, decPart] = cleaned.split(".");
  if (decPart === undefined) return intPart;
  return `${intPart}.${decPart.slice(0, maxDecimals)}`;
};

const formatAmountInput = (value: string) => {
  if (!value) return "";
  const [intPart, decPart] = value.split(".");
  const withCommas = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return decPart !== undefined && decPart.length > 0 ? `${withCommas}.${decPart}` : withCommas;
};

const Dashboard = () => {
  const remittanceUiEnabled = isRemittanceUiEnabled();
  const [balance, setBalance] = useState<number>(0);
  const [isInitialLoadDone, setIsInitialLoadDone] = useState(false);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [userName, setUserName] = useState("");
  const [username, setUsername] = useState<string | null>(null);
  const [userId, setUserId] = useState<string>("");
  const [receiptOpen, setReceiptOpen] = useState(false);
  const [receiptData, setReceiptData] = useState<ReceiptData | null>(null);
  const [balanceHidden, setBalanceHidden] = useState(false);
  const [showShortcuts, setShowShortcuts] = useState(() => {
    if (typeof window !== "undefined") {
      const saved = localStorage.getItem("dashboard_shortcuts_visible");
      return saved !== null ? JSON.parse(saved) : true;
    }
    return true;
  });
  const [swapAmount, setSwapAmount] = useState("");
  const parsedSwapAmount = Number(swapAmount);
  const safeSwapAmount = Number.isFinite(parsedSwapAmount) && parsedSwapAmount > 0 ? parsedSwapAmount : 0;
  const swapMeetsMinimum = safeSwapAmount >= 10;
  const swapFeeAmount = safeSwapAmount > 0 ? Number((safeSwapAmount * 0.02).toFixed(2)) : 0;
  const swapPayoutPiAmount = safeSwapAmount > 0 ? (safeSwapAmount - swapFeeAmount) * OUSD_TO_PI : 0;
  const [showOpenAppBanner, setShowOpenAppBanner] = useState(() => {
    if (typeof window !== "undefined") {
      const saved = localStorage.getItem("dashboard_openapp_banner_visible");
      return saved !== null ? JSON.parse(saved) : true;
    }
    return true;
  });
  const [refreshing, setRefreshing] = useState(false);
  const [showAgreement, setShowAgreement] = useState(false);
  const [agreementChecked, setAgreementChecked] = useState(false);
  const [showOnboarding, setShowOnboarding] = useState(false);
  const [showReceiveOptions, setShowReceiveOptions] = useState(false);
  const [showPinModal, setShowPinModal] = useState(false);
  const [pinAction, setPinAction] = useState<(() => Promise<void>) | null>(null);
  const [showBuyOptions, setShowBuyOptions] = useState(false);
  const [onboardingStep, setOnboardingStep] = useState(0);
  const [remittanceFeeIncome, setRemittanceFeeIncome] = useState(0);
  const [remittanceTxCount, setRemittanceTxCount] = useState(0);
  const [remittanceMonthIncome, setRemittanceMonthIncome] = useState(0);
  const [userAccount, setUserAccount] = useState<UserAccount | null>(null);
  const [lastAdRunAt, setLastAdRunAt] = useState(0);
  const [piSdkInitialized, setPiSdkInitialized] = useState(false);
  const [activeSection, setActiveSection] = useState<DashboardSection>("wallet");
  const [savings, setSavings] = useState<SavingsDashboard | null>(null);
  const [savingsTransfers, setSavingsTransfers] = useState<SavingsTransferActivity[]>([]);
  const [creditScore, setCreditScore] = useState(0);
  const [loan, setLoan] = useState<LoanDashboard | null>(null);
  const [loanApplication, setLoanApplication] = useState<LoanApplication | null>(null);
  const [loanPaymentHistory, setLoanPaymentHistory] = useState<LoanPaymentHistoryRow[]>([]);
  const [movingToSavings, setMovingToSavings] = useState(false);
  const [movingToWallet, setMovingToWallet] = useState(false);
  const [requestingLoan, setRequestingLoan] = useState(false);
  const [payingLoan, setPayingLoan] = useState(false);
  const [savingsAmount, setSavingsAmount] = useState("");
  const [withdrawAmount, setWithdrawAmount] = useState("");
  const [loanAmount, setLoanAmount] = useState("");
  const [loanTermMonths, setLoanTermMonths] = useState("6");
  const [loanPaymentAmount, setLoanPaymentAmount] = useState("");
  const [loanPaymentMethod, setLoanPaymentMethod] = useState<"wallet" | "pi">("wallet");
  const [loanPaymentReference, setLoanPaymentReference] = useState("");
  const [loanAgreementAccepted, setLoanAgreementAccepted] = useState(false);
  const [loanApplicantName, setLoanApplicantName] = useState("");
  const [loanContactNumber, setLoanContactNumber] = useState("");
  const [loanAddressLine, setLoanAddressLine] = useState("");
  const [loanCity, setLoanCity] = useState("");
  const [loanCountry, setLoanCountry] = useState("");
  const [walletView, setWalletView] = useState<"personal" | "merchant">("personal");
  const [merchantMode, setMerchantMode] = useState<MerchantMode>("live");
  const [merchantBalances, setMerchantBalances] = useState<Record<MerchantMode, MerchantBalanceSnapshot | null>>({
    sandbox: null,
    live: null,
  });
  const [merchantActivity, setMerchantActivity] = useState<MerchantActivityEntry[]>([]);
  const [miningActive, setMiningActive] = useState(false);
  const [miningTimeLeft, setMiningTimeLeft] = useState<number | null>(null);
  const [miningBalance, setMiningBalance] = useState(0);
  const [activeMiningSession, setActiveMiningSession] = useState<any>(null);

  useEffect(() => {
    if (!activeMiningSession?.expires_at) {
      setMiningActive(false);
      setMiningTimeLeft(null);
      return;
    }
    const update = () => {
      const now = new Date();
      const expiry = new Date(activeMiningSession.expires_at);
      const diff = differenceInSeconds(expiry, now);
      if (diff > 0) {
        setMiningActive(true);
        setMiningTimeLeft(diff);
      } else {
        setMiningActive(false);
        setMiningTimeLeft(0);
      }
    };
    update();
    const id = setInterval(update, 1000);
    return () => clearInterval(id);
  }, [activeMiningSession]);
  const [merchantSavingsAmount, setMerchantSavingsAmount] = useState("");
  const [merchantWithdrawAmount, setMerchantWithdrawAmount] = useState("");
  const [movingMerchantToSavings, setMovingMerchantToSavings] = useState(false);
  const [movingMerchantToWallet, setMovingMerchantToWallet] = useState(false);
  const [showMerchantFeatures, setShowMerchantFeatures] = useState(false);
  const [unreadNotifications, setUnreadNotifications] = useState(0);
  const [pendingRequestCount, setPendingRequestCount] = useState(0);
  const [pendingInvoiceCount, setPendingInvoiceCount] = useState(0);
  const [virtualCardNumber, setVirtualCardNumber] = useState("**** **** **** 4242");
  const [virtualCardActive, setVirtualCardActive] = useState(false);
  const [hideCardPreviewDetails, setHideCardPreviewDetails] = useState(false);
  const [buySpendAmount, setBuySpendAmount] = useState("");
  const buyFiatCurrency = "PI";
  const [buyOnrampProvider, setBuyOnrampProvider] = useState<BuyOnrampProvider>("Pi Payment");
  const [buyPaymentMethod, setBuyPaymentMethod] = useState<BuyPaymentMethod>("Pi Payment");
  const [showOnrampPicker, setShowOnrampPicker] = useState(false);
  const [showPaymentMethodPicker, setShowPaymentMethodPicker] = useState(false);
  const [amountFormat, setAmountFormat] = useState<"compact" | "comma">(() => {
    if (typeof window === "undefined") return "compact";
    const saved = localStorage.getItem("openpay_amount_format");
    return saved === "comma" ? "comma" : "compact";
  });
  
  // Mining state
  
  // Analytics state
  const [personalAnalytics, setPersonalAnalytics] = useState<any>(null);
  const [personalAnalyticsLoading, setPersonalAnalyticsLoading] = useState(false);
  
  const navigate = useNavigate();
  const location = useLocation();
  const { currency, currencies } = useCurrency();
  const currencyLabel = currency.code === "OUSD" ? "OPEN USD" : currency.code;
  const piCurrencyLabel = currency.code === "OUSD" ? "OPEN USD" : `PI ${currency.code}`;
  const cardCurrencyLabel = currency.code === "PI" ? "PI" : currency.code === "OUSD" ? "OPEN USD" : `PI ${currency.code}`;
  const currencyTag = currency.code === "PI" ? "PI" : `${currencyLabel} (Pi rate)`;
  const formatCompactCurrency = (amount: number, codeOverride?: string) =>
    formatCurrencyValue(amount, codeOverride || currency.code, currencies, amountFormat);
  const getPiCodeLabel = (code: string) => {
    const upper = String(code || "").toUpperCase();
    if (upper === "PI") return "PI";
    if (upper === "OUSD") return "OPEN USD";
    return `PI ${upper}`;
  };
  const onboardingSteps = [
    {
      title: "Welcome to OpenPay",
      description: "Use OpenPay as a stable Pi payment experience for daily transfers and business payments.",
    },
    {
      title: "Send Fast and Safely",
      description: "Go to Pay to choose a contact, scan QR, review details, and confirm each transfer.",
    },
    {
      title: "Receive and Request",
      description: "Use Receive and Request Money to collect payments for goods, services, and personal transfers.",
    },
    {
      title: "Grow with Affiliate",
      description: "Invite users from the Affiliate page and claim rewards when your referrals sign up.",
    },
    {
      title: "Where OpenPay Works",
      description: "Open the new OpenPay Guide page to see use cases for restaurants, shops, clothing, and digital services.",
    },
  ];

  const handleProtectedAction = async (action: () => Promise<void>, actionName: string) => {
    const { data: { user } } = await supabase.auth.getUser();
    const settings = user ? loadAppSecuritySettings(user.id) : null;
    
    if (settings?.pinHash) {
      if (
        (actionName === "handleMoveWalletToSavings" && (!Number.isFinite(Number(savingsAmount)) || Number(savingsAmount) <= 0)) ||
        (actionName === "handleMoveSavingsToWallet" && (!Number.isFinite(Number(withdrawAmount)) || Number(withdrawAmount) <= 0)) ||
        (actionName === "handleMoveMerchantToSavings" && (!Number.isFinite(Number(merchantSavingsAmount)) || Number(merchantSavingsAmount) <= 0)) ||
        (actionName === "handleMoveMerchantToWallet" && (!Number.isFinite(Number(merchantWithdrawAmount)) || Number(merchantWithdrawAmount) <= 0))
      ) {
        toast.error("Enter a valid amount");
        return;
      }
      // Pass all necessary state for the action if needed
      const actionData: any = { actionName };
      
      // Add specific data for actions that need it
      if (actionName === "handleMoveWalletToSavings") actionData.savingsAmount = Number(savingsAmount);
      if (actionName === "handleMoveSavingsToWallet") actionData.withdrawAmount = Number(withdrawAmount);
      if (actionName === "handlePayLoan") actionData.loanPaymentAmount = Number(loanPaymentAmount);
      if (actionName === "handleMoveMerchantToSavings") actionData.merchantSavingsAmount = Number(merchantSavingsAmount);
      if (actionName === "handleMoveMerchantToWallet") actionData.merchantWithdrawAmount = Number(merchantWithdrawAmount);

      navigate("/confirm-pin", { 
        state: { 
          returnTo: location.pathname + location.search,
          actionData,
          title: "Confirm your OpenPay PIN"
        } 
      });
    } else {
      await action();
    }
  };

  useEffect(() => {
    localStorage.setItem("dashboard_shortcuts_visible", JSON.stringify(showShortcuts));
  }, [showShortcuts]);

  useEffect(() => {
    localStorage.setItem("dashboard_openapp_banner_visible", JSON.stringify(showOpenAppBanner));
  }, [showOpenAppBanner]);

  useEffect(() => {
    if (typeof window !== "undefined") {
      localStorage.setItem("openpay_amount_format", amountFormat);
    }
  }, [amountFormat]);

  useEffect(() => {
    const checkPinVerification = async () => {
      // Wait until initial balance and data are loaded before processing PIN result
      if (!isInitialLoadDone) return;

      const state = location.state as any;
      if (state?.pinVerified && state?.actionData?.actionName) {
        const actionName = state.actionData.actionName;
        const data = state.actionData;
        
        // Execute the correct action IMMEDIATELY based on the name
        // We pass the data directly to the functions to avoid race conditions with state updates
        if (actionName === "handleMoveWalletToSavings") void handleMoveWalletToSavings(data.savingsAmount);
        else if (actionName === "handleMoveSavingsToWallet") void handleMoveSavingsToWallet(data.withdrawAmount);
        else if (actionName === "handleMoveMerchantToSavings") void handleMoveMerchantToSavings(data.merchantSavingsAmount);
        else if (actionName === "handleMoveMerchantToWallet") void handleMoveMerchantToWallet(data.merchantWithdrawAmount);
        else if (actionName === "handlePayLoan") void handlePayLoan(data.loanPaymentAmount);

        // Also update local state so UI is consistent
        if (data?.savingsAmount) setSavingsAmount(data.savingsAmount);
        if (data?.withdrawAmount) setWithdrawAmount(data.withdrawAmount);
        if (data?.loanPaymentAmount) setLoanPaymentAmount(data.loanPaymentAmount);
        if (data?.merchantSavingsAmount) setMerchantSavingsAmount(data.merchantSavingsAmount);
        if (data?.merchantWithdrawAmount) setMerchantWithdrawAmount(data.merchantWithdrawAmount);

        // Clear location state immediately to prevent re-execution
        navigate(location.pathname + location.search, { replace: true, state: {} });
      }
    };
    checkPinVerification();
  }, [location.state, navigate, location.pathname, location.search, isInitialLoadDone]);

  const loadSavingsAndLoan = useCallback(async () => {
    try {
      // Attempt to accrue daily interest first (best-effort)
      try {
        await (supabase as any).rpc("accrue_my_savings_interest");
      } catch {
        // ignore if RPC not available yet
      }
      const [{ data: savingsData }, { data: loanData }, { data: creditScoreData }, { data: applicationData }, { data: paymentHistoryData }] = await Promise.all([
        (supabase as any).rpc("get_my_savings_dashboard"),
        (supabase as any).rpc("get_my_latest_loan"),
        (supabase as any).rpc("get_my_credit_score"),
        (supabase as any).rpc("get_my_latest_loan_application"),
        (supabase as any).rpc("get_my_loan_payment_history", { p_loan_id: null, p_limit: 24 }),
      ]);

      const savingsRow = Array.isArray(savingsData) ? savingsData[0] : null;
      const loanRow = Array.isArray(loanData) ? loanData[0] : null;

      {
        const s: any = savingsRow || null;
        setSavings(
          s
            ? {
                wallet_balance: Number(s.wallet_balance || 0),
                savings_balance: Number(s.savings_balance || 0),
                apy: Number(s.apy || 0),
              }
            : null,
        );
      }

      {
        const l: any = loanRow || null;
        setLoan(
          l
            ? {
                id: String(l.id),
                principal_amount: Number(l.principal_amount || 0),
                outstanding_amount: Number(l.outstanding_amount || 0),
                monthly_payment_amount: Number(l.monthly_payment_amount || 0),
                monthly_fee_rate: Number(l.monthly_fee_rate || 0),
                term_months: Number(l.term_months || 0),
                paid_months: Number(l.paid_months || 0),
                credit_score: Number(l.credit_score || 0),
                status: String(l.status || "none"),
                next_due_date: String(l.next_due_date || ""),
                created_at: String(l.created_at || ""),
              }
            : null,
        );
      }

      const applicationRow = Array.isArray(applicationData) ? applicationData[0] : applicationData;
      setLoanApplication(
        applicationRow
          ? {
              id: String(applicationRow.id),
              requested_amount: Number(applicationRow.requested_amount || 0),
              requested_term_months: Number(applicationRow.requested_term_months || 0),
              credit_score_snapshot: Number(applicationRow.credit_score_snapshot || 0),
              full_name: String(applicationRow.full_name || ""),
              contact_number: String(applicationRow.contact_number || ""),
              address_line: String(applicationRow.address_line || ""),
              city: String(applicationRow.city || ""),
              country: String(applicationRow.country || ""),
              openpay_account_number: String(applicationRow.openpay_account_number || ""),
              openpay_account_username: String(applicationRow.openpay_account_username || ""),
              agreement_accepted: Boolean(applicationRow.agreement_accepted),
              status: (String(applicationRow.status || "pending") as LoanApplication["status"]),
              admin_note: String(applicationRow.admin_note || ""),
              created_at: String(applicationRow.created_at || ""),
              reviewed_at: applicationRow.reviewed_at ? String(applicationRow.reviewed_at) : null,
            }
          : null,
      );

      const historyRows = Array.isArray(paymentHistoryData) ? paymentHistoryData : [];
      setLoanPaymentHistory(
        historyRows.map((row: any) => ({
          id: String(row.id),
          loan_id: String(row.loan_id),
          amount: Number(row.amount || 0),
          principal_component: Number(row.principal_component || 0),
          fee_component: Number(row.fee_component || 0),
          payment_method: (String(row.payment_method || "wallet") as "wallet" | "pi"),
          payment_reference: row.payment_reference ? String(row.payment_reference) : null,
          note: String(row.note || ""),
          created_at: String(row.created_at || ""),
        })),
      );

      const parsedCreditScore = Number(
        Array.isArray(creditScoreData)
          ? creditScoreData[0]
          : creditScoreData,
      );
      setCreditScore(Number.isFinite(parsedCreditScore) ? parsedCreditScore : 0);
    } catch (error) {
      console.warn("Failed to load savings and loan data", error);
      toast.error("Unable to load savings and loan data");
      setSavings(null);
      setLoan(null);
      setLoanApplication(null);
      setLoanPaymentHistory([]);
      setCreditScore(0);
    }
  }, []);

  const loadMerchantBalances = useCallback(async () => {
    try {
      const [sandboxMerchantRes, liveMerchantRes] = await Promise.all([
        (supabase as any).rpc("get_my_merchant_balance_overview", { p_mode: "sandbox" }),
        (supabase as any).rpc("get_my_merchant_balance_overview", { p_mode: "live" }),
      ]);
      const toMerchantSnapshot = (row: any): MerchantBalanceSnapshot | null => {
        const payload = Array.isArray(row) ? row[0] : row;
        if (!payload) return null;
        return {
          gross_volume: Number(payload.gross_volume || 0),
          refunded_total: Number(payload.refunded_total || 0),
          transferred_total: Number(payload.transferred_total || 0),
          available_balance: Number(payload.available_balance || 0),
          wallet_balance: Number(payload.wallet_balance || 0),
          savings_balance: Number(payload.savings_balance || 0),
        };
      };
      setMerchantBalances({
        sandbox: sandboxMerchantRes.error ? null : toMerchantSnapshot(sandboxMerchantRes.data),
        live: liveMerchantRes.error ? null : toMerchantSnapshot(liveMerchantRes.data),
      });
    } catch (error) {
      console.warn("Failed to load merchant balances", error);
      setMerchantBalances({ sandbox: null, live: null });
    }
  }, []);

  const loadMerchantActivity = useCallback(async (mode: MerchantMode) => {
    const db = supabase as unknown as {
      rpc: (fn: string, args?: Record<string, unknown>) => Promise<{ data: MerchantActivityRpcRow[] | null }>;
    };
    const { data } = await db.rpc("get_my_merchant_activity", { p_mode: mode, p_limit: 10, p_offset: 0 });
    setMerchantActivity(
      (Array.isArray(data) ? data : []).map((row) => ({
        activity_id: String(row.activity_id || ""),
        activity_type: String(row.activity_type || "payment"),
        amount: Number(row.amount || 0),
        currency: String(row.currency || "USD"),
        status: String(row.status || "completed"),
        note: String(row.note || ""),
        created_at: String(row.created_at || ""),
        source: String(row.source || "merchant_portal"),
      })),
    );
  }, []);

  const loadPersonalAnalytics = useCallback(async () => {
    if (!userId) return;
    
    setPersonalAnalyticsLoading(true);
    try {
      console.log("Loading personal analytics data...");
      
      // Temporarily use only basic transactions to avoid errors
      const { data: transactions, error: txError } = await supabase
        .from("transactions")
        .select("*")
        .or(`sender_id.eq.${userId},receiver_id.eq.${userId}`);
      
      if (txError) {
        toast.error(`Failed to load transactions: ${txError.message}`);
        setPersonalAnalytics(null);
        return;
      }

      // Get payment requests
      const { data: paymentRequests, error: prError } = await supabase
        .from("payment_requests")
        .select("*")
        .or(`requester_id.eq.${userId},payer_id.eq.${userId}`);
      
      if (prError) {
        // Quietly fail or toast
      }

      // Get top-up credits
      const { data: piCredits, error: pcError } = await supabase
        .from("pi_payment_credits")
        .select("*")
        .eq("user_id", userId);
      
      if (pcError) {
        // Quietly fail or toast
      }

      // Calculate analytics from the data
      const sentTransactions = transactions?.filter(tx => tx.sender_id === userId) || [];
      const receivedTransactions = transactions?.filter(tx => tx.receiver_id === userId) || [];
      
      const totalSent = sentTransactions.reduce((sum, tx) => sum + (tx.amount || 0), 0);
      const totalReceived = receivedTransactions.reduce((sum, tx) => sum + (tx.amount || 0), 0);
      const netBalance = totalReceived - totalSent;
      
      const paymentRequestsSent = paymentRequests?.filter(pr => pr.requester_id === userId) || [];
      const paymentRequestsReceived = paymentRequests?.filter(pr => pr.payer_id === userId) || [];
      
      const topupCount = piCredits?.length || 0;
      const topupAmount = piCredits?.reduce((sum, pc) => sum + (pc.amount || 0), 0) || 0;

      // Combine all activities for recent activity timeline
      const allActivities = [
        ...(transactions?.map(tx => ({...tx, type: 'transaction', date: new Date(tx.created_at)})) || []),
        ...(paymentRequests?.map(pr => ({...pr, type: 'payment_request', date: new Date(pr.created_at)})) || []),
        ...(piCredits?.map(pc => ({...pc, type: 'topup', date: new Date(pc.created_at)})) || [])
      ];

      const recentActivities = allActivities
        .sort((a, b) => (b?.date?.getTime() || 0) - (a?.date?.getTime() || 0))
        .slice(0, 15);
      
      const personalData = {
        summary: {
          total_sent: totalSent,
          total_received: totalReceived,
          net_balance: netBalance,
          transaction_count: transactions?.length || 0,
          payment_requests_sent: paymentRequestsSent.length,
          payment_requests_received: paymentRequestsReceived.length,
          invoices_sent: 0,
          invoices_received: 0,
          topup_count: topupCount,
          topup_amount: topupAmount,
          swap_count: 0,
          swap_amount: 0,
          virtual_card_count: 0,
          active_virtual_cards: 0,
          checkout_count: 0,
          checkout_amount: 0,
          pos_payment_count: 0,
          pos_amount: 0,
          recent_activity: recentActivities.length
        },
        currency_usage: [{
          currency: 'OUSD',
          count: allActivities.length,
          amount: totalSent + totalReceived + topupAmount,
          percentage: 100
        }],
        recent_transactions: recentActivities,
        detailed_metrics: {
          avg_transaction_value: (transactions?.length || 0) > 0 ? totalSent / (transactions?.length || 1) : 0,
          avg_topup_amount: topupCount > 0 ? topupAmount / topupCount : 0,
          avg_swap_amount: 0,
          most_used_currency: 'OUSD',
          total_activities: allActivities.length
        }
      };
      
      setPersonalAnalytics(personalData);
    } catch (error) {
      toast.error("Failed to load personal analytics data");
      setPersonalAnalytics(null);
    } finally {
      setPersonalAnalyticsLoading(false);
    }
  }, [userId]);

  const loadDashboard = useCallback(async () => {
    setRefreshing(true);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      
      // First sync mining state to ensure consistency with mining page
      try {
        await supabase.rpc("sync_mining_state" as any);
      } catch (syncError) {
        console.warn("Mining state sync failed in dashboard:", syncError);
      }
      if (!user) {
        setRefreshing(false);
        navigate("/signin");
        return;
      }

      const userIdLocal = user.id;
      setUserId(userIdLocal);

      const miningInfoPromise = (async () => {
        try {
          const [{ data: miningRewards }, { data: miningSession }] = await Promise.all([
            (supabase as any)
              .from("mining_rewards")
              .select("amount")
              .eq("user_id", userIdLocal),
            (supabase as any)
              .from("mining_sessions")
              .select("*")
              .eq("user_id", userIdLocal)
              .eq("is_active", true)
              .gt("expires_at", new Date().toISOString())
              .maybeSingle(),
          ]);

          const miningBalance = miningRewards
            ? miningRewards.reduce((sum, r) => sum + Number(r.amount || 0), 0)
            : 0;
          let session: any = miningSession || null;
          if (!session && typeof window !== "undefined") {
            const localSessionStr = localStorage.getItem("mining_session");
            if (localSessionStr) {
              try {
                const localSession = JSON.parse(localSessionStr);
                if (localSession.user_id === userIdLocal && localSession.is_active && new Date(localSession.expires_at) > new Date()) {
                  session = localSession;
                } else {
                  localStorage.removeItem("mining_session");
                }
              } catch {
                localStorage.removeItem("mining_session");
              }
            }
          } else if (session && typeof window !== "undefined") {
            localStorage.setItem("mining_session", JSON.stringify(session));
          }
          return { miningBalance, session };
        } catch (miningErr) {
          console.warn("Mining info load error:", miningErr);
          return { miningBalance: 0, session: null };
        }
      })();

      const [
        unreadRes,
        claimRes,
        profileRes,
        walletRes,
        pendingReqRes,
        pendingInvRes,
        virtualCardRes,
        accountRes,
        savingsTransfersRes,
        txsRes,
      ] = await Promise.all([
        supabase
          .from("app_notifications" as any)
          .select("id", { count: "exact", head: true })
          .eq("user_id", userIdLocal)
          .is("read_at", null),
        (supabase as any).rpc("claim_welcome_bonus"),
        supabase
          .from("profiles")
          .select("full_name, username, referral_code")
          .eq("id", userIdLocal)
          .single(),
        supabase
          .from("wallets")
          .select("balance")
          .eq("user_id", userIdLocal)
          .single(),
        supabase
          .from("payment_requests" as any)
          .select("id", { count: "exact", head: true })
          .eq("payer_id", userIdLocal)
          .eq("status", "pending"),
        supabase
          .from("invoices" as any)
          .select("id", { count: "exact", head: true })
          .eq("recipient_id", userIdLocal)
          .eq("status", "pending"),
        supabase
          .from("virtual_cards")
          .select("card_number, is_active")
          .eq("user_id", userIdLocal)
          .maybeSingle(),
        supabase.rpc("upsert_my_user_account"),
        (supabase as any)
          .from("user_savings_transfers")
          .select("id, direction, amount, note, created_at")
          .eq("user_id", userIdLocal)
          .order("created_at", { ascending: false })
          .limit(10),
        supabase
          .from("transactions")
          .select("*")
          .or(`sender_id.eq.${userIdLocal},receiver_id.eq.${userIdLocal}`)
          .order("created_at", { ascending: false })
          .limit(10),
      ]);

      setUnreadNotifications(Number(unreadRes.count || 0));

      if ((claimRes.data as { claimed?: boolean } | null)?.claimed) {
        toast.success("Welcome bonus claimed: +1 balance");
      }

      const profile = profileRes.data;
      setUserName(profile?.full_name || "");
      setUsername(profile?.username || null);
      const normalizedFullName = String(profile?.full_name || "").trim();
      const normalizedUsername = String(profile?.username || "").trim();
      const hasProfile = Boolean(
        normalizedFullName &&
        normalizedUsername &&
        !normalizedUsername.toLowerCase().startsWith("pi_"),
      );
      const securitySettings = loadAppSecuritySettings(userIdLocal);

      const agreementKey = `openpay_usage_agreement_v1_${userIdLocal}`;
      const onboardingKey = `openpay_onboarding_done_v1_${userIdLocal}`;
      const hideBalanceKey = `openpay_hide_balance_v1_${userIdLocal}`;
      const hasCompletedOnboardingLocally =
        (typeof window !== "undefined" && localStorage.getItem(onboardingKey) === "1") ||
        getAppCookie(onboardingKey) === "1";

      if (profile?.full_name) {
        setLoanApplicantName((current) => current || profile.full_name);
      }
      if (profile?.username) {
        setLoanContactNumber((current) => current || profile.username);
      }
      if (profile?.referral_code) {
        setAppCookie(`openpay_ref_code_${userIdLocal}`, profile.referral_code);
      }

      setBalance(walletRes.data?.balance || 0);

      setPendingRequestCount(Number(pendingReqRes.count || 0));
      setPendingInvoiceCount(Number(pendingInvRes.count || 0));

      const cardNumberRaw = String(virtualCardRes.data?.card_number || "").replace(/\D/g, "");
      if (cardNumberRaw.length >= 4) {
        const grouped = cardNumberRaw.replace(/(\d{4})(?=\d)/g, "$1 ").trim();
        setVirtualCardNumber(grouped);
      } else {
        setVirtualCardNumber("**** **** **** 4242");
      }
      setVirtualCardActive(Boolean(virtualCardRes.data?.is_active));

      const accountData = accountRes.data as unknown as UserAccount;
      setUserAccount(accountData);
      const normalizedAccount = accountData as UserAccount | null;
      if (normalizedAccount?.account_name) {
        setLoanApplicantName((current) => current || normalizedAccount.account_name);
      }
      if (normalizedAccount?.account_username) {
        setLoanContactNumber((current) => current || normalizedAccount.account_username);
      }

      const hasRealAccountIdentity = Boolean(
        normalizedAccount &&
        String(normalizedAccount.account_name || "").trim() &&
        String(normalizedAccount.account_username || "").trim() &&
        !isPlaceholderOpenPayAccount(normalizedAccount.account_name, normalizedAccount.account_username),
      );

      const hasAccountProfileFallback = Boolean(
        hasRealAccountIdentity,
      );

      if (!hasProfile && !hasAccountProfileFallback && !hasCompletedOnboardingLocally) {
        setRefreshing(false);
        navigate("/onboarding", { replace: true });
        return;
      }

      if (!hasProfile && !hasAccountProfileFallback && hasCompletedOnboardingLocally) {
        setRefreshing(false);
        navigate("/onboarding?reset=1", { replace: true });
        return;
      }

      const savingsTransferRows = savingsTransfersRes.data;
      if (Array.isArray(savingsTransferRows)) {
        const recentSavingsTransfers: SavingsTransferActivity[] = savingsTransferRows
          .filter(
            (row: any) =>
              typeof row?.id === "string" &&
              (row?.direction === "wallet_to_savings" || row?.direction === "savings_to_wallet"),
          )
          .map((row: any) => ({
            id: String(row.id),
            direction: row.direction,
            amount: Number(row.amount || 0),
            note: String(row.note || ""),
            created_at: String(row.created_at || ""),
          }));
        setSavingsTransfers(recentSavingsTransfers);
      } else {
        setSavingsTransfers([]);
      }

      const txs = txsRes.data;
      if (Array.isArray(txs) && txs.length > 0) {
        const otherIds = Array.from(new Set(
          txs
            .map((tx) => (tx.sender_id === userIdLocal ? tx.receiver_id : tx.sender_id))
            .filter(Boolean),
        ));
        let profilesById = new Map<string, { full_name?: string; username?: string; avatar_url?: string | null }>();
        if (otherIds.length > 0) {
          const { data: otherProfiles } = await supabase
            .from("profiles")
            .select("id, full_name, username, avatar_url")
            .in("id", otherIds as string[]);
          (otherProfiles || []).forEach((p: any) => profilesById.set(p.id, p));
        }

        const enriched = txs.map((tx: any) => {
          const otherId = tx.sender_id === userIdLocal ? tx.receiver_id : tx.sender_id;
          const p = profilesById.get(otherId);
          return {
            ...tx,
            other_name: p?.full_name || "Unknown",
            other_username: p?.username || null,
            other_avatar_url: p?.avatar_url || null,
            is_sent: tx.sender_id === userIdLocal,
            is_topup: tx.sender_id === userIdLocal && tx.receiver_id === userIdLocal,
          };
        });
        setTransactions(enriched);
      }

      const miningInfo = await miningInfoPromise;
      setMiningBalance(miningInfo.miningBalance);
      setActiveMiningSession(miningInfo.session);

      const refCookie = getAppCookie(`openpay_ref_code_${userIdLocal}`) || getAppCookie("openpay_last_ref");
      let prefs = {
        hide_balance: false,
        usage_agreement_accepted: false,
        onboarding_completed: false,
        onboarding_step: 0,
      };
      try {
        const loadedPrefs = await loadUserPreferences(user.id);
        prefs = {
          hide_balance: loadedPrefs.hide_balance,
          usage_agreement_accepted: loadedPrefs.usage_agreement_accepted,
          onboarding_completed: loadedPrefs.onboarding_completed,
          onboarding_step: loadedPrefs.onboarding_step,
        };
        const mergedSecurity = { ...loadedPrefs.security_settings, ...securitySettings };
        if (JSON.stringify(mergedSecurity) !== JSON.stringify(securitySettings)) {
          saveAppSecuritySettings(userIdLocal, mergedSecurity);
        }
        const remittanceRaw = loadedPrefs.merchant_onboarding_data?.remittance_center;
        const remittance =
          remittanceRaw && typeof remittanceRaw === "object" && !Array.isArray(remittanceRaw)
            ? (remittanceRaw as Record<string, unknown>)
            : {};
        setRemittanceFeeIncome(typeof remittance.totalFeeIncome === "number" ? remittance.totalFeeIncome : 0);
        setRemittanceMonthIncome(typeof remittance.thisMonthFeeIncome === "number" ? remittance.thisMonthFeeIncome : 0);
        setRemittanceTxCount(typeof remittance.totalRemittanceTxCount === "number" ? remittance.totalRemittanceTxCount : 0);
      } catch {
        setRemittanceFeeIncome(0);
        setRemittanceMonthIncome(0);
        setRemittanceTxCount(0);
      }

      const hasAcceptedAgreement =
        prefs.usage_agreement_accepted ||
        (typeof window !== "undefined" &&
          (localStorage.getItem(agreementKey) === "1" || getAppCookie(agreementKey) === "1"));
      const hasFinishedOnboarding =
        prefs.onboarding_completed ||
        (typeof window !== "undefined" &&
          (localStorage.getItem(onboardingKey) === "1" || getAppCookie(onboardingKey) === "1"));
      const hideBalance =
        prefs.hide_balance ||
        (typeof window !== "undefined" &&
          (localStorage.getItem(hideBalanceKey) === "1" || getAppCookie(hideBalanceKey) === "1"));

      if (refCookie && !profile?.referral_code) {
        await upsertUserPreferences(userIdLocal, { reference_code: refCookie }).catch(() => undefined);
      }

      setBalanceHidden(hideBalance);
      {
        const initialStep = Number(prefs.onboarding_step || 0);
        const clamped = Number.isFinite(initialStep) ? Math.min(Math.max(initialStep, 0), onboardingSteps.length - 1) : 0;
        setOnboardingStep(clamped);
      }

      if (!hasAcceptedAgreement) {
        setShowAgreement(true);
        setShowOnboarding(false);
      } else if (!hasFinishedOnboarding) {
        setShowOnboarding(true);
      }
      setIsInitialLoadDone(true);

      void loadSavingsAndLoan();
      void loadMerchantBalances();
    } catch (error) {
      console.error("Dashboard load error:", error);
      // Don't toast here to avoid spamming if user is not logged in
    } finally {
      setRefreshing(false);
    }
  }, [navigate, loadSavingsAndLoan, loadMerchantBalances]);

  useEffect(() => {
    void loadDashboard();
  }, [loadDashboard]);

  // Mining countdown timer
  useEffect(() => {
    if (!activeMiningSession || !activeMiningSession.expires_at) {
      setMiningTimeLeft(0);
      return;
    }

    const updateTimer = () => {
      try {
        if (!activeMiningSession?.expires_at) return;
        
        const now = new Date();
        const expiry = new Date(activeMiningSession.expires_at);
        
        if (isNaN(expiry.getTime())) {
          setMiningTimeLeft(0);
          return;
        }

        const diff = Math.floor((expiry.getTime() - now.getTime()) / 1000);
        
        if (diff <= 0) {
          setMiningTimeLeft(0);
          loadDashboard();
        } else {
          setMiningTimeLeft(diff);
        }
      } catch (err) {
        setMiningTimeLeft(0);
      }
    };

    updateTimer();
    const interval = setInterval(updateTimer, 1000);
    return () => clearInterval(interval);
  }, [activeMiningSession, loadDashboard]);

  useEffect(() => {
    if (!userId || walletView !== "merchant") return;
    void loadMerchantActivity(merchantMode);
  }, [userId, walletView, merchantMode, loadMerchantActivity]);

  useEffect(() => {
    if (!userId || activeSection !== "analytics") return;
    void loadPersonalAnalytics();
  }, [userId, activeSection, loadPersonalAnalytics]);

  // Handle URL section parameter
  useEffect(() => {
    const searchParams = new URLSearchParams(location.search);
    const section = searchParams.get('section');
    if (section === 'analytics') {
      setActiveSection('analytics');
    }
  }, [location.search, setActiveSection]);

  useEffect(() => {
    if (!userId) return;

    const refreshUnread = async () => {
      try {
        const { count, error } = await supabase
          .from("app_notifications" as any)
          .select("id", { count: "exact", head: true })
          .eq("user_id", userId)
          .is("read_at", null);
        
        if (error) {
          const typedError = error as { status?: number; code?: string; message?: string };
          if (typedError.status === 404 || typedError.code === "PGRST116") {
            return;
          }
          console.warn("Unread notifications check failed:", typedError.message || "Unknown error");
          return;
        }
        setUnreadNotifications(Number(count || 0));
      } catch (err) {
        // Ignore table missing errors
      }
    };

    const channel = supabase
      .channel(`dashboard-unread-${userId}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "app_notifications",
          filter: `user_id=eq.${userId}`,
        },
        () => {
          void refreshUnread();
        },
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [userId]);

  useEffect(() => {
    const envSandbox = String(import.meta.env.VITE_PI_SANDBOX || "false").toLowerCase() === "true";
    const host = typeof window !== "undefined" ? window.location.hostname : "";
    const sandbox = envSandbox && /(^|\.)sandbox\.minepi\.com$/i.test(host);
    const inPiBrowser =
      typeof navigator !== "undefined" &&
      /pi\s?browser/i.test(navigator.userAgent || "");

    const runPiAdAuto = async () => {
      if (typeof window === "undefined" || typeof document === "undefined" || document.visibilityState !== "visible") return;
      if (!inPiBrowser) return;
      if (!window.Pi?.Ads?.showAd) return;
      if (Date.now() - lastAdRunAt < 5 * 60 * 1000) return;

      try {
        window.Pi.init({ version: "2.0", sandbox });
        setPiSdkInitialized(true);

        if (window.Pi.nativeFeaturesList) {
          const features = await window.Pi.nativeFeaturesList();
          if (!features.includes("ad_network")) return;
        }

        const adResult = await window.Pi.Ads.showAd("rewarded");
        if (adResult.result !== "AD_REWARDED" || !adResult.adId) {
          setLastAdRunAt(Date.now());
          return;
        }

        await supabase.functions.invoke("pi-platform", {
          body: { action: "ad_verify", adId: adResult.adId },
        });
        setLastAdRunAt(Date.now());
      } catch {
        // Silent by design: auto ad trigger should not interrupt dashboard usage.
      }
    };

    const initialTimer = window.setTimeout(() => {
      void runPiAdAuto();
    }, 2500);
    const intervalTimer = window.setInterval(() => {
      void runPiAdAuto();
    }, 5 * 60 * 1000);

    return () => {
      window.clearTimeout(initialTimer);
      window.clearInterval(intervalTimer);
    };
  }, [lastAdRunAt]);

  const handleAcceptAgreement = () => {
    if (!userId || !agreementChecked) return;
    localStorage.setItem(`openpay_usage_agreement_v1_${userId}`, "1");
    setAppCookie(`openpay_usage_agreement_v1_${userId}`, "1");
    upsertUserPreferences(userId, { usage_agreement_accepted: true }).catch(() => undefined);
    setShowAgreement(false);
    if (localStorage.getItem(`openpay_onboarding_done_v1_${userId}`) !== "1") {
      setOnboardingStep(0);
      setShowOnboarding(true);
    }
  };

  const completeOnboarding = () => {
    if (!userId) return;
    localStorage.setItem(`openpay_onboarding_done_v1_${userId}`, "1");
    setAppCookie(`openpay_onboarding_done_v1_${userId}`, "1");
    upsertUserPreferences(userId, { onboarding_completed: true, onboarding_step: onboardingSteps.length - 1 }).catch(() => undefined);
    setShowOnboarding(false);
    setOnboardingStep(0);
  };

  const toggleBalanceHidden = () => {
    if (!userId) return;
    const next = !balanceHidden;
    setBalanceHidden(next);
    localStorage.setItem(`openpay_hide_balance_v1_${userId}`, next ? "1" : "0");
    setAppCookie(`openpay_hide_balance_v1_${userId}`, next ? "1" : "0");
    upsertUserPreferences(userId, { hide_balance: next }).catch(() => undefined);
  };

  const showReceipt = (tx: Transaction) => {
    setReceiptData({
      transactionId: tx.id,
      ledgerTransactionId: tx.id,
      type: tx.is_topup ? "topup" : tx.is_sent ? "send" : "receive",
      amount: tx.amount,
      otherPartyName: tx.other_name,
      otherPartyUsername: tx.other_username || undefined,
      note: tx.note || undefined,
      date: new Date(tx.created_at),
    });
    setReceiptOpen(true);
  };

  const copyAccountNumber = async () => {
    if (!userAccount?.account_number) return;
    try {
      await navigator.clipboard.writeText(userAccount.account_number);
      toast.success("Account number copied");
    } catch {
      toast.error("Unable to copy account number");
    }
  };

  const handleMoveWalletToSavings = async (overrideAmount?: number) => {
    const amount = overrideAmount || Number(savingsAmount);
    if (!Number.isFinite(amount) || amount <= 0) {
      toast.error("Enter a valid amount");
      return;
    }
    setMovingToSavings(true);
    const { error } = await (supabase as any).rpc("transfer_my_wallet_to_savings", {
      p_amount: amount,
      p_note: "Dashboard savings transfer",
    });
    setMovingToSavings(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    setSavingsAmount("");
    toast.success("Moved to savings");
    playUiSound("send");
    await loadDashboard();
  };

  const handleMoveSavingsToWallet = async (overrideAmount?: number) => {
    const amount = overrideAmount || Number(withdrawAmount);
    if (!Number.isFinite(amount) || amount <= 0) {
      toast.error("Enter a valid amount");
      return;
    }
    setMovingToWallet(true);
    const { error } = await (supabase as any).rpc("transfer_my_savings_to_wallet", {
      p_amount: amount,
      p_note: "Dashboard savings withdrawal",
    });
    setMovingToWallet(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    setWithdrawAmount("");
    toast.success("Moved to wallet");
    playUiSound("receive");
    await loadDashboard();
  };

  const handleMoveMerchantToSavings = async (overrideAmount?: number) => {
    const amount = overrideAmount || Number(merchantSavingsAmount);
    if (!Number.isFinite(amount) || amount <= 0) {
      toast.error("Enter a valid amount");
      return;
    }
    setMovingMerchantToSavings(true);
    const { error } = await (supabase as any).rpc("transfer_my_merchant_balance", {
      p_amount: amount,
      p_mode: merchantMode,
      p_destination: "savings",
      p_note: "Dashboard merchant transfer",
    });
    setMovingMerchantToSavings(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    setMerchantSavingsAmount("");
    toast.success("Moved to savings");
    playUiSound("send");
    await loadDashboard();
  };

  const handleMoveMerchantToWallet = async (overrideAmount?: number) => {
    const amount = overrideAmount || Number(merchantWithdrawAmount);
    if (!Number.isFinite(amount) || amount <= 0) {
      toast.error("Enter a valid amount");
      return;
    }
    setMovingMerchantToWallet(true);
    const { error } = await (supabase as any).rpc("transfer_my_merchant_balance", {
      p_amount: amount,
      p_mode: merchantMode,
      p_destination: "wallet",
      p_note: "Dashboard merchant transfer",
    });
    setMovingMerchantToWallet(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    setMerchantWithdrawAmount("");
    toast.success("Moved to wallet");
    playUiSound("receive");
    await loadDashboard();
  };

  const handleRequestLoan = async () => {
    const principal = Number(loanAmount);
    const term = Number(loanTermMonths);
    if (!Number.isFinite(principal) || principal <= 0) {
      toast.error("Enter a valid loan amount");
      return;
    }
    if (!Number.isFinite(term) || term < 1 || term > 60) {
      toast.error("Term must be between 1 and 60 months");
      return;
    }
    if (!loanAgreementAccepted) {
      toast.error("You must accept the loan agreement");
      return;
    }
    if (!loanApplicantName.trim() || !loanContactNumber.trim() || !loanAddressLine.trim() || !loanCity.trim() || !loanCountry.trim()) {
      toast.error("Complete all loan application details");
      return;
    }
    if (!userAccount?.account_number || !userAccount?.account_username) {
      toast.error("OpenPay account details not ready. Refresh and try again.");
      return;
    }
    setRequestingLoan(true);
    const { error } = await (supabase as any).rpc("submit_my_loan_application", {
      p_requested_amount: principal,
      p_requested_term_months: term,
      p_full_name: loanApplicantName.trim(),
      p_contact_number: loanContactNumber.trim(),
      p_address_line: loanAddressLine.trim(),
      p_city: loanCity.trim(),
      p_country: loanCountry.trim(),
      p_openpay_account_number: userAccount.account_number,
      p_openpay_account_username: userAccount.account_username,
      p_agreement_accepted: true,
    });
    setRequestingLoan(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    setLoanAmount("");
    toast.success("Loan application submitted for admin review");
    await loadDashboard();
  };

  const handlePayLoan = async (overrideAmount?: number) => {
    if (!loan?.id || loan.status !== "active") {
      toast.error("No active loan");
      return;
    }
    const payment = overrideAmount || (loanPaymentAmount ? Number(loanPaymentAmount) : null);
    if (payment !== null && (!Number.isFinite(payment) || Number(payment) <= 0)) {
      toast.error("Enter a valid payment amount");
      return;
    }
    if (loanPaymentMethod === "pi" && !loanPaymentReference.trim()) {
      toast.error("Enter Pi payment reference");
      return;
    }
    setPayingLoan(true);
    const { error } = await (supabase as any).rpc("pay_my_loan_monthly_with_method", {
      p_loan_id: loan.id,
      p_amount: payment,
      p_payment_method: loanPaymentMethod,
      p_payment_reference: loanPaymentMethod === "pi" ? loanPaymentReference.trim() : null,
      p_note: loanPaymentMethod === "pi" ? "Dashboard monthly loan payment (PI)" : "Dashboard monthly loan payment (wallet)",
    });
    setPayingLoan(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    setLoanPaymentAmount("");
    setLoanPaymentReference("");
    toast.success("Loan payment completed");
    await loadDashboard();
  };


  const selectedMerchantBalance = merchantBalances[merchantMode];
  const walletCardAmount = walletView === "personal"
    ? balance
    : Number(selectedMerchantBalance?.available_balance ?? 0);
  const [loanView, setLoanView] = useState<"overview" | "form">("overview");
  const availableToBorrow = Math.max(
    0,
    Number((savings?.wallet_balance ?? balance) || 0) + Number((savings?.savings_balance ?? 0) || 0),
  );
  const previewLoanAmount = Math.max(0, Number(loanAmount || 0) || 500);
  const previewTermDays = 30;
  const previewApr = 3.5;
  const previewRepayment = previewLoanAmount * (1 + (previewApr / 100) * (previewTermDays / 365));
  const creditScoreDisplay = loan?.credit_score ?? creditScore;
  const creditProgressPercent = Math.max(0, Math.min(100, (creditScoreDisplay / 900) * 100));
  const creditTopupCount = transactions.filter((tx) => tx.is_topup && tx.status === "completed").length;
  const creditSendCount = transactions.filter((tx) => tx.is_sent && !tx.is_topup && tx.status === "completed").length;
  const creditReceiveCount = transactions.filter((tx) => !tx.is_sent && !tx.is_topup && tx.status === "completed").length;
  const creditCheckoutCount = transactions.filter((tx) => String(tx.note || "").toLowerCase().includes("merchant checkout")).length;
  const creditActivityRows = [
    { key: "topup", label: "Buy activity", count: creditTopupCount, points: 3 },
    { key: "send", label: "Send activity", count: creditSendCount, points: 4 },
    { key: "receive", label: "Receive activity", count: creditReceiveCount, points: 3 },
    { key: "checkout", label: "Checkout activity", count: creditCheckoutCount, points: 4 },
  ];
  const parsedBuySpend = Number(buySpendAmount);
  const safeBuySpend = Number.isFinite(parsedBuySpend) && parsedBuySpend > 0 ? parsedBuySpend : 0;
  const isEwalletBuyFlow = buyPaymentMethod === "Ewallet";
  const isUsdtBuyFlow = buyPaymentMethod === "USDT";
  const isUsdcBuyFlow = buyPaymentMethod === "USDC";
  const isUsdFiatBuyFlow =
    buyPaymentMethod !== "Ewallet" &&
    buyPaymentMethod !== "Pi Payment" &&
    buyPaymentMethod !== "USDT" &&
    buyPaymentMethod !== "USDC";
  const buySpendUnit = isEwalletBuyFlow ? "PHP" : isUsdtBuyFlow ? "USDT" : isUsdcBuyFlow ? "USDC" : isUsdFiatBuyFlow ? "USD" : "PI";
  const buySpendRateText = isEwalletBuyFlow
    ? `${E_WALLET_PHP_PER_OUSD.toFixed(2)} PHP = 1 OPEN USD`
    : isUsdtBuyFlow
      ? "1 USDT = 1 OPEN USD"
      : isUsdcBuyFlow
        ? "1 USDC = 1 OPEN USD"
        : isUsdFiatBuyFlow
          ? "1 USD = 1 OPEN USD"
          : `1 PI = ${PI_TO_OUSD.toFixed(2)} OPEN USD`;
  const buyOpenUsdRateText = isUsdtBuyFlow
    ? "1 USDT = 1 OPEN USD"
    : isUsdcBuyFlow
      ? "1 USDC = 1 OPEN USD"
      : isEwalletBuyFlow
        ? `${E_WALLET_PHP_PER_OUSD.toFixed(2)} PHP = 1 OPEN USD`
        : isUsdFiatBuyFlow
          ? "1 USD = 1 OPEN USD"
          : `1 OPEN USD = ${OUSD_TO_PI.toFixed(5)} PI`;
  const onrampRates: Record<BuyOnrampProvider, number> = {
    "Pi Payment": OUSD_TO_PI,
    "Ewallet QR PH": 1,
    "USDT": 1,
    "USDC": 1,
    "Solana Pay": 1,
    "PayPal": 1,
    "Apple Pay": 1,
    "Debit Card": 1,
    "Credit Card": 1,
    "Google Pay": 1,
    "Stripe": 1,
    "Venmo": 1,
    "TransFi": 1,
    "Onramp Money": 1,
    "Banxa": 1,
  };
  const selectedRate = onrampRates[buyOnrampProvider] ?? 1;
  const solanaPayEnabled = isSolanaPayEnabled();
  const baseOnrampRows: Array<{ key: BuyOnrampProvider; disabled?: boolean; subtitle: string; delta?: string; recommended?: boolean }> = [
    { key: "Pi Payment", subtitle: "Active", recommended: true },
    { key: "Ewallet QR PH", subtitle: "Active" },
    { key: "USDT", subtitle: "Active" },
    { key: "USDC", subtitle: "Active" },
    { key: "Solana Pay", subtitle: "Active" },
    { key: "PayPal", subtitle: "Active" },
    { key: "Apple Pay", subtitle: "Active" },
    { key: "Google Pay", subtitle: "Active" },
    { key: "Debit Card", subtitle: "Active" },
    { key: "Credit Card", subtitle: "Active" },
    { key: "Stripe", subtitle: "Active" },
    { key: "Venmo", subtitle: "Active" },
    { key: "TransFi", subtitle: "Coming Soon", disabled: true },
    { key: "Onramp Money", subtitle: "Coming Soon", disabled: true },
    { key: "Banxa", subtitle: "Coming Soon", disabled: true },
  ];
  const onrampRows =
    solanaPayEnabled ? baseOnrampRows : baseOnrampRows.filter((row) => row.key !== "Solana Pay");
  const basePaymentMethodRows: Array<{ key: BuyPaymentMethod; recommended?: boolean; disabled?: boolean }> = [
    { key: "Pi Payment", recommended: true },
    { key: "Ewallet" },
    { key: "USDT" },
    { key: "USDC" },
    { key: "Solana Pay" },
    { key: "PayPal" },
    { key: "Apple Pay" },
    { key: "Google Pay" },
    { key: "Debit Card" },
    { key: "Credit Card" },
    { key: "Stripe" },
    { key: "Venmo" },
  ];
  const paymentMethodRows =
    solanaPayEnabled ? basePaymentMethodRows : basePaymentMethodRows.filter((row) => row.key !== "Solana Pay");
  const baseSupportedBuyPaymentMethods: BuyPaymentMethod[] = [
    "Pi Payment",
    "Ewallet",
    "USDT",
    "USDC",
    "Solana Pay",
    "PayPal",
    "Apple Pay",
    "Google Pay",
    "Debit Card",
    "Credit Card",
    "Stripe",
    "Venmo",
  ];
  const supportedBuyPaymentMethods =
    solanaPayEnabled
      ? baseSupportedBuyPaymentMethods
      : (baseSupportedBuyPaymentMethods.filter((method) => method !== "Solana Pay") as BuyPaymentMethod[]);
  const getBuyPaymentMethodLabel = (method: BuyPaymentMethod) => {
    if (method === "Ewallet") return "Ewallet QR PH";
    return method;
  };
  const buyOpenUsdAmount =
    safeBuySpend <= 0
      ? 0
      : isEwalletBuyFlow
        ? safeBuySpend / E_WALLET_PHP_PER_OUSD
        : buyPaymentMethod === "Pi Payment"
          ? safeBuySpend * PI_TO_OUSD
          : safeBuySpend;
  const buyOpenUsdDisplay =
    buyOpenUsdAmount > 0
      ? buyOpenUsdAmount.toFixed(isEwalletBuyFlow ? 6 : 2)
      : "0.00";
  const buyOpenUsdMeetsMinimum = buyOpenUsdAmount >= 1;
  const handleBuyOpenUsd = () => {
    if (safeBuySpend <= 0) {
      toast.error("Enter a valid amount");
      return;
    }
    if (!buyOpenUsdMeetsMinimum) {
      toast.error("Minimum buy is 1 OPEN USD");
      return;
    }
    if (!supportedBuyPaymentMethods.includes(buyPaymentMethod)) {
      toast.error("OpenUSD buy currently supports all listed payment methods.");
      return;
    }
    if (buyPaymentMethod === "Ewallet") {
      const phpAmountForTopUp = Math.max(0.01, Number(safeBuySpend.toFixed(2)));
      const openUsdAmountForTopUp = Math.max(0.01, Number((phpAmountForTopUp / E_WALLET_PHP_PER_OUSD).toFixed(6)));
      navigate(`/topup-ewallet-qrph?phpAmount=${phpAmountForTopUp.toFixed(2)}&openUsdAmount=${openUsdAmountForTopUp.toFixed(6)}`);
      return;
    }
    if (buyPaymentMethod !== "Pi Payment") {
      const amountForTopUp = Math.max(0.01, Number(buyOpenUsdAmount.toFixed(2)));
      const methodRouteMap: Record<string, string> = {
        "USDT": "/topup-usdt",
        "USDC": "/topup-usdc",
        "Solana Pay": "/topup-solana-pay",
        "PayPal": "/topup-paypal",
        "Debit Card": "/topup-debit",
        "Credit Card": "/topup-credit",
        "Apple Pay": "/topup-apple-pay",
        "Google Pay": "/topup-google-pay",
        "Stripe": "/topup-stripe",
        "Venmo": "/topup-venmo",
      };
      const route = methodRouteMap[buyPaymentMethod] ?? "/topup-paypal";
      navigate(`${route}?amount=${amountForTopUp.toFixed(2)}`);
      return;
    }
    const amountForTopUp = Math.max(0.01, Number(buyOpenUsdAmount.toFixed(2)));
    navigate(`/topup?amount=${amountForTopUp.toFixed(2)}`);
  };

  const openBuyOptions = () => setShowBuyOptions(true);


  return (
    <div className="min-h-screen overflow-x-hidden bg-background pb-56">
      <div className="flex items-center justify-between px-4 pt-5">
        <div className="flex items-center gap-2">
          <CurrencySelector />
          
          {/* Mining Header Info */}
          <div 
            onClick={() => navigate("/mining")}
            className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-paypal-blue/10 border border-paypal-blue/20 cursor-pointer hover:bg-paypal-blue/15 transition-colors"
          >
            <Pickaxe className={`h-4 w-4 text-paypal-blue ${miningTimeLeft > 0 ? "animate-bounce-slow" : ""}`} />
            <div className="flex flex-col leading-none">
              <span className="text-[10px] font-black text-paypal-blue/60 uppercase">Mining</span>
              <div className="flex items-center gap-1.5">
                <span className="text-sm font-black text-paypal-blue">{miningBalance.toFixed(2)}</span>
                {miningTimeLeft > 0 && (
                  <span className="text-[10px] font-black text-paypal-blue bg-white px-1.5 py-0.5 rounded-md animate-pulse">
                    {Math.floor(miningTimeLeft / 3600)}:
                    {Math.floor((miningTimeLeft % 3600) / 60).toString().padStart(2, '0')}:
                    {(miningTimeLeft % 60).toString().padStart(2, '0')}
                  </span>
                )}
              </div>
            </div>
          </div>
        </div>

        <div className="flex gap-3">
          <button
            onClick={loadDashboard}
            aria-label="Refresh dashboard"
            className="paypal-surface flex h-10 w-10 items-center justify-center rounded-full"
            disabled={refreshing}
          >
            <RefreshCw className={`h-5 w-5 text-foreground ${refreshing ? "animate-spin" : ""}`} />
          </button>
          <button onClick={() => navigate("/notifications")} aria-label="Open notifications" className="paypal-surface relative flex h-10 w-10 items-center justify-center rounded-full">
            <Bell className="h-5 w-5 text-foreground" />
            {unreadNotifications > 0 && (
              <span className="absolute right-0 top-0 min-w-[18px] rounded-full bg-red-500 px-1 text-[10px] font-bold leading-4 text-white">
                {Math.min(unreadNotifications, 99)}
              </span>
            )}
          </button>
          <button onClick={() => navigate("/settings")} aria-label="Open settings" className="paypal-surface flex h-10 w-10 items-center justify-center rounded-full">
            <Settings className="h-5 w-5 text-foreground" />
          </button>
        </div>
      </div>

      {/* OpenApp Banner */}
      <div className="px-4 mt-2">
        <Collapsible 
          open={showOpenAppBanner} 
          onOpenChange={setShowOpenAppBanner}
          className="w-full"
        >
          <div className="flex items-center justify-between mb-2">
            <h2 className="text-sm font-bold text-muted-foreground uppercase tracking-wider">OpenApp Utilities</h2>
            <CollapsibleTrigger asChild>
              <button className="flex h-6 w-6 items-center justify-center rounded-full bg-secondary/50 text-muted-foreground hover:bg-secondary transition-colors">
                {showOpenAppBanner ? (
                  <ChevronUp className="h-4 w-4" />
                ) : (
                  <ChevronDown className="h-4 w-4" />
                )}
              </button>
            </CollapsibleTrigger>
          </div>
          <CollapsibleContent className="data-[state=closed]:animate-accordion-up data-[state=open]:animate-accordion-down overflow-hidden">
            <button 
              onClick={() => navigate("/openapp")} 
              className="w-full paypal-surface rounded-2xl p-4 flex items-center justify-between hover:opacity-90 transition-opacity"
              aria-label="Open OpenApp utilities"
            >
              <div className="flex items-center gap-3">
                <div className="flex h-10 w-10 items-center justify-center rounded-full bg-paypal-blue overflow-hidden">
                  <img 
                    src="https://i.ibb.co/JwH255BZ/photo-2026-02-27-14-47-30.jpg" 
                    alt="OpenApp" 
                    className="h-full w-full object-cover"
                  />
                </div>
                <div className="text-left">
                  <h3 className="font-semibold text-foreground">OpenApp Utilities</h3>
                  <p className="text-base text-muted-foreground">Access OpenApp platform and tools</p>
                </div>
              </div>
              <ExternalLink className="h-5 w-5 text-muted-foreground" />
            </button>
          </CollapsibleContent>
        </Collapsible>
      </div>

      {/* Greeting */}
      <div className="px-4 mt-3">
        <h1 className="text-2xl font-bold text-foreground">
          {activeSection === "cards"
            ? "OpenPay Cards"
            : activeSection === "buy"
              ? "Buy OpenUSD"
              : activeSection === "swap"
                ? "Swap"
                : activeSection === "mining"
                  ? "Mining"
                : activeSection === "analytics"
                  ? "Analytics Dashboard"
                  : `${getGreeting()}, ${userName.split(" ")[0] || "there"}`}
        </h1>
        {activeSection !== "cards" && activeSection !== "buy" && activeSection !== "swap" && activeSection !== "mining" && activeSection !== "analytics" && username && (
          <p className="text-base text-muted-foreground">@{username}</p>
        )}
      </div>

      <div className="mt-4 px-4">
        <div className="paypal-surface overflow-x-auto rounded-2xl p-1 [scrollbar-width:none] [-ms-overflow-style:none] [&::-webkit-scrollbar]:hidden">
          <div className="flex min-w-max gap-1">
            {([
              { key: "wallet", label: "Wallet" },
              { key: "savings", label: "Savings" },
              { key: "credit", label: "Credit" },
              { key: "loans", label: "Loans" },
              { key: "cards", label: "Cards" },
              { key: "buy", label: "Buy" },
              { key: "swap", label: "Swap" },
              { key: "mining", label: "Mining" },
              { key: "analytics", label: "Analytics" },
            ] as Array<{ key: DashboardSection; label: string }>).map((item) => (
              <button
                key={item.key}
                onClick={() => setActiveSection(item.key)}
                className={`rounded-xl px-4 py-2 text-base font-semibold transition ${
                  activeSection === item.key
                    ? "bg-paypal-blue text-white"
                    : "text-foreground hover:bg-secondary/70"
                }`}
              >
                {item.label}
              </button>
            ))}
          </div>
        </div>
        <div className="mt-4 rounded-2xl bg-secondary/30 p-3 border border-secondary/50">
          <div className="space-y-1">
            <p className="text-sm text-muted-foreground">
              Display currency: <span className="font-bold text-paypal-blue">{currencyTag}</span>
            </p>
            <div className="flex flex-wrap gap-x-4 gap-y-1">
              <p className="text-xs text-muted-foreground">
                Rate: <span className="font-semibold text-paypal-blue">1 PI = {PI_TO_OUSD.toFixed(2)} OUSD</span>
              </p>
              <p className="text-xs text-muted-foreground">
                Rate: <span className="font-semibold text-paypal-blue">1 USD = 1 OUSD</span>
              </p>
            </div>
          </div>
        </div>
      </div>

      {activeSection === "savings" && (
        <div className="mx-4 mt-4 space-y-4">
          <div className="rounded-3xl border border-white/30 bg-gradient-to-br from-paypal-blue to-[#0073e6] p-6 shadow-xl shadow-[#004bba]/25">
          <div className="flex items-center justify-between text-white">
            <div className="flex items-center gap-3">
              <div className="flex h-9 w-9 items-center justify-center rounded-full bg-white/20">
                <PiggyBank className="h-5 w-5" />
              </div>
              <div>
                <p className="text-3xl font-bold">{balanceHidden ? "****" : formatCompactCurrency(savings?.savings_balance ?? 0)}</p>
                <p className="text-base text-white/85">Savings balance</p>
              </div>
            </div>
            <button
              type="button"
              onClick={() => setAmountFormat((prev) => (prev === "compact" ? "comma" : "compact"))}
              className="rounded-full bg-white/15 px-3 py-1 text-xs font-semibold text-white hover:bg-white/25"
            >
              {amountFormat === "compact" ? "Compact" : "Comma"}
            </button>
          </div>
            <div className="mt-4 rounded-2xl bg-white p-4 text-paypal-dark">
              <p className="text-sm text-muted-foreground">Wallet balance</p>
              <p className="mt-1 text-base font-semibold">{balanceHidden ? "****" : formatCompactCurrency(savings?.wallet_balance ?? balance)}</p>
            </div>
            <div className="mt-4 rounded-2xl bg-white p-4 text-paypal-dark">
              <p className="text-sm text-muted-foreground">Savings balance</p>
              <p className="mt-1 text-base font-semibold">{balanceHidden ? "****" : formatCompactCurrency(savings?.savings_balance ?? 0)}</p>
            </div>
            <div className="mt-4 rounded-2xl bg-white p-4 text-paypal-dark">
              <p className="text-sm text-muted-foreground">Estimated APY</p>
              <p className="mt-1 text-base font-semibold">{(savings?.apy ?? 0).toFixed(2)}%</p>
            </div>
            <div className="mt-4 flex justify-end">
              <button
                type="button"
                onClick={toggleBalanceHidden}
                aria-label={balanceHidden ? "Show balance" : "Hide balance"}
                className="paypal-surface flex h-9 items-center gap-2 rounded-full px-3 text-base font-semibold text-foreground"
              >
                {balanceHidden ? <Eye className="h-4 w-4" /> : <EyeOff className="h-4 w-4" />}
                {balanceHidden ? "Show balance" : "Hide balance"}
              </button>
            </div>
          </div>

          <div className="paypal-surface rounded-3xl p-4">
            <div className="grid gap-3 sm:grid-cols-2">
              <div className="rounded-2xl border border-border/70 p-3">
                <p className="mb-2 text-sm font-semibold">Move wallet to savings</p>
                <input
                  value={formatAmountInput(savingsAmount)}
                  onChange={(e) => setSavingsAmount(normalizeAmountInput(e.target.value))}
                  type="text"
                  inputMode="decimal"
                  placeholder={`Amount (${currencyLabel})`}
                  className="mb-2 h-10 w-full rounded-xl border border-border px-3"
                />
                <button disabled={movingToSavings} onClick={() => handleProtectedAction(handleMoveWalletToSavings, "handleMoveWalletToSavings")} className="h-10 w-full rounded-xl bg-paypal-blue text-sm font-semibold text-white">
                  {movingToSavings ? "Moving..." : "Move to Savings"}
                </button>
              </div>
              <div className="rounded-2xl border border-border/70 p-3">
                <p className="mb-2 text-sm font-semibold text-foreground">Move savings to wallet</p>
                <input
                  value={formatAmountInput(withdrawAmount)}
                  onChange={(e) => setWithdrawAmount(normalizeAmountInput(e.target.value))}
                  type="text"
                  inputMode="decimal"
                  placeholder={`Amount (${currencyLabel})`}
                  className="mb-2 h-10 w-full rounded-xl border border-border px-3"
                />
                <button disabled={movingToWallet} onClick={() => handleProtectedAction(handleMoveSavingsToWallet, "handleMoveSavingsToWallet")} className="h-10 w-full rounded-xl border border-paypal-blue/40 bg-white text-sm font-semibold text-paypal-blue">
                  {movingToWallet ? "Moving..." : "Move to Wallet"}
                </button>
              </div>
            </div>
            <div className="mt-4 rounded-2xl border border-border/70 p-3">
              <div className="mb-2 flex items-center justify-between">
                <p className="text-sm font-semibold">Recent savings activity</p>
                {savingsTransfers.length > 0 && <p className="text-xs text-muted-foreground">{savingsTransfers.length} latest</p>}
              </div>
              {savingsTransfers.length === 0 ? (
                <p className="py-3 text-sm text-muted-foreground">No savings activity yet.</p>
              ) : (
                <div className="divide-y divide-border/70 rounded-xl border border-border/70">
                  {savingsTransfers.map((entry, index) => {
                    const isWalletToSavings = entry.direction === "wallet_to_savings";
                    const directionLabel = isWalletToSavings ? "Move wallet to savings" : "Move savings to wallet";
                    return (
                      <div key={entry.id || index} className="flex items-start justify-between gap-3 px-3 py-2.5">
                        <div>
                          <p className="text-sm font-medium text-foreground">{directionLabel}</p>
                          <p className="text-xs text-muted-foreground">{entry.created_at ? format(new Date(entry.created_at), "MMM d, yyyy h:mm a") : "-"}</p>
                          {entry.note && <p className="text-xs text-muted-foreground">{entry.note}</p>}
                        </div>
                        <p className={`text-sm font-semibold ${isWalletToSavings ? "text-paypal-success" : "text-paypal-blue"}`}>
                          {balanceHidden ? "****" : `${isWalletToSavings ? "+" : "-"}${formatCompactCurrency(entry.amount)}`}
                        </p>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {activeSection === "credit" && (
        <div className="mx-4 mt-4 space-y-4">
          <div className="paypal-surface rounded-3xl p-4">
            <div className="rounded-2xl bg-gradient-to-br from-paypal-blue to-[#2f67dc] p-4 text-white shadow-xl shadow-[#004bba]/25">
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="text-xl font-semibold">Credit Overview</p>
              </div>
              <span className="rounded-full bg-white/20 px-3 py-1 text-sm font-semibold">
                {currencyTag}
              </span>
            </div>

            <div className="mt-4 rounded-2xl bg-white/10 p-4">
              <p className="text-sm text-white/80">Credit score</p>
              <p className="mt-2 text-5xl font-bold">{creditScoreDisplay}</p>
              <div className="mt-3 h-2 w-full overflow-hidden rounded-full bg-secondary">
                <div
                  className="h-full rounded-full bg-emerald-500"
                  style={{ width: `${creditProgressPercent}%` }}
                />
              </div>
              <p className="mt-2 text-xs text-muted-foreground">
                Credit starts at 0 for new accounts and grows from OpenPay activity.
              </p>
            </div>

            <div className="mt-3 grid gap-2 sm:grid-cols-3">
              <div className="rounded-xl bg-white/15 p-3">
                <p className="text-xs text-white/75">Status</p>
                <p className="mt-1 text-sm font-semibold text-white">{creditScoreDisplay >= 120 ? "Loan-ready profile" : "Building profile"}</p>
              </div>
              <div className="rounded-xl bg-white/15 p-3">
                <p className="text-xs text-white/75">Range</p>
                <p className="mt-1 text-sm font-semibold text-white">0 - 900</p>
              </div>
              <div className="rounded-xl bg-white/15 p-3">
                <p className="text-xs text-white/75">Loan unlock</p>
                <p className="mt-1 text-sm font-semibold text-white">{creditScoreDisplay} / 120</p>
              </div>
            </div>

            <div className="mt-3 rounded-2xl bg-white/15 p-4 text-sm text-white/90">
              Credit uses send, receive, buy, checkout, invoice, and request activity.
            </div>

            <div className="mt-3 grid grid-cols-3 gap-2">
              <button
                type="button"
                onClick={() => navigate("/send")}
                className="h-11 rounded-full bg-white text-paypal-blue text-sm font-semibold"
              >
                Pay
              </button>
              <button
                type="button"
                onClick={() => navigate("/receive")}
                className="h-11 rounded-full bg-white/10 text-sm font-semibold text-white"
              >
                Receive
              </button>
              <button
                type="button"
                onClick={openBuyOptions}
                className="h-11 rounded-full bg-white/10 text-sm font-semibold text-white"
              >
                Buy
              </button>
            </div>
            </div>
          </div>

          <div className="paypal-surface rounded-3xl p-4">
            <div className="mb-3 flex items-center justify-between">
              <h3 className="text-base font-bold text-foreground">Credit score activity</h3>
              <span className="text-xs font-semibold text-muted-foreground">From recent activity</span>
            </div>
            <div className="divide-y divide-border/70 rounded-2xl border border-border/70">
              {creditActivityRows.map((row) => (
                <div key={row.key} className="flex items-center justify-between px-3 py-2.5">
                  <div>
                    <p className="text-sm font-medium text-foreground">{row.label}</p>
                    <p className="text-xs text-muted-foreground">{row.count} actions</p>
                  </div>
                  <p className="text-sm font-semibold text-paypal-blue">+{row.count * row.points} pts</p>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {activeSection === "loans" && (
        <div className="mx-4 mt-4 paypal-surface rounded-3xl p-4">
          <div className="mb-3 flex items-center gap-2">
            <HandCoins className="h-5 w-5 text-paypal-blue" />
            <h2 className="text-lg font-bold text-paypal-dark">Loans</h2>
          </div>
          {loanView === "overview" ? (
            <div className="rounded-2xl border border-border/70 p-4">
              <div className="rounded-2xl bg-gradient-to-br from-paypal-blue to-[#3b79ef] p-5 text-white">
                <p className="text-sm text-white/85">Available to borrow</p>
                <p className="mt-1 text-3xl font-bold">{balanceHidden ? "****" : formatCompactCurrency(availableToBorrow)}</p>
                <p className="mt-1 text-sm text-white/85">Based on your wallet & savings balance</p>
              </div>

              <div className="mt-4 space-y-3">
                <div className="flex items-center justify-between rounded-xl bg-secondary/40 px-4 py-3">
                  <span className="text-base text-muted-foreground">Loan amount</span>
                  <span className="text-xl font-semibold text-foreground">{formatCompactCurrency(previewLoanAmount)}</span>
                </div>
                <div className="flex items-center justify-between rounded-xl bg-secondary/40 px-4 py-3">
                  <span className="text-base text-muted-foreground">Interest rate</span>
                  <span className="text-xl font-semibold text-emerald-600">{previewApr.toFixed(1)}% APR</span>
                </div>
                <div className="flex items-center justify-between rounded-xl bg-secondary/40 px-4 py-3">
                  <span className="text-base text-muted-foreground">Term</span>
                  <span className="text-xl font-semibold text-foreground">{previewTermDays} days</span>
                </div>
                <div className="flex items-center justify-between rounded-xl border border-paypal-blue/35 bg-paypal-blue/5 px-4 py-3">
                  <span className="text-lg font-semibold text-foreground">Total repayment</span>
                  <span className="text-xl font-semibold text-paypal-blue">{formatCompactCurrency(previewRepayment)}</span>
                </div>
              </div>

              <input
                value={formatAmountInput(loanAmount)}
                onChange={(e) => setLoanAmount(normalizeAmountInput(e.target.value))}
                type="text"
                inputMode="decimal"
                placeholder={`Enter loan amount (${currencyLabel})`}
                className="mt-4 h-12 w-full rounded-xl border border-border px-3 text-sm text-foreground"
              />
              <div className="mt-3 inline-flex items-center gap-2 rounded-full bg-blue-50 px-3 py-1.5 text-sm font-semibold text-paypal-blue">
                <span className="h-2 w-2 rounded-full bg-paypal-blue" />
                Coming Soon
              </div>
              <button
                type="button"
                onClick={() => setLoanView("form")}
                className="mt-4 h-12 w-full rounded-xl bg-[#7a9de8] text-lg font-semibold text-white transition hover:bg-[#6b90e0]"
              >
                Apply for Loan
              </button>
            </div>
          ) : (
            <div className="rounded-2xl border border-border/70 p-3">
              <div className="mb-3 flex items-center justify-between">
                <p className="text-sm font-semibold text-foreground">Loan onboarding form</p>
                <button type="button" onClick={() => setLoanView("overview")} className="text-xs font-semibold text-paypal-blue">
                  Back to preview
                </button>
              </div>
              <p className="text-xs text-muted-foreground">Provide accurate details. This application is reviewed by OpenPay admin before approval.</p>
              <div className="mt-3 grid gap-3 sm:grid-cols-2">
                <label className="space-y-1 text-xs text-muted-foreground">
                  <span>Loan amount ({currencyLabel})</span>
                  <input
                    value={formatAmountInput(loanAmount)}
                    onChange={(e) => setLoanAmount(normalizeAmountInput(e.target.value))}
                    type="text"
                    inputMode="decimal"
                    placeholder="e.g. 500"
                    className="h-10 w-full rounded-xl border border-border px-3 text-sm text-foreground"
                  />
                </label>
                <label className="space-y-1 text-xs text-muted-foreground">
                  <span>Term months (1 - 60)</span>
                  <input value={loanTermMonths} onChange={(e) => setLoanTermMonths(e.target.value)} type="number" min="1" max="60" placeholder="e.g. 6" className="h-10 w-full rounded-xl border border-border px-3 text-sm text-foreground" />
                </label>
              </div>
              <div className="mt-3 grid gap-3 sm:grid-cols-2">
                <label className="space-y-1 text-xs text-muted-foreground">
                  <span>Full legal name</span>
                  <input value={loanApplicantName} onChange={(e) => setLoanApplicantName(e.target.value)} placeholder="Enter full name" className="h-10 w-full rounded-xl border border-border px-3 text-sm text-foreground" />
                </label>
                <label className="space-y-1 text-xs text-muted-foreground">
                  <span>Contact number</span>
                  <input value={loanContactNumber} onChange={(e) => setLoanContactNumber(e.target.value)} placeholder="Phone or active contact number" className="h-10 w-full rounded-xl border border-border px-3 text-sm text-foreground" />
                </label>
                <label className="space-y-1 text-xs text-muted-foreground sm:col-span-2">
                  <span>Address line</span>
                  <input value={loanAddressLine} onChange={(e) => setLoanAddressLine(e.target.value)} placeholder="Street / building / district" className="h-10 w-full rounded-xl border border-border px-3 text-sm text-foreground" />
                </label>
                <label className="space-y-1 text-xs text-muted-foreground">
                  <span>City</span>
                  <input value={loanCity} onChange={(e) => setLoanCity(e.target.value)} placeholder="Enter city" className="h-10 w-full rounded-xl border border-border px-3 text-sm text-foreground" />
                </label>
                <label className="space-y-1 text-xs text-muted-foreground">
                  <span>Country</span>
                  <input value={loanCountry} onChange={(e) => setLoanCountry(e.target.value)} placeholder="Enter country" className="h-10 w-full rounded-xl border border-border px-3 text-sm text-foreground" />
                </label>
              </div>
              <div className="mt-3 rounded-xl border border-border/70 bg-secondary/30 p-3 text-xs text-muted-foreground">
                <p className="font-semibold text-foreground">Bound OpenPay account</p>
                <p className="mt-1">Account number: {userAccount?.account_number || "-"}</p>
                <p>Username: {userAccount?.account_username ? `@${userAccount.account_username}` : "-"}</p>
              </div>
              <label className="mt-3 flex items-start gap-2 text-xs text-foreground">
                <input type="checkbox" className="mt-0.5" checked={loanAgreementAccepted} onChange={(e) => setLoanAgreementAccepted(e.target.checked)} />
                <span>I agree to OpenPay loan terms and confirm my application details are real and accurate.</span>
              </label>
              <button
                disabled={requestingLoan || loanApplication?.status === "pending"}
                onClick={handleRequestLoan}
                className="mt-3 h-10 w-full rounded-xl bg-paypal-blue text-sm font-semibold text-white disabled:opacity-60"
              >
                {requestingLoan ? "Submitting..." : "Submit Loan Application"}
              </button>
            </div>
          )}
          <div className="mt-3 rounded-2xl border border-border/70 p-3">
            <p className="mb-2 text-sm font-semibold">Pay monthly installment</p>
            <input
              value={formatAmountInput(loanPaymentAmount)}
              onChange={(e) => setLoanPaymentAmount(normalizeAmountInput(e.target.value))}
              type="text"
              inputMode="decimal"
              placeholder={`Default: ${loan ? formatCompactCurrency(loan.monthly_payment_amount) : `monthly due (${currencyLabel})`}`}
              className="h-10 w-full rounded-xl border border-border px-3"
            />
            <div className="mt-2 grid grid-cols-2 gap-2">
              <button
                type="button"
                onClick={() => setLoanPaymentMethod("wallet")}
                className={`h-10 rounded-xl border text-sm font-semibold ${loanPaymentMethod === "wallet" ? "border-paypal-blue bg-paypal-blue text-white" : "border-border bg-white text-foreground"}`}
              >
                Pi Payment
              </button>
              <button
                type="button"
                onClick={() => setLoanPaymentMethod("pi")}
                className={`h-10 rounded-xl border text-sm font-semibold ${loanPaymentMethod === "pi" ? "border-paypal-blue bg-paypal-blue text-white" : "border-border bg-white text-foreground"}`}
              >
                Pi Payment
              </button>
            </div>
            {loanPaymentMethod === "pi" && (
              <input
                value={loanPaymentReference}
                onChange={(e) => setLoanPaymentReference(e.target.value)}
                placeholder="Pi payment reference (required)"
                className="mt-2 h-10 w-full rounded-xl border border-border px-3"
              />
            )}
            <button disabled={payingLoan || !loan || loan.status !== "active"} onClick={() => handleProtectedAction(handlePayLoan, "handlePayLoan")} className="mt-2 h-10 w-full rounded-xl border border-paypal-blue/40 bg-white text-sm font-semibold text-paypal-blue">
              {payingLoan ? "Paying..." : "Pay Loan"}
            </button>
          </div>
          <div className="mt-3 rounded-2xl border border-border/70 p-3">
            <div className="mb-2 flex items-center justify-between">
              <p className="text-sm font-semibold">Loan payment history</p>
              <p className="text-xs text-muted-foreground">{loanPaymentHistory.length} records</p>
            </div>
            {loanPaymentHistory.length === 0 ? (
              <p className="text-sm text-muted-foreground">No loan payments yet.</p>
            ) : (
              <div className="divide-y divide-border/70 rounded-xl border border-border/70">
                {loanPaymentHistory.map((entry) => (
                  <div key={entry.id} className="px-3 py-2">
                    <div className="flex items-center justify-between gap-2">
                      <p className="text-sm font-medium">{formatCompactCurrency(entry.amount)}</p>
                      <p className="text-xs uppercase text-muted-foreground">{entry.payment_method}</p>
                    </div>
                    <p className="text-xs text-muted-foreground">
                      Principal {formatCompactCurrency(entry.principal_component)} | Fee {formatCompactCurrency(entry.fee_component)}
                    </p>
                    {entry.payment_reference && <p className="text-xs text-muted-foreground">Ref: {toPreviewText(entry.payment_reference, 44)}</p>}
                    <p className="text-xs text-muted-foreground">{entry.created_at ? format(new Date(entry.created_at), "MMM d, yyyy h:mm a") : "-"}</p>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      )}

      {activeSection === "cards" && (
        <div className="mx-4 mt-4 space-y-4">
        <div className="paypal-surface rounded-3xl p-4">
          <div className="rounded-2xl bg-gradient-to-br from-paypal-blue to-[#2f67dc] p-4 text-white shadow-xl shadow-[#004bba]/25">
          <div className="flex items-start justify-between gap-3">
            <div>
              <p className="text-xl font-semibold">OpenPay Cards</p>
            </div>
            <span className="rounded-full bg-white/20 px-3 py-1 text-sm font-semibold">
              {cardCurrencyLabel}
            </span>
          </div>

          <div className="mt-4 rounded-2xl bg-white/10 p-4">
            <p className="text-sm text-white/80">Virtual Card</p>
            <p className="mt-2 text-2xl font-semibold tracking-[0.12em]">
              {hideCardPreviewDetails ? "**** **** **** ****" : virtualCardNumber}
            </p>
            <p className="mt-2 text-sm text-white/80">
              {hideCardPreviewDetails ? "Card details hidden" : `Linked to wallet - ${virtualCardActive ? "Active" : "Inactive"}`}
            </p>
          </div>

          <div className="mt-4 grid grid-cols-3 gap-2">
            <button
              type="button"
              onClick={() => navigate("/send")}
              className="h-11 rounded-full bg-white text-paypal-blue text-sm font-semibold"
            >
              Pay
            </button>
            <button
              type="button"
              onClick={() => navigate("/receive")}
              className="h-11 rounded-full bg-white/10 text-sm font-semibold text-white"
            >
              Receive
            </button>
            <button
              type="button"
              onClick={openBuyOptions}
              className="h-11 rounded-full bg-white/10 text-sm font-semibold text-white"
            >
              Buy
            </button>
          </div>

          <div className="mt-3 grid grid-cols-1 gap-2 sm:grid-cols-2">
            <button
              type="button"
              onClick={() => setHideCardPreviewDetails((prev) => !prev)}
              className="h-10 w-full rounded-xl border border-white/40 px-4 text-sm font-semibold text-white transition hover:bg-white/10"
            >
              {hideCardPreviewDetails ? "View Details" : "Hide Details"}
            </button>
            <button
              onClick={() => navigate("/virtual-card")}
              className="h-10 w-full rounded-xl bg-white text-sm font-semibold text-paypal-blue transition hover:bg-white/90"
            >
              Open Virtual Card
            </button>
          </div>
          </div>
        </div>
        <div className="paypal-surface rounded-3xl p-4">
          <div className="mb-3 flex items-center justify-between">
            <h3 className="text-base font-bold text-foreground">Card activity history</h3>
            <button
              type="button"
              onClick={() => navigate("/activity")}
              className="text-xs font-semibold text-paypal-blue"
            >
              See all
            </button>
          </div>
          <div className="divide-y divide-border/70 rounded-2xl border border-border/70">
            {transactions
              .filter((tx) => {
                const note = String(tx.note || "").toLowerCase();
                return note.includes("merchant checkout") || note.includes("virtual card") || note.includes("card ****");
              })
              .slice(0, 6)
              .map((tx) => (
                <div key={tx.id} className="flex items-center justify-between px-3 py-2">
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium text-foreground">{toPreviewText(tx.note || "Card payment", 44)}</p>
                    <p className="text-xs text-muted-foreground">{format(new Date(tx.created_at), "MMM d, yyyy h:mm a")}</p>
                  </div>
                  <p className={`ml-3 text-sm font-semibold ${tx.is_sent && !tx.is_topup ? "text-red-500" : "text-paypal-success"}`}>
                    {balanceHidden ? "****" : `${tx.is_sent && !tx.is_topup ? "-" : "+"}${formatCompactCurrency(tx.amount)}`}
                  </p>
                </div>
              ))}
            {transactions.filter((tx) => {
              const note = String(tx.note || "").toLowerCase();
              return note.includes("merchant checkout") || note.includes("virtual card") || note.includes("card ****");
            }).length === 0 && <p className="px-3 py-8 text-center text-sm text-muted-foreground">No card activity yet.</p>}
          </div>
        </div>
        </div>
      )}

      {activeSection === "buy" && (
        <div className="mx-4 mt-4 space-y-4">
          <div className="paypal-surface rounded-3xl p-4">
            <div className="mb-3 flex items-center justify-between">
              <p className="text-xl font-semibold text-foreground">Onramper</p>
              <span className="rounded-full border border-border/70 px-3 py-1 text-xs font-semibold text-muted-foreground">Buy OpenUSD</span>
            </div>

            <div className="space-y-3">
              <div className="rounded-2xl bg-secondary/50 p-4">
                <p className="text-sm text-muted-foreground">
                  You spend ({buySpendUnit} amount)
                </p>
                <div className="mt-2 flex items-center justify-between gap-3">
                  <input
                    value={formatAmountInput(buySpendAmount)}
                    onChange={(e) => setBuySpendAmount(normalizeAmountInput(e.target.value))}
                    type="text"
                    inputMode="decimal"
                    placeholder={isEwalletBuyFlow ? "Custom amount in PHP (min 57)" : "Custom amount (min 1)"}
                    className="h-10 w-full bg-transparent text-4xl font-semibold text-foreground outline-none"
                  />
                  <span className="inline-flex h-11 items-center rounded-xl bg-white px-3 text-sm font-semibold text-foreground">
                    {buySpendUnit}
                  </span>
                </div>
                <p className="mt-2 text-xs font-medium text-foreground">
                  {buySpendRateText}
                </p>
              </div>

              <div className="rounded-2xl bg-secondary/50 p-4">
                <p className="text-sm text-muted-foreground">You get (OPEN USD amount)</p>
                <div className="mt-2 flex items-center justify-between gap-3">
                  <p className="text-4xl font-semibold text-foreground">{buyOpenUsdDisplay}</p>
                  <span className="inline-flex h-11 items-center rounded-xl bg-white px-3 text-sm font-semibold text-foreground">OPEN USD</span>
                </div>
                <p className="mt-2 text-xs font-medium text-foreground">{buyOpenUsdRateText}</p>
                <div className="mt-4 flex flex-wrap items-center justify-between gap-2 border-t border-border/50 pt-3 text-sm text-muted-foreground">
                  <p>
                    1 OUSD ~ {isEwalletBuyFlow
                      ? `${E_WALLET_PHP_PER_OUSD.toFixed(4)} PHP`
                      : isUsdtBuyFlow
                        ? "1.0000 USDT"
                        : isUsdcBuyFlow
                          ? "1.0000 USDC"
                          : isUsdFiatBuyFlow
                        ? "1.0000 USD"
                        : `${selectedRate.toFixed(4)} PI`}
                  </p>
                  <button
                    type="button"
                    onClick={() => setShowOnrampPicker(true)}
                    className="inline-flex items-center gap-1 font-semibold text-foreground"
                  >
                    By {buyOnrampProvider}
                    <ChevronDown className="h-4 w-4" />
                  </button>
                </div>
              </div>
            </div>

            <p className="mt-4 text-base text-foreground">Pay using</p>
            <button
              type="button"
              onClick={() => setShowPaymentMethodPicker(true)}
              className="mt-2 flex h-14 w-full items-center justify-between rounded-2xl border border-border/70 bg-white px-4"
            >
              <span className="inline-flex items-center gap-2 text-base font-semibold text-foreground">
                {buyPaymentMethod === "Pi Payment" && (
                  <img src={PI_PAYMENT_ICON_URL} alt="Pi Payment" className="h-10 w-auto object-contain" />
                )}
                {buyPaymentMethod === "Ewallet" && (
                  <img src={JQRPH_ICON_URL} alt="JQRPh" className="h-5 w-auto object-contain" />
                )}
                {buyPaymentMethod === "PayPal" && (
                  <img src={PAYPAL_ICON_URL} alt="PayPal" className="h-5 w-auto object-contain" />
                )}
                {buyPaymentMethod === "USDT" && (
                  <img src={USDT_ICON_URL} alt="USDT" className="h-5 w-auto object-contain" />
                )}
                {buyPaymentMethod === "USDC" && (
                  <img src={USDC_ICON_URL} alt="USDC" className="h-5 w-auto object-contain" />
                )}
                {buyPaymentMethod === "Solana Pay" && (
                  <img src={SOLANA_PAY_ICON_URL} alt="Solana Pay" className="h-5 w-auto object-contain" />
                )}
                {buyPaymentMethod === "Apple Pay" && (
                  <img src={APPLE_PAY_ICON_URL} alt="Apple Pay" className="h-5 w-auto object-contain" />
                )}
                {buyPaymentMethod === "Google Pay" && (
                  <img src={GOOGLE_PAY_ICON_URL} alt="Google Pay" className="h-5 w-auto object-contain" />
                )}
                {buyPaymentMethod === "Debit Card" && (
                  <img src={VISA_ICON_URL} alt="Visa" className="h-5 w-auto object-contain" />
                )}
                {buyPaymentMethod === "Credit Card" && (
                  <img src={MASTERCARD_ICON_URL} alt="Mastercard" className="h-5 w-auto object-contain" />
                )}
                {buyPaymentMethod === "Stripe" && (
                  <img src={STRIPE_ICON_URL} alt="Stripe" className="h-5 w-auto object-contain" />
                )}
                {buyPaymentMethod === "Venmo" && (
                  <img src={VENMO_ICON_URL} alt="Venmo" className="h-5 w-auto object-contain" />
                )}
                {getBuyPaymentMethodLabel(buyPaymentMethod)}
              </span>
              <ChevronDown className="h-5 w-5 text-muted-foreground" />
            </button>
            <button
              type="button"
              onClick={handleBuyOpenUsd}
              disabled={!buyOpenUsdMeetsMinimum}
              className="mt-3 h-11 w-full rounded-xl bg-paypal-blue text-sm font-semibold text-white hover:bg-[#004dc5] disabled:cursor-not-allowed disabled:opacity-60"
            >
              {buyPaymentMethod === "Ewallet"
                ? "Buy OpenUSD with Ewallet QR PH"
                : buyPaymentMethod === "USDT"
                  ? "Buy OpenUSD with USDT"
                  : buyPaymentMethod === "USDC"
                    ? "Buy OpenUSD with USDC"
                : buyPaymentMethod === "PayPal"
                  ? "Buy OpenUSD with PayPal"
                  : "Buy OpenUSD with Pi Payment"}
            </button>
            <p className="mt-2 text-xs text-muted-foreground">
              Minimum buy: 1 OPEN USD. {isEwalletBuyFlow
                ? `Ewallet QR PH uses PH price: 1 OPEN USD = ${E_WALLET_PHP_PER_OUSD.toFixed(2)} PHP.`
                : isUsdtBuyFlow
                  ? "USDT buy uses fixed rate: 1 USDT = 1 OPEN USD."
                  : isUsdcBuyFlow
                    ? "USDC buy uses fixed rate: 1 USDC = 1 OPEN USD."
                : buyPaymentMethod === "PayPal"
                  ? "PayPal uses USD amount and credits OPEN USD balance."
                  : "Purchase flow uses OpenPay OPEN USD to PI balance."}
            </p>
            <p className="mt-1 text-xs text-muted-foreground">
              Stable mode enabled: 1 PI = {PI_TO_OUSD.toFixed(2)} OPEN USD.
            </p>
          </div>
        </div>
      )}

      {activeSection === "swap" && (
        <div className="mx-4 mt-4 space-y-4">
          <div className="paypal-surface rounded-3xl p-4">
            <div className="mb-3 flex items-center justify-between">
              <p className="text-xl font-semibold text-foreground">Swap Withdrawal</p>
              <span className="rounded-full border border-border/70 px-3 py-1 text-xs font-semibold text-muted-foreground">
                OUSD → PI payout
              </span>
            </div>
            <div className="rounded-2xl bg-secondary/30 p-4">
              <p className="text-sm text-muted-foreground">Amount (min 10 OUSD)</p>
              <input
                value={swapAmount}
                onChange={(e) => setSwapAmount(normalizeAmountInput(e.target.value))}
                type="text"
                inputMode="decimal"
                placeholder="Enter amount in OUSD"
                className="mt-2 h-11 w-full rounded-xl border border-border bg-background px-3 text-sm text-foreground"
              />
              <div className="mt-3 rounded-2xl border border-border/70 bg-secondary/30 p-3 text-sm text-foreground">
                <div className="flex items-center justify-between">
                  <span>Amount</span>
                  <span className="font-semibold">{safeSwapAmount.toFixed(2)} OUSD</span>
                </div>
                <div className="mt-1 flex items-center justify-between text-xs text-muted-foreground">
                  <span>Fee (2%)</span>
                  <span>-{swapFeeAmount.toFixed(2)} OUSD</span>
                </div>
                <div className="mt-2 flex items-center justify-between">
                  <span className="font-semibold">You will receive</span>
                  <span className="inline-flex items-center gap-2 font-semibold text-paypal-blue">
                    {swapPayoutPiAmount.toFixed(4)} PI
                  </span>
                </div>
              </div>
              <p className="mt-2 text-xs text-muted-foreground">
                Rate: 1 PI = {PI_TO_OUSD.toFixed(2)} OUSD. Processing fee is 2%.
              </p>
              <div className="mt-3 grid gap-2 sm:grid-cols-2">
                <button
                  type="button"
                  onClick={() => navigate(`/swap-withdrawal?amount=${safeSwapAmount.toFixed(2)}`)}
                  className="h-11 w-full rounded-xl bg-paypal-blue text-sm font-semibold text-white hover:bg-[#004dc5]"
                  disabled={!swapMeetsMinimum}
                >
                  Continue
                </button>
                <button
                  type="button"
                  onClick={() => navigate("/swap-withdrawal")}
                  className="h-11 w-full rounded-xl border border-paypal-blue/40 bg-white text-sm font-semibold text-paypal-blue"
                >
                  View Withdrawals
                </button>
              </div>
            </div>
            <p className="mt-2 text-xs text-muted-foreground">
              You will confirm your OpenPay identity and PI mainnet wallet on the next screen.
            </p>
          </div>
        </div>
      )}

      {activeSection === "mining" && (
        <div className="mx-4 mt-4 space-y-4">
          <div className="paypal-surface rounded-3xl p-4">
            <div className="mb-3 flex items-center justify-between">
              <p className="text-xl font-semibold text-foreground">Mining</p>
              <span className="rounded-full border border-border/70 px-3 py-1 text-xs font-semibold text-muted-foreground">Earn OPEN USD</span>
            </div>

            <div className="space-y-3">
              <div className="rounded-2xl bg-gradient-to-br from-paypal-blue/20 to-[#0073e6]/20 p-4">
                <p className="text-sm text-muted-foreground">Current Mining Balance</p>
                <div className="mt-2 flex items-center justify-between gap-3">
                  <p className="text-4xl font-semibold text-foreground">{miningBalance.toFixed(2)}</p>
                  <span className="inline-flex h-11 items-center rounded-xl bg-white px-3 text-sm font-semibold text-foreground">OPEN USD</span>
                </div>
                <p className="mt-2 text-xs font-medium text-foreground">Earned through mining</p>
              </div>

              <div className="rounded-2xl bg-secondary/50 p-4">
                <p className="text-sm text-muted-foreground">Mining Status</p>
                <div className="mt-2 flex items-center justify-between gap-3">
                  <div className="flex items-center gap-2">
                    <div className={`h-3 w-3 rounded-full ${activeMiningSession ? "bg-green-500 animate-pulse" : "bg-gray-400"}`} />
                    <span className="text-lg font-semibold text-foreground">
                      {activeMiningSession ? "Active" : "Inactive"}
                    </span>
                  </div>
                  {miningTimeLeft > 0 && (
                    <span className="text-sm font-medium text-muted-foreground">
                      {Math.floor(miningTimeLeft / 3600)}h {Math.floor((miningTimeLeft % 3600) / 60)}m
                    </span>
                  )}
                </div>
                <p className="mt-2 text-xs text-muted-foreground">
                  {activeMiningSession 
                    ? "Mining session is active. Keep earning!" 
                    : "Start a new mining session to earn OPEN USD"}
                </p>
              </div>
            </div>

            <div className="mt-4 flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-foreground">Mining Rate</p>
                <div className="mt-1 flex items-center gap-2">
                  <span className="inline-flex items-center gap-2 text-base font-semibold text-foreground">
                    <Pickaxe className="h-5 w-5 text-paypal-blue" />
                    0.10 OPEN USD / day
                  </span>
                </div>
              </div>
            </div>
            <button
              type="button"
              onClick={() => navigate("/mining")}
              className="mt-3 h-11 w-full rounded-xl bg-paypal-blue text-sm font-semibold text-white hover:bg-[#004dc5] transition-colors"
            >
              {activeMiningSession ? "Manage Mining" : "Start Mining"}
            </button>
            <button
              type="button"
              onClick={() => navigate("/mining")}
              className="mt-2 h-11 w-full rounded-xl border border-paypal-blue/40 bg-white text-sm font-semibold text-paypal-blue"
            >
              View Mining History
            </button>
            <p className="mt-2 text-xs text-muted-foreground">
              Mining runs 24 hours. Earn 0.10 OPEN USD daily.
            </p>
            <p className="mt-1 text-xs text-muted-foreground">
              Powered by OpenPay Network.
            </p>
          </div>

          <div className="paypal-surface rounded-3xl p-4">
            <div className="mb-3 flex items-center justify-between">
              <p className="text-xl font-semibold text-foreground">Staking</p>
              <span className="rounded-full border border-border/70 px-3 py-1 text-xs font-semibold text-muted-foreground">Earn Yield</span>
            </div>

            <div className="space-y-3">
              <div className="rounded-2xl bg-gradient-to-br from-paypal-blue/10 to-[#00a3ff]/10 p-4">
                <p className="text-sm text-muted-foreground">Lock funds to earn rewards</p>
                <p className="mt-2 text-xs text-muted-foreground">
                  Choose a lock duration and claim rewards after the lock ends.
                </p>
                <div className="mt-3 flex flex-wrap gap-2">
                  <span className="rounded-full border border-border bg-white px-3 py-1 text-xs font-semibold text-foreground">7 days · 2%</span>
                  <span className="rounded-full border border-border bg-white px-3 py-1 text-xs font-semibold text-foreground">30 days · 5%</span>
                  <span className="rounded-full border border-border bg-white px-3 py-1 text-xs font-semibold text-foreground">90 days · 10%</span>
                  <span className="rounded-full border border-border bg-white px-3 py-1 text-xs font-semibold text-foreground">365 days · 20%</span>
                </div>
              </div>

              <div className="rounded-2xl bg-secondary/50 p-4">
                <p className="text-sm text-muted-foreground">How it works</p>
                <p className="mt-2 text-xs text-muted-foreground">
                  Staked funds are locked. Rewards are claimable only after the lock period.
                </p>
              </div>
            </div>

            <button
              type="button"
              onClick={() => navigate("/staking")}
              className="mt-3 h-11 w-full rounded-xl bg-paypal-blue text-sm font-semibold text-white hover:bg-[#004dc5] transition-colors"
            >
              Start Staking
            </button>
            <p className="mt-2 text-xs text-muted-foreground">
              Stake OpenUSD and earn yield based on lock duration.
            </p>
          </div>
        </div>
      )}

      {activeSection === "analytics" && (
        <div className="mx-4 mt-4 space-y-6">
          {/* Header Section */}
          <div className="paypal-surface rounded-3xl p-6">
            <div className="flex items-center justify-between">
              <div>
                <h2 className="text-2xl font-bold text-foreground">Analytics</h2>
                <p className="text-sm text-muted-foreground mt-1">Track your wallet performance and activity</p>
              </div>
              <button 
                onClick={() => void loadPersonalAnalytics()} 
                className="rounded-xl bg-paypal-blue px-4 py-2 text-sm font-semibold text-white hover:bg-[#004dc5] transition"
              >
                Refresh
              </button>
            </div>
          </div>

          {personalAnalyticsLoading ? (
            <div className="paypal-surface rounded-3xl p-12">
              <div className="flex flex-col items-center justify-center">
                <RefreshCw className="h-8 w-8 animate-spin text-paypal-blue" />
                <p className="mt-2 text-sm text-muted-foreground">Loading analytics...</p>
              </div>
            </div>
          ) : personalAnalytics ? (
            <>
              {/* Key Metrics Grid */}
              <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                <div className="paypal-surface rounded-2xl p-6">
                  <div className="flex items-center justify-between mb-2">
                    <div className="h-8 w-8 rounded-full bg-red-100 flex items-center justify-center">
                      <span className="text-red-600 font-bold text-sm">S</span>
                    </div>
                    <span className="text-xs text-red-600 font-medium">+12.5%</span>
                  </div>
                  <p className="text-2xl font-bold text-foreground">{formatCompactCurrency(personalAnalytics.summary.total_sent)}</p>
                  <p className="text-sm text-muted-foreground">Total Sent</p>
                </div>
                
                <div className="paypal-surface rounded-2xl p-6">
                  <div className="flex items-center justify-between mb-2">
                    <div className="h-8 w-8 rounded-full bg-green-100 flex items-center justify-center">
                      <span className="text-green-600 font-bold text-sm">R</span>
                    </div>
                    <span className="text-xs text-green-600 font-medium">+8.2%</span>
                  </div>
                  <p className="text-2xl font-bold text-foreground">{formatCompactCurrency(personalAnalytics.summary.total_received)}</p>
                  <p className="text-sm text-muted-foreground">Total Received</p>
                </div>
                
                <div className="paypal-surface rounded-2xl p-6">
                  <div className="flex items-center justify-between mb-2">
                    <div className="h-8 w-8 rounded-full bg-blue-100 flex items-center justify-center">
                      <span className="text-blue-600 font-bold text-sm">N</span>
                    </div>
                    <span className="text-xs text-blue-600 font-medium">+5.1%</span>
                  </div>
                  <p className="text-2xl font-bold text-foreground">{formatCompactCurrency(personalAnalytics.summary.net_balance)}</p>
                  <p className="text-sm text-muted-foreground">Net Balance</p>
                </div>
                
                <div className="paypal-surface rounded-2xl p-6">
                  <div className="flex items-center justify-between mb-2">
                    <div className="h-8 w-8 rounded-full bg-purple-100 flex items-center justify-center">
                      <span className="text-purple-600 font-bold text-sm">#</span>
                    </div>
                    <span className="text-xs text-purple-600 font-medium">+15.3%</span>
                  </div>
                  <p className="text-2xl font-bold text-foreground">{personalAnalytics.summary.transaction_count}</p>
                  <p className="text-sm text-muted-foreground">Transactions</p>
                </div>
              </div>

              {/* Charts Section */}
              <div className="grid gap-6 lg:grid-cols-2">
                {/* Activity Chart */}
                <div className="paypal-surface rounded-2xl p-6">
                  <h3 className="text-lg font-semibold text-foreground mb-4">Activity Overview</h3>
                  <div className="space-y-4">
                    <div className="flex justify-between items-center">
                      <span className="text-sm text-muted-foreground">Payment Requests</span>
                      <div className="flex items-center gap-2">
                        <span className="text-sm font-semibold">{personalAnalytics.summary.payment_requests_sent + personalAnalytics.summary.payment_requests_received}</span>
                        <span className="text-xs text-green-600">+23%</span>
                      </div>
                    </div>
                    <div className="w-full bg-gray-200 rounded-full h-2">
                      <div className="bg-green-500 h-2 rounded-full" style={{ width: '75%' }} />
                    </div>
                    
                    <div className="flex justify-between items-center">
                      <span className="text-sm text-muted-foreground">Top-ups</span>
                      <div className="flex items-center gap-2">
                        <span className="text-sm font-semibold">{personalAnalytics.summary.topup_count}</span>
                        <span className="text-xs text-blue-600">+12%</span>
                      </div>
                    </div>
                    <div className="w-full bg-gray-200 rounded-full h-2">
                      <div className="bg-blue-500 h-2 rounded-full" style={{ width: '45%' }} />
                    </div>
                    
                    <div className="flex justify-between items-center">
                      <span className="text-sm text-muted-foreground">Transactions</span>
                      <div className="flex items-center gap-2">
                        <span className="text-sm font-semibold">{personalAnalytics.summary.transaction_count}</span>
                        <span className="text-xs text-purple-600">+18%</span>
                      </div>
                    </div>
                    <div className="w-full bg-gray-200 rounded-full h-2">
                      <div className="bg-purple-500 h-2 rounded-full" style={{ width: '90%' }} />
                    </div>
                  </div>
                </div>

                {/* Performance Metrics */}
                <div className="paypal-surface rounded-2xl p-6">
                  <h3 className="text-lg font-semibold text-foreground mb-4">Performance Metrics</h3>
                  <div className="space-y-4">
                    <div className="flex justify-between items-center pb-3 border-b border-border/50">
                      <span className="text-sm text-muted-foreground">Avg Transaction</span>
                      <span className="text-sm font-semibold">{formatCompactCurrency(personalAnalytics.detailed_metrics.avg_transaction_value)}</span>
                    </div>
                    <div className="flex justify-between items-center pb-3 border-b border-border/50">
                      <span className="text-sm text-muted-foreground">Avg Top-up</span>
                      <span className="text-sm font-semibold">{formatCompactCurrency(personalAnalytics.detailed_metrics.avg_topup_amount)}</span>
                    </div>
                    <div className="flex justify-between items-center pb-3 border-b border-border/50">
                      <span className="text-sm text-muted-foreground">Most Used Currency</span>
                      <span className="text-sm font-semibold">{personalAnalytics.detailed_metrics.most_used_currency}</span>
                    </div>
                    <div className="flex justify-between items-center">
                      <span className="text-sm text-muted-foreground">Total Activities</span>
                      <span className="text-sm font-semibold">{personalAnalytics.detailed_metrics.total_activities}</span>
                    </div>
                  </div>
                </div>
              </div>

              {/* Recent Activity Table */}
              <div className="paypal-surface rounded-2xl p-6">
                <h3 className="text-lg font-semibold text-foreground mb-4">Recent Activity</h3>
                {personalAnalytics.recent_transactions.length === 0 ? (
                  <div className="text-center py-8">
                    <p className="text-sm text-muted-foreground">No recent activity found</p>
                  </div>
                ) : (
                  <div className="overflow-x-auto">
                    <table className="w-full">
                      <thead>
                        <tr className="border-b border-border/50">
                          <th className="text-left text-sm font-medium text-muted-foreground pb-3">Type</th>
                          <th className="text-left text-sm font-medium text-muted-foreground pb-3">Date</th>
                          <th className="text-right text-sm font-medium text-muted-foreground pb-3">Amount</th>
                        </tr>
                      </thead>
                      <tbody>
                        {personalAnalytics.recent_transactions.slice(0, 8).map((activity: any) => (
                          <tr key={activity.id || activity.created_at || activity.date} className="border-b border-border/30">
                            <td className="py-3">
                              <div className="flex items-center gap-2">
                                <div className={`h-6 w-6 rounded-full flex items-center justify-center text-xs font-bold ${
                                  activity.type === 'transaction' ? 'bg-blue-100 text-blue-600' :
                                  activity.type === 'payment_request' ? 'bg-purple-100 text-purple-600' :
                                  activity.type === 'invoice' ? 'bg-orange-100 text-orange-600' :
                                  activity.type === 'topup' ? 'bg-green-100 text-green-600' :
                                  'bg-gray-100 text-gray-600'
                                }`}>
                                  {activity.type === 'transaction' ? 'T' : 
                                   activity.type === 'payment_request' ? 'R' : 
                                   activity.type === 'invoice' ? 'I' :
                                   activity.type === 'topup' ? '+' : '\u2022'}
                                </div>
                                <span className="text-sm font-medium capitalize">{activity?.type?.replace('_', ' ') || 'Activity'}</span>
                                {activity.type === 'transaction' && (
                                  <span className="rounded-md bg-secondary px-1.5 py-0.5 text-[10px] font-bold text-muted-foreground uppercase">
                                    {getPiCodeLabel(currency.code)}
                                  </span>
                                )}
                              </div>
                            </td>
                            <td className="py-3">
                              <span className="text-sm text-muted-foreground">
                                {new Date(activity.created_at || activity.date).toLocaleDateString()}
                              </span>
                            </td>
                            <td className="py-3 text-right">
                              <span className="text-sm font-semibold">
                                {(() => {
                                  if (activity.type === 'transaction') {
                                    const isOut = activity.sender_id === userId && !(activity.sender_id === activity.receiver_id && activity.receiver_id === userId);
                                    const amtRaw = isOut ? (activity.sender_amount ?? activity.amount) : (activity.receiver_amount ?? activity.amount);
                                    const amt = Number(amtRaw || 0);
                                    const code = String((isOut ? activity.sender_currency_code : activity.receiver_currency_code) || activity.currency_code || 'OUSD').toUpperCase();
                                    const ousdAmount = convertAmountToOusd(amt, code, currencies);
                                    const sign = isOut ? '-' : '+';
                                    return sign + formatCompactCurrency(ousdAmount);
                                  }
                                  return activity.amount ? formatCompactCurrency(activity.amount) : '-';
                                })()}
                              </span>

                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            </>
          ) : (
            <div className="paypal-surface rounded-3xl p-12">
              <div className="flex flex-col items-center justify-center text-center">
                <TrendingUp className="h-12 w-12 text-muted-foreground/50" />
                <p className="mt-4 text-lg font-semibold text-foreground">No analytics data available</p>
                <p className="mt-2 text-sm text-muted-foreground">Start using OpenPay to see your analytics here</p>
              </div>
            </div>
          )}
        </div>
      )}

      {activeSection === "wallet" && (
      <>
      <div className="mx-4 mt-4 rounded-3xl border border-white/30 bg-gradient-to-br from-paypal-blue to-[#0073e6] p-6 shadow-xl shadow-[#004bba]/25">
        <div className="mb-4 flex flex-wrap items-center gap-3">
          <div className="inline-flex rounded-full bg-white/15 p-1">
          <button
            type="button"
            onClick={() => setWalletView("personal")}
            className={`rounded-full px-3 py-1 text-xs font-semibold transition ${
              walletView === "personal" ? "bg-white text-paypal-blue" : "text-white/90 hover:bg-white/10"
            }`}
          >
            Personal wallet
          </button>
          <button
            type="button"
            onClick={() => setWalletView("merchant")}
            className={`rounded-full px-3 py-1 text-xs font-semibold transition ${
              walletView === "merchant" ? "bg-white text-paypal-blue" : "text-white/90 hover:bg-white/10"
            }`}
          >
            Merchant wallet
          </button>
          </div>
          <button
            type="button"
            onClick={() => setAmountFormat((prev) => (prev === "compact" ? "comma" : "compact"))}
            className="ml-auto rounded-full bg-white/15 px-3 py-1 text-xs font-semibold text-white hover:bg-white/25"
          >
            {amountFormat === "compact" ? "Compact" : "Comma"}
          </button>
        </div>

        {walletView === "merchant" && (
          <div className="mb-4 flex flex-wrap items-center gap-2">
            <div className="inline-flex rounded-full bg-white/15 p-1">
              <button
                type="button"
                onClick={() => setMerchantMode("sandbox")}
                className={`rounded-full px-3 py-1 text-xs font-semibold transition ${
                  merchantMode === "sandbox" ? "bg-white text-paypal-blue" : "text-white/90 hover:bg-white/10"
                }`}
              >
                Sandbox
              </button>
              <button
                type="button"
                onClick={() => setMerchantMode("live")}
                className={`rounded-full px-3 py-1 text-xs font-semibold transition ${
                  merchantMode === "live" ? "bg-white text-paypal-blue" : "text-white/90 hover:bg-white/10"
                }`}
              >
                Live
              </button>
            </div>
            <button
              type="button"
              onClick={() => setShowMerchantFeatures(true)}
              className="inline-flex items-center gap-1 rounded-full bg-white/15 px-3 py-1 text-xs font-semibold text-white transition hover:bg-white/25"
            >
              <Store className="h-3.5 w-3.5" />
              Merchant features
            </button>
          </div>
        )}

        <div className="flex items-center gap-3 text-white">
          <BrandLogo className="h-8 w-8" />
          <div>
            <p className="text-3xl font-bold">{balanceHidden ? "****" : formatCompactCurrency(walletCardAmount)}</p>
            <p className="text-sm text-white/85">
              {walletView === "personal"
                ? `Balance - ${currency.code === "PI" ? "PI" : piCurrencyLabel}`
                : `Merchant available (${merchantMode})`}
            </p>
          </div>
        </div>

        {walletView === "merchant" && (
          <div className="mt-4 grid gap-2 text-white/90 sm:grid-cols-3">
            <div className="rounded-xl bg-white/10 px-3 py-2">
              <p className="text-[11px] uppercase tracking-wide text-white/80">Incoming</p>
              <p className="text-sm font-semibold">{balanceHidden ? "****" : formatCompactCurrency(Number(selectedMerchantBalance?.gross_volume ?? 0))}</p>
            </div>
            <div className="rounded-xl bg-white/10 px-3 py-2">
              <p className="text-[11px] uppercase tracking-wide text-white/80">Refunded</p>
              <p className="text-sm font-semibold">{balanceHidden ? "****" : formatCompactCurrency(Number(selectedMerchantBalance?.refunded_total ?? 0))}</p>
            </div>
            <div className="rounded-xl bg-white/10 px-3 py-2">
              <p className="text-[11px] uppercase tracking-wide text-white/80">Transferred out</p>
              <p className="text-sm font-semibold">{balanceHidden ? "****" : formatCompactCurrency(Number(selectedMerchantBalance?.transferred_total ?? 0))}</p>
            </div>
          </div>
        )}

        <div className="mt-4 flex justify-end">
          <button
            type="button"
            onClick={toggleBalanceHidden}
            aria-label={balanceHidden ? "Show balance" : "Hide balance"}
            className="paypal-surface flex h-9 items-center gap-2 rounded-full px-3 text-sm font-semibold text-foreground"
          >
            {balanceHidden ? <Eye className="h-4 w-4" /> : <EyeOff className="h-4 w-4" />}
            {balanceHidden ? "Show balance" : "Hide balance"}
          </button>
        </div>
      </div>
      {walletView === "merchant" && (
        <div className="mx-4 mt-4 paypal-surface rounded-3xl p-4">
          <div className="grid gap-3 sm:grid-cols-2">
            <div className="rounded-2xl border border-border/70 p-3">
              <p className="mb-2 text-sm font-semibold">Move merchant balance to savings</p>
              <input
                value={formatAmountInput(merchantSavingsAmount)}
                onChange={(e) => setMerchantSavingsAmount(normalizeAmountInput(e.target.value))}
                type="text"
                inputMode="decimal"
                placeholder={`Amount (${currencyLabel})`}
                className="mb-2 h-10 w-full rounded-xl border border-border px-3"
              />
              <button
                disabled={movingMerchantToSavings}
                onClick={() => handleProtectedAction(handleMoveMerchantToSavings, "handleMoveMerchantToSavings")}
                className="h-10 w-full rounded-xl bg-paypal-blue text-sm font-semibold text-white"
              >
                {movingMerchantToSavings ? "Moving..." : "Move to Savings"}
              </button>
            </div>
            <div className="rounded-2xl border border-border/70 p-3">
              <p className="mb-2 text-sm font-semibold">Move merchant balance to wallet</p>
              <input
                value={formatAmountInput(merchantWithdrawAmount)}
                onChange={(e) => setMerchantWithdrawAmount(normalizeAmountInput(e.target.value))}
                type="text"
                inputMode="decimal"
                placeholder={`Amount (${currencyLabel})`}
                className="mb-2 h-10 w-full rounded-xl border border-border px-3"
              />
              <button
                disabled={movingMerchantToWallet}
                onClick={() => handleProtectedAction(handleMoveMerchantToWallet, "handleMoveMerchantToWallet")}
                className="h-10 w-full rounded-xl border border-paypal-blue/40 bg-white text-sm font-semibold text-paypal-blue"
              >
                {movingMerchantToWallet ? "Moving..." : "Move to Wallet"}
              </button>
            </div>
          </div>
          <div className="mt-4 rounded-2xl border border-border/70 p-3">
            <div className="mb-2 flex items-center justify-between">
              <p className="text-sm font-semibold">Recent merchant activity</p>
              {merchantActivity.length > 0 && <p className="text-xs text-muted-foreground">{merchantActivity.length} latest</p>}
            </div>
            {merchantActivity.length === 0 ? (
              <p className="py-3 text-sm text-muted-foreground">No merchant activity yet.</p>
            ) : (
              <div className="divide-y divide-border/70 rounded-xl border border-border/70">
                {merchantActivity.map((entry, index) => {
                  const isOutflow = ["refund", "transfer_to_wallet", "transfer_to_savings"].includes(entry.activity_type);
                  const label =
                    entry.activity_type === "payment"
                      ? "Merchant payment"
                      : entry.activity_type === "refund"
                        ? "Merchant refund"
                        : entry.activity_type === "transfer_to_wallet"
                          ? "Move merchant balance to wallet"
                          : entry.activity_type === "transfer_to_savings"
                            ? "Move merchant balance to savings"
                            : (entry?.activity_type || "Activity").replace(/_/g, " ");
                  const detailLine = entry.note || `${entry.status} - ${entry.source}`;
                  const previewDetail = detailLine ? toPreviewText(detailLine, 64) : "";
                  return (
                    <div key={entry.activity_id || index} className="flex flex-col gap-2 px-3 py-2.5 sm:flex-row sm:items-start sm:justify-between">
                      <div className="min-w-0 flex-1">
                        <div className="flex items-start justify-between gap-3 sm:justify-start">
                          <p className="text-sm font-medium text-foreground">{label}</p>
                          <p className={`text-sm font-semibold ${isOutflow ? "text-paypal-blue" : "text-paypal-success"} sm:hidden`}>
                            {balanceHidden ? "****" : `${isOutflow ? "-" : "+"}${formatCompactCurrency(entry.amount)}`}
                          </p>
                        </div>
                        <p className="text-xs text-muted-foreground">{entry.created_at ? format(new Date(entry.created_at), "MMM d, yyyy h:mm a") : "-"}</p>
                        {previewDetail && <p className="text-xs text-muted-foreground break-words">{previewDetail}</p>}
                      </div>
                      <p className={`hidden text-sm font-semibold sm:block ${isOutflow ? "text-paypal-blue" : "text-paypal-success"}`}>
                        {balanceHidden ? "****" : `${isOutflow ? "-" : "+"}${formatCompactCurrency(entry.amount)}`}
                      </p>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </div>
      )}

      {userAccount && (
        <div className="mx-4 mt-4 paypal-surface rounded-3xl p-4">
          <div className="flex min-w-0 flex-col items-start gap-3 sm:flex-row sm:justify-between">
            <div className="min-w-0 flex-1">
              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">OpenPay Account</p>
              <p className="mt-1 text-base font-bold text-foreground">{userAccount.account_name}</p>
              <p className="text-sm text-muted-foreground">@{userAccount.account_username}</p>
              <p className="mt-2 break-all text-sm font-mono text-foreground">{userAccount.account_number}</p>
            </div>
            <button
              type="button"
              onClick={copyAccountNumber}
              className="w-full rounded-xl border border-border/70 bg-white px-3 py-2 text-sm font-medium text-foreground transition hover:bg-secondary sm:w-auto"
            >
              <Copy className="mr-1 inline h-4 w-4" />
              Copy
            </button>
          </div>
          <div className="mt-3 flex gap-2">
            <button
              type="button"
              onClick={() => navigate("/virtual-card")}
              className="w-full rounded-xl bg-paypal-blue px-3 py-2 text-sm font-semibold text-white hover:bg-[#004dc5] sm:w-auto"
            >
              Open Virtual Card
            </button>
          </div>
        </div>
      )}

      {/* Analytics and Mining Cards */}
      <Collapsible 
        open={showShortcuts} 
        onOpenChange={setShowShortcuts}
        className="mx-4 mt-6"
      >
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2">
            <LayoutGrid className="h-5 w-5 text-paypal-blue" />
            <h2 className="text-lg font-bold text-paypal-dark">Quick Access</h2>
          </div>
          <CollapsibleTrigger asChild>
            <button className="flex h-8 w-8 items-center justify-center rounded-full bg-secondary/50 text-muted-foreground hover:bg-secondary transition-colors">
              {showShortcuts ? (
                <ChevronUp className="h-5 w-5" />
              ) : (
                <ChevronDown className="h-5 w-5" />
              )}
            </button>
          </CollapsibleTrigger>
        </div>
        <CollapsibleContent className="data-[state=closed]:animate-accordion-up data-[state=open]:animate-accordion-down overflow-hidden">
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
            {/* Personal Analytics */}
            <button
              onClick={() => setActiveSection("analytics")}
              className="paypal-surface flex flex-col items-center justify-center rounded-[2rem] p-4 text-center transition hover:scale-[1.02] active:scale-[0.98] border border-border/40"
            >
              <div className="mb-3 flex h-12 w-12 items-center justify-center rounded-2xl bg-blue-50">
                <TrendingUp className="h-6 w-6 text-blue-600" />
              </div>
              <p className="text-xs font-bold text-foreground">Analytics</p>
              <p className="mt-1 text-[10px] text-muted-foreground line-clamp-1">Wallet activity</p>
            </button>

            {/* Swap Withdrawal */}
            <button
              onClick={() => setActiveSection("swap")}
              className="paypal-surface flex flex-col items-center justify-center rounded-[2rem] p-4 text-center transition hover:scale-[1.02] active:scale-[0.98] border border-border/40"
            >
              <div className="mb-3 flex h-12 w-12 items-center justify-center rounded-2xl bg-indigo-50">
                <ArrowLeftRight className="h-6 w-6 text-indigo-600" />
              </div>
              <p className="text-xs font-bold text-foreground">Swap</p>
              <p className="mt-1 text-[10px] text-muted-foreground line-clamp-1">OUSD to PI</p>
            </button>

            {/* Mining */}
            <button
              onClick={() => navigate("/mining")}
              className="paypal-surface flex flex-col items-center justify-center rounded-[2rem] p-4 text-center transition hover:scale-[1.02] active:scale-[0.98] border border-border/40"
            >
              <div className="mb-3 flex h-12 w-12 items-center justify-center rounded-2xl bg-orange-50">
                <Pickaxe className={`h-6 w-6 text-orange-600 ${miningActive ? "animate-bounce-slow" : ""}`} />
              </div>
              <p className="text-xs font-bold text-foreground">Mining</p>
              <p className="mt-1 text-[10px] text-muted-foreground line-clamp-1">
                {miningActive ? "Session active" : "Earn rewards"}
              </p>
            </button>

            {/* Staking */}
            <button
              onClick={() => navigate("/staking")}
              className="paypal-surface flex flex-col items-center justify-center rounded-[2rem] p-4 text-center transition hover:scale-[1.02] active:scale-[0.98] border border-border/40"
            >
              <div className="mb-3 flex h-12 w-12 items-center justify-center rounded-2xl bg-green-50">
                <Coins className="h-6 w-6 text-green-600" />
              </div>
              <p className="text-xs font-bold text-foreground">Staking</p>
              <p className="mt-1 text-[10px] text-muted-foreground line-clamp-1">Earn yield</p>
            </button>

            {/* Affiliate */}
            <button
              onClick={() => navigate("/affiliate")}
              className="paypal-surface flex flex-col items-center justify-center rounded-[2rem] p-4 text-center transition hover:scale-[1.02] active:scale-[0.98] border border-border/40"
            >
              <div className="mb-3 flex h-12 w-12 items-center justify-center rounded-2xl bg-purple-50">
                <HandCoins className="h-6 w-6 text-purple-600" />
              </div>
              <p className="text-xs font-bold text-foreground">Affiliate</p>
              <p className="mt-1 text-[10px] text-muted-foreground line-clamp-1">Refer & Earn</p>
            </button>

            {/* Contacts */}
            <button
              onClick={() => navigate("/contacts")}
              className="paypal-surface flex flex-col items-center justify-center rounded-[2rem] p-4 text-center transition hover:scale-[1.02] active:scale-[0.98] border border-border/40"
            >
              <div className="mb-3 flex h-12 w-12 items-center justify-center rounded-2xl bg-pink-50">
                <Users className="h-6 w-6 text-pink-600" />
              </div>
              <p className="text-xs font-bold text-foreground">Contacts</p>
              <p className="mt-1 text-[10px] text-muted-foreground line-clamp-1">Manage network</p>
            </button>
          </div>
        </CollapsibleContent>
      </Collapsible>

      {remittanceUiEnabled && (
        <div className="mx-4 mt-4 grid gap-3 sm:grid-cols-3">
          <div className="paypal-surface rounded-2xl p-3">
            <p className="text-xs text-muted-foreground">Remittance fee income</p>
            <p className="mt-1 text-xl font-bold text-foreground">{balanceHidden ? "****" : formatCompactCurrency(remittanceFeeIncome)}</p>
          </div>
          <div className="paypal-surface rounded-2xl p-3">
            <p className="text-xs text-muted-foreground">This month</p>
            <p className="mt-1 text-xl font-bold text-foreground">{balanceHidden ? "****" : formatCompactCurrency(remittanceMonthIncome)}</p>
          </div>
          <button
            onClick={() => navigate("/remittance-merchant")}
            className="paypal-surface rounded-2xl p-3 text-left transition hover:bg-secondary/50"
          >
            <p className="text-xs text-muted-foreground">Remittance records</p>
            <p className="mt-1 text-xl font-bold text-foreground">{remittanceTxCount}</p>
            <p className="text-xs font-medium text-paypal-blue">Manage center</p>
          </button>
        </div>
      )}

      <div className="mt-6 px-4">
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-xl font-bold text-paypal-dark">Recent activity</h2>
          <button onClick={() => navigate("/activity")} className="text-sm font-semibold text-paypal-blue">See more</button>
        </div>

        {transactions.length === 0 ? (
          <p className="py-8 text-center text-muted-foreground">No transactions yet</p>
        ) : (
          <div className="paypal-surface divide-y divide-border/70 rounded-3xl">
            {transactions.map((tx) => (
                            <button key={tx.id} onClick={() => showReceipt(tx)} className="flex w-full items-center justify-between p-4 text-left hover:bg-secondary/40 transition">
                <div className="flex items-center gap-3">
                  <div className="relative h-10 w-10">
                    <div className="flex h-10 w-10 items-center justify-center rounded-full border border-paypal-light-blue/50 bg-secondary">
                      <span className="text-xs font-bold text-secondary-foreground">
                        {getInitials(tx.other_name || "Unknown")}
                      </span>
                    </div>
                    {tx.other_avatar_url ? (
                      <img
                        src={tx.other_avatar_url}
                        alt={tx.other_name || "Profile"}
                        className="absolute inset-0 h-full w-full rounded-full border border-paypal-light-blue/50 object-cover"
                        onError={(e) => {
                          e.currentTarget.style.display = "none";
                        }}
                      />
                    ) : null}
                  </div>
                  <div>
                    <p className="font-semibold text-foreground">{tx.other_name}</p>
                    {tx.other_username && <p className="text-xs text-muted-foreground">@{tx.other_username}</p>}
                    <p className="text-xs text-muted-foreground">{format(new Date(tx.created_at), "MMM d, yyyy")}</p>
                    <p className="text-xs text-muted-foreground">
                      {tx.is_topup ? "Buy" : tx.is_sent ? "Payment" : "Received"}
                    </p>
                    {tx.note && <p className="text-xs text-muted-foreground">{toPreviewText(tx.note)}</p>}
                  </div>
                </div>
                <div className="text-right">
                  <p className={`font-semibold ${tx.is_sent && !tx.is_topup ? "text-red-500" : "text-paypal-success"}`}>
                    {balanceHidden ? "****" : (() => {
                      const isOut = tx.is_sent && !tx.is_topup;
                      const amtRaw = isOut ? (tx.sender_amount ?? tx.amount) : (tx.receiver_amount ?? tx.amount);
                      const amt = Number(amtRaw || 0);
                      const code = String((isOut ? tx.sender_currency_code : tx.receiver_currency_code) || tx.currency_code || 'OUSD').toUpperCase();
                      const ousdAmount = convertAmountToOusd(amt, code, currencies);
                      const sign = isOut ? '-' : '+';
                      return sign + formatCompactCurrency(ousdAmount);
                    })()}
                  </p>
                  <p className="text-[10px] text-muted-foreground uppercase font-semibold">
                    {getPiCodeLabel(currency.code)}
                  </p>
                </div>
              </button>
            ))}
          </div>
        )}
      </div>

      </>
      )}

      <div className="fixed bottom-24 left-0 right-0 z-40 overflow-x-hidden px-4 pb-1">
        <div className="flex gap-3">
          <button
            onClick={() => navigate("/contacts")}
            className="flex h-[54px] w-[54px] items-center justify-center rounded-full border border-paypal-blue/25 bg-white text-paypal-blue"
            aria-label="Open contacts"
          >
            <Users className="h-6 w-6" />
          </button>
          <button onClick={() => navigate("/send")} className="min-w-0 flex-1 rounded-full bg-paypal-blue py-3.5 text-center text-sm font-semibold text-white shadow-lg shadow-[#0057d8]/30">Pay</button>
          <button onClick={() => setShowReceiveOptions(true)} className="min-w-0 flex-1 rounded-full border border-paypal-blue/25 bg-white py-3.5 text-center text-sm font-semibold text-paypal-blue">Receive</button>
          <button onClick={openBuyOptions} className="min-w-0 flex-1 rounded-full border border-paypal-blue/25 bg-white py-3.5 text-center text-sm font-semibold text-paypal-blue">Buy</button>
        </div>
      </div>

      <BottomNav active="home" />
      <TransactionReceipt open={receiptOpen} onOpenChange={setReceiptOpen} receipt={receiptData} />

      <Dialog open={showReceiveOptions} onOpenChange={setShowReceiveOptions}>
        <DialogContent className="top-auto bottom-0 translate-y-0 rounded-b-none rounded-t-3xl px-5 pb-7 pt-5 sm:max-w-lg data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=open]:slide-in-from-bottom-8 data-[state=closed]:slide-out-to-bottom-8 data-[state=open]:fade-in-0 data-[state=closed]:fade-out-0">
          <DialogTitle className="text-center text-2xl font-bold text-foreground">Ways to get paid</DialogTitle>
          <DialogDescription className="text-center text-sm text-muted-foreground">
            Choose how you want to receive payment.
          </DialogDescription>
          <div className="mt-3 grid grid-cols-3 gap-3">
            <button
              onClick={() => {
                setShowReceiveOptions(false);
                navigate("/receive");
              }}
              className="rounded-2xl border border-border/70 bg-secondary/50 p-3 text-center transition hover:bg-secondary"
            >
              <div className="mx-auto mb-2 flex h-11 w-11 items-center justify-center rounded-full bg-white">
                <QrCode className="h-5 w-5 text-paypal-blue" />
              </div>
              <p className="text-sm font-semibold text-foreground">Receive</p>
            </button>
            <button
              onClick={() => {
                setShowReceiveOptions(false);
                navigate("/request-payment");
              }}
              className="rounded-2xl border border-border/70 bg-secondary/50 p-3 text-center transition hover:bg-secondary"
            >
              <div className="relative mx-auto mb-2 flex h-11 w-11 items-center justify-center rounded-full bg-white">
                <CircleDollarSign className="h-5 w-5 text-paypal-blue" />
                {pendingRequestCount > 0 && (
                  <span className="absolute -right-1 -top-1 min-w-[16px] rounded-full bg-red-500 px-1 text-[10px] font-bold leading-4 text-white">
                    {Math.min(pendingRequestCount, 99)}
                  </span>
                )}
              </div>
              <p className="text-sm font-semibold text-foreground">Request</p>
            </button>
            <button
              onClick={() => {
                setShowReceiveOptions(false);
                navigate("/send-invoice");
              }}
              className="rounded-2xl border border-border/70 bg-secondary/50 p-3 text-center transition hover:bg-secondary"
            >
              <div className="relative mx-auto mb-2 flex h-11 w-11 items-center justify-center rounded-full bg-white">
                <FileText className="h-5 w-5 text-paypal-blue" />
                {pendingInvoiceCount > 0 && (
                  <span className="absolute -right-1 -top-1 min-w-[16px] rounded-full bg-red-500 px-1 text-[10px] font-bold leading-4 text-white">
                    {Math.min(pendingInvoiceCount, 99)}
                  </span>
                )}
              </div>
              <p className="text-sm font-semibold text-foreground">Invoice</p>
            </button>
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={showBuyOptions} onOpenChange={setShowBuyOptions}>
        <DialogContent className="top-auto bottom-0 translate-y-0 rounded-b-none rounded-t-3xl px-5 pb-7 pt-5 sm:max-w-lg data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=open]:slide-in-from-bottom-8 data-[state=closed]:slide-out-to-bottom-8 data-[state=open]:fade-in-0 data-[state=closed]:fade-out-0">
          <DialogTitle className="text-center text-2xl font-bold text-foreground">Buy Options</DialogTitle>
          <DialogDescription className="text-center text-sm text-muted-foreground">
            Choose how you want to get OpenUSD.
          </DialogDescription>
          <div className="mt-3 grid grid-cols-2 gap-3">
            <button
              onClick={() => {
                setShowBuyOptions(false);
                setActiveSection("buy");
              }}
              className="rounded-2xl border border-border/70 bg-secondary/50 p-3 text-center transition hover:bg-secondary"
            >
              <div className="mx-auto mb-2 flex h-11 w-11 items-center justify-center rounded-full bg-white">
                <CircleDollarSign className="h-5 w-5 text-paypal-blue" />
              </div>
              <p className="text-sm font-semibold text-foreground">Top Up</p>
              <p className="text-xs text-muted-foreground">Buy OpenUSD</p>
            </button>
            <button
              onClick={() => {
                setShowBuyOptions(false);
                setActiveSection("mining");
              }}
              className="rounded-2xl border border-border/70 bg-secondary/50 p-3 text-center transition hover:bg-secondary"
            >
              <div className="mx-auto mb-2 flex h-11 w-11 items-center justify-center rounded-full bg-white">
                <Pickaxe className="h-5 w-5 text-paypal-blue" />
              </div>
              <p className="text-sm font-semibold text-foreground">Mining</p>
              <p className="text-xs text-muted-foreground">Earn OpenUSD</p>
            </button>
            <button
              onClick={() => {
                setShowBuyOptions(false);
                navigate("/staking");
              }}
              className="rounded-2xl border border-border/70 bg-secondary/50 p-3 text-center transition hover:bg-secondary"
            >
              <div className="mx-auto mb-2 flex h-11 w-11 items-center justify-center rounded-full bg-white">
                <Coins className="h-5 w-5 text-paypal-blue" />
              </div>
              <p className="text-sm font-semibold text-foreground">Staking</p>
              <p className="text-xs text-muted-foreground">Earn Yield</p>
            </button>
            <button
              onClick={() => {
                setShowBuyOptions(false);
                setActiveSection("swap");
              }}
              className="rounded-2xl border border-border/70 bg-secondary/50 p-3 text-center transition hover:bg-secondary"
            >
              <div className="mx-auto mb-2 flex h-11 w-11 items-center justify-center rounded-full bg-white">
                <ArrowLeftRight className="h-5 w-5 text-paypal-blue" />
              </div>
              <p className="text-sm font-semibold text-foreground">Swap</p>
              <p className="text-xs text-muted-foreground">OUSD to PI</p>
            </button>
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={showMerchantFeatures} onOpenChange={setShowMerchantFeatures}>
        <DialogContent className="rounded-3xl sm:max-w-md">
          <DialogTitle className="text-xl font-bold text-foreground">Merchant features</DialogTitle>
          <DialogDescription className="text-sm text-muted-foreground">
            Open merchant tools quickly from dashboard.
          </DialogDescription>
          <div className="mt-2 grid gap-2">
            <Button
              type="button"
              variant="outline"
              className="h-11 justify-start rounded-xl"
              onClick={() => {
                setShowMerchantFeatures(false);
                navigate("/merchant-onboarding");
              }}
            >
              Merchant Portal
            </Button>
            <Button
              type="button"
              variant="outline"
              className="h-11 justify-start rounded-xl"
              onClick={() => {
                setShowMerchantFeatures(false);
                navigate("/merchant-pos");
              }}
            >
              POS
            </Button>
            <Button
              type="button"
              variant="outline"
              className="h-11 justify-start rounded-xl"
              onClick={() => {
                setShowMerchantFeatures(false);
                navigate("/payment-links/create");
              }}
            >
              Checkout Link
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={showOnrampPicker} onOpenChange={setShowOnrampPicker}>
        <DialogContent className="top-auto bottom-0 max-h-[85vh] translate-y-0 overflow-y-auto rounded-b-none rounded-t-3xl px-5 pb-7 pt-5 sm:max-w-lg">
          <DialogTitle className="text-center text-2xl font-bold text-foreground">Choose onramp</DialogTitle>
          <DialogDescription className="text-center text-sm text-muted-foreground">
            Select the provider for your OpenUSD buy quote.
          </DialogDescription>
          <p className="mt-1 text-center text-xs font-medium text-foreground">
            Conversion: 1 OPEN USD = {OUSD_TO_PI.toFixed(5)} PI
          </p>
          <div className="mt-3 space-y-3">
            {onrampRows.map((row) => {
              const targetOpenUsdAmount = buyOpenUsdAmount > 0 ? buyOpenUsdAmount : 0;
              const usdOnrampProviders: BuyOnrampProvider[] = [
                "PayPal",
                "Apple Pay",
                "Debit Card",
                "Credit Card",
                "Google Pay",
                "Stripe",
                "Venmo",
              ];
              const quoteLabel =
                row.key === "Ewallet QR PH"
                  ? `${(targetOpenUsdAmount * E_WALLET_PHP_PER_OUSD).toFixed(2)} PHP`
                  : row.key === "USDT"
                    ? `${targetOpenUsdAmount.toFixed(2)} USDT`
                    : row.key === "USDC"
                      ? `${targetOpenUsdAmount.toFixed(2)} USDC`
                      : row.key === "Solana Pay"
                        ? `${targetOpenUsdAmount.toFixed(2)} USDC`
                  : usdOnrampProviders.includes(row.key)
                    ? `${targetOpenUsdAmount.toFixed(2)} USD`
                    : `${(targetOpenUsdAmount * OUSD_TO_PI).toFixed(5)} PI`;
              const selected = buyOnrampProvider === row.key;
              return (
                <button
                  key={row.key}
                  type="button"
                  disabled={row.disabled}
                  onClick={() => {
                    if (row.disabled) return;
                    setBuyOnrampProvider(row.key);
                    if (row.key === "Ewallet QR PH") {
                      setBuyPaymentMethod("Ewallet");
                    } else if (row.key === "USDT") {
                      setBuyPaymentMethod("USDT");
                    } else if (row.key === "USDC") {
                      setBuyPaymentMethod("USDC");
                    } else if (row.key === "Solana Pay") {
                      setBuyPaymentMethod("Solana Pay");
                    } else if (row.key === "Pi Payment") {
                      setBuyPaymentMethod("Pi Payment");
                    } else if (row.key === "PayPal") {
                      setBuyPaymentMethod("PayPal");
                    } else if (row.key === "Apple Pay") {
                      setBuyPaymentMethod("Apple Pay");
                    } else if (row.key === "Debit Card") {
                      setBuyPaymentMethod("Debit Card");
                    } else if (row.key === "Credit Card") {
                      setBuyPaymentMethod("Credit Card");
                    } else if (row.key === "Google Pay") {
                      setBuyPaymentMethod("Google Pay");
                    } else if (row.key === "Stripe") {
                      setBuyPaymentMethod("Stripe");
                    } else if (row.key === "Venmo") {
                      setBuyPaymentMethod("Venmo");
                    }
                    setShowOnrampPicker(false);
                  }}
                  className={`w-full rounded-2xl border px-4 py-3 text-left transition ${
                    row.disabled
                      ? "border-border/50 bg-secondary/40 text-muted-foreground"
                      : selected
                        ? "border-paypal-blue/50 bg-white"
                        : "border-border/70 bg-secondary/20 hover:bg-secondary/40"
                  }`}
                >
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <p className="inline-flex items-center gap-2 text-2xl font-semibold text-foreground">
                        {row.key === "Pi Payment" && (
                          <img src={PI_PAYMENT_ICON_URL} alt="Pi Payment" className="h-10 w-auto object-contain" />
                        )}
                        {row.key === "Ewallet QR PH" && (
                          <img src={JQRPH_ICON_URL} alt="JQRPh" className="h-6 w-auto object-contain" />
                        )}
                        {row.key === "PayPal" && (
                          <img src={PAYPAL_ICON_URL} alt="PayPal" className="h-6 w-auto object-contain" />
                        )}
                        {row.key === "USDT" && (
                          <img src={USDT_ICON_URL} alt="USDT" className="h-6 w-auto object-contain" />
                        )}
                        {row.key === "USDC" && (
                          <img src={USDC_ICON_URL} alt="USDC" className="h-6 w-auto object-contain" />
                        )}
                        {row.key === "Solana Pay" && (
                          <img src={SOLANA_PAY_ICON_URL} alt="Solana Pay" className="h-6 w-auto object-contain" />
                        )}
                        {row.key === "Apple Pay" && (
                          <img src={APPLE_PAY_ICON_URL} alt="Apple Pay" className="h-6 w-auto object-contain" />
                        )}
                        {row.key === "Google Pay" && (
                          <img src={GOOGLE_PAY_ICON_URL} alt="Google Pay" className="h-6 w-auto object-contain" />
                        )}
                        {row.key === "Debit Card" && (
                          <img src={VISA_ICON_URL} alt="Visa" className="h-6 w-auto object-contain" />
                        )}
                        {row.key === "Credit Card" && (
                          <img src={MASTERCARD_ICON_URL} alt="Mastercard" className="h-6 w-auto object-contain" />
                        )}
                        {row.key === "Stripe" && (
                          <img src={STRIPE_ICON_URL} alt="Stripe" className="h-6 w-auto object-contain" />
                        )}
                        {row.key === "Venmo" && (
                          <img src={VENMO_ICON_URL} alt="Venmo" className="h-5 w-auto object-contain" />
                        )}
                        {row.key === "TransFi" && (
                          <img
                            src={TRANSFI_ICON_URL}
                            alt="TransFi"
                            className="h-5 w-auto object-contain"
                            onError={(e) => {
                              e.currentTarget.style.display = "none";
                            }}
                          />
                        )}
                        {row.key === "Onramp Money" && (
                          <img
                            src={ONRAMP_MONEY_ICON_URL}
                            alt="Onramp Money"
                            className="h-5 w-auto object-contain"
                            onError={(e) => {
                              e.currentTarget.style.display = "none";
                            }}
                          />
                        )}
                        {row.key === "Banxa" && (
                          <img
                            src={BANXA_ICON_URL}
                            alt="Banxa"
                            className="h-5 w-auto object-contain"
                            onError={(e) => {
                              e.currentTarget.style.display = "none";
                            }}
                          />
                        )}
                        {row.key}
                      </p>
                      <div className="flex flex-wrap items-center gap-2">
                        <p className="text-sm text-muted-foreground">{row.subtitle}</p>
                        {row.recommended && (
                          <span className="rounded-md bg-paypal-blue/10 px-2 py-0.5 text-xs font-semibold text-paypal-blue">
                            Recommended
                          </span>
                        )}
                      </div>
                    </div>
                    <div className="text-right">
                      {!row.disabled && <p className="text-3xl font-semibold text-foreground">{quoteLabel}</p>}
                      {row.delta && <p className="text-sm font-semibold text-red-500">{row.delta}</p>}
                      {!row.disabled && selected && <Check className="ml-auto mt-1 h-4 w-4 text-paypal-blue" />}
                    </div>
                  </div>
                </button>
              );
            })}
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={showPaymentMethodPicker} onOpenChange={setShowPaymentMethodPicker}>
        <DialogContent className="top-auto bottom-0 translate-y-0 rounded-b-none rounded-t-3xl px-5 pb-7 pt-5 sm:max-w-lg">
          <DialogTitle className="text-center text-2xl font-bold text-foreground">Choose payment method</DialogTitle>
          <DialogDescription className="text-center text-sm text-muted-foreground">
            PI to OpenUSD buy.
          </DialogDescription>
          <div className="mt-3 space-y-2">
            {paymentMethodRows.map((row) => {
              const selected = buyPaymentMethod === row.key;
              const disabled = row.disabled ?? !supportedBuyPaymentMethods.includes(row.key);
              return (
                <button
                  key={row.key}
                  type="button"
                  disabled={disabled}
                  onClick={() => {
                    if (disabled) return;
                    setBuyPaymentMethod(row.key);
                    if (row.key === "Ewallet") {
                      setBuyOnrampProvider("Ewallet QR PH");
                    } else if (row.key === "USDT") {
                      setBuyOnrampProvider("USDT");
                    } else if (row.key === "USDC") {
                      setBuyOnrampProvider("USDC");
                    } else if (row.key === "Solana Pay") {
                      setBuyOnrampProvider("Solana Pay");
                    } else if (row.key === "Pi Payment") {
                      setBuyOnrampProvider("Pi Payment");
                    } else if (row.key === "PayPal") {
                      setBuyOnrampProvider("PayPal");
                    } else if (row.key === "Apple Pay") {
                      setBuyOnrampProvider("Apple Pay");
                    } else if (row.key === "Debit Card") {
                      setBuyOnrampProvider("Debit Card");
                    } else if (row.key === "Credit Card") {
                      setBuyOnrampProvider("Credit Card");
                    } else if (row.key === "Google Pay") {
                      setBuyOnrampProvider("Google Pay");
                    } else if (row.key === "Stripe") {
                      setBuyOnrampProvider("Stripe");
                    } else if (row.key === "Venmo") {
                      setBuyOnrampProvider("Venmo");
                    }
                    setShowPaymentMethodPicker(false);
                  }}
                  className={`flex h-14 w-full items-center justify-between rounded-2xl border px-4 ${
                    disabled
                      ? "border-border/60 bg-secondary/30 text-muted-foreground"
                      : "border-border/70 bg-white hover:bg-secondary/20"
                  }`}
                >
                  <span className="inline-flex items-center gap-2 text-base font-semibold">
                    {row.key === "Pi Payment" && (
                      <img src={PI_PAYMENT_ICON_URL} alt="Pi Payment" className="h-9 w-auto object-contain" />
                    )}
                    {row.key === "Ewallet" && (
                      <img src={JQRPH_ICON_URL} alt="JQRPh" className="h-5 w-auto object-contain" />
                    )}
                    {row.key === "PayPal" && (
                      <img src={PAYPAL_ICON_URL} alt="PayPal" className="h-5 w-auto object-contain" />
                    )}
                    {row.key === "USDT" && (
                      <img src={USDT_ICON_URL} alt="USDT" className="h-5 w-auto object-contain" />
                    )}
                    {row.key === "USDC" && (
                      <img src={USDC_ICON_URL} alt="USDC" className="h-5 w-auto object-contain" />
                    )}
                    {row.key === "Solana Pay" && (
                      <img src={SOLANA_PAY_ICON_URL} alt="Solana Pay" className="h-5 w-auto object-contain" />
                    )}
                    {row.key === "Apple Pay" && (
                      <img src={APPLE_PAY_ICON_URL} alt="Apple Pay" className="h-5 w-auto object-contain" />
                    )}
                    {row.key === "Google Pay" && (
                      <img src={GOOGLE_PAY_ICON_URL} alt="Google Pay" className="h-5 w-auto object-contain" />
                    )}
                    {row.key === "Debit Card" && (
                      <img src={VISA_ICON_URL} alt="Visa" className="h-5 w-auto object-contain" />
                    )}
                    {row.key === "Credit Card" && (
                      <img src={MASTERCARD_ICON_URL} alt="Mastercard" className="h-5 w-auto object-contain" />
                    )}
                    {row.key === "Stripe" && (
                      <img src={STRIPE_ICON_URL} alt="Stripe" className="h-5 w-auto object-contain" />
                    )}
                    {row.key === "Venmo" && (
                      <img src={VENMO_ICON_URL} alt="Venmo" className="h-5 w-auto object-contain" />
                    )}
                    {getBuyPaymentMethodLabel(row.key)}
                  </span>
                  <div className="flex items-center gap-2">
                    {row.recommended && <span className="rounded-md bg-paypal-blue/10 px-2 py-0.5 text-xs font-semibold text-paypal-blue">Recommended</span>}
                    {selected && <Check className="h-5 w-5 text-paypal-blue" />}
                  </div>
                </button>
              );
            })}
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={showAgreement} onOpenChange={() => undefined}>
        <DialogContent className="rounded-3xl sm:max-w-md">
          <DialogTitle className="text-xl font-bold text-foreground">Platform, User, and Merchant Protection Agreement</DialogTitle>
          <DialogDescription className="text-sm text-muted-foreground">
            OpenPay is designed for Pi-powered internal balance transfers. By continuing, you agree to use OpenPay only under the protection rules below.
          </DialogDescription>
          <div className="rounded-2xl border border-border/70 p-3 text-sm text-foreground">
            <p>1. Use OpenPay only to transfer OpenPay balance backed by Pi.</p>
            <p>2. Do not use OpenPay for external wallet transfers or non-Pi crypto assets.</p>
            <p>3. Verify recipient and merchant details before every payment.</p>
            <p>4. Merchants must disclose any deposit/payout exchange fee before transaction confirmation.</p>
            <p>5. Users and merchants must not use OpenPay for fraud, abuse, or illegal transactions.</p>
            <p>6. Keep your account and security settings protected at all times.</p>
          </div>
          <label className="flex items-start gap-2 text-sm text-foreground">
            <input
              type="checkbox"
              checked={agreementChecked}
              onChange={(e) => setAgreementChecked(e.target.checked)}
              className="mt-1"
            />
            I agree to the OpenPay Platform, User, and Merchant Protection Agreement, including Pi-only internal OpenPay transfer rules.
          </label>
          <div className="flex items-center justify-between text-xs">
            <Link to="/terms" className="font-medium text-paypal-blue">Terms</Link>
            <Link to="/privacy" className="font-medium text-paypal-blue">Privacy</Link>
            <Link to="/legal" className="font-medium text-paypal-blue">Legal</Link>
          </div>
          <Button
            className="h-11 w-full rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5]"
            disabled={!agreementChecked}
            onClick={handleAcceptAgreement}
          >
            Accept and Continue
          </Button>
        </DialogContent>
      </Dialog>

      <Dialog open={showOnboarding} onOpenChange={setShowOnboarding}>
        <DialogContent className="rounded-3xl sm:max-w-md">
          <div className="mb-1 text-xs font-semibold uppercase tracking-wide text-paypal-blue">
            Step {onboardingStep + 1} of {onboardingSteps.length}
          </div>
          <DialogTitle className="text-xl font-bold text-foreground">
            {onboardingSteps[Math.min(Math.max(onboardingStep, 0), onboardingSteps.length - 1)].title}
          </DialogTitle>
          <DialogDescription className="text-sm text-muted-foreground">
            {onboardingSteps[Math.min(Math.max(onboardingStep, 0), onboardingSteps.length - 1)].description}
          </DialogDescription>

          <div className="mt-3 flex gap-1.5">
            {onboardingSteps.map((_, index) => (
              <div
                key={index}
                className={`h-1.5 flex-1 rounded-full ${index <= onboardingStep ? "bg-paypal-blue" : "bg-border"}`}
              />
            ))}
          </div>

          <div className="mt-2 rounded-2xl border border-border/70 p-3 text-sm text-muted-foreground">
            Pro tip: you can revisit support and usage guidance anytime from Menu.
          </div>

          <div className="flex gap-2">
            <Button variant="outline" className="h-11 flex-1 rounded-2xl" onClick={completeOnboarding}>
              Skip
            </Button>
            {onboardingStep < onboardingSteps.length - 1 ? (
              <Button
                className="h-11 flex-1 rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5]"
                onClick={() => {
                  const nextStep = onboardingStep + 1;
                  setOnboardingStep(nextStep);
                  if (userId) upsertUserPreferences(userId, { onboarding_step: nextStep }).catch(() => undefined);
                }}
              >
                Next
              </Button>
            ) : (
              <Button
                className="h-11 flex-1 rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5]"
                onClick={completeOnboarding}
              >
                Finish
              </Button>
            )}
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default Dashboard;
