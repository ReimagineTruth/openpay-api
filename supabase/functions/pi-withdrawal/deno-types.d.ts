// Deno types declaration for Supabase Edge Functions
// This file resolves TypeScript errors for Deno-specific modules and globals

declare module "https://deno.land/std@0.168.0/http/server.ts" {
  export interface ResponseInit {
    status?: number;
    statusText?: string;
    headers?: HeadersInit;
  }

  export interface RequestEvent {
    request: Request;
    respondWith(r: Response | Promise<Response>): Promise<void>;
  }

  export function serve(handler: (req: Request) => Response | Promise<Response>): void;
}

declare module "https://esm.sh/@supabase/supabase-js@2" {
  export function createClient<T = any>(
    url: string,
    key: string,
    options?: any
  ): any;
}

declare module "https://esm.sh/pi-backend@1.2.0" {
  export default class PiNetwork {
    constructor(apiKey: string, walletPrivateSeed: string);
    createPayment(paymentData: any): Promise<string>;
    submitPayment(paymentId: string): Promise<string>;
    completePayment(paymentId: string, txid: string): Promise<any>;
    getPayment(paymentId: string): Promise<any>;
    cancelPayment(paymentId: string): Promise<any>;
    getIncompleteServerPayments(): Promise<any[]>;
  }
}

declare namespace Deno {
  export function env(): {
    get(key: string): string | undefined;
  };
  
  export namespace env {
    export function get(key: string): string | undefined;
  }
}

// Pi Network environment variables
declare interface PiNetworkEnv {
  PI_API_KEY?: string;
  PI_WALLET_PRIVATE_SEED?: string;
  PI_BACKEND_HORIZON_MAINNET_URL?: string;
  PI_BACKEND_HORIZON_MAINNET_PASSPHRASE?: string;
  PI_BACKEND_HORIZON_TESTNET_URL?: string;
  PI_BACKEND_HORIZON_TESTNET_PASSPHRASE?: string;
  PI_BACKEND_PLATFORM_BASE_URL?: string;
}

declare global {
  var Deno: typeof Deno;
  var crypto: {
    randomUUID(): string;
  };
}
