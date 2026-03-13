import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { ArrowLeft, CheckCircle, Clock, AlertCircle, FileText, RefreshCw, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { toast } from "sonner";
import BottomNav from "@/components/BottomNav";
import { supabase } from "@/integrations/supabase/client";
import BrandLogo from "@/components/BrandLogo";

interface KycApplication {
  id: string;
  user_id: string;
  full_name: string;
  date_of_birth: string;
  nationality: string;
  residential_address: string;
  phone_number: string;
  email: string;
  occupation: string;
  employer_name?: string;
  source_of_funds: string;
  annual_income_range: string;
  political_exposure: boolean;
  id_document_type: string;
  id_document_number: string;
  id_document_issue_date: string;
  id_document_expiry_date: string;
  id_document_front_url?: string;
  id_document_back_url?: string;
  selfie_url?: string;
  proof_of_address_url?: string;
  status: 'pending' | 'under_review' | 'approved' | 'rejected' | 'additional_info_required';
  rejection_reason?: string;
  admin_notes?: string;
  submitted_at: string;
  reviewed_at?: string;
  reviewed_by?: string;
}

const KycStatusPage = () => {
  const navigate = useNavigate();
  const [application, setApplication] = useState<KycApplication | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    loadApplicationStatus();
  }, []);

  const loadApplicationStatus = async () => {
    setLoading(true);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;

      // For now, we'll use localStorage since the table doesn't exist yet
      // This will be updated after we create the database schema
      const storedApplication = localStorage.getItem('kyc_application');
      
      if (storedApplication) {
        const parsedApplication = JSON.parse(storedApplication);
        setApplication(parsedApplication);
      } else {
        // Check if there's an application in the database (mock for now)
        console.log('No KYC application found');
      }
    } catch (error) {
      console.error('Error loading KYC status:', error);
      toast.error('Failed to load KYC status');
    } finally {
      setLoading(false);
    }
  };

  const getStatusInfo = (status: string) => {
    switch (status) {
      case 'pending':
        return {
          icon: <Clock className="h-8 w-8" />,
          color: 'text-yellow-600',
          bgColor: 'bg-yellow-50',
          borderColor: 'border-yellow-200',
          title: 'Application Submitted',
          description: 'Your KYC application has been submitted and is awaiting review.',
          nextSteps: 'Our team will review your application within 1-3 business days.'
        };
      case 'under_review':
        return {
          icon: <RefreshCw className="h-8 w-8 animate-spin" />,
          color: 'text-blue-600',
          bgColor: 'bg-blue-50',
          borderColor: 'border-blue-200',
          title: 'Under Review',
          description: 'Your application is currently being reviewed by our compliance team.',
          nextSteps: 'This process typically takes 1-3 business days. We\'ll notify you of any updates.'
        };
      case 'approved':
        return {
          icon: <CheckCircle className="h-8 w-8" />,
          color: 'text-green-600',
          bgColor: 'bg-green-50',
          borderColor: 'border-green-200',
          title: 'KYC Verified',
          description: 'Congratulations! Your identity has been successfully verified.',
          nextSteps: 'You now have access to all OpenPay features and higher transaction limits.'
        };
      case 'rejected':
        return {
          icon: <AlertCircle className="h-8 w-8" />,
          color: 'text-red-600',
          bgColor: 'bg-red-50',
          borderColor: 'border-red-200',
          title: 'Application Rejected',
          description: 'Unfortunately, your KYC application could not be approved at this time.',
          nextSteps: 'Please review the rejection reason and submit a new application if needed.'
        };
      case 'additional_info_required':
        return {
          icon: <FileText className="h-8 w-8" />,
          color: 'text-orange-600',
          bgColor: 'bg-orange-50',
          borderColor: 'border-orange-200',
          title: 'Additional Information Required',
          description: 'We need some additional information to complete your verification.',
          nextSteps: 'Please check your email for details and provide the requested information.'
        };
      default:
        return {
          icon: <FileText className="h-8 w-8" />,
          color: 'text-gray-600',
          bgColor: 'bg-gray-50',
          borderColor: 'border-gray-200',
          title: 'No Application',
          description: 'You haven\'t submitted a KYC application yet.',
          nextSteps: 'Complete the KYC verification process to unlock all features.'
        };
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-[#f8fbff] pb-24">
        <div className="px-4 pt-6">
          <div className="mb-6 flex items-center justify-between gap-3">
            <div className="flex items-center gap-3">
              <button onClick={() => navigate("/menu")} className="paypal-surface flex h-10 w-10 items-center justify-center rounded-full bg-white shadow-sm">
                <ArrowLeft className="h-5 w-5 text-foreground" />
              </button>
              <h1 className="text-xl font-bold text-paypal-dark">KYC Status</h1>
            </div>
            <div className="flex h-10 w-10 items-center justify-center rounded-2xl bg-white p-2 shadow-sm">
              <BrandLogo className="h-full w-full text-paypal-blue" />
            </div>
          </div>

          <div className="flex items-center justify-center py-12">
            <Loader2 className="h-8 w-8 animate-spin text-paypal-blue" />
            <span className="ml-2 text-gray-600">Loading KYC status...</span>
          </div>
        </div>
        <BottomNav active="menu" />
      </div>
    );
  }

  const statusInfo = application ? getStatusInfo(application.status) : getStatusInfo('none');

  return (
    <div className="min-h-screen bg-[#f8fbff] pb-24">
      <div className="px-4 pt-6">
        <div className="mb-6 flex items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            <button onClick={() => navigate("/menu")} className="paypal-surface flex h-10 w-10 items-center justify-center rounded-full bg-white shadow-sm">
              <ArrowLeft className="h-5 w-5 text-foreground" />
            </button>
            <h1 className="text-xl font-bold text-paypal-dark">KYC Status</h1>
          </div>
          <div className="flex h-10 w-10 items-center justify-center rounded-2xl bg-white p-2 shadow-sm">
            <BrandLogo className="h-full w-full text-paypal-blue" />
          </div>
        </div>

        {/* Status Card */}
        <div className={`paypal-surface rounded-2xl p-6 shadow-sm border ${statusInfo.borderColor}`}>
          <div className="flex items-center justify-between mb-4">
            <div className={`flex items-center gap-3 ${statusInfo.color}`}>
              <div className={`p-3 rounded-full ${statusInfo.bgColor}`}>
                {statusInfo.icon}
              </div>
              <div>
                <h2 className="text-lg font-semibold text-foreground">{statusInfo.title}</h2>
                <p className="text-sm text-muted-foreground">{statusInfo.description}</p>
              </div>
            </div>
          </div>

          <div className={`p-4 rounded-lg ${statusInfo.bgColor} mb-4`}>
            <p className="text-sm text-foreground">{statusInfo.nextSteps}</p>
          </div>

          {application && (
            <div className="space-y-3 text-sm">
              <div className="flex justify-between">
                <span className="text-muted-foreground">Application ID</span>
                <span className="font-mono text-foreground">{application.id.slice(0, 8)}...</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Submitted</span>
                <span className="text-foreground">
                  {new Date(application.submitted_at).toLocaleDateString()}
                </span>
              </div>
              {application.reviewed_at && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Reviewed</span>
                  <span className="text-foreground">
                    {new Date(application.reviewed_at).toLocaleDateString()}
                  </span>
                </div>
              )}
            </div>
          )}
        </div>

        {/* Application Details */}
        {application && (
          <div className="mt-6 paypal-surface rounded-2xl p-6 shadow-sm">
            <h3 className="font-semibold text-foreground mb-4">Application Details</h3>
            
            <div className="space-y-4">
              <div>
                <p className="text-sm text-muted-foreground mb-1">Full Name</p>
                <p className="font-medium text-foreground">{application.full_name}</p>
              </div>

              <div>
                <p className="text-sm text-muted-foreground mb-1">Email</p>
                <p className="font-medium text-foreground">{application.email}</p>
              </div>

              <div>
                <p className="text-sm text-muted-foreground mb-1">Phone</p>
                <p className="font-medium text-foreground">{application.phone_number}</p>
              </div>

              <div>
                <p className="text-sm text-muted-foreground mb-1">ID Document</p>
                <p className="font-medium text-foreground">
                  {application.id_document_type.toUpperCase()} - {application.id_document_number}
                </p>
              </div>

              {application.rejection_reason && (
                <div className="bg-red-50 border border-red-200 rounded-lg p-4">
                  <div className="flex items-start gap-3">
                    <AlertCircle className="h-5 w-5 text-red-600 mt-0.5" />
                    <div>
                      <p className="font-medium text-red-800">Rejection Reason</p>
                      <p className="text-sm text-red-700 mt-1">{application.rejection_reason}</p>
                    </div>
                  </div>
                </div>
              )}

              {application.admin_notes && (
                <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
                  <div className="flex items-start gap-3">
                    <FileText className="h-5 w-5 text-blue-600 mt-0.5" />
                    <div>
                      <p className="font-medium text-blue-800">Admin Notes</p>
                      <p className="text-sm text-blue-700 mt-1">{application.admin_notes}</p>
                    </div>
                  </div>
                </div>
              )}
            </div>
          </div>
        )}

        {/* Action Buttons */}
        <div className="mt-6 space-y-3">
          {!application && (
            <Button 
              onClick={() => navigate("/kyc")}
              className="w-full bg-paypal-blue hover:bg-[#004dc5] h-12"
            >
              Start KYC Verification
            </Button>
          )}

          {application?.status === 'rejected' && (
            <Button 
              onClick={() => navigate("/kyc")}
              className="w-full bg-paypal-blue hover:bg-[#004dc5] h-12"
            >
              Submit New Application
            </Button>
          )}

          {application?.status === 'additional_info_required' && (
            <Button 
              onClick={() => navigate("/kyc")}
              className="w-full bg-paypal-blue hover:bg-[#004dc5] h-12"
            >
              Provide Additional Information
            </Button>
          )}

          <Button 
            onClick={loadApplicationStatus}
            variant="outline"
            className="w-full h-12"
          >
            <RefreshCw className="h-4 w-4 mr-2" />
            Refresh Status
          </Button>
        </div>

        {/* Benefits Section */}
        {application?.status === 'approved' && (
          <div className="mt-6 paypal-surface rounded-2xl p-6 shadow-sm">
            <h3 className="font-semibold text-foreground mb-4">KYC Benefits</h3>
            <div className="space-y-3">
              <div className="flex items-center gap-3">
                <CheckCircle className="h-5 w-5 text-green-600" />
                <span className="text-sm text-foreground">Higher transaction limits</span>
              </div>
              <div className="flex items-center gap-3">
                <CheckCircle className="h-5 w-5 text-green-600" />
                <span className="text-sm text-foreground">Access to all OpenPay features</span>
              </div>
              <div className="flex items-center gap-3">
                <CheckCircle className="h-5 w-5 text-green-600" />
                <span className="text-sm text-foreground">Priority customer support</span>
              </div>
              <div className="flex items-center gap-3">
                <CheckCircle className="h-5 w-5 text-green-600" />
                <span className="text-sm text-foreground">Enhanced security features</span>
              </div>
            </div>
          </div>
        )}
      </div>
      <BottomNav active="menu" />
    </div>
  );
};

export default KycStatusPage;
