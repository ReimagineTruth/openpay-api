import { useEffect, useMemo, useState } from "react";
import { useNavigate, useSearchParams, useLocation } from "react-router-dom";
import { ArrowLeft, RefreshCw } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import BrandLogo from "@/components/BrandLogo";
import { loadAppSecuritySettings, isPinSetupCompleted } from "@/lib/appSecurity";
import { playGoogleWalletSuccessSound } from "@/lib/soundEffects";
import { PI_TO_USD } from "@/contexts/CurrencyContext";

type SwapWithdrawalRow = {
  id: string;
  amount: number;
  openpay_account_name: string;
  openpay_account_username: string;
  openpay_account_number: string;
  pi_wallet_address: string;
  status: string;
  admin_note: string;
  reviewed_at: string | null;
  created_at: string;
};

const SETTLEMENT_ACCOUNT_NUMBER = "OPEA68BB7A9F964994A199A15786D680FA";
const SETTLEMENT_USERNAME = "@openpay";
const PI_LOGO_URL = "https://i.ibb.co/jk8XtTPj/pi-network-pi-icons-pi-logo-design-illustration-trendy-and-modern-crypto-currency-pi-symbol-for-logo.png";
const WITHDRAWAL_FEE_RATE = 0.02;
const PIN_ACTION_KEY = "openpay_pin_action_swap_v1";
const swapEnabled = String(import.meta.env.VITE_SWAP_ENABLED || "false").toLowerCase() === "true";

const normalizeUsername = (value: string) => value.trim().replace(/^@+/, "").toLowerCase();
const isSchemaCacheMissingError = (message: string | undefined, target: string) =>
  Boolean(message) && message.includes("schema cache") && message.includes(target);

