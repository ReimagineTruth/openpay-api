import { useEffect, useMemo, useState } from "react";
import { useNavigate, useParams, useSearchParams } from "react-router-dom";
import { ChevronDown, CreditCard, HelpCircle, LockKeyhole, QrCode, ShoppingCart, WalletCards, X } from "lucide-react";
import { toast } from "sonner";
import { QRCodeSVG } from "qrcode.react";

import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { PI_TO_USD, useCurrency } from "@/contexts/CurrencyContext";
import { supabase } from "@/integrations/supabase/client";
import { getFunctionErrorMessage } from "@/lib/supabaseFunctionError";
import SplashScreen from "@/components/SplashScreen";
import BrandLogo from "@/components/BrandLogo";

type CheckoutSessionPublic = {
  session_id: string;
  status: "open" | "paid" | "expired" | "canceled";
  mode: "sandbox" | "live";
  currency: string;
  amount: number;
  subtotal_amount?: number;
  fee_amount?: number;
  fee_payer?: "customer" | "merchant";
  merchant_settlement_amount?: number;
  expires_at: string;
  merchant_user_id: string;
  merchant_name: string;
  merchant_username: string;
  merchant_logo_url: string | null;
  items: Array<{
    item_name: string;
    quantity: number;
    unit_amount: number;
    line_total: number;
    item_image_url?: string | null;
    item_images?: string[] | null;
  }>;
};

type PaymentLinkSessionCreate = {
  session_id: string;
  session_token: string;
  total_amount: number;
  currency: string;
  expires_at: string;
  after_payment_type: "confirmation" | "redirect";
  confirmation_message: string;
  redirect_url: string | null;
  call_to_action: string;
};
const PURE_PI_ICON_URL = "https://i.ibb.co/BV8PHjB4/Pi-200x200.png";
const OPENPAY_ICON_URL = "/openpay-logo.jpg";

const COUNTRIES: string[] = [
  "Afghanistan", "Albania", "Algeria", "Andorra", "Angola", "Antigua and Barbuda", "Argentina", "Armenia", "Australia", "Austria",
  "Azerbaijan", "Bahamas", "Bahrain", "Bangladesh", "Barbados", "Belarus", "Belgium", "Belize", "Benin", "Bhutan",
  "Bolivia", "Bosnia and Herzegovina", "Botswana", "Brazil", "Brunei", "Bulgaria", "Burkina Faso", "Burundi", "Cabo Verde", "Cambodia",
  "Cameroon", "Canada", "Central African Republic", "Chad", "Chile", "China", "Colombia", "Comoros", "Congo", "Costa Rica",
  "Cote d'Ivoire", "Croatia", "Cuba", "Cyprus", "Czech Republic", "Democratic Republic of the Congo", "Denmark", "Djibouti", "Dominica", "Dominican Republic",
  "Ecuador", "Egypt", "El Salvador", "Equatorial Guinea", "Eritrea", "Estonia", "Eswatini", "Ethiopia", "Fiji", "Finland",
  "France", "Gabon", "Gambia", "Georgia", "Germany", "Ghana", "Greece", "Grenada", "Guatemala", "Guinea",
  "Guinea-Bissau", "Guyana", "Haiti", "Honduras", "Hungary", "Iceland", "India", "Indonesia", "Iran", "Iraq",
  "Ireland", "Israel", "Italy", "Jamaica", "Japan", "Jordan", "Kazakhstan", "Kenya", "Kiribati", "Kuwait",
  "Kyrgyzstan", "Laos", "Latvia", "Lebanon", "Lesotho", "Liberia", "Libya", "Liechtenstein", "Lithuania", "Luxembourg",
  "Madagascar", "Malawi", "Malaysia", "Maldives", "Mali", "Malta", "Marshall Islands", "Mauritania", "Mauritius", "Mexico",
  "Micronesia", "Moldova", "Monaco", "Mongolia", "Montenegro", "Morocco", "Mozambique", "Myanmar", "Namibia", "Nauru",
  "Nepal", "Netherlands", "New Zealand", "Nicaragua", "Niger", "Nigeria", "North Korea", "North Macedonia", "Norway", "Oman",
  "Pakistan", "Palau", "Palestine", "Panama", "Papua New Guinea", "Paraguay", "Peru", "Philippines", "Poland", "Portugal",
  "Qatar", "Romania", "Russia", "Rwanda", "Saint Kitts and Nevis", "Saint Lucia", "Saint Vincent and the Grenadines", "Samoa", "San Marino", "Sao Tome and Principe",
  "Saudi Arabia", "Senegal", "Serbia", "Seychelles", "Sierra Leone", "Singapore", "Slovakia", "Slovenia", "Solomon Islands", "Somalia",
  "South Africa", "South Korea", "South Sudan", "Spain", "Sri Lanka", "Sudan", "Suriname", "Sweden", "Switzerland", "Syria",
  "Taiwan", "Tajikistan", "Tanzania", "Thailand", "Timor-Leste", "Togo", "Tonga", "Trinidad and Tobago", "Tunisia", "Turkey",
  "Turkmenistan", "Tuvalu", "Uganda", "Ukraine", "United Arab Emirates", "United Kingdom", "United States", "Uruguay", "Uzbekistan", "Vanuatu",
  "Vatican City", "Venezuela", "Vietnam", "Yemen", "Zambia", "Zimbabwe",
];

