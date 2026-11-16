-- Day 1 / 7 / 30 retention, by install cohort.
--
-- The cohort is the day the SDK first saw the device
-- (user_first_touch_timestamp), not the first day inside the query window —
-- otherwise every long-standing player would be re-cohorted as a new install
-- at the window's left edge and D1 would read far too high.
--
-- Retention here is "came back on exactly day N", which is the definition
-- Firebase's own retention card uses. It is a stricter number than "came back
-- on day N or later"; do not compare it against a rolling-window figure from
-- another tool without checking which one that tool means.
--
-- A cohort younger than N days cannot have a day-N number yet, and counting it
-- as zero would drag the average down as a pure artefact of the window. Those
-- cells come back NULL instead: d7 is NULL until the cohort is 7 days old, d30
-- until it is 30.
WITH ev AS (
  SELECT
    user_pseudo_id,
    user_first_touch_timestamp,
    PARSE_DATE('%Y%m%d', event_date) AS active_day
  FROM `__DATASET__.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '__START__' AND '__END__'
    AND user_first_touch_timestamp IS NOT NULL
),
cohorts AS (
  SELECT
    user_pseudo_id,
    DATE(TIMESTAMP_MICROS(MIN(user_first_touch_timestamp))) AS cohort_day
  FROM ev
  GROUP BY user_pseudo_id
),
activity AS (
  SELECT DISTINCT user_pseudo_id, active_day FROM ev
),
joined AS (
  SELECT
    c.cohort_day,
    c.user_pseudo_id,
    DATE_DIFF(a.active_day, c.cohort_day, DAY) AS day_n
  FROM cohorts c
  JOIN activity a USING (user_pseudo_id)
  -- Only cohorts that installed inside the window: an older cohort would be
  -- missing the early days that its own D1 depends on.
  WHERE c.cohort_day >= PARSE_DATE('%Y%m%d', '__START__')
)
SELECT
  cohort_day,
  COUNT(DISTINCT user_pseudo_id) AS cohort_size,
  IF(DATE_DIFF(CURRENT_DATE(), cohort_day, DAY) >= 1,
     ROUND(SAFE_DIVIDE(
       COUNT(DISTINCT IF(day_n = 1, user_pseudo_id, NULL)),
       COUNT(DISTINCT user_pseudo_id)), 4), NULL) AS d1,
  IF(DATE_DIFF(CURRENT_DATE(), cohort_day, DAY) >= 7,
     ROUND(SAFE_DIVIDE(
       COUNT(DISTINCT IF(day_n = 7, user_pseudo_id, NULL)),
       COUNT(DISTINCT user_pseudo_id)), 4), NULL) AS d7,
  IF(DATE_DIFF(CURRENT_DATE(), cohort_day, DAY) >= 30,
     ROUND(SAFE_DIVIDE(
       COUNT(DISTINCT IF(day_n = 30, user_pseudo_id, NULL)),
       COUNT(DISTINCT user_pseudo_id)), 4), NULL) AS d30
FROM joined
GROUP BY cohort_day
ORDER BY cohort_day
