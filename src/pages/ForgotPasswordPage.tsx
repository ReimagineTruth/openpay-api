import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { ArrowLeft } from "lucide-react";
import { toast } from "sonner";

import BrandLogo from "@/components/BrandLogo";
import AuthFooter from "@/components/AuthFooter";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { supabase } from "@/integrations/supabase/client";

const ForgotPasswordPage = () => {
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [loading, setLoading] = useState(false);

  const sendReset = async (e: React.FormEvent) => {
    e.preventDefault();

    if (typeof navigator !== "undefined" && !navigator.onLine) {
      toast.error("No internet connection. Please reconnect and try again.");
      return;
    }

    const trimmed = email.trim();
    if (!trimmed) {
      toast.error("Enter your email");
      return;
    }

    setLoading(true);
    const { error } = await supabase.auth.resetPasswordForEmail(trimmed, {
      redirectTo: typeof window === "undefined" ? undefined : `${window.location.origin}/reset-password`,
    });
    setLoading(false);

    if (error) {
      toast.error(error.message || "Failed to send reset email");
      return;
    }

    toast.success("Password reset email sent. Check your inbox (and spam).");
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
              <p className="text-lg font-bold text-foreground">Forgot password</p>
              <p className="text-xs text-muted-foreground">We’ll email you a secure reset link.</p>
            </div>
          </div>

          <form onSubmit={sendReset} className="space-y-4">
            <Input
              type="email"
              placeholder="Email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              className="h-12 rounded-2xl border-white/70 bg-white"
            />

            <Button type="submit" disabled={loading} className="h-12 w-full rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5]">
              {loading ? "Sending..." : "Send reset link"}
            </Button>

            <Button asChild type="button" variant="outline" className="h-12 w-full rounded-2xl">
              <Link to="/sign-in?mode=signin">Back to sign in</Link>
            </Button>
          </form>

          <AuthFooter />
        </div>
      </div>
    </div>
  );
};

export default ForgotPasswordPage;

