-- Pi Network A2U Withdrawal Tracking Schema
-- This SQL file creates the necessary tables for tracking Pi Network withdrawals

-- Create pi_withdrawals table to track all A2U withdrawals
CREATE TABLE IF NOT EXISTS pi_withdrawals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_uid UUID NOT NULL,
    amount DECIMAL(20, 8) NOT NULL CHECK (amount > 0),
    memo TEXT NOT NULL,
    metadata JSONB DEFAULT '{}',
    payment_id TEXT UNIQUE NOT NULL,
    txid TEXT,
    status TEXT NOT NULL CHECK (status IN ('pending', 'submitted', 'completed', 'failed', 'cancelled')) DEFAULT 'pending',
    from_address TEXT,
    to_address TEXT,
    direction TEXT NOT NULL DEFAULT 'app_to_user',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    network TEXT NOT NULL DEFAULT 'Pi Network' CHECK (network IN ('Pi Network', 'Pi Testnet')),
    transaction_verified BOOLEAN DEFAULT FALSE,
    developer_completed BOOLEAN DEFAULT FALSE,
    
    -- Constraints
    CONSTRAINT pi_withdrawals_user_uid_fkey FOREIGN KEY (user_uid) REFERENCES auth.users(id) ON DELETE CASCADE
);

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_pi_withdrawals_user_uid ON pi_withdrawals(user_uid);
CREATE INDEX IF NOT EXISTS idx_pi_withdrawals_payment_id ON pi_withdrawals(payment_id);
CREATE INDEX IF NOT EXISTS idx_pi_withdrawals_status ON pi_withdrawals(status);
CREATE INDEX IF NOT EXISTS idx_pi_withdrawals_created_at ON pi_withdrawals(created_at DESC);

-- Create or update function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create trigger to automatically update updated_at
CREATE TRIGGER update_pi_withdrawals_updated_at
    BEFORE UPDATE ON pi_withdrawals
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Create user_balances table if it doesn't exist (for balance checking)
CREATE TABLE IF NOT EXISTS user_balances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_uid UUID UNIQUE NOT NULL,
    pi_balance DECIMAL(20, 8) DEFAULT 0 CHECK (pi_balance >= 0),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT user_balances_user_uid_fkey FOREIGN KEY (user_uid) REFERENCES auth.users(id) ON DELETE CASCADE
);

-- Create index for user_balances
CREATE INDEX IF NOT EXISTS idx_user_balances_user_uid ON user_balances(user_uid);

-- Create trigger for user_balances updated_at
CREATE TRIGGER update_user_balances_updated_at
    BEFORE UPDATE ON user_balances
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Create pi_withdrawal_audit table for audit trail
CREATE TABLE IF NOT EXISTS pi_withdrawal_audit (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    withdrawal_id UUID NOT NULL REFERENCES pi_withdrawals(id) ON DELETE CASCADE,
    action TEXT NOT NULL CHECK (action IN ('created', 'submitted', 'completed', 'failed', 'cancelled', 'updated')),
    old_status TEXT,
    new_status TEXT,
    changes JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by TEXT NOT NULL -- user_uid or system
);

-- Create index for audit table
CREATE INDEX IF NOT EXISTS idx_pi_withdrawal_audit_withdrawal_id ON pi_withdrawal_audit(withdrawal_id);
CREATE INDEX IF NOT EXISTS idx_pi_withdrawal_audit_created_at ON pi_withdrawal_audit(created_at DESC);

-- Create function to log audit changes
CREATE OR REPLACE FUNCTION log_withdrawal_audit()
RETURNS TRIGGER AS $$
BEGIN
    -- Log the change
    INSERT INTO pi_withdrawal_audit (
        withdrawal_id,
        action,
        old_status,
        new_status,
        changes,
        created_by
    ) VALUES (
        NEW.id,
        CASE 
            WHEN TG_OP = 'INSERT' THEN 'created'
            WHEN TG_OP = 'UPDATE' THEN 
                CASE 
                    WHEN OLD.status != NEW.status THEN 'updated'
                    ELSE 'updated'
                END
            WHEN TG_OP = 'DELETE' THEN 'cancelled'
            ELSE 'unknown'
        END,
        OLD.status,
        NEW.status,
        row_to_json(NEW) - row_to_json(OLD),
        COALESCE(NEW.user_uid, 'system')
    );
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Create triggers for audit logging
CREATE TRIGGER pi_withdrawals_audit_trigger
    AFTER INSERT OR UPDATE OR DELETE ON pi_withdrawals
    FOR EACH ROW
    EXECUTE FUNCTION log_withdrawal_audit();

