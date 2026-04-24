import { describe, it, expect, vi, beforeEach } from 'vitest';
import { piWithdrawalService } from '@/lib/piWithdrawal';

// Mock the pi-backend module
vi.mock('pi-backend', () => {
  return {
    default: class MockPiNetwork {
      constructor(apiKey: string, walletPrivateSeed: string) {
        console.log('Mock PiNetwork constructor called with:', { apiKey, walletPrivateSeed });
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
    },
  };
});

// Mock the piSDKConfig
vi.mock('@/lib/piSDKConfig', () => ({
  PiSDKConfig: {
    isDevelopment: true,
    api: {
      key: 'test-api-key',
      sandbox: false,
    },
    wallet: {
      privateSeed: 'test-wallet-seed',
    },
  },
  initializePiSDKWarnings: () => () => {},
}));

describe('PiWithdrawalService Initialization', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Reset console mocks
    const originalConsole = global.console;
    global.console = {
      ...originalConsole,
      log: vi.fn(),
      error: vi.fn(),
      warn: vi.fn(),
    };
  });

  it('should initialize successfully', () => {
    // The service should be created and initialized
    expect(piWithdrawalService).toBeDefined();
    
    // Check console logs for initialization messages
    expect(console.log).toHaveBeenCalledWith(
      expect.stringContaining('Initializing Pi Network with API Key:')
    );
    expect(console.log).toHaveBeenCalledWith(
      expect.stringContaining('Wallet Private Seed:')
    );
  });

  it('should handle creation request after initialization', async () => {
    const request = {
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

  it('should handle complete withdrawal flow', async () => {
    const request = {
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
