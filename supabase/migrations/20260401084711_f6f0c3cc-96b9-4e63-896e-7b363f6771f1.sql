
-- Fix merchant_product_stats view: set security_invoker = true
-- This ensures the view runs with the querying user's permissions, not the view creator's
CREATE OR REPLACE VIEW public.merchant_product_stats
WITH (security_invoker = true)
AS
SELECT mpsi.product_id,
    mcs.merchant_user_id,
    count(DISTINCT mp.id) AS total_sales,
    count(DISTINCT mp.id) AS total_purchases,
    COALESCE(sum(
        CASE
            WHEN mp.id IS NOT NULL THEN mpsi.line_total
            ELSE 0::numeric
        END), 0::numeric) AS total_revenue
FROM merchant_checkout_session_items mpsi
    JOIN merchant_checkout_sessions mcs ON mcs.id = mpsi.session_id
    LEFT JOIN merchant_payments mp ON mp.session_id = mcs.id AND mp.status = 'succeeded'::text
GROUP BY mpsi.product_id, mcs.merchant_user_id;
