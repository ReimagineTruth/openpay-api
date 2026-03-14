import { useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { ArrowLeft, Copy, HelpCircle, ExternalLink, FileText, LifeBuoy, CreditCard, ListChecks, MessageCircle, History } from "lucide-react";
import { QRCodeSVG } from "qrcode.react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import TopUpAccountDetails from "@/components/TopUpAccountDetails";
import TopUpActionGrid from "@/components/TopUpActionGrid";
const JQRPH_ICON_URL = "https://upload.wikimedia.org/wikipedia/commons/thumb/3/35/QR_Ph_Logo.svg/960px-QR_Ph_Logo.svg.png?20250310160234";
const E_WALLET_PHP_PER_OUSD = 57;

const TopUpEwalletQrPh = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [embedOpen, setEmbedOpen] = useState(false);
  const [showInstructions, setShowInstructions] = useState(false);
  const [showTopUpInstructions, setShowTopUpInstructions] = useState(false);
  const [showSupportedQrPh, setShowSupportedQrPh] = useState(false);
  const [showSafetyAgreement, setShowSafetyAgreement] = useState(false);
  const [safetyAgreementChecked, setSafetyAgreementChecked] = useState(false);
  const [paymentCompleted, setPaymentCompleted] = useState(false);

  const parsedPhpAmount = Number(searchParams.get("phpAmount") || "0");
  const safePhpAmount = Number.isFinite(parsedPhpAmount) && parsedPhpAmount > 0 ? parsedPhpAmount : 0;
  const parsedOpenUsdAmount = Number(searchParams.get("openUsdAmount") || searchParams.get("amount") || "0");
  const safeOpenUsdAmount = Number.isFinite(parsedOpenUsdAmount) && parsedOpenUsdAmount > 0 ? parsedOpenUsdAmount : 0;

  // Keep PHP exact when provided from Buy flow, and only round OPEN USD display.
  const payPhpAmount = safePhpAmount > 0 ? safePhpAmount : safeOpenUsdAmount * E_WALLET_PHP_PER_OUSD;
  const openUsdAmount = safeOpenUsdAmount > 0 ? safeOpenUsdAmount : payPhpAmount / E_WALLET_PHP_PER_OUSD;
  const roundedOpenUsdAmount = Math.round(openUsdAmount * 100) / 100;
  const phpDisplay = payPhpAmount > 0 ? payPhpAmount.toFixed(2) : "0.00";
  const openUsdDisplay = roundedOpenUsdAmount > 0 ? roundedOpenUsdAmount.toFixed(2) : "0.00";
  const payQrPhUrl = "https://paymongo.page/l/openpay";

  const handleCopyQrLink = async () => {
    try {
      await navigator.clipboard.writeText(payQrPhUrl);
      toast.success("Pay QR PH link copied");
    } catch {
      toast.error("Copy failed");
    }
  };

  const handleOpenPayQrPh = () => {
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

  const confirmOpenPayQrPh = () => {
    setShowSafetyAgreement(false);
    setEmbedOpen(true);
  };

  return (
    <div className="min-h-screen bg-background px-4 pt-4">
      <div className="flex items-center gap-3">
        <button onClick={() => navigate("/dashboard")}>
          <ArrowLeft className="h-6 w-6 text-foreground" />
        </button>
        <h1 className="text-lg font-semibold text-paypal-dark">Top Up - Ewallet QR PH</h1>
        <img src={JQRPH_ICON_URL} alt="JQRPh" className="ml-auto h-7 w-auto object-contain" />
        <button
          onClick={() => setShowInstructions(true)}
          className="inline-flex items-center gap-1 rounded-full border border-border px-3 py-1.5 text-xs font-medium text-foreground"
        >
          <HelpCircle className="h-4 w-4" />
          How it works
        </button>
        <button
          onClick={() => setShowSupportedQrPh(true)}
          className="inline-flex items-center gap-1 rounded-full border border-border px-3 py-1.5 text-xs font-medium text-foreground"
        >
          Supported banks
        </button>
      </div>

      <div className="paypal-surface mt-8 rounded-3xl p-6">
        <p className="text-center text-sm text-muted-foreground">Amount to pay</p>
        <p className="mt-1 text-center text-5xl font-bold text-foreground">{phpDisplay} PHP</p>
        <p className="mt-1 text-center text-xs text-muted-foreground">You will receive {openUsdDisplay} OPEN USD (1 OPEN USD = {E_WALLET_PHP_PER_OUSD.toFixed(2)} PHP)</p>
        <p className="mt-2 text-center text-sm font-semibold text-foreground">
          OPEN USD to receive: {openUsdDisplay} OPEN USD
        </p>

        <div className="mt-5 flex justify-center rounded-2xl border border-border bg-white p-4">
          <QRCodeSVG
            key={`${payQrPhUrl}-plain`}
            value={payQrPhUrl}
            size={220}
            includeMargin
            imageSettings={undefined}
          />
        </div>

        <p className="mt-3 text-center text-sm font-medium text-foreground">
          Note: Scanning this QR code will redirect you to a third-party payment provider. Read the top-up instructions below, review all disclaimers, then proceed with your top up.
        </p>

        <TopUpActionGrid
          actions={[
            {
              label: "Pay QR PH",
              onClick: handleOpenPayQrPh,
              icon: <CreditCard className="h-4 w-4" />,
              disabled: roundedOpenUsdAmount <= 0,
            },
            {
              label: "Copy Link",
              onClick: handleCopyQrLink,
              icon: <Copy className="h-4 w-4" />,
            },
            {
              label: "Open Link",
              onClick: () => window.open(payQrPhUrl, "_blank", "noopener,noreferrer"),
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
            {
              label: "Supported Banks",
              onClick: () => setShowSupportedQrPh(true),
              icon: <ListChecks className="h-4 w-4" />,
            },
          ]}
        />

        <Button
          type="button"
          variant="outline"
          className="mt-3 h-11 w-full rounded-2xl"
          onClick={() => setPaymentCompleted(true)}
          disabled={roundedOpenUsdAmount <= 0}
        >
          I completed QR PH payment
        </Button>

        {paymentCompleted && (
          <div className="mt-5 rounded-2xl border border-border bg-white p-4">
            <TopUpAccountDetails providerName="Ewallet QR PH" amount={roundedOpenUsdAmount} submitLabel="Submit Ewallet Top Up" />
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

      <Dialog open={embedOpen} onOpenChange={setEmbedOpen}>
        <DialogContent className="max-w-3xl rounded-2xl">
          <DialogTitle className="text-xl font-bold text-foreground">Pay QR PH</DialogTitle>
          <DialogDescription className="text-sm text-muted-foreground">
            Embedded checkout for: {payQrPhUrl}
          </DialogDescription>
          <div className="mt-2 rounded-xl border border-border bg-white p-2">
            <iframe
              src={payQrPhUrl}
              title="Pay QR PH Embed"
              className="h-[70vh] w-full rounded-lg border border-border"
              loading="lazy"
            />
          </div>
          <Button
            type="button"
            variant="outline"
            className="mt-2 h-10 w-full rounded-xl"
            onClick={() => window.open(payQrPhUrl, "_blank", "noopener,noreferrer")}
          >
            <ExternalLink className="mr-2 h-4 w-4" />
            Open https://paymongo.page/l/openpay
          </Button>
        </DialogContent>
      </Dialog>

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

          <div className="rounded-2xl border border-paypal-light-blue/40 bg-paypal-light-blue/10 p-3 text-xs text-muted-foreground">
            OpenPay is an independent platform built for the Pi Network ecosystem and is not affiliated with any
            government authority or central bank. OpenPay is powered by the Pi digital currency. For more information,
            visit{" "}
            <a href="https://minepi.com" target="_blank" rel="noreferrer" className="font-semibold text-paypal-blue">
              minepi.com
            </a>
            .
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
                <li>Review the final PHP amount displayed.</li>
              </ul>
            </div>

            <div className="rounded-md border-l-4 border-yellow-500 bg-yellow-100 p-3 text-sm">
              <strong>Important:</strong> You must pay the exact amount shown in OpenPay.
            </div>

            <div>
              <h3 className="text-base font-semibold text-teal-700">Step 2: Complete Order Information</h3>
              <ul className="list-disc pl-5">
                <li>OPEN USD Amount</li>
                <li>OpenPay Account Number</li>
                <li>OpenPay Username</li>
                <li>Full Name</li>
                <li>Email Address</li>
                <li>Mobile Number (Optional)</li>
              </ul>
              <p className="mt-2">Ensure all details are correct before proceeding.</p>
            </div>

            <div>
              <h3 className="text-base font-semibold text-teal-700">Step 3: Proceed to Third-Party Payment</h3>
              <ul className="list-disc pl-5">
                <li>Click <strong>Proceed to Checkout</strong>.</li>
                <li>You will be redirected to a secure third-party payment provider.</li>
                <li>Scan the QR code using your e-wallet or banking app.</li>
              </ul>
            </div>

            <div>
              <h3 className="text-base font-semibold text-teal-700">Step 4: Pay the Exact Amount</h3>
              <ul className="list-disc pl-5">
                <li>Confirm the amount matches the OpenPay display.</li>
                <li>Complete payment inside your banking or e-wallet app.</li>
                <li>Wait for payment confirmation.</li>
              </ul>
            </div>

            <div className="rounded-md border-l-4 border-red-600 bg-red-100 p-3 text-sm">
              Payments made with incorrect amounts may result in delays or failed crediting.
            </div>

            <div>
              <h3 className="text-base font-semibold text-teal-700">Step 5: Confirmation</h3>
              <ul className="list-disc pl-5">
                <li>OpenPay will verify your transaction.</li>
                <li>Your balance will be credited after confirmation.</li>
                <li>Processing times may vary depending on the provider.</li>
              </ul>
            </div>

            <p className="text-xs text-muted-foreground">
              OpenPay is a payment technology platform that partners with regulated third-party providers.
              OpenPay is not a bank or financial institution.
            </p>
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

      <Dialog open={showSupportedQrPh} onOpenChange={setShowSupportedQrPh}>
        <DialogContent className="max-h-[85vh] overflow-y-auto rounded-3xl sm:max-w-xl">
          <DialogTitle className="text-xl font-bold text-foreground">See all supported banks and e-wallets</DialogTitle>
          <DialogDescription className="text-sm text-muted-foreground">
            QRPH code supported issuers
          </DialogDescription>

          <div className="space-y-4 text-sm text-foreground">
            <div className="rounded-2xl border border-border p-3">
              <p className="font-semibold">QRPH code Banks</p>
              <p className="mt-2">AllBank (A Thrift Bank), Inc.</p>
              <p>Asia United Bank Corporation (AUB)</p>
              <p>Bank of the Philippine Islands (BPI)</p>
              <p>BDO Unibank Inc.</p>
              <p>Cebuana Lhuillier Rural Bank, Inc.</p>
              <p>China Banking Corporation</p>
              <p>GoTyme Bank Corporation</p>
              <p>Land Bank of the Philippines</p>
              <p>Metropolitan Bank and Trust Company (MetroBank)</p>
              <p>Philippine National Bank (PNB)</p>
              <p>Philippine Savings Bank</p>
              <p>Queen City Development Bank, Inc. or QueenBank, A Thrift Bank</p>
              <p>Rizal Commercial Banking Corporation (RCBC)</p>
              <p>Robinsons Bank Corporation</p>
              <p>Rural Bank of Guinobatan, Inc.</p>
              <p>SeaBank Philippines Inc. (A Rural Bank)</p>
              <p>Security Bank Corporation</p>
              <p>Sterling Bank of Asia, Inc. (A Savings Bank)</p>
              <p>Union Bank of the Philippines (UBP)</p>
            </div>

            <div className="rounded-2xl border border-border p-3">
              <p className="font-semibold">E-wallets</p>
              <p className="mt-2">GCash (G-Xchange, Inc.)</p>
              <p>Maya Philippines, Inc.</p>
              <p>ShopeePay Philippines, Inc.</p>
            </div>

            <div className="rounded-2xl border border-border p-3">
              <p className="font-semibold">Buy Now, Pay Later</p>
              <p className="mt-2">BillEase</p>
              <p>Home Credit</p>
            </div>

            <div className="rounded-2xl border border-border p-3">
              <p className="font-semibold">Other issuers</p>
              <p className="mt-2">CIS Bayad Center, Inc.</p>
              <p>Coins.ph (DCPAY Philippines, Inc.)</p>
              <p>GrabPay (Gpay Network PH, Inc.)</p>
              <p>PalawanPay (PPS-PEPP Financial Services Corporation)</p>
              <p>Starpay Corporation</p>
              <p>TayoCash, Inc.</p>
              <p>Traxion Pay, Inc.</p>
              <p>USSC Money Services, Inc.</p>
              <p>Zybi Tech, Inc.</p>
            </div>
          </div>

          <Button
            type="button"
            className="h-11 w-full rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5]"
            onClick={() => setShowSupportedQrPh(false)}
          >
            Close
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
            onClick={confirmOpenPayQrPh}
          >
            Accept & Continue
          </Button>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default TopUpEwalletQrPh;
