-- DAU and session length, per day.
--
-- Both come from GA4's automatic collection, not from anything this app logs:
-- a session is stitched together by the SDK's ga_session_id, and the length is
-- the span from a session's first event to its last.
--
-- That span is a floor, not the truth. A session with one event has length
-- zero — the player opened the app and did nothing measurable — and the final
-- stretch between the last event and actually putting the phone down is
-- invisible. Compare days against each other rather than reading the absolute
-- number as "time played".
WITH ev AS (
  SELECT
    event_date,
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
      AS session_id,
    event_timestamp
  FROM `__DATASET__.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '__START__' AND '__END__'
),
sessions AS (
  SELECT
    event_date,
    user_pseudo_id,
    session_id,
    (MAX(event_timestamp) - MIN(event_timestamp)) / 1000000 AS seconds
  FROM ev
  WHERE session_id IS NOT NULL
  GROUP BY event_date, user_pseudo_id, session_id
),
daily_users AS (
  SELECT event_date, COUNT(DISTINCT user_pseudo_id) AS dau
  FROM ev
  GROUP BY event_date
)
SELECT
  PARSE_DATE('%Y%m%d', d.event_date) AS day,
  d.dau,
  COUNT(s.session_id) AS sessions,
  ROUND(SAFE_DIVIDE(COUNT(s.session_id), d.dau), 2) AS sessions_per_user,
  ROUND(AVG(s.seconds), 1) AS avg_session_seconds,
  ROUND(APPROX_QUANTILES(s.seconds, 100)[OFFSET(50)], 1)
    AS median_session_seconds
FROM daily_users d
LEFT JOIN sessions s USING (event_date)
GROUP BY day, d.dau
ORDER BY day
