import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { ArrowLeft } from "lucide-react";
import { toast } from "sonner";

import BrandLogo from "@/components/BrandLogo";
import AuthFooter from "@/components/AuthFooter";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { supabase } from "@/integrations/supabase/client";

const ResetPasswordPage = () => {
  const navigate = useNavigate();
  const [checking, setChecking] = useState(true);
  const [hasSession, setHasSession] = useState(false);
  const [saving, setSaving] = useState(false);
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");

  useEffect(() => {
    let mounted = true;

    const syncSession = async () => {
      const { data } = await supabase.auth.getSession();
      if (!mounted) return;
      setHasSession(Boolean(data.session));
      setChecking(false);
    };

    const { data: sub } = supabase.auth.onAuthStateChange(() => {
      void syncSession();
    });

    void syncSession();
    return () => {
      mounted = false;
      sub.subscription.unsubscribe();
    };
  }, []);

  const passwordError = useMemo(() => {
    if (!password && !confirmPassword) return "";
    if (password.length > 0 && password.length < 6) return "Password must be at least 6 characters.";
    if (confirmPassword && password !== confirmPassword) return "Passwords do not match.";
    return "";
  }, [confirmPassword, password]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (typeof navigator !== "undefined" && !navigator.onLine) {
      toast.error("No internet connection. Please reconnect and try again.");
      return;
    }

    if (!hasSession) {
      toast.error("Open the reset link from your email first.");
      return;
    }

    if (passwordError) {
      toast.error(passwordError);
      return;
    }

    if (!password.trim()) {
      toast.error("Enter a new password");
      return;
    }

    setSaving(true);
    const { error } = await supabase.auth.updateUser({ password: password.trim() });
    setSaving(false);

    if (error) {
      toast.error(error.message || "Failed to update password");
      return;
    }

    toast.success("Password updated. Please sign in again.");
    await supabase.auth.signOut();
    navigate("/sign-in?mode=signin", { replace: true });
  };

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
              <p className="text-lg font-bold text-foreground">Reset password</p>
              <p className="text-xs text-muted-foreground">Choose a new password for your account.</p>
            </div>
          </div>

          {checking ? (
            <p className="text-sm text-muted-foreground">Preparing reset…</p>
          ) : !hasSession ? (
            <div className="space-y-3">
              <p className="text-sm text-muted-foreground">
                This page must be opened from the password reset email link.
              </p>
              <Button asChild className="h-12 w-full rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5]">
                <Link to="/forgot-password">Request a new reset link</Link>
              </Button>
              <Button asChild variant="outline" className="h-12 w-full rounded-2xl">
                <Link to="/sign-in?mode=signin">Back to sign in</Link>
              </Button>
            </div>
          ) : (
            <form onSubmit={submit} className="space-y-4">
              <Input
                type="password"
                placeholder="New password (min 6 characters)"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                className="h-12 rounded-2xl border-white/70 bg-white"
              />
              <Input
                type="password"
                placeholder="Confirm new password"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                required
                className="h-12 rounded-2xl border-white/70 bg-white"
              />
              {passwordError && <p className="-mt-2 text-xs font-medium text-red-600">{passwordError}</p>}
              <Button type="submit" disabled={saving} className="h-12 w-full rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5]">
                {saving ? "Saving..." : "Update password"}
              </Button>
            </form>
          )}

          <AuthFooter />
        </div>
      </div>
    </div>
  );
};

export default ResetPasswordPage;

