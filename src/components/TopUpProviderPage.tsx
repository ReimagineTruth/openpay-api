import { useMemo, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { ArrowLeft, ExternalLink, HelpCircle, FileText, LifeBuoy, Copy, MessageCircle, History } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import TopUpAccountDetails from "@/components/TopUpAccountDetails";
import RegulatoryStatusModal from "@/components/RegulatoryStatusModal";
import { QRCodeSVG } from "qrcode.react";
import TopUpActionGrid from "@/components/TopUpActionGrid";

type TopUpProviderPageProps = {
  providerName: string;
  providerLogoUrl?: string;
  providerUrl?: string;
  depositAddress?: string;
  depositNetwork?: string;
  qrLogoUrl?: string;
  accentClassName?: string;
};

const TopUpProviderPage = ({
  providerName,
  providerLogoUrl,
  providerUrl,
  depositAddress,
  depositNetwork,
  qrLogoUrl,
  accentClassName = "text-foreground",
}: TopUpProviderPageProps) => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();

  const parsedUsdAmount = Number(searchParams.get("openUsdAmount") || searchParams.get("amount") || "0");
  const safeUsdAmount = Number.isFinite(parsedUsdAmount) && parsedUsdAmount > 0 ? parsedUsdAmount : 0;
  const usdDisplay = safeUsdAmount > 0 ? safeUsdAmount.toFixed(2) : "0.00";

  const openUsdDisplay = useMemo(() => usdDisplay, [usdDisplay]);
  const providerUnit = providerName === "USDT" ? "USDT" : providerName === "USDC" ? "USDC" : "USD";
  const conversionText =
    providerName === "USDT"
      ? "1 USDT = 1 OPEN USD"
      : providerName === "USDC"
        ? "1 USDC = 1 OPEN USD"
        : "1 OPEN USD = 1 USD";
  const [paymentCompleted, setPaymentCompleted] = useState(false);
  const [showSafetyAgreement, setShowSafetyAgreement] = useState(false);
  const [safetyAgreementChecked, setSafetyAgreementChecked] = useState(false);
  const [safetyAccepted, setSafetyAccepted] = useState(false);
  const [showTopUpInstructions, setShowTopUpInstructions] = useState(false);
  const [showRegulatoryModal, setShowRegulatoryModal] = useState(false);
  const normalizedAddress = String(depositAddress || "").trim();
  const normalizedNetwork = String(depositNetwork || "").trim();

  const handleProceed = () => {
    if (!safetyAccepted) {
      setSafetyAgreementChecked(false);
      setShowSafetyAgreement(true);
      return;
    }
    if (providerUrl) {
      window.open(providerUrl, "_blank", "noopener,noreferrer");
      return;
    }
    if (normalizedAddress) {
      void navigator.clipboard.writeText(normalizedAddress).then(
        () => toast.success(`${providerName} address copied`),
        () => toast.error("Unable to copy address"),
      );
      return;
    }
    toast.error(`${providerName} top-up is not configured yet.`);
  };

  const confirmProceed = () => {
    setSafetyAccepted(true);
    setShowSafetyAgreement(false);
    if (providerUrl) {
      window.open(providerUrl, "_blank", "noopener,noreferrer");
      return;
    }
    if (normalizedAddress) {
      void navigator.clipboard.writeText(normalizedAddress).then(
        () => toast.success(`${providerName} address copied`),
        () => toast.error("Unable to copy address"),
      );
      return;
    }
    toast.error(`${providerName} top-up is not configured yet.`);
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

  return (
    <div className="min-h-screen bg-background px-4 pt-4">
      <div className="flex items-center gap-3">
        <button onClick={() => navigate("/dashboard")}>
          <ArrowLeft className="h-6 w-6 text-foreground" />
        </button>
        <h1 className={`text-lg font-semibold ${accentClassName}`}>Top Up - {providerName}</h1>
        {providerLogoUrl && (
          <img src={providerLogoUrl} alt={providerName} className="ml-auto h-7 w-auto object-contain" />
        )}
      </div>

      <div className="paypal-surface mt-8 rounded-3xl p-6">
        <p className="text-center text-sm text-muted-foreground">Amount to pay</p>
        <p className="mt-1 text-center text-5xl font-bold text-foreground">{usdDisplay} {providerUnit}</p>
        <p className="mt-1 text-center text-xs text-muted-foreground">
          You will receive {openUsdDisplay} OPEN USD ({conversionText})
        </p>
        <p className="mt-2 text-center text-sm font-semibold text-foreground">
          OPEN USD to receive: {openUsdDisplay} OPEN USD
        </p>

        <div className="mt-5 rounded-2xl border border-border bg-white p-4">
          <p className="text-center text-xs font-semibold text-muted-foreground">Pay with {providerName}</p>
          <div className="mt-3 flex justify-center">
            <button
              type="button"
              onClick={handleProceed}
              className="paypal-surface w-full max-w-md rounded-md border border-border bg-white py-3 text-center text-base font-semibold text-foreground shadow-sm"
            >
              {providerUrl ? `Pay with ${providerName}` : normalizedAddress ? `Copy ${providerName} Address` : providerName}
            </button>
          </div>
          {!providerUrl && !normalizedAddress && (
            <p className="mt-3 text-center text-xs text-muted-foreground">
              {providerName} top-up is coming soon. Please choose another method or contact support.
            </p>
          )}
        </div>

        {normalizedAddress && (
          <div className="mt-5 rounded-2xl border border-border bg-white p-4">
            <p className="text-center text-xs font-semibold text-muted-foreground">Deposit {providerName}</p>
            <div className="mt-4 flex flex-col items-center gap-4">
              <div className="rounded-2xl bg-white p-3 shadow-sm">
                <QRCodeSVG
                  value={normalizedAddress}
                  size={220}
                  level="M"
                  includeMargin
                  imageSettings={
                    qrLogoUrl
                      ? {
                          src: qrLogoUrl,
                          height: 40,
                          width: 40,
                          excavate: true,
                        }
                      : undefined
                  }
                />
              </div>
              <div className="w-full rounded-xl border border-border bg-muted/20 p-3 text-center">
                <p className="text-xs uppercase tracking-wide text-muted-foreground">Address</p>
                <p className="mt-1 break-all text-sm font-semibold text-foreground">{normalizedAddress}</p>
              </div>
              {normalizedNetwork && (
                <div className="w-full rounded-xl border border-border bg-muted/20 p-3 text-center">
                  <p className="text-xs uppercase tracking-wide text-muted-foreground">Network</p>
                  <p className="mt-1 text-sm font-semibold text-foreground">{normalizedNetwork}</p>
                </div>
              )}
              <Button
                type="button"
                variant="outline"
                className="h-11 w-full rounded-2xl"
                onClick={() => {
                  void navigator.clipboard.writeText(normalizedAddress).then(
                    () => toast.success(`${providerName} address copied`),
                    () => toast.error("Unable to copy address"),
                  );
                }}
              >
                Copy {providerName} Address
              </Button>
            </div>
          </div>
        )}

        <TopUpActionGrid
          actions={[
            {
              label: providerUrl ? `Open ${providerName}` : normalizedAddress ? "Copy Address" : providerName,
              onClick: handleProceed,
              icon: normalizedAddress ? <Copy className="h-4 w-4" /> : <ExternalLink className="h-4 w-4" />,
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
            {
              label: "Regulatory",
              onClick: () => setShowRegulatoryModal(true),
              icon: <FileText className="h-4 w-4" />,
            },
          ]}
        />

        <Button
          type="button"
          variant="outline"
          className="mt-3 h-11 w-full rounded-2xl"
          onClick={() => setPaymentCompleted(true)}
          disabled={!safetyAccepted || safeUsdAmount <= 0}
        >
          I completed {providerName} payment - Submit proof
        </Button>

        {paymentCompleted && (
          <div className="mt-5 rounded-2xl border border-border bg-white p-4">
            <TopUpAccountDetails
              providerName={providerName}
              amount={safeUsdAmount}
              submitLabel={`Submit ${providerName} Top Up`}
            />
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
            onClick={confirmProceed}
          >
            Accept & Continue
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

      <Dialog open={showTopUpInstructions} onOpenChange={setShowTopUpInstructions}>
        <DialogContent className="max-h-[85vh] overflow-y-auto rounded-3xl sm:max-w-xl">
          <DialogTitle className="text-xl font-bold text-foreground">{providerName} Top-Up Instructions</DialogTitle>
          <DialogDescription className="text-sm text-muted-foreground">
            Complete step-by-step guide to successfully top up your OpenPay account
          </DialogDescription>

          <div className="rounded-2xl border border-border p-3 text-sm text-foreground space-y-4">
            <div className="space-y-2">
              <p className="font-semibold text-lg">📋 Step 1: Prepare Payment Details</p>
              <p className="text-muted-foreground">
                • Copy the {providerName} address using the copy button<br/>
                • Double-check the network: <span className="font-medium">{normalizedNetwork || "As shown on deposit screen"}</span><br/>
                • Note the exact amount: <span className="font-medium">{usdDisplay} {providerUnit}</span>
              </p>
            </div>

            <div className="space-y-2">
              <p className="font-semibold text-lg">💳 Step 2: Complete Payment</p>
              <p className="text-muted-foreground">
                • Open your {providerName} app/wallet<br/>
                • Send <span className="font-medium">{usdDisplay} {providerUnit}</span> to the copied address<br/>
                • Use the correct network to avoid loss of funds<br/>
                • Wait for transaction confirmation (few minutes)
              </p>
            </div>

            <div className="space-y-2">
              <p className="font-semibold text-lg">📸 Step 3: Prepare Payment Proof</p>
              <p className="text-muted-foreground">
                • Take a screenshot of the completed transaction<br/>
                • Include: Transaction hash, amount, recipient address<br/>
                • Save the reference/transaction ID<br/>
                • Make sure all details are clearly visible
              </p>
            </div>

            <div className="space-y-2">
              <p className="font-semibold text-lg">✅ Step 4: Submit Top-Up Request</p>
              <p className="text-muted-foreground">
                • Click <span className="font-medium">"I completed {providerName} payment - Submit proof"</span><br/>
                • Upload your payment proof screenshot<br/>
                • Enter the reference/transaction ID<br/>
                • Fill in your account details<br/>
                • Submit for review
              </p>
            </div>

            <div className="space-y-2">
              <p className="font-semibold text-lg">⏱️ Step 5: Wait for Processing</p>
              <p className="text-muted-foreground">
                • Your request will be reviewed by our team<br/>
                • Usually processed within 24 hours<br/>
                • Check status in <span className="font-medium">Top-Up History</span><br/>
                • You'll receive notification when approved
              </p>
            </div>

            <div className="rounded-lg bg-blue-50 border border-blue-200 p-3">
              <p className="font-semibold text-blue-900">🆘 Need Help?</p>
              <p className="text-blue-800 text-sm mt-1">
                • Contact Telegram Support: <a href="https://t.me/openpayofficial" target="_blank" rel="noopener noreferrer" className="underline">@openpayofficial</a><br/>
                • Check your Top-Up History for status updates<br/>
                • Keep your payment proof handy for verification
              </p>
            </div>

            <div className="rounded-lg bg-yellow-50 border border-yellow-200 p-3">
              <p className="font-semibold text-yellow-900">⚠️ Important Notes</p>
              <p className="text-yellow-800 text-sm mt-1">
                • Send only {providerName} to this address<br/>
                • Wrong network = loss of funds<br/>
                • Minimum amount: 1 {providerUnit}<br/>
                • Keep your transaction ID for reference
              </p>
            </div>
          </div>

          <div className="flex gap-2 mt-4">
            <Button
              type="button"
              variant="outline"
              className="flex-1 h-11 rounded-2xl"
              onClick={() => {
                setShowTopUpInstructions(false);
                navigate("/topup-history");
              }}
            >
              <History className="h-4 w-4 mr-2" />
              View History
            </Button>
            <Button
              type="button"
              className="flex-1 h-11 rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5]"
              onClick={() => setShowTopUpInstructions(false)}
            >
              I Understand
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      <RegulatoryStatusModal open={showRegulatoryModal} onOpenChange={setShowRegulatoryModal} />
    </div>
  );
};

export default TopUpProviderPage;
