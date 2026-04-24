import PiNetwork from 'pi-backend';
import { supabase } from '@/integrations/supabase/client';

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

  private async initializePiNetwork() {
    try {
      // Get Pi Network credentials from environment
      // Note: In production, these should be stored securely on the backend
      const apiKey = import.meta.env.VITE_PI_API_KEY || "fudrvmlzm7ucqu94smlgeudrryccqxpymkr1vqk6nw0yoli8ikirbzrn9siv4hi9";
      const walletPrivateSeed = import.meta.env.VITE_PI_WALLET_PRIVATE_SEED || "SDZWK2Z4JA3KTQIGAEUSKWFLZBDILJAWLUNAUFHURFIF5BWNNH3PB5Y3";

      if (!apiKey || !walletPrivateSeed) {
        console.error('Pi Network credentials not found in environment variables');
        return;
      }

      this.pi = new PiNetwork(apiKey, walletPrivateSeed);
      this.isInitialized = true;
      console.log('Pi Network withdrawal service initialized successfully');
    } catch (error) {
      console.error('Failed to initialize Pi Network:', error);
      this.isInitialized = false;
    }
  }

  private async ensureInitialized(): Promise<boolean> {
    if (!this.isInitialized) {
      await this.initializePiNetwork();
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

      // Create payment in Pi Network
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
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error occurred'
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

      // Update withdrawal record with completion status
      await this.updateWithdrawalRecord(paymentId, {
        status: 'completed',
        transaction_verified: completedPayment.transaction?.verified || false,
        developer_completed: completedPayment.status.developer_completed,
        from_address: completedPayment.from_address,
        to_address: completedPayment.to_address
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
    // This is a placeholder implementation
    // In a real application, you would check the user's actual balance
    // This could be from your database, blockchain, or other sources
    try {
      const { data, error } = await supabase
        .from('user_balances' as any)
        .select('pi_balance')
        .eq('user_uid', userUid)
        .single();

      if (error || !data) {
        console.error('Error checking user balance:', error);
        return false;
      }

      return (data as any).pi_balance >= amount;
    } catch (error) {
      console.error('Error checking user balance:', error);
      return false;
    }
  }
}

// Export singleton instance
export const piWithdrawalService = new PiWithdrawalService();
