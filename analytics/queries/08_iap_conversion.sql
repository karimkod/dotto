-- IAP conversion — INERT. Dotto has no in-app purchases.
--
-- There is no `in_app_purchase` dependency in pubspec.yaml, no product ids
-- anywhere in lib/, and no code path that could log a purchase. The app
-- monetises through AdMob alone; see 05_ad_revenue.sql for the number that
-- actually exists today.
--
-- This file is kept, and wired into the dashboard as an explicitly empty panel,
-- so that "IAP conversion is 0%" is never mistaken for a measurement. It will
-- return zero rows against a correct dataset, forever, until products ship.
--
-- If IAP is added later, `purchase` is the reserved GA4 event name to send —
-- with `value`, `currency`, `transaction_id` and `items` — and this query
-- starts working with no edit. Note that it deliberately does NOT count
-- Google Play / App Store server-side revenue, which arrives through the
-- linked-account integration rather than as an event.
WITH ev AS (
  SELECT
    event_date,
    event_name,
    user_pseudo_id,
    (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value')
      AS value
  FROM `__DATASET__.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '__START__' AND '__END__'
)
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS day,
  COUNT(DISTINCT user_pseudo_id) AS dau,
  COUNT(DISTINCT IF(event_name = 'purchase', user_pseudo_id, NULL)) AS payers,
  ROUND(SAFE_DIVIDE(
    COUNT(DISTINCT IF(event_name = 'purchase', user_pseudo_id, NULL)),
    COUNT(DISTINCT user_pseudo_id)), 5) AS conversion_rate,
  ROUND(SUM(IF(event_name = 'purchase', value, 0)), 4) AS revenue
FROM ev
GROUP BY day
HAVING payers > 0
ORDER BY day
