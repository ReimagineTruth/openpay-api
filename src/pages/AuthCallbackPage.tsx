import { useEffect } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { Loader2 } from "lucide-react";
import { toast } from "sonner";

const AuthCallbackPage = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();

  useEffect(() => {
    const handleAuthCallback = async () => {
      try {
        console.log("Processing auth callback...");
        
        // Check if there's an error in the URL params
        const error = searchParams.get("error");
        const errorDescription = searchParams.get("error_description");
        
        if (error) {
          console.error("OAuth error:", error, errorDescription);
          toast.error(`Authentication error: ${errorDescription || error}`);
          navigate("/sign-in", { replace: true });
          return;
        }

        // Wait a moment for Supabase to process the auth state
        await new Promise(resolve => setTimeout(resolve, 500));

        // Check if we have a session now
        const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
        
        if (sessionError) {
          console.error("Session error:", sessionError);
          toast.error("Failed to get session: " + sessionError.message);
          navigate("/sign-in", { replace: true });
          return;
        }

        if (sessionData.session) {
          console.log("Successfully authenticated:", sessionData.session.user.email);
          toast.success("Successfully signed in!");
          
          // Clear any URL hash fragments
          if (window.location.hash) {
            window.history.replaceState({}, document.title, window.location.pathname);
          }
          
          // Navigate to dashboard
          navigate("/dashboard", { replace: true });
        } else {
          console.log("No session found, redirecting to sign in");
          toast.error("Authentication failed - no session found");
          navigate("/sign-in", { replace: true });
        }
      } catch (error) {
        console.error("Auth callback error:", error);
        toast.error("An unexpected error occurred during authentication");
        navigate("/sign-in", { replace: true });
      }
    };

    handleAuthCallback();
  }, [navigate, searchParams]);

  return (
    <div className="min-h-screen bg-gradient-to-b from-paypal-blue to-[#072a7a] px-6 py-10 flex items-center justify-center">
      <div className="text-center">
        <Loader2 className="h-8 w-8 animate-spin text-white mx-auto mb-4" />
        <p className="text-white">Completing authentication...</p>
      </div>
    </div>
  );
};

export default AuthCallbackPage;
