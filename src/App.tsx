import { useEffect, useRef, useState } from "react";
import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route, Navigate, useLocation } from "react-router-dom";
import Index from "./pages/Index";
import AdminMrwainAuth from "./pages/AdminMrwainAuth";
import Dashboard from "./pages/Dashboard";
import SendMoney from "./pages/SendMoney";
import QrScannerPage from "./pages/QrScannerPage";
import TopUp from "./pages/TopUp";
import TopUpEwalletQrPh from "./pages/TopUpEwalletQrPh";
import TopUpPaypal from "./pages/TopUpPaypal";
import TopUpDebit from "./pages/TopUpDebit";
import TopUpCredit from "./pages/TopUpCredit";
import TopUpApplePay from "./pages/TopUpApplePay";
import TopUpGooglePay from "./pages/TopUpGooglePay";
import TopUpStripe from "./pages/TopUpStripe";
import TopUpVenmo from "./pages/TopUpVenmo";
import TopUpUSDT from "./pages/TopUpUSDT";
import TopUpUSDC from "./pages/TopUpUSDC";
import ReceivePage from "./pages/ReceivePage";
import Contacts from "./pages/Contacts";
import MenuPage from "./pages/MenuPage";
import CurrencyConverterPage from "./pages/CurrencyConverterPage";
import ActivityPage from "./pages/ActivityPage";
import RequestMoney from "./pages/RequestMoney";
import DisputesPage from "./pages/DisputesPage";
import SendInvoice from "./pages/SendInvoice";
import HelpCenter from "./pages/HelpCenter";
import NotificationsPage from "./pages/NotificationsPage";
import SettingsPage from "./pages/SettingsPage";
import ProfilePage from "./pages/ProfilePage";
import AffiliatePage from "./pages/AffiliatePage";
import MiningPage from "./pages/MiningPage";
import StakingPage from "./pages/StakingPage";
import OpenPayGuidePage from "./pages/OpenPayGuidePage";
import PublicLedgerPage from "./pages/PublicLedgerPage";
import AnnouncementsPage from "./pages/AnnouncementsPage";
import TermsPage from "./pages/TermsPage";
import PrivacyPage from "./pages/PrivacyPage";
import RegulatoryStatusPage from "./pages/RegulatoryStatusPage";
import AboutOpenPayPage from "./pages/AboutOpenPayPage";
import LegalPage from "./pages/LegalPage";
import OpenPayDocumentationPage from "./pages/OpenPayDocumentationPage";
import OpenPayApiDocsPage from "./pages/OpenPayApiDocsPage";
import OpenPayPosDocsPage from "./pages/OpenPayPosDocsPage";
import OpenPayMerchantPortalDocsPage from "./pages/OpenPayMerchantPortalDocsPage";
import OpenPartnerPage from "./pages/OpenPartnerPage";
import PiWhitepaperPage from "./pages/PiWhitepaperPage";
import PiMicaWhitepaperPage from "./pages/PiMicaWhitepaperPage";
import WhitepaperPage from "./pages/WhitepaperPage";
import GdprPage from "./pages/GdprPage";
import PaymentLinksCreatePage from "./pages/PaymentLinksCreatePage";
import MerchantProductCatalogPage from "./pages/MerchantProductCatalogPage";
import MerchantProductCreatePage from "./pages/MerchantProductCreatePage";
import PiAuthPage from "./pages/PiAuthPage";
import SetupProfilePage from "./pages/SetupProfilePage";
import PiAdsPage from "./pages/PiAdsPage";
import OnboardingPage from "./pages/OnboardingPage";
import AdminDashboard from "./pages/AdminDashboard";
import AdminSwapWithdrawalsPage from "./pages/AdminSwapWithdrawalsPage";
import AdminLoanApplicationsPage from "./pages/AdminLoanApplicationsPage";
import AdminTopUpRequestsPage from "./pages/AdminTopUpRequestsPage";
import AdminMasterTopUp from "./pages/AdminMasterTopUp";
import MerchantOnboardingPage from "./pages/MerchantOnboardingPage";
import OpenPayOfficialPage from "./pages/OpenPayOfficialPage";
import RemittanceMerchantPage from "./pages/RemittanceMerchantPage";
import MerchantPosPage from "./pages/MerchantPosPage";
import MerchantCheckoutPage from "./pages/MerchantCheckoutPage";
import MerchantCheckoutThankYouPage from "./pages/MerchantCheckoutThankYouPage";
import PosThankYouPage from "./pages/PosThankYouPage";
import PublicWalletPaymentPage from "./pages/PublicWalletPaymentPage";
import OpenAppPage from "./pages/OpenAppPage";
import OpenPayDesktopPage from "./pages/OpenPayDesktopPage";
import VirtualCardPage from "./pages/VirtualCardPage";
import LiveCustomerServicePage from "./pages/LiveCustomerServicePage";
import SwapWithdrawalPage from "./pages/SwapWithdrawalPage";
import ConfirmPinPage from "./pages/ConfirmPinPage";
import NotFound from "./pages/NotFound";
import { CurrencyProvider } from "./contexts/CurrencyContext";
import { useRealtimePushNotifications } from "./hooks/useRealtimePushNotifications";
import AppSecurityGate from "./components/AppSecurityGate";
import AppFooter from "./components/AppFooter";
import BrandLogo from "./components/BrandLogo";
import AppLanguageTranslate from "./components/AppLanguageTranslate";
import SupportWidget from "./components/SupportWidget";
import { CookieConsentProvider } from "./contexts/CookieConsentContext";
import PageTransition from "./components/PageTransition";

