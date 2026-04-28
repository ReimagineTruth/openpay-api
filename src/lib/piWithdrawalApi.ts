import { supabase } from '@/integrations/supabase/client';

export interface PiWithdrawalRequest {
  amount: number;
  memo: string;
  metadata?: Record<string, unknown>;
}

export interface PiWithdrawalResult {
  success: boolean;
  paymentId?: string;
  txid?: string;
  error?: string;
  completedPayment?: any;
  newBalance?: number;
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

class PiWithdrawalApiService {
  private functionUrl: string;

  constructor() {
    // Get the Supabase function URL from environment or construct it
    const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
    this.functionUrl = `${supabaseUrl}/functions/v1/pi-withdrawal`;
  }

  /**
   * Create a new Pi withdrawal using the backend API
   */
  async createWithdrawal(request: PiWithdrawalRequest): Promise<PiWithdrawalResult> {
    try {
      const { data, error } = await supabase.functions.invoke('pi-withdrawal', {
        body: request,
        method: 'POST'
      });

      if (error) {
        console.error('API Error:', error);
        return {
          success: false,
          error: error.message || 'API request failed'
        };
      }

      return data as PiWithdrawalResult;
    } catch (error) {
      console.error('Error creating withdrawal:', error);
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error occurred'
      };
    }
  }

  /**
   * Get withdrawal history from the backend API
   */
  async getWithdrawalHistory(): Promise<PiWithdrawalRecord[]> {
    try {
      const { data, error } = await supabase.functions.invoke('pi-withdrawal', {
        method: 'GET'
      });

      if (error) {
        console.error('Error fetching withdrawal history:', error);
        return [];
      }

      return (data as any)?.history || [];
    } catch (error) {
      console.error('Error fetching withdrawal history:', error);
      return [];
    }
  }

  /**
   * Process complete withdrawal flow (create, submit, complete)
   * This is handled by the backend API in a single call
   */
  async processCompleteWithdrawal(request: PiWithdrawalRequest): Promise<PiWithdrawalResult> {
    return this.createWithdrawal(request);
  }
}

// Export singleton instance
export const piWithdrawalApiService = new PiWithdrawalApiService();
