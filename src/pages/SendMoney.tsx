import { useEffect, useState, useCallback } from "react";
import { useNavigate, useSearchParams, useLocation } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { SlideToConfirm } from "@/components/ui/slide-to-confirm";
import { ArrowLeft, Search, Info, ScanLine, Bookmark, BookmarkCheck, Loader2, FileText, Users, X, Check } from "lucide-react";
import { toast } from "sonner";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { useCurrency } from "@/contexts/CurrencyContext";
import { getFunctionErrorMessage } from "@/lib/supabaseFunctionError";
import CurrencySelector from "@/components/CurrencySelector";
import TransactionReceipt, { type ReceiptData } from "@/components/TransactionReceipt";
import NumberPad from "@/components/NumberPad";
import { loadAppSecuritySettings, isPinSetupCompleted } from "@/lib/appSecurity";
import SplashScreen from "@/components/SplashScreen";
 
type PinReturnState = {
  pinVerified?: boolean;
  actionData?: {
    selectedUser?: UserProfile;
    selectedUsers?: UserProfile[];
    isMultiSend?: boolean;
    amount?: string;
    note?: string;
    step?: "select" | "amount" | "confirm";
  };
} | null;

interface UserProfile {
  id: string;
  full_name: string;
  username: string | null;
  avatar_url?: string | null;
}

interface RecentRecipient extends UserProfile {
  last_sent_at: string;
}

const sendSuccessSoundUrl = "https://www.myinstants.com/media/sounds/applepay.mp3";
const OPENPAY_ICON_URL = "/openpay-o.svg";
let sendSuccessAudio: HTMLAudioElement | null = null;
let sendSoundUnlocked = false;

const playSendSuccessSound = () => {
  if (typeof window === "undefined") return;

  const playFallbackTone = () => {
    const AudioCtx = window.AudioContext || (window as typeof window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!AudioCtx) return;
    try {
      const context = new AudioCtx();
      const gain = context.createGain();
      gain.connect(context.destination);
      gain.gain.setValueAtTime(0.0001, context.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.08, context.currentTime + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, context.currentTime + 0.2);

      const osc1 = context.createOscillator();
      osc1.type = "triangle";
      osc1.frequency.setValueAtTime(784, context.currentTime);
      osc1.connect(gain);
      osc1.start(context.currentTime);
      osc1.stop(context.currentTime + 0.09);

      const osc2 = context.createOscillator();
      osc2.type = "triangle";
      osc2.frequency.setValueAtTime(1046, context.currentTime + 0.1);
      osc2.connect(gain);
      osc2.start(context.currentTime + 0.1);
      osc2.stop(context.currentTime + 0.19);

      osc2.onended = () => {
        void context.close();
      };
    } catch {
      // no-op
    }
  };

  try {
    if (!sendSuccessAudio) {
      sendSuccessAudio = new Audio(sendSuccessSoundUrl);
      sendSuccessAudio.preload = "auto";
      sendSuccessAudio.volume = 0.95;
    }
    sendSuccessAudio.currentTime = 0;
    const playPromise = sendSuccessAudio.play();
    if (playPromise && typeof playPromise.catch === "function") {
      void playPromise.catch(() => {
        playFallbackTone();
      });
    }
  } catch {
    playFallbackTone();
  }
};

