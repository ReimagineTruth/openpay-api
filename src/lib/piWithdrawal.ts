import PiNetwork from 'pi-backend';
import { supabase } from '@/integrations/supabase/client';
import { PiSDKConfig, initializePiSDKWarnings } from './piSDKConfig';

export interface PiWithdrawalRequest {
  amount: number;
  memo: string;
  metadata?: Record<string, unknown>;
  userUid: string;
}

export interface PiWithdrawalResult {
  success: boolean;
  paymentId?: string;
  txid?: string;
  error?: string;
  completedPayment?: any;
}

export interface PiWithdrawalRecord {
  id: string;
  user_uid: string;
  amount: number;
  memo: string;
  metadata: Record<string, unknown>;
  payment_id: string;
  txid?: string;
  status: 'pending' | 'submitted' | 'completed' | 'failed' | 'cancelled';
  from_address: string;
  to_address: string;
  direction: 'app_to_user';
  created_at: string;
  network: 'Pi Network' | 'Pi Testnet';
  transaction_verified: boolean;
  developer_completed: boolean;
}

class PiWithdrawalService {
  private pi: PiNetwork | null = null;
  private isInitialized = false;

  constructor() {
    this.initializePiNetwork();
  }

  private initializePiNetwork() {
    try {
      console.log('=== Starting Pi Network Service Initialization ===');
      
      // Initialize Pi SDK warning suppression
      const cleanupWarnings = initializePiSDKWarnings();
      
      // Get Pi Network credentials from environment
      // Note: In production, these should be stored securely on the backend
      const apiKey = PiSDKConfig.api.key;
      const walletPrivateSeed = PiSDKConfig.wallet.privateSeed;

      console.log('API Key available:', !!apiKey);
      console.log('Wallet Seed available:', !!walletPrivateSeed);
      console.log('API Key length:', apiKey?.length || 0);
      console.log('Wallet Seed length:', walletPrivateSeed?.length || 0);

      if (!apiKey || !walletPrivateSeed) {
        console.error('Pi Network credentials not found in environment variables');
        this.isInitialized = false;
        return;
      }

      console.log('Creating PiNetwork instance...');
      // pi-backend is a backend service, doesn't need frontend Pi SDK
      this.pi = new PiNetwork(apiKey, walletPrivateSeed);
      console.log('PiNetwork instance created successfully');
      
      this.isInitialized = true;
      console.log('✅ Pi Network withdrawal service initialized successfully');
      console.log('=== Pi Network Service Initialization Complete ===');
      
      // Cleanup warning suppression
      cleanupWarnings();
    } catch (error) {
      console.error('❌ Failed to initialize Pi Network:', error);
      console.error('Error type:', typeof error);
      console.error('Error name:', error instanceof Error ? error.name : 'Unknown');
      console.error('Error message:', error instanceof Error ? error.message : String(error));
      console.error('Error stack:', error instanceof Error ? error.stack : 'No stack trace');
      this.isInitialized = false;
    }
  }

  private async ensureInitialized(): Promise<boolean> {
    if (!this.isInitialized) {
      // Try to reinitialize if it failed before
      this.initializePiNetwork();
    }
    return this.isInitialized && this.pi !== null;
  }

