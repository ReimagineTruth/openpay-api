-- ============================================================
-- OpenPay Complete SQL Database Reference
-- Generated: 2026-03-05
-- This file documents ALL tables, functions, triggers, policies
-- ============================================================

-- ===================== TABLES =====================

-- 1. profiles - User profiles (linked to auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT NOT NULL DEFAULT '',
  username TEXT UNIQUE,
  avatar_url TEXT,
  referral_code TEXT NOT NULL UNIQUE,
  referred_by_user_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. wallets - User wallet balances
CREATE TABLE IF NOT EXISTS public.wallets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  balance NUMERIC NOT NULL DEFAULT 0,
  welcome_bonus_claimed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. user_accounts - OpenPay account numbers
CREATE TABLE IF NOT EXISTS public.user_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  account_number TEXT NOT NULL UNIQUE,
  account_username TEXT NOT NULL DEFAULT '',
  account_name TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. transactions - All money transfers
CREATE TABLE IF NOT EXISTS public.transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id UUID NOT NULL REFERENCES auth.users(id),
  receiver_id UUID NOT NULL REFERENCES auth.users(id),
  amount NUMERIC NOT NULL,
  note TEXT,
  status TEXT NOT NULL DEFAULT 'completed',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5. user_preferences - App settings per user
CREATE TABLE IF NOT EXISTS public.user_preferences (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  hide_balance BOOLEAN NOT NULL DEFAULT false,
  usage_agreement_accepted BOOLEAN NOT NULL DEFAULT false,
  onboarding_completed BOOLEAN NOT NULL DEFAULT false,
  onboarding_step INTEGER NOT NULL DEFAULT 0,
  reference_code TEXT,
  profile_full_name TEXT,
  profile_username TEXT,
  security_settings JSONB NOT NULL DEFAULT '{}',
  merchant_onboarding_data JSONB NOT NULL DEFAULT '{}',
  qr_print_settings JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 6. contacts
CREATE TABLE IF NOT EXISTS public.contacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  contact_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, contact_id)
);

-- 7. payment_requests
CREATE TABLE IF NOT EXISTS public.payment_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id UUID NOT NULL REFERENCES auth.users(id),
  payer_id UUID NOT NULL REFERENCES auth.users(id),
  amount NUMERIC NOT NULL,
  note TEXT DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 8. invoices
CREATE TABLE IF NOT EXISTS public.invoices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id UUID NOT NULL REFERENCES auth.users(id),
  recipient_id UUID NOT NULL REFERENCES auth.users(id),
  amount NUMERIC NOT NULL,
  description TEXT DEFAULT '',
  due_date DATE,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 9. disputes
CREATE TABLE IF NOT EXISTS public.disputes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  transaction_id UUID NOT NULL REFERENCES public.transactions(id),
  reason TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'open',
  admin_response TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 10. virtual_cards
CREATE TABLE IF NOT EXISTS public.virtual_cards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  card_number TEXT NOT NULL,
  cardholder_name TEXT NOT NULL DEFAULT '',
  card_username TEXT NOT NULL DEFAULT '',
  expiry_month INTEGER NOT NULL,
  expiry_year INTEGER NOT NULL,
  cvc TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  is_locked BOOLEAN NOT NULL DEFAULT false,
  locked_at TIMESTAMPTZ,
  hide_details BOOLEAN NOT NULL DEFAULT false,
  card_settings JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 11. ledger_events - Immutable audit trail
CREATE TABLE IF NOT EXISTS public.ledger_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_table TEXT NOT NULL,
  source_id UUID NOT NULL,
  event_type TEXT NOT NULL,
  actor_user_id UUID,
  related_user_id UUID,
  amount NUMERIC,
  note TEXT DEFAULT '',
  status TEXT,
  payload JSONB NOT NULL DEFAULT '{}',
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 12. mining_sessions
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

-- 13. mining_rewards
CREATE TABLE IF NOT EXISTS public.mining_rewards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id UUID REFERENCES public.mining_sessions(id) ON DELETE SET NULL,
  amount NUMERIC NOT NULL,
  reward_type TEXT NOT NULL CHECK (reward_type IN ('base', 'referral_bonus')),
  referral_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 14. referral_rewards
CREATE TABLE IF NOT EXISTS public.referral_rewards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_user_id UUID NOT NULL REFERENCES auth.users(id),
  referred_user_id UUID NOT NULL REFERENCES auth.users(id),
  reward_amount NUMERIC NOT NULL DEFAULT 1.00,
  status TEXT NOT NULL DEFAULT 'pending',
  claimed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(referrer_user_id, referred_user_id)
);

