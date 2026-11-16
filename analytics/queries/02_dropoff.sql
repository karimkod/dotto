-- Where players stop, as a survival curve over the campaign.
--
-- players_reached counts everyone who got at least this far; the curve it draws
-- only ever falls, and the steep steps in it are the walls. players_stopped_here
-- is the cliff itself — the players whose furthest completed level is this one
-- and who were never seen beyond it.
--
-- "Never seen beyond it" is bounded by the query window: someone whose last
-- session was inside the window may still come back tomorrow. Read the last few
-- days of any window as provisional.
WITH furthest AS (
  SELECT
    user_pseudo_id,
    MAX(
      -- Older builds send the ids as numbers, newer ones as text: read both.
      (SELECT COALESCE(value.int_value, SAFE_CAST(value.string_value AS INT64))
        FROM UNNEST(event_params) WHERE key = 'level_id')
    ) AS furthest_level
  FROM `__DATASET__.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '__START__' AND '__END__'
    AND event_name = 'level_complete'
  GROUP BY user_pseudo_id
)
SELECT
  furthest_level,
  COUNT(*) AS players_stopped_here,
  SUM(COUNT(*)) OVER (ORDER BY furthest_level DESC) AS players_reached,
  ROUND(SAFE_DIVIDE(
    COUNT(*),
    SUM(COUNT(*)) OVER (ORDER BY furthest_level DESC)
  ), 4) AS stop_rate
FROM furthest
WHERE furthest_level IS NOT NULL
GROUP BY furthest_level
ORDER BY furthest_level