  /**
   * Create a new A2U withdrawal payment
   */
  async createWithdrawal(request: PiWithdrawalRequest): Promise<PiWithdrawalResult> {
    try {
      const isReady = await this.ensureInitialized();
      if (!isReady || !this.pi) {
        return {
          success: false,
          error: 'Pi Network service not initialized'
        };
      }

      // Validate amount
      if (request.amount <= 0) {
        return {
          success: false,
          error: 'Amount must be greater than 0'
        };
      }

      // Check if user has sufficient balance (optional - depends on your business logic)
      const hasBalance = await this.checkUserBalance(request.userUid, request.amount);
      if (!hasBalance) {
        return {
          success: false,
          error: 'Insufficient balance'
        };
      }

      // Create payment in Pi Network - validate payment data structure
      const paymentData = {
        amount: request.amount,
        memo: request.memo || `A2U Withdrawal - ${new Date().toISOString()}`,
        metadata: {
          ...request.metadata,
          type: 'a2u_withdrawal',
          timestamp: new Date().toISOString(),
          user_uid: request.userUid
        },
        uid: request.userUid
      };

      // Validate payment data according to Pi SDK requirements
      if (!paymentData.amount || paymentData.amount <= 0) {
        return {
          success: false,
          error: 'Invalid payment amount'
        };
      }

      if (!paymentData.uid || typeof paymentData.uid !== 'string') {
        return {
          success: false,
          error: 'Invalid user UID'
        };
      }

      if (!paymentData.memo || typeof paymentData.memo !== 'string') {
        return {
          success: false,
          error: 'Invalid payment memo'
        };
      }

      const paymentId = await this.pi.createPayment(paymentData);

      // Store withdrawal record in database
      await this.storeWithdrawalRecord({
        id: crypto.randomUUID(),
        user_uid: request.userUid,
        amount: request.amount,
        memo: paymentData.memo,
        metadata: paymentData.metadata,
        payment_id: paymentId,
        status: 'pending',
        from_address: '',
        to_address: '',
        direction: 'app_to_user',
        created_at: new Date().toISOString(),
        network: 'Pi Network',
        transaction_verified: false,
        developer_completed: false
      });

      return {
        success: true,
        paymentId
      };

    } catch (error) {
      console.error('Error creating withdrawal:', error);
      
      // Handle specific Pi Network errors
      const errorMessage = error instanceof Error ? error.message : String(error);
      
      if (errorMessage.includes('You need to complete the ongoing payment first')) {
        return {
          success: false,
          error: 'Please complete any pending payments before creating a new withdrawal'
        };
      }
      
      if (errorMessage.includes('insufficient')) {
        return {
          success: false,
          error: 'Insufficient balance for this withdrawal'
        };
      }
      
      if (errorMessage.includes('unauthorized') || errorMessage.includes('authentication')) {
        return {
          success: false,
          error: 'Authentication failed. Please check your Pi Network credentials'
        };
      }
      
      return {
        success: false,
        error: errorMessage || 'Unknown error occurred'
      };
    }
  }

