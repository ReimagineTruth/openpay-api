declare module "https://deno.land/std@0.168.0/http/server.ts" {
  export function serve(
    handler: (req: Request) => Response | Promise<Response>,
  ): void;
}

declare module "https://esm.sh/@supabase/supabase-js@2" {
  type SupabaseUser = {
    id: string;
    email?: string | null;
    user_metadata?: Record<string, unknown>;
  };

  type SupabaseError = {
    message?: string;
    code?: string;
  };

  type SupabaseResult<T = unknown> = Promise<{
    data?: T;
    error?: SupabaseError | null;
  }>;

  type SupabaseQuery = {
    select: (...args: unknown[]) => SupabaseQuery;
    insert: (values: Record<string, unknown>) => SupabaseQuery;
    update: (values: Record<string, unknown>) => SupabaseQuery;
    delete: () => SupabaseQuery;
    eq: (...args: unknown[]) => SupabaseQuery;
    in: (...args: unknown[]) => SupabaseQuery;
    order: (...args: unknown[]) => SupabaseQuery;
    limit: (value: number) => SupabaseQuery;
    maybeSingle: () => SupabaseResult;
    single: () => SupabaseResult;
  };

  type SupabaseClient = {
    auth: {
      getUser: (token: string) => SupabaseResult<{ user: SupabaseUser | null }>;
      admin: {
        listUsers: () => Promise<{ users?: SupabaseUser[] }>;
        getUserById: (id: string) => SupabaseResult<{ user: SupabaseUser | null }>;
      };
    };
    rpc: (fn: string, args?: Record<string, unknown>) => SupabaseResult;
    from: (table: string) => SupabaseQuery;
  };

  export const createClient: (
    supabaseUrl: string,
    supabaseKey: string,
  ) => SupabaseClient;
}

declare global {
  const Deno: {
    env: {
      get(key: string): string | undefined;
    };
  };
}
export {};
