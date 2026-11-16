-- Ad revenue per user: ARPDAU, and the impression counts behind it.
--
-- Revenue comes from the `value` parameter on ad_impression, which AdManager
-- fills from AdMob's paid-event callback. Nothing else in the app carries
-- money, so if revenue_usd is zero while impressions are not, the callback is
-- not firing — see docs/analytics-setup.md, it needs enabling per account.
--
-- ARPDAU divides by every active user, including the ones who saw no ad; ARPIU
-- divides by only the ones who did. The first is the business number, the
-- second says what an ad-watching player is worth, and the gap between them is
-- how much of the audience is currently monetising at all.
--
-- The currency is whatever AdMob reported. Mixed currencies would sum into
-- nonsense, so currencies is listed to make that visible rather than assumed.
WITH ev AS (
  SELECT
    event_date,
    event_name,
    user_pseudo_id,
    (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value')
      AS value,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'currency')
      AS currency,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ad_format')
      AS ad_format
  FROM `__DATASET__.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '__START__' AND '__END__'
),
daily AS (
  SELECT event_date, COUNT(DISTINCT user_pseudo_id) AS dau
  FROM ev GROUP BY event_date
),
rev AS (
  SELECT
    event_date,
    COUNT(*) AS impressions,
    COUNT(DISTINCT user_pseudo_id) AS users_shown_ads,
    SUM(value) AS revenue,
    COUNTIF(ad_format = 'rewarded') AS rewarded_impressions,
    COUNTIF(ad_format = 'interstitial') AS interstitial_impressions,
    STRING_AGG(DISTINCT currency ORDER BY currency) AS currencies
  FROM ev
  WHERE event_name = 'ad_impression'
  GROUP BY event_date
)
SELECT
  PARSE_DATE('%Y%m%d', daily.event_date) AS day,
  daily.dau,
  IFNULL(rev.impressions, 0) AS impressions,
  IFNULL(rev.rewarded_impressions, 0) AS rewarded,
  IFNULL(rev.interstitial_impressions, 0) AS interstitial,
  rev.currencies,
  ROUND(IFNULL(rev.revenue, 0), 4) AS revenue,
  ROUND(SAFE_DIVIDE(rev.revenue, daily.dau), 5) AS arpdau,
  ROUND(SAFE_DIVIDE(rev.revenue, rev.users_shown_ads), 5) AS arpiu,
  ROUND(SAFE_DIVIDE(rev.revenue, rev.impressions) * 1000, 3) AS ecpm
FROM daily
LEFT JOIN rev USING (event_date)
ORDER BY day
