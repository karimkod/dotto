-- Level completion rate, per level.
--
-- Rates are per PLAYER, not per event: a player who retries level 84 eleven
-- times still counts once on each side, so the rate stays "how many of the
-- people who met this level beat it" rather than being dragged down by the
-- persistence of the people who eventually won.
--
-- players_started is the denominator for everything. It comes from level_start,
-- which fires on every entry to a campaign level — including a re-entry to a
-- level already beaten, which is why players_completed can exceed it for early
-- levels that people replay. Read a completion_rate above 1.0 as "replayed",
-- not as a bug.
SELECT
  level_id,
  ANY_VALUE(world_id) AS world_id,
  COUNT(DISTINCT IF(event_name = 'level_start', user_pseudo_id, NULL))
    AS players_started,
  COUNT(DISTINCT IF(event_name = 'level_complete', user_pseudo_id, NULL))
    AS players_completed,
  COUNT(DISTINCT IF(event_name = 'level_abandon', user_pseudo_id, NULL))
    AS players_abandoned,
  COUNTIF(event_name = 'level_fail') AS total_fails,
  ROUND(SAFE_DIVIDE(
    COUNTIF(event_name = 'level_fail'),
    COUNT(DISTINCT IF(event_name = 'level_complete', user_pseudo_id, NULL))
  ), 2) AS fails_per_completer,
  ROUND(SAFE_DIVIDE(
    COUNT(DISTINCT IF(event_name = 'level_complete', user_pseudo_id, NULL)),
    COUNT(DISTINCT IF(event_name = 'level_start', user_pseudo_id, NULL))
  ), 4) AS completion_rate
FROM (
  SELECT
    event_name,
    user_pseudo_id,
    -- Older builds send the ids as numbers, newer ones as text: read both.
    (SELECT COALESCE(value.int_value, SAFE_CAST(value.string_value AS INT64))
      FROM UNNEST(event_params) WHERE key = 'level_id')
      AS level_id,
    (SELECT COALESCE(value.int_value, SAFE_CAST(value.string_value AS INT64))
      FROM UNNEST(event_params) WHERE key = 'world_id')
      AS world_id
  FROM `__DATASET__.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '__START__' AND '__END__'
    AND event_name IN
      ('level_start', 'level_complete', 'level_abandon', 'level_fail')
)
WHERE level_id IS NOT NULL
GROUP BY level_id
ORDER BY level_id
