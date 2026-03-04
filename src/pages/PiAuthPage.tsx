import { useEffect, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import BrandLogo from "@/components/BrandLogo";
import { supabase } from "@/integrations/supabase/client";
import { setAppCookie } from "@/lib/userPreferences";
import AuthFooter from "@/components/AuthFooter";
import { Loader2 } from "lucide-react";

const PiAuthPage = () => {
  const [piUser, setPiUser] = useState<{ uid: string; username: string } | null>(null);
  const [busyAuth, setBusyAuth] = useState(false);
  const [authorizationCode, setAuthorizationCode] = useState("");
  const [sdkReady, setSdkReady] = useState(() => typeof window !== "undefined" && !!window.Pi);
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();

  const envSandbox = String(import.meta.env.VITE_PI_SANDBOX || "").trim().toLowerCase();
  const sandbox =
    envSandbox.length > 0
      ? envSandbox === "true"
      : typeof window !== "undefined"
        ? window.location.hostname === "localhost" ||
          window.location.hostname === "127.0.0.1" ||
          window.location.hostname.endsWith(".local") ||
          window.location.hostname.endsWith(".test")
        : false;

  const initPi = () => {
    if (!window.Pi) {
      toast.error("Pi SDK not loaded");
      return false;
    }
    window.Pi.init({ version: "2.0", sandbox });
    return true;
  };

  useEffect(() => {
    const checkSession = async () => {
      const { data } = await supabase.auth.getSession();
      if (data.session) {
        navigate("/dashboard", { replace: true });
      }
    };
    checkSession();
  }, [navigate]);

  useEffect(() => {
    if (typeof window === "undefined") return;
    if (window.Pi) {
      setSdkReady(true);
      return;
    }
    const handleSdkReady = () => setSdkReady(!!window.Pi);
    window.addEventListener("pi-sdk-ready", handleSdkReady);
    return () => window.removeEventListener("pi-sdk-ready", handleSdkReady);
  }, []);

  useEffect(() => {
    const ref = (searchParams.get("ref") || "").trim().toLowerCase();
    if (ref) {
      setAppCookie("openpay_last_ref", ref);
    }
    const incomingCode = (
      searchParams.get("auth_code") ||
      searchParams.get("openpay_code") ||
      searchParams.get("code") ||
      ""
    )
      .trim()
      .toUpperCase();
    if (incomingCode) setAuthorizationCode(incomingCode);
  }, [searchParams]);

  const signInPiBackedAccount = async (piUid: string, piUsername: string, referralCode?: string) => {
    const piEmail = `pi_${piUid}@openpay.local`;
    const piPassword = `OpenPay-Pi-${piUid}-v1!`;
    // Prefer Pi username when creating OpenPay account; fallback to uid-derived handle if missing
    const cleanPiUsername = (piUsername || "")
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9_]/g, "_")
      .replace(/_+/g, "_")
      .replace(/^_+|_+$/g, "");
    const piSignupUsername =
      cleanPiUsername && cleanPiUsername.length >= 3
        ? cleanPiUsername
        : `pi_${piUid.replace(/-/g, "").slice(0, 16)}`;
    let created = false;

    const doSignIn = async () => {
      const { data, error } = await supabase.auth.signInWithPassword({
        email: piEmail,
        password: piPassword,
      });
      return { session: data.session, error };
    };

    const firstSignIn = await doSignIn();
    if (!firstSignIn.error && firstSignIn.session) return;

    const firstSignInMessage = firstSignIn.error?.message?.toLowerCase() || "";
    const accountMissing =
      firstSignInMessage.includes("invalid login credentials") ||
      firstSignInMessage.includes("email not confirmed") ||
      firstSignInMessage.includes("user not found");

    if (accountMissing) {
      const { error: signUpError } = await supabase.auth.signUp({
        email: piEmail,
        password: piPassword,
        options: {
          data: {
            full_name: piUsername,
            username: piSignupUsername,
            referral_code: referralCode,
            pi_uid: piUid,
            pi_username: piUsername,
            pi_connected_at: new Date().toISOString(),
          },
        },
      });

      if (signUpError && !signUpError.message.toLowerCase().includes("already registered")) {
        throw new Error(signUpError.message || "Failed to create Pi account");
      }
      if (!signUpError) created = true;

      const secondSignIn = await doSignIn();
      if (secondSignIn.error || !secondSignIn.session) {
        throw new Error(secondSignIn.error?.message || "Failed to sign in Pi account");
      }
      // Ensure profile/account records exist and reflect latest metadata
      try {
        await supabase.rpc("upsert_my_user_account" as any);
      } catch {
        // ignore best-effort
      }
      return { created };
    }

    throw new Error(firstSignIn.error?.message || "Failed to sign in Pi account");
  };

  const verifyPiAccessToken = async (accessToken: string) => {
    const { data, error } = await supabase.functions.invoke("pi-platform", {
      body: { action: "auth_verify", accessToken },
    });
    if (error) throw new Error(error.message || "Pi auth verification failed");
    const payload = data as { success?: boolean; data?: { uid?: string; username?: string }; error?: string } | null;
    if (!payload?.success || !payload.data?.uid) {
      throw new Error(payload?.error || "Pi auth verification failed");
    }
    return {
      uid: String(payload.data.uid),
      username: String(payload.data.username || ""),
    };
  };

  const verifyAuthorizationCode = async (code: string) => {
    if (!code) return true;
    const { data, error } = await supabase.rpc("verify_my_openpay_authorization_code" as any, {
      p_code: code,
    });
    if (error) throw new Error(error.message || "Authorization code verification failed");
    if (!data) throw new Error("Authorization code is invalid or expired");
    return true;
  };

  const handlePiAuth = async () => {
    const expectedCode = authorizationCode.trim().toUpperCase();

    if (!initPi() || !window.Pi) return;
    setBusyAuth(true);
    try {
      const referralCode = (searchParams.get("ref") || "").trim().toLowerCase();
      const auth = await window.Pi.authenticate(["username"]);
      const verified = await verifyPiAccessToken(auth.accessToken);
      const username = verified.username || auth.user.username;

      const signInResult = await signInPiBackedAccount(verified.uid, username, referralCode || undefined);
      if (expectedCode) {
        try {
          await verifyAuthorizationCode(expectedCode);
        } catch (error) {
          await supabase.auth.signOut();
          throw error;
        }
      }

      // Ensure current authenticated user has latest Pi metadata.
      const {
        data: user,
      } = await supabase.auth.getUser();
      try {
        await supabase.rpc("upsert_my_user_account" as any);
      } catch {
        // ignore best-effort
      }

      setPiUser({ uid: verified.uid, username });
      toast.success(`Authenticated as @${username}`);
      navigate("/dashboard", { replace: true });
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Pi auth failed");
    } finally {
      setBusyAuth(false);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-b from-paypal-blue to-[#072a7a] px-6 py-10">
      <div className="mx-auto flex min-h-[calc(100vh-5rem)] w-full max-w-md lg:max-w-lg xl:max-w-xl flex-col justify-center">
        <div className="mb-8 text-center">
          <div className="mx-auto mb-4 flex h-20 w-20 items-center justify-center rounded-3xl bg-white/10 backdrop-blur-sm">
            <BrandLogo className="h-14 w-14 text-white" />
          </div>
          <p className="mb-1 text-lg font-semibold text-white">OpenPay</p>
          <p className="text-sm font-medium text-white/85">Welcome to OpenPay</p>
        </div>

        <div className="paypal-surface w-full rounded-3xl p-7 shadow-2xl shadow-black/15">
          <div className="mb-4">
            <h1 className="paypal-heading text-xl">Welcome</h1>
          </div>

          <div className="rounded-2xl border border-border/70 bg-white dark:bg-[#0f172a] p-3">
            <h2 className="text-base font-semibold text-gray-800 dark:text-white">Pi Browser</h2>
            <p className="mt-1 text-sm text-gray-600 dark:text-white/80">
              Connect your Pi account securely with Pi authentication.
            </p>
            <p className="mt-1 text-xs text-gray-500 dark:text-white/60">
              Note: OpenPay works in the Pi Browser.
            </p>
            {!!searchParams.get("ref") && (
              <p className="mt-1 text-xs text-paypal-blue dark:text-blue-400">
                Referral code detected: {(searchParams.get("ref") || "").trim().toLowerCase()}
              </p>
            )}
            {!sdkReady && (
              <p className="mt-1 text-xs text-destructive dark:text-red-300">
                Pi SDK is unavailable. Please open this app in Pi Browser.
              </p>
            )}
            <div className="mt-4 space-y-2">
              <Button
                onClick={handlePiAuth}
                disabled={busyAuth || !sdkReady}
                className="h-11 w-full rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5] relative overflow-hidden"
              >
                <div className="flex items-center justify-center gap-2">
                  {busyAuth ? (
                    <>
                      <Loader2 className="h-4 w-4 animate-spin" />
                      <span>Authenticating...</span>
                    </>
                  ) : !sdkReady ? (
                    <>
                      <Loader2 className="h-4 w-4 animate-spin" />
                      <span>Loading Pi SDK...</span>
                    </>
                  ) : (
                    <>
                      <span>Authenticate with Pi</span>
                    </>
                  )}
                </div>
              </Button>
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                <Button
                  asChild
                  variant="outline"
                  className="h-11 w-full rounded-2xl"
                >
                  <Link to="/sign-in?mode=signin">Use Email Sign In</Link>
                </Button>
                <Button
                  asChild
                  type="button"
                  variant="outline"
                  className="h-11 w-full rounded-2xl"
                >
                  <a href="https://openpaylandingpage.vercel.app/" target="_blank" rel="noreferrer">
                    OpenPay Website
                  </a>
                </Button>
              </div>
            </div>
            <p className="mt-2 text-xs text-gray-600">
              Use Email Sign In when using OpenPay App, Desktop, Tablet, or Browser. Enjoy full-screen experience, notifications, POS, Merchant Portal access, and more.
            </p>
            {piUser && (
              <p className="mt-3 text-sm text-gray-800">
                Connected as <span className="font-semibold">@{piUser.username}</span> ({piUser.uid})
              </p>
            )}
            <AuthFooter />
          </div>
      </div>
    </div>
  </div>
  );
};

export default PiAuthPage;
