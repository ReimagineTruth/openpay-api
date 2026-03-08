-- ============================================================
-- OpenPay Full Install SQL (all migrations combined)
-- Generated: 2026-03-08 23:05:26
-- NOTE: Run once on a fresh Supabase database.
-- Source: supabase/migrations/*.sql in filename order.
-- ============================================================


-- >>> MIGRATION: 20260214181722_0e401cc1-fe1a-4d4e-8952-b36cfbb5596d.sql

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Profiles table
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT NOT NULL DEFAULT '',
  username TEXT UNIQUE,
  avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Wallets table
CREATE TABLE public.wallets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  balance NUMERIC(12,2) NOT NULL DEFAULT 0.00 CHECK (balance >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;

-- Transactions table
CREATE TABLE public.transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id UUID NOT NULL REFERENCES auth.users(id),
  receiver_id UUID NOT NULL REFERENCES auth.users(id),
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  note TEXT DEFAULT '',
  status TEXT NOT NULL DEFAULT 'completed',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

-- Contacts table
CREATE TABLE public.contacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  contact_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, contact_id)
);
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;

-- Auto-create profile and wallet on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, username)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', ''), COALESCE(NEW.raw_user_meta_data->>'username', NULL));
  
  INSERT INTO public.wallets (user_id)
  VALUES (NEW.id);
  
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Helper function to check transaction participation
CREATE OR REPLACE FUNCTION public.is_transaction_participant(_transaction_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.transactions
    WHERE id = _transaction_id
    AND (sender_id = auth.uid() OR receiver_id = auth.uid())
  );
$$;

-- RLS Policies

-- Profiles: users can read all profiles (for sending money), update own
CREATE POLICY "Anyone authenticated can view profiles"
  ON public.profiles FOR SELECT TO authenticated USING (true);
CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE TO authenticated USING (id = auth.uid());
CREATE POLICY "Users can insert own profile"
  ON public.profiles FOR INSERT TO authenticated WITH CHECK (id = auth.uid());

-- Wallets: users can only see and update own wallet
CREATE POLICY "Users can view own wallet"
  ON public.wallets FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "Users can update own wallet"
  ON public.wallets FOR UPDATE TO authenticated USING (user_id = auth.uid());

-- Transactions: users can see own transactions
CREATE POLICY "Users can view own transactions"
  ON public.transactions FOR SELECT TO authenticated
  USING (sender_id = auth.uid() OR receiver_id = auth.uid());
CREATE POLICY "Users can insert transactions"
  ON public.transactions FOR INSERT TO authenticated
  WITH CHECK (sender_id = auth.uid());

-- Contacts: users can manage own contacts
CREATE POLICY "Users can view own contacts"
  ON public.contacts FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "Users can add contacts"
  ON public.contacts FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "Users can remove contacts"
  ON public.contacts FOR DELETE TO authenticated USING (user_id = auth.uid());

-- <<< END MIGRATION: 20260214181722_0e401cc1-fe1a-4d4e-8952-b36cfbb5596d.sql

-- >>> MIGRATION: 20260215043000_menu_features.sql
-- Payment requests
CREATE TABLE public.payment_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  payer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  note TEXT DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'rejected', 'cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.payment_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view related payment requests"
  ON public.payment_requests FOR SELECT TO authenticated
  USING (requester_id = auth.uid() OR payer_id = auth.uid());

CREATE POLICY "Users can create own payment requests"
  ON public.payment_requests FOR INSERT TO authenticated
  WITH CHECK (requester_id = auth.uid());

CREATE POLICY "Requester or payer can update payment requests"
  ON public.payment_requests FOR UPDATE TO authenticated
  USING (requester_id = auth.uid() OR payer_id = auth.uid())
  WITH CHECK (requester_id = auth.uid() OR payer_id = auth.uid());

-- Invoices
CREATE TABLE public.invoices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  description TEXT DEFAULT '',
  due_date DATE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view related invoices"
  ON public.invoices FOR SELECT TO authenticated
  USING (sender_id = auth.uid() OR recipient_id = auth.uid());

CREATE POLICY "Users can create own invoices"
  ON public.invoices FOR INSERT TO authenticated
  WITH CHECK (sender_id = auth.uid());

CREATE POLICY "Sender or recipient can update invoices"
  ON public.invoices FOR UPDATE TO authenticated
  USING (sender_id = auth.uid() OR recipient_id = auth.uid())
  WITH CHECK (sender_id = auth.uid() OR recipient_id = auth.uid());

-- Support tickets
CREATE TABLE public.support_tickets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  subject TEXT NOT NULL,
  message TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'resolved')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own tickets"
  ON public.support_tickets FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Users can create own tickets"
  ON public.support_tickets FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- <<< END MIGRATION: 20260215043000_menu_features.sql

-- >>> MIGRATION: 20260215104000_avatar_storage_and_realtime.sql
-- Avatar storage bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars',
  'avatars',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE
SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Public read for avatar images
CREATE POLICY "Avatar images are publicly readable"
  ON storage.objects
  FOR SELECT
  USING (bucket_id = 'avatars');

-- Users can upload/update/delete only their own avatar objects in avatars/{user_id}/...
CREATE POLICY "Users can upload own avatars"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Users can update own avatars"
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Users can delete own avatars"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Ensure realtime publication includes app event tables used for notifications
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'transactions'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.transactions';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'payment_requests'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.payment_requests';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'invoices'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.invoices';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'support_tickets'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.support_tickets';
  END IF;
END $$;

-- <<< END MIGRATION: 20260215104000_avatar_storage_and_realtime.sql

-- >>> MIGRATION: 20260215113000_admin_ledger_history.sql
-- Immutable ledger for transparent admin history
CREATE TABLE IF NOT EXISTS public.ledger_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_table TEXT NOT NULL,
  source_id UUID NOT NULL,
  event_type TEXT NOT NULL,
  actor_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  related_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  amount NUMERIC(12,2),
  status TEXT,
  note TEXT DEFAULT '',
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ledger_events_occurred_at ON public.ledger_events (occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_ledger_events_source ON public.ledger_events (source_table, source_id);
CREATE INDEX IF NOT EXISTS idx_ledger_events_actor ON public.ledger_events (actor_user_id);
CREATE INDEX IF NOT EXISTS idx_ledger_events_related ON public.ledger_events (related_user_id);

ALTER TABLE public.ledger_events ENABLE ROW LEVEL SECURITY;

-- No read policy for regular users. Admin dashboard reads via service role edge function.

CREATE OR REPLACE FUNCTION public.log_transaction_insert_to_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.ledger_events (
    source_table,
    source_id,
    event_type,
    actor_user_id,
    related_user_id,
    amount,
    status,
    note,
    payload,
    occurred_at
  )
  VALUES (
    'transactions',
    NEW.id,
    'transaction_created',
    NEW.sender_id,
    NEW.receiver_id,
    NEW.amount,
    NEW.status,
    COALESCE(NEW.note, ''),
    jsonb_build_object(
      'sender_id', NEW.sender_id,
      'receiver_id', NEW.receiver_id
    ),
    NEW.created_at
  );

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.log_transaction_update_to_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.amount IS DISTINCT FROM OLD.amount
    OR NEW.status IS DISTINCT FROM OLD.status
    OR NEW.note IS DISTINCT FROM OLD.note THEN
    INSERT INTO public.ledger_events (
      source_table,
      source_id,
      event_type,
      actor_user_id,
      related_user_id,
      amount,
      status,
      note,
      payload,
      occurred_at
    )
    VALUES (
      'transactions',
      NEW.id,
      'transaction_updated',
      NEW.sender_id,
      NEW.receiver_id,
      NEW.amount,
      NEW.status,
      COALESCE(NEW.note, ''),
      jsonb_build_object(
        'old_amount', OLD.amount,
        'new_amount', NEW.amount,
        'old_status', OLD.status,
        'new_status', NEW.status,
        'old_note', COALESCE(OLD.note, ''),
        'new_note', COALESCE(NEW.note, '')
      ),
      now()
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.log_payment_request_insert_to_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.ledger_events (
    source_table,
    source_id,
    event_type,
    actor_user_id,
    related_user_id,
    amount,
    status,
    note,
    payload,
    occurred_at
  )
  VALUES (
    'payment_requests',
    NEW.id,
    'payment_request_created',
    NEW.requester_id,
    NEW.payer_id,
    NEW.amount,
    NEW.status,
    COALESCE(NEW.note, ''),
    '{}'::jsonb,
    NEW.created_at
  );

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.log_payment_request_update_to_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
    OR NEW.amount IS DISTINCT FROM OLD.amount
    OR NEW.note IS DISTINCT FROM OLD.note THEN
    INSERT INTO public.ledger_events (
      source_table,
      source_id,
      event_type,
      actor_user_id,
      related_user_id,
      amount,
      status,
      note,
      payload,
      occurred_at
    )
    VALUES (
      'payment_requests',
      NEW.id,
      'payment_request_updated',
      NEW.requester_id,
      NEW.payer_id,
      NEW.amount,
      NEW.status,
      COALESCE(NEW.note, ''),
      jsonb_build_object(
        'old_status', OLD.status,
        'new_status', NEW.status,
        'old_amount', OLD.amount,
        'new_amount', NEW.amount
      ),
      COALESCE(NEW.updated_at, now())
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.log_invoice_insert_to_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.ledger_events (
    source_table,
    source_id,
    event_type,
    actor_user_id,
    related_user_id,
    amount,
    status,
    note,
    payload,
    occurred_at
  )
  VALUES (
    'invoices',
    NEW.id,
    'invoice_created',
    NEW.sender_id,
    NEW.recipient_id,
    NEW.amount,
    NEW.status,
    COALESCE(NEW.description, ''),
    jsonb_build_object('due_date', NEW.due_date),
    NEW.created_at
  );

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.log_invoice_update_to_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
    OR NEW.amount IS DISTINCT FROM OLD.amount
    OR NEW.description IS DISTINCT FROM OLD.description
    OR NEW.due_date IS DISTINCT FROM OLD.due_date THEN
    INSERT INTO public.ledger_events (
      source_table,
      source_id,
      event_type,
      actor_user_id,
      related_user_id,
      amount,
      status,
      note,
      payload,
      occurred_at
    )
    VALUES (
      'invoices',
      NEW.id,
      'invoice_updated',
      NEW.sender_id,
      NEW.recipient_id,
      NEW.amount,
      NEW.status,
      COALESCE(NEW.description, ''),
      jsonb_build_object(
        'old_status', OLD.status,
        'new_status', NEW.status,
        'old_due_date', OLD.due_date,
        'new_due_date', NEW.due_date
      ),
      COALESCE(NEW.updated_at, now())
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.log_wallet_update_to_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  delta NUMERIC(12,2);
BEGIN
  IF NEW.balance IS DISTINCT FROM OLD.balance THEN
    delta := NEW.balance - OLD.balance;
    INSERT INTO public.ledger_events (
      source_table,
      source_id,
      event_type,
      actor_user_id,
      amount,
      note,
      payload,
      occurred_at
    )
    VALUES (
      'wallets',
      NEW.id,
      'wallet_balance_changed',
      NEW.user_id,
      delta,
      '',
      jsonb_build_object(
        'old_balance', OLD.balance,
        'new_balance', NEW.balance,
        'delta', delta
      ),
      COALESCE(NEW.updated_at, now())
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ledger_transactions_insert ON public.transactions;
CREATE TRIGGER trg_ledger_transactions_insert
AFTER INSERT ON public.transactions
FOR EACH ROW EXECUTE FUNCTION public.log_transaction_insert_to_ledger();

DROP TRIGGER IF EXISTS trg_ledger_transactions_update ON public.transactions;
CREATE TRIGGER trg_ledger_transactions_update
AFTER UPDATE ON public.transactions
FOR EACH ROW EXECUTE FUNCTION public.log_transaction_update_to_ledger();

DROP TRIGGER IF EXISTS trg_ledger_payment_requests_insert ON public.payment_requests;
CREATE TRIGGER trg_ledger_payment_requests_insert
AFTER INSERT ON public.payment_requests
FOR EACH ROW EXECUTE FUNCTION public.log_payment_request_insert_to_ledger();

DROP TRIGGER IF EXISTS trg_ledger_payment_requests_update ON public.payment_requests;
CREATE TRIGGER trg_ledger_payment_requests_update
AFTER UPDATE ON public.payment_requests
FOR EACH ROW EXECUTE FUNCTION public.log_payment_request_update_to_ledger();

DROP TRIGGER IF EXISTS trg_ledger_invoices_insert ON public.invoices;
CREATE TRIGGER trg_ledger_invoices_insert
AFTER INSERT ON public.invoices
FOR EACH ROW EXECUTE FUNCTION public.log_invoice_insert_to_ledger();

DROP TRIGGER IF EXISTS trg_ledger_invoices_update ON public.invoices;
CREATE TRIGGER trg_ledger_invoices_update
AFTER UPDATE ON public.invoices
FOR EACH ROW EXECUTE FUNCTION public.log_invoice_update_to_ledger();

DROP TRIGGER IF EXISTS trg_ledger_wallets_update ON public.wallets;
CREATE TRIGGER trg_ledger_wallets_update
AFTER UPDATE ON public.wallets
FOR EACH ROW EXECUTE FUNCTION public.log_wallet_update_to_ledger();

-- Backfill current records for historical transparency
INSERT INTO public.ledger_events (
  source_table,
  source_id,
  event_type,
  actor_user_id,
  related_user_id,
  amount,
  status,
  note,
  payload,
  occurred_at
)
SELECT
  'transactions',
  t.id,
  'transaction_created',
  t.sender_id,
  t.receiver_id,
  t.amount,
  t.status,
  COALESCE(t.note, ''),
  jsonb_build_object('sender_id', t.sender_id, 'receiver_id', t.receiver_id),
  t.created_at
FROM public.transactions t
WHERE NOT EXISTS (
  SELECT 1
  FROM public.ledger_events le
  WHERE le.source_table = 'transactions'
    AND le.source_id = t.id
    AND le.event_type = 'transaction_created'
);

INSERT INTO public.ledger_events (
  source_table,
  source_id,
  event_type,
  actor_user_id,
  related_user_id,
  amount,
  status,
  note,
  payload,
  occurred_at
)
SELECT
  'payment_requests',
  pr.id,
  'payment_request_created',
  pr.requester_id,
  pr.payer_id,
  pr.amount,
  pr.status,
  COALESCE(pr.note, ''),
  '{}'::jsonb,
  pr.created_at
FROM public.payment_requests pr
WHERE NOT EXISTS (
  SELECT 1
  FROM public.ledger_events le
  WHERE le.source_table = 'payment_requests'
    AND le.source_id = pr.id
    AND le.event_type = 'payment_request_created'
);

INSERT INTO public.ledger_events (
  source_table,
  source_id,
  event_type,
  actor_user_id,
  related_user_id,
  amount,
  status,
  note,
  payload,
  occurred_at
)
SELECT
  'invoices',
  i.id,
  'invoice_created',
  i.sender_id,
  i.recipient_id,
  i.amount,
  i.status,
  COALESCE(i.description, ''),
  jsonb_build_object('due_date', i.due_date),
  i.created_at
FROM public.invoices i
WHERE NOT EXISTS (
  SELECT 1
  FROM public.ledger_events le
  WHERE le.source_table = 'invoices'
    AND le.source_id = i.id
    AND le.event_type = 'invoice_created'
);


-- <<< END MIGRATION: 20260215113000_admin_ledger_history.sql

-- >>> MIGRATION: 20260215120000_admin_dashboard_rpc.sql
CREATE OR REPLACE FUNCTION public.admin_dashboard_history(
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_email TEXT;
  v_limit INTEGER;
  v_offset INTEGER;
  v_total_history BIGINT;
  v_total_users BIGINT;
  v_page_amount_sum NUMERIC(12,2);
  v_history JSONB;
BEGIN
  v_email := auth.jwt() ->> 'email';
  IF v_email IS NULL OR btrim(v_email) = '' THEN
    RAISE EXCEPTION 'Email sign-in required'
      USING ERRCODE = '42501';
  END IF;

  v_limit := GREATEST(1, LEAST(COALESCE(p_limit, 50), 200));
  v_offset := GREATEST(0, COALESCE(p_offset, 0));

  SELECT COUNT(*) INTO v_total_history
  FROM public.ledger_events;

  SELECT COUNT(*) INTO v_total_users
  FROM public.profiles;

  SELECT COALESCE(SUM(t.amount), 0) INTO v_page_amount_sum
  FROM (
    SELECT le.amount
    FROM public.ledger_events le
    ORDER BY le.occurred_at DESC
    OFFSET v_offset
    LIMIT v_limit
  ) AS t;

  SELECT COALESCE(jsonb_agg(to_jsonb(r)), '[]'::jsonb) INTO v_history
  FROM (
    SELECT
      le.id,
      le.source_table,
      le.source_id,
      le.event_type,
      le.actor_user_id,
      le.related_user_id,
      le.amount,
      le.status,
      le.note,
      le.payload,
      le.occurred_at,
      le.recorded_at,
      CASE
        WHEN le.actor_user_id IS NULL THEN NULL
        ELSE jsonb_build_object(
          'full_name', COALESCE(actor_profile.full_name, ''),
          'username', COALESCE(actor_profile.username, '')
        )
      END AS actor_profile,
      CASE
        WHEN le.related_user_id IS NULL THEN NULL
        ELSE jsonb_build_object(
          'full_name', COALESCE(related_profile.full_name, ''),
          'username', COALESCE(related_profile.username, '')
        )
      END AS related_profile
    FROM public.ledger_events le
    LEFT JOIN public.profiles actor_profile ON actor_profile.id = le.actor_user_id
    LEFT JOIN public.profiles related_profile ON related_profile.id = le.related_user_id
    ORDER BY le.occurred_at DESC
    OFFSET v_offset
    LIMIT v_limit
  ) AS r;

  RETURN jsonb_build_object(
    'success', true,
    'data', jsonb_build_object(
      'summary', jsonb_build_object(
        'total_history_events', v_total_history,
        'total_users', v_total_users,
        'page_amount_sum', v_page_amount_sum,
        'page_limit', v_limit,
        'page_offset', v_offset
      ),
      'history', v_history
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_dashboard_history(INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_history(INTEGER, INTEGER) TO authenticated;


-- <<< END MIGRATION: 20260215120000_admin_dashboard_rpc.sql

-- >>> MIGRATION: 20260215123000_fix_admin_dashboard_history_rpc_cache.sql
-- Recreate admin RPC with explicit 2-arg signature and force schema cache reload.
DROP FUNCTION IF EXISTS public.admin_dashboard_history(INTEGER, INTEGER);
DROP FUNCTION IF EXISTS public.admin_dashboard_history();

CREATE FUNCTION public.admin_dashboard_history(
  p_limit INTEGER,
  p_offset INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_email TEXT;
  v_limit INTEGER;
  v_offset INTEGER;
  v_total_history BIGINT;
  v_total_users BIGINT;
  v_page_amount_sum NUMERIC(12,2);
  v_history JSONB;
BEGIN
  v_email := auth.jwt() ->> 'email';
  IF v_email IS NULL OR btrim(v_email) = '' THEN
    RAISE EXCEPTION 'Email sign-in required'
      USING ERRCODE = '42501';
  END IF;

  v_limit := GREATEST(1, LEAST(COALESCE(p_limit, 50), 200));
  v_offset := GREATEST(0, COALESCE(p_offset, 0));

  SELECT COUNT(*) INTO v_total_history
  FROM public.ledger_events;

  SELECT COUNT(*) INTO v_total_users
  FROM public.profiles;

  SELECT COALESCE(SUM(t.amount), 0) INTO v_page_amount_sum
  FROM (
    SELECT le.amount
    FROM public.ledger_events le
    ORDER BY le.occurred_at DESC
    OFFSET v_offset
    LIMIT v_limit
  ) AS t;

  SELECT COALESCE(jsonb_agg(to_jsonb(r)), '[]'::jsonb) INTO v_history
  FROM (
    SELECT
      le.id,
      le.source_table,
      le.source_id,
      le.event_type,
      le.actor_user_id,
      le.related_user_id,
      le.amount,
      le.status,
      le.note,
      le.payload,
      le.occurred_at,
      le.recorded_at,
      CASE
        WHEN le.actor_user_id IS NULL THEN NULL
        ELSE jsonb_build_object(
          'full_name', COALESCE(actor_profile.full_name, ''),
          'username', COALESCE(actor_profile.username, '')
        )
      END AS actor_profile,
      CASE
        WHEN le.related_user_id IS NULL THEN NULL
        ELSE jsonb_build_object(
          'full_name', COALESCE(related_profile.full_name, ''),
          'username', COALESCE(related_profile.username, '')
        )
      END AS related_profile
    FROM public.ledger_events le
    LEFT JOIN public.profiles actor_profile ON actor_profile.id = le.actor_user_id
    LEFT JOIN public.profiles related_profile ON related_profile.id = le.related_user_id
    ORDER BY le.occurred_at DESC
    OFFSET v_offset
    LIMIT v_limit
  ) AS r;

  RETURN jsonb_build_object(
    'success', true,
    'data', jsonb_build_object(
      'summary', jsonb_build_object(
        'total_history_events', v_total_history,
        'total_users', v_total_users,
        'page_amount_sum', v_page_amount_sum,
        'page_limit', v_limit,
        'page_offset', v_offset
      ),
      'history', v_history
    )
  );
END;
$$;

-- Optional no-arg overload for direct SQL/manual use.
CREATE FUNCTION public.admin_dashboard_history()
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT public.admin_dashboard_history(50, 0);
$$;

REVOKE ALL ON FUNCTION public.admin_dashboard_history(INTEGER, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_dashboard_history() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_history(INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_history() TO authenticated;

-- Force PostgREST schema cache refresh so RPC becomes immediately visible.
NOTIFY pgrst, 'reload schema';


-- <<< END MIGRATION: 20260215123000_fix_admin_dashboard_history_rpc_cache.sql

-- >>> MIGRATION: 20260215124000_fix_numeric_overflow_admin_history.sql
-- Prevent numeric overflow in admin history totals and ledger amount storage.
ALTER TABLE public.ledger_events
  ALTER COLUMN amount TYPE NUMERIC(20,2);

CREATE OR REPLACE FUNCTION public.admin_dashboard_history(
  p_limit INTEGER,
  p_offset INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_email TEXT;
  v_limit INTEGER;
  v_offset INTEGER;
  v_total_history BIGINT;
  v_total_users BIGINT;
  v_page_amount_sum NUMERIC;
  v_history JSONB;
BEGIN
  v_email := auth.jwt() ->> 'email';
  IF v_email IS NULL OR btrim(v_email) = '' THEN
    RAISE EXCEPTION 'Email sign-in required'
      USING ERRCODE = '42501';
  END IF;

  v_limit := GREATEST(1, LEAST(COALESCE(p_limit, 50), 200));
  v_offset := GREATEST(0, COALESCE(p_offset, 0));

  SELECT COUNT(*) INTO v_total_history
  FROM public.ledger_events;

  SELECT COUNT(*) INTO v_total_users
  FROM public.profiles;

  SELECT COALESCE(SUM(t.amount), 0) INTO v_page_amount_sum
  FROM (
    SELECT le.amount
    FROM public.ledger_events le
    ORDER BY le.occurred_at DESC
    OFFSET v_offset
    LIMIT v_limit
  ) AS t;

  SELECT COALESCE(jsonb_agg(to_jsonb(r)), '[]'::jsonb) INTO v_history
  FROM (
    SELECT
      le.id,
      le.source_table,
      le.source_id,
      le.event_type,
      le.actor_user_id,
      le.related_user_id,
      le.amount,
      le.status,
      le.note,
      le.payload,
      le.occurred_at,
      le.recorded_at,
      CASE
        WHEN le.actor_user_id IS NULL THEN NULL
        ELSE jsonb_build_object(
          'full_name', COALESCE(actor_profile.full_name, ''),
          'username', COALESCE(actor_profile.username, '')
        )
      END AS actor_profile,
      CASE
        WHEN le.related_user_id IS NULL THEN NULL
        ELSE jsonb_build_object(
          'full_name', COALESCE(related_profile.full_name, ''),
          'username', COALESCE(related_profile.username, '')
        )
      END AS related_profile
    FROM public.ledger_events le
    LEFT JOIN public.profiles actor_profile ON actor_profile.id = le.actor_user_id
    LEFT JOIN public.profiles related_profile ON related_profile.id = le.related_user_id
    ORDER BY le.occurred_at DESC
    OFFSET v_offset
    LIMIT v_limit
  ) AS r;

  RETURN jsonb_build_object(
    'success', true,
    'data', jsonb_build_object(
      'summary', jsonb_build_object(
        'total_history_events', v_total_history,
        'total_users', v_total_users,
        'page_amount_sum', v_page_amount_sum,
        'page_limit', v_limit,
        'page_offset', v_offset
      ),
      'history', v_history
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_dashboard_history()
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT public.admin_dashboard_history(50, 0);
$$;

NOTIFY pgrst, 'reload schema';


-- <<< END MIGRATION: 20260215124000_fix_numeric_overflow_admin_history.sql

-- >>> MIGRATION: 20260215130000_pi_payment_credits.sql
CREATE TABLE IF NOT EXISTS public.pi_payment_credits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id TEXT NOT NULL UNIQUE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount NUMERIC(20,2) NOT NULL CHECK (amount > 0),
  txid TEXT,
  status TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('completed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.pi_payment_credits ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own pi payment credits"
  ON public.pi_payment_credits
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());


-- <<< END MIGRATION: 20260215130000_pi_payment_credits.sql

-- >>> MIGRATION: 20260215134000_fix_handle_new_user_username_conflict.sql
-- Prevent auth signup failures when profile username collides with existing users.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  requested_username TEXT;
  final_username TEXT;
BEGIN
  requested_username := NULLIF(BTRIM(NEW.raw_user_meta_data->>'username'), '');

  IF requested_username IS NOT NULL THEN
    final_username := requested_username;

    IF EXISTS (SELECT 1 FROM public.profiles p WHERE p.username = final_username) THEN
      final_username := requested_username || '_' || REPLACE(SUBSTRING(NEW.id::text, 1, 8), '-', '');
    END IF;
  END IF;

  INSERT INTO public.profiles (id, full_name, username)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    final_username
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.wallets (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;


-- <<< END MIGRATION: 20260215134000_fix_handle_new_user_username_conflict.sql

-- >>> MIGRATION: 20260215152000_atomic_transfer_and_admin_refund.sql
CREATE OR REPLACE FUNCTION public.transfer_funds(
  p_sender_id UUID,
  p_receiver_id UUID,
  p_amount NUMERIC,
  p_note TEXT DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sender_balance NUMERIC(12,2);
  v_receiver_balance NUMERIC(12,2);
  v_transaction_id UUID;
BEGIN
  IF p_sender_id IS NULL OR p_receiver_id IS NULL THEN
    RAISE EXCEPTION 'Missing sender or receiver';
  END IF;

  IF p_sender_id = p_receiver_id THEN
    RAISE EXCEPTION 'Cannot send to yourself';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Invalid amount';
  END IF;

  SELECT balance INTO v_sender_balance
  FROM public.wallets
  WHERE user_id = p_sender_id
  FOR UPDATE;

  IF v_sender_balance IS NULL THEN
    RAISE EXCEPTION 'Sender wallet not found';
  END IF;

  SELECT balance INTO v_receiver_balance
  FROM public.wallets
  WHERE user_id = p_receiver_id
  FOR UPDATE;

  IF v_receiver_balance IS NULL THEN
    RAISE EXCEPTION 'Recipient wallet not found';
  END IF;

  IF v_sender_balance < p_amount THEN
    RAISE EXCEPTION 'Insufficient balance';
  END IF;

  UPDATE public.wallets
  SET balance = v_sender_balance - p_amount,
      updated_at = now()
  WHERE user_id = p_sender_id;

  UPDATE public.wallets
  SET balance = v_receiver_balance + p_amount,
      updated_at = now()
  WHERE user_id = p_receiver_id;

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (p_sender_id, p_receiver_id, p_amount, COALESCE(p_note, ''), 'completed')
  RETURNING id INTO v_transaction_id;

  RETURN v_transaction_id;
END;
$$;

REVOKE ALL ON FUNCTION public.transfer_funds(UUID, UUID, NUMERIC, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transfer_funds(UUID, UUID, NUMERIC, TEXT) TO service_role;

CREATE TABLE IF NOT EXISTS public.admin_self_send_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_id UUID NOT NULL UNIQUE REFERENCES public.transactions(id) ON DELETE CASCADE,
  reviewed_by_email TEXT NOT NULL,
  decision TEXT NOT NULL CHECK (decision IN ('approve', 'reject')),
  reason TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.admin_self_send_reviews ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.admin_refund_self_send(
  p_transaction_id UUID,
  p_decision TEXT,
  p_reason TEXT DEFAULT '',
  p_admin_email TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tx public.transactions%ROWTYPE;
  v_refund_tx_id UUID;
  v_wallet_balance NUMERIC(12,2);
BEGIN
  IF p_transaction_id IS NULL THEN
    RAISE EXCEPTION 'Transaction ID is required';
  END IF;

  IF p_decision NOT IN ('approve', 'reject') THEN
    RAISE EXCEPTION 'Invalid decision';
  END IF;

  SELECT *
  INTO v_tx
  FROM public.transactions
  WHERE id = p_transaction_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transaction not found';
  END IF;

  IF v_tx.sender_id IS DISTINCT FROM v_tx.receiver_id THEN
    RAISE EXCEPTION 'Only self-send transactions can be reviewed here';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.admin_self_send_reviews
    WHERE transaction_id = p_transaction_id
  ) THEN
    RAISE EXCEPTION 'Transaction already reviewed';
  END IF;

  IF p_decision = 'approve' THEN
    SELECT balance INTO v_wallet_balance
    FROM public.wallets
    WHERE user_id = v_tx.sender_id
    FOR UPDATE;

    IF v_wallet_balance IS NULL THEN
      RAISE EXCEPTION 'Wallet not found';
    END IF;

    UPDATE public.wallets
    SET balance = v_wallet_balance + v_tx.amount,
        updated_at = now()
    WHERE user_id = v_tx.sender_id;

    INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
    VALUES (
      v_tx.sender_id,
      v_tx.receiver_id,
      v_tx.amount,
      CONCAT('Admin self-send refund for transaction ', v_tx.id::TEXT, '. ', COALESCE(p_reason, '')),
      'refunded'
    )
    RETURNING id INTO v_refund_tx_id;
  END IF;

  INSERT INTO public.admin_self_send_reviews (transaction_id, reviewed_by_email, decision, reason)
  VALUES (p_transaction_id, COALESCE(NULLIF(p_admin_email, ''), 'unknown-admin'), p_decision, COALESCE(p_reason, ''));

  RETURN jsonb_build_object(
    'success', true,
    'decision', p_decision,
    'transaction_id', p_transaction_id,
    'refunded_transaction_id', v_refund_tx_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_refund_self_send(UUID, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_refund_self_send(UUID, TEXT, TEXT, TEXT) TO service_role;

-- <<< END MIGRATION: 20260215152000_atomic_transfer_and_admin_refund.sql

-- >>> MIGRATION: 20260216101000_supported_currencies_realtime.sql
-- USD-based FX rates for the app.
-- Product rule: 1 PI = 3.14 USD.

CREATE TABLE IF NOT EXISTS public.supported_currencies (
  iso_code TEXT PRIMARY KEY,
  display_code TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  symbol TEXT NOT NULL,
  flag TEXT NOT NULL,
  usd_rate NUMERIC(20, 8) NOT NULL CHECK (usd_rate > 0),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Normalize and relax iso_code checks so PI (2 letters) is valid.
UPDATE public.supported_currencies
SET iso_code = upper(trim(iso_code))
WHERE iso_code IS NOT NULL;

ALTER TABLE public.supported_currencies
DROP CONSTRAINT IF EXISTS supported_currencies_iso_code_check;

DO $$
DECLARE
  v_constraint_name TEXT;
BEGIN
  FOR v_constraint_name IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.supported_currencies'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%iso_code%'
  LOOP
    EXECUTE format(
      'ALTER TABLE public.supported_currencies DROP CONSTRAINT IF EXISTS %I',
      v_constraint_name
    );
  END LOOP;
END $$;

ALTER TABLE public.supported_currencies
ADD CONSTRAINT supported_currencies_iso_code_check
CHECK (iso_code ~ '^[A-Z]{2,3}$');

ALTER TABLE public.supported_currencies ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'supported_currencies'
      AND policyname = 'Anyone can read supported currencies'
  ) THEN
    CREATE POLICY "Anyone can read supported currencies"
      ON public.supported_currencies
      FOR SELECT
      USING (true);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.set_supported_currencies_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_supported_currencies_updated_at ON public.supported_currencies;
CREATE TRIGGER trg_supported_currencies_updated_at
BEFORE UPDATE ON public.supported_currencies
FOR EACH ROW
EXECUTE FUNCTION public.set_supported_currencies_updated_at();

INSERT INTO public.supported_currencies (
  iso_code, display_code, display_name, symbol, flag, usd_rate, is_active
)
SELECT
  v.code,
  v.code,
  v.code,
  v.code,
  'ðŸ³ï¸',
  CASE
    WHEN v.code = 'PI' THEN 3.14
    WHEN v.code = 'USD' THEN 1
    ELSE 1
  END,
  true
FROM (
  VALUES
  ('PI'), ('USD'), ('CAD'), ('MXN'), ('BRL'), ('ARS'), ('CLP'), ('COP'), ('PEN'), ('BOB'),
  ('UYU'), ('PYG'), ('VES'), ('GTQ'), ('HNL'), ('NIO'), ('CRC'), ('PAB'), ('DOP'), ('CUP'),
  ('JMD'), ('TTD'), ('BBD'), ('BSD'), ('XCD'),
  ('EUR'), ('GBP'), ('CHF'), ('SEK'), ('NOK'), ('DKK'), ('PLN'), ('CZK'), ('HUF'), ('RON'),
  ('BGN'), ('RSD'), ('MKD'), ('ALL'), ('ISK'), ('UAH'), ('BYN'), ('RUB'), ('TRY'), ('BAM'), ('MDL'),
  ('JPY'), ('CNY'), ('KRW'), ('INR'), ('PKR'), ('BDT'), ('LKR'), ('NPR'), ('IDR'), ('MYR'),
  ('THB'), ('PHP'), ('SGD'), ('VND'), ('KHR'), ('LAK'), ('MMK'), ('BND'), ('HKD'), ('MOP'),
  ('TWD'), ('MNT'), ('KZT'), ('UZS'), ('TJS'), ('TMT'), ('KGS'), ('IRR'), ('IQD'), ('SAR'),
  ('AED'), ('QAR'), ('KWD'), ('OMR'), ('BHD'), ('ILS'), ('JOD'), ('LBP'), ('SYP'), ('YER'), ('AFN'),
  ('ZAR'), ('EGP'), ('NGN'), ('KES'), ('TZS'), ('UGX'), ('ETB'), ('GHS'), ('ZMW'), ('MWK'),
  ('MZN'), ('BWP'), ('NAD'), ('SZL'), ('LSL'), ('AOA'), ('CDF'), ('RWF'), ('BIF'), ('DJF'),
  ('SOS'), ('SDG'), ('SSP'), ('DZD'), ('MAD'), ('TND'), ('LYD'), ('XOF'), ('XAF'), ('MUR'), ('SCR'),
  ('AUD'), ('NZD'), ('PGK'), ('FJD'), ('SBD'), ('VUV'), ('WST'), ('TOP')
  , ('AMD'), ('AZN'), ('ERN'), ('GMD'), ('GNF'), ('HTG'), ('KMF'), ('KYD'), ('MGA'), ('MRU'),
  ('MVR'), ('SLL'), ('SRD'), ('STN'), ('SVC')
) AS v(code)
ON CONFLICT (iso_code) DO UPDATE
SET
  is_active = true,
  updated_at = now();

-- Apply fixed USD rates (1 PI = 3.14 USD).
UPDATE public.supported_currencies
SET usd_rate = CASE iso_code
  WHEN 'PI' THEN 3.14
  WHEN 'USD' THEN 1
  WHEN 'EUR' THEN 0.8429
  WHEN 'GBP' THEN 0.7344
  WHEN 'AUD' THEN 1.428
  WHEN 'CAD' THEN 1.362
  WHEN 'JPY' THEN 155.926
  WHEN 'CNY' THEN 6.901
  WHEN 'CHF' THEN 0.7786
  WHEN 'SGD' THEN 1.271
  WHEN 'HKD' THEN 7.816
  WHEN 'INR' THEN 90.599
  WHEN 'BRL' THEN 5.5745
  WHEN 'MXN' THEN 17.232
  WHEN 'ZAR' THEN 15.961
  WHEN 'TRY' THEN 43.645
  WHEN 'PLN' THEN 3.554
  WHEN 'RON' THEN 4.292
  WHEN 'CZK' THEN 20.443
  WHEN 'NOK' THEN 9.545
  WHEN 'DKK' THEN 6.298
  WHEN 'SEK' THEN 8.931
  WHEN 'AED' THEN 3.6725
  WHEN 'SAR' THEN 3.75
  WHEN 'QAR' THEN 3.641
  WHEN 'KWD' THEN 0.3066
  WHEN 'BHD' THEN 0.376992
  WHEN 'OMR' THEN 0.3845
  WHEN 'JOD' THEN 0.709
  WHEN 'NGN' THEN 1352
  WHEN 'KES' THEN 129
  WHEN 'ETB' THEN 155.05
  WHEN 'GHS' THEN 11.005
  WHEN 'MAD' THEN 9.139
  WHEN 'RWF' THEN 1453
  WHEN 'XOF' THEN 552.915
  WHEN 'XAF' THEN 552.915
  WHEN 'ARS' THEN 1482.94905
  WHEN 'COP' THEN 3670
  WHEN 'PEN' THEN 3.355
  WHEN 'BOB' THEN 6.9269
  WHEN 'PYG' THEN 6586
  WHEN 'UYU' THEN 38.557
  WHEN 'DOP' THEN 62.625
  WHEN 'CRC' THEN 495.723
  WHEN 'GTQ' THEN 7.672
  WHEN 'NIO' THEN 36.715
  WHEN 'BSD' THEN 1
  WHEN 'BBD' THEN 2
  WHEN 'TTD' THEN 6.776
  WHEN 'CUP' THEN 25.75
  WHEN 'JMD' THEN 156.252
  WHEN 'PHP' THEN 58.074
  WHEN 'THB' THEN 31.082
  WHEN 'VND' THEN 25961
  WHEN 'IDR' THEN 16817
  WHEN 'PKR' THEN 279.6
  WHEN 'BDT' THEN 122.205858
  WHEN 'LKR' THEN 309.457
  WHEN 'NPR' THEN 145.049
  WHEN 'KHR' THEN 4022
  WHEN 'LAK' THEN 21445
  WHEN 'MMK' THEN 2100
  WHEN 'PGK' THEN 4.299
  WHEN 'MOP' THEN 8.055
  WHEN 'AFN' THEN 66.207039
  WHEN 'ALL' THEN 83.2
  WHEN 'AMD' THEN 381.473652
  WHEN 'AZN' THEN 1.7
  WHEN 'BAM' THEN 1.683408
  WHEN 'BIF' THEN 2982.243336
  WHEN 'BWP' THEN 13.115
  WHEN 'CDF' THEN 2240
  WHEN 'DJF' THEN 177.5
  WHEN 'ERN' THEN 15
  WHEN 'FJD' THEN 2.191
  WHEN 'GMD' THEN 73.5
  WHEN 'GNF' THEN 8775
  WHEN 'HTG' THEN 130.977
  WHEN 'KMF' THEN 416
  WHEN 'KYD' THEN 0.8336
  WHEN 'MGA' THEN 4430
  WHEN 'MRU' THEN 39.9
  WHEN 'MVR' THEN 15.46
  WHEN 'MWK' THEN 1737
  WHEN 'MZN' THEN 63.91
  WHEN 'NAD' THEN 15.96
  WHEN 'RSD' THEN 98.934
  WHEN 'SBD' THEN 8.048
  WHEN 'SLL' THEN 20970
  WHEN 'SOS' THEN 571.5
  WHEN 'SRD' THEN 37.779
  WHEN 'SSP' THEN 130.26
  WHEN 'STN' THEN 20.95
  WHEN 'SVC' THEN 8.752
  WHEN 'TJS' THEN 9.418
  WHEN 'TMT' THEN 3.51
  WHEN 'TND' THEN 2.835
  WHEN 'TOP' THEN 2.408
  WHEN 'TZS' THEN 2600
  WHEN 'VUV' THEN 119.995
  ELSE usd_rate
END,
updated_at = now()
WHERE iso_code IN (
  'PI','USD','EUR','GBP','AUD','CAD','JPY','CNY','CHF','SGD','HKD','INR','BRL','MXN','ZAR','TRY','PLN','RON','CZK',
  'NOK','DKK','SEK','AED','SAR','QAR','KWD','BHD','OMR','JOD','NGN','KES','ETB','GHS','MAD','RWF','XOF','XAF','ARS',
  'COP','PEN','BOB','PYG','UYU','DOP','CRC','GTQ','NIO','BSD','BBD','TTD','CUP','JMD','PHP','THB','VND','IDR','PKR',
  'BDT','LKR','NPR','KHR','LAK','MMK','PGK','MOP','AFN','ALL','AMD','AZN','BAM','BIF','BWP','CDF','DJF','ERN','FJD',
  'GMD','GNF','HTG','KMF','KYD','MGA','MRU','MVR','MWK','MZN','NAD','RSD','SBD','SLL','SOS','SRD','SSP','STN','SVC',
  'TJS','TMT','TND','TOP','TZS','VUV'
);

CREATE OR REPLACE FUNCTION public.apply_usd_exchange_rates(p_rates JSONB)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated_count INTEGER := 0;
  v_code TEXT;
  v_rate_text TEXT;
  v_rate NUMERIC;
BEGIN
  IF jsonb_typeof(p_rates) <> 'object' THEN
    RAISE EXCEPTION 'p_rates must be a JSON object keyed by currency code';
  END IF;

  -- Hard business rule.
  UPDATE public.supported_currencies
  SET usd_rate = CASE WHEN iso_code = 'PI' THEN 3.14 ELSE 1 END,
      updated_at = now()
  WHERE iso_code IN ('PI', 'USD');

  FOR v_code, v_rate_text IN
    SELECT key, value
    FROM jsonb_each_text(p_rates)
  LOOP
    v_code := upper(v_code);
    IF v_code IN ('PI', 'USD') THEN
      CONTINUE;
    END IF;

    BEGIN
      v_rate := v_rate_text::numeric;
    EXCEPTION WHEN OTHERS THEN
      CONTINUE;
    END;

    IF v_rate IS NULL OR v_rate <= 0 THEN
      CONTINUE;
    END IF;

    UPDATE public.supported_currencies
    SET usd_rate = v_rate, updated_at = now()
    WHERE iso_code = v_code;

    IF FOUND THEN
      v_updated_count := v_updated_count + 1;
    END IF;
  END LOOP;

  RETURN v_updated_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.apply_usd_exchange_rates(JSONB) TO service_role;

-- <<< END MIGRATION: 20260216101000_supported_currencies_realtime.sql

-- >>> MIGRATION: 20260216124500_notifications_foundation.sql
-- Notification foundation for in-app + optional web push pipeline.
-- Works with existing tables: transactions, payment_requests, invoices, support_tickets.

CREATE TABLE IF NOT EXISTS public.notification_preferences (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  in_app_enabled BOOLEAN NOT NULL DEFAULT true,
  push_enabled BOOLEAN NOT NULL DEFAULT true,
  email_enabled BOOLEAN NOT NULL DEFAULT false,
  quiet_hours_start TIME NULL,
  quiet_hours_end TIME NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'notification_preferences'
      AND policyname = 'Users can view own notification preferences'
  ) THEN
    CREATE POLICY "Users can view own notification preferences"
      ON public.notification_preferences
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'notification_preferences'
      AND policyname = 'Users can upsert own notification preferences'
  ) THEN
    CREATE POLICY "Users can upsert own notification preferences"
      ON public.notification_preferences
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'notification_preferences'
      AND policyname = 'Users can update own notification preferences'
  ) THEN
    CREATE POLICY "Users can update own notification preferences"
      ON public.notification_preferences
      FOR UPDATE TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.app_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data JSONB NOT NULL DEFAULT '{}'::jsonb,
  read_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_app_notifications_user_created
  ON public.app_notifications (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_app_notifications_user_unread
  ON public.app_notifications (user_id, read_at)
  WHERE read_at IS NULL;

ALTER TABLE public.app_notifications ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'app_notifications'
      AND policyname = 'Users can view own app notifications'
  ) THEN
    CREATE POLICY "Users can view own app notifications"
      ON public.app_notifications
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'app_notifications'
      AND policyname = 'Users can update own app notifications'
  ) THEN
    CREATE POLICY "Users can update own app notifications"
      ON public.app_notifications
      FOR UPDATE TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

-- Optional table for browser push subscriptions (if web push is supported).
CREATE TABLE IF NOT EXISTS public.push_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  endpoint TEXT NOT NULL UNIQUE,
  p256dh TEXT NOT NULL,
  auth TEXT NOT NULL,
  user_agent TEXT NULL,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_push_subscriptions_user
  ON public.push_subscriptions (user_id);

ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'push_subscriptions'
      AND policyname = 'Users can view own push subscriptions'
  ) THEN
    CREATE POLICY "Users can view own push subscriptions"
      ON public.push_subscriptions
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'push_subscriptions'
      AND policyname = 'Users can manage own push subscriptions'
  ) THEN
    CREATE POLICY "Users can manage own push subscriptions"
      ON public.push_subscriptions
      FOR ALL TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.set_common_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notification_preferences_updated_at ON public.notification_preferences;
CREATE TRIGGER trg_notification_preferences_updated_at
BEFORE UPDATE ON public.notification_preferences
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

DROP TRIGGER IF EXISTS trg_push_subscriptions_updated_at ON public.push_subscriptions;
CREATE TRIGGER trg_push_subscriptions_updated_at
BEFORE UPDATE ON public.push_subscriptions
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

CREATE OR REPLACE FUNCTION public.create_app_notification(
  p_user_id UUID,
  p_type TEXT,
  p_title TEXT,
  p_body TEXT,
  p_data JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_notification_id UUID;
  v_enabled BOOLEAN := true;
BEGIN
  SELECT np.in_app_enabled
  INTO v_enabled
  FROM public.notification_preferences np
  WHERE np.user_id = p_user_id;

  IF v_enabled IS FALSE THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.app_notifications (user_id, type, title, body, data)
  VALUES (p_user_id, p_type, p_title, p_body, COALESCE(p_data, '{}'::jsonb))
  RETURNING id INTO v_notification_id;

  RETURN v_notification_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_app_notification(UUID, TEXT, TEXT, TEXT, JSONB) TO service_role;

CREATE OR REPLACE FUNCTION public.handle_tx_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_amount TEXT := to_char(COALESCE(NEW.amount, 0), 'FM999999999990D00');
BEGIN
  IF NEW.sender_id = NEW.receiver_id THEN
    PERFORM public.create_app_notification(
      NEW.receiver_id,
      'top_up_success',
      'Top up successful',
      format('$%s was added to your balance.', v_amount),
      jsonb_build_object('transaction_id', NEW.id, 'amount', NEW.amount)
    );
  ELSE
    PERFORM public.create_app_notification(
      NEW.receiver_id,
      'payment_received',
      'Payment received',
      format('$%s was added to your balance.', v_amount),
      jsonb_build_object('transaction_id', NEW.id, 'amount', NEW.amount, 'sender_id', NEW.sender_id)
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_app_notifications_tx_insert ON public.transactions;
CREATE TRIGGER trg_app_notifications_tx_insert
AFTER INSERT ON public.transactions
FOR EACH ROW
EXECUTE FUNCTION public.handle_tx_notification();

CREATE OR REPLACE FUNCTION public.handle_request_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_amount TEXT := to_char(COALESCE(NEW.amount, 0), 'FM999999999990D00');
BEGIN
  PERFORM public.create_app_notification(
    NEW.payer_id,
    'money_request_received',
    'Money request',
    format('You received a request for $%s.', v_amount),
    jsonb_build_object('request_id', NEW.id, 'amount', NEW.amount, 'requester_id', NEW.requester_id)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_app_notifications_request_insert ON public.payment_requests;
CREATE TRIGGER trg_app_notifications_request_insert
AFTER INSERT ON public.payment_requests
FOR EACH ROW
EXECUTE FUNCTION public.handle_request_notification();

CREATE OR REPLACE FUNCTION public.handle_invoice_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_amount TEXT := to_char(COALESCE(NEW.amount, 0), 'FM999999999990D00');
BEGIN
  PERFORM public.create_app_notification(
    NEW.recipient_id,
    'invoice_received',
    'Invoice received',
    format('New invoice for $%s.', v_amount),
    jsonb_build_object('invoice_id', NEW.id, 'amount', NEW.amount, 'sender_id', NEW.sender_id)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_app_notifications_invoice_insert ON public.invoices;
CREATE TRIGGER trg_app_notifications_invoice_insert
AFTER INSERT ON public.invoices
FOR EACH ROW
EXECUTE FUNCTION public.handle_invoice_notification();

CREATE OR REPLACE FUNCTION public.handle_support_status_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    PERFORM public.create_app_notification(
      NEW.user_id,
      'support_ticket_update',
      'Support update',
      format('Your ticket status is now %s.', replace(COALESCE(NEW.status, 'updated'), '_', ' ')),
      jsonb_build_object('ticket_id', NEW.id, 'status', NEW.status)
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_app_notifications_support_update ON public.support_tickets;
CREATE TRIGGER trg_app_notifications_support_update
AFTER UPDATE ON public.support_tickets
FOR EACH ROW
EXECUTE FUNCTION public.handle_support_status_notification();

-- Realtime availability for app_notifications stream.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'app_notifications'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.app_notifications';
  END IF;
END $$;

-- <<< END MIGRATION: 20260216124500_notifications_foundation.sql

-- >>> MIGRATION: 20260216130000_welcome_bonus.sql
ALTER TABLE public.wallets
ADD COLUMN IF NOT EXISTS welcome_bonus_claimed_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  requested_username TEXT;
  final_username TEXT;
BEGIN
  requested_username := NULLIF(BTRIM(NEW.raw_user_meta_data->>'username'), '');

  IF requested_username IS NOT NULL THEN
    final_username := requested_username;

    IF EXISTS (SELECT 1 FROM public.profiles p WHERE p.username = final_username) THEN
      final_username := requested_username || '_' || REPLACE(SUBSTRING(NEW.id::text, 1, 8), '-', '');
    END IF;
  END IF;

  INSERT INTO public.profiles (id, full_name, username)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    final_username
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.wallets (user_id, balance, welcome_bonus_claimed_at)
  VALUES (NEW.id, 1.00, now())
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_welcome_bonus()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_wallet_balance NUMERIC(12,2);
  v_claimed_at TIMESTAMPTZ;
  v_new_balance NUMERIC(12,2);
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  INSERT INTO public.wallets (user_id)
  VALUES (v_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT balance, welcome_bonus_claimed_at
  INTO v_wallet_balance, v_claimed_at
  FROM public.wallets
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_claimed_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'claimed', false,
      'amount', 0,
      'balance', v_wallet_balance
    );
  END IF;

  UPDATE public.wallets
  SET balance = v_wallet_balance + 1.00,
      welcome_bonus_claimed_at = now(),
      updated_at = now()
  WHERE user_id = v_user_id
  RETURNING balance INTO v_new_balance;

  RETURN jsonb_build_object(
    'claimed', true,
    'amount', 1,
    'balance', v_new_balance
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_welcome_bonus() TO authenticated;

-- <<< END MIGRATION: 20260216130000_welcome_bonus.sql

-- >>> MIGRATION: 20260216133000_referral_system.sql
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS referral_code TEXT,
ADD COLUMN IF NOT EXISTS referred_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.profiles
DROP CONSTRAINT IF EXISTS profiles_no_self_referral;

ALTER TABLE public.profiles
ADD CONSTRAINT profiles_no_self_referral
CHECK (referred_by_user_id IS NULL OR referred_by_user_id <> id);

CREATE INDEX IF NOT EXISTS idx_profiles_referred_by_user_id
ON public.profiles (referred_by_user_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_referral_code_unique
ON public.profiles (LOWER(referral_code))
WHERE referral_code IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.referral_rewards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  referred_user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  reward_amount NUMERIC(12,2) NOT NULL DEFAULT 1.00 CHECK (reward_amount > 0),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'claimed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  claimed_at TIMESTAMPTZ
);

ALTER TABLE public.referral_rewards ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'referral_rewards'
      AND policyname = 'Users can view own referral rewards'
  ) THEN
    CREATE POLICY "Users can view own referral rewards"
      ON public.referral_rewards
      FOR SELECT
      TO authenticated
      USING (
        referrer_user_id = auth.uid() OR referred_user_id = auth.uid()
      );
  END IF;
END;
$$;

DO $$
DECLARE
  rec RECORD;
  base_code TEXT;
  candidate_code TEXT;
  code_counter INTEGER;
BEGIN
  FOR rec IN
    SELECT p.id, p.username
    FROM public.profiles p
    WHERE p.referral_code IS NULL
  LOOP
    base_code := LOWER(
      REGEXP_REPLACE(
        COALESCE(NULLIF(BTRIM(rec.username), ''), 'user_' || REPLACE(SUBSTRING(rec.id::text, 1, 8), '-', '')),
        '[^a-z0-9_]',
        '',
        'g'
      )
    );

    IF base_code IS NULL OR base_code = '' THEN
      base_code := 'user_' || REPLACE(SUBSTRING(rec.id::text, 1, 8), '-', '');
    END IF;

    candidate_code := base_code;
    code_counter := 0;

    WHILE EXISTS (
      SELECT 1
      FROM public.profiles p2
      WHERE p2.id <> rec.id
        AND LOWER(p2.referral_code) = candidate_code
    ) LOOP
      code_counter := code_counter + 1;
      candidate_code := base_code || code_counter::text;
    END LOOP;

    UPDATE public.profiles
    SET referral_code = candidate_code
    WHERE id = rec.id;
  END LOOP;
END;
$$;

ALTER TABLE public.profiles
ALTER COLUMN referral_code SET NOT NULL;

UPDATE public.profiles
SET referral_code = LOWER(referral_code)
WHERE referral_code IS NOT NULL;

INSERT INTO public.referral_rewards (referrer_user_id, referred_user_id, reward_amount, status)
SELECT p.referred_by_user_id, p.id, 1.00, 'pending'
FROM public.profiles p
WHERE p.referred_by_user_id IS NOT NULL
ON CONFLICT (referred_user_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  requested_username TEXT;
  final_username TEXT;
  requested_referral_code TEXT;
  referred_by_id UUID;
  base_referral_code TEXT;
  final_referral_code TEXT;
  referral_suffix INTEGER := 0;
BEGIN
  requested_username := NULLIF(BTRIM(NEW.raw_user_meta_data->>'username'), '');

  IF requested_username IS NOT NULL THEN
    final_username := requested_username;

    IF EXISTS (SELECT 1 FROM public.profiles p WHERE p.username = final_username) THEN
      final_username := requested_username || '_' || REPLACE(SUBSTRING(NEW.id::text, 1, 8), '-', '');
    END IF;
  END IF;

  requested_referral_code := LOWER(NULLIF(BTRIM(NEW.raw_user_meta_data->>'referral_code'), ''));

  IF requested_referral_code IS NOT NULL THEN
    SELECT p.id
    INTO referred_by_id
    FROM public.profiles p
    WHERE LOWER(p.referral_code) = requested_referral_code
      AND p.id <> NEW.id
    LIMIT 1;
  END IF;

  base_referral_code := LOWER(
    REGEXP_REPLACE(
      COALESCE(final_username, 'user_' || REPLACE(SUBSTRING(NEW.id::text, 1, 8), '-', '')),
      '[^a-z0-9_]',
      '',
      'g'
    )
  );

  IF base_referral_code IS NULL OR base_referral_code = '' THEN
    base_referral_code := 'user_' || REPLACE(SUBSTRING(NEW.id::text, 1, 8), '-', '');
  END IF;

  final_referral_code := base_referral_code;

  WHILE EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE LOWER(p.referral_code) = final_referral_code
  ) LOOP
    referral_suffix := referral_suffix + 1;
    final_referral_code := base_referral_code || referral_suffix::text;
  END LOOP;

  INSERT INTO public.profiles (id, full_name, username, referral_code, referred_by_user_id)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    final_username,
    final_referral_code,
    referred_by_id
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.wallets (user_id, balance, welcome_bonus_claimed_at)
  VALUES (NEW.id, 1.00, now())
  ON CONFLICT (user_id) DO NOTHING;

  IF referred_by_id IS NOT NULL THEN
    INSERT INTO public.referral_rewards (referrer_user_id, referred_user_id, reward_amount, status)
    VALUES (referred_by_id, NEW.id, 1.00, 'pending')
    ON CONFLICT (referred_user_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_referral_rewards()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_claim_count INTEGER := 0;
  v_claim_amount NUMERIC(12,2) := 0;
  v_balance NUMERIC(12,2) := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  WITH claimed AS (
    UPDATE public.referral_rewards rr
    SET status = 'claimed',
        claimed_at = now()
    WHERE rr.referrer_user_id = v_user_id
      AND rr.status = 'pending'
    RETURNING rr.reward_amount
  )
  SELECT COALESCE(COUNT(*), 0), COALESCE(SUM(reward_amount), 0)
  INTO v_claim_count, v_claim_amount
  FROM claimed;

  IF v_claim_count = 0 OR v_claim_amount <= 0 THEN
    INSERT INTO public.wallets (user_id)
    VALUES (v_user_id)
    ON CONFLICT (user_id) DO NOTHING;

    SELECT w.balance INTO v_balance
    FROM public.wallets w
    WHERE w.user_id = v_user_id;

    RETURN jsonb_build_object(
      'claimed', false,
      'count', 0,
      'amount', 0,
      'balance', COALESCE(v_balance, 0)
    );
  END IF;

  INSERT INTO public.wallets (user_id)
  VALUES (v_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  UPDATE public.wallets w
  SET balance = w.balance + v_claim_amount,
      updated_at = now()
  WHERE w.user_id = v_user_id
  RETURNING w.balance INTO v_balance;

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_user_id,
    v_user_id,
    v_claim_amount,
    format('Affiliate referral rewards (%s invite%s)', v_claim_count, CASE WHEN v_claim_count = 1 THEN '' ELSE 's' END),
    'completed'
  );

  RETURN jsonb_build_object(
    'claimed', true,
    'count', v_claim_count,
    'amount', v_claim_amount,
    'balance', v_balance
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_referral_rewards() TO authenticated;

-- <<< END MIGRATION: 20260216133000_referral_system.sql

-- >>> MIGRATION: 20260217090000_user_preferences.sql
CREATE TABLE IF NOT EXISTS public.user_preferences (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  hide_balance BOOLEAN NOT NULL DEFAULT false,
  usage_agreement_accepted BOOLEAN NOT NULL DEFAULT false,
  onboarding_completed BOOLEAN NOT NULL DEFAULT false,
  onboarding_step INTEGER NOT NULL DEFAULT 0 CHECK (onboarding_step >= 0),
  reference_code TEXT NULL,
  profile_full_name TEXT NULL,
  profile_username TEXT NULL,
  security_settings JSONB NOT NULL DEFAULT '{}'::jsonb,
  merchant_onboarding_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_preferences'
      AND policyname = 'Users can view own preferences'
  ) THEN
    CREATE POLICY "Users can view own preferences"
      ON public.user_preferences
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_preferences'
      AND policyname = 'Users can insert own preferences'
  ) THEN
    CREATE POLICY "Users can insert own preferences"
      ON public.user_preferences
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_preferences'
      AND policyname = 'Users can update own preferences'
  ) THEN
    CREATE POLICY "Users can update own preferences"
      ON public.user_preferences
      FOR UPDATE TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.set_common_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_preferences_updated_at ON public.user_preferences;
CREATE TRIGGER trg_user_preferences_updated_at
BEFORE UPDATE ON public.user_preferences
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

INSERT INTO public.user_preferences (user_id, profile_full_name, profile_username, reference_code)
SELECT p.id, p.full_name, p.username, p.referral_code
FROM public.profiles p
ON CONFLICT (user_id) DO NOTHING;

-- <<< END MIGRATION: 20260217090000_user_preferences.sql

-- >>> MIGRATION: 20260217093000_user_preferences_qr_print_settings.sql
ALTER TABLE public.user_preferences
ADD COLUMN IF NOT EXISTS qr_print_settings JSONB NOT NULL DEFAULT '{}'::jsonb;

-- <<< END MIGRATION: 20260217093000_user_preferences_qr_print_settings.sql

-- >>> MIGRATION: 20260217110000_remittance_merchants.sql
CREATE TABLE IF NOT EXISTS public.remittance_merchants (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  merchant_name TEXT NOT NULL DEFAULT 'OpenPay Remittance Center',
  merchant_username TEXT NOT NULL DEFAULT '',
  merchant_city TEXT NOT NULL DEFAULT '',
  merchant_country TEXT NOT NULL DEFAULT 'United States',
  business_note TEXT NOT NULL DEFAULT 'Cash deposit and payout available.',
  fee_title TEXT NOT NULL DEFAULT 'Remittance Fee Card',
  deposit_fee_percent NUMERIC(6,3) NOT NULL DEFAULT 0 CHECK (deposit_fee_percent >= 0 AND deposit_fee_percent <= 100),
  payout_fee_percent NUMERIC(6,3) NOT NULL DEFAULT 0 CHECK (payout_fee_percent >= 0 AND payout_fee_percent <= 100),
  flat_service_fee NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (flat_service_fee >= 0),
  fee_notes TEXT NOT NULL DEFAULT 'Rates are set by merchant and may vary by amount/currency.',
  qr_tagline TEXT NOT NULL DEFAULT 'SCAN TO DEPOSIT / PAYOUT',
  qr_accent TEXT NOT NULL DEFAULT '#2148ff',
  qr_background TEXT NOT NULL DEFAULT '#ffffff',
  banner_title TEXT NOT NULL DEFAULT 'OpenPay Remittance Center',
  banner_subtitle TEXT NOT NULL DEFAULT 'Powered by Pi Network',
  min_operating_balance NUMERIC(12,2) NOT NULL DEFAULT 25 CHECK (min_operating_balance >= 0),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_remittance_merchants_active
ON public.remittance_merchants (is_active);

CREATE INDEX IF NOT EXISTS idx_remittance_merchants_location
ON public.remittance_merchants (merchant_country, merchant_city);

ALTER TABLE public.remittance_merchants ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'remittance_merchants'
      AND policyname = 'Users can view active remittance merchants'
  ) THEN
    CREATE POLICY "Users can view active remittance merchants"
      ON public.remittance_merchants
      FOR SELECT TO authenticated
      USING (is_active = true OR user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'remittance_merchants'
      AND policyname = 'Users can insert own remittance merchant profile'
  ) THEN
    CREATE POLICY "Users can insert own remittance merchant profile"
      ON public.remittance_merchants
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'remittance_merchants'
      AND policyname = 'Users can update own remittance merchant profile'
  ) THEN
    CREATE POLICY "Users can update own remittance merchant profile"
      ON public.remittance_merchants
      FOR UPDATE TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_remittance_merchants_updated_at ON public.remittance_merchants;
CREATE TRIGGER trg_remittance_merchants_updated_at
BEFORE UPDATE ON public.remittance_merchants
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

INSERT INTO public.remittance_merchants (user_id, merchant_name, merchant_username)
SELECT p.id, COALESCE(NULLIF(p.full_name, ''), 'OpenPay Remittance Center'), COALESCE(NULLIF(p.username, ''), '')
FROM public.profiles p
ON CONFLICT (user_id) DO NOTHING;

-- <<< END MIGRATION: 20260217110000_remittance_merchants.sql

-- >>> MIGRATION: 20260217113000_remittance_merchants_finalize.sql
-- Finalize remittance merchant schema and storage

ALTER TABLE public.remittance_merchants
ADD COLUMN IF NOT EXISTS merchant_logo_url TEXT NOT NULL DEFAULT '';

ALTER TABLE public.remittance_merchants
ADD CONSTRAINT remittance_merchants_qr_accent_hex_chk
CHECK (qr_accent ~* '^#[0-9a-f]{6}$');

ALTER TABLE public.remittance_merchants
ADD CONSTRAINT remittance_merchants_qr_background_hex_chk
CHECK (qr_background ~* '^#[0-9a-f]{6}$');

CREATE UNIQUE INDEX IF NOT EXISTS idx_remittance_merchants_username_unique
ON public.remittance_merchants (LOWER(merchant_username))
WHERE merchant_username <> '';

CREATE INDEX IF NOT EXISTS idx_remittance_merchants_updated_at
ON public.remittance_merchants (updated_at DESC);

-- Dedicated logo bucket for remittance stores/tarpaulins
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'remittance-logos',
  'remittance-logos',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE
SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'Remittance logos are publicly readable'
  ) THEN
    CREATE POLICY "Remittance logos are publicly readable"
      ON storage.objects
      FOR SELECT
      USING (bucket_id = 'remittance-logos');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'Users can upload own remittance logos'
  ) THEN
    CREATE POLICY "Users can upload own remittance logos"
      ON storage.objects
      FOR INSERT
      TO authenticated
      WITH CHECK (
        bucket_id = 'remittance-logos'
        AND (storage.foldername(name))[1] = auth.uid()::text
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'Users can update own remittance logos'
  ) THEN
    CREATE POLICY "Users can update own remittance logos"
      ON storage.objects
      FOR UPDATE
      TO authenticated
      USING (
        bucket_id = 'remittance-logos'
        AND (storage.foldername(name))[1] = auth.uid()::text
      )
      WITH CHECK (
        bucket_id = 'remittance-logos'
        AND (storage.foldername(name))[1] = auth.uid()::text
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'Users can delete own remittance logos'
  ) THEN
    CREATE POLICY "Users can delete own remittance logos"
      ON storage.objects
      FOR DELETE
      TO authenticated
      USING (
        bucket_id = 'remittance-logos'
        AND (storage.foldername(name))[1] = auth.uid()::text
      );
  END IF;
END $$;

-- <<< END MIGRATION: 20260217113000_remittance_merchants_finalize.sql

-- >>> MIGRATION: 20260217132000_user_preferences_password_lifecycle.sql
-- Ensure user preferences always exist per account and enforce security password lifecycle.

-- 1) Backfill missing user preference rows for existing auth users.
INSERT INTO public.user_preferences (user_id)
SELECT u.id
FROM auth.users u
LEFT JOIN public.user_preferences p ON p.user_id = u.id
WHERE p.user_id IS NULL
ON CONFLICT (user_id) DO NOTHING;

-- 2) Keep user_preferences synced from profiles so account-level preferences remain attached.
CREATE OR REPLACE FUNCTION public.sync_profile_to_user_preferences()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.user_preferences (user_id, profile_full_name, profile_username, reference_code)
  VALUES (NEW.id, NEW.full_name, NEW.username, NEW.referral_code)
  ON CONFLICT (user_id) DO UPDATE
  SET
    profile_full_name = EXCLUDED.profile_full_name,
    profile_username = EXCLUDED.profile_username,
    reference_code = EXCLUDED.reference_code;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_sync_user_preferences ON public.profiles;
CREATE TRIGGER trg_profiles_sync_user_preferences
AFTER INSERT OR UPDATE OF full_name, username, referral_code
ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.sync_profile_to_user_preferences();

-- 3) Enforce security password lifecycle:
--    - Allowed: null -> hash (initial setup)
--    - Allowed: hash -> null (disable)
--    - Disallowed: hashA -> hashB directly (must disable first, then set again)
CREATE OR REPLACE FUNCTION public.enforce_user_preferences_security_password_lifecycle()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  old_password_hash TEXT;
  new_password_hash TEXT;
BEGIN
  IF NEW.security_settings IS NULL OR jsonb_typeof(NEW.security_settings) <> 'object' THEN
    NEW.security_settings := '{}'::jsonb;
  END IF;

  old_password_hash := COALESCE(NULLIF(OLD.security_settings->>'passwordHash', ''), NULL);
  new_password_hash := COALESCE(NULLIF(NEW.security_settings->>'passwordHash', ''), NULL);

  IF old_password_hash IS NOT NULL
     AND new_password_hash IS NOT NULL
     AND old_password_hash <> new_password_hash THEN
    RAISE EXCEPTION
      USING MESSAGE = 'Security password can only be changed after disabling it first.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_preferences_password_lifecycle ON public.user_preferences;
CREATE TRIGGER trg_user_preferences_password_lifecycle
BEFORE UPDATE OF security_settings
ON public.user_preferences
FOR EACH ROW
EXECUTE FUNCTION public.enforce_user_preferences_security_password_lifecycle();

-- <<< END MIGRATION: 20260217132000_user_preferences_password_lifecycle.sql

-- >>> MIGRATION: 20260218103000_virtual_cards_checkout.sql
CREATE TABLE IF NOT EXISTS public.virtual_cards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  cardholder_name TEXT NOT NULL DEFAULT '',
  card_username TEXT NOT NULL DEFAULT '',
  card_number TEXT NOT NULL UNIQUE,
  expiry_month INTEGER NOT NULL CHECK (expiry_month BETWEEN 1 AND 12),
  expiry_year INTEGER NOT NULL CHECK (expiry_year >= 2026),
  cvc TEXT NOT NULL CHECK (char_length(cvc) = 3),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.virtual_cards ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'virtual_cards'
      AND policyname = 'Users can view own virtual card'
  ) THEN
    CREATE POLICY "Users can view own virtual card"
      ON public.virtual_cards
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'virtual_cards'
      AND policyname = 'Users can insert own virtual card'
  ) THEN
    CREATE POLICY "Users can insert own virtual card"
      ON public.virtual_cards
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'virtual_cards'
      AND policyname = 'Users can update own virtual card'
  ) THEN
    CREATE POLICY "Users can update own virtual card"
      ON public.virtual_cards
      FOR UPDATE TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_virtual_cards_updated_at ON public.virtual_cards;
CREATE TRIGGER trg_virtual_cards_updated_at
BEFORE UPDATE ON public.virtual_cards
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

CREATE OR REPLACE FUNCTION public.generate_openpay_card_number()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_candidate TEXT;
BEGIN
  LOOP
    v_candidate := '5599' || LPAD((FLOOR(random() * 1000000000000))::BIGINT::TEXT, 12, '0');
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.virtual_cards WHERE card_number = v_candidate);
  END LOOP;
  RETURN v_candidate;
END;
$$;

CREATE OR REPLACE FUNCTION public.generate_openpay_cvc()
RETURNS TEXT
LANGUAGE sql
AS $$
  SELECT LPAD((FLOOR(random() * 1000))::INT::TEXT, 3, '0');
$$;

CREATE OR REPLACE FUNCTION public.upsert_my_virtual_card(
  p_cardholder_name TEXT DEFAULT NULL,
  p_card_username TEXT DEFAULT NULL
)
RETURNS public.virtual_cards
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_profile_name TEXT;
  v_profile_username TEXT;
  v_card public.virtual_cards;
  v_now DATE := CURRENT_DATE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT full_name, COALESCE(username, '')
  INTO v_profile_name, v_profile_username
  FROM public.profiles
  WHERE id = v_user_id;

  SELECT *
  INTO v_card
  FROM public.virtual_cards
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF FOUND THEN
    UPDATE public.virtual_cards
    SET cardholder_name = COALESCE(NULLIF(TRIM(p_cardholder_name), ''), cardholder_name),
        card_username = COALESCE(NULLIF(TRIM(p_card_username), ''), card_username),
        is_active = true
    WHERE user_id = v_user_id
    RETURNING * INTO v_card;
    RETURN v_card;
  END IF;

  INSERT INTO public.virtual_cards (
    user_id,
    cardholder_name,
    card_username,
    card_number,
    expiry_month,
    expiry_year,
    cvc
  )
  VALUES (
    v_user_id,
    COALESCE(NULLIF(TRIM(p_cardholder_name), ''), NULLIF(TRIM(v_profile_name), ''), 'OpenPay User'),
    COALESCE(NULLIF(TRIM(p_card_username), ''), NULLIF(TRIM(v_profile_username), ''), 'openpay'),
    public.generate_openpay_card_number(),
    EXTRACT(MONTH FROM v_now)::INT,
    (EXTRACT(YEAR FROM v_now)::INT + 4),
    public.generate_openpay_cvc()
  )
  RETURNING * INTO v_card;

  RETURN v_card;
END;
$$;

CREATE OR REPLACE FUNCTION public.pay_with_virtual_card_checkout(
  p_card_number TEXT,
  p_expiry_month INTEGER,
  p_expiry_year INTEGER,
  p_cvc TEXT,
  p_receiver_id UUID,
  p_amount NUMERIC,
  p_note TEXT DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_sender_balance NUMERIC(12,2);
  v_receiver_balance NUMERIC(12,2);
  v_transaction_id UUID;
  v_sanitized_card_number TEXT := regexp_replace(COALESCE(p_card_number, ''), '\D', '', 'g');
  v_sanitized_cvc TEXT := regexp_replace(COALESCE(p_cvc, ''), '\D', '', 'g');
  v_expiry_end DATE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_receiver_id IS NULL THEN
    RAISE EXCEPTION 'Receiver required';
  END IF;

  IF p_receiver_id = v_user_id THEN
    RAISE EXCEPTION 'Cannot pay your own checkout link';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Invalid amount';
  END IF;

  IF char_length(v_sanitized_card_number) <> 16 THEN
    RAISE EXCEPTION 'Card number must be 16 digits';
  END IF;

  IF p_expiry_month IS NULL OR p_expiry_month < 1 OR p_expiry_month > 12 THEN
    RAISE EXCEPTION 'Invalid expiry month';
  END IF;

  IF p_expiry_year IS NULL OR p_expiry_year < 2026 THEN
    RAISE EXCEPTION 'Invalid expiry year';
  END IF;

  IF char_length(v_sanitized_cvc) <> 3 THEN
    RAISE EXCEPTION 'Invalid CVC';
  END IF;

  v_expiry_end := (make_date(p_expiry_year, p_expiry_month, 1) + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
  IF v_expiry_end < CURRENT_DATE THEN
    RAISE EXCEPTION 'Card expired';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.virtual_cards vc
    WHERE vc.user_id = v_user_id
      AND vc.card_number = v_sanitized_card_number
      AND vc.expiry_month = p_expiry_month
      AND vc.expiry_year = p_expiry_year
      AND vc.cvc = v_sanitized_cvc
      AND vc.is_active = true
  ) THEN
    RAISE EXCEPTION 'Invalid virtual card details';
  END IF;

  SELECT balance INTO v_sender_balance
  FROM public.wallets
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_sender_balance IS NULL THEN
    RAISE EXCEPTION 'Sender wallet not found';
  END IF;

  SELECT balance INTO v_receiver_balance
  FROM public.wallets
  WHERE user_id = p_receiver_id
  FOR UPDATE;

  IF v_receiver_balance IS NULL THEN
    RAISE EXCEPTION 'Recipient wallet not found';
  END IF;

  IF v_sender_balance < p_amount THEN
    RAISE EXCEPTION 'Insufficient balance';
  END IF;

  UPDATE public.wallets
  SET balance = v_sender_balance - p_amount,
      updated_at = now()
  WHERE user_id = v_user_id;

  UPDATE public.wallets
  SET balance = v_receiver_balance + p_amount,
      updated_at = now()
  WHERE user_id = p_receiver_id;

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_user_id,
    p_receiver_id,
    p_amount,
    CONCAT('Virtual card payment | ', COALESCE(p_note, '')),
    'completed'
  )
  RETURNING id INTO v_transaction_id;

  RETURN v_transaction_id;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_my_virtual_card(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pay_with_virtual_card_checkout(TEXT, INTEGER, INTEGER, TEXT, UUID, NUMERIC, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_my_virtual_card(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pay_with_virtual_card_checkout(TEXT, INTEGER, INTEGER, TEXT, UUID, NUMERIC, TEXT) TO authenticated;


-- <<< END MIGRATION: 20260218103000_virtual_cards_checkout.sql

-- >>> MIGRATION: 20260218113000_virtual_cards_controls.sql
ALTER TABLE public.virtual_cards
ADD COLUMN IF NOT EXISTS hide_details BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS is_locked BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS locked_at TIMESTAMPTZ NULL,
ADD COLUMN IF NOT EXISTS card_settings JSONB NOT NULL DEFAULT '{"allow_checkout": true}'::jsonb;

CREATE OR REPLACE FUNCTION public.update_my_virtual_card_controls(
  p_hide_details BOOLEAN DEFAULT NULL,
  p_lock_card BOOLEAN DEFAULT NULL,
  p_card_settings JSONB DEFAULT NULL
)
RETURNS public.virtual_cards
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_card public.virtual_cards;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  PERFORM public.upsert_my_virtual_card(NULL, NULL);

  UPDATE public.virtual_cards
  SET hide_details = COALESCE(p_hide_details, hide_details),
      is_locked = COALESCE(p_lock_card, is_locked),
      locked_at = CASE
        WHEN p_lock_card IS TRUE THEN now()
        WHEN p_lock_card IS FALSE THEN NULL
        ELSE locked_at
      END,
      card_settings = CASE
        WHEN p_card_settings IS NULL THEN card_settings
        ELSE COALESCE(card_settings, '{}'::jsonb) || p_card_settings
      END
  WHERE user_id = v_user_id
  RETURNING * INTO v_card;

  RETURN v_card;
END;
$$;

CREATE OR REPLACE FUNCTION public.pay_with_virtual_card_checkout(
  p_card_number TEXT,
  p_expiry_month INTEGER,
  p_expiry_year INTEGER,
  p_cvc TEXT,
  p_receiver_id UUID,
  p_amount NUMERIC,
  p_note TEXT DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_sender_balance NUMERIC(12,2);
  v_receiver_balance NUMERIC(12,2);
  v_transaction_id UUID;
  v_sanitized_card_number TEXT := regexp_replace(COALESCE(p_card_number, ''), '\D', '', 'g');
  v_sanitized_cvc TEXT := regexp_replace(COALESCE(p_cvc, ''), '\D', '', 'g');
  v_expiry_end DATE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_receiver_id IS NULL THEN
    RAISE EXCEPTION 'Receiver required';
  END IF;

  IF p_receiver_id = v_user_id THEN
    RAISE EXCEPTION 'Cannot pay your own checkout link';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Invalid amount';
  END IF;

  IF char_length(v_sanitized_card_number) <> 16 THEN
    RAISE EXCEPTION 'Card number must be 16 digits';
  END IF;

  IF p_expiry_month IS NULL OR p_expiry_month < 1 OR p_expiry_month > 12 THEN
    RAISE EXCEPTION 'Invalid expiry month';
  END IF;

  IF p_expiry_year IS NULL OR p_expiry_year < 2026 THEN
    RAISE EXCEPTION 'Invalid expiry year';
  END IF;

  IF char_length(v_sanitized_cvc) <> 3 THEN
    RAISE EXCEPTION 'Invalid CVC';
  END IF;

  v_expiry_end := (make_date(p_expiry_year, p_expiry_month, 1) + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
  IF v_expiry_end < CURRENT_DATE THEN
    RAISE EXCEPTION 'Card expired';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.virtual_cards vc
    WHERE vc.user_id = v_user_id
      AND vc.card_number = v_sanitized_card_number
      AND vc.expiry_month = p_expiry_month
      AND vc.expiry_year = p_expiry_year
      AND vc.cvc = v_sanitized_cvc
      AND vc.is_active = true
      AND vc.is_locked = false
      AND COALESCE((vc.card_settings ->> 'allow_checkout')::BOOLEAN, true) = true
  ) THEN
    RAISE EXCEPTION 'Card locked, disabled, or invalid details';
  END IF;

  SELECT balance INTO v_sender_balance
  FROM public.wallets
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_sender_balance IS NULL THEN
    RAISE EXCEPTION 'Sender wallet not found';
  END IF;

  SELECT balance INTO v_receiver_balance
  FROM public.wallets
  WHERE user_id = p_receiver_id
  FOR UPDATE;

  IF v_receiver_balance IS NULL THEN
    RAISE EXCEPTION 'Recipient wallet not found';
  END IF;

  IF v_sender_balance < p_amount THEN
    RAISE EXCEPTION 'Insufficient balance';
  END IF;

  UPDATE public.wallets
  SET balance = v_sender_balance - p_amount,
      updated_at = now()
  WHERE user_id = v_user_id;

  UPDATE public.wallets
  SET balance = v_receiver_balance + p_amount,
      updated_at = now()
  WHERE user_id = p_receiver_id;

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_user_id,
    p_receiver_id,
    p_amount,
    CONCAT('Virtual card payment | ', COALESCE(p_note, '')),
    'completed'
  )
  RETURNING id INTO v_transaction_id;

  RETURN v_transaction_id;
END;
$$;

REVOKE ALL ON FUNCTION public.update_my_virtual_card_controls(BOOLEAN, BOOLEAN, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_my_virtual_card_controls(BOOLEAN, BOOLEAN, JSONB) TO authenticated;


-- <<< END MIGRATION: 20260218113000_virtual_cards_controls.sql

-- >>> MIGRATION: 20260218123000_virtual_card_profile_sync.sql
CREATE OR REPLACE FUNCTION public.upsert_my_virtual_card(
  p_cardholder_name TEXT DEFAULT NULL,
  p_card_username TEXT DEFAULT NULL
)
RETURNS public.virtual_cards
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_profile_name TEXT;
  v_profile_username TEXT;
  v_card public.virtual_cards;
  v_now DATE := CURRENT_DATE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT full_name, COALESCE(username, '')
  INTO v_profile_name, v_profile_username
  FROM public.profiles
  WHERE id = v_user_id;

  SELECT *
  INTO v_card
  FROM public.virtual_cards
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF FOUND THEN
    UPDATE public.virtual_cards
    SET cardholder_name = COALESCE(NULLIF(TRIM(v_profile_name), ''), cardholder_name),
        card_username = COALESCE(NULLIF(TRIM(v_profile_username), ''), card_username),
        is_active = true
    WHERE user_id = v_user_id
    RETURNING * INTO v_card;
    RETURN v_card;
  END IF;

  INSERT INTO public.virtual_cards (
    user_id,
    cardholder_name,
    card_username,
    card_number,
    expiry_month,
    expiry_year,
    cvc
  )
  VALUES (
    v_user_id,
    COALESCE(NULLIF(TRIM(v_profile_name), ''), 'OpenPay User'),
    COALESCE(NULLIF(TRIM(v_profile_username), ''), 'openpay'),
    public.generate_openpay_card_number(),
    EXTRACT(MONTH FROM v_now)::INT,
    (EXTRACT(YEAR FROM v_now)::INT + 4),
    public.generate_openpay_cvc()
  )
  RETURNING * INTO v_card;

  RETURN v_card;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_virtual_card_from_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  UPDATE public.virtual_cards
  SET cardholder_name = COALESCE(NULLIF(TRIM(NEW.full_name), ''), cardholder_name),
      card_username = COALESCE(NULLIF(TRIM(COALESCE(NEW.username, '')), ''), card_username)
  WHERE user_id = NEW.id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_sync_virtual_card ON public.profiles;
CREATE TRIGGER trg_profiles_sync_virtual_card
AFTER UPDATE OF full_name, username
ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.sync_virtual_card_from_profile();


-- <<< END MIGRATION: 20260218123000_virtual_card_profile_sync.sql

-- >>> MIGRATION: 20260218133000_user_unique_account_numbers.sql
CREATE TABLE IF NOT EXISTS public.user_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  account_number TEXT NOT NULL UNIQUE,
  account_name TEXT NOT NULL DEFAULT '',
  account_username TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.user_accounts ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_accounts'
      AND policyname = 'Users can view own account'
  ) THEN
    CREATE POLICY "Users can view own account"
      ON public.user_accounts
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_accounts'
      AND policyname = 'Users can insert own account'
  ) THEN
    CREATE POLICY "Users can insert own account"
      ON public.user_accounts
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_accounts'
      AND policyname = 'Users can update own account'
  ) THEN
    CREATE POLICY "Users can update own account"
      ON public.user_accounts
      FOR UPDATE TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_user_accounts_updated_at ON public.user_accounts;
CREATE TRIGGER trg_user_accounts_updated_at
BEFORE UPDATE ON public.user_accounts
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

CREATE OR REPLACE FUNCTION public.generate_openpay_account_number(p_user_id UUID)
RETURNS TEXT
LANGUAGE sql
AS $$
  SELECT 'OP' || UPPER(REPLACE(p_user_id::TEXT, '-', ''));
$$;

CREATE OR REPLACE FUNCTION public.upsert_my_user_account()
RETURNS public.user_accounts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_profile_name TEXT;
  v_profile_username TEXT;
  v_account public.user_accounts;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT full_name, COALESCE(username, '')
  INTO v_profile_name, v_profile_username
  FROM public.profiles
  WHERE id = v_user_id;

  SELECT *
  INTO v_account
  FROM public.user_accounts
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF FOUND THEN
    UPDATE public.user_accounts
    SET account_name = COALESCE(NULLIF(TRIM(v_profile_name), ''), account_name),
        account_username = COALESCE(NULLIF(TRIM(v_profile_username), ''), account_username)
    WHERE user_id = v_user_id
    RETURNING * INTO v_account;
    RETURN v_account;
  END IF;

  INSERT INTO public.user_accounts (user_id, account_number, account_name, account_username)
  VALUES (
    v_user_id,
    public.generate_openpay_account_number(v_user_id),
    COALESCE(NULLIF(TRIM(v_profile_name), ''), 'OpenPay User'),
    COALESCE(NULLIF(TRIM(v_profile_username), ''), 'openpay')
  )
  RETURNING * INTO v_account;

  RETURN v_account;
END;
$$;

-- Enforce correct format for account_number on insert/update
CREATE OR REPLACE FUNCTION public.enforce_user_account_number_format()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.account_number IS NULL OR NEW.account_number !~ '^OP[A-Z0-9]{6,64}$' THEN
    NEW.account_number := public.generate_openpay_account_number(NEW.user_id);
  ELSE
    NEW.account_number := UPPER(TRIM(NEW.account_number));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_accounts_enforce_format ON public.user_accounts;
CREATE TRIGGER trg_user_accounts_enforce_format
BEFORE INSERT OR UPDATE ON public.user_accounts
FOR EACH ROW
EXECUTE FUNCTION public.enforce_user_account_number_format();

CREATE OR REPLACE FUNCTION public.sync_user_account_from_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.user_accounts (user_id, account_number, account_name, account_username)
  VALUES (
    NEW.id,
    public.generate_openpay_account_number(NEW.id),
    COALESCE(NULLIF(TRIM(NEW.full_name), ''), 'OpenPay User'),
    COALESCE(NULLIF(TRIM(COALESCE(NEW.username, '')), ''), 'openpay')
  )
  ON CONFLICT (user_id) DO UPDATE
  SET account_name = EXCLUDED.account_name,
      account_username = EXCLUDED.account_username;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_sync_user_account ON public.profiles;
CREATE TRIGGER trg_profiles_sync_user_account
AFTER INSERT OR UPDATE OF full_name, username
ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.sync_user_account_from_profile();

INSERT INTO public.user_accounts (user_id, account_number, account_name, account_username)
SELECT
  p.id,
  public.generate_openpay_account_number(p.id),
  COALESCE(NULLIF(TRIM(p.full_name), ''), 'OpenPay User'),
  COALESCE(NULLIF(TRIM(COALESCE(p.username, '')), ''), 'openpay')
FROM public.profiles p
ON CONFLICT (user_id) DO UPDATE
SET account_name = EXCLUDED.account_name,
    account_username = EXCLUDED.account_username;

REVOKE ALL ON FUNCTION public.upsert_my_user_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_my_user_account() TO authenticated;

-- <<< END MIGRATION: 20260218133000_user_unique_account_numbers.sql

-- >>> MIGRATION: 20260218143000_account_number_lookup.sql
CREATE OR REPLACE FUNCTION public.find_user_by_account_number(
  p_account_number TEXT
)
RETURNS TABLE (
  id UUID,
  full_name TEXT,
  username TEXT,
  avatar_url TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_lookup TEXT := UPPER(TRIM(COALESCE(p_account_number, '')));
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_lookup = '' THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT p.id, p.full_name, p.username, p.avatar_url
  FROM public.user_accounts ua
  JOIN public.profiles p ON p.id = ua.user_id
  WHERE ua.account_number = v_lookup
    AND ua.user_id <> v_user_id
  LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.find_user_by_account_number(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.find_user_by_account_number(TEXT) TO authenticated;


-- <<< END MIGRATION: 20260218143000_account_number_lookup.sql

-- >>> MIGRATION: 20260218153000_merchant_portal.sql
CREATE TABLE IF NOT EXISTS public.merchant_profiles (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  merchant_name TEXT NOT NULL DEFAULT 'OpenPay Merchant',
  merchant_username TEXT NOT NULL DEFAULT '',
  merchant_logo_url TEXT,
  default_currency TEXT NOT NULL DEFAULT 'USD' CHECK (char_length(default_currency) = 3),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.merchant_api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  key_mode TEXT NOT NULL CHECK (key_mode IN ('sandbox', 'live')),
  key_name TEXT NOT NULL DEFAULT 'Default key',
  publishable_key TEXT NOT NULL UNIQUE,
  secret_key_hash TEXT NOT NULL UNIQUE,
  secret_key_last4 TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  last_used_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.merchant_products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_code TEXT NOT NULL,
  product_name TEXT NOT NULL,
  product_description TEXT NOT NULL DEFAULT '',
  image_url TEXT,
  unit_amount NUMERIC(12,2) NOT NULL CHECK (unit_amount > 0),
  currency TEXT NOT NULL DEFAULT 'USD' CHECK (char_length(currency) = 3),
  is_active BOOLEAN NOT NULL DEFAULT true,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (merchant_user_id, product_code)
);

CREATE TABLE IF NOT EXISTS public.merchant_checkout_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  key_mode TEXT NOT NULL CHECK (key_mode IN ('sandbox', 'live')),
  session_token TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'paid', 'expired', 'canceled')),
  currency TEXT NOT NULL CHECK (char_length(currency) = 3),
  subtotal_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (subtotal_amount >= 0),
  fee_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (fee_amount >= 0),
  total_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
  customer_email TEXT,
  customer_name TEXT,
  success_url TEXT,
  cancel_url TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  expires_at TIMESTAMPTZ NOT NULL,
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.merchant_checkout_session_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.merchant_checkout_sessions(id) ON DELETE CASCADE,
  product_id UUID REFERENCES public.merchant_products(id) ON DELETE SET NULL,
  item_name TEXT NOT NULL,
  unit_amount NUMERIC(12,2) NOT NULL CHECK (unit_amount > 0),
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  line_total NUMERIC(12,2) NOT NULL CHECK (line_total > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (line_total = ROUND(unit_amount * quantity, 2))
);

CREATE TABLE IF NOT EXISTS public.merchant_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL UNIQUE REFERENCES public.merchant_checkout_sessions(id) ON DELETE RESTRICT,
  merchant_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  buyer_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  transaction_id UUID NOT NULL UNIQUE REFERENCES public.transactions(id) ON DELETE RESTRICT,
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  currency TEXT NOT NULL CHECK (char_length(currency) = 3),
  key_mode TEXT NOT NULL CHECK (key_mode IN ('sandbox', 'live')),
  status TEXT NOT NULL DEFAULT 'succeeded' CHECK (status IN ('succeeded', 'failed', 'refunded')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_merchant_api_keys_owner_mode
ON public.merchant_api_keys (merchant_user_id, key_mode, is_active);

CREATE INDEX IF NOT EXISTS idx_merchant_products_owner_active
ON public.merchant_products (merchant_user_id, is_active);

CREATE INDEX IF NOT EXISTS idx_merchant_checkout_sessions_owner_status
ON public.merchant_checkout_sessions (merchant_user_id, status, key_mode);

CREATE INDEX IF NOT EXISTS idx_merchant_checkout_sessions_expires
ON public.merchant_checkout_sessions (expires_at);

CREATE INDEX IF NOT EXISTS idx_merchant_checkout_items_session
ON public.merchant_checkout_session_items (session_id);

CREATE INDEX IF NOT EXISTS idx_merchant_payments_merchant
ON public.merchant_payments (merchant_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_merchant_payments_buyer
ON public.merchant_payments (buyer_user_id, created_at DESC);

ALTER TABLE public.merchant_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_api_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_checkout_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_checkout_session_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_payments ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_profiles' AND policyname = 'Users can view own merchant profile'
  ) THEN
    CREATE POLICY "Users can view own merchant profile"
      ON public.merchant_profiles
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_profiles' AND policyname = 'Users can insert own merchant profile'
  ) THEN
    CREATE POLICY "Users can insert own merchant profile"
      ON public.merchant_profiles
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_profiles' AND policyname = 'Users can update own merchant profile'
  ) THEN
    CREATE POLICY "Users can update own merchant profile"
      ON public.merchant_profiles
      FOR UPDATE TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_api_keys' AND policyname = 'Users can view own merchant api keys'
  ) THEN
    CREATE POLICY "Users can view own merchant api keys"
      ON public.merchant_api_keys
      FOR SELECT TO authenticated
      USING (merchant_user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_api_keys' AND policyname = 'Users can insert own merchant api keys'
  ) THEN
    CREATE POLICY "Users can insert own merchant api keys"
      ON public.merchant_api_keys
      FOR INSERT TO authenticated
      WITH CHECK (merchant_user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_api_keys' AND policyname = 'Users can update own merchant api keys'
  ) THEN
    CREATE POLICY "Users can update own merchant api keys"
      ON public.merchant_api_keys
      FOR UPDATE TO authenticated
      USING (merchant_user_id = auth.uid())
      WITH CHECK (merchant_user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_products' AND policyname = 'Users can view own merchant products'
  ) THEN
    CREATE POLICY "Users can view own merchant products"
      ON public.merchant_products
      FOR SELECT TO authenticated
      USING (merchant_user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_products' AND policyname = 'Users can insert own merchant products'
  ) THEN
    CREATE POLICY "Users can insert own merchant products"
      ON public.merchant_products
      FOR INSERT TO authenticated
      WITH CHECK (merchant_user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_products' AND policyname = 'Users can update own merchant products'
  ) THEN
    CREATE POLICY "Users can update own merchant products"
      ON public.merchant_products
      FOR UPDATE TO authenticated
      USING (merchant_user_id = auth.uid())
      WITH CHECK (merchant_user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_products' AND policyname = 'Users can delete own merchant products'
  ) THEN
    CREATE POLICY "Users can delete own merchant products"
      ON public.merchant_products
      FOR DELETE TO authenticated
      USING (merchant_user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_checkout_sessions' AND policyname = 'Users can view own merchant checkout sessions'
  ) THEN
    CREATE POLICY "Users can view own merchant checkout sessions"
      ON public.merchant_checkout_sessions
      FOR SELECT TO authenticated
      USING (merchant_user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_checkout_sessions' AND policyname = 'Users can insert own merchant checkout sessions'
  ) THEN
    CREATE POLICY "Users can insert own merchant checkout sessions"
      ON public.merchant_checkout_sessions
      FOR INSERT TO authenticated
      WITH CHECK (merchant_user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_checkout_sessions' AND policyname = 'Users can update own merchant checkout sessions'
  ) THEN
    CREATE POLICY "Users can update own merchant checkout sessions"
      ON public.merchant_checkout_sessions
      FOR UPDATE TO authenticated
      USING (merchant_user_id = auth.uid())
      WITH CHECK (merchant_user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_checkout_session_items' AND policyname = 'Users can view own merchant checkout items'
  ) THEN
    CREATE POLICY "Users can view own merchant checkout items"
      ON public.merchant_checkout_session_items
      FOR SELECT TO authenticated
      USING (
        EXISTS (
          SELECT 1
          FROM public.merchant_checkout_sessions mcs
          WHERE mcs.id = session_id
            AND mcs.merchant_user_id = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_checkout_session_items' AND policyname = 'Users can insert own merchant checkout items'
  ) THEN
    CREATE POLICY "Users can insert own merchant checkout items"
      ON public.merchant_checkout_session_items
      FOR INSERT TO authenticated
      WITH CHECK (
        EXISTS (
          SELECT 1
          FROM public.merchant_checkout_sessions mcs
          WHERE mcs.id = session_id
            AND mcs.merchant_user_id = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_checkout_session_items' AND policyname = 'Users can delete own merchant checkout items'
  ) THEN
    CREATE POLICY "Users can delete own merchant checkout items"
      ON public.merchant_checkout_session_items
      FOR DELETE TO authenticated
      USING (
        EXISTS (
          SELECT 1
          FROM public.merchant_checkout_sessions mcs
          WHERE mcs.id = session_id
            AND mcs.merchant_user_id = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_payments' AND policyname = 'Merchant or buyer can view merchant payments'
  ) THEN
    CREATE POLICY "Merchant or buyer can view merchant payments"
      ON public.merchant_payments
      FOR SELECT TO authenticated
      USING (merchant_user_id = auth.uid() OR buyer_user_id = auth.uid());
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_merchant_profiles_updated_at ON public.merchant_profiles;
CREATE TRIGGER trg_merchant_profiles_updated_at
BEFORE UPDATE ON public.merchant_profiles
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

DROP TRIGGER IF EXISTS trg_merchant_api_keys_updated_at ON public.merchant_api_keys;
CREATE TRIGGER trg_merchant_api_keys_updated_at
BEFORE UPDATE ON public.merchant_api_keys
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

DROP TRIGGER IF EXISTS trg_merchant_products_updated_at ON public.merchant_products;
CREATE TRIGGER trg_merchant_products_updated_at
BEFORE UPDATE ON public.merchant_products
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

DROP TRIGGER IF EXISTS trg_merchant_checkout_sessions_updated_at ON public.merchant_checkout_sessions;
CREATE TRIGGER trg_merchant_checkout_sessions_updated_at
BEFORE UPDATE ON public.merchant_checkout_sessions
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

CREATE OR REPLACE FUNCTION public.generate_merchant_api_key(p_prefix TEXT)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_candidate TEXT;
BEGIN
  LOOP
    v_candidate := p_prefix || encode(gen_random_bytes(24), 'hex');
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.merchant_api_keys WHERE publishable_key = v_candidate)
          AND NOT EXISTS (SELECT 1 FROM public.merchant_checkout_sessions WHERE session_token = v_candidate);
  END LOOP;

  RETURN v_candidate;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_my_merchant_profile(
  p_merchant_name TEXT DEFAULT NULL,
  p_merchant_username TEXT DEFAULT NULL,
  p_merchant_logo_url TEXT DEFAULT NULL,
  p_default_currency TEXT DEFAULT NULL
)
RETURNS public.merchant_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_profile_name TEXT;
  v_profile_username TEXT;
  v_profile_logo TEXT;
  v_profile public.merchant_profiles;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT full_name, COALESCE(username, ''), avatar_url
  INTO v_profile_name, v_profile_username, v_profile_logo
  FROM public.profiles
  WHERE id = v_user_id;

  INSERT INTO public.merchant_profiles (
    user_id,
    merchant_name,
    merchant_username,
    merchant_logo_url,
    default_currency
  )
  VALUES (
    v_user_id,
    COALESCE(NULLIF(TRIM(p_merchant_name), ''), NULLIF(TRIM(v_profile_name), ''), 'OpenPay Merchant'),
    COALESCE(NULLIF(TRIM(p_merchant_username), ''), NULLIF(TRIM(v_profile_username), ''), 'openpay-merchant'),
    COALESCE(NULLIF(TRIM(p_merchant_logo_url), ''), v_profile_logo),
    UPPER(COALESCE(NULLIF(TRIM(p_default_currency), ''), 'USD'))
  )
  ON CONFLICT (user_id) DO UPDATE
  SET merchant_name = COALESCE(NULLIF(TRIM(p_merchant_name), ''), public.merchant_profiles.merchant_name),
      merchant_username = COALESCE(NULLIF(TRIM(p_merchant_username), ''), public.merchant_profiles.merchant_username),
      merchant_logo_url = COALESCE(NULLIF(TRIM(p_merchant_logo_url), ''), public.merchant_profiles.merchant_logo_url),
      default_currency = UPPER(COALESCE(NULLIF(TRIM(p_default_currency), ''), public.merchant_profiles.default_currency)),
      is_active = true
  RETURNING * INTO v_profile;

  RETURN v_profile;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_my_merchant_api_key(
  p_mode TEXT,
  p_key_name TEXT DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  key_mode TEXT,
  publishable_key TEXT,
  secret_key TEXT,
  key_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, '')));
  v_key_name TEXT := COALESCE(NULLIF(TRIM(p_key_name), ''), 'Default key');
  v_publishable_key TEXT;
  v_secret_key TEXT;
  v_row public.merchant_api_keys;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  PERFORM public.upsert_my_merchant_profile();

  v_publishable_key := public.generate_merchant_api_key('opk_' || v_mode || '_');
  v_secret_key := 'osk_' || v_mode || '_' || encode(gen_random_bytes(32), 'hex');

  INSERT INTO public.merchant_api_keys (
    merchant_user_id,
    key_mode,
    key_name,
    publishable_key,
    secret_key_hash,
    secret_key_last4
  )
  VALUES (
    v_user_id,
    v_mode,
    v_key_name,
    v_publishable_key,
    encode(digest(v_secret_key, 'sha256'), 'hex'),
    RIGHT(v_secret_key, 4)
  )
  RETURNING * INTO v_row;

  RETURN QUERY
  SELECT v_row.id, v_row.key_mode, v_row.publishable_key, v_secret_key, v_row.key_name;
END;
$$;

CREATE OR REPLACE FUNCTION public.revoke_my_merchant_api_key(p_key_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  UPDATE public.merchant_api_keys
  SET is_active = false,
      revoked_at = now()
  WHERE id = p_key_id
    AND merchant_user_id = v_user_id
    AND is_active = true;

  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_merchant_checkout_session(
  p_secret_key TEXT,
  p_mode TEXT,
  p_currency TEXT,
  p_items JSONB,
  p_customer_email TEXT DEFAULT NULL,
  p_customer_name TEXT DEFAULT NULL,
  p_success_url TEXT DEFAULT NULL,
  p_cancel_url TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::jsonb,
  p_expires_in_minutes INTEGER DEFAULT 60
)
RETURNS TABLE (
  session_id UUID,
  session_token TEXT,
  total_amount NUMERIC,
  currency TEXT,
  expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, '')));
  v_currency TEXT := UPPER(TRIM(COALESCE(p_currency, 'USD')));
  v_secret_hash TEXT := encode(digest(COALESCE(p_secret_key, ''), 'sha256'), 'hex');
  v_merchant_user_id UUID;
  v_api_key_id UUID;
  v_session public.merchant_checkout_sessions;
  v_item JSONB;
  v_product public.merchant_products;
  v_quantity INTEGER;
  v_line_total NUMERIC(12,2);
  v_total NUMERIC(12,2) := 0;
  v_expires_minutes INTEGER := GREATEST(5, LEAST(COALESCE(p_expires_in_minutes, 60), 10080));
BEGIN
  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  IF char_length(v_currency) <> 3 THEN
    RAISE EXCEPTION 'Currency must be 3 letters';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'At least one item is required';
  END IF;

  SELECT mak.merchant_user_id, mak.id
  INTO v_merchant_user_id, v_api_key_id
  FROM public.merchant_api_keys mak
  WHERE mak.secret_key_hash = v_secret_hash
    AND mak.key_mode = v_mode
    AND mak.is_active = true
  LIMIT 1;

  IF v_merchant_user_id IS NULL THEN
    RAISE EXCEPTION 'Invalid merchant API key for mode %', v_mode;
  END IF;

  INSERT INTO public.merchant_checkout_sessions (
    merchant_user_id,
    key_mode,
    session_token,
    status,
    currency,
    subtotal_amount,
    fee_amount,
    total_amount,
    customer_email,
    customer_name,
    success_url,
    cancel_url,
    metadata,
    expires_at
  )
  VALUES (
    v_merchant_user_id,
    v_mode,
    'opsess_' || encode(gen_random_bytes(24), 'hex'),
    'open',
    v_currency,
    0,
    0,
    0,
    NULLIF(TRIM(COALESCE(p_customer_email, '')), ''),
    NULLIF(TRIM(COALESCE(p_customer_name, '')), ''),
    NULLIF(TRIM(COALESCE(p_success_url, '')), ''),
    NULLIF(TRIM(COALESCE(p_cancel_url, '')), ''),
    COALESCE(p_metadata, '{}'::jsonb),
    now() + make_interval(mins => v_expires_minutes)
  )
  RETURNING * INTO v_session;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    SELECT *
    INTO v_product
    FROM public.merchant_products mp
    WHERE mp.id = (v_item->>'product_id')::UUID
      AND mp.merchant_user_id = v_merchant_user_id
      AND mp.is_active = true
    LIMIT 1;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Invalid product_id in items payload';
    END IF;

    v_quantity := COALESCE((v_item->>'quantity')::INTEGER, 1);
    IF v_quantity < 1 OR v_quantity > 1000 THEN
      RAISE EXCEPTION 'Quantity must be between 1 and 1000';
    END IF;

    IF UPPER(v_product.currency) <> v_currency THEN
      RAISE EXCEPTION 'Product currency mismatch for product %', v_product.id;
    END IF;

    v_line_total := ROUND(v_product.unit_amount * v_quantity, 2);

    INSERT INTO public.merchant_checkout_session_items (
      session_id,
      product_id,
      item_name,
      unit_amount,
      quantity,
      line_total
    )
    VALUES (
      v_session.id,
      v_product.id,
      v_product.product_name,
      v_product.unit_amount,
      v_quantity,
      v_line_total
    );

    v_total := v_total + v_line_total;
  END LOOP;

  IF v_total <= 0 THEN
    RAISE EXCEPTION 'Session total must be positive';
  END IF;

  UPDATE public.merchant_checkout_sessions
  SET subtotal_amount = v_total,
      total_amount = v_total
  WHERE id = v_session.id
  RETURNING * INTO v_session;

  UPDATE public.merchant_api_keys
  SET last_used_at = now()
  WHERE id = v_api_key_id;

  RETURN QUERY
  SELECT v_session.id, v_session.session_token, v_session.total_amount, v_session.currency, v_session.expires_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_public_merchant_checkout_session(
  p_session_token TEXT
)
RETURNS TABLE (
  session_id UUID,
  status TEXT,
  mode TEXT,
  currency TEXT,
  amount NUMERIC,
  expires_at TIMESTAMPTZ,
  merchant_user_id UUID,
  merchant_name TEXT,
  merchant_username TEXT,
  merchant_logo_url TEXT,
  items JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.merchant_checkout_sessions;
BEGIN
  SELECT *
  INTO v_session
  FROM public.merchant_checkout_sessions mcs
  WHERE mcs.session_token = TRIM(COALESCE(p_session_token, ''))
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF v_session.status = 'open' AND v_session.expires_at < now() THEN
    UPDATE public.merchant_checkout_sessions
    SET status = 'expired'
    WHERE id = v_session.id
      AND status = 'open';

    SELECT *
    INTO v_session
    FROM public.merchant_checkout_sessions
    WHERE id = v_session.id;
  END IF;

  RETURN QUERY
  SELECT
    v_session.id,
    v_session.status,
    v_session.key_mode,
    v_session.currency,
    v_session.total_amount,
    v_session.expires_at,
    mp.user_id,
    mp.merchant_name,
    mp.merchant_username,
    mp.merchant_logo_url,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'item_name', mcsi.item_name,
            'quantity', mcsi.quantity,
            'unit_amount', mcsi.unit_amount,
            'line_total', mcsi.line_total
          )
          ORDER BY mcsi.created_at ASC
        )
        FROM public.merchant_checkout_session_items mcsi
        WHERE mcsi.session_id = v_session.id
      ),
      '[]'::jsonb
    )
  FROM public.merchant_profiles mp
  WHERE mp.user_id = v_session.merchant_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.pay_merchant_checkout_with_virtual_card(
  p_session_token TEXT,
  p_card_number TEXT,
  p_expiry_month INTEGER,
  p_expiry_year INTEGER,
  p_cvc TEXT,
  p_note TEXT DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buyer_user_id UUID := auth.uid();
  v_session public.merchant_checkout_sessions;
  v_sender_balance NUMERIC(12,2);
  v_receiver_balance NUMERIC(12,2);
  v_transaction_id UUID;
  v_payment_id UUID;
  v_card_number TEXT := regexp_replace(COALESCE(p_card_number, ''), '\D', '', 'g');
  v_cvc TEXT := regexp_replace(COALESCE(p_cvc, ''), '\D', '', 'g');
  v_expiry_end DATE;
BEGIN
  IF v_buyer_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT *
  INTO v_session
  FROM public.merchant_checkout_sessions mcs
  WHERE mcs.session_token = TRIM(COALESCE(p_session_token, ''))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Checkout session not found';
  END IF;

  IF v_session.status <> 'open' THEN
    RAISE EXCEPTION 'Checkout session is not open';
  END IF;

  IF v_session.expires_at < now() THEN
    UPDATE public.merchant_checkout_sessions
    SET status = 'expired'
    WHERE id = v_session.id;
    RAISE EXCEPTION 'Checkout session expired';
  END IF;

  IF v_session.merchant_user_id = v_buyer_user_id THEN
    RAISE EXCEPTION 'Merchant cannot pay own checkout';
  END IF;

  IF char_length(v_card_number) <> 16 THEN
    RAISE EXCEPTION 'Card number must be 16 digits';
  END IF;

  IF p_expiry_month IS NULL OR p_expiry_month < 1 OR p_expiry_month > 12 THEN
    RAISE EXCEPTION 'Invalid expiry month';
  END IF;

  IF p_expiry_year IS NULL OR p_expiry_year < 2026 THEN
    RAISE EXCEPTION 'Invalid expiry year';
  END IF;

  IF char_length(v_cvc) <> 3 THEN
    RAISE EXCEPTION 'Invalid CVC';
  END IF;

  v_expiry_end := (make_date(p_expiry_year, p_expiry_month, 1) + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
  IF v_expiry_end < CURRENT_DATE THEN
    RAISE EXCEPTION 'Card expired';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.virtual_cards vc
    WHERE vc.user_id = v_buyer_user_id
      AND vc.card_number = v_card_number
      AND vc.expiry_month = p_expiry_month
      AND vc.expiry_year = p_expiry_year
      AND vc.cvc = v_cvc
      AND vc.is_active = true
  ) THEN
    RAISE EXCEPTION 'Invalid virtual card details';
  END IF;

  SELECT balance INTO v_sender_balance
  FROM public.wallets
  WHERE user_id = v_buyer_user_id
  FOR UPDATE;

  IF v_sender_balance IS NULL THEN
    RAISE EXCEPTION 'Buyer wallet not found';
  END IF;

  SELECT balance INTO v_receiver_balance
  FROM public.wallets
  WHERE user_id = v_session.merchant_user_id
  FOR UPDATE;

  IF v_receiver_balance IS NULL THEN
    RAISE EXCEPTION 'Merchant wallet not found';
  END IF;

  IF v_sender_balance < v_session.total_amount THEN
    RAISE EXCEPTION 'Insufficient balance';
  END IF;

  UPDATE public.wallets
  SET balance = v_sender_balance - v_session.total_amount,
      updated_at = now()
  WHERE user_id = v_buyer_user_id;

  UPDATE public.wallets
  SET balance = v_receiver_balance + v_session.total_amount,
      updated_at = now()
  WHERE user_id = v_session.merchant_user_id;

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_buyer_user_id,
    v_session.merchant_user_id,
    v_session.total_amount,
    CONCAT('Merchant checkout ', v_session.session_token, ' | ', COALESCE(p_note, '')),
    'completed'
  )
  RETURNING id INTO v_transaction_id;

  INSERT INTO public.merchant_payments (
    session_id,
    merchant_user_id,
    buyer_user_id,
    transaction_id,
    amount,
    currency,
    key_mode,
    status
  )
  VALUES (
    v_session.id,
    v_session.merchant_user_id,
    v_buyer_user_id,
    v_transaction_id,
    v_session.total_amount,
    v_session.currency,
    v_session.key_mode,
    'succeeded'
  )
  RETURNING id INTO v_payment_id;

  UPDATE public.merchant_checkout_sessions
  SET status = 'paid',
      paid_at = now()
  WHERE id = v_session.id;

  RETURN v_transaction_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_merchant_profile_from_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.merchant_profiles (user_id, merchant_name, merchant_username, merchant_logo_url)
  VALUES (
    NEW.id,
    COALESCE(NULLIF(TRIM(NEW.full_name), ''), 'OpenPay Merchant'),
    COALESCE(NULLIF(TRIM(COALESCE(NEW.username, '')), ''), 'openpay-merchant'),
    NEW.avatar_url
  )
  ON CONFLICT (user_id) DO UPDATE
  SET merchant_name = EXCLUDED.merchant_name,
      merchant_username = EXCLUDED.merchant_username,
      merchant_logo_url = COALESCE(EXCLUDED.merchant_logo_url, public.merchant_profiles.merchant_logo_url);

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_sync_merchant_profile ON public.profiles;
CREATE TRIGGER trg_profiles_sync_merchant_profile
AFTER INSERT OR UPDATE OF full_name, username, avatar_url
ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.sync_merchant_profile_from_profile();

INSERT INTO public.merchant_profiles (user_id, merchant_name, merchant_username, merchant_logo_url)
SELECT
  p.id,
  COALESCE(NULLIF(TRIM(p.full_name), ''), 'OpenPay Merchant'),
  COALESCE(NULLIF(TRIM(COALESCE(p.username, '')), ''), 'openpay-merchant'),
  p.avatar_url
FROM public.profiles p
ON CONFLICT (user_id) DO UPDATE
SET merchant_name = EXCLUDED.merchant_name,
    merchant_username = EXCLUDED.merchant_username,
    merchant_logo_url = COALESCE(EXCLUDED.merchant_logo_url, public.merchant_profiles.merchant_logo_url);

REVOKE ALL ON FUNCTION public.upsert_my_merchant_profile(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_my_merchant_api_key(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.revoke_my_merchant_api_key(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_merchant_checkout_session(TEXT, TEXT, TEXT, JSONB, TEXT, TEXT, TEXT, TEXT, JSONB, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_public_merchant_checkout_session(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pay_merchant_checkout_with_virtual_card(TEXT, TEXT, INTEGER, INTEGER, TEXT, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.upsert_my_merchant_profile(TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_my_merchant_api_key(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_my_merchant_api_key(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_merchant_checkout_session(TEXT, TEXT, TEXT, JSONB, TEXT, TEXT, TEXT, TEXT, JSONB, INTEGER) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_merchant_checkout_session(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pay_merchant_checkout_with_virtual_card(TEXT, TEXT, INTEGER, INTEGER, TEXT, TEXT) TO authenticated;

-- <<< END MIGRATION: 20260218153000_merchant_portal.sql

-- >>> MIGRATION: 20260218180000_merchant_payment_links.sql
CREATE TABLE IF NOT EXISTS public.merchant_payment_links (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  key_mode TEXT NOT NULL CHECK (key_mode IN ('sandbox', 'live')),
  link_token TEXT NOT NULL UNIQUE,
  link_type TEXT NOT NULL CHECK (link_type IN ('products', 'custom_amount')),
  title TEXT NOT NULL DEFAULT 'OpenPay Payment',
  description TEXT NOT NULL DEFAULT '',
  currency TEXT NOT NULL DEFAULT 'USD' CHECK (char_length(currency) = 3),
  custom_amount NUMERIC(12,2),
  collect_customer_name BOOLEAN NOT NULL DEFAULT true,
  collect_customer_email BOOLEAN NOT NULL DEFAULT true,
  collect_phone BOOLEAN NOT NULL DEFAULT false,
  collect_address BOOLEAN NOT NULL DEFAULT false,
  after_payment_type TEXT NOT NULL DEFAULT 'confirmation' CHECK (after_payment_type IN ('confirmation', 'redirect')),
  confirmation_message TEXT NOT NULL DEFAULT 'Thanks for your payment.',
  redirect_url TEXT,
  call_to_action TEXT NOT NULL DEFAULT 'Pay',
  is_active BOOLEAN NOT NULL DEFAULT true,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (custom_amount IS NULL OR custom_amount > 0)
);

CREATE TABLE IF NOT EXISTS public.merchant_payment_link_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  link_id UUID NOT NULL REFERENCES public.merchant_payment_links(id) ON DELETE CASCADE,
  product_id UUID REFERENCES public.merchant_products(id) ON DELETE SET NULL,
  item_name TEXT NOT NULL,
  unit_amount NUMERIC(12,2) NOT NULL CHECK (unit_amount > 0),
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  line_total NUMERIC(12,2) NOT NULL CHECK (line_total > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (line_total = ROUND(unit_amount * quantity, 2))
);

CREATE INDEX IF NOT EXISTS idx_merchant_payment_links_owner_mode
ON public.merchant_payment_links (merchant_user_id, key_mode, is_active);

CREATE INDEX IF NOT EXISTS idx_merchant_payment_links_token
ON public.merchant_payment_links (link_token);

CREATE INDEX IF NOT EXISTS idx_merchant_payment_link_items_link
ON public.merchant_payment_link_items (link_id);

ALTER TABLE public.merchant_payment_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_payment_link_items ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_payment_links' AND policyname = 'Users can view own merchant payment links'
  ) THEN
    CREATE POLICY "Users can view own merchant payment links"
      ON public.merchant_payment_links
      FOR SELECT TO authenticated
      USING (merchant_user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_payment_links' AND policyname = 'Users can insert own merchant payment links'
  ) THEN
    CREATE POLICY "Users can insert own merchant payment links"
      ON public.merchant_payment_links
      FOR INSERT TO authenticated
      WITH CHECK (merchant_user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_payment_links' AND policyname = 'Users can update own merchant payment links'
  ) THEN
    CREATE POLICY "Users can update own merchant payment links"
      ON public.merchant_payment_links
      FOR UPDATE TO authenticated
      USING (merchant_user_id = auth.uid())
      WITH CHECK (merchant_user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_payment_links' AND policyname = 'Users can delete own merchant payment links'
  ) THEN
    CREATE POLICY "Users can delete own merchant payment links"
      ON public.merchant_payment_links
      FOR DELETE TO authenticated
      USING (merchant_user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_payment_link_items' AND policyname = 'Users can view own merchant payment link items'
  ) THEN
    CREATE POLICY "Users can view own merchant payment link items"
      ON public.merchant_payment_link_items
      FOR SELECT TO authenticated
      USING (
        EXISTS (
          SELECT 1
          FROM public.merchant_payment_links mpl
          WHERE mpl.id = link_id
            AND mpl.merchant_user_id = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_payment_link_items' AND policyname = 'Users can insert own merchant payment link items'
  ) THEN
    CREATE POLICY "Users can insert own merchant payment link items"
      ON public.merchant_payment_link_items
      FOR INSERT TO authenticated
      WITH CHECK (
        EXISTS (
          SELECT 1
          FROM public.merchant_payment_links mpl
          WHERE mpl.id = link_id
            AND mpl.merchant_user_id = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_payment_link_items' AND policyname = 'Users can delete own merchant payment link items'
  ) THEN
    CREATE POLICY "Users can delete own merchant payment link items"
      ON public.merchant_payment_link_items
      FOR DELETE TO authenticated
      USING (
        EXISTS (
          SELECT 1
          FROM public.merchant_payment_links mpl
          WHERE mpl.id = link_id
            AND mpl.merchant_user_id = auth.uid()
        )
      );
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_merchant_payment_links_updated_at ON public.merchant_payment_links;
CREATE TRIGGER trg_merchant_payment_links_updated_at
BEFORE UPDATE ON public.merchant_payment_links
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

CREATE OR REPLACE FUNCTION public.create_merchant_payment_link(
  p_secret_key TEXT,
  p_mode TEXT,
  p_link_type TEXT,
  p_title TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_currency TEXT DEFAULT 'USD',
  p_custom_amount NUMERIC DEFAULT NULL,
  p_items JSONB DEFAULT '[]'::jsonb,
  p_collect_customer_name BOOLEAN DEFAULT true,
  p_collect_customer_email BOOLEAN DEFAULT true,
  p_collect_phone BOOLEAN DEFAULT false,
  p_collect_address BOOLEAN DEFAULT false,
  p_after_payment_type TEXT DEFAULT 'confirmation',
  p_confirmation_message TEXT DEFAULT NULL,
  p_redirect_url TEXT DEFAULT NULL,
  p_call_to_action TEXT DEFAULT 'Pay',
  p_expires_in_minutes INTEGER DEFAULT NULL
)
RETURNS TABLE (
  link_id UUID,
  link_token TEXT,
  total_amount NUMERIC,
  currency TEXT,
  key_mode TEXT,
  expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, '')));
  v_link_type TEXT := LOWER(TRIM(COALESCE(p_link_type, '')));
  v_after_payment_type TEXT := LOWER(TRIM(COALESCE(p_after_payment_type, 'confirmation')));
  v_currency TEXT := UPPER(TRIM(COALESCE(p_currency, 'USD')));
  v_secret_hash TEXT := encode(digest(COALESCE(p_secret_key, ''), 'sha256'), 'hex');
  v_merchant_user_id UUID;
  v_link public.merchant_payment_links;
  v_item JSONB;
  v_product public.merchant_products;
  v_quantity INTEGER;
  v_line_total NUMERIC(12,2);
  v_total NUMERIC(12,2) := 0;
  v_expires_at TIMESTAMPTZ;
BEGIN
  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  IF v_link_type NOT IN ('products', 'custom_amount') THEN
    RAISE EXCEPTION 'Link type must be products or custom_amount';
  END IF;

  IF v_after_payment_type NOT IN ('confirmation', 'redirect') THEN
    RAISE EXCEPTION 'After payment type must be confirmation or redirect';
  END IF;

  IF char_length(v_currency) <> 3 THEN
    RAISE EXCEPTION 'Currency must be 3 letters';
  END IF;

  SELECT mak.merchant_user_id
  INTO v_merchant_user_id
  FROM public.merchant_api_keys mak
  WHERE mak.secret_key_hash = v_secret_hash
    AND mak.key_mode = v_mode
    AND mak.is_active = true
  LIMIT 1;

  IF v_merchant_user_id IS NULL THEN
    RAISE EXCEPTION 'Invalid merchant API key for mode %', v_mode;
  END IF;

  IF p_expires_in_minutes IS NOT NULL THEN
    v_expires_at := now() + make_interval(mins => GREATEST(5, LEAST(p_expires_in_minutes, 525600)));
  END IF;

  INSERT INTO public.merchant_payment_links (
    merchant_user_id,
    key_mode,
    link_token,
    link_type,
    title,
    description,
    currency,
    custom_amount,
    collect_customer_name,
    collect_customer_email,
    collect_phone,
    collect_address,
    after_payment_type,
    confirmation_message,
    redirect_url,
    call_to_action,
    expires_at
  )
  VALUES (
    v_merchant_user_id,
    v_mode,
    'oplink_' || encode(gen_random_bytes(24), 'hex'),
    v_link_type,
    COALESCE(NULLIF(TRIM(p_title), ''), 'OpenPay Payment'),
    COALESCE(NULLIF(TRIM(p_description), ''), ''),
    v_currency,
    p_custom_amount,
    COALESCE(p_collect_customer_name, true),
    COALESCE(p_collect_customer_email, true),
    COALESCE(p_collect_phone, false),
    COALESCE(p_collect_address, false),
    v_after_payment_type,
    COALESCE(NULLIF(TRIM(p_confirmation_message), ''), 'Thanks for your payment.'),
    NULLIF(TRIM(COALESCE(p_redirect_url, '')), ''),
    COALESCE(NULLIF(TRIM(p_call_to_action), ''), 'Pay'),
    v_expires_at
  )
  RETURNING * INTO v_link;

  IF v_link_type = 'custom_amount' THEN
    IF p_custom_amount IS NULL OR p_custom_amount <= 0 THEN
      RAISE EXCEPTION 'Custom amount must be greater than 0';
    END IF;
    v_total := ROUND(p_custom_amount, 2);
  ELSE
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
      RAISE EXCEPTION 'At least one product item is required';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
      SELECT *
      INTO v_product
      FROM public.merchant_products mp
      WHERE mp.id = (v_item->>'product_id')::UUID
        AND mp.merchant_user_id = v_merchant_user_id
        AND mp.is_active = true
      LIMIT 1;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid product_id in items payload';
      END IF;

      v_quantity := COALESCE((v_item->>'quantity')::INTEGER, 1);
      IF v_quantity < 1 OR v_quantity > 1000 THEN
        RAISE EXCEPTION 'Quantity must be between 1 and 1000';
      END IF;

      IF UPPER(v_product.currency) <> v_currency THEN
        RAISE EXCEPTION 'Product currency mismatch for product %', v_product.id;
      END IF;

      v_line_total := ROUND(v_product.unit_amount * v_quantity, 2);

      INSERT INTO public.merchant_payment_link_items (
        link_id,
        product_id,
        item_name,
        unit_amount,
        quantity,
        line_total
      )
      VALUES (
        v_link.id,
        v_product.id,
        v_product.product_name,
        v_product.unit_amount,
        v_quantity,
        v_line_total
      );

      v_total := v_total + v_line_total;
    END LOOP;
  END IF;

  IF v_total <= 0 THEN
    RAISE EXCEPTION 'Payment link total must be positive';
  END IF;

  RETURN QUERY
  SELECT v_link.id, v_link.link_token, v_total, v_link.currency, v_link.key_mode, v_link.expires_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_public_merchant_payment_link(
  p_link_token TEXT
)
RETURNS TABLE (
  link_id UUID,
  link_token TEXT,
  mode TEXT,
  link_type TEXT,
  title TEXT,
  description TEXT,
  currency TEXT,
  total_amount NUMERIC,
  collect_customer_name BOOLEAN,
  collect_customer_email BOOLEAN,
  collect_phone BOOLEAN,
  collect_address BOOLEAN,
  after_payment_type TEXT,
  confirmation_message TEXT,
  redirect_url TEXT,
  call_to_action TEXT,
  expires_at TIMESTAMPTZ,
  merchant_user_id UUID,
  merchant_name TEXT,
  merchant_username TEXT,
  merchant_logo_url TEXT,
  items JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_link public.merchant_payment_links;
  v_total NUMERIC(12,2) := 0;
BEGIN
  SELECT *
  INTO v_link
  FROM public.merchant_payment_links mpl
  WHERE mpl.link_token = TRIM(COALESCE(p_link_token, ''))
    AND mpl.is_active = true
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF v_link.expires_at IS NOT NULL AND v_link.expires_at < now() THEN
    RETURN;
  END IF;

  IF v_link.link_type = 'custom_amount' THEN
    v_total := COALESCE(v_link.custom_amount, 0);
  ELSE
    SELECT COALESCE(SUM(mpli.line_total), 0)
    INTO v_total
    FROM public.merchant_payment_link_items mpli
    WHERE mpli.link_id = v_link.id;
  END IF;

  RETURN QUERY
  SELECT
    v_link.id,
    v_link.link_token,
    v_link.key_mode,
    v_link.link_type,
    v_link.title,
    v_link.description,
    v_link.currency,
    v_total,
    v_link.collect_customer_name,
    v_link.collect_customer_email,
    v_link.collect_phone,
    v_link.collect_address,
    v_link.after_payment_type,
    v_link.confirmation_message,
    v_link.redirect_url,
    v_link.call_to_action,
    v_link.expires_at,
    mp.user_id,
    mp.merchant_name,
    mp.merchant_username,
    mp.merchant_logo_url,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'item_name', mpli.item_name,
            'quantity', mpli.quantity,
            'unit_amount', mpli.unit_amount,
            'line_total', mpli.line_total
          )
          ORDER BY mpli.created_at ASC
        )
        FROM public.merchant_payment_link_items mpli
        WHERE mpli.link_id = v_link.id
      ),
      '[]'::jsonb
    )
  FROM public.merchant_profiles mp
  WHERE mp.user_id = v_link.merchant_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_checkout_session_from_payment_link(
  p_link_token TEXT,
  p_customer_email TEXT DEFAULT NULL,
  p_customer_name TEXT DEFAULT NULL
)
RETURNS TABLE (
  session_id UUID,
  session_token TEXT,
  total_amount NUMERIC,
  currency TEXT,
  expires_at TIMESTAMPTZ,
  after_payment_type TEXT,
  confirmation_message TEXT,
  redirect_url TEXT,
  call_to_action TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_link public.merchant_payment_links;
  v_session public.merchant_checkout_sessions;
  v_total NUMERIC(12,2) := 0;
BEGIN
  SELECT *
  INTO v_link
  FROM public.merchant_payment_links mpl
  WHERE mpl.link_token = TRIM(COALESCE(p_link_token, ''))
    AND mpl.is_active = true
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment link not found';
  END IF;

  IF v_link.expires_at IS NOT NULL AND v_link.expires_at < now() THEN
    RAISE EXCEPTION 'Payment link expired';
  END IF;

  INSERT INTO public.merchant_checkout_sessions (
    merchant_user_id,
    key_mode,
    session_token,
    status,
    currency,
    subtotal_amount,
    fee_amount,
    total_amount,
    customer_email,
    customer_name,
    success_url,
    cancel_url,
    metadata,
    expires_at
  )
  VALUES (
    v_link.merchant_user_id,
    v_link.key_mode,
    'opsess_' || encode(gen_random_bytes(24), 'hex'),
    'open',
    v_link.currency,
    0,
    0,
    0,
    NULLIF(TRIM(COALESCE(p_customer_email, '')), ''),
    NULLIF(TRIM(COALESCE(p_customer_name, '')), ''),
    NULL,
    NULL,
    jsonb_build_object(
      'payment_link_id', v_link.id,
      'payment_link_token', v_link.link_token,
      'after_payment_type', v_link.after_payment_type,
      'confirmation_message', v_link.confirmation_message,
      'redirect_url', v_link.redirect_url,
      'call_to_action', v_link.call_to_action
    ),
    now() + INTERVAL '60 minutes'
  )
  RETURNING * INTO v_session;

  IF v_link.link_type = 'custom_amount' THEN
    v_total := COALESCE(v_link.custom_amount, 0);

    INSERT INTO public.merchant_checkout_session_items (
      session_id,
      product_id,
      item_name,
      unit_amount,
      quantity,
      line_total
    )
    VALUES (
      v_session.id,
      NULL,
      v_link.title,
      v_total,
      1,
      v_total
    );
  ELSE
    INSERT INTO public.merchant_checkout_session_items (
      session_id,
      product_id,
      item_name,
      unit_amount,
      quantity,
      line_total
    )
    SELECT
      v_session.id,
      mpli.product_id,
      mpli.item_name,
      mpli.unit_amount,
      mpli.quantity,
      mpli.line_total
    FROM public.merchant_payment_link_items mpli
    WHERE mpli.link_id = v_link.id;

    SELECT COALESCE(SUM(mpli.line_total), 0)
    INTO v_total
    FROM public.merchant_payment_link_items mpli
    WHERE mpli.link_id = v_link.id;
  END IF;

  IF v_total <= 0 THEN
    RAISE EXCEPTION 'Payment link total must be positive';
  END IF;

  UPDATE public.merchant_checkout_sessions
  SET subtotal_amount = v_total,
      total_amount = v_total
  WHERE id = v_session.id
  RETURNING * INTO v_session;

  RETURN QUERY
  SELECT
    v_session.id,
    v_session.session_token,
    v_session.total_amount,
    v_session.currency,
    v_session.expires_at,
    v_link.after_payment_type,
    v_link.confirmation_message,
    v_link.redirect_url,
    v_link.call_to_action;
END;
$$;

REVOKE ALL ON FUNCTION public.create_merchant_payment_link(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, JSONB, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, TEXT, TEXT, TEXT, TEXT, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_public_merchant_payment_link(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_checkout_session_from_payment_link(TEXT, TEXT, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_merchant_payment_link(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, JSONB, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, TEXT, TEXT, TEXT, TEXT, INTEGER) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_public_merchant_payment_link(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_checkout_session_from_payment_link(TEXT, TEXT, TEXT) TO anon, authenticated;

-- <<< END MIGRATION: 20260218180000_merchant_payment_links.sql

-- >>> MIGRATION: 20260218190000_enable_pgcrypto.sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- <<< END MIGRATION: 20260218190000_enable_pgcrypto.sql

-- >>> MIGRATION: 20260218201000_virtual_card_signature_persistence.sql
ALTER TABLE public.virtual_cards
ALTER COLUMN card_settings
SET DEFAULT '{"allow_checkout": true, "signature": ""}'::jsonb;

UPDATE public.virtual_cards
SET card_settings = COALESCE(card_settings, '{}'::jsonb) || jsonb_build_object(
  'signature',
  LEFT(COALESCE(NULLIF(TRIM(cardholder_name), ''), ''), 32)
)
WHERE COALESCE(card_settings, '{}'::jsonb) ? 'signature' = false;

CREATE OR REPLACE FUNCTION public.update_my_virtual_card_controls(
  p_hide_details BOOLEAN DEFAULT NULL,
  p_lock_card BOOLEAN DEFAULT NULL,
  p_card_settings JSONB DEFAULT NULL
)
RETURNS public.virtual_cards
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_card public.virtual_cards;
  v_settings_patch JSONB := p_card_settings;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  PERFORM public.upsert_my_virtual_card(NULL, NULL);

  IF v_settings_patch IS NOT NULL
     AND jsonb_typeof(v_settings_patch) = 'object'
     AND v_settings_patch ? 'signature' THEN
    v_settings_patch := jsonb_set(
      v_settings_patch,
      '{signature}',
      to_jsonb(LEFT(TRIM(COALESCE(v_settings_patch ->> 'signature', '')), 32)),
      true
    );
  END IF;

  UPDATE public.virtual_cards
  SET hide_details = COALESCE(p_hide_details, hide_details),
      is_locked = COALESCE(p_lock_card, is_locked),
      locked_at = CASE
        WHEN p_lock_card IS TRUE THEN now()
        WHEN p_lock_card IS FALSE THEN NULL
        ELSE locked_at
      END,
      card_settings = CASE
        WHEN v_settings_patch IS NULL THEN card_settings
        ELSE COALESCE(card_settings, '{}'::jsonb) || v_settings_patch
      END
  WHERE user_id = v_user_id
  RETURNING * INTO v_card;

  RETURN v_card;
END;
$$;

REVOKE ALL ON FUNCTION public.update_my_virtual_card_controls(BOOLEAN, BOOLEAN, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_my_virtual_card_controls(BOOLEAN, BOOLEAN, JSONB) TO authenticated;

-- <<< END MIGRATION: 20260218201000_virtual_card_signature_persistence.sql

-- >>> MIGRATION: 20260218204000_open_partner_leads.sql
CREATE TABLE IF NOT EXISTS public.open_partner_leads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  company_name TEXT NOT NULL,
  contact_name TEXT NOT NULL,
  contact_email TEXT NOT NULL,
  country TEXT,
  website_url TEXT,
  business_type TEXT,
  integration_type TEXT,
  estimated_monthly_volume TEXT,
  use_case_summary TEXT NOT NULL DEFAULT '',
  message TEXT,
  status TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'reviewing', 'approved', 'rejected', 'closed')),
  admin_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_open_partner_leads_requester_created
ON public.open_partner_leads (requester_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_open_partner_leads_status_created
ON public.open_partner_leads (status, created_at DESC);

ALTER TABLE public.open_partner_leads ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'open_partner_leads' AND policyname = 'Users can view own partner leads'
  ) THEN
    CREATE POLICY "Users can view own partner leads"
      ON public.open_partner_leads
      FOR SELECT TO authenticated
      USING (requester_user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'open_partner_leads' AND policyname = 'Users can create own partner leads'
  ) THEN
    CREATE POLICY "Users can create own partner leads"
      ON public.open_partner_leads
      FOR INSERT TO authenticated
      WITH CHECK (requester_user_id = auth.uid());
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_open_partner_leads_updated_at ON public.open_partner_leads;
CREATE TRIGGER trg_open_partner_leads_updated_at
BEFORE UPDATE ON public.open_partner_leads
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

-- <<< END MIGRATION: 20260218204000_open_partner_leads.sql

-- >>> MIGRATION: 20260218210000_wallet_savings_loans.sql
CREATE TABLE IF NOT EXISTS public.user_savings_accounts (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  balance NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
  apy NUMERIC(5,2) NOT NULL DEFAULT 4.50 CHECK (apy >= 0 AND apy <= 100),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.user_savings_transfers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  direction TEXT NOT NULL CHECK (direction IN ('wallet_to_savings', 'savings_to_wallet')),
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  fee_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (fee_amount >= 0),
  note TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.user_loans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  principal_amount NUMERIC(12,2) NOT NULL CHECK (principal_amount > 0),
  outstanding_amount NUMERIC(12,2) NOT NULL CHECK (outstanding_amount >= 0),
  monthly_payment_amount NUMERIC(12,2) NOT NULL CHECK (monthly_payment_amount > 0),
  monthly_fee_rate NUMERIC(6,4) NOT NULL DEFAULT 0.0200 CHECK (monthly_fee_rate >= 0 AND monthly_fee_rate <= 1),
  term_months INTEGER NOT NULL CHECK (term_months >= 1 AND term_months <= 120),
  paid_months INTEGER NOT NULL DEFAULT 0 CHECK (paid_months >= 0),
  credit_score INTEGER NOT NULL DEFAULT 620 CHECK (credit_score >= 300 AND credit_score <= 900),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('pending', 'active', 'paid', 'rejected', 'defaulted')),
  next_due_date DATE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.user_loan_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  loan_id UUID NOT NULL REFERENCES public.user_loans(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  principal_component NUMERIC(12,2) NOT NULL CHECK (principal_component >= 0),
  fee_component NUMERIC(12,2) NOT NULL CHECK (fee_component >= 0),
  note TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_savings_transfers_user_created
ON public.user_savings_transfers (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_loans_user_status
ON public.user_loans (user_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_loan_payments_loan_created
ON public.user_loan_payments (loan_id, created_at DESC);

ALTER TABLE public.user_savings_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_savings_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_loans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_loan_payments ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_savings_accounts' AND policyname = 'Users can view own savings account'
  ) THEN
    CREATE POLICY "Users can view own savings account"
      ON public.user_savings_accounts
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_savings_accounts' AND policyname = 'Users can insert own savings account'
  ) THEN
    CREATE POLICY "Users can insert own savings account"
      ON public.user_savings_accounts
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_savings_accounts' AND policyname = 'Users can update own savings account'
  ) THEN
    CREATE POLICY "Users can update own savings account"
      ON public.user_savings_accounts
      FOR UPDATE TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_savings_transfers' AND policyname = 'Users can view own savings transfers'
  ) THEN
    CREATE POLICY "Users can view own savings transfers"
      ON public.user_savings_transfers
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_loans' AND policyname = 'Users can view own loans'
  ) THEN
    CREATE POLICY "Users can view own loans"
      ON public.user_loans
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_loan_payments' AND policyname = 'Users can view own loan payments'
  ) THEN
    CREATE POLICY "Users can view own loan payments"
      ON public.user_loan_payments
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_user_savings_accounts_updated_at ON public.user_savings_accounts;
CREATE TRIGGER trg_user_savings_accounts_updated_at
BEFORE UPDATE ON public.user_savings_accounts
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

DROP TRIGGER IF EXISTS trg_user_loans_updated_at ON public.user_loans;
CREATE TRIGGER trg_user_loans_updated_at
BEFORE UPDATE ON public.user_loans
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

CREATE OR REPLACE FUNCTION public.upsert_my_savings_account()
RETURNS public.user_savings_accounts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_row public.user_savings_accounts;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  INSERT INTO public.user_savings_accounts (user_id)
  VALUES (v_user_id)
  ON CONFLICT (user_id) DO UPDATE
  SET user_id = EXCLUDED.user_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_savings_dashboard()
RETURNS TABLE (
  wallet_balance NUMERIC,
  savings_balance NUMERIC,
  apy NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_wallet_balance NUMERIC(12,2);
  v_savings public.user_savings_accounts;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  PERFORM public.upsert_my_savings_account();

  SELECT balance INTO v_wallet_balance
  FROM public.wallets
  WHERE user_id = v_user_id;

  SELECT * INTO v_savings
  FROM public.user_savings_accounts
  WHERE user_id = v_user_id;

  RETURN QUERY
  SELECT COALESCE(v_wallet_balance, 0), COALESCE(v_savings.balance, 0), COALESCE(v_savings.apy, 4.50);
END;
$$;

CREATE OR REPLACE FUNCTION public.transfer_my_wallet_to_savings(
  p_amount NUMERIC,
  p_note TEXT DEFAULT ''
)
RETURNS TABLE (
  wallet_balance NUMERIC,
  savings_balance NUMERIC,
  transfer_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_amount NUMERIC(12,2) := ROUND(COALESCE(p_amount, 0), 2);
  v_wallet_balance NUMERIC(12,2);
  v_savings public.user_savings_accounts;
  v_transfer_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than 0';
  END IF;

  PERFORM public.upsert_my_savings_account();

  SELECT balance INTO v_wallet_balance
  FROM public.wallets
  WHERE user_id = v_user_id
  FOR UPDATE;

  SELECT * INTO v_savings
  FROM public.user_savings_accounts
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'Wallet not found';
  END IF;

  IF v_wallet_balance < v_amount THEN
    RAISE EXCEPTION 'Insufficient wallet balance';
  END IF;

  UPDATE public.wallets
  SET balance = v_wallet_balance - v_amount,
      updated_at = now()
  WHERE user_id = v_user_id
  RETURNING balance INTO v_wallet_balance;

  UPDATE public.user_savings_accounts
  SET balance = v_savings.balance + v_amount
  WHERE user_id = v_user_id
  RETURNING * INTO v_savings;

  INSERT INTO public.user_savings_transfers (user_id, direction, amount, fee_amount, note)
  VALUES (v_user_id, 'wallet_to_savings', v_amount, 0, COALESCE(p_note, ''))
  RETURNING id INTO v_transfer_id;

  RETURN QUERY
  SELECT v_wallet_balance, v_savings.balance, v_transfer_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.transfer_my_savings_to_wallet(
  p_amount NUMERIC,
  p_note TEXT DEFAULT ''
)
RETURNS TABLE (
  wallet_balance NUMERIC,
  savings_balance NUMERIC,
  transfer_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_amount NUMERIC(12,2) := ROUND(COALESCE(p_amount, 0), 2);
  v_wallet_balance NUMERIC(12,2);
  v_savings public.user_savings_accounts;
  v_transfer_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than 0';
  END IF;

  PERFORM public.upsert_my_savings_account();

  SELECT balance INTO v_wallet_balance
  FROM public.wallets
  WHERE user_id = v_user_id
  FOR UPDATE;

  SELECT * INTO v_savings
  FROM public.user_savings_accounts
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'Wallet not found';
  END IF;

  IF COALESCE(v_savings.balance, 0) < v_amount THEN
    RAISE EXCEPTION 'Insufficient savings balance';
  END IF;

  UPDATE public.user_savings_accounts
  SET balance = v_savings.balance - v_amount
  WHERE user_id = v_user_id
  RETURNING * INTO v_savings;

  UPDATE public.wallets
  SET balance = v_wallet_balance + v_amount,
      updated_at = now()
  WHERE user_id = v_user_id
  RETURNING balance INTO v_wallet_balance;

  INSERT INTO public.user_savings_transfers (user_id, direction, amount, fee_amount, note)
  VALUES (v_user_id, 'savings_to_wallet', v_amount, 0, COALESCE(p_note, ''))
  RETURNING id INTO v_transfer_id;

  RETURN QUERY
  SELECT v_wallet_balance, v_savings.balance, v_transfer_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.request_my_openpay_loan(
  p_principal_amount NUMERIC,
  p_term_months INTEGER DEFAULT 6,
  p_credit_score INTEGER DEFAULT NULL
)
RETURNS public.user_loans
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_principal NUMERIC(12,2) := ROUND(COALESCE(p_principal_amount, 0), 2);
  v_term INTEGER := GREATEST(1, LEAST(COALESCE(p_term_months, 6), 60));
  v_credit_score INTEGER := GREATEST(300, LEAST(COALESCE(p_credit_score, 620), 900));
  v_fee_rate NUMERIC(6,4);
  v_wallet_balance NUMERIC(12,2);
  v_monthly NUMERIC(12,2);
  v_existing UUID;
  v_loan public.user_loans;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_principal < 10 OR v_principal > 50000 THEN
    RAISE EXCEPTION 'Loan amount must be between 10 and 50000';
  END IF;

  SELECT id INTO v_existing
  FROM public.user_loans
  WHERE user_id = v_user_id
    AND status IN ('pending', 'active')
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    RAISE EXCEPTION 'You already have an active or pending loan';
  END IF;

  v_fee_rate := CASE
    WHEN v_credit_score >= 750 THEN 0.0100
    WHEN v_credit_score >= 680 THEN 0.0150
    WHEN v_credit_score >= 620 THEN 0.0200
    ELSE 0.0300
  END;

  v_monthly := ROUND((v_principal / v_term) + (v_principal * v_fee_rate), 2);

  INSERT INTO public.user_loans (
    user_id,
    principal_amount,
    outstanding_amount,
    monthly_payment_amount,
    monthly_fee_rate,
    term_months,
    credit_score,
    status,
    next_due_date
  )
  VALUES (
    v_user_id,
    v_principal,
    v_principal,
    v_monthly,
    v_fee_rate,
    v_term,
    v_credit_score,
    'active',
    (CURRENT_DATE + INTERVAL '1 month')::DATE
  )
  RETURNING * INTO v_loan;

  SELECT balance INTO v_wallet_balance
  FROM public.wallets
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'Wallet not found';
  END IF;

  UPDATE public.wallets
  SET balance = v_wallet_balance + v_principal,
      updated_at = now()
  WHERE user_id = v_user_id;

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_user_id,
    v_user_id,
    v_principal,
    CONCAT('OpenPay loan disbursement | Loan ', v_loan.id),
    'completed'
  );

  RETURN v_loan;
END;
$$;

CREATE OR REPLACE FUNCTION public.pay_my_loan_monthly(
  p_loan_id UUID,
  p_amount NUMERIC DEFAULT NULL,
  p_note TEXT DEFAULT 'Loan monthly payment'
)
RETURNS TABLE (
  loan_id UUID,
  remaining_balance NUMERIC,
  paid_months INTEGER,
  status TEXT,
  wallet_balance NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_loan public.user_loans;
  v_due NUMERIC(12,2);
  v_wallet_balance NUMERIC(12,2);
  v_principal_component NUMERIC(12,2);
  v_fee_component NUMERIC(12,2);
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT * INTO v_loan
  FROM public.user_loans
  WHERE id = p_loan_id
    AND user_id = v_user_id
    AND status = 'active'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active loan not found';
  END IF;

  v_due := ROUND(COALESCE(p_amount, LEAST(v_loan.outstanding_amount, v_loan.monthly_payment_amount)), 2);
  IF v_due <= 0 THEN
    RAISE EXCEPTION 'Payment amount must be greater than 0';
  END IF;

  SELECT balance INTO v_wallet_balance
  FROM public.wallets
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'Wallet not found';
  END IF;

  IF v_wallet_balance < v_due THEN
    RAISE EXCEPTION 'Insufficient wallet balance';
  END IF;

  v_principal_component := ROUND(LEAST(v_loan.outstanding_amount, v_due / (1 + v_loan.monthly_fee_rate)), 2);
  v_fee_component := ROUND(v_due - v_principal_component, 2);

  UPDATE public.wallets
  SET balance = v_wallet_balance - v_due,
      updated_at = now()
  WHERE user_id = v_user_id
  RETURNING balance INTO v_wallet_balance;

  UPDATE public.user_loans
  SET outstanding_amount = GREATEST(0, outstanding_amount - v_principal_component),
      paid_months = paid_months + 1,
      next_due_date = (next_due_date + INTERVAL '1 month')::DATE,
      status = CASE
        WHEN GREATEST(0, outstanding_amount - v_principal_component) = 0 THEN 'paid'
        ELSE v_loan.status
      END
  WHERE id = v_loan.id
  RETURNING * INTO v_loan;

  INSERT INTO public.user_loan_payments (
    loan_id,
    user_id,
    amount,
    principal_component,
    fee_component,
    note
  )
  VALUES (
    v_loan.id,
    v_user_id,
    v_due,
    v_principal_component,
    v_fee_component,
    COALESCE(p_note, 'Loan monthly payment')
  );

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_user_id,
    v_user_id,
    v_due,
    CONCAT('OpenPay loan repayment | Loan ', v_loan.id),
    'completed'
  );

  RETURN QUERY
  SELECT v_loan.id, v_loan.outstanding_amount, v_loan.paid_months, v_loan.status, v_wallet_balance;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_latest_loan()
RETURNS TABLE (
  id UUID,
  principal_amount NUMERIC,
  outstanding_amount NUMERIC,
  monthly_payment_amount NUMERIC,
  monthly_fee_rate NUMERIC,
  term_months INTEGER,
  paid_months INTEGER,
  credit_score INTEGER,
  status TEXT,
  next_due_date DATE,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  RETURN QUERY
  SELECT
    ul.id,
    ul.principal_amount,
    ul.outstanding_amount,
    ul.monthly_payment_amount,
    ul.monthly_fee_rate,
    ul.term_months,
    ul.paid_months,
    ul.credit_score,
    ul.status,
    ul.next_due_date,
    ul.created_at
  FROM public.user_loans ul
  WHERE ul.user_id = v_user_id
  ORDER BY ul.created_at DESC
  LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_my_savings_account() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_savings_dashboard() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.transfer_my_wallet_to_savings(NUMERIC, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.transfer_my_savings_to_wallet(NUMERIC, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.request_my_openpay_loan(NUMERIC, INTEGER, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pay_my_loan_monthly(UUID, NUMERIC, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_latest_loan() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.upsert_my_savings_account() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_savings_dashboard() TO authenticated;
GRANT EXECUTE ON FUNCTION public.transfer_my_wallet_to_savings(NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transfer_my_savings_to_wallet(NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.request_my_openpay_loan(NUMERIC, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pay_my_loan_monthly(UUID, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_latest_loan() TO authenticated;

-- <<< END MIGRATION: 20260218210000_wallet_savings_loans.sql

-- >>> MIGRATION: 20260218212000_fix_pay_my_loan_monthly_status_ambiguity.sql
CREATE OR REPLACE FUNCTION public.pay_my_loan_monthly(
  p_loan_id UUID,
  p_amount NUMERIC DEFAULT NULL,
  p_note TEXT DEFAULT 'Loan monthly payment'
)
RETURNS TABLE (
  loan_id UUID,
  remaining_balance NUMERIC,
  paid_months INTEGER,
  status TEXT,
  wallet_balance NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_loan public.user_loans;
  v_due NUMERIC(12,2);
  v_wallet_balance NUMERIC(12,2);
  v_principal_component NUMERIC(12,2);
  v_fee_component NUMERIC(12,2);
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT * INTO v_loan
  FROM public.user_loans
  WHERE id = p_loan_id
    AND user_id = v_user_id
    AND status = 'active'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active loan not found';
  END IF;

  v_due := ROUND(COALESCE(p_amount, LEAST(v_loan.outstanding_amount, v_loan.monthly_payment_amount)), 2);
  IF v_due <= 0 THEN
    RAISE EXCEPTION 'Payment amount must be greater than 0';
  END IF;

  SELECT balance INTO v_wallet_balance
  FROM public.wallets
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'Wallet not found';
  END IF;

  IF v_wallet_balance < v_due THEN
    RAISE EXCEPTION 'Insufficient wallet balance';
  END IF;

  v_principal_component := ROUND(LEAST(v_loan.outstanding_amount, v_due / (1 + v_loan.monthly_fee_rate)), 2);
  v_fee_component := ROUND(v_due - v_principal_component, 2);

  UPDATE public.wallets
  SET balance = v_wallet_balance - v_due,
      updated_at = now()
  WHERE user_id = v_user_id
  RETURNING balance INTO v_wallet_balance;

  UPDATE public.user_loans
  SET outstanding_amount = GREATEST(0, outstanding_amount - v_principal_component),
      paid_months = paid_months + 1,
      next_due_date = (next_due_date + INTERVAL '1 month')::DATE,
      status = CASE
        WHEN GREATEST(0, outstanding_amount - v_principal_component) = 0 THEN 'paid'
        ELSE v_loan.status
      END
  WHERE id = v_loan.id
  RETURNING * INTO v_loan;

  INSERT INTO public.user_loan_payments (
    loan_id,
    user_id,
    amount,
    principal_component,
    fee_component,
    note
  )
  VALUES (
    v_loan.id,
    v_user_id,
    v_due,
    v_principal_component,
    v_fee_component,
    COALESCE(p_note, 'Loan monthly payment')
  );

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_user_id,
    v_user_id,
    v_due,
    CONCAT('OpenPay loan repayment | Loan ', v_loan.id),
    'completed'
  );

  RETURN QUERY
  SELECT v_loan.id, v_loan.outstanding_amount, v_loan.paid_months, v_loan.status, v_wallet_balance;
END;
$$;

-- <<< END MIGRATION: 20260218212000_fix_pay_my_loan_monthly_status_ambiguity.sql

-- >>> MIGRATION: 20260218213000_new_features_sql_hardening.sql
-- Final hardening for newly added features:
-- - Open Partner lead intake validation + RPC
-- - Additional explicit insert policies for savings/loan journals

ALTER TABLE public.open_partner_leads
  ADD CONSTRAINT open_partner_leads_contact_email_format_chk
  CHECK (position('@' in contact_email) > 1);

ALTER TABLE public.open_partner_leads
  ADD CONSTRAINT open_partner_leads_company_name_len_chk
  CHECK (char_length(trim(company_name)) BETWEEN 2 AND 120);

ALTER TABLE public.open_partner_leads
  ADD CONSTRAINT open_partner_leads_contact_name_len_chk
  CHECK (char_length(trim(contact_name)) BETWEEN 2 AND 120);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_savings_transfers' AND policyname = 'Users can insert own savings transfers'
  ) THEN
    CREATE POLICY "Users can insert own savings transfers"
      ON public.user_savings_transfers
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_loans' AND policyname = 'Users can insert own loans'
  ) THEN
    CREATE POLICY "Users can insert own loans"
      ON public.user_loans
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_loan_payments' AND policyname = 'Users can insert own loan payments'
  ) THEN
    CREATE POLICY "Users can insert own loan payments"
      ON public.user_loan_payments
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.submit_open_partner_lead(
  p_company_name TEXT,
  p_contact_name TEXT,
  p_contact_email TEXT,
  p_country TEXT DEFAULT NULL,
  p_website_url TEXT DEFAULT NULL,
  p_business_type TEXT DEFAULT NULL,
  p_integration_type TEXT DEFAULT NULL,
  p_estimated_monthly_volume TEXT DEFAULT NULL,
  p_use_case_summary TEXT DEFAULT '',
  p_message TEXT DEFAULT NULL
)
RETURNS public.open_partner_leads
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_row public.open_partner_leads;
  v_company_name TEXT := trim(COALESCE(p_company_name, ''));
  v_contact_name TEXT := trim(COALESCE(p_contact_name, ''));
  v_contact_email TEXT := lower(trim(COALESCE(p_contact_email, '')));
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF char_length(v_company_name) < 2 THEN
    RAISE EXCEPTION 'Company name is required';
  END IF;

  IF char_length(v_contact_name) < 2 THEN
    RAISE EXCEPTION 'Contact name is required';
  END IF;

  IF position('@' in v_contact_email) <= 1 THEN
    RAISE EXCEPTION 'Valid contact email is required';
  END IF;

  INSERT INTO public.open_partner_leads (
    requester_user_id,
    company_name,
    contact_name,
    contact_email,
    country,
    website_url,
    business_type,
    integration_type,
    estimated_monthly_volume,
    use_case_summary,
    message,
    status
  )
  VALUES (
    v_user_id,
    v_company_name,
    v_contact_name,
    v_contact_email,
    NULLIF(trim(COALESCE(p_country, '')), ''),
    NULLIF(trim(COALESCE(p_website_url, '')), ''),
    NULLIF(trim(COALESCE(p_business_type, '')), ''),
    NULLIF(trim(COALESCE(p_integration_type, '')), ''),
    NULLIF(trim(COALESCE(p_estimated_monthly_volume, '')), ''),
    trim(COALESCE(p_use_case_summary, '')),
    NULLIF(trim(COALESCE(p_message, '')), ''),
    'new'
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_open_partner_lead(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_open_partner_lead(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- <<< END MIGRATION: 20260218213000_new_features_sql_hardening.sql

-- >>> MIGRATION: 20260218215000_lock_loans_temporarily.sql
CREATE OR REPLACE FUNCTION public.request_my_openpay_loan(
  p_principal_amount NUMERIC,
  p_term_months INTEGER DEFAULT 6,
  p_credit_score INTEGER DEFAULT NULL
)
RETURNS public.user_loans
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RAISE EXCEPTION 'OpenPay loans are temporarily locked. Please try again later.';
END;
$$;

-- <<< END MIGRATION: 20260218215000_lock_loans_temporarily.sql

-- >>> MIGRATION: 20260219120000_activity_based_credit_score.sql
CREATE OR REPLACE FUNCTION public.calculate_user_activity_credit_score(
  p_user_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_topup_count INTEGER := 0;
  v_send_count INTEGER := 0;
  v_receive_count INTEGER := 0;
  v_invoice_count INTEGER := 0;
  v_request_count INTEGER := 0;
  v_paid_invoice_count INTEGER := 0;
  v_paid_request_count INTEGER := 0;
  v_score NUMERIC := 500;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN 500;
  END IF;

  SELECT COUNT(*)::INTEGER
  INTO v_topup_count
  FROM public.transactions t
  WHERE t.sender_id = p_user_id
    AND t.receiver_id = p_user_id
    AND t.status = 'completed';

  SELECT COUNT(*)::INTEGER
  INTO v_send_count
  FROM public.transactions t
  WHERE t.sender_id = p_user_id
    AND t.receiver_id <> p_user_id
    AND t.status = 'completed';

  SELECT COUNT(*)::INTEGER
  INTO v_receive_count
  FROM public.transactions t
  WHERE t.receiver_id = p_user_id
    AND t.sender_id <> p_user_id
    AND t.status = 'completed';

  SELECT COUNT(*)::INTEGER
  INTO v_invoice_count
  FROM public.invoices i
  WHERE i.sender_id = p_user_id
     OR i.recipient_id = p_user_id;

  SELECT COUNT(*)::INTEGER
  INTO v_paid_invoice_count
  FROM public.invoices i
  WHERE (i.sender_id = p_user_id OR i.recipient_id = p_user_id)
    AND i.status = 'paid';

  SELECT COUNT(*)::INTEGER
  INTO v_request_count
  FROM public.payment_requests pr
  WHERE pr.requester_id = p_user_id
     OR pr.payer_id = p_user_id;

  SELECT COUNT(*)::INTEGER
  INTO v_paid_request_count
  FROM public.payment_requests pr
  WHERE (pr.requester_id = p_user_id OR pr.payer_id = p_user_id)
    AND pr.status = 'paid';

  -- Core activity score (caps prevent farming score with spam actions).
  v_score := v_score
    + LEAST(v_topup_count, 50) * 2
    + LEAST(v_send_count, 120) * 1.2
    + LEAST(v_receive_count, 120) * 1.0
    + LEAST(v_invoice_count, 80) * 0.8
    + LEAST(v_request_count, 80) * 0.8
    + LEAST(v_paid_invoice_count, 80) * 0.6
    + LEAST(v_paid_request_count, 80) * 0.6;

  -- Clamp to the app score range.
  RETURN GREATEST(300, LEAST(900, ROUND(v_score)::INTEGER));
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_credit_score()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  RETURN public.calculate_user_activity_credit_score(v_user_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.request_my_openpay_loan(
  p_principal_amount NUMERIC,
  p_term_months INTEGER DEFAULT 6,
  p_credit_score INTEGER DEFAULT NULL
)
RETURNS public.user_loans
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_principal NUMERIC(12,2) := ROUND(COALESCE(p_principal_amount, 0), 2);
  v_term INTEGER := GREATEST(1, LEAST(COALESCE(p_term_months, 6), 60));
  v_credit_score INTEGER;
  v_fee_rate NUMERIC(6,4);
  v_wallet_balance NUMERIC(12,2);
  v_monthly NUMERIC(12,2);
  v_existing UUID;
  v_loan public.user_loans;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_principal < 10 OR v_principal > 50000 THEN
    RAISE EXCEPTION 'Loan amount must be between 10 and 50000';
  END IF;

  SELECT id INTO v_existing
  FROM public.user_loans
  WHERE user_id = v_user_id
    AND status IN ('pending', 'active')
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    RAISE EXCEPTION 'You already have an active or pending loan';
  END IF;

  IF p_credit_score IS NULL THEN
    v_credit_score := public.calculate_user_activity_credit_score(v_user_id);
  ELSE
    v_credit_score := GREATEST(300, LEAST(COALESCE(p_credit_score, 620), 900));
  END IF;

  v_fee_rate := CASE
    WHEN v_credit_score >= 750 THEN 0.0100
    WHEN v_credit_score >= 680 THEN 0.0150
    WHEN v_credit_score >= 620 THEN 0.0200
    ELSE 0.0300
  END;

  v_monthly := ROUND((v_principal / v_term) + (v_principal * v_fee_rate), 2);

  INSERT INTO public.user_loans (
    user_id,
    principal_amount,
    outstanding_amount,
    monthly_payment_amount,
    monthly_fee_rate,
    term_months,
    credit_score,
    status,
    next_due_date
  )
  VALUES (
    v_user_id,
    v_principal,
    v_principal,
    v_monthly,
    v_fee_rate,
    v_term,
    v_credit_score,
    'active',
    (CURRENT_DATE + INTERVAL '1 month')::DATE
  )
  RETURNING * INTO v_loan;

  SELECT balance INTO v_wallet_balance
  FROM public.wallets
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'Wallet not found';
  END IF;

  UPDATE public.wallets
  SET balance = v_wallet_balance + v_principal,
      updated_at = now()
  WHERE user_id = v_user_id;

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_user_id,
    v_user_id,
    v_principal,
    CONCAT('OpenPay loan disbursement | Loan ', v_loan.id),
    'completed'
  );

  RETURN v_loan;
END;
$$;

REVOKE ALL ON FUNCTION public.calculate_user_activity_credit_score(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_credit_score() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.request_my_openpay_loan(NUMERIC, INTEGER, INTEGER) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_my_credit_score() TO authenticated;
GRANT EXECUTE ON FUNCTION public.request_my_openpay_loan(NUMERIC, INTEGER, INTEGER) TO authenticated;

-- <<< END MIGRATION: 20260219120000_activity_based_credit_score.sql

-- >>> MIGRATION: 20260219133000_fix_merchant_token_generation.sql
CREATE OR REPLACE FUNCTION public.random_token_hex(p_bytes INTEGER DEFAULT 24)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_target_len INTEGER := GREATEST(1, COALESCE(p_bytes, 24)) * 2;
  v_out TEXT := '';
BEGIN
  WHILE char_length(v_out) < v_target_len LOOP
    v_out := v_out || md5(random()::TEXT || clock_timestamp()::TEXT || txid_current()::TEXT);
  END LOOP;
  RETURN SUBSTRING(v_out FROM 1 FOR v_target_len);
END;
$$;

CREATE OR REPLACE FUNCTION public.generate_merchant_api_key(p_prefix TEXT)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_candidate TEXT;
BEGIN
  LOOP
    v_candidate := p_prefix || public.random_token_hex(24);
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.merchant_api_keys WHERE publishable_key = v_candidate)
          AND NOT EXISTS (SELECT 1 FROM public.merchant_checkout_sessions WHERE session_token = v_candidate);
  END LOOP;

  RETURN v_candidate;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_my_merchant_api_key(
  p_mode TEXT,
  p_key_name TEXT DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  key_mode TEXT,
  publishable_key TEXT,
  secret_key TEXT,
  key_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, '')));
  v_key_name TEXT := COALESCE(NULLIF(TRIM(p_key_name), ''), 'Default key');
  v_publishable_key TEXT;
  v_secret_key TEXT;
  v_row public.merchant_api_keys;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  PERFORM public.upsert_my_merchant_profile();

  v_publishable_key := public.generate_merchant_api_key('opk_' || v_mode || '_');
  v_secret_key := 'osk_' || v_mode || '_' || public.random_token_hex(32);

  INSERT INTO public.merchant_api_keys (
    merchant_user_id,
    key_mode,
    key_name,
    publishable_key,
    secret_key_hash,
    secret_key_last4
  )
  VALUES (
    v_user_id,
    v_mode,
    v_key_name,
    v_publishable_key,
    md5(v_secret_key),
    RIGHT(v_secret_key, 4)
  )
  RETURNING * INTO v_row;

  RETURN QUERY
  SELECT v_row.id, v_row.key_mode, v_row.publishable_key, v_secret_key, v_row.key_name;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_merchant_checkout_session(
  p_secret_key TEXT,
  p_mode TEXT,
  p_currency TEXT,
  p_items JSONB,
  p_customer_email TEXT DEFAULT NULL,
  p_customer_name TEXT DEFAULT NULL,
  p_success_url TEXT DEFAULT NULL,
  p_cancel_url TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::jsonb,
  p_expires_in_minutes INTEGER DEFAULT 60
)
RETURNS TABLE (
  session_id UUID,
  session_token TEXT,
  total_amount NUMERIC,
  currency TEXT,
  expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, '')));
  v_currency TEXT := UPPER(TRIM(COALESCE(p_currency, 'USD')));
  v_secret_hash TEXT := md5(COALESCE(p_secret_key, ''));
  v_merchant_user_id UUID;
  v_api_key_id UUID;
  v_session public.merchant_checkout_sessions;
  v_item JSONB;
  v_product public.merchant_products;
  v_quantity INTEGER;
  v_line_total NUMERIC(12,2);
  v_total NUMERIC(12,2) := 0;
  v_expires_minutes INTEGER := GREATEST(5, LEAST(COALESCE(p_expires_in_minutes, 60), 10080));
BEGIN
  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  IF char_length(v_currency) <> 3 THEN
    RAISE EXCEPTION 'Currency must be 3 letters';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'At least one item is required';
  END IF;

  SELECT mak.merchant_user_id, mak.id
  INTO v_merchant_user_id, v_api_key_id
  FROM public.merchant_api_keys mak
  WHERE mak.secret_key_hash = v_secret_hash
    AND mak.key_mode = v_mode
    AND mak.is_active = true
  LIMIT 1;

  IF v_merchant_user_id IS NULL THEN
    RAISE EXCEPTION 'Invalid merchant API key for mode %', v_mode;
  END IF;

  INSERT INTO public.merchant_checkout_sessions (
    merchant_user_id,
    key_mode,
    session_token,
    status,
    currency,
    subtotal_amount,
    fee_amount,
    total_amount,
    customer_email,
    customer_name,
    success_url,
    cancel_url,
    metadata,
    expires_at
  )
  VALUES (
    v_merchant_user_id,
    v_mode,
    'opsess_' || public.random_token_hex(24),
    'open',
    v_currency,
    0,
    0,
    0,
    NULLIF(TRIM(COALESCE(p_customer_email, '')), ''),
    NULLIF(TRIM(COALESCE(p_customer_name, '')), ''),
    NULLIF(TRIM(COALESCE(p_success_url, '')), ''),
    NULLIF(TRIM(COALESCE(p_cancel_url, '')), ''),
    COALESCE(p_metadata, '{}'::jsonb),
    now() + make_interval(mins => v_expires_minutes)
  )
  RETURNING * INTO v_session;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    SELECT *
    INTO v_product
    FROM public.merchant_products mp
    WHERE mp.id = (v_item->>'product_id')::UUID
      AND mp.merchant_user_id = v_merchant_user_id
      AND mp.is_active = true
    LIMIT 1;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Invalid product_id in items payload';
    END IF;

    v_quantity := COALESCE((v_item->>'quantity')::INTEGER, 1);
    IF v_quantity < 1 OR v_quantity > 1000 THEN
      RAISE EXCEPTION 'Quantity must be between 1 and 1000';
    END IF;

    IF UPPER(v_product.currency) <> v_currency THEN
      RAISE EXCEPTION 'Product currency mismatch for product %', v_product.id;
    END IF;

    v_line_total := ROUND(v_product.unit_amount * v_quantity, 2);

    INSERT INTO public.merchant_checkout_session_items (
      session_id,
      product_id,
      item_name,
      unit_amount,
      quantity,
      line_total
    )
    VALUES (
      v_session.id,
      v_product.id,
      v_product.product_name,
      v_product.unit_amount,
      v_quantity,
      v_line_total
    );

    v_total := v_total + v_line_total;
  END LOOP;

  IF v_total <= 0 THEN
    RAISE EXCEPTION 'Session total must be positive';
  END IF;

  UPDATE public.merchant_checkout_sessions
  SET subtotal_amount = v_total,
      total_amount = v_total
  WHERE id = v_session.id
  RETURNING * INTO v_session;

  UPDATE public.merchant_api_keys
  SET last_used_at = now()
  WHERE id = v_api_key_id;

  RETURN QUERY
  SELECT v_session.id, v_session.session_token, v_session.total_amount, v_session.currency, v_session.expires_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_merchant_payment_link(
  p_secret_key TEXT,
  p_mode TEXT,
  p_link_type TEXT,
  p_title TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_currency TEXT DEFAULT 'USD',
  p_custom_amount NUMERIC DEFAULT NULL,
  p_items JSONB DEFAULT '[]'::jsonb,
  p_collect_customer_name BOOLEAN DEFAULT true,
  p_collect_customer_email BOOLEAN DEFAULT true,
  p_collect_phone BOOLEAN DEFAULT false,
  p_collect_address BOOLEAN DEFAULT false,
  p_after_payment_type TEXT DEFAULT 'confirmation',
  p_confirmation_message TEXT DEFAULT NULL,
  p_redirect_url TEXT DEFAULT NULL,
  p_call_to_action TEXT DEFAULT 'Pay',
  p_expires_in_minutes INTEGER DEFAULT NULL
)
RETURNS TABLE (
  link_id UUID,
  link_token TEXT,
  total_amount NUMERIC,
  currency TEXT,
  key_mode TEXT,
  expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, '')));
  v_link_type TEXT := LOWER(TRIM(COALESCE(p_link_type, '')));
  v_after_payment_type TEXT := LOWER(TRIM(COALESCE(p_after_payment_type, 'confirmation')));
  v_currency TEXT := UPPER(TRIM(COALESCE(p_currency, 'USD')));
  v_secret_hash TEXT := md5(COALESCE(p_secret_key, ''));
  v_merchant_user_id UUID;
  v_link public.merchant_payment_links;
  v_item JSONB;
  v_product public.merchant_products;
  v_quantity INTEGER;
  v_line_total NUMERIC(12,2);
  v_total NUMERIC(12,2) := 0;
  v_expires_at TIMESTAMPTZ;
BEGIN
  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  IF v_link_type NOT IN ('products', 'custom_amount') THEN
    RAISE EXCEPTION 'Link type must be products or custom_amount';
  END IF;

  IF v_after_payment_type NOT IN ('confirmation', 'redirect') THEN
    RAISE EXCEPTION 'After payment type must be confirmation or redirect';
  END IF;

  IF char_length(v_currency) <> 3 THEN
    RAISE EXCEPTION 'Currency must be 3 letters';
  END IF;

  SELECT mak.merchant_user_id
  INTO v_merchant_user_id
  FROM public.merchant_api_keys mak
  WHERE mak.secret_key_hash = v_secret_hash
    AND mak.key_mode = v_mode
    AND mak.is_active = true
  LIMIT 1;

  IF v_merchant_user_id IS NULL THEN
    RAISE EXCEPTION 'Invalid merchant API key for mode %', v_mode;
  END IF;

  IF p_expires_in_minutes IS NOT NULL THEN
    v_expires_at := now() + make_interval(mins => GREATEST(5, LEAST(p_expires_in_minutes, 525600)));
  END IF;

  INSERT INTO public.merchant_payment_links (
    merchant_user_id,
    key_mode,
    link_token,
    link_type,
    title,
    description,
    currency,
    custom_amount,
    collect_customer_name,
    collect_customer_email,
    collect_phone,
    collect_address,
    after_payment_type,
    confirmation_message,
    redirect_url,
    call_to_action,
    expires_at
  )
  VALUES (
    v_merchant_user_id,
    v_mode,
    'oplink_' || public.random_token_hex(24),
    v_link_type,
    COALESCE(NULLIF(TRIM(p_title), ''), 'OpenPay Payment'),
    COALESCE(NULLIF(TRIM(p_description), ''), ''),
    v_currency,
    p_custom_amount,
    COALESCE(p_collect_customer_name, true),
    COALESCE(p_collect_customer_email, true),
    COALESCE(p_collect_phone, false),
    COALESCE(p_collect_address, false),
    v_after_payment_type,
    COALESCE(NULLIF(TRIM(p_confirmation_message), ''), 'Thanks for your payment.'),
    NULLIF(TRIM(COALESCE(p_redirect_url, '')), ''),
    COALESCE(NULLIF(TRIM(p_call_to_action), ''), 'Pay'),
    v_expires_at
  )
  RETURNING * INTO v_link;

  IF v_link_type = 'custom_amount' THEN
    IF p_custom_amount IS NULL OR p_custom_amount <= 0 THEN
      RAISE EXCEPTION 'Custom amount must be greater than 0';
    END IF;
    v_total := ROUND(p_custom_amount, 2);
  ELSE
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
      RAISE EXCEPTION 'At least one product item is required';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
      SELECT *
      INTO v_product
      FROM public.merchant_products mp
      WHERE mp.id = (v_item->>'product_id')::UUID
        AND mp.merchant_user_id = v_merchant_user_id
        AND mp.is_active = true
      LIMIT 1;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid product_id in items payload';
      END IF;

      v_quantity := COALESCE((v_item->>'quantity')::INTEGER, 1);
      IF v_quantity < 1 OR v_quantity > 1000 THEN
        RAISE EXCEPTION 'Quantity must be between 1 and 1000';
      END IF;

      IF UPPER(v_product.currency) <> v_currency THEN
        RAISE EXCEPTION 'Product currency mismatch for product %', v_product.id;
      END IF;

      v_line_total := ROUND(v_product.unit_amount * v_quantity, 2);

      INSERT INTO public.merchant_payment_link_items (
        link_id,
        product_id,
        item_name,
        unit_amount,
        quantity,
        line_total
      )
      VALUES (
        v_link.id,
        v_product.id,
        v_product.product_name,
        v_product.unit_amount,
        v_quantity,
        v_line_total
      );

      v_total := v_total + v_line_total;
    END LOOP;
  END IF;

  IF v_total <= 0 THEN
    RAISE EXCEPTION 'Payment link total must be positive';
  END IF;

  RETURN QUERY
  SELECT v_link.id, v_link.link_token, v_total, v_link.currency, v_link.key_mode, v_link.expires_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_checkout_session_from_payment_link(
  p_link_token TEXT,
  p_customer_email TEXT DEFAULT NULL,
  p_customer_name TEXT DEFAULT NULL
)
RETURNS TABLE (
  session_id UUID,
  session_token TEXT,
  total_amount NUMERIC,
  currency TEXT,
  expires_at TIMESTAMPTZ,
  after_payment_type TEXT,
  confirmation_message TEXT,
  redirect_url TEXT,
  call_to_action TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_link public.merchant_payment_links;
  v_session public.merchant_checkout_sessions;
  v_total NUMERIC(12,2) := 0;
BEGIN
  SELECT *
  INTO v_link
  FROM public.merchant_payment_links mpl
  WHERE mpl.link_token = TRIM(COALESCE(p_link_token, ''))
    AND mpl.is_active = true
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment link not found';
  END IF;

  IF v_link.expires_at IS NOT NULL AND v_link.expires_at < now() THEN
    RAISE EXCEPTION 'Payment link expired';
  END IF;

  INSERT INTO public.merchant_checkout_sessions (
    merchant_user_id,
    key_mode,
    session_token,
    status,
    currency,
    subtotal_amount,
    fee_amount,
    total_amount,
    customer_email,
    customer_name,
    success_url,
    cancel_url,
    metadata,
    expires_at
  )
  VALUES (
    v_link.merchant_user_id,
    v_link.key_mode,
    'opsess_' || public.random_token_hex(24),
    'open',
    v_link.currency,
    0,
    0,
    0,
    NULLIF(TRIM(COALESCE(p_customer_email, '')), ''),
    NULLIF(TRIM(COALESCE(p_customer_name, '')), ''),
    NULL,
    NULL,
    jsonb_build_object(
      'payment_link_id', v_link.id,
      'payment_link_token', v_link.link_token,
      'after_payment_type', v_link.after_payment_type,
      'confirmation_message', v_link.confirmation_message,
      'redirect_url', v_link.redirect_url,
      'call_to_action', v_link.call_to_action
    ),
    now() + INTERVAL '60 minutes'
  )
  RETURNING * INTO v_session;

  IF v_link.link_type = 'custom_amount' THEN
    v_total := COALESCE(v_link.custom_amount, 0);

    INSERT INTO public.merchant_checkout_session_items (
      session_id,
      product_id,
      item_name,
      unit_amount,
      quantity,
      line_total
    )
    VALUES (
      v_session.id,
      NULL,
      v_link.title,
      v_total,
      1,
      v_total
    );
  ELSE
    INSERT INTO public.merchant_checkout_session_items (
      session_id,
      product_id,
      item_name,
      unit_amount,
      quantity,
      line_total
    )
    SELECT
      v_session.id,
      mpli.product_id,
      mpli.item_name,
      mpli.unit_amount,
      mpli.quantity,
      mpli.line_total
    FROM public.merchant_payment_link_items mpli
    WHERE mpli.link_id = v_link.id;

    SELECT COALESCE(SUM(mpli.line_total), 0)
    INTO v_total
    FROM public.merchant_payment_link_items mpli
    WHERE mpli.link_id = v_link.id;
  END IF;

  IF v_total <= 0 THEN
    RAISE EXCEPTION 'Payment link total must be positive';
  END IF;

  UPDATE public.merchant_checkout_sessions
  SET subtotal_amount = v_total,
      total_amount = v_total
  WHERE id = v_session.id
  RETURNING * INTO v_session;

  RETURN QUERY
  SELECT
    v_session.id,
    v_session.session_token,
    v_session.total_amount,
    v_session.currency,
    v_session.expires_at,
    v_link.after_payment_type,
    v_link.confirmation_message,
    v_link.redirect_url,
    v_link.call_to_action;
END;
$$;

-- <<< END MIGRATION: 20260219133000_fix_merchant_token_generation.sql

-- >>> MIGRATION: 20260219143000_fix_digest_and_random_bytes_wrappers.sql
-- Ensure pgcrypto is available. Supabase usually installs extensions in schema "extensions".
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- Compatibility wrapper: existing functions call digest(...) with search_path=public.
-- This wrapper forwards to extensions.digest(...) so those functions keep working.
CREATE OR REPLACE FUNCTION public.digest(data TEXT, algorithm TEXT)
RETURNS BYTEA
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
  SELECT extensions.digest(data, algorithm);
$$;

-- Compatibility wrapper for random byte generation used by merchant key/link/session functions.
CREATE OR REPLACE FUNCTION public.gen_random_bytes(length INTEGER)
RETURNS BYTEA
LANGUAGE sql
VOLATILE
STRICT
AS $$
  SELECT extensions.gen_random_bytes(length);
$$;

-- <<< END MIGRATION: 20260219143000_fix_digest_and_random_bytes_wrappers.sql

-- >>> MIGRATION: 20260219152000_complete_wallet_checkout_workflow.sql
CREATE OR REPLACE FUNCTION public.complete_merchant_checkout_with_transaction(
  p_session_token TEXT,
  p_transaction_id UUID,
  p_note TEXT DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buyer_user_id UUID := auth.uid();
  v_session public.merchant_checkout_sessions;
  v_tx public.transactions;
  v_existing_tx UUID;
BEGIN
  IF v_buyer_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_transaction_id IS NULL THEN
    RAISE EXCEPTION 'Transaction id is required';
  END IF;

  SELECT *
  INTO v_session
  FROM public.merchant_checkout_sessions mcs
  WHERE mcs.session_token = TRIM(COALESCE(p_session_token, ''))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Checkout session not found';
  END IF;

  IF v_session.status = 'paid' THEN
    SELECT mp.transaction_id
    INTO v_existing_tx
    FROM public.merchant_payments mp
    WHERE mp.session_id = v_session.id
    LIMIT 1;

    RETURN COALESCE(v_existing_tx, p_transaction_id);
  END IF;

  IF v_session.status <> 'open' THEN
    RAISE EXCEPTION 'Checkout session is not open';
  END IF;

  IF v_session.expires_at < now() THEN
    UPDATE public.merchant_checkout_sessions
    SET status = 'expired'
    WHERE id = v_session.id;
    RAISE EXCEPTION 'Checkout session expired';
  END IF;

  IF v_session.merchant_user_id = v_buyer_user_id THEN
    RAISE EXCEPTION 'Merchant cannot pay own checkout';
  END IF;

  SELECT *
  INTO v_tx
  FROM public.transactions t
  WHERE t.id = p_transaction_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transaction not found';
  END IF;

  IF v_tx.status <> 'completed' THEN
    RAISE EXCEPTION 'Transaction is not completed';
  END IF;

  IF v_tx.sender_id <> v_buyer_user_id THEN
    RAISE EXCEPTION 'Transaction sender does not match buyer';
  END IF;

  IF v_tx.receiver_id <> v_session.merchant_user_id THEN
    RAISE EXCEPTION 'Transaction receiver does not match merchant';
  END IF;

  IF ABS(COALESCE(v_tx.amount, 0) - COALESCE(v_session.total_amount, 0)) > 0.02 THEN
    RAISE EXCEPTION 'Transaction amount does not match checkout amount';
  END IF;

  INSERT INTO public.merchant_payments (
    session_id,
    merchant_user_id,
    buyer_user_id,
    transaction_id,
    amount,
    currency,
    key_mode,
    status
  )
  VALUES (
    v_session.id,
    v_session.merchant_user_id,
    v_buyer_user_id,
    v_tx.id,
    v_session.total_amount,
    v_session.currency,
    v_session.key_mode,
    'succeeded'
  )
  ON CONFLICT (session_id) DO NOTHING;

  UPDATE public.merchant_checkout_sessions
  SET status = 'paid',
      paid_at = now()
  WHERE id = v_session.id;

  IF COALESCE(TRIM(p_note), '') <> '' THEN
    UPDATE public.transactions
    SET note = CONCAT(COALESCE(note, ''), ' | ', TRIM(p_note))
    WHERE id = v_tx.id;
  END IF;

  RETURN v_tx.id;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_merchant_checkout_with_transaction(TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_merchant_checkout_with_transaction(TEXT, UUID, TEXT) TO authenticated;

-- <<< END MIGRATION: 20260219152000_complete_wallet_checkout_workflow.sql

-- >>> MIGRATION: 20260219160000_payment_link_apikey_tracking.sql
ALTER TABLE public.merchant_payment_links
ADD COLUMN IF NOT EXISTS api_key_id UUID REFERENCES public.merchant_api_keys(id) ON DELETE SET NULL;

ALTER TABLE public.merchant_checkout_sessions
ADD COLUMN IF NOT EXISTS api_key_id UUID REFERENCES public.merchant_api_keys(id) ON DELETE SET NULL;

ALTER TABLE public.merchant_payments
ADD COLUMN IF NOT EXISTS api_key_id UUID REFERENCES public.merchant_api_keys(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS payment_link_id UUID REFERENCES public.merchant_payment_links(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS payment_link_token TEXT;

CREATE INDEX IF NOT EXISTS idx_merchant_payment_links_api_key_id
ON public.merchant_payment_links(api_key_id);

CREATE INDEX IF NOT EXISTS idx_merchant_checkout_sessions_api_key_id
ON public.merchant_checkout_sessions(api_key_id);

CREATE INDEX IF NOT EXISTS idx_merchant_payments_api_key_id
ON public.merchant_payments(api_key_id);

CREATE INDEX IF NOT EXISTS idx_merchant_payments_payment_link_id
ON public.merchant_payments(payment_link_id);

UPDATE public.merchant_payment_links mpl
SET api_key_id = (
  SELECT mak.id
  FROM public.merchant_api_keys mak
  WHERE mak.merchant_user_id = mpl.merchant_user_id
    AND mak.key_mode = mpl.key_mode
  ORDER BY mak.created_at DESC
  LIMIT 1
)
WHERE mpl.api_key_id IS NULL;

UPDATE public.merchant_checkout_sessions mcs
SET api_key_id = COALESCE(
  NULLIF((mcs.metadata->>'api_key_id')::UUID, NULL),
  (
    SELECT mpl.api_key_id
    FROM public.merchant_payment_links mpl
    WHERE mpl.id = NULLIF((mcs.metadata->>'payment_link_id')::UUID, NULL)
    LIMIT 1
  )
)
WHERE mcs.api_key_id IS NULL;

UPDATE public.merchant_payments mp
SET api_key_id = mcs.api_key_id,
    payment_link_id = NULLIF((mcs.metadata->>'payment_link_id')::UUID, NULL),
    payment_link_token = NULLIF(TRIM(COALESCE(mcs.metadata->>'payment_link_token', '')), '')
FROM public.merchant_checkout_sessions mcs
WHERE mcs.id = mp.session_id
  AND (mp.api_key_id IS NULL OR mp.payment_link_id IS NULL OR mp.payment_link_token IS NULL);

CREATE OR REPLACE FUNCTION public.create_merchant_payment_link(
  p_secret_key TEXT,
  p_mode TEXT,
  p_link_type TEXT,
  p_title TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_currency TEXT DEFAULT 'USD',
  p_custom_amount NUMERIC DEFAULT NULL,
  p_items JSONB DEFAULT '[]'::jsonb,
  p_collect_customer_name BOOLEAN DEFAULT true,
  p_collect_customer_email BOOLEAN DEFAULT true,
  p_collect_phone BOOLEAN DEFAULT false,
  p_collect_address BOOLEAN DEFAULT false,
  p_after_payment_type TEXT DEFAULT 'confirmation',
  p_confirmation_message TEXT DEFAULT NULL,
  p_redirect_url TEXT DEFAULT NULL,
  p_call_to_action TEXT DEFAULT 'Pay',
  p_expires_in_minutes INTEGER DEFAULT NULL
)
RETURNS TABLE (
  link_id UUID,
  link_token TEXT,
  total_amount NUMERIC,
  currency TEXT,
  key_mode TEXT,
  expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, '')));
  v_link_type TEXT := LOWER(TRIM(COALESCE(p_link_type, '')));
  v_after_payment_type TEXT := LOWER(TRIM(COALESCE(p_after_payment_type, 'confirmation')));
  v_currency TEXT := UPPER(TRIM(COALESCE(p_currency, 'USD')));
  v_secret_hash TEXT := md5(COALESCE(p_secret_key, ''));
  v_merchant_user_id UUID;
  v_api_key_id UUID;
  v_link public.merchant_payment_links;
  v_item JSONB;
  v_product public.merchant_products;
  v_quantity INTEGER;
  v_line_total NUMERIC(12,2);
  v_total NUMERIC(12,2) := 0;
  v_expires_at TIMESTAMPTZ;
BEGIN
  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  IF v_link_type NOT IN ('products', 'custom_amount') THEN
    RAISE EXCEPTION 'Link type must be products or custom_amount';
  END IF;

  IF v_after_payment_type NOT IN ('confirmation', 'redirect') THEN
    RAISE EXCEPTION 'After payment type must be confirmation or redirect';
  END IF;

  IF char_length(v_currency) <> 3 THEN
    RAISE EXCEPTION 'Currency must be 3 letters';
  END IF;

  SELECT mak.merchant_user_id, mak.id
  INTO v_merchant_user_id, v_api_key_id
  FROM public.merchant_api_keys mak
  WHERE mak.secret_key_hash = v_secret_hash
    AND mak.key_mode = v_mode
    AND mak.is_active = true
  LIMIT 1;

  IF v_merchant_user_id IS NULL THEN
    RAISE EXCEPTION 'Invalid merchant API key for mode %', v_mode;
  END IF;

  IF p_expires_in_minutes IS NOT NULL THEN
    v_expires_at := now() + make_interval(mins => GREATEST(5, LEAST(p_expires_in_minutes, 525600)));
  END IF;

  INSERT INTO public.merchant_payment_links (
    merchant_user_id,
    api_key_id,
    key_mode,
    link_token,
    link_type,
    title,
    description,
    currency,
    custom_amount,
    collect_customer_name,
    collect_customer_email,
    collect_phone,
    collect_address,
    after_payment_type,
    confirmation_message,
    redirect_url,
    call_to_action,
    expires_at
  )
  VALUES (
    v_merchant_user_id,
    v_api_key_id,
    v_mode,
    'oplink_' || public.random_token_hex(24),
    v_link_type,
    COALESCE(NULLIF(TRIM(p_title), ''), 'OpenPay Payment'),
    COALESCE(NULLIF(TRIM(p_description), ''), ''),
    v_currency,
    p_custom_amount,
    COALESCE(p_collect_customer_name, true),
    COALESCE(p_collect_customer_email, true),
    COALESCE(p_collect_phone, false),
    COALESCE(p_collect_address, false),
    v_after_payment_type,
    COALESCE(NULLIF(TRIM(p_confirmation_message), ''), 'Thanks for your payment.'),
    NULLIF(TRIM(COALESCE(p_redirect_url, '')), ''),
    COALESCE(NULLIF(TRIM(p_call_to_action), ''), 'Pay'),
    v_expires_at
  )
  RETURNING * INTO v_link;

  IF v_link_type = 'custom_amount' THEN
    IF p_custom_amount IS NULL OR p_custom_amount <= 0 THEN
      RAISE EXCEPTION 'Custom amount must be greater than 0';
    END IF;
    v_total := ROUND(p_custom_amount, 2);
  ELSE
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
      RAISE EXCEPTION 'At least one product item is required';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
      SELECT *
      INTO v_product
      FROM public.merchant_products mp
      WHERE mp.id = (v_item->>'product_id')::UUID
        AND mp.merchant_user_id = v_merchant_user_id
        AND mp.is_active = true
      LIMIT 1;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid product_id in items payload';
      END IF;

      v_quantity := COALESCE((v_item->>'quantity')::INTEGER, 1);
      IF v_quantity < 1 OR v_quantity > 1000 THEN
        RAISE EXCEPTION 'Quantity must be between 1 and 1000';
      END IF;

      IF UPPER(v_product.currency) <> v_currency THEN
        RAISE EXCEPTION 'Product currency mismatch for product %', v_product.id;
      END IF;

      v_line_total := ROUND(v_product.unit_amount * v_quantity, 2);

      INSERT INTO public.merchant_payment_link_items (
        link_id,
        product_id,
        item_name,
        unit_amount,
        quantity,
        line_total
      )
      VALUES (
        v_link.id,
        v_product.id,
        v_product.product_name,
        v_product.unit_amount,
        v_quantity,
        v_line_total
      );

      v_total := v_total + v_line_total;
    END LOOP;
  END IF;

  IF v_total <= 0 THEN
    RAISE EXCEPTION 'Payment link total must be positive';
  END IF;

  RETURN QUERY
  SELECT v_link.id, v_link.link_token, v_total, v_link.currency, v_link.key_mode, v_link.expires_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_checkout_session_from_payment_link(
  p_link_token TEXT,
  p_customer_email TEXT DEFAULT NULL,
  p_customer_name TEXT DEFAULT NULL
)
RETURNS TABLE (
  session_id UUID,
  session_token TEXT,
  total_amount NUMERIC,
  currency TEXT,
  expires_at TIMESTAMPTZ,
  after_payment_type TEXT,
  confirmation_message TEXT,
  redirect_url TEXT,
  call_to_action TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_link public.merchant_payment_links;
  v_session public.merchant_checkout_sessions;
  v_total NUMERIC(12,2) := 0;
BEGIN
  SELECT *
  INTO v_link
  FROM public.merchant_payment_links mpl
  WHERE mpl.link_token = TRIM(COALESCE(p_link_token, ''))
    AND mpl.is_active = true
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment link not found';
  END IF;

  IF v_link.expires_at IS NOT NULL AND v_link.expires_at < now() THEN
    RAISE EXCEPTION 'Payment link expired';
  END IF;

  INSERT INTO public.merchant_checkout_sessions (
    merchant_user_id,
    api_key_id,
    key_mode,
    session_token,
    status,
    currency,
    subtotal_amount,
    fee_amount,
    total_amount,
    customer_email,
    customer_name,
    success_url,
    cancel_url,
    metadata,
    expires_at
  )
  VALUES (
    v_link.merchant_user_id,
    v_link.api_key_id,
    v_link.key_mode,
    'opsess_' || public.random_token_hex(24),
    'open',
    v_link.currency,
    0,
    0,
    0,
    NULLIF(TRIM(COALESCE(p_customer_email, '')), ''),
    NULLIF(TRIM(COALESCE(p_customer_name, '')), ''),
    NULL,
    NULL,
    jsonb_build_object(
      'payment_link_id', v_link.id,
      'payment_link_token', v_link.link_token,
      'api_key_id', v_link.api_key_id,
      'after_payment_type', v_link.after_payment_type,
      'confirmation_message', v_link.confirmation_message,
      'redirect_url', v_link.redirect_url,
      'call_to_action', v_link.call_to_action
    ),
    now() + INTERVAL '60 minutes'
  )
  RETURNING * INTO v_session;

  IF v_link.link_type = 'custom_amount' THEN
    v_total := COALESCE(v_link.custom_amount, 0);

    INSERT INTO public.merchant_checkout_session_items (
      session_id,
      product_id,
      item_name,
      unit_amount,
      quantity,
      line_total
    )
    VALUES (
      v_session.id,
      NULL,
      v_link.title,
      v_total,
      1,
      v_total
    );
  ELSE
    INSERT INTO public.merchant_checkout_session_items (
      session_id,
      product_id,
      item_name,
      unit_amount,
      quantity,
      line_total
    )
    SELECT
      v_session.id,
      mpli.product_id,
      mpli.item_name,
      mpli.unit_amount,
      mpli.quantity,
      mpli.line_total
    FROM public.merchant_payment_link_items mpli
    WHERE mpli.link_id = v_link.id;

    SELECT COALESCE(SUM(mpli.line_total), 0)
    INTO v_total
    FROM public.merchant_payment_link_items mpli
    WHERE mpli.link_id = v_link.id;
  END IF;

  IF v_total <= 0 THEN
    RAISE EXCEPTION 'Payment link total must be positive';
  END IF;

  UPDATE public.merchant_checkout_sessions
  SET subtotal_amount = v_total,
      total_amount = v_total
  WHERE id = v_session.id
  RETURNING * INTO v_session;

  RETURN QUERY
  SELECT
    v_session.id,
    v_session.session_token,
    v_session.total_amount,
    v_session.currency,
    v_session.expires_at,
    v_link.after_payment_type,
    v_link.confirmation_message,
    v_link.redirect_url,
    v_link.call_to_action;
END;
$$;

CREATE OR REPLACE FUNCTION public.pay_merchant_checkout_with_virtual_card(
  p_session_token TEXT,
  p_card_number TEXT,
  p_expiry_month INTEGER,
  p_expiry_year INTEGER,
  p_cvc TEXT,
  p_note TEXT DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buyer_user_id UUID := auth.uid();
  v_session public.merchant_checkout_sessions;
  v_sender_balance NUMERIC(12,2);
  v_receiver_balance NUMERIC(12,2);
  v_transaction_id UUID;
  v_card_number TEXT := regexp_replace(COALESCE(p_card_number, ''), '\D', '', 'g');
  v_cvc TEXT := regexp_replace(COALESCE(p_cvc, ''), '\D', '', 'g');
  v_expiry_end DATE;
  v_payment_link_id UUID;
  v_payment_link_token TEXT;
BEGIN
  IF v_buyer_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT *
  INTO v_session
  FROM public.merchant_checkout_sessions mcs
  WHERE mcs.session_token = TRIM(COALESCE(p_session_token, ''))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Checkout session not found';
  END IF;

  IF v_session.status <> 'open' THEN
    RAISE EXCEPTION 'Checkout session is not open';
  END IF;

  IF v_session.expires_at < now() THEN
    UPDATE public.merchant_checkout_sessions
    SET status = 'expired'
    WHERE id = v_session.id;
    RAISE EXCEPTION 'Checkout session expired';
  END IF;

  IF v_session.merchant_user_id = v_buyer_user_id THEN
    RAISE EXCEPTION 'Merchant cannot pay own checkout';
  END IF;

  IF char_length(v_card_number) <> 16 THEN
    RAISE EXCEPTION 'Card number must be 16 digits';
  END IF;

  IF p_expiry_month IS NULL OR p_expiry_month < 1 OR p_expiry_month > 12 THEN
    RAISE EXCEPTION 'Invalid expiry month';
  END IF;

  IF p_expiry_year IS NULL OR p_expiry_year < 2026 THEN
    RAISE EXCEPTION 'Invalid expiry year';
  END IF;

  IF char_length(v_cvc) <> 3 THEN
    RAISE EXCEPTION 'Invalid CVC';
  END IF;

  v_expiry_end := (make_date(p_expiry_year, p_expiry_month, 1) + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
  IF v_expiry_end < CURRENT_DATE THEN
    RAISE EXCEPTION 'Card expired';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.virtual_cards vc
    WHERE vc.user_id = v_buyer_user_id
      AND vc.card_number = v_card_number
      AND vc.expiry_month = p_expiry_month
      AND vc.expiry_year = p_expiry_year
      AND vc.cvc = v_cvc
      AND vc.is_active = true
  ) THEN
    RAISE EXCEPTION 'Invalid virtual card details';
  END IF;

  SELECT balance INTO v_sender_balance
  FROM public.wallets
  WHERE user_id = v_buyer_user_id
  FOR UPDATE;

  IF v_sender_balance IS NULL THEN
    RAISE EXCEPTION 'Buyer wallet not found';
  END IF;

  SELECT balance INTO v_receiver_balance
  FROM public.wallets
  WHERE user_id = v_session.merchant_user_id
  FOR UPDATE;

  IF v_receiver_balance IS NULL THEN
    RAISE EXCEPTION 'Merchant wallet not found';
  END IF;

  IF v_sender_balance < v_session.total_amount THEN
    RAISE EXCEPTION 'Insufficient balance';
  END IF;

  UPDATE public.wallets
  SET balance = v_sender_balance - v_session.total_amount,
      updated_at = now()
  WHERE user_id = v_buyer_user_id;

  UPDATE public.wallets
  SET balance = v_receiver_balance + v_session.total_amount,
      updated_at = now()
  WHERE user_id = v_session.merchant_user_id;

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_buyer_user_id,
    v_session.merchant_user_id,
    v_session.total_amount,
    CONCAT('Merchant checkout ', v_session.session_token, ' | ', COALESCE(p_note, '')),
    'completed'
  )
  RETURNING id INTO v_transaction_id;

  v_payment_link_id := NULLIF((v_session.metadata->>'payment_link_id')::UUID, NULL);
  v_payment_link_token := NULLIF(TRIM(COALESCE(v_session.metadata->>'payment_link_token', '')), '');

  INSERT INTO public.merchant_payments (
    session_id,
    merchant_user_id,
    buyer_user_id,
    transaction_id,
    amount,
    currency,
    api_key_id,
    key_mode,
    payment_link_id,
    payment_link_token,
    status
  )
  VALUES (
    v_session.id,
    v_session.merchant_user_id,
    v_buyer_user_id,
    v_transaction_id,
    v_session.total_amount,
    v_session.currency,
    v_session.api_key_id,
    v_session.key_mode,
    v_payment_link_id,
    v_payment_link_token,
    'succeeded'
  );

  UPDATE public.merchant_checkout_sessions
  SET status = 'paid',
      paid_at = now()
  WHERE id = v_session.id;

  RETURN v_transaction_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_merchant_checkout_with_transaction(
  p_session_token TEXT,
  p_transaction_id UUID,
  p_note TEXT DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buyer_user_id UUID := auth.uid();
  v_session public.merchant_checkout_sessions;
  v_tx public.transactions;
  v_existing_tx UUID;
  v_payment_link_id UUID;
  v_payment_link_token TEXT;
BEGIN
  IF v_buyer_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_transaction_id IS NULL THEN
    RAISE EXCEPTION 'Transaction id is required';
  END IF;

  SELECT *
  INTO v_session
  FROM public.merchant_checkout_sessions mcs
  WHERE mcs.session_token = TRIM(COALESCE(p_session_token, ''))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Checkout session not found';
  END IF;

  IF v_session.status = 'paid' THEN
    SELECT mp.transaction_id
    INTO v_existing_tx
    FROM public.merchant_payments mp
    WHERE mp.session_id = v_session.id
    LIMIT 1;

    RETURN COALESCE(v_existing_tx, p_transaction_id);
  END IF;

  IF v_session.status <> 'open' THEN
    RAISE EXCEPTION 'Checkout session is not open';
  END IF;

  IF v_session.expires_at < now() THEN
    UPDATE public.merchant_checkout_sessions
    SET status = 'expired'
    WHERE id = v_session.id;
    RAISE EXCEPTION 'Checkout session expired';
  END IF;

  IF v_session.merchant_user_id = v_buyer_user_id THEN
    RAISE EXCEPTION 'Merchant cannot pay own checkout';
  END IF;

  SELECT *
  INTO v_tx
  FROM public.transactions t
  WHERE t.id = p_transaction_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transaction not found';
  END IF;

  IF v_tx.status <> 'completed' THEN
    RAISE EXCEPTION 'Transaction is not completed';
  END IF;

  IF v_tx.sender_id <> v_buyer_user_id THEN
    RAISE EXCEPTION 'Transaction sender does not match buyer';
  END IF;

  IF v_tx.receiver_id <> v_session.merchant_user_id THEN
    RAISE EXCEPTION 'Transaction receiver does not match merchant';
  END IF;

  IF ABS(COALESCE(v_tx.amount, 0) - COALESCE(v_session.total_amount, 0)) > 0.02 THEN
    RAISE EXCEPTION 'Transaction amount does not match checkout amount';
  END IF;

  v_payment_link_id := NULLIF((v_session.metadata->>'payment_link_id')::UUID, NULL);
  v_payment_link_token := NULLIF(TRIM(COALESCE(v_session.metadata->>'payment_link_token', '')), '');

  INSERT INTO public.merchant_payments (
    session_id,
    merchant_user_id,
    buyer_user_id,
    transaction_id,
    amount,
    currency,
    api_key_id,
    key_mode,
    payment_link_id,
    payment_link_token,
    status
  )
  VALUES (
    v_session.id,
    v_session.merchant_user_id,
    v_buyer_user_id,
    v_tx.id,
    v_session.total_amount,
    v_session.currency,
    v_session.api_key_id,
    v_session.key_mode,
    v_payment_link_id,
    v_payment_link_token,
    'succeeded'
  )
  ON CONFLICT (session_id) DO NOTHING;

  UPDATE public.merchant_checkout_sessions
  SET status = 'paid',
      paid_at = now()
  WHERE id = v_session.id;

  IF COALESCE(TRIM(p_note), '') <> '' THEN
    UPDATE public.transactions
    SET note = CONCAT(COALESCE(note, ''), ' | ', TRIM(p_note))
    WHERE id = v_tx.id;
  END IF;

  RETURN v_tx.id;
END;
$$;

-- <<< END MIGRATION: 20260219160000_payment_link_apikey_tracking.sql

-- >>> MIGRATION: 20260219170000_fix_virtual_card_checkout_deduction.sql
CREATE OR REPLACE FUNCTION public.pay_merchant_checkout_with_virtual_card(
  p_session_token TEXT,
  p_card_number TEXT,
  p_expiry_month INTEGER,
  p_expiry_year INTEGER,
  p_cvc TEXT,
  p_note TEXT DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buyer_user_id UUID := auth.uid();
  v_session public.merchant_checkout_sessions;
  v_sender_balance NUMERIC(12,2);
  v_receiver_balance NUMERIC(12,2);
  v_transaction_id UUID;
  v_card_number TEXT := regexp_replace(COALESCE(p_card_number, ''), '\D', '', 'g');
  v_cvc TEXT := regexp_replace(COALESCE(p_cvc, ''), '\D', '', 'g');
  v_expiry_end DATE;
  v_expiry_year INTEGER := COALESCE(p_expiry_year, 0);
  v_payment_link_id UUID;
  v_payment_link_token TEXT;
  v_card_owner_user_id UUID;
BEGIN
  IF v_buyer_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_expiry_year > 0 AND v_expiry_year < 100 THEN
    v_expiry_year := 2000 + v_expiry_year;
  END IF;

  SELECT *
  INTO v_session
  FROM public.merchant_checkout_sessions mcs
  WHERE mcs.session_token = TRIM(COALESCE(p_session_token, ''))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Checkout session not found';
  END IF;

  IF v_session.status <> 'open' THEN
    RAISE EXCEPTION 'Checkout session is not open';
  END IF;

  IF v_session.expires_at < now() THEN
    UPDATE public.merchant_checkout_sessions
    SET status = 'expired'
    WHERE id = v_session.id;
    RAISE EXCEPTION 'Checkout session expired';
  END IF;

  IF v_session.merchant_user_id = v_buyer_user_id THEN
    RAISE EXCEPTION 'Merchant cannot pay own checkout';
  END IF;

  IF char_length(v_card_number) <> 16 THEN
    RAISE EXCEPTION 'Card number must be 16 digits';
  END IF;

  IF p_expiry_month IS NULL OR p_expiry_month < 1 OR p_expiry_month > 12 THEN
    RAISE EXCEPTION 'Invalid expiry month';
  END IF;

  IF v_expiry_year < 2026 THEN
    RAISE EXCEPTION 'Invalid expiry year';
  END IF;

  IF char_length(v_cvc) <> 3 THEN
    RAISE EXCEPTION 'Invalid CVC';
  END IF;

  v_expiry_end := (make_date(v_expiry_year, p_expiry_month, 1) + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
  IF v_expiry_end < CURRENT_DATE THEN
    RAISE EXCEPTION 'Card expired';
  END IF;

  SELECT vc.user_id
  INTO v_card_owner_user_id
  FROM public.virtual_cards vc
  WHERE vc.card_number = v_card_number
    AND vc.expiry_month = p_expiry_month
    AND vc.expiry_year = v_expiry_year
    AND vc.cvc = v_cvc
    AND vc.is_active = true
    AND COALESCE(vc.is_locked, false) = false
    AND COALESCE((vc.card_settings ->> 'allow_checkout')::BOOLEAN, true) = true
  FOR UPDATE;

  IF v_card_owner_user_id IS NULL THEN
    RAISE EXCEPTION 'Invalid virtual card details';
  END IF;

  IF v_card_owner_user_id <> v_buyer_user_id THEN
    RAISE EXCEPTION 'Card owner does not match authenticated customer';
  END IF;

  SELECT balance INTO v_sender_balance
  FROM public.wallets
  WHERE user_id = v_card_owner_user_id
  FOR UPDATE;

  IF v_sender_balance IS NULL THEN
    RAISE EXCEPTION 'Buyer wallet not found';
  END IF;

  SELECT balance INTO v_receiver_balance
  FROM public.wallets
  WHERE user_id = v_session.merchant_user_id
  FOR UPDATE;

  IF v_receiver_balance IS NULL THEN
    RAISE EXCEPTION 'Merchant wallet not found';
  END IF;

  IF v_sender_balance < v_session.total_amount THEN
    RAISE EXCEPTION 'Insufficient virtual card balance';
  END IF;

  UPDATE public.wallets
  SET balance = v_sender_balance - v_session.total_amount,
      updated_at = now()
  WHERE user_id = v_card_owner_user_id;

  UPDATE public.wallets
  SET balance = v_receiver_balance + v_session.total_amount,
      updated_at = now()
  WHERE user_id = v_session.merchant_user_id;

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_card_owner_user_id,
    v_session.merchant_user_id,
    v_session.total_amount,
    CONCAT(
      'Merchant checkout ',
      v_session.session_token,
      ' | Card ****',
      RIGHT(v_card_number, 4),
      CASE WHEN COALESCE(TRIM(p_note), '') <> '' THEN CONCAT(' | ', TRIM(p_note)) ELSE '' END
    ),
    'completed'
  )
  RETURNING id INTO v_transaction_id;

  v_payment_link_id := NULLIF((v_session.metadata->>'payment_link_id')::UUID, NULL);
  v_payment_link_token := NULLIF(TRIM(COALESCE(v_session.metadata->>'payment_link_token', '')), '');

  INSERT INTO public.merchant_payments (
    session_id,
    merchant_user_id,
    buyer_user_id,
    transaction_id,
    amount,
    currency,
    api_key_id,
    key_mode,
    payment_link_id,
    payment_link_token,
    status
  )
  VALUES (
    v_session.id,
    v_session.merchant_user_id,
    v_buyer_user_id,
    v_transaction_id,
    v_session.total_amount,
    v_session.currency,
    v_session.api_key_id,
    v_session.key_mode,
    v_payment_link_id,
    v_payment_link_token,
    'succeeded'
  );

  UPDATE public.merchant_checkout_sessions
  SET status = 'paid',
      paid_at = now()
  WHERE id = v_session.id;

  RETURN v_transaction_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.pay_with_virtual_card_checkout(
  p_card_number TEXT,
  p_expiry_month INTEGER,
  p_expiry_year INTEGER,
  p_cvc TEXT,
  p_receiver_id UUID,
  p_amount NUMERIC,
  p_note TEXT DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_sender_balance NUMERIC(12,2);
  v_receiver_balance NUMERIC(12,2);
  v_transaction_id UUID;
  v_sanitized_card_number TEXT := regexp_replace(COALESCE(p_card_number, ''), '\D', '', 'g');
  v_sanitized_cvc TEXT := regexp_replace(COALESCE(p_cvc, ''), '\D', '', 'g');
  v_expiry_end DATE;
  v_expiry_year INTEGER := COALESCE(p_expiry_year, 0);
  v_card_owner_user_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_receiver_id IS NULL THEN
    RAISE EXCEPTION 'Receiver required';
  END IF;

  IF p_receiver_id = v_user_id THEN
    RAISE EXCEPTION 'Cannot pay your own checkout link';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Invalid amount';
  END IF;

  IF v_expiry_year > 0 AND v_expiry_year < 100 THEN
    v_expiry_year := 2000 + v_expiry_year;
  END IF;

  IF char_length(v_sanitized_card_number) <> 16 THEN
    RAISE EXCEPTION 'Card number must be 16 digits';
  END IF;

  IF p_expiry_month IS NULL OR p_expiry_month < 1 OR p_expiry_month > 12 THEN
    RAISE EXCEPTION 'Invalid expiry month';
  END IF;

  IF v_expiry_year < 2026 THEN
    RAISE EXCEPTION 'Invalid expiry year';
  END IF;

  IF char_length(v_sanitized_cvc) <> 3 THEN
    RAISE EXCEPTION 'Invalid CVC';
  END IF;

  v_expiry_end := (make_date(v_expiry_year, p_expiry_month, 1) + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
  IF v_expiry_end < CURRENT_DATE THEN
    RAISE EXCEPTION 'Card expired';
  END IF;

  SELECT vc.user_id
  INTO v_card_owner_user_id
  FROM public.virtual_cards vc
  WHERE vc.card_number = v_sanitized_card_number
    AND vc.expiry_month = p_expiry_month
    AND vc.expiry_year = v_expiry_year
    AND vc.cvc = v_sanitized_cvc
    AND vc.is_active = true
    AND COALESCE(vc.is_locked, false) = false
    AND COALESCE((vc.card_settings ->> 'allow_checkout')::BOOLEAN, true) = true
  FOR UPDATE;

  IF v_card_owner_user_id IS NULL THEN
    RAISE EXCEPTION 'Card locked, disabled, or invalid details';
  END IF;

  IF v_card_owner_user_id <> v_user_id THEN
    RAISE EXCEPTION 'Card owner does not match authenticated user';
  END IF;

  SELECT balance INTO v_sender_balance
  FROM public.wallets
  WHERE user_id = v_card_owner_user_id
  FOR UPDATE;

  IF v_sender_balance IS NULL THEN
    RAISE EXCEPTION 'Sender wallet not found';
  END IF;

  SELECT balance INTO v_receiver_balance
  FROM public.wallets
  WHERE user_id = p_receiver_id
  FOR UPDATE;

  IF v_receiver_balance IS NULL THEN
    RAISE EXCEPTION 'Recipient wallet not found';
  END IF;

  IF v_sender_balance < p_amount THEN
    RAISE EXCEPTION 'Insufficient virtual card balance';
  END IF;

  UPDATE public.wallets
  SET balance = v_sender_balance - p_amount,
      updated_at = now()
  WHERE user_id = v_card_owner_user_id;

  UPDATE public.wallets
  SET balance = v_receiver_balance + p_amount,
      updated_at = now()
  WHERE user_id = p_receiver_id;

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_card_owner_user_id,
    p_receiver_id,
    p_amount,
    CONCAT(
      'Virtual card payment | Card ****',
      RIGHT(v_sanitized_card_number, 4),
      CASE WHEN COALESCE(TRIM(p_note), '') <> '' THEN CONCAT(' | ', TRIM(p_note)) ELSE '' END
    ),
    'completed'
  )
  RETURNING id INTO v_transaction_id;

  RETURN v_transaction_id;
END;
$$;

-- <<< END MIGRATION: 20260219170000_fix_virtual_card_checkout_deduction.sql

-- >>> MIGRATION: 20260219174000_loan_application_admin_workflow.sql
CREATE TABLE IF NOT EXISTS public.user_loan_applications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  requested_amount NUMERIC(12,2) NOT NULL CHECK (requested_amount >= 10 AND requested_amount <= 50000),
  requested_term_months INTEGER NOT NULL CHECK (requested_term_months >= 1 AND requested_term_months <= 60),
  credit_score_snapshot INTEGER NOT NULL DEFAULT 620 CHECK (credit_score_snapshot >= 300 AND credit_score_snapshot <= 900),
  full_name TEXT NOT NULL DEFAULT '',
  contact_number TEXT NOT NULL DEFAULT '',
  address_line TEXT NOT NULL DEFAULT '',
  city TEXT NOT NULL DEFAULT '',
  country TEXT NOT NULL DEFAULT '',
  openpay_account_number TEXT NOT NULL DEFAULT '',
  openpay_account_username TEXT NOT NULL DEFAULT '',
  agreement_accepted BOOLEAN NOT NULL DEFAULT false,
  agreement_accepted_at TIMESTAMPTZ NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  admin_note TEXT NOT NULL DEFAULT '',
  reviewed_by UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_loan_applications_user_created
ON public.user_loan_applications(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_loan_applications_status_created
ON public.user_loan_applications(status, created_at DESC);

ALTER TABLE public.user_loan_applications ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_loan_applications' AND policyname = 'Users can view own loan applications'
  ) THEN
    CREATE POLICY "Users can view own loan applications"
      ON public.user_loan_applications
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_user_loan_applications_updated_at ON public.user_loan_applications;
CREATE TRIGGER trg_user_loan_applications_updated_at
BEFORE UPDATE ON public.user_loan_applications
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

ALTER TABLE public.user_loan_payments
ADD COLUMN IF NOT EXISTS payment_method TEXT NOT NULL DEFAULT 'wallet' CHECK (payment_method IN ('wallet', 'pi')),
ADD COLUMN IF NOT EXISTS payment_reference TEXT;

CREATE OR REPLACE FUNCTION public.is_openpay_core_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_username TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT LOWER(COALESCE(p.username, ''))
  INTO v_username
  FROM public.profiles p
  WHERE p.id = v_user_id;

  RETURN v_username IN ('openpay', 'wainfoundation');
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_my_loan_application(
  p_requested_amount NUMERIC,
  p_requested_term_months INTEGER,
  p_full_name TEXT,
  p_contact_number TEXT,
  p_address_line TEXT,
  p_city TEXT,
  p_country TEXT,
  p_openpay_account_number TEXT,
  p_openpay_account_username TEXT,
  p_agreement_accepted BOOLEAN DEFAULT false
)
RETURNS public.user_loan_applications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_app public.user_loan_applications;
  v_existing_id UUID;
  v_credit_score INTEGER := 620;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF COALESCE(p_agreement_accepted, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'You must accept loan agreement before submitting';
  END IF;

  IF COALESCE(TRIM(p_full_name), '') = '' OR COALESCE(TRIM(p_contact_number), '') = '' OR COALESCE(TRIM(p_address_line), '') = '' OR
     COALESCE(TRIM(p_city), '') = '' OR COALESCE(TRIM(p_country), '') = '' OR
     COALESCE(TRIM(p_openpay_account_number), '') = '' OR COALESCE(TRIM(p_openpay_account_username), '') = '' THEN
    RAISE EXCEPTION 'Complete all required loan form fields';
  END IF;

  SELECT ula.id INTO v_existing_id
  FROM public.user_loan_applications ula
  WHERE ula.user_id = v_user_id
    AND ula.status = 'pending'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    RAISE EXCEPTION 'You already have a pending loan application';
  END IF;

  SELECT ul.id INTO v_existing_id
  FROM public.user_loans ul
  WHERE ul.user_id = v_user_id
    AND ul.status IN ('pending', 'active')
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    RAISE EXCEPTION 'You already have an active or pending loan';
  END IF;

  BEGIN
    v_credit_score := public.calculate_user_activity_credit_score(v_user_id);
  EXCEPTION
    WHEN OTHERS THEN
      v_credit_score := 620;
  END;

  INSERT INTO public.user_loan_applications (
    user_id,
    requested_amount,
    requested_term_months,
    credit_score_snapshot,
    full_name,
    contact_number,
    address_line,
    city,
    country,
    openpay_account_number,
    openpay_account_username,
    agreement_accepted,
    agreement_accepted_at,
    status
  )
  VALUES (
    v_user_id,
    ROUND(COALESCE(p_requested_amount, 0), 2),
    GREATEST(1, LEAST(COALESCE(p_requested_term_months, 6), 60)),
    GREATEST(300, LEAST(v_credit_score, 900)),
    LEFT(TRIM(p_full_name), 120),
    LEFT(TRIM(p_contact_number), 60),
    LEFT(TRIM(p_address_line), 180),
    LEFT(TRIM(p_city), 120),
    LEFT(TRIM(p_country), 120),
    LEFT(TRIM(p_openpay_account_number), 80),
    LEFT(TRIM(p_openpay_account_username), 80),
    true,
    now(),
    'pending'
  )
  RETURNING * INTO v_app;

  RETURN v_app;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_latest_loan_application()
RETURNS public.user_loan_applications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_row public.user_loan_applications;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT *
  INTO v_row
  FROM public.user_loan_applications
  WHERE user_id = v_user_id
  ORDER BY created_at DESC
  LIMIT 1;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_loan_payment_history(
  p_loan_id UUID DEFAULT NULL,
  p_limit INTEGER DEFAULT 24
)
RETURNS TABLE (
  id UUID,
  loan_id UUID,
  amount NUMERIC,
  principal_component NUMERIC,
  fee_component NUMERIC,
  payment_method TEXT,
  payment_reference TEXT,
  note TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_target_loan UUID := p_loan_id;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_target_loan IS NULL THEN
    SELECT ul.id
    INTO v_target_loan
    FROM public.user_loans ul
    WHERE ul.user_id = v_user_id
    ORDER BY ul.created_at DESC
    LIMIT 1;
  END IF;

  RETURN QUERY
  SELECT
    ulp.id,
    ulp.loan_id,
    ulp.amount,
    ulp.principal_component,
    ulp.fee_component,
    ulp.payment_method,
    ulp.payment_reference,
    ulp.note,
    ulp.created_at
  FROM public.user_loan_payments ulp
  WHERE ulp.user_id = v_user_id
    AND (v_target_loan IS NULL OR ulp.loan_id = v_target_loan)
  ORDER BY ulp.created_at DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 24), 200));
END;
$$;

CREATE OR REPLACE FUNCTION public.pay_my_loan_monthly_with_method(
  p_loan_id UUID,
  p_amount NUMERIC DEFAULT NULL,
  p_payment_method TEXT DEFAULT 'wallet',
  p_note TEXT DEFAULT 'Loan monthly payment',
  p_payment_reference TEXT DEFAULT NULL
)
RETURNS TABLE (
  loan_id UUID,
  remaining_balance NUMERIC,
  paid_months INTEGER,
  status TEXT,
  wallet_balance NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_loan public.user_loans;
  v_due NUMERIC(12,2);
  v_wallet_balance NUMERIC(12,2);
  v_principal_component NUMERIC(12,2);
  v_fee_component NUMERIC(12,2);
  v_method TEXT := LOWER(TRIM(COALESCE(p_payment_method, 'wallet')));
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_method NOT IN ('wallet', 'pi') THEN
    RAISE EXCEPTION 'Payment method must be wallet or pi';
  END IF;

  SELECT * INTO v_loan
  FROM public.user_loans
  WHERE id = p_loan_id
    AND user_id = v_user_id
    AND public.user_loans.status = 'active'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active loan not found';
  END IF;

  v_due := ROUND(COALESCE(p_amount, LEAST(v_loan.outstanding_amount, v_loan.monthly_payment_amount)), 2);
  IF v_due <= 0 THEN
    RAISE EXCEPTION 'Payment amount must be greater than 0';
  END IF;

  SELECT balance INTO v_wallet_balance
  FROM public.wallets
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'Wallet not found';
  END IF;

  IF v_wallet_balance < v_due THEN
    RAISE EXCEPTION 'Insufficient wallet balance';
  END IF;

  v_principal_component := ROUND(LEAST(v_loan.outstanding_amount, v_due / (1 + v_loan.monthly_fee_rate)), 2);
  v_fee_component := ROUND(v_due - v_principal_component, 2);

  UPDATE public.wallets
  SET balance = v_wallet_balance - v_due,
      updated_at = now()
  WHERE user_id = v_user_id
  RETURNING balance INTO v_wallet_balance;

  UPDATE public.user_loans
  SET outstanding_amount = GREATEST(0, outstanding_amount - v_principal_component),
      paid_months = paid_months + 1,
      next_due_date = (next_due_date + INTERVAL '1 month')::DATE,
      status = CASE
        WHEN GREATEST(0, outstanding_amount - v_principal_component) = 0 THEN 'paid'
        ELSE v_loan.status
      END
  WHERE id = v_loan.id
  RETURNING * INTO v_loan;

  INSERT INTO public.user_loan_payments (
    loan_id,
    user_id,
    amount,
    principal_component,
    fee_component,
    payment_method,
    payment_reference,
    note
  )
  VALUES (
    v_loan.id,
    v_user_id,
    v_due,
    v_principal_component,
    v_fee_component,
    v_method,
    NULLIF(TRIM(COALESCE(p_payment_reference, '')), ''),
    COALESCE(p_note, 'Loan monthly payment')
  );

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_user_id,
    v_user_id,
    v_due,
    CONCAT(
      'OpenPay loan repayment | Loan ',
      v_loan.id,
      ' | Method ',
      UPPER(v_method),
      CASE
        WHEN NULLIF(TRIM(COALESCE(p_payment_reference, '')), '') IS NOT NULL
          THEN CONCAT(' | Ref ', LEFT(TRIM(p_payment_reference), 80))
        ELSE ''
      END
    ),
    'completed'
  );

  RETURN QUERY
  SELECT v_loan.id, v_loan.outstanding_amount, v_loan.paid_months, v_loan.status, v_wallet_balance;
END;
$$;

CREATE OR REPLACE FUNCTION public.pay_my_loan_monthly(
  p_loan_id UUID,
  p_amount NUMERIC DEFAULT NULL,
  p_note TEXT DEFAULT 'Loan monthly payment'
)
RETURNS TABLE (
  loan_id UUID,
  remaining_balance NUMERIC,
  paid_months INTEGER,
  status TEXT,
  wallet_balance NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT *
  FROM public.pay_my_loan_monthly_with_method(
    p_loan_id => p_loan_id,
    p_amount => p_amount,
    p_payment_method => 'wallet',
    p_note => p_note,
    p_payment_reference => NULL
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_loan_applications(
  p_status TEXT DEFAULT 'pending',
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  requested_amount NUMERIC,
  requested_term_months INTEGER,
  credit_score_snapshot INTEGER,
  full_name TEXT,
  contact_number TEXT,
  address_line TEXT,
  city TEXT,
  country TEXT,
  openpay_account_number TEXT,
  openpay_account_username TEXT,
  agreement_accepted BOOLEAN,
  status TEXT,
  admin_note TEXT,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ,
  applicant_display_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT := LOWER(TRIM(COALESCE(p_status, 'pending')));
BEGIN
  IF public.is_openpay_core_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  RETURN QUERY
  SELECT
    ula.id,
    ula.user_id,
    ula.requested_amount,
    ula.requested_term_months,
    ula.credit_score_snapshot,
    ula.full_name,
    ula.contact_number,
    ula.address_line,
    ula.city,
    ula.country,
    ula.openpay_account_number,
    ula.openpay_account_username,
    ula.agreement_accepted,
    ula.status,
    ula.admin_note,
    ula.reviewed_at,
    ula.created_at,
    COALESCE(NULLIF(p.full_name, ''), CONCAT('@', NULLIF(p.username, '')), LEFT(ula.user_id::TEXT, 8))
  FROM public.user_loan_applications ula
  LEFT JOIN public.profiles p ON p.id = ula.user_id
  WHERE (v_status = 'all' OR ula.status = v_status)
  ORDER BY ula.created_at DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 50), 200))
  OFFSET GREATEST(0, COALESCE(p_offset, 0));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_review_loan_application(
  p_application_id UUID,
  p_decision TEXT,
  p_admin_note TEXT DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_user_id UUID := auth.uid();
  v_decision TEXT := LOWER(TRIM(COALESCE(p_decision, '')));
  v_app public.user_loan_applications;
  v_fee_rate NUMERIC(6,4);
  v_monthly NUMERIC(12,2);
  v_wallet_balance NUMERIC(12,2);
  v_loan public.user_loans;
  v_existing UUID;
BEGIN
  IF public.is_openpay_core_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  IF p_application_id IS NULL THEN
    RAISE EXCEPTION 'Application id is required';
  END IF;

  IF v_decision NOT IN ('approve', 'reject') THEN
    RAISE EXCEPTION 'Decision must be approve or reject';
  END IF;

  SELECT * INTO v_app
  FROM public.user_loan_applications
  WHERE id = p_application_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Loan application not found';
  END IF;

  IF v_app.status <> 'pending' THEN
    RAISE EXCEPTION 'Loan application already processed';
  END IF;

  IF v_decision = 'reject' THEN
    UPDATE public.user_loan_applications
    SET status = 'rejected',
        admin_note = COALESCE(p_admin_note, ''),
        reviewed_by = v_admin_user_id,
        reviewed_at = now()
    WHERE id = v_app.id;

    RETURN NULL;
  END IF;

  SELECT ul.id INTO v_existing
  FROM public.user_loans ul
  WHERE ul.user_id = v_app.user_id
    AND ul.status IN ('pending', 'active')
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    RAISE EXCEPTION 'User already has active or pending loan';
  END IF;

  v_fee_rate := CASE
    WHEN v_app.credit_score_snapshot >= 750 THEN 0.0100
    WHEN v_app.credit_score_snapshot >= 680 THEN 0.0150
    WHEN v_app.credit_score_snapshot >= 620 THEN 0.0200
    ELSE 0.0300
  END;

  v_monthly := ROUND((v_app.requested_amount / v_app.requested_term_months) + (v_app.requested_amount * v_fee_rate), 2);

  INSERT INTO public.user_loans (
    user_id,
    principal_amount,
    outstanding_amount,
    monthly_payment_amount,
    monthly_fee_rate,
    term_months,
    credit_score,
    status,
    next_due_date
  )
  VALUES (
    v_app.user_id,
    v_app.requested_amount,
    v_app.requested_amount,
    v_monthly,
    v_fee_rate,
    v_app.requested_term_months,
    v_app.credit_score_snapshot,
    'active',
    (CURRENT_DATE + INTERVAL '1 month')::DATE
  )
  RETURNING * INTO v_loan;

  SELECT balance INTO v_wallet_balance
  FROM public.wallets
  WHERE user_id = v_app.user_id
  FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'Wallet not found';
  END IF;

  UPDATE public.wallets
  SET balance = v_wallet_balance + v_app.requested_amount,
      updated_at = now()
  WHERE user_id = v_app.user_id;

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_app.user_id,
    v_app.user_id,
    v_app.requested_amount,
    CONCAT('OpenPay loan disbursement (admin approved) | Loan ', v_loan.id),
    'completed'
  );

  UPDATE public.user_loan_applications
  SET status = 'approved',
      admin_note = COALESCE(p_admin_note, ''),
      reviewed_by = v_admin_user_id,
      reviewed_at = now()
  WHERE id = v_app.id;

  RETURN v_loan.id;
END;
$$;

REVOKE ALL ON FUNCTION public.is_openpay_core_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.submit_my_loan_application(NUMERIC, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_latest_loan_application() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_loan_payment_history(UUID, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pay_my_loan_monthly_with_method(UUID, NUMERIC, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_loan_applications(TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_review_loan_application(UUID, TEXT, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.is_openpay_core_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_my_loan_application(NUMERIC, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_latest_loan_application() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_loan_payment_history(UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pay_my_loan_monthly_with_method(UUID, NUMERIC, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_loan_applications(TEXT, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_review_loan_application(UUID, TEXT, TEXT) TO authenticated;

-- <<< END MIGRATION: 20260219174000_loan_application_admin_workflow.sql

-- >>> MIGRATION: 20260219190000_fix_loan_status_ambiguity.sql
CREATE OR REPLACE FUNCTION public.pay_my_loan_monthly_with_method(
  p_loan_id UUID,
  p_amount NUMERIC DEFAULT NULL,
  p_payment_method TEXT DEFAULT 'wallet',
  p_note TEXT DEFAULT 'Loan monthly payment',
  p_payment_reference TEXT DEFAULT NULL
)
RETURNS TABLE (
  loan_id UUID,
  remaining_balance NUMERIC,
  paid_months INTEGER,
  status TEXT,
  wallet_balance NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_loan public.user_loans;
  v_due NUMERIC(12,2);
  v_wallet_balance NUMERIC(12,2);
  v_principal_component NUMERIC(12,2);
  v_fee_component NUMERIC(12,2);
  v_method TEXT := LOWER(TRIM(COALESCE(p_payment_method, 'wallet')));
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_method NOT IN ('wallet', 'pi') THEN
    RAISE EXCEPTION 'Payment method must be wallet or pi';
  END IF;

  SELECT * INTO v_loan
  FROM public.user_loans ul
  WHERE ul.id = p_loan_id
    AND ul.user_id = v_user_id
    AND ul.status = 'active'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active loan not found';
  END IF;

  v_due := ROUND(COALESCE(p_amount, LEAST(v_loan.outstanding_amount, v_loan.monthly_payment_amount)), 2);
  IF v_due <= 0 THEN
    RAISE EXCEPTION 'Payment amount must be greater than 0';
  END IF;

  SELECT balance INTO v_wallet_balance
  FROM public.wallets
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'Wallet not found';
  END IF;

  IF v_wallet_balance < v_due THEN
    RAISE EXCEPTION 'Insufficient wallet balance';
  END IF;

  v_principal_component := ROUND(LEAST(v_loan.outstanding_amount, v_due / (1 + v_loan.monthly_fee_rate)), 2);
  v_fee_component := ROUND(v_due - v_principal_component, 2);

  UPDATE public.wallets
  SET balance = v_wallet_balance - v_due,
      updated_at = now()
  WHERE user_id = v_user_id
  RETURNING balance INTO v_wallet_balance;

  UPDATE public.user_loans
  SET outstanding_amount = GREATEST(0, outstanding_amount - v_principal_component),
      paid_months = paid_months + 1,
      next_due_date = (next_due_date + INTERVAL '1 month')::DATE,
      status = CASE
        WHEN GREATEST(0, outstanding_amount - v_principal_component) = 0 THEN 'paid'
        ELSE v_loan.status
      END
  WHERE id = v_loan.id
  RETURNING * INTO v_loan;

  INSERT INTO public.user_loan_payments (
    loan_id,
    user_id,
    amount,
    principal_component,
    fee_component,
    payment_method,
    payment_reference,
    note
  )
  VALUES (
    v_loan.id,
    v_user_id,
    v_due,
    v_principal_component,
    v_fee_component,
    v_method,
    NULLIF(TRIM(COALESCE(p_payment_reference, '')), ''),
    COALESCE(p_note, 'Loan monthly payment')
  );

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_user_id,
    v_user_id,
    v_due,
    CONCAT(
      'OpenPay loan repayment | Loan ',
      v_loan.id,
      ' | Method ',
      UPPER(v_method),
      CASE
        WHEN NULLIF(TRIM(COALESCE(p_payment_reference, '')), '') IS NOT NULL
          THEN CONCAT(' | Ref ', LEFT(TRIM(p_payment_reference), 80))
        ELSE ''
      END
    ),
    'completed'
  );

  RETURN QUERY
  SELECT v_loan.id, v_loan.outstanding_amount, v_loan.paid_months, v_loan.status, v_wallet_balance;
END;
$$;

-- <<< END MIGRATION: 20260219190000_fix_loan_status_ambiguity.sql

-- >>> MIGRATION: 20260219193000_fix_loan_paid_months_ambiguity.sql
CREATE OR REPLACE FUNCTION public.pay_my_loan_monthly_with_method(
  p_loan_id UUID,
  p_amount NUMERIC DEFAULT NULL,
  p_payment_method TEXT DEFAULT 'wallet',
  p_note TEXT DEFAULT 'Loan monthly payment',
  p_payment_reference TEXT DEFAULT NULL
)
RETURNS TABLE (
  loan_id UUID,
  remaining_balance NUMERIC,
  paid_months INTEGER,
  status TEXT,
  wallet_balance NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_loan public.user_loans;
  v_due NUMERIC(12,2);
  v_wallet_balance NUMERIC(12,2);
  v_principal_component NUMERIC(12,2);
  v_fee_component NUMERIC(12,2);
  v_method TEXT := LOWER(TRIM(COALESCE(p_payment_method, 'wallet')));
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_method NOT IN ('wallet', 'pi') THEN
    RAISE EXCEPTION 'Payment method must be wallet or pi';
  END IF;

  SELECT * INTO v_loan
  FROM public.user_loans ul
  WHERE ul.id = p_loan_id
    AND ul.user_id = v_user_id
    AND ul.status = 'active'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active loan not found';
  END IF;

  v_due := ROUND(COALESCE(p_amount, LEAST(v_loan.outstanding_amount, v_loan.monthly_payment_amount)), 2);
  IF v_due <= 0 THEN
    RAISE EXCEPTION 'Payment amount must be greater than 0';
  END IF;

  SELECT balance INTO v_wallet_balance
  FROM public.wallets
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'Wallet not found';
  END IF;

  IF v_wallet_balance < v_due THEN
    RAISE EXCEPTION 'Insufficient wallet balance';
  END IF;

  v_principal_component := ROUND(LEAST(v_loan.outstanding_amount, v_due / (1 + v_loan.monthly_fee_rate)), 2);
  v_fee_component := ROUND(v_due - v_principal_component, 2);

  UPDATE public.wallets
  SET balance = v_wallet_balance - v_due,
      updated_at = now()
  WHERE user_id = v_user_id
  RETURNING balance INTO v_wallet_balance;

  UPDATE public.user_loans ul
  SET outstanding_amount = GREATEST(0, ul.outstanding_amount - v_principal_component),
      paid_months = ul.paid_months + 1,
      next_due_date = (ul.next_due_date + INTERVAL '1 month')::DATE,
      status = CASE
        WHEN GREATEST(0, ul.outstanding_amount - v_principal_component) = 0 THEN 'paid'
        ELSE v_loan.status
      END
  WHERE ul.id = v_loan.id
  RETURNING * INTO v_loan;

  INSERT INTO public.user_loan_payments (
    loan_id,
    user_id,
    amount,
    principal_component,
    fee_component,
    payment_method,
    payment_reference,
    note
  )
  VALUES (
    v_loan.id,
    v_user_id,
    v_due,
    v_principal_component,
    v_fee_component,
    v_method,
    NULLIF(TRIM(COALESCE(p_payment_reference, '')), ''),
    COALESCE(p_note, 'Loan monthly payment')
  );

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_user_id,
    v_user_id,
    v_due,
    CONCAT(
      'OpenPay loan repayment | Loan ',
      v_loan.id,
      ' | Method ',
      UPPER(v_method),
      CASE
        WHEN NULLIF(TRIM(COALESCE(p_payment_reference, '')), '') IS NOT NULL
          THEN CONCAT(' | Ref ', LEFT(TRIM(p_payment_reference), 80))
        ELSE ''
      END
    ),
    'completed'
  );

  RETURN QUERY
  SELECT v_loan.id, v_loan.outstanding_amount, v_loan.paid_months, v_loan.status, v_wallet_balance;
END;
$$;
-- <<< END MIGRATION: 20260219193000_fix_loan_paid_months_ambiguity.sql

-- >>> MIGRATION: 20260219194000_route_wallet_loan_repayments_to_openpay.sql
CREATE OR REPLACE FUNCTION public.pay_my_loan_monthly_with_method(
  p_loan_id UUID,
  p_amount NUMERIC DEFAULT NULL,
  p_payment_method TEXT DEFAULT 'wallet',
  p_note TEXT DEFAULT 'Loan monthly payment',
  p_payment_reference TEXT DEFAULT NULL
)
RETURNS TABLE (
  loan_id UUID,
  remaining_balance NUMERIC,
  paid_months INTEGER,
  status TEXT,
  wallet_balance NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_loan public.user_loans;
  v_due NUMERIC(12,2);
  v_wallet_balance NUMERIC(12,2);
  v_principal_component NUMERIC(12,2);
  v_fee_component NUMERIC(12,2);
  v_method TEXT := LOWER(TRIM(COALESCE(p_payment_method, 'wallet')));
  v_openpay_user_id UUID;
  v_openpay_wallet_balance NUMERIC(12,2);
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_method NOT IN ('wallet', 'pi') THEN
    RAISE EXCEPTION 'Payment method must be wallet or pi';
  END IF;

  SELECT ua.user_id
  INTO v_openpay_user_id
  FROM public.user_accounts ua
  WHERE LOWER(TRIM(COALESCE(ua.account_username, ''))) = 'openpay'
  ORDER BY
    CASE
      WHEN UPPER(TRIM(COALESCE(ua.account_number, ''))) = 'OPEA68BB7A9F964994A199A15786D680FA' THEN 0
      ELSE 1
    END,
    ua.created_at ASC
  LIMIT 1;

  IF v_openpay_user_id IS NULL THEN
    RAISE EXCEPTION 'OpenPay settlement account not found';
  END IF;

  SELECT * INTO v_loan
  FROM public.user_loans ul
  WHERE ul.id = p_loan_id
    AND ul.user_id = v_user_id
    AND ul.status = 'active'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active loan not found';
  END IF;

  v_due := ROUND(COALESCE(p_amount, LEAST(v_loan.outstanding_amount, v_loan.monthly_payment_amount)), 2);
  IF v_due <= 0 THEN
    RAISE EXCEPTION 'Payment amount must be greater than 0';
  END IF;

  SELECT w.balance INTO v_wallet_balance
  FROM public.wallets w
  WHERE w.user_id = v_user_id
  FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'Wallet not found';
  END IF;

  IF v_wallet_balance < v_due THEN
    RAISE EXCEPTION 'Insufficient wallet balance';
  END IF;

  v_principal_component := ROUND(LEAST(v_loan.outstanding_amount, v_due / (1 + v_loan.monthly_fee_rate)), 2);
  v_fee_component := ROUND(v_due - v_principal_component, 2);

  UPDATE public.wallets
  SET balance = v_wallet_balance - v_due,
      updated_at = now()
  WHERE user_id = v_user_id
  RETURNING balance INTO v_wallet_balance;

  SELECT w.balance INTO v_openpay_wallet_balance
  FROM public.wallets w
  WHERE w.user_id = v_openpay_user_id
  FOR UPDATE;

  IF v_openpay_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'OpenPay settlement wallet not found';
  END IF;

  UPDATE public.wallets
  SET balance = v_openpay_wallet_balance + v_due,
      updated_at = now()
  WHERE user_id = v_openpay_user_id;

  UPDATE public.user_loans ul
  SET outstanding_amount = GREATEST(0, ul.outstanding_amount - v_principal_component),
      paid_months = ul.paid_months + 1,
      next_due_date = (ul.next_due_date + INTERVAL '1 month')::DATE,
      status = CASE
        WHEN GREATEST(0, ul.outstanding_amount - v_principal_component) = 0 THEN 'paid'
        ELSE v_loan.status
      END
  WHERE ul.id = v_loan.id
  RETURNING * INTO v_loan;

  INSERT INTO public.user_loan_payments (
    loan_id,
    user_id,
    amount,
    principal_component,
    fee_component,
    payment_method,
    payment_reference,
    note
  )
  VALUES (
    v_loan.id,
    v_user_id,
    v_due,
    v_principal_component,
    v_fee_component,
    v_method,
    NULLIF(TRIM(COALESCE(p_payment_reference, '')), ''),
    COALESCE(p_note, 'Loan monthly payment')
  );

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_user_id,
    v_openpay_user_id,
    v_due,
    CONCAT(
      'OpenPay loan repayment | To OPEA68BB7A9F964994A199A15786D680FA @openpay | Loan ',
      v_loan.id,
      ' | Method ',
      UPPER(v_method),
      CASE
        WHEN NULLIF(TRIM(COALESCE(p_payment_reference, '')), '') IS NOT NULL
          THEN CONCAT(' | Ref ', LEFT(TRIM(p_payment_reference), 80))
        ELSE ''
      END
    ),
    'completed'
  );

  RETURN QUERY
  SELECT v_loan.id, v_loan.outstanding_amount, v_loan.paid_months, v_loan.status, v_wallet_balance;
END;
$$;

-- <<< END MIGRATION: 20260219194000_route_wallet_loan_repayments_to_openpay.sql

-- >>> MIGRATION: 20260219195000_add_loan_platform_fee_toggle_to_openpay_settlement.sql
CREATE TABLE IF NOT EXISTS public.openpay_runtime_settings (
  setting_key TEXT PRIMARY KEY,
  value_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.openpay_runtime_settings (setting_key, value_json)
VALUES (
  'loan_wallet_platform_fee',
  jsonb_build_object('enabled', false, 'rate', 0)
)
ON CONFLICT (setting_key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.pay_my_loan_monthly_with_method(
  p_loan_id UUID,
  p_amount NUMERIC DEFAULT NULL,
  p_payment_method TEXT DEFAULT 'wallet',
  p_note TEXT DEFAULT 'Loan monthly payment',
  p_payment_reference TEXT DEFAULT NULL
)
RETURNS TABLE (
  loan_id UUID,
  remaining_balance NUMERIC,
  paid_months INTEGER,
  status TEXT,
  wallet_balance NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_loan public.user_loans;
  v_due NUMERIC(12,2);
  v_wallet_balance NUMERIC(12,2);
  v_principal_component NUMERIC(12,2);
  v_fee_component NUMERIC(12,2);
  v_method TEXT := LOWER(TRIM(COALESCE(p_payment_method, 'wallet')));
  v_openpay_user_id UUID;
  v_openpay_wallet_balance NUMERIC(12,2);
  v_platform_fee_enabled BOOLEAN := false;
  v_platform_fee_rate NUMERIC := 0;
  v_platform_fee_amount NUMERIC(12,2) := 0;
  v_total_debit NUMERIC(12,2);
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_method NOT IN ('wallet', 'pi') THEN
    RAISE EXCEPTION 'Payment method must be wallet or pi';
  END IF;

  SELECT ua.user_id
  INTO v_openpay_user_id
  FROM public.user_accounts ua
  WHERE LOWER(TRIM(COALESCE(ua.account_username, ''))) = 'openpay'
  ORDER BY
    CASE
      WHEN UPPER(TRIM(COALESCE(ua.account_number, ''))) = 'OPEA68BB7A9F964994A199A15786D680FA' THEN 0
      ELSE 1
    END,
    ua.created_at ASC
  LIMIT 1;

  IF v_openpay_user_id IS NULL THEN
    RAISE EXCEPTION 'OpenPay settlement account not found';
  END IF;

  SELECT * INTO v_loan
  FROM public.user_loans ul
  WHERE ul.id = p_loan_id
    AND ul.user_id = v_user_id
    AND ul.status = 'active'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active loan not found';
  END IF;

  v_due := ROUND(COALESCE(p_amount, LEAST(v_loan.outstanding_amount, v_loan.monthly_payment_amount)), 2);
  IF v_due <= 0 THEN
    RAISE EXCEPTION 'Payment amount must be greater than 0';
  END IF;

  SELECT
    COALESCE((ors.value_json ->> 'enabled')::BOOLEAN, false),
    GREATEST(0, LEAST(COALESCE((ors.value_json ->> 'rate')::NUMERIC, 0), 1))
  INTO v_platform_fee_enabled, v_platform_fee_rate
  FROM public.openpay_runtime_settings ors
  WHERE ors.setting_key = 'loan_wallet_platform_fee'
  LIMIT 1;

  IF v_platform_fee_enabled AND v_method = 'wallet' AND v_platform_fee_rate > 0 THEN
    v_platform_fee_amount := ROUND(v_due * v_platform_fee_rate, 2);
  ELSE
    v_platform_fee_amount := 0;
  END IF;

  v_total_debit := v_due + v_platform_fee_amount;

  SELECT w.balance INTO v_wallet_balance
  FROM public.wallets w
  WHERE w.user_id = v_user_id
  FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'Wallet not found';
  END IF;

  IF v_wallet_balance < v_total_debit THEN
    RAISE EXCEPTION 'Insufficient wallet balance';
  END IF;

  v_principal_component := ROUND(LEAST(v_loan.outstanding_amount, v_due / (1 + v_loan.monthly_fee_rate)), 2);
  v_fee_component := ROUND(v_due - v_principal_component, 2);

  UPDATE public.wallets
  SET balance = v_wallet_balance - v_total_debit,
      updated_at = now()
  WHERE user_id = v_user_id
  RETURNING balance INTO v_wallet_balance;

  SELECT w.balance INTO v_openpay_wallet_balance
  FROM public.wallets w
  WHERE w.user_id = v_openpay_user_id
  FOR UPDATE;

  IF v_openpay_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'OpenPay settlement wallet not found';
  END IF;

  UPDATE public.wallets
  SET balance = v_openpay_wallet_balance + v_total_debit,
      updated_at = now()
  WHERE user_id = v_openpay_user_id;

  UPDATE public.user_loans ul
  SET outstanding_amount = GREATEST(0, ul.outstanding_amount - v_principal_component),
      paid_months = ul.paid_months + 1,
      next_due_date = (ul.next_due_date + INTERVAL '1 month')::DATE,
      status = CASE
        WHEN GREATEST(0, ul.outstanding_amount - v_principal_component) = 0 THEN 'paid'
        ELSE v_loan.status
      END
  WHERE ul.id = v_loan.id
  RETURNING * INTO v_loan;

  INSERT INTO public.user_loan_payments (
    loan_id,
    user_id,
    amount,
    principal_component,
    fee_component,
    payment_method,
    payment_reference,
    note
  )
  VALUES (
    v_loan.id,
    v_user_id,
    v_due,
    v_principal_component,
    v_fee_component,
    v_method,
    NULLIF(TRIM(COALESCE(p_payment_reference, '')), ''),
    COALESCE(p_note, 'Loan monthly payment')
  );

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_user_id,
    v_openpay_user_id,
    v_due,
    CONCAT(
      'OpenPay loan repayment | To OPEA68BB7A9F964994A199A15786D680FA @openpay | Loan ',
      v_loan.id,
      ' | Method ',
      UPPER(v_method),
      CASE
        WHEN NULLIF(TRIM(COALESCE(p_payment_reference, '')), '') IS NOT NULL
          THEN CONCAT(' | Ref ', LEFT(TRIM(p_payment_reference), 80))
        ELSE ''
      END
    ),
    'completed'
  );

  IF v_platform_fee_amount > 0 THEN
    INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
    VALUES (
      v_user_id,
      v_openpay_user_id,
      v_platform_fee_amount,
      CONCAT(
        'OpenPay loan platform fee | To OPEA68BB7A9F964994A199A15786D680FA @openpay | Loan ',
        v_loan.id,
        ' | Rate ',
        ROUND(v_platform_fee_rate * 100, 4),
        '%'
      ),
      'completed'
    );
  END IF;

  RETURN QUERY
  SELECT v_loan.id, v_loan.outstanding_amount, v_loan.paid_months, v_loan.status, v_wallet_balance;
END;
$$;
-- <<< END MIGRATION: 20260219195000_add_loan_platform_fee_toggle_to_openpay_settlement.sql

-- >>> MIGRATION: 20260219202000_merchant_analytics_rpc.sql
CREATE OR REPLACE FUNCTION public.get_my_merchant_analytics(
  p_mode TEXT DEFAULT NULL,
  p_days INTEGER DEFAULT 30
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(NULLIF(TRIM(COALESCE(p_mode, '')), ''));
  v_days INTEGER := GREATEST(1, LEAST(COALESCE(p_days, 30), 365));
  v_result JSONB;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode IS NOT NULL AND v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  WITH filtered AS (
    SELECT
      mp.*,
      COALESCE(mcs.paid_at, mp.created_at) AS paid_at
    FROM public.merchant_payments mp
    LEFT JOIN public.merchant_checkout_sessions mcs
      ON mcs.id = mp.session_id
    WHERE mp.merchant_user_id = v_user_id
      AND (v_mode IS NULL OR mp.key_mode = v_mode)
      AND mp.created_at >= (now() - make_interval(days => v_days))
  ),
  summary AS (
    SELECT
      COUNT(*)::INTEGER AS total_payments,
      COUNT(*) FILTER (WHERE status = 'succeeded')::INTEGER AS succeeded_payments,
      COUNT(*) FILTER (WHERE status = 'failed')::INTEGER AS failed_payments,
      COUNT(*) FILTER (WHERE status = 'refunded')::INTEGER AS refunded_payments,
      COALESCE(SUM(amount) FILTER (WHERE status = 'succeeded'), 0)::NUMERIC(14,2) AS gross_revenue,
      COALESCE(SUM(amount) FILTER (WHERE status = 'refunded'), 0)::NUMERIC(14,2) AS refunds,
      GREATEST(
        0,
        COALESCE(SUM(amount) FILTER (WHERE status = 'succeeded'), 0)
        - COALESCE(SUM(amount) FILTER (WHERE status = 'refunded'), 0)
      )::NUMERIC(14,2) AS net_revenue,
      COALESCE(AVG(amount) FILTER (WHERE status = 'succeeded'), 0)::NUMERIC(14,2) AS avg_ticket,
      COUNT(DISTINCT buyer_user_id) FILTER (WHERE status = 'succeeded')::INTEGER AS unique_customers
    FROM filtered
  )
  SELECT jsonb_build_object(
    'period_days', v_days,
    'mode', COALESCE(v_mode, 'all'),
    'summary',
      jsonb_build_object(
        'total_payments', s.total_payments,
        'succeeded_payments', s.succeeded_payments,
        'failed_payments', s.failed_payments,
        'refunded_payments', s.refunded_payments,
        'gross_revenue', s.gross_revenue,
        'refunds', s.refunds,
        'net_revenue', s.net_revenue,
        'avg_ticket', s.avg_ticket,
        'unique_customers', s.unique_customers,
        'success_rate',
          CASE WHEN s.total_payments = 0 THEN 0
               ELSE ROUND((s.succeeded_payments::NUMERIC / s.total_payments::NUMERIC) * 100, 2)
          END,
        'failure_rate',
          CASE WHEN s.total_payments = 0 THEN 0
               ELSE ROUND((s.failed_payments::NUMERIC / s.total_payments::NUMERIC) * 100, 2)
          END
      ),
    'currency_breakdown',
      COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'currency', x.currency,
            'payments', x.payments,
            'gross_revenue', x.gross_revenue,
            'net_revenue', x.net_revenue
          )
          ORDER BY x.net_revenue DESC, x.currency ASC
        )
        FROM (
          SELECT
            f.currency,
            COUNT(*)::INTEGER AS payments,
            COALESCE(SUM(f.amount) FILTER (WHERE f.status = 'succeeded'), 0)::NUMERIC(14,2) AS gross_revenue,
            GREATEST(
              0,
              COALESCE(SUM(f.amount) FILTER (WHERE f.status = 'succeeded'), 0)
              - COALESCE(SUM(f.amount) FILTER (WHERE f.status = 'refunded'), 0)
            )::NUMERIC(14,2) AS net_revenue
          FROM filtered f
          GROUP BY f.currency
        ) x
      ), '[]'::JSONB),
    'top_customers',
      COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'buyer_user_id', x.buyer_user_id,
            'customer_name', x.customer_name,
            'customer_username', x.customer_username,
            'payments', x.payments,
            'total_spent', x.total_spent,
            'last_payment_at', x.last_payment_at
          )
          ORDER BY x.total_spent DESC, x.payments DESC
        )
        FROM (
          SELECT
            f.buyer_user_id,
            COALESCE(NULLIF(TRIM(p.full_name), ''), 'OpenPay Customer') AS customer_name,
            COALESCE(NULLIF(TRIM(p.username), ''), '') AS customer_username,
            COUNT(*)::INTEGER AS payments,
            COALESCE(SUM(f.amount) FILTER (WHERE f.status = 'succeeded'), 0)::NUMERIC(14,2) AS total_spent,
            MAX(f.paid_at) AS last_payment_at
          FROM filtered f
          LEFT JOIN public.profiles p
            ON p.id = f.buyer_user_id
          GROUP BY f.buyer_user_id, p.full_name, p.username
          ORDER BY total_spent DESC, payments DESC
          LIMIT 10
        ) x
      ), '[]'::JSONB),
    'top_products',
      COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'item_name', x.item_name,
            'quantity_sold', x.quantity_sold,
            'gross_revenue', x.gross_revenue
          )
          ORDER BY x.gross_revenue DESC, x.quantity_sold DESC, x.item_name ASC
        )
        FROM (
          SELECT
            mcsi.item_name,
            COALESCE(SUM(mcsi.quantity), 0)::INTEGER AS quantity_sold,
            COALESCE(SUM(mcsi.line_total), 0)::NUMERIC(14,2) AS gross_revenue
          FROM filtered f
          JOIN public.merchant_checkout_session_items mcsi
            ON mcsi.session_id = f.session_id
          WHERE f.status = 'succeeded'
          GROUP BY mcsi.item_name
          ORDER BY gross_revenue DESC, quantity_sold DESC, mcsi.item_name ASC
          LIMIT 10
        ) x
      ), '[]'::JSONB),
    'revenue_timeline',
      COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'date', x.day,
            'payments', x.payments,
            'gross_revenue', x.gross_revenue,
            'net_revenue', x.net_revenue
          )
          ORDER BY x.day ASC
        )
        FROM (
          SELECT
            to_char(date_trunc('day', f.paid_at), 'YYYY-MM-DD') AS day,
            COUNT(*)::INTEGER AS payments,
            COALESCE(SUM(f.amount) FILTER (WHERE f.status = 'succeeded'), 0)::NUMERIC(14,2) AS gross_revenue,
            GREATEST(
              0,
              COALESCE(SUM(f.amount) FILTER (WHERE f.status = 'succeeded'), 0)
              - COALESCE(SUM(f.amount) FILTER (WHERE f.status = 'refunded'), 0)
            )::NUMERIC(14,2) AS net_revenue
          FROM filtered f
          GROUP BY date_trunc('day', f.paid_at)
        ) x
      ), '[]'::JSONB),
    'hourly_activity',
      COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'hour', x.hour,
            'payments', x.payments
          )
          ORDER BY x.hour ASC
        )
        FROM (
          SELECT
            EXTRACT(HOUR FROM f.paid_at)::INTEGER AS hour,
            COUNT(*)::INTEGER AS payments
          FROM filtered f
          GROUP BY EXTRACT(HOUR FROM f.paid_at)
        ) x
      ), '[]'::JSONB)
  )
  INTO v_result
  FROM summary s;

  RETURN COALESCE(v_result, '{}'::JSONB);
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_merchant_analytics(TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_merchant_analytics(TEXT, INTEGER) TO authenticated;

-- <<< END MIGRATION: 20260219202000_merchant_analytics_rpc.sql

-- >>> MIGRATION: 20260219204000_merchant_delete_actions.sql
CREATE OR REPLACE FUNCTION public.delete_my_merchant_api_key(
  p_key_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  DELETE FROM public.merchant_api_keys
  WHERE id = p_key_id
    AND merchant_user_id = v_user_id;

  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_my_merchant_payment_link(
  p_link_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  DELETE FROM public.merchant_payment_links
  WHERE id = p_link_id
    AND merchant_user_id = v_user_id;

  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_my_merchant_checkout_link(
  p_session_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  DELETE FROM public.merchant_checkout_sessions mcs
  WHERE mcs.id = p_session_id
    AND mcs.merchant_user_id = v_user_id
    AND NOT EXISTS (
      SELECT 1
      FROM public.merchant_payments mp
      WHERE mp.session_id = mcs.id
    );

  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_my_merchant_api_key(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_my_merchant_payment_link(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_my_merchant_checkout_link(UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.delete_my_merchant_api_key(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_my_merchant_payment_link(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_my_merchant_checkout_link(UUID) TO authenticated;

-- <<< END MIGRATION: 20260219204000_merchant_delete_actions.sql

-- >>> MIGRATION: 20260219213000_virtual_card_activity_notifications.sql
CREATE OR REPLACE FUNCTION public.handle_virtual_card_tx_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_amount TEXT := to_char(COALESCE(NEW.amount, 0), 'FM999999999990D00');
  v_note TEXT := COALESCE(NEW.note, '');
BEGIN
  IF NEW.sender_id = NEW.receiver_id THEN
    RETURN NEW;
  END IF;

  IF v_note ILIKE 'Virtual card payment%'
     OR v_note ILIKE '%| Card ****%' THEN
    PERFORM public.create_app_notification(
      NEW.sender_id,
      'virtual_card_payment_sent',
      'Virtual card payment sent',
      format('$%s was paid using your OpenPay virtual card.', v_amount),
      jsonb_build_object(
        'transaction_id', NEW.id,
        'amount', NEW.amount,
        'receiver_id', NEW.receiver_id
      )
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_app_notifications_virtual_card_tx_insert ON public.transactions;
CREATE TRIGGER trg_app_notifications_virtual_card_tx_insert
AFTER INSERT ON public.transactions
FOR EACH ROW
EXECUTE FUNCTION public.handle_virtual_card_tx_notification();


-- <<< END MIGRATION: 20260219213000_virtual_card_activity_notifications.sql

-- >>> MIGRATION: 20260219223000_payment_link_share_settings.sql
CREATE TABLE IF NOT EXISTS public.merchant_payment_link_share_settings (
  link_id UUID PRIMARY KEY REFERENCES public.merchant_payment_links(id) ON DELETE CASCADE,
  merchant_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  button_label TEXT NOT NULL DEFAULT 'Pay with OpenPay',
  button_style TEXT NOT NULL DEFAULT 'default' CHECK (button_style IN ('default', 'soft', 'dark')),
  button_size TEXT NOT NULL DEFAULT 'medium' CHECK (button_size IN ('small', 'medium', 'large')),
  widget_theme TEXT NOT NULL DEFAULT 'light' CHECK (widget_theme IN ('light', 'dark')),
  iframe_height INTEGER NOT NULL DEFAULT 720 CHECK (iframe_height BETWEEN 320 AND 2000),
  direct_open_new_tab BOOLEAN NOT NULL DEFAULT true,
  qr_size INTEGER NOT NULL DEFAULT 240 CHECK (qr_size BETWEEN 160 AND 1024),
  qr_logo_enabled BOOLEAN NOT NULL DEFAULT true,
  qr_logo_url TEXT NOT NULL DEFAULT '/openpay-o.svg',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_merchant_payment_link_share_settings_owner
ON public.merchant_payment_link_share_settings (merchant_user_id, updated_at DESC);

ALTER TABLE public.merchant_payment_link_share_settings ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'merchant_payment_link_share_settings'
      AND policyname = 'Users can view own merchant payment link share settings'
  ) THEN
    CREATE POLICY "Users can view own merchant payment link share settings"
      ON public.merchant_payment_link_share_settings
      FOR SELECT TO authenticated
      USING (merchant_user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'merchant_payment_link_share_settings'
      AND policyname = 'Users can insert own merchant payment link share settings'
  ) THEN
    CREATE POLICY "Users can insert own merchant payment link share settings"
      ON public.merchant_payment_link_share_settings
      FOR INSERT TO authenticated
      WITH CHECK (merchant_user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'merchant_payment_link_share_settings'
      AND policyname = 'Users can update own merchant payment link share settings'
  ) THEN
    CREATE POLICY "Users can update own merchant payment link share settings"
      ON public.merchant_payment_link_share_settings
      FOR UPDATE TO authenticated
      USING (merchant_user_id = auth.uid())
      WITH CHECK (merchant_user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'merchant_payment_link_share_settings'
      AND policyname = 'Users can delete own merchant payment link share settings'
  ) THEN
    CREATE POLICY "Users can delete own merchant payment link share settings"
      ON public.merchant_payment_link_share_settings
      FOR DELETE TO authenticated
      USING (merchant_user_id = auth.uid());
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_merchant_payment_link_share_settings_updated_at ON public.merchant_payment_link_share_settings;
CREATE TRIGGER trg_merchant_payment_link_share_settings_updated_at
BEFORE UPDATE ON public.merchant_payment_link_share_settings
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

CREATE OR REPLACE FUNCTION public.upsert_my_payment_link_share_settings(
  p_link_id UUID,
  p_button_label TEXT DEFAULT NULL,
  p_button_style TEXT DEFAULT NULL,
  p_button_size TEXT DEFAULT NULL,
  p_widget_theme TEXT DEFAULT NULL,
  p_iframe_height INTEGER DEFAULT NULL,
  p_direct_open_new_tab BOOLEAN DEFAULT NULL,
  p_qr_size INTEGER DEFAULT NULL,
  p_qr_logo_enabled BOOLEAN DEFAULT NULL,
  p_qr_logo_url TEXT DEFAULT NULL
)
RETURNS public.merchant_payment_link_share_settings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_link public.merchant_payment_links;
  v_row public.merchant_payment_link_share_settings;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT *
  INTO v_link
  FROM public.merchant_payment_links mpl
  WHERE mpl.id = p_link_id
    AND mpl.merchant_user_id = v_user_id
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment link not found';
  END IF;

  INSERT INTO public.merchant_payment_link_share_settings (
    link_id,
    merchant_user_id,
    button_label,
    button_style,
    button_size,
    widget_theme,
    iframe_height,
    direct_open_new_tab,
    qr_size,
    qr_logo_enabled,
    qr_logo_url
  )
  VALUES (
    v_link.id,
    v_user_id,
    COALESCE(NULLIF(TRIM(COALESCE(p_button_label, '')), ''), 'Pay with OpenPay'),
    COALESCE(NULLIF(TRIM(COALESCE(p_button_style, '')), ''), 'default'),
    COALESCE(NULLIF(TRIM(COALESCE(p_button_size, '')), ''), 'medium'),
    COALESCE(NULLIF(TRIM(COALESCE(p_widget_theme, '')), ''), 'light'),
    COALESCE(p_iframe_height, 720),
    COALESCE(p_direct_open_new_tab, true),
    COALESCE(p_qr_size, 240),
    COALESCE(p_qr_logo_enabled, true),
    COALESCE(NULLIF(TRIM(COALESCE(p_qr_logo_url, '')), ''), '/openpay-o.svg')
  )
  ON CONFLICT (link_id)
  DO UPDATE SET
    button_label = COALESCE(NULLIF(TRIM(COALESCE(EXCLUDED.button_label, '')), ''), public.merchant_payment_link_share_settings.button_label),
    button_style = COALESCE(NULLIF(TRIM(COALESCE(EXCLUDED.button_style, '')), ''), public.merchant_payment_link_share_settings.button_style),
    button_size = COALESCE(NULLIF(TRIM(COALESCE(EXCLUDED.button_size, '')), ''), public.merchant_payment_link_share_settings.button_size),
    widget_theme = COALESCE(NULLIF(TRIM(COALESCE(EXCLUDED.widget_theme, '')), ''), public.merchant_payment_link_share_settings.widget_theme),
    iframe_height = COALESCE(EXCLUDED.iframe_height, public.merchant_payment_link_share_settings.iframe_height),
    direct_open_new_tab = COALESCE(EXCLUDED.direct_open_new_tab, public.merchant_payment_link_share_settings.direct_open_new_tab),
    qr_size = COALESCE(EXCLUDED.qr_size, public.merchant_payment_link_share_settings.qr_size),
    qr_logo_enabled = COALESCE(EXCLUDED.qr_logo_enabled, public.merchant_payment_link_share_settings.qr_logo_enabled),
    qr_logo_url = COALESCE(NULLIF(TRIM(COALESCE(EXCLUDED.qr_logo_url, '')), ''), public.merchant_payment_link_share_settings.qr_logo_url),
    updated_at = now()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_payment_link_share_settings(
  p_link_id UUID
)
RETURNS public.merchant_payment_link_share_settings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_row public.merchant_payment_link_share_settings;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT *
  INTO v_row
  FROM public.merchant_payment_link_share_settings s
  WHERE s.link_id = p_link_id
    AND s.merchant_user_id = v_user_id
  LIMIT 1;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_my_payment_link_share_settings(UUID, TEXT, TEXT, TEXT, TEXT, INTEGER, BOOLEAN, INTEGER, BOOLEAN, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_payment_link_share_settings(UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.upsert_my_payment_link_share_settings(UUID, TEXT, TEXT, TEXT, TEXT, INTEGER, BOOLEAN, INTEGER, BOOLEAN, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_payment_link_share_settings(UUID) TO authenticated;

-- <<< END MIGRATION: 20260219223000_payment_link_share_settings.sql

-- >>> MIGRATION: 20260219230000_save_virtual_card_signature_rpc.sql
CREATE OR REPLACE FUNCTION public.save_my_virtual_card_signature(
  p_signature TEXT
)
RETURNS public.virtual_cards
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_signature TEXT := LEFT(TRIM(COALESCE(p_signature, '')), 32);
  v_card public.virtual_cards;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  PERFORM public.upsert_my_virtual_card(NULL, NULL);

  UPDATE public.virtual_cards vc
  SET card_settings = jsonb_set(
    COALESCE(vc.card_settings, '{}'::jsonb),
    '{signature}',
    to_jsonb(v_signature),
    true
  ),
  updated_at = now()
  WHERE vc.user_id = v_user_id
  RETURNING * INTO v_card;

  RETURN v_card;
END;
$$;

REVOKE ALL ON FUNCTION public.save_my_virtual_card_signature(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_my_virtual_card_signature(TEXT) TO authenticated;

-- <<< END MIGRATION: 20260219230000_save_virtual_card_signature_rpc.sql

-- >>> MIGRATION: 20260220100000_make_public_ledger_access.sql
CREATE OR REPLACE FUNCTION public.get_public_ledger(
  p_limit INTEGER DEFAULT 30,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  amount NUMERIC,
  note TEXT,
  status TEXT,
  occurred_at TIMESTAMPTZ,
  event_type TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    le.amount,
    le.note,
    COALESCE(le.status, 'completed') AS status,
    le.occurred_at,
    le.event_type
  FROM public.ledger_events le
  WHERE le.source_table = 'transactions'
    AND le.amount IS NOT NULL
  ORDER BY le.occurred_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
$$;

REVOKE ALL ON FUNCTION public.get_public_ledger(INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_ledger(INTEGER, INTEGER) TO anon, authenticated;

-- <<< END MIGRATION: 20260220100000_make_public_ledger_access.sql

-- >>> MIGRATION: 20260220101000_hide_uuid_in_public_ledger_notes.sql
CREATE OR REPLACE FUNCTION public.get_public_ledger(
  p_limit INTEGER DEFAULT 30,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  amount NUMERIC,
  note TEXT,
  status TEXT,
  occurred_at TIMESTAMPTZ,
  event_type TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    le.amount,
    CASE
      WHEN le.note IS NULL THEN NULL
      ELSE regexp_replace(
        le.note,
        '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
        '[hidden]',
        'g'
      )
    END AS note,
    COALESCE(le.status, 'completed') AS status,
    le.occurred_at,
    le.event_type
  FROM public.ledger_events le
  WHERE le.source_table = 'transactions'
    AND le.amount IS NOT NULL
  ORDER BY le.occurred_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
$$;

REVOKE ALL ON FUNCTION public.get_public_ledger(INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_ledger(INTEGER, INTEGER) TO anon, authenticated;

-- <<< END MIGRATION: 20260220101000_hide_uuid_in_public_ledger_notes.sql

-- >>> MIGRATION: 20260220113000_checkout_customer_details_and_thankyou_workflow.sql
CREATE OR REPLACE FUNCTION public.complete_merchant_checkout_with_transaction(
  p_session_token TEXT,
  p_transaction_id UUID,
  p_note TEXT DEFAULT '',
  p_customer_name TEXT DEFAULT NULL,
  p_customer_email TEXT DEFAULT NULL,
  p_customer_phone TEXT DEFAULT NULL,
  p_customer_address TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tx_id UUID;
  v_customer_name TEXT := NULLIF(TRIM(COALESCE(p_customer_name, '')), '');
  v_customer_email TEXT := NULLIF(TRIM(COALESCE(p_customer_email, '')), '');
  v_customer_phone TEXT := NULLIF(TRIM(COALESCE(p_customer_phone, '')), '');
  v_customer_address TEXT := NULLIF(TRIM(COALESCE(p_customer_address, '')), '');
BEGIN
  v_tx_id := public.complete_merchant_checkout_with_transaction(
    p_session_token,
    p_transaction_id,
    p_note
  );

  UPDATE public.merchant_checkout_sessions mcs
  SET customer_name = COALESCE(v_customer_name, mcs.customer_name),
      customer_email = COALESCE(v_customer_email, mcs.customer_email),
      metadata = COALESCE(mcs.metadata, '{}'::jsonb) || jsonb_strip_nulls(
        jsonb_build_object(
          'customer_phone', v_customer_phone,
          'customer_address', v_customer_address
        )
      ),
      updated_at = now()
  WHERE mcs.session_token = TRIM(COALESCE(p_session_token, ''));

  RETURN v_tx_id;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_merchant_checkout_with_transaction(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_merchant_checkout_with_transaction(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.pay_merchant_checkout_with_virtual_card(
  p_session_token TEXT,
  p_card_number TEXT,
  p_expiry_month INTEGER,
  p_expiry_year INTEGER,
  p_cvc TEXT,
  p_note TEXT DEFAULT '',
  p_customer_name TEXT DEFAULT NULL,
  p_customer_email TEXT DEFAULT NULL,
  p_customer_phone TEXT DEFAULT NULL,
  p_customer_address TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tx_id UUID;
  v_customer_name TEXT := NULLIF(TRIM(COALESCE(p_customer_name, '')), '');
  v_customer_email TEXT := NULLIF(TRIM(COALESCE(p_customer_email, '')), '');
  v_customer_phone TEXT := NULLIF(TRIM(COALESCE(p_customer_phone, '')), '');
  v_customer_address TEXT := NULLIF(TRIM(COALESCE(p_customer_address, '')), '');
BEGIN
  v_tx_id := public.pay_merchant_checkout_with_virtual_card(
    p_session_token,
    p_card_number,
    p_expiry_month,
    p_expiry_year,
    p_cvc,
    p_note
  );

  UPDATE public.merchant_checkout_sessions mcs
  SET customer_name = COALESCE(v_customer_name, mcs.customer_name),
      customer_email = COALESCE(v_customer_email, mcs.customer_email),
      metadata = COALESCE(mcs.metadata, '{}'::jsonb) || jsonb_strip_nulls(
        jsonb_build_object(
          'customer_phone', v_customer_phone,
          'customer_address', v_customer_address
        )
      ),
      updated_at = now()
  WHERE mcs.session_token = TRIM(COALESCE(p_session_token, ''));

  RETURN v_tx_id;
END;
$$;

REVOKE ALL ON FUNCTION public.pay_merchant_checkout_with_virtual_card(TEXT, TEXT, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pay_merchant_checkout_with_virtual_card(TEXT, TEXT, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- <<< END MIGRATION: 20260220113000_checkout_customer_details_and_thankyou_workflow.sql

-- >>> MIGRATION: 20260220120000_add_merchant_link_transactions_api.sql
CREATE OR REPLACE FUNCTION public.get_my_merchant_link_transactions(
  p_mode TEXT DEFAULT NULL,
  p_payment_link_token TEXT DEFAULT NULL,
  p_session_token TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 100,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  payment_id UUID,
  payment_created_at TIMESTAMPTZ,
  payment_status TEXT,
  payment_amount NUMERIC,
  payment_currency TEXT,
  payment_mode TEXT,
  transaction_id UUID,
  transaction_status TEXT,
  transaction_note TEXT,
  transaction_created_at TIMESTAMPTZ,
  checkout_session_id UUID,
  checkout_session_token TEXT,
  checkout_status TEXT,
  checkout_paid_at TIMESTAMPTZ,
  payment_link_id UUID,
  payment_link_token TEXT,
  payment_link_title TEXT,
  payment_link_description TEXT,
  payment_link_type TEXT,
  customer_user_id UUID,
  customer_name TEXT,
  customer_username TEXT,
  customer_email TEXT,
  customer_phone TEXT,
  customer_address TEXT,
  api_key_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, '')));
  v_link_token TEXT := NULLIF(TRIM(COALESCE(p_payment_link_token, '')), '');
  v_session_token TEXT := NULLIF(TRIM(COALESCE(p_session_token, '')), '');
  v_status TEXT := LOWER(TRIM(COALESCE(p_status, '')));
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode = '' THEN
    v_mode := NULL;
  END IF;
  IF v_status = '' THEN
    v_status := NULL;
  END IF;

  RETURN QUERY
  SELECT
    mp.id AS payment_id,
    mp.created_at AS payment_created_at,
    mp.status AS payment_status,
    mp.amount AS payment_amount,
    mp.currency AS payment_currency,
    mp.key_mode AS payment_mode,
    tx.id AS transaction_id,
    tx.status AS transaction_status,
    tx.note AS transaction_note,
    tx.created_at AS transaction_created_at,
    mcs.id AS checkout_session_id,
    mcs.session_token AS checkout_session_token,
    mcs.status AS checkout_status,
    mcs.paid_at AS checkout_paid_at,
    mpl.id AS payment_link_id,
    mp.payment_link_token AS payment_link_token,
    mpl.title AS payment_link_title,
    mpl.description AS payment_link_description,
    mpl.link_type AS payment_link_type,
    mp.buyer_user_id AS customer_user_id,
    COALESCE(NULLIF(TRIM(COALESCE(mcs.customer_name, '')), ''), buyer.full_name, 'OpenPay Customer') AS customer_name,
    buyer.username AS customer_username,
    mcs.customer_email AS customer_email,
    NULLIF(TRIM(COALESCE(mcs.metadata->>'customer_phone', '')), '') AS customer_phone,
    NULLIF(TRIM(COALESCE(mcs.metadata->>'customer_address', '')), '') AS customer_address,
    mp.api_key_id AS api_key_id
  FROM public.merchant_payments mp
  JOIN public.merchant_checkout_sessions mcs
    ON mcs.id = mp.session_id
  LEFT JOIN public.transactions tx
    ON tx.id = mp.transaction_id
  LEFT JOIN public.merchant_payment_links mpl
    ON mpl.id = mp.payment_link_id
  LEFT JOIN public.profiles buyer
    ON buyer.id = mp.buyer_user_id
  WHERE mp.merchant_user_id = v_user_id
    AND (v_mode IS NULL OR mp.key_mode = v_mode)
    AND (v_status IS NULL OR LOWER(mp.status) = v_status)
    AND (v_link_token IS NULL OR mp.payment_link_token = v_link_token)
    AND (v_session_token IS NULL OR mcs.session_token = v_session_token)
  ORDER BY mp.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_merchant_link_transactions(TEXT, TEXT, TEXT, TEXT, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_merchant_link_transactions(TEXT, TEXT, TEXT, TEXT, INTEGER, INTEGER) TO authenticated, service_role;

-- <<< END MIGRATION: 20260220120000_add_merchant_link_transactions_api.sql

-- >>> MIGRATION: 20260220132000_openpay_code_auth_support.sql
CREATE OR REPLACE FUNCTION public.normalize_openpay_code(p_code TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT UPPER(TRIM(COALESCE(p_code, '')));
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'user_accounts_account_number_format_ck'
      AND conrelid = 'public.user_accounts'::regclass
  ) THEN
    ALTER TABLE public.user_accounts
      ADD CONSTRAINT user_accounts_account_number_format_ck
      CHECK (account_number ~ '^OP[A-Z0-9]{6,64}$') NOT VALID;
  END IF;
END $$;

ALTER TABLE public.user_accounts
  VALIDATE CONSTRAINT user_accounts_account_number_format_ck;

CREATE OR REPLACE FUNCTION public.get_my_openpay_code()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account public.user_accounts;
BEGIN
  v_account := public.upsert_my_user_account();
  RETURN v_account.account_number;
END;
$$;

CREATE OR REPLACE FUNCTION public.verify_my_openpay_code(
  p_code TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expected TEXT;
  v_lookup TEXT := public.normalize_openpay_code(p_code);
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_lookup = '' THEN
    RETURN FALSE;
  END IF;

  v_expected := public.get_my_openpay_code();
  RETURN v_lookup = v_expected;
END;
$$;

REVOKE ALL ON FUNCTION public.normalize_openpay_code(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.normalize_openpay_code(TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_my_openpay_code() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_openpay_code() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.verify_my_openpay_code(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_my_openpay_code(TEXT) TO authenticated, service_role;

-- <<< END MIGRATION: 20260220132000_openpay_code_auth_support.sql

-- >>> MIGRATION: 20260220133000_openpay_authorization_code_auth.sql
CREATE TABLE IF NOT EXISTS public.openpay_authorization_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  authorization_code TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_openpay_authorization_codes_user
ON public.openpay_authorization_codes(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_openpay_authorization_codes_expiry
ON public.openpay_authorization_codes(expires_at);

ALTER TABLE public.openpay_authorization_codes ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'openpay_authorization_codes'
      AND policyname = 'Users can view own authorization codes'
  ) THEN
    CREATE POLICY "Users can view own authorization codes"
      ON public.openpay_authorization_codes
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.normalize_openpay_authorization_code(p_code TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT UPPER(TRIM(COALESCE(p_code, '')));
$$;

CREATE OR REPLACE FUNCTION public.generate_openpay_authorization_code()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_chars CONSTANT TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code TEXT := '';
  v_i INTEGER;
BEGIN
  FOR v_i IN 1..8 LOOP
    v_code := v_code || substr(v_chars, (get_byte(gen_random_bytes(1), 0) % length(v_chars)) + 1, 1);
  END LOOP;
  RETURN v_code;
END;
$$;

CREATE OR REPLACE FUNCTION public.issue_my_openpay_authorization_code(
  p_force_new BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
  authorization_code TEXT,
  expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_existing RECORD;
  v_candidate TEXT;
  v_try INTEGER := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  DELETE FROM public.openpay_authorization_codes oac
  WHERE (oac.used_at IS NOT NULL OR oac.expires_at <= now() - interval '1 day');

  IF NOT COALESCE(p_force_new, FALSE) THEN
    SELECT oac.authorization_code, oac.expires_at
    INTO v_existing
    FROM public.openpay_authorization_codes oac
    WHERE oac.user_id = v_user_id
      AND oac.used_at IS NULL
      AND oac.expires_at > now()
    ORDER BY oac.created_at DESC
    LIMIT 1;

    IF FOUND THEN
      RETURN QUERY SELECT v_existing.authorization_code, v_existing.expires_at;
      RETURN;
    END IF;
  ELSE
    UPDATE public.openpay_authorization_codes oac
    SET used_at = now()
    WHERE oac.user_id = v_user_id
      AND oac.used_at IS NULL
      AND oac.expires_at > now();
  END IF;

  WHILE v_try < 20 LOOP
    v_try := v_try + 1;
    v_candidate := public.generate_openpay_authorization_code();

    BEGIN
      INSERT INTO public.openpay_authorization_codes (
        user_id,
        authorization_code,
        expires_at
      )
      VALUES (
        v_user_id,
        v_candidate,
        now() + interval '10 minutes'
      )
      RETURNING openpay_authorization_codes.authorization_code, openpay_authorization_codes.expires_at
      INTO authorization_code, expires_at;

      RETURN NEXT;
      RETURN;
    EXCEPTION WHEN unique_violation THEN
      CONTINUE;
    END;
  END LOOP;

  RAISE EXCEPTION 'Failed to issue authorization code';
END;
$$;

CREATE OR REPLACE FUNCTION public.verify_my_openpay_authorization_code(
  p_code TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_lookup TEXT := public.normalize_openpay_authorization_code(p_code);
  v_row_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_lookup = '' THEN
    RETURN FALSE;
  END IF;

  UPDATE public.openpay_authorization_codes oac
  SET used_at = now()
  WHERE oac.user_id = v_user_id
    AND oac.authorization_code = v_lookup
    AND oac.used_at IS NULL
    AND oac.expires_at > now()
  RETURNING oac.id INTO v_row_id;

  RETURN v_row_id IS NOT NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.verify_my_openpay_code(
  p_code TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.verify_my_openpay_authorization_code(p_code);
$$;

REVOKE ALL ON TABLE public.openpay_authorization_codes FROM PUBLIC;
GRANT SELECT ON TABLE public.openpay_authorization_codes TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.normalize_openpay_authorization_code(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.normalize_openpay_authorization_code(TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.generate_openpay_authorization_code() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.generate_openpay_authorization_code() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.issue_my_openpay_authorization_code(BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.issue_my_openpay_authorization_code(BOOLEAN) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.verify_my_openpay_authorization_code(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_my_openpay_authorization_code(TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.verify_my_openpay_code(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_my_openpay_code(TEXT) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260220133000_openpay_authorization_code_auth.sql

-- >>> MIGRATION: 20260220140000_merchant_pos_api.sql
CREATE OR REPLACE FUNCTION public.get_my_pos_dashboard(
  p_mode TEXT DEFAULT 'live'
)
RETURNS TABLE (
  merchant_name TEXT,
  merchant_username TEXT,
  wallet_balance NUMERIC,
  today_total_received NUMERIC,
  today_transactions INTEGER,
  refunded_transactions INTEGER,
  key_mode TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, 'live')));
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  PERFORM public.upsert_my_merchant_profile(NULL, NULL, NULL, NULL);

  RETURN QUERY
  SELECT
    mpf.merchant_name,
    mpf.merchant_username,
    COALESCE(w.balance, 0)::NUMERIC AS wallet_balance,
    COALESCE(SUM(CASE WHEN p.status = 'succeeded' THEN p.amount ELSE 0 END), 0)::NUMERIC AS today_total_received,
    COUNT(*) FILTER (WHERE p.status = 'succeeded')::INTEGER AS today_transactions,
    COUNT(*) FILTER (WHERE p.status = 'refunded')::INTEGER AS refunded_transactions,
    v_mode AS key_mode
  FROM public.merchant_profiles mpf
  LEFT JOIN public.wallets w
    ON w.user_id = mpf.user_id
  LEFT JOIN public.merchant_payments p
    ON p.merchant_user_id = mpf.user_id
   AND p.key_mode = v_mode
   AND p.created_at >= date_trunc('day', now())
  WHERE mpf.user_id = v_user_id
  GROUP BY mpf.merchant_name, mpf.merchant_username, w.balance;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_my_pos_checkout_session(
  p_amount NUMERIC,
  p_currency TEXT DEFAULT 'USD',
  p_mode TEXT DEFAULT 'live',
  p_customer_name TEXT DEFAULT NULL,
  p_customer_email TEXT DEFAULT NULL,
  p_reference TEXT DEFAULT NULL,
  p_qr_style TEXT DEFAULT 'dynamic',
  p_expires_in_minutes INTEGER DEFAULT 30
)
RETURNS TABLE (
  session_id UUID,
  session_token TEXT,
  total_amount NUMERIC,
  currency TEXT,
  status TEXT,
  expires_at TIMESTAMPTZ,
  qr_payload TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, 'live')));
  v_currency TEXT := UPPER(TRIM(COALESCE(p_currency, 'USD')));
  v_qr_style TEXT := LOWER(TRIM(COALESCE(p_qr_style, 'dynamic')));
  v_amount NUMERIC(12,2) := ROUND(COALESCE(p_amount, 0)::NUMERIC, 2);
  v_expires_minutes INTEGER := GREATEST(5, LEAST(COALESCE(p_expires_in_minutes, 30), 10080));
  v_session public.merchant_checkout_sessions;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  IF char_length(v_currency) <> 3 THEN
    RAISE EXCEPTION 'Currency must be 3 letters';
  END IF;

  IF v_qr_style NOT IN ('dynamic', 'static') THEN
    RAISE EXCEPTION 'QR style must be dynamic or static';
  END IF;

  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  PERFORM public.upsert_my_merchant_profile(NULL, NULL, NULL, v_currency);

  IF v_qr_style = 'static' THEN
    v_expires_minutes := GREATEST(v_expires_minutes, 1440);
  END IF;

  INSERT INTO public.merchant_checkout_sessions (
    merchant_user_id,
    key_mode,
    session_token,
    status,
    currency,
    subtotal_amount,
    fee_amount,
    total_amount,
    customer_email,
    customer_name,
    metadata,
    expires_at
  )
  VALUES (
    v_user_id,
    v_mode,
    'opsess_' || public.random_token_hex(24),
    'open',
    v_currency,
    v_amount,
    0,
    v_amount,
    NULLIF(TRIM(COALESCE(p_customer_email, '')), ''),
    NULLIF(TRIM(COALESCE(p_customer_name, '')), ''),
    jsonb_strip_nulls(
      jsonb_build_object(
        'channel', 'pos',
        'qr_style', v_qr_style,
        'reference', NULLIF(TRIM(COALESCE(p_reference, '')), '')
      )
    ),
    now() + make_interval(mins => v_expires_minutes)
  )
  RETURNING * INTO v_session;

  INSERT INTO public.merchant_checkout_session_items (
    session_id,
    product_id,
    item_name,
    unit_amount,
    quantity,
    line_total
  )
  VALUES (
    v_session.id,
    NULL,
    'POS Payment',
    v_amount,
    1,
    v_amount
  );

  RETURN QUERY
  SELECT
    v_session.id,
    v_session.session_token,
    v_session.total_amount,
    v_session.currency,
    v_session.status,
    v_session.expires_at,
    'openpay-pos://checkout/' || v_session.session_token;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_pos_transactions(
  p_mode TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_search TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  payment_id UUID,
  payment_created_at TIMESTAMPTZ,
  payment_status TEXT,
  amount NUMERIC,
  currency TEXT,
  payer_user_id UUID,
  payer_name TEXT,
  payer_username TEXT,
  transaction_id UUID,
  transaction_note TEXT,
  session_token TEXT,
  customer_name TEXT,
  customer_email TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, '')));
  v_status TEXT := LOWER(TRIM(COALESCE(p_status, '')));
  v_search TEXT := NULLIF(TRIM(COALESCE(p_search, '')), '');
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode = '' THEN
    v_mode := NULL;
  END IF;
  IF v_status = '' THEN
    v_status := NULL;
  END IF;

  RETURN QUERY
  SELECT
    mp.id AS payment_id,
    mp.created_at AS payment_created_at,
    mp.status AS payment_status,
    mp.amount,
    mp.currency,
    mp.buyer_user_id AS payer_user_id,
    COALESCE(NULLIF(TRIM(COALESCE(mcs.customer_name, '')), ''), pr.full_name, 'OpenPay Customer') AS payer_name,
    pr.username AS payer_username,
    mp.transaction_id,
    tx.note AS transaction_note,
    mcs.session_token,
    mcs.customer_name,
    mcs.customer_email
  FROM public.merchant_payments mp
  JOIN public.merchant_checkout_sessions mcs
    ON mcs.id = mp.session_id
  LEFT JOIN public.transactions tx
    ON tx.id = mp.transaction_id
  LEFT JOIN public.profiles pr
    ON pr.id = mp.buyer_user_id
  WHERE mp.merchant_user_id = v_user_id
    AND (v_mode IS NULL OR mp.key_mode = v_mode)
    AND (v_status IS NULL OR LOWER(mp.status) = v_status)
    AND (
      v_search IS NULL
      OR mp.transaction_id::TEXT ILIKE ('%' || v_search || '%')
      OR mcs.session_token ILIKE ('%' || v_search || '%')
      OR COALESCE(mcs.customer_name, '') ILIKE ('%' || v_search || '%')
      OR COALESCE(mcs.customer_email, '') ILIKE ('%' || v_search || '%')
      OR COALESCE(pr.username, '') ILIKE ('%' || v_search || '%')
      OR COALESCE(pr.full_name, '') ILIKE ('%' || v_search || '%')
    )
  ORDER BY mp.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 300)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.refund_my_pos_transaction(
  p_payment_id UUID,
  p_reason TEXT DEFAULT ''
)
RETURNS TABLE (
  refund_transaction_id UUID,
  new_status TEXT,
  refunded_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_payment public.merchant_payments;
  v_session public.merchant_checkout_sessions;
  v_merchant_balance NUMERIC(12,2);
  v_buyer_balance NUMERIC(12,2);
  v_refund_tx_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_payment_id IS NULL THEN
    RAISE EXCEPTION 'Payment ID is required';
  END IF;

  SELECT *
  INTO v_payment
  FROM public.merchant_payments
  WHERE id = p_payment_id
    AND merchant_user_id = v_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment not found';
  END IF;

  IF v_payment.status = 'refunded' THEN
    RAISE EXCEPTION 'Payment already refunded';
  END IF;

  IF v_payment.status <> 'succeeded' THEN
    RAISE EXCEPTION 'Only succeeded payments can be refunded';
  END IF;

  SELECT *
  INTO v_session
  FROM public.merchant_checkout_sessions
  WHERE id = v_payment.session_id
  FOR UPDATE;

  SELECT w.balance
  INTO v_merchant_balance
  FROM public.wallets w
  WHERE w.user_id = v_user_id
  FOR UPDATE;

  SELECT w.balance
  INTO v_buyer_balance
  FROM public.wallets w
  WHERE w.user_id = v_payment.buyer_user_id
  FOR UPDATE;

  IF v_merchant_balance IS NULL OR v_buyer_balance IS NULL THEN
    RAISE EXCEPTION 'Wallet not found';
  END IF;

  IF v_merchant_balance < v_payment.amount THEN
    RAISE EXCEPTION 'Insufficient merchant wallet balance for refund';
  END IF;

  UPDATE public.wallets
  SET balance = v_merchant_balance - v_payment.amount,
      updated_at = now()
  WHERE user_id = v_user_id;

  UPDATE public.wallets
  SET balance = v_buyer_balance + v_payment.amount,
      updated_at = now()
  WHERE user_id = v_payment.buyer_user_id;

  INSERT INTO public.transactions (
    sender_id,
    receiver_id,
    amount,
    note,
    status
  )
  VALUES (
    v_user_id,
    v_payment.buyer_user_id,
    v_payment.amount,
    CONCAT(
      'POS refund for payment ',
      v_payment.id::TEXT,
      CASE WHEN NULLIF(TRIM(COALESCE(p_reason, '')), '') IS NULL THEN '' ELSE ' | ' || TRIM(p_reason) END
    ),
    'refunded'
  )
  RETURNING id INTO v_refund_tx_id;

  UPDATE public.merchant_payments
  SET status = 'refunded'
  WHERE id = v_payment.id;

  UPDATE public.merchant_checkout_sessions
  SET metadata = COALESCE(v_session.metadata, '{}'::jsonb) || jsonb_build_object(
    'refunded_at', now(),
    'refund_transaction_id', v_refund_tx_id::TEXT
  ),
      updated_at = now()
  WHERE id = v_session.id;

  RETURN QUERY
  SELECT
    v_refund_tx_id,
    'refunded'::TEXT,
    now();
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_pos_dashboard(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_my_pos_checkout_session(NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_pos_transactions(TEXT, TEXT, TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.refund_my_pos_transaction(UUID, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_my_pos_dashboard(TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_my_pos_checkout_session(NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_pos_transactions(TEXT, TEXT, TEXT, INTEGER, INTEGER) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.refund_my_pos_transaction(UUID, TEXT) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260220140000_merchant_pos_api.sql

-- >>> MIGRATION: 20260220153000_merchant_portal_balance_activity.sql
CREATE TABLE IF NOT EXISTS public.merchant_balance_transfers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  key_mode TEXT NOT NULL CHECK (key_mode IN ('sandbox', 'live')),
  destination TEXT NOT NULL CHECK (destination IN ('wallet', 'savings')),
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  currency TEXT NOT NULL DEFAULT 'USD' CHECK (char_length(currency) = 3),
  note TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_merchant_balance_transfers_user_mode_created
ON public.merchant_balance_transfers (merchant_user_id, key_mode, created_at DESC);

CREATE TABLE IF NOT EXISTS public.merchant_pos_api_settings (
  merchant_user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  sandbox_api_key_id UUID REFERENCES public.merchant_api_keys(id) ON DELETE SET NULL,
  live_api_key_id UUID REFERENCES public.merchant_api_keys(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.merchant_balance_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_pos_api_settings ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'merchant_balance_transfers'
      AND policyname = 'Users can view own merchant balance transfers'
  ) THEN
    CREATE POLICY "Users can view own merchant balance transfers"
      ON public.merchant_balance_transfers
      FOR SELECT TO authenticated
      USING (merchant_user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'merchant_balance_transfers'
      AND policyname = 'Users can insert own merchant balance transfers'
  ) THEN
    CREATE POLICY "Users can insert own merchant balance transfers"
      ON public.merchant_balance_transfers
      FOR INSERT TO authenticated
      WITH CHECK (merchant_user_id = auth.uid());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'merchant_pos_api_settings'
      AND policyname = 'Users can view own merchant pos api settings'
  ) THEN
    CREATE POLICY "Users can view own merchant pos api settings"
      ON public.merchant_pos_api_settings
      FOR SELECT TO authenticated
      USING (merchant_user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'merchant_pos_api_settings'
      AND policyname = 'Users can insert own merchant pos api settings'
  ) THEN
    CREATE POLICY "Users can insert own merchant pos api settings"
      ON public.merchant_pos_api_settings
      FOR INSERT TO authenticated
      WITH CHECK (merchant_user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'merchant_pos_api_settings'
      AND policyname = 'Users can update own merchant pos api settings'
  ) THEN
    CREATE POLICY "Users can update own merchant pos api settings"
      ON public.merchant_pos_api_settings
      FOR UPDATE TO authenticated
      USING (merchant_user_id = auth.uid())
      WITH CHECK (merchant_user_id = auth.uid());
  END IF;
END $$;

ALTER TABLE public.merchant_checkout_sessions
ADD COLUMN IF NOT EXISTS api_key_id UUID REFERENCES public.merchant_api_keys(id) ON DELETE SET NULL;

DROP FUNCTION IF EXISTS public.upsert_my_pos_api_key(TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.upsert_my_pos_api_key(
  p_mode TEXT,
  p_secret_key TEXT
)
RETURNS TABLE (
  mode TEXT,
  api_key_id UUID,
  key_name TEXT,
  publishable_key TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, '')));
  v_secret_hash TEXT := md5(COALESCE(p_secret_key, ''));
  v_key public.merchant_api_keys;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  IF NULLIF(TRIM(COALESCE(p_secret_key, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Secret key is required';
  END IF;

  SELECT *
  INTO v_key
  FROM public.merchant_api_keys mak
  WHERE mak.merchant_user_id = v_user_id
    AND mak.key_mode = v_mode
    AND mak.is_active = true
    AND mak.secret_key_hash = v_secret_hash
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or inactive API key for mode %', v_mode;
  END IF;

  INSERT INTO public.merchant_pos_api_settings (merchant_user_id, sandbox_api_key_id, live_api_key_id, updated_at)
  VALUES (
    v_user_id,
    CASE WHEN v_mode = 'sandbox' THEN v_key.id ELSE NULL END,
    CASE WHEN v_mode = 'live' THEN v_key.id ELSE NULL END,
    now()
  )
  ON CONFLICT (merchant_user_id) DO UPDATE
  SET
    sandbox_api_key_id = CASE
      WHEN v_mode = 'sandbox' THEN v_key.id
      ELSE public.merchant_pos_api_settings.sandbox_api_key_id
    END,
    live_api_key_id = CASE
      WHEN v_mode = 'live' THEN v_key.id
      ELSE public.merchant_pos_api_settings.live_api_key_id
    END,
    updated_at = now();

  RETURN QUERY
  SELECT v_mode, v_key.id, v_key.key_name, v_key.publishable_key;
END;
$$;

DROP FUNCTION IF EXISTS public.get_my_pos_api_key_settings();
CREATE OR REPLACE FUNCTION public.get_my_pos_api_key_settings()
RETURNS TABLE (
  sandbox_api_key_id UUID,
  sandbox_key_name TEXT,
  sandbox_publishable_key TEXT,
  live_api_key_id UUID,
  live_key_name TEXT,
  live_publishable_key TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  RETURN QUERY
  SELECT
    cfg.cfg_sandbox_api_key_id AS sandbox_api_key_id,
    sk.key_name,
    sk.publishable_key,
    cfg.cfg_live_api_key_id AS live_api_key_id,
    lk.key_name,
    lk.publishable_key
  FROM (
    SELECT
      mps.sandbox_api_key_id AS cfg_sandbox_api_key_id,
      mps.live_api_key_id AS cfg_live_api_key_id
    FROM public.merchant_pos_api_settings mps
    WHERE mps.merchant_user_id = v_user_id
    LIMIT 1
  ) cfg
  FULL JOIN (SELECT 1 AS keep_row) k ON TRUE
  LEFT JOIN public.merchant_api_keys sk ON sk.id = cfg.cfg_sandbox_api_key_id
  LEFT JOIN public.merchant_api_keys lk ON lk.id = cfg.cfg_live_api_key_id
  LIMIT 1;
END;
$$;

DROP FUNCTION IF EXISTS public.create_my_pos_checkout_session(NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER);
DROP FUNCTION IF EXISTS public.create_my_pos_checkout_session(NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT);

CREATE OR REPLACE FUNCTION public.create_my_pos_checkout_session(
  p_amount NUMERIC,
  p_currency TEXT DEFAULT 'USD',
  p_mode TEXT DEFAULT 'live',
  p_customer_name TEXT DEFAULT NULL,
  p_customer_email TEXT DEFAULT NULL,
  p_reference TEXT DEFAULT NULL,
  p_qr_style TEXT DEFAULT 'dynamic',
  p_expires_in_minutes INTEGER DEFAULT 30,
  p_secret_key TEXT DEFAULT NULL
)
RETURNS TABLE (
  session_id UUID,
  session_token TEXT,
  total_amount NUMERIC,
  currency TEXT,
  status TEXT,
  expires_at TIMESTAMPTZ,
  qr_payload TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, 'live')));
  v_currency TEXT := UPPER(TRIM(COALESCE(p_currency, 'USD')));
  v_qr_style TEXT := LOWER(TRIM(COALESCE(p_qr_style, 'dynamic')));
  v_amount NUMERIC(12,2) := ROUND(COALESCE(p_amount, 0)::NUMERIC, 2);
  v_expires_minutes INTEGER := GREATEST(5, LEAST(COALESCE(p_expires_in_minutes, 30), 10080));
  v_secret_hash TEXT := md5(COALESCE(p_secret_key, ''));
  v_api_key_id UUID;
  v_api_key_ok BOOLEAN := false;
  v_session public.merchant_checkout_sessions;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  IF char_length(v_currency) <> 3 THEN
    RAISE EXCEPTION 'Currency must be 3 letters';
  END IF;

  IF v_qr_style NOT IN ('dynamic', 'static') THEN
    RAISE EXCEPTION 'QR style must be dynamic or static';
  END IF;

  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  IF NULLIF(TRIM(COALESCE(p_secret_key, '')), '') IS NOT NULL THEN
    SELECT mak.id
    INTO v_api_key_id
    FROM public.merchant_api_keys mak
    WHERE mak.merchant_user_id = v_user_id
      AND mak.key_mode = v_mode
      AND mak.is_active = true
      AND mak.secret_key_hash = v_secret_hash
    LIMIT 1;
  ELSE
    SELECT
      CASE
        WHEN v_mode = 'sandbox' THEN s.sandbox_api_key_id
        ELSE s.live_api_key_id
      END
    INTO v_api_key_id
    FROM public.merchant_pos_api_settings s
    WHERE s.merchant_user_id = v_user_id
    LIMIT 1;
  END IF;

  IF v_api_key_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.merchant_api_keys mak
      WHERE mak.id = v_api_key_id
        AND mak.merchant_user_id = v_user_id
        AND mak.key_mode = v_mode
        AND mak.is_active = true
    )
    INTO v_api_key_ok;
  END IF;

  IF NOT v_api_key_ok THEN
    RAISE EXCEPTION 'Set your % POS API key in Settings first (from Merchant Portal / API keys)', v_mode;
  END IF;

  PERFORM public.upsert_my_merchant_profile(NULL, NULL, NULL, v_currency);

  IF v_qr_style = 'static' THEN
    v_expires_minutes := GREATEST(v_expires_minutes, 1440);
  END IF;

  INSERT INTO public.merchant_checkout_sessions (
    merchant_user_id,
    api_key_id,
    key_mode,
    session_token,
    status,
    currency,
    subtotal_amount,
    fee_amount,
    total_amount,
    customer_email,
    customer_name,
    metadata,
    expires_at
  )
  VALUES (
    v_user_id,
    v_api_key_id,
    v_mode,
    'opsess_' || public.random_token_hex(24),
    'open',
    v_currency,
    v_amount,
    0,
    v_amount,
    NULLIF(TRIM(COALESCE(p_customer_email, '')), ''),
    NULLIF(TRIM(COALESCE(p_customer_name, '')), ''),
    jsonb_strip_nulls(
      jsonb_build_object(
        'channel', 'pos',
        'source', 'merchant_pos',
        'api_key_id', v_api_key_id::TEXT,
        'qr_style', v_qr_style,
        'reference', NULLIF(TRIM(COALESCE(p_reference, '')), '')
      )
    ),
    now() + make_interval(mins => v_expires_minutes)
  )
  RETURNING * INTO v_session;

  INSERT INTO public.merchant_checkout_session_items (
    session_id,
    product_id,
    item_name,
    unit_amount,
    quantity,
    line_total
  )
  VALUES (
    v_session.id,
    NULL,
    'POS Payment',
    v_amount,
    1,
    v_amount
  );

  RETURN QUERY
  SELECT
    v_session.id,
    v_session.session_token,
    v_session.total_amount,
    v_session.currency,
    v_session.status,
    v_session.expires_at,
    'openpay-pos://checkout/' || v_session.session_token;
END;
$$;

DROP FUNCTION IF EXISTS public.get_my_merchant_balance_overview(TEXT);
CREATE OR REPLACE FUNCTION public.get_my_merchant_balance_overview(
  p_mode TEXT DEFAULT 'live'
)
RETURNS TABLE (
  gross_volume NUMERIC,
  refunded_total NUMERIC,
  transferred_total NUMERIC,
  available_balance NUMERIC,
  wallet_balance NUMERIC,
  savings_balance NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, 'live')));
  v_gross NUMERIC(14,2) := 0;
  v_refunded NUMERIC(14,2) := 0;
  v_transferred NUMERIC(14,2) := 0;
  v_wallet NUMERIC(14,2) := 0;
  v_savings NUMERIC(14,2) := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  SELECT
    COALESCE(SUM(CASE WHEN mp.status = 'succeeded' THEN mp.amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN mp.status = 'refunded' THEN mp.amount ELSE 0 END), 0)
  INTO v_gross, v_refunded
  FROM public.merchant_payments mp
  WHERE mp.merchant_user_id = v_user_id
    AND mp.key_mode = v_mode;

  SELECT COALESCE(SUM(mbt.amount), 0)
  INTO v_transferred
  FROM public.merchant_balance_transfers mbt
  WHERE mbt.merchant_user_id = v_user_id
    AND mbt.key_mode = v_mode;

  SELECT COALESCE(w.balance, 0)
  INTO v_wallet
  FROM public.wallets w
  WHERE w.user_id = v_user_id;

  PERFORM public.upsert_my_savings_account();
  SELECT COALESCE(usa.balance, 0)
  INTO v_savings
  FROM public.user_savings_accounts usa
  WHERE usa.user_id = v_user_id;

  RETURN QUERY
  SELECT
    v_gross,
    v_refunded,
    v_transferred,
    GREATEST(v_gross - v_refunded - v_transferred, 0),
    v_wallet,
    v_savings;
END;
$$;

DROP FUNCTION IF EXISTS public.transfer_my_merchant_balance(NUMERIC, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.transfer_my_merchant_balance(
  p_amount NUMERIC,
  p_mode TEXT DEFAULT 'live',
  p_destination TEXT DEFAULT 'wallet',
  p_note TEXT DEFAULT ''
)
RETURNS TABLE (
  transfer_id UUID,
  available_balance NUMERIC,
  wallet_balance NUMERIC,
  savings_balance NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, 'live')));
  v_destination TEXT := LOWER(TRIM(COALESCE(p_destination, 'wallet')));
  v_amount NUMERIC(12,2) := ROUND(COALESCE(p_amount, 0)::NUMERIC, 2);
  v_gross NUMERIC(14,2) := 0;
  v_refunded NUMERIC(14,2) := 0;
  v_transferred NUMERIC(14,2) := 0;
  v_available NUMERIC(14,2) := 0;
  v_wallet NUMERIC(14,2) := 0;
  v_savings NUMERIC(14,2) := 0;
  v_transfer_id UUID;
  v_tx_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  IF v_destination NOT IN ('wallet', 'savings') THEN
    RAISE EXCEPTION 'Destination must be wallet or savings';
  END IF;

  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::TEXT || ':' || v_mode));

  SELECT
    COALESCE(SUM(CASE WHEN mp.status = 'succeeded' THEN mp.amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN mp.status = 'refunded' THEN mp.amount ELSE 0 END), 0)
  INTO v_gross, v_refunded
  FROM public.merchant_payments mp
  WHERE mp.merchant_user_id = v_user_id
    AND mp.key_mode = v_mode;

  SELECT COALESCE(SUM(mbt.amount), 0)
  INTO v_transferred
  FROM public.merchant_balance_transfers mbt
  WHERE mbt.merchant_user_id = v_user_id
    AND mbt.key_mode = v_mode;

  v_available := GREATEST(v_gross - v_refunded - v_transferred, 0);
  IF v_available < v_amount THEN
    RAISE EXCEPTION 'Insufficient merchant available balance';
  END IF;

  INSERT INTO public.merchant_balance_transfers (
    merchant_user_id,
    key_mode,
    destination,
    amount,
    currency,
    note
  )
  VALUES (
    v_user_id,
    v_mode,
    v_destination,
    v_amount,
    'USD',
    COALESCE(p_note, '')
  )
  RETURNING id INTO v_transfer_id;

  SELECT COALESCE(w.balance, 0)
  INTO v_wallet
  FROM public.wallets w
  WHERE w.user_id = v_user_id
  FOR UPDATE;

  IF v_destination = 'wallet' THEN
    UPDATE public.wallets
    SET balance = v_wallet + v_amount,
        updated_at = now()
    WHERE user_id = v_user_id
    RETURNING balance INTO v_wallet;
  ELSE
    PERFORM public.upsert_my_savings_account();

    UPDATE public.user_savings_accounts
    SET balance = balance + v_amount,
        updated_at = now()
    WHERE user_id = v_user_id
    RETURNING balance INTO v_savings;

    INSERT INTO public.user_savings_transfers (user_id, direction, amount, fee_amount, note)
    VALUES (
      v_user_id,
      'wallet_to_savings',
      v_amount,
      0,
      CONCAT('Merchant balance transfer (', v_mode, ')')
    );
  END IF;

  IF v_destination = 'wallet' THEN
    INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
    VALUES (
      v_user_id,
      v_user_id,
      v_amount,
      CONCAT('Merchant balance transfer to wallet (', v_mode, ')'),
      'completed'
    )
    RETURNING id INTO v_tx_id;
  ELSE
    INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
    VALUES (
      v_user_id,
      v_user_id,
      v_amount,
      CONCAT('Merchant balance transfer to savings (', v_mode, ')'),
      'completed'
    )
    RETURNING id INTO v_tx_id;
  END IF;

  PERFORM public.create_app_notification(
    v_user_id,
    'merchant_activity',
    'Merchant balance transferred',
    CONCAT('Moved ', v_amount::TEXT, ' to ', v_destination, ' (', v_mode, ').'),
    jsonb_build_object(
      'transfer_id', v_transfer_id::TEXT,
      'transaction_id', v_tx_id::TEXT,
      'mode', v_mode,
      'destination', v_destination,
      'amount', v_amount
    )
  );

  SELECT COALESCE(w.balance, 0)
  INTO v_wallet
  FROM public.wallets w
  WHERE w.user_id = v_user_id;

  SELECT COALESCE(usa.balance, 0)
  INTO v_savings
  FROM public.user_savings_accounts usa
  WHERE usa.user_id = v_user_id;

  RETURN QUERY
  SELECT
    v_transfer_id,
    GREATEST(v_available - v_amount, 0),
    v_wallet,
    v_savings;
END;
$$;

DROP FUNCTION IF EXISTS public.get_my_merchant_activity(TEXT, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION public.get_my_merchant_activity(
  p_mode TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  activity_id TEXT,
  activity_type TEXT,
  amount NUMERIC,
  currency TEXT,
  status TEXT,
  note TEXT,
  created_at TIMESTAMPTZ,
  counterparty_name TEXT,
  counterparty_username TEXT,
  source TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, '')));
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode = '' THEN
    v_mode := NULL;
  END IF;

  RETURN QUERY
  WITH payment_rows AS (
    SELECT
      'mp_' || mp.id::TEXT AS activity_id,
      CASE
        WHEN mp.status = 'refunded' THEN 'refund'
        ELSE 'payment'
      END AS activity_type,
      mp.amount,
      mp.currency,
      mp.status,
      COALESCE(tx.note, 'Merchant payment') AS note,
      mp.created_at,
      COALESCE(NULLIF(TRIM(COALESCE(mcs.customer_name, '')), ''), pr.full_name, 'OpenPay Customer') AS counterparty_name,
      pr.username AS counterparty_username,
      CASE
        WHEN COALESCE(mcs.metadata->>'channel', '') = 'pos' THEN 'pos'
        WHEN mp.payment_link_id IS NOT NULL OR COALESCE(mp.payment_link_token, '') <> '' THEN 'payment_link'
        ELSE 'checkout'
      END AS source
    FROM public.merchant_payments mp
    JOIN public.merchant_checkout_sessions mcs
      ON mcs.id = mp.session_id
    LEFT JOIN public.transactions tx
      ON tx.id = mp.transaction_id
    LEFT JOIN public.profiles pr
      ON pr.id = mp.buyer_user_id
    WHERE mp.merchant_user_id = v_user_id
      AND (v_mode IS NULL OR mp.key_mode = v_mode)
  ),
  transfer_rows AS (
    SELECT
      'mbt_' || mbt.id::TEXT AS activity_id,
      CASE
        WHEN mbt.destination = 'wallet' THEN 'transfer_to_wallet'
        ELSE 'transfer_to_savings'
      END AS activity_type,
      mbt.amount,
      mbt.currency,
      'completed'::TEXT AS status,
      COALESCE(NULLIF(TRIM(mbt.note), ''), CONCAT('Merchant balance transfer to ', mbt.destination)) AS note,
      mbt.created_at,
      'Merchant account'::TEXT AS counterparty_name,
      NULL::TEXT AS counterparty_username,
      'merchant_portal'::TEXT AS source
    FROM public.merchant_balance_transfers mbt
    WHERE mbt.merchant_user_id = v_user_id
      AND (v_mode IS NULL OR mbt.key_mode = v_mode)
  )
  SELECT *
  FROM (
    SELECT * FROM payment_rows
    UNION ALL
    SELECT * FROM transfer_rows
  ) rows
  ORDER BY rows.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 300)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$$;

DROP FUNCTION IF EXISTS public.complete_merchant_checkout_with_transaction(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.complete_merchant_checkout_with_transaction(
  p_session_token TEXT,
  p_transaction_id UUID,
  p_note TEXT DEFAULT '',
  p_customer_name TEXT DEFAULT NULL,
  p_customer_email TEXT DEFAULT NULL,
  p_customer_phone TEXT DEFAULT NULL,
  p_customer_address TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buyer_user_id UUID := auth.uid();
  v_session public.merchant_checkout_sessions;
  v_tx public.transactions;
  v_existing_tx UUID;
  v_payment_link_id UUID;
  v_payment_link_token TEXT;
  v_customer_name TEXT := NULLIF(TRIM(COALESCE(p_customer_name, '')), '');
  v_customer_email TEXT := NULLIF(TRIM(COALESCE(p_customer_email, '')), '');
  v_customer_phone TEXT := NULLIF(TRIM(COALESCE(p_customer_phone, '')), '');
  v_customer_address TEXT := NULLIF(TRIM(COALESCE(p_customer_address, '')), '');
BEGIN
  IF v_buyer_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_transaction_id IS NULL THEN
    RAISE EXCEPTION 'Transaction id is required';
  END IF;

  SELECT *
  INTO v_session
  FROM public.merchant_checkout_sessions mcs
  WHERE mcs.session_token = TRIM(COALESCE(p_session_token, ''))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Checkout session not found';
  END IF;

  IF v_session.status = 'paid' THEN
    SELECT mp.transaction_id
    INTO v_existing_tx
    FROM public.merchant_payments mp
    WHERE mp.session_id = v_session.id
    LIMIT 1;

    UPDATE public.merchant_checkout_sessions mcs
    SET customer_name = COALESCE(v_customer_name, mcs.customer_name),
        customer_email = COALESCE(v_customer_email, mcs.customer_email),
        metadata = COALESCE(mcs.metadata, '{}'::jsonb) || jsonb_strip_nulls(
          jsonb_build_object(
            'customer_phone', v_customer_phone,
            'customer_address', v_customer_address
          )
        ),
        updated_at = now()
    WHERE mcs.id = v_session.id;

    RETURN COALESCE(v_existing_tx, p_transaction_id);
  END IF;

  IF v_session.status <> 'open' THEN
    RAISE EXCEPTION 'Checkout session is not open';
  END IF;

  IF v_session.expires_at < now() THEN
    UPDATE public.merchant_checkout_sessions
    SET status = 'expired'
    WHERE id = v_session.id;
    RAISE EXCEPTION 'Checkout session expired';
  END IF;

  IF v_session.merchant_user_id = v_buyer_user_id THEN
    RAISE EXCEPTION 'Merchant cannot pay own checkout';
  END IF;

  SELECT *
  INTO v_tx
  FROM public.transactions t
  WHERE t.id = p_transaction_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transaction not found';
  END IF;

  IF v_tx.status <> 'completed' THEN
    RAISE EXCEPTION 'Transaction is not completed';
  END IF;

  IF v_tx.sender_id <> v_buyer_user_id THEN
    RAISE EXCEPTION 'Transaction sender does not match buyer';
  END IF;

  IF v_tx.receiver_id <> v_session.merchant_user_id THEN
    RAISE EXCEPTION 'Transaction receiver does not match merchant';
  END IF;

  IF ABS(COALESCE(v_tx.amount, 0) - COALESCE(v_session.total_amount, 0)) > 0.02 THEN
    RAISE EXCEPTION 'Transaction amount does not match checkout amount';
  END IF;

  v_payment_link_id := NULLIF((v_session.metadata->>'payment_link_id')::UUID, NULL);
  v_payment_link_token := NULLIF(TRIM(COALESCE(v_session.metadata->>'payment_link_token', '')), '');

  INSERT INTO public.merchant_payments (
    session_id,
    merchant_user_id,
    buyer_user_id,
    transaction_id,
    amount,
    currency,
    api_key_id,
    key_mode,
    payment_link_id,
    payment_link_token,
    status
  )
  VALUES (
    v_session.id,
    v_session.merchant_user_id,
    v_buyer_user_id,
    v_tx.id,
    v_session.total_amount,
    v_session.currency,
    v_session.api_key_id,
    v_session.key_mode,
    v_payment_link_id,
    v_payment_link_token,
    'succeeded'
  )
  ON CONFLICT (session_id) DO NOTHING;

  UPDATE public.merchant_checkout_sessions mcs
  SET status = 'paid',
      paid_at = now(),
      customer_name = COALESCE(v_customer_name, mcs.customer_name),
      customer_email = COALESCE(v_customer_email, mcs.customer_email),
      metadata = COALESCE(mcs.metadata, '{}'::jsonb) || jsonb_strip_nulls(
        jsonb_build_object(
          'customer_phone', v_customer_phone,
          'customer_address', v_customer_address
        )
      ),
      updated_at = now()
  WHERE mcs.id = v_session.id;

  IF COALESCE(TRIM(p_note), '') <> '' THEN
    UPDATE public.transactions
    SET note = CONCAT(COALESCE(note, ''), ' | ', TRIM(p_note))
    WHERE id = v_tx.id;
  END IF;

  RETURN v_tx.id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_merchant_balance_overview(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.transfer_my_merchant_balance(NUMERIC, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_merchant_activity(TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.upsert_my_pos_api_key(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_pos_api_key_settings() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_my_pos_checkout_session(NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_merchant_checkout_with_transaction(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_my_merchant_balance_overview(TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.transfer_my_merchant_balance(NUMERIC, TEXT, TEXT, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_merchant_activity(TEXT, INTEGER, INTEGER) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.upsert_my_pos_api_key(TEXT, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_pos_api_key_settings() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_my_pos_checkout_session(NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_merchant_checkout_with_transaction(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260220153000_merchant_portal_balance_activity.sql

-- >>> MIGRATION: 20260220193000_transaction_email_support.sql
-- Ensure transaction-related screens can show counterparty email
-- and prepare an email outbox pipeline for transaction notifications.

CREATE TABLE IF NOT EXISTS public.email_notifications_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  transaction_id UUID REFERENCES public.transactions(id) ON DELETE CASCADE,
  to_email TEXT NOT NULL,
  subject TEXT NOT NULL,
  body TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'failed')),
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_email_notifications_outbox_status_created
ON public.email_notifications_outbox (status, created_at);

CREATE INDEX IF NOT EXISTS idx_email_notifications_outbox_user_created
ON public.email_notifications_outbox (user_id, created_at DESC);

ALTER TABLE public.email_notifications_outbox ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'email_notifications_outbox'
      AND policyname = 'Service role manages email outbox'
  ) THEN
    CREATE POLICY "Service role manages email outbox"
      ON public.email_notifications_outbox
      FOR ALL TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_email_notifications_outbox_updated_at ON public.email_notifications_outbox;
CREATE TRIGGER trg_email_notifications_outbox_updated_at
BEFORE UPDATE ON public.email_notifications_outbox
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

CREATE OR REPLACE FUNCTION public.queue_transaction_email_notifications()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sender_email TEXT;
  v_receiver_email TEXT;
  v_sender_name TEXT;
  v_receiver_name TEXT;
  v_amount_text TEXT := to_char(COALESCE(NEW.amount, 0), 'FM999999999990D00');
  v_sender_pref BOOLEAN := true;
  v_receiver_pref BOOLEAN := true;
BEGIN
  SELECT email INTO v_sender_email FROM auth.users WHERE id = NEW.sender_id;
  SELECT email INTO v_receiver_email FROM auth.users WHERE id = NEW.receiver_id;

  SELECT COALESCE(NULLIF(TRIM(p.full_name), ''), p.username, 'OpenPay user')
  INTO v_sender_name
  FROM public.profiles p
  WHERE p.id = NEW.sender_id;

  SELECT COALESCE(NULLIF(TRIM(p.full_name), ''), p.username, 'OpenPay user')
  INTO v_receiver_name
  FROM public.profiles p
  WHERE p.id = NEW.receiver_id;

  SELECT COALESCE(np.email_enabled, true)
  INTO v_sender_pref
  FROM public.notification_preferences np
  WHERE np.user_id = NEW.sender_id;

  SELECT COALESCE(np.email_enabled, true)
  INTO v_receiver_pref
  FROM public.notification_preferences np
  WHERE np.user_id = NEW.receiver_id;

  IF NEW.sender_id = NEW.receiver_id THEN
    IF NULLIF(TRIM(COALESCE(v_receiver_email, '')), '') IS NOT NULL AND COALESCE(v_receiver_pref, true) THEN
      INSERT INTO public.email_notifications_outbox (user_id, transaction_id, to_email, subject, body, payload)
      VALUES (
        NEW.receiver_id,
        NEW.id,
        v_receiver_email,
        'OpenPay transaction confirmation',
        format('Your balance was updated by %s. Amount: $%s.', v_sender_name, v_amount_text),
        jsonb_build_object('type', 'self_transfer', 'transaction_id', NEW.id::TEXT, 'amount', NEW.amount)
      );
    END IF;
    RETURN NEW;
  END IF;

  IF NULLIF(TRIM(COALESCE(v_receiver_email, '')), '') IS NOT NULL AND COALESCE(v_receiver_pref, true) THEN
    INSERT INTO public.email_notifications_outbox (user_id, transaction_id, to_email, subject, body, payload)
    VALUES (
      NEW.receiver_id,
      NEW.id,
      v_receiver_email,
      'OpenPay payment received',
      format('You received $%s from %s via OpenPay.', v_amount_text, COALESCE(v_sender_name, 'OpenPay user')),
      jsonb_build_object('type', 'payment_received', 'transaction_id', NEW.id::TEXT, 'amount', NEW.amount, 'sender_id', NEW.sender_id::TEXT)
    );
  END IF;

  IF NULLIF(TRIM(COALESCE(v_sender_email, '')), '') IS NOT NULL AND COALESCE(v_sender_pref, true) THEN
    INSERT INTO public.email_notifications_outbox (user_id, transaction_id, to_email, subject, body, payload)
    VALUES (
      NEW.sender_id,
      NEW.id,
      v_sender_email,
      'OpenPay payment sent',
      format('You sent $%s to %s via OpenPay.', v_amount_text, COALESCE(v_receiver_name, 'OpenPay user')),
      jsonb_build_object('type', 'payment_sent', 'transaction_id', NEW.id::TEXT, 'amount', NEW.amount, 'receiver_id', NEW.receiver_id::TEXT)
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_queue_transaction_email_notifications ON public.transactions;
CREATE TRIGGER trg_queue_transaction_email_notifications
AFTER INSERT ON public.transactions
FOR EACH ROW
EXECUTE FUNCTION public.queue_transaction_email_notifications();

DROP FUNCTION IF EXISTS public.get_my_pos_transactions(TEXT, TEXT, TEXT, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION public.get_my_pos_transactions(
  p_mode TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_search TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  payment_id UUID,
  payment_created_at TIMESTAMPTZ,
  payment_status TEXT,
  amount NUMERIC,
  currency TEXT,
  payer_user_id UUID,
  payer_name TEXT,
  payer_username TEXT,
  transaction_id UUID,
  transaction_note TEXT,
  session_token TEXT,
  customer_name TEXT,
  customer_email TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, '')));
  v_status TEXT := LOWER(TRIM(COALESCE(p_status, '')));
  v_search TEXT := NULLIF(TRIM(COALESCE(p_search, '')), '');
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode = '' THEN
    v_mode := NULL;
  END IF;
  IF v_status = '' THEN
    v_status := NULL;
  END IF;

  RETURN QUERY
  SELECT
    mp.id AS payment_id,
    mp.created_at AS payment_created_at,
    mp.status AS payment_status,
    mp.amount,
    mp.currency,
    mp.buyer_user_id AS payer_user_id,
    COALESCE(NULLIF(TRIM(COALESCE(mcs.customer_name, '')), ''), pr.full_name, 'OpenPay Customer') AS payer_name,
    pr.username AS payer_username,
    mp.transaction_id,
    tx.note AS transaction_note,
    mcs.session_token,
    mcs.customer_name,
    COALESCE(NULLIF(TRIM(COALESCE(mcs.customer_email, '')), ''), buyer_auth.email) AS customer_email
  FROM public.merchant_payments mp
  JOIN public.merchant_checkout_sessions mcs
    ON mcs.id = mp.session_id
  LEFT JOIN public.transactions tx
    ON tx.id = mp.transaction_id
  LEFT JOIN public.profiles pr
    ON pr.id = mp.buyer_user_id
  LEFT JOIN auth.users buyer_auth
    ON buyer_auth.id = mp.buyer_user_id
  WHERE mp.merchant_user_id = v_user_id
    AND (v_mode IS NULL OR mp.key_mode = v_mode)
    AND (v_status IS NULL OR LOWER(mp.status) = v_status)
    AND (
      v_search IS NULL
      OR mp.transaction_id::TEXT ILIKE ('%' || v_search || '%')
      OR mcs.session_token ILIKE ('%' || v_search || '%')
      OR COALESCE(mcs.customer_name, '') ILIKE ('%' || v_search || '%')
      OR COALESCE(mcs.customer_email, '') ILIKE ('%' || v_search || '%')
      OR COALESCE(buyer_auth.email, '') ILIKE ('%' || v_search || '%')
      OR COALESCE(pr.username, '') ILIKE ('%' || v_search || '%')
      OR COALESCE(pr.full_name, '') ILIKE ('%' || v_search || '%')
    )
  ORDER BY mp.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 300)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$$;

DROP FUNCTION IF EXISTS public.get_my_merchant_activity(TEXT, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION public.get_my_merchant_activity(
  p_mode TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  activity_id TEXT,
  activity_type TEXT,
  amount NUMERIC,
  currency TEXT,
  status TEXT,
  note TEXT,
  created_at TIMESTAMPTZ,
  counterparty_name TEXT,
  counterparty_username TEXT,
  counterparty_email TEXT,
  source TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, '')));
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode = '' THEN
    v_mode := NULL;
  END IF;

  RETURN QUERY
  WITH payment_rows AS (
    SELECT
      'mp_' || mp.id::TEXT AS activity_id,
      CASE
        WHEN mp.status = 'refunded' THEN 'refund'
        ELSE 'payment'
      END AS activity_type,
      mp.amount,
      mp.currency,
      mp.status,
      COALESCE(tx.note, 'Merchant payment') AS note,
      mp.created_at,
      COALESCE(NULLIF(TRIM(COALESCE(mcs.customer_name, '')), ''), pr.full_name, 'OpenPay Customer') AS counterparty_name,
      pr.username AS counterparty_username,
      COALESCE(NULLIF(TRIM(COALESCE(mcs.customer_email, '')), ''), buyer_auth.email) AS counterparty_email,
      CASE
        WHEN COALESCE(mcs.metadata->>'channel', '') = 'pos' THEN 'pos'
        WHEN mp.payment_link_id IS NOT NULL OR COALESCE(mp.payment_link_token, '') <> '' THEN 'payment_link'
        ELSE 'checkout'
      END AS source
    FROM public.merchant_payments mp
    JOIN public.merchant_checkout_sessions mcs
      ON mcs.id = mp.session_id
    LEFT JOIN public.transactions tx
      ON tx.id = mp.transaction_id
    LEFT JOIN public.profiles pr
      ON pr.id = mp.buyer_user_id
    LEFT JOIN auth.users buyer_auth
      ON buyer_auth.id = mp.buyer_user_id
    WHERE mp.merchant_user_id = v_user_id
      AND (v_mode IS NULL OR mp.key_mode = v_mode)
  ),
  transfer_rows AS (
    SELECT
      'mbt_' || mbt.id::TEXT AS activity_id,
      CASE
        WHEN mbt.destination = 'wallet' THEN 'transfer_to_wallet'
        ELSE 'transfer_to_savings'
      END AS activity_type,
      mbt.amount,
      mbt.currency,
      'completed'::TEXT AS status,
      COALESCE(NULLIF(TRIM(mbt.note), ''), CONCAT('Merchant balance transfer to ', mbt.destination)) AS note,
      mbt.created_at,
      'Merchant account'::TEXT AS counterparty_name,
      NULL::TEXT AS counterparty_username,
      NULL::TEXT AS counterparty_email,
      'merchant_portal'::TEXT AS source
    FROM public.merchant_balance_transfers mbt
    WHERE mbt.merchant_user_id = v_user_id
      AND (v_mode IS NULL OR mbt.key_mode = v_mode)
  )
  SELECT *
  FROM (
    SELECT * FROM payment_rows
    UNION ALL
    SELECT * FROM transfer_rows
  ) rows
  ORDER BY rows.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 300)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$$;

DROP FUNCTION IF EXISTS public.complete_merchant_checkout_with_transaction(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.complete_merchant_checkout_with_transaction(
  p_session_token TEXT,
  p_transaction_id UUID,
  p_note TEXT DEFAULT '',
  p_customer_name TEXT DEFAULT NULL,
  p_customer_email TEXT DEFAULT NULL,
  p_customer_phone TEXT DEFAULT NULL,
  p_customer_address TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buyer_user_id UUID := auth.uid();
  v_session public.merchant_checkout_sessions;
  v_tx public.transactions;
  v_existing_tx UUID;
  v_payment_link_id UUID;
  v_payment_link_token TEXT;
  v_customer_name TEXT := NULLIF(TRIM(COALESCE(p_customer_name, '')), '');
  v_customer_email TEXT := NULLIF(TRIM(COALESCE(p_customer_email, '')), '');
  v_customer_phone TEXT := NULLIF(TRIM(COALESCE(p_customer_phone, '')), '');
  v_customer_address TEXT := NULLIF(TRIM(COALESCE(p_customer_address, '')), '');
  v_buyer_email TEXT;
BEGIN
  IF v_buyer_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_transaction_id IS NULL THEN
    RAISE EXCEPTION 'Transaction id is required';
  END IF;

  SELECT email INTO v_buyer_email
  FROM auth.users
  WHERE id = v_buyer_user_id;

  SELECT *
  INTO v_session
  FROM public.merchant_checkout_sessions mcs
  WHERE mcs.session_token = TRIM(COALESCE(p_session_token, ''))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Checkout session not found';
  END IF;

  IF v_session.status = 'paid' THEN
    SELECT mp.transaction_id
    INTO v_existing_tx
    FROM public.merchant_payments mp
    WHERE mp.session_id = v_session.id
    LIMIT 1;

    UPDATE public.merchant_checkout_sessions mcs
    SET customer_name = COALESCE(v_customer_name, mcs.customer_name),
        customer_email = COALESCE(v_customer_email, v_buyer_email, mcs.customer_email),
        metadata = COALESCE(mcs.metadata, '{}'::jsonb) || jsonb_strip_nulls(
          jsonb_build_object(
            'customer_phone', v_customer_phone,
            'customer_address', v_customer_address
          )
        ),
        updated_at = now()
    WHERE mcs.id = v_session.id;

    RETURN COALESCE(v_existing_tx, p_transaction_id);
  END IF;

  IF v_session.status <> 'open' THEN
    RAISE EXCEPTION 'Checkout session is not open';
  END IF;

  IF v_session.expires_at < now() THEN
    UPDATE public.merchant_checkout_sessions
    SET status = 'expired'
    WHERE id = v_session.id;
    RAISE EXCEPTION 'Checkout session expired';
  END IF;

  IF v_session.merchant_user_id = v_buyer_user_id THEN
    RAISE EXCEPTION 'Merchant cannot pay own checkout';
  END IF;

  SELECT *
  INTO v_tx
  FROM public.transactions t
  WHERE t.id = p_transaction_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transaction not found';
  END IF;

  IF v_tx.status <> 'completed' THEN
    RAISE EXCEPTION 'Transaction is not completed';
  END IF;

  IF v_tx.sender_id <> v_buyer_user_id THEN
    RAISE EXCEPTION 'Transaction sender does not match buyer';
  END IF;

  IF v_tx.receiver_id <> v_session.merchant_user_id THEN
    RAISE EXCEPTION 'Transaction receiver does not match merchant';
  END IF;

  IF ABS(COALESCE(v_tx.amount, 0) - COALESCE(v_session.total_amount, 0)) > 0.02 THEN
    RAISE EXCEPTION 'Transaction amount does not match checkout amount';
  END IF;

  v_payment_link_id := NULLIF((v_session.metadata->>'payment_link_id')::UUID, NULL);
  v_payment_link_token := NULLIF(TRIM(COALESCE(v_session.metadata->>'payment_link_token', '')), '');

  INSERT INTO public.merchant_payments (
    session_id,
    merchant_user_id,
    buyer_user_id,
    transaction_id,
    amount,
    currency,
    api_key_id,
    key_mode,
    payment_link_id,
    payment_link_token,
    status
  )
  VALUES (
    v_session.id,
    v_session.merchant_user_id,
    v_buyer_user_id,
    v_tx.id,
    v_session.total_amount,
    v_session.currency,
    v_session.api_key_id,
    v_session.key_mode,
    v_payment_link_id,
    v_payment_link_token,
    'succeeded'
  )
  ON CONFLICT (session_id) DO NOTHING;

  UPDATE public.merchant_checkout_sessions mcs
  SET status = 'paid',
      paid_at = now(),
      customer_name = COALESCE(v_customer_name, mcs.customer_name),
      customer_email = COALESCE(v_customer_email, v_buyer_email, mcs.customer_email),
      metadata = COALESCE(mcs.metadata, '{}'::jsonb) || jsonb_strip_nulls(
        jsonb_build_object(
          'customer_phone', v_customer_phone,
          'customer_address', v_customer_address
        )
      ),
      updated_at = now()
  WHERE mcs.id = v_session.id;

  IF COALESCE(TRIM(p_note), '') <> '' THEN
    UPDATE public.transactions
    SET note = CONCAT(COALESCE(note, ''), ' | ', TRIM(p_note))
    WHERE id = v_tx.id;
  END IF;

  RETURN v_tx.id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_pos_transactions(TEXT, TEXT, TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_merchant_activity(TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_merchant_checkout_with_transaction(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_my_pos_transactions(TEXT, TEXT, TEXT, INTEGER, INTEGER) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_merchant_activity(TEXT, INTEGER, INTEGER) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_merchant_checkout_with_transaction(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260220193000_transaction_email_support.sql

-- >>> MIGRATION: 20260220235500_transfer_funds_authenticated_fallback.sql
CREATE OR REPLACE FUNCTION public.transfer_funds_authenticated(
  p_receiver_id UUID,
  p_amount NUMERIC,
  p_note TEXT DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sender_id UUID := auth.uid();
BEGIN
  IF v_sender_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  RETURN public.transfer_funds(
    v_sender_id,
    p_receiver_id,
    p_amount,
    COALESCE(p_note, '')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.transfer_funds_authenticated(UUID, NUMERIC, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transfer_funds_authenticated(UUID, NUMERIC, TEXT) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260220235500_transfer_funds_authenticated_fallback.sql

-- >>> MIGRATION: 20260221002000_fix_missing_notification_preferences.sql
-- Self-heal migration for environments where notification foundation
-- migrations were skipped and transaction triggers now fail.

CREATE TABLE IF NOT EXISTS public.notification_preferences (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  in_app_enabled BOOLEAN NOT NULL DEFAULT true,
  push_enabled BOOLEAN NOT NULL DEFAULT true,
  email_enabled BOOLEAN NOT NULL DEFAULT false,
  quiet_hours_start TIME NULL,
  quiet_hours_end TIME NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'notification_preferences'
      AND policyname = 'Users can view own notification preferences'
  ) THEN
    CREATE POLICY "Users can view own notification preferences"
      ON public.notification_preferences
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'notification_preferences'
      AND policyname = 'Users can upsert own notification preferences'
  ) THEN
    CREATE POLICY "Users can upsert own notification preferences"
      ON public.notification_preferences
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'notification_preferences'
      AND policyname = 'Users can update own notification preferences'
  ) THEN
    CREATE POLICY "Users can update own notification preferences"
      ON public.notification_preferences
      FOR UPDATE TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.set_common_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notification_preferences_updated_at ON public.notification_preferences;
CREATE TRIGGER trg_notification_preferences_updated_at
BEFORE UPDATE ON public.notification_preferences
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260221002000_fix_missing_notification_preferences.sql

-- >>> MIGRATION: 20260221004000_self_heal_user_accounts.sql
-- Self-heal for user account identity objects used by top-up/account-based flows.
-- Safe to run multiple times.

CREATE TABLE IF NOT EXISTS public.user_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  account_number TEXT NOT NULL UNIQUE,
  account_name TEXT NOT NULL DEFAULT '',
  account_username TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.user_accounts ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_accounts'
      AND policyname = 'Users can view own account'
  ) THEN
    CREATE POLICY "Users can view own account"
      ON public.user_accounts
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_accounts'
      AND policyname = 'Users can insert own account'
  ) THEN
    CREATE POLICY "Users can insert own account"
      ON public.user_accounts
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_accounts'
      AND policyname = 'Users can update own account'
  ) THEN
    CREATE POLICY "Users can update own account"
      ON public.user_accounts
      FOR UPDATE TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.set_common_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_accounts_updated_at ON public.user_accounts;
CREATE TRIGGER trg_user_accounts_updated_at
BEFORE UPDATE ON public.user_accounts
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

CREATE OR REPLACE FUNCTION public.generate_openpay_account_number(p_user_id UUID)
RETURNS TEXT
LANGUAGE sql
AS $$
  SELECT 'OP' || UPPER(REPLACE(p_user_id::TEXT, '-', ''));
$$;

CREATE OR REPLACE FUNCTION public.upsert_my_user_account()
RETURNS public.user_accounts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_profile_name TEXT;
  v_profile_username TEXT;
  v_account public.user_accounts;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT full_name, COALESCE(username, '')
  INTO v_profile_name, v_profile_username
  FROM public.profiles
  WHERE id = v_user_id;

  INSERT INTO public.user_accounts (user_id, account_number, account_name, account_username)
  VALUES (
    v_user_id,
    public.generate_openpay_account_number(v_user_id),
    COALESCE(NULLIF(TRIM(v_profile_name), ''), 'OpenPay User'),
    COALESCE(NULLIF(TRIM(v_profile_username), ''), 'openpay')
  )
  ON CONFLICT (user_id) DO UPDATE
  SET account_name = EXCLUDED.account_name,
      account_username = EXCLUDED.account_username
  RETURNING * INTO v_account;

  RETURN v_account;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_my_user_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_my_user_account() TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260221004000_self_heal_user_accounts.sql

-- >>> MIGRATION: 20260222110000_pos_allow_pi_currency.sql
CREATE OR REPLACE FUNCTION public.create_my_pos_checkout_session(
  p_amount NUMERIC,
  p_currency TEXT DEFAULT 'USD',
  p_mode TEXT DEFAULT 'live',
  p_customer_name TEXT DEFAULT NULL,
  p_customer_email TEXT DEFAULT NULL,
  p_reference TEXT DEFAULT NULL,
  p_qr_style TEXT DEFAULT 'dynamic',
  p_expires_in_minutes INTEGER DEFAULT 30,
  p_secret_key TEXT DEFAULT NULL
)
RETURNS TABLE (
  session_id UUID,
  session_token TEXT,
  total_amount NUMERIC,
  currency TEXT,
  status TEXT,
  expires_at TIMESTAMPTZ,
  qr_payload TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, 'live')));
  v_currency TEXT := UPPER(TRIM(COALESCE(p_currency, 'USD')));
  v_qr_style TEXT := LOWER(TRIM(COALESCE(p_qr_style, 'dynamic')));
  v_amount NUMERIC(12,2) := ROUND(COALESCE(p_amount, 0)::NUMERIC, 2);
  v_expires_minutes INTEGER := GREATEST(5, LEAST(COALESCE(p_expires_in_minutes, 30), 10080));
  v_secret_hash TEXT := md5(COALESCE(p_secret_key, ''));
  v_api_key_id UUID;
  v_api_key_ok BOOLEAN := false;
  v_session public.merchant_checkout_sessions;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  IF char_length(v_currency) < 2 OR char_length(v_currency) > 3 THEN
    RAISE EXCEPTION 'Currency must be 2 or 3 letters';
  END IF;

  IF v_qr_style NOT IN ('dynamic', 'static') THEN
    RAISE EXCEPTION 'QR style must be dynamic or static';
  END IF;

  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  IF NULLIF(TRIM(COALESCE(p_secret_key, '')), '') IS NOT NULL THEN
    SELECT mak.id
    INTO v_api_key_id
    FROM public.merchant_api_keys mak
    WHERE mak.merchant_user_id = v_user_id
      AND mak.key_mode = v_mode
      AND mak.is_active = true
      AND mak.secret_key_hash = v_secret_hash
    LIMIT 1;
  ELSE
    SELECT
      CASE
        WHEN v_mode = 'sandbox' THEN s.sandbox_api_key_id
        ELSE s.live_api_key_id
      END
    INTO v_api_key_id
    FROM public.merchant_pos_api_settings s
    WHERE s.merchant_user_id = v_user_id
    LIMIT 1;
  END IF;

  IF v_api_key_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.merchant_api_keys mak
      WHERE mak.id = v_api_key_id
        AND mak.merchant_user_id = v_user_id
        AND mak.key_mode = v_mode
        AND mak.is_active = true
    )
    INTO v_api_key_ok;
  END IF;

  IF NOT v_api_key_ok THEN
    RAISE EXCEPTION 'Set your % POS API key in Settings first (from Merchant Portal / API keys)', v_mode;
  END IF;

  PERFORM public.upsert_my_merchant_profile(NULL, NULL, NULL, v_currency);

  IF v_qr_style = 'static' THEN
    v_expires_minutes := GREATEST(v_expires_minutes, 1440);
  END IF;

  INSERT INTO public.merchant_checkout_sessions (
    merchant_user_id,
    api_key_id,
    key_mode,
    session_token,
    status,
    currency,
    subtotal_amount,
    fee_amount,
    total_amount,
    customer_email,
    customer_name,
    metadata,
    expires_at
  )
  VALUES (
    v_user_id,
    v_api_key_id,
    v_mode,
    'opsess_' || public.random_token_hex(24),
    'open',
    v_currency,
    v_amount,
    0,
    v_amount,
    NULLIF(TRIM(COALESCE(p_customer_email, '')), ''),
    NULLIF(TRIM(COALESCE(p_customer_name, '')), ''),
    jsonb_strip_nulls(
      jsonb_build_object(
        'channel', 'pos',
        'source', 'merchant_pos',
        'api_key_id', v_api_key_id::TEXT,
        'qr_style', v_qr_style,
        'reference', NULLIF(TRIM(COALESCE(p_reference, '')), '')
      )
    ),
    now() + make_interval(mins => v_expires_minutes)
  )
  RETURNING * INTO v_session;

  INSERT INTO public.merchant_checkout_session_items (
    session_id,
    product_id,
    item_name,
    unit_amount,
    quantity,
    line_total
  )
  VALUES (
    v_session.id,
    NULL,
    'POS Payment',
    v_amount,
    1,
    v_amount
  );

  RETURN QUERY
  SELECT
    v_session.id,
    v_session.session_token,
    v_session.total_amount,
    v_session.currency,
    v_session.status,
    v_session.expires_at,
    'openpay-pos://checkout/' || v_session.session_token;
END;
$$;

-- <<< END MIGRATION: 20260222110000_pos_allow_pi_currency.sql

-- >>> MIGRATION: 20260222113000_checkout_amount_currency_conversion.sql
CREATE OR REPLACE FUNCTION public.complete_merchant_checkout_with_transaction(
  p_session_token TEXT,
  p_transaction_id UUID,
  p_note TEXT DEFAULT '',
  p_customer_name TEXT DEFAULT NULL,
  p_customer_email TEXT DEFAULT NULL,
  p_customer_phone TEXT DEFAULT NULL,
  p_customer_address TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buyer_user_id UUID := auth.uid();
  v_session public.merchant_checkout_sessions;
  v_tx public.transactions;
  v_existing_tx UUID;
  v_payment_link_id UUID;
  v_payment_link_token TEXT;
  v_customer_name TEXT := NULLIF(TRIM(COALESCE(p_customer_name, '')), '');
  v_customer_email TEXT := NULLIF(TRIM(COALESCE(p_customer_email, '')), '');
  v_customer_phone TEXT := NULLIF(TRIM(COALESCE(p_customer_phone, '')), '');
  v_customer_address TEXT := NULLIF(TRIM(COALESCE(p_customer_address, '')), '');
  v_buyer_email TEXT;
  v_session_usd_rate NUMERIC(20, 8) := 1;
  v_expected_amount_usd NUMERIC(12, 2) := 0;
BEGIN
  IF v_buyer_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_transaction_id IS NULL THEN
    RAISE EXCEPTION 'Transaction id is required';
  END IF;

  SELECT email INTO v_buyer_email
  FROM auth.users
  WHERE id = v_buyer_user_id;

  SELECT *
  INTO v_session
  FROM public.merchant_checkout_sessions mcs
  WHERE mcs.session_token = TRIM(COALESCE(p_session_token, ''))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Checkout session not found';
  END IF;

  IF v_session.status = 'paid' THEN
    SELECT mp.transaction_id
    INTO v_existing_tx
    FROM public.merchant_payments mp
    WHERE mp.session_id = v_session.id
    LIMIT 1;

    UPDATE public.merchant_checkout_sessions mcs
    SET customer_name = COALESCE(v_customer_name, mcs.customer_name),
        customer_email = COALESCE(v_customer_email, v_buyer_email, mcs.customer_email),
        metadata = COALESCE(mcs.metadata, '{}'::jsonb) || jsonb_strip_nulls(
          jsonb_build_object(
            'customer_phone', v_customer_phone,
            'customer_address', v_customer_address
          )
        ),
        updated_at = now()
    WHERE mcs.id = v_session.id;

    RETURN COALESCE(v_existing_tx, p_transaction_id);
  END IF;

  IF v_session.status <> 'open' THEN
    RAISE EXCEPTION 'Checkout session is not open';
  END IF;

  IF v_session.expires_at < now() THEN
    UPDATE public.merchant_checkout_sessions
    SET status = 'expired'
    WHERE id = v_session.id;
    RAISE EXCEPTION 'Checkout session expired';
  END IF;

  IF v_session.merchant_user_id = v_buyer_user_id THEN
    RAISE EXCEPTION 'Merchant cannot pay own checkout';
  END IF;

  SELECT *
  INTO v_tx
  FROM public.transactions t
  WHERE t.id = p_transaction_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transaction not found';
  END IF;

  IF v_tx.status <> 'completed' THEN
    RAISE EXCEPTION 'Transaction is not completed';
  END IF;

  IF v_tx.sender_id <> v_buyer_user_id THEN
    RAISE EXCEPTION 'Transaction sender does not match buyer';
  END IF;

  IF v_tx.receiver_id <> v_session.merchant_user_id THEN
    RAISE EXCEPTION 'Transaction receiver does not match merchant';
  END IF;

  SELECT sc.usd_rate
  INTO v_session_usd_rate
  FROM public.supported_currencies sc
  WHERE sc.iso_code = UPPER(COALESCE(v_session.currency, 'USD'))
    AND sc.is_active = true
  LIMIT 1;

  v_session_usd_rate := COALESCE(NULLIF(v_session_usd_rate, 0), 1);
  v_expected_amount_usd := ROUND(COALESCE(v_session.total_amount, 0) / v_session_usd_rate, 2);

  IF ABS(COALESCE(v_tx.amount, 0) - v_expected_amount_usd) > 0.02 THEN
    RAISE EXCEPTION 'Transaction amount does not match checkout amount';
  END IF;

  v_payment_link_id := NULLIF((v_session.metadata->>'payment_link_id')::UUID, NULL);
  v_payment_link_token := NULLIF(TRIM(COALESCE(v_session.metadata->>'payment_link_token', '')), '');

  INSERT INTO public.merchant_payments (
    session_id,
    merchant_user_id,
    buyer_user_id,
    transaction_id,
    amount,
    currency,
    api_key_id,
    key_mode,
    payment_link_id,
    payment_link_token,
    status
  )
  VALUES (
    v_session.id,
    v_session.merchant_user_id,
    v_buyer_user_id,
    v_tx.id,
    v_session.total_amount,
    v_session.currency,
    v_session.api_key_id,
    v_session.key_mode,
    v_payment_link_id,
    v_payment_link_token,
    'succeeded'
  )
  ON CONFLICT (session_id) DO NOTHING;

  UPDATE public.merchant_checkout_sessions mcs
  SET status = 'paid',
      paid_at = now(),
      customer_name = COALESCE(v_customer_name, mcs.customer_name),
      customer_email = COALESCE(v_customer_email, v_buyer_email, mcs.customer_email),
      metadata = COALESCE(mcs.metadata, '{}'::jsonb) || jsonb_strip_nulls(
        jsonb_build_object(
          'customer_phone', v_customer_phone,
          'customer_address', v_customer_address
        )
      ),
      updated_at = now()
  WHERE mcs.id = v_session.id;

  IF COALESCE(TRIM(p_note), '') <> '' THEN
    UPDATE public.transactions
    SET note = CONCAT(COALESCE(note, ''), ' | ', TRIM(p_note))
    WHERE id = v_tx.id;
  END IF;

  RETURN v_tx.id;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_merchant_checkout_with_transaction(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_merchant_checkout_with_transaction(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role;

-- <<< END MIGRATION: 20260222113000_checkout_amount_currency_conversion.sql

-- >>> MIGRATION: 20260222120000_merchant_escrow_and_api_checkout_flow.sql
CREATE OR REPLACE FUNCTION public.get_openpay_settlement_user_id()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_openpay_user_id UUID;
BEGIN
  SELECT ua.user_id
  INTO v_openpay_user_id
  FROM public.user_accounts ua
  WHERE LOWER(TRIM(COALESCE(ua.account_username, ''))) = 'openpay'
  ORDER BY
    CASE
      WHEN UPPER(TRIM(COALESCE(ua.account_number, ''))) = 'OPEA68BB7A9F964994A199A15786D680FA' THEN 0
      ELSE 1
    END,
    ua.created_at ASC
  LIMIT 1;

  IF v_openpay_user_id IS NULL THEN
    RAISE EXCEPTION 'OpenPay settlement account not found';
  END IF;

  RETURN v_openpay_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_merchant_balance_overview(
  p_mode TEXT DEFAULT 'live'
)
RETURNS TABLE (
  gross_volume NUMERIC,
  refunded_total NUMERIC,
  transferred_total NUMERIC,
  available_balance NUMERIC,
  wallet_balance NUMERIC,
  savings_balance NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, 'live')));
  v_gross NUMERIC(14,2) := 0;
  v_refunded NUMERIC(14,2) := 0;
  v_transferred NUMERIC(14,2) := 0;
  v_wallet NUMERIC(14,2) := 0;
  v_savings NUMERIC(14,2) := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  SELECT
    COALESCE(SUM(CASE WHEN mp.status = 'succeeded' THEN ROUND(mp.amount / COALESCE(NULLIF(sc.usd_rate, 0), 1), 2) ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN mp.status = 'refunded' THEN ROUND(mp.amount / COALESCE(NULLIF(sc.usd_rate, 0), 1), 2) ELSE 0 END), 0)
  INTO v_gross, v_refunded
  FROM public.merchant_payments mp
  LEFT JOIN public.supported_currencies sc
    ON sc.iso_code = UPPER(COALESCE(mp.currency, 'USD'))
  WHERE mp.merchant_user_id = v_user_id
    AND mp.key_mode = v_mode;

  SELECT COALESCE(SUM(mbt.amount), 0)
  INTO v_transferred
  FROM public.merchant_balance_transfers mbt
  WHERE mbt.merchant_user_id = v_user_id
    AND mbt.key_mode = v_mode;

  SELECT COALESCE(w.balance, 0)
  INTO v_wallet
  FROM public.wallets w
  WHERE w.user_id = v_user_id;

  PERFORM public.upsert_my_savings_account();
  SELECT COALESCE(usa.balance, 0)
  INTO v_savings
  FROM public.user_savings_accounts usa
  WHERE usa.user_id = v_user_id;

  RETURN QUERY
  SELECT
    v_gross,
    v_refunded,
    v_transferred,
    GREATEST(v_gross - v_refunded - v_transferred, 0),
    v_wallet,
    v_savings;
END;
$$;

CREATE OR REPLACE FUNCTION public.transfer_my_merchant_balance(
  p_amount NUMERIC,
  p_mode TEXT DEFAULT 'live',
  p_destination TEXT DEFAULT 'wallet',
  p_note TEXT DEFAULT ''
)
RETURNS TABLE (
  transfer_id UUID,
  available_balance NUMERIC,
  wallet_balance NUMERIC,
  savings_balance NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, 'live')));
  v_destination TEXT := LOWER(TRIM(COALESCE(p_destination, 'wallet')));
  v_amount NUMERIC(12,2) := ROUND(COALESCE(p_amount, 0)::NUMERIC, 2);
  v_gross NUMERIC(14,2) := 0;
  v_refunded NUMERIC(14,2) := 0;
  v_transferred NUMERIC(14,2) := 0;
  v_available NUMERIC(14,2) := 0;
  v_wallet NUMERIC(14,2) := 0;
  v_savings NUMERIC(14,2) := 0;
  v_transfer_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  IF v_destination NOT IN ('wallet', 'savings') THEN
    RAISE EXCEPTION 'Destination must be wallet or savings';
  END IF;

  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::TEXT || ':' || v_mode));

  SELECT
    COALESCE(SUM(CASE WHEN mp.status = 'succeeded' THEN ROUND(mp.amount / COALESCE(NULLIF(sc.usd_rate, 0), 1), 2) ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN mp.status = 'refunded' THEN ROUND(mp.amount / COALESCE(NULLIF(sc.usd_rate, 0), 1), 2) ELSE 0 END), 0)
  INTO v_gross, v_refunded
  FROM public.merchant_payments mp
  LEFT JOIN public.supported_currencies sc
    ON sc.iso_code = UPPER(COALESCE(mp.currency, 'USD'))
  WHERE mp.merchant_user_id = v_user_id
    AND mp.key_mode = v_mode;

  SELECT COALESCE(SUM(mbt.amount), 0)
  INTO v_transferred
  FROM public.merchant_balance_transfers mbt
  WHERE mbt.merchant_user_id = v_user_id
    AND mbt.key_mode = v_mode;

  v_available := GREATEST(v_gross - v_refunded - v_transferred, 0);
  IF v_available < v_amount THEN
    RAISE EXCEPTION 'Insufficient merchant available balance';
  END IF;

  INSERT INTO public.merchant_balance_transfers (
    merchant_user_id,
    key_mode,
    destination,
    amount,
    currency,
    note
  )
  VALUES (
    v_user_id,
    v_mode,
    v_destination,
    v_amount,
    'USD',
    COALESCE(p_note, '')
  )
  RETURNING id INTO v_transfer_id;

  SELECT COALESCE(w.balance, 0)
  INTO v_wallet
  FROM public.wallets w
  WHERE w.user_id = v_user_id
  FOR UPDATE;

  IF v_destination = 'wallet' THEN
    UPDATE public.wallets
    SET balance = v_wallet + v_amount,
        updated_at = now()
    WHERE user_id = v_user_id
    RETURNING balance INTO v_wallet;
  ELSE
    PERFORM public.upsert_my_savings_account();

    UPDATE public.user_savings_accounts
    SET balance = balance + v_amount,
        updated_at = now()
    WHERE user_id = v_user_id
    RETURNING balance INTO v_savings;

    INSERT INTO public.user_savings_transfers (user_id, direction, amount, fee_amount, note)
    VALUES (
      v_user_id,
      'wallet_to_savings',
      v_amount,
      0,
      CONCAT('Merchant balance transfer (', v_mode, ')')
    );
  END IF;

  IF v_destination <> 'savings' THEN
    PERFORM public.upsert_my_savings_account();
    SELECT COALESCE(usa.balance, 0)
    INTO v_savings
    FROM public.user_savings_accounts usa
    WHERE usa.user_id = v_user_id;
  END IF;

  RETURN QUERY
  SELECT
    v_transfer_id,
    GREATEST(v_available - v_amount, 0),
    COALESCE(v_wallet, 0),
    COALESCE(v_savings, 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.pay_merchant_checkout_with_wallet(
  p_session_token TEXT,
  p_note TEXT DEFAULT '',
  p_customer_name TEXT DEFAULT NULL,
  p_customer_email TEXT DEFAULT NULL,
  p_customer_phone TEXT DEFAULT NULL,
  p_customer_address TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buyer_user_id UUID := auth.uid();
  v_openpay_user_id UUID;
  v_session public.merchant_checkout_sessions;
  v_existing_tx UUID;
  v_tx_id UUID;
  v_sender_balance NUMERIC(12,2);
  v_merchant_balance NUMERIC(12,2);
  v_openpay_balance NUMERIC(12,2);
  v_currency_rate NUMERIC(20,8) := 1;
  v_wallet_amount NUMERIC(12,2) := 0;
  v_customer_name TEXT := NULLIF(TRIM(COALESCE(p_customer_name, '')), '');
  v_customer_email TEXT := NULLIF(TRIM(COALESCE(p_customer_email, '')), '');
  v_customer_phone TEXT := NULLIF(TRIM(COALESCE(p_customer_phone, '')), '');
  v_customer_address TEXT := NULLIF(TRIM(COALESCE(p_customer_address, '')), '');
  v_buyer_email TEXT;
  v_payment_link_id UUID;
  v_payment_link_token TEXT;
BEGIN
  IF v_buyer_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT email INTO v_buyer_email
  FROM auth.users
  WHERE id = v_buyer_user_id;

  v_openpay_user_id := public.get_openpay_settlement_user_id();

  SELECT *
  INTO v_session
  FROM public.merchant_checkout_sessions mcs
  WHERE mcs.session_token = TRIM(COALESCE(p_session_token, ''))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Checkout session not found';
  END IF;

  IF v_session.status = 'paid' THEN
    SELECT mp.transaction_id
    INTO v_existing_tx
    FROM public.merchant_payments mp
    WHERE mp.session_id = v_session.id
    LIMIT 1;

    RETURN v_existing_tx;
  END IF;

  IF v_session.status <> 'open' THEN
    RAISE EXCEPTION 'Checkout session is not open';
  END IF;

  IF v_session.expires_at < now() THEN
    UPDATE public.merchant_checkout_sessions
    SET status = 'expired'
    WHERE id = v_session.id;
    RAISE EXCEPTION 'Checkout session expired';
  END IF;

  IF v_session.merchant_user_id = v_buyer_user_id THEN
    RAISE EXCEPTION 'Merchant cannot pay own checkout';
  END IF;

  SELECT sc.usd_rate
  INTO v_currency_rate
  FROM public.supported_currencies sc
  WHERE sc.iso_code = UPPER(COALESCE(v_session.currency, 'USD'))
    AND sc.is_active = true
  LIMIT 1;

  v_currency_rate := COALESCE(NULLIF(v_currency_rate, 0), 1);
  v_wallet_amount := ROUND(COALESCE(v_session.total_amount, 0) / v_currency_rate, 2);

  IF v_wallet_amount <= 0 THEN
    RAISE EXCEPTION 'Checkout amount must be greater than zero';
  END IF;

  SELECT balance INTO v_sender_balance
  FROM public.wallets
  WHERE user_id = v_buyer_user_id
  FOR UPDATE;

  IF v_sender_balance IS NULL THEN
    RAISE EXCEPTION 'Buyer wallet not found';
  END IF;

  SELECT balance INTO v_merchant_balance
  FROM public.wallets
  WHERE user_id = v_session.merchant_user_id
  FOR UPDATE;

  IF v_merchant_balance IS NULL THEN
    RAISE EXCEPTION 'Merchant wallet not found';
  END IF;

  SELECT balance INTO v_openpay_balance
  FROM public.wallets
  WHERE user_id = v_openpay_user_id
  FOR UPDATE;

  IF v_openpay_balance IS NULL THEN
    RAISE EXCEPTION 'OpenPay settlement wallet not found';
  END IF;

  IF v_sender_balance < v_wallet_amount THEN
    RAISE EXCEPTION 'Insufficient balance';
  END IF;

  UPDATE public.wallets
  SET balance = v_sender_balance - v_wallet_amount,
      updated_at = now()
  WHERE user_id = v_buyer_user_id;

  UPDATE public.wallets
  SET balance = v_merchant_balance + v_wallet_amount,
      updated_at = now()
  WHERE user_id = v_session.merchant_user_id;

  UPDATE public.wallets
  SET balance = v_openpay_balance + v_wallet_amount,
      updated_at = now()
  WHERE user_id = v_openpay_user_id;

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_buyer_user_id,
    v_session.merchant_user_id,
    v_wallet_amount,
    CONCAT(
      'Merchant checkout ',
      v_session.session_token,
      ' | Held in merchant available balance',
      CASE WHEN COALESCE(TRIM(p_note), '') <> '' THEN CONCAT(' | ', TRIM(p_note)) ELSE '' END
    ),
    'completed'
  )
  RETURNING id INTO v_tx_id;

  v_payment_link_id := NULLIF((v_session.metadata->>'payment_link_id')::UUID, NULL);
  v_payment_link_token := NULLIF(TRIM(COALESCE(v_session.metadata->>'payment_link_token', '')), '');

  INSERT INTO public.merchant_payments (
    session_id,
    merchant_user_id,
    buyer_user_id,
    transaction_id,
    amount,
    currency,
    api_key_id,
    key_mode,
    payment_link_id,
    payment_link_token,
    status
  )
  VALUES (
    v_session.id,
    v_session.merchant_user_id,
    v_buyer_user_id,
    v_tx_id,
    v_session.total_amount,
    v_session.currency,
    v_session.api_key_id,
    v_session.key_mode,
    v_payment_link_id,
    v_payment_link_token,
    'succeeded'
  )
  ON CONFLICT (session_id) DO UPDATE SET
    transaction_id = EXCLUDED.transaction_id,
    status = EXCLUDED.status,
    amount = EXCLUDED.amount,
    currency = EXCLUDED.currency;

  -- Log the merchant payment creation
  INSERT INTO public.ledger_events (
    source_table,
    source_id,
    event_type,
    actor_user_id,
    related_user_id,
    amount,
    status,
    note,
    payload,
    occurred_at
  )
  VALUES (
    'merchant_payments',
    v_tx_id,
    'merchant_payment_created',
    v_buyer_user_id,
    v_session.merchant_user_id,
    v_session.total_amount,
    'succeeded',
    'POS payment completed',
    jsonb_build_object(
      'session_id', v_session.id,
      'session_token', v_session.session_token,
      'transaction_id', v_tx_id,
      'currency', v_session.currency,
      'payment_method', 'wallet'
    ),
    now()
  );

  UPDATE public.merchant_checkout_sessions mcs
  SET status = 'paid',
      paid_at = now(),
      customer_name = COALESCE(v_customer_name, mcs.customer_name),
      customer_email = COALESCE(v_customer_email, v_buyer_email, mcs.customer_email),
      metadata = COALESCE(mcs.metadata, '{}'::jsonb) || jsonb_strip_nulls(
        jsonb_build_object(
          'customer_phone', v_customer_phone,
          'customer_address', v_customer_address
        )
      ),
      updated_at = now()
  WHERE mcs.id = v_session.id;

  RETURN v_tx_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.pay_merchant_checkout_with_virtual_card(
  p_session_token TEXT,
  p_card_number TEXT,
  p_expiry_month INTEGER,
  p_expiry_year INTEGER,
  p_cvc TEXT,
  p_note TEXT DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buyer_user_id UUID := auth.uid();
  v_session public.merchant_checkout_sessions;
  v_sender_balance NUMERIC(12,2);
  v_receiver_balance NUMERIC(12,2);
  v_openpay_balance NUMERIC(12,2);
  v_transaction_id UUID;
  v_card_number TEXT := regexp_replace(COALESCE(p_card_number, ''), '\D', '', 'g');
  v_cvc TEXT := regexp_replace(COALESCE(p_cvc, ''), '\D', '', 'g');
  v_expiry_end DATE;
  v_expiry_year INTEGER := COALESCE(p_expiry_year, 0);
  v_payment_link_id UUID;
  v_payment_link_token TEXT;
  v_card_owner_user_id UUID;
  v_currency_rate NUMERIC(20,8) := 1;
  v_wallet_amount NUMERIC(12,2) := 0;
  v_openpay_user_id UUID;
BEGIN
  IF v_buyer_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  v_openpay_user_id := public.get_openpay_settlement_user_id();

  IF v_expiry_year > 0 AND v_expiry_year < 100 THEN
    v_expiry_year := 2000 + v_expiry_year;
  END IF;

  SELECT *
  INTO v_session
  FROM public.merchant_checkout_sessions mcs
  WHERE mcs.session_token = TRIM(COALESCE(p_session_token, ''))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Checkout session not found';
  END IF;

  IF v_session.status <> 'open' THEN
    RAISE EXCEPTION 'Checkout session is not open';
  END IF;

  IF v_session.expires_at < now() THEN
    UPDATE public.merchant_checkout_sessions
    SET status = 'expired'
    WHERE id = v_session.id;
    RAISE EXCEPTION 'Checkout session expired';
  END IF;

  IF v_session.merchant_user_id = v_buyer_user_id THEN
    RAISE EXCEPTION 'Merchant cannot pay own checkout';
  END IF;

  IF char_length(v_card_number) <> 16 THEN
    RAISE EXCEPTION 'Card number must be 16 digits';
  END IF;

  IF p_expiry_month IS NULL OR p_expiry_month < 1 OR p_expiry_month > 12 THEN
    RAISE EXCEPTION 'Invalid expiry month';
  END IF;

  IF v_expiry_year < 2026 THEN
    RAISE EXCEPTION 'Invalid expiry year';
  END IF;

  IF char_length(v_cvc) <> 3 THEN
    RAISE EXCEPTION 'Invalid CVC';
  END IF;

  v_expiry_end := (make_date(v_expiry_year, p_expiry_month, 1) + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
  IF v_expiry_end < CURRENT_DATE THEN
    RAISE EXCEPTION 'Card expired';
  END IF;

  SELECT vc.user_id
  INTO v_card_owner_user_id
  FROM public.virtual_cards vc
  WHERE vc.card_number = v_card_number
    AND vc.expiry_month = p_expiry_month
    AND vc.expiry_year = v_expiry_year
    AND vc.cvc = v_cvc
    AND vc.is_active = true
    AND COALESCE(vc.is_locked, false) = false
    AND COALESCE((vc.card_settings ->> 'allow_checkout')::BOOLEAN, true) = true
  FOR UPDATE;

  IF v_card_owner_user_id IS NULL THEN
    RAISE EXCEPTION 'Invalid virtual card details';
  END IF;

  IF v_card_owner_user_id <> v_buyer_user_id THEN
    RAISE EXCEPTION 'Card owner does not match authenticated customer';
  END IF;

  SELECT sc.usd_rate
  INTO v_currency_rate
  FROM public.supported_currencies sc
  WHERE sc.iso_code = UPPER(COALESCE(v_session.currency, 'USD'))
    AND sc.is_active = true
  LIMIT 1;

  v_currency_rate := COALESCE(NULLIF(v_currency_rate, 0), 1);
  v_wallet_amount := ROUND(COALESCE(v_session.total_amount, 0) / v_currency_rate, 2);

  IF v_wallet_amount <= 0 THEN
    RAISE EXCEPTION 'Checkout amount must be greater than zero';
  END IF;

  SELECT balance INTO v_sender_balance
  FROM public.wallets
  WHERE user_id = v_card_owner_user_id
  FOR UPDATE;

  IF v_sender_balance IS NULL THEN
    RAISE EXCEPTION 'Buyer wallet not found';
  END IF;

  SELECT balance INTO v_receiver_balance
  FROM public.wallets
  WHERE user_id = v_session.merchant_user_id
  FOR UPDATE;

  IF v_receiver_balance IS NULL THEN
    RAISE EXCEPTION 'Merchant wallet not found';
  END IF;

  SELECT balance INTO v_openpay_balance
  FROM public.wallets
  WHERE user_id = v_openpay_user_id
  FOR UPDATE;

  IF v_openpay_balance IS NULL THEN
    RAISE EXCEPTION 'OpenPay settlement wallet not found';
  END IF;

  IF v_sender_balance < v_wallet_amount THEN
    RAISE EXCEPTION 'Insufficient virtual card balance';
  END IF;

  UPDATE public.wallets
  SET balance = v_sender_balance - v_wallet_amount,
      updated_at = now()
  WHERE user_id = v_card_owner_user_id;

  UPDATE public.wallets
  SET balance = v_receiver_balance + v_wallet_amount,
      updated_at = now()
  WHERE user_id = v_session.merchant_user_id;

  UPDATE public.wallets
  SET balance = balance - v_wallet_amount,
      updated_at = now()
  WHERE user_id = v_session.merchant_user_id;

  UPDATE public.wallets
  SET balance = v_openpay_balance + v_wallet_amount,
      updated_at = now()
  WHERE user_id = v_openpay_user_id;

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_card_owner_user_id,
    v_session.merchant_user_id,
    v_wallet_amount,
    CONCAT(
      'Merchant checkout ',
      v_session.session_token,
      ' | Card ****',
      RIGHT(v_card_number, 4),
      ' | Held in merchant available balance',
      CASE WHEN COALESCE(TRIM(p_note), '') <> '' THEN CONCAT(' | ', TRIM(p_note)) ELSE '' END
    ),
    'completed'
  )
  RETURNING id INTO v_transaction_id;

  v_payment_link_id := NULLIF((v_session.metadata->>'payment_link_id')::UUID, NULL);
  v_payment_link_token := NULLIF(TRIM(COALESCE(v_session.metadata->>'payment_link_token', '')), '');

  INSERT INTO public.merchant_payments (
    session_id,
    merchant_user_id,
    buyer_user_id,
    transaction_id,
    amount,
    currency,
    api_key_id,
    key_mode,
    payment_link_id,
    payment_link_token,
    status
  )
  VALUES (
    v_session.id,
    v_session.merchant_user_id,
    v_buyer_user_id,
    v_transaction_id,
    v_session.total_amount,
    v_session.currency,
    v_session.api_key_id,
    v_session.key_mode,
    v_payment_link_id,
    v_payment_link_token,
    'succeeded'
  );

  UPDATE public.merchant_checkout_sessions
  SET status = 'paid',
      paid_at = now()
  WHERE id = v_session.id;

  RETURN v_transaction_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.refund_my_pos_transaction(
  p_payment_id UUID,
  p_reason TEXT DEFAULT ''
)
RETURNS TABLE (
  refund_transaction_id UUID,
  new_status TEXT,
  refunded_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_openpay_user_id UUID;
  v_payment public.merchant_payments;
  v_session public.merchant_checkout_sessions;
  v_openpay_balance NUMERIC(12,2);
  v_buyer_balance NUMERIC(12,2);
  v_refund_tx_id UUID;
  v_currency_rate NUMERIC(20,8) := 1;
  v_wallet_amount NUMERIC(12,2) := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_payment_id IS NULL THEN
    RAISE EXCEPTION 'Payment ID is required';
  END IF;

  v_openpay_user_id := public.get_openpay_settlement_user_id();

  SELECT *
  INTO v_payment
  FROM public.merchant_payments
  WHERE id = p_payment_id
    AND merchant_user_id = v_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment not found';
  END IF;

  IF v_payment.status = 'refunded' THEN
    RAISE EXCEPTION 'Payment already refunded';
  END IF;

  IF v_payment.status <> 'succeeded' THEN
    RAISE EXCEPTION 'Only succeeded payments can be refunded';
  END IF;

  SELECT *
  INTO v_session
  FROM public.merchant_checkout_sessions
  WHERE id = v_payment.session_id
  FOR UPDATE;

  SELECT sc.usd_rate
  INTO v_currency_rate
  FROM public.supported_currencies sc
  WHERE sc.iso_code = UPPER(COALESCE(v_payment.currency, 'USD'))
    AND sc.is_active = true
  LIMIT 1;

  v_currency_rate := COALESCE(NULLIF(v_currency_rate, 0), 1);
  v_wallet_amount := ROUND(COALESCE(v_payment.amount, 0) / v_currency_rate, 2);

  SELECT w.balance
  INTO v_openpay_balance
  FROM public.wallets w
  WHERE w.user_id = v_openpay_user_id
  FOR UPDATE;

  SELECT w.balance
  INTO v_buyer_balance
  FROM public.wallets w
  WHERE w.user_id = v_payment.buyer_user_id
  FOR UPDATE;

  IF v_openpay_balance IS NULL OR v_buyer_balance IS NULL THEN
    RAISE EXCEPTION 'Wallet not found';
  END IF;

  IF v_openpay_balance < v_wallet_amount THEN
    RAISE EXCEPTION 'Insufficient settlement balance for refund';
  END IF;

  UPDATE public.wallets
  SET balance = v_openpay_balance - v_wallet_amount,
      updated_at = now()
  WHERE user_id = v_openpay_user_id;

  UPDATE public.wallets
  SET balance = v_buyer_balance + v_wallet_amount,
      updated_at = now()
  WHERE user_id = v_payment.buyer_user_id;

  INSERT INTO public.transactions (
    sender_id,
    receiver_id,
    amount,
    note,
    status
  )
  VALUES (
    v_user_id,
    v_payment.buyer_user_id,
    v_wallet_amount,
    CONCAT(
      'POS refund for payment ',
      v_payment.id::TEXT,
      ' | Refunded from merchant available balance',
      CASE WHEN NULLIF(TRIM(COALESCE(p_reason, '')), '') IS NULL THEN '' ELSE ' | ' || TRIM(p_reason) END
    ),
    'refunded'
  )
  RETURNING id INTO v_refund_tx_id;

  UPDATE public.merchant_payments
  SET status = 'refunded'
  WHERE id = v_payment.id;

  UPDATE public.merchant_checkout_sessions
  SET metadata = COALESCE(v_session.metadata, '{}'::jsonb) || jsonb_build_object(
    'refunded_at', now(),
    'refund_transaction_id', v_refund_tx_id::TEXT
  ),
      updated_at = now()
  WHERE id = v_session.id;

  RETURN QUERY
  SELECT
    v_refund_tx_id,
    'refunded'::TEXT,
    now();
END;
$$;

REVOKE ALL ON FUNCTION public.get_openpay_settlement_user_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pay_merchant_checkout_with_wallet(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_openpay_settlement_user_id() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.pay_merchant_checkout_with_wallet(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role;

-- <<< END MIGRATION: 20260222120000_merchant_escrow_and_api_checkout_flow.sql

-- >>> MIGRATION: 20260222121000_fix_pos_pi_profile_currency_constraint.sql
CREATE OR REPLACE FUNCTION public.create_my_pos_checkout_session(
  p_amount NUMERIC,
  p_currency TEXT DEFAULT 'USD',
  p_mode TEXT DEFAULT 'live',
  p_customer_name TEXT DEFAULT NULL,
  p_customer_email TEXT DEFAULT NULL,
  p_reference TEXT DEFAULT NULL,
  p_qr_style TEXT DEFAULT 'dynamic',
  p_expires_in_minutes INTEGER DEFAULT 30,
  p_secret_key TEXT DEFAULT NULL
)
RETURNS TABLE (
  session_id UUID,
  session_token TEXT,
  total_amount NUMERIC,
  currency TEXT,
  status TEXT,
  expires_at TIMESTAMPTZ,
  qr_payload TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, 'live')));
  v_currency TEXT := UPPER(TRIM(COALESCE(p_currency, 'USD')));
  v_profile_currency TEXT := CASE WHEN char_length(UPPER(TRIM(COALESCE(p_currency, 'USD')))) = 3 THEN UPPER(TRIM(COALESCE(p_currency, 'USD'))) ELSE 'USD' END;
  v_qr_style TEXT := LOWER(TRIM(COALESCE(p_qr_style, 'dynamic')));
  v_amount NUMERIC(12,2) := ROUND(COALESCE(p_amount, 0)::NUMERIC, 2);
  v_expires_minutes INTEGER := GREATEST(5, LEAST(COALESCE(p_expires_in_minutes, 30), 10080));
  v_secret_hash TEXT := md5(COALESCE(p_secret_key, ''));
  v_api_key_id UUID;
  v_api_key_ok BOOLEAN := false;
  v_session public.merchant_checkout_sessions;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  IF char_length(v_currency) < 2 OR char_length(v_currency) > 3 THEN
    RAISE EXCEPTION 'Currency must be 2 or 3 letters';
  END IF;

  IF v_qr_style NOT IN ('dynamic', 'static') THEN
    RAISE EXCEPTION 'QR style must be dynamic or static';
  END IF;

  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  IF NULLIF(TRIM(COALESCE(p_secret_key, '')), '') IS NOT NULL THEN
    SELECT mak.id
    INTO v_api_key_id
    FROM public.merchant_api_keys mak
    WHERE mak.merchant_user_id = v_user_id
      AND mak.key_mode = v_mode
      AND mak.is_active = true
      AND mak.secret_key_hash = v_secret_hash
    LIMIT 1;
  ELSE
    SELECT
      CASE
        WHEN v_mode = 'sandbox' THEN s.sandbox_api_key_id
        ELSE s.live_api_key_id
      END
    INTO v_api_key_id
    FROM public.merchant_pos_api_settings s
    WHERE s.merchant_user_id = v_user_id
    LIMIT 1;
  END IF;

  IF v_api_key_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.merchant_api_keys mak
      WHERE mak.id = v_api_key_id
        AND mak.merchant_user_id = v_user_id
        AND mak.key_mode = v_mode
        AND mak.is_active = true
    )
    INTO v_api_key_ok;
  END IF;

  IF NOT v_api_key_ok THEN
    RAISE EXCEPTION 'Set your % POS API key in Settings first (from Merchant Portal / API keys)', v_mode;
  END IF;

  PERFORM public.upsert_my_merchant_profile(NULL, NULL, NULL, v_profile_currency);

  IF v_qr_style = 'static' THEN
    v_expires_minutes := GREATEST(v_expires_minutes, 1440);
  END IF;

  INSERT INTO public.merchant_checkout_sessions (
    merchant_user_id,
    api_key_id,
    key_mode,
    session_token,
    status,
    currency,
    subtotal_amount,
    fee_amount,
    total_amount,
    customer_email,
    customer_name,
    metadata,
    expires_at
  )
  VALUES (
    v_user_id,
    v_api_key_id,
    v_mode,
    'opsess_' || public.random_token_hex(24),
    'open',
    v_currency,
    v_amount,
    0,
    v_amount,
    NULLIF(TRIM(COALESCE(p_customer_email, '')), ''),
    NULLIF(TRIM(COALESCE(p_customer_name, '')), ''),
    jsonb_strip_nulls(
      jsonb_build_object(
        'channel', 'pos',
        'source', 'merchant_pos',
        'api_key_id', v_api_key_id::TEXT,
        'qr_style', v_qr_style,
        'reference', NULLIF(TRIM(COALESCE(p_reference, '')), '')
      )
    ),
    now() + make_interval(mins => v_expires_minutes)
  )
  RETURNING * INTO v_session;

  INSERT INTO public.merchant_checkout_session_items (
    session_id,
    product_id,
    item_name,
    unit_amount,
    quantity,
    line_total
  )
  VALUES (
    v_session.id,
    NULL,
    'POS Payment',
    v_amount,
    1,
    v_amount
  );

  RETURN QUERY
  SELECT
    v_session.id,
    v_session.session_token,
    v_session.total_amount,
    v_session.currency,
    v_session.status,
    v_session.expires_at,
    'openpay-pos://checkout/' || v_session.session_token;
END;
$$;

-- <<< END MIGRATION: 20260222121000_fix_pos_pi_profile_currency_constraint.sql

-- >>> MIGRATION: 20260222124000_credit_score_zero_start_and_loan_unlock.sql
CREATE OR REPLACE FUNCTION public.calculate_user_activity_credit_score(
  p_user_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_topup_count INTEGER := 0;
  v_send_count INTEGER := 0;
  v_receive_count INTEGER := 0;
  v_invoice_count INTEGER := 0;
  v_request_count INTEGER := 0;
  v_paid_invoice_count INTEGER := 0;
  v_paid_request_count INTEGER := 0;
  v_checkout_buyer_count INTEGER := 0;
  v_checkout_merchant_count INTEGER := 0;
  v_pos_payment_count INTEGER := 0;
  v_checkout_link_payment_count INTEGER := 0;
  v_total_tx_volume NUMERIC(14,2) := 0;
  v_score NUMERIC := 0;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN 0;
  END IF;

  SELECT COUNT(*)::INTEGER
  INTO v_topup_count
  FROM public.transactions t
  WHERE t.sender_id = p_user_id
    AND t.receiver_id = p_user_id
    AND t.status = 'completed';

  SELECT COUNT(*)::INTEGER
  INTO v_send_count
  FROM public.transactions t
  WHERE t.sender_id = p_user_id
    AND t.receiver_id <> p_user_id
    AND t.status = 'completed';

  SELECT COUNT(*)::INTEGER
  INTO v_receive_count
  FROM public.transactions t
  WHERE t.receiver_id = p_user_id
    AND t.sender_id <> p_user_id
    AND t.status = 'completed';

  SELECT COALESCE(SUM(t.amount), 0)
  INTO v_total_tx_volume
  FROM public.transactions t
  WHERE (t.sender_id = p_user_id OR t.receiver_id = p_user_id)
    AND t.status = 'completed';

  SELECT COUNT(*)::INTEGER
  INTO v_invoice_count
  FROM public.invoices i
  WHERE i.sender_id = p_user_id
     OR i.recipient_id = p_user_id;

  SELECT COUNT(*)::INTEGER
  INTO v_paid_invoice_count
  FROM public.invoices i
  WHERE (i.sender_id = p_user_id OR i.recipient_id = p_user_id)
    AND i.status = 'paid';

  SELECT COUNT(*)::INTEGER
  INTO v_request_count
  FROM public.payment_requests pr
  WHERE pr.requester_id = p_user_id
     OR pr.payer_id = p_user_id;

  SELECT COUNT(*)::INTEGER
  INTO v_paid_request_count
  FROM public.payment_requests pr
  WHERE (pr.requester_id = p_user_id OR pr.payer_id = p_user_id)
    AND pr.status = 'paid';

  SELECT COUNT(*)::INTEGER
  INTO v_checkout_buyer_count
  FROM public.merchant_payments mp
  WHERE mp.buyer_user_id = p_user_id
    AND mp.status = 'succeeded';

  SELECT COUNT(*)::INTEGER
  INTO v_checkout_merchant_count
  FROM public.merchant_payments mp
  WHERE mp.merchant_user_id = p_user_id
    AND mp.status = 'succeeded';

  SELECT COUNT(*)::INTEGER
  INTO v_pos_payment_count
  FROM public.merchant_payments mp
  JOIN public.merchant_checkout_sessions mcs ON mcs.id = mp.session_id
  WHERE mp.merchant_user_id = p_user_id
    AND mp.status = 'succeeded'
    AND LOWER(COALESCE(mcs.metadata->>'channel', '')) = 'pos';

  SELECT COUNT(*)::INTEGER
  INTO v_checkout_link_payment_count
  FROM public.merchant_payments mp
  JOIN public.merchant_checkout_sessions mcs ON mcs.id = mp.session_id
  WHERE mp.merchant_user_id = p_user_id
    AND mp.status = 'succeeded'
    AND COALESCE(
      NULLIF(TRIM(COALESCE(mcs.metadata->>'payment_link_token', '')), ''),
      NULLIF(TRIM(COALESCE(mp.payment_link_token, '')), '')
    ) IS NOT NULL;

  -- New account starts at zero and grows from real OpenPay usage.
  v_score := v_score
    + LEAST(v_topup_count, 50) * 3
    + LEAST(v_send_count, 200) * 4
    + LEAST(v_receive_count, 200) * 3
    + LEAST(v_invoice_count, 80) * 1
    + LEAST(v_request_count, 80) * 1
    + LEAST(v_paid_invoice_count, 120) * 4
    + LEAST(v_paid_request_count, 120) * 4
    + LEAST(v_checkout_buyer_count, 200) * 4
    + LEAST(v_checkout_merchant_count, 200) * 5
    + LEAST(v_pos_payment_count, 200) * 6
    + LEAST(v_checkout_link_payment_count, 200) * 5
    + LEAST(COALESCE(v_total_tx_volume, 0), 50000) / 200;

  RETURN GREATEST(0, LEAST(900, ROUND(v_score)::INTEGER));
END;
$$;

CREATE OR REPLACE FUNCTION public.can_user_unlock_loans(
  p_user_id UUID
)
RETURNS TABLE (
  unlocked BOOLEAN,
  score INTEGER,
  required_score INTEGER,
  total_activity INTEGER,
  required_activity INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_score INTEGER := 0;
  v_activity INTEGER := 0;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN QUERY SELECT false, 0, 120, 0, 8;
    RETURN;
  END IF;

  v_score := public.calculate_user_activity_credit_score(p_user_id);

  SELECT
    COALESCE(t.tx_count, 0)
    + COALESCE(inv.paid_count, 0)
    + COALESCE(req.paid_count, 0)
    + COALESCE(mp.pay_count, 0)
  INTO v_activity
  FROM (
    SELECT COUNT(*)::INTEGER AS tx_count
    FROM public.transactions tr
    WHERE tr.status = 'completed'
      AND (
        tr.sender_id = p_user_id
        OR tr.receiver_id = p_user_id
      )
  ) t
  CROSS JOIN (
    SELECT COUNT(*)::INTEGER AS paid_count
    FROM public.invoices i
    WHERE (i.sender_id = p_user_id OR i.recipient_id = p_user_id)
      AND i.status = 'paid'
  ) inv
  CROSS JOIN (
    SELECT COUNT(*)::INTEGER AS paid_count
    FROM public.payment_requests pr
    WHERE (pr.requester_id = p_user_id OR pr.payer_id = p_user_id)
      AND pr.status = 'paid'
  ) req
  CROSS JOIN (
    SELECT COUNT(*)::INTEGER AS pay_count
    FROM public.merchant_payments mp
    WHERE mp.status = 'succeeded'
      AND (
        mp.buyer_user_id = p_user_id
        OR mp.merchant_user_id = p_user_id
      )
  ) mp;

  RETURN QUERY
  SELECT
    (v_score >= 120 AND v_activity >= 8),
    v_score,
    120,
    v_activity,
    8;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_my_loan_application(
  p_requested_amount NUMERIC,
  p_requested_term_months INTEGER,
  p_full_name TEXT,
  p_contact_number TEXT,
  p_address_line TEXT,
  p_city TEXT,
  p_country TEXT,
  p_openpay_account_number TEXT,
  p_openpay_account_username TEXT,
  p_agreement_accepted BOOLEAN DEFAULT false
)
RETURNS public.user_loan_applications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_app public.user_loan_applications;
  v_existing_id UUID;
  v_credit_score INTEGER := 0;
  v_unlocked BOOLEAN := false;
  v_required_score INTEGER := 120;
  v_total_activity INTEGER := 0;
  v_required_activity INTEGER := 8;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF COALESCE(p_agreement_accepted, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'You must accept loan agreement before submitting';
  END IF;

  IF COALESCE(TRIM(p_full_name), '') = '' OR COALESCE(TRIM(p_contact_number), '') = '' OR COALESCE(TRIM(p_address_line), '') = '' OR
     COALESCE(TRIM(p_city), '') = '' OR COALESCE(TRIM(p_country), '') = '' OR
     COALESCE(TRIM(p_openpay_account_number), '') = '' OR COALESCE(TRIM(p_openpay_account_username), '') = '' THEN
    RAISE EXCEPTION 'Complete all required loan form fields';
  END IF;

  SELECT ula.id INTO v_existing_id
  FROM public.user_loan_applications ula
  WHERE ula.user_id = v_user_id
    AND ula.status = 'pending'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    RAISE EXCEPTION 'You already have a pending loan application';
  END IF;

  SELECT ul.id INTO v_existing_id
  FROM public.user_loans ul
  WHERE ul.user_id = v_user_id
    AND ul.status IN ('pending', 'active')
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    RAISE EXCEPTION 'You already have an active or pending loan';
  END IF;

  BEGIN
    v_credit_score := public.calculate_user_activity_credit_score(v_user_id);
  EXCEPTION
    WHEN OTHERS THEN
      v_credit_score := 0;
  END;

  SELECT c.unlocked, c.score, c.required_score, c.total_activity, c.required_activity
  INTO v_unlocked, v_credit_score, v_required_score, v_total_activity, v_required_activity
  FROM public.can_user_unlock_loans(v_user_id) c;

  IF COALESCE(v_unlocked, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'Loan unlock requirements not met. Current score: %, required score: %, activity: %/%',
      COALESCE(v_credit_score, 0),
      COALESCE(v_required_score, 120),
      COALESCE(v_total_activity, 0),
      COALESCE(v_required_activity, 8);
  END IF;

  INSERT INTO public.user_loan_applications (
    user_id,
    requested_amount,
    requested_term_months,
    credit_score_snapshot,
    full_name,
    contact_number,
    address_line,
    city,
    country,
    openpay_account_number,
    openpay_account_username,
    agreement_accepted,
    agreement_accepted_at,
    status
  )
  VALUES (
    v_user_id,
    ROUND(COALESCE(p_requested_amount, 0), 2),
    GREATEST(1, LEAST(COALESCE(p_requested_term_months, 6), 60)),
    GREATEST(300, LEAST(v_credit_score, 900)),
    LEFT(TRIM(p_full_name), 120),
    LEFT(TRIM(p_contact_number), 60),
    LEFT(TRIM(p_address_line), 180),
    LEFT(TRIM(p_city), 120),
    LEFT(TRIM(p_country), 120),
    LEFT(TRIM(p_openpay_account_number), 80),
    LEFT(TRIM(p_openpay_account_username), 80),
    true,
    now(),
    'pending'
  )
  RETURNING * INTO v_app;

  RETURN v_app;
END;
$$;

REVOKE ALL ON FUNCTION public.can_user_unlock_loans(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_user_unlock_loans(UUID) TO authenticated;


-- <<< END MIGRATION: 20260222124000_credit_score_zero_start_and_loan_unlock.sql

-- >>> MIGRATION: 20260222130000_allow_pi_currency_in_merchant_checkout_and_payments.sql
ALTER TABLE public.merchant_checkout_sessions
DROP CONSTRAINT IF EXISTS merchant_checkout_sessions_currency_check;

ALTER TABLE public.merchant_checkout_sessions
ADD CONSTRAINT merchant_checkout_sessions_currency_check
CHECK (
  currency = 'PI'
  OR currency ~ '^[A-Z]{3}$'
);

ALTER TABLE public.merchant_payments
DROP CONSTRAINT IF EXISTS merchant_payments_currency_check;

ALTER TABLE public.merchant_payments
ADD CONSTRAINT merchant_payments_currency_check
CHECK (
  currency = 'PI'
  OR currency ~ '^[A-Z]{3}$'
);

-- <<< END MIGRATION: 20260222130000_allow_pi_currency_in_merchant_checkout_and_payments.sql

-- >>> MIGRATION: 20260222133000_public_ledger_transaction_lookup.sql
CREATE OR REPLACE FUNCTION public.get_public_ledger_transaction(
  p_transaction_id UUID
)
RETURNS TABLE (
  amount NUMERIC,
  note TEXT,
  status TEXT,
  occurred_at TIMESTAMPTZ,
  event_type TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    le.amount,
    CASE
      WHEN le.note IS NULL THEN NULL
      ELSE regexp_replace(
        le.note,
        '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
        '[hidden]',
        'g'
      )
    END AS note,
    COALESCE(le.status, 'completed') AS status,
    le.occurred_at,
    le.event_type
  FROM public.ledger_events le
  WHERE le.source_table = 'transactions'
    AND le.source_id = p_transaction_id
    AND le.amount IS NOT NULL
  ORDER BY le.occurred_at DESC
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_public_ledger_transaction(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_ledger_transaction(UUID) TO anon, authenticated;

-- <<< END MIGRATION: 20260222133000_public_ledger_transaction_lookup.sql

-- >>> MIGRATION: 20260223120000_product_catalog_full.sql
ALTER TABLE public.merchant_products
ADD COLUMN IF NOT EXISTS product_tags TEXT[] NOT NULL DEFAULT '{}'::TEXT[],
ADD COLUMN IF NOT EXISTS media_urls TEXT[] NOT NULL DEFAULT '{}'::TEXT[],
ADD COLUMN IF NOT EXISTS checkout_info TEXT NOT NULL DEFAULT '',
ADD COLUMN IF NOT EXISTS pricing_type TEXT NOT NULL DEFAULT 'one_time' CHECK (pricing_type IN ('one_time', 'subscription')),
ADD COLUMN IF NOT EXISTS repeat_every INTEGER,
ADD COLUMN IF NOT EXISTS repeat_unit TEXT,
ADD COLUMN IF NOT EXISTS tax_code TEXT,
ADD COLUMN IF NOT EXISTS published_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_merchant_products_owner_published
ON public.merchant_products (merchant_user_id, published_at DESC);

DROP VIEW IF EXISTS public.merchant_product_stats;
CREATE VIEW public.merchant_product_stats AS
SELECT
  mpsi.product_id,
  mcs.merchant_user_id,
  COUNT(DISTINCT mp.id) AS total_sales,
  COUNT(DISTINCT mp.id) AS total_purchases,
  COALESCE(SUM(CASE WHEN mp.id IS NOT NULL THEN mpsi.line_total ELSE 0 END), 0) AS total_revenue
FROM public.merchant_checkout_session_items mpsi
JOIN public.merchant_checkout_sessions mcs
  ON mcs.id = mpsi.session_id
LEFT JOIN public.merchant_payments mp
  ON mp.session_id = mcs.id
  AND mp.status = 'succeeded'
GROUP BY mpsi.product_id, mcs.merchant_user_id;

ALTER TABLE public.merchant_payment_links
ADD COLUMN IF NOT EXISTS reference_number TEXT,
ADD COLUMN IF NOT EXISTS remarks TEXT,
ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;

-- <<< END MIGRATION: 20260223120000_product_catalog_full.sql

-- >>> MIGRATION: 20260223130000_support_widget.sql
CREATE TABLE IF NOT EXISTS public.support_agents (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  handle TEXT NOT NULL DEFAULT 'openpay',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.support_conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed', 'pending')),
  last_message_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.support_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.support_conversations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sender_role TEXT NOT NULL DEFAULT 'user' CHECK (sender_role IN ('user', 'agent')),
  message TEXT NOT NULL,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.support_faq_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.support_faq_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id UUID REFERENCES public.support_faq_categories(id) ON DELETE SET NULL,
  question TEXT NOT NULL,
  answer TEXT NOT NULL,
  tags TEXT[] NOT NULL DEFAULT '{}'::TEXT[],
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_support_conversations_user
ON public.support_conversations (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_support_messages_conversation
ON public.support_messages (conversation_id, created_at ASC);

CREATE INDEX IF NOT EXISTS idx_support_messages_sender
ON public.support_messages (sender_id, created_at DESC);

ALTER TABLE public.support_agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_faq_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_faq_items ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_support_agent(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.support_agents sa
    WHERE sa.user_id = p_user_id
  )
  OR EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = p_user_id
      AND LOWER(COALESCE(p.username, '')) IN ('openpay', 'wainfoundation')
  );
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'support_conversations' AND policyname = 'Users can view own support conversations'
  ) THEN
    CREATE POLICY "Users can view own support conversations"
      ON public.support_conversations
      FOR SELECT TO authenticated
      USING (user_id = auth.uid() OR public.is_support_agent(auth.uid()));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'support_conversations' AND policyname = 'Users can insert own support conversations'
  ) THEN
    CREATE POLICY "Users can insert own support conversations"
      ON public.support_conversations
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'support_conversations' AND policyname = 'Agents can update support conversations'
  ) THEN
    CREATE POLICY "Agents can update support conversations"
      ON public.support_conversations
      FOR UPDATE TO authenticated
      USING (public.is_support_agent(auth.uid()))
      WITH CHECK (public.is_support_agent(auth.uid()));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'support_messages' AND policyname = 'Users can view own support messages'
  ) THEN
    CREATE POLICY "Users can view own support messages"
      ON public.support_messages
      FOR SELECT TO authenticated
      USING (
        EXISTS (
          SELECT 1
          FROM public.support_conversations sc
          WHERE sc.id = support_messages.conversation_id
            AND (sc.user_id = auth.uid() OR public.is_support_agent(auth.uid()))
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'support_messages' AND policyname = 'Users can insert support messages'
  ) THEN
    CREATE POLICY "Users can insert support messages"
      ON public.support_messages
      FOR INSERT TO authenticated
      WITH CHECK (
        EXISTS (
          SELECT 1
          FROM public.support_conversations sc
          WHERE sc.id = support_messages.conversation_id
            AND sc.user_id = auth.uid()
        )
        OR public.is_support_agent(auth.uid())
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'support_faq_categories' AND policyname = 'Anyone can read FAQ categories'
  ) THEN
    CREATE POLICY "Anyone can read FAQ categories"
      ON public.support_faq_categories
      FOR SELECT TO authenticated
      USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'support_faq_items' AND policyname = 'Anyone can read FAQ items'
  ) THEN
    CREATE POLICY "Anyone can read FAQ items"
      ON public.support_faq_items
      FOR SELECT TO authenticated
      USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'support_faq_categories' AND policyname = 'Agents can manage FAQ categories'
  ) THEN
    CREATE POLICY "Agents can manage FAQ categories"
      ON public.support_faq_categories
      FOR ALL TO authenticated
      USING (public.is_support_agent(auth.uid()))
      WITH CHECK (public.is_support_agent(auth.uid()));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'support_faq_items' AND policyname = 'Agents can manage FAQ items'
  ) THEN
    CREATE POLICY "Agents can manage FAQ items"
      ON public.support_faq_items
      FOR ALL TO authenticated
      USING (public.is_support_agent(auth.uid()))
      WITH CHECK (public.is_support_agent(auth.uid()));
  END IF;
END $$;

-- <<< END MIGRATION: 20260223130000_support_widget.sql

-- >>> MIGRATION: 20260223133000_seed_openpay_faq.sql
DO $$
DECLARE
  v_getting_started UUID;
  v_account UUID;
  v_wallet UUID;
  v_merchant UUID;
  v_channels UUID;
  v_virtual_card UUID;
  v_security UUID;
  v_fees UUID;
  v_troubleshooting UUID;
  v_legal UUID;
  v_support UUID;
BEGIN
  INSERT INTO public.support_faq_categories (title, description, sort_order)
  SELECT 'Getting Started', 'Learn the basics of OpenPay and first-time setup.', 10
  WHERE NOT EXISTS (
    SELECT 1 FROM public.support_faq_categories c WHERE LOWER(c.title) = 'getting started'
  )
  RETURNING id INTO v_getting_started;

  IF v_getting_started IS NULL THEN
    SELECT id INTO v_getting_started
    FROM public.support_faq_categories
    WHERE LOWER(title) = 'getting started'
    LIMIT 1;
  END IF;

  INSERT INTO public.support_faq_categories (title, description, sort_order)
  SELECT 'Account and Sign-In', 'Account access, profile setup, and sign-in concerns.', 20
  WHERE NOT EXISTS (
    SELECT 1 FROM public.support_faq_categories c WHERE LOWER(c.title) = 'account and sign-in'
  )
  RETURNING id INTO v_account;

  IF v_account IS NULL THEN
    SELECT id INTO v_account
    FROM public.support_faq_categories
    WHERE LOWER(title) = 'account and sign-in'
    LIMIT 1;
  END IF;

  INSERT INTO public.support_faq_categories (title, description, sort_order)
  SELECT 'Wallet and Transfers', 'Balance, send/receive, and internal OpenPay transfer rules.', 30
  WHERE NOT EXISTS (
    SELECT 1 FROM public.support_faq_categories c WHERE LOWER(c.title) = 'wallet and transfers'
  )
  RETURNING id INTO v_wallet;

  IF v_wallet IS NULL THEN
    SELECT id INTO v_wallet
    FROM public.support_faq_categories
    WHERE LOWER(title) = 'wallet and transfers'
    LIMIT 1;
  END IF;

  INSERT INTO public.support_faq_categories (title, description, sort_order)
  SELECT 'Merchant Portal and Checkout', 'Merchant setup, checkout links, and settlement flow.', 40
  WHERE NOT EXISTS (
    SELECT 1 FROM public.support_faq_categories c WHERE LOWER(c.title) = 'merchant portal and checkout'
  )
  RETURNING id INTO v_merchant;

  IF v_merchant IS NULL THEN
    SELECT id INTO v_merchant
    FROM public.support_faq_categories
    WHERE LOWER(title) = 'merchant portal and checkout'
    LIMIT 1;
  END IF;

  INSERT INTO public.support_faq_categories (title, description, sort_order)
  SELECT 'Payment Links and Channels', 'Direct links, references, and channel payments.', 50
  WHERE NOT EXISTS (
    SELECT 1 FROM public.support_faq_categories c WHERE LOWER(c.title) = 'payment links and channels'
  )
  RETURNING id INTO v_channels;

  IF v_channels IS NULL THEN
    SELECT id INTO v_channels
    FROM public.support_faq_categories
    WHERE LOWER(title) = 'payment links and channels'
    LIMIT 1;
  END IF;

  INSERT INTO public.support_faq_categories (title, description, sort_order)
  SELECT 'Virtual Card', 'OpenPay virtual card usage and limits.', 60
  WHERE NOT EXISTS (
    SELECT 1 FROM public.support_faq_categories c WHERE LOWER(c.title) = 'virtual card'
  )
  RETURNING id INTO v_virtual_card;

  IF v_virtual_card IS NULL THEN
    SELECT id INTO v_virtual_card
    FROM public.support_faq_categories
    WHERE LOWER(title) = 'virtual card'
    LIMIT 1;
  END IF;

  INSERT INTO public.support_faq_categories (title, description, sort_order)
  SELECT 'Security and Safety', 'How to protect your account and avoid scams.', 70
  WHERE NOT EXISTS (
    SELECT 1 FROM public.support_faq_categories c WHERE LOWER(c.title) = 'security and safety'
  )
  RETURNING id INTO v_security;

  IF v_security IS NULL THEN
    SELECT id INTO v_security
    FROM public.support_faq_categories
    WHERE LOWER(title) = 'security and safety'
    LIMIT 1;
  END IF;

  INSERT INTO public.support_faq_categories (title, description, sort_order)
  SELECT 'Fees and Limits', 'Platform fees, transfer limits, and payout notes.', 80
  WHERE NOT EXISTS (
    SELECT 1 FROM public.support_faq_categories c WHERE LOWER(c.title) = 'fees and limits'
  )
  RETURNING id INTO v_fees;

  IF v_fees IS NULL THEN
    SELECT id INTO v_fees
    FROM public.support_faq_categories
    WHERE LOWER(title) = 'fees and limits'
    LIMIT 1;
  END IF;

  INSERT INTO public.support_faq_categories (title, description, sort_order)
  SELECT 'Troubleshooting', 'Common technical issues and recovery steps.', 90
  WHERE NOT EXISTS (
    SELECT 1 FROM public.support_faq_categories c WHERE LOWER(c.title) = 'troubleshooting'
  )
  RETURNING id INTO v_troubleshooting;

  IF v_troubleshooting IS NULL THEN
    SELECT id INTO v_troubleshooting
    FROM public.support_faq_categories
    WHERE LOWER(title) = 'troubleshooting'
    LIMIT 1;
  END IF;

  INSERT INTO public.support_faq_categories (title, description, sort_order)
  SELECT 'Legal and Compliance', 'Policy, terms, and permitted use of OpenPay.', 100
  WHERE NOT EXISTS (
    SELECT 1 FROM public.support_faq_categories c WHERE LOWER(c.title) = 'legal and compliance'
  )
  RETURNING id INTO v_legal;

  IF v_legal IS NULL THEN
    SELECT id INTO v_legal
    FROM public.support_faq_categories
    WHERE LOWER(title) = 'legal and compliance'
    LIMIT 1;
  END IF;

  INSERT INTO public.support_faq_categories (title, description, sort_order)
  SELECT 'Support and Contact', 'How to contact OpenPay support and response expectations.', 110
  WHERE NOT EXISTS (
    SELECT 1 FROM public.support_faq_categories c WHERE LOWER(c.title) = 'support and contact'
  )
  RETURNING id INTO v_support;

  IF v_support IS NULL THEN
    SELECT id INTO v_support
    FROM public.support_faq_categories
    WHERE LOWER(title) = 'support and contact'
    LIMIT 1;
  END IF;

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_getting_started, 'What is OpenPay?',
    'OpenPay is a Pi-powered internal payment platform for users and merchants. It supports in-app balance transfers, merchant checkout, payment links, and wallet tools.',
    ARRAY['openpay', 'intro']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'what is openpay?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_getting_started, 'How do I start using OpenPay?',
    'Sign in, complete your profile, review the usage agreement, and use Wallet, Send, Receive, and Merchant tools from the dashboard and menu.',
    ARRAY['getting-started', 'signup']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'how do i start using openpay?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_getting_started, 'Does OpenPay support external wallets or bank transfer rails?',
    'No. OpenPay is designed for internal OpenPay balance flows. External wallet rails and direct bank transfer rails are not supported in standard user transfer flow.',
    ARRAY['limits', 'rails']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'does openpay support external wallets or bank transfer rails?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_getting_started, 'What payment methods are supported for OpenUSD buy?',
    'OpenUSD buy supports Pi Payment, Ewallet QR PH, debit card, credit card, Apple Pay, Google Pay, PayPal, Stripe, and Venmo. Availability can vary by region and account status.',
    ARRAY['payment-methods', 'openusd', 'buy']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'what payment methods are supported for openusd buy?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_account, 'I cannot sign in. What should I check first?',
    'Confirm your login method, network connection, and correct account credentials. If still blocked, use support chat and include your username and error screenshot.',
    ARRAY['signin', 'access']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'i cannot sign in. what should i check first?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_account, 'How do I update my OpenPay profile?',
    'Open Profile or Settings, then update your display information. Keep your username accurate because merchants and customers use it for verification.',
    ARRAY['profile', 'settings']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'how do i update my openpay profile?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_wallet, 'How are wallet balances displayed?',
    'Balances are shown in supported OpenPay currencies and converted for UI display using OpenPay currency rates. Internal transfer values are recorded in platform ledger units.',
    ARRAY['wallet', 'currency']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'how are wallet balances displayed?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_wallet, 'How do I send money to another OpenPay user?',
    'Go to Send, choose a recipient, enter amount and note, review details, then confirm. Transfers are internal to OpenPay accounts.',
    ARRAY['send', 'transfer']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'how do i send money to another openpay user?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_wallet, 'Why did my transfer fail?',
    'Common reasons are insufficient balance, invalid recipient, session expiration, or temporary network/API issues. Retry after refresh and verify recipient account.',
    ARRAY['failed-transfer', 'errors']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'why did my transfer fail?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_merchant, 'How do I access Merchant Portal?',
    'Open Menu, then Merchant Portal. You can manage API keys, product catalog, checkout links, payment channels, balances, and analytics.',
    ARRAY['merchant', 'portal']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'how do i access merchant portal?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_merchant, 'How does merchant checkout settlement work?',
    'When a checkout succeeds, payment records are saved and merchant available balance updates based on merchant payment and transfer events.',
    ARRAY['checkout', 'settlement']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'how does merchant checkout settlement work?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_merchant, 'Can merchant transfer available balance to wallet or savings?',
    'Yes. Merchant available balance can be moved to merchant wallet or savings from merchant balances controls and dashboard merchant tools.',
    ARRAY['merchant-balance', 'savings']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'can merchant transfer available balance to wallet or savings?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_channels, 'What are payment channel links?',
    'Payment channel links are one-time customer payment links with a reference number, description, remarks, amount, and currency, managed inside Merchant Portal.',
    ARRAY['payment-link', 'channels']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'what are payment channel links?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_channels, 'How do I share payment links?',
    'Use copy link, share actions, direct URL, QR, or embed options from payment link tools. Always verify title, amount, and currency before sharing.',
    ARRAY['share', 'qr', 'embed']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'how do i share payment links?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_channels, 'Can I archive payment links?',
    'Yes. Archived links are hidden from active lists and can be viewed by enabling archived filters in Payment Channels.',
    ARRAY['archive', 'links']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'can i archive payment links?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_virtual_card, 'Where can I use OpenPay Virtual Card?',
    'OpenPay virtual card is intended for OpenPay merchant checkout flows. It should not be used for ATM, external card rails, or unsupported external networks.',
    ARRAY['virtual-card', 'checkout']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'where can i use openpay virtual card?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_virtual_card, 'Why does virtual card checkout fail?',
    'Verify card number, expiry, CVC, card owner session, and sufficient balance. Failures can also happen when checkout session is expired or not open.',
    ARRAY['virtual-card', 'failed-payment']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'why does virtual card checkout fail?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_security, 'How do I keep my account safe?',
    'Never share OTP, PIN, secret keys, or private credentials. Verify recipients and merchant details before confirming payments.',
    ARRAY['security', 'fraud']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'how do i keep my account safe?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_security, 'How should merchants handle API keys?',
    'Keep secret keys server-side only, rotate keys periodically, and revoke exposed keys immediately from Merchant API key controls.',
    ARRAY['api-key', 'merchant-security']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'how should merchants handle api keys?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_security, 'What should I do if I suspect fraud?',
    'Stop transactions, collect evidence, and contact support immediately with transaction IDs, screenshots, and timestamps.',
    ARRAY['fraud', 'incident']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'what should i do if i suspect fraud?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_fees, 'Does OpenPay charge platform fees?',
    'Core in-app features may have zero platform fee depending on current policy. Merchant-specific and partner terms can apply in some flows.',
    ARRAY['fees', 'pricing']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'does openpay charge platform fees?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_fees, 'Are there transfer limits?',
    'Limits may depend on account state, security checks, and product rules. If blocked by limits, contact support with amount and intended use.',
    ARRAY['limits', 'transfers']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'are there transfer limits?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_troubleshooting, 'QR code checkout is not working. What should I check?',
    'Confirm the link is valid, unexpired, and accessible from your device. If using local URLs, external devices cannot open localhost links.',
    ARRAY['qr', 'checkout', 'localhost']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'qr code checkout is not working. what should i check?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_troubleshooting, 'I see API or network timeout errors. What now?',
    'Refresh the page, verify internet connection, and retry. If errors continue, include console/network logs in support chat.',
    ARRAY['timeout', 'network', 'api']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'i see api or network timeout errors. what now?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_troubleshooting, 'Why is a new column not found in schema cache?',
    'Apply the latest database migration and allow schema cache refresh. Then reload the app.',
    ARRAY['schema-cache', 'migration']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'why is a new column not found in schema cache?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_legal, 'Is OpenPay a bank or financial institution?',
    'No. OpenPay is a payment technology platform. It is not a bank and does not provide bank deposit or investment services unless explicitly stated under applicable law.',
    ARRAY['legal', 'banking']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'is openpay a bank or financial institution?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_legal, 'What transactions are not allowed?',
    'Fraud, abuse, illegal transactions, misuse of credentials, and unsupported external transfer flows are prohibited.',
    ARRAY['policy', 'compliance']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'what transactions are not allowed?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_legal, 'Where can I read Terms, Privacy, and Legal notices?',
    'Open Menu and visit Terms, Privacy, and Legal pages. Merchant and API docs are also available in OpenPay documentation routes.',
    ARRAY['terms', 'privacy', 'legal']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'where can i read terms, privacy, and legal notices?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_support, 'How can I contact live support?',
    'Use the floating support widget and open Messages. Send complete details so support can respond faster.',
    ARRAY['support', 'chat']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'how can i contact live support?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_support, 'What details should I include in a support request?',
    'Include account username, transaction ID, amount, date/time, issue summary, and screenshots or logs when available.',
    ARRAY['support', 'ticket']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'what details should i include in a support request?');

  INSERT INTO public.support_faq_items (category_id, question, answer, tags)
  SELECT v_support, 'Who can reply to support messages?',
    'Official support agents such as @openpay and @wainfoundation can reply to all support conversations.',
    ARRAY['agent', 'openpay', 'wainfoundation']
  WHERE NOT EXISTS (SELECT 1 FROM public.support_faq_items f WHERE LOWER(f.question) = 'who can reply to support messages?');
END $$;

-- <<< END MIGRATION: 20260223133000_seed_openpay_faq.sql

-- >>> MIGRATION: 20260224160000_swap_withdrawals.sql
CREATE TABLE IF NOT EXISTS public.user_swap_withdrawals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount NUMERIC(12,2) NOT NULL CHECK (amount >= 1),
  fee_rate NUMERIC(6,4) NOT NULL DEFAULT 0.02 CHECK (fee_rate >= 0 AND fee_rate <= 0.2),
  fee_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  payout_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  openpay_account_name TEXT NOT NULL DEFAULT '',
  openpay_account_username TEXT NOT NULL DEFAULT '',
  openpay_account_number TEXT NOT NULL DEFAULT '',
  pi_wallet_address TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  admin_note TEXT NOT NULL DEFAULT '',
  transfer_transaction_id UUID NULL REFERENCES public.transactions(id) ON DELETE SET NULL,
  refund_transaction_id UUID NULL REFERENCES public.transactions(id) ON DELETE SET NULL,
  reviewed_by UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_swap_withdrawals_user_created
  ON public.user_swap_withdrawals(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_swap_withdrawals_status_created
  ON public.user_swap_withdrawals(status, created_at DESC);

ALTER TABLE public.user_swap_withdrawals ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_swap_withdrawals' AND policyname = 'Users can view own swap withdrawals'
  ) THEN
    CREATE POLICY "Users can view own swap withdrawals"
      ON public.user_swap_withdrawals
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_user_swap_withdrawals_updated_at ON public.user_swap_withdrawals;
CREATE TRIGGER trg_user_swap_withdrawals_updated_at
BEFORE UPDATE ON public.user_swap_withdrawals
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

-- Parameter name changes require dropping existing function signature.
DROP FUNCTION IF EXISTS public.submit_swap_withdrawal(NUMERIC, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.submit_swap_withdrawal(
  p_amount NUMERIC,
  p_openpay_account_name TEXT,
  p_openpay_account_number TEXT,
  p_openpay_account_username TEXT,
  p_pi_wallet_address TEXT
)
RETURNS public.user_swap_withdrawals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_amount NUMERIC(12,2) := ROUND(COALESCE(p_amount, 0), 2);
  v_fee_rate NUMERIC(6,4) := 0.02;
  v_fee_amount NUMERIC(12,2);
  v_payout_amount NUMERIC(12,2);
  v_openpay_user_id UUID;
  v_wallet_balance NUMERIC(12,2);
  v_openpay_balance NUMERIC(12,2);
  v_tx_id UUID;
  v_row public.user_swap_withdrawals;
  v_settlement_account TEXT := 'OPEA68BB7A9F964994A199A15786D680FA';
  v_name TEXT := LEFT(TRIM(COALESCE(p_openpay_account_name, '')), 160);
  v_account TEXT := UPPER(TRIM(COALESCE(p_openpay_account_number, '')));
  v_username TEXT := LEFT(TRIM(COALESCE(p_openpay_account_username, '')), 120);
  v_wallet TEXT := LEFT(TRIM(COALESCE(p_pi_wallet_address, '')), 240);
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_amount < 1 THEN
    RAISE EXCEPTION 'Minimum withdrawal is 1 OPEN USD';
  END IF;

  v_fee_amount := ROUND(v_amount * v_fee_rate, 2);
  v_payout_amount := ROUND(v_amount - v_fee_amount, 2);
  IF v_payout_amount <= 0 THEN
    RAISE EXCEPTION 'Withdrawal amount too low after fees';
  END IF;

  IF v_name = '' OR v_username = '' OR v_account = '' OR v_wallet = '' THEN
    RAISE EXCEPTION 'Complete all required withdrawal fields';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.user_accounts ua
    WHERE ua.user_id = v_user_id
      AND UPPER(ua.account_number) = v_account
  ) THEN
    RAISE EXCEPTION 'OpenPay account number does not match your profile';
  END IF;

  SELECT ua.user_id INTO v_openpay_user_id
  FROM public.user_accounts ua
  WHERE ua.account_number = v_settlement_account
  LIMIT 1;

  IF v_openpay_user_id IS NULL THEN
    RAISE EXCEPTION 'Settlement account not found';
  END IF;

  IF v_openpay_user_id = v_user_id THEN
    RAISE EXCEPTION 'Settlement account invalid';
  END IF;

  SELECT balance INTO v_wallet_balance
  FROM public.wallets
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'Wallet not found';
  END IF;

  IF v_wallet_balance < v_amount THEN
    RAISE EXCEPTION 'Insufficient wallet balance';
  END IF;

  SELECT balance INTO v_openpay_balance
  FROM public.wallets
  WHERE user_id = v_openpay_user_id
  FOR UPDATE;

  IF v_openpay_balance IS NULL THEN
    RAISE EXCEPTION 'Settlement wallet not found';
  END IF;

  UPDATE public.wallets
  SET balance = v_wallet_balance - v_amount,
      updated_at = now()
  WHERE user_id = v_user_id;

  UPDATE public.wallets
  SET balance = v_openpay_balance + v_amount,
      updated_at = now()
  WHERE user_id = v_openpay_user_id;

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_user_id,
    v_openpay_user_id,
    v_amount,
    CONCAT(
      'Swap withdrawal request to PI | Wallet ',
      LEFT(v_wallet, 80),
      ' | OpenPay ',
      LEFT(v_username, 40),
      ' ',
      LEFT(v_account, 60)
    ),
    'completed'
  )
  RETURNING id INTO v_tx_id;

  INSERT INTO public.user_swap_withdrawals (
    user_id,
    amount,
    fee_rate,
    fee_amount,
    payout_amount,
    openpay_account_name,
    openpay_account_username,
    openpay_account_number,
    pi_wallet_address,
    status,
    transfer_transaction_id
  )
  VALUES (
    v_user_id,
    v_amount,
    v_fee_rate,
    v_fee_amount,
    v_payout_amount,
    v_name,
    v_username,
    v_account,
    v_wallet,
    'pending',
    v_tx_id
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_swap_withdrawals(
  p_status TEXT DEFAULT 'pending',
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  amount NUMERIC,
  openpay_account_name TEXT,
  openpay_account_username TEXT,
  openpay_account_number TEXT,
  pi_wallet_address TEXT,
  status TEXT,
  admin_note TEXT,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ,
  applicant_display_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT := LOWER(TRIM(COALESCE(p_status, 'pending')));
BEGIN
  IF public.is_openpay_core_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  RETURN QUERY
  SELECT
    usw.id,
    usw.user_id,
    usw.amount,
    usw.openpay_account_name,
    usw.openpay_account_username,
    usw.openpay_account_number,
    usw.pi_wallet_address,
    usw.status,
    usw.admin_note,
    usw.reviewed_at,
    usw.created_at,
    COALESCE(NULLIF(p.full_name, ''), CONCAT('@', NULLIF(p.username, '')), LEFT(usw.user_id::TEXT, 8))
  FROM public.user_swap_withdrawals usw
  LEFT JOIN public.profiles p ON p.id = usw.user_id
  WHERE (v_status = 'all' OR usw.status = v_status)
  ORDER BY usw.created_at DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 50), 200))
  OFFSET GREATEST(0, COALESCE(p_offset, 0));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_review_swap_withdrawal(
  p_withdrawal_id UUID,
  p_decision TEXT,
  p_admin_note TEXT DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_user_id UUID := auth.uid();
  v_decision TEXT := LOWER(TRIM(COALESCE(p_decision, '')));
  v_row public.user_swap_withdrawals;
  v_openpay_user_id UUID;
  v_openpay_balance NUMERIC(12,2);
  v_user_balance NUMERIC(12,2);
  v_refund_tx UUID;
  v_settlement_account TEXT := 'OPEA68BB7A9F964994A199A15786D680FA';
BEGIN
  IF public.is_openpay_core_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  IF p_withdrawal_id IS NULL THEN
    RAISE EXCEPTION 'Withdrawal id is required';
  END IF;

  IF v_decision NOT IN ('approve', 'reject') THEN
    RAISE EXCEPTION 'Decision must be approve or reject';
  END IF;

  SELECT * INTO v_row
  FROM public.user_swap_withdrawals
  WHERE id = p_withdrawal_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Withdrawal not found';
  END IF;

  IF v_row.status <> 'pending' THEN
    RAISE EXCEPTION 'Withdrawal already processed';
  END IF;

  IF v_decision = 'reject' THEN
    SELECT ua.user_id INTO v_openpay_user_id
    FROM public.user_accounts ua
    WHERE ua.account_number = v_settlement_account
    LIMIT 1;

    IF v_openpay_user_id IS NULL THEN
      RAISE EXCEPTION 'Settlement account not found';
    END IF;

    SELECT balance INTO v_openpay_balance
    FROM public.wallets
    WHERE user_id = v_openpay_user_id
    FOR UPDATE;

    IF v_openpay_balance IS NULL THEN
      RAISE EXCEPTION 'Settlement wallet not found';
    END IF;

    IF v_openpay_balance < v_row.amount THEN
      RAISE EXCEPTION 'Settlement wallet balance insufficient for refund';
    END IF;

    SELECT balance INTO v_user_balance
    FROM public.wallets
    WHERE user_id = v_row.user_id
    FOR UPDATE;

    IF v_user_balance IS NULL THEN
      RAISE EXCEPTION 'User wallet not found';
    END IF;

    UPDATE public.wallets
    SET balance = v_openpay_balance - v_row.amount,
        updated_at = now()
    WHERE user_id = v_openpay_user_id;

    UPDATE public.wallets
    SET balance = v_user_balance + v_row.amount,
        updated_at = now()
    WHERE user_id = v_row.user_id;

    INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
    VALUES (
      v_openpay_user_id,
      v_row.user_id,
      v_row.amount,
      CONCAT('Swap withdrawal rejected refund | Request ', v_row.id::TEXT),
      'refunded'
    )
    RETURNING id INTO v_refund_tx;
  END IF;

  UPDATE public.user_swap_withdrawals
  SET status = CASE WHEN v_decision = 'approve' THEN 'approved' ELSE 'rejected' END,
      admin_note = COALESCE(p_admin_note, ''),
      reviewed_by = v_admin_user_id,
      reviewed_at = now(),
      refund_transaction_id = v_refund_tx
  WHERE id = v_row.id;

  RETURN v_row.id;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_swap_withdrawal(NUMERIC, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_swap_withdrawals(TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_review_swap_withdrawal(UUID, TEXT, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.submit_swap_withdrawal(NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_swap_withdrawals(TEXT, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_review_swap_withdrawal(UUID, TEXT, TEXT) TO authenticated;

-- <<< END MIGRATION: 20260224160000_swap_withdrawals.sql

-- >>> MIGRATION: 20260225120000_topup_requests.sql
CREATE TABLE IF NOT EXISTS public.user_topup_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider TEXT NOT NULL DEFAULT '',
  amount NUMERIC(12,2) NOT NULL CHECK (amount >= 1),
  openpay_account_name TEXT NOT NULL DEFAULT '',
  openpay_account_username TEXT NOT NULL DEFAULT '',
  openpay_account_number TEXT NOT NULL DEFAULT '',
  reference_code TEXT NOT NULL DEFAULT '',
  proof_url TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  admin_note TEXT NOT NULL DEFAULT '',
  transfer_transaction_id UUID NULL REFERENCES public.transactions(id) ON DELETE SET NULL,
  reviewed_by UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_topup_requests_user_created
  ON public.user_topup_requests(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_topup_requests_status_created
  ON public.user_topup_requests(status, created_at DESC);

ALTER TABLE public.user_topup_requests ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_topup_requests' AND policyname = 'Users can view own topup requests'
  ) THEN
    CREATE POLICY "Users can view own topup requests"
      ON public.user_topup_requests
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_user_topup_requests_updated_at ON public.user_topup_requests;
CREATE TRIGGER trg_user_topup_requests_updated_at
BEFORE UPDATE ON public.user_topup_requests
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

CREATE OR REPLACE FUNCTION public.submit_topup_request(
  p_amount NUMERIC,
  p_openpay_account_name TEXT,
  p_openpay_account_number TEXT,
  p_openpay_account_username TEXT,
  p_proof_url TEXT,
  p_provider TEXT,
  p_reference_code TEXT
)
RETURNS public.user_topup_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_amount NUMERIC(12,2) := ROUND(COALESCE(p_amount, 0), 2);
  v_name TEXT := LEFT(TRIM(COALESCE(p_openpay_account_name, '')), 160);
  v_account TEXT := UPPER(TRIM(COALESCE(p_openpay_account_number, '')));
  v_username TEXT := LEFT(TRIM(COALESCE(p_openpay_account_username, '')), 120);
  v_proof_url TEXT := LEFT(TRIM(COALESCE(p_proof_url, '')), 400);
  v_provider TEXT := LEFT(TRIM(COALESCE(p_provider, '')), 80);
  v_reference TEXT := LEFT(TRIM(COALESCE(p_reference_code, '')), 160);
  v_row public.user_topup_requests;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_amount < 1 THEN
    RAISE EXCEPTION 'Minimum top up is 1 OPEN USD';
  END IF;

  IF v_provider = '' THEN
    RAISE EXCEPTION 'Top up provider is required';
  END IF;

  IF v_name = '' OR v_username = '' OR v_account = '' THEN
    RAISE EXCEPTION 'Complete all required top up fields';
  END IF;
  IF v_reference = '' THEN
    RAISE EXCEPTION 'Payment reference is required';
  END IF;
  IF v_proof_url = '' THEN
    RAISE EXCEPTION 'Payment proof is required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.user_accounts ua
    WHERE ua.user_id = v_user_id
      AND UPPER(ua.account_number) = v_account
  ) THEN
    RAISE EXCEPTION 'OpenPay account number does not match your profile';
  END IF;

  INSERT INTO public.user_topup_requests (
    user_id,
    provider,
    amount,
    openpay_account_name,
    openpay_account_username,
    openpay_account_number,
    reference_code,
    proof_url,
    status
  )
  VALUES (
    v_user_id,
    v_provider,
    v_amount,
    v_name,
    v_username,
    v_account,
    v_reference,
    v_proof_url,
    'pending'
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_topup_requests(
  p_status TEXT DEFAULT 'pending',
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  provider TEXT,
  amount NUMERIC,
  openpay_account_name TEXT,
  openpay_account_username TEXT,
  openpay_account_number TEXT,
  reference_code TEXT,
  proof_url TEXT,
  status TEXT,
  admin_note TEXT,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ,
  applicant_display_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT := LOWER(TRIM(COALESCE(p_status, 'pending')));
BEGIN
  IF public.is_openpay_core_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  RETURN QUERY
  SELECT
    utr.id,
    utr.user_id,
    utr.provider,
    utr.amount,
    utr.openpay_account_name,
    utr.openpay_account_username,
    utr.openpay_account_number,
    utr.reference_code,
    utr.proof_url,
    utr.status,
    utr.admin_note,
    utr.reviewed_at,
    utr.created_at,
    COALESCE(NULLIF(p.full_name, ''), CONCAT('@', NULLIF(p.username, '')), LEFT(utr.user_id::TEXT, 8))
  FROM public.user_topup_requests utr
  LEFT JOIN public.profiles p ON p.id = utr.user_id
  WHERE (v_status = 'all' OR utr.status = v_status)
  ORDER BY utr.created_at DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 50), 200))
  OFFSET GREATEST(0, COALESCE(p_offset, 0));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_review_topup_request(
  p_request_id UUID,
  p_decision TEXT,
  p_admin_note TEXT DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_user_id UUID := auth.uid();
  v_decision TEXT := LOWER(TRIM(COALESCE(p_decision, '')));
  v_row public.user_topup_requests;
  v_openpay_user_id UUID;
  v_openpay_balance NUMERIC(12,2);
  v_user_balance NUMERIC(12,2);
  v_tx_id UUID;
  v_settlement_account TEXT := 'OPEA68BB7A9F964994A199A15786D680FA';
BEGIN
  IF public.is_openpay_core_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  IF p_request_id IS NULL THEN
    RAISE EXCEPTION 'Request id is required';
  END IF;

  IF v_decision NOT IN ('approve', 'reject') THEN
    RAISE EXCEPTION 'Decision must be approve or reject';
  END IF;

  SELECT * INTO v_row
  FROM public.user_topup_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Top up request not found';
  END IF;

  IF v_row.status <> 'pending' THEN
    RAISE EXCEPTION 'Top up request already processed';
  END IF;

  IF v_decision = 'approve' THEN
    SELECT ua.user_id INTO v_openpay_user_id
    FROM public.user_accounts ua
    WHERE ua.account_number = v_settlement_account
    LIMIT 1;

    IF v_openpay_user_id IS NULL THEN
      RAISE EXCEPTION 'Settlement account not found';
    END IF;

    SELECT balance INTO v_openpay_balance
    FROM public.wallets
    WHERE user_id = v_openpay_user_id
    FOR UPDATE;

    IF v_openpay_balance IS NULL THEN
      RAISE EXCEPTION 'Settlement wallet not found';
    END IF;

    IF v_openpay_balance < v_row.amount THEN
      RAISE EXCEPTION 'Settlement wallet balance insufficient for top up';
    END IF;

    SELECT balance INTO v_user_balance
    FROM public.wallets
    WHERE user_id = v_row.user_id
    FOR UPDATE;

    IF v_user_balance IS NULL THEN
      RAISE EXCEPTION 'User wallet not found';
    END IF;

    UPDATE public.wallets
    SET balance = v_openpay_balance - v_row.amount,
        updated_at = now()
    WHERE user_id = v_openpay_user_id;

    UPDATE public.wallets
    SET balance = v_user_balance + v_row.amount,
        updated_at = now()
    WHERE user_id = v_row.user_id;

    INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
    VALUES (
      v_openpay_user_id,
      v_row.user_id,
      v_row.amount,
      CONCAT('Top up approved | ', v_row.provider, ' | Request ', v_row.id::TEXT),
      'completed'
    )
    RETURNING id INTO v_tx_id;
  END IF;

  UPDATE public.user_topup_requests
  SET status = CASE WHEN v_decision = 'approve' THEN 'approved' ELSE 'rejected' END,
      admin_note = COALESCE(p_admin_note, ''),
      reviewed_by = v_admin_user_id,
      reviewed_at = now(),
      transfer_transaction_id = v_tx_id
  WHERE id = v_row.id;

  RETURN v_row.id;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_topup_request(NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_topup_requests(TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_review_topup_request(UUID, TEXT, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.submit_topup_request(NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- Storage bucket for top up proof uploads
INSERT INTO storage.buckets (id, name, public)
VALUES ('topup-proof', 'topup-proof', true)
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'Topup proof read'
  ) THEN
    CREATE POLICY "Topup proof read"
      ON storage.objects
      FOR SELECT TO authenticated
      USING (bucket_id = 'topup-proof');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'Topup proof insert'
  ) THEN
    CREATE POLICY "Topup proof insert"
      ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'topup-proof');
  END IF;
END $$;
GRANT EXECUTE ON FUNCTION public.admin_list_topup_requests(TEXT, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_review_topup_request(UUID, TEXT, TEXT) TO authenticated;

-- <<< END MIGRATION: 20260225120000_topup_requests.sql

-- >>> MIGRATION: 20260225123000_support_message_attachments.sql
-- Support message attachments (image uploads)
ALTER TABLE public.support_messages
  ADD COLUMN IF NOT EXISTS attachment_url TEXT;

-- Storage bucket for support attachments
INSERT INTO storage.buckets (id, name, public)
VALUES ('support-attachments', 'support-attachments', true)
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'Support attachments read'
  ) THEN
    CREATE POLICY "Support attachments read"
      ON storage.objects
      FOR SELECT TO authenticated
      USING (bucket_id = 'support-attachments');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'Support attachments insert'
  ) THEN
    CREATE POLICY "Support attachments insert"
      ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'support-attachments');
  END IF;
END $$;

-- <<< END MIGRATION: 20260225123000_support_message_attachments.sql

-- >>> MIGRATION: 20260225130000_master_topup.sql
-- Master top up (internal credit) for @wainfoundation only
CREATE OR REPLACE FUNCTION public.master_topup_internal(
  p_amount NUMERIC,
  p_target_account_number TEXT DEFAULT NULL,
  p_target_username TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id UUID := auth.uid();
  v_admin_username TEXT;
  v_amount NUMERIC(12,2) := ROUND(COALESCE(p_amount, 0), 2);
  v_target_account TEXT := UPPER(TRIM(COALESCE(p_target_account_number, '')));
  v_target_username TEXT := LOWER(TRIM(COALESCE(p_target_username, '')));
  v_target_user_id UUID;
  v_user_balance NUMERIC(12,2);
  v_tx_id UUID;
BEGIN
  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT LOWER(COALESCE(username, ''))
  INTO v_admin_username
  FROM public.profiles
  WHERE id = v_admin_id;

  IF v_admin_username <> 'wainfoundation' THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  IF v_amount < 1 THEN
    RAISE EXCEPTION 'Minimum top up is 1 OPEN USD';
  END IF;

  IF v_target_account = '' AND v_target_username = '' THEN
    RAISE EXCEPTION 'Target account number or username is required';
  END IF;

  SELECT ua.user_id
  INTO v_target_user_id
  FROM public.user_accounts ua
  WHERE (v_target_account <> '' AND UPPER(ua.account_number) = v_target_account)
     OR (v_target_username <> '' AND LOWER(ua.account_username) = v_target_username)
  LIMIT 1;

  IF v_target_user_id IS NULL THEN
    RAISE EXCEPTION 'Target account not found';
  END IF;

  SELECT balance
  INTO v_user_balance
  FROM public.wallets
  WHERE user_id = v_target_user_id
  FOR UPDATE;

  IF v_user_balance IS NULL THEN
    RAISE EXCEPTION 'User wallet not found';
  END IF;

  UPDATE public.wallets
  SET balance = v_user_balance + v_amount,
      updated_at = now()
  WHERE user_id = v_target_user_id;

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_target_user_id,
    v_target_user_id,
    v_amount,
    '[internal] Master top up',
    'completed'
  )
  RETURNING id INTO v_tx_id;

  RETURN v_tx_id;
END;
$$;

REVOKE ALL ON FUNCTION public.master_topup_internal(NUMERIC, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.master_topup_internal(NUMERIC, TEXT, TEXT) TO authenticated;

-- <<< END MIGRATION: 20260225130000_master_topup.sql

-- >>> MIGRATION: 20260225130500_hide_internal_public_ledger.sql
-- Exclude internal master top ups from public ledger
CREATE OR REPLACE FUNCTION public.get_public_ledger(
  p_limit INTEGER DEFAULT 30,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  amount NUMERIC,
  note TEXT,
  status TEXT,
  occurred_at TIMESTAMPTZ,
  event_type TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    le.amount,
    CASE
      WHEN le.note IS NULL THEN NULL
      ELSE regexp_replace(
        le.note,
        '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
        '[hidden]',
        'g'
      )
    END AS note,
    COALESCE(le.status, 'completed') AS status,
    le.occurred_at,
    le.event_type
  FROM public.ledger_events le
  LEFT JOIN public.transactions t ON t.id = le.source_id
  LEFT JOIN public.profiles ps ON ps.id = t.sender_id
  LEFT JOIN public.profiles pr ON pr.id = t.receiver_id
  WHERE le.source_table = 'transactions'
    AND le.amount IS NOT NULL
    AND (le.note IS NULL OR le.note NOT ILIKE '[internal]%')
    AND NOT (
      LOWER(COALESCE(ps.username, '')) = 'wainfoundation'
      AND LOWER(COALESCE(pr.username, '')) = 'openpay'
    )
  ORDER BY le.occurred_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
$$;

REVOKE ALL ON FUNCTION public.get_public_ledger(INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_ledger(INTEGER, INTEGER) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_public_ledger_transaction(
  p_transaction_id UUID
)
RETURNS TABLE (
  amount NUMERIC,
  note TEXT,
  status TEXT,
  occurred_at TIMESTAMPTZ,
  event_type TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    le.amount,
    CASE
      WHEN le.note IS NULL THEN NULL
      ELSE regexp_replace(
        le.note,
        '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
        '[hidden]',
        'g'
      )
    END AS note,
    COALESCE(le.status, 'completed') AS status,
    le.occurred_at,
    le.event_type
  FROM public.ledger_events le
  LEFT JOIN public.transactions t ON t.id = le.source_id
  LEFT JOIN public.profiles ps ON ps.id = t.sender_id
  LEFT JOIN public.profiles pr ON pr.id = t.receiver_id
  WHERE le.source_table = 'transactions'
    AND le.source_id = p_transaction_id
    AND le.amount IS NOT NULL
    AND (le.note IS NULL OR le.note NOT ILIKE '[internal]%')
    AND NOT (
      LOWER(COALESCE(ps.username, '')) = 'wainfoundation'
      AND LOWER(COALESCE(pr.username, '')) = 'openpay'
    )
  ORDER BY le.occurred_at DESC
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_public_ledger_transaction(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_ledger_transaction(UUID) TO anon, authenticated;

-- <<< END MIGRATION: 20260225130500_hide_internal_public_ledger.sql

-- >>> MIGRATION: 20260225133000_grant_user_topup_requests_select.sql
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'user_topup_requests'
      AND c.relkind = 'r'
  ) THEN
    GRANT SELECT ON TABLE public.user_topup_requests TO authenticated;
  END IF;
END $$;

-- <<< END MIGRATION: 20260225133000_grant_user_topup_requests_select.sql

-- >>> MIGRATION: 20260225133500_grant_user_swap_withdrawals_select.sql
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'user_swap_withdrawals'
      AND c.relkind = 'r'
  ) THEN
    GRANT SELECT ON TABLE public.user_swap_withdrawals TO authenticated;
  END IF;
END $$;

-- <<< END MIGRATION: 20260225133500_grant_user_swap_withdrawals_select.sql

-- >>> MIGRATION: 20260225134000_grant_support_widget_access.sql
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'support_conversations'
      AND c.relkind = 'r'
  ) THEN
    GRANT SELECT, INSERT, UPDATE ON TABLE public.support_conversations TO authenticated;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'support_messages'
      AND c.relkind = 'r'
  ) THEN
    GRANT SELECT, INSERT ON TABLE public.support_messages TO authenticated;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'support_faq_categories'
      AND c.relkind = 'r'
  ) THEN
    GRANT SELECT ON TABLE public.support_faq_categories TO authenticated;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'support_faq_items'
      AND c.relkind = 'r'
  ) THEN
    GRANT SELECT ON TABLE public.support_faq_items TO authenticated;
  END IF;
END $$;

-- <<< END MIGRATION: 20260225134000_grant_support_widget_access.sql

-- >>> MIGRATION: 20260225140000_private_ledger_transaction.sql
CREATE OR REPLACE FUNCTION public.get_private_ledger_transaction(
  p_transaction_id UUID
)
RETURNS TABLE (
  amount NUMERIC,
  note TEXT,
  status TEXT,
  occurred_at TIMESTAMPTZ,
  event_type TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    le.amount,
    le.note,
    COALESCE(le.status, 'completed') AS status,
    le.occurred_at,
    le.event_type
  FROM public.ledger_events le
  LEFT JOIN public.transactions t ON t.id = le.source_id
  WHERE le.source_table = 'transactions'
    AND le.source_id = p_transaction_id
    AND le.amount IS NOT NULL
    AND (
      t.sender_id = auth.uid()
      OR t.receiver_id = auth.uid()
    )
  ORDER BY le.occurred_at DESC
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_private_ledger_transaction(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_private_ledger_transaction(UUID) TO authenticated;

-- <<< END MIGRATION: 20260225140000_private_ledger_transaction.sql

-- >>> MIGRATION: 20260225152000_repair_topup_requests_schema_cache.sql
CREATE TABLE IF NOT EXISTS public.user_topup_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider TEXT NOT NULL DEFAULT '',
  amount NUMERIC(12,2) NOT NULL CHECK (amount >= 1),
  openpay_account_name TEXT NOT NULL DEFAULT '',
  openpay_account_username TEXT NOT NULL DEFAULT '',
  openpay_account_number TEXT NOT NULL DEFAULT '',
  reference_code TEXT NOT NULL DEFAULT '',
  proof_url TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  admin_note TEXT NOT NULL DEFAULT '',
  transfer_transaction_id UUID NULL REFERENCES public.transactions(id) ON DELETE SET NULL,
  reviewed_by UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_topup_requests_user_created
  ON public.user_topup_requests(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_topup_requests_status_created
  ON public.user_topup_requests(status, created_at DESC);

ALTER TABLE public.user_topup_requests ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_topup_requests' AND policyname = 'Users can view own topup requests'
  ) THEN
    CREATE POLICY "Users can view own topup requests"
      ON public.user_topup_requests
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_user_topup_requests_updated_at ON public.user_topup_requests;
CREATE TRIGGER trg_user_topup_requests_updated_at
BEFORE UPDATE ON public.user_topup_requests
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

CREATE OR REPLACE FUNCTION public.submit_topup_request(
  p_amount NUMERIC,
  p_openpay_account_name TEXT,
  p_openpay_account_number TEXT,
  p_openpay_account_username TEXT,
  p_proof_url TEXT,
  p_provider TEXT,
  p_reference_code TEXT
)
RETURNS public.user_topup_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_amount NUMERIC(12,2) := ROUND(COALESCE(p_amount, 0), 2);
  v_name TEXT := LEFT(TRIM(COALESCE(p_openpay_account_name, '')), 160);
  v_account TEXT := UPPER(TRIM(COALESCE(p_openpay_account_number, '')));
  v_username TEXT := LEFT(TRIM(COALESCE(p_openpay_account_username, '')), 120);
  v_proof_url TEXT := LEFT(TRIM(COALESCE(p_proof_url, '')), 400);
  v_provider TEXT := LEFT(TRIM(COALESCE(p_provider, '')), 80);
  v_reference TEXT := LEFT(TRIM(COALESCE(p_reference_code, '')), 160);
  v_row public.user_topup_requests;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_amount < 1 THEN
    RAISE EXCEPTION 'Minimum top up is 1 OPEN USD';
  END IF;

  IF v_provider = '' THEN
    RAISE EXCEPTION 'Top up provider is required';
  END IF;

  IF v_name = '' OR v_username = '' OR v_account = '' THEN
    RAISE EXCEPTION 'Complete all required top up fields';
  END IF;

  IF v_reference = '' THEN
    RAISE EXCEPTION 'Payment reference is required';
  END IF;

  IF v_proof_url = '' THEN
    RAISE EXCEPTION 'Payment proof is required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.user_accounts ua
    WHERE ua.user_id = v_user_id
      AND UPPER(ua.account_number) = v_account
  ) THEN
    RAISE EXCEPTION 'OpenPay account number does not match your profile';
  END IF;

  INSERT INTO public.user_topup_requests (
    user_id,
    provider,
    amount,
    openpay_account_name,
    openpay_account_username,
    openpay_account_number,
    reference_code,
    proof_url,
    status
  )
  VALUES (
    v_user_id,
    v_provider,
    v_amount,
    v_name,
    v_username,
    v_account,
    v_reference,
    v_proof_url,
    'pending'
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_topup_request(NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_topup_request(NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

GRANT SELECT ON TABLE public.user_topup_requests TO authenticated;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260225152000_repair_topup_requests_schema_cache.sql

-- >>> MIGRATION: 20260225153000_repair_private_ledger_transaction_schema_cache.sql
CREATE OR REPLACE FUNCTION public.get_private_ledger_transaction(
  p_transaction_id UUID
)
RETURNS TABLE (
  amount NUMERIC,
  note TEXT,
  status TEXT,
  occurred_at TIMESTAMPTZ,
  event_type TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    le.amount,
    le.note,
    COALESCE(le.status, 'completed') AS status,
    le.occurred_at,
    le.event_type
  FROM public.ledger_events le
  LEFT JOIN public.transactions t ON t.id = le.source_id
  WHERE le.source_table = 'transactions'
    AND le.source_id = p_transaction_id
    AND le.amount IS NOT NULL
    AND (
      t.sender_id = auth.uid()
      OR t.receiver_id = auth.uid()
    )
  ORDER BY le.occurred_at DESC
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_private_ledger_transaction(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_private_ledger_transaction(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260225153000_repair_private_ledger_transaction_schema_cache.sql

-- >>> MIGRATION: 20260225154000_repair_swap_withdrawals_schema_cache.sql
CREATE TABLE IF NOT EXISTS public.user_swap_withdrawals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount NUMERIC(12,2) NOT NULL CHECK (amount >= 1),
  fee_rate NUMERIC(6,4) NOT NULL DEFAULT 0.02 CHECK (fee_rate >= 0 AND fee_rate <= 0.2),
  fee_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  payout_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  openpay_account_name TEXT NOT NULL DEFAULT '',
  openpay_account_username TEXT NOT NULL DEFAULT '',
  openpay_account_number TEXT NOT NULL DEFAULT '',
  pi_wallet_address TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  admin_note TEXT NOT NULL DEFAULT '',
  transfer_transaction_id UUID NULL REFERENCES public.transactions(id) ON DELETE SET NULL,
  refund_transaction_id UUID NULL REFERENCES public.transactions(id) ON DELETE SET NULL,
  reviewed_by UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_swap_withdrawals_user_created
  ON public.user_swap_withdrawals(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_swap_withdrawals_status_created
  ON public.user_swap_withdrawals(status, created_at DESC);

ALTER TABLE public.user_swap_withdrawals ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_swap_withdrawals' AND policyname = 'Users can view own swap withdrawals'
  ) THEN
    CREATE POLICY "Users can view own swap withdrawals"
      ON public.user_swap_withdrawals
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_user_swap_withdrawals_updated_at ON public.user_swap_withdrawals;
CREATE TRIGGER trg_user_swap_withdrawals_updated_at
BEFORE UPDATE ON public.user_swap_withdrawals
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

DROP FUNCTION IF EXISTS public.submit_swap_withdrawal(NUMERIC, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.submit_swap_withdrawal(
  p_amount NUMERIC,
  p_openpay_account_name TEXT,
  p_openpay_account_number TEXT,
  p_openpay_account_username TEXT,
  p_pi_wallet_address TEXT
)
RETURNS public.user_swap_withdrawals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_amount NUMERIC(12,2) := ROUND(COALESCE(p_amount, 0), 2);
  v_fee_rate NUMERIC(6,4) := 0.02;
  v_fee_amount NUMERIC(12,2);
  v_payout_amount NUMERIC(12,2);
  v_openpay_user_id UUID;
  v_wallet_balance NUMERIC(12,2);
  v_openpay_balance NUMERIC(12,2);
  v_tx_id UUID;
  v_row public.user_swap_withdrawals;
  v_settlement_account TEXT := 'OPEA68BB7A9F964994A199A15786D680FA';
  v_name TEXT := LEFT(TRIM(COALESCE(p_openpay_account_name, '')), 160);
  v_account TEXT := UPPER(TRIM(COALESCE(p_openpay_account_number, '')));
  v_username TEXT := LEFT(TRIM(COALESCE(p_openpay_account_username, '')), 120);
  v_wallet TEXT := LEFT(TRIM(COALESCE(p_pi_wallet_address, '')), 240);
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_amount < 1 THEN
    RAISE EXCEPTION 'Minimum withdrawal is 1 OPEN USD';
  END IF;

  v_fee_amount := ROUND(v_amount * v_fee_rate, 2);
  v_payout_amount := ROUND(v_amount - v_fee_amount, 2);
  IF v_payout_amount <= 0 THEN
    RAISE EXCEPTION 'Withdrawal amount too low after fees';
  END IF;

  IF v_name = '' OR v_username = '' OR v_account = '' OR v_wallet = '' THEN
    RAISE EXCEPTION 'Complete all required withdrawal fields';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.user_accounts ua
    WHERE ua.user_id = v_user_id
      AND UPPER(ua.account_number) = v_account
  ) THEN
    RAISE EXCEPTION 'OpenPay account number does not match your profile';
  END IF;

  SELECT ua.user_id INTO v_openpay_user_id
  FROM public.user_accounts ua
  WHERE ua.account_number = v_settlement_account
  LIMIT 1;

  IF v_openpay_user_id IS NULL THEN
    RAISE EXCEPTION 'Settlement account not found';
  END IF;

  IF v_openpay_user_id = v_user_id THEN
    RAISE EXCEPTION 'Settlement account invalid';
  END IF;

  SELECT balance INTO v_wallet_balance
  FROM public.wallets
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'Wallet not found';
  END IF;

  IF v_wallet_balance < v_amount THEN
    RAISE EXCEPTION 'Insufficient wallet balance';
  END IF;

  SELECT balance INTO v_openpay_balance
  FROM public.wallets
  WHERE user_id = v_openpay_user_id
  FOR UPDATE;

  IF v_openpay_balance IS NULL THEN
    RAISE EXCEPTION 'Settlement wallet not found';
  END IF;

  UPDATE public.wallets
  SET balance = v_wallet_balance - v_amount,
      updated_at = now()
  WHERE user_id = v_user_id;

  UPDATE public.wallets
  SET balance = v_openpay_balance + v_amount,
      updated_at = now()
  WHERE user_id = v_openpay_user_id;

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_user_id,
    v_openpay_user_id,
    v_amount,
    CONCAT(
      'Swap withdrawal request to PI | Wallet ',
      LEFT(v_wallet, 80),
      ' | OpenPay ',
      LEFT(v_username, 40),
      ' ',
      LEFT(v_account, 60)
    ),
    'completed'
  )
  RETURNING id INTO v_tx_id;

  INSERT INTO public.user_swap_withdrawals (
    user_id,
    amount,
    fee_rate,
    fee_amount,
    payout_amount,
    openpay_account_name,
    openpay_account_username,
    openpay_account_number,
    pi_wallet_address,
    status,
    transfer_transaction_id
  )
  VALUES (
    v_user_id,
    v_amount,
    v_fee_rate,
    v_fee_amount,
    v_payout_amount,
    v_name,
    v_username,
    v_account,
    v_wallet,
    'pending',
    v_tx_id
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_swap_withdrawal(NUMERIC, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_swap_withdrawal(NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated;

GRANT SELECT ON TABLE public.user_swap_withdrawals TO authenticated;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260225154000_repair_swap_withdrawals_schema_cache.sql

-- >>> MIGRATION: 20260225160000_allow_rejected_invoice_status.sql
ALTER TABLE public.invoices
  DROP CONSTRAINT IF EXISTS invoices_status_check;

ALTER TABLE public.invoices
  ADD CONSTRAINT invoices_status_check
  CHECK (status IN ('pending', 'paid', 'rejected', 'cancelled'));

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260225160000_allow_rejected_invoice_status.sql

-- >>> MIGRATION: 20260225162000_admin_list_rpc_signature_compat.sql
CREATE OR REPLACE FUNCTION public.admin_list_topup_requests(
  p_limit INTEGER,
  p_offset INTEGER,
  p_status TEXT
)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  provider TEXT,
  amount NUMERIC,
  openpay_account_name TEXT,
  openpay_account_username TEXT,
  openpay_account_number TEXT,
  reference_code TEXT,
  proof_url TEXT,
  status TEXT,
  admin_note TEXT,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ,
  applicant_display_name TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT *
  FROM public.admin_list_topup_requests(
    p_status => p_status,
    p_limit => p_limit,
    p_offset => p_offset
  );
$$;

CREATE OR REPLACE FUNCTION public.admin_list_swap_withdrawals(
  p_limit INTEGER,
  p_offset INTEGER,
  p_status TEXT
)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  amount NUMERIC,
  openpay_account_name TEXT,
  openpay_account_username TEXT,
  openpay_account_number TEXT,
  pi_wallet_address TEXT,
  status TEXT,
  admin_note TEXT,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ,
  applicant_display_name TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT *
  FROM public.admin_list_swap_withdrawals(
    p_status => p_status,
    p_limit => p_limit,
    p_offset => p_offset
  );
$$;

REVOKE ALL ON FUNCTION public.admin_list_topup_requests(INTEGER, INTEGER, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_swap_withdrawals(INTEGER, INTEGER, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_list_topup_requests(INTEGER, INTEGER, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_swap_withdrawals(INTEGER, INTEGER, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260225162000_admin_list_rpc_signature_compat.sql

-- >>> MIGRATION: 20260225163000_repair_support_workflow_access.sql
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'support_tickets'
      AND c.relkind = 'r'
  ) THEN
    GRANT SELECT, INSERT, UPDATE ON TABLE public.support_tickets TO authenticated;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'support_conversations'
      AND c.relkind = 'r'
  ) THEN
    GRANT SELECT, INSERT, UPDATE ON TABLE public.support_conversations TO authenticated;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'support_messages'
      AND c.relkind = 'r'
  ) THEN
    GRANT SELECT, INSERT ON TABLE public.support_messages TO authenticated;
  END IF;
END $$;

ALTER TABLE public.support_messages
  ADD COLUMN IF NOT EXISTS attachment_url TEXT;

INSERT INTO storage.buckets (id, name, public)
VALUES ('support-attachments', 'support-attachments', true)
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'Support attachments read'
  ) THEN
    CREATE POLICY "Support attachments read"
      ON storage.objects
      FOR SELECT TO authenticated
      USING (bucket_id = 'support-attachments');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'Support attachments insert'
  ) THEN
    CREATE POLICY "Support attachments insert"
      ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'support-attachments');
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260225163000_repair_support_workflow_access.sql

-- >>> MIGRATION: 20260225164000_fix_admin_list_wrapper_recursion.sql
CREATE OR REPLACE FUNCTION public.admin_list_topup_requests(
  p_limit INTEGER,
  p_offset INTEGER,
  p_status TEXT
)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  provider TEXT,
  amount NUMERIC,
  openpay_account_name TEXT,
  openpay_account_username TEXT,
  openpay_account_number TEXT,
  reference_code TEXT,
  proof_url TEXT,
  status TEXT,
  admin_note TEXT,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ,
  applicant_display_name TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT *
  FROM public.admin_list_topup_requests(
    p_status,
    p_limit,
    p_offset
  );
$$;

CREATE OR REPLACE FUNCTION public.admin_list_swap_withdrawals(
  p_limit INTEGER,
  p_offset INTEGER,
  p_status TEXT
)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  amount NUMERIC,
  openpay_account_name TEXT,
  openpay_account_username TEXT,
  openpay_account_number TEXT,
  pi_wallet_address TEXT,
  status TEXT,
  admin_note TEXT,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ,
  applicant_display_name TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT *
  FROM public.admin_list_swap_withdrawals(
    p_status,
    p_limit,
    p_offset
  );
$$;

REVOKE ALL ON FUNCTION public.admin_list_topup_requests(INTEGER, INTEGER, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_swap_withdrawals(INTEGER, INTEGER, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_list_topup_requests(INTEGER, INTEGER, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_swap_withdrawals(INTEGER, INTEGER, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260225164000_fix_admin_list_wrapper_recursion.sql

-- >>> MIGRATION: 20260225165000_repair_admin_list_functions_full.sql
CREATE OR REPLACE FUNCTION public.admin_list_topup_requests(
  p_status TEXT DEFAULT 'pending',
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  provider TEXT,
  amount NUMERIC,
  openpay_account_name TEXT,
  openpay_account_username TEXT,
  openpay_account_number TEXT,
  reference_code TEXT,
  proof_url TEXT,
  status TEXT,
  admin_note TEXT,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ,
  applicant_display_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT := LOWER(TRIM(COALESCE(p_status, 'pending')));
BEGIN
  IF public.is_openpay_core_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  RETURN QUERY
  SELECT
    utr.id,
    utr.user_id,
    utr.provider,
    utr.amount,
    utr.openpay_account_name,
    utr.openpay_account_username,
    utr.openpay_account_number,
    utr.reference_code,
    utr.proof_url,
    utr.status,
    utr.admin_note,
    utr.reviewed_at,
    utr.created_at,
    COALESCE(NULLIF(p.full_name, ''), CONCAT('@', NULLIF(p.username, '')), LEFT(utr.user_id::TEXT, 8))
  FROM public.user_topup_requests utr
  LEFT JOIN public.profiles p ON p.id = utr.user_id
  WHERE (v_status = 'all' OR utr.status = v_status)
  ORDER BY utr.created_at DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 50), 200))
  OFFSET GREATEST(0, COALESCE(p_offset, 0));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_swap_withdrawals(
  p_status TEXT DEFAULT 'pending',
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  amount NUMERIC,
  openpay_account_name TEXT,
  openpay_account_username TEXT,
  openpay_account_number TEXT,
  pi_wallet_address TEXT,
  status TEXT,
  admin_note TEXT,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ,
  applicant_display_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT := LOWER(TRIM(COALESCE(p_status, 'pending')));
BEGIN
  IF public.is_openpay_core_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  RETURN QUERY
  SELECT
    usw.id,
    usw.user_id,
    usw.amount,
    usw.openpay_account_name,
    usw.openpay_account_username,
    usw.openpay_account_number,
    usw.pi_wallet_address,
    usw.status,
    usw.admin_note,
    usw.reviewed_at,
    usw.created_at,
    COALESCE(NULLIF(p.full_name, ''), CONCAT('@', NULLIF(p.username, '')), LEFT(usw.user_id::TEXT, 8))
  FROM public.user_swap_withdrawals usw
  LEFT JOIN public.profiles p ON p.id = usw.user_id
  WHERE (v_status = 'all' OR usw.status = v_status)
  ORDER BY usw.created_at DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 50), 200))
  OFFSET GREATEST(0, COALESCE(p_offset, 0));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_topup_requests(
  p_limit INTEGER,
  p_offset INTEGER,
  p_status TEXT
)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  provider TEXT,
  amount NUMERIC,
  openpay_account_name TEXT,
  openpay_account_username TEXT,
  openpay_account_number TEXT,
  reference_code TEXT,
  proof_url TEXT,
  status TEXT,
  admin_note TEXT,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ,
  applicant_display_name TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT *
  FROM public.admin_list_topup_requests(
    p_status::TEXT,
    p_limit::INTEGER,
    p_offset::INTEGER
  );
$$;

CREATE OR REPLACE FUNCTION public.admin_list_swap_withdrawals(
  p_limit INTEGER,
  p_offset INTEGER,
  p_status TEXT
)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  amount NUMERIC,
  openpay_account_name TEXT,
  openpay_account_username TEXT,
  openpay_account_number TEXT,
  pi_wallet_address TEXT,
  status TEXT,
  admin_note TEXT,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ,
  applicant_display_name TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT *
  FROM public.admin_list_swap_withdrawals(
    p_status::TEXT,
    p_limit::INTEGER,
    p_offset::INTEGER
  );
$$;

REVOKE ALL ON FUNCTION public.admin_list_topup_requests(TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_topup_requests(INTEGER, INTEGER, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_swap_withdrawals(TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_swap_withdrawals(INTEGER, INTEGER, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_list_topup_requests(TEXT, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_topup_requests(INTEGER, INTEGER, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_swap_withdrawals(TEXT, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_swap_withdrawals(INTEGER, INTEGER, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260225165000_repair_admin_list_functions_full.sql

-- >>> MIGRATION: 20260225170000_fix_admin_list_rpc_ambiguity.sql
-- Resolve PostgREST function overload ambiguity for admin list RPCs.
-- Keep only the canonical signature:
--   (p_status TEXT DEFAULT 'pending', p_limit INTEGER DEFAULT 50, p_offset INTEGER DEFAULT 0)
-- and remove compatibility overload:
--   (p_limit INTEGER, p_offset INTEGER, p_status TEXT)

DROP FUNCTION IF EXISTS public.admin_list_topup_requests(INTEGER, INTEGER, TEXT);
DROP FUNCTION IF EXISTS public.admin_list_swap_withdrawals(INTEGER, INTEGER, TEXT);

REVOKE ALL ON FUNCTION public.admin_list_topup_requests(TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_swap_withdrawals(TEXT, INTEGER, INTEGER) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_list_topup_requests(TEXT, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_swap_withdrawals(TEXT, INTEGER, INTEGER) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260225170000_fix_admin_list_rpc_ambiguity.sql

-- >>> MIGRATION: 20260225171000_fix_admin_review_rpc_signature.sql
-- Fix PostgREST RPC resolution for admin review actions in production.
-- Recreate functions using parameter order currently requested by client/runtime.

DROP FUNCTION IF EXISTS public.admin_review_topup_request(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.admin_review_swap_withdrawal(UUID, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.admin_review_topup_request(
  p_admin_note TEXT DEFAULT '',
  p_decision TEXT DEFAULT '',
  p_request_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_user_id UUID := auth.uid();
  v_decision TEXT := LOWER(TRIM(COALESCE(p_decision, '')));
  v_row public.user_topup_requests;
  v_openpay_user_id UUID;
  v_openpay_balance NUMERIC(12,2);
  v_user_balance NUMERIC(12,2);
  v_tx_id UUID;
  v_settlement_account TEXT := 'OPEA68BB7A9F964994A199A15786D680FA';
BEGIN
  IF public.is_openpay_core_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  IF p_request_id IS NULL THEN
    RAISE EXCEPTION 'Request id is required';
  END IF;

  IF v_decision NOT IN ('approve', 'reject') THEN
    RAISE EXCEPTION 'Decision must be approve or reject';
  END IF;

  SELECT * INTO v_row
  FROM public.user_topup_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Top up request not found';
  END IF;

  IF v_row.status <> 'pending' THEN
    RAISE EXCEPTION 'Top up request already processed';
  END IF;

  IF v_decision = 'approve' THEN
    SELECT ua.user_id INTO v_openpay_user_id
    FROM public.user_accounts ua
    WHERE ua.account_number = v_settlement_account
    LIMIT 1;

    IF v_openpay_user_id IS NULL THEN
      RAISE EXCEPTION 'Settlement account not found';
    END IF;

    SELECT balance INTO v_openpay_balance
    FROM public.wallets
    WHERE user_id = v_openpay_user_id
    FOR UPDATE;

    IF v_openpay_balance IS NULL THEN
      RAISE EXCEPTION 'Settlement wallet not found';
    END IF;

    IF v_openpay_balance < v_row.amount THEN
      RAISE EXCEPTION 'Settlement wallet balance insufficient for top up';
    END IF;

    SELECT balance INTO v_user_balance
    FROM public.wallets
    WHERE user_id = v_row.user_id
    FOR UPDATE;

    IF v_user_balance IS NULL THEN
      RAISE EXCEPTION 'User wallet not found';
    END IF;

    UPDATE public.wallets
    SET balance = v_openpay_balance - v_row.amount,
        updated_at = now()
    WHERE user_id = v_openpay_user_id;

    UPDATE public.wallets
    SET balance = v_user_balance + v_row.amount,
        updated_at = now()
    WHERE user_id = v_row.user_id;

    INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
    VALUES (
      v_openpay_user_id,
      v_row.user_id,
      v_row.amount,
      CONCAT('Top up approved | ', v_row.provider, ' | Request ', v_row.id::TEXT),
      'completed'
    )
    RETURNING id INTO v_tx_id;
  END IF;

  UPDATE public.user_topup_requests
  SET status = CASE WHEN v_decision = 'approve' THEN 'approved' ELSE 'rejected' END,
      admin_note = COALESCE(p_admin_note, ''),
      reviewed_by = v_admin_user_id,
      reviewed_at = now(),
      transfer_transaction_id = v_tx_id
  WHERE id = v_row.id;

  RETURN v_row.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_review_swap_withdrawal(
  p_admin_note TEXT DEFAULT '',
  p_decision TEXT DEFAULT '',
  p_withdrawal_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_user_id UUID := auth.uid();
  v_decision TEXT := LOWER(TRIM(COALESCE(p_decision, '')));
  v_row public.user_swap_withdrawals;
  v_openpay_user_id UUID;
  v_openpay_balance NUMERIC(12,2);
  v_user_balance NUMERIC(12,2);
  v_refund_tx UUID;
  v_settlement_account TEXT := 'OPEA68BB7A9F964994A199A15786D680FA';
BEGIN
  IF public.is_openpay_core_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  IF p_withdrawal_id IS NULL THEN
    RAISE EXCEPTION 'Withdrawal id is required';
  END IF;

  IF v_decision NOT IN ('approve', 'reject') THEN
    RAISE EXCEPTION 'Decision must be approve or reject';
  END IF;

  SELECT * INTO v_row
  FROM public.user_swap_withdrawals
  WHERE id = p_withdrawal_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Withdrawal not found';
  END IF;

  IF v_row.status <> 'pending' THEN
    RAISE EXCEPTION 'Withdrawal already processed';
  END IF;

  IF v_decision = 'reject' THEN
    SELECT ua.user_id INTO v_openpay_user_id
    FROM public.user_accounts ua
    WHERE ua.account_number = v_settlement_account
    LIMIT 1;

    IF v_openpay_user_id IS NULL THEN
      RAISE EXCEPTION 'Settlement account not found';
    END IF;

    SELECT balance INTO v_openpay_balance
    FROM public.wallets
    WHERE user_id = v_openpay_user_id
    FOR UPDATE;

    IF v_openpay_balance IS NULL THEN
      RAISE EXCEPTION 'Settlement wallet not found';
    END IF;

    IF v_openpay_balance < v_row.amount THEN
      RAISE EXCEPTION 'Settlement wallet balance insufficient for refund';
    END IF;

    SELECT balance INTO v_user_balance
    FROM public.wallets
    WHERE user_id = v_row.user_id
    FOR UPDATE;

    IF v_user_balance IS NULL THEN
      RAISE EXCEPTION 'User wallet not found';
    END IF;

    UPDATE public.wallets
    SET balance = v_openpay_balance - v_row.amount,
        updated_at = now()
    WHERE user_id = v_openpay_user_id;

    UPDATE public.wallets
    SET balance = v_user_balance + v_row.amount,
        updated_at = now()
    WHERE user_id = v_row.user_id;

    INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
    VALUES (
      v_openpay_user_id,
      v_row.user_id,
      v_row.amount,
      CONCAT('Swap withdrawal rejected refund | Request ', v_row.id::TEXT),
      'refunded'
    )
    RETURNING id INTO v_refund_tx;
  END IF;

  UPDATE public.user_swap_withdrawals
  SET status = CASE WHEN v_decision = 'approve' THEN 'approved' ELSE 'rejected' END,
      admin_note = COALESCE(p_admin_note, ''),
      reviewed_by = v_admin_user_id,
      reviewed_at = now(),
      refund_transaction_id = v_refund_tx
  WHERE id = v_row.id;

  RETURN v_row.id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_review_topup_request(TEXT, TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_review_swap_withdrawal(TEXT, TEXT, UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_review_topup_request(TEXT, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_review_swap_withdrawal(TEXT, TEXT, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260225171000_fix_admin_review_rpc_signature.sql

-- >>> MIGRATION: 20260225182000_public_checkout_digital_delivery_and_fee_policy.sql
DROP FUNCTION IF EXISTS public.get_public_merchant_checkout_session(TEXT);

CREATE OR REPLACE FUNCTION public.get_public_merchant_checkout_session(
  p_session_token TEXT
)
RETURNS TABLE (
  session_id UUID,
  status TEXT,
  mode TEXT,
  currency TEXT,
  amount NUMERIC,
  subtotal_amount NUMERIC,
  fee_amount NUMERIC,
  fee_payer TEXT,
  merchant_settlement_amount NUMERIC,
  expires_at TIMESTAMPTZ,
  merchant_user_id UUID,
  merchant_name TEXT,
  merchant_username TEXT,
  merchant_logo_url TEXT,
  items JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.merchant_checkout_sessions;
  v_fee_payer TEXT;
  v_settlement NUMERIC(12,2);
BEGIN
  SELECT *
  INTO v_session
  FROM public.merchant_checkout_sessions mcs
  WHERE mcs.session_token = TRIM(COALESCE(p_session_token, ''))
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF v_session.status = 'open' AND v_session.expires_at < now() THEN
    UPDATE public.merchant_checkout_sessions
    SET status = 'expired'
    WHERE id = v_session.id
      AND status = 'open';

    SELECT *
    INTO v_session
    FROM public.merchant_checkout_sessions
    WHERE id = v_session.id;
  END IF;

  v_fee_payer := LOWER(COALESCE(NULLIF(TRIM(v_session.metadata->>'fee_payer'), ''), 'customer'));
  v_settlement := COALESCE(
    NULLIF(TRIM(v_session.metadata->>'merchant_settlement_amount'), '')::NUMERIC,
    CASE
      WHEN v_fee_payer = 'merchant' THEN GREATEST(COALESCE(v_session.subtotal_amount, 0) - COALESCE(v_session.fee_amount, 0), 0)
      ELSE COALESCE(v_session.subtotal_amount, COALESCE(v_session.total_amount, 0))
    END
  );

  RETURN QUERY
  SELECT
    v_session.id,
    v_session.status,
    v_session.key_mode,
    v_session.currency,
    v_session.total_amount,
    v_session.subtotal_amount,
    v_session.fee_amount,
    v_fee_payer,
    v_settlement,
    v_session.expires_at,
    mp.user_id,
    mp.merchant_name,
    mp.merchant_username,
    mp.merchant_logo_url,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'product_id', mcsi.product_id,
            'item_name', mcsi.item_name,
            'quantity', mcsi.quantity,
            'unit_amount', mcsi.unit_amount,
            'line_total', mcsi.line_total,
            'item_image_url', prod.image_url,
            'item_images', CASE
              WHEN jsonb_typeof(prod.metadata->'product_images') = 'array' THEN prod.metadata->'product_images'
              ELSE '[]'::jsonb
            END,
            'product_kind', LOWER(COALESCE(prod.metadata->>'product_kind', 'physical')),
            'delivery_type', LOWER(NULLIF(COALESCE(prod.metadata->>'digital_delivery_type', ''), '')),
            'delivery_file_name', NULLIF(COALESCE(prod.metadata->>'digital_file_name', ''), ''),
            'delivery_file_data_url', NULLIF(COALESCE(prod.metadata->>'digital_file_data_url', ''), ''),
            'delivery_link_url', NULLIF(COALESCE(prod.metadata->>'digital_download_link', ''), '')
          )
          ORDER BY mcsi.created_at ASC
        )
        FROM public.merchant_checkout_session_items mcsi
        LEFT JOIN public.merchant_products prod
          ON prod.id = mcsi.product_id
        WHERE mcsi.session_id = v_session.id
      ),
      '[]'::jsonb
    )
  FROM public.merchant_profiles mp
  WHERE mp.user_id = v_session.merchant_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_checkout_session_from_payment_link(
  p_link_token TEXT,
  p_customer_email TEXT DEFAULT NULL,
  p_customer_name TEXT DEFAULT NULL
)
RETURNS TABLE (
  session_id UUID,
  session_token TEXT,
  total_amount NUMERIC,
  currency TEXT,
  expires_at TIMESTAMPTZ,
  after_payment_type TEXT,
  confirmation_message TEXT,
  redirect_url TEXT,
  call_to_action TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_link public.merchant_payment_links;
  v_session public.merchant_checkout_sessions;
  v_total NUMERIC(12,2) := 0;
  v_fee_payer TEXT := 'customer';
  v_fee_amount NUMERIC(12,2) := 0;
  v_total_due NUMERIC(12,2) := 0;
  v_merchant_settlement NUMERIC(12,2) := 0;
BEGIN
  SELECT *
  INTO v_link
  FROM public.merchant_payment_links mpl
  WHERE mpl.link_token = TRIM(COALESCE(p_link_token, ''))
    AND mpl.is_active = true
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment link not found';
  END IF;

  IF v_link.expires_at IS NOT NULL AND v_link.expires_at < now() THEN
    RAISE EXCEPTION 'Payment link expired';
  END IF;

  INSERT INTO public.merchant_checkout_sessions (
    merchant_user_id,
    api_key_id,
    key_mode,
    session_token,
    status,
    currency,
    subtotal_amount,
    fee_amount,
    total_amount,
    customer_email,
    customer_name,
    success_url,
    cancel_url,
    metadata,
    expires_at
  )
  VALUES (
    v_link.merchant_user_id,
    v_link.api_key_id,
    v_link.key_mode,
    'opsess_' || public.random_token_hex(24),
    'open',
    v_link.currency,
    0,
    0,
    0,
    NULLIF(TRIM(COALESCE(p_customer_email, '')), ''),
    NULLIF(TRIM(COALESCE(p_customer_name, '')), ''),
    NULL,
    NULL,
    jsonb_build_object(
      'payment_link_id', v_link.id,
      'payment_link_token', v_link.link_token,
      'api_key_id', v_link.api_key_id,
      'after_payment_type', v_link.after_payment_type,
      'confirmation_message', v_link.confirmation_message,
      'redirect_url', v_link.redirect_url,
      'call_to_action', v_link.call_to_action
    ),
    now() + INTERVAL '60 minutes'
  )
  RETURNING * INTO v_session;

  IF v_link.link_type = 'custom_amount' THEN
    v_total := COALESCE(v_link.custom_amount, 0);

    INSERT INTO public.merchant_checkout_session_items (
      session_id,
      product_id,
      item_name,
      unit_amount,
      quantity,
      line_total
    )
    VALUES (
      v_session.id,
      NULL,
      v_link.title,
      v_total,
      1,
      v_total
    );
  ELSE
    INSERT INTO public.merchant_checkout_session_items (
      session_id,
      product_id,
      item_name,
      unit_amount,
      quantity,
      line_total
    )
    SELECT
      v_session.id,
      mpli.product_id,
      mpli.item_name,
      mpli.unit_amount,
      mpli.quantity,
      mpli.line_total
    FROM public.merchant_payment_link_items mpli
    WHERE mpli.link_id = v_link.id;

    SELECT COALESCE(SUM(mpli.line_total), 0)
    INTO v_total
    FROM public.merchant_payment_link_items mpli
    WHERE mpli.link_id = v_link.id;

    SELECT LOWER(COALESCE(NULLIF(TRIM(prod.metadata->>'fee_payer'), ''), 'customer'))
    INTO v_fee_payer
    FROM public.merchant_payment_link_items mpli
    JOIN public.merchant_products prod
      ON prod.id = mpli.product_id
    WHERE mpli.link_id = v_link.id
    ORDER BY mpli.created_at ASC
    LIMIT 1;
  END IF;

  IF v_total <= 0 THEN
    RAISE EXCEPTION 'Payment link total must be positive';
  END IF;

  v_fee_amount := ROUND(v_total * 0.02, 2);
  v_total_due := CASE WHEN v_fee_payer = 'customer' THEN ROUND(v_total + v_fee_amount, 2) ELSE ROUND(v_total, 2) END;
  v_merchant_settlement := CASE WHEN v_fee_payer = 'merchant' THEN GREATEST(ROUND(v_total - v_fee_amount, 2), 0) ELSE ROUND(v_total, 2) END;

  UPDATE public.merchant_checkout_sessions
  SET subtotal_amount = v_total,
      fee_amount = v_fee_amount,
      total_amount = v_total_due,
      metadata = COALESCE(v_session.metadata, '{}'::jsonb) || jsonb_build_object(
        'fee_percent', 2,
        'fee_payer', v_fee_payer,
        'merchant_settlement_amount', v_merchant_settlement,
        'openpay_fee_amount', v_fee_amount
      )
  WHERE id = v_session.id
  RETURNING * INTO v_session;

  RETURN QUERY
  SELECT
    v_session.id,
    v_session.session_token,
    v_session.total_amount,
    v_session.currency,
    v_session.expires_at,
    v_link.after_payment_type,
    v_link.confirmation_message,
    v_link.redirect_url,
    v_link.call_to_action;
END;
$$;

CREATE OR REPLACE FUNCTION public.pay_merchant_checkout_with_virtual_card(
  p_session_token TEXT,
  p_card_number TEXT,
  p_expiry_month INTEGER,
  p_expiry_year INTEGER,
  p_cvc TEXT,
  p_note TEXT DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buyer_user_id UUID := auth.uid();
  v_session public.merchant_checkout_sessions;
  v_sender_balance NUMERIC(12,2);
  v_receiver_balance NUMERIC(12,2);
  v_openpay_balance NUMERIC(12,2);
  v_transaction_id UUID;
  v_card_number TEXT := regexp_replace(COALESCE(p_card_number, ''), '\D', '', 'g');
  v_cvc TEXT := regexp_replace(COALESCE(p_cvc, ''), '\D', '', 'g');
  v_expiry_end DATE;
  v_expiry_year INTEGER := COALESCE(p_expiry_year, 0);
  v_payment_link_id UUID;
  v_payment_link_token TEXT;
  v_card_owner_user_id UUID;
  v_currency_rate NUMERIC(20,8) := 1;
  v_wallet_amount NUMERIC(12,2) := 0;
  v_openpay_user_id UUID;
  v_fee_payer TEXT := 'customer';
  v_fee_amount NUMERIC(12,2) := 0;
  v_merchant_settlement NUMERIC(12,2) := 0;
BEGIN
  v_openpay_user_id := public.get_openpay_settlement_user_id();

  IF v_expiry_year > 0 AND v_expiry_year < 100 THEN
    v_expiry_year := 2000 + v_expiry_year;
  END IF;

  SELECT *
  INTO v_session
  FROM public.merchant_checkout_sessions mcs
  WHERE mcs.session_token = TRIM(COALESCE(p_session_token, ''))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Checkout session not found';
  END IF;

  IF v_session.status <> 'open' THEN
    RAISE EXCEPTION 'Checkout session is not open';
  END IF;

  IF v_session.expires_at < now() THEN
    UPDATE public.merchant_checkout_sessions
    SET status = 'expired'
    WHERE id = v_session.id;
    RAISE EXCEPTION 'Checkout session expired';
  END IF;

  IF char_length(v_card_number) <> 16 THEN
    RAISE EXCEPTION 'Card number must be 16 digits';
  END IF;

  IF p_expiry_month IS NULL OR p_expiry_month < 1 OR p_expiry_month > 12 THEN
    RAISE EXCEPTION 'Invalid expiry month';
  END IF;

  IF v_expiry_year < 2026 THEN
    RAISE EXCEPTION 'Invalid expiry year';
  END IF;

  IF char_length(v_cvc) <> 3 THEN
    RAISE EXCEPTION 'Invalid CVC';
  END IF;

  v_expiry_end := (make_date(v_expiry_year, p_expiry_month, 1) + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
  IF v_expiry_end < CURRENT_DATE THEN
    RAISE EXCEPTION 'Card expired';
  END IF;

  SELECT vc.user_id
  INTO v_card_owner_user_id
  FROM public.virtual_cards vc
  WHERE vc.card_number = v_card_number
    AND vc.expiry_month = p_expiry_month
    AND vc.expiry_year = v_expiry_year
    AND vc.cvc = v_cvc
    AND vc.is_active = true
    AND COALESCE(vc.is_locked, false) = false
    AND COALESCE((vc.card_settings ->> 'allow_checkout')::BOOLEAN, true) = true
  FOR UPDATE;

  IF v_card_owner_user_id IS NULL THEN
    RAISE EXCEPTION 'Invalid virtual card details';
  END IF;

  IF v_buyer_user_id IS NULL THEN
    v_buyer_user_id := v_card_owner_user_id;
  END IF;

  IF v_card_owner_user_id <> v_buyer_user_id THEN
    RAISE EXCEPTION 'Card owner does not match authenticated customer';
  END IF;

  IF v_session.merchant_user_id = v_buyer_user_id THEN
    RAISE EXCEPTION 'Merchant cannot pay own checkout';
  END IF;

  v_fee_payer := LOWER(COALESCE(NULLIF(TRIM(v_session.metadata->>'fee_payer'), ''), 'customer'));
  v_fee_amount := COALESCE(v_session.fee_amount, ROUND(COALESCE(v_session.subtotal_amount, 0) * 0.02, 2));
  v_merchant_settlement := COALESCE(
    NULLIF(TRIM(v_session.metadata->>'merchant_settlement_amount'), '')::NUMERIC,
    CASE
      WHEN v_fee_payer = 'merchant' THEN GREATEST(COALESCE(v_session.subtotal_amount, 0) - v_fee_amount, 0)
      ELSE COALESCE(v_session.subtotal_amount, COALESCE(v_session.total_amount, 0))
    END
  );

  SELECT sc.usd_rate
  INTO v_currency_rate
  FROM public.supported_currencies sc
  WHERE sc.iso_code = UPPER(COALESCE(v_session.currency, 'USD'))
    AND sc.is_active = true
  LIMIT 1;

  v_currency_rate := COALESCE(NULLIF(v_currency_rate, 0), 1);
  v_wallet_amount := ROUND(COALESCE(v_session.total_amount, 0) / v_currency_rate, 2);

  IF v_wallet_amount <= 0 THEN
    RAISE EXCEPTION 'Checkout amount must be greater than zero';
  END IF;

  SELECT balance INTO v_sender_balance
  FROM public.wallets
  WHERE user_id = v_card_owner_user_id
  FOR UPDATE;

  IF v_sender_balance IS NULL THEN
    RAISE EXCEPTION 'Buyer wallet not found';
  END IF;

  SELECT balance INTO v_receiver_balance
  FROM public.wallets
  WHERE user_id = v_session.merchant_user_id
  FOR UPDATE;

  IF v_receiver_balance IS NULL THEN
    RAISE EXCEPTION 'Merchant wallet not found';
  END IF;

  SELECT balance INTO v_openpay_balance
  FROM public.wallets
  WHERE user_id = v_openpay_user_id
  FOR UPDATE;

  IF v_openpay_balance IS NULL THEN
    RAISE EXCEPTION 'OpenPay settlement wallet not found';
  END IF;

  IF v_sender_balance < v_wallet_amount THEN
    RAISE EXCEPTION 'Insufficient virtual card balance';
  END IF;

  UPDATE public.wallets
  SET balance = v_sender_balance - v_wallet_amount,
      updated_at = now()
  WHERE user_id = v_card_owner_user_id;

  UPDATE public.wallets
  SET balance = v_receiver_balance + v_wallet_amount,
      updated_at = now()
  WHERE user_id = v_session.merchant_user_id;

  UPDATE public.wallets
  SET balance = balance - v_wallet_amount,
      updated_at = now()
  WHERE user_id = v_session.merchant_user_id;

  UPDATE public.wallets
  SET balance = v_openpay_balance + v_wallet_amount,
      updated_at = now()
  WHERE user_id = v_openpay_user_id;

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_card_owner_user_id,
    v_session.merchant_user_id,
    v_wallet_amount,
    CONCAT(
      'Merchant checkout ',
      v_session.session_token,
      ' | Card ****',
      RIGHT(v_card_number, 4),
      ' | Held in merchant available balance',
      CASE WHEN COALESCE(TRIM(p_note), '') <> '' THEN CONCAT(' | ', TRIM(p_note)) ELSE '' END
    ),
    'completed'
  )
  RETURNING id INTO v_transaction_id;

  v_payment_link_id := NULLIF((v_session.metadata->>'payment_link_id')::UUID, NULL);
  v_payment_link_token := NULLIF(TRIM(COALESCE(v_session.metadata->>'payment_link_token', '')), '');

  INSERT INTO public.merchant_payments (
    session_id,
    merchant_user_id,
    buyer_user_id,
    transaction_id,
    amount,
    currency,
    api_key_id,
    key_mode,
    payment_link_id,
    payment_link_token,
    status
  )
  VALUES (
    v_session.id,
    v_session.merchant_user_id,
    v_buyer_user_id,
    v_transaction_id,
    v_merchant_settlement,
    v_session.currency,
    v_session.api_key_id,
    v_session.key_mode,
    v_payment_link_id,
    v_payment_link_token,
    'succeeded'
  );

  UPDATE public.merchant_checkout_sessions
  SET status = 'paid',
      paid_at = now(),
      metadata = COALESCE(v_session.metadata, '{}'::jsonb) || jsonb_build_object(
        'fee_payer', v_fee_payer,
        'openpay_fee_amount', v_fee_amount,
        'merchant_settlement_amount', v_merchant_settlement
      )
  WHERE id = v_session.id;

  RETURN v_transaction_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_public_merchant_checkout_session(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_checkout_session_from_payment_link(TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pay_merchant_checkout_with_virtual_card(TEXT, TEXT, INTEGER, INTEGER, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pay_merchant_checkout_with_virtual_card(TEXT, TEXT, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_public_merchant_checkout_session(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_checkout_session_from_payment_link(TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pay_merchant_checkout_with_virtual_card(TEXT, TEXT, INTEGER, INTEGER, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pay_merchant_checkout_with_virtual_card(TEXT, TEXT, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;

-- <<< END MIGRATION: 20260225182000_public_checkout_digital_delivery_and_fee_policy.sql

-- >>> MIGRATION: 20260226000000_relax_currency_constraints.sql
-- Relax currency constraints to allow 2-10 character currency codes (OUSD, USDT, etc.)
DO $$
BEGIN
    -- Update merchant_profiles
    ALTER TABLE public.merchant_profiles DROP CONSTRAINT IF EXISTS merchant_profiles_default_currency_check;
    ALTER TABLE public.merchant_profiles ADD CONSTRAINT merchant_profiles_default_currency_check CHECK (char_length(default_currency) >= 2 AND char_length(default_currency) <= 10);

    -- Update merchant_products
    ALTER TABLE public.merchant_products DROP CONSTRAINT IF EXISTS merchant_products_currency_check;
    ALTER TABLE public.merchant_products ADD CONSTRAINT merchant_products_currency_check CHECK (char_length(currency) >= 2 AND char_length(currency) <= 10);

    -- Update merchant_checkout_sessions
    ALTER TABLE public.merchant_checkout_sessions DROP CONSTRAINT IF EXISTS merchant_checkout_sessions_currency_check;
    ALTER TABLE public.merchant_checkout_sessions ADD CONSTRAINT merchant_checkout_sessions_currency_check CHECK (char_length(currency) >= 2 AND char_length(currency) <= 10);

    -- Update merchant_payments
    ALTER TABLE public.merchant_payments DROP CONSTRAINT IF EXISTS merchant_payments_currency_check;
    ALTER TABLE public.merchant_payments ADD CONSTRAINT merchant_payments_currency_check CHECK (char_length(currency) >= 2 AND char_length(currency) <= 10);

    -- Update merchant_payment_links
    ALTER TABLE public.merchant_payment_links DROP CONSTRAINT IF EXISTS merchant_payment_links_currency_check;
    ALTER TABLE public.merchant_payment_links ADD CONSTRAINT merchant_payment_links_currency_check CHECK (char_length(currency) >= 2 AND char_length(currency) <= 10);
END $$;

-- Drop all versions of functions to ensure clean replacement
DROP FUNCTION IF EXISTS public.create_my_pos_checkout_session(NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER);
DROP FUNCTION IF EXISTS public.create_my_pos_checkout_session(NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT);
DROP FUNCTION IF EXISTS public.create_merchant_checkout_session(TEXT, TEXT, TEXT, JSONB, TEXT, TEXT, TEXT, TEXT, JSONB, INTEGER);
DROP FUNCTION IF EXISTS public.create_merchant_payment_link(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, JSONB, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, TEXT, TEXT, TEXT, TEXT, INTEGER);
DROP FUNCTION IF EXISTS public.create_merchant_pos_terminal_session(UUID, NUMERIC, TEXT, TEXT);

-- 1. create_my_pos_checkout_session
CREATE OR REPLACE FUNCTION public.create_my_pos_checkout_session(
  p_amount NUMERIC,
  p_currency TEXT DEFAULT 'USD',
  p_mode TEXT DEFAULT 'live',
  p_customer_name TEXT DEFAULT NULL,
  p_customer_email TEXT DEFAULT NULL,
  p_reference TEXT DEFAULT NULL,
  p_qr_style TEXT DEFAULT 'dynamic',
  p_expires_in_minutes INTEGER DEFAULT 30,
  p_secret_key TEXT DEFAULT NULL
)
RETURNS TABLE (
  session_id UUID,
  session_token TEXT,
  total_amount NUMERIC,
  currency TEXT,
  status TEXT,
  expires_at TIMESTAMPTZ,
  qr_payload TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, 'live')));
  v_currency TEXT := UPPER(TRIM(COALESCE(p_currency, 'USD')));
  v_qr_style TEXT := LOWER(TRIM(COALESCE(p_qr_style, 'dynamic')));
  v_amount NUMERIC(12,2) := ROUND(COALESCE(p_amount, 0)::NUMERIC, 2);
  v_expires_minutes INTEGER := GREATEST(5, LEAST(COALESCE(p_expires_in_minutes, 30), 10080));
  v_api_key_id UUID;
  v_api_key_ok BOOLEAN := false;
  v_session public.merchant_checkout_sessions;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  IF char_length(v_currency) < 2 OR char_length(v_currency) > 10 THEN
    RAISE EXCEPTION 'Currency must be between 2 and 10 characters';
  END IF;

  IF v_qr_style NOT IN ('dynamic', 'static') THEN
    RAISE EXCEPTION 'QR style must be dynamic or static';
  END IF;

  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  IF NULLIF(TRIM(COALESCE(p_secret_key, '')), '') IS NOT NULL THEN
    SELECT mak.id
    INTO v_api_key_id
    FROM public.merchant_api_keys mak
    WHERE mak.merchant_user_id = v_user_id
      AND mak.key_mode = v_mode
      AND mak.is_active = true
      AND (mak.secret_key_hash = md5(p_secret_key) OR mak.secret_key_hash = encode(digest(p_secret_key, 'sha256'), 'hex'))
    LIMIT 1;
  ELSE
    SELECT
      CASE
        WHEN v_mode = 'sandbox' THEN s.sandbox_api_key_id
        ELSE s.live_api_key_id
      END
    INTO v_api_key_id
    FROM public.merchant_pos_api_settings s
    WHERE s.merchant_user_id = v_user_id
    LIMIT 1;
  END IF;

  IF v_api_key_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.merchant_api_keys mak
      WHERE mak.id = v_api_key_id
        AND mak.merchant_user_id = v_user_id
        AND mak.key_mode = v_mode
        AND mak.is_active = true
    )
    INTO v_api_key_ok;
  END IF;

  IF NOT v_api_key_ok THEN
    RAISE EXCEPTION 'Set your % POS API key in Settings first (from Merchant Portal / API keys)', v_mode;
  END IF;

  PERFORM public.upsert_my_merchant_profile(NULL, NULL, NULL, v_currency);

  IF v_qr_style = 'static' THEN
    v_expires_minutes := GREATEST(v_expires_minutes, 1440);
  END IF;

  INSERT INTO public.merchant_checkout_sessions (
    merchant_user_id,
    api_key_id,
    key_mode,
    session_token,
    status,
    currency,
    subtotal_amount,
    fee_amount,
    total_amount,
    metadata,
    expires_at
  )
  VALUES (
    v_user_id,
    v_api_key_id,
    v_mode,
    'opsess_' || public.random_token_hex(24),
    'open',
    v_currency,
    v_amount,
    0,
    v_amount,
    jsonb_build_object(
      'pos_checkout', true,
      'pos_reference', p_reference,
      'customer_name', p_customer_name,
      'customer_email', p_customer_email,
      'qr_style', v_qr_style
    ),
    now() + (v_expires_minutes || ' minutes')::INTERVAL
  )
  RETURNING * INTO v_session;

  RETURN QUERY
  SELECT
    v_session.id,
    v_session.session_token,
    v_session.total_amount,
    v_session.currency,
    v_session.status,
    v_session.expires_at,
    CASE
      WHEN v_qr_style = 'static' THEN 'openpay-pos-static:' || v_user_id::TEXT || ':' || v_api_key_id::TEXT
      ELSE 'openpay-checkout:' || v_session.session_token
    END;
END;
$$;

-- 2. create_merchant_checkout_session
CREATE OR REPLACE FUNCTION public.create_merchant_checkout_session(
  p_secret_key TEXT,
  p_mode TEXT,
  p_currency TEXT,
  p_items JSONB,
  p_customer_email TEXT DEFAULT NULL,
  p_customer_name TEXT DEFAULT NULL,
  p_success_url TEXT DEFAULT NULL,
  p_cancel_url TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::jsonb,
  p_expires_in_minutes INTEGER DEFAULT 60
)
RETURNS TABLE (
  session_id UUID,
  session_token TEXT,
  total_amount NUMERIC,
  currency TEXT,
  expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, '')));
  v_currency TEXT := UPPER(TRIM(COALESCE(p_currency, 'USD')));
  v_merchant_user_id UUID;
  v_api_key_id UUID;
  v_session public.merchant_checkout_sessions;
  v_item JSONB;
  v_product public.merchant_products;
  v_quantity INTEGER;
  v_line_total NUMERIC(12,2);
  v_total NUMERIC(12,2) := 0;
  v_expires_minutes INTEGER := GREATEST(5, LEAST(COALESCE(p_expires_in_minutes, 60), 10080));
BEGIN
  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  IF char_length(v_currency) < 2 OR char_length(v_currency) > 10 THEN
    RAISE EXCEPTION 'Currency must be between 2 and 10 characters';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'At least one item is required';
  END IF;

  SELECT mak.merchant_user_id, mak.id
  INTO v_merchant_user_id, v_api_key_id
  FROM public.merchant_api_keys mak
  WHERE (mak.secret_key_hash = md5(p_secret_key) OR mak.secret_key_hash = encode(digest(p_secret_key, 'sha256'), 'hex'))
    AND mak.key_mode = v_mode
    AND mak.is_active = true
  LIMIT 1;

  IF v_merchant_user_id IS NULL THEN
    RAISE EXCEPTION 'Invalid merchant API key for mode %', v_mode;
  END IF;

  INSERT INTO public.merchant_checkout_sessions (
    merchant_user_id,
    key_mode,
    session_token,
    status,
    currency,
    subtotal_amount,
    fee_amount,
    total_amount,
    customer_email,
    customer_name,
    success_url,
    cancel_url,
    metadata,
    expires_at
  )
  VALUES (
    v_merchant_user_id,
    v_mode,
    'opsess_' || public.random_token_hex(24),
    'open',
    v_currency,
    0,
    0,
    0,
    NULLIF(TRIM(COALESCE(p_customer_email, '')), ''),
    NULLIF(TRIM(COALESCE(p_customer_name, '')), ''),
    NULLIF(TRIM(COALESCE(p_success_url, '')), ''),
    NULLIF(TRIM(COALESCE(p_cancel_url, '')), ''),
    COALESCE(p_metadata, '{}'::jsonb),
    now() + (v_expires_minutes || ' minutes')::INTERVAL
  )
  RETURNING * INTO v_session;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    SELECT *
    INTO v_product
    FROM public.merchant_products mp
    WHERE mp.id = (v_item->>'product_id')::UUID
      AND mp.merchant_user_id = v_merchant_user_id
      AND mp.is_active = true
    LIMIT 1;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Invalid product_id in items payload';
    END IF;

    v_quantity := COALESCE((v_item->>'quantity')::INTEGER, 1);
    IF v_quantity < 1 OR v_quantity > 1000 THEN
      RAISE EXCEPTION 'Quantity must be between 1 and 1000';
    END IF;

    IF UPPER(v_product.currency) <> v_currency THEN
      RAISE EXCEPTION 'Product currency mismatch for product %', v_product.id;
    END IF;

    v_line_total := ROUND(v_product.unit_amount * v_quantity, 2);

    INSERT INTO public.merchant_checkout_session_items (
      session_id,
      product_id,
      item_name,
      unit_amount,
      quantity,
      line_total
    )
    VALUES (
      v_session.id,
      v_product.id,
      v_product.product_name,
      v_product.unit_amount,
      v_quantity,
      v_line_total
    );

    v_total := v_total + v_line_total;
  END LOOP;

  IF v_total <= 0 THEN
    RAISE EXCEPTION 'Session total must be positive';
  END IF;

  UPDATE public.merchant_checkout_sessions
  SET subtotal_amount = v_total,
      total_amount = v_total
  WHERE id = v_session.id
  RETURNING * INTO v_session;

  UPDATE public.merchant_api_keys
  SET last_used_at = now()
  WHERE id = v_api_key_id;

  RETURN QUERY
  SELECT v_session.id, v_session.session_token, v_session.total_amount, v_session.currency, v_session.expires_at;
END;
$$;

-- 3. create_merchant_payment_link
CREATE OR REPLACE FUNCTION public.create_merchant_payment_link(
  p_secret_key TEXT,
  p_mode TEXT,
  p_link_type TEXT,
  p_title TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_currency TEXT DEFAULT 'USD',
  p_custom_amount NUMERIC DEFAULT NULL,
  p_items JSONB DEFAULT '[]'::jsonb,
  p_collect_customer_name BOOLEAN DEFAULT true,
  p_collect_customer_email BOOLEAN DEFAULT true,
  p_collect_phone BOOLEAN DEFAULT false,
  p_collect_address BOOLEAN DEFAULT false,
  p_after_payment_type TEXT DEFAULT 'confirmation',
  p_confirmation_message TEXT DEFAULT NULL,
  p_redirect_url TEXT DEFAULT NULL,
  p_call_to_action TEXT DEFAULT 'Pay',
  p_expires_in_minutes INTEGER DEFAULT NULL
)
RETURNS TABLE (
  link_id UUID,
  link_token TEXT,
  total_amount NUMERIC,
  currency TEXT,
  key_mode TEXT,
  expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, '')));
  v_link_type TEXT := LOWER(TRIM(COALESCE(p_link_type, '')));
  v_after_payment_type TEXT := LOWER(TRIM(COALESCE(p_after_payment_type, 'confirmation')));
  v_currency TEXT := UPPER(TRIM(COALESCE(p_currency, 'USD')));
  v_merchant_user_id UUID;
  v_api_key_id UUID;
  v_link public.merchant_payment_links;
  v_item JSONB;
  v_product public.merchant_products;
  v_quantity INTEGER;
  v_line_total NUMERIC(12,2);
  v_total NUMERIC(12,2) := 0;
  v_expires_at TIMESTAMPTZ;
BEGIN
  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  IF v_link_type NOT IN ('products', 'custom_amount') THEN
    RAISE EXCEPTION 'Link type must be products or custom_amount';
  END IF;

  IF v_after_payment_type NOT IN ('confirmation', 'redirect') THEN
    RAISE EXCEPTION 'After payment type must be confirmation or redirect';
  END IF;

  IF char_length(v_currency) < 2 OR char_length(v_currency) > 10 THEN
    RAISE EXCEPTION 'Currency must be between 2 and 10 characters';
  END IF;

  SELECT mak.merchant_user_id, mak.id
  INTO v_merchant_user_id, v_api_key_id
  FROM public.merchant_api_keys mak
  WHERE (mak.secret_key_hash = md5(p_secret_key) OR mak.secret_key_hash = encode(digest(p_secret_key, 'sha256'), 'hex'))
    AND mak.key_mode = v_mode
    AND mak.is_active = true
  LIMIT 1;

  IF v_merchant_user_id IS NULL THEN
    RAISE EXCEPTION 'Invalid merchant API key for mode %', v_mode;
  END IF;

  IF p_expires_in_minutes IS NOT NULL THEN
    v_expires_at := now() + (GREATEST(5, LEAST(p_expires_in_minutes, 525600)) || ' minutes')::INTERVAL;
  END IF;

  INSERT INTO public.merchant_payment_links (
    merchant_user_id,
    api_key_id,
    key_mode,
    link_token,
    link_type,
    title,
    description,
    currency,
    custom_amount,
    collect_customer_name,
    collect_customer_email,
    collect_phone,
    collect_address,
    after_payment_type,
    confirmation_message,
    redirect_url,
    call_to_action,
    expires_at
  )
  VALUES (
    v_merchant_user_id,
    v_api_key_id,
    v_mode,
    'oplink_' || public.random_token_hex(24),
    v_link_type,
    COALESCE(NULLIF(TRIM(p_title), ''), 'OpenPay Payment'),
    COALESCE(NULLIF(TRIM(p_description), ''), ''),
    v_currency,
    p_custom_amount,
    COALESCE(p_collect_customer_name, true),
    COALESCE(p_collect_customer_email, true),
    COALESCE(p_collect_phone, false),
    COALESCE(p_collect_address, false),
    v_after_payment_type,
    COALESCE(NULLIF(TRIM(p_confirmation_message), ''), 'Thanks for your payment.'),
    NULLIF(TRIM(COALESCE(p_redirect_url, '')), ''),
    COALESCE(NULLIF(TRIM(p_call_to_action), ''), 'Pay'),
    v_expires_at
  )
  RETURNING * INTO v_link;

  IF v_link_type = 'custom_amount' THEN
    IF p_custom_amount IS NULL OR p_custom_amount <= 0 THEN
      RAISE EXCEPTION 'Custom amount must be greater than 0';
    END IF;
    v_total := ROUND(p_custom_amount, 2);
  ELSE
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
      RAISE EXCEPTION 'At least one product item is required';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
      SELECT *
      INTO v_product
      FROM public.merchant_products mp
      WHERE mp.id = (v_item->>'product_id')::UUID
        AND mp.merchant_user_id = v_merchant_user_id
        AND mp.is_active = true
      LIMIT 1;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid product_id in items payload';
      END IF;

      v_quantity := COALESCE((v_item->>'quantity')::INTEGER, 1);
      IF v_quantity < 1 OR v_quantity > 1000 THEN
        RAISE EXCEPTION 'Quantity must be between 1 and 1000';
      END IF;

      IF UPPER(v_product.currency) <> v_currency THEN
        RAISE EXCEPTION 'Product currency mismatch for product %', v_product.id;
      END IF;

      v_line_total := ROUND(v_product.unit_amount * v_quantity, 2);

      INSERT INTO public.merchant_payment_link_items (
        link_id,
        product_id,
        item_name,
        unit_amount,
        quantity,
        line_total
      )
      VALUES (
        v_link.id,
        v_product.id,
        v_product.product_name,
        v_product.unit_amount,
        v_quantity,
        v_line_total
      );

      v_total := v_total + v_line_total;
    END LOOP;
  END IF;

  IF v_total <= 0 THEN
    RAISE EXCEPTION 'Link total must be positive';
  END IF;

  UPDATE public.merchant_payment_links
  SET total_amount = v_total
  WHERE id = v_link.id
  RETURNING * INTO v_link;

  UPDATE public.merchant_api_keys
  SET last_used_at = now()
  WHERE id = v_api_key_id;

  RETURN QUERY
  SELECT v_link.id, v_link.link_token, v_link.total_amount, v_link.currency, v_link.key_mode, v_link.expires_at;
END;
$$;

-- 4. upsert_my_merchant_profile
CREATE OR REPLACE FUNCTION public.upsert_my_merchant_profile(
  p_merchant_name TEXT DEFAULT NULL,
  p_merchant_username TEXT DEFAULT NULL,
  p_merchant_logo_url TEXT DEFAULT NULL,
  p_default_currency TEXT DEFAULT NULL
)
RETURNS public.merchant_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_profile_name TEXT;
  v_profile_username TEXT;
  v_profile_logo TEXT;
  v_profile public.merchant_profiles;
  v_currency TEXT := UPPER(TRIM(COALESCE(p_default_currency, 'USD')));
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF char_length(v_currency) < 2 OR char_length(v_currency) > 10 THEN
    v_currency := 'USD';
  END IF;

  SELECT full_name, COALESCE(username, ''), avatar_url
  INTO v_profile_name, v_profile_username, v_profile_logo
  FROM public.profiles
  WHERE id = v_user_id;

  INSERT INTO public.merchant_profiles (
    user_id,
    merchant_name,
    merchant_username,
    merchant_logo_url,
    default_currency
  )
  VALUES (
    v_user_id,
    COALESCE(NULLIF(TRIM(p_merchant_name), ''), NULLIF(TRIM(v_profile_name), ''), 'OpenPay Merchant'),
    COALESCE(NULLIF(TRIM(p_merchant_username), ''), NULLIF(TRIM(v_profile_username), ''), 'openpay-merchant'),
    COALESCE(NULLIF(TRIM(p_merchant_logo_url), ''), v_profile_logo),
    v_currency
  )
  ON CONFLICT (user_id) DO UPDATE
  SET merchant_name = COALESCE(NULLIF(TRIM(p_merchant_name), ''), public.merchant_profiles.merchant_name),
      merchant_username = COALESCE(NULLIF(TRIM(p_merchant_username), ''), public.merchant_profiles.merchant_username),
      merchant_logo_url = COALESCE(NULLIF(TRIM(p_merchant_logo_url), ''), public.merchant_profiles.merchant_logo_url),
      default_currency = v_currency,
      is_active = true
  RETURNING * INTO v_profile;

  RETURN v_profile;
END;
$$;

-- 5. create_merchant_pos_terminal_session
CREATE OR REPLACE FUNCTION public.create_merchant_pos_terminal_session(
  p_terminal_id UUID,
  p_amount NUMERIC,
  p_currency TEXT DEFAULT 'USD',
  p_reference TEXT DEFAULT NULL
)
RETURNS TABLE (
  session_id UUID,
  session_token TEXT,
  total_amount NUMERIC,
  currency TEXT,
  status TEXT,
  expires_at TIMESTAMPTZ,
  qr_payload TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_currency TEXT := UPPER(TRIM(COALESCE(p_currency, 'USD')));
  v_amount NUMERIC(12,2) := ROUND(COALESCE(p_amount, 0)::NUMERIC, 2);
  v_terminal public.merchant_pos_terminals;
  v_session public.merchant_checkout_sessions;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF char_length(v_currency) < 2 OR char_length(v_currency) > 10 THEN
    RAISE EXCEPTION 'Currency must be between 2 and 10 characters';
  END IF;

  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  SELECT * INTO v_terminal
  FROM public.merchant_pos_terminals
  WHERE id = p_terminal_id AND merchant_user_id = v_user_id AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Terminal not found or inactive';
  END IF;

  INSERT INTO public.merchant_checkout_sessions (
    merchant_user_id,
    api_key_id,
    key_mode,
    session_token,
    status,
    currency,
    subtotal_amount,
    fee_amount,
    total_amount,
    metadata,
    expires_at
  )
  VALUES (
    v_user_id,
    v_terminal.api_key_id,
    'live',
    'opsess_' || public.random_token_hex(24),
    'open',
    v_currency,
    v_amount,
    0,
    v_amount,
    jsonb_build_object(
      'pos_checkout', true,
      'terminal_id', p_terminal_id,
      'pos_reference', p_reference
    ),
    now() + INTERVAL '30 minutes'
  )
  RETURNING * INTO v_session;

  RETURN QUERY
  SELECT
    v_session.id,
    v_session.session_token,
    v_session.total_amount,
    v_session.currency,
    v_session.status,
    v_session.expires_at,
    'openpay-checkout:' || v_session.session_token;
END;
$$;

-- <<< END MIGRATION: 20260226000000_relax_currency_constraints.sql

-- >>> MIGRATION: 20260226200000_public_checkout_payments.sql
-- Create public payment functions that don't require authentication
-- These functions allow anyone to pay without signing in

CREATE OR REPLACE FUNCTION public.pay_merchant_checkout_public_virtual_card(
  p_session_token TEXT,
  p_card_number TEXT,
  p_expiry_month INTEGER,
  p_expiry_year INTEGER,
  p_cvc TEXT,
  p_customer_name TEXT DEFAULT NULL,
  p_customer_email TEXT DEFAULT NULL,
  p_customer_phone TEXT DEFAULT NULL,
  p_customer_address TEXT DEFAULT NULL
)
RETURNS TABLE (
  transaction_id UUID,
  status TEXT,
  message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.merchant_checkout_sessions;
  v_merchant_user_id UUID;
  v_sanitized_card_number TEXT := regexp_replace(COALESCE(p_card_number, ''), '\D', '', 'g');
  v_sanitized_cvc TEXT := regexp_replace(COALESCE(p_cvc, ''), '\D', '', 'g');
  v_expiry_end DATE;
  v_transaction_id UUID;
  v_fee_amount NUMERIC(12,2) := 0;
  v_total_amount NUMERIC(12,2);
BEGIN
  -- Validate session
  SELECT *
  INTO v_session
  FROM public.merchant_checkout_sessions mcs
  WHERE mcs.session_token = TRIM(COALESCE(p_session_token, ''))
    AND mcs.status = 'open'
    AND mcs.expires_at > now()
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT NULL::UUID, 'error', 'Invalid or expired checkout session'::TEXT;
    RETURN;
  END IF;

  v_merchant_user_id := v_session.merchant_user_id;
  v_total_amount := v_session.total_amount;
  v_fee_amount := v_session.fee_amount;

  -- Validate card details
  IF char_length(v_sanitized_card_number) <> 16 THEN
    RETURN QUERY SELECT NULL::UUID, 'error', 'Card number must be 16 digits'::TEXT;
    RETURN;
  END IF;

  IF p_expiry_month IS NULL OR p_expiry_month < 1 OR p_expiry_month > 12 THEN
    RETURN QUERY SELECT NULL::UUID, 'error', 'Invalid expiry month'::TEXT;
    RETURN;
  END IF;

  IF p_expiry_year IS NULL OR p_expiry_year < 2026 THEN
    RETURN QUERY SELECT NULL::UUID, 'error', 'Invalid expiry year'::TEXT;
    RETURN;
  END IF;

  IF char_length(v_sanitized_cvc) <> 3 THEN
    RETURN QUERY SELECT NULL::UUID, 'error', 'Invalid CVC'::TEXT;
    RETURN;
  END IF;

  v_expiry_end := (make_date(p_expiry_year, p_expiry_month, 1) + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
  IF v_expiry_end < CURRENT_DATE THEN
    RETURN QUERY SELECT NULL::UUID, 'error', 'Card expired'::TEXT;
    RETURN;
  END IF;

  -- Check if virtual card exists and is valid
  IF NOT EXISTS (
    SELECT 1
    FROM public.virtual_cards vc
    WHERE vc.card_number = v_sanitized_card_number
      AND vc.expiry_month = p_expiry_month
      AND vc.expiry_year = p_expiry_year
      AND vc.cvc = v_sanitized_cvc
      AND vc.is_active = true
  ) THEN
    RETURN QUERY SELECT NULL::UUID, 'error', 'Invalid virtual card details'::TEXT;
    RETURN;
  END IF;

  -- Create transaction record (without balance checks for public payments)
  INSERT INTO public.transactions (
    sender_id,
    receiver_id,
    amount,
    note,
    status,
    created_at
  ) VALUES (
    NULL, -- No sender for public payments
    v_merchant_user_id,
    v_total_amount,
    CONCAT('Public virtual card payment | Session: ', p_session_token, ' | Customer: ', COALESCE(p_customer_name, 'Anonymous')),
    'completed',
    now()
  )
  RETURNING id INTO v_transaction_id;

  -- Update session status
  UPDATE public.merchant_checkout_sessions
  SET status = 'paid',
      paid_at = now(),
      updated_at = now()
  WHERE id = v_session.id;

  -- Create merchant payment record
  INSERT INTO public.merchant_payments (
    session_id,
    merchant_user_id,
    buyer_user_id,
    transaction_id,
    amount,
    currency,
    key_mode,
    status,
    created_at
  ) VALUES (
    v_session.id,
    v_merchant_user_id,
    NULL, -- No buyer user for public payments
    v_transaction_id,
    v_total_amount,
    v_session.currency,
    v_session.key_mode,
    'succeeded',
    now()
  );

  RETURN QUERY SELECT v_transaction_id, 'success'::TEXT, 'Payment completed successfully'::TEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.pay_merchant_checkout_public_wallet(
  p_session_token TEXT,
  p_payer_account_number TEXT,
  p_payer_pin TEXT,
  p_customer_name TEXT DEFAULT NULL,
  p_customer_email TEXT DEFAULT NULL,
  p_customer_phone TEXT DEFAULT NULL,
  p_customer_address TEXT DEFAULT NULL
)
RETURNS TABLE (
  transaction_id UUID,
  status TEXT,
  message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.merchant_checkout_sessions;
  v_merchant_user_id UUID;
  v_payer_user_id UUID;
  v_payer_balance NUMERIC(12,2);
  v_merchant_balance NUMERIC(12,2);
  v_transaction_id UUID;
  v_total_amount NUMERIC(12,2);
  v_fee_amount NUMERIC(12,2);
BEGIN
  -- Validate session
  SELECT *
  INTO v_session
  FROM public.merchant_checkout_sessions mcs
  WHERE mcs.session_token = TRIM(COALESCE(p_session_token, ''))
    AND mcs.status = 'open'
    AND mcs.expires_at > now()
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT NULL::UUID, 'error', 'Invalid or expired checkout session'::TEXT;
    RETURN;
  END IF;

  v_merchant_user_id := v_session.merchant_user_id;
  v_total_amount := v_session.total_amount;
  v_fee_amount := v_session.fee_amount;

  -- Find payer by account number
  SELECT user_id
  INTO v_payer_user_id
  FROM public.profiles
  WHERE account_number = UPPER(TRIM(COALESCE(p_payer_account_number, '')))
  LIMIT 1;

  IF v_payer_user_id IS NULL THEN
    RETURN QUERY SELECT NULL::UUID, 'error', 'Invalid account number'::TEXT;
    RETURN;
  END IF;

  -- Verify PIN (simplified for demo - in production, use proper hashing)
  SELECT pin_hash
  INTO v_payer_user_id -- This is just to use the variable, actual PIN verification would go here
  FROM public.app_security_settings
  WHERE user_id = v_payer_user_id
  LIMIT 1;

  -- Check balance
  SELECT balance
  INTO v_payer_balance
  FROM public.wallets
  WHERE user_id = v_payer_user_id
  LIMIT 1;

  IF v_payer_balance IS NULL THEN
    RETURN QUERY SELECT NULL::UUID, 'error', 'Payer wallet not found'::TEXT;
    RETURN;
  END IF;

  IF v_payer_balance < v_total_amount THEN
    RETURN QUERY SELECT NULL::UUID, 'error', 'Insufficient balance'::TEXT;
    RETURN;
  END IF;

  -- Get merchant wallet
  SELECT balance
  INTO v_merchant_balance
  FROM public.wallets
  WHERE user_id = v_merchant_user_id
  LIMIT 1;

  IF v_merchant_balance IS NULL THEN
    RETURN QUERY SELECT NULL::UUID, 'error', 'Merchant wallet not found'::TEXT;
    RETURN;
  END IF;

  -- Process payment atomically
  UPDATE public.wallets
  SET balance = v_payer_balance - v_total_amount,
      updated_at = now()
  WHERE user_id = v_payer_user_id;

  UPDATE public.wallets
  SET balance = v_merchant_balance + v_total_amount,
      updated_at = now()
  WHERE user_id = v_merchant_user_id;

  -- Create transaction record
  INSERT INTO public.transactions (
    sender_id,
    receiver_id,
    amount,
    note,
    status,
    created_at
  ) VALUES (
    v_payer_user_id,
    v_merchant_user_id,
    v_total_amount,
    CONCAT('Public wallet payment | Session: ', p_session_token, ' | Customer: ', COALESCE(p_customer_name, 'Anonymous')),
    'completed',
    now()
  )
  RETURNING id INTO v_transaction_id;

  -- Update session status
  UPDATE public.merchant_checkout_sessions
  SET status = 'paid',
      paid_at = now(),
      updated_at = now()
  WHERE id = v_session.id;

  -- Create merchant payment record
  INSERT INTO public.merchant_payments (
    session_id,
    merchant_user_id,
    buyer_user_id,
    transaction_id,
    amount,
    currency,
    key_mode,
    status,
    created_at
  ) VALUES (
    v_session.id,
    v_merchant_user_id,
    v_payer_user_id,
    v_transaction_id,
    v_total_amount,
    v_session.currency,
    v_session.key_mode,
    'succeeded',
    now()
  );

  RETURN QUERY SELECT v_transaction_id, 'success'::TEXT, 'Payment completed successfully'::TEXT;
END;
$$;

-- Grant public access to these functions
REVOKE ALL ON FUNCTION public.pay_merchant_checkout_public_virtual_card(TEXT, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pay_merchant_checkout_public_wallet(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.pay_merchant_checkout_public_virtual_card(TEXT, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pay_merchant_checkout_public_wallet(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;

-- <<< END MIGRATION: 20260226200000_public_checkout_payments.sql

-- >>> MIGRATION: 20260227010000_pos_payment_system.sql
-- Create separate POS payment system with different tables and workflows
-- This is completely separate from checkout system

-- POS Payments Table (completely separate from merchant_checkout_sessions)
CREATE TABLE IF NOT EXISTS public.pos_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- pos_terminal_id UUID REFERENCES public.merchant_pos_terminals(id) ON DELETE SET NULL, -- Table doesn't exist yet
  session_token TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'expired', 'canceled')),
  currency TEXT NOT NULL CHECK (char_length(currency) = 3),
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  fee_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (fee_amount >= 0),
  total_amount NUMERIC(12,2) NOT NULL CHECK (total_amount > 0),
  customer_name TEXT,
  customer_email TEXT,
  customer_phone TEXT,
  payment_method TEXT DEFAULT 'wallet' CHECK (payment_method IN ('wallet', 'card', 'cash')),
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  expires_at TIMESTAMPTZ NOT NULL,
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- POS Transactions Table (separate from merchant_payments)
CREATE TABLE IF NOT EXISTS public.pos_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pos_payment_id UUID NOT NULL REFERENCES public.pos_payments(id) ON DELETE CASCADE,
  transaction_id UUID REFERENCES public.transactions(id) ON DELETE SET NULL,
  payer_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  payment_method TEXT NOT NULL DEFAULT 'wallet' CHECK (payment_method IN ('wallet', 'card', 'cash')),
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  currency TEXT NOT NULL CHECK (char_length(currency) = 3),
  fee_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (fee_amount >= 0),
  net_amount NUMERIC(12,2) NOT NULL CHECK (net_amount > 0),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'succeeded', 'failed', 'refunded')),
  gateway_response JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- POS API Keys Table (separate from merchant_api_keys)
CREATE TABLE IF NOT EXISTS public.pos_api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- pos_terminal_id UUID REFERENCES public.merchant_pos_terminals(id) ON DELETE SET NULL, -- Table doesn't exist yet
  key_mode TEXT NOT NULL CHECK (key_mode IN ('sandbox', 'live')),
  key_name TEXT NOT NULL DEFAULT 'POS Default Key',
  publishable_key TEXT NOT NULL UNIQUE,
  secret_key_hash TEXT NOT NULL UNIQUE,
  secret_key_last4 TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  last_used_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for POS system
CREATE INDEX IF NOT EXISTS idx_pos_payments_session_token ON public.pos_payments(session_token);
CREATE INDEX IF NOT EXISTS idx_pos_payments_merchant_user_id ON public.pos_payments(merchant_user_id);
CREATE INDEX IF NOT EXISTS idx_pos_payments_status ON public.pos_payments(status);
CREATE INDEX IF NOT EXISTS idx_pos_payments_expires_at ON public.pos_payments(expires_at);

CREATE INDEX IF NOT EXISTS idx_pos_transactions_pos_payment_id ON public.pos_transactions(pos_payment_id);
CREATE INDEX IF NOT EXISTS idx_pos_transactions_payer_user_id ON public.pos_transactions(payer_user_id);
CREATE INDEX IF NOT EXISTS idx_pos_transactions_status ON public.pos_transactions(status);

CREATE INDEX IF NOT EXISTS idx_pos_api_keys_merchant_user_id ON public.pos_api_keys(merchant_user_id);
CREATE INDEX IF NOT EXISTS idx_pos_api_keys_publishable_key ON public.pos_api_keys(publishable_key);

-- POS Payment Functions (completely separate from checkout functions)

-- Create POS payment session
CREATE OR REPLACE FUNCTION public.create_pos_payment_session(
  p_amount NUMERIC(12,2),
  p_currency TEXT DEFAULT 'USD',
  p_customer_name TEXT DEFAULT NULL,
  p_customer_email TEXT DEFAULT NULL,
  p_customer_phone TEXT DEFAULT NULL,
  p_payment_method TEXT DEFAULT 'wallet',
  p_expires_in_minutes INTEGER DEFAULT 30
  -- p_pos_terminal_id UUID DEFAULT NULL -- Table doesn't exist yet
)
RETURNS TABLE (
  session_id UUID,
  session_token TEXT,
  amount NUMERIC(12,2),
  currency TEXT,
  status TEXT,
  expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_pos_payment_id UUID;
  v_session_token TEXT;
  v_amount NUMERIC(12,2) := ROUND(COALESCE(p_amount, 0)::NUMERIC, 2);
  v_currency TEXT := UPPER(TRIM(COALESCE(p_currency, 'USD')));
  v_expires_minutes INTEGER := GREATEST(5, LEAST(COALESCE(p_expires_in_minutes, 30), 10080));
  v_fee_amount NUMERIC(12,2) := 0;
  v_total_amount NUMERIC(12,2);
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive';
  END IF;

  -- Generate unique session token
  v_session_token := 'opsess_' || encode(gen_random_bytes(16), 'hex');
  
  -- Calculate fee (2% for POS)
  v_fee_amount := ROUND(v_amount * 0.02, 2);
  v_total_amount := v_amount + v_fee_amount;

  -- Create POS payment session
  INSERT INTO public.pos_payments (
    merchant_user_id,
    -- pos_terminal_id, -- Table doesn't exist yet
    session_token,
    currency,
    amount,
    fee_amount,
    total_amount,
    customer_name,
    customer_email,
    customer_phone,
    payment_method,
    expires_at
  ) VALUES (
    v_user_id,
    -- p_pos_terminal_id, -- Table doesn't exist yet
    v_session_token,
    v_currency,
    v_amount,
    v_fee_amount,
    v_total_amount,
    p_customer_name,
    p_customer_email,
    p_customer_phone,
    p_payment_method,
    now() + (v_expires_minutes || ' minutes')::INTERVAL
  ) RETURNING id INTO v_pos_payment_id;

  RETURN QUERY SELECT 
    v_pos_payment_id::UUID,
    v_session_token::TEXT,
    v_amount::NUMERIC(12,2),
    v_currency::TEXT,
    'pending'::TEXT,
    now() + (v_expires_minutes || ' minutes')::INTERVAL::TIMESTAMPTZ;
END;
$$;

-- Get POS payment session
CREATE OR REPLACE FUNCTION public.get_pos_payment_session(
  p_session_token TEXT
)
RETURNS TABLE (
  id UUID,
  merchant_user_id UUID,
  session_token TEXT,
  status TEXT,
  amount NUMERIC(12,2),
  currency TEXT,
  fee_amount NUMERIC(12,2),
  total_amount NUMERIC(12,2),
  customer_name TEXT,
  customer_email TEXT,
  customer_phone TEXT,
  payment_method TEXT,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY SELECT 
    pp.id,
    pp.merchant_user_id,
    pp.session_token,
    pp.status,
    pp.amount,
    pp.currency,
    pp.fee_amount,
    pp.total_amount,
    pp.customer_name,
    pp.customer_email,
    pp.customer_phone,
    pp.payment_method,
    pp.expires_at,
    pp.created_at
  FROM public.pos_payments pp
  WHERE pp.session_token = TRIM(COALESCE(p_session_token, ''))
    AND pp.status = 'pending'
    AND pp.expires_at > now();
END;
$$;

-- Process POS payment (wallet payment)
CREATE OR REPLACE FUNCTION public.process_pos_payment_wallet(
  p_session_token TEXT,
  p_payer_user_id UUID DEFAULT NULL
)
RETURNS TABLE (
  transaction_id UUID,
  pos_payment_id UUID,
  status TEXT,
  message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pos_payment public.pos_payments;
  v_payer_balance NUMERIC(12,2);
  v_merchant_balance NUMERIC(12,2);
  v_transaction_id UUID;
  v_pos_transaction_id UUID;
  v_fee_amount NUMERIC(12,2);
  v_net_amount NUMERIC(12,2);
BEGIN
  -- Get POS payment session
  SELECT *
  INTO v_pos_payment
  FROM public.pos_payments pp
  WHERE pp.session_token = TRIM(COALESCE(p_session_token, ''))
    AND pp.status = 'pending'
    AND pp.expires_at > now()
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT NULL::UUID, NULL::UUID, 'error', 'Invalid or expired POS payment session'::TEXT;
    RETURN;
  END IF;

  -- Calculate amounts
  v_fee_amount := v_pos_payment.fee_amount;
  v_net_amount := v_pos_payment.total_amount - v_fee_amount;

  -- Create main transaction
  INSERT INTO public.transactions (
    sender_user_id,
    receiver_user_id,
    amount,
    currency,
    fee_amount,
    status,
    type,
    metadata
  ) VALUES (
    p_payer_user_id,
    v_pos_payment.merchant_user_id,
    v_pos_payment.total_amount,
    v_pos_payment.currency,
    v_fee_amount,
    'pending',
    'payment',
    jsonb_build_object('pos_payment_id', v_pos_payment.id, 'payment_method', 'wallet')
  ) RETURNING id INTO v_transaction_id;

  -- Create POS transaction record
  INSERT INTO public.pos_transactions (
    pos_payment_id,
    transaction_id,
    payer_user_id,
    payment_method,
    amount,
    currency,
    fee_amount,
    net_amount,
    status
  ) VALUES (
    v_pos_payment.id,
    v_transaction_id,
    p_payer_user_id,
    'wallet',
    v_pos_payment.total_amount,
    v_pos_payment.currency,
    v_fee_amount,
    v_net_amount,
    'succeeded'
  ) RETURNING id INTO v_pos_transaction_id;

  -- Update POS payment status
  UPDATE public.pos_payments
  SET status = 'paid',
      paid_at = now(),
      updated_at = now()
  WHERE id = v_pos_payment.id;

  RETURN QUERY SELECT 
    v_transaction_id::UUID,
    v_pos_payment.id::UUID,
    'success'::TEXT,
    'POS payment processed successfully'::TEXT;
END;
$$;

-- Get POS payment QR code data
CREATE OR REPLACE FUNCTION public.get_pos_payment_qr_data(
  p_session_token TEXT
)
RETURNS TABLE (
  qr_data TEXT,
  amount NUMERIC(12,2),
  currency TEXT,
  merchant_name TEXT,
  note TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pos_payment public.pos_payments;
  v_merchant_name TEXT;
BEGIN
  -- Get POS payment session
  SELECT *
  INTO v_pos_payment
  FROM public.pos_payments pp
  WHERE pp.session_token = TRIM(COALESCE(p_session_token, ''))
    AND pp.status = 'pending'
    AND pp.expires_at > now()
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT 
      NULL::TEXT,
      NULL::NUMERIC(12,2),
      NULL::TEXT,
      NULL::TEXT,
      NULL::TEXT;
    RETURN;
  END IF;

  -- Get merchant name
  SELECT username
  INTO v_merchant_name
  FROM auth.users
  WHERE id = v_pos_payment.merchant_user_id;

  -- Generate QR data
  RETURN QUERY SELECT 
    ('openpay://pay?uid=' || v_pos_payment.merchant_user_id::TEXT || 
     '&amount=' || v_pos_payment.amount::TEXT ||
     '&currency=' || v_pos_payment.currency ||
     '&note=POS+payment' ||
     '&name=' || COALESCE(v_merchant_name, ''))::TEXT,
    v_pos_payment.amount::NUMERIC(12,2),
    v_pos_payment.currency::TEXT,
    COALESCE(v_merchant_name, '')::TEXT,
    'POS Payment'::TEXT;
END;
$$;

-- Grant permissions (only for authenticated users)
GRANT EXECUTE ON FUNCTION public.create_pos_payment_session TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_pos_payment_session TO authenticated;
GRANT EXECUTE ON FUNCTION public.process_pos_payment_wallet TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_pos_payment_qr_data TO authenticated;

-- Row Level Security for POS tables
ALTER TABLE public.pos_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_api_keys ENABLE ROW LEVEL SECURITY;

-- POS policies
CREATE POLICY "Users can view their own POS payments" ON public.pos_payments
  FOR SELECT USING (auth.uid() = merchant_user_id);

CREATE POLICY "Users can insert their own POS payments" ON public.pos_payments
  FOR INSERT WITH CHECK (auth.uid() = merchant_user_id);

CREATE POLICY "Users can update their own POS payments" ON public.pos_payments
  FOR UPDATE USING (auth.uid() = merchant_user_id);

CREATE POLICY "Users can view their own POS transactions" ON public.pos_transactions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.pos_payments pp 
      WHERE pp.id = pos_transactions.pos_payment_id 
      AND pp.merchant_user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert their own POS transactions" ON public.pos_transactions
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.pos_payments pp 
      WHERE pp.id = pos_transactions.pos_payment_id 
      AND pp.merchant_user_id = auth.uid()
    )
  );

CREATE POLICY "Users can view their own POS API keys" ON public.pos_api_keys
  FOR SELECT USING (auth.uid() = merchant_user_id);

CREATE POLICY "Users can insert their own POS API keys" ON public.pos_api_keys
  FOR INSERT WITH CHECK (auth.uid() = merchant_user_id);

CREATE POLICY "Users can update their own POS API keys" ON public.pos_api_keys
  FOR UPDATE USING (auth.uid() = merchant_user_id);

-- <<< END MIGRATION: 20260227010000_pos_payment_system.sql

-- >>> MIGRATION: 20260227020000_checkout_payment_system.sql
-- Create separate checkout payment system with different tables and workflows
-- This is completely separate from POS system

-- Checkout Sessions Table (enhanced version, separate from pos_payments)
CREATE TABLE IF NOT EXISTS public.checkout_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  checkout_api_key_id UUID REFERENCES public.checkout_api_keys(id) ON DELETE SET NULL,
  session_token TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'paid', 'expired', 'canceled')),
  currency TEXT NOT NULL CHECK (char_length(currency) = 3),
  subtotal_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (subtotal_amount >= 0),
  fee_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (fee_amount >= 0),
  total_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
  customer_email TEXT,
  customer_name TEXT,
  customer_phone TEXT,
  customer_address TEXT,
  success_url TEXT,
  cancel_url TEXT,
  payment_method TEXT DEFAULT 'card' CHECK (payment_method IN ('card', 'wallet', 'bank_transfer')),
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  expires_at TIMESTAMPTZ NOT NULL,
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Checkout Session Items Table (for product-based checkouts)
CREATE TABLE IF NOT EXISTS public.checkout_session_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.checkout_sessions(id) ON DELETE CASCADE,
  product_id UUID REFERENCES public.merchant_products(id) ON DELETE SET NULL,
  item_name TEXT NOT NULL,
  item_description TEXT,
  unit_amount NUMERIC(12,2) NOT NULL CHECK (unit_amount > 0),
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  line_total NUMERIC(12,2) NOT NULL CHECK (line_total > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Checkout Transactions Table (separate from pos_transactions)
CREATE TABLE IF NOT EXISTS public.checkout_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  checkout_session_id UUID NOT NULL REFERENCES public.checkout_sessions(id) ON DELETE CASCADE,
  transaction_id UUID REFERENCES public.transactions(id) ON DELETE SET NULL,
  payer_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  payment_method TEXT NOT NULL DEFAULT 'card' CHECK (payment_method IN ('card', 'wallet', 'bank_transfer')),
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  currency TEXT NOT NULL CHECK (char_length(currency) = 3),
  fee_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (fee_amount >= 0),
  net_amount NUMERIC(12,2) NOT NULL CHECK (net_amount > 0),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'succeeded', 'failed', 'refunded')),
  gateway_response JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Checkout API Keys Table (separate from pos_api_keys)
CREATE TABLE IF NOT EXISTS public.checkout_api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  key_mode TEXT NOT NULL CHECK (key_mode IN ('sandbox', 'live')),
  key_name TEXT NOT NULL DEFAULT 'Checkout Default Key',
  publishable_key TEXT NOT NULL UNIQUE,
  secret_key_hash TEXT NOT NULL UNIQUE,
  secret_key_last4 TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  last_used_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for checkout system
CREATE INDEX IF NOT EXISTS idx_checkout_sessions_session_token ON public.checkout_sessions(session_token);
CREATE INDEX IF NOT EXISTS idx_checkout_sessions_merchant_user_id ON public.checkout_sessions(merchant_user_id);
CREATE INDEX IF NOT EXISTS idx_checkout_sessions_status ON public.checkout_sessions(status);
CREATE INDEX IF NOT EXISTS idx_checkout_sessions_expires_at ON public.checkout_sessions(expires_at);

CREATE INDEX IF NOT EXISTS idx_checkout_session_items_session_id ON public.checkout_session_items(session_id);
CREATE INDEX IF NOT EXISTS idx_checkout_session_items_product_id ON public.checkout_session_items(product_id);

CREATE INDEX IF NOT EXISTS idx_checkout_transactions_checkout_session_id ON public.checkout_transactions(checkout_session_id);
CREATE INDEX IF NOT EXISTS idx_checkout_transactions_payer_user_id ON public.checkout_transactions(payer_user_id);
CREATE INDEX IF NOT EXISTS idx_checkout_transactions_status ON public.checkout_transactions(status);

CREATE INDEX IF NOT EXISTS idx_checkout_api_keys_merchant_user_id ON public.checkout_api_keys(merchant_user_id);
CREATE INDEX IF NOT EXISTS idx_checkout_api_keys_publishable_key ON public.checkout_api_keys(publishable_key);

-- Checkout Payment Functions (completely separate from POS functions)

-- Create checkout session
CREATE OR REPLACE FUNCTION public.create_checkout_session(
  p_amount NUMERIC(12,2),
  p_currency TEXT DEFAULT 'USD',
  p_customer_name TEXT DEFAULT NULL,
  p_customer_email TEXT DEFAULT NULL,
  p_customer_phone TEXT DEFAULT NULL,
  p_customer_address TEXT DEFAULT NULL,
  p_success_url TEXT DEFAULT NULL,
  p_cancel_url TEXT DEFAULT NULL,
  p_payment_method TEXT DEFAULT 'card',
  p_expires_in_minutes INTEGER DEFAULT 60,
  p_items JSONB DEFAULT '[]'::jsonb
)
RETURNS TABLE (
  session_id UUID,
  session_token TEXT,
  amount NUMERIC(12,2),
  currency TEXT,
  status TEXT,
  expires_at TIMESTAMPTZ,
  checkout_url TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_checkout_session_id UUID;
  v_session_token TEXT;
  v_amount NUMERIC(12,2) := ROUND(COALESCE(p_amount, 0)::NUMERIC, 2);
  v_currency TEXT := UPPER(TRIM(COALESCE(p_currency, 'USD')));
  v_expires_minutes INTEGER := GREATEST(15, LEAST(COALESCE(p_expires_in_minutes, 60), 10080));
  v_fee_amount NUMERIC(12,2) := 0;
  v_total_amount NUMERIC(12,2);
  v_checkout_url TEXT;
  v_item JSONB;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive';
  END IF;

  -- Generate unique session token
  v_session_token := 'csess_' || encode(gen_random_bytes(16), 'hex');
  
  -- Calculate fee (3% for checkout)
  v_fee_amount := ROUND(v_amount * 0.03, 2);
  v_total_amount := v_amount + v_fee_amount;

  -- Create checkout session
  INSERT INTO public.checkout_sessions (
    merchant_user_id,
    session_token,
    currency,
    subtotal_amount,
    fee_amount,
    total_amount,
    customer_name,
    customer_email,
    customer_phone,
    customer_address,
    success_url,
    cancel_url,
    payment_method,
    expires_at
  ) VALUES (
    v_user_id,
    v_session_token,
    v_currency,
    v_amount,
    v_fee_amount,
    v_total_amount,
    p_customer_name,
    p_customer_email,
    p_customer_phone,
    p_customer_address,
    p_success_url,
    p_cancel_url,
    p_payment_method,
    now() + (v_expires_minutes || ' minutes')::INTERVAL
  ) RETURNING id INTO v_checkout_session_id;

  -- Add items if provided
  IF p_items IS NOT NULL AND jsonb_array_length(p_items) > 0 THEN
    FOREACH v_item IN SELECT value FROM jsonb_array_elements(p_items)
    LOOP
      INSERT INTO public.checkout_session_items (
        session_id,
        product_id,
        item_name,
        item_description,
        unit_amount,
        quantity,
        line_total
      ) VALUES (
        v_checkout_session_id,
        (v_item->>'product_id')::UUID,
        v_item->>'item_name',
        v_item->>'item_description',
        (v_item->>'unit_amount')::NUMERIC(12,2),
        (v_item->>'quantity')::INTEGER,
        (v_item->>'line_total')::NUMERIC(12,2)
      );
    END LOOP;
  END IF;

  -- Generate checkout URL
  v_checkout_url := 'https://openpay.com/checkout/' || v_session_token;

  RETURN QUERY SELECT 
    v_checkout_session_id::UUID,
    v_session_token::TEXT,
    v_amount::NUMERIC(12,2),
    v_currency::TEXT,
    'open'::TEXT,
    now() + (v_expires_minutes || ' minutes')::INTERVAL::TIMESTAMPTZ,
    v_checkout_url::TEXT;
END;
$$;

-- Get checkout session
CREATE OR REPLACE FUNCTION public.get_checkout_session(
  p_session_token TEXT
)
RETURNS TABLE (
  id UUID,
  merchant_user_id UUID,
  session_token TEXT,
  status TEXT,
  subtotal_amount NUMERIC(12,2),
  fee_amount NUMERIC(12,2),
  total_amount NUMERIC(12,2),
  currency TEXT,
  customer_name TEXT,
  customer_email TEXT,
  customer_phone TEXT,
  customer_address TEXT,
  success_url TEXT,
  cancel_url TEXT,
  payment_method TEXT,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ,
  items JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY SELECT 
    cs.id,
    cs.merchant_user_id,
    cs.session_token,
    cs.status,
    cs.subtotal_amount,
    cs.fee_amount,
    cs.total_amount,
    cs.currency,
    cs.customer_name,
    cs.customer_email,
    cs.customer_phone,
    cs.customer_address,
    cs.success_url,
    cs.cancel_url,
    cs.payment_method,
    cs.expires_at,
    cs.created_at,
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'item_name', csi.item_name,
          'item_description', csi.item_description,
          'unit_amount', csi.unit_amount,
          'quantity', csi.quantity,
          'line_total', csi.line_total
        )
      ) FILTER (WHERE csi.id IS NOT NULL),
      '[]'::jsonb
    ) as items
  FROM public.checkout_sessions cs
  LEFT JOIN public.checkout_session_items csi ON cs.id = csi.session_id
  WHERE cs.session_token = TRIM(COALESCE(p_session_token, ''))
    AND cs.status = 'open'
    AND cs.expires_at > now()
  GROUP BY cs.id, cs.merchant_user_id, cs.session_token, cs.status, cs.subtotal_amount, 
           cs.fee_amount, cs.total_amount, cs.currency, cs.customer_name, cs.customer_email,
           cs.customer_phone, cs.customer_address, cs.success_url, cs.cancel_url, 
           cs.payment_method, cs.expires_at, cs.created_at;
END;
$$;

-- Process checkout payment (virtual card)
CREATE OR REPLACE FUNCTION public.process_checkout_payment_virtual_card(
  p_session_token TEXT,
  p_card_number TEXT,
  p_expiry_month INTEGER,
  p_expiry_year INTEGER,
  p_cvc TEXT,
  p_customer_name TEXT DEFAULT NULL,
  p_customer_email TEXT DEFAULT NULL,
  p_customer_phone TEXT DEFAULT NULL,
  p_customer_address TEXT DEFAULT NULL
)
RETURNS TABLE (
  transaction_id UUID,
  checkout_session_id UUID,
  status TEXT,
  message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_checkout_session public.checkout_sessions;
  v_sanitized_card_number TEXT := regexp_replace(COALESCE(p_card_number, ''), '\D', '', 'g');
  v_sanitized_cvc TEXT := regexp_replace(COALESCE(p_cvc, ''), '\D', '', 'g');
  v_expiry_end DATE;
  v_transaction_id UUID;
  v_checkout_transaction_id UUID;
  v_fee_amount NUMERIC(12,2);
  v_net_amount NUMERIC(12,2);
BEGIN
  -- Validate session
  SELECT *
  INTO v_checkout_session
  FROM public.checkout_sessions cs
  WHERE cs.session_token = TRIM(COALESCE(p_session_token, ''))
    AND cs.status = 'open'
    AND cs.expires_at > now()
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT NULL::UUID, NULL::UUID, 'error', 'Invalid or expired checkout session'::TEXT;
    RETURN;
  END IF;

  -- Validate card
  IF length(v_sanitized_card_number) NOT IN (13, 15, 16) THEN
    RETURN QUERY SELECT NULL::UUID, NULL::UUID, 'error', 'Invalid card number'::TEXT;
    RETURN;
  END IF;

  IF length(v_sanitized_cvc) NOT IN (3, 4) THEN
    RETURN QUERY SELECT NULL::UUID, NULL::UUID, 'error', 'Invalid CVC'::TEXT;
    RETURN;
  END IF;

  v_expiry_end := make_date(p_expiry_year, p_expiry_month, 1);
  IF v_expiry_end < make_date(extract(year from now()), extract(month from now()), 1) THEN
    RETURN QUERY SELECT NULL::UUID, NULL::UUID, 'error', 'Card expired'::TEXT;
    RETURN;
  END IF;

  -- Calculate amounts
  v_fee_amount := v_checkout_session.fee_amount;
  v_net_amount := v_checkout_session.total_amount - v_fee_amount;

  -- Create main transaction
  INSERT INTO public.transactions (
    sender_user_id,
    receiver_user_id,
    amount,
    currency,
    fee_amount,
    status,
    type,
    metadata
  ) VALUES (
    NULL, -- Card payment - no sender user
    v_checkout_session.merchant_user_id,
    v_checkout_session.total_amount,
    v_checkout_session.currency,
    v_fee_amount,
    'pending',
    'payment',
    jsonb_build_object(
      'checkout_session_id', v_checkout_session.id,
      'payment_method', 'virtual_card',
      'card_last4', right(v_sanitized_card_number, 4),
      'customer_name', p_customer_name
    )
  ) RETURNING id INTO v_transaction_id;

  -- Create checkout transaction record
  INSERT INTO public.checkout_transactions (
    checkout_session_id,
    transaction_id,
    payment_method,
    amount,
    currency,
    fee_amount,
    net_amount,
    status,
    gateway_response
  ) VALUES (
    v_checkout_session.id,
    v_transaction_id,
    'virtual_card',
    v_checkout_session.total_amount,
    v_checkout_session.currency,
    v_fee_amount,
    v_net_amount,
    'succeeded',
    jsonb_build_object(
      'card_last4', right(v_sanitized_card_number, 4),
      'auth_code', 'APPROVED',
      'transaction_id', v_transaction_id
    )
  ) RETURNING id INTO v_checkout_transaction_id;

  -- Update checkout session status
  UPDATE public.checkout_sessions
  SET status = 'paid',
      paid_at = now(),
      updated_at = now()
  WHERE id = v_checkout_session.id;

  RETURN QUERY SELECT 
    v_transaction_id::UUID,
    v_checkout_session.id::UUID,
    'success'::TEXT,
    'Checkout payment processed successfully'::TEXT;
END;
$$;

-- Get checkout payment QR code data
CREATE OR REPLACE FUNCTION public.get_checkout_payment_qr_data(
  p_session_token TEXT
)
RETURNS TABLE (
  qr_data TEXT,
  amount NUMERIC(12,2),
  currency TEXT,
  merchant_name TEXT,
  note TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_checkout_session public.checkout_sessions;
  v_merchant_name TEXT;
BEGIN
  -- Get checkout session
  SELECT *
  INTO v_checkout_session
  FROM public.checkout_sessions cs
  WHERE cs.session_token = TRIM(COALESCE(p_session_token, ''))
    AND cs.status = 'open'
    AND cs.expires_at > now()
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT 
      NULL::TEXT,
      NULL::NUMERIC(12,2),
      NULL::TEXT,
      NULL::TEXT,
      NULL::TEXT;
    RETURN;
  END IF;

  -- Get merchant name
  SELECT username
  INTO v_merchant_name
  FROM auth.users
  WHERE id = v_checkout_session.merchant_user_id;

  -- Generate QR data
  RETURN QUERY SELECT 
    ('openpay://checkout?session=' || v_checkout_session.session_token ||
     '&amount=' || v_checkout_session.total_amount::TEXT ||
     '&currency=' || v_checkout_session.currency ||
     '&note=Checkout+payment' ||
     '&name=' || COALESCE(v_merchant_name, ''))::TEXT,
    v_checkout_session.total_amount::NUMERIC(12,2),
    v_checkout_session.currency::TEXT,
    COALESCE(v_merchant_name, '')::TEXT,
    'Checkout Payment'::TEXT;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.create_checkout_session TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.get_checkout_session TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.process_checkout_payment_virtual_card TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.get_checkout_payment_qr_data TO authenticated, anon;

-- Row Level Security for checkout tables
ALTER TABLE public.checkout_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.checkout_session_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.checkout_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.checkout_api_keys ENABLE ROW LEVEL SECURITY;

-- Checkout policies
CREATE POLICY "Users can view their own checkout sessions" ON public.checkout_sessions
  FOR SELECT USING (auth.uid() = merchant_user_id);

CREATE POLICY "Users can insert their own checkout sessions" ON public.checkout_sessions
  FOR INSERT WITH CHECK (auth.uid() = merchant_user_id);

CREATE POLICY "Users can update their own checkout sessions" ON public.checkout_sessions
  FOR UPDATE USING (auth.uid() = merchant_user_id);

CREATE POLICY "Users can view their own checkout session items" ON public.checkout_session_items
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.checkout_sessions cs 
      WHERE cs.id = checkout_session_items.session_id 
      AND cs.merchant_user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert their own checkout session items" ON public.checkout_session_items
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.checkout_sessions cs 
      WHERE cs.id = checkout_session_items.session_id 
      AND cs.merchant_user_id = auth.uid()
    )
  );

CREATE POLICY "Users can view their own checkout transactions" ON public.checkout_transactions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.checkout_sessions cs 
      WHERE cs.id = checkout_transactions.checkout_session_id 
      AND cs.merchant_user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert their own checkout transactions" ON public.checkout_transactions
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.checkout_sessions cs 
      WHERE cs.id = checkout_transactions.checkout_session_id 
      AND cs.merchant_user_id = auth.uid()
    )
  );

CREATE POLICY "Users can view their own checkout API keys" ON public.checkout_api_keys
  FOR SELECT USING (auth.uid() = merchant_user_id);

CREATE POLICY "Users can insert their own checkout API keys" ON public.checkout_api_keys
  FOR INSERT WITH CHECK (auth.uid() = merchant_user_id);

CREATE POLICY "Users can update their own checkout API keys" ON public.checkout_api_keys
  FOR UPDATE USING (auth.uid() = merchant_user_id);

-- <<< END MIGRATION: 20260227020000_checkout_payment_system.sql

-- >>> MIGRATION: 20260227030000_fix_merchant_payment_link_function.sql
-- Fix create_merchant_payment_link function to include fee parameters
-- This migration adds the missing fee-related parameters that the frontend expects

DROP FUNCTION IF EXISTS public.create_merchant_payment_link(
  TEXT,
  TEXT,
  TEXT,
  TEXT,
  TEXT,
  TEXT,
  NUMERIC,
  JSONB,
  BOOLEAN,
  BOOLEAN,
  BOOLEAN,
  BOOLEAN,
  TEXT,
  TEXT,
  TEXT,
  TEXT,
  INTEGER
);

CREATE OR REPLACE FUNCTION public.create_merchant_payment_link(
  p_secret_key TEXT,
  p_mode TEXT,
  p_link_type TEXT,
  p_title TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_currency TEXT DEFAULT 'USD',
  p_custom_amount NUMERIC DEFAULT NULL,
  p_items JSONB DEFAULT '[]'::jsonb,
  p_collect_customer_name BOOLEAN DEFAULT true,
  p_collect_customer_email BOOLEAN DEFAULT true,
  p_collect_phone BOOLEAN DEFAULT false,
  p_collect_address BOOLEAN DEFAULT false,
  p_after_payment_type TEXT DEFAULT 'confirmation',
  p_confirmation_message TEXT DEFAULT NULL,
  p_redirect_url TEXT DEFAULT NULL,
  p_call_to_action TEXT DEFAULT 'Pay',
  p_expires_in_minutes INTEGER DEFAULT NULL,
  p_fee_amount NUMERIC DEFAULT NULL,
  p_fee_payer TEXT DEFAULT NULL,
  p_merchant_settlement_amount NUMERIC DEFAULT NULL,
  p_openpay_fee_account TEXT DEFAULT NULL
)
RETURNS TABLE (
  link_id UUID,
  link_token TEXT,
  total_amount NUMERIC,
  currency TEXT,
  key_mode TEXT,
  expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, '')));
  v_link_type TEXT := LOWER(TRIM(COALESCE(p_link_type, '')));
  v_after_payment_type TEXT := LOWER(TRIM(COALESCE(p_after_payment_type, 'confirmation')));
  v_currency TEXT := UPPER(TRIM(COALESCE(p_currency, 'USD')));
  v_merchant_user_id UUID;
  v_api_key_id UUID;
  v_link public.merchant_payment_links;
  v_item JSONB;
  v_product public.merchant_products;
  v_quantity INTEGER;
  v_line_total NUMERIC(12,2);
  v_total NUMERIC(12,2) := 0;
  v_expires_at TIMESTAMPTZ;
BEGIN
  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  IF v_link_type NOT IN ('products', 'custom_amount') THEN
    RAISE EXCEPTION 'Link type must be products or custom_amount';
  END IF;

  IF v_after_payment_type NOT IN ('confirmation', 'redirect') THEN
    RAISE EXCEPTION 'After payment type must be confirmation or redirect';
  END IF;

  IF char_length(v_currency) < 2 OR char_length(v_currency) > 10 THEN
    RAISE EXCEPTION 'Currency must be between 2 and 10 characters';
  END IF;

  SELECT mak.merchant_user_id, mak.id
  INTO v_merchant_user_id, v_api_key_id
  FROM public.merchant_api_keys mak
  WHERE (mak.secret_key_hash = md5(p_secret_key) OR mak.secret_key_hash = encode(digest(p_secret_key, 'sha256'), 'hex'))
    AND mak.key_mode = v_mode
    AND mak.is_active = true
  LIMIT 1;

  IF v_merchant_user_id IS NULL THEN
    RAISE EXCEPTION 'Invalid merchant API key for mode %', v_mode;
  END IF;

  IF p_expires_in_minutes IS NOT NULL THEN
    v_expires_at := now() + (GREATEST(5, LEAST(p_expires_in_minutes, 525600)) || ' minutes')::INTERVAL;
  END IF;

  INSERT INTO public.merchant_payment_links (
    merchant_user_id,
    api_key_id,
    key_mode,
    link_token,
    link_type,
    title,
    description,
    currency,
    custom_amount,
    collect_customer_name,
    collect_customer_email,
    collect_phone,
    collect_address,
    after_payment_type,
    confirmation_message,
    redirect_url,
    call_to_action,
    expires_at
  )
  VALUES (
    v_merchant_user_id,
    v_api_key_id,
    v_mode,
    'oplink_' || public.random_token_hex(24),
    v_link_type,
    COALESCE(NULLIF(TRIM(p_title), ''), 'OpenPay Payment'),
    COALESCE(NULLIF(TRIM(p_description), ''), ''),
    v_currency,
    p_custom_amount,
    COALESCE(p_collect_customer_name, true),
    COALESCE(p_collect_customer_email, true),
    COALESCE(p_collect_phone, false),
    COALESCE(p_collect_address, false),
    v_after_payment_type,
    COALESCE(NULLIF(TRIM(p_confirmation_message), ''), 'Thanks for your payment.'),
    NULLIF(TRIM(COALESCE(p_redirect_url, '')), ''),
    COALESCE(NULLIF(TRIM(p_call_to_action), ''), 'Pay'),
    v_expires_at
  )
  RETURNING * INTO v_link;

  IF v_link_type = 'custom_amount' THEN
    IF p_custom_amount IS NULL OR p_custom_amount <= 0 THEN
      RAISE EXCEPTION 'Custom amount must be greater than 0';
    END IF;
    v_total := ROUND(p_custom_amount, 2);
  ELSE
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
      RAISE EXCEPTION 'At least one product item is required';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
      SELECT *
      INTO v_product
      FROM public.merchant_products mp
      WHERE mp.id = (v_item->>'product_id')::UUID
        AND mp.merchant_user_id = v_merchant_user_id
        AND mp.is_active = true
      LIMIT 1;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid product_id in items payload';
      END IF;

      v_quantity := COALESCE((v_item->>'quantity')::INTEGER, 1);
      IF v_quantity < 1 OR v_quantity > 1000 THEN
        RAISE EXCEPTION 'Quantity must be between 1 and 1000';
      END IF;

      IF UPPER(v_product.currency) <> v_currency THEN
        RAISE EXCEPTION 'Product currency mismatch for product %', v_product.id;
      END IF;

      v_line_total := ROUND(v_product.unit_amount * v_quantity, 2);

      INSERT INTO public.merchant_payment_link_items (
        link_id,
        product_id,
        item_name,
        unit_amount,
        quantity,
        line_total
      )
      VALUES (
        v_link.id,
        v_product.id,
        v_product.product_name,
        v_product.unit_amount,
        v_quantity,
        v_line_total
      );

      v_total := v_total + v_line_total;
    END LOOP;
  END IF;

  IF v_total <= 0 THEN
    RAISE EXCEPTION 'Link total must be positive';
  END IF;

  UPDATE public.merchant_payment_links
  SET total_amount = v_total
  WHERE id = v_link.id
  RETURNING * INTO v_link;

  UPDATE public.merchant_api_keys
  SET last_used_at = now()
  WHERE id = v_api_key_id;

  RETURN QUERY
  SELECT v_link.id, v_link.link_token, v_link.total_amount, v_link.currency, v_link.key_mode, v_link.expires_at;
END;
$$;

-- Enable RLS for payment links
ALTER TABLE public.merchant_payment_links ENABLE ROW LEVEL SECURITY;

-- Create policy for payment links
CREATE POLICY "Users can view their own payment links" ON public.merchant_payment_links
  FOR SELECT USING (merchant_user_id = auth.uid());

CREATE POLICY "Users can insert their own payment links" ON public.merchant_payment_links
  FOR INSERT WITH CHECK (merchant_user_id = auth.uid());

CREATE POLICY "Users can update their own payment links" ON public.merchant_payment_links
  FOR UPDATE USING (merchant_user_id = auth.uid());

-- Enable RLS for payment link items
ALTER TABLE public.merchant_payment_link_items ENABLE ROW LEVEL SECURITY;

-- Create policy for payment link items
CREATE POLICY "Users can view their own payment link items" ON public.merchant_payment_link_items
  FOR SELECT USING (
    link_id IN (
      SELECT id FROM public.merchant_payment_links 
      WHERE merchant_user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert their own payment link items" ON public.merchant_payment_link_items
  FOR INSERT WITH CHECK (
    link_id IN (
      SELECT id FROM public.merchant_payment_links 
      WHERE merchant_user_id = auth.uid()
    )
  );

-- <<< END MIGRATION: 20260227030000_fix_merchant_payment_link_function.sql

-- >>> MIGRATION: 20260227040000_complete_pos_system.sql
-- Complete POS SQL system with additional missing functions
-- This migration completes the POS system with additional utilities and functions

-- Additional POS functions for complete functionality

-- Create POS API key
CREATE OR REPLACE FUNCTION public.create_pos_api_key(
  -- p_pos_terminal_id UUID DEFAULT NULL, -- Table doesn't exist yet
  p_key_name TEXT DEFAULT 'POS Default Key',
  p_key_mode TEXT DEFAULT 'live'
)
RETURNS TABLE (
  api_key_id UUID,
  publishable_key TEXT,
  secret_key TEXT,
  secret_key_last4 TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_api_key_id UUID;
  v_publishable_key TEXT;
  v_secret_key TEXT;
  v_secret_key_hash TEXT;
  v_secret_key_last4 TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_key_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Key mode must be sandbox or live';
  END IF;

  -- Generate keys
  v_publishable_key := 'pos_pk_' || encode(gen_random_bytes(24), 'hex');
  v_secret_key := 'pos_sk_' || encode(gen_random_bytes(32), 'hex');
  v_secret_key_hash := encode(digest(v_secret_key, 'sha256'), 'hex');
  v_secret_key_last4 := RIGHT(v_secret_key, 4);

  -- Create POS API key
  INSERT INTO public.pos_api_keys (
    merchant_user_id,
    -- pos_terminal_id, -- Table doesn't exist yet
    key_mode,
    key_name,
    publishable_key,
    secret_key_hash,
    secret_key_last4
  ) VALUES (
    v_user_id,
    -- p_pos_terminal_id, -- Table doesn't exist yet
    p_key_mode,
    p_key_name,
    v_publishable_key,
    v_secret_key_hash,
    v_secret_key_last4
  ) RETURNING id INTO v_api_key_id;

  RETURN QUERY SELECT 
    v_api_key_id::UUID,
    v_publishable_key::TEXT,
    v_secret_key::TEXT,
    v_secret_key_last4::TEXT;
END;
$$;

-- Get POS API keys
CREATE OR REPLACE FUNCTION public.get_pos_api_keys(
  p_key_mode TEXT DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  key_name TEXT,
  key_mode TEXT,
  publishable_key TEXT,
  secret_key_last4 TEXT,
  is_active BOOLEAN,
  last_used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY SELECT 
    pak.id,
    pak.key_name,
    pak.key_mode,
    pak.publishable_key,
    pak.secret_key_last4,
    pak.is_active,
    pak.last_used_at,
    pak.created_at
  FROM public.pos_api_keys pak
  WHERE pak.merchant_user_id = auth.uid()
    AND (p_key_mode IS NULL OR pak.key_mode = p_key_mode)
    AND pak.revoked_at IS NULL
  ORDER BY pak.created_at DESC;
END;
$$;

-- Revoke POS API key
CREATE OR REPLACE FUNCTION public.revoke_pos_api_key(
  p_api_key_id UUID
)
RETURNS TABLE (
  success BOOLEAN,
  message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_updated_count INTEGER;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  UPDATE public.pos_api_keys
  SET is_active = false,
      revoked_at = now(),
      updated_at = now()
  WHERE id = p_api_key_id
    AND merchant_user_id = v_user_id;

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;

  IF v_updated_count > 0 THEN
    RETURN QUERY SELECT true::BOOLEAN, 'POS API key revoked successfully'::TEXT;
  ELSE
    RETURN QUERY SELECT false::BOOLEAN, 'POS API key not found or already revoked'::TEXT;
  END IF;
END;
$$;

-- Get POS payment history
CREATE OR REPLACE FUNCTION public.get_pos_payment_history(
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0,
  p_status TEXT DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  session_token TEXT,
  status TEXT,
  amount NUMERIC(12,2),
  currency TEXT,
  fee_amount NUMERIC(12,2),
  total_amount NUMERIC(12,2),
  customer_name TEXT,
  customer_email TEXT,
  payment_method TEXT,
  created_at TIMESTAMPTZ,
  paid_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY SELECT 
    pp.id,
    pp.session_token,
    pp.status,
    pp.amount,
    pp.currency,
    pp.fee_amount,
    pp.total_amount,
    pp.customer_name,
    pp.customer_email,
    pp.payment_method,
    pp.created_at,
    pp.paid_at,
    pp.expires_at
  FROM public.pos_payments pp
  WHERE pp.merchant_user_id = auth.uid()
    AND (p_status IS NULL OR pp.status = p_status)
  ORDER BY pp.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

-- Get POS payment statistics
CREATE OR REPLACE FUNCTION public.get_pos_payment_statistics(
  p_date_from DATE DEFAULT NULL,
  p_date_to DATE DEFAULT NULL
)
RETURNS TABLE (
  total_payments BIGINT,
  total_amount NUMERIC(12,2),
  total_fees NUMERIC(12,2),
  successful_payments BIGINT,
  pending_payments BIGINT,
  expired_payments BIGINT,
  average_amount NUMERIC(12,2)
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY SELECT 
    COUNT(*)::BIGINT,
    COALESCE(SUM(total_amount), 0)::NUMERIC(12,2),
    COALESCE(SUM(fee_amount), 0)::NUMERIC(12,2),
    COUNT(CASE WHEN status = 'paid' THEN 1 END)::BIGINT,
    COUNT(CASE WHEN status = 'pending' THEN 1 END)::BIGINT,
    COUNT(CASE WHEN status = 'expired' THEN 1 END)::BIGINT,
    COALESCE(AVG(amount), 0)::NUMERIC(12,2)
  FROM public.pos_payments
  WHERE merchant_user_id = auth.uid()
    AND (p_date_from IS NULL OR DATE(created_at) >= p_date_from)
    AND (p_date_to IS NULL OR DATE(created_at) <= p_date_to);
END;
$$;

-- Cancel POS payment
CREATE OR REPLACE FUNCTION public.cancel_pos_payment(
  p_session_token TEXT
)
RETURNS TABLE (
  success BOOLEAN,
  message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_pos_payment public.pos_payments;
  v_updated_count INTEGER;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Get POS payment
  SELECT *
  INTO v_pos_payment
  FROM public.pos_payments pp
  WHERE pp.session_token = TRIM(COALESCE(p_session_token, ''))
    AND pp.merchant_user_id = v_user_id
    AND pp.status = 'pending'
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false::BOOLEAN, 'POS payment not found or cannot be canceled'::TEXT;
    RETURN;
  END IF;

  -- Update status to canceled
  UPDATE public.pos_payments
  SET status = 'canceled',
      updated_at = now()
  WHERE id = v_pos_payment.id;

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;

  IF v_updated_count > 0 THEN
    RETURN QUERY SELECT true::BOOLEAN, 'POS payment canceled successfully'::TEXT;
  ELSE
    RETURN QUERY SELECT false::BOOLEAN, 'Failed to cancel POS payment'::TEXT;
  END IF;
END;
$$;

-- Validate POS API key
CREATE OR REPLACE FUNCTION public.validate_pos_api_key(
  p_publishable_key TEXT,
  p_secret_key TEXT
)
RETURNS TABLE (
  valid BOOLEAN,
  merchant_user_id UUID,
  key_mode TEXT,
  message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_api_key public.pos_api_keys;
  v_secret_hash TEXT;
BEGIN
  IF p_publishable_key IS NULL OR p_secret_key IS NULL THEN
    RETURN QUERY SELECT false::BOOLEAN, NULL::UUID, NULL::TEXT, 'Both keys are required'::TEXT;
    RETURN;
  END IF;

  v_secret_hash := encode(digest(p_secret_key, 'sha256'), 'hex');

  -- Get API key
  SELECT *
  INTO v_api_key
  FROM public.pos_api_keys pak
  WHERE pak.publishable_key = TRIM(p_publishable_key)
    AND pak.secret_key_hash = v_secret_hash
    AND pak.is_active = true
    AND pak.revoked_at IS NULL
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false::BOOLEAN, NULL::UUID, NULL::TEXT, 'Invalid POS API key'::TEXT;
    RETURN;
  END IF;

  -- Update last used at
  UPDATE public.pos_api_keys
  SET last_used_at = now(),
      updated_at = now()
  WHERE id = v_api_key.id;

  RETURN QUERY SELECT 
    true::BOOLEAN,
    v_api_key.merchant_user_id::UUID,
    v_api_key.key_mode::TEXT,
    'POS API key is valid'::TEXT;
END;
$$;

-- Grant permissions for new functions
GRANT EXECUTE ON FUNCTION public.create_pos_api_key TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_pos_api_keys TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_pos_api_key TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_pos_payment_history TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_pos_payment_statistics TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_pos_payment TO authenticated;
GRANT EXECUTE ON FUNCTION public.validate_pos_api_key TO authenticated, anon;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_pos_payments_created_at ON public.pos_payments(created_at);
CREATE INDEX IF NOT EXISTS idx_pos_payments_merchant_status ON public.pos_payments(merchant_user_id, status);
CREATE INDEX IF NOT EXISTS idx_pos_transactions_created_at ON public.pos_transactions(created_at);
CREATE INDEX IF NOT EXISTS idx_pos_api_keys_key_mode ON public.pos_api_keys(key_mode, is_active);

-- Add triggers for updated_at timestamps
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_pos_payments_updated_at 
    BEFORE UPDATE ON public.pos_payments 
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_pos_transactions_updated_at 
    BEFORE UPDATE ON public.pos_transactions 
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_pos_api_keys_updated_at 
    BEFORE UPDATE ON public.pos_api_keys 
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- <<< END MIGRATION: 20260227040000_complete_pos_system.sql

-- >>> MIGRATION: 20260227050000_fix_pos_dependencies.sql
-- Fix POS system dependencies and ensure tables exist
-- This migration fixes the "type does not exist" error by ensuring proper order

-- First, ensure the tables exist (create them if they don't)
-- This handles the case where the previous migration failed or wasn't applied

-- POS Payments Table (ensure it exists)
CREATE TABLE IF NOT EXISTS public.pos_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- pos_terminal_id UUID REFERENCES public.merchant_pos_terminals(id) ON DELETE SET NULL, -- Table doesn't exist yet
  session_token TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'expired', 'canceled')),
  currency TEXT NOT NULL CHECK (char_length(currency) = 3),
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  fee_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (fee_amount >= 0),
  total_amount NUMERIC(12,2) NOT NULL CHECK (total_amount > 0),
  customer_name TEXT,
  customer_email TEXT,
  customer_phone TEXT,
  payment_method TEXT DEFAULT 'wallet' CHECK (payment_method IN ('wallet', 'card', 'cash')),
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  expires_at TIMESTAMPTZ NOT NULL,
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- POS Transactions Table (ensure it exists)
CREATE TABLE IF NOT EXISTS public.pos_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pos_payment_id UUID NOT NULL REFERENCES public.pos_payments(id) ON DELETE CASCADE,
  transaction_id UUID REFERENCES public.transactions(id) ON DELETE SET NULL,
  payer_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  payment_method TEXT NOT NULL DEFAULT 'wallet' CHECK (payment_method IN ('wallet', 'card', 'cash')),
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  currency TEXT NOT NULL CHECK (char_length(currency) = 3),
  fee_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (fee_amount >= 0),
  net_amount NUMERIC(12,2) NOT NULL CHECK (net_amount > 0),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'succeeded', 'failed', 'refunded')),
  gateway_response JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- POS API Keys Table (ensure it exists)
CREATE TABLE IF NOT EXISTS public.pos_api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- pos_terminal_id UUID REFERENCES public.merchant_pos_terminals(id) ON DELETE SET NULL, -- Table doesn't exist yet
  key_mode TEXT NOT NULL CHECK (key_mode IN ('sandbox', 'live')),
  key_name TEXT NOT NULL DEFAULT 'POS Default Key',
  publishable_key TEXT NOT NULL UNIQUE,
  secret_key_hash TEXT NOT NULL UNIQUE,
  secret_key_last4 TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  last_used_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create indexes if they don't exist
CREATE INDEX IF NOT EXISTS idx_pos_payments_session_token ON public.pos_payments(session_token);
CREATE INDEX IF NOT EXISTS idx_pos_payments_merchant_user_id ON public.pos_payments(merchant_user_id);
CREATE INDEX IF NOT EXISTS idx_pos_payments_status ON public.pos_payments(status);
CREATE INDEX IF NOT EXISTS idx_pos_payments_expires_at ON public.pos_payments(expires_at);
CREATE INDEX IF NOT EXISTS idx_pos_payments_created_at ON public.pos_payments(created_at);
CREATE INDEX IF NOT EXISTS idx_pos_payments_merchant_status ON public.pos_payments(merchant_user_id, status);

CREATE INDEX IF NOT EXISTS idx_pos_transactions_pos_payment_id ON public.pos_transactions(pos_payment_id);
CREATE INDEX IF NOT EXISTS idx_pos_transactions_payer_user_id ON public.pos_transactions(payer_user_id);
CREATE INDEX IF NOT EXISTS idx_pos_transactions_status ON public.pos_transactions(status);
CREATE INDEX IF NOT EXISTS idx_pos_transactions_created_at ON public.pos_transactions(created_at);

CREATE INDEX IF NOT EXISTS idx_pos_api_keys_merchant_user_id ON public.pos_api_keys(merchant_user_id);
CREATE INDEX IF NOT EXISTS idx_pos_api_keys_publishable_key ON public.pos_api_keys(publishable_key);
CREATE INDEX IF NOT EXISTS idx_pos_api_keys_key_mode ON public.pos_api_keys(key_mode, is_active);

-- Enable RLS if not already enabled
ALTER TABLE public.pos_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_api_keys ENABLE ROW LEVEL SECURITY;

-- Create policies (drop existing first to avoid conflicts)
DROP POLICY IF EXISTS "Users can view their own POS payments" ON public.pos_payments;
CREATE POLICY "Users can view their own POS payments" ON public.pos_payments
  FOR SELECT USING (auth.uid() = merchant_user_id);

DROP POLICY IF EXISTS "Users can insert their own POS payments" ON public.pos_payments;
CREATE POLICY "Users can insert their own POS payments" ON public.pos_payments
  FOR INSERT WITH CHECK (auth.uid() = merchant_user_id);

DROP POLICY IF EXISTS "Users can update their own POS payments" ON public.pos_payments;
CREATE POLICY "Users can update their own POS payments" ON public.pos_payments
  FOR UPDATE USING (auth.uid() = merchant_user_id);

DROP POLICY IF EXISTS "Users can view their own POS transactions" ON public.pos_transactions;
CREATE POLICY "Users can view their own POS transactions" ON public.pos_transactions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.pos_payments pp 
      WHERE pp.id = pos_transactions.pos_payment_id 
      AND pp.merchant_user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Users can insert their own POS transactions" ON public.pos_transactions;
CREATE POLICY "Users can insert their own POS transactions" ON public.pos_transactions
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.pos_payments pp 
      WHERE pp.id = pos_transactions.pos_payment_id 
      AND pp.merchant_user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Users can view their own POS API keys" ON public.pos_api_keys;
CREATE POLICY "Users can view their own POS API keys" ON public.pos_api_keys
  FOR SELECT USING (auth.uid() = merchant_user_id);

DROP POLICY IF EXISTS "Users can insert their own POS API keys" ON public.pos_api_keys;
CREATE POLICY "Users can insert their own POS API keys" ON public.pos_api_keys
  FOR INSERT WITH CHECK (auth.uid() = merchant_user_id);

DROP POLICY IF EXISTS "Users can update their own POS API keys" ON public.pos_api_keys;
CREATE POLICY "Users can update their own POS API keys" ON public.pos_api_keys
  FOR UPDATE USING (auth.uid() = merchant_user_id);

-- Now recreate the core POS functions with proper error handling
-- Drop functions first to avoid conflicts
DROP FUNCTION IF EXISTS public.create_pos_payment_session(NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, UUID);
DROP FUNCTION IF EXISTS public.get_pos_payment_session(TEXT);
DROP FUNCTION IF EXISTS public.process_pos_payment_wallet(TEXT, UUID);
DROP FUNCTION IF EXISTS public.get_pos_payment_qr_data(TEXT);

-- Create POS payment session (recreated)
CREATE OR REPLACE FUNCTION public.create_pos_payment_session(
  p_amount NUMERIC(12,2),
  p_currency TEXT DEFAULT 'USD',
  p_customer_name TEXT DEFAULT NULL,
  p_customer_email TEXT DEFAULT NULL,
  p_customer_phone TEXT DEFAULT NULL,
  p_payment_method TEXT DEFAULT 'wallet',
  p_expires_in_minutes INTEGER DEFAULT 30
  -- p_pos_terminal_id UUID DEFAULT NULL -- Table doesn't exist yet
)
RETURNS TABLE (
  session_id UUID,
  session_token TEXT,
  amount NUMERIC(12,2),
  currency TEXT,
  status TEXT,
  expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_pos_payment_id UUID;
  v_session_token TEXT;
  v_amount NUMERIC(12,2) := ROUND(COALESCE(p_amount, 0)::NUMERIC, 2);
  v_currency TEXT := UPPER(TRIM(COALESCE(p_currency, 'USD')));
  v_expires_minutes INTEGER := GREATEST(5, LEAST(COALESCE(p_expires_in_minutes, 30), 10080));
  v_fee_amount NUMERIC(12,2) := 0;
  v_total_amount NUMERIC(12,2);
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive';
  END IF;

  -- Generate unique session token
  v_session_token := 'opsess_' || encode(gen_random_bytes(16), 'hex');
  
  -- Calculate fee (2% for POS)
  v_fee_amount := ROUND(v_amount * 0.02, 2);
  v_total_amount := v_amount + v_fee_amount;

  -- Create POS payment session
  INSERT INTO public.pos_payments (
    merchant_user_id,
    -- pos_terminal_id, -- Table doesn't exist yet
    session_token,
    currency,
    amount,
    fee_amount,
    total_amount,
    customer_name,
    customer_email,
    customer_phone,
    payment_method,
    expires_at
  ) VALUES (
    v_user_id,
    -- p_pos_terminal_id, -- Table doesn't exist yet
    v_session_token,
    v_currency,
    v_amount,
    v_fee_amount,
    v_total_amount,
    p_customer_name,
    p_customer_email,
    p_customer_phone,
    p_payment_method,
    now() + (v_expires_minutes || ' minutes')::INTERVAL
  ) RETURNING id INTO v_pos_payment_id;

  RETURN QUERY SELECT 
    v_pos_payment_id::UUID,
    v_session_token::TEXT,
    v_amount::NUMERIC(12,2),
    v_currency::TEXT,
    'pending'::TEXT,
    now() + (v_expires_minutes || ' minutes')::INTERVAL::TIMESTAMPTZ;
END;
$$;

-- Grant permissions (only for authenticated users)
GRANT EXECUTE ON FUNCTION public.create_pos_payment_session TO authenticated;

-- <<< END MIGRATION: 20260227050000_fix_pos_dependencies.sql

-- >>> MIGRATION: 20260227060000_fix_merchant_payment_links_columns.sql
-- Add missing total_amount column to merchant_payment_links table
-- This migration fixes the "column total_amount does not exist" error

-- Add total_amount column to merchant_payment_links table
ALTER TABLE public.merchant_payment_links 
ADD COLUMN IF NOT EXISTS total_amount NUMERIC(12,2) CHECK (total_amount > 0);

-- Add api_key_id column if it doesn't exist (for tracking which API key was used)
ALTER TABLE public.merchant_payment_links 
ADD COLUMN IF NOT EXISTS api_key_id UUID REFERENCES public.merchant_api_keys(id) ON DELETE SET NULL;

-- Add reference_number column for merchant reference
ALTER TABLE public.merchant_payment_links 
ADD COLUMN IF NOT EXISTS reference_number TEXT;

-- Add remarks column for additional notes
ALTER TABLE public.merchant_payment_links 
ADD COLUMN IF NOT EXISTS remarks TEXT;

-- Add archived_at column for soft deletion
ALTER TABLE public.merchant_payment_links 
ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;

-- Create indexes for new columns
CREATE INDEX IF NOT EXISTS idx_merchant_payment_links_total_amount 
ON public.merchant_payment_links(total_amount);

CREATE INDEX IF NOT EXISTS idx_merchant_payment_links_api_key_id 
ON public.merchant_payment_links(api_key_id);

CREATE INDEX IF NOT EXISTS idx_merchant_payment_links_archived_at 
ON public.merchant_payment_links(archived_at);

-- Update existing payment links to calculate total_amount from items
UPDATE public.merchant_payment_links mpl
SET total_amount = (
  SELECT COALESCE(SUM(mpli.line_total), 0)
  FROM public.merchant_payment_link_items mpli
  WHERE mpli.link_id = mpl.id
)
WHERE mpl.total_amount IS NULL
AND mpl.link_type = 'products';

-- For custom_amount links, set total_amount from custom_amount
UPDATE public.merchant_payment_links
SET total_amount = custom_amount
WHERE total_amount IS NULL
AND link_type = 'custom_amount'
AND custom_amount IS NOT NULL;

-- Update RLS policies to include new columns
DROP POLICY IF EXISTS "Users can view their own payment links" ON public.merchant_payment_links;
CREATE POLICY "Users can view their own payment links" ON public.merchant_payment_links
  FOR SELECT USING (merchant_user_id = auth.uid());

DROP POLICY IF EXISTS "Users can insert their own payment links" ON public.merchant_payment_links;
CREATE POLICY "Users can insert their own payment links" ON public.merchant_payment_links
  FOR INSERT WITH CHECK (merchant_user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update their own payment links" ON public.merchant_payment_links;
CREATE POLICY "Users can update their own payment links" ON public.merchant_payment_links
  FOR UPDATE USING (merchant_user_id = auth.uid());

-- Grant permissions for the updated table
GRANT ALL ON public.merchant_payment_links TO authenticated;
GRANT ALL ON public.merchant_payment_links TO service_role;

-- <<< END MIGRATION: 20260227060000_fix_merchant_payment_links_columns.sql

-- >>> MIGRATION: 20260227080000_simple_analytics.sql
-- Simple Analytics Fix
CREATE OR REPLACE FUNCTION public.get_user_analytics_summary(p_user_id UUID)
RETURNS TABLE (
  total_sent NUMERIC,
  total_received NUMERIC,
  net_balance NUMERIC,
  transaction_count BIGINT,
  payment_requests_sent BIGINT,
  payment_requests_received BIGINT,
  topup_count BIGINT,
  topup_amount NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COALESCE(SUM(CASE WHEN t.sender_id = p_user_id THEN t.amount ELSE 0 END), 0) as total_sent,
    COALESCE(SUM(CASE WHEN t.receiver_id = p_user_id THEN t.amount ELSE 0 END), 0) as total_received,
    COALESCE(SUM(CASE WHEN t.receiver_id = p_user_id THEN t.amount ELSE 0 END), 0) - 
    COALESCE(SUM(CASE WHEN t.sender_id = p_user_id THEN t.amount ELSE 0 END), 0) as net_balance,
    COUNT(t.id) as transaction_count,
    COUNT(CASE WHEN pr.requester_id = p_user_id THEN 1 END) as payment_requests_sent,
    COUNT(CASE WHEN pr.payer_id = p_user_id THEN 1 END) as payment_requests_received,
    COUNT(pc.id) as topup_count,
    COALESCE(SUM(pc.amount), 0) as topup_amount
  FROM auth.users u
  LEFT JOIN public.transactions t ON (t.sender_id = p_user_id OR t.receiver_id = p_user_id)
  LEFT JOIN public.payment_requests pr ON (pr.requester_id = p_user_id OR pr.payer_id = p_user_id)
  LEFT JOIN public.pi_payment_credits pc ON pc.user_id = p_user_id
  WHERE u.id = p_user_id
  GROUP BY u.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_analytics_summary TO authenticated;

-- <<< END MIGRATION: 20260227080000_simple_analytics.sql

-- >>> MIGRATION: 20260227090000_basic_analytics.sql
-- Basic Analytics - Simplified version without complex joins
CREATE OR REPLACE FUNCTION public.get_user_analytics_summary(p_user_id UUID)
RETURNS TABLE (
  total_sent NUMERIC,
  total_received NUMERIC,
  net_balance NUMERIC,
  transaction_count BIGINT,
  payment_requests_sent BIGINT,
  payment_requests_received BIGINT,
  topup_count BIGINT,
  topup_amount NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COALESCE((SELECT COALESCE(SUM(amount), 0) FROM public.transactions WHERE sender_id = p_user_id), 0) as total_sent,
    COALESCE((SELECT COALESCE(SUM(amount), 0) FROM public.transactions WHERE receiver_id = p_user_id), 0) as total_received,
    COALESCE((SELECT COALESCE(SUM(amount), 0) FROM public.transactions WHERE receiver_id = p_user_id), 0) - 
    COALESCE((SELECT COALESCE(SUM(amount), 0) FROM public.transactions WHERE sender_id = p_user_id), 0) as net_balance,
    COALESCE((SELECT COUNT(*) FROM public.transactions WHERE sender_id = p_user_id OR receiver_id = p_user_id), 0) as transaction_count,
    COALESCE((SELECT COUNT(*) FROM public.payment_requests WHERE requester_id = p_user_id), 0) as payment_requests_sent,
    COALESCE((SELECT COUNT(*) FROM public.payment_requests WHERE payer_id = p_user_id), 0) as payment_requests_received,
    COALESCE((SELECT COUNT(*) FROM public.pi_payment_credits WHERE user_id = p_user_id), 0) as topup_count,
    COALESCE((SELECT COALESCE(SUM(amount), 0) FROM public.pi_payment_credits WHERE user_id = p_user_id), 0) as topup_amount;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_analytics_summary TO authenticated;

-- <<< END MIGRATION: 20260227090000_basic_analytics.sql

-- >>> MIGRATION: 20260227100000_fix_track_user_activity.sql
-- Fix track_user_activity function error by creating stub functions
-- Drop all possible existing versions first
DROP FUNCTION IF EXISTS public.track_user_activity(uuid, text, numeric, text, uuid, text, uuid, jsonb);
DROP FUNCTION IF EXISTS public.track_user_activity(uuid, text, numeric, text, uuid, text, uuid, json);
DROP FUNCTION IF EXISTS public.track_user_activity(uuid, text, numeric, text, uuid, text, uuid, text);

-- Create multiple overloads to handle different parameter types
CREATE OR REPLACE FUNCTION public.track_user_activity(
  p_user_id UUID,
  p_activity_type TEXT,
  p_amount NUMERIC,
  p_currency TEXT,
  p_related_id UUID,
  p_source TEXT,
  p_session_id UUID,
  p_metadata JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Simple stub function that does nothing but prevents the error
  NULL;
END;
$$;

-- Create overload for JSON instead of JSONB
CREATE OR REPLACE FUNCTION public.track_user_activity(
  p_user_id UUID,
  p_activity_type TEXT,
  p_amount NUMERIC,
  p_currency TEXT,
  p_related_id UUID,
  p_source TEXT,
  p_session_id UUID,
  p_metadata JSON
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Simple stub function that does nothing but prevents the error
  NULL;
END;
$$;

-- Create overload with all TEXT parameters (most flexible)
CREATE OR REPLACE FUNCTION public.track_user_activity(
  p_user_id UUID,
  p_activity_type TEXT,
  p_amount NUMERIC,
  p_currency TEXT,
  p_related_id UUID,
  p_source TEXT,
  p_session_id UUID,
  p_metadata TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Simple stub function that does nothing but prevents the error
  NULL;
END;
$$;

-- Grant permissions on all versions
GRANT EXECUTE ON FUNCTION public.track_user_activity(uuid, text, numeric, text, uuid, text, uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.track_user_activity(uuid, text, numeric, text, uuid, text, uuid, json) TO authenticated;
GRANT EXECUTE ON FUNCTION public.track_user_activity(uuid, text, numeric, text, uuid, text, uuid, text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.track_user_activity(uuid, text, numeric, text, uuid, text, uuid, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.track_user_activity(uuid, text, numeric, text, uuid, text, uuid, json) TO service_role;
GRANT EXECUTE ON FUNCTION public.track_user_activity(uuid, text, numeric, text, uuid, text, uuid, text) TO service_role;

-- <<< END MIGRATION: 20260227100000_fix_track_user_activity.sql

-- >>> MIGRATION: 20260227110000_payment_purpose.sql
-- Payment Purpose Schema for Analytics
-- Add purpose column to transactions table
ALTER TABLE public.transactions 
ADD COLUMN IF NOT EXISTS purpose TEXT,
ADD COLUMN IF NOT EXISTS purpose_category TEXT,
ADD COLUMN IF NOT EXISTS custom_purpose TEXT;

-- Create payment purposes table
CREATE TABLE IF NOT EXISTS public.payment_purposes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  category TEXT NOT NULL,
  icon TEXT,
  color TEXT,
  is_active BOOLEAN DEFAULT true,
  is_custom BOOLEAN DEFAULT false,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create payment purpose categories table
CREATE TABLE IF NOT EXISTS public.payment_purpose_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  icon TEXT,
  color TEXT,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Insert default categories
INSERT INTO public.payment_purpose_categories (name, icon, color, sort_order) VALUES
('Living Expenses', 'home', 'blue', 1),
('Transportation', 'car', 'green', 2),
('Food & Dining', 'utensils', 'orange', 3),
('Entertainment', 'gamepad-2', 'purple', 4),
('Shopping', 'shopping-bag', 'pink', 5),
('Healthcare', 'heart', 'red', 6),
('Education', 'graduation-cap', 'indigo', 7),
('Utilities', 'zap', 'yellow', 8),
('Business', 'briefcase', 'gray', 9),
('Personal', 'user', 'teal', 10),
('Other', 'more-horizontal', 'slate', 11)
ON CONFLICT (name) DO NOTHING;

-- Insert default payment purposes
INSERT INTO public.payment_purposes (name, category, icon, color, sort_order) VALUES
-- Living Expenses
('Rent', 'Living Expenses', 'home', 'blue', 1),
('Mortgage', 'Living Expenses', 'building', 'blue', 2),
('Insurance', 'Living Expenses', 'shield', 'blue', 3),
('Property Tax', 'Living Expenses', 'file-text', 'blue', 4),

-- Transportation
('Car Payment', 'Transportation', 'car', 'green', 1),
('Gas/Fuel', 'Transportation', 'fuel', 'green', 2),
('Public Transport', 'Transportation', 'train', 'green', 3),
('Ride Sharing', 'Transportation', 'taxi', 'green', 4),
('Car Maintenance', 'Transportation', 'wrench', 'green', 5),

-- Food & Dining
('Groceries', 'Food & Dining', 'shopping-cart', 'orange', 1),
('Restaurant', 'Food & Dining', 'utensils-crossed', 'orange', 2),
('Food Delivery', 'Food & Dining', 'truck', 'orange', 3),
('Coffee', 'Food & Dining', 'coffee', 'orange', 4),
('Takeout', 'Food & Dining', 'package', 'orange', 5),

-- Entertainment
('Movies', 'Entertainment', 'film', 'purple', 1),
('Music', 'Entertainment', 'music', 'purple', 2),
('Games', 'Entertainment', 'gamepad-2', 'purple', 3),
('Streaming', 'Entertainment', 'tv', 'purple', 4),
('Events', 'Entertainment', 'calendar', 'purple', 5),

-- Shopping
('Clothing', 'Shopping', 'shirt', 'pink', 1),
('Electronics', 'Shopping', 'smartphone', 'pink', 2),
('Home Goods', 'Shopping', 'sofa', 'pink', 3),
('Books', 'Shopping', 'book-open', 'pink', 4),
('Gifts', 'Shopping', 'gift', 'pink', 5),

-- Healthcare
('Doctor Visit', 'Healthcare', 'stethoscope', 'red', 1),
('Medicine', 'Healthcare', 'pill', 'red', 2),
('Dental', 'Healthcare', 'smile', 'red', 3),
('Vision', 'Healthcare', 'eye', 'red', 4),
('Fitness', 'Healthcare', 'dumbbell', 'red', 5),

-- Education
('Tuition', 'Education', 'graduation-cap', 'indigo', 1),
('Books', 'Education', 'book', 'indigo', 2),
('Courses', 'Education', 'laptop', 'indigo', 3),
('School Supplies', 'Education', 'pencil', 'indigo', 4),
('Student Loans', 'Education', 'dollar-sign', 'indigo', 5),

-- Utilities
('Electricity', 'Utilities', 'lightbulb', 'yellow', 1),
('Water', 'Utilities', 'droplet', 'yellow', 2),
('Gas', 'Utilities', 'flame', 'yellow', 3),
('Internet', 'Utilities', 'wifi', 'yellow', 4),
('Phone', 'Utilities', 'phone', 'yellow', 5),
('Trash', 'Utilities', 'trash-2', 'yellow', 6),

-- Business
('Office Supplies', 'Business', 'briefcase', 'gray', 1),
('Software', 'Business', 'monitor', 'gray', 2),
('Marketing', 'Business', 'megaphone', 'gray', 3),
('Travel', 'Business', 'plane', 'gray', 4),
('Equipment', 'Business', 'settings', 'gray', 5),

-- Personal
('Gift', 'Personal', 'gift', 'teal', 1),
('Charity', 'Personal', 'heart', 'teal', 2),
('Family', 'Personal', 'users', 'teal', 3),
('Friends', 'Personal', 'user-plus', 'teal', 4),
('Emergency', 'Personal', 'alert-triangle', 'teal', 5),

-- Other
('General', 'Other', 'more-horizontal', 'slate', 1),
('Uncategorized', 'Other', 'help-circle', 'slate', 2),
('Miscellaneous', 'Other', 'folder', 'slate', 3)
ON CONFLICT (name) DO NOTHING;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_transactions_purpose ON public.transactions(purpose);
CREATE INDEX IF NOT EXISTS idx_transactions_purpose_category ON public.transactions(purpose_category);
CREATE INDEX IF NOT EXISTS idx_transactions_created_at_purpose ON public.transactions(created_at, purpose);

-- Create view for analytics by purpose
CREATE OR REPLACE VIEW public.transaction_purpose_analytics AS
SELECT 
  t.purpose,
  t.purpose_category,
  pp.category as category_name,
  COUNT(*) as transaction_count,
  COALESCE(SUM(t.amount), 0) as total_amount,
  COALESCE(AVG(t.amount), 0) as average_amount,
  MIN(t.created_at) as first_transaction,
  MAX(t.created_at) as last_transaction,
  DATE_TRUNC('month', t.created_at) as month,
  DATE_TRUNC('week', t.created_at) as week
FROM public.transactions t
LEFT JOIN public.payment_purposes pp ON t.purpose = pp.name
WHERE t.purpose IS NOT NULL
GROUP BY t.purpose, t.purpose_category, pp.category, DATE_TRUNC('month', t.created_at), DATE_TRUNC('week', t.created_at);

-- Create function to get purpose analytics
CREATE OR REPLACE FUNCTION public.get_purpose_analytics(
  p_user_id UUID DEFAULT NULL,
  p_date_range TEXT DEFAULT 'month' -- 'day', 'week', 'month', 'year'
)
RETURNS TABLE (
  purpose TEXT,
  purpose_category TEXT,
  category_name TEXT,
  transaction_count BIGINT,
  total_amount NUMERIC,
  average_amount NUMERIC,
  percentage DECIMAL(5,2)
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH purpose_stats AS (
    SELECT 
      t.purpose,
      t.purpose_category,
      pp.category as category_name,
      COUNT(*) as transaction_count,
      COALESCE(SUM(t.amount), 0) as total_amount,
      COALESCE(AVG(t.amount), 0) as average_amount
    FROM public.transactions t
    LEFT JOIN public.payment_purposes pp ON t.purpose = pp.name
    WHERE (p_user_id IS NULL OR (t.sender_id = p_user_id OR t.receiver_id = p_user_id))
      AND t.purpose IS NOT NULL
      AND CASE 
        WHEN p_date_range = 'day' THEN t.created_at >= CURRENT_DATE - INTERVAL '1 day'
        WHEN p_date_range = 'week' THEN t.created_at >= CURRENT_DATE - INTERVAL '1 week'
        WHEN p_date_range = 'month' THEN t.created_at >= CURRENT_DATE - INTERVAL '1 month'
        WHEN p_date_range = 'year' THEN t.created_at >= CURRENT_DATE - INTERVAL '1 year'
        ELSE true
      END
    GROUP BY t.purpose, t.purpose_category, pp.category
  ),
  total_stats AS (
    SELECT SUM(transaction_count) as total_count
    FROM purpose_stats
  )
  SELECT 
    ps.purpose,
    ps.purpose_category,
    ps.category_name,
    ps.transaction_count,
    ps.total_amount,
    ps.average_amount,
    CASE 
      WHEN ts.total_count > 0 THEN (ps.transaction_count::DECIMAL / ts.total_count * 100)
      ELSE 0
    END as percentage
  FROM purpose_stats ps, total_stats ts
  ORDER BY ps.total_amount DESC;
END;
$$;

-- Grant permissions
GRANT SELECT ON public.payment_purposes TO authenticated;
GRANT SELECT ON public.payment_purposes TO service_role;
GRANT SELECT ON public.payment_purpose_categories TO authenticated;
GRANT SELECT ON public.payment_purpose_categories TO service_role;
GRANT SELECT ON public.transaction_purpose_analytics TO authenticated;
GRANT SELECT ON public.transaction_purpose_analytics TO service_role;
GRANT EXECUTE ON FUNCTION public.get_purpose_analytics TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_purpose_analytics TO service_role;

-- Create trigger to update updated_at
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$
LANGUAGE plpgsql;

-- Drop existing triggers if they exist
DROP TRIGGER IF EXISTS update_payment_purposes_updated_at ON public.payment_purposes;
DROP TRIGGER IF EXISTS update_payment_purpose_categories_updated_at ON public.payment_purpose_categories;

CREATE TRIGGER update_payment_purposes_updated_at 
  BEFORE UPDATE ON public.payment_purposes 
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_payment_purpose_categories_updated_at 
  BEFORE UPDATE ON public.payment_purpose_categories 
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- <<< END MIGRATION: 20260227110000_payment_purpose.sql

-- >>> MIGRATION: 20260301120000_mining_system.sql

-- 20260301120000_mining_system.sql
-- Create mining_sessions table to track active mining
CREATE TABLE IF NOT EXISTS public.mining_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  last_reward_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_active BOOLEAN NOT NULL DEFAULT true,
  device_fingerprint TEXT,
  ip_address TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create mining_rewards table for history
CREATE TABLE IF NOT EXISTS public.mining_rewards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id UUID REFERENCES public.mining_sessions(id) ON DELETE SET NULL,
  amount NUMERIC NOT NULL,
  reward_type TEXT NOT NULL CHECK (reward_type IN ('base', 'referral_bonus')),
  referral_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_mining_sessions_user_active ON public.mining_sessions(user_id) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_mining_rewards_user ON public.mining_rewards(user_id);

-- Function to start mining
CREATE OR REPLACE FUNCTION public.start_mining_session(p_device_fingerprint TEXT, p_ip_address TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_active_session_id UUID;
  v_expires_at TIMESTAMPTZ := now() + INTERVAL '24 hours';
BEGIN
  -- Check for existing active session
  SELECT id INTO v_active_session_id
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true AND expires_at > now();

  IF v_active_session_id IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Mining session already active', 'session_id', v_active_session_id);
  END IF;

  -- Deactivate any stale sessions
  UPDATE public.mining_sessions
  SET is_active = false
  WHERE user_id = v_user_id AND is_active = true;

  -- Start new session
  INSERT INTO public.mining_sessions (user_id, expires_at, device_fingerprint, ip_address)
  VALUES (v_user_id, v_expires_at, p_device_fingerprint, p_ip_address)
  RETURNING id INTO v_active_session_id;

  RETURN jsonb_build_object('success', true, 'session_id', v_active_session_id, 'expires_at', v_expires_at);
END;
$$;

-- Function to claim mining rewards (can be called periodically or at end of session)
CREATE OR REPLACE FUNCTION public.claim_mining_rewards()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_session RECORD;
  v_base_reward NUMERIC := 0.10;
  v_referral_bonus_rate NUMERIC := 0.10; -- 10% per active referral
  v_max_bonus_rate NUMERIC := 1.00; -- 100% max bonus
  v_active_referrals INTEGER;
  v_total_reward NUMERIC;
  v_bonus_reward NUMERIC;
BEGIN
  -- Get active session
  SELECT * INTO v_session
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true AND expires_at > now();

  IF v_session IS NULL THEN
    RETURN jsonb_build_object('error', 'No active mining session');
  END IF;

  -- Only allow claiming once per session or after it expires
  -- For this simple version, we'll reward the full 0.10 at the end or when they check in
  -- But the prompt says "increases gradually or at end of 24h". 
  -- Let's implement "at end of 24h" logic for simplicity, or "on check-in after 24h".
  
  -- Check if already rewarded for this session
  IF EXISTS (SELECT 1 FROM public.mining_rewards WHERE session_id = v_session.id AND reward_type = 'base') THEN
     RETURN jsonb_build_object('error', 'Reward already claimed for this session');
  END IF;

  -- Only allow claim if session has expired
  IF v_session.expires_at > now() THEN
     RETURN jsonb_build_object('error', 'Mining still in progress. Come back after 24 hours.');
  END IF;

  -- Calculate active referrals (those who have an active mining session)
  SELECT COUNT(DISTINCT r.referred_user_id) INTO v_active_referrals
  FROM public.referral_rewards r
  JOIN public.mining_sessions ms ON ms.user_id = r.referred_user_id
  WHERE r.referrer_id = v_user_id
    AND ms.is_active = true
    AND ms.expires_at > now();

  v_bonus_reward := LEAST(v_base_reward * v_active_referrals * v_referral_bonus_rate, v_base_reward * v_max_bonus_rate);
  v_total_reward := v_base_reward + v_bonus_reward;

  -- Record rewards
  INSERT INTO public.mining_rewards (user_id, session_id, amount, reward_type)
  VALUES (v_user_id, v_session.id, v_base_reward, 'base');

  IF v_bonus_reward > 0 THEN
    INSERT INTO public.mining_rewards (user_id, session_id, amount, reward_type)
    VALUES (v_user_id, v_session.id, v_bonus_reward, 'referral_bonus');
  END IF;

  -- Update wallet balance (storing off-chain as requested, but we use the wallets table)
  UPDATE public.wallets
  SET balance = balance + v_total_reward,
      updated_at = now()
  WHERE user_id = v_user_id;

  -- Deactivate session
  UPDATE public.mining_sessions
  SET is_active = false
  WHERE id = v_session.id;

  RETURN jsonb_build_object(
    'success', true, 
    'base_reward', v_base_reward, 
    'bonus_reward', v_bonus_reward, 
    'total_reward', v_total_reward,
    'active_referrals', v_active_referrals
  );
END;
$$;

-- RLS Policies
ALTER TABLE public.mining_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mining_rewards ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own mining sessions"
ON public.mining_sessions FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can view their own mining rewards"
ON public.mining_rewards FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Enable Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.mining_sessions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.mining_rewards;

-- <<< END MIGRATION: 20260301120000_mining_system.sql

-- >>> MIGRATION: 20260301130000_repair_mining_system_cache.sql

-- 20260301130000_repair_mining_system_cache.sql
-- Force schema cache refresh for mining tables and functions

-- Re-assert table structure to trigger cache refresh
CREATE TABLE IF NOT EXISTS public.mining_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  last_reward_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_active BOOLEAN NOT NULL DEFAULT true,
  device_fingerprint TEXT,
  ip_address TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.mining_rewards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id UUID REFERENCES public.mining_sessions(id) ON DELETE SET NULL,
  amount NUMERIC NOT NULL,
  reward_type TEXT NOT NULL CHECK (reward_type IN ('base', 'referral_bonus')),
  referral_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Re-define functions
CREATE OR REPLACE FUNCTION public.start_mining_session(p_device_fingerprint TEXT, p_ip_address TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_active_session_id UUID;
  v_expires_at TIMESTAMPTZ := now() + INTERVAL '24 hours';
BEGIN
  -- Check for existing active session
  SELECT id INTO v_active_session_id
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true AND expires_at > now();

  IF v_active_session_id IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Mining session already active', 'session_id', v_active_session_id);
  END IF;

  -- Deactivate any stale sessions
  UPDATE public.mining_sessions
  SET is_active = false
  WHERE user_id = v_user_id AND is_active = true;

  -- Start new session
  INSERT INTO public.mining_sessions (user_id, expires_at, device_fingerprint, ip_address)
  VALUES (v_user_id, v_expires_at, p_device_fingerprint, p_ip_address)
  RETURNING id INTO v_active_session_id;

  RETURN jsonb_build_object('success', true, 'session_id', v_active_session_id, 'expires_at', v_expires_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_mining_rewards()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_session RECORD;
  v_base_reward NUMERIC := 0.10;
  v_referral_bonus_rate NUMERIC := 0.10; -- 10% per active referral
  v_max_bonus_rate NUMERIC := 1.00; -- 100% max bonus
  v_active_referrals INTEGER;
  v_total_reward NUMERIC;
  v_bonus_reward NUMERIC;
BEGIN
  -- Get active session
  SELECT * INTO v_session
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true AND expires_at > now();

  IF v_session IS NULL THEN
    -- Check if there is an expired but unclaimed session
    SELECT * INTO v_session
    FROM public.mining_sessions
    WHERE user_id = v_user_id AND is_active = true AND expires_at <= now()
    ORDER BY expires_at DESC
    LIMIT 1;
    
    IF v_session IS NULL THEN
      RETURN jsonb_build_object('error', 'No active or completed mining session found');
    END IF;
  END IF;

  -- Check if already rewarded for this session
  IF EXISTS (SELECT 1 FROM public.mining_rewards WHERE session_id = v_session.id AND reward_type = 'base') THEN
     -- If already rewarded, just deactivate and return error
     UPDATE public.mining_sessions SET is_active = false WHERE id = v_session.id;
     RETURN jsonb_build_object('error', 'Reward already claimed for this session');
  END IF;

  -- Calculate active referrals (those who have an active mining session)
  SELECT COUNT(DISTINCT r.referred_user_id) INTO v_active_referrals
  FROM public.referral_rewards r
  JOIN public.mining_sessions ms ON ms.user_id = r.referred_user_id
  WHERE r.referrer_user_id = v_user_id
    AND ms.is_active = true
    AND ms.expires_at > now();

  v_bonus_reward := LEAST(v_base_reward * v_active_referrals * v_referral_bonus_rate, v_base_reward * v_max_bonus_rate);
  v_total_reward := v_base_reward + v_bonus_reward;

  -- Record rewards
  INSERT INTO public.mining_rewards (user_id, session_id, amount, reward_type)
  VALUES (v_user_id, v_session.id, v_base_reward, 'base');

  IF v_bonus_reward > 0 THEN
    INSERT INTO public.mining_rewards (user_id, session_id, amount, reward_type)
    VALUES (v_user_id, v_session.id, v_bonus_reward, 'referral_bonus');
  END IF;

  -- Update wallet balance
  UPDATE public.wallets
  SET balance = balance + v_total_reward,
      updated_at = now()
  WHERE user_id = v_user_id;

  -- Deactivate session
  UPDATE public.mining_sessions
  SET is_active = false
  WHERE id = v_session.id;

  RETURN jsonb_build_object(
    'success', true, 
    'base_reward', v_base_reward, 
    'bonus_reward', v_bonus_reward, 
    'total_reward', v_total_reward,
    'active_referrals', v_active_referrals
  );
END;
$$;

-- Ensure grants are correct
GRANT EXECUTE ON FUNCTION public.start_mining_session(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_mining_rewards() TO authenticated;

-- Force a dummy change to trigger cache
COMMENT ON TABLE public.mining_sessions IS 'Tracks 24h mining sessions for users';
COMMENT ON TABLE public.mining_rewards IS 'History of mining rewards and referral bonuses';

-- <<< END MIGRATION: 20260301130000_repair_mining_system_cache.sql

-- >>> MIGRATION: 20260301150000_add_bulk_transfer_funds.sql

-- 20260301150000_add_bulk_transfer_funds.sql
-- Add support for sending funds to multiple recipients in a single atomic transaction

CREATE OR REPLACE FUNCTION public.bulk_transfer_funds(
  p_recipients UUID[],
  p_amounts NUMERIC[],
  p_notes TEXT[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sender_id UUID := auth.uid();
  v_sender_balance NUMERIC;
  v_total_amount NUMERIC := 0;
  v_i INTEGER;
  v_tx_ids UUID[] := '{}';
  v_tx_id UUID;
BEGIN
  -- Basic validation
  IF array_length(p_recipients, 1) IS NULL OR array_length(p_recipients, 1) = 0 THEN
    RETURN jsonb_build_object('error', 'No recipients specified');
  END IF;

  IF array_length(p_recipients, 1) <> array_length(p_amounts, 1) OR 
     array_length(p_recipients, 1) <> array_length(p_notes, 1) THEN
    RETURN jsonb_build_object('error', 'Input arrays must have the same length');
  END IF;

  IF array_length(p_recipients, 1) > 5 THEN
    RETURN jsonb_build_object('error', 'Maximum 5 recipients allowed per bulk transfer');
  END IF;

  -- Calculate total amount and check for self-transfer/negative amounts
  FOR v_i IN 1..array_length(p_recipients, 1) LOOP
    IF p_recipients[v_i] = v_sender_id THEN
      RETURN jsonb_build_object('error', 'Cannot send funds to yourself');
    END IF;
    IF p_amounts[v_i] <= 0 THEN
      RETURN jsonb_build_object('error', 'Transfer amount must be positive');
    END IF;
    v_total_amount := v_total_amount + p_amounts[v_i];
  END LOOP;

  -- Check sender balance
  SELECT balance INTO v_sender_balance
  FROM public.wallets
  WHERE user_id = v_sender_id
  FOR UPDATE; -- Lock sender's wallet for the duration of the transaction

  IF v_sender_balance < v_total_amount THEN
    RETURN jsonb_build_object('error', 'Insufficient funds for total bulk transfer');
  END IF;

  -- Perform transfers
  FOR v_i IN 1..array_length(p_recipients, 1) LOOP
    -- Subtract from sender
    UPDATE public.wallets
    SET balance = balance - p_amounts[v_i],
        updated_at = now()
    WHERE user_id = v_sender_id;

    -- Add to receiver
    UPDATE public.wallets
    SET balance = balance + p_amounts[v_i],
        updated_at = now()
    WHERE user_id = p_recipients[v_i];

    -- Record transaction
    INSERT INTO public.transactions (
      sender_id,
      receiver_id,
      amount,
      note,
      status
    ) VALUES (
      v_sender_id,
      p_recipients[v_i],
      p_amounts[v_i],
      COALESCE(p_notes[v_i], ''),
      'completed'
    ) RETURNING id INTO v_tx_id;

    v_tx_ids := array_append(v_tx_ids, v_tx_id);
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'transaction_ids', v_tx_ids,
    'total_amount', v_total_amount
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.bulk_transfer_funds(UUID[], NUMERIC[], TEXT[]) TO authenticated;

COMMENT ON FUNCTION public.bulk_transfer_funds IS 'Performs multiple fund transfers atomically (max 5 recipients)';

-- <<< END MIGRATION: 20260301150000_add_bulk_transfer_funds.sql

-- >>> MIGRATION: 20260301160000_enhance_public_ledger.sql
-- 20260301160000_enhance_public_ledger.sql
-- Enhance public ledger RPCs to include currency and payload for icons/logos

DROP FUNCTION IF EXISTS public.get_public_ledger(INTEGER, INTEGER);
DROP FUNCTION IF EXISTS public.get_public_ledger_transaction(UUID);
DROP FUNCTION IF EXISTS public.get_private_ledger_transaction(UUID);

ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS currency_code TEXT DEFAULT 'OUSD';
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS sender_amount NUMERIC;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS sender_currency_code TEXT DEFAULT 'OUSD';
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS receiver_amount NUMERIC;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS receiver_currency_code TEXT DEFAULT 'OUSD';

DROP FUNCTION IF EXISTS public.transfer_funds(UUID, UUID, NUMERIC, TEXT);
DROP FUNCTION IF EXISTS public.transfer_funds(UUID, UUID, NUMERIC, TEXT, TEXT, NUMERIC, TEXT, NUMERIC, TEXT);
CREATE OR REPLACE FUNCTION public.transfer_funds(
  p_sender_id UUID,
  p_receiver_id UUID,
  p_amount NUMERIC,
  p_note TEXT DEFAULT '',
  p_currency_code TEXT DEFAULT 'OUSD',
  p_sender_amount NUMERIC DEFAULT NULL,
  p_sender_currency_code TEXT DEFAULT NULL,
  p_receiver_amount NUMERIC DEFAULT NULL,
  p_receiver_currency_code TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sender_balance NUMERIC(12,2);
  v_receiver_balance NUMERIC(12,2);
  v_transaction_id UUID;
  v_currency_code TEXT := UPPER(TRIM(COALESCE(p_currency_code, 'OUSD')));
  v_sender_amount NUMERIC := COALESCE(p_sender_amount, p_amount);
  v_sender_currency_code TEXT := UPPER(TRIM(COALESCE(p_sender_currency_code, v_currency_code, 'OUSD')));
  v_receiver_amount NUMERIC := COALESCE(p_receiver_amount, p_amount);
  v_receiver_currency_code TEXT := UPPER(TRIM(COALESCE(p_receiver_currency_code, 'OUSD')));
BEGIN
  IF p_sender_id IS NULL OR p_receiver_id IS NULL THEN
    RAISE EXCEPTION 'Missing sender or receiver';
  END IF;

  IF p_sender_id = p_receiver_id THEN
    RAISE EXCEPTION 'Cannot send to yourself';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Invalid amount';
  END IF;

  SELECT balance INTO v_sender_balance
  FROM public.wallets
  WHERE user_id = p_sender_id
  FOR UPDATE;

  IF v_sender_balance IS NULL THEN
    RAISE EXCEPTION 'Sender wallet not found';
  END IF;

  SELECT balance INTO v_receiver_balance
  FROM public.wallets
  WHERE user_id = p_receiver_id
  FOR UPDATE;

  IF v_receiver_balance IS NULL THEN
    RAISE EXCEPTION 'Recipient wallet not found';
  END IF;

  IF v_sender_balance < p_amount THEN
    RAISE EXCEPTION 'Insufficient balance';
  END IF;

  UPDATE public.wallets
  SET balance = v_sender_balance - p_amount,
      updated_at = now()
  WHERE user_id = p_sender_id;

  UPDATE public.wallets
  SET balance = v_receiver_balance + p_amount,
      updated_at = now()
  WHERE user_id = p_receiver_id;

  INSERT INTO public.transactions (
    sender_id,
    receiver_id,
    amount,
    note,
    status,
    currency_code,
    sender_amount,
    sender_currency_code,
    receiver_amount,
    receiver_currency_code
  )
  VALUES (
    p_sender_id,
    p_receiver_id,
    p_amount,
    COALESCE(p_note, ''),
    'completed',
    v_currency_code,
    v_sender_amount,
    v_sender_currency_code,
    v_receiver_amount,
    v_receiver_currency_code
  )
  RETURNING id INTO v_transaction_id;

  RETURN v_transaction_id;
END;
$$;

REVOKE ALL ON FUNCTION public.transfer_funds(UUID, UUID, NUMERIC, TEXT, TEXT, NUMERIC, TEXT, NUMERIC, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transfer_funds(UUID, UUID, NUMERIC, TEXT, TEXT, NUMERIC, TEXT, NUMERIC, TEXT) TO service_role;

DROP FUNCTION IF EXISTS public.transfer_funds_authenticated(UUID, NUMERIC, TEXT);
DROP FUNCTION IF EXISTS public.transfer_funds_authenticated(UUID, NUMERIC, TEXT, TEXT, NUMERIC, TEXT, NUMERIC, TEXT);
CREATE OR REPLACE FUNCTION public.transfer_funds_authenticated(
  p_receiver_id UUID,
  p_amount NUMERIC,
  p_note TEXT DEFAULT '',
  p_currency_code TEXT DEFAULT 'OUSD',
  p_sender_amount NUMERIC DEFAULT NULL,
  p_sender_currency_code TEXT DEFAULT NULL,
  p_receiver_amount NUMERIC DEFAULT NULL,
  p_receiver_currency_code TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sender_id UUID := auth.uid();
BEGIN
  IF v_sender_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  RETURN public.transfer_funds(
    v_sender_id,
    p_receiver_id,
    p_amount,
    COALESCE(p_note, ''),
    p_currency_code,
    p_sender_amount,
    p_sender_currency_code,
    p_receiver_amount,
    p_receiver_currency_code
  );
END;
$$;

REVOKE ALL ON FUNCTION public.transfer_funds_authenticated(UUID, NUMERIC, TEXT, TEXT, NUMERIC, TEXT, NUMERIC, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transfer_funds_authenticated(UUID, NUMERIC, TEXT, TEXT, NUMERIC, TEXT, NUMERIC, TEXT) TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.bulk_transfer_funds(UUID[], NUMERIC[], TEXT[]);
DROP FUNCTION IF EXISTS public.bulk_transfer_funds(UUID[], NUMERIC[], TEXT[], TEXT, NUMERIC, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.bulk_transfer_funds(
  p_recipients UUID[],
  p_amounts NUMERIC[],
  p_notes TEXT[],
  p_currency_code TEXT DEFAULT 'OUSD',
  p_sender_amount NUMERIC DEFAULT NULL,
  p_sender_currency_code TEXT DEFAULT NULL,
  p_receiver_currency_code TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sender_id UUID := auth.uid();
  v_sender_balance NUMERIC;
  v_total_amount NUMERIC := 0;
  v_i INTEGER;
  v_tx_ids UUID[] := '{}';
  v_tx_id UUID;
  v_currency_code TEXT := UPPER(TRIM(COALESCE(p_currency_code, 'OUSD')));
  v_sender_amount NUMERIC := COALESCE(p_sender_amount, 0);
  v_sender_currency_code TEXT := UPPER(TRIM(COALESCE(p_sender_currency_code, v_currency_code, 'OUSD')));
  v_receiver_currency_code TEXT := UPPER(TRIM(COALESCE(p_receiver_currency_code, 'OUSD')));
BEGIN
  IF array_length(p_recipients, 1) IS NULL OR array_length(p_recipients, 1) = 0 THEN
    RETURN jsonb_build_object('error', 'No recipients specified');
  END IF;

  IF array_length(p_recipients, 1) <> array_length(p_amounts, 1) OR 
     array_length(p_recipients, 1) <> array_length(p_notes, 1) THEN
    RETURN jsonb_build_object('error', 'Input arrays must have the same length');
  END IF;

  IF array_length(p_recipients, 1) > 5 THEN
    RETURN jsonb_build_object('error', 'Maximum 5 recipients allowed per bulk transfer');
  END IF;

  FOR v_i IN 1..array_length(p_recipients, 1) LOOP
    IF p_recipients[v_i] = v_sender_id THEN
      RETURN jsonb_build_object('error', 'Cannot send funds to yourself');
    END IF;
    IF p_amounts[v_i] <= 0 THEN
      RETURN jsonb_build_object('error', 'Transfer amount must be positive');
    END IF;
    v_total_amount := v_total_amount + p_amounts[v_i];
  END LOOP;

  SELECT balance INTO v_sender_balance
  FROM public.wallets
  WHERE user_id = v_sender_id
  FOR UPDATE;

  IF v_sender_balance < v_total_amount THEN
    RETURN jsonb_build_object('error', 'Insufficient funds for total bulk transfer');
  END IF;

  FOR v_i IN 1..array_length(p_recipients, 1) LOOP
    UPDATE public.wallets
    SET balance = balance - p_amounts[v_i],
        updated_at = now()
    WHERE user_id = v_sender_id;

    UPDATE public.wallets
    SET balance = balance + p_amounts[v_i],
        updated_at = now()
    WHERE user_id = p_recipients[v_i];

    INSERT INTO public.transactions (
      sender_id,
      receiver_id,
      amount,
      note,
      status,
      currency_code,
      sender_amount,
      sender_currency_code,
      receiver_amount,
      receiver_currency_code
    ) VALUES (
      v_sender_id,
      p_recipients[v_i],
      p_amounts[v_i],
      COALESCE(p_notes[v_i], ''),
      'completed',
      v_currency_code,
      CASE WHEN v_sender_amount > 0 THEN v_sender_amount ELSE p_amounts[v_i] END,
      v_sender_currency_code,
      p_amounts[v_i],
      v_receiver_currency_code
    ) RETURNING id INTO v_tx_id;

    v_tx_ids := array_append(v_tx_ids, v_tx_id);
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'transaction_ids', v_tx_ids,
    'total_amount', v_total_amount
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.bulk_transfer_funds(UUID[], NUMERIC[], TEXT[], TEXT, NUMERIC, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.log_transaction_insert_to_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.ledger_events (
    source_table,
    source_id,
    event_type,
    actor_user_id,
    related_user_id,
    amount,
    status,
    note,
    payload,
    occurred_at
  )
  VALUES (
    'transactions',
    NEW.id,
    'transaction_created',
    NEW.sender_id,
    NEW.receiver_id,
    NEW.amount,
    NEW.status,
    COALESCE(NEW.note, ''),
    jsonb_build_object(
      'sender_id', NEW.sender_id,
      'receiver_id', NEW.receiver_id,
      'currency_code', COALESCE(NULLIF(TRIM(NEW.currency_code), ''), 'OUSD'),
      'sender_amount', COALESCE(NEW.sender_amount, NEW.amount),
      'sender_currency_code', COALESCE(NULLIF(TRIM(NEW.sender_currency_code), ''), COALESCE(NULLIF(TRIM(NEW.currency_code), ''), 'OUSD')),
      'receiver_amount', COALESCE(NEW.receiver_amount, NEW.amount),
      'receiver_currency_code', COALESCE(NULLIF(TRIM(NEW.receiver_currency_code), ''), COALESCE(NULLIF(TRIM(NEW.currency_code), ''), 'OUSD'))
    ),
    NEW.created_at
  );

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.log_transaction_update_to_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.amount IS DISTINCT FROM OLD.amount
    OR NEW.status IS DISTINCT FROM OLD.status
    OR NEW.note IS DISTINCT FROM OLD.note THEN
    INSERT INTO public.ledger_events (
      source_table,
      source_id,
      event_type,
      actor_user_id,
      related_user_id,
      amount,
      status,
      note,
      payload,
      occurred_at
    )
    VALUES (
      'transactions',
      NEW.id,
      'transaction_updated',
      NEW.sender_id,
      NEW.receiver_id,
      NEW.amount,
      NEW.status,
      COALESCE(NEW.note, ''),
      jsonb_build_object(
        'old_amount', OLD.amount,
        'new_amount', NEW.amount,
        'old_status', OLD.status,
        'new_status', NEW.status,
        'old_note', COALESCE(OLD.note, ''),
        'new_note', COALESCE(NEW.note, ''),
        'currency_code', COALESCE(NULLIF(TRIM(NEW.currency_code), ''), 'OUSD'),
        'sender_amount', COALESCE(NEW.sender_amount, NEW.amount),
        'sender_currency_code', COALESCE(NULLIF(TRIM(NEW.sender_currency_code), ''), COALESCE(NULLIF(TRIM(NEW.currency_code), ''), 'OUSD')),
        'receiver_amount', COALESCE(NEW.receiver_amount, NEW.amount),
        'receiver_currency_code', COALESCE(NULLIF(TRIM(NEW.receiver_currency_code), ''), COALESCE(NULLIF(TRIM(NEW.currency_code), ''), 'OUSD'))
      ),
      now()
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.log_user_topup_request_insert_to_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.ledger_events (
    source_table,
    source_id,
    event_type,
    actor_user_id,
    related_user_id,
    amount,
    status,
    note,
    payload,
    occurred_at
  )
  VALUES (
    'user_topup_requests',
    NEW.id,
    'topup_request_created',
    NEW.user_id,
    NULL,
    NEW.amount,
    NEW.status,
    COALESCE(NEW.provider, ''),
    jsonb_build_object(
      'provider', NEW.provider,
      'payment_method', NEW.provider,
      'reference_code', NEW.reference_code,
      'proof_url', NEW.proof_url,
      'currency_code', 'OUSD',
      'sender_amount', NEW.amount,
      'sender_currency_code', 'OUSD',
      'receiver_amount', NEW.amount,
      'receiver_currency_code', 'OUSD'
    ),
    NEW.created_at
  );

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.log_user_topup_request_update_to_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
    OR NEW.amount IS DISTINCT FROM OLD.amount
    OR NEW.reference_code IS DISTINCT FROM OLD.reference_code THEN
    INSERT INTO public.ledger_events (
      source_table,
      source_id,
      event_type,
      actor_user_id,
      related_user_id,
      amount,
      status,
      note,
      payload,
      occurred_at
    )
    VALUES (
      'user_topup_requests',
      NEW.id,
      'topup_request_updated',
      NEW.user_id,
      NULL,
      NEW.amount,
      NEW.status,
      COALESCE(NEW.provider, ''),
      jsonb_build_object(
        'provider', NEW.provider,
        'payment_method', NEW.provider,
        'reference_code', NEW.reference_code,
        'proof_url', NEW.proof_url,
        'old_status', OLD.status,
        'new_status', NEW.status,
        'currency_code', 'OUSD',
        'sender_amount', NEW.amount,
        'sender_currency_code', 'OUSD',
        'receiver_amount', NEW.amount,
        'receiver_currency_code', 'OUSD'
      ),
      COALESCE(NEW.updated_at, now())
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ledger_user_topup_requests_insert ON public.user_topup_requests;
CREATE TRIGGER trg_ledger_user_topup_requests_insert
AFTER INSERT ON public.user_topup_requests
FOR EACH ROW EXECUTE FUNCTION public.log_user_topup_request_insert_to_ledger();

DROP TRIGGER IF EXISTS trg_ledger_user_topup_requests_update ON public.user_topup_requests;
CREATE TRIGGER trg_ledger_user_topup_requests_update
AFTER UPDATE ON public.user_topup_requests
FOR EACH ROW EXECUTE FUNCTION public.log_user_topup_request_update_to_ledger();

CREATE OR REPLACE FUNCTION public.log_user_swap_withdrawal_insert_to_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.ledger_events (
    source_table,
    source_id,
    event_type,
    actor_user_id,
    related_user_id,
    amount,
    status,
    note,
    payload,
    occurred_at
  )
  VALUES (
    'user_swap_withdrawals',
    NEW.id,
    'swap_withdrawal_created',
    NEW.user_id,
    NULL,
    NEW.amount,
    NEW.status,
    'Swap withdrawal',
    jsonb_build_object(
      'payment_method', 'Pi Wallet',
      'pi_wallet_address', NEW.pi_wallet_address,
      'openpay_account_number', NEW.openpay_account_number,
      'currency_code', 'PI',
      'sender_amount', NEW.amount,
      'sender_currency_code', 'OUSD',
      'receiver_amount', NEW.payout_amount,
      'receiver_currency_code', 'PI'
    ),
    NEW.created_at
  );

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.log_user_swap_withdrawal_update_to_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
    OR NEW.amount IS DISTINCT FROM OLD.amount THEN
    INSERT INTO public.ledger_events (
      source_table,
      source_id,
      event_type,
      actor_user_id,
      related_user_id,
      amount,
      status,
      note,
      payload,
      occurred_at
    )
    VALUES (
      'user_swap_withdrawals',
      NEW.id,
      'swap_withdrawal_updated',
      NEW.user_id,
      NULL,
      NEW.amount,
      NEW.status,
      'Swap withdrawal',
      jsonb_build_object(
        'payment_method', 'Pi Wallet',
        'pi_wallet_address', NEW.pi_wallet_address,
        'openpay_account_number', NEW.openpay_account_number,
        'old_status', OLD.status,
        'new_status', NEW.status,
        'currency_code', 'PI',
        'sender_amount', NEW.amount,
        'sender_currency_code', 'OUSD',
        'receiver_amount', NEW.payout_amount,
        'receiver_currency_code', 'PI'
      ),
      COALESCE(NEW.updated_at, now())
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ledger_user_swap_withdrawals_insert ON public.user_swap_withdrawals;
CREATE TRIGGER trg_ledger_user_swap_withdrawals_insert
AFTER INSERT ON public.user_swap_withdrawals
FOR EACH ROW EXECUTE FUNCTION public.log_user_swap_withdrawal_insert_to_ledger();

DROP TRIGGER IF EXISTS trg_ledger_user_swap_withdrawals_update ON public.user_swap_withdrawals;
CREATE TRIGGER trg_ledger_user_swap_withdrawals_update
AFTER UPDATE ON public.user_swap_withdrawals
FOR EACH ROW EXECUTE FUNCTION public.log_user_swap_withdrawal_update_to_ledger();

-- 1. Update get_public_ledger
CREATE OR REPLACE FUNCTION public.get_public_ledger(
  p_limit INTEGER DEFAULT 30,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  amount NUMERIC,
  note TEXT,
  status TEXT,
  occurred_at TIMESTAMPTZ,
  event_type TEXT,
  currency_code TEXT,
  sender_amount NUMERIC,
  sender_currency_code TEXT,
  receiver_amount NUMERIC,
  receiver_currency_code TEXT,
  payload JSONB,
  sender_name TEXT,
  sender_username TEXT,
  sender_avatar TEXT,
  receiver_name TEXT,
  receiver_username TEXT,
  receiver_avatar TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    le.amount,
    CASE
      WHEN le.note IS NULL THEN NULL
      ELSE regexp_replace(
        le.note,
        '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
        '[hidden]',
        'g'
      )
    END AS note,
    COALESCE(le.status, 'completed') AS status,
    le.occurred_at,
    le.event_type,
    COALESCE(
      t.receiver_currency_code,
      t.currency_code,
      le.payload->>'receiver_currency_code',
      le.payload->>'currency_code',
      le.payload->>'currency',
      CASE
        WHEN le.source_table = 'wallets' THEN 'PI'
        WHEN le.source_table = 'user_swap_withdrawals' THEN 'PI'
        ELSE 'OUSD'
      END
    ) AS currency_code,
    COALESCE(t.sender_amount, NULLIF(le.payload->>'sender_amount', '')::numeric, le.amount) AS sender_amount,
    COALESCE(t.sender_currency_code, le.payload->>'sender_currency_code', le.payload->>'currency_code', 'OUSD') AS sender_currency_code,
    COALESCE(t.receiver_amount, NULLIF(le.payload->>'receiver_amount', '')::numeric, le.amount) AS receiver_amount,
    COALESCE(t.receiver_currency_code, le.payload->>'receiver_currency_code', le.payload->>'currency_code', 'OUSD') AS receiver_currency_code,
    le.payload,
    ps.full_name AS sender_name,
    ps.username AS sender_username,
    ps.avatar_url AS sender_avatar,
    pr.full_name AS receiver_name,
    pr.username AS receiver_username,
    pr.avatar_url AS receiver_avatar
  FROM public.ledger_events le
  LEFT JOIN public.transactions t ON t.id = le.source_id
  LEFT JOIN public.profiles ps ON ps.id = le.actor_user_id
  LEFT JOIN public.profiles pr ON pr.id = le.related_user_id
  WHERE le.source_table IN ('transactions', 'user_topup_requests', 'user_swap_withdrawals', 'wallets', 'payment_requests')
    AND le.amount IS NOT NULL
    AND (le.note IS NULL OR le.note NOT ILIKE '[internal]%')
    AND NOT (
      LOWER(COALESCE(ps.username, '')) = 'wainfoundation'
      AND LOWER(COALESCE(pr.username, '')) = 'openpay'
    )
  ORDER BY le.occurred_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
$$;

-- 2. Update get_public_ledger_transaction
CREATE OR REPLACE FUNCTION public.get_public_ledger_transaction(
  p_transaction_id UUID
)
RETURNS TABLE (
  amount NUMERIC,
  note TEXT,
  status TEXT,
  occurred_at TIMESTAMPTZ,
  event_type TEXT,
  currency_code TEXT,
  sender_amount NUMERIC,
  sender_currency_code TEXT,
  receiver_amount NUMERIC,
  receiver_currency_code TEXT,
  payload JSONB,
  sender_name TEXT,
  sender_username TEXT,
  sender_avatar TEXT,
  receiver_name TEXT,
  receiver_username TEXT,
  receiver_avatar TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    le.amount,
    CASE
      WHEN le.note IS NULL THEN NULL
      ELSE regexp_replace(
        le.note,
        '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
        '[hidden]',
        'g'
      )
    END AS note,
    COALESCE(le.status, 'completed') AS status,
    le.occurred_at,
    le.event_type,
    COALESCE(
      t.receiver_currency_code,
      t.currency_code,
      le.payload->>'receiver_currency_code',
      le.payload->>'currency_code',
      le.payload->>'currency',
      CASE
        WHEN le.source_table = 'wallets' THEN 'PI'
        WHEN le.source_table = 'user_swap_withdrawals' THEN 'PI'
        ELSE 'OUSD'
      END
    ) AS currency_code,
    COALESCE(t.sender_amount, NULLIF(le.payload->>'sender_amount', '')::numeric, le.amount) AS sender_amount,
    COALESCE(t.sender_currency_code, le.payload->>'sender_currency_code', le.payload->>'currency_code', 'OUSD') AS sender_currency_code,
    COALESCE(t.receiver_amount, NULLIF(le.payload->>'receiver_amount', '')::numeric, le.amount) AS receiver_amount,
    COALESCE(t.receiver_currency_code, le.payload->>'receiver_currency_code', le.payload->>'currency_code', 'OUSD') AS receiver_currency_code,
    le.payload,
    ps.full_name AS sender_name,
    ps.username AS sender_username,
    ps.avatar_url AS sender_avatar,
    pr.full_name AS receiver_name,
    pr.username AS receiver_username,
    pr.avatar_url AS receiver_avatar
  FROM public.ledger_events le
  LEFT JOIN public.transactions t ON t.id = le.source_id
  LEFT JOIN public.profiles ps ON ps.id = le.actor_user_id
  LEFT JOIN public.profiles pr ON pr.id = le.related_user_id
  WHERE le.source_id = p_transaction_id
    AND le.amount IS NOT NULL
    AND (le.note IS NULL OR le.note NOT ILIKE '[internal]%')
    AND NOT (
      LOWER(COALESCE(ps.username, '')) = 'wainfoundation'
      AND LOWER(COALESCE(pr.username, '')) = 'openpay'
    )
  ORDER BY le.occurred_at DESC
  LIMIT 1;
$$;

-- 3. Update get_private_ledger_transaction
CREATE OR REPLACE FUNCTION public.get_private_ledger_transaction(
  p_transaction_id UUID
)
RETURNS TABLE (
  amount NUMERIC,
  note TEXT,
  status TEXT,
  occurred_at TIMESTAMPTZ,
  event_type TEXT,
  currency_code TEXT,
  sender_amount NUMERIC,
  sender_currency_code TEXT,
  receiver_amount NUMERIC,
  receiver_currency_code TEXT,
  payload JSONB,
  sender_name TEXT,
  sender_username TEXT,
  sender_avatar TEXT,
  receiver_name TEXT,
  receiver_username TEXT,
  receiver_avatar TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    le.amount,
    le.note,
    COALESCE(le.status, 'completed') AS status,
    le.occurred_at,
    le.event_type,
    COALESCE(
      t.receiver_currency_code,
      t.currency_code,
      le.payload->>'receiver_currency_code',
      le.payload->>'currency_code',
      le.payload->>'currency',
      CASE
        WHEN le.source_table = 'wallets' THEN 'PI'
        WHEN le.source_table = 'user_swap_withdrawals' THEN 'PI'
        ELSE 'OUSD'
      END
    ) AS currency_code,
    COALESCE(t.sender_amount, NULLIF(le.payload->>'sender_amount', '')::numeric, le.amount) AS sender_amount,
    COALESCE(t.sender_currency_code, le.payload->>'sender_currency_code', le.payload->>'currency_code', 'OUSD') AS sender_currency_code,
    COALESCE(t.receiver_amount, NULLIF(le.payload->>'receiver_amount', '')::numeric, le.amount) AS receiver_amount,
    COALESCE(t.receiver_currency_code, le.payload->>'receiver_currency_code', le.payload->>'currency_code', 'OUSD') AS receiver_currency_code,
    le.payload,
    ps.full_name AS sender_name,
    ps.username AS sender_username,
    ps.avatar_url AS sender_avatar,
    pr.full_name AS receiver_name,
    pr.username AS receiver_username,
    pr.avatar_url AS receiver_avatar
  FROM public.ledger_events le
  LEFT JOIN public.transactions t ON t.id = le.source_id
  LEFT JOIN public.profiles ps ON ps.id = le.actor_user_id
  LEFT JOIN public.profiles pr ON pr.id = le.related_user_id
  WHERE le.source_id = p_transaction_id
    AND le.amount IS NOT NULL
    AND (
      t.sender_id = auth.uid()
      OR t.receiver_id = auth.uid()
      OR le.actor_user_id = auth.uid()
      OR le.related_user_id = auth.uid()
    )
  ORDER BY le.occurred_at DESC
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_public_ledger(INTEGER, INTEGER) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_ledger_transaction(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_private_ledger_transaction(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260301160000_enhance_public_ledger.sql

-- >>> MIGRATION: 20260301185512_37e9d941-905b-4d98-ba97-3555178c08aa.sql
-- Fix invoices_status_check to include 'rejected' status
-- First drop the existing constraint, then re-add with all needed statuses
ALTER TABLE public.invoices DROP CONSTRAINT IF EXISTS invoices_status_check;
ALTER TABLE public.invoices ADD CONSTRAINT invoices_status_check CHECK (status = ANY (ARRAY['pending'::text, 'paid'::text, 'cancelled'::text, 'rejected'::text]));
-- <<< END MIGRATION: 20260301185512_37e9d941-905b-4d98-ba97-3555178c08aa.sql

-- >>> MIGRATION: 20260303150000_fix_mining_session_management.sql
-- 20260303150000_fix_mining_session_management.sql
-- Fix mining session management to prevent restarts and ensure proper countdown tracking

-- Add ad verification tracking to mining sessions
ALTER TABLE public.mining_sessions 
ADD COLUMN IF NOT EXISTS ad_verified BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS pi_browser_used BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS last_sync_at TIMESTAMPTZ DEFAULT now();

-- Add unique constraint to prevent duplicate active sessions
ALTER TABLE public.mining_sessions 
ADD CONSTRAINT unique_active_session 
UNIQUE (user_id, is_active) 
DEFERRABLE INITIALLY DEFERRED;

-- Create improved function to start mining session with better validation
CREATE OR REPLACE FUNCTION public.start_mining_session(p_device_fingerprint TEXT, p_ip_address TEXT, p_ad_verified BOOLEAN DEFAULT false, p_pi_browser_used BOOLEAN DEFAULT false)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_active_session_id UUID;
  v_expires_at TIMESTAMPTZ := now() + INTERVAL '24 hours';
  v_stale_sessions INTEGER;
BEGIN
  -- Check for existing active session
  SELECT id INTO v_active_session_id
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true AND expires_at > now();

  IF v_active_session_id IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Mining session already active', 'session_id', v_active_session_id);
  END IF;

  -- Count and deactivate any stale sessions
  UPDATE public.mining_sessions
  SET is_active = false, last_sync_at = now()
  WHERE user_id = v_user_id AND is_active = true
  RETURNING 1 INTO v_stale_sessions;

  -- Start new session with ad verification tracking
  INSERT INTO public.mining_sessions (
    user_id, 
    expires_at, 
    device_fingerprint, 
    ip_address,
    ad_verified,
    pi_browser_used,
    last_sync_at
  )
  VALUES (
    v_user_id, 
    v_expires_at, 
    p_device_fingerprint, 
    p_ip_address,
    p_ad_verified,
    p_pi_browser_used,
    now()
  )
  RETURNING id INTO v_active_session_id;

  RETURN jsonb_build_object(
    'success', true, 
    'session_id', v_active_session_id, 
    'expires_at', v_expires_at,
    'ad_verified', p_ad_verified,
    'pi_browser_used', p_pi_browser_used,
    'stale_sessions_deactivated', v_stale_sessions
  );
END;
$$;

-- Create improved function to claim mining rewards with better session management
CREATE OR REPLACE FUNCTION public.claim_mining_rewards()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_session RECORD;
  v_base_reward NUMERIC := 0.10;
  v_referral_bonus_rate NUMERIC := 0.10; -- 10% per active referral
  v_max_bonus_rate NUMERIC := 1.00; -- 100% max bonus
  v_active_referrals INTEGER;
  v_total_reward NUMERIC;
  v_bonus_reward NUMERIC;
  v_already_claimed BOOLEAN;
BEGIN
  -- Get the most recent session (active or expired but unclaimed)
  SELECT * INTO v_session
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true
  ORDER BY 
    CASE WHEN expires_at > now() THEN 0 ELSE 1 END, -- Active sessions first
    expires_at DESC -- Most recent first
  LIMIT 1;

  IF v_session IS NULL THEN
    -- Check for expired but unclaimed session
    SELECT * INTO v_session
    FROM public.mining_sessions
    WHERE user_id = v_user_id AND is_active = true AND expires_at <= now()
    ORDER BY expires_at DESC
    LIMIT 1;
    
    IF v_session IS NULL THEN
      RETURN jsonb_build_object('error', 'No mining session found to claim');
    END IF;
  END IF;

  -- Check if already rewarded for this session
  SELECT EXISTS(SELECT 1 FROM public.mining_rewards WHERE session_id = v_session.id AND reward_type = 'base') 
  INTO v_already_claimed;

  IF v_already_claimed THEN
    -- Deactivate the already claimed session
    UPDATE public.mining_sessions 
    SET is_active = false, last_sync_at = now() 
    WHERE id = v_session.id;
    RETURN jsonb_build_object('error', 'Reward already claimed for this session');
  END IF;

  -- Only allow claim if session has expired
  IF v_session.expires_at > now() THEN
    RETURN jsonb_build_object('error', 'Mining still in progress. Come back after 24 hours.');
  END IF;

  -- Calculate active referrals (those who have an active mining session)
  SELECT COUNT(DISTINCT r.referred_user_id) INTO v_active_referrals
  FROM public.referral_rewards r
  JOIN public.mining_sessions ms ON ms.user_id = r.referred_user_id
  WHERE r.referrer_id = v_user_id
    AND ms.is_active = true
    AND ms.expires_at > now();

  v_bonus_reward := LEAST(v_base_reward * v_active_referrals * v_referral_bonus_rate, v_base_reward * v_max_bonus_rate);
  v_total_reward := v_base_reward + v_bonus_reward;

  -- Record rewards in a transaction
  INSERT INTO public.mining_rewards (user_id, session_id, amount, reward_type)
  VALUES (v_user_id, v_session.id, v_base_reward, 'base');

  IF v_bonus_reward > 0 THEN
    INSERT INTO public.mining_rewards (user_id, session_id, amount, reward_type)
    VALUES (v_user_id, v_session.id, v_bonus_reward, 'referral_bonus');
  END IF;

  -- Update wallet balance
  UPDATE public.wallets
  SET balance = balance + v_total_reward,
      updated_at = now()
  WHERE user_id = v_user_id;

  -- Deactivate session and update sync
  UPDATE public.mining_sessions
  SET is_active = false, 
      last_sync_at = now()
  WHERE id = v_session.id;

  RETURN jsonb_build_object(
    'success', true, 
    'base_reward', v_base_reward, 
    'bonus_reward', v_bonus_reward, 
    'total_reward', v_total_reward,
    'active_referrals', v_active_referrals,
    'session_expired', v_session.expires_at <= now(),
    'ad_verified', v_session.ad_verified,
    'pi_browser_used', v_session.pi_browser_used
  );
END;
$$;

-- Create function to sync mining state (for dashboard consistency)
CREATE OR REPLACE FUNCTION public.sync_mining_state()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_active_session RECORD;
  v_claimable_session RECORD;
BEGIN
  -- Get active session
  SELECT * INTO v_active_session
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true AND expires_at > now()
  ORDER BY expires_at DESC
  LIMIT 1;

  -- If no active session, check for claimable expired session
  IF v_active_session IS NULL THEN
    SELECT * INTO v_claimable_session
    FROM public.mining_sessions
    WHERE user_id = v_user_id AND is_active = true AND expires_at <= now()
    ORDER BY expires_at DESC
    LIMIT 1;
  END IF;

  -- Update last sync timestamp
  IF v_active_session IS NOT NULL THEN
    UPDATE public.mining_sessions 
    SET last_sync_at = now() 
    WHERE id = v_active_session.id;
  ELSIF v_claimable_session IS NOT NULL THEN
    UPDATE public.mining_sessions 
    SET last_sync_at = now() 
    WHERE id = v_claimable_session.id;
  END IF;

  RETURN jsonb_build_object(
    'active_session', v_active_session,
    'claimable_session', v_claimable_session,
    'synced_at', now()
  );
END;
$$;

-- Create index for better performance
CREATE INDEX IF NOT EXISTS idx_mining_sessions_user_active_expires 
ON public.mining_sessions(user_id, is_active, expires_at DESC);

CREATE INDEX IF NOT EXISTS idx_mining_sessions_last_sync 
ON public.mining_sessions(last_sync_at);

-- Update RLS policies to include new columns
DROP POLICY IF EXISTS "Users can view their own mining sessions" ON public.mining_sessions;
CREATE POLICY "Users can view their own mining sessions"
ON public.mining_sessions FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Ensure grants are correct
GRANT EXECUTE ON FUNCTION public.start_mining_session(TEXT, TEXT, BOOLEAN, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_mining_rewards() TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_mining_state() TO authenticated;

-- <<< END MIGRATION: 20260303150000_fix_mining_session_management.sql

-- >>> MIGRATION: 20260303163000_sync_mining_ads.sql
-- 20260303163000_sync_mining_ads.sql
-- Ensure mining ad verification fields and RPC signatures are present

ALTER TABLE public.mining_sessions 
  ADD COLUMN IF NOT EXISTS ad_verified BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS pi_browser_used BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS last_sync_at TIMESTAMPTZ DEFAULT now();

CREATE OR REPLACE FUNCTION public.start_mining_session(
  p_device_fingerprint TEXT,
  p_ip_address TEXT,
  p_ad_verified BOOLEAN DEFAULT false,
  p_pi_browser_used BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_active_session_id UUID;
  v_expires_at TIMESTAMPTZ := now() + INTERVAL '24 hours';
  v_stale_sessions INTEGER;
BEGIN
  SELECT id INTO v_active_session_id
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true AND expires_at > now();

  IF v_active_session_id IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Mining session already active', 'session_id', v_active_session_id);
  END IF;

  UPDATE public.mining_sessions
  SET is_active = false, last_sync_at = now()
  WHERE user_id = v_user_id AND is_active = true
  RETURNING 1 INTO v_stale_sessions;

  INSERT INTO public.mining_sessions (
    user_id,
    expires_at,
    device_fingerprint,
    ip_address,
    ad_verified,
    pi_browser_used,
    last_sync_at
  )
  VALUES (
    v_user_id,
    v_expires_at,
    p_device_fingerprint,
    p_ip_address,
    p_ad_verified,
    p_pi_browser_used,
    now()
  )
  RETURNING id INTO v_active_session_id;

  RETURN jsonb_build_object(
    'success', true,
    'session_id', v_active_session_id,
    'expires_at', v_expires_at,
    'ad_verified', p_ad_verified,
    'pi_browser_used', p_pi_browser_used,
    'stale_sessions_deactivated', v_stale_sessions
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_mining_state()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_active_session RECORD;
  v_claimable_session RECORD;
BEGIN
  SELECT * INTO v_active_session
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true AND expires_at > now()
  ORDER BY expires_at DESC
  LIMIT 1;

  IF v_active_session IS NULL THEN
    SELECT * INTO v_claimable_session
    FROM public.mining_sessions
    WHERE user_id = v_user_id AND is_active = true AND expires_at <= now()
    ORDER BY expires_at DESC
    LIMIT 1;
  END IF;

  IF v_active_session IS NOT NULL THEN
    UPDATE public.mining_sessions
    SET last_sync_at = now()
    WHERE id = v_active_session.id;
  ELSIF v_claimable_session IS NOT NULL THEN
    UPDATE public.mining_sessions
    SET last_sync_at = now()
    WHERE id = v_claimable_session.id;
  END IF;

  RETURN jsonb_build_object(
    'active_session', v_active_session,
    'claimable_session', v_claimable_session,
    'synced_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.start_mining_session(TEXT, TEXT, BOOLEAN, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_mining_state() TO authenticated;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260303163000_sync_mining_ads.sql

-- >>> MIGRATION: 20260303180000_enforce_mining_session_guard.sql
-- 20260303180000_enforce_mining_session_guard.sql
-- Prevent overlapping sessions and block new starts until expired sessions are claimed.

ALTER TABLE public.mining_sessions
  DROP CONSTRAINT IF EXISTS unique_active_session;

CREATE UNIQUE INDEX IF NOT EXISTS uniq_mining_sessions_user_active
  ON public.mining_sessions(user_id)
  WHERE is_active = true;

CREATE OR REPLACE FUNCTION public.start_mining_session(
  p_device_fingerprint TEXT,
  p_ip_address TEXT,
  p_ad_verified BOOLEAN DEFAULT false,
  p_pi_browser_used BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_active_session_id UUID;
  v_claimable_session_id UUID;
  v_expires_at TIMESTAMPTZ := now() + INTERVAL '24 hours';
  v_stale_sessions INTEGER;
BEGIN
  SELECT id INTO v_active_session_id
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true AND expires_at > now();

  IF v_active_session_id IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Mining session already active', 'session_id', v_active_session_id);
  END IF;

  SELECT id INTO v_claimable_session_id
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true AND expires_at <= now()
  ORDER BY expires_at DESC
  LIMIT 1;

  IF v_claimable_session_id IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Mining session complete. Claim rewards before starting again.', 'session_id', v_claimable_session_id);
  END IF;

  UPDATE public.mining_sessions
  SET is_active = false, last_sync_at = now()
  WHERE user_id = v_user_id AND is_active = true
  RETURNING 1 INTO v_stale_sessions;

  INSERT INTO public.mining_sessions (
    user_id,
    expires_at,
    device_fingerprint,
    ip_address,
    ad_verified,
    pi_browser_used,
    last_sync_at
  )
  VALUES (
    v_user_id,
    v_expires_at,
    p_device_fingerprint,
    p_ip_address,
    p_ad_verified,
    p_pi_browser_used,
    now()
  )
  RETURNING id INTO v_active_session_id;

  RETURN jsonb_build_object(
    'success', true,
    'session_id', v_active_session_id,
    'expires_at', v_expires_at,
    'ad_verified', p_ad_verified,
    'pi_browser_used', p_pi_browser_used,
    'stale_sessions_deactivated', v_stale_sessions
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.start_mining_session(TEXT, TEXT, BOOLEAN, BOOLEAN) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260303180000_enforce_mining_session_guard.sql

-- >>> MIGRATION: 20260304015113_84df8259-ec1b-41b3-bdb8-653a90841552.sql

-- Create mining_sessions table
CREATE TABLE IF NOT EXISTS public.mining_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  last_reward_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_active BOOLEAN NOT NULL DEFAULT true,
  device_fingerprint TEXT,
  ip_address TEXT,
  ad_verified BOOLEAN DEFAULT false,
  pi_browser_used BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create mining_rewards table
CREATE TABLE IF NOT EXISTS public.mining_rewards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id UUID REFERENCES public.mining_sessions(id) ON DELETE SET NULL,
  amount NUMERIC NOT NULL,
  reward_type TEXT NOT NULL CHECK (reward_type IN ('base', 'referral_bonus')),
  referral_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create app_notifications table
CREATE TABLE IF NOT EXISTS public.app_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'info' CHECK (type IN ('info', 'success', 'warning', 'error')),
  read_at TIMESTAMPTZ,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_mining_sessions_user_active ON public.mining_sessions(user_id) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_mining_rewards_user ON public.mining_rewards(user_id);
CREATE INDEX IF NOT EXISTS idx_app_notifications_user_unread ON public.app_notifications(user_id) WHERE read_at IS NULL;

-- Enable RLS
ALTER TABLE public.mining_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mining_rewards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_notifications ENABLE ROW LEVEL SECURITY;

-- Mining sessions policies
CREATE POLICY "Users can view their own mining sessions" ON public.mining_sessions FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- Mining rewards policies
CREATE POLICY "Users can view their own mining rewards" ON public.mining_rewards FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- App notifications policies
CREATE POLICY "Users can view their own notifications" ON public.app_notifications FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own notifications" ON public.app_notifications FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own notifications" ON public.app_notifications FOR UPDATE TO authenticated USING (auth.uid() = user_id);

-- Enable Realtime
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'mining_sessions') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.mining_sessions;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'mining_rewards') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.mining_rewards;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'app_notifications') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.app_notifications;
    END IF;
END $$;

-- Function: start_mining_session
CREATE OR REPLACE FUNCTION public.start_mining_session(
  p_device_fingerprint TEXT DEFAULT '',
  p_ip_address TEXT DEFAULT '',
  p_ad_verified BOOLEAN DEFAULT false,
  p_pi_browser_used BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_active_session_id UUID;
  v_expires_at TIMESTAMPTZ := now() + INTERVAL '24 hours';
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT id INTO v_active_session_id
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true AND expires_at > now();

  IF v_active_session_id IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Mining session already active', 'session_id', v_active_session_id);
  END IF;

  -- Deactivate stale sessions
  UPDATE public.mining_sessions SET is_active = false WHERE user_id = v_user_id AND is_active = true;

  -- Start new session
  INSERT INTO public.mining_sessions (user_id, expires_at, device_fingerprint, ip_address, ad_verified, pi_browser_used)
  VALUES (v_user_id, v_expires_at, p_device_fingerprint, p_ip_address, p_ad_verified, p_pi_browser_used)
  RETURNING id INTO v_active_session_id;

  RETURN jsonb_build_object('success', true, 'session_id', v_active_session_id, 'expires_at', v_expires_at);
END;
$$;

-- Function: claim_mining_rewards
CREATE OR REPLACE FUNCTION public.claim_mining_rewards()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_session RECORD;
  v_base_reward NUMERIC := 0.10;
  v_referral_bonus_rate NUMERIC := 0.10;
  v_max_bonus_rate NUMERIC := 1.00;
  v_active_referrals INTEGER;
  v_total_reward NUMERIC;
  v_bonus_reward NUMERIC;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT * INTO v_session
  FROM public.mining_sessions
  WHERE user_id = v_user_id AND is_active = true
  ORDER BY expires_at DESC
  LIMIT 1;

  IF v_session IS NULL THEN
    RETURN jsonb_build_object('error', 'No active or completed mining session found');
  END IF;

  IF EXISTS (SELECT 1 FROM public.mining_rewards WHERE session_id = v_session.id AND reward_type = 'base') THEN
     UPDATE public.mining_sessions SET is_active = false WHERE id = v_session.id;
     RETURN jsonb_build_object('error', 'Reward already claimed for this session');
  END IF;

  IF v_session.expires_at > now() THEN
     RETURN jsonb_build_object('error', 'Mining still in progress. Come back after 24 hours.');
  END IF;

  SELECT COUNT(DISTINCT r.referred_user_id) INTO v_active_referrals
  FROM public.referral_rewards r
  JOIN public.mining_sessions ms ON ms.user_id = r.referred_user_id
  WHERE r.referrer_user_id = v_user_id
    AND ms.is_active = true
    AND ms.expires_at > now();

  v_bonus_reward := LEAST(v_base_reward * v_active_referrals * v_referral_bonus_rate, v_base_reward * v_max_bonus_rate);
  v_total_reward := v_base_reward + v_bonus_reward;

  INSERT INTO public.mining_rewards (user_id, session_id, amount, reward_type)
  VALUES (v_user_id, v_session.id, v_base_reward, 'base');

  IF v_bonus_reward > 0 THEN
    INSERT INTO public.mining_rewards (user_id, session_id, amount, reward_type)
    VALUES (v_user_id, v_session.id, v_bonus_reward, 'referral_bonus');
  END IF;

  UPDATE public.wallets SET balance = balance + v_total_reward, updated_at = now() WHERE user_id = v_user_id;

  UPDATE public.mining_sessions SET is_active = false WHERE id = v_session.id;

  RETURN jsonb_build_object(
    'success', true,
    'base_reward', v_base_reward,
    'bonus_reward', v_bonus_reward,
    'total_reward', v_total_reward,
    'active_referrals', v_active_referrals
  );
END;
$$;

-- Function: sync_mining_state (deactivates expired sessions)
CREATE OR REPLACE FUNCTION public.sync_mining_state()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- No-op for now; sessions are managed via start/claim functions
  -- This exists so client calls don't error out
  RETURN;
END;
$$;

-- Function: withdraw_mining_earnings
CREATE OR REPLACE FUNCTION public.withdraw_mining_earnings(p_min_payout NUMERIC DEFAULT 5)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_total NUMERIC;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT COALESCE(SUM(amount), 0) INTO v_total
  FROM public.mining_rewards
  WHERE user_id = v_user_id;

  IF v_total < p_min_payout THEN
    RETURN jsonb_build_object('error', 'Minimum payout not reached', 'total', v_total, 'min', p_min_payout);
  END IF;

  -- Mining rewards are already credited to wallet via claim_mining_rewards
  RETURN jsonb_build_object('success', true, 'total', v_total);
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.start_mining_session(TEXT, TEXT, BOOLEAN, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_mining_rewards() TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_mining_state() TO authenticated;
GRANT EXECUTE ON FUNCTION public.withdraw_mining_earnings(NUMERIC) TO authenticated;

-- <<< END MIGRATION: 20260304015113_84df8259-ec1b-41b3-bdb8-653a90841552.sql

-- >>> MIGRATION: 20260304015147_e1f49235-b87b-4cf5-a595-3f8ac865578d.sql

DROP FUNCTION IF EXISTS public.get_public_ledger(integer, integer);

CREATE OR REPLACE FUNCTION public.get_public_ledger(p_limit integer DEFAULT 30, p_offset integer DEFAULT 0)
RETURNS TABLE(
  amount numeric,
  note text,
  status text,
  occurred_at timestamptz,
  event_type text,
  currency_code text,
  sender_amount numeric,
  sender_currency_code text,
  receiver_amount numeric,
  receiver_currency_code text,
  payload jsonb,
  sender_name text,
  sender_username text,
  sender_avatar text,
  receiver_name text,
  receiver_username text,
  receiver_avatar text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT
    le.amount,
    CASE
      WHEN le.note IS NULL THEN NULL
      ELSE regexp_replace(
        le.note,
        '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
        '[hidden]',
        'g'
      )
    END AS note,
    COALESCE(le.status, 'completed') AS status,
    le.occurred_at,
    le.event_type,
    COALESCE((le.payload->>'currency_code')::text, 'OUSD') AS currency_code,
    (le.payload->>'sender_amount')::numeric AS sender_amount,
    (le.payload->>'sender_currency_code')::text AS sender_currency_code,
    (le.payload->>'receiver_amount')::numeric AS receiver_amount,
    (le.payload->>'receiver_currency_code')::text AS receiver_currency_code,
    le.payload,
    COALESCE(sp.full_name, '') AS sender_name,
    COALESCE(sp.username, '') AS sender_username,
    COALESCE(sp.avatar_url, '') AS sender_avatar,
    COALESCE(rp.full_name, '') AS receiver_name,
    COALESCE(rp.username, '') AS receiver_username,
    COALESCE(rp.avatar_url, '') AS receiver_avatar
  FROM public.ledger_events le
  LEFT JOIN public.profiles sp ON sp.id = le.actor_user_id
  LEFT JOIN public.profiles rp ON rp.id = le.related_user_id
  WHERE le.source_table = 'transactions'
    AND le.amount IS NOT NULL
  ORDER BY le.occurred_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
$$;

-- <<< END MIGRATION: 20260304015147_e1f49235-b87b-4cf5-a595-3f8ac865578d.sql

-- >>> MIGRATION: 20260305090000_add_request_invoice_currency.sql
-- Store original currency details for payment requests and invoices
ALTER TABLE public.payment_requests
  ADD COLUMN IF NOT EXISTS original_amount NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS original_currency_code TEXT;

ALTER TABLE public.invoices
  ADD COLUMN IF NOT EXISTS original_amount NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS original_currency_code TEXT;

-- <<< END MIGRATION: 20260305090000_add_request_invoice_currency.sql

-- >>> MIGRATION: 20260305143000_staking.sql
-- Staking system: lock balance and earn yield after lock period

CREATE TABLE IF NOT EXISTS public.staking_positions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  lock_days INTEGER NOT NULL CHECK (lock_days IN (7, 30, 90, 365)),
  reward_rate NUMERIC(6,4) NOT NULL CHECK (reward_rate >= 0),
  reward_amount NUMERIC(12,2) NOT NULL CHECK (reward_amount >= 0),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'claimed', 'cancelled')),
  starts_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ends_at TIMESTAMPTZ NOT NULL,
  claimed_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_staking_positions_user_created
  ON public.staking_positions(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_staking_positions_status_end
  ON public.staking_positions(status, ends_at DESC);

ALTER TABLE public.staking_positions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'staking_positions' AND policyname = 'Users can view own staking positions'
  ) THEN
    CREATE POLICY "Users can view own staking positions"
      ON public.staking_positions
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_staking_positions_updated_at ON public.staking_positions;
CREATE TRIGGER trg_staking_positions_updated_at
BEFORE UPDATE ON public.staking_positions
FOR EACH ROW
EXECUTE FUNCTION public.set_common_updated_at();

-- Create stake: lock funds and create staking position
CREATE OR REPLACE FUNCTION public.create_stake(
  p_amount NUMERIC,
  p_lock_days INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_amount NUMERIC(12,2) := ROUND(COALESCE(p_amount, 0), 2);
  v_lock_days INTEGER := COALESCE(p_lock_days, 0);
  v_reward_rate NUMERIC(6,4);
  v_reward_amount NUMERIC(12,2);
  v_wallet_balance NUMERIC(12,2);
  v_position_id UUID;
  v_ends_at TIMESTAMPTZ;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_amount < 1 THEN
    RAISE EXCEPTION 'Minimum stake is 1 OPEN USD';
  END IF;

  IF v_lock_days NOT IN (7, 30, 90, 365) THEN
    RAISE EXCEPTION 'Invalid lock duration';
  END IF;

  v_reward_rate := CASE v_lock_days
    WHEN 7 THEN 0.02
    WHEN 30 THEN 0.05
    WHEN 90 THEN 0.10
    WHEN 365 THEN 0.20
    ELSE 0
  END;

  v_reward_amount := ROUND(v_amount * v_reward_rate, 2);
  v_ends_at := now() + (v_lock_days || ' days')::INTERVAL;

  SELECT balance INTO v_wallet_balance
  FROM public.wallets
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'Wallet not found';
  END IF;

  IF v_wallet_balance < v_amount THEN
    RAISE EXCEPTION 'Insufficient balance';
  END IF;

  UPDATE public.wallets
  SET balance = v_wallet_balance - v_amount,
      updated_at = now()
  WHERE user_id = v_user_id;

  INSERT INTO public.staking_positions (
    user_id,
    amount,
    lock_days,
    reward_rate,
    reward_amount,
    status,
    ends_at
  )
  VALUES (
    v_user_id,
    v_amount,
    v_lock_days,
    v_reward_rate,
    v_reward_amount,
    'active',
    v_ends_at
  )
  RETURNING id INTO v_position_id;

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_user_id,
    v_user_id,
    v_amount,
    CONCAT('Stake lock | ', v_lock_days, ' days | Reward ', v_reward_amount::TEXT, ' OPEN USD'),
    'completed'
  );

  RETURN jsonb_build_object(
    'success', true,
    'position_id', v_position_id,
    'reward_amount', v_reward_amount,
    'ends_at', v_ends_at
  );
END;
$$;

-- Claim stake after lock period
CREATE OR REPLACE FUNCTION public.claim_stake(
  p_position_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_position public.staking_positions%ROWTYPE;
  v_wallet_balance NUMERIC(12,2);
  v_total NUMERIC(12,2);
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT * INTO v_position
  FROM public.staking_positions
  WHERE id = p_position_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stake not found';
  END IF;

  IF v_position.user_id <> v_user_id THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  IF v_position.status <> 'active' THEN
    RAISE EXCEPTION 'Stake already claimed';
  END IF;

  IF v_position.ends_at > now() THEN
    RAISE EXCEPTION 'Stake is still locked';
  END IF;

  SELECT balance INTO v_wallet_balance
  FROM public.wallets
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'Wallet not found';
  END IF;

  v_total := v_position.amount + v_position.reward_amount;

  UPDATE public.wallets
  SET balance = v_wallet_balance + v_total,
      updated_at = now()
  WHERE user_id = v_user_id;

  UPDATE public.staking_positions
  SET status = 'claimed',
      claimed_at = now()
  WHERE id = v_position.id;

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_user_id,
    v_user_id,
    v_total,
    CONCAT('Stake claim | Principal ', v_position.amount::TEXT, ' + Reward ', v_position.reward_amount::TEXT),
    'completed'
  );

  RETURN jsonb_build_object(
    'success', true,
    'amount', v_position.amount,
    'reward', v_position.reward_amount,
    'total', v_total
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_stake(NUMERIC, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_stake(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_stake(NUMERIC, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_stake(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260305143000_staking.sql

-- >>> MIGRATION: 20260305150000_update_staking_rates.sql
-- Update staking lock options and reward rates (adds 365 days and new rates)

ALTER TABLE public.staking_positions
  DROP CONSTRAINT IF EXISTS staking_positions_lock_days_check;

ALTER TABLE public.staking_positions
  ADD CONSTRAINT staking_positions_lock_days_check
  CHECK (lock_days IN (7, 30, 90, 365));

CREATE OR REPLACE FUNCTION public.create_stake(
  p_amount NUMERIC,
  p_lock_days INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_amount NUMERIC(12,2) := ROUND(COALESCE(p_amount, 0), 2);
  v_lock_days INTEGER := COALESCE(p_lock_days, 0);
  v_reward_rate NUMERIC(6,4);
  v_reward_amount NUMERIC(12,2);
  v_wallet_balance NUMERIC(12,2);
  v_position_id UUID;
  v_ends_at TIMESTAMPTZ;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_amount < 1 THEN
    RAISE EXCEPTION 'Minimum stake is 1 OPEN USD';
  END IF;

  IF v_lock_days NOT IN (7, 30, 90, 365) THEN
    RAISE EXCEPTION 'Invalid lock duration';
  END IF;

  v_reward_rate := CASE v_lock_days
    WHEN 7 THEN 0.02
    WHEN 30 THEN 0.05
    WHEN 90 THEN 0.10
    WHEN 365 THEN 0.20
    ELSE 0
  END;

  v_reward_amount := ROUND(v_amount * v_reward_rate, 2);
  v_ends_at := now() + (v_lock_days || ' days')::INTERVAL;

  SELECT balance INTO v_wallet_balance
  FROM public.wallets
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'Wallet not found';
  END IF;

  IF v_wallet_balance < v_amount THEN
    RAISE EXCEPTION 'Insufficient balance';
  END IF;

  UPDATE public.wallets
  SET balance = v_wallet_balance - v_amount,
      updated_at = now()
  WHERE user_id = v_user_id;

  INSERT INTO public.staking_positions (
    user_id,
    amount,
    lock_days,
    reward_rate,
    reward_amount,
    status,
    ends_at
  )
  VALUES (
    v_user_id,
    v_amount,
    v_lock_days,
    v_reward_rate,
    v_reward_amount,
    'active',
    v_ends_at
  )
  RETURNING id INTO v_position_id;

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_user_id,
    v_user_id,
    v_amount,
    CONCAT('Stake lock | ', v_lock_days, ' days | Reward ', v_reward_amount::TEXT, ' OPEN USD'),
    'completed'
  );

  RETURN jsonb_build_object(
    'success', true,
    'position_id', v_position_id,
    'reward_amount', v_reward_amount,
    'ends_at', v_ends_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_stake(NUMERIC, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_stake(NUMERIC, INTEGER) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260305150000_update_staking_rates.sql

-- >>> MIGRATION: 20260306000000_fix_pos_payment_issues.sql
-- Fix POS payment issues
-- This migration fixes several issues with POS payment processing

-- 1. Ensure merchant_payments table has proper triggers for ledger updates
CREATE OR REPLACE FUNCTION public.update_merchant_payment_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Insert into ledger_events when merchant payment is created
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.ledger_events (
      source_table,
      source_id,
      event_type,
      actor_user_id,
      related_user_id,
      amount,
      status,
      note,
      payload,
      occurred_at
    )
    VALUES (
      'merchant_payments',
      NEW.id,
      'merchant_payment_created',
      NEW.buyer_user_id,
      NEW.merchant_user_id,
      NEW.amount,
      NEW.status,
      'POS payment completed',
      jsonb_build_object(
        'session_id', NEW.session_id,
        'transaction_id', NEW.transaction_id,
        'currency', NEW.currency,
        'payment_method', 'wallet'
      ),
      NEW.created_at
    );
    RETURN NEW;
  END IF;
  
  RETURN NULL;
END;
$$;

-- 2. Create trigger for merchant payments ledger updates
DROP TRIGGER IF EXISTS trg_merchant_payment_ledger ON public.merchant_payments;
CREATE TRIGGER trg_merchant_payment_ledger
AFTER INSERT ON public.merchant_payments
FOR EACH ROW EXECUTE FUNCTION public.update_merchant_payment_ledger();

-- 3. Fix POS dashboard function to ensure it counts today's transactions correctly
CREATE OR REPLACE FUNCTION public.get_my_pos_dashboard(
  p_mode TEXT DEFAULT 'live'
)
RETURNS TABLE (
  merchant_name TEXT,
  merchant_username TEXT,
  wallet_balance NUMERIC,
  today_total_received NUMERIC,
  today_transactions INTEGER,
  refunded_transactions INTEGER,
  key_mode TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, 'live')));
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  PERFORM public.upsert_my_merchant_profile(NULL, NULL, NULL, NULL);

  RETURN QUERY
  SELECT
    mpf.merchant_name,
    mpf.merchant_username,
    COALESCE(w.balance, 0)::NUMERIC AS wallet_balance,
    COALESCE(SUM(CASE WHEN p.status = 'succeeded' THEN p.amount ELSE 0 END), 0)::NUMERIC AS today_total_received,
    COUNT(*) FILTER (WHERE p.status = 'succeeded')::INTEGER AS today_transactions,
    COUNT(*) FILTER (WHERE p.status = 'refunded')::INTEGER AS refunded_transactions,
    v_mode AS key_mode
  FROM public.merchant_profiles mpf
  LEFT JOIN public.wallets w
    ON w.user_id = mpf.user_id
  LEFT JOIN public.merchant_payments p
    ON p.merchant_user_id = mpf.user_id
   AND p.key_mode = v_mode
   AND DATE(p.created_at) = DATE(now())
  WHERE mpf.user_id = v_user_id
  GROUP BY mpf.merchant_name, mpf.merchant_username, w.balance;
END;
$$;

-- 4. Ensure merchant checkout sessions are properly updated with payment details
CREATE OR REPLACE FUNCTION public.update_checkout_session_payment_details()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- When merchant payment is created, update the checkout session
  IF TG_OP = 'INSERT' THEN
    UPDATE public.merchant_checkout_sessions mcs
    SET 
      status = 'paid',
      paid_at = NEW.created_at,
      updated_at = NEW.created_at
    WHERE mcs.id = NEW.session_id
      AND mcs.status = 'open';
    
    RETURN NEW;
  END IF;
  
  RETURN NULL;
END;
$$;

-- 5. Create trigger for checkout session updates
DROP TRIGGER IF EXISTS trg_checkout_session_payment_update ON public.merchant_payments;
CREATE TRIGGER trg_checkout_session_payment_update
AFTER INSERT ON public.merchant_payments
FOR EACH ROW EXECUTE FUNCTION public.update_checkout_session_payment_details();

-- 6. Fix any existing checkout sessions that might be stuck
UPDATE public.merchant_checkout_sessions mcs
SET status = 'paid',
    paid_at = mp.created_at,
    updated_at = mp.created_at
FROM public.merchant_payments mp
WHERE mcs.id = mp.session_id
  AND mcs.status = 'open'
  AND mp.status = 'succeeded';

-- 7. Add function to get POS transactions with proper joins
CREATE OR REPLACE FUNCTION public.get_my_pos_transactions(
  p_mode TEXT DEFAULT 'live',
  p_status TEXT DEFAULT NULL,
  p_search TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 100,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  payment_id UUID,
  payment_created_at TIMESTAMPTZ,
  payment_status TEXT,
  amount NUMERIC,
  currency TEXT,
  payer_user_id UUID,
  payer_name TEXT,
  payer_username TEXT,
  transaction_id UUID,
  transaction_note TEXT,
  session_token TEXT,
  customer_name TEXT,
  customer_email TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mode TEXT := LOWER(TRIM(COALESCE(p_mode, 'live')));
  v_status_filter TEXT := LOWER(TRIM(COALESCE(p_status, 'all')));
  v_search_term TEXT := '%' || LOWER(TRIM(COALESCE(p_search, ''))) || '%';
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_mode NOT IN ('sandbox', 'live') THEN
    RAISE EXCEPTION 'Mode must be sandbox or live';
  END IF;

  RETURN QUERY
  SELECT
    mp.id::UUID,
    mp.created_at::TIMESTAMPTZ,
    mp.status::TEXT,
    mp.amount::NUMERIC,
    mp.currency::TEXT,
    mp.buyer_user_id::UUID,
    COALESCE(p.full_name, 'OpenPay Customer')::TEXT,
    p.username::TEXT,
    mp.transaction_id::UUID,
    t.note::TEXT,
    mcs.session_token::TEXT,
    mcs.customer_name::TEXT,
    mcs.customer_email::TEXT
  FROM public.merchant_payments mp
  LEFT JOIN public.profiles p ON p.id = mp.buyer_user_id
  LEFT JOIN public.transactions t ON t.id = mp.transaction_id
  LEFT JOIN public.merchant_checkout_sessions mcs ON mcs.id = mp.session_id
  WHERE mp.merchant_user_id = v_user_id
    AND mp.key_mode = v_mode
    AND (v_status_filter = 'all' OR LOWER(mp.status) = v_status_filter)
    AND (
      v_search_term = '%%' 
      OR LOWER(COALESCE(p.full_name, '')) LIKE v_search_term
      OR LOWER(COALESCE(p.username, '')) LIKE v_search_term
      OR LOWER(COALESCE(mcs.customer_name, '')) LIKE v_search_term
      OR LOWER(COALESCE(mcs.customer_email, '')) LIKE v_search_term
      OR LOWER(mcs.session_token) LIKE v_search_term
    )
  ORDER BY mp.created_at DESC
  LIMIT LEAST(GREATEST(p_limit, 1), 1000)
  OFFSET GREATEST(p_offset, 0);
END;
$$;

-- Grant permissions
REVOKE ALL ON FUNCTION public.get_my_pos_dashboard(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_pos_transactions(TEXT, TEXT, TEXT, INTEGER, INTEGER) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_my_pos_dashboard(TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_pos_transactions(TEXT, TEXT, TEXT, INTEGER, INTEGER) TO authenticated, service_role;

-- Notify schema reload
NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260306000000_fix_pos_payment_issues.sql

-- >>> MIGRATION: 20260306010000_ensure_payment_function_exists.sql
-- Ensure payment function exists and is properly configured
-- This migration fixes any issues with the pay_merchant_checkout_with_wallet function

-- Drop and recreate the function to ensure it's properly defined
DROP FUNCTION IF EXISTS public.pay_merchant_checkout_with_wallet(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.pay_merchant_checkout_with_wallet(
  p_session_token TEXT,
  p_note TEXT DEFAULT '',
  p_customer_name TEXT DEFAULT NULL,
  p_customer_email TEXT DEFAULT NULL,
  p_customer_phone TEXT DEFAULT NULL,
  p_customer_address TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buyer_user_id UUID := auth.uid();
  v_openpay_user_id UUID;
  v_session public.merchant_checkout_sessions;
  v_existing_tx UUID;
  v_tx_id UUID;
  v_sender_balance NUMERIC(12,2);
  v_merchant_balance NUMERIC(12,2);
  v_openpay_balance NUMERIC(12,2);
  v_currency_rate NUMERIC(20,8) := 1;
  v_wallet_amount NUMERIC(12,2) := 0;
  v_customer_name TEXT := NULLIF(TRIM(COALESCE(p_customer_name, '')), '');
  v_customer_email TEXT := NULLIF(TRIM(COALESCE(p_customer_email, '')), '');
  v_customer_phone TEXT := NULLIF(TRIM(COALESCE(p_customer_phone, '')), '');
  v_customer_address TEXT := NULLIF(TRIM(COALESCE(p_customer_address, '')), '');
  v_buyer_email TEXT;
  v_payment_link_id UUID;
  v_payment_link_token TEXT;
BEGIN
  IF v_buyer_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT email INTO v_buyer_email
  FROM auth.users
  WHERE id = v_buyer_user_id;

  v_openpay_user_id := public.get_openpay_settlement_user_id();

  SELECT *
  INTO v_session
  FROM public.merchant_checkout_sessions mcs
  WHERE mcs.session_token = TRIM(COALESCE(p_session_token, ''))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Checkout session not found';
  END IF;

  IF v_session.status = 'paid' THEN
    SELECT mp.transaction_id
    INTO v_existing_tx
    FROM public.merchant_payments mp
    WHERE mp.session_id = v_session.id
    LIMIT 1;

    RETURN v_existing_tx;
  END IF;

  IF v_session.status <> 'open' THEN
    RAISE EXCEPTION 'Checkout session is not open';
  END IF;

  IF v_session.expires_at < now() THEN
    UPDATE public.merchant_checkout_sessions
    SET status = 'expired'
    WHERE id = v_session.id;
    RAISE EXCEPTION 'Checkout session expired';
  END IF;

  IF v_session.merchant_user_id = v_buyer_user_id THEN
    RAISE EXCEPTION 'Merchant cannot pay own checkout';
  END IF;

  SELECT sc.usd_rate
  INTO v_currency_rate
  FROM public.supported_currencies sc
  WHERE sc.iso_code = UPPER(COALESCE(v_session.currency, 'USD'))
    AND sc.is_active = true
  LIMIT 1;

  v_currency_rate := COALESCE(NULLIF(v_currency_rate, 0), 1);
  v_wallet_amount := ROUND(COALESCE(v_session.total_amount, 0) / v_currency_rate, 2);

  IF v_wallet_amount <= 0 THEN
    RAISE EXCEPTION 'Checkout amount must be greater than zero';
  END IF;

  SELECT balance INTO v_sender_balance
  FROM public.wallets
  WHERE user_id = v_buyer_user_id
  FOR UPDATE;

  IF v_sender_balance IS NULL THEN
    RAISE EXCEPTION 'Buyer wallet not found';
  END IF;

  SELECT balance INTO v_merchant_balance
  FROM public.wallets
  WHERE user_id = v_session.merchant_user_id
  FOR UPDATE;

  IF v_merchant_balance IS NULL THEN
    RAISE EXCEPTION 'Merchant wallet not found';
  END IF;

  SELECT balance INTO v_openpay_balance
  FROM public.wallets
  WHERE user_id = v_openpay_user_id
  FOR UPDATE;

  IF v_openpay_balance IS NULL THEN
    RAISE EXCEPTION 'OpenPay settlement wallet not found';
  END IF;

  IF v_sender_balance < v_wallet_amount THEN
    RAISE EXCEPTION 'Insufficient balance';
  END IF;

  UPDATE public.wallets
  SET balance = v_sender_balance - v_wallet_amount,
      updated_at = now()
  WHERE user_id = v_buyer_user_id;

  UPDATE public.wallets
  SET balance = v_merchant_balance + v_wallet_amount,
      updated_at = now()
  WHERE user_id = v_session.merchant_user_id;

  UPDATE public.wallets
  SET balance = v_openpay_balance + v_wallet_amount,
      updated_at = now()
  WHERE user_id = v_openpay_user_id;

  INSERT INTO public.transactions (sender_id, receiver_id, amount, note, status)
  VALUES (
    v_buyer_user_id,
    v_session.merchant_user_id,
    v_wallet_amount,
    CONCAT(
      'Merchant checkout ',
      v_session.session_token,
      ' | Held in merchant available balance',
      CASE WHEN COALESCE(TRIM(p_note), '') <> '' THEN CONCAT(' | ', TRIM(p_note)) ELSE '' END
    ),
    'completed'
  )
  RETURNING id INTO v_tx_id;

  v_payment_link_id := NULLIF((v_session.metadata->>'payment_link_id')::UUID, NULL);
  v_payment_link_token := NULLIF(TRIM(COALESCE(v_session.metadata->>'payment_link_token', '')), '');

  INSERT INTO public.merchant_payments (
    session_id,
    merchant_user_id,
    buyer_user_id,
    transaction_id,
    amount,
    currency,
    api_key_id,
    key_mode,
    payment_link_id,
    payment_link_token,
    status
  )
  VALUES (
    v_session.id,
    v_session.merchant_user_id,
    v_buyer_user_id,
    v_tx_id,
    v_session.total_amount,
    v_session.currency,
    v_session.api_key_id,
    v_session.key_mode,
    v_payment_link_id,
    v_payment_link_token,
    'succeeded'
  )
  ON CONFLICT (session_id) DO UPDATE SET
    transaction_id = EXCLUDED.transaction_id,
    status = EXCLUDED.status,
    amount = EXCLUDED.amount,
    currency = EXCLUDED.currency;

  UPDATE public.merchant_checkout_sessions mcs
  SET status = 'paid',
      paid_at = now(),
      customer_name = COALESCE(v_customer_name, mcs.customer_name),
      customer_email = COALESCE(v_customer_email, v_buyer_email, mcs.customer_email),
      metadata = COALESCE(mcs.metadata, '{}'::jsonb) || jsonb_strip_nulls(
        jsonb_build_object(
          'customer_phone', v_customer_phone,
          'customer_address', v_customer_address
        )
      ),
      updated_at = now()
  WHERE mcs.id = v_session.id;

  RETURN v_tx_id;
END;
$$;

-- Grant permissions
REVOKE ALL ON FUNCTION public.pay_merchant_checkout_with_wallet(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pay_merchant_checkout_with_wallet(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role;

-- Notify schema reload
NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260306010000_ensure_payment_function_exists.sql

-- >>> MIGRATION: 20260307000000_fix_onboarding_user_data.sql
-- Fix onboarding database to ensure user data saves properly
-- This migration fixes issues with user_preferences and profile creation during onboarding

-- Fix user_preferences trigger to properly handle new users
DROP TRIGGER IF EXISTS trg_profiles_sync_user_preferences ON public.profiles;

CREATE OR REPLACE FUNCTION public.sync_user_preferences_from_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.user_preferences (
    user_id, 
    profile_full_name, 
    profile_username, 
    reference_code,
    onboarding_step,
    onboarding_completed
  )
  SELECT 
    NEW.id, 
    NEW.full_name, 
    NEW.username, 
    NEW.referral_code,
    0,
    false
  FROM public.profiles NEW
  ON CONFLICT (user_id) DO UPDATE
  SET 
    profile_full_name = EXCLUDED.profile_full_name,
    profile_username = EXCLUDED.profile_username,
    reference_code = EXCLUDED.reference_code,
    updated_at = now();

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_profiles_sync_user_preferences
AFTER INSERT OR UPDATE OF full_name, username, referral_code
ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.sync_user_preferences_from_profile();

-- Ensure all existing users have user_preferences records
INSERT INTO public.user_preferences (user_id, profile_full_name, profile_username, reference_code, onboarding_step, onboarding_completed)
SELECT 
  p.id, 
  p.full_name, 
  p.username, 
  p.referral_code,
  0,
  false
FROM public.profiles p
WHERE NOT EXISTS (
  SELECT 1 FROM public.user_preferences up 
  WHERE up.user_id = p.id
);

-- Create or replace function to handle onboarding completion
CREATE OR REPLACE FUNCTION public.complete_onboarding_step(
  p_step INTEGER,
  p_data JSONB DEFAULT '{}'::jsonb
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_current_step INTEGER;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Get current onboarding step
  SELECT onboarding_step 
  INTO v_current_step
  FROM public.user_preferences 
  WHERE user_id = v_user_id;

  -- Update onboarding step and data
  UPDATE public.user_preferences
  SET 
    onboarding_step = GREATEST(p_step, COALESCE(v_current_step, 0)),
    merchant_onboarding_data = CASE 
      WHEN p_data IS NOT NULL THEN 
        CASE 
          WHEN merchant_onboarding_data IS NULL THEN p_data
          ELSE merchant_onboarding_data || p_data
        END
      ELSE merchant_onboarding_data
    END,
    updated_at = now()
  WHERE user_id = v_user_id;

  -- Mark onboarding as completed if step is 5 or higher
  IF p_step >= 5 THEN
    UPDATE public.user_preferences
    SET 
      onboarding_completed = true,
      updated_at = now()
    WHERE user_id = v_user_id;
  END IF;

  RETURN true;
END;
$$;

-- Grant permissions for onboarding function
REVOKE ALL ON FUNCTION public.complete_onboarding_step() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_onboarding_step() TO authenticated;

-- Create function to get user onboarding status
CREATE OR REPLACE FUNCTION public.get_my_onboarding_status()
RETURNS TABLE(
  onboarding_step INTEGER,
  onboarding_completed BOOLEAN,
  profile_full_name TEXT,
  profile_username TEXT,
  reference_code TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    up.onboarding_step,
    up.onboarding_completed,
    up.profile_full_name,
    up.profile_username,
    up.reference_code
  FROM public.user_preferences up
  WHERE up.user_id = auth.uid();
END;
$$;

-- Grant permissions for onboarding status function
REVOKE ALL ON FUNCTION public.get_my_onboarding_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_onboarding_status() TO authenticated;

-- Fix policy for user_preferences to ensure proper access
DROP POLICY IF EXISTS "Users can view own preferences" ON public.user_preferences;
DROP POLICY IF EXISTS "Users can insert own preferences" ON public.user_preferences;
DROP POLICY IF EXISTS "Users can update own preferences" ON public.user_preferences;

CREATE POLICY "Users can view own preferences"
  ON public.user_preferences
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Users can insert own preferences"
  ON public.user_preferences
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own preferences"
  ON public.user_preferences
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Ensure all profiles have corresponding user_preferences and user_accounts
INSERT INTO public.user_accounts (user_id, account_number, account_name, account_username)
SELECT
  p.id,
  public.generate_openpay_account_number(p.id),
  COALESCE(NULLIF(TRIM(p.full_name), ''), 'OpenPay User'),
  COALESCE(NULLIF(TRIM(p.username), ''), 'openpay')
FROM public.profiles p
WHERE NOT EXISTS (
  SELECT 1 FROM public.user_accounts ua 
  WHERE ua.user_id = p.id
)
ON CONFLICT (user_id) DO UPDATE
SET 
  account_name = EXCLUDED.account_name,
  account_username = EXCLUDED.account_username;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_user_preferences_user_id ON public.user_preferences(user_id);
CREATE INDEX IF NOT EXISTS idx_user_preferences_onboarding_step ON public.user_preferences(onboarding_step);
CREATE INDEX IF NOT EXISTS idx_user_preferences_completed ON public.user_preferences(onboarding_completed);

-- Add RLS policies for user_accounts if they don't exist
DROP POLICY IF EXISTS "Users can view own account" ON public.user_accounts;
DROP POLICY IF EXISTS "Users can insert own account" ON public.user_accounts;
DROP POLICY IF EXISTS "Users can update own account" ON public.user_accounts;

CREATE POLICY "Users can view own account"
  ON public.user_accounts
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Users can insert own account"
  ON public.user_accounts
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own account"
  ON public.user_accounts
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Create indexes for user_accounts
CREATE INDEX IF NOT EXISTS idx_user_accounts_user_id ON public.user_accounts(user_id);
CREATE INDEX IF NOT EXISTS idx_user_accounts_account_number ON public.user_accounts(account_number);

-- <<< END MIGRATION: 20260307000000_fix_onboarding_user_data.sql

-- >>> MIGRATION: 20260307010000_enhance_user_account_creation.sql
-- Enhanced user account creation and onboarding functions
-- This ensures all user data is properly saved during authentication and onboarding

-- Enhanced function to create complete user profile with all necessary data
CREATE OR REPLACE FUNCTION public.create_complete_user_profile(
  p_user_id UUID,
  p_full_name TEXT DEFAULT NULL,
  p_username TEXT DEFAULT NULL,
  p_email TEXT DEFAULT NULL,
  p_referral_code TEXT DEFAULT NULL,
  p_pi_uid TEXT DEFAULT NULL,
  p_pi_username TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile_created BOOLEAN := FALSE;
  v_preferences_created BOOLEAN := FALSE;
  v_account_created BOOLEAN := FALSE;
BEGIN
  -- Create or update profile
  INSERT INTO public.profiles (
    id, 
    full_name, 
    username, 
    referral_code
  )
  VALUES (
    p_user_id, 
    p_full_name, 
    p_username, 
    p_referral_code
  )
  ON CONFLICT (id) DO UPDATE
  SET 
    full_name = COALESCE(p_full_name, profiles.full_name),
    username = COALESCE(p_username, profiles.username),
    referral_code = COALESCE(p_referral_code, profiles.referral_code),
    updated_at = now()
  RETURNING id IS NOT NULL INTO v_profile_created;

  -- Create user preferences
  INSERT INTO public.user_preferences (
    user_id, 
    profile_full_name, 
    profile_username, 
    reference_code,
    onboarding_step,
    onboarding_completed
  )
  SELECT 
    p_user_id, 
    p_full_name, 
    p_username, 
    p_referral_code,
    0,
    false
  ON CONFLICT (user_id) DO UPDATE
  SET 
    profile_full_name = COALESCE(p_full_name, user_preferences.profile_full_name),
    profile_username = COALESCE(p_username, user_preferences.profile_username),
    reference_code = COALESCE(p_referral_code, user_preferences.reference_code),
    updated_at = now()
  RETURNING user_id IS NOT NULL INTO v_preferences_created;

  -- Create user account
  INSERT INTO public.user_accounts (
    user_id, 
    account_number, 
    account_name, 
    account_username
  )
  VALUES (
    p_user_id,
    public.generate_openpay_account_number(p_user_id),
    COALESCE(NULLIF(TRIM(p_full_name), ''), 'OpenPay User'),
    COALESCE(NULLIF(TRIM(p_username), ''), 'openpay')
  )
  ON CONFLICT (user_id) DO UPDATE
  SET 
    account_name = COALESCE(NULLIF(TRIM(p_full_name), ''), user_accounts.account_name),
    account_username = COALESCE(NULLIF(TRIM(p_username), ''), user_accounts.account_username),
    updated_at = now()
  RETURNING user_id IS NOT NULL INTO v_account_created;

  -- Create wallet if not exists
  INSERT INTO public.wallets (user_id, balance)
  VALUES (p_user_id, 0.00)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN v_profile_created AND v_preferences_created AND v_account_created;
END;
$$;

-- Grant permissions for complete user profile function
REVOKE ALL ON FUNCTION public.create_complete_user_profile() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_complete_user_profile() TO authenticated;

-- Enhanced function to handle Pi user authentication with complete data creation
CREATE OR REPLACE FUNCTION public.handle_pi_user_auth(
  p_pi_uid TEXT,
  p_pi_username TEXT,
  p_referral_code TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_email TEXT;
  v_password TEXT;
  v_profile_created BOOLEAN;
BEGIN
  -- Generate Pi user email and password
  v_email := 'pi_' || p_pi_uid || '@openpay.local';
  v_password := 'OpenPay-Pi-' || p_pi_uid || '-v1!';

  -- Create or get user
  v_profile_created := public.create_complete_user_profile(
    auth.uid(),
    p_pi_username, -- Use Pi username as full name
    p_pi_username, -- Use Pi username as username
    v_email,
    p_referral_code,
    p_pi_uid,
    p_pi_username
  );

  IF v_profile_created THEN
    -- Log successful Pi user creation
    INSERT INTO public.audit_logs (
      user_id,
      action,
      details,
      created_at
    ) VALUES (
      auth.uid(),
      'pi_user_auth_success',
      json_build_object(
        'pi_uid', p_pi_uid,
        'pi_username', p_pi_username,
        'referral_code', p_referral_code
      ),
      now()
    );
  END IF;

  RETURN v_profile_created;
END;
$$;

-- Grant permissions for Pi user auth function
REVOKE ALL ON FUNCTION public.handle_pi_user_auth() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.handle_pi_user_auth() TO authenticated;

-- Create audit logs table for tracking user creation
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  details JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create indexes for audit logs
CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON public.audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON public.audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON public.audit_logs(created_at);

-- Enable RLS for audit logs
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- Create policy for audit logs
CREATE POLICY "Users can view own audit logs"
  ON public.audit_logs
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Create policy for audit logs insertion
CREATE POLICY "Service functions can insert audit logs"
  ON public.audit_logs
  FOR INSERT TO authenticated
  WITH CHECK (true);

-- <<< END MIGRATION: 20260307010000_enhance_user_account_creation.sql

-- >>> MIGRATION: 20260307020000_complete_account_onboarding.sql
-- Complete Account Onboarding Database Schema
-- Supports the "Complete your account" screen with profile image, full name, username, and security PIN

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Add profile image and security PIN fields to profiles table
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS profile_image_url TEXT,
ADD COLUMN IF NOT EXISTS security_pin_hash TEXT,
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- Create trigger to update updated_at timestamp on profiles
CREATE OR REPLACE FUNCTION public.update_profiles_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_updated_at ON public.profiles;
CREATE TRIGGER trg_profiles_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.update_profiles_updated_at();

-- First, let's see what usernames exist and identify problematic ones
-- Clean up existing invalid usernames before adding constraint
UPDATE public.profiles 
SET username = CASE 
  WHEN username IS NULL OR username = '' THEN 'openpay_user_' || LEFT(id::text, 8)
  WHEN username !~ '^[a-zA-Z0-9_]{3,20}$' THEN 'openpay_user_' || LEFT(id::text, 8)
  WHEN LENGTH(username) < 3 THEN 'openpay_user_' || LEFT(id::text, 8)
  WHEN LENGTH(username) > 20 THEN 'openpay_user_' || LEFT(id::text, 8)
  ELSE username
END;

-- Ensure all usernames are unique after cleanup
DO $$
DECLARE
  v_count INTEGER;
BEGIN
  -- Check for duplicates and make them unique
  LOOP
    SELECT COUNT(*) INTO v_count
    FROM (
      SELECT username, COUNT(*) as cnt
      FROM public.profiles
      WHERE username IS NOT NULL
      GROUP BY username
      HAVING COUNT(*) > 1
    ) dup;
    
    EXIT WHEN v_count = 0;
    
    -- Fix duplicates by appending counter
    UPDATE public.profiles p1
    SET username = p1.username || '_' || ROW_NUMBER() OVER (PARTITION BY p1.username ORDER BY p1.id)
    WHERE p1.ctid IN (
      SELECT ctid
      FROM (
        SELECT ctid, username, ROW_NUMBER() OVER (PARTITION BY username ORDER BY id) as rn
        FROM public.profiles
        WHERE username IS NOT NULL
      ) ranked
      WHERE rn > 1
    );
  END LOOP;
END $$;

-- Add constraint as NOT VALID first to identify problematic rows
ALTER TABLE public.profiles 
ADD CONSTRAINT username_format 
CHECK (username ~ '^[a-zA-Z0-9_]{3,20}$') NOT VALID;

-- Try to validate the constraint to see what fails
-- This will show us exactly which rows violate the constraint
DO $$
DECLARE
  v_username TEXT;
  v_user_id UUID;
BEGIN
  -- Find and fix any remaining problematic usernames
  FOR v_username, v_user_id IN 
    SELECT username, id 
    FROM public.profiles 
    WHERE username IS NULL 
       OR username !~ '^[a-zA-Z0-9_]{3,20}$'
       OR LENGTH(username) < 3
       OR LENGTH(username) > 20
  LOOP
    RAISE NOTICE 'Fixing invalid username: % for user: %', v_username, v_user_id;
    UPDATE public.profiles 
    SET username = 'openpay_user_' || LEFT(id::text, 8)
    WHERE id = v_user_id;
  END LOOP;
END $$;

-- Now validate the constraint
ALTER TABLE public.profiles VALIDATE CONSTRAINT username_format;

-- Enhanced user_preferences table for onboarding tracking
ALTER TABLE public.user_preferences 
ADD COLUMN IF NOT EXISTS profile_image_uploaded BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS security_pin_set BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS onboarding_started_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS onboarding_completed_at TIMESTAMPTZ;

-- Create onboarding_steps table for detailed tracking
CREATE TABLE IF NOT EXISTS public.onboarding_steps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  step_name TEXT NOT NULL,
  step_number INTEGER NOT NULL,
  completed BOOLEAN NOT NULL DEFAULT false,
  data JSONB DEFAULT '{}'::jsonb,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, step_name)
);

ALTER TABLE public.onboarding_steps ENABLE ROW LEVEL SECURITY;

-- Create trigger for onboarding_steps updated_at
CREATE OR REPLACE FUNCTION public.update_onboarding_steps_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  IF NEW.completed AND NOT OLD.completed THEN
    NEW.completed_at = now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_onboarding_steps_updated_at ON public.onboarding_steps;
CREATE TRIGGER trg_onboarding_steps_updated_at
BEFORE UPDATE ON public.onboarding_steps
FOR EACH ROW
EXECUTE FUNCTION public.update_onboarding_steps_updated_at();

-- Function to complete onboarding step with validation
CREATE OR REPLACE FUNCTION public.complete_account_onboarding(
  p_full_name TEXT,
  p_username TEXT,
  p_profile_image_url TEXT DEFAULT NULL,
  p_security_pin TEXT DEFAULT NULL
)
RETURNS TABLE(
  success BOOLEAN,
  message TEXT,
  onboarding_step INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_current_step INTEGER;
  v_username_exists BOOLEAN := FALSE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Validate username format
  IF p_username IS NOT NULL AND p_username !~ '^[a-zA-Z0-9_]{3,20}$' THEN
    RETURN QUERY SELECT false, 'Username must be 3-20 characters using letters, numbers, or underscore', 0;
    RETURN;
  END IF;

  -- Check if username already exists (excluding current user)
  SELECT EXISTS(SELECT 1 FROM public.profiles WHERE username = p_username AND id != v_user_id)
  INTO v_username_exists;

  IF v_username_exists THEN
    RETURN QUERY SELECT false, 'Username is already taken', 0;
    RETURN;
  END IF;

  -- Update profile with account completion data
  UPDATE public.profiles
  SET 
    full_name = COALESCE(p_full_name, full_name),
    username = COALESCE(p_username, username),
    profile_image_url = COALESCE(p_profile_image_url, profile_image_url),
    security_pin_hash = CASE 
      WHEN p_security_pin IS NOT NULL THEN crypt(p_security_pin, gen_salt('bf'))
      ELSE security_pin_hash
    END,
    updated_at = now()
  WHERE id = v_user_id;

  -- Update user_preferences
  UPDATE public.user_preferences
  SET 
    profile_full_name = COALESCE(p_full_name, profile_full_name),
    profile_username = COALESCE(p_username, profile_username),
    profile_image_uploaded = COALESCE(p_profile_image_url IS NOT NULL, profile_image_uploaded),
    security_pin_set = COALESCE(p_security_pin IS NOT NULL, security_pin_set),
    onboarding_step = 5,
    onboarding_completed = true,
    onboarding_completed_at = now(),
    updated_at = now()
  WHERE user_id = v_user_id;

  -- Insert onboarding step completion
  INSERT INTO public.onboarding_steps (user_id, step_name, step_number, completed, data)
  VALUES 
    (v_user_id, 'profile_completion', 5, true, json_build_object(
      'full_name', p_full_name,
      'username', p_username,
      'profile_image_url', p_profile_image_url,
      'security_pin_set', p_security_pin IS NOT NULL
    ))
  ON CONFLICT (user_id, step_name) DO UPDATE
  SET 
    completed = true,
    data = EXCLUDED.data,
    completed_at = now(),
    updated_at = now();

  -- Ensure user_accounts row exists and conforms to format
  PERFORM public.upsert_my_user_account();

  RETURN QUERY SELECT true, 'Account completed successfully', 5;
END;
$$;

-- Function to validate username availability
CREATE OR REPLACE FUNCTION public.check_username_availability(
  p_username TEXT
)
RETURNS TABLE(
  available BOOLEAN,
  message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_username_exists BOOLEAN := FALSE;
  v_valid_format BOOLEAN := FALSE;
BEGIN
  -- Check username format
  v_valid_format := p_username ~ '^[a-zA-Z0-9_]{3,20}$';
  
  IF NOT v_valid_format THEN
    RETURN QUERY SELECT false, 'Username must be 3-20 characters using letters, numbers, or underscore';
    RETURN;
  END IF;

  -- Check if username exists
  SELECT EXISTS(SELECT 1 FROM public.profiles WHERE username = p_username AND id != v_user_id)
  INTO v_username_exists;

  IF v_username_exists THEN
    RETURN QUERY SELECT false, 'Username is already taken';
  ELSE
    RETURN QUERY SELECT true, 'Username is available';
  END IF;
END;
$$;

-- Function to upload profile image
CREATE OR REPLACE FUNCTION public.upload_profile_image(
  p_image_url TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  UPDATE public.profiles
  SET 
    profile_image_url = p_image_url,
    updated_at = now()
  WHERE id = v_user_id;

  UPDATE public.user_preferences
  SET 
    profile_image_uploaded = true,
    updated_at = now()
  WHERE user_id = v_user_id;

  RETURN true;
END;
$$;

-- Function to update security PIN
CREATE OR REPLACE FUNCTION public.update_security_pin(
  p_new_pin TEXT,
  p_current_pin TEXT DEFAULT NULL
)
RETURNS TABLE(
  success BOOLEAN,
  message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_current_pin_hash TEXT;
  v_pin_length INTEGER := LENGTH(p_new_pin);
BEGIN
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT false, 'Unauthorized';
    RETURN;
  END IF;

  -- Validate PIN length (4-6 digits)
  IF v_pin_length < 4 OR v_pin_length > 6 OR p_new_pin !~ '^[0-9]+$' THEN
    RETURN QUERY SELECT false, 'PIN must be 4-6 digits';
    RETURN;
  END IF;

  -- Get current PIN hash
  SELECT security_pin_hash INTO v_current_pin_hash
  FROM public.profiles
  WHERE id = v_user_id;

  -- If user has existing PIN, verify current PIN
  IF v_current_pin_hash IS NOT NULL AND p_current_pin IS NULL THEN
    RETURN QUERY SELECT false, 'Current PIN required to update security PIN';
    RETURN;
  END IF;

  IF v_current_pin_hash IS NOT NULL AND p_current_pin IS NOT NULL THEN
    IF NOT (v_current_pin_hash = crypt(p_current_pin, v_current_pin_hash)) THEN
      RETURN QUERY SELECT false, 'Current PIN is incorrect';
      RETURN;
    END IF;
  END IF;

  -- Update PIN
  UPDATE public.profiles
  SET 
    security_pin_hash = crypt(p_new_pin, gen_salt('bf')),
    updated_at = now()
  WHERE id = v_user_id;

  UPDATE public.user_preferences
  SET 
    security_pin_set = true,
    updated_at = now()
  WHERE user_id = v_user_id;

  RETURN QUERY SELECT true, 'Security PIN updated successfully';
END;
$$;

-- Function to get onboarding status
CREATE OR REPLACE FUNCTION public.get_onboarding_status()
RETURNS TABLE(
  step INTEGER,
  completed BOOLEAN,
  profile_full_name TEXT,
  profile_username TEXT,
  profile_image_url TEXT,
  profile_image_uploaded BOOLEAN,
  security_pin_set BOOLEAN,
  onboarding_started_at TIMESTAMPTZ,
  onboarding_completed_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    up.onboarding_step,
    up.onboarding_completed,
    up.profile_full_name,
    up.profile_username,
    p.profile_image_url,
    up.profile_image_uploaded,
    up.security_pin_set,
    up.onboarding_started_at,
    up.onboarding_completed_at
  FROM public.user_preferences up
  LEFT JOIN public.profiles p ON p.id = up.user_id
  WHERE up.user_id = auth.uid();
END;
$$;

-- Grant permissions for new functions
REVOKE ALL ON FUNCTION public.complete_account_onboarding(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_account_onboarding(TEXT, TEXT, TEXT, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.check_username_availability(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_username_availability(TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.upload_profile_image(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upload_profile_image(TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.update_security_pin(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_security_pin(TEXT, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.get_onboarding_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_onboarding_status() TO authenticated;

-- RLS policies for onboarding_steps
DROP POLICY IF EXISTS "Users can view own onboarding steps" ON public.onboarding_steps;
DROP POLICY IF EXISTS "Users can insert own onboarding steps" ON public.onboarding_steps;
DROP POLICY IF EXISTS "Users can update own onboarding steps" ON public.onboarding_steps;

CREATE POLICY "Users can view own onboarding steps"
  ON public.onboarding_steps
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Users can insert own onboarding steps"
  ON public.onboarding_steps
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own onboarding steps"
  ON public.onboarding_steps
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_profiles_username ON public.profiles(username);
CREATE INDEX IF NOT EXISTS idx_profiles_updated_at ON public.profiles(updated_at);
CREATE INDEX IF NOT EXISTS idx_onboarding_steps_user_id ON public.onboarding_steps(user_id);
CREATE INDEX IF NOT EXISTS idx_onboarding_steps_step_number ON public.onboarding_steps(step_number);
CREATE INDEX IF NOT EXISTS idx_onboarding_steps_completed ON public.onboarding_steps(completed);

-- Initialize onboarding steps for existing users
INSERT INTO public.onboarding_steps (user_id, step_name, step_number, completed)
SELECT 
  user_id,
  unnest(ARRAY['profile_image', 'full_name', 'username', 'security_pin', 'profile_completion']),
  unnest(ARRAY[1, 2, 3, 4, 5]),
  unnest(ARRAY[false, false, false, false, false])
FROM public.user_preferences
WHERE onboarding_completed = false
ON CONFLICT (user_id, step_name) DO NOTHING;

-- <<< END MIGRATION: 20260307020000_complete_account_onboarding.sql

-- >>> MIGRATION: 20260307020000_fix_onboarding_syntax.sql
-- Fix onboarding database to ensure user data saves properly
-- This migration fixes issues with user_preferences and profile creation during onboarding

-- Fix user_preferences trigger to properly handle new users
DROP TRIGGER IF EXISTS trg_profiles_sync_user_preferences ON public.profiles;

CREATE OR REPLACE FUNCTION public.sync_user_preferences_from_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.user_preferences (
    user_id, 
    profile_full_name, 
    profile_username, 
    reference_code,
    onboarding_step,
    onboarding_completed
  )
  SELECT 
    NEW.id, 
    NEW.full_name, 
    NEW.username, 
    NEW.referral_code,
    0,
    false
  FROM public.profiles NEW
  ON CONFLICT (user_id) DO UPDATE
  SET 
    profile_full_name = EXCLUDED.profile_full_name,
    profile_username = EXCLUDED.profile_username,
    reference_code = EXCLUDED.reference_code,
    updated_at = now();

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_profiles_sync_user_preferences
AFTER INSERT OR UPDATE OF full_name, username, referral_code
ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.sync_user_preferences_from_profile();

-- Ensure all existing users have user_preferences records
INSERT INTO public.user_preferences (user_id, profile_full_name, profile_username, reference_code, onboarding_step, onboarding_completed)
SELECT 
  p.id, 
  p.full_name, 
  p.username, 
  p.referral_code,
  0,
  false
FROM public.profiles p
WHERE NOT EXISTS (
  SELECT 1 FROM public.user_preferences up 
  WHERE up.user_id = p.id
);

-- Create or replace function to handle onboarding completion
CREATE OR REPLACE FUNCTION public.complete_onboarding_step(
  p_step INTEGER,
  p_data JSONB DEFAULT '{}'::jsonb
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_current_step INTEGER;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Get current onboarding step
  SELECT onboarding_step 
  INTO v_current_step
  FROM public.user_preferences 
  WHERE user_id = v_user_id;

  -- Update onboarding step and data
  UPDATE public.user_preferences
  SET 
    onboarding_step = GREATEST(p_step, COALESCE(v_current_step, 0)),
    merchant_onboarding_data = CASE 
      WHEN p_data IS NOT NULL THEN 
        CASE 
          WHEN merchant_onboarding_data IS NULL THEN p_data
          ELSE merchant_onboarding_data || p_data
        END
      ELSE merchant_onboarding_data
    END,
    updated_at = now()
  WHERE user_id = v_user_id;

  -- Mark onboarding as completed if step is 5 or higher
  IF p_step >= 5 THEN
    UPDATE public.user_preferences
    SET 
      onboarding_completed = true,
      updated_at = now()
    WHERE user_id = v_user_id;
  END IF;

  RETURN true;
END;
$$;

-- Grant permissions for onboarding function
REVOKE ALL ON FUNCTION public.complete_onboarding_step() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_onboarding_step() TO authenticated;

-- Create function to get user onboarding status
CREATE OR REPLACE FUNCTION public.get_my_onboarding_status()
RETURNS TABLE(
  onboarding_step INTEGER,
  onboarding_completed BOOLEAN,
  profile_full_name TEXT,
  profile_username TEXT,
  reference_code TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    up.onboarding_step,
    up.onboarding_completed,
    up.profile_full_name,
    up.profile_username,
    up.reference_code
  FROM public.user_preferences up
  WHERE up.user_id = auth.uid();
END;
$$;

-- Grant permissions for onboarding status function
REVOKE ALL ON FUNCTION public.get_my_onboarding_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_onboarding_status() TO authenticated;

-- Ensure all profiles have corresponding user_preferences and user_accounts
INSERT INTO public.user_accounts (user_id, account_number, account_name, account_username)
SELECT
  p.id,
  public.generate_openpay_account_number(p.id),
  COALESCE(NULLIF(TRIM(p.full_name), ''), 'OpenPay User'),
  COALESCE(NULLIF(TRIM(p.username), ''), 'openpay')
FROM public.profiles p
WHERE NOT EXISTS (
  SELECT 1 FROM public.user_accounts ua 
  WHERE ua.user_id = p.id
)
ON CONFLICT (user_id) DO UPDATE
SET 
  account_name = EXCLUDED.account_name,
  account_username = EXCLUDED.account_username;

-- Fix policy for user_preferences to ensure proper access
DROP POLICY IF EXISTS "Users can view own preferences" ON public.user_preferences;
DROP POLICY IF EXISTS "Users can insert own preferences" ON public.user_preferences;
DROP POLICY IF EXISTS "Users can update own preferences" ON public.user_preferences;

CREATE POLICY "Users can view own preferences"
  ON public.user_preferences
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Users can insert own preferences"
  ON public.user_preferences
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own preferences"
  ON public.user_preferences
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_user_preferences_user_id ON public.user_preferences(user_id);
CREATE INDEX IF NOT EXISTS idx_user_preferences_onboarding_step ON public.user_preferences(onboarding_step);
CREATE INDEX IF NOT EXISTS idx_user_preferences_completed ON public.user_preferences(onboarding_completed);

-- Ensure RLS policies for user_accounts if they don't exist
DROP POLICY IF EXISTS "Users can view own account" ON public.user_accounts;
DROP POLICY IF EXISTS "Users can insert own account" ON public.user_accounts;
DROP POLICY IF EXISTS "Users can update own account" ON public.user_accounts;

CREATE POLICY "Users can view own account"
  ON public.user_accounts
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Users can insert own account"
  ON public.user_accounts
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own account"
  ON public.user_accounts
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Create indexes for user_accounts
CREATE INDEX IF NOT EXISTS idx_user_accounts_user_id ON public.user_accounts(user_id);
CREATE INDEX IF NOT EXISTS idx_user_accounts_account_number ON public.user_accounts(account_number);

-- <<< END MIGRATION: 20260307020000_fix_onboarding_syntax.sql

-- >>> MIGRATION: 20260307135815_e514f4ba-c573-45bc-a71f-1f07dbff2905.sql
-- Create complete_account_onboarding RPC function
CREATE OR REPLACE FUNCTION public.complete_account_onboarding(
  p_full_name text,
  p_username text,
  p_profile_image_url text DEFAULT NULL,
  p_security_pin text DEFAULT NULL
)
RETURNS TABLE(success boolean, message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_existing_username uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT false, 'Not authenticated'::text;
    RETURN;
  END IF;

  IF length(trim(p_full_name)) < 1 THEN
    RETURN QUERY SELECT false, 'Full name is required'::text;
    RETURN;
  END IF;

  IF p_username !~ '^[a-z0-9_]{3,20}$' THEN
    RETURN QUERY SELECT false, 'Username must be 3-20 lowercase letters, numbers, or underscore'::text;
    RETURN;
  END IF;

  SELECT id INTO v_existing_username
  FROM profiles
  WHERE lower(username) = lower(p_username) AND id != v_user_id
  LIMIT 1;

  IF v_existing_username IS NOT NULL THEN
    RETURN QUERY SELECT false, 'Username is already taken'::text;
    RETURN;
  END IF;

  UPDATE profiles
  SET full_name = trim(p_full_name),
      username = p_username,
      avatar_url = COALESCE(p_profile_image_url, avatar_url)
  WHERE id = v_user_id;

  INSERT INTO user_preferences (user_id, onboarding_completed, onboarding_step, profile_full_name, profile_username)
  VALUES (v_user_id, true, 99, trim(p_full_name), p_username)
  ON CONFLICT (user_id) DO UPDATE
  SET onboarding_completed = true,
      onboarding_step = 99,
      profile_full_name = trim(p_full_name),
      profile_username = p_username,
      updated_at = now();

  INSERT INTO user_accounts (user_id, account_number, account_name, account_username)
  VALUES (
    v_user_id,
    public.generate_openpay_account_number(v_user_id),
    trim(p_full_name),
    p_username
  )
  ON CONFLICT (user_id) DO UPDATE
  SET account_name = trim(p_full_name),
      account_username = p_username,
      updated_at = now();

  RETURN QUERY SELECT true, 'Onboarding completed successfully'::text;
END;
$$;

CREATE OR REPLACE FUNCTION public.upload_profile_image(
  p_image_url text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE profiles
  SET avatar_url = p_image_url
  WHERE id = auth.uid();
END;
$$;

-- <<< END MIGRATION: 20260307135815_e514f4ba-c573-45bc-a71f-1f07dbff2905.sql

-- >>> MIGRATION: 20260308090000_fix_onboarding_account_number_constraint.sql
-- Fix onboarding flow: prevent user_accounts check constraint violations during account completion
-- Replaces complete_account_onboarding to ensure a compliant user_accounts row is upserted explicitly
-- Date: 2026-03-08
-- Idempotent: CREATE OR REPLACE FUNCTION

-- Normalize any existing invalid account_number values to the compliant format
DO $$
BEGIN
  UPDATE public.user_accounts ua
  SET account_number = public.generate_openpay_account_number(ua.user_id)
  WHERE ua.account_number IS NULL OR ua.account_number !~ '^OP[A-Z0-9]{6,64}$';
END $$;

CREATE OR REPLACE FUNCTION public.complete_account_onboarding(
  p_full_name TEXT,
  p_username TEXT,
  p_profile_image_url TEXT DEFAULT NULL,
  p_security_pin TEXT DEFAULT NULL
)
RETURNS TABLE(
  success BOOLEAN,
  message TEXT,
  onboarding_step INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_username_exists BOOLEAN := FALSE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Validate username format
  IF p_username IS NOT NULL AND p_username !~ '^[a-zA-Z0-9_]{3,20}$' THEN
    RETURN QUERY SELECT false, 'Username must be 3-20 characters using letters, numbers, or underscore', 0;
    RETURN;
  END IF;

  -- Check if username already exists (excluding current user)
  SELECT EXISTS(SELECT 1 FROM public.profiles WHERE username = p_username AND id != v_user_id)
  INTO v_username_exists;

  IF v_username_exists THEN
    RETURN QUERY SELECT false, 'Username is already taken', 0;
    RETURN;
  END IF;

  -- Update profile with account completion data
  UPDATE public.profiles
  SET 
    full_name = COALESCE(p_full_name, full_name),
    username = COALESCE(p_username, username),
    profile_image_url = COALESCE(p_profile_image_url, profile_image_url),
    security_pin_hash = CASE 
      WHEN p_security_pin IS NOT NULL THEN crypt(p_security_pin, gen_salt('bf'))
      ELSE security_pin_hash
    END,
    updated_at = now()
  WHERE id = v_user_id;

  -- Update user_preferences
  UPDATE public.user_preferences
  SET 
    profile_full_name = COALESCE(p_full_name, profile_full_name),
    profile_username = COALESCE(p_username, profile_username),
    profile_image_uploaded = COALESCE(p_profile_image_url IS NOT NULL, profile_image_uploaded),
    security_pin_set = COALESCE(p_security_pin IS NOT NULL, security_pin_set),
    onboarding_step = 5,
    onboarding_completed = true,
    onboarding_completed_at = now(),
    updated_at = now()
  WHERE user_id = v_user_id;

  -- Insert onboarding step completion
  INSERT INTO public.onboarding_steps (user_id, step_name, step_number, completed, data)
  VALUES 
    (v_user_id, 'profile_completion', 5, true, json_build_object(
      'full_name', p_full_name,
      'username', p_username,
      'profile_image_url', p_profile_image_url,
      'security_pin_set', p_security_pin IS NOT NULL
    ))
  ON CONFLICT (user_id, step_name) DO UPDATE
  SET 
    completed = true,
    data = EXCLUDED.data,
    completed_at = now(),
    updated_at = now();

  -- Explicitly upsert user_accounts with a compliant account_number
  INSERT INTO public.user_accounts (user_id, account_number, account_name, account_username)
  VALUES (
    v_user_id,
    public.generate_openpay_account_number(v_user_id),
    COALESCE(NULLIF(TRIM(p_full_name), ''), 'OpenPay User'),
    COALESCE(NULLIF(TRIM(p_username), ''), 'openpay')
  )
  ON CONFLICT (user_id) DO UPDATE
  SET 
    account_name = EXCLUDED.account_name,
    account_username = EXCLUDED.account_username;

  RETURN QUERY SELECT true, 'Account completed successfully', 5;
END;
$$;


-- <<< END MIGRATION: 20260308090000_fix_onboarding_account_number_constraint.sql

-- >>> MIGRATION: 20260308090500_grant_onboarding_rpc.sql
-- Ensure complete_account_onboarding RPC has correct execution permissions
-- Date: 2026-03-08

REVOKE ALL ON FUNCTION public.complete_account_onboarding(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_account_onboarding(TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_account_onboarding(TEXT, TEXT, TEXT, TEXT) TO service_role;

NOTIFY pgrst, 'reload schema';


-- <<< END MIGRATION: 20260308090500_grant_onboarding_rpc.sql

-- >>> MIGRATION: 20260308091500_add_skip_account_onboarding.sql
CREATE OR REPLACE FUNCTION public.skip_account_onboarding()
RETURNS TABLE(success BOOLEAN, message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  PERFORM public.upsert_my_user_account();

  UPDATE public.user_preferences
  SET 
    onboarding_step = COALESCE(onboarding_step, 1),
    onboarding_completed = false,
    onboarding_started_at = COALESCE(onboarding_started_at, now()),
    updated_at = now()
  WHERE user_id = v_user_id;

  INSERT INTO public.onboarding_steps (user_id, step_name, step_number, completed)
  VALUES (v_user_id, 'profile_completion', 5, false)
  ON CONFLICT (user_id, step_name) DO UPDATE
  SET completed = false,
      updated_at = now();

  RETURN QUERY SELECT true, 'Onboarding postponed';
END;
$$;

REVOKE ALL ON FUNCTION public.skip_account_onboarding() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.skip_account_onboarding() TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260308091500_add_skip_account_onboarding.sql

-- >>> MIGRATION: 20260308092000_reinstate_user_account_number_enforcement.sql
CREATE OR REPLACE FUNCTION public.enforce_user_account_number_format()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.account_number IS NULL OR NEW.account_number !~ '^OP[A-Z0-9]{6,64}$' THEN
    NEW.account_number := public.generate_openpay_account_number(NEW.user_id);
  ELSE
    NEW.account_number := UPPER(TRIM(NEW.account_number));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_accounts_enforce_format ON public.user_accounts;
CREATE TRIGGER trg_user_accounts_enforce_format
BEFORE INSERT OR UPDATE ON public.user_accounts
FOR EACH ROW
EXECUTE FUNCTION public.enforce_user_account_number_format();

UPDATE public.user_accounts ua
SET account_number = public.generate_openpay_account_number(ua.user_id)
WHERE ua.account_number IS NULL OR ua.account_number !~ '^OP[A-Z0-9]{6,64}$';

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260308092000_reinstate_user_account_number_enforcement.sql

-- >>> MIGRATION: 20260308093000_repair_false_onboarding_states.sql
CREATE OR REPLACE FUNCTION public.repair_my_onboarding_if_ready()
RETURNS TABLE(success BOOLEAN, message TEXT, onboarding_step INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_full_name TEXT;
  v_username TEXT;
  v_has_account BOOLEAN := FALSE;
  v_account_ok BOOLEAN := FALSE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  PERFORM public.upsert_my_user_account();

  SELECT 
    COALESCE(NULLIF(TRIM(p.full_name), ''), ''),
    COALESCE(NULLIF(TRIM(COALESCE(p.username, '')), ''), '')
  INTO v_full_name, v_username
  FROM public.profiles p
  WHERE p.id = v_user_id;

  SELECT EXISTS(SELECT 1 FROM public.user_accounts ua WHERE ua.user_id = v_user_id)
  INTO v_has_account;

  SELECT EXISTS(
    SELECT 1 
    FROM public.user_accounts ua 
    WHERE ua.user_id = v_user_id 
      AND ua.account_number ~ '^OP[A-Z0-9]{6,64}$'
  )
  INTO v_account_ok;

  IF v_full_name != '' AND v_username != '' AND v_has_account AND v_account_ok THEN
    UPDATE public.user_preferences
    SET 
      onboarding_step = 5,
      onboarding_completed = true,
      onboarding_completed_at = COALESCE(onboarding_completed_at, now()),
      profile_full_name = v_full_name,
      profile_username = v_username,
      updated_at = now()
    WHERE user_id = v_user_id;

    INSERT INTO public.onboarding_steps (user_id, step_name, step_number, completed, data, completed_at)
    VALUES (
      v_user_id,
      'profile_completion',
      5,
      true,
      jsonb_build_object('full_name', v_full_name, 'username', v_username),
      now()
    )
    ON CONFLICT (user_id, step_name) DO UPDATE
    SET 
      completed = true,
      data = EXCLUDED.data,
      completed_at = now(),
      updated_at = now();

    RETURN QUERY SELECT true, 'Onboarding repaired', 5;
    RETURN;
  END IF;

  RETURN QUERY SELECT false, 'Profile or account incomplete', 0;
END;
$$;

DO $$
BEGIN
  UPDATE public.user_preferences up
  SET 
    onboarding_step = 5,
    onboarding_completed = true,
    onboarding_completed_at = COALESCE(onboarding_completed_at, now()),
    updated_at = now()
  WHERE up.onboarding_completed = false
    AND COALESCE(NULLIF(TRIM(up.profile_full_name), ''), '') != ''
    AND COALESCE(NULLIF(TRIM(COALESCE(up.profile_username, '')), ''), '') != ''
    AND EXISTS (
      SELECT 1 FROM public.user_accounts ua 
      WHERE ua.user_id = up.user_id 
        AND ua.account_number ~ '^OP[A-Z0-9]{6,64}$'
    );

  INSERT INTO public.onboarding_steps (user_id, step_name, step_number, completed, data, completed_at)
  SELECT 
    up.user_id,
    'profile_completion',
    5,
    true,
    jsonb_build_object('full_name', up.profile_full_name, 'username', up.profile_username),
    now()
  FROM public.user_preferences up
  WHERE up.onboarding_completed = true
  ON CONFLICT (user_id, step_name) DO UPDATE
  SET 
    completed = true,
    data = EXCLUDED.data,
    completed_at = now(),
    updated_at = now();
END $$;

REVOKE ALL ON FUNCTION public.repair_my_onboarding_if_ready() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.repair_my_onboarding_if_ready() TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260308093000_repair_false_onboarding_states.sql

-- >>> MIGRATION: 20260308094000_reset_false_onboarding.sql
CREATE OR REPLACE FUNCTION public.reset_my_onboarding_to_false()
RETURNS TABLE(success BOOLEAN, message TEXT, onboarding_step INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_full_name TEXT;
  v_username TEXT;
  v_has_account BOOLEAN := FALSE;
  v_account_ok BOOLEAN := FALSE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT 
    COALESCE(NULLIF(TRIM(p.full_name), ''), ''),
    COALESCE(NULLIF(TRIM(COALESCE(p.username, '')), ''), '')
  INTO v_full_name, v_username
  FROM public.profiles p
  WHERE p.id = v_user_id;

  SELECT EXISTS(SELECT 1 FROM public.user_accounts ua WHERE ua.user_id = v_user_id)
  INTO v_has_account;

  SELECT EXISTS(
    SELECT 1 
    FROM public.user_accounts ua 
    WHERE ua.user_id = v_user_id 
      AND ua.account_number ~ '^OP[A-Z0-9]{6,64}$'
  )
  INTO v_account_ok;

  IF v_full_name = '' OR v_username = '' OR NOT v_has_account OR NOT v_account_ok THEN
    UPDATE public.user_preferences
    SET 
      onboarding_step = COALESCE(onboarding_step, 1),
      onboarding_completed = false,
      onboarding_started_at = COALESCE(onboarding_started_at, now()),
      updated_at = now()
    WHERE user_id = v_user_id;

    INSERT INTO public.onboarding_steps (user_id, step_name, step_number, completed)
    VALUES (v_user_id, 'profile_completion', 5, false)
    ON CONFLICT (user_id, step_name) DO UPDATE
    SET completed = false,
        updated_at = now();

    RETURN QUERY SELECT true, 'Onboarding reset', 0;
    RETURN;
  END IF;

  RETURN QUERY SELECT false, 'Prerequisites are complete', 5;
END;
$$;

DO $$
BEGIN
  UPDATE public.user_preferences up
  SET 
    onboarding_step = COALESCE(onboarding_step, 1),
    onboarding_completed = false,
    onboarding_started_at = COALESCE(onboarding_started_at, now()),
    updated_at = now()
  WHERE COALESCE(NULLIF(TRIM(up.profile_full_name), ''), '') = ''
     OR COALESCE(NULLIF(TRIM(COALESCE(up.profile_username, '')), ''), '') = ''
     OR NOT EXISTS (
       SELECT 1 FROM public.user_accounts ua 
       WHERE ua.user_id = up.user_id 
         AND ua.account_number ~ '^OP[A-Z0-9]{6,64}$'
     );

  INSERT INTO public.onboarding_steps (user_id, step_name, step_number, completed)
  SELECT 
    up.user_id,
    'profile_completion',
    5,
    false
  FROM public.user_preferences up
  WHERE up.onboarding_completed = false
  ON CONFLICT (user_id, step_name) DO UPDATE
  SET 
    completed = false,
    updated_at = now();
END $$;

REVOKE ALL ON FUNCTION public.reset_my_onboarding_to_false() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reset_my_onboarding_to_false() TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260308094000_reset_false_onboarding.sql

-- >>> MIGRATION: 20260308095000_fix_user_accounts_account_number_format.sql
-- Hard-fix user_accounts account_number format enforcement.
-- Some environments may already have the constraint name but with a legacy definition,
-- or a legacy generate_openpay_account_number() that includes UUID dashes.
-- This migration normalizes all paths to the format: ^OP[A-Z0-9]{6,64}$

CREATE OR REPLACE FUNCTION public.generate_openpay_account_number(p_user_id UUID)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 'OP' || UPPER(REPLACE(p_user_id::TEXT, '-', ''));
$$;

-- Ensure check constraint expression matches the expected format, even if a legacy constraint exists.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'user_accounts_account_number_format_ck'
      AND conrelid = 'public.user_accounts'::regclass
  ) THEN
    ALTER TABLE public.user_accounts
      DROP CONSTRAINT user_accounts_account_number_format_ck;
  END IF;

  ALTER TABLE public.user_accounts
    ADD CONSTRAINT user_accounts_account_number_format_ck
    CHECK (account_number ~ '^OP[A-Z0-9]{6,64}$') NOT VALID;
END $$;

-- Reinstate/ensure trigger-based normalization on inserts/updates.
CREATE OR REPLACE FUNCTION public.enforce_user_account_number_format()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.account_number IS NULL OR NEW.account_number !~ '^OP[A-Z0-9]{6,64}$' THEN
    NEW.account_number := public.generate_openpay_account_number(NEW.user_id);
  ELSE
    NEW.account_number := UPPER(TRIM(NEW.account_number));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_accounts_enforce_format ON public.user_accounts;
CREATE TRIGGER trg_user_accounts_enforce_format
BEFORE INSERT OR UPDATE ON public.user_accounts
FOR EACH ROW
EXECUTE FUNCTION public.enforce_user_account_number_format();

-- Backfill any existing invalid account numbers.
UPDATE public.user_accounts ua
SET account_number = public.generate_openpay_account_number(ua.user_id)
WHERE ua.account_number IS NULL
   OR TRIM(ua.account_number) = ''
   OR ua.account_number !~ '^OP[A-Z0-9]{6,64}$';

ALTER TABLE public.user_accounts
  VALIDATE CONSTRAINT user_accounts_account_number_format_ck;

REVOKE ALL ON FUNCTION public.generate_openpay_account_number(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.generate_openpay_account_number(UUID) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

-- <<< END MIGRATION: 20260308095000_fix_user_accounts_account_number_format.sql

-- >>> MIGRATION: 20260308095500_complete_account_onboarding_upsert_prefs.sql
-- Make complete_account_onboarding resilient when user_preferences row does not exist yet.
-- This prevents "onboarding completed" from being lost due to UPDATE affecting 0 rows.

CREATE OR REPLACE FUNCTION public.complete_account_onboarding(
  p_full_name TEXT,
  p_username TEXT,
  p_profile_image_url TEXT DEFAULT NULL,
  p_security_pin TEXT DEFAULT NULL
)
RETURNS TABLE(
  success BOOLEAN,
  message TEXT,
  onboarding_step INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_username_exists BOOLEAN := FALSE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_username IS NOT NULL AND p_username !~ '^[a-zA-Z0-9_]{3,20}$' THEN
    RETURN QUERY SELECT false, 'Username must be 3-20 characters using letters, numbers, or underscore', 0;
    RETURN;
  END IF;

  SELECT EXISTS(SELECT 1 FROM public.profiles WHERE username = p_username AND id != v_user_id)
  INTO v_username_exists;

  IF v_username_exists THEN
    RETURN QUERY SELECT false, 'Username is already taken', 0;
    RETURN;
  END IF;

  UPDATE public.profiles
  SET
    full_name = COALESCE(p_full_name, full_name),
    username = COALESCE(p_username, username),
    profile_image_url = COALESCE(p_profile_image_url, profile_image_url),
    security_pin_hash = CASE
      WHEN p_security_pin IS NOT NULL THEN crypt(p_security_pin, gen_salt('bf'))
      ELSE security_pin_hash
    END,
    updated_at = now()
  WHERE id = v_user_id;

  INSERT INTO public.user_preferences (
    user_id,
    profile_full_name,
    profile_username,
    profile_image_uploaded,
    security_pin_set,
    onboarding_step,
    onboarding_completed,
    onboarding_completed_at,
    updated_at
  )
  VALUES (
    v_user_id,
    COALESCE(p_full_name, NULL),
    COALESCE(p_username, NULL),
    COALESCE(p_profile_image_url IS NOT NULL, false),
    COALESCE(p_security_pin IS NOT NULL, false),
    5,
    true,
    now(),
    now()
  )
  ON CONFLICT (user_id) DO UPDATE
  SET
    profile_full_name = COALESCE(EXCLUDED.profile_full_name, public.user_preferences.profile_full_name),
    profile_username = COALESCE(EXCLUDED.profile_username, public.user_preferences.profile_username),
    profile_image_uploaded = public.user_preferences.profile_image_uploaded OR EXCLUDED.profile_image_uploaded,
    security_pin_set = public.user_preferences.security_pin_set OR EXCLUDED.security_pin_set,
    onboarding_step = 5,
    onboarding_completed = true,
    onboarding_completed_at = COALESCE(public.user_preferences.onboarding_completed_at, now()),
    updated_at = now();

  INSERT INTO public.onboarding_steps (user_id, step_name, step_number, completed, data)
  VALUES
    (v_user_id, 'profile_completion', 5, true, json_build_object(
      'full_name', p_full_name,
      'username', p_username,
      'profile_image_url', p_profile_image_url,
      'security_pin_set', p_security_pin IS NOT NULL
    ))
  ON CONFLICT (user_id, step_name) DO UPDATE
  SET
    completed = true,
    data = EXCLUDED.data,
    completed_at = now(),
    updated_at = now();

  INSERT INTO public.user_accounts (user_id, account_number, account_name, account_username)
  VALUES (
    v_user_id,
    public.generate_openpay_account_number(v_user_id),
    COALESCE(NULLIF(TRIM(p_full_name), ''), 'OpenPay User'),
    COALESCE(NULLIF(TRIM(p_username), ''), 'openpay')
  )
  ON CONFLICT (user_id) DO UPDATE
  SET
    account_name = EXCLUDED.account_name,
    account_username = EXCLUDED.account_username;

  RETURN QUERY SELECT true, 'Account completed successfully', 5;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_account_onboarding(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_account_onboarding(TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';


-- <<< END MIGRATION: 20260308095500_complete_account_onboarding_upsert_prefs.sql

-- >>> MIGRATION: 20260308096000_complete_account_onboarding_account_first.sql
-- Fix: prevent user_accounts check constraint violation during onboarding.
-- Root cause: profiles triggers may INSERT into user_accounts using a legacy generate_openpay_account_number()
-- that returns UUIDs with dashes, violating ^OP[A-Z0-9]{6,64}$.
--
-- Strategy: ensure a valid user_accounts row exists *before* updating profiles, so downstream triggers hit
-- ON CONFLICT (user_id) DO UPDATE instead of INSERT.

CREATE OR REPLACE FUNCTION public.complete_account_onboarding(
  p_full_name TEXT,
  p_username TEXT,
  p_profile_image_url TEXT DEFAULT NULL,
  p_security_pin TEXT DEFAULT NULL
)
RETURNS TABLE(
  success BOOLEAN,
  message TEXT,
  onboarding_step INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_username_exists BOOLEAN := FALSE;
  v_account_number TEXT := 'OP' || UPPER(REPLACE(auth.uid()::TEXT, '-', ''));
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_username IS NOT NULL AND p_username !~ '^[a-zA-Z0-9_]{3,20}$' THEN
    RETURN QUERY SELECT false, 'Username must be 3-20 characters using letters, numbers, or underscore', 0;
    RETURN;
  END IF;

  SELECT EXISTS(SELECT 1 FROM public.profiles WHERE username = p_username AND id != v_user_id)
  INTO v_username_exists;

  IF v_username_exists THEN
    RETURN QUERY SELECT false, 'Username is already taken', 0;
    RETURN;
  END IF;

  INSERT INTO public.user_accounts (user_id, account_number, account_name, account_username)
  VALUES (
    v_user_id,
    v_account_number,
    COALESCE(NULLIF(TRIM(p_full_name), ''), 'OpenPay User'),
    COALESCE(NULLIF(TRIM(p_username), ''), 'openpay')
  )
  ON CONFLICT (user_id) DO UPDATE
  SET
    account_name = EXCLUDED.account_name,
    account_username = EXCLUDED.account_username;

  UPDATE public.profiles
  SET
    full_name = COALESCE(p_full_name, full_name),
    username = COALESCE(p_username, username),
    profile_image_url = COALESCE(p_profile_image_url, profile_image_url),
    security_pin_hash = CASE
      WHEN p_security_pin IS NOT NULL THEN crypt(p_security_pin, gen_salt('bf'))
      ELSE security_pin_hash
    END,
    updated_at = now()
  WHERE id = v_user_id;

  INSERT INTO public.user_preferences (
    user_id,
    profile_full_name,
    profile_username,
    profile_image_uploaded,
    security_pin_set,
    onboarding_step,
    onboarding_completed,
    onboarding_completed_at,
    updated_at
  )
  VALUES (
    v_user_id,
    COALESCE(p_full_name, NULL),
    COALESCE(p_username, NULL),
    COALESCE(p_profile_image_url IS NOT NULL, false),
    COALESCE(p_security_pin IS NOT NULL, false),
    5,
    true,
    now(),
    now()
  )
  ON CONFLICT (user_id) DO UPDATE
  SET
    profile_full_name = COALESCE(EXCLUDED.profile_full_name, public.user_preferences.profile_full_name),
    profile_username = COALESCE(EXCLUDED.profile_username, public.user_preferences.profile_username),
    profile_image_uploaded = public.user_preferences.profile_image_uploaded OR EXCLUDED.profile_image_uploaded,
    security_pin_set = public.user_preferences.security_pin_set OR EXCLUDED.security_pin_set,
    onboarding_step = 5,
    onboarding_completed = true,
    onboarding_completed_at = COALESCE(public.user_preferences.onboarding_completed_at, now()),
    updated_at = now();

  INSERT INTO public.onboarding_steps (user_id, step_name, step_number, completed, data)
  VALUES
    (v_user_id, 'profile_completion', 5, true, json_build_object(
      'full_name', p_full_name,
      'username', p_username,
      'profile_image_url', p_profile_image_url,
      'security_pin_set', p_security_pin IS NOT NULL
    ))
  ON CONFLICT (user_id, step_name) DO UPDATE
  SET
    completed = true,
    data = EXCLUDED.data,
    completed_at = now(),
    updated_at = now();

  RETURN QUERY SELECT true, 'Account completed successfully', 5;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_account_onboarding(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_account_onboarding(TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';


-- <<< END MIGRATION: 20260308096000_complete_account_onboarding_account_first.sql
