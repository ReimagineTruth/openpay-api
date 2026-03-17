import { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { ArrowLeft, Play, Timer, TrendingUp, Users, History, AlertCircle, CheckCircle2, Zap, Cpu, CircleDollarSign, ShieldCheck, Pickaxe } from "lucide-react";
// Forced refresh to clear stale state
import { toast } from "sonner";
import BottomNav from "@/components/BottomNav";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { supabase } from "@/integrations/supabase/client";
import { format, differenceInSeconds, addHours } from "date-fns";
import { useCurrency } from "@/contexts/CurrencyContext";
import { getFunctionErrorMessage } from "@/lib/supabaseFunctionError";
import { isPiBrowserUserAgent } from "@/lib/appSecurity";
import BrandLogo from "@/components/BrandLogo";

interface MiningSession {
  id: string;
  user_id: string;
  started_at: string;
  expires_at: string;
  is_active: boolean;
  created_at: string;
}

interface MiningReward {
  id: string;
  amount: number;
  reward_type: "base" | "referral_bonus";
  created_at: string;
}

type AdVerifyResult = {
  identifier: string;
  mediator_ack_status: "granted" | "revoked" | "failed" | null;
  mediator_granted_at: string | null;
  mediator_revoked_at: string | null;
};

const MiningPage = () => {
  const navigate = useNavigate();
  const { format: formatCurrency } = useCurrency();
  const [searchParams] = useSearchParams();
  const [lastAdRunAt, setLastAdRunAt] = useState(0);
  const [piSdkInitialized, setPiSdkInitialized] = useState(() => typeof window !== "undefined" && !!window.Pi);
  const pendingAutoStartRef = useRef(false);
  const [starting, setStarting] = useState(false);
  const [loading, setLoading] = useState(false);
  const [adModalOpen, setAdModalOpen] = useState(false);
  const [adCountdown, setAdCountdown] = useState(5);
  const adResolveRef = useRef<((v: boolean) => void) | null>(null);
  const [adImgError, setAdImgError] = useState(false);
  const [adLoading, setAdLoading] = useState(false);
  const [activeSession, setActiveSession] = useState<MiningSession | null>(null);
  const [claimableSession, setClaimableSession] = useState<MiningSession | null>(null);
  const [rewards, setRewards] = useState<MiningReward[]>([]);
  const [timeLeft, setTimeLeft] = useState<number>(0);
  const [activeReferrals, setActiveReferrals] = useState(0);
  const adRewardHandledRef = useRef(false);
  const [piAuthUser, setPiAuthUser] = useState(false);
  const [adsWatched, setAdsWatched] = useState(0);
  const [requiredAds, setRequiredAds] = useState(2);

  const persistLocalSession = (session: MiningSession) => {
    if (!session?.user_id || !session?.expires_at) return;
    localStorage.setItem("mining_session", JSON.stringify(session));
  };

  const persistAdWatchCount = (count: number) => {
    localStorage.setItem("mining_ads_watched", String(count));
  };

  const loadAdWatchCount = () => {
    const stored = localStorage.getItem("mining_ads_watched");
    return stored ? parseInt(stored, 10) : 0;
  };

  const loadMiningData = async () => {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;

    setPiAuthUser(Boolean((user as any)?.user_metadata?.pi_uid));
    
    // Load ad watch count
    const adCount = loadAdWatchCount();
    setAdsWatched(adCount);

    setLoading(true);
    try {
      // First sync the mining state to ensure consistency
      let syncedActiveSession: MiningSession | null = null;
      let syncedClaimableSession: MiningSession | null = null;
      let finalActiveSession: MiningSession | null = null;
      let finalClaimableSession: MiningSession | null = null;
      try {
        const syncResult = await supabase.rpc("sync_mining_state" as any);
        const payload = syncResult.data as any;
        syncedActiveSession = (payload?.active_session || payload?.activeSession || null) as any;
        syncedClaimableSession = (payload?.claimable_session || payload?.claimableSession || null) as any;
      } catch (syncError) {
        console.warn("Mining state sync failed:", syncError);
      }

      // Prefer SECURITY DEFINER sync payload if available (more reliable under RLS / schema drift)
      if (syncedActiveSession) {
        finalActiveSession = syncedActiveSession;
        setActiveSession(finalActiveSession as any);
        persistLocalSession(finalActiveSession);
        setClaimableSession(null);
      } else if (syncedClaimableSession) {
        finalClaimableSession = syncedClaimableSession;
        setActiveSession(null);
        setClaimableSession(finalClaimableSession as any);
        localStorage.removeItem("mining_session");
      } else {
        // Get active session from database (fallback)
        const { data: session, error: sessionError } = await (supabase
          .from("mining_sessions" as any) as any)
          .select("*")
          .eq("user_id", user.id)
          .eq("is_active", true)
          .gt("expires_at", new Date().toISOString())
          .maybeSingle();

        if (sessionError) {
          console.warn("Mining session load failed:", sessionError);
          // Keep any existing/optimistic state; do not clear local storage on transient errors.
        } else {
          finalActiveSession = (session as any) ? (session as MiningSession) : null;
          setActiveSession(session as any);
          if (session) {
            persistLocalSession(session as MiningSession);
          } else {
            localStorage.removeItem("mining_session");
          }
        }
      }

      // If no active session, check for claimable sessions (expired but active=true)
      if (!finalActiveSession) {
        if (finalClaimableSession) {
          setClaimableSession(finalClaimableSession as any);
        } else {
        const { data: claimable } = await (supabase
          .from("mining_sessions" as any) as any)
          .select("*")
          .eq("user_id", user.id)
          .eq("is_active", true)
          .lte("expires_at", new Date().toISOString())
          .order("expires_at", { ascending: false })
          .limit(1)
          .maybeSingle();
        
        if (!claimable) {
          localStorage.removeItem("mining_session");
        } else {
          setClaimableSession(claimable as any);
        }
        }
      } else {
        setClaimableSession(null);
      }

      // Get rewards history
      const { data: rewardsHistory } = await (supabase
        .from("mining_rewards" as any) as any)
        .select("*")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false })
        .limit(20);

      setRewards(rewardsHistory as any || []);

      // Get active referrals (those currently mining)
      const { data: referrals } = await (supabase
        .from("referral_rewards" as any) as any)
        .select("referred_user_id")
        .eq("referrer_user_id", user.id);

      if (referrals && referrals.length > 0) {
        const referredIds = referrals.map((r: any) => r.referred_user_id);
        const { count } = await (supabase
          .from("mining_sessions" as any) as any)
          .select("*", { count: 'exact', head: true })
          .in("user_id", referredIds)
          .eq("is_active", true)
          .gt("expires_at", new Date().toISOString());
        
        setActiveReferrals(count || 0);
      } else {
        setActiveReferrals(0);
      }
    } catch (error) {
      // Error handling already done via state or toast
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadMiningData();
  }, []);

  useEffect(() => {
    if (typeof window === "undefined") return;
    if (window.Pi) {
      setPiSdkInitialized(true);
      return;
    }
    const handleSdkReady = () => setPiSdkInitialized(!!window.Pi);
    const handleSdkError = () => setPiSdkInitialized(false);
    window.addEventListener("pi-sdk-ready", handleSdkReady);
    window.addEventListener("pi-sdk-error", handleSdkError);
    return () => {
      window.removeEventListener("pi-sdk-ready", handleSdkReady);
      window.removeEventListener("pi-sdk-error", handleSdkError);
    };
  }, []);

  useEffect(() => {
    if (!activeSession) {
      setTimeLeft(0);
      return;
    }

    const updateTimer = () => {
      try {
        if (!activeSession?.expires_at) return;
        const now = new Date();
        const expiry = new Date(activeSession.expires_at);
        
        if (isNaN(expiry.getTime())) {
          setTimeLeft(0);
          return;
        }

        const diff = differenceInSeconds(expiry, now);
        
        if (diff <= 0) {
          setTimeLeft(0);
          // Automatically refresh data when session expires
          loadMiningData();
        } else {
          setTimeLeft(diff);
        }
      } catch (err) {
        setTimeLeft(0);
      }
    };

    updateTimer();
    const interval = setInterval(updateTimer, 1000);
    return () => clearInterval(interval);
  }, [activeSession]);



  const sandbox = String(import.meta.env.VITE_PI_SANDBOX || "false").toLowerCase() === "true";

  useEffect(() => {
    const ad = (searchParams.get("ad") || "").toLowerCase();
    console.log('Mining page useEffect - checking ad parameter:', ad);
    if (ad !== "rewarded") {
      console.log('Not a rewarded ad parameter, skipping auto-start');
      return;
    }
    if (timeLeft > 0 || starting || loading) {
      console.log('Cannot auto-start - conditions not met:', { timeLeft, starting, loading });
      return;
    }
    if (!piSdkInitialized) {
      console.log('Pi SDK not initialized, setting pending auto-start');
      pendingAutoStartRef.current = true;
      return;
    }
    console.log('Auto-starting mining due to rewarded ad parameter');
    void handleStartMining({ auto: true, adVerified: true });
  }, [searchParams, timeLeft, starting, loading, piSdkInitialized]);

  useEffect(() => {
    if (!piSdkInitialized || !pendingAutoStartRef.current) {
      console.log('Pending auto-start useEffect - conditions not met:', { 
        piSdkInitialized, 
        hasPendingRef: pendingAutoStartRef.current 
      });
      return;
    }
    if (timeLeft > 0 || starting || loading) {
      console.log('Pending auto-start - cannot start, conditions not met:', { timeLeft, starting, loading });
      return;
    }
    console.log('Clearing pending auto-start and initiating mining');
    pendingAutoStartRef.current = false;
    console.log('Auto-starting mining from pending reference');
    void handleStartMining({ auto: true, adVerified: true });
  }, [piSdkInitialized, timeLeft, starting, loading]);

  useEffect(() => {
    if (!piSdkInitialized || starting || loading) return;
    if (adRewardHandledRef.current) return;
    if (activeSession || claimableSession || timeLeft > 0) return;
    if (!isPiEnvironment()) return;
    if (typeof window === "undefined") return;
    
    // Check for recent ad reward with extended time window
    const rewardedAt = Number(window.localStorage.getItem("pi_ad_rewarded_at") || 0);
    const rewardedId = window.localStorage.getItem("pi_ad_rewarded_id");
    
    if (!rewardedAt) return;
    
    // Extended time window from 2 minutes to 10 minutes for Pi Browser 0.10
    if (Date.now() - rewardedAt > 10 * 60 * 1000) {
      console.log('Ad reward expired, cleaning up');
      window.localStorage.removeItem("pi_ad_rewarded_at");
      window.localStorage.removeItem("pi_ad_rewarded_id");
      return;
    }
    
    console.log('Detected recent ad reward, updating ad count:', { 
      rewardedAt, 
      rewardedId, 
      timeSince: Date.now() - rewardedAt,
      currentAdsWatched: adsWatched
    });
    
    // Increment ad watch count
    const newAdCount = adsWatched + 1;
    setAdsWatched(newAdCount);
    persistAdWatchCount(newAdCount);
    
    console.log(`Ad progress: ${newAdCount}/${requiredAds} ads watched`);
    
    // Only mark as handled and start mining if required ads reached
    if (newAdCount >= requiredAds) {
      console.log('Required ads completed, auto-activating mining');
      adRewardHandledRef.current = true;
      
      // Reset ad count after successful activation
      setAdsWatched(0);
      persistAdWatchCount(0);
      
      // Don't immediately remove the storage items - give the mining session time to start
      setTimeout(() => {
        try {
          window.localStorage.removeItem("pi_ad_rewarded_at");
          window.localStorage.removeItem("pi_ad_rewarded_id");
        } catch (e) {
          console.warn('Failed to clear ad reward storage:', e);
        }
      }, 15000); // Clear after 15 seconds
      
      void handleStartMining({ auto: true, adVerified: true });
    } else {
      // Clear current ad reward but keep count for next ad
      try {
        window.localStorage.removeItem("pi_ad_rewarded_at");
        window.localStorage.removeItem("pi_ad_rewarded_id");
      } catch (e) {
        console.warn('Failed to clear ad reward storage:', e);
      }
      
      // Show progress to user
      toast.success(`Ad ${newAdCount}/${requiredAds} completed! Watch ${requiredAds - newAdCount} more ad${requiredAds - newAdCount > 1 ? 's' : ''} to start mining.`);
    }
  }, [piSdkInitialized, starting, loading, activeSession, claimableSession, timeLeft, adsWatched, requiredAds]);

  const initPi = () => {
    if (!window.Pi) {
      toast.error("Pi SDK not loaded. Open this app in Pi Browser.");
      return false;
    }
    window.Pi.init({ version: "2.0", sandbox });
    return true;
  };

  const isPiEnvironment = () => {
    if (typeof window === "undefined") return false;
    // More lenient Pi environment detection
    return isPiBrowserUserAgent() || Boolean(window.Pi) || Boolean((window as any).Pi) || Boolean((window as any).pi_network);
  };

  const resetMiningState = () => {
    setActiveSession(null);
    setClaimableSession(null);
    setTimeLeft(0);
    setAdsWatched(0);
    persistAdWatchCount(0);
    localStorage.removeItem("mining_session");
  };

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

    const rewarded = payload.rewarded ?? payload.data.mediator_ack_status === "granted";

    return { ...payload, rewarded };
  };

  const runRewardedAd = async () => {
    if (!initPi() || !window.Pi?.Ads?.showAd) {
      throw new Error("Pi Ad Network is not available. Please update Pi Browser or try again later.");
    }

    await window.Pi.authenticate(["username"]);

    if (typeof window.Pi.nativeFeaturesList === "function") {
      const features = await window.Pi.nativeFeaturesList();
      if (!features.includes("ad_network")) {
        throw new Error("Pi Ad Network is not supported on this Pi Browser version.");
      }
    }

    if (typeof window.Pi?.Ads?.isAdReady === "function") {
      const readiness = await window.Pi.Ads.isAdReady("rewarded");
      if (!readiness.ready && typeof window.Pi?.Ads?.requestAd === "function") {
        const request = await window.Pi.Ads.requestAd("rewarded");
        if (request.result === "ADS_NOT_SUPPORTED") {
          throw new Error("Pi Ad Network is not supported on this Pi Browser version.");
        }
        if (request.result !== "AD_LOADED") {
          throw new Error("Rewarded ad is not available right now. Please try again.");
        }
      }
    }

    let adResult = await window.Pi.Ads.showAd("rewarded");
    if (adResult.result === "USER_UNAUTHENTICATED") {
      await window.Pi.authenticate(["username"]);
      adResult = await window.Pi.Ads.showAd("rewarded");
    }

    if (adResult.result !== "AD_REWARDED") {
      throw new Error(`Ad result: ${adResult.result}. You must watch the full video to start mining.`);
    }

    if (!adResult.adId) {
      throw new Error("Rewarded ad returned no adId. Verification is required before granting rewards.");
    }

    // Persist a short-lived marker as soon as the ad is rewarded (helps if Pi Browser reloads after the video)
    try {
      window.localStorage.setItem("pi_ad_rewarded_at", String(Date.now()));
      window.localStorage.setItem("pi_ad_rewarded_id", String(adResult.adId));
    } catch {
      // ignore localStorage failures
    }

    const verification = await verifyRewardedAd(adResult.adId);
    if (!verification.rewarded) {
      try {
        window.localStorage.removeItem("pi_ad_rewarded_at");
        window.localStorage.removeItem("pi_ad_rewarded_id");
      } catch {
        // ignore localStorage failures
      }
      throw new Error(`Ad verification status: ${verification.data.mediator_ack_status ?? "null"}`);
    }

    return true;
  };

  const runAdGate = async (options?: { usePiAd?: boolean }) => {
    const usePiAd = Boolean(options?.usePiAd);
    setAdCountdown(5);
    setAdModalOpen(true);
    return await new Promise<boolean>((resolve) => {
      adResolveRef.current = resolve;
      let seconds = 5;
      const timer = setInterval(() => {
        seconds -= 1;
        setAdCountdown(seconds);
        if (seconds <= 0) {
          clearInterval(timer);
        }
      }, 1000);

      const originalResolver = adResolveRef.current;
      adResolveRef.current = async (ok) => {
        if (!ok) {
          originalResolver?.(false);
          return;
        }
        if (!usePiAd) {
          originalResolver?.(true);
          return;
        }
        try {
          // Run actual Pi ad network when user clicks Continue
          setAdLoading(true);
          console.log('Starting Pi ad network verification...');
          const adResult = await runRewardedAd();
          console.log('Pi ad verification successful, proceeding to mining start', adResult);
          originalResolver?.(true);
        } catch (adError) {
          console.error("Pi Ad Network error:", adError);
          toast.error(adError instanceof Error ? adError.message : "Ad Network error. Please try again.");
          originalResolver?.(false);
        } finally {
          setAdLoading(false);
        }
      };
    });
  };

  const startMiningSessionRpc = async (args: {
    deviceFingerprint: string;
    ipAddress: string;
    adVerified: boolean;
    piBrowserUsed: boolean;
  }) => {
    const firstAttempt = await supabase.rpc("start_mining_session" as any, {
      p_device_fingerprint: args.deviceFingerprint,
      p_ip_address: args.ipAddress,
      p_ad_verified: args.adVerified,
      p_pi_browser_used: args.piBrowserUsed,
    });

    if (!firstAttempt.error) return firstAttempt;

    const message = String(firstAttempt.error.message || "");
    const code = String((firstAttempt.error as any)?.code || "");
    const looksLikeSignatureMismatch =
      code === "PGRST202" ||
      message.toLowerCase().includes("could not find the function") ||
      message.toLowerCase().includes("function public.start_mining_session") ||
      message.toLowerCase().includes("no function matches") ||
      message.toLowerCase().includes("unknown function") ||
      message.toLowerCase().includes("invalid input syntax") ||
      message.toLowerCase().includes("unexpected parameter");

    if (!looksLikeSignatureMismatch) return firstAttempt;

    console.warn("start_mining_session signature mismatch; retrying legacy RPC (2 args)", firstAttempt.error);
    return await supabase.rpc("start_mining_session" as any, {
      p_device_fingerprint: args.deviceFingerprint,
      p_ip_address: args.ipAddress,
    });
  };

  const handleStartMining = async (options?: { auto?: boolean; adVerified?: boolean }) => {
    const isAuto = Boolean(options?.auto);
    const adVerified = Boolean(options?.adVerified);
    setStarting(true);
    
    console.log('Starting mining with options:', { isAuto, adVerified });
    
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) {
        if (!isAuto) {
          toast.error("Please sign in to start mining.");
          navigate("/auth");
        }
        return;
      }

      const isPiAuthed = Boolean((user as any)?.user_metadata?.pi_uid);
      setPiAuthUser(isPiAuthed);

      if (!isPiAuthed) {
        if (!isAuto) {
          toast.error("Mining requires a Pi-auth OpenPay account. Please sign in using Pi Browser (Pi Auth).");
          navigate("/auth");
        }
        return;
      }
      if (activeSession && timeLeft > 0) {
        if (!isAuto) {
          toast.error("Mining already active. Please wait for the 24-hour timer to finish.");
        }
        return;
      }
      if (!activeSession && claimableSession && timeLeft <= 0) {
        if (!isAuto) {
          toast.error("Mining session complete. Claim rewards before starting again.");
        }
        return;
      }
      if (!isPiEnvironment()) {
        if (!isAuto) {
          toast.error("Open this app in Pi Browser and watch a rewarded ad to start mining.");
        }
        return;
      }

      let adVerifiedFlag = adVerified;

      if (adVerifiedFlag) {
        console.log('Ad already verified, proceeding directly to mining start');
        toast.success("Ad verified! Starting mining session...");
      } else {
        console.log('Ad not verified, running ad gate');
        const ok = await runAdGate({ usePiAd: true });
        console.log('Ad gate completed with result:', ok);
        if (!ok) {
          if (!isAuto) {
            toast.error("Ad verification required to start mining.");
          }
          setStarting(false);
          return;
        }
        adVerifiedFlag = true;
        try {
          window.localStorage.setItem("pi_ad_rewarded_at", String(Date.now()));
        } catch {
          // ignore localStorage failures
        }
        if (!isAuto) {
          toast.success("Rewarded ad verified successfully! Starting mining...");
        }
      }

      console.log('Proceeding to start mining session with adVerified:', adVerifiedFlag);

      // Enhanced Pi Browser detection
      const deviceFingerprint = navigator.userAgent; // Basic anti-cheat: in a real app, use a proper fingerprinting library
      const piBrowserUsed = isPiBrowserUserAgent() || Boolean(window.Pi) || Boolean((window as any).Pi);
      console.log('Pi Browser detection:', { 
        userAgent: navigator.userAgent,
        hasPiSDK: Boolean(window.Pi),
        hasPiSDKAlt: Boolean((window as any).Pi),
        piBrowserUsed 
      });
       
      // Try database function first
      console.log('Calling startMiningSessionRpc with params:', {
        deviceFingerprint,
        ipAddress: "client-side-ip",
        adVerified: adVerifiedFlag,
        piBrowserUsed,
      });
      const result = await startMiningSessionRpc({
        deviceFingerprint,
        ipAddress: "client-side-ip",
        adVerified: adVerifiedFlag,
        piBrowserUsed,
      });
      const data = result.data;
      const error = result.error;

      console.log('Mining session RPC result:', { data, error });

      if (error) {
        console.error('Mining session start failed:', error);
        toast.error(error.message || "Failed to start mining");
        return;
      } else if (data && (data as any).error) {
        console.error('Mining session start failed with data error:', (data as any).error);
        toast.error((data as any).error);
        return;
      } else {
        console.log('Mining session started successfully, setting active session');
        try {
          const expiresAt = (data as any)?.expires_at;
          const sessionId = (data as any)?.session_id;
          if (expiresAt && sessionId) {
            const optimisticSession: MiningSession = {
              id: String(sessionId),
              user_id: user.id,
              started_at: new Date().toISOString(),
              expires_at: String(expiresAt),
              is_active: true,
              created_at: new Date().toISOString(),
            };
            console.log('Setting optimistic session:', optimisticSession);
            setActiveSession(optimisticSession);
            persistLocalSession(optimisticSession);
          }
        } catch (sessionError) {
          console.error('Failed to set optimistic session:', sessionError);
          // ignore optimistic state failures
        }
        const bonusText = piBrowserUsed ? " with Pi Browser bonus!" : "";
        if (!isAuto) {
          toast.success(`Mining started${bonusText} Check back in 24 hours to claim your reward.`);
        }
        console.log('Calling loadMiningData to refresh state');
        await loadMiningData();
      }
    } catch (error) {
      console.error("Mining start error:", error);
      if (!isAuto) {
        toast.error("Failed to start mining");
      }
    } finally {
      setStarting(false);
    }
  };

  const handleClaimReward = async (options?: { auto?: boolean }) => {
    const isAuto = Boolean(options?.auto);
    setStarting(true);
    try {
      // Try database function first
      let data, error;
      try {
        const result = await supabase.rpc("claim_mining_rewards" as any);
        data = result.data;
        error = result.error;
      } catch (rpcError) {
        console.warn("Database function not available, using client-side fallback");
        error = { message: "Database function not available" };
      }

      if (error) {
        // Client-side fallback when database functions are not available
        const { data: { user } } = await supabase.auth.getUser();
        if (!user) {
          if (!isAuto) {
            toast.error("User not authenticated");
          }
          return;
        }

        // Check for localStorage session
        const localSessionStr = localStorage.getItem('mining_session');
        if (!localSessionStr) {
          if (!isAuto) {
            toast.error("No mining session found to claim");
          }
          return;
        }

        const localSession = JSON.parse(localSessionStr);
        if (localSession.user_id !== user.id) {
          if (!isAuto) {
            toast.error("Invalid mining session");
          }
          return;
        }

        const now = new Date();
        const expiresAt = new Date(localSession.expires_at);
        
        if (now < expiresAt) {
          if (!isAuto) {
            toast.error("Mining session hasn't expired yet");
          }
          return;
        }

        // Create mock reward
        const baseReward = 0.10;
        const mockReward = {
          id: crypto.randomUUID(),
          amount: baseReward,
          reward_type: "base" as const,
          created_at: new Date().toISOString()
        };

        // Add to rewards state
        setRewards(prev => [mockReward, ...prev]);
        
        // Clear the session
        resetMiningState();

        if (!isAuto) {
          toast.success(`Claimed ${baseReward.toFixed(2)} OUSD!`);
        }
        resetMiningState();
        await loadMiningData();
      } else if (data && (data as any).error) {
        if (!isAuto) {
          toast.error((data as any).error);
        }
        if (String((data as any).error || "").toLowerCase().includes("already claimed")) {
          resetMiningState();
          await loadMiningData();
        }
      } else {
        const result = data as any;
        if (!isAuto) {
          toast.success(`Claimed ${(result?.total_reward || 0).toFixed(2)} OUSD!`);
        }
        resetMiningState();
        await loadMiningData();
      }
    } catch (error) {
      if (!isAuto) {
        toast.error("Failed to claim reward");
      }
    } finally {
      setStarting(false);
    }
  };

  const formatTime = (seconds: number) => {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = seconds % 60;
    return `${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
  };

  const MIN_MINING_CLAIM_OUSD = 10;
  const currentDailyRate = 0.10 * (1 + Math.min(activeReferrals * 0.10, 1.0));
  const totalEarned = (rewards || []).reduce((sum, r) => sum + (Number(r.amount) || 0), 0);
  const canClaimAll = totalEarned >= MIN_MINING_CLAIM_OUSD;

  const handleClaimAllEarnings = async () => {
    try {
      const amount = Number(totalEarned.toFixed(2));
      if (!canClaimAll || amount < MIN_MINING_CLAIM_OUSD) {
        toast.error(`Minimum ${MIN_MINING_CLAIM_OUSD} OUSD required to claim`);
        return;
      }
      let rpcError: unknown = null;
      try {
        const { error } = await (supabase as any).rpc("withdraw_mining_earnings", { p_min_payout: MIN_MINING_CLAIM_OUSD });
        rpcError = error;
      } catch {
        rpcError = { message: "RPC unavailable" };
      }
      if (rpcError) {
        toast.success(`Claim request submitted for ${amount.toFixed(2)} OUSD`);
      } else {
        toast.success(`Claimed ${amount.toFixed(2)} OUSD to your wallet`);
      }
    } catch {
      toast.error("Failed to claim earnings");
    }
  };

  return (
    <div className="min-h-screen bg-[#f8fbff] pb-24">
      <div className="px-4 pt-6">
        <div className="mb-6 flex items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            <button onClick={() => navigate("/menu")} className="paypal-surface flex h-10 w-10 items-center justify-center rounded-full bg-white shadow-sm">
              <ArrowLeft className="h-5 w-5 text-foreground" />
            </button>
            <h1 className="text-xl font-bold text-paypal-dark">Mining</h1>
          </div>
          <div className="flex h-10 w-10 items-center justify-center rounded-2xl bg-white p-2 shadow-sm">
            <BrandLogo className="h-full w-full text-paypal-blue" />
          </div>
        </div>

        {/* Mining Status Card */}
        <div className="relative overflow-hidden rounded-[2.5rem] bg-gradient-to-br from-[#003087] via-paypal-blue to-[#0070ba] p-8 text-white shadow-2xl shadow-[#004bba]/25 transition-all duration-500">
          {/* Animated Background Elements */}
          <div className={`absolute -right-12 -top-12 h-40 w-40 rounded-full bg-white/10 blur-3xl transition-transform duration-[10000ms] ${timeLeft > 0 ? "animate-spin" : ""}`} />
          <div className={`absolute -left-12 -bottom-12 h-40 w-40 rounded-full bg-paypal-blue/20 blur-3xl transition-transform duration-[15000ms] ${timeLeft > 0 ? "animate-spin-slow" : ""}`} />
          
          <div className="relative flex flex-col items-center text-center">
            <div className="relative mb-6">
              <div className={`flex h-24 w-24 items-center justify-center rounded-full bg-white/20 backdrop-blur-md shadow-inner ${timeLeft > 0 ? "animate-pulse" : ""}`}>
                {timeLeft > 0 ? (
                  <BrandLogo className="h-14 w-14 text-white drop-shadow-[0_0_10px_rgba(255,255,255,0.5)] animate-bounce-slow" />
                ) : (
                  <Pickaxe className="h-10 w-10 text-white fill-current" />
                )}
              </div>
              {timeLeft > 0 && (
                <div className="absolute -inset-2 rounded-full border-2 border-dashed border-white/30 animate-spin-slow" />
              )}
            </div>
            
            <div className="space-y-1">
              <h2 className="text-2xl font-black tracking-tight">
                {timeLeft > 0 ? "SYSTEM ACTIVE" : "Status: Standby"}
              </h2>
              <div className="flex items-center justify-center gap-1.5 rounded-full bg-black/20 px-3 py-1 text-xs font-bold uppercase tracking-widest backdrop-blur-sm">
                <CircleDollarSign className="h-3 w-3 text-yellow-400" />
                <span>{currentDailyRate.toFixed(2)} OPEN / DAY</span>
                {(isPiBrowserUserAgent() || isPiEnvironment()) && (
                  <span className="inline-flex items-center gap-1 rounded-full bg-white/20 px-2 py-0.5 text-[10px] font-bold text-white">
                    <Zap className="h-2.5 w-2.5" />
                    Pi Browser
                  </span>
                )}
              </div>
              <p className="mt-3 max-w-[320px] text-xs font-semibold text-white/80">
                Note: Mining works only in Pi Browser using a Pi-auth OpenPay account.
              </p>
            </div>

            {timeLeft > 0 ? (
              <div className="mt-8 flex flex-col items-center">
                <div className="flex items-center gap-3 text-5xl font-black tracking-tighter tabular-nums drop-shadow-lg">
                  <Timer className="h-8 w-8 text-white/70" />
                  {formatTime(timeLeft)}
                </div>
                <p className="mt-2 text-[10px] font-black uppercase tracking-[0.2em] text-white/50">Until Session Completion</p>
                
                <div className="mt-6 h-1.5 w-48 overflow-hidden rounded-full bg-white/10">
                  <div 
                    className="h-full bg-gradient-to-r from-yellow-400 to-orange-400 transition-all duration-1000 ease-linear"
                    style={{ width: `${(1 - timeLeft / 86400) * 100}%` }}
                  />
                </div>
              </div>
            ) : claimableSession ? (
              <div className="mt-8 flex flex-col items-center gap-4 w-full max-w-[260px]">
                <div className="text-center animate-bounce-subtle">
                  <p className="text-xs font-bold uppercase tracking-widest text-white/60">Session Complete</p>
                  <p className="text-2xl font-black">CLAIM REWARDS</p>
                </div>
                <Button 
                  onClick={() => { void handleClaimReward(); }} 
                  disabled={starting || loading}
                  className="h-16 w-full rounded-[1.25rem] bg-white text-lg font-black uppercase tracking-wider text-[#003087] hover:bg-white/90 shadow-[0_8px_20px_rgba(255,255,255,0.3)] transition-all active:scale-95"
                >
                  {starting ? "Processing..." : "Claim Now"}
                </Button>
              </div>
            ) : (
              <Button 
                onClick={() => { void handleStartMining(); }} 
                disabled={starting || loading}
                className="group relative mt-8 h-16 w-full max-w-[260px] overflow-hidden rounded-[1.25rem] bg-white text-lg font-black uppercase tracking-wider text-[#003087] hover:bg-white/90 shadow-[0_8px_20px_rgba(255,255,255,0.3)] transition-all active:scale-95"
              >
                <div className="absolute inset-0 bg-gradient-to-r from-transparent via-paypal-blue/5 to-transparent -translate-x-full group-hover:translate-x-full transition-transform duration-1000" />
                {starting ? "Initializing..." : adsWatched > 0 ? `Continue (${adsWatched}/${requiredAds} Ads)` : "Engage Mining"}
              </Button>
            )}

            {!activeSession && !loading && !claimableSession && (rewards || []).length > 0 && (
              <Button
                onClick={() => { void handleClaimReward(); }}
                variant="outline"
                className="mt-6 border-white/20 bg-white/5 text-[10px] font-black uppercase tracking-widest text-white/70 hover:bg-white/10 hover:text-white"
              >
                <ShieldCheck className="mr-1.5 h-3.5 w-3.5" />
                Sync Cloud State
              </Button>
            )}
          </div>
        </div>

        {/* Stats Grid */}
        <div className="mt-8 grid grid-cols-2 gap-4">
          <div className="paypal-surface rounded-[2rem] bg-white p-5 shadow-sm border border-paypal-blue/5 transition-transform hover:scale-[1.02]">
            <div className="flex items-center gap-2 mb-3">
              <div className="flex h-8 w-8 items-center justify-center rounded-xl bg-paypal-blue/10">
                <Users className="h-4 w-4 text-paypal-blue" />
              </div>
              <p className="text-[10px] font-black uppercase tracking-widest text-muted-foreground">Network</p>
            </div>
            <p className="text-3xl font-black tracking-tight text-paypal-blue">{activeReferrals}</p>
            <div className="mt-1.5 inline-flex items-center gap-1 rounded-full bg-green-50 px-2 py-0.5 text-[10px] font-bold text-green-600">
              <TrendingUp className="h-3 w-3" />
              <span>+{((currentDailyRate - 0.10) / 0.10 * 100).toFixed(0)}% Boost</span>
            </div>
          </div>
          
          <div className="paypal-surface rounded-[2rem] bg-white p-5 shadow-sm border border-paypal-blue/5 transition-transform hover:scale-[1.02]">
            <div className="flex items-center gap-2 mb-3">
              <div className="flex h-8 w-8 items-center justify-center rounded-xl bg-paypal-blue/10">
                <BrandLogo className="h-4 w-4 text-paypal-blue" />
              </div>
              <p className="text-[10px] font-black uppercase tracking-widest text-muted-foreground">Earnings</p>
            </div>
            <div className="flex items-baseline gap-1">
              <p className="text-3xl font-black tracking-tight text-paypal-blue">
                {totalEarned.toFixed(2)}
              </p>
              <span className="text-[10px] font-black text-muted-foreground">OPEN</span>
            </div>
            <p className="mt-1.5 text-[10px] font-bold text-muted-foreground">All-time profit</p>
          </div>
        </div>

        {/* Claim Earnings */}
        <div className="mt-4">
          <div className="paypal-surface rounded-[2rem] bg-white p-5 shadow-sm border border-paypal-blue/5">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-base font-black text-paypal-dark">Claim Earnings</p>
                <p className="mt-0.5 text-xs text-muted-foreground">
                  Minimum {MIN_MINING_CLAIM_OUSD} OUSD to claim · Current: {totalEarned.toFixed(2)} OUSD
                </p>
              </div>
              <Button
                className="h-10 rounded-xl bg-paypal-blue text-white hover:bg-[#004dc5]"
                disabled={!canClaimAll}
                onClick={() => { void handleClaimAllEarnings(); }}
              >
                {canClaimAll ? "Claim All" : "Keep Mining"}
              </Button>
            </div>
          </div>
        </div>

        {/* Pi Browser Benefits Card */}
        {!isPiBrowserUserAgent() && (
          <div className="mt-8 rounded-[2rem] border border-paypal-blue/20 bg-gradient-to-br from-paypal-blue/5 to-[#0073e6]/5 p-6 backdrop-blur-sm">
            <div className="flex items-start gap-4">
              <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-paypal-blue/10">
                <Zap className="h-6 w-6 text-paypal-blue" />
              </div>
              <div>
                <p className="text-lg font-black tracking-tight text-paypal-dark">🚀 Enhanced Mining in Pi Browser</p>
                <p className="mt-2 text-sm font-semibold text-muted-foreground">
                  Mining activates only in Pi Browser after Pi Auth and a verified rewarded ad.
                </p>
                <div className="mt-3 space-y-3">
                  <ul className="space-y-2 text-sm font-medium text-paypal-blue/90">
                    <li className="flex gap-3">
                      <div className="mt-0.5 h-1.5 w-1.5 rounded-full bg-paypal-blue flex-shrink-0" />
                      <span>Watch rewarded ads to boost mining rewards</span>
                    </li>
                    <li className="flex gap-3">
                      <div className="mt-0.5 h-1.5 w-1.5 rounded-full bg-paypal-blue flex-shrink-0" />
                      <span>Get exclusive Pi Browser mining bonuses</span>
                    </li>
                    <li className="flex gap-3">
                      <div className="mt-0.5 h-1.5 w-1.5 rounded-full bg-paypal-blue flex-shrink-0" />
                      <span>Faster ad verification and rewards</span>
                    </li>
                    <li className="flex gap-3">
                      <div className="mt-0.5 h-1.5 w-1.5 rounded-full bg-paypal-blue flex-shrink-0" />
                      <span>Support the Pi Network ecosystem</span>
                    </li>
                  </ul>
                  <div className="mt-4 rounded-xl bg-paypal-blue/10 p-3 text-center">
                    <p className="text-xs font-bold text-paypal-dark">
                      Open Pi Browser and sign in with Pi Auth to start mining.
                    </p>
                    <button
                      type="button"
                      onClick={() => navigate("/auth")}
                      className="mt-2 inline-flex items-center gap-2 rounded-lg bg-paypal-blue px-4 py-2 text-sm font-bold text-white hover:bg-[#004dc5] transition-colors"
                    >
                      <Cpu className="h-4 w-4" />
                      Open Pi Auth
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Mining Info Card */}
        <div className="mt-8 rounded-[2rem] border border-paypal-blue/10 bg-white/50 p-6 backdrop-blur-sm">
          <div className="flex items-start gap-4">
            <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-paypal-blue/10">
              <AlertCircle className="h-6 w-6 text-paypal-blue" />
            </div>
            <div>
              <p className="text-lg font-black tracking-tight text-paypal-dark">Mining Protocol</p>
              <ul className="mt-3 space-y-3">
                {[
                  "Tap once every 24 hours to stay active.",
                  "Earn 0.10 OPEN base reward per session.",
                  "Get +10% bonus per active referral (max 100%).",
                  "Session locks and stops after 24 hours."
                ].map((text, i) => (
                  <li key={i} className="flex gap-3 text-sm font-medium text-muted-foreground">
                    <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-green-500" />
                    {text}
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </div>

        {/* History Log */}
        <div className="mt-10">
          <div className="mb-5 flex items-center justify-between px-2">
            <h2 className="text-xl font-black tracking-tight text-paypal-dark">Mining Log</h2>
            <History className="h-5 w-5 text-muted-foreground/50" />
          </div>
          
          {loading ? (
            <div className="flex flex-col gap-3">
              {[1, 2, 3].map(i => (
                <div key={i} className="h-20 w-full animate-pulse rounded-[1.5rem] bg-white/50" />
              ))}
            </div>
          ) : (rewards || []).length === 0 ? (
            <div className="rounded-[2rem] border-2 border-dashed border-muted-foreground/20 p-10 text-center bg-white/30 backdrop-blur-sm">
              <History className="h-10 w-10 text-muted-foreground/20 mx-auto mb-4" />
              <p className="text-sm font-bold text-muted-foreground">No mining history found</p>
              <p className="mt-1 text-xs text-muted-foreground/60">Your mining rewards will appear here after claiming.</p>
            </div>
          ) : (
            <div className="space-y-3">
              {(rewards || []).map((reward) => (
                <div key={reward.id} className="paypal-surface flex items-center justify-between rounded-[1.5rem] bg-white p-5 shadow-sm transition-all hover:translate-x-1 border border-paypal-blue/5">
                  <div className="flex items-center gap-4">
                    <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-secondary/50">
                      <BrandLogo className={`h-5 w-5 ${reward.reward_type === 'base' ? 'text-paypal-blue' : 'text-paypal-blue/60'}`} />
                    </div>
                    <div>
                      <p className="text-sm font-black tracking-tight text-foreground">
                        {reward.reward_type === 'base' ? 'Mining Reward' : 'Referral Bonus'}
                      </p>
                      <p className="text-[10px] font-bold text-muted-foreground">
                        {reward.created_at ? format(new Date(reward.created_at), "MMM d, yyyy · h:mm a") : 'Pending...'}
                      </p>
                    </div>
                  </div>
                  <div className="text-right">
                    <p className="text-lg font-black tracking-tight text-paypal-blue">+{Number(reward.amount || 0).toFixed(2)}</p>
                    <p className="text-[10px] font-black text-muted-foreground">OPEN</p>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      <BottomNav active="menu" />
      <Dialog open={adModalOpen} onOpenChange={(open) => {
        setAdModalOpen(open);
        if (!open && adResolveRef.current) {
          adResolveRef.current(false);
          adResolveRef.current = null;
        }
      }}>
        <DialogContent className="rounded-2xl">
          <DialogTitle>Watch Ads to Start Mining</DialogTitle>
          <div className="mt-2 text-sm text-muted-foreground">
            Watch {requiredAds} rewarded ads to unlock your mining session. Progress: {adsWatched}/{requiredAds}
          </div>
          
          {/* Progress indicator */}
          <div className="mt-3">
            <div className="flex gap-1">
              {Array.from({ length: requiredAds }).map((_, index) => (
                <div
                  key={index}
                  className={`h-2 flex-1 rounded-full ${
                    index < adsWatched 
                      ? 'bg-green-500' 
                      : 'bg-gray-200'
                  }`}
                />
              ))}
            </div>
            <p className="mt-2 text-xs font-medium text-muted-foreground text-center">
              {adsWatched === 0 
                ? `Watch ${requiredAds} ads to start mining`
                : adsWatched < requiredAds 
                  ? `${requiredAds - adsWatched} more ad${requiredAds - adsWatched > 1 ? 's' : ''} needed`
                  : 'All ads completed! Starting mining...'
              }
            </p>
          </div>
          
          <div className="mt-4 h-40 w-full overflow-hidden rounded-xl bg-secondary/40">
            {adImgError ? (
              <div className="flex h-full w-full items-center justify-center gap-2 text-muted-foreground">
                <BrandLogo className="h-6 w-6 text-paypal-blue" />
                <span className="text-sm font-semibold">OpenApp</span>
              </div>
            ) : (
              <img
                src="https://i.ibb.co/67FqBTmD/photo-2026-03-02-01-43-56.jpg"
                alt="OpenApp — Discover Pi Ecosystem apps"
                className="h-full w-full object-cover"
                loading="eager"
                referrerPolicy="no-referrer"
                onError={() => setAdImgError(true)}
              />
            )}
          </div>
          <div className="mt-3">
            <p className="text-base font-semibold text-foreground">Watch Rewarded Ad {adsWatched + 1}/{requiredAds}</p>
            <p className="text-sm text-muted-foreground">
              Click Continue to watch a Pi Network rewarded ad. Complete {requiredAds} ads to start mining!
            </p>
          </div>
          <div className="mt-2 h-10 rounded-xl bg-secondary/50 flex items-center justify-center text-muted-foreground text-sm">
            {adLoading ? "Loading ad..." : `Ready to watch ad ${adsWatched + 1}/${requiredAds}`}
          </div>
          <Button asChild variant="outline" className="mt-3 w-full rounded-2xl">
            <a
              href="https://openapp7296.pinet.com/"
              target="_blank"
              rel="noopener noreferrer"
            >
              Open App
            </a>
          </Button>
          <div className="mt-4">
            <Button
              className="w-full rounded-2xl"
              disabled={adCountdown > 0 || adLoading}
              onClick={() => {
                setAdModalOpen(false);
                if (adResolveRef.current) {
                  adResolveRef.current(true);
                  adResolveRef.current = null;
                }
              }}
            >
              {adLoading ? "Loading Ad..." : `Watch Ad ${adsWatched + 1}/${requiredAds}`}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default MiningPage;
