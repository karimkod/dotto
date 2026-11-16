-- The first-launch funnel, in the order a new player meets it.
--
-- Every step is gated: the UMP form is only shown where a form exists, ATT only
-- on iOS 14+, so a step's count being lower than the one above it is not
-- automatically a loss — it may be a step that population never sees. What is
-- always a real loss is onboarding_completed against onboarding_consent_shown,
-- since the first fires only for launches that entered the funnel.
WITH steps AS (
  SELECT event_name, COUNT(DISTINCT user_pseudo_id) AS users
  FROM `__DATASET__.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '__START__' AND '__END__'
    AND event_name LIKE 'onboarding_%'
  GROUP BY event_name
)
SELECT
  step,
  IFNULL(users, 0) AS users,
  ROUND(SAFE_DIVIDE(users, MAX(users) OVER ()), 4) AS share_of_entrants
FROM UNNEST([
  'onboarding_consent_shown', 'onboarding_consent_completed',
  'onboarding_ump_shown', 'onboarding_ump_completed',
  'onboarding_att_shown', 'onboarding_att_accepted', 'onboarding_att_denied',
  'onboarding_signin_shown', 'onboarding_signin_accepted',
  'onboarding_signin_skipped', 'onboarding_signin_failed',
  'onboarding_completed'
]) AS step WITH OFFSET AS ord
LEFT JOIN steps ON steps.event_name = step
ORDER BY ord
