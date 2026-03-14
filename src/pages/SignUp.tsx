import { useState } from "react";
import { useNavigate, Link, useSearchParams } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { toast } from "sonner";
import AuthMark from "@/components/AuthMark";

const SignUp = () => {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [fullName, setFullName] = useState("");
  const [username, setUsername] = useState("");
  const [signupCode, setSignupCode] = useState("");
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const referralParam = searchParams.get("ref")?.trim().toLowerCase() || "";

  const handleSignUp = async (e: React.FormEvent) => {
    e.preventDefault();
    if (password.length < 6) {
      toast.error("Password must be at least 6 characters");
      return;
    }
    setLoading(true);
    
    const userData: any = { full_name: fullName, username };
    if (signupCode.trim()) {
      userData.signup_code = signupCode.trim().toUpperCase();
    }
    if (referralParam) {
      userData.referral_code = referralParam;
    }
    
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: userData,
        emailRedirectTo: window.location.origin,
      },
    });
    setLoading(false);
    if (error) {
      toast.error(error.message);
    } else {
      if (!data.session) {
        toast.success("Account created! Check your email to confirm, then log in.");
        navigate("/signin", { replace: true });
        return;
      }

      toast.success("Account created!");
      navigate("/onboarding", { replace: true });
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-b from-paypal-blue to-[#072a7a] px-6 py-10">
      <div className="mx-auto flex min-h-[calc(100vh-5rem)] w-full max-w-sm flex-col justify-center">
        <div className="mb-8 text-center">
          <AuthMark className="mx-auto mb-5 h-32 w-32" />
          <p className="mb-1 text-2xl font-bold tracking-tight text-white">OpenPay</p>
          <p className="text-sm font-medium text-white/85">Create your wallet</p>
        </div>
        <div className="paypal-surface w-full rounded-3xl p-7 shadow-2xl shadow-black/15">
          <h1 className="paypal-heading mb-6 text-center">Sign Up</h1>
          <form onSubmit={handleSignUp} className="space-y-4">
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
            <Input
              type="text"
              placeholder="Your Friend Affiliate Code (Optional)"
              value={signupCode}
              onChange={(e) => setSignupCode(e.target.value)}
              className="h-12 rounded-2xl border-white/70 bg-white"
            />
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
              placeholder="Password (min 6 characters)"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              className="h-12 rounded-2xl border-white/70 bg-white"
            />
            <Button type="submit" disabled={loading} className="w-full h-12 rounded-2xl bg-paypal-blue text-primary-foreground text-base font-semibold hover:bg-[#004dc5]">
              {loading ? "Creating account..." : "Sign Up"}
            </Button>
          </form>
          <p className="text-center mt-6 text-sm text-muted-foreground">
            Already have an account?{" "}
            <Link to="/signin" className="text-paypal-blue font-semibold">Log In</Link>
          </p>
          <p className="mt-4 text-center text-xs text-muted-foreground">
            By creating an account, you agree to our{" "}
            <Link to="/terms" className="text-paypal-blue font-medium">Terms</Link>
            {" "}and{" "}
            <Link to="/privacy" className="text-paypal-blue font-medium">Privacy Policy</Link>.
          </p>
          <div className="mt-4">
            <a
              href="https://www.openpy.space/blog"
              target="_blank"
              rel="noreferrer"
              className="inline-block w-full text-center text-sm font-semibold text-paypal-blue underline"
            >
              OpenPay Blog
            </a>
          </div>
        </div>
      </div>
    </div>
  );
};

export default SignUp;
