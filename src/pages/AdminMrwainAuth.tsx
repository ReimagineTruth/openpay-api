import { useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { toast } from "sonner";
import BrandLogo from "@/components/BrandLogo";
import AuthFooter from "@/components/AuthFooter";
import { ExternalLink } from "lucide-react";

const AdminMrwainAuth = () => {
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();
  const mode = params.get("mode") === "signup" ? "signup" : "signin";
  const [loading, setLoading] = useState(false);
  const [showEmailConfirmationModal, setShowEmailConfirmationModal] = useState(false);
  const [signedUpEmail, setSignedUpEmail] = useState("");

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [fullName, setFullName] = useState("");
  const [username, setUsername] = useState("");

  const setMode = (nextMode: "signin" | "signup") => {
    setParams({ mode: nextMode });
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (typeof navigator !== "undefined" && !navigator.onLine) {
      toast.error("No internet connection. Please reconnect and try again.");
      return;
    }

    setLoading(true);

    if (mode === "signin") {
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      setLoading(false);
      if (error) toast.error(error.message);
      else navigate("/dashboard");
      return;
    }

    if (password.length < 6) {
      setLoading(false);
      toast.error("Password must be at least 6 characters");
      return;
    }

    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { full_name: fullName, username },
        emailRedirectTo: window.location.origin,
      },
    });
    setLoading(false);
    if (error) {
      toast.error(error.message);
    } else {
      toast.success("Account created successfully!");
      setSignedUpEmail(email);
      setShowEmailConfirmationModal(true);
    }
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
          {/* OpenPay Socials */}
          <Button 
            asChild 
            variant="outline" 
            className="mb-4 h-10 w-full rounded-2xl border-gray-300 bg-white text-gray-800 hover:bg-gray-50 flex items-center justify-center"
          >
            <a 
              href="https://droplink.space/@openpay" 
              target="_blank" 
              rel="noreferrer"
              className="w-full h-full flex items-center justify-center"
            >
              OpenPay Socials
            </a>
          </Button>

          <Button 
            asChild 
            variant="outline" 
            className="mb-4 h-10 w-full rounded-2xl border-gray-300 bg-white text-gray-800 hover:bg-gray-50 flex items-center justify-center"
          >
            <Link to="/auth" className="w-full h-full flex items-center justify-center">
              Back to Pi Authentication
            </Link>
          </Button>

          <div className="mb-5 grid grid-cols-2 gap-2 rounded-2xl bg-secondary p-1">
            <button
              onClick={() => setMode("signin")}
              className={`rounded-xl py-2 text-sm font-semibold ${mode === "signin" ? "bg-white text-paypal-blue" : "text-muted-foreground"}`}
            >
              Sign In
            </button>
            <button
              onClick={() => setMode("signup")}
              className={`rounded-xl py-2 text-sm font-semibold ${mode === "signup" ? "bg-white text-paypal-blue" : "text-muted-foreground"}`}
            >
              Sign Up
            </button>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">
            {mode === "signup" && (
              <>
                <Input
                  type="text"
                  placeholder="Full Name"
                  value={fullName}
                  onChange={(e) => setFullName(e.target.value)}
                  required
                  className="h-12 rounded-2xl border-white/70 bg-white"
                />
                <Input
                  type="text"
                  placeholder="Username"
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  required
                  className="h-12 rounded-2xl border-white/70 bg-white"
                />
              </>
            )}
            <Input
              type="email"
              placeholder="Email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              className="h-12 rounded-2xl border-white/70 bg-white"
            />
            <Input
              type="password"
              placeholder={mode === "signin" ? "Password" : "Password (min 6 characters)"}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              className="h-12 rounded-2xl border-white/70 bg-white"
            />
            {mode === "signin" && (
              <div className="-mt-2 flex items-center justify-between text-xs">
                <button
                  type="button"
                  onClick={() => navigate("/forgot-password")}
                  className="font-semibold text-paypal-blue hover:underline"
                >
                  Forgot password?
                </button>
                <button
                  type="button"
                  onClick={() => navigate("/forgot-mpin")}
                  className="font-semibold text-paypal-blue hover:underline"
                >
                  Forgot MPIN?
                </button>
              </div>
            )}
            <Button type="submit" disabled={loading} className="h-12 w-full rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5]">
              {loading ? "Please wait..." : mode === "signin" ? "Sign In" : "Create Account"}
            </Button>
            {mode === "signup" && (
              <Button
                asChild
                type="button"
                variant="outline"
                className="h-12 w-full rounded-2xl"
              >
                <Link to="/sign-in?mode=signin">
                  Already have an account? Sign In
                </Link>
              </Button>
            )}
            <Button
              asChild
              type="button"
              variant="outline"
              className="h-12 w-full rounded-2xl"
            >
              <a href="https://www.openpy.space/" target="_blank" rel="noreferrer">
                OpenPay Website
              </a>
            </Button>
            <Button
              asChild
              type="button"
              variant="outline"
              className="h-12 w-full rounded-2xl"
            >
              <a href="https://www.openpy.space/blog" target="_blank" rel="noreferrer">
                OpenPay Blog
              </a>
            </Button>
          </form>

          <AuthFooter />
        </div>
      </div>

      {/* Email Confirmation Modal */}
      <Dialog open={showEmailConfirmationModal} onOpenChange={setShowEmailConfirmationModal}>
        <DialogContent className="max-w-md mx-4">
          <DialogHeader>
            <DialogTitle className="text-center text-lg font-semibold text-paypal-blue">
              Check Your Email
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4 text-center">
            <div className="mx-auto w-16 h-16 bg-emerald-100 rounded-full flex items-center justify-center">
              <svg className="w-8 h-8 text-emerald-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
              </svg>
            </div>
            
            <div className="space-y-2">
              <h3 className="text-lg font-semibold text-gray-900">
                Confirmation Email Sent!
              </h3>
              <p className="text-sm text-gray-600">
                We've sent a confirmation email to:
              </p>
              <div className="bg-gray-50 rounded-lg p-3 border border-gray-200">
                <p className="font-mono text-sm text-gray-800 break-all">{signedUpEmail}</p>
              </div>
            </div>

            <div className="space-y-3 text-left bg-blue-50 rounded-lg p-4">
              <h4 className="font-semibold text-blue-900 text-sm">Next Steps:</h4>
              <ol className="space-y-2 text-sm text-blue-800">
                <li className="flex items-start gap-2">
                  <span className="font-bold text-blue-600">1.</span>
                  <span>Check your inbox (and spam folder)</span>
                </li>
                <li className="flex items-start gap-2">
                  <span className="font-bold text-blue-600">2.</span>
                  <span>Open the "Confirm your email" message</span>
                </li>
                <li className="flex items-start gap-2">
                  <span className="font-bold text-blue-600">3.</span>
                  <span>Click the confirmation link inside</span>
                </li>
                <li className="flex items-start gap-2">
                  <span className="font-bold text-blue-600">4.</span>
                  <span>Return here to sign in</span>
                </li>
              </ol>
            </div>

            <div className="space-y-2">
              <p className="text-xs text-gray-500">
                Didn't receive the email? Check your spam folder or
                <button 
                  onClick={() => setShowEmailConfirmationModal(false)}
                  className="text-paypal-blue hover:underline ml-1"
                >
                  try signing in
                </button>
              </p>
              <p className="text-xs text-gray-500">
                The confirmation link expires in 24 hours.
              </p>
            </div>

            <Button 
              onClick={() => {
                setShowEmailConfirmationModal(false);
                setMode("signin");
              }}
              className="w-full bg-paypal-blue text-white hover:bg-[#004dc5]"
            >
              Got it, I'll check my email
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default AdminMrwainAuth;
