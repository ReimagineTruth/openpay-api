
-- ============================================================
-- OpenPay Smart Contract API - Developer Apps & OAuth System
-- ============================================================

-- 1. Developer applications (third-party apps)
CREATE TABLE public.developer_apps (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  app_name TEXT NOT NULL,
  app_description TEXT NOT NULL DEFAULT '',
  app_url TEXT NOT NULL DEFAULT '',
  redirect_uris TEXT[] NOT NULL DEFAULT '{}',
  logo_url TEXT,
  client_id TEXT NOT NULL UNIQUE DEFAULT ('opc_' || replace(gen_random_uuid()::text, '-', '')),
  client_secret_hash TEXT NOT NULL DEFAULT '',
  client_secret_last4 TEXT NOT NULL DEFAULT '',
  is_active BOOLEAN NOT NULL DEFAULT true,
  rate_limit_per_minute INTEGER NOT NULL DEFAULT 60,
  scopes TEXT[] NOT NULL DEFAULT '{read:balance,read:profile}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.developer_apps ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own developer apps" ON public.developer_apps
  FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "Users can insert own developer apps" ON public.developer_apps
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "Users can update own developer apps" ON public.developer_apps
  FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "Users can delete own developer apps" ON public.developer_apps
  FOR DELETE TO authenticated USING (user_id = auth.uid());

-- 2. OAuth authorizations (user grants to apps)
CREATE TABLE public.oauth_authorizations (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  app_id UUID NOT NULL REFERENCES public.developer_apps(id) ON DELETE CASCADE,
  scopes TEXT[] NOT NULL DEFAULT '{}',
  access_token_hash TEXT NOT NULL DEFAULT '',
  refresh_token_hash TEXT,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, app_id)
);

ALTER TABLE public.oauth_authorizations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own oauth authorizations" ON public.oauth_authorizations
  FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "Users can revoke own authorizations" ON public.oauth_authorizations
  FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "Users can delete own authorizations" ON public.oauth_authorizations
  FOR DELETE TO authenticated USING (user_id = auth.uid());

-- 3. API access logs
CREATE TABLE public.api_access_logs (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  app_id UUID NOT NULL REFERENCES public.developer_apps(id) ON DELETE CASCADE,
  user_id UUID,
  endpoint TEXT NOT NULL,
  method TEXT NOT NULL DEFAULT 'GET',
  status_code INTEGER NOT NULL DEFAULT 200,
  ip_address TEXT,
  response_time_ms INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.api_access_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "App owners can view their api logs" ON public.api_access_logs
  FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.developer_apps da WHERE da.id = app_id AND da.user_id = auth.uid())
  );

-- 4. Webhook registrations
CREATE TABLE public.developer_webhooks (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  app_id UUID NOT NULL REFERENCES public.developer_apps(id) ON DELETE CASCADE,
  webhook_url TEXT NOT NULL,
  events TEXT[] NOT NULL DEFAULT '{transaction.completed}',
  secret_hash TEXT NOT NULL DEFAULT '',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.developer_webhooks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "App owners can manage webhooks" ON public.developer_webhooks
  FOR ALL TO authenticated USING (
    EXISTS (SELECT 1 FROM public.developer_apps da WHERE da.id = app_id AND da.user_id = auth.uid())
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM public.developer_apps da WHERE da.id = app_id AND da.user_id = auth.uid())
  );