const queryClient = new QueryClient();

const AppRoutes = () => {
  const location = useLocation();
  const routeLoaderReady = useRef(false);
  const [showRouteSplash, setShowRouteSplash] = useState(true);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      routeLoaderReady.current = true;
      setShowRouteSplash(false);
    }, 500);
    return () => window.clearTimeout(timer);
  }, []);

  useEffect(() => {
    if (!routeLoaderReady.current) {
      return;
    }

    setShowRouteSplash(true);
    const timer = window.setTimeout(() => setShowRouteSplash(false), 500);
    return () => window.clearTimeout(timer);
  }, [location.pathname, location.search]);

  const LegacyAdminMrwainRedirect = () => {
    const current = useLocation();
    return <Navigate to={`/sign-in${current.search || ""}`} replace />;
  };

  return (
    <>
      <PageTransition key={location.pathname}>
        <Routes>
        <Route path="/" element={<Index />} />
        <Route path="/auth" element={<PiAuthPage />} />
        <Route path="/setup-profile" element={<SetupProfilePage />} />
        <Route path="/onboarding" element={<OnboardingPage />} />
        <Route path="/pi-ads" element={<PiAdsPage />} />
        <Route path="/sign-in" element={<AdminMrwainAuth />} />
        <Route path="/admin-mrwain" element={<LegacyAdminMrwainRedirect />} />
        <Route path="/admin-dashboard" element={<AdminDashboard />} />
        <Route path="/admin-swap-withrawals" element={<AdminSwapWithdrawalsPage />} />
        <Route path="/admin-loan-applications" element={<AdminLoanApplicationsPage />} />
        <Route path="/admin-topup-requests" element={<AdminTopUpRequestsPage />} />
        <Route path="/master-topup" element={<AdminMasterTopUp />} />
        <Route path="/signin" element={<Navigate to="/sign-in?mode=signin" replace />} />
        <Route path="/signup" element={<Navigate to="/sign-in?mode=signup" replace />} />
        <Route path="/dashboard" element={<Dashboard />} />
        <Route path="/send" element={<SendMoney />} />
        <Route path="/scan-qr" element={<QrScannerPage />} />
        <Route path="/topup" element={<TopUp />} />
        <Route path="/topup-ewallet-qrph" element={<TopUpEwalletQrPh />} />
        <Route path="/topup-paypal" element={<TopUpPaypal />} />
        <Route path="/topup-debit" element={<TopUpDebit />} />
        <Route path="/topup-credit" element={<TopUpCredit />} />
        <Route path="/topup-apple-pay" element={<TopUpApplePay />} />
        <Route path="/topup-google-pay" element={<TopUpGooglePay />} />
        <Route path="/topup-stripe" element={<TopUpStripe />} />
        <Route path="/topup-venmo" element={<TopUpVenmo />} />
        <Route path="/topup-usdt" element={<TopUpUSDT />} />
        <Route path="/topup-usdc" element={<TopUpUSDC />} />
        <Route path="/receive" element={<ReceivePage />} />
        <Route path="/contacts" element={<Contacts />} />
        <Route path="/menu" element={<MenuPage />} />
        <Route path="/currency-converter" element={<CurrencyConverterPage />} />
        <Route path="/activity" element={<ActivityPage />} />
        <Route path="/request-payment" element={<RequestMoney />} />
        <Route path="/send-invoice" element={<SendInvoice />} />
        <Route path="/disputes" element={<DisputesPage />} />
        <Route path="/help-center" element={<HelpCenter />} />
        <Route path="/notifications" element={<NotificationsPage />} />
        <Route path="/settings" element={<SettingsPage />} />
        <Route path="/profile" element={<ProfilePage />} />
        <Route path="/affiliate" element={<AffiliatePage />} />
        <Route path="/mining" element={<MiningPage />} />
        <Route path="/staking" element={<StakingPage />} />
        <Route path="/ledger" element={<PublicLedgerPage />} />
        <Route path="/openledger" element={<Navigate to="/ledger" replace />} />
        <Route path="/announcements" element={<AnnouncementsPage />} />
        <Route path="/openpay-guide" element={<OpenPayGuidePage />} />
        <Route path="/terms" element={<TermsPage />} />
        <Route path="/privacy" element={<PrivacyPage />} />
        <Route path="/regulatory-status" element={<RegulatoryStatusPage />} />
        <Route path="/about-openpay" element={<AboutOpenPayPage />} />
        <Route path="/openpay-documentation" element={<OpenPayDocumentationPage />} />
        <Route path="/openpay-api-docs" element={<OpenPayApiDocsPage />} />
        <Route path="/openpay-pos-docs" element={<OpenPayPosDocsPage />} />
        <Route path="/openpay-merchant-portal-docs" element={<OpenPayMerchantPortalDocsPage />} />
        <Route path="/open-partner" element={<OpenPartnerPage />} />
        <Route path="/pi-whitepaper" element={<PiWhitepaperPage />} />
        <Route path="/pi-mica-whitepaper" element={<PiMicaWhitepaperPage />} />
        <Route path="/whitepaper" element={<WhitepaperPage />} />
        <Route path="/gdpr" element={<GdprPage />} />
        <Route path="/legal" element={<LegalPage />} />
        <Route path="/merchant-onboarding" element={<MerchantOnboardingPage />} />
        <Route path="/merchant-products" element={<MerchantProductCatalogPage />} />
        <Route path="/merchant-products/create" element={<MerchantProductCreatePage />} />
        <Route path="/merchant-pos" element={<MerchantPosPage />} />
        <Route path="/payment-links/create" element={<PaymentLinksCreatePage />} />
        <Route path="/payment-link/:token" element={<MerchantCheckoutPage />} />
        <Route path="/merchant-checkout" element={<MerchantCheckoutPage />} />
        <Route path="/public-payment" element={<PublicWalletPaymentPage />} />
        <Route path="/merchant-checkout/thank-you" element={<MerchantCheckoutThankYouPage />} />
        <Route path="/pos-thank-you" element={<PosThankYouPage />} />
        <Route path="/virtual-card" element={<VirtualCardPage />} />
        <Route path="/remittance-merchant" element={<RemittanceMerchantPage />} />
        <Route path="/openpay-official" element={<OpenPayOfficialPage />} />
        <Route path="/openapp" element={<OpenAppPage />} />
        <Route path="/openpay-desktop" element={<OpenPayDesktopPage />} />
        <Route path="/live-customer-service" element={<LiveCustomerServicePage />} />
        <Route path="/support" element={<></>} />
        <Route path="/swap-withdrawal" element={<SwapWithdrawalPage />} />
        <Route path="/confirm-pin" element={<ConfirmPinPage />} />
        <Route path="*" element={<NotFound />} />
      </Routes>
      </PageTransition>
      <AppSecurityGate />
      {location.pathname !== "/support" ? <AppFooter /> : null}
      {!showRouteSplash ? <SupportWidget /> : null}

      {showRouteSplash && (
        <div className="fixed inset-0 z-[120] flex items-center justify-center bg-gradient-to-b from-paypal-blue to-[#072a7a]">
          <div className="text-center">
            <div className="mx-auto mb-4 flex h-24 w-24 items-center justify-center rounded-3xl bg-white/10 backdrop-blur-sm">
              <BrandLogo className="h-14 w-14 text-white" />
            </div>
            <p className="text-3xl font-bold tracking-tight text-white">OpenPay</p>
            <p className="mt-1 text-sm text-white/80">Loading page...</p>
            <p className="mt-1 text-xs font-medium tracking-normal text-white/65">Powered by Pi Network</p>
            <div className="mx-auto mt-6 h-8 w-8 rounded-full border-2 border-white/35 border-t-white animate-spin" />
          </div>
        </div>
      )}
    </>
  );
};

const App = () => {
  useRealtimePushNotifications();

  return (
    <QueryClientProvider client={queryClient}>
      <CookieConsentProvider>
        <CurrencyProvider>
          <TooltipProvider>
            <AppLanguageTranslate />
            <Toaster />
            <Sonner />
            <BrowserRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
              <AppRoutes />
            </BrowserRouter>
          </TooltipProvider>
        </CurrencyProvider>
      </CookieConsentProvider>
    </QueryClientProvider>
  );
};

export default App;