const SendMoney = () => {
  const [step, setStep] = useState<"select" | "amount" | "confirm">("select");
  const [searchQuery, setSearchQuery] = useState("");
  const [contacts, setContacts] = useState<UserProfile[]>([]);
  const [allUsers, setAllUsers] = useState<UserProfile[]>([]);
  const [recentRecipients, setRecentRecipients] = useState<RecentRecipient[]>([]);
  const [contactIds, setContactIds] = useState<string[]>([]);
  const [balance, setBalance] = useState(0);
  const [selectedUser, setSelectedUser] = useState<UserProfile | null>(null);
  const [selectedUsers, setSelectedUsers] = useState<UserProfile[]>([]);
  const [isMultiSend, setIsMultiSend] = useState(false);
  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("");
  const [purpose, setPurpose] = useState("");
  const [customPurpose, setCustomPurpose] = useState("");
  const [showPurposeSelector, setShowPurposeSelector] = useState(false);
  const [paymentPurposes, setPaymentPurposes] = useState<any[]>([]);
  const [isPosCheckoutSession, setIsPosCheckoutSession] = useState(false);
  const [loading, setLoading] = useState(false);
  const [slideConfirmLoading, setSlideConfirmLoading] = useState(false);
  const [isInitialLoadDone, setIsInitialLoadDone] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);
  const [showSendConfirm, setShowSendConfirm] = useState(false);
  const [receiptOpen, setReceiptOpen] = useState(false);
  const [receiptData, setReceiptData] = useState<ReceiptData | null>(null);
  const [myAvatarUrl, setMyAvatarUrl] = useState<string | null>(null);
  const [myFullName, setMyFullName] = useState("");
  const [accountLookupResult, setAccountLookupResult] = useState<UserProfile | null>(null);
  const [accountLookupLoading, setAccountLookupLoading] = useState(false);
  const [transactions, setTransactions] = useState<any[]>([]);
  const [userId, setUserId] = useState<string>("");
  const navigate = useNavigate();
  const location = useLocation();
  const [searchParams] = useSearchParams();
  const { currencies, currency, setCurrency, format: formatCurrency } = useCurrency();
  const checkoutSessionToken = searchParams.get("checkout_session") || "";
  const checkoutCustomerName = searchParams.get("checkout_customer_name") || "";
  const checkoutCustomerEmail = searchParams.get("checkout_customer_email") || "";
  const checkoutCustomerPhone = searchParams.get("checkout_customer_phone") || "";
  const checkoutCustomerAddress = searchParams.get("checkout_customer_address") || "";
  const posSessionToken = searchParams.get("pos_session") || "";
  const formatShortText = (value: string, head = 28, tail = 18) => {
    const cleaned = value.trim();
    if (cleaned.length <= head + tail + 3) return cleaned;
    return `${cleaned.slice(0, head)}...${cleaned.slice(-tail)}`;
  };

  useEffect(() => {
    if (typeof window === "undefined") return;
    const unlockAudio = () => {
      if (sendSoundUnlocked) return;
      sendSoundUnlocked = true;
      if (!sendSuccessAudio) {
        sendSuccessAudio = new Audio(sendSuccessSoundUrl);
        sendSuccessAudio.preload = "auto";
        sendSuccessAudio.volume = 0.95;
      }
      sendSuccessAudio.load();
      const AudioCtx = window.AudioContext || (window as typeof window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
      if (!AudioCtx) return;
      try {
        const ctx = new AudioCtx();
        if (ctx.state === "suspended") {
          void ctx.resume().finally(() => {
            void ctx.close();
          });
        } else {
          void ctx.close();
        }
      } catch {
        // no-op
      }
    };
    const events: Array<keyof WindowEventMap> = ["pointerdown", "touchend", "keydown"];
    for (const eventName of events) {
      window.addEventListener(eventName, unlockAudio, { passive: true });
    }
    return () => {
      for (const eventName of events) {
        window.removeEventListener(eventName, unlockAudio);
      }
    };
  }, []);

  useEffect(() => {
    const checkPinVerification = async () => {
      // Wait until initial balance and data are loaded before processing PIN result
      if (!isInitialLoadDone) return;

      const state = location.state as PinReturnState;
      console.log('PIN verification state:', state);
      if (state?.pinVerified && state?.actionData) {
        // Restore state from before PIN redirect
        const data = state.actionData;
        console.log('Restoring action data from PIN:', data);
        
        // Execute send immediately
        void handleSend(data.selectedUser, data.amount, data.note, data.selectedUsers, data.isMultiSend);

        // Clear location state to prevent re-triggering if component re-renders
        navigate(location.pathname, { replace: true, state: {} });

        // Also update local state so UI is consistent if needed
        if (data.selectedUser) setSelectedUser(data.selectedUser);
        if (data.selectedUsers) setSelectedUsers(data.selectedUsers);
        if (data?.isMultiSend !== undefined) setIsMultiSend(data.isMultiSend);
        if (data.amount) setAmount(data.amount);
        if (data.note) setNote(data.note);
        if (data.step) setStep(data.step);
      }
    };
    checkPinVerification();
  }, [location.state, navigate, location.pathname, isInitialLoadDone]);

  const refreshTransactions = useCallback(async () => {
    if (!userId) return;
    
    try {
      const { data: txs } = await supabase
        .from("transactions")
        .select("*")
        .or(`sender_id.eq.${userId},receiver_id.eq.${userId}`)
        .order("created_at", { ascending: false })
        .limit(10);

      if (txs) {
        const enriched = await Promise.all(
          txs.map(async (tx) => {
            const otherId = tx.sender_id === userId ? tx.receiver_id : tx.sender_id;
            const { data: p } = await supabase
              .from("profiles")
              .select("full_name, username, avatar_url")
              .eq("id", otherId)
              .single();
            return {
              ...tx,
              other_name: p?.full_name || "Unknown",
              other_username: p?.username || null,
              other_avatar_url: p?.avatar_url || null,
              is_sent: tx.sender_id === userId,
              is_topup: tx.sender_id === userId && tx.receiver_id === userId,
            };
          }),
        );
        setTransactions(enriched);
      }
    } catch (error) {
      console.error("Failed to refresh transactions:", error);
      toast.error("Failed to refresh transactions");
    }
  }, [userId]);

  const handleSend = async (overrideUser?: UserProfile, overrideAmount?: string, overrideNote?: string, overrideUsers?: UserProfile[], overrideIsMultiSend?: boolean) => {
    if (loading) return; // Prevent double spending by checking if already loading

    const activeIsMultiSend = overrideIsMultiSend !== undefined ? overrideIsMultiSend : isMultiSend;
    const activeUser = overrideUser || selectedUser;
    const activeUsers = overrideUsers || selectedUsers;
    const activeAmount = overrideAmount || amount;
    const activeNote = overrideNote !== undefined ? overrideNote : note;

    const parsedAmount = parseFloat(activeAmount);
    if ((!activeUser && activeUsers.length === 0) || !activeAmount || parsedAmount <= 0) { 
      toast.error("Enter a valid amount"); 
      return; 
    }
    
    const isActuallyMultiSend = activeIsMultiSend && activeUsers.length > 0;
    const totalAmount = isActuallyMultiSend ? (parsedAmount * activeUsers.length) : parsedAmount;
    const rate = Number(currency?.rate || 1);
    const usdAmountPerUser = parsedAmount / (rate > 0 ? rate : 1);
    const totalUsdAmount = totalAmount / (rate > 0 ? rate : 1);
    
    if (totalUsdAmount > balance) { 
      toast.error("Amount exceeds your available balance"); 
      return; 
    }
    
    setLoading(true); // Lock the UI immediately after basic validation

    try {
      if (isActuallyMultiSend) {
        // Multi-send logic using RPC
        const recipientIds = activeUsers.map(u => u.id);
        const amounts = activeUsers.map(() => Number(usdAmountPerUser.toFixed(2))); // Ensure numeric and limited precision
        const notes = activeUsers.map(() => activeNote || "");

        console.log('Initiating bulk transfer:', {
          recipientCount: recipientIds.length,
          amountPerUser: usdAmountPerUser,
          totalAmount: totalUsdAmount,
          recipientIds,
          amounts
        });

        const { data: rpcData, error: rpcError } = await (supabase as any).rpc("bulk_transfer_funds", {
          p_recipients: recipientIds,
          p_amounts: amounts,
          p_notes: notes,
          p_currency_code: currency.code,
          p_sender_amount: parsedAmount,
          p_sender_currency_code: currency.code,
          p_receiver_currency_code: "OUSD",
        });

        let result = rpcData as any;

        if (rpcError) {
          const rpcMessage =
            typeof (rpcError as { message?: unknown })?.message === "string"
              ? (rpcError as { message: string }).message
              : "Bulk transfer failed";
          const shouldTryLegacy =
            /schema cache|bulk_transfer_funds|function.*not\s+found/i.test(rpcMessage);

          if (!shouldTryLegacy) {
            console.error('Bulk transfer RPC error:', rpcError);
            throw new Error(rpcMessage);
          }

          const { data: legacyData, error: legacyError } = await (supabase as any).rpc("bulk_transfer_funds", {
            p_recipients: recipientIds,
            p_amounts: amounts,
            p_notes: notes,
          });

          if (!legacyError) {
            result = legacyData as any;
          } else {
            const legacyMessage =
              typeof (legacyError as { message?: unknown })?.message === "string"
                ? (legacyError as { message: string }).message
                : "Bulk transfer failed";
            const shouldFallbackToSingle =
              /schema cache|bulk_transfer_funds|function.*not\s+found/i.test(legacyMessage);

            if (!shouldFallbackToSingle) {
              console.error('Bulk transfer legacy RPC error:', legacyError);
              throw new Error(legacyMessage);
            }

            const transferSingle = async (recipientId: string, noteText: string) => {
              const { data: txId, error: txError } = await supabase.rpc("transfer_funds_authenticated", {
                p_receiver_id: recipientId,
                p_amount: usdAmountPerUser,
                p_note: noteText || "",
                p_currency_code: currency.code,
                p_sender_amount: parsedAmount,
                p_sender_currency_code: currency.code,
                p_receiver_amount: usdAmountPerUser,
                p_receiver_currency_code: "OUSD",
              });

              if (!txError) return String(txId || "");

              const txMessage =
                typeof (txError as { message?: unknown })?.message === "string"
                  ? (txError as { message: string }).message
                  : "Transfer failed";
              const shouldTryLegacyTx =
                /schema cache|transfer_funds_authenticated|function.*not\s+found/i.test(txMessage);

              if (!shouldTryLegacyTx) {
                throw new Error(txMessage);
              }

              const { data: legacyTxId, error: legacyTxError } = await supabase.rpc("transfer_funds_authenticated", {
                p_receiver_id: recipientId,
                p_amount: usdAmountPerUser,
                p_note: noteText || "",
              });

              if (legacyTxError) {
                const legacyTxMessage =
                  typeof (legacyTxError as { message?: unknown })?.message === "string"
                    ? (legacyTxError as { message: string }).message
                    : "Transfer failed";
                throw new Error(legacyTxMessage);
              }

              return String(legacyTxId || "");
            };

            const txIds: string[] = [];
            for (let i = 0; i < recipientIds.length; i += 1) {
              const recipientId = recipientIds[i];
              const noteText = notes[i] || "";
              const txId = await transferSingle(recipientId, noteText);
              txIds.push(txId);
            }

            result = {
              success: true,
              transaction_ids: txIds,
              total_amount: totalUsdAmount,
            };
          }
        }
        if (result.error) {
          console.error('Bulk transfer result error:', result.error);
          throw new Error(result.error);
        }

        const firstTxId = result.transaction_ids?.[0] || "bulk-tx";
        
        setLoading(false);
        setReceiptData({
          transactionId: firstTxId,
          ledgerTransactionId: firstTxId,
          type: "send",
          amount: totalUsdAmount,
          otherPartyName: `${activeUsers.length} recipients`,
          otherPartyUsername: `Multiple recipients`,
          note: activeNote || undefined,
          date: new Date(),
        });
        setReceiptOpen(true);
        playSendSuccessSound();
        toast.success(`${currency.symbol}${totalAmount.toFixed(2)} sent to ${activeUsers.length} people!`);

        // Reset state
        setAmount("");
        setNote("");
        setSelectedUsers([]);
        setIsMultiSend(false);
        setStep("select");
        refreshTransactions();
        return;
      }

      if (checkoutSessionToken) {
        const { data: checkoutTxId, error: checkoutError } = await (supabase as any).rpc("pay_merchant_checkout_with_wallet", {
          p_session_token: checkoutSessionToken,
          p_note: activeNote || "Completed via OpenPay wallet /send flow",
          p_customer_name: checkoutCustomerName || null,
          p_customer_email: checkoutCustomerEmail || null,
          p_customer_phone: checkoutCustomerPhone || null,
          p_customer_address: checkoutCustomerAddress || null,
        });

        if (checkoutError) {
          setLoading(false);
          toast.error(checkoutError.message || "Checkout payment failed");
          return;
        }

        const txId = String(checkoutTxId || "");
        const isPosRedirect = isPosCheckoutSession || (typeof activeNote === "string" && activeNote.toLowerCase().includes("pos"));
        const nextPath = isPosRedirect ? "/pos-thank-you" : "/merchant-checkout/thank-you";
        navigate(`${nextPath}?session=${encodeURIComponent(checkoutSessionToken)}&tx=${encodeURIComponent(txId)}`, { replace: true });
        setLoading(false);
        return;
      }

      const transferViaSecureRpcFallback = async () => {
        const { data: txId, error: rpcError } = await supabase.rpc("transfer_funds_authenticated", {
          p_receiver_id: activeUser!.id,
          p_amount: usdAmountPerUser,
          p_note: activeNote || "",
          p_currency_code: currency.code,
          p_sender_amount: parsedAmount,
          p_sender_currency_code: currency.code,
          p_receiver_amount: usdAmountPerUser,
          p_receiver_currency_code: "OUSD",
        });

        if (!rpcError) {
          return String(txId || "");
        }

        const rpcMessage =
          typeof (rpcError as { message?: unknown })?.message === "string"
            ? (rpcError as { message: string }).message
            : "Fallback transfer failed";

        const shouldTryLegacy =
          /schema cache|transfer_funds_authenticated|function.*not\s+found/i.test(rpcMessage);

        if (!shouldTryLegacy) {
          throw new Error(rpcMessage);
        }

        const { data: legacyTxId, error: legacyError } = await supabase.rpc("transfer_funds_authenticated", {
          p_receiver_id: activeUser!.id,
          p_amount: usdAmountPerUser,
          p_note: activeNote || "",
        });

        if (legacyError) {
          const legacyMessage =
            typeof (legacyError as { message?: unknown })?.message === "string"
              ? (legacyError as { message: string }).message
              : "Fallback transfer failed";
          throw new Error(legacyMessage);
        }

        return String(legacyTxId || "");
      };

      let txId = "";
      let usedFallback = false;

      const { data, error } = await supabase.functions.invoke("send-money", {
        body: {
          receiver_id: activeUser!.id,
          amount: usdAmountPerUser,
          note: activeNote,
          purpose: purpose || null,
          currency_code: currency.code,
          sender_amount: parsedAmount,
          sender_currency_code: currency.code,
          receiver_amount: usdAmountPerUser,
          receiver_currency_code: "OUSD",
        },
      });

      if (error) {
        try {
          txId = await transferViaSecureRpcFallback();
          usedFallback = true;
        } catch (fallbackError) {
          const edgeErrorMessage = await getFunctionErrorMessage(error, "Transfer failed");
          const fallbackErrorMessage =
            fallbackError instanceof Error
              ? fallbackError.message
              : typeof (fallbackError as { message?: unknown })?.message === "string"
                ? String((fallbackError as { message: string }).message)
                : "Fallback transfer failed";
          setLoading(false);
          toast.error(`${edgeErrorMessage}. ${fallbackErrorMessage}`);
          return;
        }
      } else {
        txId = (data as { transaction_id?: string } | null)?.transaction_id || "";
      }

      setLoading(false);
      setReceiptData({
        transactionId: txId,
        ledgerTransactionId: txId,
        type: "send",
        amount: usdAmountPerUser,
        otherPartyName: activeUser?.full_name || "Unknown",
        otherPartyUsername: activeUser?.username || undefined,
        note: activeNote || undefined,
        date: new Date(),
      });
      console.log('Receipt data set:', {
        transactionId: txId,
        amount: usdAmountPerUser,
        otherPartyName: activeUser?.full_name
      });
      setReceiptOpen(true);
      console.log('Receipt modal opened:', true);
      playSendSuccessSound();
      toast.success(`${currency.symbol}${parseFloat(activeAmount).toFixed(2)} sent to ${activeUser?.full_name || "Unknown"}!`);

      // Clear the amount and note
      setAmount("");
      setNote("");
      setSelectedUser(null);
      setStep("select");
      setSearchQuery("");
      setAccountLookupResult(null);

      // Refresh transactions for recent list
      refreshTransactions();
    } catch (err) {
      console.error("handleSend unexpected error:", err);
      setLoading(false);
      const errorMessage = err instanceof Error ? err.message : "An unexpected error occurred. Please try again.";
      toast.error(errorMessage);
    }
  };

  const loadDashboard = useCallback(async () => {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) { 
      navigate("/signin"); 
      return; 
    }
    setUserId(user.id);

    const { data: wallet } = await supabase
      .from("wallets").select("balance").eq("user_id", user.id).single();
    setBalance(wallet?.balance || 0);

    const { data: myProfile } = await supabase
      .from("profiles")
      .select("full_name, avatar_url")
      .eq("id", user.id)
      .single();
    setMyAvatarUrl(myProfile?.avatar_url || null);
    setMyFullName(myProfile?.full_name || "");

    const { data: contactRows } = await supabase
      .from("contacts").select("contact_id").eq("user_id", user.id);
    const contactIds = contactRows?.map(c => c.contact_id) || [];
    setContactIds(contactIds);

    const { data: profiles } = await supabase
      .from("profiles").select("id, full_name, username, avatar_url").neq("id", user.id);

    if (profiles) {
      let openpayProfile = profiles.find((p) => (p.username || "").toLowerCase() === "openpay") || null;
      if (!openpayProfile) {
        const { data: openpayRow } = await supabase
          .from("profiles")
          .select("id, full_name, username, avatar_url")
          .eq("username", "openpay")
          .single();
        openpayProfile = openpayRow || null;
      }
      const combinedProfiles = openpayProfile && !profiles.some((p) => p.id === openpayProfile!.id)
        ? [openpayProfile, ...profiles]
        : profiles;
      setAllUsers(combinedProfiles);
      const baseContacts = profiles.filter(p => contactIds.includes(p.id));
      const contactsWithDemo = openpayProfile && !baseContacts.some((p) => p.id === openpayProfile!.id)
        ? [openpayProfile, ...baseContacts]
        : baseContacts;
      setContacts(contactsWithDemo);
    }

    const { data: txs } = await supabase
      .from("transactions")
      .select("sender_id, receiver_id, created_at")
      .eq("sender_id", user.id)
      .order("created_at", { ascending: false })
      .limit(50);

    if (txs && profiles) {
      const seen = new Set<string>();
      const recent: RecentRecipient[] = [];
      for (const tx of txs) {
        const recipientId = tx.receiver_id;
        if (!recipientId || seen.has(recipientId) || recipientId === user.id) continue;
        const profile = profiles.find((p) => p.id === recipientId);
        if (!profile) continue;
        seen.add(recipientId);
        recent.push({
          ...profile,
          last_sent_at: tx.created_at,
        });
        if (recent.length >= 8) break;
      }
      setRecentRecipients(recent);
    }

    const toId = searchParams.get("to");
    const initialSearch = searchParams.get("search") || "";
    const qrAmount = searchParams.get("amount");
    const qrCurrency = (searchParams.get("currency") || "").toUpperCase();
    const qrNote = searchParams.get("note");
    if (initialSearch) {
      setSearchQuery(initialSearch);
    }
    if (toId && profiles) {
      const found = profiles.find(p => p.id === toId);
      if (found) {
        setSelectedUser(found);
        if (qrAmount && Number.isFinite(Number(qrAmount)) && Number(qrAmount) > 0) {
          setAmount(Number(qrAmount).toFixed(2));
        }
        if (qrNote) {
          setNote(qrNote);
        }
        if (qrCurrency) {
          const foundCurrency = currencies.find((c) => c.code === qrCurrency);
          if (foundCurrency) setCurrency(foundCurrency);
        }
        setStep("amount");
      }
    }

    if (checkoutSessionToken) {
      const { data: checkoutPayload } = await (supabase as any).rpc("get_public_merchant_checkout_session", {
        p_session_token: checkoutSessionToken,
      });
      const checkoutRow = Array.isArray(checkoutPayload) ? checkoutPayload[0] : checkoutPayload;
      const typedCheckout: {
        total_amount?: number;
        currency?: string;
        merchant_user_id?: string;
        items?: Array<{ item_name?: string }>;
      } = (checkoutRow || {}) as any;
      if (checkoutRow) {
        const checkoutAmount = Number(typedCheckout.total_amount || 0);
        const checkoutCurrency = String(typedCheckout.currency || "").toUpperCase();
        const checkoutMerchantId = String(typedCheckout.merchant_user_id || "");
        const checkoutItems = Array.isArray(typedCheckout.items) ? typedCheckout.items : [];
        const firstItemName = String(checkoutItems[0]?.item_name || "").toLowerCase();
        const qrNoteHint = String(searchParams.get("note") || "").toLowerCase();
        const isPosHint = firstItemName.includes("pos payment") || qrNoteHint.includes("pos");
        setIsPosCheckoutSession(isPosHint);

        if (checkoutAmount > 0) {
          setAmount(checkoutAmount.toFixed(2));
        }
        if (checkoutCurrency) {
          const foundCurrency = currencies.find((c) => c.code === checkoutCurrency);
          if (foundCurrency) setCurrency(foundCurrency);
        }
        if (checkoutMerchantId && profiles) {
          const merchantProfile = profiles.find((p) => p.id === checkoutMerchantId);
          if (merchantProfile) {
            setSelectedUser(merchantProfile);
            setStep("amount");
          }
        }
      }
    }

    // Handle POS session token
    if (posSessionToken) {
      const { data: posPayload } = await (supabase as any)
        .from("merchant_checkout_sessions")
        .select("*")
        .eq("session_token", posSessionToken)
        .eq("status", "open")
        .gte("expires_at", new Date().toISOString())
        .maybeSingle();

      if (posPayload) {
        const posAmount = Number(posPayload.total_amount || 0);
        const posCurrency = String(posPayload.currency || "").toUpperCase();
        const posMerchantId = String(posPayload.merchant_user_id || "");
        
        setIsPosCheckoutSession(true);
        
        if (posAmount > 0) {
          setAmount(posAmount.toFixed(2));
        }
        if (posCurrency) {
          const foundCurrency = currencies.find((c) => c.code === posCurrency);
          if (foundCurrency) setCurrency(foundCurrency);
        }
        if (posMerchantId && profiles) {
          const merchantProfile = profiles.find((p) => p.id === posMerchantId);
          if (merchantProfile) {
            setSelectedUser(merchantProfile);
            setStep("amount");
          }
        }
      }
    }

    const fallbackPurposes = [
      { id: "1", name: "Rent", category: "Living Expenses", icon: "home", color: "blue" },
      { id: "2", name: "Car Payment", category: "Transportation", icon: "car", color: "green" },
      { id: "3", name: "Groceries", category: "Food & Dining", icon: "shopping-cart", color: "orange" },
      { id: "4", name: "Restaurant", category: "Food & Dining", icon: "utensils", color: "orange" },
      { id: "5", name: "Gas/Fuel", category: "Transportation", icon: "fuel", color: "green" },
      { id: "6", name: "Electricity", category: "Utilities", icon: "lightbulb", color: "yellow" },
      { id: "7", name: "Water", category: "Utilities", icon: "droplet", color: "yellow" },
      { id: "8", name: "Internet", category: "Utilities", icon: "wifi", color: "yellow" },
      { id: "9", name: "Phone", category: "Utilities", icon: "phone", color: "yellow" },
      { id: "10", name: "Insurance", category: "Living Expenses", icon: "shield", color: "blue" },
      { id: "11", name: "Subscription", category: "Other", icon: "credit-card", color: "slate" },
      { id: "12", name: "General", category: "Other", icon: "more-horizontal", color: "slate" },
    ];
    const enablePurposeTable =
      String(import.meta.env.VITE_PAYMENT_PURPOSES_ENABLED || "false").toLowerCase() === "true";

    if (!enablePurposeTable) {
      setPaymentPurposes(fallbackPurposes);
    } else {
      try {
        const { data: purposes } = await (supabase as any)
          .from("payment_purposes")
          .select("*")
          .eq("is_active", true)
          .order("sort_order");

        setPaymentPurposes(purposes || fallbackPurposes);
      } catch (error) {
        console.warn("Failed to load payment purposes, using fallback:", error);
        setPaymentPurposes(fallbackPurposes);
      }
    }

    setIsInitialLoadDone(true);
  }, [navigate, searchParams, setCurrency]);

  useEffect(() => {
    loadDashboard();
  }, [loadDashboard]);

  const normalizedSearch = searchQuery.trim().toLowerCase();
  const normalizedSearchRaw = searchQuery.trim();
  const isAccountNumberSearch = normalizedSearchRaw.toUpperCase().startsWith("OP");
  const normalizedUsernameSearch = normalizedSearch.startsWith("@")
    ? normalizedSearch.slice(1)
    : normalizedSearch;

  const filtered = normalizedSearch
    ? allUsers.filter((u) => {
        const fullName = u.full_name.toLowerCase();
        const username = (u.username || "").toLowerCase();
        return (
          fullName.includes(normalizedSearch) ||
          username.includes(normalizedSearch) ||
          (normalizedUsernameSearch.length > 0 && username.includes(normalizedUsernameSearch))
        );
      })
    : contacts;
  const filteredWithoutAccountMatch = accountLookupResult
    ? filtered.filter((user) => user.id !== accountLookupResult.id)
    : filtered;

  useEffect(() => {
    const lookup = async () => {
      if (!isAccountNumberSearch || normalizedSearchRaw.length < 8) {
        setAccountLookupResult(null);
        setAccountLookupLoading(false);
        return;
      }
      setAccountLookupLoading(true);
      const { data, error } = await supabase.rpc("find_user_by_account_number", {
        p_account_number: normalizedSearchRaw.toUpperCase(),
      });
      if (error) {
        setAccountLookupResult(null);
        setAccountLookupLoading(false);
        return;
      }
      const row = (data as UserProfile[] | null)?.[0] || null;
      setAccountLookupResult(row);
      setAccountLookupLoading(false);
    };
    void lookup();
  }, [isAccountNumberSearch, normalizedSearchRaw]);

  const toggleBookmark = async (profile: UserProfile) => {
    const {
      data: { user },
    } = await supabase.auth.getUser();
    const userId = user?.id;
    if (!userId) return;

    const isSaved = contactIds.includes(profile.id);
    if (isSaved) {
      const { error } = await supabase
        .from("contacts")
        .delete()
        .eq("user_id", userId)
        .eq("contact_id", profile.id);
      if (error) {
        toast.error(error.message);
        return;
      }
      setContactIds((prev) => prev.filter((id) => id !== profile.id));
      setContacts((prev) => prev.filter((p) => p.id !== profile.id));
      toast.success("Removed from bookmarks");
      return;
    }

    const { error } = await supabase
      .from("contacts")
      .insert({ user_id: userId, contact_id: profile.id });
    if (error) {
      toast.error(error.message);
      return;
    }
    setContactIds((prev) => [...prev, profile.id]);
    setContacts((prev) => [profile, ...prev.filter((p) => p.id !== profile.id)]);
    toast.success("Saved to bookmarks");
  };

  const handleSelectUser = (user: UserProfile) => { 
    if (isMultiSend) {
      if (selectedUsers.some(u => u.id === user.id)) {
        setSelectedUsers(prev => prev.filter(u => u.id !== user.id));
      } else if (selectedUsers.length < 5) {
        setSelectedUsers(prev => [...prev, user]);
      } else {
        toast.error("Maximum 5 recipients allowed");
      }
    } else {
      setSelectedUsers([]); // Clear multi-send selection
      setSelectedUser(user); 
      setShowConfirm(true); 
    }
  };
  const handleConfirmUser = () => { setShowConfirm(false); setStep("amount"); };
  const handleConfirmMultiSend = () => {
    if (selectedUsers.length === 0) {
      toast.error("Select at least one recipient");
      return;
    }
    setStep("amount");
  };

  const handleNumberPress = (val: string) => {
    setAmount((prev) => {
      if (val === "." && prev.includes(".")) return prev;
      if (prev.includes(".") && prev.split(".")[1].length >= 2) return prev;
      if (prev === "" && val === ".") return "0.";
      if (prev === "0" && val !== ".") return val;
      return prev + val;
    });
  };

  const handleBackspace = () => {
    setAmount((prev) => (prev.length > 0 ? prev.slice(0, -1) : ""));
  };

  const handleOpenSendConfirm = () => {
    const parsedAmount = parseFloat(amount);
    if ((!selectedUser && selectedUsers.length === 0) || !amount || parsedAmount <= 0) {
      toast.error("Enter a valid amount");
      return;
    }
    const totalAmount = isMultiSend ? parsedAmount * selectedUsers.length : parsedAmount;
    const usdAmount = totalAmount / (currency?.rate || 1);
    if (usdAmount > balance) {
      toast.error("Amount exceeds your available balance");
      return;
    }
    setShowSendConfirm(true);
  };

  const getInitials = (name: string) => (name || "User").split(" ").filter(Boolean).map((n) => n[0]).join("").slice(0, 2).toUpperCase();
  const colors = ["bg-paypal-dark", "bg-paypal-light-blue", "bg-primary", "bg-muted-foreground"];
  const renderAvatar = (user: UserProfile, colorIndex: number) => {
    const bg = colors[colorIndex % colors.length];
    return (
      <div className="relative h-12 w-12">
        <div className={`flex h-12 w-12 items-center justify-center rounded-full ${bg}`}>
          <span className="text-base font-bold text-primary-foreground">{getInitials(user.full_name)}</span>
        </div>
        {user.avatar_url ? (
          <img
            src={user.avatar_url}
            alt={user.full_name}
            className="absolute inset-0 h-full w-full rounded-full border border-border object-cover"
            onError={(e) => {
              e.currentTarget.style.display = "none";
            }}
          />
        ) : null}
      </div>
    );
  };
  const renderAvatarWithFallback = (
    name: string,
    avatarUrl: string | null | undefined,
    sizeClass: string,
    fallbackClassName: string,
    textClassName: string,
    borderClassName = ""
  ) => (
    <div className={`relative ${sizeClass}`}>
      <div className={`flex ${sizeClass} items-center justify-center rounded-full ${fallbackClassName}`}>
        <span className={textClassName}>{getInitials(name)}</span>
      </div>
      {avatarUrl ? (
        <img
          src={avatarUrl}
          alt={name}
          className={`absolute inset-0 ${sizeClass} rounded-full object-cover ${borderClassName}`.trim()}
          onError={(e) => {
            e.currentTarget.style.display = "none";
          }}
        />
      ) : null}
    </div>
  );

  if (!isInitialLoadDone) {
    return <SplashScreen message="Loading send..." />;
  }

  if (step === "amount") {
    return (
      <div className="min-h-screen bg-paypal-blue flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-6 pt-6 text-white">
          <div className="flex items-center gap-5">
            <button onClick={() => setStep("select")} className="active:opacity-60">
              <ArrowLeft className="h-7 w-7" />
            </button>
            <button onClick={() => navigate("/scan-qr?returnTo=/send")} className="active:opacity-60">
              <ScanLine className="h-7 w-7" />
            </button>
            <button onClick={() => navigate("/send-invoice")} className="active:opacity-60" title="Request Invoice">
              <FileText className="h-7 w-7" />
            </button>
          </div>
          
          <div className="flex items-center gap-1.5 rounded-full bg-black/10 px-4 py-1.5 active:bg-black/20">
            <span className="text-base font-bold uppercase tracking-wide">{currency.code}</span>
            <CurrencySelector />
          </div>

          {renderAvatarWithFallback(
            myFullName || "User",
            myAvatarUrl,
            "h-9 w-9",
            "bg-white/20",
            "text-sm font-bold text-white",
            "border border-white/20"
          )}
        </div>

        {/* Amount Display */}
        <div className="flex flex-1 flex-col items-center justify-center text-white">
          <div className="mb-2 flex items-center text-8xl font-medium tracking-tight">
            <span>{currency.symbol}</span>
            <span>{amount || "0"}</span>
          </div>
          
          {isMultiSend && selectedUsers.length > 0 ? (
            <div className="flex flex-col items-center gap-2">
              <div className="flex items-center gap-2 rounded-full bg-black/10 px-3 py-1.5 text-base font-medium">
                <span>Sending to {selectedUsers.length} people</span>
              </div>
              <div className="flex -space-x-2 mt-1">
                {selectedUsers.slice(0, 5).map((user) => (
                  <div key={user.id} className="rounded-full border-2 border-paypal-blue">
                    {renderAvatarWithFallback(
                      user.full_name,
                      user.avatar_url,
                      "h-8 w-8",
                      "bg-white/20",
                      "text-[10px] font-bold text-white"
                    )}
                  </div>
                ))}
              </div>
              <p className="text-sm font-medium text-white/80">
                Total: {currency.symbol}{(Number(amount || 0) * selectedUsers.length).toFixed(2)} ({formatCurrency(balance)} available)
              </p>
            </div>
          ) : selectedUser ? (
            <div className="flex flex-col items-center gap-2">
              <div className="flex items-center gap-2 rounded-full bg-black/5 px-3 py-1.5 text-base font-medium">
                <span>Sending to {selectedUser.full_name}</span>
              </div>
              <p className="text-sm font-medium text-white/80">Available: {formatCurrency(balance)}</p>
            </div>
          ) : (
            <p className="text-sm font-medium text-white/80">Available: {formatCurrency(balance)}</p>
          )}

          <div className="mt-8 w-full max-w-[240px]">
            <input
              type="text"
              placeholder="Add a note"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              className="w-full bg-transparent text-center text-lg text-white placeholder:text-white/50 focus:outline-none"
            />
          </div>

          {/* Purpose Selection */}
          <div className="mt-4 w-full max-w-[320px]">
            <button
              onClick={() => setShowPurposeSelector(true)}
              className="w-full rounded-full bg-white/10 px-4 py-2 text-center text-sm text-white placeholder:text-white/50 hover:bg-white/20 transition-colors"
            >
              {purpose ? `Purpose: ${purpose}` : "Add purpose (optional)"}
            </button>
          </div>
        </div>

        {/* Number Pad */}
        <div className="px-8 pb-8">
          <NumberPad 
            onPress={handleNumberPress}
            onBackspace={handleBackspace}
            className="mb-8"
          />

          <div className="flex gap-4">
            <Button 
              variant="ghost"
              className="h-14 flex-1 rounded-full bg-white/10 text-xl font-bold text-white hover:bg-white/20 active:scale-95 transition-all"
              onClick={() => navigate("/request-payment")}
            >
              Request
            </Button>
            <Button 
              className="h-14 flex-1 rounded-full bg-white text-xl font-bold text-paypal-blue hover:bg-white/90 active:scale-95 transition-all shadow-lg"
              onClick={handleOpenSendConfirm}
              disabled={loading || !amount || parseFloat(amount) <= 0}
            >
              {loading ? <Loader2 className="h-6 w-6 animate-spin" /> : "Pay"}
            </Button>
          </div>
        </div>

        <TransactionReceipt open={receiptOpen} onOpenChange={(open) => {
          setReceiptOpen(open);
          if (!open) navigate("/dashboard");
        }} receipt={receiptData} />

        <Dialog open={showSendConfirm} onOpenChange={setShowSendConfirm}>
          <DialogContent className="rounded-3xl">
            <DialogTitle className="text-xl font-bold text-foreground">Confirm payment</DialogTitle>
            <DialogDescription className="text-base text-muted-foreground">
              Review the details before sending.
            </DialogDescription>
            {isMultiSend && selectedUsers.length > 0 ? (
              <div className="mt-3 space-y-2">
                <p className="text-[10px] font-bold text-muted-foreground uppercase tracking-wider">Recipients ({selectedUsers.length}/5)</p>
                <div className="flex flex-wrap gap-2 rounded-2xl bg-secondary/70 p-3">
                  {selectedUsers.map(u => (
                    <div key={u.id} className="flex items-center gap-2 bg-white/20 rounded-full pl-1 pr-3 py-1 border border-white/10">
                    {renderAvatarWithFallback(
                      u.full_name,
                      u.avatar_url,
                      "h-6 w-6",
                      "bg-paypal-dark",
                      "text-[8px] font-bold text-white"
                    )}
                      <span className="text-[10px] font-semibold text-foreground">{u.full_name.split(' ')[0]}</span>
                    </div>
                  ))}
                </div>
              </div>
            ) : selectedUser && (
              <div className="mt-3 flex items-center gap-3 rounded-2xl bg-secondary/70 px-3 py-2.5">
                {renderAvatarWithFallback(
                  selectedUser.full_name,
                  selectedUser.avatar_url,
                  "h-12 w-12",
                  "bg-paypal-dark",
                  "text-base font-bold text-primary-foreground",
                  "border border-border"
                )}
                <div>
                  <p className="font-semibold text-foreground">{selectedUser.full_name}</p>
                  {selectedUser.username && <p className="text-sm text-muted-foreground">@{selectedUser.username}</p>}
                </div>
              </div>
            )}

            <div className="mt-4 space-y-2 rounded-2xl border border-border p-3 text-base">
              <p className="flex items-center justify-between">
                <span className="text-muted-foreground">{isMultiSend ? "Amount per person" : "Amount"}</span>
                <span className="font-semibold text-foreground">{currency.symbol}{Number(amount || 0).toFixed(2)} ({currency.code})</span>
              </p>
              {isMultiSend && (
                <p className="flex items-center justify-between border-t border-border pt-2 mt-2">
                  <span className="text-foreground font-bold">Total Amount</span>
                  <span className="font-bold text-paypal-blue">{currency.symbol}{(Number(amount || 0) * selectedUsers.length).toFixed(2)}</span>
                </p>
              )}
              <p className="flex items-center justify-between">
                <span className="text-muted-foreground">Converted (USD)</span>
                <span className="font-semibold text-foreground">
                  {isMultiSend 
                    ? `$${(Number(amount || 0) * selectedUsers.length / (currency.rate || 1)).toFixed(2)} total`
                    : `$${(Number(amount || 0) / (currency.rate || 1)).toFixed(2)}`}
                </span>
              </p>
              {note.trim() && (
                <p className="flex items-start justify-between gap-2">
                  <span className="text-muted-foreground">Note</span>
                  <span className="max-w-[70%] break-all text-right text-foreground">{formatShortText(note.trim())}</span>
                </p>
              )}
            </div>

            <p className="mt-3 rounded-md border border-paypal-light-blue/60 bg-[#edf3ff] px-3 py-2 text-sm text-paypal-blue">
              Only transact with users you know. Approve only if you expected this transaction. If you do not recognize the user, cancel now.
            </p>

            <div className="mt-4 space-y-3">
              <Button variant="outline" className="h-11 w-full rounded-2xl" onClick={() => setShowSendConfirm(false)}>
                Cancel
              </Button>
              <SlideToConfirm
                onConfirm={async () => {
                  setSlideConfirmLoading(true);
                  try {
                    const { data: { user } } = await supabase.auth.getUser();
                    const settings = user ? loadAppSecuritySettings(user.id) : null;
                    const pinSetupCompleted = user ? isPinSetupCompleted(user.id) : false;
                    setShowSendConfirm(false);
                    
                    // Navigate to PIN confirmation page if user has PIN set up
                    if (pinSetupCompleted && settings?.pinHash) {
                      navigate("/confirm-pin", {
                        state: {
                          title: "Confirm your OpenPay PIN",
                          returnTo: "/send",
                          actionData: {
                            selectedUser,
                            selectedUsers,
                            isMultiSend,
                            amount,
                            note,
                            step: "confirm"
                          }
                        },
                      });
                    } else {
                      // Proceed directly with send if no PIN set up
                      await handleSend();
                    }
                  } finally {
                    setSlideConfirmLoading(false);
                  }
                }}
                loading={slideConfirmLoading}
                disabled={loading || slideConfirmLoading}
                text="Slide to confirm & send"
                onPaymentComplete={refreshTransactions}
              />
            </div>
          </DialogContent>
        </Dialog>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-paypal-blue px-4 pt-4 text-white">
      <div className="flex items-center gap-3">
        {myAvatarUrl ? (
          <img
            src={myAvatarUrl}
            alt={myFullName || "Profile"}
            className="h-10 w-10 rounded-full border border-white/20 object-cover"
          />
        ) : (
          <div className="flex h-10 w-10 items-center justify-center rounded-full bg-white/20">
            <span className="text-sm font-bold text-white">{getInitials(myFullName || "OpenPay User")}</span>
          </div>
        )}
        <button onClick={() => navigate("/dashboard")} className="active:opacity-60 transition-opacity">
          <ArrowLeft className="w-6 h-6 text-white" />
        </button>
        <div className="flex-1">
          <Input 
            placeholder="Name, username, email, or account number" 
            value={searchQuery} 
            onChange={(e) => setSearchQuery(e.target.value)}
            className="h-12 rounded-full border-none bg-white/10 text-white placeholder:text-white/55 pl-4 focus-visible:ring-1 focus-visible:ring-white/30" 
            autoFocus 
          />
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setIsMultiSend(!isMultiSend)}
            className={`flex h-12 w-12 items-center justify-center rounded-full transition-colors ${
              isMultiSend ? "bg-white text-paypal-blue" : "bg-white/10 text-white"
            }`}
            aria-label="Toggle Multi-Send"
          >
            <Users className="h-5 w-5" />
          </button>
          <button
            onClick={() => navigate("/scan-qr?returnTo=/send")}
            className="flex h-12 w-12 items-center justify-center rounded-full bg-white/10 active:bg-white/20 transition-colors"
            aria-label="Scan QR code"
          >
            <ScanLine className="h-5 w-5 text-white" />
          </button>
          <button
            onClick={() => navigate("/send-invoice")}
            className="flex h-12 w-12 items-center justify-center rounded-full bg-white/10 active:bg-white/20 transition-colors"
            aria-label="Send Invoice"
          >
            <FileText className="h-5 w-5 text-white" />
          </button>
        </div>
      </div>

      <div className="mt-6">
        {isMultiSend && (
          <div className="mb-6 p-4 rounded-2xl bg-white/10 border border-white/20">
            <div className="flex items-center justify-between mb-3">
              <h2 className="font-bold text-white">Multi-Send ({selectedUsers.length}/5)</h2>
              <button 
                onClick={handleConfirmMultiSend}
                disabled={selectedUsers.length === 0}
                className="px-4 py-1.5 rounded-full bg-white text-paypal-blue text-xs font-bold disabled:opacity-50"
              >
                Continue
              </button>
            </div>
            {selectedUsers.length > 0 ? (
              <div className="flex flex-wrap gap-2">
                {selectedUsers.map(user => (
                  <div key={user.id} className="flex items-center gap-2 bg-white/20 rounded-full pl-1 pr-3 py-1">
                    {renderAvatar(user, 0)}
                    <span className="text-xs font-medium">{user.full_name.split(' ')[0]}</span>
                    <button onClick={() => handleSelectUser(user)} className="text-white/60 hover:text-white">
                      <X className="h-3 w-3" />
                    </button>
                  </div>
                ))}
              </div>
            ) : (
              <p className="text-sm text-white/60 italic">Select up to 5 people to send money to.</p>
            )}
          </div>
        )}

        {!searchQuery && recentRecipients.length > 0 && (
          <>
            <h2 className="mb-3 font-bold text-white">Recent</h2>
            <div className="overflow-hidden rounded-2xl mb-5 border border-white/60 bg-card">
              {recentRecipients.map((user, i) => (
                <div
                  key={`${user.id}-${user.last_sent_at}`}
                  onClick={() => handleSelectUser(user)}
                  className="flex w-full items-center gap-3 border-b border-border/70 px-3 py-3 text-left last:border-b-0 hover:bg-secondary/50 transition cursor-pointer"
                >
                  {renderAvatar(user, i)}
                  <div className="text-left flex-1">
                    <p className="font-semibold text-foreground">{user.full_name}</p>
                    {user.username && <p className="text-base text-muted-foreground">@{user.username}</p>}
                    <p className="text-sm text-muted-foreground">Recent transaction</p>
                  </div>
                  {isMultiSend && (
                    <div className={`h-6 w-6 rounded-full border-2 flex items-center justify-center transition-colors ${
                      selectedUsers.some(u => u.id === user.id) ? "bg-paypal-blue border-paypal-blue text-white" : "border-muted-foreground/30"
                    }`}>
                      {selectedUsers.some(u => u.id === user.id) && <Check className="h-4 w-4" />}
                    </div>
                  )}
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation();
                      void toggleBookmark(user);
                    }}
                    className="rounded-full p-2 hover:bg-secondary/50 transition-colors"
                    aria-label={contactIds.includes(user.id) ? "Remove bookmark" : "Save bookmark"}
                  >
                    {contactIds.includes(user.id) ? <BookmarkCheck className="h-5 w-5 text-paypal-blue" /> : <Bookmark className="h-5 w-5 text-muted-foreground" />}
                  </button>
                </div>
              ))}
            </div>
          </>
        )}

        <h2 className="mb-4 font-bold text-white">{searchQuery ? "Search results" : "Your contacts"}</h2>
        <div className="overflow-hidden rounded-2xl border border-white/60 bg-card">
          {isAccountNumberSearch && (
            <>
              {accountLookupLoading && (
                <p className="border-b border-border/70 px-3 py-3 text-base text-muted-foreground">Searching account number...</p>
              )}
              {!accountLookupLoading && accountLookupResult && (
                <div
                  onClick={() => handleSelectUser(accountLookupResult)}
                  className="flex w-full items-center gap-3 border-b border-border/70 px-3 py-3 text-left hover:bg-secondary/50 transition cursor-pointer"
                >
                  {renderAvatar(accountLookupResult, 0)}
                  <div className="text-left flex-1">
                    <p className="font-semibold text-foreground">{accountLookupResult.full_name}</p>
                    {accountLookupResult.username && <p className="text-base text-muted-foreground">@{accountLookupResult.username}</p>}
                    <p className="text-sm text-muted-foreground">Matched by account number</p>
                  </div>
                  <Info className="w-5 h-5 text-muted-foreground" />
                </div>
              )}
            </>
          )}
          {filteredWithoutAccountMatch.map((user, i) => (
            <div
              key={user.id}
              onClick={() => handleSelectUser(user)}
              className="flex w-full items-center gap-3 border-b border-border/70 px-3 py-3 text-left last:border-b-0 hover:bg-secondary/50 transition cursor-pointer"
            >
              {renderAvatar(user, i)}
              <div className="text-left flex-1">
                    <p className="font-semibold text-foreground">{user.full_name}</p>
                    {user.username && <p className="text-base text-muted-foreground">@{user.username}</p>}
                  </div>
                  {isMultiSend && (
                    <div className={`h-6 w-6 rounded-full border-2 flex items-center justify-center transition-colors ${
                      selectedUsers.some(u => u.id === user.id) ? "bg-paypal-blue border-paypal-blue text-white" : "border-muted-foreground/30"
                    }`}>
                      {selectedUsers.some(u => u.id === user.id) && <Check className="h-4 w-4" />}
                    </div>
                  )}
                  <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation();
                  void toggleBookmark(user);
                }}
                className="rounded-full p-2 hover:bg-secondary/50 transition-colors"
                aria-label={contactIds.includes(user.id) ? "Remove bookmark" : "Save bookmark"}
              >
                {contactIds.includes(user.id) ? <BookmarkCheck className="h-5 w-5 text-paypal-blue" /> : <Bookmark className="h-5 w-5 text-muted-foreground" />}
              </button>
              <Info className="w-5 h-5 text-muted-foreground" />
            </div>
          ))}
          {filteredWithoutAccountMatch.length === 0 && !accountLookupResult && !accountLookupLoading && (
            <p className="text-center text-muted-foreground py-8">No users found</p>
          )}
        </div>
      </div>

      <Dialog open={showConfirm} onOpenChange={setShowConfirm}>
        <DialogContent className="rounded-3xl">
          <DialogTitle className="sr-only">Confirm recipient</DialogTitle>
          <DialogDescription className="sr-only">Confirm that the selected recipient is correct.</DialogDescription>
          {selectedUser && (
            <div>
              <div className="mb-3">
                {renderAvatarWithFallback(
                  selectedUser.full_name,
                  selectedUser.avatar_url,
                  "h-16 w-16",
                  "bg-paypal-dark",
                  "text-lg font-bold text-primary-foreground",
                  "border border-border"
                )}
              </div>
              <h3 className="text-xl font-bold">{selectedUser.full_name}</h3>
              {selectedUser.username && <p className="text-muted-foreground">@{selectedUser.username}</p>}
              <p className="text-2xl font-bold mt-4 mb-2">Is this the right person?</p>
              <Button onClick={handleConfirmUser} className="mt-4 h-14 w-full rounded-full bg-paypal-blue text-lg font-semibold text-white hover:bg-[#004dc5]">Continue</Button>
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Purpose Selector Dialog */}
      <Dialog open={showPurposeSelector} onOpenChange={setShowPurposeSelector}>
        <DialogContent className="rounded-3xl max-h-[80vh] overflow-y-auto">
          <DialogTitle className="text-xl font-bold">Select Payment Purpose</DialogTitle>
          <DialogDescription className="text-sm text-muted-foreground">
            Choose a purpose to help track your spending in analytics
          </DialogDescription>
          
          <div className="mt-4 space-y-4">
            {/* Group purposes by category */}
            {Array.from(new Set(paymentPurposes.filter(p => p.category).map(p => p.category))).map(category => (
              <div key={category}>
                <h4 className="text-sm font-semibold text-muted-foreground mb-2">{category}</h4>
                <div className="grid grid-cols-2 gap-2">
                  {paymentPurposes
                    .filter(p => p.category === category)
                    .map(purposeOption => (
                      <button
                        key={purposeOption.id}
                        onClick={() => {
                          setPurpose(purposeOption.name);
                          setShowPurposeSelector(false);
                        }}
                        className={`p-3 rounded-xl border text-left transition-colors ${
                          purpose === purposeOption.name
                            ? 'border-paypal-blue bg-paypal-blue/10'
                            : 'border-border hover:bg-secondary/50'
                        }`}
                      >
                        <div className="font-medium text-sm">{purposeOption.name}</div>
                      </button>
                    ))}
                </div>
              </div>
            ))}
            
            {/* Custom purpose option */}
            <div className="pt-4 border-t border-border">
              <h4 className="text-sm font-semibold text-muted-foreground mb-2">Custom Purpose</h4>
              <input
                type="text"
                placeholder="Enter custom purpose..."
                value={customPurpose}
                onChange={(e) => setCustomPurpose(e.target.value)}
                className="w-full p-3 rounded-xl border border-border focus:border-paypal-blue focus:outline-none"
              />
              <button
                onClick={() => {
                  if (customPurpose.trim()) {
                    setPurpose(customPurpose.trim());
                    setCustomPurpose("");
                    setShowPurposeSelector(false);
                  }
                }}
                disabled={!customPurpose.trim()}
                className="mt-2 w-full p-3 rounded-xl bg-paypal-blue text-white font-medium disabled:opacity-50 disabled:cursor-not-allowed"
              >
                Use Custom Purpose
              </button>
            </div>
            
            {/* Clear purpose option */}
            <button
              onClick={() => {
                setPurpose("");
                setCustomPurpose("");
                setShowPurposeSelector(false);
              }}
              className="w-full p-3 rounded-xl border border-border text-muted-foreground hover:bg-secondary/50 transition-colors"
            >
              Remove Purpose
            </button>
          </div>
        </DialogContent>
      </Dialog>


    </div>
  );
};

export default SendMoney;
