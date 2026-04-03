import { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate, useLocation } from "react-router-dom";
import { ArrowLeft, QrCode, ScanLine } from "lucide-react";
import { format } from "date-fns";
import { supabase } from "@/integrations/supabase/client";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "sonner";
import { PI_TO_USD, useCurrency } from "@/contexts/CurrencyContext";
import { getFunctionErrorMessage } from "@/lib/supabaseFunctionError";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { QRCodeSVG } from "qrcode.react";
import { Html5Qrcode } from "html5-qrcode";
import { Info } from "lucide-react";
import TransactionReceipt, { type ReceiptData } from "@/components/TransactionReceipt";
import { loadAppSecuritySettings, isPinSetupCompleted } from "@/lib/appSecurity";
import SplashScreen from "@/components/SplashScreen";
import { playUiSound } from "@/lib/appSounds";

const PIN_ACTION_KEY = "openpay_pin_action_v1";

interface Profile {
  id: string;
  full_name: string;
  username: string | null;
  avatar_url?: string | null;
}

interface PaymentRequest {
  id: string;
  requester_id: string;
  payer_id: string;
  amount: number;
  note: string | null;
  status: string;
  created_at: string;
}

const parseOriginalAmount = (note: string | null | undefined): { amount: number; code: string } | null => {
  if (!note) return null;
  const m = note.match(/\[(\w+)\s+([\d.]+)\]/);
  if (!m) return null;
  return { code: m[1], amount: Number(m[2]) };
};