-- 15. app_notifications
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

-- 16. notification_preferences
CREATE TABLE IF NOT EXISTS public.notification_preferences (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  push_enabled BOOLEAN NOT NULL DEFAULT true,
  email_enabled BOOLEAN NOT NULL DEFAULT false,
  in_app_enabled BOOLEAN NOT NULL DEFAULT true,
  quiet_hours_start TIME,
  quiet_hours_end TIME,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 17. pi_payment_credits
CREATE TABLE IF NOT EXISTS public.pi_payment_credits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  payment_id TEXT NOT NULL UNIQUE,
  amount NUMERIC NOT NULL,
  txid TEXT,
  status TEXT NOT NULL DEFAULT 'completed',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 18. supported_currencies
CREATE TABLE IF NOT EXISTS public.supported_currencies (
  iso_code TEXT PRIMARY KEY,
  display_code TEXT NOT NULL,
  display_name TEXT NOT NULL,
  symbol TEXT NOT NULL,
  flag TEXT NOT NULL,
  usd_rate NUMERIC NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 19. email_notifications_outbox
CREATE TABLE IF NOT EXISTS public.email_notifications_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  transaction_id UUID REFERENCES public.transactions(id),
  to_email TEXT NOT NULL,
  subject TEXT NOT NULL,
  body TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'pending',
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 20. admin_self_send_reviews
CREATE TABLE IF NOT EXISTS public.admin_self_send_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_id UUID NOT NULL UNIQUE REFERENCES public.transactions(id),
  decision TEXT NOT NULL,
  reason TEXT NOT NULL DEFAULT '',
  reviewed_by_email TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 21. openpay_authorization_codes
CREATE TABLE IF NOT EXISTS public.openpay_authorization_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  authorization_code TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 22. openpay_runtime_settings
CREATE TABLE IF NOT EXISTS public.openpay_runtime_settings (
  setting_key TEXT PRIMARY KEY,
  value_json JSONB NOT NULL DEFAULT '{}',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 23. support_tickets
CREATE TABLE IF NOT EXISTS public.support_tickets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  subject TEXT NOT NULL,
  message TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 24. support_agents
CREATE TABLE IF NOT EXISTS public.support_agents (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id),
  handle TEXT NOT NULL DEFAULT 'openpay',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 25. support_conversations
CREATE TABLE IF NOT EXISTS public.support_conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  status TEXT NOT NULL DEFAULT 'open',
  last_message_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 26. support_messages
CREATE TABLE IF NOT EXISTS public.support_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.support_conversations(id),
  sender_id UUID NOT NULL REFERENCES auth.users(id),
  sender_role TEXT NOT NULL DEFAULT 'user',
  message TEXT NOT NULL,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 27. support_faq_categories
CREATE TABLE IF NOT EXISTS public.support_faq_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 28. support_faq_items
CREATE TABLE IF NOT EXISTS public.support_faq_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id UUID REFERENCES public.support_faq_categories(id),
  question TEXT NOT NULL,
  answer TEXT NOT NULL,
  tags TEXT[] NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 29. open_partner_leads
CREATE TABLE IF NOT EXISTS public.open_partner_leads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_user_id UUID NOT NULL REFERENCES auth.users(id),
  company_name TEXT NOT NULL,
  contact_name TEXT NOT NULL,
  contact_email TEXT NOT NULL,
  website_url TEXT,
  business_type TEXT,
  integration_type TEXT,
  estimated_monthly_volume TEXT,
  use_case_summary TEXT NOT NULL DEFAULT '',
  message TEXT,
  country TEXT,
  status TEXT NOT NULL DEFAULT 'new',
  admin_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ===================== MERCHANT TABLES =====================

-- 30. merchant_profiles
CREATE TABLE IF NOT EXISTS public.merchant_profiles (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id),
  merchant_name TEXT NOT NULL DEFAULT 'OpenPay Merchant',
  merchant_username TEXT NOT NULL DEFAULT '',
  merchant_logo_url TEXT,
  default_currency TEXT NOT NULL DEFAULT 'USD',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 31. merchant_api_keys
CREATE TABLE IF NOT EXISTS public.merchant_api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_user_id UUID NOT NULL REFERENCES auth.users(id),
  key_name TEXT NOT NULL DEFAULT 'Default key',
  key_mode TEXT NOT NULL,
  publishable_key TEXT NOT NULL,
  secret_key_hash TEXT NOT NULL,
  secret_key_last4 TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  last_used_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 32. merchant_products
CREATE TABLE IF NOT EXISTS public.merchant_products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_user_id UUID NOT NULL REFERENCES auth.users(id),
  product_name TEXT NOT NULL,
  product_code TEXT NOT NULL,
  product_description TEXT NOT NULL DEFAULT '',
  unit_amount NUMERIC NOT NULL,
  currency TEXT NOT NULL DEFAULT 'USD',
  pricing_type TEXT NOT NULL DEFAULT 'one_time',
  image_url TEXT,
  media_urls TEXT[] NOT NULL DEFAULT '{}',
  product_tags TEXT[] NOT NULL DEFAULT '{}',
  checkout_info TEXT NOT NULL DEFAULT '',
  tax_code TEXT,
  repeat_every INTEGER,
  repeat_unit TEXT,
  metadata JSONB NOT NULL DEFAULT '{}',
  is_active BOOLEAN NOT NULL DEFAULT true,
  published_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 33. merchant_checkout_sessions
CREATE TABLE IF NOT EXISTS public.merchant_checkout_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_user_id UUID NOT NULL REFERENCES auth.users(id),
  api_key_id UUID REFERENCES public.merchant_api_keys(id),
  session_token TEXT NOT NULL UNIQUE,
  currency TEXT NOT NULL,
  key_mode TEXT NOT NULL,
  subtotal_amount NUMERIC NOT NULL DEFAULT 0,
  fee_amount NUMERIC NOT NULL DEFAULT 0,
  total_amount NUMERIC NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'open',
  customer_name TEXT,
  customer_email TEXT,
  success_url TEXT,
  cancel_url TEXT,
  metadata JSONB NOT NULL DEFAULT '{}',
  paid_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 34. merchant_checkout_session_items
CREATE TABLE IF NOT EXISTS public.merchant_checkout_session_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.merchant_checkout_sessions(id) ON DELETE CASCADE,
  product_id UUID REFERENCES public.merchant_products(id),
  item_name TEXT NOT NULL,
  unit_amount NUMERIC NOT NULL,
  quantity INTEGER NOT NULL,
  line_total NUMERIC NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 35. merchant_payment_links
CREATE TABLE IF NOT EXISTS public.merchant_payment_links (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_user_id UUID NOT NULL REFERENCES auth.users(id),
  api_key_id UUID REFERENCES public.merchant_api_keys(id),
  link_token TEXT NOT NULL UNIQUE,
  link_type TEXT NOT NULL,
  key_mode TEXT NOT NULL,
  title TEXT NOT NULL DEFAULT 'OpenPay Payment',
  description TEXT NOT NULL DEFAULT '',
  currency TEXT NOT NULL DEFAULT 'USD',
  custom_amount NUMERIC,
  call_to_action TEXT NOT NULL DEFAULT 'Pay',
  collect_customer_name BOOLEAN NOT NULL DEFAULT true,
  collect_customer_email BOOLEAN NOT NULL DEFAULT true,
  collect_phone BOOLEAN NOT NULL DEFAULT false,
  collect_address BOOLEAN NOT NULL DEFAULT false,
  after_payment_type TEXT NOT NULL DEFAULT 'confirmation',
  confirmation_message TEXT NOT NULL DEFAULT 'Thanks for your payment.',
  redirect_url TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 36. merchant_payment_link_items
CREATE TABLE IF NOT EXISTS public.merchant_payment_link_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  link_id UUID NOT NULL REFERENCES public.merchant_payment_links(id) ON DELETE CASCADE,
  product_id UUID REFERENCES public.merchant_products(id),
  item_name TEXT NOT NULL,
  unit_amount NUMERIC NOT NULL,
  quantity INTEGER NOT NULL,
  line_total NUMERIC NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 37. merchant_payment_link_share_settings
CREATE TABLE IF NOT EXISTS public.merchant_payment_link_share_settings (
  link_id UUID PRIMARY KEY REFERENCES public.merchant_payment_links(id) ON DELETE CASCADE,
  merchant_user_id UUID NOT NULL REFERENCES auth.users(id),
  qr_size INTEGER NOT NULL DEFAULT 240,
  qr_logo_enabled BOOLEAN NOT NULL DEFAULT true,
  qr_logo_url TEXT NOT NULL DEFAULT '/openpay-o.svg',
  widget_theme TEXT NOT NULL DEFAULT 'light',
  button_label TEXT NOT NULL DEFAULT 'Pay with OpenPay',
  button_size TEXT NOT NULL DEFAULT 'medium',
  button_style TEXT NOT NULL DEFAULT 'default',
  iframe_height INTEGER NOT NULL DEFAULT 720,
  direct_open_new_tab BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 38. merchant_payments
CREATE TABLE IF NOT EXISTS public.merchant_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL UNIQUE REFERENCES public.merchant_checkout_sessions(id),
  merchant_user_id UUID NOT NULL REFERENCES auth.users(id),
  buyer_user_id UUID NOT NULL REFERENCES auth.users(id),
  transaction_id UUID NOT NULL UNIQUE REFERENCES public.transactions(id),
  amount NUMERIC NOT NULL,
  currency TEXT NOT NULL,
  key_mode TEXT NOT NULL,
  api_key_id UUID REFERENCES public.merchant_api_keys(id),
  payment_link_id UUID REFERENCES public.merchant_payment_links(id),
  payment_link_token TEXT,
  status TEXT NOT NULL DEFAULT 'succeeded',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 39. merchant_balance_transfers
CREATE TABLE IF NOT EXISTS public.merchant_balance_transfers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_user_id UUID NOT NULL REFERENCES auth.users(id),
  amount NUMERIC NOT NULL,
  destination TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  currency TEXT NOT NULL DEFAULT 'USD',
  key_mode TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 40. merchant_pos_api_settings
CREATE TABLE IF NOT EXISTS public.merchant_pos_api_settings (
  merchant_user_id UUID PRIMARY KEY REFERENCES auth.users(id),
  sandbox_api_key_id UUID REFERENCES public.merchant_api_keys(id),
  live_api_key_id UUID REFERENCES public.merchant_api_keys(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ===================== LOANS & SAVINGS =====================

-- 41. user_loans
CREATE TABLE IF NOT EXISTS public.user_loans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  principal_amount NUMERIC NOT NULL,
  outstanding_amount NUMERIC NOT NULL,
  monthly_payment_amount NUMERIC NOT NULL,
  monthly_fee_rate NUMERIC NOT NULL DEFAULT 0,
  term_months INTEGER NOT NULL,
  paid_months INTEGER NOT NULL DEFAULT 0,
  next_due_date DATE NOT NULL,
  credit_score INTEGER NOT NULL DEFAULT 300,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 42. user_loan_applications
CREATE TABLE IF NOT EXISTS public.user_loan_applications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  full_name TEXT NOT NULL DEFAULT '',
  contact_number TEXT NOT NULL DEFAULT '',
  address_line TEXT NOT NULL DEFAULT '',
  city TEXT NOT NULL DEFAULT '',
  country TEXT NOT NULL DEFAULT '',
  openpay_account_number TEXT NOT NULL DEFAULT '',
  openpay_account_username TEXT NOT NULL DEFAULT '',
  requested_amount NUMERIC NOT NULL,
  requested_term_months INTEGER NOT NULL,
  credit_score_snapshot INTEGER NOT NULL DEFAULT 300,
  agreement_accepted BOOLEAN NOT NULL DEFAULT false,
  agreement_accepted_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending',
  admin_note TEXT NOT NULL DEFAULT '',
  reviewed_by TEXT,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 43. user_loan_payments
CREATE TABLE IF NOT EXISTS public.user_loan_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  loan_id UUID NOT NULL REFERENCES public.user_loans(id),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  amount NUMERIC NOT NULL,
  principal_component NUMERIC NOT NULL,
  fee_component NUMERIC NOT NULL,
  payment_method TEXT NOT NULL DEFAULT 'wallet',
  payment_reference TEXT,
  note TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 44. user_savings_accounts
CREATE TABLE IF NOT EXISTS public.user_savings_accounts (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id),
  balance NUMERIC NOT NULL DEFAULT 0,
  apy NUMERIC NOT NULL DEFAULT 5.0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 45. user_savings_transfers
CREATE TABLE IF NOT EXISTS public.user_savings_transfers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  amount NUMERIC NOT NULL,
  direction TEXT NOT NULL,
  fee_amount NUMERIC NOT NULL DEFAULT 0,
  note TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ===================== REMITTANCE =====================

-- 46. remittance_merchants
CREATE TABLE IF NOT EXISTS public.remittance_merchants (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id),
  merchant_name TEXT NOT NULL DEFAULT 'OpenPay Remittance Center',
  merchant_username TEXT NOT NULL DEFAULT '',
  merchant_logo_url TEXT NOT NULL DEFAULT '',
  merchant_country TEXT NOT NULL DEFAULT 'United States',
  merchant_city TEXT NOT NULL DEFAULT '',
  banner_title TEXT NOT NULL DEFAULT 'OpenPay Remittance Center',
  banner_subtitle TEXT NOT NULL DEFAULT 'Powered by Pi Network',
  fee_title TEXT NOT NULL DEFAULT 'Remittance Fee Card',
  fee_notes TEXT NOT NULL DEFAULT 'Rates are set by merchant and may vary by amount/currency.',
  business_note TEXT NOT NULL DEFAULT 'Cash deposit and payout available.',
  deposit_fee_percent NUMERIC NOT NULL DEFAULT 0,
  payout_fee_percent NUMERIC NOT NULL DEFAULT 0,
  flat_service_fee NUMERIC NOT NULL DEFAULT 0,
  min_operating_balance NUMERIC NOT NULL DEFAULT 25,
  qr_tagline TEXT NOT NULL DEFAULT 'SCAN TO DEPOSIT / PAYOUT',
  qr_accent TEXT NOT NULL DEFAULT '#2148ff',
  qr_background TEXT NOT NULL DEFAULT '#ffffff',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ===================== INDEXES =====================

CREATE INDEX IF NOT EXISTS idx_transactions_sender ON public.transactions(sender_id);
CREATE INDEX IF NOT EXISTS idx_transactions_receiver ON public.transactions(receiver_id);
CREATE INDEX IF NOT EXISTS idx_mining_sessions_user_active ON public.mining_sessions(user_id) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_mining_rewards_user ON public.mining_rewards(user_id);
CREATE INDEX IF NOT EXISTS idx_app_notifications_user_unread ON public.app_notifications(user_id) WHERE read_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_ledger_events_occurred ON public.ledger_events(occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_ledger_events_actor ON public.ledger_events(actor_user_id);
CREATE INDEX IF NOT EXISTS idx_ledger_events_related ON public.ledger_events(related_user_id);

-- ===================== KEY FUNCTIONS =====================
-- (All already exist in database - documented here for reference)

-- handle_new_user() - Trigger on auth.users insert: creates profile, wallet, account
-- transfer_funds(p_sender_id, p_receiver_id, p_amount, p_note, ...) - Atomic money transfer
-- start_mining_session(p_device_fingerprint, p_ip_address) - Start 24h mining
-- claim_mining_rewards() - Claim after 24h with referral bonus calculation
-- sync_mining_state() - Get current mining state for UI
-- withdraw_mining_earnings() - Withdraw mining balance to wallet
-- claim_referral_rewards() - Claim affiliate/referral bonuses
-- claim_welcome_bonus() - One-time welcome bonus
-- get_public_ledger(p_limit, p_offset) - Public transparent ledger with profile info
-- get_public_ledger_transaction(p_source_id) - Single ledger event detail
-- create_merchant_checkout_session(...) - Merchant creates checkout
-- pay_merchant_checkout_with_wallet(...) - Pay checkout with wallet balance
-- pay_merchant_checkout_with_virtual_card(...) - Pay checkout with virtual card
-- complete_merchant_checkout_with_transaction(...) - Complete checkout flow
-- create_merchant_payment_link(...) - Payment link creation
-- create_my_merchant_api_key(...) - API key generation
-- get_my_merchant_analytics() - Merchant dashboard analytics
-- get_my_merchant_balance_overview() - Merchant balance summary
-- admin_refund_self_send(p_transaction_id, p_decision, p_reason, p_admin_email) - Admin review
-- is_support_agent(p_user_id) - Check support agent status
-- is_transaction_participant(p_transaction_id) - Check if user is sender/receiver
-- generate_openpay_account_number() - Generate unique OP account number
-- generate_openpay_card_number() - Generate virtual card number
-- calculate_user_activity_credit_score(p_user_id) - Credit scoring

-- ===================== REALTIME =====================
-- Enabled on: mining_sessions, mining_rewards, app_notifications, transactions, wallets

-- ===================== NOTES =====================
-- All tables have RLS enabled with appropriate policies
-- Mining requires ad verification before session starts
-- Pi Auth maps pi_uid to supabase user via edge function
-- Referral bonuses calculated during mining claim (10% per active referral, max 100%)
-- Public ledger strips UUIDs from notes for privacy