const MerchantCheckoutPage = () => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const db = supabase as any;
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { token: pathToken } = useParams();
  const { currencies, currency: dashboardCurrency } = useCurrency();

  const rawSessionToken = searchParams.get("session") || searchParams.get("session_token") || "";
  const paymentLinkToken = pathToken || searchParams.get("payment_link") || searchParams.get("link") || "";

  const [viewerEmail, setViewerEmail] = useState("");

  const [sessionData, setSessionData] = useState<CheckoutSessionPublic | null>(null);
  const [linkSessionMeta, setLinkSessionMeta] = useState<PaymentLinkSessionCreate | null>(null);
  const [resolvedSessionToken, setResolvedSessionToken] = useState(rawSessionToken);
  const [loadingSession, setLoadingSession] = useState(false);

  const [customerName, setCustomerName] = useState("");
  const [customerEmail, setCustomerEmail] = useState("");
  const [customerPhone, setCustomerPhone] = useState("");
  const [customerAddress, setCustomerAddress] = useState("");

  const [paying, setPaying] = useState(false);

  const [cardNumber, setCardNumber] = useState("");
  const [cardExpiryMonth, setCardExpiryMonth] = useState("");
  const [cardExpiryYear] = useState("");
  const [cardCvc, setCardCvc] = useState("");
  const [paymentMethod, setPaymentMethod] = useState<"card" | "openpay_wallet">("card");
  const [country, setCountry] = useState("United States");
  const [payCurrencyCode, setPayCurrencyCode] = useState("PI");
  const [promoOptIn, setPromoOptIn] = useState(false);
  const [showProductDetails, setShowProductDetails] = useState(false);
  const [showInstructions, setShowInstructions] = useState(false);

  const legacyMerchantId = searchParams.get("merchantId") || "";
  const legacyProductName = searchParams.get("productName") || "Merchant product";
  const legacyProductDescription = searchParams.get("description") || "";
  const legacyAmount = Number(searchParams.get("amount") || "0");
  const legacyCurrency = (searchParams.get("currency") || "USD").toUpperCase();
  const legacyMerchantName = searchParams.get("merchantName") || "";
  const checkoutStatus = (searchParams.get("status") || "").toLowerCase();
  const returnedTxId = searchParams.get("tx") || "";
  const checkoutCustomerName = searchParams.get("checkout_customer_name") || "";
  const checkoutCustomerEmail = searchParams.get("checkout_customer_email") || "";
  const checkoutCustomerPhone = searchParams.get("checkout_customer_phone") || "";
  const checkoutCustomerAddress = searchParams.get("checkout_customer_address") || "";

  const isSessionCheckout = !!resolvedSessionToken;

  useEffect(() => {
    if (!currencies.length) return;
    const preferred = currencies.find((c) => c.code === dashboardCurrency.code)?.code || currencies[0].code;
    setPayCurrencyCode(preferred);
  }, [currencies, dashboardCurrency.code]);

  const safeLegacyAmount = useMemo(() => (Number.isFinite(legacyAmount) && legacyAmount > 0 ? legacyAmount : 0), [legacyAmount]);

  useEffect(() => {
    if (checkoutCustomerName) setCustomerName(checkoutCustomerName);
    if (checkoutCustomerEmail) setCustomerEmail(checkoutCustomerEmail);
    if (checkoutCustomerPhone) setCustomerPhone(checkoutCustomerPhone);
    if (checkoutCustomerAddress) setCustomerAddress(checkoutCustomerAddress);
    if (checkoutStatus === "paid") {
      const paidSessionToken = rawSessionToken || resolvedSessionToken;
      if (paidSessionToken) {
        navigate(`/merchant-checkout/thank-you?session=${encodeURIComponent(paidSessionToken)}&tx=${encodeURIComponent(returnedTxId)}`, { replace: true });
      }
    }
  }, [checkoutCustomerAddress, checkoutCustomerEmail, checkoutCustomerName, checkoutCustomerPhone, checkoutStatus, navigate, rawSessionToken, resolvedSessionToken, returnedTxId]);

  useEffect(() => {
    const boot = async () => {
      const {
        data: { user },
      } = await supabase.auth.getUser();

      if (user) {
        setViewerEmail(user.email || "");
        setCustomerEmail(user.email || "");
      }

      let nextSessionToken = rawSessionToken;

      if (!nextSessionToken && paymentLinkToken) {
        setLoadingSession(true);
        const { data: sessionFromLink, error: linkError } = await db.rpc("create_checkout_session_from_payment_link", {
          p_link_token: paymentLinkToken,
          p_customer_email: user?.email || null,
          p_customer_name: null,
        });
        setLoadingSession(false);

        if (linkError) {
          toast.error(linkError.message || "Failed to create checkout from payment link");
          return;
        }

        const row = Array.isArray(sessionFromLink) ? sessionFromLink[0] : sessionFromLink;
        if (!row?.session_token) {
          toast.error("Payment link session token missing");
          return;
        }

        setLinkSessionMeta(row as PaymentLinkSessionCreate);
        nextSessionToken = row.session_token;
        setResolvedSessionToken(nextSessionToken);
      }

      setLoadingSession(true);
      const { data, error } = await db.rpc("get_public_merchant_checkout_session", { p_session_token: nextSessionToken });
      setLoadingSession(false);

      if (error) {
        toast.error(error.message || "Failed to load checkout session");
        return;
      }

      const row = Array.isArray(data) ? data[0] : data;
      if (!row) {
        toast.error("Checkout session not found");
        return;
      }

      const nextSession = row as CheckoutSessionPublic;
      setSessionData(nextSession);
    };

    boot();
  }, [db, paymentLinkToken, rawSessionToken]);

  const handlePaySession = async () => {
    if (!sessionData) {
      toast.error("Session data missing");
      return;
    }
    const parseExpiryInput = () => {
      const compact = cardExpiryMonth.replace(/\s+/g, "");
      const slashParts = compact.split("/").filter(Boolean);
      if (slashParts.length >= 2) {
        return { monthRaw: slashParts[0], yearRaw: slashParts[1] };
      }
      const digits = compact.replace(/\D/g, "");
      if (digits.length === 4) {
        return { monthRaw: digits.slice(0, 2), yearRaw: digits.slice(2) };
      }
      if (digits.length === 6) {
        return { monthRaw: digits.slice(0, 2), yearRaw: digits.slice(2) };
      }
      return { monthRaw: cardExpiryMonth.trim(), yearRaw: cardExpiryYear.trim() };
    };

    const { monthRaw, yearRaw } = parseExpiryInput();
    const parsedMonth = Number(monthRaw);
    const parsedYearRaw = Number(yearRaw || cardExpiryYear.trim());
    const parsedYear = Number.isFinite(parsedYearRaw) && parsedYearRaw < 100 ? 2000 + parsedYearRaw : parsedYearRaw;

    if (!cardNumber.trim() || !monthRaw || !yearRaw || !cardCvc.trim()) {
      toast.error("Virtual card number, expiry (MM/YY), and CVC are required");
      return;
    }
    if (!Number.isFinite(parsedMonth) || parsedMonth < 1 || parsedMonth > 12) {
      toast.error("Invalid virtual card expiry month");
      return;
    }
    if (!Number.isFinite(parsedYear) || parsedYear < 2026) {
      toast.error("Invalid virtual card expiry year");
      return;
    }

    setPaying(true);
    try {
      const note = [
        `Merchant checkout session: ${resolvedSessionToken}`,
        customerName.trim() ? `Customer: ${customerName.trim()}` : "",
        customerEmail.trim() ? `Email: ${customerEmail.trim()}` : "",
        customerPhone.trim() ? `Phone: ${customerPhone.trim()}` : "",
        customerAddress.trim() ? `Address: ${customerAddress.trim()}` : "",
      ]
        .filter(Boolean)
        .join(" | ");

      const basePayload = {
        p_session_token: resolvedSessionToken,
        p_card_number: cardNumber,
        p_expiry_month: parsedMonth,
        p_expiry_year: parsedYear,
        p_cvc: cardCvc,
        p_note: note,
      };
      let { data: rpcResult, error: rpcError } = await db.rpc("pay_merchant_checkout_with_virtual_card", {
        p_session_token: resolvedSessionToken,
        p_card_number: cardNumber,
        p_expiry_month: parsedMonth,
        p_expiry_year: parsedYear,
        p_cvc: cardCvc,
        p_note: note,
        p_customer_name: customerName.trim() || null,
        p_customer_email: customerEmail.trim() || null,
        p_customer_phone: customerPhone.trim() || null,
        p_customer_address: customerAddress.trim() || null,
      });

      if (rpcError) {
        // Retry with base params only
        const retry = await db.rpc("pay_merchant_checkout_with_virtual_card", {
          p_session_token: resolvedSessionToken,
          p_card_number: cardNumber,
          p_expiry_month: parsedMonth,
          p_expiry_year: parsedYear,
          p_cvc: cardCvc,
          p_note: note,
        });
        rpcResult = retry.data;
        rpcError = retry.error;
      }

      if (rpcError) throw rpcError;

      const result = Array.isArray(rpcResult) ? rpcResult[0] : rpcResult;
      const txid = String(result?.transaction_id || "");
      toast.success("Payment successful");

      if (linkSessionMeta?.after_payment_type === "redirect" && linkSessionMeta.redirect_url) {
        const target = new URL(linkSessionMeta.redirect_url);
        target.searchParams.set("tx", txid);
        target.searchParams.set("status", "paid");
        window.location.href = target.toString();
        return;
      }

      const thankYouParams = new URLSearchParams({
        session: resolvedSessionToken,
        tx: txid,
      });
      if (linkSessionMeta?.confirmation_message) {
        thankYouParams.set("message", linkSessionMeta.confirmation_message);
      }
      const thankYouPath = String(sessionData?.items?.[0]?.item_name || "").toLowerCase().includes("pos payment")
        ? "/pos-thank-you"
        : "/merchant-checkout/thank-you";
      navigate(`${thankYouPath}?${thankYouParams.toString()}`, { replace: true });
      return;
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Payment failed");
    } finally {
      setPaying(false);
    }
  };

  const handlePayLegacy = async () => {
    if (!legacyMerchantId) {
      toast.error("Invalid checkout link");
      return;
    }
    if (!safeLegacyAmount) {
      toast.error("Invalid amount");
      return;
    }

    setPaying(true);
    try {
      const note = [
        `Merchant checkout: ${legacyProductName}`,
        legacyProductDescription ? `Description: ${legacyProductDescription}` : "",
        customerName.trim() ? `Customer: ${customerName.trim()}` : "",
        customerEmail.trim() ? `Email: ${customerEmail.trim()}` : "",
      ]
        .filter(Boolean)
        .join(" | ");

      const { data, error } = await supabase.functions.invoke("send-money", {
        body: {
          receiver_email: "__by_id__",
          receiver_id: legacyMerchantId,
          amount: safeLegacyAmount,
          note,
        },
      });

      if (error) throw new Error(await getFunctionErrorMessage(error, "Payment failed"));

      const txid = String((data as { transaction_id?: string } | null)?.transaction_id || "");
      toast.success("Payment successful");
      const thankYouParams = new URLSearchParams({
        tx: txid,
        merchant_name: merchantName,
        merchant_username: merchantUsername || "",
        currency,
        amount: String(amount),
      });
      navigate(`/merchant-checkout/thank-you?${thankYouParams.toString()}`, { replace: true });
      return;
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Payment failed");
    } finally {
      setPaying(false);
    }
  };

  const merchantName = isSessionCheckout ? (sessionData?.merchant_name || "OpenPay Merchant") : legacyMerchantName || "OpenPay Merchant";
  const merchantUsername = isSessionCheckout ? (sessionData?.merchant_username || "") : "";
  const currency = isSessionCheckout ? (sessionData?.currency || "USD") : legacyCurrency;
  const amount = isSessionCheckout ? Number(sessionData?.amount || 0) : safeLegacyAmount;
  const subtotalAmount = isSessionCheckout ? Number(sessionData?.subtotal_amount ?? amount) : amount;
  const checkoutFeeAmount = isSessionCheckout ? Number(sessionData?.fee_amount || 0) : 0;
  const feePayer = isSessionCheckout ? sessionData?.fee_payer || "customer" : "customer";
  const merchantSettlementAmount = isSessionCheckout
    ? Number(sessionData?.merchant_settlement_amount ?? (feePayer === "merchant" ? subtotalAmount - checkoutFeeAmount : subtotalAmount))
    : amount;
  const getPiCodeLabel = (code: string) => (code === "PI" ? "PI" : code === "OUSD" ? "OUSD" : `PI ${code}`);

  if (isSessionCheckout && loadingSession && !sessionData) {
    return <SplashScreen message="Loading checkout..." />;
  }

  const sessionCurrency = currencies.find((c) => c.code === currency);
  const amountLabel = `${sessionCurrency?.symbol || ""}${amount.toFixed(2)} ${getPiCodeLabel(currency)}`;
  const sessionCurrencyRate = currencies.find((c) => c.code === currency)?.rate ?? 1;
  const selectedPayCurrency = currencies.find((c) => c.code === payCurrencyCode) ?? currencies[0];
  const selectedPayCurrencyRate = selectedPayCurrency?.rate ?? 1;
  const amountInUsd = sessionCurrencyRate ? (amount / sessionCurrencyRate) * PI_TO_USD : 0;
  const amountInSelectedCurrency = sessionCurrencyRate ? (amount / sessionCurrencyRate) * selectedPayCurrencyRate : 0;
  const subtotalInSelectedCurrency = sessionCurrencyRate ? (subtotalAmount / sessionCurrencyRate) * selectedPayCurrencyRate : 0;
  const feeInSelectedCurrency = sessionCurrencyRate ? (checkoutFeeAmount / sessionCurrencyRate) * selectedPayCurrencyRate : 0;
  const settlementInSelectedCurrency = sessionCurrencyRate ? (merchantSettlementAmount / sessionCurrencyRate) * selectedPayCurrencyRate : 0;
  const convertedAmountLabel = `${selectedPayCurrency?.symbol || ""}${amountInSelectedCurrency.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ${getPiCodeLabel(selectedPayCurrency?.code || "PI")}`;
  const showConvertedHint = (selectedPayCurrency?.code || "PI") !== currency;
  const checkoutMemo = isSessionCheckout
    ? `${sessionData?.items?.[0]?.item_name || "OpenPay Payment"} | Session ${resolvedSessionToken}`
    : `${legacyProductName}${legacyProductDescription ? ` | ${legacyProductDescription}` : ""}`;
  const primaryItemImage = isSessionCheckout
    ? (sessionData?.items?.[0]?.item_image_url || sessionData?.items?.[0]?.item_images?.[0] || "")
    : "";
  const isCardReady = Boolean(cardNumber.trim() && cardExpiryMonth.trim() && cardCvc.trim());
  const canPay =
    !paying &&
    Boolean(amount) &&
    (paymentMethod === "openpay_wallet" || isCardReady);
  const walletPayUrl = `/public-payment?session=${encodeURIComponent(resolvedSessionToken)}&customer_name=${encodeURIComponent(customerName)}&customer_email=${encodeURIComponent(customerEmail)}&customer_phone=${encodeURIComponent(customerPhone)}&customer_address=${encodeURIComponent(customerAddress)}`;
  const walletPayDeepLink = `openpay://public-payment?session=${encodeURIComponent(resolvedSessionToken)}&customer_name=${encodeURIComponent(customerName)}&customer_email=${encodeURIComponent(customerEmail)}&customer_phone=${encodeURIComponent(customerPhone)}&customer_address=${encodeURIComponent(customerAddress)}`;
  const walletPayWebUrl = typeof window !== "undefined" ? `${window.location.origin}${walletPayUrl}` : walletPayUrl;
  const walletPayQrValue = walletPayDeepLink;
  const formatShortText = (value: string, head = 28, tail = 16) => {
    const cleaned = value.trim();
    if (cleaned.length <= head + tail + 3) return cleaned;
    return `${cleaned.slice(0, head)}...${cleaned.slice(-tail)}`;
  };
  const walletPayQrDisplay = formatShortText(walletPayWebUrl, 36, 20);
  const checkoutMemoDisplay = formatShortText(checkoutMemo, 24, 14);
  const handleCopyWalletLink = async () => {
    try {
      await navigator.clipboard.writeText(walletPayWebUrl);
      toast.success("OpenPay payment link copied");
    } catch {
      toast.error("Copy failed");
    }
  };
  const handleOpenWallet = () => {
    if (typeof window === "undefined") return;
    const isMobile = /android|iphone|ipad|ipod/i.test(navigator.userAgent || "");
    if (isMobile) {
      window.location.href = walletPayDeepLink;
      return;
    }
    navigate(walletPayUrl);
  };

  return (
    <div className="min-h-screen bg-background">
      <div className="flex h-14 items-center border-b border-border bg-card px-4">
        <button onClick={() => navigate(-1)} className="flex h-9 w-9 items-center justify-center rounded-md hover:bg-secondary" aria-label="Back">
          <X className="h-5 w-5 text-foreground" />
        </button>
        <div className="mx-3 h-7 w-px bg-border" />
        <p className="flex items-center gap-2 text-xl font-medium text-foreground">
          <ShoppingCart className="h-5 w-5" />
          Checkout
        </p>
        <button
          type="button"
          onClick={() => setShowInstructions(true)}
          className="ml-auto inline-flex items-center gap-1 rounded-full border border-border px-3 py-1.5 text-xs font-medium text-foreground hover:bg-secondary"
        >
          <HelpCircle className="h-4 w-4" />
          Instructions
        </button>
      </div>

      <div className="grid min-h-[calc(100vh-56px)] grid-cols-1 lg:grid-cols-[1fr_900px]">
        <div className="border-r border-border bg-muted/30 px-6 py-10">
          <div className="mx-auto w-full max-w-xl">
            {primaryItemImage ? (
              <img
                src={primaryItemImage}
                alt={isSessionCheckout ? (sessionData?.items?.[0]?.item_name || "Product image") : "Product image"}
                className="mb-4 h-48 w-full rounded-2xl border border-border object-cover"
              />
            ) : null}
            <div className="mb-3 flex items-center gap-2">
              {sessionData?.merchant_logo_url ? (
                <img src={sessionData.merchant_logo_url} alt={merchantName} className="h-6 w-6 rounded-full object-cover" />
              ) : (
                <div className="flex h-6 w-6 items-center justify-center rounded-full bg-paypal-blue/20 text-[10px] font-bold text-paypal-blue">
                  {(merchantName || "M").slice(0, 1).toUpperCase()}
                </div>
              )}
              <p className="text-3xl font-semibold text-foreground">{merchantName}</p>
            </div>
            <p className="text-6xl font-semibold leading-none text-foreground">{convertedAmountLabel}</p>
            <p className="mt-8 text-4xl font-semibold leading-tight text-foreground">
              {isSessionCheckout ? (sessionData?.items?.[0]?.item_name || "OpenPay Payment") : legacyProductName}
            </p>
            {legacyProductDescription && !isSessionCheckout && <p className="mt-2 text-lg text-muted-foreground">{legacyProductDescription}</p>}
            <button
              type="button"
              onClick={() => setShowProductDetails(true)}
              className="mt-4 text-lg text-muted-foreground hover:text-foreground"
            >
              View full product details &rsaquo;
            </button>
          </div>
        </div>

        <div className="bg-card px-6 py-10">
          <div className="mx-auto w-full max-w-lg">
            <h2 className="text-4xl font-semibold text-foreground">Confirm and pay</h2>

            <div className="mt-5 rounded-2xl border border-border bg-card p-5 shadow-sm">
              <div className="grid grid-cols-2 gap-2">
                <button
                  type="button"
                  onClick={() => setPaymentMethod("card")}
                  className={`flex h-16 items-center gap-2 rounded-md border px-3 text-left ${paymentMethod === "card" ? "border-paypal-blue text-paypal-blue" : "border-border text-muted-foreground"}`}
                >
                  <CreditCard className="h-5 w-5" />
                  <span className="text-lg font-medium">Virtual Card</span>
                </button>
                <button
                  type="button"
                  onClick={() => setPaymentMethod("openpay_wallet")}
                  className={`flex h-16 items-center gap-2 rounded-md border px-3 text-left ${paymentMethod === "openpay_wallet" ? "border-paypal-blue text-paypal-blue" : "border-border text-muted-foreground"}`}
                >
                  <div className="relative">
                    <WalletCards className="h-5 w-5" />
                    <BrandLogo className="absolute -right-1 -top-1 h-3 w-3 rounded-full bg-white" />
                  </div>
                  <span className="text-lg font-medium">OpenPay Wallet</span>
                </button>
              </div>

              {paymentMethod === "card" ? (
                <>
                  <div className="mt-4">
                    <p className="mb-1 text-xl text-foreground">Virtual card number</p>
                    <Input value={cardNumber} onChange={(e) => setCardNumber(e.target.value)} placeholder="1234 1234 1234 1234" className="h-12 rounded-md text-lg" />
                  </div>

                  <div className="mt-3 grid grid-cols-2 gap-2">
                    <div>
                      <p className="mb-1 text-xl text-foreground">Expiration date</p>
                      <Input
                        value={cardExpiryMonth}
                        onChange={(e) => setCardExpiryMonth(e.target.value)}
                        placeholder="MM / YY"
                        className="h-12 rounded-md text-lg"
                      />
                    </div>
                    <div>
                      <p className="mb-1 text-xl text-foreground">Security code</p>
                      <Input value={cardCvc} onChange={(e) => setCardCvc(e.target.value)} placeholder="CVC" className="h-12 rounded-md text-lg" />
                    </div>
                  </div>
                  <p className="mt-2 text-center text-xs font-medium text-paypal-blue">
                    Use only OpenPay Virtual Card for this payment method.
                  </p>
                </>
              ) : (
                <div className="mt-4 rounded-xl border border-border bg-secondary/20 p-4">
                  <div className="flex items-center gap-2">
                    <QrCode className="h-4 w-4 text-paypal-blue" />
                    <p className="text-sm font-semibold text-foreground">Scan with OpenPay wallet app</p>
                  </div>
                  <div className="mt-3 flex justify-center">
                    <div className="rounded-xl bg-white p-3 shadow-sm">
                      <QRCodeSVG
                        value={walletPayQrValue}
                        size={170}
                        level="H"
                        includeMargin
                        imageSettings={{
                          src: "/openpay-logo.jpg",
                          height: 30,
                          width: 30,
                          excavate: true,
                        }}
                      />
                    </div>
                  </div>
                  <p className="mt-3 text-center text-sm text-muted-foreground">
                    Amount: <span className="font-semibold text-foreground">{convertedAmountLabel}</span>
                  </p>
                  <p className="mt-1 text-center text-xs text-muted-foreground">Memo: {checkoutMemoDisplay}</p>
                  <Button
                    type="button"
                    onClick={handleOpenWallet}
                    className="mt-3 h-10 w-full rounded-full bg-paypal-blue text-white hover:bg-[#004dc5]"
                  >
                    <BrandLogo className="mr-2 h-4 w-4" />
                    Open /send in OpenPay
                  </Button>
                  <div className="mt-3 rounded-lg border border-border bg-white p-2">
                    <p className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">OpenPay QR link</p>
                    <p className="mt-1 break-all text-xs text-foreground">{walletPayQrDisplay}</p>
                    <Button
                      type="button"
                      variant="outline"
                      onClick={handleCopyWalletLink}
                      className="mt-2 h-8 w-full rounded-md text-xs"
                    >
                      Copy link (if scanner fails)
                    </Button>
                  </div>
                  <p className="mt-2 text-center text-xs font-medium text-paypal-blue">
                    Use OpenPay wallet only. Other wallets are not supported for this payment link.
                  </p>
                </div>
              )}

              <div className="mt-3">
                <p className="mb-1 text-xl text-foreground">Country</p>
                <div className="relative">
                  <select
                    value={country}
                    onChange={(e) => setCountry(e.target.value)}
                    className="h-12 w-full appearance-none rounded-md border border-border bg-white px-3 text-lg"
                  >
                    {COUNTRIES.map((countryName) => (
                      <option key={countryName} value={countryName}>
                        {countryName}
                      </option>
                    ))}
                  </select>
                  <ChevronDown className="pointer-events-none absolute right-3 top-3.5 h-5 w-5 text-muted-foreground" />
                </div>
              </div>

              <div className="mt-3">
                <p className="mb-1 text-xl text-foreground">Pay currency (170+ OpenPay currencies)</p>
                <div className="relative">
                  {(payCurrencyCode === "PI" || payCurrencyCode === "OUSD") && (
                    <img
                      src={payCurrencyCode === "PI" ? PURE_PI_ICON_URL : OPENPAY_ICON_URL}
                      alt={payCurrencyCode === "PI" ? "Pure Pi" : "Open USD"}
                      className="pointer-events-none absolute left-3 top-3.5 h-5 w-5 rounded-full object-cover"
                    />
                  )}
                  <select
                    value={payCurrencyCode}
                    onChange={(e) => setPayCurrencyCode(e.target.value)}
                    className={`h-12 w-full appearance-none rounded-md border border-border bg-white text-lg ${payCurrencyCode === "PI" || payCurrencyCode === "OUSD" ? "pl-10 pr-3" : "px-3"}`}
                  >
                    {currencies.map((currencyOption) => (
                      <option key={currencyOption.code} value={currencyOption.code}>
                        {`${currencyOption.code === "PI" ? "PI " : currencyOption.code === "OUSD" ? "" : currencyOption.flag ? `${currencyOption.flag} ` : ""}${getPiCodeLabel(currencyOption.code)} - ${currencyOption.name}`}
                      </option>
                    ))}
                  </select>
                  <ChevronDown className="pointer-events-none absolute right-3 top-3.5 h-5 w-5 text-muted-foreground" />
                </div>
                <p className="mt-1 text-xs text-muted-foreground">Includes Pure Pi (PI) and all supported OpenPay currencies.</p>
              </div>

              <div className="mt-3 space-y-2 rounded-md border border-border p-3">
                {!(sessionData?.items?.[0]?.item_name || "").toLowerCase().includes("disable_contact_collection") && (
                  <>
                    <p className="text-sm font-semibold text-foreground">Customer details (for receipt)</p>
                    <Input
                      value={customerName}
                      onChange={(e) => setCustomerName(e.target.value)}
                      placeholder="Full name"
                      className="h-11 rounded-md"
                    />
                    <Input
                      value={customerEmail}
                      onChange={(e) => setCustomerEmail(e.target.value)}
                      placeholder="Email"
                      className="h-11 rounded-md"
                    />
                    <Input
                      value={customerPhone}
                      onChange={(e) => setCustomerPhone(e.target.value)}
                      placeholder="Phone"
                      className="h-11 rounded-md"
                    />
                    <Input
                      value={customerAddress}
                      onChange={(e) => setCustomerAddress(e.target.value)}
                      placeholder="Address"
                      className="h-11 rounded-md"
                    />
                  </>
                )}
                {(sessionData?.items?.[0]?.item_name || "").toLowerCase().includes("disable_contact_collection") && (
                  <p className="text-sm text-muted-foreground">Customer details collection is disabled for this payment</p>
                )}
              </div>

              <div className="mt-4 border-t border-border pt-4">
                <div className="flex items-center justify-between text-lg">
                  <span className="text-foreground">Subtotal</span>
                  <span className="font-semibold text-foreground">
                    {selectedPayCurrency?.symbol || ""}
                    {subtotalInSelectedCurrency.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} {getPiCodeLabel(selectedPayCurrency?.code || "PI")}
                  </span>
                </div>
                <div className="mt-2 flex items-center justify-between text-sm">
                  <span className="text-muted-foreground">OpenPay fee (2%)</span>
                  <span className="font-medium text-foreground">
                    {selectedPayCurrency?.symbol || ""}
                    {feeInSelectedCurrency.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} {getPiCodeLabel(selectedPayCurrency?.code || "PI")} ({feePayer})
                  </span>
                </div>
                <div className="mt-2 flex items-center justify-between rounded-md bg-secondary px-3 py-2 text-lg">
                  <span className="font-semibold text-foreground">Due today</span>
                  <span className="font-bold text-foreground">{convertedAmountLabel}</span>
                </div>
                <p className="mt-2 text-xs text-muted-foreground">
                  Merchant receives: {selectedPayCurrency?.symbol || ""}
                  {settlementInSelectedCurrency.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} {getPiCodeLabel(selectedPayCurrency?.code || "PI")}. Fee is routed to @openpay.
                </p>
                {showConvertedHint && (
                  <p className="mt-2 text-xs text-muted-foreground">
                    Converted from {amountLabel} to {convertedAmountLabel} using current OpenPay FX rate.
                  </p>
                )}
              </div>

              <label className="mt-4 flex items-center gap-2 text-sm text-foreground">
                <input type="checkbox" checked={promoOptIn} onChange={(e) => setPromoOptIn(e.target.checked)} />
                Send me updates and promotions from {merchantName} by email.
              </label>

              <Button
                onClick={
                  paymentMethod === "openpay_wallet"
                    ? () => navigate(walletPayUrl)
                    : isSessionCheckout
                      ? handlePaySession
                      : handlePayLegacy
                }
                disabled={!canPay}
                className={`mt-4 h-12 w-full rounded-full text-base ${
                  canPay
                    ? "bg-paypal-blue text-white hover:bg-[#004dc5]"
                    : "bg-[#ebedf3] text-muted-foreground hover:bg-[#e2e6ef]"
                }`}
              >
                {paying ? "Processing payment..." : paymentMethod === "card" ? (
                  <span className="inline-flex items-center">
                    {canPay && <BrandLogo className="mr-2 h-4 w-4" />}
                    Pay with OpenPay
                  </span>
                ) : (
                  <span className="inline-flex items-center">
                    <BrandLogo className="mr-2 h-4 w-4" />
                    Pay with OpenPay Wallet
                  </span>
                )}
              </Button>

              <div className="mt-4 text-center text-sm text-muted-foreground">
                <p className="inline-flex items-center gap-1 font-medium">
                  <LockKeyhole className="h-4 w-4" /> SSL Secure Payment
                </p>
                <p className="mt-2">OpenPay uses secure virtual card payment. You can access the receipt in your transaction log.</p>
                <p className="mt-1 text-xs">For wallet checkout, use only OpenPay wallet via QR or /send.</p>
              </div>
            </div>

            {!!viewerEmail && <p className="mt-2 text-sm text-muted-foreground">Signed in as {viewerEmail}</p>}
            <p className="mt-8 text-center text-sm text-muted-foreground">Powered by OpenPay</p>
          </div>
        </div>
      </div>

      <Dialog open={showProductDetails} onOpenChange={setShowProductDetails}>
        <DialogContent className="rounded-2xl">
          <DialogTitle className="text-xl font-semibold text-foreground">Product details</DialogTitle>
          <DialogDescription className="text-sm text-muted-foreground">
            Review this payment before you continue.
          </DialogDescription>
          <div className="mt-3 space-y-2 rounded-xl border border-border p-3 text-sm">
            {primaryItemImage ? (
              <img src={primaryItemImage} alt="Product image" className="h-40 w-full rounded-xl border border-border object-cover" />
            ) : null}
            <p className="flex items-center justify-between gap-2">
              <span className="text-muted-foreground">Merchant</span>
              <span className="text-right font-medium text-foreground">{merchantName}</span>
            </p>
            <p className="flex items-center justify-between gap-2">
              <span className="text-muted-foreground">Item</span>
              <span className="text-right font-medium text-foreground">{isSessionCheckout ? (sessionData?.items?.[0]?.item_name || "OpenPay Payment") : legacyProductName}</span>
            </p>
            {legacyProductDescription && !isSessionCheckout && (
              <p className="flex items-start justify-between gap-2">
                <span className="text-muted-foreground">Description</span>
                <span className="max-w-[70%] text-right text-foreground">{legacyProductDescription}</span>
              </p>
            )}
            <p className="flex items-center justify-between gap-2">
              <span className="text-muted-foreground">Original amount</span>
              <span className="text-right font-medium text-foreground">{amountLabel}</span>
            </p>
            <p className="flex items-center justify-between gap-2">
              <span className="text-muted-foreground">Pay amount</span>
              <span className="text-right font-semibold text-foreground">{convertedAmountLabel}</span>
            </p>
          </div>
          <Button className="mt-3 h-10 rounded-xl" onClick={() => setShowProductDetails(false)}>
            Close
          </Button>
        </DialogContent>
      </Dialog>
      <Dialog open={showInstructions} onOpenChange={setShowInstructions}>
        <DialogContent className="rounded-2xl">
          <DialogTitle className="text-xl font-semibold text-foreground">Payment Instructions</DialogTitle>
          <DialogDescription className="text-sm text-muted-foreground">
            Follow these steps to complete checkout securely.
          </DialogDescription>
          <div className="mt-3 space-y-3 rounded-xl border border-border p-3 text-sm text-foreground">
            <p>1. Choose your payment method: OpenPay Virtual Card or OpenPay Wallet.</p>
            <p>2. For Virtual Card: enter valid card number, expiry, and CVC from your OpenPay virtual card.</p>
            <p>3. For OpenPay Wallet: scan the QR or open the /send link inside OpenPay.</p>
            <p>4. Confirm country and pay currency before submitting payment.</p>
            <p>5. Complete payment and keep your receipt in transaction history.</p>
          </div>
          <Button className="mt-3 h-10 rounded-xl" onClick={() => setShowInstructions(false)}>
            Got it
          </Button>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default MerchantCheckoutPage;