const RequestMoney = () => {
  const navigate = useNavigate();
  const location = useLocation();
  const { format: formatCurrency, currencies, currency } = useCurrency();
  const PURE_PI_ICON_URL = "https://i.ibb.co/BV8PHjB4/Pi-200x200.png";
  const OPENPAY_ICON_URL = "/openpay-logo.jpg";
  const [createCurrencyCode, setCreateCurrencyCode] = useState<string>(currency.code);
  const [payCurrencyCode, setPayCurrencyCode] = useState<string>(currency.code);
  const getPiCodeLabel = (code: string) => {
    const upper = String(code || "").toUpperCase();
    if (upper === "PI") return "PI";
    if (upper === "OUSD") return "OPEN USD";
    return `PI ${upper}`;
  };
  const [userId, setUserId] = useState<string | null>(null);
  const [selfProfile, setSelfProfile] = useState<Profile | null>(null);
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [requests, setRequests] = useState<PaymentRequest[]>([]);
  const [payerId, setPayerId] = useState("");
  const [selectedPayer, setSelectedPayer] = useState<Profile | null>(null);
  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("");
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(false);
  const [showScanner, setShowScanner] = useState(false);
  const [showInstructions, setShowInstructions] = useState(false);
  const [scanError, setScanError] = useState("");
  const [accountLookupResult, setAccountLookupResult] = useState<Profile | null>(null);
  const [accountLookupLoading, setAccountLookupLoading] = useState(false);
  const [confirmModalOpen, setConfirmModalOpen] = useState(false);
  const [receiptOpen, setReceiptOpen] = useState(false);
  const [receiptData, setReceiptData] = useState<ReceiptData | null>(null);
  const [pageLoading, setPageLoading] = useState(true);
  const [confirmAction, setConfirmAction] = useState<
    | { type: "create"; payer: Profile; amount: number; note: string; currencyCode: string }
    | { type: "pay"; request: PaymentRequest; requester: Profile | null }
    | { type: "reject"; request: PaymentRequest; requester: Profile | null }
    | null
  >(null);
  const pinActionExecutedRef = useRef(false);

  const profileMap = useMemo(() => {
    const map = new Map<string, Profile>();
    profiles.forEach((p) => map.set(p.id, p));
    return map;
  }, [profiles]);

  const loadData = async () => {
    setPageLoading(true);
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
      navigate("/signin");
      return;
    }
    setUserId(user.id);

    const { data: selfProfileRow } = await supabase
      .from("profiles")
      .select("id, full_name, username, avatar_url")
      .eq("id", user.id)
      .single();

    const { data: profileRows } = await supabase
      .from("profiles")
      .select("id, full_name, username, avatar_url")
      .neq("id", user.id);

    const { data: requestRows } = await supabase
      .from("payment_requests")
      .select("id, requester_id, payer_id, amount, note, status, created_at")
      .or(`requester_id.eq.${user.id},payer_id.eq.${user.id}`)
      .order("created_at", { ascending: false });

    setProfiles(profileRows || []);
    setSelfProfile(selfProfileRow || null);
    setRequests(requestRows || []);
    setPageLoading(false);
  };

  useEffect(() => {
    loadData();
  }, []);

  useEffect(() => {
    const state = location.state as any;
    if (pinActionExecutedRef.current) return;
    let data = state?.actionData || null;
    if (!data) {
      try {
        const raw = typeof window !== "undefined" ? window.sessionStorage.getItem(PIN_ACTION_KEY) : null;
        if (raw) data = JSON.parse(raw);
      } catch {}
    }
    if (state?.pinVerified && data) {
      let executed = false;
      if (data?.kind === "request_pay") {
        const req = requests.find((r) => r.id === data.requestId);
        if (req) {
          void submitPay(req, profileMap.get(req.requester_id) || null);
          executed = true;
        } else {
          return;
        }
      }
      if (executed) {
        pinActionExecutedRef.current = true;
        try {
          if (typeof window !== "undefined") window.sessionStorage.removeItem(PIN_ACTION_KEY);
        } catch {}
        navigate(location.pathname + location.search, { replace: true, state: {} });
      }
    }
  }, [location.state, requests, profileMap, navigate, location.pathname, location.search]);

  useEffect(() => {
    if (pageLoading) return;
    const state = location.state as any;
    if (pinActionExecutedRef.current) return;
    let data = state?.actionData || null;
    if (!data) {
      try {
        const raw = typeof window !== "undefined" ? window.sessionStorage.getItem(PIN_ACTION_KEY) : null;
        if (raw) data = JSON.parse(raw);
      } catch {}
    }
    if (state?.pinVerified && data) {
      let executed = false;
      if (data?.kind === "request_pay") {
        const req = requests.find((r) => r.id === data.requestId);
        if (req) {
          void submitPay(req, profileMap.get(req.requester_id) || null);
          executed = true;
        }
      }
      if (executed) {
        pinActionExecutedRef.current = true;
        try {
          if (typeof window !== "undefined") window.sessionStorage.removeItem(PIN_ACTION_KEY);
        } catch {}
        navigate(location.pathname + location.search, { replace: true, state: {} });
      }
    }
  }, [pageLoading, requests, profileMap, location.state, navigate, location.pathname, location.search]);

  const normalizedSearch = search.trim().toLowerCase();
  const normalizedSearchRaw = search.trim();
  const isAccountNumberSearch = normalizedSearchRaw.toUpperCase().startsWith("OP");
  const normalizedUsernameSearch = normalizedSearch.startsWith("@")
    ? normalizedSearch.slice(1)
    : normalizedSearch;

  const filteredProfiles = normalizedSearch
    ? profiles.filter((p) => {
      const fullName = p.full_name.toLowerCase();
      const username = (p.username || "").toLowerCase();
      return (
        fullName.includes(normalizedSearch) ||
        username.includes(normalizedSearch) ||
        (normalizedUsernameSearch.length > 0 && username.includes(normalizedUsernameSearch))
      );
    })
    : profiles;
  const filteredWithoutAccountMatch = accountLookupResult
    ? filteredProfiles.filter((profile) => profile.id !== accountLookupResult.id)
    : filteredProfiles;

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
      const row = (data as Profile[] | null)?.[0] || null;
      setAccountLookupResult(row);
      setAccountLookupLoading(false);
    };
    void lookup();
  }, [isAccountNumberSearch, normalizedSearchRaw]);

  const incoming = requests.filter((r) => r.payer_id === userId);
  const outgoing = requests.filter((r) => r.requester_id === userId);
  const receiveQrValue = useMemo(() => {
    if (!userId) return "";
    const params = new URLSearchParams({
      uid: userId,
      name: selfProfile?.full_name || "",
      username: selfProfile?.username || "",
    });
    return `openpay://pay?${params.toString()}`;
  }, [selfProfile?.full_name, selfProfile?.username, userId]);

  const extractUserIdFromQr = (rawValue: string): string | null => {
    const value = rawValue.trim();
    if (!value) return null;

    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (uuidRegex.test(value)) return value;

    try {
      const parsed = new URL(value);
      const uid = parsed.searchParams.get("uid") || parsed.searchParams.get("to");
      if (uid && uuidRegex.test(uid)) return uid;
    } catch {
      // no-op
    }

    const maybeUid = value.split("uid=")[1]?.split("&")[0];
    if (maybeUid && uuidRegex.test(maybeUid)) return maybeUid;

    return null;
  };

  useEffect(() => {
    if (!showScanner) return;

    let scanner: Html5Qrcode | null = null;
    let isDone = false;
    setScanError("");

    const waitForScannerElement = async () => {
      if (typeof document === "undefined") return false;
      for (let i = 0; i < 10; i += 1) {
        if (document.getElementById("openpay-receive-scanner")) return true;
        await new Promise((resolve) => requestAnimationFrame(resolve));
      }
      return false;
    };

    const stopScanner = async () => {
      if (!scanner) return;
      try {
        if (scanner.isScanning) {
          await scanner.stop();
        }
      } catch {
        // no-op
      }
      try {
        scanner.clear();
      } catch {
        // no-op
      }
    };

    const patchVideoElementForMobile = () => {
      if (typeof document === "undefined") return;
      const video = document.querySelector("#openpay-receive-scanner video") as HTMLVideoElement | null;
      if (!video) return;
      video.setAttribute("playsinline", "true");
      video.setAttribute("webkit-playsinline", "true");
      video.setAttribute("autoplay", "true");
      video.setAttribute("muted", "true");
    };

    const startScanner = async () => {
      const mounted = await waitForScannerElement();
      if (!mounted) {
        setScanError("Scanner failed to mount. Please try again.");
        return;
      }
      if (typeof window !== "undefined" && !window.isSecureContext) {
        setScanError("Camera needs HTTPS (or localhost) to work.");
        return;
      }
      if (typeof navigator === "undefined" || !navigator.mediaDevices?.getUserMedia) {
        setScanError("Camera API is not available on this device/browser.");
        return;
      }

      scanner = new Html5Qrcode("openpay-receive-scanner", {
        verbose: false,
        useBarCodeDetectorIfSupported: false,
      });
      const onDecoded = async (decodedText: string) => {
        if (isDone) return;
        isDone = true;

        const scannedUserId = extractUserIdFromQr(decodedText);
        await stopScanner();
        setShowScanner(false);

        if (!scannedUserId) {
          toast.error("Invalid QR code");
          return;
        }
        if (scannedUserId === userId) {
          toast.error("You scanned your own QR code");
          return;
        }
        navigate(`/send?to=${scannedUserId}`);
      };

      const scanConfig = {
        fps: 12,
        disableFlip: false,
        qrbox: (viewfinderWidth: number, viewfinderHeight: number) => {
          const minEdge = Math.min(viewfinderWidth, viewfinderHeight);
          const box = Math.max(180, Math.floor(minEdge * 0.68));
          return { width: box, height: box };
        },
      };
      try {
        let cameras: Awaited<ReturnType<typeof Html5Qrcode.getCameras>> = [];
        try {
          cameras = await Html5Qrcode.getCameras();
        } catch {
          // Some browsers block camera enumeration until stream opens. Keep fallback sources.
        }
        const preferredBack = cameras.find((cam) =>
          /(back|rear|environment)/i.test(cam.label || ""),
        );

        const sources: Array<string | MediaTrackConstraints> = [];
        sources.push({ facingMode: { exact: "environment" } });
        sources.push({ facingMode: { ideal: "environment" } });
        sources.push({ facingMode: "environment" });
        if (preferredBack?.id) sources.push(preferredBack.id);
        if (cameras[0]?.id) sources.push(cameras[0].id);
        sources.push({ facingMode: "user" });

        let started = false;
        let startError = "";

        for (const source of sources) {
          try {
            await scanner.start(source, scanConfig, onDecoded, () => undefined);
            patchVideoElementForMobile();
            setScanError("");
            started = true;
            break;
          } catch (error) {
            startError = error instanceof Error ? error.message : "Unable to start camera";
          }
        }

        if (!started) {
          setScanError(startError || "Unable to start camera");
        }
      } catch (error) {
        setScanError(error instanceof Error ? error.message : "Unable to start camera");
      }
    };

    startScanner();

    return () => {
      isDone = true;
      stopScanner();
    };
  }, [navigate, showScanner, userId]);

  const submitCreate = async () => {
    if (!userId || !payerId) {
      toast.error("Select who you are requesting from");
      return;
    }

    const parsedAmount = Number(amount);
    if (!Number.isFinite(parsedAmount) || parsedAmount <= 0) {
      toast.error("Enter a valid amount");
      return;
    }

    setLoading(true);
    const createMeta = currencies.find((c) => c.code === createCurrencyCode);
    const createRate = createMeta?.rate ?? 1;
    const ousdAmount = createRate ? (parsedAmount / createRate) * PI_TO_USD : parsedAmount;
    const fullNote = note.trim();
    const noteWithOriginalInfo = fullNote 
      ? `${fullNote} [${createCurrencyCode} ${parsedAmount.toFixed(2)}]`
      : `[${createCurrencyCode} ${parsedAmount.toFixed(2)}]`;

    const { error } = await supabase.from("payment_requests").insert({
      requester_id: userId,
      payer_id: payerId,
      amount: Number(ousdAmount.toFixed(2)),
      // Temporarily commented out until schema cache is updated
      // original_amount: Number(parsedAmount.toFixed(2)),
      // original_currency_code: createCurrencyCode,
      note: noteWithOriginalInfo,
      status: "pending",
    });
    setLoading(false);

    if (error) {
      toast.error(error.message);
      return;
    }

    toast.success("Request sent");
    setAmount("");
    setNote("");
    setPayerId("");
    setSelectedPayer(null);
    await loadData();
  };

  const submitPay = async (request: PaymentRequest, requester?: Profile | null) => {
    setLoading(true);

    const parseOriginalAmount = (text?: string | null) => {
      if (!text) return null;
      
      // Try [CODE AMOUNT] format first (used in new inserts)
      const bracketMatch = text.match(/\[(\w+)\s+([\d.]+)\]/);
      if (bracketMatch) {
        return { code: bracketMatch[1].toUpperCase(), amount: Number(bracketMatch[2]) };
      }

      // Fallback to legacy "Original amount: AMOUNT CODE" format
      const match = text.match(/Original amount:\s*([0-9.,]+)\s*([A-Za-z]{2,6})/i);
      if (!match) return null;
      const rawAmount = match[1].replace(/,/g, "");
      const code = match[2].toUpperCase();
      const amountNum = Number(rawAmount);
      if (!Number.isFinite(amountNum) || amountNum <= 0) return null;
      return { amount: amountNum, code };
    };

    const original = parseOriginalAmount(request.note);

    let requestOusdAmount = Number(request.amount || 0);
    if (original) {
      const meta = currencies.find((c) => c.code === original.code);
      const rate = meta?.rate ?? 1;
      const computedOusd = rate ? (original.amount / rate) * PI_TO_USD : original.amount;
      if (Number.isFinite(computedOusd) && Math.abs(computedOusd - requestOusdAmount) > 0.01) {
        requestOusdAmount = computedOusd;
      }
    }

    const payMeta = currencies.find((c) => c.code === payCurrencyCode);
    const rate = payMeta?.rate ?? 1;
    const senderAmount = rate ? (requestOusdAmount / PI_TO_USD) * rate : 0;
    const { data, error } = await supabase.functions.invoke("send-money", {
      body: {
        receiver_id: request.requester_id,
        receiver_email: "__by_id__",
        amount: Number(requestOusdAmount.toFixed(2)),
        note: request.note || "Payment request",
        currency_code: payCurrencyCode,
        sender_amount: senderAmount,
        sender_currency_code: payCurrencyCode,
        receiver_amount: Number(requestOusdAmount.toFixed(2)),
        receiver_currency_code: "OUSD",
      },
    });

    if (error) {
      setLoading(false);
      toast.error(await getFunctionErrorMessage(error, "Payment failed"));
      return;
    }

    const { error: updateError } = await supabase
      .from("payment_requests")
      .update({ status: "paid", updated_at: new Date().toISOString() })
      .eq("id", request.id);

    setLoading(false);
    if (updateError) {
      toast.error(updateError.message);
      return;
    }

    const txId = String((data as { transaction_id?: string } | null)?.transaction_id || "");
    setReceiptData({
      transactionId: txId || request.id,
      ledgerTransactionId: txId || undefined,
      type: "send",
      amount: Number(requestOusdAmount.toFixed(2)),
      otherPartyName: requester?.full_name || "OpenPay User",
      otherPartyUsername: requester?.username || undefined,
      note: request.note || "Payment request",
      date: new Date(),
    });
    setReceiptOpen(true);
    toast.success("Request paid");
    playUiSound("send");
    await loadData();
  };

  const handleCreate = () => {
    if (!payerId || !selectedPayer) {
      toast.error("Select who you are requesting from");
      return;
    }
    const parsedAmount = Number(amount);
    if (!Number.isFinite(parsedAmount) || parsedAmount <= 0) {
      toast.error("Enter a valid amount");
      return;
    }

    setConfirmAction({
      type: "create",
      payer: selectedPayer,
      amount: parsedAmount,
      note: note.trim(),
      currencyCode: createCurrencyCode,
    });
    setConfirmModalOpen(true);
  };

  const handlePay = (request: PaymentRequest) => {
    setConfirmAction({
      type: "pay",
      request,
      requester: profileMap.get(request.requester_id) || null,
    });
    setConfirmModalOpen(true);
  };

  const submitReject = async (request: PaymentRequest) => {
    setLoading(true);
    const { error } = await supabase
      .from("payment_requests")
      .update({ status: "rejected", updated_at: new Date().toISOString() })
      .eq("id", request.id);
    setLoading(false);

    if (error) {
      toast.error(error.message);
      return;
    }

    toast.success("Request rejected");
    await loadData();
  };

  const handleReject = (request: PaymentRequest) => {
    setConfirmAction({
      type: "reject",
      request,
      requester: profileMap.get(request.requester_id) || null,
    });
    setConfirmModalOpen(true);
  };

  const handleConfirmAction = async () => {
    if (!confirmAction || loading) return;

    const { data: { user } } = await supabase.auth.getUser();
    const settings = user ? loadAppSecuritySettings(user.id) : null;
    const pinSetupCompleted = user ? isPinSetupCompleted(user.id) : false;

    if (confirmAction.type === "pay") {
      setConfirmModalOpen(false);
      
      // Navigate to PIN confirmation page if user has PIN set up
      if (pinSetupCompleted && settings?.pinHash) {
        navigate("/confirm-pin", {
          state: {
            title: "Confirm your OpenPay PIN",
            returnTo: "/request-payment",
            actionData: {
              kind: "request_pay",
              requestId: confirmAction.request.id
            }
          },
        });
      } else {
        // Proceed directly with pay if no PIN set up
        await submitPay(confirmAction.request, confirmAction.requester);
      }
      return;
    }

    if (confirmAction.type === "create") {
      await submitCreate();
      setConfirmModalOpen(false);
      setConfirmAction(null);
      return;
    }
    if (confirmAction.type === "reject") {
      await submitReject(confirmAction.request);
      setConfirmModalOpen(false);
      setConfirmAction(null);
    }
  };

  const getInitials = (name: string) => name.split(" ").map((n) => n[0]).join("").slice(0, 2).toUpperCase();

  if (pageLoading) {
    return <SplashScreen message="Loading requests..." />;
  }

  return (
    <div className="min-h-screen bg-paypal-blue px-4 pt-4 pb-10 text-white">
      <div className="flex items-center justify-between gap-3 px-4 pt-4 mb-4">
        <div className="flex items-center gap-3">
          <button onClick={() => navigate("/menu")}>
            <ArrowLeft className="w-6 h-6 text-white" />
          </button>
          <h1 className="text-xl font-bold text-white">Request Payment</h1>
        </div>
        <Button type="button" variant="secondary" className="h-9 rounded-full px-4 bg-white/10 text-white border-white/20 hover:bg-white/20" onClick={() => setShowInstructions(true)}>
          Instructions
        </Button>
      </div>

      <div className="px-4 space-y-4">
        <div className="bg-card rounded-2xl border border-gray-200 bg-gray-50 p-4 space-y-3">
          <div className="flex items-start justify-between gap-3">
            <div>
              <h2 className="font-semibold text-gray-900">Receive via QR</h2>
              <p className="text-sm text-gray-600">{selfProfile?.full_name || "Your account"}</p>
              {selfProfile?.username && <p className="text-sm text-gray-600">@{selfProfile.username}</p>}
              {/* Debug info removed */}
            </div>
            <Button type="button" variant="secondary" className="bg-blue-600 text-white hover:bg-blue-700 border-blue-700" onClick={() => setShowScanner(true)}>
              <ScanLine className="mr-2 h-4 w-4" />
              Scan QR code
            </Button>
          </div>
          <div className="flex justify-center rounded-2xl border border-gray-200 bg-white p-4">
            {receiveQrValue ? (
              <QRCodeSVG
                value={receiveQrValue}
                size={180}
                level="H"
                includeMargin
                imageSettings={{
                  src: "/openpay-logo.jpg",
                  height: 30,
                  width: 30,
                  excavate: true,
                }}
              />
            ) : (
              <p className="text-sm text-gray-600">Loading QR code...</p>
            )}
          </div>
          <p className="text-xs text-gray-600">
            Ask sender to scan this QR to open Express Send with your account.
          </p>
        </div>

        <div className="bg-card rounded-2xl border border-gray-200 bg-gray-50 p-4 space-y-3">
          <h2 className="font-semibold text-gray-900">Create request</h2>
          <Input
            placeholder="Search person by name, username, email, or account number"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="bg-white text-gray-900 placeholder:text-gray-500 border-gray-300"
          />
          <div className="rounded-xl border border-gray-200 bg-white px-3 py-2 text-sm text-gray-900">
            {selectedPayer ? (
              <div className="flex items-center justify-between gap-2">
                <div className="flex items-center gap-2">
                  {selectedPayer.avatar_url ? (
                    <img src={selectedPayer.avatar_url} alt={selectedPayer.full_name} className="h-8 w-8 rounded-full border border-border object-cover" />
                  ) : (
                    <div className="flex h-8 w-8 items-center justify-center rounded-full bg-secondary text-xs font-semibold text-white">
                      {selectedPayer.full_name.split(" ").map((n) => n[0]).join("").slice(0, 2).toUpperCase()}
                    </div>
                  )}
                  <div>
                    <p className="text-sm font-semibold text-gray-800">{selectedPayer.full_name}</p>
                    {selectedPayer.username && <p className="text-xs text-gray-600">@{selectedPayer.username}</p>}
                  </div>
                </div>
                <Button
                  type="button"
                  variant="outline"
                  className="h-8 rounded-full px-3"
                  onClick={() => { setSelectedPayer(null); setPayerId(""); }}
                >
                  Change
                </Button>
              </div>
            ) : (
              <div>
                <p className="text-xs uppercase tracking-wide text-gray-600">Select recipient</p>
                <div className="mt-2 max-h-40 overflow-auto rounded-xl border border-gray-200">
                  {isAccountNumberSearch && accountLookupLoading && (
                    <p className="border-b border-gray-200 px-3 py-2 text-sm text-gray-600">Searching account number...</p>
                  )}
                  {isAccountNumberSearch && !accountLookupLoading && accountLookupResult && (
                    <button
                      onClick={() => { setPayerId(accountLookupResult.id); setSelectedPayer(accountLookupResult); }}
                      className="w-full border-b border-gray-200 px-3 py-2 text-left hover:bg-gray-50"
                    >
                      <div className="flex items-center gap-2">
                        {accountLookupResult.avatar_url ? (
                          <img src={accountLookupResult.avatar_url} alt={accountLookupResult.full_name} className="h-9 w-9 rounded-full border border-border object-cover" />
                        ) : (
                          <div className="flex h-9 w-9 items-center justify-center rounded-full bg-secondary text-xs font-semibold text-gray-800">
                            {accountLookupResult.full_name.split(" ").map((n) => n[0]).join("").slice(0, 2).toUpperCase()}
                          </div>
                        )}
                        <div className="flex-1">
                          <p className="font-medium text-gray-800">{accountLookupResult.full_name}</p>
                          {accountLookupResult.username && <p className="text-sm text-gray-600">@{accountLookupResult.username}</p>}
                          <p className="text-xs text-gray-600">Matched by account number</p>
                        </div>
                        <Info className="h-4 w-4 text-gray-600" />
                      </div>
                    </button>
                  )}
                  {filteredWithoutAccountMatch.map((p) => (
                    <button
                      key={p.id}
                      onClick={() => { setPayerId(p.id); setSelectedPayer(p); }}
                      className="w-full text-left px-3 py-2 hover:bg-gray-50"
                    >
                      <div className="flex items-center gap-2">
                        {p.avatar_url ? (
                          <img src={p.avatar_url} alt={p.full_name} className="h-9 w-9 rounded-full border border-border object-cover" />
                        ) : (
                          <div className="flex h-9 w-9 items-center justify-center rounded-full bg-secondary text-xs font-semibold text-white">
                            {p.full_name.split(" ").map((n) => n[0]).join("").slice(0, 2).toUpperCase()}
                          </div>
                        )}
                        <div>
                          <p className="font-medium text-gray-800">{p.full_name}</p>
                          {p.username && <p className="text-sm text-gray-600">@{p.username}</p>}
                        </div>
                      </div>
                    </button>
                  ))}
                  {filteredWithoutAccountMatch.length === 0 && !accountLookupResult && !accountLookupLoading && (
                    <p className="px-3 py-4 text-sm text-gray-600">No users found</p>
                  )}
                </div>
              </div>
            )}
          </div>
          <Input
            type="number"
            min="0.01"
            step="0.01"
            placeholder="Amount"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            className="bg-white text-gray-900 placeholder:text-gray-500 border-gray-300"
          />
          <div>
            <p className="mb-1 text-sm text-gray-700">Requested currency</p>
            <div className="relative">
              {(createCurrencyCode === "PI" || createCurrencyCode === "OUSD") && (
                <img
                  src={createCurrencyCode === "PI" ? PURE_PI_ICON_URL : OPENPAY_ICON_URL}
                  alt={createCurrencyCode === "PI" ? "Pure Pi" : "Open USD"}
                  className="pointer-events-none absolute left-3 top-1/2 h-5 w-5 -translate-y-1/2 rounded-full object-cover"
                />
              )}
              <select
                value={createCurrencyCode}
                onChange={(e) => setCreateCurrencyCode(e.target.value)}
                className={`h-10 w-full rounded-xl border border-gray-300 bg-white text-sm text-gray-900 ${createCurrencyCode === "PI" || createCurrencyCode === "OUSD" ? "pl-10 pr-3" : "px-3"}`}
              >
                {currencies.map((c) => (
                  <option key={c.code} value={c.code}>
                    {`${c.code === "PI" ? "PI " : c.code === "OUSD" ? "" : `${c.flag} `}${getPiCodeLabel(c.code)} - ${c.name}`}
                  </option>
                ))}
              </select>
            </div>
          </div>
          <Textarea
            placeholder="Note (optional)"
            value={note}
            onChange={(e) => setNote(e.target.value)}
            className="bg-white text-gray-900 placeholder:text-gray-500 border-gray-300"
          />
          <Button onClick={handleCreate} disabled={loading || !payerId} className="w-full">
            {loading ? "Sending..." : "Send Request"}
          </Button>
        </div>

        <div className="bg-card rounded-2xl border border-gray-200 bg-gray-50 p-4 space-y-3">
          <h2 className="font-semibold text-gray-900">Incoming requests</h2>
          <div>
            <p className="mb-1 text-sm text-gray-700">Payment currency</p>
            <div className="relative">
              {(payCurrencyCode === "PI" || payCurrencyCode === "OUSD") && (
                <img
                  src={payCurrencyCode === "PI" ? PURE_PI_ICON_URL : OPENPAY_ICON_URL}
                  alt={payCurrencyCode === "PI" ? "Pure Pi" : "Open USD"}
                  className="pointer-events-none absolute left-3 top-1/2 h-5 w-5 -translate-y-1/2 rounded-full object-cover"
                />
              )}
              <select
                value={payCurrencyCode}
                onChange={(e) => setPayCurrencyCode(e.target.value)}
                className={`h-10 w-full rounded-xl border border-gray-300 bg-white text-sm text-gray-900 ${payCurrencyCode === "PI" || payCurrencyCode === "OUSD" ? "pl-10 pr-3" : "px-3"}`}
              >
                {currencies.map((c) => (
                  <option key={c.code} value={c.code}>
                    {`${c.code === "PI" ? "PI " : c.code === "OUSD" ? "" : `${c.flag} `}${getPiCodeLabel(c.code)} - ${c.name}`}
                  </option>
                ))}
              </select>
            </div>
          </div>
          {incoming.length === 0 && <p className="text-sm text-gray-600">No incoming requests</p>}
          {incoming.map((request) => {
            const requester = profileMap.get(request.requester_id);
            const parsed = parseOriginalAmount(request.note);
            const originalCurrency = parsed?.code;
            const originalAmount = parsed?.amount;
            const originalMeta = originalCurrency ? currencies.find((c) => c.code === originalCurrency) : null;
            return (
              <div key={request.id} className="border border-gray-200 rounded-xl p-3">
                <div className="flex items-center gap-2">
                  {requester?.avatar_url ? (
                    <img src={requester.avatar_url} alt={requester.full_name} className="h-10 w-10 rounded-full border border-border object-cover" />
                  ) : (
                    <div className="flex h-10 w-10 items-center justify-center rounded-full bg-gray-100 text-xs font-semibold text-gray-900">
                      {(requester?.full_name || "U").split(" ").map((n) => n[0]).join("").slice(0, 2).toUpperCase()}
                    </div>
                  )}
                  <div>
                    <p className="font-medium text-gray-900">{requester?.full_name || "Unknown user"}</p>
                    {requester?.username && <p className="text-sm text-gray-600">@{requester.username}</p>}
                  </div>
                </div>
                <p className="text-sm text-gray-600">{format(new Date(request.created_at), "MMM d, yyyy")}</p>
                <p className="font-semibold mt-1 text-gray-900">{formatCurrency(request.amount)}</p>
                {originalCurrency && Number.isFinite(Number(originalAmount)) && (
                  <p className="text-xs text-gray-600 mt-1">
                    Original: {originalMeta?.symbol || ""}{Number(originalAmount).toFixed(2)} {originalCurrency}
                  </p>
                )}
                {request.note && <p className="text-sm text-gray-600 mt-1">{request.note}</p>}
                <p className="text-sm mt-1 capitalize text-gray-900">Status: {request.status}</p>
                {request.status === "pending" && (
                  <div className="flex gap-2 mt-3">
                    <Button className="flex-1" disabled={loading} onClick={() => handlePay(request)}>
                      Pay
                    </Button>
                    <Button
                      variant="outline"
                      className="flex-1 bg-red-600 text-white hover:bg-red-700 border-red-600"
                      disabled={loading}
                      onClick={() => handleReject(request)}
                    >
                      Reject
                    </Button>
                  </div>
                )}
              </div>
            );
          })}
        </div>

        <div className="bg-card rounded-2xl border border-gray-200 bg-gray-50 p-4 space-y-3">
          <h2 className="font-semibold text-gray-900">Sent requests</h2>
          {outgoing.length === 0 && <p className="text-sm text-gray-600">No requests sent yet</p>}
          {outgoing.map((request) => {
            const payer = profileMap.get(request.payer_id);
            const parsed = parseOriginalAmount(request.note);
            const originalCurrency = parsed?.code;
            const originalAmount = parsed?.amount;
            const originalMeta = originalCurrency ? currencies.find((c) => c.code === originalCurrency) : null;
            return (
              <div key={request.id} className="border border-gray-200 rounded-xl p-3">
                <div className="flex items-center gap-2">
                  {payer?.avatar_url ? (
                    <img src={payer.avatar_url} alt={payer.full_name} className="h-10 w-10 rounded-full border border-border object-cover" />
                  ) : (
                    <div className="flex h-10 w-10 items-center justify-center rounded-full bg-gray-100 text-xs font-semibold text-gray-900">
                      {(payer?.full_name || "U").split(" ").map((n) => n[0]).join("").slice(0, 2).toUpperCase()}
                    </div>
                  )}
                  <div>
                    <p className="font-medium text-gray-900">{payer?.full_name || "Unknown user"}</p>
                    {payer?.username && <p className="text-sm text-gray-600">@{payer.username}</p>}
                  </div>
                </div>
                <p className="text-sm text-gray-600">{format(new Date(request.created_at), "MMM d, yyyy")}</p>
                <p className="font-semibold mt-1 text-gray-900">{formatCurrency(request.amount)}</p>
                {originalCurrency && Number.isFinite(Number(originalAmount)) && (
                  <p className="text-xs text-gray-600 mt-1">
                    Original: {originalMeta?.symbol || ""}{Number(originalAmount).toFixed(2)} {originalCurrency}
                  </p>
                )}
                {request.note && <p className="text-sm text-gray-600 mt-1">{request.note}</p>}
                <p className="text-sm mt-1 capitalize text-gray-900">Status: {request.status}</p>
              </div>
            );
          })}
        </div>
      </div>

      <Dialog open={showScanner} onOpenChange={setShowScanner}>
        <DialogContent className="max-w-md rounded-3xl">
          <div className="mb-2 flex items-center gap-2">
            <QrCode className="h-5 w-5 text-gray-800" />
            <DialogTitle className="text-lg font-semibold text-gray-800">Scan QR Code</DialogTitle>
          </div>
          <DialogDescription className="text-xs text-muted-foreground">
            Point your camera at an OpenPay receive QR code.
          </DialogDescription>
          <div id="openpay-receive-scanner" className="min-h-[260px] overflow-hidden rounded-2xl border border-gray-200" />
          {scanError && <p className="text-sm text-red-500">{scanError}</p>}
          <p className="text-xs text-gray-600">If camera does not open in Pi Browser, enable camera permission for this app and retry.</p>
        </DialogContent>
      </Dialog>

      <Dialog open={showInstructions} onOpenChange={setShowInstructions}>
        <DialogContent className="max-w-md rounded-3xl">
          <DialogTitle className="text-lg font-semibold text-gray-800">Request Payment Instructions</DialogTitle>
          <DialogDescription className="text-xs text-muted-foreground">
            Review before sending or paying a request.
          </DialogDescription>
          <div className="space-y-2 text-sm text-gray-800">
            <p>1. Confirm the name and username before you send a request.</p>
            <p>2. Verify the amount and note details carefully.</p>
            <p>3. Only pay requests from people you know and expected to transact with.</p>
            <p>4. If you do not recognize a request, reject or cancel it.</p>
          </div>
        </DialogContent>
      </Dialog>

      <Dialog
        open={confirmModalOpen}
        onOpenChange={(open) => {
          if (loading) return;
          setConfirmModalOpen(open);
          if (!open) setConfirmAction(null);
        }}
      >
        <DialogContent className="rounded-3xl">
          <DialogTitle className="text-xl font-bold text-gray-800">
            {confirmAction?.type === "create"
              ? "Confirm request"
              : confirmAction?.type === "pay"
                ? "Confirm payment"
                : "Confirm rejection"}
          </DialogTitle>
          <DialogDescription className="text-sm text-muted-foreground">
            Review the details before continuing.
          </DialogDescription>

          {(confirmAction?.type === "create" || confirmAction?.type === "pay" || confirmAction?.type === "reject") && (
            <div className="mt-3 flex items-center gap-3 rounded-2xl bg-secondary/70 px-3 py-2.5">
              {(confirmAction.type === "create" ? confirmAction.payer.avatar_url : confirmAction.requester?.avatar_url) ? (
                <img
                  src={confirmAction.type === "create" ? confirmAction.payer.avatar_url || "" : confirmAction.requester?.avatar_url || ""}
                  alt={confirmAction.type === "create" ? confirmAction.payer.full_name : confirmAction.requester?.full_name || "User"}
                  className="h-12 w-12 rounded-full border border-border object-cover"
                />
              ) : (
                <div className="flex h-12 w-12 items-center justify-center rounded-full bg-paypal-dark">
                  <span className="text-sm font-bold text-primary-foreground">
                    {getInitials(confirmAction.type === "create" ? confirmAction.payer.full_name : confirmAction.requester?.full_name || "User")}
                  </span>
                </div>
              )}
              <div>
                <p className="font-semibold text-gray-800">
                  {confirmAction.type === "create" ? confirmAction.payer.full_name : confirmAction.requester?.full_name || "Unknown user"}
                </p>
                {(confirmAction.type === "create" ? confirmAction.payer.username : confirmAction.requester?.username) && (
                  <p className="text-sm text-muted-foreground">
                    @{confirmAction.type === "create" ? confirmAction.payer.username : confirmAction.requester?.username}
                  </p>
                )}
              </div>
            </div>
          )}

          <div className="mt-4 space-y-2 rounded-2xl border border-gray-200 bg-gray-50 p-3 text-sm text-gray-900">
            <p className="flex items-center justify-between">
              <span className="text-gray-600">Amount</span>
              <span className="font-semibold text-gray-900">
                {confirmAction?.type === "create"
                  ? (() => {
                    const meta = currencies.find((c) => c.code === confirmAction.currencyCode);
                    const symbol = meta?.symbol ?? "";
                    return `${symbol}${confirmAction.amount.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ${confirmAction.currencyCode}`;
                  })()
                  : confirmAction?.type === "pay" || confirmAction?.type === "reject"
                    ? formatCurrency(confirmAction.request.amount)
                    : "-"}
              </span>
            </p>
            <p className="flex items-center justify-between">
              <span className="text-gray-600">Converted (USD)</span>
              <span className="font-semibold text-gray-900">
                ${confirmAction?.type === "create"
                  ? (() => {
                    const meta = currencies.find((c) => c.code === confirmAction.currencyCode);
                    const rate = meta?.rate ?? 1;
                    const ousd = rate ? (confirmAction.amount / rate) * PI_TO_USD : confirmAction.amount;
                    return ousd.toFixed(2);
                  })()
                  : confirmAction?.type === "pay" || confirmAction?.type === "reject"
                    ? Number(confirmAction.request.amount || 0).toFixed(2)
                    : "0.00"}
              </span>
            </p>
            <p className="flex items-start justify-between gap-2">
              <span className="text-gray-600">Note</span>
              <span className="max-w-[70%] break-all text-right text-gray-900">
                {confirmAction?.type === "create"
                  ? confirmAction.note || "No note"
                  : confirmAction?.type === "pay" || confirmAction?.type === "reject"
                    ? confirmAction.request.note || "Payment request"
                    : "No note"}
              </span>
            </p>
          </div>

          <p className="mt-3 rounded-md border border-paypal-light-blue/60 bg-[#edf3ff] px-2 py-1 text-xs text-paypal-blue">
            Approve only if you know this user and expected this transaction. If you do not recognize the user or request, cancel now.
          </p>

          <div className="mt-4 flex gap-2">
            <Button
              variant="outline"
              className="h-11 flex-1 rounded-2xl"
              disabled={loading}
              onClick={() => {
                setConfirmModalOpen(false);
                setConfirmAction(null);
              }}
            >
              Cancel
            </Button>
            <Button
              className={`h-11 flex-1 rounded-2xl text-white ${
                confirmAction?.type === "reject"
                  ? "bg-red-600 hover:bg-red-700"
                  : "bg-paypal-blue hover:bg-[#004dc5]"
              }`}
              disabled={loading}
              onClick={handleConfirmAction}
            >
              {loading
                ? "Processing..."
                : confirmAction?.type === "create"
                  ? "Confirm & Send"
                  : confirmAction?.type === "pay"
                    ? "Confirm & Pay"
                    : "Confirm & Reject"}
            </Button>
          </div>
        </DialogContent>
      </Dialog>


      <TransactionReceipt
        open={receiptOpen}
        onOpenChange={setReceiptOpen}
        receipt={receiptData}
      />
    </div>
  );
};

export default RequestMoney;
