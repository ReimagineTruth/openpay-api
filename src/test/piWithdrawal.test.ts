import { describe, it, expect, vi, beforeEach } from 'vitest';
import { piWithdrawalService, PiWithdrawalRequest } from '@/lib/piWithdrawal';

// Mock the pi-backend module
vi.mock('pi-backend', () => {
  return {
    default: class MockPiNetwork {
      constructor(apiKey: string, walletPrivateSeed: string) {
        console.log('Mock PiNetwork initialized with:', { apiKey, walletPrivateSeed });
      }
      
      async createPayment(paymentData: any) {
        return 'test-payment-id-123';
      }
      
      async submitPayment(paymentId: string) {
        return 'test-txid-456';
      }
      
      async completePayment(paymentId: string, txid: string) {
        return {
          identifier: paymentId,
          user_uid: 'test-user-uid',
          amount: 1.0,
          memo: 'Test withdrawal',
          metadata: {},
          from_address: 'test-from-address',
          to_address: 'test-to-address',
          direction: 'app_to_user' as const,
          created_at: new Date().toISOString(),
          network: 'Pi Network' as const,
          status: {
            developer_approved: true,
            transaction_verified: true,
            developer_completed: true,
            cancelled: false,
            user_cancelled: false,
          },
          transaction: {
            txid,
            verified: true,
            _link: `https://explorer.minepi.com/transactions/${txid}`,
          },
        };
      }
      
      async getPayment(paymentId: string) {
        return {
          identifier: paymentId,
          user_uid: 'test-user-uid',
          amount: 1.0,
          memo: 'Test withdrawal',
          metadata: {},
          from_address: 'test-from-address',
          to_address: 'test-to-address',
          direction: 'app_to_user' as const,
          created_at: new Date().toISOString(),
          network: 'Pi Network' as const,
          status: {
            developer_approved: true,
            transaction_verified: true,
            developer_completed: true,
            cancelled: false,
            user_cancelled: false,
          },
          transaction: {
            txid: 'test-txid-456',
            verified: true,
            _link: 'https://explorer.minepi.com/transactions/test-txid-456',
          },
        };
      }
      
      async cancelPayment(paymentId: string) {
        return {
          identifier: paymentId,
          user_uid: 'test-user-uid',
          amount: 1.0,
          memo: 'Test withdrawal',
          metadata: {},
          from_address: 'test-from-address',
          to_address: 'test-to-address',
          direction: 'app_to_user' as const,
          created_at: new Date().toISOString(),
          network: 'Pi Network' as const,
          status: {
            developer_approved: true,
            transaction_verified: false,
            developer_completed: false,
            cancelled: true,
            user_cancelled: false,
          },
          transaction: null,
        };
      }
    },
  };
});

// Mock supabase
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: vi.fn(() => ({
      insert: vi.fn().mockResolvedValue({ data: null, error: null }),
      select: vi.fn(() => ({
        eq: vi.fn(() => ({
          single: vi.fn().mockResolvedValue({ 
            data: { pi_balance: 1000 }, 
            error: null 
          }),
          order: vi.fn().mockResolvedValue({ 
            data: [], 
            error: null 
          }),
        })),
        order: vi.fn().mockResolvedValue({ 
          data: [], 
          error: null 
        }),
      })),
      update: vi.fn().mockResolvedValue({ data: null, error: null }),
    })),
  },
}));

describe('PiWithdrawalService', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('createWithdrawal', () => {
    it('should create a withdrawal successfully', async () => {
      const request: PiWithdrawalRequest = {
        amount: 1.0,
        memo: 'Test withdrawal',
        metadata: { type: 'test' },
        userUid: 'test-user-uid',
      };

      const result = await piWithdrawalService.createWithdrawal(request);

      expect(result.success).toBe(true);
      expect(result.paymentId).toBe('test-payment-id-123');
      expect(result.error).toBeUndefined();
    });

    it('should fail for invalid amount', async () => {
      const request: PiWithdrawalRequest = {
        amount: -1.0,
        memo: 'Test withdrawal',
        userUid: 'test-user-uid',
      };

      const result = await piWithdrawalService.createWithdrawal(request);

      expect(result.success).toBe(false);
      expect(result.error).toBe('Amount must be greater than 0');
    });

    it('should fail for zero amount', async () => {
      const request: PiWithdrawalRequest = {
        amount: 0,
        memo: 'Test withdrawal',
        userUid: 'test-user-uid',
      };

      const result = await piWithdrawalService.createWithdrawal(request);

      expect(result.success).toBe(false);
      expect(result.error).toBe('Amount must be greater than 0');
    });
  });

  describe('submitWithdrawal', () => {
    it('should submit withdrawal successfully', async () => {
      const paymentId = 'test-payment-id-123';

      const result = await piWithdrawalService.submitWithdrawal(paymentId);

      expect(result.success).toBe(true);
      expect(result.paymentId).toBe(paymentId);
      expect(result.txid).toBe('test-txid-456');
      expect(result.error).toBeUndefined();
    });
  });

  describe('completeWithdrawal', () => {
    it('should complete withdrawal successfully', async () => {
      const paymentId = 'test-payment-id-123';
      const txid = 'test-txid-456';

      const result = await piWithdrawalService.completeWithdrawal(paymentId, txid);

      expect(result.success).toBe(true);
      expect(result.paymentId).toBe(paymentId);
      expect(result.txid).toBe(txid);
      expect(result.completedPayment).toBeDefined();
      expect(result.completedPayment.status.developer_completed).toBe(true);
      expect(result.error).toBeUndefined();
    });
  });

  describe('processCompleteWithdrawal', () => {
    it('should process complete withdrawal flow successfully', async () => {
      const request: PiWithdrawalRequest = {
        amount: 1.0,
        memo: 'Test complete withdrawal',
        metadata: { type: 'complete_test' },
        userUid: 'test-user-uid',
      };

      const result = await piWithdrawalService.processCompleteWithdrawal(request);

      expect(result.success).toBe(true);
      expect(result.paymentId).toBe('test-payment-id-123');
      expect(result.txid).toBe('test-txid-456');
      expect(result.completedPayment).toBeDefined();
      expect(result.error).toBeUndefined();
    });
  });

  describe('getWithdrawalStatus', () => {
    it('should get withdrawal status successfully', async () => {
      const paymentId = 'test-payment-id-123';

      const result = await piWithdrawalService.getWithdrawalStatus(paymentId);

      expect(result.success).toBe(true);
      expect(result.completedPayment).toBeDefined();
      expect(result.completedPayment.identifier).toBe(paymentId);
      expect(result.error).toBeUndefined();
    });
  });

  describe('cancelWithdrawal', () => {
    it('should cancel withdrawal successfully', async () => {
      const paymentId = 'test-payment-id-123';

      const result = await piWithdrawalService.cancelWithdrawal(paymentId);

      expect(result.success).toBe(true);
      expect(result.completedPayment).toBeDefined();
      expect(result.completedPayment.status.cancelled).toBe(true);
      expect(result.error).toBeUndefined();
    });
  });

  describe('getUserWithdrawalHistory', () => {
    it('should get user withdrawal history', async () => {
      const userUid = 'test-user-uid';

      const history = await piWithdrawalService.getUserWithdrawalHistory(userUid);

      expect(Array.isArray(history)).toBe(true);
    });
  });
});
