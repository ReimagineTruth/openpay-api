import { createContext, useContext, useState, useEffect, ReactNode } from "react";
import CookieConsentDialog from "@/components/CookieConsentDialog";
import {
  hasAcceptedCookies,
  canUseFunctionalCookies,
  canUseAnalyticsCookies,
  canUseMarketingCookies,
  loadUserPreferences,
  saveUserPreferences,
} from "@/lib/userPreferencesStorage";

interface CookieConsentContextType {
  hasAcceptedCookies: boolean;
  canUseFunctionalCookies: boolean;
  canUseAnalyticsCookies: boolean;
  canUseMarketingCookies: boolean;
  showCookieDialog: boolean;
  acceptAllCookies: () => void;
  showCookieSettings: () => void;
}

const CookieConsentContext = createContext<CookieConsentContextType | undefined>(undefined);

export const useCookieConsent = () => {
  const context = useContext(CookieConsentContext);
  if (context === undefined) {
    throw new Error("useCookieConsent must be used within a CookieConsentProvider");
  }
  return context;
};

interface CookieConsentProviderProps {
  children: ReactNode;
}

export const CookieConsentProvider = ({ children }: CookieConsentProviderProps) => {
  const [showCookieDialog, setShowCookieDialog] = useState(false);
  const [cookieConsent, setCookieConsent] = useState({
    hasAcceptedCookies: false,
    canUseFunctionalCookies: false,
    canUseAnalyticsCookies: false,
    canUseMarketingCookies: false,
  });

  useEffect(() => {
    // Check if user has already made consent decision
    const hasConsent = hasAcceptedCookies();
    const canUseFunctional = canUseFunctionalCookies();
    const canUseAnalytics = canUseAnalyticsCookies();
    const canUseMarketing = canUseMarketingCookies();

    setCookieConsent({
      hasAcceptedCookies: hasConsent,
      canUseFunctionalCookies: canUseFunctional,
      canUseAnalyticsCookies: canUseAnalytics,
      canUseMarketingCookies: canUseMarketing,
    });

    // Show cookie dialog only if no consent has been given at all
    // Don't show again if user has already made a decision
    if (!hasConsent) {
      // Delay showing the dialog to allow page to load
      const timer = setTimeout(() => {
        setShowCookieDialog(true);
      }, 2000);

      return () => clearTimeout(timer);
    }
  }, []);

  const acceptAllCookies = () => {
    saveUserPreferences({
      cookiesAccepted: true,
      analyticsConsent: true,
      marketingConsent: true,
    });

    setCookieConsent({
      hasAcceptedCookies: true,
      canUseFunctionalCookies: true,
      canUseAnalyticsCookies: true,
      canUseMarketingCookies: true,
    });
  };

  const showCookieSettings = () => {
    setShowCookieDialog(true);
  };

  const value: CookieConsentContextType = {
    ...cookieConsent,
    showCookieDialog,
    acceptAllCookies,
    showCookieSettings,
  };

  return (
    <CookieConsentContext.Provider value={value}>
      {children}
      <CookieConsentDialog
        open={showCookieDialog}
        onOpenChange={setShowCookieDialog}
      />
    </CookieConsentContext.Provider>
  );
};
