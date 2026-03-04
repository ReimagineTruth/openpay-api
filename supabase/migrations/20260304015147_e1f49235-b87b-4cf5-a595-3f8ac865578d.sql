
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
