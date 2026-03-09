import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { ArrowLeft, Shield } from "lucide-react";

import BrandLogo from "@/components/BrandLogo";
import AuthFooter from "@/components/AuthFooter";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";

const ForgotMpinPage = () => {
  const navigate = useNavigate();
  const [hasSession, setHasSession] = useState<boolean | null>(null);

  useEffect(() => {
    const load = async () => {
      const { data } = await supabase.auth.getSession();
      setHasSession(Boolean(data.session));
    };
    void load();
  }, []);

  return (
    <div className="min-h-screen bg-gradient-to-b from-paypal-blue to-[#072a7a] px-6 py-10">
      <div className="mx-auto flex min-h-[calc(100vh-5rem)] w-full max-w-sm flex-col justify-center">
        <div className="mb-8 text-center">
          <div className="mx-auto mb-4 flex h-20 w-20 items-center justify-center rounded-3xl bg-white/10 backdrop-blur-sm">
            <BrandLogo className="h-14 w-14 text-white" />
          </div>
          <p className="mb-1 text-lg font-semibold text-white">OpenPay</p>
        </div>

        <div className="paypal-surface w-full rounded-3xl p-7 shadow-2xl shadow-black/15">
          <div className="mb-5 flex items-center gap-2">
            <button
              type="button"
              onClick={() => navigate(-1)}
              className="inline-flex h-9 w-9 items-center justify-center rounded-xl border border-border bg-white/70 text-foreground hover:bg-white"
              aria-label="Back"
            >
              <ArrowLeft className="h-4 w-4" />
            </button>
            <div className="min-w-0">
              <p className="text-lg font-bold text-foreground">Forgot MPIN</p>
              <p className="text-xs text-muted-foreground">Recover your device lock settings.</p>
            </div>
          </div>

          <div className="space-y-4">
            <div className="rounded-2xl border border-border bg-secondary/30 p-4">
              <div className="flex items-start gap-3">
                <div className="mt-0.5 rounded-xl bg-paypal-blue/10 p-2">
                  <Shield className="h-5 w-5 text-paypal-blue" />
                </div>
                <div>
                  <p className="text-sm font-semibold text-foreground">MPIN is device-only</p>
                  <p className="mt-1 text-xs text-muted-foreground">
                    Your MPIN is stored on this device/browser. OpenPay staff cannot see or reset it remotely.
                  </p>
                </div>
              </div>
            </div>

            <div className="space-y-2 text-sm text-muted-foreground">
              <p>
                If you’re locked out, use the <span className="font-semibold text-foreground">Help Center → Forgot MPIN</span> recovery screen to remove the MPIN using your security password or biometric.
              </p>
              <p>
                If you cleared browser/app data, you may need to sign in again and set a new MPIN in Settings.
              </p>
            </div>

            <div className="grid gap-2">
              <Button
                className="h-12 w-full rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5]"
                onClick={() => navigate("/help-center?topic=forgot-mpin")}
              >
                Open MPIN recovery
              </Button>

              {hasSession === false && (
                <Button asChild variant="outline" className="h-12 w-full rounded-2xl">
                  <Link to="/sign-in?mode=signin">Sign in first</Link>
                </Button>
              )}
            </div>
          </div>

          <AuthFooter />
        </div>
      </div>
    </div>
  );
};

export default ForgotMpinPage;