const SwapWithdrawalPage = () => {
  const navigate = useNavigate();
  const location = useLocation();
  const [searchParams] = useSearchParams();

  const handleProtectedAction = async (action: () => Promise<void>) => {
    const { data: { user } } = await supabase.auth.getUser();
    const settings = user ? loadAppSecuritySettings(user.id) : null;
    const pinSetupCompleted = user ? isPinSetupCompleted(user.id) : false;
    
    // Navigate to PIN confirmation page if user has PIN set up
    if (pinSetupCompleted && settings?.pinHash) {
      navigate("/confirm-pin", {
        state: {
          title: "Confirm your OpenPay PIN",
          returnTo: location.pathname + location.search,
          actionData: {
            kind: "swap_withdrawal_submit",
            amount: safeAmount,
            openpayName,
            openpayUsername: normalizedUsername,
            openpayAccountNumber,
            piWalletAddress,
          },
        },
      });
    } else {
      // Proceed directly with action if no PIN set up
      await action();
    }
  };

  useEffect(() => {
    // No PIN redirect flow; proceed without confirm-pin
  }, []);

  const [loading, setLoading] = useState(false);
  const [isInitialLoadDone, setIsInitialLoadDone] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [amount, setAmount] = useState("");
  const [openpayName, setOpenpayName] = useState("");
  const [openpayUsername, setOpenpayUsername] = useState("");
  const [openpayAccountNumber, setOpenpayAccountNumber] = useState("");
  const [piWalletAddress, setPiWalletAddress] = useState("");
  const [agreementAccepted, setAgreementAccepted] = useState(false);
  const [showAgreementModal, setShowAgreementModal] = useState(false);
  const [agreementChecked, setAgreementChecked] = useState(false);
  const [showConfirmModal, setShowConfirmModal] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [history, setHistory] = useState<SwapWithdrawalRow[]>([]);
  const [piPriceUsd] = useState<number>(PI_TO_USD);

  const parsedAmount = Number(amount);
  const safeAmount = Number.isFinite(parsedAmount) && parsedAmount > 0 ? parsedAmount : 0;
  const meetsMinimum = safeAmount >= 10;
  const feeAmount = safeAmount > 0 ? Number((safeAmount * WITHDRAWAL_FEE_RATE).toFixed(2)) : 0;
  const payoutAmount = safeAmount > 0 ? Number((safeAmount - feeAmount).toFixed(2)) : 0;
  const payoutPiAmount = payoutAmount > 0 ? payoutAmount / PI_TO_USD : 0;

  const normalizedUsername = useMemo(() => normalizeUsername(openpayUsername), [openpayUsername]);
  const formattedPiPrice = useMemo(
    () => new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 6 }).format(piPriceUsd),
    [piPriceUsd],
  );

  const loadIdentity = async () => {
    const { data, error } = await supabase.rpc("upsert_my_user_account");
    if (error) return;
    const row = data as { account_number?: string; account_name?: string; account_username?: string } | null;
    setOpenpayAccountNumber((prev) => prev || String(row?.account_number || "").trim().toUpperCase());
    setOpenpayName((prev) => prev || String(row?.account_name || "").trim());
    setOpenpayUsername((prev) => prev || String(row?.account_username || "").trim());
  };

  const loadHistory = async () => {
    setRefreshing(true);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) {
        navigate("/sign-in?mode=signin", { replace: true });
        return;
      }
      const { data, error } = await supabase
        .from("user_swap_withdrawals" as any)
        .select("id, amount, openpay_account_name, openpay_account_username, openpay_account_number, pi_wallet_address, status, admin_note, reviewed_at, created_at")
        .order("created_at", { ascending: false })
        .limit(10);
      if (error) throw new Error(error.message || "Failed to load withdrawals");
      const rows: any[] = Array.isArray(data) ? (data as any[]) : [];
      setHistory(
        rows.map((r: any) => {
          return {
            id: String(r.id ?? ""),
            amount: Number((r.amount as number | string | undefined) ?? 0),
            openpay_account_name: String(r.openpay_account_name ?? ""),
            openpay_account_username: String(r.openpay_account_username ?? ""),
            openpay_account_number: String(r.openpay_account_number ?? ""),
            pi_wallet_address: String(r.pi_wallet_address ?? ""),
            status: String(r.status ?? "pending"),
            admin_note: String(r.admin_note ?? ""),
            reviewed_at: r.reviewed_at ? String(r.reviewed_at) : null,
            created_at: String(r.created_at ?? ""),
          };
        }),
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : "Failed to load withdrawals";
      if (isSchemaCacheMissingError(message, "public.user_swap_withdrawals")) {
        setHistory([]);
        toast.error("Withdrawal history is initializing. Please refresh in a moment.");
        return;
      }
      toast.error(message);
    } finally {
      setRefreshing(false);
    }
  };

  useEffect(() => {
    const boot = async () => {
      await Promise.all([loadIdentity(), loadHistory()]);
      setIsInitialLoadDone(true);
    };
    void boot();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const state = location.state as any;
    let data = state?.actionData || null;
    if (!data) {
      try {
        const raw = typeof window !== "undefined" ? window.sessionStorage.getItem(PIN_ACTION_KEY) : null;
        if (raw) data = JSON.parse(raw);
      } catch {
        // no-op
      }
    }
    if (state?.pinVerified && data?.kind === "swap_withdrawal_submit") {
      void (async () => {
        await submitWithdrawalRequest({
          amount: String(data.amount),
          openpayName: String(data.openpayName || ""),
          openpayUsername: String(data.openpayUsername || ""),
          openpayAccountNumber: String(data.openpayAccountNumber || ""),
          piWalletAddress: String(data.piWalletAddress || ""),
        });
        try {
          if (typeof window !== "undefined") window.sessionStorage.removeItem(PIN_ACTION_KEY);
        } catch {
          // no-op
        }
        navigate(location.pathname + location.search, { replace: true, state: {} });
      })();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [location.state]);

  useEffect(() => {
    const amountParam = searchParams.get("amount");
    if (!amountParam) return;
    const parsed = Number(amountParam);
    if (!Number.isFinite(parsed) || parsed <= 0) return;
    const formatted = parsed.toFixed(2);
    setAmount((prev) => prev || formatted);
  }, [searchParams]);

  const submitWithdrawal = async () => {
    if (!swapEnabled) {
      toast.error("Swap withdrawal is coming soon");
      return;
    }
    if (!Number.isFinite(parsedAmount) || parsedAmount <= 0) {
      toast.error("Enter a valid amount");
      return;
    }
    if (!meetsMinimum) {
      toast.error("Minimum withdrawal is 10 OPEN USD");
      return;
    }
    if (!openpayName.trim() || !normalizedUsername || !openpayAccountNumber.trim() || !piWalletAddress.trim()) {
      toast.error("Complete all required fields");
      return;
    }
    if (!agreementAccepted) {
      setAgreementChecked(false);
      setShowAgreementModal(true);
      return;
    }

    setShowConfirmModal(true);
  };

  const submitWithdrawalRequest = async (overrideData?: {
    amount: string;
    openpayName: string;
    openpayUsername: string;
    openpayAccountNumber: string;
    piWalletAddress: string;
  }) => {
    const activeAmount = overrideData ? Number(overrideData.amount) : safeAmount;
    const activeOpenpayName = overrideData ? overrideData.openpayName : openpayName;
    const activeOpenpayUsername = overrideData ? overrideData.openpayUsername : normalizedUsername;
    const activeOpenpayAccountNumber = overrideData ? overrideData.openpayAccountNumber : openpayAccountNumber;
    const activePiWalletAddress = overrideData ? overrideData.piWalletAddress : piWalletAddress;

    playGoogleWalletSuccessSound();
    setSubmitted(false);
    setLoading(true);
    try {
      const { data, error } = await (supabase as any).rpc("submit_swap_withdrawal", {
        p_amount: activeAmount,
        p_openpay_account_name: activeOpenpayName.trim(),
        p_openpay_account_username: activeOpenpayUsername,
        p_openpay_account_number: activeOpenpayAccountNumber.trim().toUpperCase(),
        p_pi_wallet_address: activePiWalletAddress.trim(),
      });
      if (error) throw new Error(error.message || "Withdrawal submission failed");
      if (data) {
        toast.success("Thank you! Withdrawal request submitted.");
      } else {
        toast.message("Thank you! Withdrawal request submitted.");
      }
      toast.message("Please wait for admin confirmation. You will receive updates in your dashboard activity history.");
      setSubmitted(true);
      setAmount("");
      await loadHistory();
    } catch (error) {
      const message = error instanceof Error ? error.message : "Withdrawal submission failed";
      if (isSchemaCacheMissingError(message, "public.submit_swap_withdrawal")) {
        toast.error("Withdrawal submission is initializing. Please refresh and try again.");
        return;
      }
      toast.error(message);
    } finally {
      setLoading(false);
    }
  };

  const confirmAgreementAndSubmit = async () => {
    if (!agreementChecked) return;
    if (!swapEnabled) {
      toast.error("Swap withdrawal is coming soon");
      return;
    }
    setAgreementAccepted(true);
    setShowAgreementModal(false);
    setShowConfirmModal(true);
  };

  return (
    <div className="min-h-screen bg-background px-4 py-4 pb-10">
      <div className="mx-auto w-full max-w-3xl">
        <div className="mb-4 flex items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            <button onClick={() => navigate("/dashboard")} aria-label="Back">
              <ArrowLeft className="h-6 w-6 text-foreground" />
            </button>
            <div>
              <div className="flex items-center gap-2">
                <div className="flex h-9 w-9 items-center justify-center rounded-2xl bg-paypal-blue/10">
                  <BrandLogo className="h-6 w-6 text-paypal-blue" />
                </div>
                <div>
                  <h1 className="text-xl font-bold text-paypal-dark">OpenPay</h1>
                  <p className="text-xs text-muted-foreground">Swap Withdrawal</p>
                </div>
              </div>
              <p className="text-xs text-muted-foreground">OpenUSD to PI mainnet payout</p>
            </div>
          </div>
          <Button variant="outline" onClick={loadHistory} disabled={refreshing}>
            <RefreshCw className={`mr-2 h-4 w-4 ${refreshing ? "animate-spin" : ""}`} />
            Refresh
          </Button>
        </div>

        <div className="paypal-surface rounded-3xl p-4 space-y-4">
          {!swapEnabled && (
            <div className="rounded-2xl border border-border/70 bg-secondary/30 p-4 text-sm text-muted-foreground">
              <p className="text-base font-semibold text-foreground">Swap Withdrawal</p>
              <p className="mt-2">This feature is coming soon.</p>
              <p className="mt-1">You can view your recent requests below once available.</p>
            </div>
          )}
          <div className="rounded-2xl border border-border/70 bg-secondary/30 p-4 text-sm text-muted-foreground">
            <p className="font-semibold text-foreground">How this works</p>
            <p className="mt-2">1. Fill in your OpenPay identity and mainnet PI wallet address.</p>
            <p>2. When you submit, your OpenUSD is moved to the settlement account {SETTLEMENT_USERNAME} ({SETTLEMENT_ACCOUNT_NUMBER}).</p>
            <p>3. After admin approval, you receive PI to your mainnet wallet. Rate is always 1 PI = 3.14 OPEN USD.</p>
            <p>4. A 2% processing fee applies to withdrawals.</p>
            <div className="mt-3 rounded-xl border border-border/60 bg-secondary/30 p-3 text-xs text-foreground">
              <div className="flex items-center justify-between">
                <span className="inline-flex items-center gap-2">
                  <img src={PI_LOGO_URL} alt="Pi" className="h-4 w-4" />
                  Pi fixed rate
                </span>
                <span className="inline-flex items-center gap-1 font-semibold">
                  <img src={PI_LOGO_URL} alt="Pi" className="h-4 w-4" />
                  <span>π</span>
                  <span>{formattedPiPrice}</span>
                </span>
              </div>
                <div className="mt-1 flex items-center justify-between text-[11px] text-muted-foreground">
                  <span>Fixed</span>
                  <span>1 PI = {PI_TO_USD.toFixed(2)} OPEN USD</span>
                </div>
            </div>
            <p className="mt-2 text-xs text-muted-foreground">
              Processing may be delayed due to high transaction volume or network congestion.
            </p>
          </div>

          <div>
            <p className="text-sm font-semibold text-foreground">Withdrawal details</p>
            <p className="text-xs text-muted-foreground">Confirm your OpenPay identity and enter your PI wallet address.</p>
          </div>

          <div className="mt-4 grid gap-3">
            <label className="space-y-1 text-xs text-muted-foreground">
              <span>OpenUSD amount (min 10)</span>
              <input
                value={amount}
                type="number"
                min="10"
                step="0.01"
                placeholder="Enter amount"
                readOnly
                aria-readonly="true"
                className="h-11 w-full rounded-xl border border-border bg-secondary/30 px-3 text-sm text-foreground"
              />
            </label>
            <label className="space-y-1 text-xs text-muted-foreground">
              <span>OpenPay full name</span>
              <input
                value={openpayName}
                placeholder="Full name"
                readOnly
                aria-readonly="true"
                className="h-11 w-full rounded-xl border border-border bg-secondary/30 px-3 text-sm text-foreground"
              />
            </label>
            <label className="space-y-1 text-xs text-muted-foreground">
              <span>OpenPay username</span>
              <input
                value={openpayUsername}
                placeholder="@username"
                readOnly
                aria-readonly="true"
                className="h-11 w-full rounded-xl border border-border bg-secondary/30 px-3 text-sm text-foreground"
              />
            </label>
            <label className="space-y-1 text-xs text-muted-foreground">
              <span>OpenPay account number</span>
              <input
                value={openpayAccountNumber}
                placeholder="OPEA..."
                readOnly
                aria-readonly="true"
                className="h-11 w-full rounded-xl border border-border bg-secondary/30 px-3 text-sm text-foreground"
              />
            </label>
            <label className="space-y-1 text-xs text-muted-foreground">
              <span>Mainnet PI wallet address</span>
              <input
                value={piWalletAddress}
                onChange={(e) => setPiWalletAddress(e.target.value)}
                placeholder="Pi wallet address"
                readOnly={!swapEnabled}
                aria-readonly={!swapEnabled ? "true" : undefined}
                className="h-11 w-full rounded-xl border border-border px-3 text-sm text-foreground"
              />
              <span className="text-[11px] text-muted-foreground">Make sure this is your PI mainnet address.</span>
            </label>
          </div>

          <div className="mt-4 rounded-2xl border border-border/70 bg-secondary/30 p-3 text-sm text-foreground">
            <div className="flex items-center justify-between">
              <span>Amount</span>
              <span className="font-semibold">{safeAmount.toFixed(2)} OPEN USD</span>
            </div>
            <div className="mt-1 flex items-center justify-between text-xs text-muted-foreground">
              <span>Fee (2%)</span>
              <span>-{feeAmount.toFixed(2)} OPEN USD</span>
            </div>
            <div className="mt-2 flex items-center justify-between">
              <span className="font-semibold">You will receive</span>
              <span className="inline-flex items-center gap-2 font-semibold text-paypal-blue">
                <img src={PI_LOGO_URL} alt="Pi" className="h-5 w-5" />
                {payoutPiAmount.toFixed(4)} PI
              </span>
            </div>
          </div>

          <Button
            className="mt-3 h-11 w-full rounded-xl bg-paypal-blue text-sm font-semibold text-white hover:bg-[#004dc5]"
            onClick={submitWithdrawal}
            disabled={!swapEnabled || loading || !meetsMinimum}
          >
            {!swapEnabled ? "Coming Soon" : loading ? "Submitting..." : "Submit Withdrawal"}
          </Button>
          {submitted ? (
            <div className="mt-3 rounded-xl border border-emerald-200 bg-emerald-50 px-3 py-2 text-xs text-emerald-700">
              Thank you! Your withdrawal request is complete. Please wait for admin confirmation. You will receive updates
              in your dashboard activity history.
            </div>
          ) : null}
          <p className="mt-2 text-xs text-muted-foreground">
            By submitting, you authorize the transfer of your OpenUSD to {SETTLEMENT_USERNAME} ({SETTLEMENT_ACCOUNT_NUMBER}).
          </p>
        </div>

        <div className="mt-4 paypal-surface rounded-3xl p-4">
          <div className="mb-3 flex items-center justify-between">
            <h2 className="text-base font-bold text-foreground">Recent withdrawals</h2>
            <p className="text-xs text-muted-foreground">{history.length} latest</p>
          </div>
          {history.length === 0 ? (
            <p className="text-sm text-muted-foreground">No withdrawal requests yet.</p>
          ) : (
            <div className="divide-y divide-border/70 rounded-2xl border border-border/70">
              {history.map((row, index) => (
                <div key={row.id || index} className="px-3 py-3">
                  <div className="flex items-center justify-between gap-2">
                    <p className="text-sm font-semibold text-foreground">{row.amount.toFixed(2)} OPEN USD</p>
                    <span className="rounded-full border border-border/70 px-2 py-0.5 text-xs font-semibold text-muted-foreground">
                      {row.status}
                    </span>
                  </div>
                  <p className="mt-1 text-xs text-muted-foreground">
                    Pi wallet: {row.pi_wallet_address}
                  </p>
                  {row.admin_note && (
                    <p className="mt-1 text-xs text-muted-foreground">Admin note: {row.admin_note}</p>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      <Dialog open={showAgreementModal} onOpenChange={setShowAgreementModal}>
        <DialogContent className="max-h-[85vh] overflow-y-auto rounded-3xl sm:max-w-lg">
          <DialogTitle className="text-xl font-bold text-foreground">OpenPay Swap Withdrawal Agreement</DialogTitle>
          <DialogDescription className="text-sm text-muted-foreground">
            Please review and accept before proceeding with your swap withdrawal.
          </DialogDescription>
          <div className="rounded-2xl border border-border p-3 text-sm text-foreground">
            <p className="font-semibold">1. Nature of Service</p>
            <p className="mt-1">
              OpenPay facilitates internal balance transfers and swap withdrawal requests. OpenPay is not a bank or
              licensed money service business unless stated under applicable law.
            </p>
            <p className="mt-3 font-semibold">2. Withdrawal Authorization</p>
            <p className="mt-1">By proceeding, you authorize OpenPay to move your OpenUSD to the settlement account.</p>
            <p className="mt-1">You confirm the OpenPay account details and PI wallet address are correct.</p>
            <p className="mt-3 font-semibold">3. Fees and Processing</p>
            <p className="mt-1">A 2% processing fee applies to swap withdrawals.</p>
            <p className="mt-1">Processing time depends on network conditions and admin approval.</p>
            <p className="mt-3 font-semibold">4. User Responsibility</p>
            <p className="mt-1">Verify the withdrawal amount and wallet address before submitting.</p>
            <p className="mt-1">Incorrect details may lead to delayed or failed payouts.</p>
            <p className="mt-3 font-semibold">5. No Deposit Insurance</p>
            <p className="mt-1">OpenPay balances are not insured by any government deposit insurance program.</p>
          </div>
          <label className="flex items-start gap-2 text-sm text-foreground">
            <input
              type="checkbox"
              className="mt-1"
              checked={agreementChecked}
              onChange={(e) => setAgreementChecked(e.target.checked)}
            />
            <span>I understand and agree to proceed with this withdrawal.</span>
          </label>
          <Button
            className="h-11 w-full rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5]"
            disabled={!swapEnabled || !agreementChecked}
            onClick={confirmAgreementAndSubmit}
          >
            {!swapEnabled ? "Coming Soon" : "Accept & Continue"}
          </Button>
        </DialogContent>
      </Dialog>

      
      <Dialog open={showConfirmModal} onOpenChange={setShowConfirmModal}>
        <DialogContent className="rounded-3xl sm:max-w-md">
          <DialogTitle className="text-lg font-bold text-foreground">Confirm Withdrawal</DialogTitle>
          <DialogDescription className="text-sm text-muted-foreground">
            Please confirm the withdrawal details before submitting.
          </DialogDescription>
          <div className="mt-2 rounded-2xl border border-border p-3 text-sm text-foreground space-y-2">
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground">Amount</span>
              <span className="font-semibold">{safeAmount.toFixed(2)} OPEN USD</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground">Fee (2%)</span>
              <span className="font-semibold">-{feeAmount.toFixed(2)} OPEN USD</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground">You will receive</span>
              <span className="font-semibold">{payoutPiAmount.toFixed(4)} PI</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground">PI wallet</span>
              <span className="font-semibold">{piWalletAddress || "N/A"}</span>
            </div>
          </div>
          <div className="mt-3 flex gap-2">
            <Button
              className="flex-1 h-11 rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5]"
              onClick={() => {
                setShowConfirmModal(false);
                handleProtectedAction(submitWithdrawalRequest);
              }}
              disabled={!swapEnabled || loading}
            >
              {!swapEnabled ? "Coming Soon" : "Confirm & Submit"}
            </Button>
            <Button
              variant="outline"
              className="h-11 rounded-2xl"
              onClick={() => setShowConfirmModal(false)}
              disabled={loading}
            >
              Cancel
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default SwapWithdrawalPage;