-- Enable Row Level Security (RLS) for all tables
ALTER TABLE pi_withdrawals ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE pi_withdrawal_audit ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for pi_withdrawals
CREATE POLICY "Users can view their own withdrawals" ON pi_withdrawals
    FOR SELECT USING (auth.uid() = user_uid);

CREATE POLICY "Users can insert their own withdrawals" ON pi_withdrawals
    FOR INSERT WITH CHECK (auth.uid() = user_uid);

CREATE POLICY "Service can update withdrawals" ON pi_withdrawals
    FOR UPDATE USING (true);

-- Create RLS policies for user_balances
CREATE POLICY "Users can view their own balance" ON user_balances
    FOR SELECT USING (auth.uid() = user_uid);

CREATE POLICY "Service can manage balances" ON user_balances
    FOR ALL USING (true);

-- Create RLS policies for audit table
CREATE POLICY "Users can view their own audit records" ON pi_withdrawal_audit
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM pi_withdrawals 
            WHERE pi_withdrawals.id = pi_withdrawal_audit.withdrawal_id 
            AND pi_withdrawals.user_uid = auth.uid()
        )
    );

-- Create function to get user withdrawal statistics
CREATE OR REPLACE FUNCTION get_user_withdrawal_stats(p_user_uid UUID)
RETURNS TABLE (
    total_withdrawals BIGINT,
    total_amount DECIMAL(20, 8),
    successful_withdrawals BIGINT,
    successful_amount DECIMAL(20, 8),
    pending_withdrawals BIGINT,
    pending_amount DECIMAL(20, 8),
    failed_withdrawals BIGINT,
    failed_amount DECIMAL(20, 8)
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(*)::BIGINT as total_withdrawals,
        COALESCE(SUM(amount), 0) as total_amount,
        COUNT(*) FILTER (WHERE status = 'completed')::BIGINT as successful_withdrawals,
        COALESCE(SUM(amount) FILTER (WHERE status = 'completed'), 0) as successful_amount,
        COUNT(*) FILTER (WHERE status = 'pending' OR status = 'submitted')::BIGINT as pending_withdrawals,
        COALESCE(SUM(amount) FILTER (WHERE status = 'pending' OR status = 'submitted'), 0) as pending_amount,
        COUNT(*) FILTER (WHERE status = 'failed' OR status = 'cancelled')::BIGINT as failed_withdrawals,
        COALESCE(SUM(amount) FILTER (WHERE status = 'failed' OR status = 'cancelled'), 0) as failed_amount
    FROM pi_withdrawals
    WHERE user_uid = p_user_uid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create function to check if user can make withdrawal
CREATE OR REPLACE FUNCTION can_user_withdraw(p_user_uid UUID, p_amount DECIMAL(20, 8))
RETURNS BOOLEAN AS $$
DECLARE
    current_balance DECIMAL(20, 8);
    pending_amount DECIMAL(20, 8);
BEGIN
    -- Get current balance
    SELECT pi_balance INTO current_balance
    FROM user_balances
    WHERE user_uid = p_user_uid;
    
    -- If no balance record, return false
    IF current_balance IS NULL THEN
        RETURN FALSE;
    END IF;
    
    -- Get pending withdrawal amount
    SELECT COALESCE(SUM(amount), 0) INTO pending_amount
    FROM pi_withdrawals
    WHERE user_uid = p_user_uid 
    AND status IN ('pending', 'submitted');
    
    -- Check if user has sufficient balance considering pending withdrawals
    RETURN (current_balance - pending_amount) >= p_amount;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant necessary permissions
GRANT EXECUTE ON FUNCTION get_user_withdrawal_stats(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION can_user_withdraw(UUID, DECIMAL) TO authenticated;
GRANT EXECUTE ON FUNCTION update_updated_at_column() TO authenticated;
GRANT EXECUTE ON FUNCTION log_withdrawal_audit() TO authenticated;
