import { useNavigate, useSearchParams } from "react-router-dom";
import { ArrowLeft, Copy, HelpCircle, ExternalLink, FileText, LifeBuoy, CreditCard, MessageCircle, History } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { useState } from "react";
import TopUpAccountDetails from "@/components/TopUpAccountDetails";
import TopUpActionGrid from "@/components/TopUpActionGrid";

const APPLE_PAY_ICON_URL =
  "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b0/Apple_Pay_logo.svg/1920px-Apple_Pay_logo.svg.png";

const TopUpApplePay = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [showInstructions, setShowInstructions] = useState(false);
  const [showTopUpInstructions, setShowTopUpInstructions] = useState(false);
  const [showSafetyAgreement, setShowSafetyAgreement] = useState(false);
  const [safetyAgreementChecked, setSafetyAgreementChecked] = useState(false);
  const [safetyAccepted, setSafetyAccepted] = useState(false);
  const [paymentCompleted, setPaymentCompleted] = useState(false);

  const parsedUsdAmount = Number(searchParams.get("openUsdAmount") || searchParams.get("amount") || "0");
  const safeUsdAmount = Number.isFinite(parsedUsdAmount) && parsedUsdAmount > 0 ? parsedUsdAmount : 0;
  const usdDisplay = safeUsdAmount > 0 ? safeUsdAmount.toFixed(2) : "0.00";
  const openUsdDisplay = usdDisplay;
  const applePayCheckoutUrl = "https://www.apple.com/apple-pay/";

  const handleCopyApplePayLink = async () => {
    try {
      await navigator.clipboard.writeText(applePayCheckoutUrl);
      toast.success("Apple Pay link copied");
    } catch {
      toast.error("Copy failed");
    }
  };

  const handleOpenApplePay = () => {
    setSafetyAgreementChecked(false);
    setShowSafetyAgreement(true);
  };
  const openSupportWidget = () => {
    window.dispatchEvent(new CustomEvent("open-support-widget", { detail: { tab: "messages" } }));
  };

  const openTelegramSupport = () => {
    window.open("https://t.me/openpayofficial/1", "_blank", "noopener,noreferrer");
  };

  const openTopUpHistory = () => {
    navigate("/topup-history");
  };

  const confirmOpenApplePay = () => {
    setSafetyAccepted(true);
    setShowSafetyAgreement(false);
  };

  return (
    <div className="min-h-screen bg-background px-4 pt-4">
      <div className="flex items-center gap-3">
        <button onClick={() => navigate("/dashboard")}>
          <ArrowLeft className="h-6 w-6 text-foreground" />
        </button>
        <h1 className="text-lg font-semibold text-foreground">Top Up - Apple Pay</h1>
        <img src={APPLE_PAY_ICON_URL} alt="Apple Pay" className="ml-auto h-7 w-auto object-contain" />
        <button
          onClick={() => setShowInstructions(true)}
          className="inline-flex items-center gap-1 rounded-full border border-border px-3 py-1.5 text-xs font-medium text-foreground"
        >
          <HelpCircle className="h-4 w-4" />
          How it works
        </button>
      </div>

      <div className="paypal-surface mt-8 rounded-3xl p-6">
        <p className="text-center text-sm text-muted-foreground">Amount to pay</p>
        <p className="mt-1 text-center text-5xl font-bold text-foreground">{usdDisplay} USD</p>
        <p className="mt-1 text-center text-xs text-muted-foreground">
          You will receive {openUsdDisplay} OPEN USD (1 OPEN USD = 1 USD)
        </p>
        <p className="mt-2 text-center text-sm font-semibold text-foreground">
          OPEN USD to receive: {openUsdDisplay} OPEN USD
        </p>

        {safeUsdAmount > 0 && (
          <div className="mt-5 rounded-2xl border border-border bg-blue-50 p-4">
            <p className="text-center text-xs font-semibold text-muted-foreground">Pay with Apple Pay</p>
            {!safetyAccepted ? (
              <div className="mt-3 flex justify-center">
                <button
                  type="button"
                  onClick={handleOpenApplePay}
                  className="paypal-surface w-full max-w-md rounded-md border border-border bg-black py-3 text-center text-base font-semibold text-white shadow-sm"
                >
                  Apple Pay
                </button>
              </div>
            ) : (
              <div className="mt-3 flex justify-center">
                <button
                  type="button"
                  onClick={() => toast.info("Apple Pay button will appear once Apple Pay is enabled.")}
                  className="paypal-surface w-full max-w-md rounded-md border border-border bg-black py-3 text-center text-base font-semibold text-white shadow-sm"
                >
                  Apple Pay
                </button>
              </div>
            )}
          </div>
        )}

        <p className="mt-3 text-center text-sm font-medium text-foreground">
          Note: Apple Pay checkout may redirect you. Review the top-up instructions below, then proceed with your top up.
        </p>

        <TopUpActionGrid
          actions={[
            {
              label: "Pay with Apple Pay",
              onClick: () => {
                if (!safetyAccepted) {
                  handleOpenApplePay();
                  return;
                }
                toast.info("Apple Pay will open when integrated.");
              },
              icon: <CreditCard className="h-4 w-4" />,
            },
            {
              label: "Copy Link",
              onClick: handleCopyApplePayLink,
              icon: <Copy className="h-4 w-4" />,
            },
            {
              label: "Open Link",
              onClick: () => window.open(applePayCheckoutUrl, "_blank"),
              icon: <ExternalLink className="h-4 w-4" />,
            },
            {
              label: "Support Chat",
              onClick: openSupportWidget,
              icon: <LifeBuoy className="h-4 w-4" />,
            },
            {
              label: "Telegram Support",
              onClick: openTelegramSupport,
              icon: <MessageCircle className="h-4 w-4" />,
            },
            {
              label: "Top-Up History",
              onClick: openTopUpHistory,
              icon: <History className="h-4 w-4" />,
            },
            {
              label: "Instructions",
              onClick: () => setShowTopUpInstructions(true),
              icon: <HelpCircle className="h-4 w-4" />,
            },
          ]}
        />

        <Button
          type="button"
          variant="outline"
          className="mt-3 h-11 w-full rounded-2xl"
          onClick={() => setPaymentCompleted(true)}
        >
          I completed Apple Pay payment
        </Button>

        {paymentCompleted && (
          <div className="mt-5 rounded-2xl border border-border bg-blue-50 p-4">
            <TopUpAccountDetails providerName="Apple Pay" amount={safeUsdAmount} submitLabel="Submit Apple Pay Top Up" />
          </div>
        )}

        <Button
          type="button"
          className="mt-2 h-11 w-full rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5]"
          onClick={() => navigate("/dashboard")}
        >
          Done
        </Button>
      </div>

      <Dialog open={showInstructions} onOpenChange={setShowInstructions}>
        <DialogContent className="rounded-3xl sm:max-w-lg">
          <DialogTitle className="text-xl font-bold text-foreground">Top Up Instructions</DialogTitle>
          <DialogDescription className="text-sm text-muted-foreground">
            Top up works on OpenPay app and browser across desktop, mobile, and tablet.
          </DialogDescription>

          <div className="rounded-2xl border border-border p-3 text-sm text-foreground">
            <p>1. You can top up your OpenPay balance using Pi payments or approved third-party partner providers.</p>
            <p>2. Third-party provider top up is supported on desktop, mobile, tablet, and browser.</p>
            <p>3. Pi Payment top up works only in Pi Browser.</p>
            <p>4. If you use OpenPay app with email login, sign in with the same email in Pi Browser first, then top up.</p>
            <p>5. If you do not have Pi in your wallet, buy Pi in your Pi Wallet onramp first, then top up in OpenPay.</p>
            <p>6. Third-party provider availability, limits, fees, and processing time depend on partner terms.</p>
            <p>7. You can also exchange with another OpenPay user or merchant who accepts real-currency exchange.</p>
            <p>8. OpenPay top up has no fee from OpenPay. A merchant or partner may add exchange or processing fee terms.</p>
          </div>

          <Button
            className="h-11 w-full rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5]"
            onClick={() => setShowInstructions(false)}
          >
            I Understand
          </Button>
        </DialogContent>
      </Dialog>

      <Dialog open={showTopUpInstructions} onOpenChange={setShowTopUpInstructions}>
        <DialogContent className="max-h-[85vh] overflow-y-auto rounded-3xl sm:max-w-2xl">
          <DialogTitle className="text-2xl font-bold text-paypal-blue">OpenPay Top-Up Instructions</DialogTitle>

          <div className="space-y-4 text-sm text-foreground">
            <div>
              <h3 className="text-base font-semibold text-teal-700">Step 1: Enter Amount in OpenPay</h3>
              <ul className="list-disc pl-5">
                <li>Go to <strong>OpenPay → Top Up</strong>.</li>
                <li>Enter your desired top-up amount.</li>
                <li>Review the final USD amount displayed.</li>
              </ul>
            </div>
          </div>

          <Button
            type="button"
            className="h-11 w-full rounded-2xl bg-paypal-blue text-white hover:bg-[#162c6e]"
            onClick={() => setShowTopUpInstructions(false)}
          >
            Accept & Continue
          </Button>
        </DialogContent>
      </Dialog>

      <Dialog open={showSafetyAgreement} onOpenChange={setShowSafetyAgreement}>
        <DialogContent className="max-h-[85vh] overflow-y-auto rounded-3xl sm:max-w-lg">
          <DialogTitle className="text-xl font-bold text-foreground">OpenPay Top-Up Safety Agreement</DialogTitle>
          <DialogDescription className="text-sm text-muted-foreground">
            Please review and accept before proceeding with your top-up transaction.
          </DialogDescription>
          <div className="rounded-2xl border border-border p-3 text-sm text-foreground">
            <p className="font-semibold">1. Nature of Service</p>
            <p className="mt-1">
              OpenPay is a technology platform that facilitates digital payments and transaction processing. OpenPay is not a bank, financial institution, investment platform, remittance company, or licensed money service business unless otherwise stated under applicable law.
            </p>
            <p className="mt-3 font-semibold">2. Payment Authorization</p>
            <p className="mt-1">By proceeding with this top-up, you:</p>
            <p className="mt-1">Authorize OpenPay to process the transaction using your selected payment method.</p>
            <p className="mt-1">Confirm that you are the authorized holder of the payment method used.</p>
            <p className="mt-1">Understand that payment processing is handled through third-party providers.</p>
            <p className="mt-3 font-semibold">3. Fees, Rates, and Processing</p>
            <p className="mt-1">You acknowledge and agree that:</p>
            <p className="mt-1">Exchange rates (if applicable), service fees, and third-party processing fees may apply.</p>
            <p className="mt-1">Processing times may vary depending on your payment provider, banking institution, or network conditions.</p>
            <p className="mt-1">OpenPay is not responsible for delays caused by third-party payment processors.</p>
            <p className="mt-3 font-semibold">4. User Responsibility</p>
            <p className="mt-1">Before completing your transaction, you agree to:</p>
            <p className="mt-1">Verify the top-up amount.</p>
            <p className="mt-1">Confirm the recipient account or wallet details.</p>
            <p className="mt-1">Review all payment information carefully.</p>
            <p className="mt-1">Transactions completed with incorrect details may not be reversible.</p>
            <p className="mt-3 font-semibold">5. No Deposit Insurance</p>
            <p className="mt-1">
              Funds topped up into your OpenPay balance are not bank deposits and are not insured by any government deposit insurance corporation.
            </p>
            <p className="mt-3 font-semibold">6. License & Compliance</p>
            <p className="mt-1">
              OpenPay operates as a payment technology platform and partners with regulated third-party payment providers where required by law. OpenPay complies with applicable digital commerce and platform regulations in the jurisdictions where it operates.
            </p>
            <p className="mt-1">
              OpenPay does not directly hold customer deposits as a bank and does not provide investment or financial advisory services.
            </p>
            <p className="mt-2 text-xs text-muted-foreground">
              OpenPay License:{" "}
              <a href="/legal" className="font-semibold text-paypal-blue underline">
                View License
              </a>
            </p>
          </div>
          <label className="flex items-start gap-2 text-sm text-foreground">
            <input
              type="checkbox"
              className="mt-1"
              checked={safetyAgreementChecked}
              onChange={(e) => setSafetyAgreementChecked(e.target.checked)}
            />
            <span>I understand and agree to proceed with this top up.</span>
          </label>
          <Button
            className="h-11 w-full rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5]"
            disabled={!safetyAgreementChecked}
            onClick={confirmOpenApplePay}
          >
            Pay with Apple Pay
          </Button>
          <Button
            type="button"
            variant="outline"
            className="h-11 w-full rounded-2xl"
            onClick={() => setShowSafetyAgreement(false)}
          >
            Cancel
          </Button>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default TopUpApplePay;
