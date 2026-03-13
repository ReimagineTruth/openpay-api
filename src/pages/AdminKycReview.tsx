import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { ArrowLeft, CheckCircle, XCircle, AlertCircle, Eye, Download, FileText, User, Calendar, Shield, Search, Filter, ChevronDown, Loader2, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { toast } from "sonner";
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

const AdminKycReview = () => {
  const navigate = useNavigate();
  const [applications, setApplications] = useState<KycApplication[]>([]);
  const [selectedApplication, setSelectedApplication] = useState<KycApplication | null>(null);
  const [loading, setLoading] = useState(false);
  const [actionLoading, setActionLoading] = useState(false);
  const [searchTerm, setSearchTerm] = useState("");
  const [statusFilter, setStatusFilter] = useState<string>("all");
  const [showRejectionModal, setShowRejectionModal] = useState(false);
  const [rejectionReason, setRejectionReason] = useState("");
  const [adminNotes, setAdminNotes] = useState("");

  useEffect(() => {
    loadApplications();
  }, []);

  const loadApplications = async () => {
    setLoading(true);
    try {
      // For now, we'll use mock data since the table doesn't exist yet
      // This will be updated after we create the database schema
      const mockApplications: KycApplication[] = [
        {
          id: "1",
          user_id: "user1",
          full_name: "John Doe",
          date_of_birth: "1990-01-01",
          nationality: "US",
          residential_address: "123 Main St, New York, NY 10001",
          phone_number: "+1 234 567 8900",
          email: "john.doe@example.com",
          occupation: "Software Engineer",
          employer_name: "Tech Corp",
          source_of_funds: "employment",
          annual_income_range: "100000-250000",
          political_exposure: false,
          id_document_type: "passport",
          id_document_number: "US123456789",
          id_document_issue_date: "2020-01-01",
          id_document_expiry_date: "2030-01-01",
          id_document_front_url: "https://example.com/id-front.jpg",
          id_document_back_url: "https://example.com/id-back.jpg",
          selfie_url: "https://example.com/selfie.jpg",
          proof_of_address_url: "https://example.com/address-proof.jpg",
          status: "pending",
          submitted_at: "2024-01-15T10:00:00Z",
        },
        {
          id: "2",
          user_id: "user2",
          full_name: "Jane Smith",
          date_of_birth: "1985-05-15",
          nationality: "UK",
          residential_address: "456 Oak Ave, London, UK",
          phone_number: "+44 20 1234 5678",
          email: "jane.smith@example.com",
          occupation: "Marketing Manager",
          employer_name: "Marketing Ltd",
          source_of_funds: "employment",
          annual_income_range: "50000-100000",
          political_exposure: false,
          id_document_type: "national_id",
          id_document_number: "UK987654321",
          id_document_issue_date: "2018-06-01",
          id_document_expiry_date: "2028-06-01",
          id_document_front_url: "https://example.com/id-front.jpg",
          id_document_back_url: "https://example.com/id-back.jpg",
          selfie_url: "https://example.com/selfie.jpg",
          proof_of_address_url: "https://example.com/address-proof.jpg",
          status: "under_review",
          submitted_at: "2024-01-14T15:30:00Z",
        },
      ];

      setApplications(mockApplications);
    } catch (error) {
      console.error('Error loading applications:', error);
      toast.error('Failed to load KYC applications');
    } finally {
      setLoading(false);
    }
  };

  const handleApprove = async (applicationId: string) => {
    setActionLoading(true);
    try {
      // For now, we'll just update the local state
      // This will be updated after we create the database schema
      setApplications(prev => prev.map(app => 
        app.id === applicationId 
          ? { ...app, status: 'approved', reviewed_at: new Date().toISOString(), reviewed_by: 'admin' }
          : app
      ));
      
      toast.success('KYC application approved successfully');
      setSelectedApplication(null);
    } catch (error) {
      console.error('Error approving application:', error);
      toast.error('Failed to approve application');
    } finally {
      setActionLoading(false);
    }
  };

  const handleReject = async () => {
    if (!rejectionReason.trim()) {
      toast.error('Please provide a rejection reason');
      return;
    }

    setActionLoading(true);
    try {
      // For now, we'll just update the local state
      // This will be updated after we create the database schema
      if (selectedApplication) {
        setApplications(prev => prev.map(app => 
          app.id === selectedApplication.id 
            ? { 
                ...app, 
                status: 'rejected', 
                rejection_reason: rejectionReason,
                admin_notes: adminNotes,
                reviewed_at: new Date().toISOString(), 
                reviewed_by: 'admin' 
              }
            : app
        ));
      }
      
      toast.success('KYC application rejected');
      setShowRejectionModal(false);
      setRejectionReason("");
      setAdminNotes("");
      setSelectedApplication(null);
    } catch (error) {
      console.error('Error rejecting application:', error);
      toast.error('Failed to reject application');
    } finally {
      setActionLoading(false);
    }
  };

  const handleRequestAdditionalInfo = async (applicationId: string) => {
    setActionLoading(true);
    try {
      // For now, we'll just update the local state
      // This will be updated after we create the database schema
      setApplications(prev => prev.map(app => 
        app.id === applicationId 
          ? { ...app, status: 'additional_info_required', reviewed_at: new Date().toISOString(), reviewed_by: 'admin' }
          : app
      ));
      
      toast.success('Additional information requested');
    } catch (error) {
      console.error('Error requesting additional info:', error);
      toast.error('Failed to request additional information');
    } finally {
      setActionLoading(false);
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'approved': return 'bg-green-100 text-green-800';
      case 'rejected': return 'bg-red-100 text-red-800';
      case 'under_review': return 'bg-blue-100 text-blue-800';
      case 'additional_info_required': return 'bg-orange-100 text-orange-800';
      default: return 'bg-gray-100 text-gray-800';
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'approved': return <CheckCircle className="h-4 w-4" />;
      case 'rejected': return <XCircle className="h-4 w-4" />;
      case 'under_review': return <Eye className="h-4 w-4" />;
      case 'additional_info_required': return <AlertCircle className="h-4 w-4" />;
      default: return <FileText className="h-4 w-4" />;
    }
  };

  const filteredApplications = applications.filter(app => {
    const matchesSearch = app.full_name.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         app.email.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         app.id_document_number.toLowerCase().includes(searchTerm.toLowerCase());
    const matchesStatus = statusFilter === 'all' || app.status === statusFilter;
    return matchesSearch && matchesStatus;
  });

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-white border-b border-gray-200">
        <div className="px-4 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <button 
                onClick={() => navigate("/admin-dashboard")}
                className="flex h-10 w-10 items-center justify-center rounded-full bg-gray-100 hover:bg-gray-200 transition-colors"
              >
                <ArrowLeft className="h-5 w-5" />
              </button>
              <div className="flex items-center gap-3">
                <BrandLogo className="h-8 w-8" />
                <div>
                  <h1 className="text-xl font-bold text-gray-900">KYC Review</h1>
                  <p className="text-sm text-gray-500">Review and manage identity verification applications</p>
                </div>
              </div>
            </div>
            <Button 
              onClick={loadApplications}
              disabled={loading}
              variant="outline"
              className="flex items-center gap-2"
            >
              <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
              Refresh
            </Button>
          </div>
        </div>
      </div>

      {/* Filters */}
      <div className="bg-white border-b border-gray-200 px-4 py-3">
        <div className="flex flex-col sm:flex-row gap-3">
          <div className="flex-1 relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-gray-400" />
            <input
              type="text"
              placeholder="Search by name, email, or ID number..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full pl-10 pr-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>
          <div className="relative">
            <select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value)}
              className="appearance-none bg-white border border-gray-300 rounded-lg px-4 py-2 pr-8 focus:outline-none focus:ring-2 focus:ring-blue-500"
            >
              <option value="all">All Status</option>
              <option value="pending">Pending</option>
              <option value="under_review">Under Review</option>
              <option value="approved">Approved</option>
              <option value="rejected">Rejected</option>
              <option value="additional_info_required">Additional Info Required</option>
            </select>
            <ChevronDown className="absolute right-2 top-1/2 transform -translate-y-1/2 h-4 w-4 text-gray-400 pointer-events-none" />
          </div>
        </div>
      </div>

      <div className="flex">
        {/* Applications List */}
        <div className={`${selectedApplication ? 'w-1/2' : 'w-full'} bg-white border-r border-gray-200`}>
          <div className="divide-y divide-gray-200">
            {loading ? (
              <div className="flex items-center justify-center py-12">
                <Loader2 className="h-8 w-8 animate-spin text-blue-600" />
                <span className="ml-2 text-gray-600">Loading applications...</span>
              </div>
            ) : filteredApplications.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-12">
                <FileText className="h-12 w-12 text-gray-400 mb-3" />
                <p className="text-gray-600">No KYC applications found</p>
              </div>
            ) : (
              filteredApplications.map((application) => (
                <div
                  key={application.id}
                  onClick={() => setSelectedApplication(application)}
                  className={`p-4 hover:bg-gray-50 cursor-pointer transition-colors ${
                    selectedApplication?.id === application.id ? 'bg-blue-50' : ''
                  }`}
                >
                  <div className="flex items-start justify-between">
                    <div className="flex-1">
                      <div className="flex items-center gap-2 mb-1">
                        <h3 className="font-semibold text-gray-900">{application.full_name}</h3>
                        <span className={`inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium ${getStatusColor(application.status)}`}>
                          {getStatusIcon(application.status)}
                          {application.status.replace('_', ' ').toUpperCase()}
                        </span>
                      </div>
                      <p className="text-sm text-gray-600">{application.email}</p>
                      <p className="text-sm text-gray-600">{application.phone_number}</p>
                      <div className="flex items-center gap-4 mt-2 text-xs text-gray-500">
                        <span>ID: {application.id_document_type}</span>
                        <span>Submitted: {new Date(application.submitted_at).toLocaleDateString()}</span>
                      </div>
                    </div>
                    <Eye className="h-5 w-5 text-gray-400" />
                  </div>
                </div>
              ))
            )}
          </div>
        </div>

        {/* Application Details */}
        {selectedApplication && (
          <div className="w-1/2 bg-white">
            <div className="border-b border-gray-200 p-4">
              <div className="flex items-center justify-between">
                <h2 className="text-lg font-semibold text-gray-900">Application Details</h2>
                <div className="flex items-center gap-2">
                  <span className={`inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium ${getStatusColor(selectedApplication.status)}`}>
                    {getStatusIcon(selectedApplication.status)}
                    {selectedApplication.status.replace('_', ' ').toUpperCase()}
                  </span>
                </div>
              </div>
            </div>

            <div className="p-4 space-y-6 max-h-[calc(100vh-200px)] overflow-y-auto">
              {/* Personal Information */}
              <div>
                <h3 className="font-semibold text-gray-900 mb-3 flex items-center gap-2">
                  <User className="h-4 w-4" />
                  Personal Information
                </h3>
                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div>
                    <p className="text-gray-600">Full Name</p>
                    <p className="font-medium">{selectedApplication.full_name}</p>
                  </div>
                  <div>
                    <p className="text-gray-600">Date of Birth</p>
                    <p className="font-medium">{selectedApplication.date_of_birth}</p>
                  </div>
                  <div>
                    <p className="text-gray-600">Nationality</p>
                    <p className="font-medium">{selectedApplication.nationality}</p>
                  </div>
                  <div>
                    <p className="text-gray-600">Phone</p>
                    <p className="font-medium">{selectedApplication.phone_number}</p>
                  </div>
                  <div className="col-span-2">
                    <p className="text-gray-600">Address</p>
                    <p className="font-medium">{selectedApplication.residential_address}</p>
                  </div>
                </div>
              </div>

              {/* Financial Information */}
              <div>
                <h3 className="font-semibold text-gray-900 mb-3 flex items-center gap-2">
                  <FileText className="h-4 w-4" />
                  Financial Information
                </h3>
                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div>
                    <p className="text-gray-600">Occupation</p>
                    <p className="font-medium">{selectedApplication.occupation}</p>
                  </div>
                  <div>
                    <p className="text-gray-600">Employer</p>
                    <p className="font-medium">{selectedApplication.employer_name || 'N/A'}</p>
                  </div>
                  <div>
                    <p className="text-gray-600">Source of Funds</p>
                    <p className="font-medium">{selectedApplication.source_of_funds}</p>
                  </div>
                  <div>
                    <p className="text-gray-600">Annual Income</p>
                    <p className="font-medium">${selectedApplication.annual_income_range}</p>
                  </div>
                  <div className="col-span-2">
                    <p className="text-gray-600">Political Exposure</p>
                    <p className="font-medium">{selectedApplication.political_exposure ? 'Yes' : 'No'}</p>
                  </div>
                </div>
              </div>

              {/* ID Documents */}
              <div>
                <h3 className="font-semibold text-gray-900 mb-3 flex items-center gap-2">
                  <Shield className="h-4 w-4" />
                  Identity Documents
                </h3>
                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div>
                    <p className="text-gray-600">Document Type</p>
                    <p className="font-medium">{selectedApplication.id_document_type}</p>
                  </div>
                  <div>
                    <p className="text-gray-600">Document Number</p>
                    <p className="font-medium">{selectedApplication.id_document_number}</p>
                  </div>
                  <div>
                    <p className="text-gray-600">Issue Date</p>
                    <p className="font-medium">{selectedApplication.id_document_issue_date}</p>
                  </div>
                  <div>
                    <p className="text-gray-600">Expiry Date</p>
                    <p className="font-medium">{selectedApplication.id_document_expiry_date}</p>
                  </div>
                </div>

                {/* Document Images */}
                <div className="grid grid-cols-2 gap-4 mt-4">
                  {selectedApplication.id_document_front_url && (
                    <div>
                      <p className="text-gray-600 text-sm mb-2">ID Front</p>
                      <div className="border border-gray-200 rounded-lg overflow-hidden">
                        <img src={selectedApplication.id_document_front_url} alt="ID Front" className="w-full h-32 object-cover" />
                      </div>
                      <Button variant="outline" size="sm" className="w-full mt-2">
                        <Download className="h-4 w-4 mr-1" />
                        Download
                      </Button>
                    </div>
                  )}
                  {selectedApplication.id_document_back_url && (
                    <div>
                      <p className="text-gray-600 text-sm mb-2">ID Back</p>
                      <div className="border border-gray-200 rounded-lg overflow-hidden">
                        <img src={selectedApplication.id_document_back_url} alt="ID Back" className="w-full h-32 object-cover" />
                      </div>
                      <Button variant="outline" size="sm" className="w-full mt-2">
                        <Download className="h-4 w-4 mr-1" />
                        Download
                      </Button>
                    </div>
                  )}
                  {selectedApplication.selfie_url && (
                    <div>
                      <p className="text-gray-600 text-sm mb-2">Selfie</p>
                      <div className="border border-gray-200 rounded-lg overflow-hidden">
                        <img src={selectedApplication.selfie_url} alt="Selfie" className="w-full h-32 object-cover" />
                      </div>
                      <Button variant="outline" size="sm" className="w-full mt-2">
                        <Download className="h-4 w-4 mr-1" />
                        Download
                      </Button>
                    </div>
                  )}
                  {selectedApplication.proof_of_address_url && (
                    <div>
                      <p className="text-gray-600 text-sm mb-2">Proof of Address</p>
                      <div className="border border-gray-200 rounded-lg overflow-hidden">
                        <img src={selectedApplication.proof_of_address_url} alt="Proof of Address" className="w-full h-32 object-cover" />
                      </div>
                      <Button variant="outline" size="sm" className="w-full mt-2">
                        <Download className="h-4 w-4 mr-1" />
                        Download
                      </Button>
                    </div>
                  )}
                </div>
              </div>

              {/* Admin Notes */}
              {selectedApplication.admin_notes && (
                <div>
                  <h3 className="font-semibold text-gray-900 mb-3">Admin Notes</h3>
                  <div className="bg-gray-50 rounded-lg p-3">
                    <p className="text-sm text-gray-700">{selectedApplication.admin_notes}</p>
                  </div>
                </div>
              )}

              {/* Rejection Reason */}
              {selectedApplication.rejection_reason && (
                <div>
                  <h3 className="font-semibold text-gray-900 mb-3">Rejection Reason</h3>
                  <div className="bg-red-50 border border-red-200 rounded-lg p-3">
                    <p className="text-sm text-red-700">{selectedApplication.rejection_reason}</p>
                  </div>
                </div>
              )}
            </div>

            {/* Action Buttons */}
            <div className="border-t border-gray-200 p-4">
              <div className="flex gap-3">
                {selectedApplication.status === 'pending' && (
                  <>
                    <Button
                      onClick={() => handleApprove(selectedApplication.id)}
                      disabled={actionLoading}
                      className="flex-1 bg-green-600 hover:bg-green-700"
                    >
                      {actionLoading ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <CheckCircle className="h-4 w-4 mr-2" />}
                      Approve
                    </Button>
                    <Button
                      onClick={() => setShowRejectionModal(true)}
                      disabled={actionLoading}
                      variant="outline"
                      className="flex-1 border-red-300 text-red-600 hover:bg-red-50"
                    >
                      {actionLoading ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <XCircle className="h-4 w-4 mr-2" />}
                      Reject
                    </Button>
                    <Button
                      onClick={() => handleRequestAdditionalInfo(selectedApplication.id)}
                      disabled={actionLoading}
                      variant="outline"
                      className="flex-1 border-orange-300 text-orange-600 hover:bg-orange-50"
                    >
                      {actionLoading ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <AlertCircle className="h-4 w-4 mr-2" />}
                      Request Info
                    </Button>
                  </>
                )}
                {selectedApplication.status === 'under_review' && (
                  <>
                    <Button
                      onClick={() => handleApprove(selectedApplication.id)}
                      disabled={actionLoading}
                      className="flex-1 bg-green-600 hover:bg-green-700"
                    >
                      {actionLoading ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <CheckCircle className="h-4 w-4 mr-2" />}
                      Approve
                    </Button>
                    <Button
                      onClick={() => setShowRejectionModal(true)}
                      disabled={actionLoading}
                      variant="outline"
                      className="flex-1 border-red-300 text-red-600 hover:bg-red-50"
                    >
                      {actionLoading ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <XCircle className="h-4 w-4 mr-2" />}
                      Reject
                    </Button>
                  </>
                )}
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Rejection Modal */}
      {showRejectionModal && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
          <div className="bg-white rounded-xl max-w-md w-full p-6">
            <h3 className="text-lg font-semibold text-gray-900 mb-4">Reject Application</h3>
            
            <div className="mb-4">
              <label className="block text-sm font-medium text-gray-700 mb-2">Rejection Reason *</label>
              <textarea
                value={rejectionReason}
                onChange={(e) => setRejectionReason(e.target.value)}
                className="w-full h-24 border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-red-500"
                placeholder="Provide a clear reason for rejection..."
              />
            </div>

            <div className="mb-6">
              <label className="block text-sm font-medium text-gray-700 mb-2">Admin Notes (Optional)</label>
              <textarea
                value={adminNotes}
                onChange={(e) => setAdminNotes(e.target.value)}
                className="w-full h-20 border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-red-500"
                placeholder="Additional notes for internal use..."
              />
            </div>

            <div className="flex gap-3">
              <Button
                onClick={() => setShowRejectionModal(false)}
                variant="outline"
                className="flex-1"
              >
                Cancel
              </Button>
              <Button
                onClick={handleReject}
                disabled={actionLoading}
                className="flex-1 bg-red-600 hover:bg-red-700"
              >
                {actionLoading ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : ''}
                Confirm Rejection
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default AdminKycReview;