  /**
   * Submit the withdrawal payment to Pi Blockchain
   */
  async submitWithdrawal(paymentId: string): Promise<PiWithdrawalResult> {
    try {
      const isReady = await this.ensureInitialized();
      if (!isReady || !this.pi) {
        return {
          success: false,
          error: 'Pi Network service not initialized'
        };
      }

      const txid = await this.pi.submitPayment(paymentId);

      // Update withdrawal record with txid
      await this.updateWithdrawalRecord(paymentId, {
        txid,
        status: 'submitted'
      });

      return {
        success: true,
        paymentId,
        txid
      };

    } catch (error) {
      console.error('Error submitting withdrawal:', error);
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error occurred'
      };
    }
  }

  /**
   * Complete the withdrawal payment
   */
  async completeWithdrawal(paymentId: string, txid: string): Promise<PiWithdrawalResult> {
    try {
      const isReady = await this.ensureInitialized();
      if (!isReady || !this.pi) {
        return {
          success: false,
          error: 'Pi Network service not initialized'
        };
      }

      const completedPayment = await this.pi.completePayment(paymentId, txid);

      // Validate the completed payment structure according to Pi SDK documentation
      if (!completedPayment) {
        throw new Error('No payment data returned from completePayment');
      }

      // Check payment status fields
      if (!completedPayment.status) {
        console.warn('Payment status object is missing');
      }

      // Update withdrawal record with completion status
      await this.updateWithdrawalRecord(paymentId, {
        status: completedPayment.status?.developer_completed ? 'completed' : 'pending',
        transaction_verified: completedPayment.transaction?.verified || false,
        developer_completed: completedPayment.status?.developer_completed || false,
        from_address: completedPayment.from_address || '',
        to_address: completedPayment.to_address || ''
      });

      // Log payment completion details for debugging
      console.log('Payment completed successfully:', {
        paymentId,
        txid,
        status: completedPayment.status,
        transactionVerified: completedPayment.transaction?.verified,
        fromAddress: completedPayment.from_address,
        toAddress: completedPayment.to_address
      });

      return {
        success: true,
        paymentId,
        txid,
        completedPayment
      };

    } catch (error) {
      console.error('Error completing withdrawal:', error);
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error occurred'
      };
    }
  }

  /**
   * Get complete withdrawal flow (create, submit, complete)
   */
  async processCompleteWithdrawal(request: PiWithdrawalRequest): Promise<PiWithdrawalResult> {
    try {
      // Step 1: Create withdrawal
      const createResult = await this.createWithdrawal(request);
      if (!createResult.success || !createResult.paymentId) {
        return createResult;
      }

      // Step 2: Submit to blockchain
      const submitResult = await this.submitWithdrawal(createResult.paymentId);
      if (!submitResult.success || !submitResult.txid) {
        return submitResult;
      }

      // Step 3: Complete payment
      const completeResult = await this.completeWithdrawal(createResult.paymentId, submitResult.txid);
      return completeResult;

    } catch (error) {
      console.error('Error in complete withdrawal flow:', error);
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error occurred'
      };
    }
  }

  /**
   * Get withdrawal status
   */
  async getWithdrawalStatus(paymentId: string): Promise<PiWithdrawalResult> {
    try {
      const isReady = await this.ensureInitialized();
      if (!isReady || !this.pi) {
        return {
          success: false,
          error: 'Pi Network service not initialized'
        };
      }

      const payment = await this.pi.getPayment(paymentId);
      
      return {
        success: true,
        completedPayment: payment
      };

    } catch (error) {
      console.error('Error getting withdrawal status:', error);
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error occurred'
      };
    }
  }

  /**
   * Cancel withdrawal
   */
  async cancelWithdrawal(paymentId: string): Promise<PiWithdrawalResult> {
    try {
      const isReady = await this.ensureInitialized();
      if (!isReady || !this.pi) {
        return {
          success: false,
          error: 'Pi Network service not initialized'
        };
      }

      const cancelledPayment = await this.pi.cancelPayment(paymentId);

      // Update withdrawal record
      await this.updateWithdrawalRecord(paymentId, {
        status: 'cancelled'
      });

      return {
        success: true,
        completedPayment: cancelledPayment
      };

    } catch (error) {
      console.error('Error cancelling withdrawal:', error);
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error occurred'
      };
    }
  }

  /**
   * Get user's withdrawal history
   */
  async getUserWithdrawalHistory(userUid: string): Promise<PiWithdrawalRecord[]> {
    try {
      const { data, error } = await supabase
        .from('pi_withdrawals' as any)
        .select('*')
        .eq('user_uid', userUid)
        .order('created_at', { ascending: false });

      if (error) {
        console.error('Error fetching withdrawal history:', error);
        return [];
      }

      return (data as unknown as PiWithdrawalRecord[]) || [];
    } catch (error) {
      console.error('Error fetching withdrawal history:', error);
      return [];
    }
  }

  private async storeWithdrawalRecord(record: PiWithdrawalRecord): Promise<void> {
    try {
      const { error } = await supabase
        .from('pi_withdrawals' as any)
        .insert(record);

      if (error) {
        console.error('Error storing withdrawal record:', error);
      }
    } catch (error) {
      console.error('Error storing withdrawal record:', error);
    }
  }

  private async updateWithdrawalRecord(paymentId: string, updates: Partial<PiWithdrawalRecord>): Promise<void> {
    try {
      const { error } = await supabase
        .from('pi_withdrawals' as any)
        .update(updates)
        .eq('payment_id', paymentId);

      if (error) {
        console.error('Error updating withdrawal record:', error);
      }
    } catch (error) {
      console.error('Error updating withdrawal record:', error);
    }
  }

  private async checkUserBalance(userUid: string, amount: number): Promise<boolean> {
    // Check user's actual balance from the wallets table
    try {
      const { data, error } = await supabase
        .from('wallets' as any)
        .select('balance')
        .eq('user_id', userUid)
        .single();

      if (error || !data) {
        console.error('Error checking user balance:', error);
        // If wallet not found, check if we have a default balance to use
        console.log('Balance table not found, using default balance:', error);
        return false; // Don't allow withdrawal if balance can't be verified
      }

      const currentBalance = (data as any).balance || 0;
      console.log(`Current balance: ${currentBalance}, Requested amount: ${amount}`);
      return currentBalance >= amount;
    } catch (error) {
      console.error('Error checking user balance:', error);
      return false;
    }
  }
}

// Export singleton instance
export const piWithdrawalService = new PiWithdrawalService();
