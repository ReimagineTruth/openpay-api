import { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { ArrowLeft, HelpCircle, ImageIcon, RotateCcw, Search } from "lucide-react";
import { Html5Qrcode, Html5QrcodeSupportedFormats } from "html5-qrcode";
import { toast } from "sonner";
import BrandLogo from "@/components/BrandLogo";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";

const extractQrPayload = (rawValue: string) => {
  const value = rawValue.trim();
  if (!value) return { uid: null as string | null, username: "", amount: "", currency: "", note: "", checkoutSession: "", publicPayment: false };

  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (uuidRegex.test(value)) return { uid: value, username: "", amount: "", currency: "", note: "", checkoutSession: "", publicPayment: false };

  const normalizeUsername = (input: string | null | undefined) =>
    (input || "").trim().replace(/^@+/, "").toLowerCase();

  try {
    const parsed = new URL(value);
    const uidOrTo = parsed.searchParams.get("uid") || parsed.searchParams.get("to");
    const usernameParam = parsed.searchParams.get("username");
    const amount = parsed.searchParams.get("amount") || "";
    const currencyCode = (parsed.searchParams.get("currency") || "").toUpperCase();
    const note = parsed.searchParams.get("note") || "";
    
    // Check if this is a public payment QR code
    const isPublicPayment = parsed.protocol.toLowerCase() === "openpay:" && parsed.hostname.toLowerCase() === "public-payment";
    
    // Check if this is a POS QR code (different from checkout)
    const isPosPayment = parsed.protocol.toLowerCase() === "openpay-pos:" && parsed.hostname.toLowerCase() === "checkout";
    
    // Check if this is a POS payment QR code in openpay://pay format
    const isPosPayFormat = parsed.protocol.toLowerCase() === "openpay:" && 
                           parsed.hostname.toLowerCase() === "pay" && 
                           (parsed.searchParams.get("note")?.toLowerCase().includes("pos") || 
                            parsed.searchParams.get("note")?.toLowerCase().includes("payment"));
    
    // Check if this is a regular checkout link
    const isCheckoutLink = parsed.protocol.toLowerCase() === "openpay:" && 
                              (parsed.hostname.toLowerCase() === "checkout" || 
                               parsed.hostname.toLowerCase() === "payment-link" ||
                               parsed.hostname.toLowerCase().includes("localhost"));
    
    // Debug logging
    console.log("QR Detection Debug:", {
      protocol: parsed.protocol,
      hostname: parsed.hostname,
      pathname: parsed.pathname,
      searchParams: Object.fromEntries(parsed.searchParams),
      isPublicPayment,
      isPosPayment,
      isPosPayFormat,
      isCheckoutLink
    });
    
    // Extract session tokens differently for POS vs checkout
    let checkoutSession = null;
    let apiKeyType = null;
    
    if (isPosPayment) {
      // POS QR codes have session token in pathname
      checkoutSession = parsed.pathname.replace(/^\/+/, "");
      apiKeyType = "pos";
      console.log("POS Payment detected:", { checkoutSession, apiKeyType });
    } else if (isPosPayFormat) {
      // POS payment in openpay://pay format - no session, direct payment
      checkoutSession = null;
      apiKeyType = "pos";
      console.log("POS Pay Format detected:", { checkoutSession, apiKeyType });
    } else if (isCheckoutLink) {
      // Checkout links have session in query params
      checkoutSession = parsed.searchParams.get("session") || parsed.searchParams.get("checkout_session");
      apiKeyType = "checkout";
      console.log("Checkout Link detected:", { checkoutSession, apiKeyType });
    } else {
      // Regular checkout session
      checkoutSession = parsed.searchParams.get("session") || parsed.searchParams.get("checkout_session");
      // If it has a session parameter, treat it as a checkout link
      if (checkoutSession) {
        apiKeyType = "checkout";
        console.log("Session detected as checkout:", { checkoutSession, apiKeyType });
      }
    }
    
    return {
      uid: uidOrTo && uuidRegex.test(uidOrTo) ? uidOrTo : null,
      username: normalizeUsername(usernameParam),
      amount,
      currency: currencyCode,
      note,
      checkoutSession,
      publicPayment: isPublicPayment,
      posPayment: isPosPayment || isPosPayFormat,
      apiKeyType,
    };
  } catch {
    // Fallback for non-URL QR codes
    const maybeUid = value.split("uid=")[1]?.split("&")[0] || value.split("to=")[1]?.split("&")[0];
    const maybeUsername = value.split("username=")[1]?.split("&")[0]?.toLowerCase().trim();
    const maybeAmount = value.split("amount=")[1]?.split("&")[0] || "";
    const maybeCurrency = (value.split("currency=")[1]?.split("&")[0] || "").toUpperCase();
    const maybeNote = value.split("note=")[1]?.split("&")[0] || "";
    
    // Check for POS session tokens (opsess_ pattern) - more flexible matching
    const posSessionMatch = value.match(/^openpay-pos:\/\/checkout\/([^/?#]+)/i) || 
                                   value.match(/opsess_[a-zA-Z0-9]+/) ||
                                   (value.includes("opsess_") && value.includes("checkout"));
    let checkoutSession = null;
    let isPosPayment = false;
    let apiKeyType = null;
    
    console.log("Fallback QR Detection Debug:", {
      value,
      posSessionMatch,
      hasOpsess: value.includes("opsess_"),
      hasCheckout: value.includes("checkout"),
      hasSession: value.includes("session=")
    });
    
    if (posSessionMatch) {
      if (Array.isArray(posSessionMatch)) {
        checkoutSession = posSessionMatch[1];
      } else {
        checkoutSession = posSessionMatch;
      }
      isPosPayment = true;
      apiKeyType = "pos";
      console.log("Fallback POS Payment detected:", { checkoutSession, apiKeyType });
    } else {
      // Regular checkout session
      checkoutSession = value.split("session=")[1]?.split("&")[0] ||
        value.split("checkout_session=")[1]?.split("&")[0] || "";
      // If it has a session parameter, treat it as a checkout link
      if (checkoutSession) {
        apiKeyType = "checkout";
        console.log("Fallback Session detected as checkout:", { checkoutSession, apiKeyType });
      }
    }
    
    const isPublicPayment = value.includes("public-payment") && !isPosPayment;
    
    return {
      uid: maybeUid && uuidRegex.test(maybeUid) ? maybeUid : null,
      username: maybeUsername,
      amount: maybeAmount,
      currency: maybeCurrency,
      note: maybeNote,
      checkoutSession,
      publicPayment: isPublicPayment,
      posPayment: isPosPayment,
      apiKeyType,
    };
  }
};

const isOpenPayQrCode = (rawValue: string) => {
  const value = rawValue.trim();
  if (!value) return false;
  
  // Check for direct UUID
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (uuidRegex.test(value)) return true;

  // Check for base64 encoded data (PDF QR codes, images)
  if (value.startsWith('data:image/') || value.startsWith('data:application/pdf') || value.startsWith('data:')) {
    // For PDF QR codes and image QR codes, we need to extract text content
    return true; // Accept these for processing
  }

  try {
    const parsed = new URL(value);
    const protocol = parsed.protocol.toLowerCase();
    const host = parsed.hostname.toLowerCase();
    const path = parsed.pathname.toLowerCase();
    const hasRecipient = Boolean(parsed.searchParams.get("uid") || parsed.searchParams.get("to") || parsed.searchParams.get("username"));
    const hasSession = Boolean(parsed.searchParams.get("session") || parsed.searchParams.get("checkout_session"));
    const hasAmount = Boolean(parsed.searchParams.get("amount"));
    const hasNote = Boolean(parsed.searchParams.get("note"));
    const hasLinkToken = Boolean(parsed.searchParams.get("link_token") || parsed.searchParams.get("token"));
    const hasTxId = Boolean(parsed.searchParams.get("tx") || parsed.searchParams.get("transaction_id"));

    if (protocol === "openpay:") {
      // Support for public payment QR codes
      if (host === "public-payment") return true;
      // Support for regular payment QR codes (send/receive)
      if (host === "pay" || host === "send" || host === "receive") return hasRecipient;
      // Support for checkout link QR codes
      if (host === "checkout" || host === "payment-link") return hasLinkToken || hasSession;
      // Support for receipt QR codes
      if (host === "receipt" || host === "transaction") return hasTxId || hasSession;
      return hasRecipient;
    }

    if (protocol === "openpay-pos:") {
      // Support for POS checkout QR codes
      const sessionToken = parsed.pathname.replace(/^\/+/, "");
      return host === "checkout" && (sessionToken.startsWith("opsess_") || sessionToken.length > 10);
    }

    if (protocol === "http:" || protocol === "https:") {
      const isOpenPayDomain = host.includes("openpay") || host.includes("localhost");
      const isPayPath = path.startsWith("/send") || path.startsWith("/pay") || path.startsWith("/public-payment");
      const isReceivePath = path.startsWith("/receive") || path.startsWith("/request");
      const isCheckoutPath = path.startsWith("/checkout") || path.startsWith("/payment-link") || path.startsWith("/merchant-checkout");
      const isReceiptPath = path.startsWith("/receipt") || path.startsWith("/transaction") || path.startsWith("/thank-you");
      const isPosPath = path.startsWith("/pos") || path.startsWith("/merchant-pos");
      const hasCheckoutSession = Boolean(parsed.searchParams.get("checkout_session") || parsed.searchParams.get("session"));
      
      return isOpenPayDomain && (
        (hasRecipient && (isPayPath || isReceivePath)) || 
        hasCheckoutSession || 
        hasSession || 
        hasAmount ||
        hasLinkToken ||
        hasTxId ||
        isCheckoutPath ||
        isReceiptPath ||
        isPosPath
      );
    }
  } catch {
    // If URL parsing fails, try to parse as plain text
    // Check for common OpenPay patterns
    const lowerValue = value.toLowerCase();
    
    // Check for all openpay:// patterns
    if (lowerValue.startsWith('openpay://')) return true;
    
    // Check for openpay-pos:// patterns
    if (lowerValue.startsWith('openpay-pos://')) return true;
    
    // Check for session tokens (POS, checkout)
    if (lowerValue.includes('opsess_') || lowerValue.includes('session=')) return true;
    
    // Check for payment link tokens
    if (lowerValue.includes('oplink_') || lowerValue.includes('link_token=')) return true;
    
    // Check for transaction IDs (receipts)
    if (lowerValue.includes('tx=') || lowerValue.includes('transaction_id=')) return true;
    
    // Check for UUID patterns in text (receive/send)
    if (uuidRegex.test(value)) return true;
    
    // Check for common payment parameters
    if (lowerValue.includes('uid=') || lowerValue.includes('to=') || lowerValue.includes('amount=')) return true;
    
    // Check for receive parameters
    if (lowerValue.includes('from=') || lowerValue.includes('request=')) return true;
    
    // Check for checkout parameters
    if (lowerValue.includes('checkout=') || lowerValue.includes('payment=')) return true;
    
    // Check for receipt parameters
    if (lowerValue.includes('receipt=') || lowerValue.includes('confirm=')) return true;
    
    // Check for account numbers (receive)
    if (lowerValue.includes('account=') || lowerValue.includes('wallet=')) return true;
    
    return false;
  }

  return false;
};

const QrScannerPage = () => {
  const scannerBeepUrl = "https://www.myinstants.com/media/sounds/store-scanner-beep-sound-effect.mp3";
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [scanError, setScanError] = useState("");
  const [scanning, setScanning] = useState(false);
  const [scanHint, setScanHint] = useState("Initializing camera...");
  const [pastedCode, setPastedCode] = useState("");
  const [showInstructions, setShowInstructions] = useState(false);
  const [retryToken, setRetryToken] = useState(0);
  const [scanMode, setScanMode] = useState<"camera" | "photo" | "paste">("camera");
  const [manualQuery, setManualQuery] = useState("");
  const scannerRef = useRef<Html5Qrcode | null>(null);
  const fileScannerRef = useRef<Html5Qrcode | null>(null);
  const scannerBeepRef = useRef<HTMLAudioElement | null>(null);
  const audioUnlockReadyRef = useRef(false);
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const handlingDecodeRef = useRef(false);
  const lastInvalidToastAtRef = useRef(0);
  const lastHintUpdateRef = useRef(0);

  const returnTo = useMemo(() => {
    const requested = searchParams.get("returnTo") || "/send";
    return requested.startsWith("/") ? requested : "/send";
  }, [searchParams]);

  const stopScanner = async () => {
    if (!scannerRef.current) return;
    try {
      if (scannerRef.current.isScanning) {
        await scannerRef.current.stop();
      }
    } catch {
      // no-op
    }
    try {
      scannerRef.current.clear();
    } catch {
      // no-op
    }
  };

  const patchVideoElementForMobile = () => {
    if (typeof document === "undefined") return;
    const video = document.querySelector("#openpay-full-scanner video") as HTMLVideoElement | null;
    if (!video) return;
    video.setAttribute("playsinline", "true");
    video.setAttribute("webkit-playsinline", "true");
    video.setAttribute("autoplay", "true");
    video.setAttribute("muted", "true");
  };

  const playScanBeep = () => {
    if (typeof window === "undefined") return;
    if (!scannerBeepRef.current) {
      scannerBeepRef.current = new Audio(scannerBeepUrl);
      scannerBeepRef.current.preload = "auto";
      scannerBeepRef.current.volume = 0.95;
    }
    const playFallbackTone = () => {
      const AudioCtx = window.AudioContext || (window as typeof window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
      if (!AudioCtx) return;
      try {
        const audioContext = new AudioCtx();
        const oscillator = audioContext.createOscillator();
        const gainNode = audioContext.createGain();
        oscillator.type = "sine";
        oscillator.frequency.setValueAtTime(1046, audioContext.currentTime);
        gainNode.gain.setValueAtTime(0.0001, audioContext.currentTime);
        gainNode.gain.exponentialRampToValueAtTime(0.08, audioContext.currentTime + 0.01);
        gainNode.gain.exponentialRampToValueAtTime(0.0001, audioContext.currentTime + 0.12);
        oscillator.connect(gainNode);
        gainNode.connect(audioContext.destination);
        oscillator.start(audioContext.currentTime);
        oscillator.stop(audioContext.currentTime + 0.12);
        oscillator.onended = () => {
          void audioContext.close();
        };
      } catch {
        // no-op
      }
    };
    try {
      scannerBeepRef.current.currentTime = 0;
      const playPromise = scannerBeepRef.current.play();
      if (playPromise && typeof playPromise.catch === "function") {
        void playPromise.catch(() => {
          playFallbackTone();
        });
      }
    } catch {
      playFallbackTone();
    }
  };

  useEffect(() => {
    if (typeof window === "undefined") return;

    const unlockAudio = () => {
      if (audioUnlockReadyRef.current) return;
      audioUnlockReadyRef.current = true;
      if (!scannerBeepRef.current) {
        scannerBeepRef.current = new Audio(scannerBeepUrl);
        scannerBeepRef.current.preload = "auto";
        scannerBeepRef.current.volume = 0.95;
      }
      scannerBeepRef.current.load();
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
  }, [scannerBeepUrl]);

  const handleDecoded = async (decodedText: string) => {
    if (handlingDecodeRef.current) return;
    handlingDecodeRef.current = true;

    try {
      // Validate the decoded text
      if (!decodedText || decodedText.trim().length < 3) {
        const now = Date.now();
        setScanHint("QR code appears to be empty or invalid.");
        if (now - lastInvalidToastAtRef.current > 1800) {
          toast.error("Invalid QR code - no data found");
          lastInvalidToastAtRef.current = now;
        }
        handlingDecodeRef.current = false;
        return;
      }

      if (!isOpenPayQrCode(decodedText)) {
        const now = Date.now();
        setScanHint("QR detected, but this is not an OpenPay QR code.");
        if (now - lastInvalidToastAtRef.current > 1800) {
          toast.error("Only OpenPay QR codes are allowed");
          lastInvalidToastAtRef.current = now;
        }
        handlingDecodeRef.current = false;
        return;
      }

      setScanHint("OpenPay QR detected. Validating...");
      const payload = extractQrPayload(decodedText);
      
      console.log("Extracted QR Payload:", payload);
      
      // Handle POS payment QR codes - original behavior
      if (payload.posPayment) {
        console.log("Handling POS payment QR code");
        setScanHint("POS payment QR detected. Opening payment page...");
        playScanBeep();
        await stopScanner();
        
        // Navigate to send payment page with POS details
        const params = new URLSearchParams();
        if (payload.checkoutSession) {
          params.set("pos_session", payload.checkoutSession);
        }
        if (payload.uid) {
          params.set("to", payload.uid);
        }
        if (payload.username) {
          params.set("username", payload.username);
        }
        params.set("note", payload.note || "POS Payment");
        params.set("amount", payload.amount || "");
        params.set("currency", payload.currency || "USD");
        
        navigate(`/send?${params.toString()}`, { replace: true });
        handlingDecodeRef.current = false;
        return;
      }
      
      // Handle checkout link QR codes - original behavior
      if (payload.apiKeyType === "checkout" && payload.checkoutSession && !payload.posPayment) {
        console.log("Handling checkout link QR code");
        setScanHint("Checkout link QR detected. Opening payment page...");
        playScanBeep();
        await stopScanner();
        
        const params = new URLSearchParams();
        if (payload.checkoutSession) {
          params.set("session", payload.checkoutSession);
        }
        // Add customer details if present
        const customerName = decodedText.match(/customer_name=([^&]+)/)?.[1];
        const customerEmail = decodedText.match(/customer_email=([^&]+)/)?.[1];
        const customerPhone = decodedText.match(/customer_phone=([^&]+)/)?.[1];
        const customerAddress = decodedText.match(/customer_address=([^&]+)/)?.[1];
        
        if (customerName) params.set("customer_name", decodeURIComponent(customerName));
        if (customerEmail) params.set("customer_email", decodeURIComponent(customerEmail));
        if (customerPhone) params.set("customer_phone", decodeURIComponent(customerPhone));
        if (customerAddress) params.set("customer_address", decodeURIComponent(customerAddress));
        
        navigate(`/public-payment?${params.toString()}`, { replace: true });
        handlingDecodeRef.current = false;
        return;
      }
      
      // Handle public payment QR codes
      if (payload.publicPayment || (payload.checkoutSession && !payload.posPayment)) {
        setScanHint("Public payment QR detected. Opening payment page...");
        playScanBeep();
        await stopScanner();
        
        const params = new URLSearchParams();
        if (payload.checkoutSession) {
          params.set("session", payload.checkoutSession);
        }
        // Add customer details if present
        const customerName = decodedText.match(/customer_name=([^&]+)/)?.[1];
        const customerEmail = decodedText.match(/customer_email=([^&]+)/)?.[1];
        const customerPhone = decodedText.match(/customer_phone=([^&]+)/)?.[1];
        const customerAddress = decodedText.match(/customer_address=([^&]+)/)?.[1];
        
        if (customerName) params.set("customer_name", decodeURIComponent(customerName));
        if (customerEmail) params.set("customer_email", decodeURIComponent(customerEmail));
        if (customerPhone) params.set("customer_phone", decodeURIComponent(customerPhone));
        if (customerAddress) params.set("customer_address", decodeURIComponent(customerAddress));
        
        navigate(`/public-payment?${params.toString()}`, { replace: true });
        handlingDecodeRef.current = false;
        return;
      }
      
      let recipientId = payload.uid;
      let resolvedAmount = payload.amount;
      let resolvedCurrency = payload.currency;
      let resolvedNote = payload.note;

      // If no recipient found but we have a checkout session, try to get merchant info
      if (!recipientId && payload.checkoutSession) {
        try {
          const { data: checkoutPayload } = await (supabase as any).rpc("get_public_merchant_checkout_session", {
            p_session_token: payload.checkoutSession,
          });
          const checkoutRow = Array.isArray(checkoutPayload) ? checkoutPayload[0] : checkoutPayload;
          if (checkoutRow) {
            const merchantUserId = String(checkoutRow.merchant_user_id || "");
            if (merchantUserId) recipientId = merchantUserId;
            const checkoutAmount = Number(checkoutRow.total_amount || 0);
            if (checkoutAmount > 0) resolvedAmount = checkoutAmount.toFixed(2);
            const checkoutCurrency = String(checkoutRow.currency || "").toUpperCase();
            if (checkoutCurrency) resolvedCurrency = checkoutCurrency;
            if (!resolvedNote) {
              resolvedNote = `Merchant checkout ${String(checkoutRow.session_token || payload.checkoutSession)}`;
            }
          }
        } catch (error) {
          console.error("Failed to fetch checkout session:", error);
        }
      }

      // Try to find user by username if no recipient ID
      if (!recipientId && payload.username) {
        try {
          const { data } = await supabase
            .from("profiles")
            .select("id")
            .ilike("username", payload.username)
            .limit(1)
            .maybeSingle();
          recipientId = data?.id || null;
        } catch (error) {
          console.error("Failed to find user by username:", error);
        }
      }

      // Validate that we have a valid recipient
      if (!recipientId) {
        const now = Date.now();
        setScanHint("OpenPay QR format is valid, but recipient was not found.");
        if (now - lastInvalidToastAtRef.current > 1800) {
          toast.error("Invalid QR code - recipient not found");
          lastInvalidToastAtRef.current = now;
        }
        handlingDecodeRef.current = false;
        return;
      }

      // Build payment parameters
      const params = new URLSearchParams({ to: recipientId });
      if (resolvedAmount && Number.isFinite(Number(resolvedAmount)) && Number(resolvedAmount) > 0) {
        params.set("amount", Number(resolvedAmount).toFixed(2));
      }
      if (resolvedCurrency) {
        params.set("currency", resolvedCurrency);
      }
      if (resolvedNote) {
        params.set("note", resolvedNote);
      }
      if (payload.checkoutSession) {
        params.set("checkout_session", payload.checkoutSession);
      }

      setScanHint("Recipient found. Opening payment...");
      playScanBeep();
      await stopScanner();
      navigate(`${returnTo}?${params.toString()}`, { replace: true });
    } catch (error) {
      console.error("QR processing error:", error);
      const now = Date.now();
      setScanHint("Error processing QR code.");
      if (now - lastInvalidToastAtRef.current > 1800) {
        toast.error("Failed to process QR code");
        lastInvalidToastAtRef.current = now;
      }
    } finally {
      handlingDecodeRef.current = false;
    }
  };

  useEffect(() => {
    if (typeof window === "undefined") return;
    const key = "openpay_scan_instructions_ack_v1";
    const seen = localStorage.getItem(key) === "1";
    if (!seen) setShowInstructions(true);
  }, []);

  useEffect(() => {
    let mounted = true;
    handlingDecodeRef.current = false;

    if (scanMode !== "camera") {
      setScanning(false);
      setScanError("");
      setScanHint("Camera paused. Switch back to Camera to scan live QR.");
      void stopScanner();
      return () => {
        mounted = false;
      };
    }

    const waitForScannerElement = async () => {
      if (typeof document === "undefined") return false;
      for (let i = 0; i < 12; i += 1) {
        if (document.getElementById("openpay-full-scanner")) return true;
        await new Promise((resolve) => requestAnimationFrame(resolve));
      }
      return false;
    };

    const startScanner = async () => {
      await stopScanner();
      const hasScannerElement = await waitForScannerElement();
      if (!hasScannerElement) {
        if (mounted) setScanError("Scanner failed to mount. Please retry.");
        return;
      }
      if (typeof window !== "undefined" && !window.isSecureContext) {
        if (mounted) setScanError("Camera requires HTTPS (or localhost).");
        return;
      }
      if (typeof navigator === "undefined" || !navigator.mediaDevices?.getUserMedia) {
        if (mounted) setScanError("Camera is not available on this device/browser.");
        return;
      }

      const scanner = new Html5Qrcode("openpay-full-scanner", {
        useBarCodeDetectorIfSupported: false,
        verbose: false,
      });
      scannerRef.current = scanner;

      try {
        let cameras: Awaited<ReturnType<typeof Html5Qrcode.getCameras>> = [];
        try {
          cameras = await Html5Qrcode.getCameras();
        } catch {
          // Some browsers block camera enumeration until stream opens. Keep fallback sources.
        }
        const preferredBack = cameras.find((cam) => /(back|rear|environment)/i.test(cam.label || ""));
        const sources: Array<string | MediaTrackConstraints> = [];
        sources.push({ facingMode: { exact: "environment" } });
        sources.push({ facingMode: { ideal: "environment" } });
        sources.push({ facingMode: "environment" });
        if (preferredBack?.id) sources.push(preferredBack.id);
        if (cameras[0]?.id) sources.push(cameras[0].id);
        sources.push({ facingMode: "user" });

        const scanConfig = {
          fps: 18,
          disableFlip: false,
          formatsToSupport: [
            Html5QrcodeSupportedFormats.QR_CODE,
            Html5QrcodeSupportedFormats.AZTEC,
            Html5QrcodeSupportedFormats.CODABAR,
            Html5QrcodeSupportedFormats.DATA_MATRIX,
            Html5QrcodeSupportedFormats.PDF_417,
          ],
          qrbox: (viewfinderWidth: number, viewfinderHeight: number) => {
            const minEdgeSize = Math.min(viewfinderWidth, viewfinderHeight);
            const qrboxSize = Math.floor(minEdgeSize * 0.85);
            return {
              width: qrboxSize,
              height: qrboxSize,
            };
          },
        };

        let started = false;
        let startError = "";
        for (const source of sources) {
          try {
            await scanner.start(source, scanConfig, (decodedText) => {
              void handleDecoded(decodedText);
            }, (errorMessage) => {
              const now = Date.now();
              if (now - lastHintUpdateRef.current < 400) return;
              lastHintUpdateRef.current = now;
              const raw = String(errorMessage || "").toLowerCase();
              if (raw.includes("notfoundexception") || raw.includes("no multi-format readers")) {
                setScanHint("No QR detected yet. Keep the code inside the frame.");
                return;
              }
              if (raw.includes("checksum") || raw.includes("format") || raw.includes("decode")) {
                setScanHint("QR is blurry or unclear. Move closer and improve lighting.");
                return;
              }
              if (raw.includes("camera") || raw.includes("permission")) {
                setScanHint("Camera permission needed. Allow camera access to scan QR codes.");
                return;
              }
              if (raw.includes("device") || raw.includes("not supported")) {
                setScanHint("Camera not supported. Try using photo upload or paste QR code.");
                return;
              }
              setScanHint("Scanning in progress... Keep the QR code steady and well-lit.");
            });
            patchVideoElementForMobile();
            started = true;
            if (mounted) {
              setScanError("");
              setScanning(true);
              setScanHint("Camera ready. Point to an OpenPay QR code.");
            }
            break;
          } catch (error) {
            startError = error instanceof Error ? error.message : "Unable to open camera";
          }
        }

        if (!started && mounted) setScanError(startError || "Unable to open camera");
      } catch (error) {
        if (mounted) setScanError(error instanceof Error ? error.message : "Unable to open camera");
      }
    };

    void startScanner();

    return () => {
      mounted = false;
      void stopScanner();
      scannerRef.current = null;
      try {
        fileScannerRef.current?.clear();
      } catch {
        // no-op
      }
      fileScannerRef.current = null;
    };
  }, [returnTo, retryToken, scanMode]);

  const handleSelectFile = async (file: File) => {
    try {
      if (!fileScannerRef.current) {
        fileScannerRef.current = new Html5Qrcode("openpay-file-scanner");
      }
      if (fileScannerRef.current.isScanning) {
        await fileScannerRef.current.stop();
      }
      
      const decoded = await fileScannerRef.current.scanFile(file);
      await handleDecoded(decoded);
    } catch (error) {
      setScanHint("Could not detect a clear OpenPay QR from this image.");
      toast.error(error instanceof Error ? error.message : "Unable to read QR from image");
    }
  };

  const handleUsePastedCode = async () => {
    if (!pastedCode.trim()) {
      toast.error("Paste an OpenPay QR code/link first");
      return;
    }
    await handleDecoded(pastedCode.trim());
  };

  const handleManualSearch = async () => {
    const raw = manualQuery.trim();
    if (!raw) {
      toast.error("Enter @username, name, email, or account number");
      return;
    }
    await stopScanner();
    navigate(`/send?search=${encodeURIComponent(raw)}`, { replace: true });
  };

  const handleAcknowledgeInstructions = () => {
    if (typeof window !== "undefined") {
      localStorage.setItem("openpay_scan_instructions_ack_v1", "1");
    }
    setShowInstructions(false);
  };

  return (
    <div className="fixed inset-0 h-[100dvh] w-screen bg-paypal-blue text-white">
      <div className="relative h-full w-full overflow-hidden">
        <style>{`
          #openpay-full-scanner {
            position: absolute !important;
            inset: 0 !important;
            width: 100% !important;
            height: 100% !important;
            overflow: hidden !important;
            background: #063991 !important;
          }
          #openpay-full-scanner > div {
            position: absolute !important;
            inset: 0 !important;
          }
          #openpay-full-scanner video {
            position: absolute !important;
            top: 0 !important;
            left: 0 !important;
            width: 100% !important;
            height: 100% !important;
            object-fit: cover !important;
            transform: translateZ(0);
            background: #063991 !important;
          }
          #openpay-full-scanner__scan_region {
            position: absolute !important;
            inset: 0 !important;
            width: 100% !important;
            height: 100% !important;
            min-height: 100% !important;
            margin: 0 !important;
            border: 0 !important;
            background: transparent !important;
          }
          #openpay-full-scanner__scan_region img,
          #openpay-full-scanner__scan_region canvas {
            opacity: 0 !important;
            pointer-events: none !important;
          }
          #openpay-full-scanner__dashboard {
            display: none !important;
          }
          #openpay-full-scanner__dashboard_section_csr {
            display: none !important;
          }
          @keyframes scan {
            0% { top: 0; }
            50% { top: 100%; }
            100% { top: 0; }
          }
        `}</style>
        <div className="relative z-10 h-[100dvh] overflow-hidden px-5 pt-4 pb-5">
          <div className="mx-auto flex h-full w-full max-w-xl flex-col pb-[max(0.75rem,env(safe-area-inset-bottom))]">
          <div className="flex items-center justify-between gap-2">
            <button
              onClick={() => navigate(returnTo)}
              className="flex h-10 w-10 items-center justify-center rounded-full border border-white/25 bg-black/35"
              aria-label="Back"
            >
              <ArrowLeft className="h-5 w-5" />
            </button>
            <h1 className="text-2xl font-bold">Scan QR code</h1>
            <div className="flex items-center gap-2">
              <button
                onClick={() => {
                  setScanError("");
                  setScanHint("Retrying camera...");
                  setRetryToken((prev) => prev + 1);
                }}
                className="flex h-10 w-10 items-center justify-center rounded-full border border-white/25 bg-black/35"
                aria-label="Retry camera"
              >
                <RotateCcw className="h-5 w-5" />
              </button>
              <button
                onClick={() => setShowInstructions(true)}
                className="flex h-10 w-10 items-center justify-center rounded-full border border-white/25 bg-black/35"
                aria-label="Help"
              >
                <HelpCircle className="h-5 w-5" />
              </button>
            </div>
          </div>

          <div className="mt-4 grid grid-cols-3 gap-2 rounded-2xl border border-white/20 bg-black/20 p-2">
            <Button
              type="button"
              variant={scanMode === "camera" ? "default" : "outline"}
              className={`h-9 rounded-xl ${scanMode === "camera" ? "bg-paypal-blue text-white hover:bg-[#004dc5]" : "border-white/35 bg-black/25 text-white hover:bg-black/45"}`}
              onClick={() => setScanMode("camera")}
            >
              Camera
            </Button>
            <Button
              type="button"
              variant={scanMode === "photo" ? "default" : "outline"}
              className={`h-9 rounded-xl ${scanMode === "photo" ? "bg-paypal-blue text-white hover:bg-[#004dc5]" : "border-white/35 bg-black/25 text-white hover:bg-black/45"}`}
              onClick={() => setScanMode("photo")}
            >
              Photo
            </Button>
            <Button
              type="button"
              variant={scanMode === "paste" ? "default" : "outline"}
              className={`h-9 rounded-xl ${scanMode === "paste" ? "bg-paypal-blue text-white hover:bg-[#004dc5]" : "border-white/35 bg-black/25 text-white hover:bg-black/45"}`}
              onClick={() => setScanMode("paste")}
            >
              Paste
            </Button>
          </div>

          <div className="mt-3 text-center">
            <p className="text-xl font-semibold">Please confirm</p>
            <p className="text-base text-white/90">which QR you are scanning for payment</p>
            <div className="mt-3 flex items-center justify-center gap-2">
              <BrandLogo className="h-8 w-8" />
              <span className="text-2xl font-bold tracking-tight">OpenPay</span>
            </div>
          </div>

          {scanMode === "camera" && (
            <>
              <div className="mt-3">
                <div className="relative h-[55dvh] min-h-[300px] overflow-hidden rounded-3xl border border-white/40 bg-black/30 shadow-2xl shadow-black/50">
                  <div id="openpay-full-scanner" className="absolute inset-0" />
                  <div
                    className={`pointer-events-none absolute inset-0 ${
                      scanning ? "bg-black/5" : "bg-black/30"
                    } transition`}
                  />
                  <div className="pointer-events-none absolute inset-0 flex items-center justify-center p-6">
                    <div className="relative h-[280px] w-[280px] sm:h-[320px] sm:w-[320px] border border-white/30 bg-black/5">
                      <div className="absolute -left-1 -top-1 h-12 w-12 border-l-[6px] border-t-[6px] border-white drop-shadow-md" />
                      <div className="absolute -right-1 -top-1 h-12 w-12 border-r-[6px] border-t-[6px] border-white drop-shadow-md" />
                      <div className="absolute -bottom-1 -left-1 h-12 w-12 border-b-[6px] border-l-[6px] border-white drop-shadow-md" />
                      <div className="absolute -bottom-1 -right-1 h-12 w-12 border-b-[6px] border-r-[6px] border-white drop-shadow-md" />
                      
                      {/* Scanning animation line */}
                      {scanning && (
                        <div className="absolute left-0 top-0 h-1 w-full bg-white/50 blur-[1px] animate-[scan_3s_infinite]" />
                      )}
                    </div>
                  </div>
                </div>
              </div>
              <p className="mt-3 text-center text-base font-semibold text-white/90 drop-shadow-sm">Position the QR code within the frame to pay</p>
            </>
          )}
          {scanError && <p className="mt-3 text-center text-sm text-red-300">{scanError}</p>}
          {scanError && (
            <div className="mt-2 flex justify-center">
              <Button
                type="button"
                variant="outline"
                className="h-9 rounded-xl border-white/40 bg-black/30 text-white hover:bg-black/45"
                onClick={() => {
                  setScanError("");
                  setScanHint("Retrying camera...");
                  setRetryToken((prev) => prev + 1);
                }}
              >
                <RotateCcw className="mr-2 h-4 w-4" />
                Retry Camera
              </Button>
            </div>
          )}
          {!scanError && <p className="mt-3 text-center text-sm text-white/80">{scanHint}</p>}
          {!scanError && scanMode === "camera" && !scanning && (
            <p className="mt-1 text-center text-xs text-white/70">Opening camera...</p>
          )}

          <div className={`${scanMode === "camera" ? "mt-3" : "mt-3 flex flex-1 items-center justify-center"}`}>
            <input
              ref={fileInputRef}
              type="file"
              accept="image/*"
              className="hidden"
              onChange={(event) => {
                const file = event.target.files?.[0];
                if (file) void handleSelectFile(file);
                event.currentTarget.value = "";
              }}
            />
            {scanMode === "photo" && (
              <button
                onClick={() => fileInputRef.current?.click()}
                className="w-full max-w-md rounded-2xl border border-white/40 bg-black/25 py-4 text-xl font-semibold"
              >
                <span className="inline-flex items-center gap-2">
                  <ImageIcon className="h-6 w-6" />
                  Select From Photos
                </span>
              </button>
            )}

            {scanMode === "paste" && (
              <div className="w-full max-w-md rounded-2xl border border-white/30 bg-black/30 p-3">
                <p className="mb-2 text-sm text-white/85">Paste OpenPay code/link</p>
                <input
                  value={pastedCode}
                  onChange={(event) => setPastedCode(event.target.value)}
                  placeholder="openpay://pay?... or https://.../send?to=..."
                  className="h-11 w-full rounded-xl border border-white/30 bg-black/30 px-3 text-sm text-white placeholder:text-white/55"
                />
                <button
                  onClick={() => void handleUsePastedCode()}
                  className="mt-2 h-11 w-full rounded-xl border border-white/40 bg-black/35 text-base font-semibold"
                >
                  Use Pasted Code
                </button>
              </div>
            )}

            {scanMode === "camera" && (
              <div className="rounded-2xl border border-white/30 bg-black/30 p-3 text-center text-sm text-white/80">
                Live camera mode is active.
              </div>
            )}
          </div>

          {scanMode !== "camera" && (
            <div className="mt-3 rounded-2xl border border-white/30 bg-black/30 p-3">
              <p className="text-sm font-semibold text-white">Express Search (if scanner fails)</p>
              <p className="mt-1 text-xs text-white/75">Enter @username, name, Gmail/email handle, or OP account number.</p>
              <div className="mt-2 flex gap-2">
                <input
                  value={manualQuery}
                  onChange={(event) => setManualQuery(event.target.value)}
                  onKeyDown={(event) => {
                    if (event.key === "Enter") {
                      event.preventDefault();
                      void handleManualSearch();
                    }
                  }}
                  placeholder="@username, name, gmail, OP123..."
                  className="h-11 w-full rounded-xl border border-white/30 bg-black/35 px-3 text-sm text-white placeholder:text-white/55"
                />
                <Button
                  type="button"
                  className="h-11 rounded-xl bg-paypal-blue px-4 text-white hover:bg-[#004dc5]"
                  onClick={() => void handleManualSearch()}
                >
                  <Search className="h-4 w-4" />
                </Button>
              </div>
              <p className="mt-2 text-xs text-white/70">
                Search opens the same Express Send search logic used in `/send`.
              </p>
            </div>
          )}
          </div>
        </div>
      </div>
      <div id="openpay-file-scanner" className="pointer-events-none absolute h-0 w-0 overflow-hidden opacity-0" />

      <Dialog open={showInstructions} onOpenChange={setShowInstructions}>
        <DialogContent className="rounded-3xl sm:max-w-lg">
          <DialogTitle className="text-xl font-bold text-foreground">OpenPay Scan Instructions</DialogTitle>
          <DialogDescription className="text-sm text-muted-foreground">
            For payment safety, follow these rules before scanning.
          </DialogDescription>

          <div className="rounded-2xl border border-border p-3 text-sm text-foreground">
            <p>1. Only scan OpenPay QR codes.</p>
            <p>2. Do not scan QR codes from other wallets or unknown apps.</p>
            <p>3. Verify the merchant username before you confirm payment.</p>
            <p>4. Only pay merchants or users you directly interacted with.</p>
            <p>5. Use Scan to Pay only for trusted payment requests.</p>
          </div>
          <div className="rounded-2xl border border-border bg-secondary/40 p-3 text-xs text-foreground">
            <p className="font-semibold">Allowed paste formats:</p>
            <p className="mt-1 break-all">openpay://pay?username=&lt;recipient_username&gt;&amp;amount=10.00&amp;currency=USD</p>
            <p className="mt-1 break-all">https://your-openpay-domain/send?username=&lt;recipient_username&gt;&amp;amount=10.00&amp;currency=USD</p>
            <p className="mt-1">You can also paste `@username`, OpenPay link, or use Express Search.</p>
          </div>

          <div className="flex gap-2">
            <Button variant="outline" className="h-11 flex-1 rounded-2xl" onClick={() => setShowInstructions(false)}>
              Close
            </Button>
            <Button className="h-11 flex-1 rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5]" onClick={handleAcknowledgeInstructions}>
              I Understand
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default QrScannerPage;
