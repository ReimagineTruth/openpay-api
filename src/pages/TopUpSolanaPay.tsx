import { useMemo, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { ArrowLeft, Copy, MessageSquare, History } from "lucide-react";
import { toast } from "sonner";
import { PaymentButton } from "@solana-commerce/kit";
import { Button } from "@/components/ui/button";
import TopUpAccountDetails from "@/components/TopUpAccountDetails";

const SOLANA_ICON_URL = "https://cryptologos.cc/logos/solana-sol-logo.png?v=040";
const DEFAULT_SOLANA_PAY_MERCHANT_WALLET = "3P3j1HQR3DpjsTvv3F5SD2HUK46GGVQxWwtHEesqFH7S";

const USDC_MINT_MAINNET = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v";
const USDC_MINT_DEVNET = "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU";

const normalizeNetwork = (value: string) => {
  const network = value.trim().toLowerCase();
  if (network === "devnet") return "devnet";
  if (network === "testnet") return "testnet";
  return "mainnet";
};

const TopUpSolanaPay = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [signature, setSignature] = useState("");
  const [paymentCompleted, setPaymentCompleted] = useState(false);

  const parsedUsdAmount = Number(searchParams.get("openUsdAmount") || searchParams.get("amount") || "0");
  const safeUsdAmount = Number.isFinite(parsedUsdAmount) && parsedUsdAmount > 0 ? parsedUsdAmount : 0;
  const usdDisplay = safeUsdAmount > 0 ? safeUsdAmount.toFixed(2) : "0.00";

  const network = normalizeNetwork(String(import.meta.env.VITE_SOLANA_PAY_NETWORK || "mainnet"));
  const merchantWallet =
    String(import.meta.env.VITE_SOLANA_PAY_MERCHANT_WALLET || "").trim() || DEFAULT_SOLANA_PAY_MERCHANT_WALLET;
  const merchantName = String(import.meta.env.VITE_SOLANA_PAY_MERCHANT_NAME || "OpenPay").trim() || "OpenPay";
  const merchantLogoUrl =
    typeof window === "undefined" ? "/openpay-logo.jpg" : `${window.location.origin}/openpay-logo.jpg`;

  const allowedMints = useMemo(() => {
    const configured = String(import.meta.env.VITE_SOLANA_PAY_ALLOWED_MINTS || "").trim();
    if (configured) {
      return configured
        .split(",")
        .map((mint) => mint.trim())
        .filter(Boolean);
    }
    return [network === "devnet" ? USDC_MINT_DEVNET : USDC_MINT_MAINNET];
  }, [network]);

  const paymentConfig = useMemo(() => {
    return {
      products: [
        {
          id: "openpay-topup-openusd",
          name: "OpenPay Top Up",
          description: "Top up your OpenPay balance (OPEN USD).",
          price: safeUsdAmount,
          quantity: 1,
        },
      ],
      fallbackSolPriceUsd: 150,
    };
  }, [safeUsdAmount]);

  const openTelegramSupport = () => {
    window.open("https://t.me/openpayofficial", "_blank", "noopener,noreferrer");
  };

  const openTopUpHistory = () => {
    navigate("/topup-history");
  };

  const canPay = Boolean(merchantWallet) && safeUsdAmount > 0;

  return (
    <div className="min-h-screen bg-background px-4 pt-4">
      <div className="flex items-center gap-3">
        <button onClick={() => navigate("/dashboard")} aria-label="Back to dashboard">
          <ArrowLeft className="h-6 w-6 text-foreground" />
        </button>
        <h1 className="text-lg font-semibold text-foreground">Top Up - Solana Pay</h1>
        <img src={SOLANA_ICON_URL} alt="Solana" className="ml-auto h-7 w-auto object-contain" />
      </div>

      <div className="paypal-surface mt-8 rounded-3xl p-6">
        <p className="text-center text-sm text-muted-foreground">Amount to pay</p>
        <p className="mt-1 text-center text-5xl font-bold text-foreground">{usdDisplay} USDC</p>
        <p className="mt-1 text-center text-xs text-muted-foreground">
          You will receive {usdDisplay} OPEN USD (1 USDC = 1 OPEN USD)
        </p>

        <div className="mt-5 rounded-2xl border border-border bg-white p-4">
          <p className="text-center text-xs font-semibold text-muted-foreground">Pay with Solana Pay</p>
          <div className="mt-3 rounded-xl border border-border bg-muted/10 p-3 text-center">
            <p className="text-[11px] uppercase tracking-wide text-muted-foreground">Merchant wallet</p>
            <p className="mt-1 break-all text-xs font-semibold text-foreground">{merchantWallet}</p>
            <Button
              type="button"
              variant="outline"
              className="mt-2 h-9 w-full rounded-xl"
              onClick={() => {
                void navigator.clipboard.writeText(merchantWallet).then(
                  () => toast.success("Merchant wallet copied"),
                  () => toast.error("Unable to copy wallet"),
                );
              }}
            >
              <Copy className="mr-2 h-4 w-4" /> Copy Wallet
            </Button>
          </div>
          <div className="mt-3 flex justify-center">
            <PaymentButton
              config={{
                merchant: { name: merchantName, wallet: merchantWallet, logo: merchantLogoUrl },
                mode: "buyNow",
                network,
                allowedMints,
                showQR: true,
                theme: {
                  primaryColor: "#2148ff",
                  secondaryColor: "#14F195",
                  borderRadius: "xl",
                },
              }}
              paymentConfig={paymentConfig as any}
              onPaymentStart={() => toast.message("Opening Solana Pay...")}
              onPaymentSuccess={(sig) => {
                setSignature(String(sig || ""));
                setPaymentCompleted(true);
                toast.success("Payment confirmed on-chain.");
              }}
              onPaymentError={(error) => {
                toast.error(error?.message || "Solana Pay payment failed");
              }}
              onCancel={() => toast.message("Payment cancelled")}
            >
              <button
                type="button"
                disabled={!canPay}
                className="paypal-surface w-full max-w-md rounded-md border border-border bg-white py-3 text-center text-base font-semibold text-foreground shadow-sm disabled:cursor-not-allowed disabled:opacity-60"
              >
                Pay with Solana Pay
              </button>
            </PaymentButton>
          </div>
        </div>

        {signature ? (
          <div className="mt-4 rounded-2xl border border-border bg-white p-4">
            <p className="text-xs font-semibold text-muted-foreground">Transaction signature</p>
            <p className="mt-1 break-all text-sm font-semibold text-foreground">{signature}</p>
            <Button
              type="button"
              variant="outline"
              className="mt-3 h-10 w-full rounded-2xl"
              onClick={() => {
                void navigator.clipboard.writeText(signature).then(
                  () => toast.success("Signature copied"),
                  () => toast.error("Unable to copy signature"),
                );
              }}
            >
              <Copy className="mr-2 h-4 w-4" /> Copy Signature
            </Button>
          </div>
        ) : null}

        <Button
          type="button"
          variant="outline"
          className="mt-4 h-11 w-full rounded-2xl"
          onClick={() => setPaymentCompleted(true)}
          disabled={safeUsdAmount <= 0}
        >
          I completed Solana Pay payment
        </Button>

        {paymentCompleted && (
          <div className="mt-5 rounded-2xl border border-border bg-white p-4">
            <TopUpAccountDetails
              providerName="Solana Pay"
              amount={safeUsdAmount}
              submitLabel="Submit Solana Pay Top Up"
              initialReferenceCode={signature || undefined}
              lockReferenceCode={Boolean(signature)}
            />
          </div>
        )}

        <Button
          type="button"
          className="mt-4 h-11 w-full rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5]"
          onClick={() => navigate("/dashboard")}
        >
          Done
        </Button>

        <div className="mt-4 rounded-2xl border border-blue-200 bg-blue-50 p-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <MessageSquare className="h-5 w-5 text-blue-600" />
              <div>
                <p className="text-sm font-semibold text-blue-900">Need help with Solana Pay?</p>
                <p className="text-xs text-blue-700">Get instant support on Telegram</p>
              </div>
            </div>
            <div className="flex gap-2">
              <Button
                onClick={openTopUpHistory}
                variant="outline"
                size="sm"
                className="border-blue-200 text-blue-700 hover:bg-blue-100"
              >
                <History className="h-4 w-4 mr-1" />
                History
              </Button>
              <Button
                onClick={openTelegramSupport}
                className="bg-blue-600 hover:bg-blue-700 text-white"
                size="sm"
              >
                <MessageSquare className="h-4 w-4 mr-1" />
                Support
              </Button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default TopUpSolanaPay;
