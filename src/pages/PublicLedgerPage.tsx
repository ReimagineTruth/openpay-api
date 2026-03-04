import { useEffect, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { ArrowLeft, RefreshCw } from "lucide-react";
import { format } from "date-fns";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { useCurrency } from "@/contexts/CurrencyContext";

type PublicLedgerEntry = {
  amount: number;
  note: string | null;
  status: string;
  occurred_at: string;
  event_type: string;
  currency_code?: string;
  sender_amount?: number;
  sender_currency_code?: string;
  receiver_amount?: number;
  receiver_currency_code?: string;
  payload?: any;
  sender_name?: string;
  sender_username?: string;
  sender_avatar?: string;
  receiver_name?: string;
  receiver_username?: string;
  receiver_avatar?: string;
};

const PAGE_SIZE = 30;
const PI_LOGO_URL = "https://i.ibb.co/jk8XtTPj/pi-network-pi-icons-pi-logo-design-illustration-trendy-and-modern-crypto-currency-pi-symbol-for-logo.png";
const PROVIDER_LOGOS: Record<string, string> = {
  "Pi Payment": PI_LOGO_URL,
  PayPal: "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b5/PayPal.svg/1920px-PayPal.svg.png",
  "Ewallet QR PH": "https://upload.wikimedia.org/wikipedia/commons/thumb/3/35/QR_Ph_Logo.svg/960px-QR_Ph_Logo.svg.png?20250310160234",
  "Apple Pay": "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b0/Apple_Pay_logo.svg/1920px-Apple_Pay_logo.svg.png",
  "Google Pay": "https://upload.wikimedia.org/wikipedia/commons/thumb/5/5c/Google_Pay_Logo.svg/1920px-Google_Pay_Logo.svg.png",
  "Debit Card": "https://i.ibb.co/G3FGwngR/Visa-Inc-logo-2021-present-svg.png",
  "Credit Card": "https://i.ibb.co/9kkZmFDq/Mastercard-2019-logo-svg.png",
  Stripe: "https://upload.wikimedia.org/wikipedia/commons/thumb/b/ba/Stripe_Logo%2C_revised_2016.svg/1920px-Stripe_Logo%2C_revised_2016.svg.png",
  Venmo: "https://upload.wikimedia.org/wikipedia/commons/thumb/4/45/Venmo_Logo.svg/1920px-Venmo_Logo.svg.png",
  "Pi Wallet": PI_LOGO_URL,
};
const isMissingPrivateLedgerRpcError = (message: string | undefined) =>
  Boolean(message) &&
  (message.includes("public.get_private_ledger_transaction")
    || message.includes("Could not find the function public.get_private_ledger_transaction"));

const redactLedgerNote = (note: string) =>
  note
    .replace(/@[\w.-]+/g, "@hidden")
    .replace(/OpenPay\s+[A-Za-z0-9_.-]+/g, "OpenPay [hidden]")
    .replace(/\bWallet\s+[A-Za-z0-9-]{6,}\b/g, "Wallet [hidden]")
    .replace(/\bOPEA[0-9A-Z]{6,}\b/g, "OPEA****")
    .replace(/\bOP[A-Z0-9]{6,}\b/g, (match) => `${match.slice(0, 4)}****`);

const PublicLedgerPage = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const transactionId = (searchParams.get("tx") || "").trim();
  const { currencies } = useCurrency();
  const [entries, setEntries] = useState<PublicLedgerEntry[]>([]);
  const [privateView, setPrivateView] = useState(false);
  const [loading, setLoading] = useState(true);
  const [offset, setOffset] = useState(0);
  const [hasMore, setHasMore] = useState(false);

  const getInitials = (name: string) => (name || "U").split(" ").filter(Boolean).map(n => n[0]).join("").slice(0, 2).toUpperCase();
  const getPiCodeLabel = (code: string) => {
    const upper = String(code || "").toUpperCase();
    if (upper === "PI") return "PI";
    if (upper === "OUSD") return "OPEN USD";
    return `PI ${upper}`;
  };

  const formatAmountWithCurrency = (amount: number, code: string) => {
    const upper = String(code || "OUSD").toUpperCase();
    const meta = currencies.find((currency) => currency.code === upper);
    const symbol = meta?.symbol || (upper === "PI" ? "Ãâ‚¬" : "$");
    const label = getPiCodeLabel(upper);
    const flag = meta?.flag || (upper === "PI" ? "PI" : "OP");
    return `${flag} ${label} ${symbol}${amount.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
  };

  const renderProfile = (
    name?: string,
    avatar?: string,
    username?: string,
    amount?: number,
    currencyCode?: string
  ) => {
    if (!name && !username) return null;
    return (
      <div className="flex items-center gap-2">
        {avatar ? (
          <img src={avatar} alt={name} className="h-6 w-6 rounded-full object-cover border border-border/50" />
        ) : (
          <div className="flex h-6 w-6 items-center justify-center rounded-full bg-secondary text-[10px] font-bold text-muted-foreground border border-border/50">
            {getInitials(name || username || "?")}
          </div>
        )}
        <div className="flex flex-col">
          <span className="text-[11px] font-semibold text-foreground leading-tight">
            {name || (username ? `@${username}` : "")}
          </span>
          {username && name && <span className="text-[9px] text-muted-foreground leading-tight">@{username}</span>}
          {Number.isFinite(amount) && currencyCode && (
            <span className="text-[9px] text-muted-foreground leading-tight">
              {formatAmountWithCurrency(Number(amount), currencyCode)}
            </span>
          )}
        </div>
      </div>
    );
  };

  const loadPage = async (nextOffset = 0) => {
    setLoading(true);
    try {
      const { data, error } = await supabase.rpc("get_public_ledger", {
        p_limit: PAGE_SIZE,
        p_offset: nextOffset,
      });

      if (error) throw new Error(error.message || "Failed to load ledger.");

      const rows = (data || []) as PublicLedgerEntry[];
      setEntries(rows);
      setOffset(nextOffset);
      setHasMore(rows.length === PAGE_SIZE);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to load ledger.");
    } finally {
      setLoading(false);
    }
  };

  const loadTransaction = async (txId: string) => {
    setLoading(true);
    try {
      const { data: userData } = await supabase.auth.getUser();
      const isSignedIn = Boolean(userData?.user);
      let rpcName = isSignedIn
        ? "get_private_ledger_transaction"
        : "get_public_ledger_transaction";
      let { data, error } = await (supabase as any).rpc(rpcName, { p_transaction_id: txId });

      if (isSignedIn && error && isMissingPrivateLedgerRpcError(error.message)) {
        rpcName = "get_public_ledger_transaction";
        ({ data, error } = await (supabase as any).rpc(rpcName, { p_transaction_id: txId }));
      }

      if (error) throw new Error(error.message || "Failed to load ledger transaction.");
      const row = Array.isArray(data) ? data[0] : data;
      setEntries(row ? [row as PublicLedgerEntry] : []);
      setPrivateView(Boolean(row) && isSignedIn && rpcName === "get_private_ledger_transaction");
      setOffset(0);
      setHasMore(false);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to load ledger transaction.");
      setEntries([]);
      setPrivateView(false);
      setOffset(0);
      setHasMore(false);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (transactionId) {
      void loadTransaction(transactionId);
      return;
    }
    void loadPage(0);
  }, [transactionId]);

  return (
    <div className="min-h-screen bg-background px-4 pt-4 pb-10">
      <div className="mb-4 flex items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <button onClick={() => navigate("/")} aria-label="Back to home">
            <ArrowLeft className="h-6 w-6 text-foreground" />
          </button>
          <div>
            <h1 className="text-xl font-bold text-paypal-dark">OpenLedger</h1>
            <p className="text-xs text-muted-foreground">
              {transactionId
                ? `OpenLedger record for transaction ${transactionId.slice(0, 8)}...`
                : "OpenLedger transaction history. User IDs are not shown."}
            </p>
          </div>
        </div>
        <button
          onClick={() => (transactionId ? loadTransaction(transactionId) : loadPage(offset))}
          className="paypal-surface flex h-9 items-center gap-2 rounded-full px-3 text-sm font-semibold text-foreground"
          disabled={loading}
        >
          <RefreshCw className={`h-4 w-4 ${loading ? "animate-spin" : ""}`} />
          Refresh
        </button>
      </div>

      {entries.length === 0 && !loading ? (
        <p className="py-12 text-center text-muted-foreground">No ledger transactions yet.</p>
      ) : (
        <div className="paypal-surface divide-y divide-border/70 rounded-3xl">
          {entries.map((row, index) => {
            const evt = (row.event_type || "").toLowerCase();
            const isTopup = evt.includes("topup") || evt.includes("deposit") || evt.includes("receive") || evt.includes("incoming");
            const isWithdraw = evt.includes("withdraw") || evt.includes("payout") || evt.includes("send") || evt.includes("outgoing") || evt.includes("payment");
            const paymentMethod = String(row.payload?.payment_method || row.payload?.provider || "").trim();
            const providerLogo = paymentMethod ? PROVIDER_LOGOS[paymentMethod] : "";
            const noteHint = String(row.note || "").toLowerCase();
            const inferredPiLogo = (isTopup || isWithdraw) && (noteHint.includes("pi") || noteHint.includes("wallet top up"));
            const methodLogo =
              row.payload?.payment_method_logo ||
              row.payload?.logo_url ||
              providerLogo ||
              (row.payload?.pi_wallet_address ? PI_LOGO_URL : "") ||
              (inferredPiLogo ? PI_LOGO_URL : "");
            const currencyCode = String(row.currency_code || "OUSD").toUpperCase();
            const currencyMeta = currencies.find((currency) => currency.code === currencyCode);
            const currencyFlag = currencyMeta?.flag || (currencyCode === "PI" ? "PI" : "OP");
            const currencySymbol = currencyMeta?.symbol || (currencyCode === "PI" ? "Ï€" : "$");
            const currencyLabel = getPiCodeLabel(currencyCode);
            const senderCurrencyCode = String(row.sender_currency_code || row.payload?.sender_currency_code || currencyCode || "OUSD").toUpperCase();
            const receiverCurrencyCode = String(row.receiver_currency_code || row.payload?.receiver_currency_code || currencyCode || "OUSD").toUpperCase();
            const senderAmountRaw = row.sender_amount ?? row.payload?.sender_amount ?? row.amount;
            const receiverAmountRaw = row.receiver_amount ?? row.payload?.receiver_amount ?? row.amount;
            const senderAmountValue = Number(senderAmountRaw || 0);
            const receiverAmountValue = Number(receiverAmountRaw || 0);
            const senderMeta = currencies.find((currency) => currency.code === senderCurrencyCode);
            const receiverMeta = currencies.find((currency) => currency.code === receiverCurrencyCode);
            const senderSymbol = senderMeta?.symbol || (senderCurrencyCode === "PI" ? "Ï€" : "$");
            const receiverSymbol = receiverMeta?.symbol || (receiverCurrencyCode === "PI" ? "Ï€" : "$");
            const senderFlag = senderMeta?.flag || (senderCurrencyCode === "PI" ? "PI" : "OP");
            const receiverFlag = receiverMeta?.flag || (receiverCurrencyCode === "PI" ? "PI" : "OP");
            const senderLabel = getPiCodeLabel(senderCurrencyCode);
            const receiverLabel = getPiCodeLabel(receiverCurrencyCode);
            const showTransferAmounts = Number.isFinite(senderAmountValue) && Number.isFinite(receiverAmountValue);
            const currencyIcon = currencySymbol;
            const primaryName = row.receiver_name || row.sender_name || "";
            const primaryAvatar = row.receiver_avatar || row.sender_avatar || "";
            const primaryUsername = row.receiver_username || row.sender_username || "";
            const numericAmount = Number(row.amount ?? receiverAmountValue ?? senderAmountValue ?? 0);
            const displayAmountValue = Number.isFinite(receiverAmountValue)
              ? receiverAmountValue
              : Number.isFinite(senderAmountValue)
                ? senderAmountValue
                : numericAmount;
            const displayCurrencySymbol = Number.isFinite(receiverAmountValue)
              ? receiverSymbol
              : Number.isFinite(senderAmountValue)
                ? senderSymbol
                : currencySymbol;
            const amountClass =
              numericAmount > 0
                ? "text-green-600"
                : numericAmount < 0
                  ? "text-red-600"
                  : isTopup
                    ? "text-green-600"
                    : isWithdraw
                      ? "text-red-600"
                      : "text-foreground";
            
            return (
              <div key={`${row.occurred_at}-${index}`} className="flex flex-col gap-2 p-4 sm:flex-row sm:items-center sm:justify-between">
                <div className="flex items-start gap-3 flex-1 min-w-0">
                  {(isTopup || isWithdraw) && methodLogo ? (
                    <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-secondary/50 overflow-hidden border border-border/50">
                      <img src={methodLogo} alt="Method" className="h-6 w-6 object-contain" />
                    </div>
                  ) : (
                    primaryName || primaryUsername ? (
                      primaryAvatar ? (
                        <img src={primaryAvatar} alt={primaryName || primaryUsername} className="h-10 w-10 shrink-0 rounded-full object-cover border border-border/50" />
                      ) : (
                        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-secondary text-xs font-bold text-muted-foreground border border-border/50">
                          {getInitials(primaryName || primaryUsername || "?")}
                        </div>
                      )
                    ) : (
                      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-paypal-blue/10 text-paypal-blue font-bold">
                        {currencyIcon}
                      </div>
                    )
                  )}
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <p className="font-semibold text-foreground">{isTopup ? "Top Up" : isWithdraw ? "Swap" : "Transaction"}</p>
                      {currencyCode && (
                        <span className="rounded-md bg-secondary px-1.5 py-0.5 text-[10px] font-bold text-muted-foreground uppercase">
                          {currencyFlag} {currencyLabel}
                        </span>
                      )}
                      {(row.sender_name || row.sender_username || row.receiver_name || row.receiver_username) && (
                        <span className="text-[11px] font-semibold text-muted-foreground">
                          â€¢ {(row.sender_name || row.sender_username || "Sender")}
                          {" â†’ "}
                          {(row.receiver_name || row.receiver_username || "Receiver")}
                        </span>
                      )}
                    </div>
                    <p className="text-[10px] text-muted-foreground">
                      {format(new Date(row.occurred_at), "MMM d, yyyy HH:mm")} â€¢ {(row.event_type || "").replace(/_/g, " ")}
                    </p>
                    {showTransferAmounts && (
                      <p className="text-[11px] text-muted-foreground mt-1">
                        Sender: {senderFlag} {senderLabel} {senderSymbol}{senderAmountValue.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} â†’ Receiver: {receiverFlag} {receiverLabel} {receiverSymbol}{receiverAmountValue.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                      </p>
                    )}
                    
                    <div className="mt-2 flex items-center gap-2 flex-wrap">
                      {(row.sender_name || row.sender_username) && renderProfile(
                        row.sender_name,
                        row.sender_avatar,
                        row.sender_username,
                        senderAmountValue,
                        senderCurrencyCode
                      )}
                      {(row.sender_name || row.sender_username) && (row.receiver_name || row.receiver_username) && (
                        <span className="text-muted-foreground text-[10px]">â†’</span>
                      )}
                      {(row.receiver_name || row.receiver_username) && renderProfile(
                        row.receiver_name,
                        row.receiver_avatar,
                        row.receiver_username,
                        receiverAmountValue,
                        receiverCurrencyCode
                      )}
                    </div>

                    {row.note && (
                      <p className="text-[11px] text-muted-foreground mt-1.5 italic line-clamp-2">
                        {privateView ? row.note : redactLedgerNote(row.note)}
                      </p>
                    )}
                    <p className="text-[9px] font-medium text-muted-foreground uppercase tracking-wider mt-1">
                      Status: <span className={row.status === "completed" ? "text-green-600" : "text-amber-600"}>{row.status || "unknown"}</span>
                    </p>
                  </div>
                </div>
                <div className="text-right sm:ml-4">
                  <p className={`font-bold ${amountClass}`}>
                    {displayCurrencySymbol}{displayAmountValue.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                  </p>
                  <p className="text-[10px] text-muted-foreground uppercase font-semibold">OpenLedger Record</p>
                </div>
              </div>
            );
          })}
        </div>
      )}

      <div className="mt-4 flex items-center justify-end gap-2">
        <button
          className="paypal-surface h-9 rounded-full px-4 text-sm font-semibold text-foreground disabled:opacity-50"
          onClick={() => loadPage(Math.max(0, offset - PAGE_SIZE))}
          disabled={loading || offset === 0 || !!transactionId}
        >
          Previous
        </button>
        <button
          className="paypal-surface h-9 rounded-full px-4 text-sm font-semibold text-foreground disabled:opacity-50"
          onClick={() => loadPage(offset + PAGE_SIZE)}
          disabled={loading || !hasMore || !!transactionId}
        >
          Next
        </button>
      </div>
    </div>
  );
};

export default PublicLedgerPage;
