import { useEffect, useRef, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { ArrowLeft } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";
import { getFunctionErrorMessage } from "@/lib/supabaseFunctionError";

type AdVerifyResult = {
  identifier: string;
  mediator_ack_status: "granted" | "revoked" | "failed" | null;
  mediator_granted_at: string | null;
  mediator_revoked_at: string | null;
};

const PiAdsPage = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [loading, setLoading] = useState(false);
  const [lastResult, setLastResult] = useState<string>("");
  const [sdkReady, setSdkReady] = useState(() => typeof window !== "undefined" && !!window.Pi);
  const pendingAutoRef = useRef(false);

  const sandbox = String(import.meta.env.VITE_PI_SANDBOX || "false").toLowerCase() === "true";

  const initPi = () => {
    if (!window.Pi) {
      toast.error("Pi SDK not loaded. Open this app in Pi Browser.");
      return false;
    }
    window.Pi.init({ version: "2.0", sandbox });
    return true;
  };

  useEffect(() => {
    if (typeof window === "undefined") return;
    if (window.Pi) {
      setSdkReady(true);
      return;
    }
    const handleSdkReady = () => setSdkReady(!!window.Pi);
    const handleSdkError = () => setSdkReady(false);
    window.addEventListener("pi-sdk-ready", handleSdkReady);
    window.addEventListener("pi-sdk-error", handleSdkError);
    return () => {
      window.removeEventListener("pi-sdk-ready", handleSdkReady);
      window.removeEventListener("pi-sdk-error", handleSdkError);
    };
  }, []);

  const verifyRewardedAd = async (adId: string) => {
    const { data, error } = await supabase.functions.invoke("pi-platform", {
      body: { action: "ad_verify", adId },
    });
    if (error) throw new Error(await getFunctionErrorMessage(error, "Pi ad verification failed"));

    const payload = data as
      | { success?: boolean; data?: AdVerifyResult; rewarded?: boolean; error?: string }
      | null;
    if (!payload?.success || !payload.data) {
      throw new Error(payload?.error || "Pi ad verification failed");
    }

    return payload;
  };

  const handleWatchRewardedAd = async () => {
    if (!initPi() || !window.Pi?.Ads?.showAd) return;
    setLoading(true);
    setLastResult("");

    try {
      await window.Pi.authenticate(["username"]);

      if (typeof window.Pi?.nativeFeaturesList === "function") {
        const features = await window.Pi.nativeFeaturesList();
        if (!Array.isArray(features) || !features.includes("ad_network")) {
          throw new Error("Ads not supported. Update Pi Browser to latest and try again.");
        }
      }

      if (typeof window.Pi?.Ads?.requestAd === "function") {
        try {
          await window.Pi.Ads.requestAd("rewarded");
        } catch {
          // ignore prefetch errors; we'll attempt showAd anyway
        }
      }

      const adResult = await window.Pi.Ads.showAd("rewarded");
      setLastResult(adResult.result);

      if (adResult.result !== "AD_REWARDED") {
        throw new Error(`Ad result: ${adResult.result}`);
      }

      if (!adResult.adId) {
        throw new Error("Rewarded ad returned no adId. Verification is required before granting rewards.");
      }

      const verification = await verifyRewardedAd(adResult.adId);
      if (!verification.rewarded) {
        throw new Error(`Ad verification status: ${verification.data.mediator_ack_status ?? "null"}`);
      }

      toast.success("Rewarded ad verified successfully");
      const returnTo = searchParams.get("returnTo");
      if (returnTo) {
        navigate(decodeURIComponent(returnTo), { replace: true });
      }
    } catch (error) {
      const message =
        error instanceof Error
          ? error.message
          : typeof (error as { message?: unknown })?.message === "string"
            ? String((error as { message: string }).message)
            : "Rewarded ad flow failed";
      toast.error(message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    const auto = searchParams.get("auto") === "1";
    const from = searchParams.get("from");
    if (!auto && from !== "mining") return;
    if (!sdkReady) {
      pendingAutoRef.current = true;
      return;
    }
    void handleWatchRewardedAd();
  }, [searchParams, sdkReady]);

  useEffect(() => {
    if (!sdkReady || !pendingAutoRef.current) return;
    pendingAutoRef.current = false;
    void handleWatchRewardedAd();
  }, [sdkReady]);

  return (
    <div className="min-h-screen bg-background px-4 pt-4">
      <div className="flex items-center gap-3">
        <button onClick={() => navigate("/menu")} aria-label="Back to menu">
          <ArrowLeft className="h-6 w-6 text-foreground" />
        </button>
        <h1 className="text-lg font-semibold text-paypal-dark">Pi Ad Network</h1>
      </div>

      <div className="paypal-surface mt-8 rounded-3xl p-6">
        <h2 className="text-xl font-semibold text-foreground">Watch Rewarded Ad</h2>
        <p className="mt-2 text-sm text-muted-foreground">
          Watch a rewarded ad. When it finishes and verifies, you'll be returned to Mining automatically.
        </p>

        <Button
          onClick={handleWatchRewardedAd}
          disabled={loading}
          className="mt-6 h-12 w-full rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5]"
        >
          {loading ? "Running rewarded ad flow..." : "Watch rewarded ad"}
        </Button>

        {lastResult && (
          <p className="mt-4 text-sm text-foreground">
            Last SDK result: <span className="font-semibold">{lastResult}</span>
          </p>
        )}
      </div>
    </div>
  );
};

export default PiAdsPage;
