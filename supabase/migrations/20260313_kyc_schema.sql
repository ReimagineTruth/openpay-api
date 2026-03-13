-- KYC Applications Table
CREATE TABLE IF NOT EXISTS kyc_applications (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    date_of_birth DATE NOT NULL,
    nationality TEXT NOT NULL,
    residential_address TEXT NOT NULL,
    phone_number TEXT NOT NULL,
    email TEXT NOT NULL,
    occupation TEXT NOT NULL,
    employer_name TEXT,
    source_of_funds TEXT NOT NULL CHECK (source_of_funds IN ('employment', 'business', 'investments', 'inheritance', 'savings', 'other')),
    annual_income_range TEXT NOT NULL CHECK (annual_income_range IN ('0-25000', '25000-50000', '50000-100000', '100000-250000', '250000+')),
    political_exposure BOOLEAN DEFAULT FALSE,
    id_document_type TEXT NOT NULL CHECK (id_document_type IN ('passport', 'national_id', 'drivers_license', 'residence_permit')),
    id_document_number TEXT NOT NULL,
    id_document_issue_date DATE NOT NULL,
    id_document_expiry_date DATE NOT NULL,
    id_document_front_url TEXT,
    id_document_back_url TEXT,
    selfie_url TEXT,
    proof_of_address_url TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'under_review', 'approved', 'rejected', 'additional_info_required')),
    rejection_reason TEXT,
    admin_notes TEXT,
    submitted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    reviewed_by UUID REFERENCES auth.users(id),
    
    -- Constraints
    CONSTRAINT valid_date_of_birth CHECK (date_of_birth <= CURRENT_DATE - INTERVAL '18 years'),
    CONSTRAINT valid_expiry_date CHECK (id_document_expiry_date > id_document_issue_date),
    CONSTRAINT valid_review_sequence CHECK (
        (status = 'pending' AND reviewed_at IS NULL) OR
        (status IN ('under_review', 'approved', 'rejected', 'additional_info_required') AND reviewed_at IS NOT NULL)
    )
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_kyc_applications_user_id ON kyc_applications(user_id);
CREATE INDEX IF NOT EXISTS idx_kyc_applications_status ON kyc_applications(status);
CREATE INDEX IF NOT EXISTS idx_kyc_applications_submitted_at ON kyc_applications(submitted_at);
CREATE INDEX IF NOT EXISTS idx_kyc_applications_reviewed_by ON kyc_applications(reviewed_by);

-- Row Level Security (RLS)
ALTER TABLE kyc_applications ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view their own KYC applications" ON kyc_applications
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own KYC applications" ON kyc_applications
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own KYC applications (only before review)" ON kyc_applications
    FOR UPDATE USING (
        auth.uid() = user_id AND 
        status IN ('pending', 'additional_info_required')
    );

CREATE POLICY "Admin users can view all KYC applications" ON kyc_applications
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM profiles 
            WHERE profiles.id = auth.uid() 
            AND profiles.username IN ('openpay', 'wainfoundation')
        )
    );

CREATE POLICY "Admin users can update KYC applications" ON kyc_applications
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM profiles 
            WHERE profiles.id = auth.uid() 
            AND profiles.username IN ('openpay', 'wainfoundation')
        )
    );

-- Storage bucket for KYC documents
INSERT INTO storage.buckets (id, name, public)
VALUES ('kyc-documents', 'kyc-documents', false)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for KYC documents
CREATE POLICY "Users can upload their own KYC documents" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'kyc-documents' AND
        auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Users can view their own KYC documents" ON storage.objects
    FOR SELECT USING (
        bucket_id = 'kyc-documents' AND
        auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Admin users can view all KYC documents" ON storage.objects
    FOR SELECT USING (
        bucket_id = 'kyc-documents' AND
        EXISTS (
            SELECT 1 FROM profiles 
            WHERE profiles.id = auth.uid() 
            AND profiles.username IN ('openpay', 'wainfoundation')
        )
    );

-- Function to get KYC status for user
CREATE OR REPLACE FUNCTION get_user_kyc_status(user_uuid UUID)
RETURNS TABLE (
    id UUID,
    status TEXT,
    submitted_at TIMESTAMP WITH TIME ZONE,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    rejection_reason TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ka.id,
        ka.status,
        ka.submitted_at,
        ka.reviewed_at,
        ka.rejection_reason
    FROM kyc_applications ka
    WHERE ka.user_id = user_uuid
    ORDER BY ka.submitted_at DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function for admin to update KYC status
CREATE OR REPLACE FUNCTION update_kyc_status(
    application_id UUID,
    new_status TEXT,
    rejection_reason_text TEXT DEFAULT NULL,
    admin_notes_text TEXT DEFAULT NULL
)
RETURNS TABLE (
    success BOOLEAN,
    message TEXT
) AS $$
DECLARE
    current_user_id UUID := auth.uid();
    is_admin BOOLEAN;
    app_record kyc_applications%ROWTYPE;
BEGIN
    -- Check if user is admin
    SELECT EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = current_user_id 
        AND profiles.username IN ('openpay', 'wainfoundation')
    ) INTO is_admin;
    
    IF NOT is_admin THEN
        RETURN QUERY SELECT FALSE, 'Unauthorized: Admin access required';
        RETURN;
    END IF;
    
    -- Get current application
    SELECT * INTO app_record FROM kyc_applications WHERE id = application_id;
    
    IF app_record IS NULL THEN
        RETURN QUERY SELECT FALSE, 'Application not found';
        RETURN;
    END IF;
    
    -- Validate status transition
    IF new_status NOT IN ('pending', 'under_review', 'approved', 'rejected', 'additional_info_required') THEN
        RETURN QUERY SELECT FALSE, 'Invalid status';
        RETURN;
    END IF;
    
    -- If rejecting, require rejection reason
    IF new_status = 'rejected' AND rejection_reason_text IS NULL OR rejection_reason_text = '' THEN
        RETURN QUERY SELECT FALSE, 'Rejection reason is required';
        RETURN;
    END IF;
    
    -- Update application
    UPDATE kyc_applications SET
        status = new_status,
        rejection_reason = rejection_reason_text,
        admin_notes = admin_notes_text,
        reviewed_at = NOW(),
        reviewed_by = current_user_id
    WHERE id = application_id;
    
    RETURN QUERY SELECT TRUE, 'KYC status updated successfully';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to update user profile KYC status
CREATE OR REPLACE FUNCTION update_user_kyc_status()
RETURNS TRIGGER AS $$
BEGIN
    -- Update user profile with latest KYC status
    UPDATE profiles SET
        kyc_status = NEW.status,
        kyc_verified_at = CASE 
            WHEN NEW.status = 'approved' THEN NEW.reviewed_at 
            ELSE profiles.kyc_verified_at 
        END
    WHERE id = NEW.user_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_user_kyc_status_trigger
    AFTER UPDATE ON kyc_applications
    FOR EACH ROW
    EXECUTE FUNCTION update_user_kyc_status();

-- Add KYC status to profiles table if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'profiles' 
        AND column_name = 'kyc_status'
    ) THEN
        ALTER TABLE profiles ADD COLUMN kyc_status TEXT DEFAULT 'not_submitted';
        ALTER TABLE profiles ADD COLUMN kyc_verified_at TIMESTAMP WITH TIME ZONE;
    END IF;
END $$;
