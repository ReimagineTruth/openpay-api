import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { ArrowLeft, Upload, Camera, CheckCircle, AlertCircle, User, FileText, Shield, Eye, EyeOff, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { toast } from "sonner";
import BottomNav from "@/components/BottomNav";
import { supabase } from "@/integrations/supabase/client";
import BrandLogo from "@/components/BrandLogo";

interface KycApplication {
  id?: string;
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

const KycPage = () => {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [currentApplication, setCurrentApplication] = useState<KycApplication | null>(null);
  const [showPassword, setShowPassword] = useState(false);
  
  // Form state
  const [formData, setFormData] = useState({
    full_name: "",
    date_of_birth: "",
    nationality: "",
    residential_address: "",
    phone_number: "",
    email: "",
    occupation: "",
    employer_name: "",
    source_of_funds: "",
    annual_income_range: "",
    political_exposure: false,
    id_document_type: "",
    id_document_number: "",
    id_document_issue_date: "",
    id_document_expiry_date: "",
  });

  // File upload state
  const [uploadedFiles, setUploadedFiles] = useState({
    id_document_front: null as File | null,
    id_document_back: null as File | null,
    selfie: null as File | null,
    proof_of_address: null as File | null,
  });

  const [uploadedUrls, setUploadedUrls] = useState({
    id_document_front_url: "",
    id_document_back_url: "",
    selfie_url: "",
    proof_of_address_url: "",
  });

  useEffect(() => {
    loadExistingApplication();
  }, []);

  const loadExistingApplication = async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;

      // For now, we'll use a mock implementation since the table doesn't exist yet
      // This will be updated after we create the database schema
      console.log('Loading existing KYC application for user:', user.id);
      
      // Mock data for testing - remove this after database schema is created
      const mockData = null;
      
      if (mockData) {
        setCurrentApplication(mockData);
        setFormData({
          full_name: mockData.full_name || "",
          date_of_birth: mockData.date_of_birth || "",
          nationality: mockData.nationality || "",
          residential_address: mockData.residential_address || "",
          phone_number: mockData.phone_number || "",
          email: mockData.email || "",
          occupation: mockData.occupation || "",
          employer_name: mockData.employer_name || "",
          source_of_funds: mockData.source_of_funds || "",
          annual_income_range: mockData.annual_income_range || "",
          political_exposure: mockData.political_exposure || false,
          id_document_type: mockData.id_document_type || "",
          id_document_number: mockData.id_document_number || "",
          id_document_issue_date: mockData.id_document_issue_date || "",
          id_document_expiry_date: mockData.id_document_expiry_date || "",
        });
        setUploadedUrls({
          id_document_front_url: mockData.id_document_front_url || "",
          id_document_back_url: mockData.id_document_back_url || "",
          selfie_url: mockData.selfie_url || "",
          proof_of_address_url: mockData.proof_of_address_url || "",
        });
      }
    } catch (error) {
      console.error('Error loading KYC application:', error);
    }
  };

  const handleInputChange = (field: string, value: string | boolean) => {
    setFormData(prev => ({
      ...prev,
      [field]: value
    }));
  };

  const handleFileUpload = async (fileType: string, file: File) => {
    if (!file) return;

    setUploading(true);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('User not authenticated');

      const fileExt = file.name.split('.').pop();
      const fileName = `${user.id}/${fileType}_${Date.now()}.${fileExt}`;
      
      const { error: uploadError } = await supabase.storage
        .from('kyc-documents')
        .upload(fileName, file, {
          cacheControl: '3600',
          upsert: true
        });

      if (uploadError) throw uploadError;

      const { data: { publicUrl } } = supabase.storage
        .from('kyc-documents')
        .getPublicUrl(fileName);

      setUploadedUrls(prev => ({
        ...prev,
        [`${fileType}_url`]: publicUrl
      }));

      setUploadedFiles(prev => ({
        ...prev,
        [fileType]: file
      }));

      toast.success(`${fileType.replace('_', ' ')} uploaded successfully`);
    } catch (error) {
      console.error('Upload error:', error);
      toast.error(`Failed to upload ${fileType.replace('_', ' ')}`);
    } finally {
      setUploading(false);
    }
  };

  const handleSubmit = async () => {
    if (!formData.full_name || !formData.date_of_birth || !formData.nationality || 
        !formData.residential_address || !formData.phone_number || !formData.email ||
        !formData.occupation || !formData.source_of_funds || !formData.annual_income_range ||
        !formData.id_document_type || !formData.id_document_number || 
        !formData.id_document_issue_date || !formData.id_document_expiry_date) {
      toast.error('Please fill in all required fields');
      return;
    }

    if (!uploadedUrls.id_document_front_url || !uploadedUrls.selfie_url) {
      toast.error('Please upload ID document front and selfie');
      return;
    }

    setLoading(true);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('User not authenticated');

      // For now, we'll store the application in localStorage since the table doesn't exist yet
      // This will be updated after we create the database schema
      const applicationData: KycApplication = {
        user_id: user.id,
        ...formData,
        ...uploadedUrls,
        status: 'pending',
        submitted_at: new Date().toISOString(),
      };

      // Mock submission - store in localStorage for now
      localStorage.setItem('kyc_application', JSON.stringify(applicationData));

      toast.success('KYC application submitted successfully');
      navigate('/kyc-status');
    } catch (error) {
      console.error('Submit error:', error);
      toast.error('Failed to submit KYC application');
    } finally {
      setLoading(false);
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'approved': return 'text-green-600 bg-green-50';
      case 'rejected': return 'text-red-600 bg-red-50';
      case 'under_review': return 'text-blue-600 bg-blue-50';
      case 'additional_info_required': return 'text-orange-600 bg-orange-50';
      default: return 'text-gray-600 bg-gray-50';
    }
  };

  const getStatusText = (status: string) => {
    switch (status) {
      case 'approved': return 'Approved';
      case 'rejected': return 'Rejected';
      case 'under_review': return 'Under Review';
      case 'additional_info_required': return 'Additional Info Required';
      default: return 'Pending';
    }
  };

  if (currentApplication && currentApplication.status !== 'rejected') {
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

          <div className="paypal-surface rounded-2xl p-6 shadow-sm">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-lg font-semibold text-foreground">Application Status</h2>
              <span className={`px-3 py-1 rounded-full text-sm font-medium ${getStatusColor(currentApplication.status)}`}>
                {getStatusText(currentApplication.status)}
              </span>
            </div>

            <div className="space-y-4">
              <div>
                <p className="text-sm text-muted-foreground mb-1">Full Name</p>
                <p className="font-medium text-foreground">{currentApplication.full_name}</p>
              </div>

              <div>
                <p className="text-sm text-muted-foreground mb-1">Email</p>
                <p className="font-medium text-foreground">{currentApplication.email}</p>
              </div>

              <div>
                <p className="text-sm text-muted-foreground mb-1">Submitted Date</p>
                <p className="font-medium text-foreground">
                  {new Date(currentApplication.submitted_at).toLocaleDateString()}
                </p>
              </div>

              {currentApplication.rejection_reason && (
                <div className="bg-red-50 border border-red-200 rounded-lg p-4">
                  <div className="flex items-start gap-3">
                    <AlertCircle className="h-5 w-5 text-red-600 mt-0.5" />
                    <div>
                      <p className="font-medium text-red-800">Rejection Reason</p>
                      <p className="text-sm text-red-700 mt-1">{currentApplication.rejection_reason}</p>
                    </div>
                  </div>
                </div>
              )}

              {currentApplication.admin_notes && (
                <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
                  <div className="flex items-start gap-3">
                    <FileText className="h-5 w-5 text-blue-600 mt-0.5" />
                    <div>
                      <p className="font-medium text-blue-800">Admin Notes</p>
                      <p className="text-sm text-blue-700 mt-1">{currentApplication.admin_notes}</p>
                    </div>
                  </div>
                </div>
              )}
            </div>

            {(currentApplication.status as string) === 'rejected' && (
              <Button 
                onClick={() => window.location.reload()} 
                className="w-full mt-6 bg-paypal-blue hover:bg-[#004dc5]"
              >
                Submit New Application
              </Button>
            )}
          </div>
        </div>
        <BottomNav active="menu" />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-[#f8fbff] pb-24">
      <div className="px-4 pt-6">
        <div className="mb-6 flex items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            <button onClick={() => navigate("/menu")} className="paypal-surface flex h-10 w-10 items-center justify-center rounded-full bg-white shadow-sm">
              <ArrowLeft className="h-5 w-5 text-foreground" />
            </button>
            <h1 className="text-xl font-bold text-paypal-dark">KYC Verification</h1>
          </div>
          <div className="flex h-10 w-10 items-center justify-center rounded-2xl bg-white p-2 shadow-sm">
            <BrandLogo className="h-full w-full text-paypal-blue" />
          </div>
        </div>

        <div className="mb-6 paypal-surface rounded-2xl p-4 shadow-sm">
          <div className="flex items-start gap-3">
            <Shield className="h-5 w-5 text-paypal-blue mt-0.5" />
            <div>
              <h3 className="font-semibold text-foreground mb-1">Identity Verification</h3>
              <p className="text-sm text-muted-foreground">
                Complete KYC verification to unlock full account features and higher transaction limits.
              </p>
            </div>
          </div>
        </div>

        <div className="space-y-6">
          {/* Personal Information */}
          <div className="paypal-surface rounded-2xl p-6 shadow-sm">
            <h3 className="font-semibold text-foreground mb-4 flex items-center gap-2">
              <User className="h-4 w-4 text-paypal-blue" />
              Personal Information
            </h3>
            
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-foreground mb-1">Full Name *</label>
                <input
                  type="text"
                  value={formData.full_name}
                  onChange={(e) => handleInputChange('full_name', e.target.value)}
                  className="w-full h-10 rounded-lg border border-border bg-background px-3 text-foreground"
                  placeholder="Enter your full legal name"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-foreground mb-1">Date of Birth *</label>
                <input
                  type="date"
                  value={formData.date_of_birth}
                  onChange={(e) => handleInputChange('date_of_birth', e.target.value)}
                  className="w-full h-10 rounded-lg border border-border bg-background px-3 text-foreground"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-foreground mb-1">Nationality *</label>
                <input
                  type="text"
                  value={formData.nationality}
                  onChange={(e) => handleInputChange('nationality', e.target.value)}
                  className="w-full h-10 rounded-lg border border-border bg-background px-3 text-foreground"
                  placeholder="Enter your nationality"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-foreground mb-1">Residential Address *</label>
                <textarea
                  value={formData.residential_address}
                  onChange={(e) => handleInputChange('residential_address', e.target.value)}
                  className="w-full h-20 rounded-lg border border-border bg-background px-3 text-foreground resize-none"
                  placeholder="Enter your complete residential address"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-foreground mb-1">Phone Number *</label>
                <input
                  type="tel"
                  value={formData.phone_number}
                  onChange={(e) => handleInputChange('phone_number', e.target.value)}
                  className="w-full h-10 rounded-lg border border-border bg-background px-3 text-foreground"
                  placeholder="+1 234 567 8900"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-foreground mb-1">Email Address *</label>
                <input
                  type="email"
                  value={formData.email}
                  onChange={(e) => handleInputChange('email', e.target.value)}
                  className="w-full h-10 rounded-lg border border-border bg-background px-3 text-foreground"
                  placeholder="your.email@example.com"
                />
              </div>
            </div>
          </div>

          {/* Financial Information */}
          <div className="paypal-surface rounded-2xl p-6 shadow-sm">
            <h3 className="font-semibold text-foreground mb-4 flex items-center gap-2">
              <FileText className="h-4 w-4 text-paypal-blue" />
              Financial Information
            </h3>
            
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-foreground mb-1">Occupation *</label>
                <input
                  type="text"
                  value={formData.occupation}
                  onChange={(e) => handleInputChange('occupation', e.target.value)}
                  className="w-full h-10 rounded-lg border border-border bg-background px-3 text-foreground"
                  placeholder="Enter your occupation"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-foreground mb-1">Employer Name</label>
                <input
                  type="text"
                  value={formData.employer_name}
                  onChange={(e) => handleInputChange('employer_name', e.target.value)}
                  className="w-full h-10 rounded-lg border border-border bg-background px-3 text-foreground"
                  placeholder="Enter employer name (if applicable)"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-foreground mb-1">Source of Funds *</label>
                <select
                  value={formData.source_of_funds}
                  onChange={(e) => handleInputChange('source_of_funds', e.target.value)}
                  className="w-full h-10 rounded-lg border border-border bg-background px-3 text-foreground"
                >
                  <option value="">Select source of funds</option>
                  <option value="employment">Employment Income</option>
                  <option value="business">Business Income</option>
                  <option value="investments">Investments</option>
                  <option value="inheritance">Inheritance</option>
                  <option value="savings">Personal Savings</option>
                  <option value="other">Other</option>
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-foreground mb-1">Annual Income Range *</label>
                <select
                  value={formData.annual_income_range}
                  onChange={(e) => handleInputChange('annual_income_range', e.target.value)}
                  className="w-full h-10 rounded-lg border border-border bg-background px-3 text-foreground"
                >
                  <option value="">Select income range</option>
                  <option value="0-25000">Under $25,000</option>
                  <option value="25000-50000">$25,000 - $50,000</option>
                  <option value="50000-100000">$50,000 - $100,000</option>
                  <option value="100000-250000">$100,000 - $250,000</option>
                  <option value="250000+">$250,000+</option>
                </select>
              </div>

              <div className="flex items-center gap-3">
                <input
                  type="checkbox"
                  id="political_exposure"
                  checked={formData.political_exposure}
                  onChange={(e) => handleInputChange('political_exposure', e.target.checked)}
                  className="h-4 w-4 rounded border-border"
                />
                <label htmlFor="political_exposure" className="text-sm text-foreground">
                  I am a politically exposed person (PEP) or related to one
                </label>
              </div>
            </div>
          </div>

          {/* ID Documents */}
          <div className="paypal-surface rounded-2xl p-6 shadow-sm">
            <h3 className="font-semibold text-foreground mb-4 flex items-center gap-2">
              <FileText className="h-4 w-4 text-paypal-blue" />
              Identity Documents
            </h3>
            
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-foreground mb-1">ID Document Type *</label>
                <select
                  value={formData.id_document_type}
                  onChange={(e) => handleInputChange('id_document_type', e.target.value)}
                  className="w-full h-10 rounded-lg border border-border bg-background px-3 text-foreground"
                >
                  <option value="">Select document type</option>
                  <option value="passport">Passport</option>
                  <option value="national_id">National ID Card</option>
                  <option value="drivers_license">Driver's License</option>
                  <option value="residence_permit">Residence Permit</option>
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-foreground mb-1">ID Document Number *</label>
                <input
                  type="text"
                  value={formData.id_document_number}
                  onChange={(e) => handleInputChange('id_document_number', e.target.value)}
                  className="w-full h-10 rounded-lg border border-border bg-background px-3 text-foreground"
                  placeholder="Enter document number"
                />
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-foreground mb-1">Issue Date *</label>
                  <input
                    type="date"
                    value={formData.id_document_issue_date}
                    onChange={(e) => handleInputChange('id_document_issue_date', e.target.value)}
                    className="w-full h-10 rounded-lg border border-border bg-background px-3 text-foreground"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-foreground mb-1">Expiry Date *</label>
                  <input
                    type="date"
                    value={formData.id_document_expiry_date}
                    onChange={(e) => handleInputChange('id_document_expiry_date', e.target.value)}
                    className="w-full h-10 rounded-lg border border-border bg-background px-3 text-foreground"
                  />
                </div>
              </div>

              {/* File Uploads */}
              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-foreground mb-2">ID Document Front *</label>
                  <div className="border-2 border-dashed border-border rounded-lg p-4">
                    <input
                      type="file"
                      accept="image/*,.pdf"
                      onChange={(e) => e.target.files?.[0] && handleFileUpload('id_document_front', e.target.files[0])}
                      className="hidden"
                      id="id_front"
                    />
                    <label htmlFor="id_front" className="cursor-pointer">
                      <div className="flex flex-col items-center">
                        {uploadedUrls.id_document_front_url ? (
                          <div className="relative">
                            <img src={uploadedUrls.id_document_front_url} alt="ID Front" className="h-20 w-20 object-cover rounded" />
                            <CheckCircle className="absolute -top-2 -right-2 h-6 w-6 text-green-600" />
                          </div>
                        ) : (
                          <>
                            <Upload className="h-8 w-8 text-muted-foreground mb-2" />
                            <p className="text-sm text-muted-foreground">Click to upload ID front</p>
                          </>
                        )}
                      </div>
                    </label>
                  </div>
                </div>

                <div>
                  <label className="block text-sm font-medium text-foreground mb-2">ID Document Back</label>
                  <div className="border-2 border-dashed border-border rounded-lg p-4">
                    <input
                      type="file"
                      accept="image/*,.pdf"
                      onChange={(e) => e.target.files?.[0] && handleFileUpload('id_document_back', e.target.files[0])}
                      className="hidden"
                      id="id_back"
                    />
                    <label htmlFor="id_back" className="cursor-pointer">
                      <div className="flex flex-col items-center">
                        {uploadedUrls.id_document_back_url ? (
                          <div className="relative">
                            <img src={uploadedUrls.id_document_back_url} alt="ID Back" className="h-20 w-20 object-cover rounded" />
                            <CheckCircle className="absolute -top-2 -right-2 h-6 w-6 text-green-600" />
                          </div>
                        ) : (
                          <>
                            <Upload className="h-8 w-8 text-muted-foreground mb-2" />
                            <p className="text-sm text-muted-foreground">Click to upload ID back (if applicable)</p>
                          </>
                        )}
                      </div>
                    </label>
                  </div>
                </div>

                <div>
                  <label className="block text-sm font-medium text-foreground mb-2">Selfie Photo *</label>
                  <div className="border-2 border-dashed border-border rounded-lg p-4">
                    <input
                      type="file"
                      accept="image/*"
                      onChange={(e) => e.target.files?.[0] && handleFileUpload('selfie', e.target.files[0])}
                      className="hidden"
                      id="selfie"
                    />
                    <label htmlFor="selfie" className="cursor-pointer">
                      <div className="flex flex-col items-center">
                        {uploadedUrls.selfie_url ? (
                          <div className="relative">
                            <img src={uploadedUrls.selfie_url} alt="Selfie" className="h-20 w-20 object-cover rounded" />
                            <CheckCircle className="absolute -top-2 -right-2 h-6 w-6 text-green-600" />
                          </div>
                        ) : (
                          <>
                            <Camera className="h-8 w-8 text-muted-foreground mb-2" />
                            <p className="text-sm text-muted-foreground">Click to upload selfie photo</p>
                          </>
                        )}
                      </div>
                    </label>
                  </div>
                </div>

                <div>
                  <label className="block text-sm font-medium text-foreground mb-2">Proof of Address</label>
                  <div className="border-2 border-dashed border-border rounded-lg p-4">
                    <input
                      type="file"
                      accept="image/*,.pdf"
                      onChange={(e) => e.target.files?.[0] && handleFileUpload('proof_of_address', e.target.files[0])}
                      className="hidden"
                      id="proof_of_address"
                    />
                    <label htmlFor="proof_of_address" className="cursor-pointer">
                      <div className="flex flex-col items-center">
                        {uploadedUrls.proof_of_address_url ? (
                          <div className="relative">
                            <img src={uploadedUrls.proof_of_address_url} alt="Proof of Address" className="h-20 w-20 object-cover rounded" />
                            <CheckCircle className="absolute -top-2 -right-2 h-6 w-6 text-green-600" />
                          </div>
                        ) : (
                          <>
                            <Upload className="h-8 w-8 text-muted-foreground mb-2" />
                            <p className="text-sm text-muted-foreground">Click to upload proof of address</p>
                            <p className="text-xs text-muted-foreground mt-1">Utility bill, bank statement, etc.</p>
                          </>
                        )}
                      </div>
                    </label>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <Button 
            onClick={handleSubmit}
            disabled={loading || uploading}
            className="w-full bg-paypal-blue hover:bg-[#004dc5] h-12"
          >
            {loading ? (
              <>
                <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                Submitting Application...
              </>
            ) : (
              'Submit KYC Application'
            )}
          </Button>
        </div>
      </div>
      <BottomNav active="menu" />
    </div>
  );
};

export default KycPage;
