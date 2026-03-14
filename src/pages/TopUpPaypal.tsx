import { useEffect, useRef, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { ArrowLeft, Copy, HelpCircle, ExternalLink, FileText, LifeBuoy, CreditCard, MessageCircle, History } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import TopUpAccountDetails from "@/components/TopUpAccountDetails";
import RegulatoryStatusModal from "@/components/RegulatoryStatusModal";
import TopUpActionGrid from "@/components/TopUpActionGrid";

const PAYPAL_ICON_URL = "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b5/PayPal.svg/1920px-PayPal.svg.png";
const PAYPAL_CLIENT_ID = "BAABvvC7_J4mukHtbKyyIkmPBX7N1UzqgAkCmei4q0NbUxp4nBMiCxVLKir2SdQ68p5hbosDBWF8pvLFdE";
const PAYPAL_HOSTED_BUTTON_ID = "22Y6YDQAUV6B2";
const PAYPAL_DIRECT_URL = "https://www.paypal.com/ncp/payment/22Y6YDQAUV6B2";

declare global {
  interface Window {
    paypal?: {
      HostedButtons: (options: { hostedButtonId: string }) => { render: (selector: string) => Promise<void> };
    };
  }
}

const TopUpPaypal = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [showInstructions, setShowInstructions] = useState(false);
  const [showTopUpInstructions, setShowTopUpInstructions] = useState(false);
  const [showSafetyAgreement, setShowSafetyAgreement] = useState(false);
  const [safetyAgreementChecked, setSafetyAgreementChecked] = useState(false);
  const [safetyAccepted, setSafetyAccepted] = useState(false);
  const [paymentCompleted, setPaymentCompleted] = useState(false);
  const [showRegulatoryModal, setShowRegulatoryModal] = useState(false);
  const paypalButtonRef = useRef<HTMLDivElement | null>(null);
  const paypalSectionRef = useRef<HTMLDivElement | null>(null);

  const parsedUsdAmount = Number(searchParams.get("openUsdAmount") || searchParams.get("amount") || "0");
  const safeUsdAmount = Number.isFinite(parsedUsdAmount) && parsedUsdAmount > 0 ? parsedUsdAmount : 0;
  const usdDisplay = safeUsdAmount > 0 ? safeUsdAmount.toFixed(2) : "0.00";
  const paypalAmount = Number(usdDisplay);
  const openUsdDisplay = usdDisplay;
  const paypalCheckoutUrl = PAYPAL_DIRECT_URL;

  const handleCopyPaypalLink = async () => {
    try {
      await navigator.clipboard.writeText(paypalCheckoutUrl);
      toast.success("PayPal link copied");
    } catch {
      toast.error("Copy failed");
    }
  };

  const handleOpenPaypal = () => {
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

  const confirmOpenPaypal = () => {
    setSafetyAccepted(true);
    setShowSafetyAgreement(false);
  };

  useEffect(() => {
    if (!safeUsdAmount || !safetyAccepted || !paypalButtonRef.current) return;

    const scriptId = "paypal-js-sdk";
    const existing = document.getElementById(scriptId) as HTMLScriptElement | null;
    const loadScript = () =>
      new Promise<void>((resolve, reject) => {
        if (window.paypal) {
          resolve();
          return;
        }
        const script = document.createElement("script");
        script.id = scriptId;
        script.src = `https://www.paypal.com/sdk/js?client-id=${encodeURIComponent(
          PAYPAL_CLIENT_ID
        )}&components=hosted-buttons&disable-funding=venmo&currency=USD`;
        script.async = true;
        script.crossOrigin = "anonymous";
        script.onload = () => resolve();
        script.onerror = () => reject(new Error("Failed to load PayPal SDK"));
        document.body.appendChild(script);
      });

    const renderButton = async () => {
      try {
        if (!existing && !window.paypal) {
          await loadScript();
        } else if (existing && !window.paypal) {
          await new Promise<void>((resolve, reject) => {
            existing.addEventListener("load", () => resolve(), { once: true });
            existing.addEventListener("error", () => reject(new Error("Failed to load PayPal SDK")), { once: true });
          });
        }
        if (!window.paypal || !paypalButtonRef.current) return;
        if (paypalButtonRef.current.getAttribute("data-rendered") === "true") {
          return;
        }

        paypalButtonRef.current.innerHTML = "";
        paypalButtonRef.current.setAttribute("data-rendered", "true");
        const containerId = `paypal-container-${PAYPAL_HOSTED_BUTTON_ID}`;
        const container = document.createElement("div");
        container.id = containerId;
        paypalButtonRef.current.appendChild(container);

        if (!window.paypal?.HostedButtons) {
          throw new Error("PayPal Hosted Buttons is unavailable.");
        }

        await window.paypal.HostedButtons({
          hostedButtonId: PAYPAL_HOSTED_BUTTON_ID,
        }).render(`#${containerId}`);
      } catch {
        toast.error("Unable to load PayPal button.");
      }
    };

    void renderButton();
  }, [safeUsdAmount, safetyAccepted]);

  return (
    <div className="min-h-screen bg-background px-4 pt-4">
      <div className="flex items-center gap-3">
        <button onClick={() => navigate("/dashboard")}>
          <ArrowLeft className="h-6 w-6 text-foreground" />
        </button>
        <h1 className="text-lg font-semibold text-paypal-dark">Top Up - PayPal</h1>
        <img src={PAYPAL_ICON_URL} alt="PayPal" className="ml-auto h-7 w-auto object-contain" />
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
        <p className="mt-1 text-center text-xs text-muted-foreground">You will receive {openUsdDisplay} OPEN USD (1 OPEN USD = 1 USD)</p>
        <p className="mt-2 text-center text-sm font-semibold text-foreground">
          OPEN USD to receive: {openUsdDisplay} OPEN USD
        </p>

        {safeUsdAmount > 0 && (
          <div ref={paypalSectionRef} className="mt-5 rounded-2xl border border-border bg-blue-50 p-4">
            <p className="text-center text-xs font-semibold text-muted-foreground">Pay with PayPal</p>
            {!safetyAccepted ? (
              <div className="mt-3 flex justify-center">
                <button
                  type="button"
                  onClick={handleOpenPaypal}
                  className="paypal-surface w-full max-w-md rounded-md border border-border bg-[#ffc439] py-3 text-center text-base font-semibold text-[#003087] shadow-sm"
                >
                  PayPal
                </button>
              </div>
            ) : (
              <div ref={paypalButtonRef} className="mt-3 w-full sm:max-w-md sm:mx-auto" />
            )}
          </div>
        )}

        <p className="mt-3 text-center text-sm font-medium text-foreground">
          Note: PayPal checkout will redirect you to PayPal. Review the top-up instructions below, then proceed with your top up.
        </p>

        <TopUpActionGrid
          actions={[
            {
              label: "Pay with PayPal",
              onClick: () => {
                if (!safetyAccepted) {
                  handleOpenPaypal();
                  return;
                }
                paypalSectionRef.current?.scrollIntoView({ behavior: "smooth", block: "center" });
              },
              icon: <CreditCard className="h-4 w-4" />,
            },
            {
              label: "Copy Link",
              onClick: handleCopyPaypalLink,
              icon: <Copy className="h-4 w-4" />,
            },
            {
              label: "Open Link",
              onClick: () => window.open(PAYPAL_DIRECT_URL, "_blank"),
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
        >
          I completed PayPal payment
        </Button>

        {paymentCompleted && (
          <div className="mt-5 rounded-2xl border border-border bg-blue-50 p-4">
            <TopUpAccountDetails providerName="PayPal" amount={safeUsdAmount} submitLabel="Submit PayPal Top Up" />
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
                <li>Review the final USD amount displayed.</li>
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
              <h3 className="text-base font-semibold text-teal-700">Step 3: Proceed to PayPal</h3>
              <ul className="list-disc pl-5">
                <li>Click <strong>Proceed to Checkout</strong>.</li>
                <li>You will be redirected to PayPal for payment authorization.</li>
              </ul>
            </div>

            <div>
              <h3 className="text-base font-semibold text-teal-700">Step 4: Pay the Exact Amount</h3>
              <ul className="list-disc pl-5">
                <li>Confirm the amount matches the OpenPay display.</li>
                <li>Complete payment inside PayPal.</li>
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
            onClick={confirmOpenPaypal}
          >
            Pay with PayPal
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

      <RegulatoryStatusModal open={showRegulatoryModal} onOpenChange={setShowRegulatoryModal} />
    </div>
  );
};

export default TopUpPaypal;
