-- The shape of an abandonment: how long they fought before leaving.
--
-- level_abandon fires from the game screen's dispose, so it means "left this
-- level unfinished" — backing out to the menu, or being popped for any other
-- reason. It does NOT fire when the OS kills the app or the player swipes it
-- away from the task switcher, because nothing disposes in that path.
--
-- That gap is the point of unexplained_exits below: starts minus completes
-- minus abandons is the population that walked away with the app still on the
-- level. A level where that number dwarfs the deliberate abandons is a level
-- people are stuck on at the moment they put the phone down.
WITH ev AS (
  SELECT
    event_name,
    user_pseudo_id,
    -- Older builds send the ids as numbers, newer ones as text: read both.
    (SELECT COALESCE(value.int_value, SAFE_CAST(value.string_value AS INT64))
      FROM UNNEST(event_params) WHERE key = 'level_id')
      AS level_id,
    (SELECT value.int_value FROM UNNEST(event_params)
      WHERE key = 'seconds_spent') AS seconds_spent,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'attempts')
      AS attempts
  FROM `__DATASET__.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '__START__' AND '__END__'
    AND event_name IN ('level_start', 'level_complete', 'level_abandon')
)
SELECT
  level_id,
  COUNTIF(event_name = 'level_start') AS starts,
  COUNTIF(event_name = 'level_complete') AS completes,
  COUNTIF(event_name = 'level_abandon') AS abandons,
  COUNTIF(event_name = 'level_start')
    - COUNTIF(event_name = 'level_complete')
    - COUNTIF(event_name = 'level_abandon') AS unexplained_exits,
  ROUND(AVG(IF(event_name = 'level_abandon', seconds_spent, NULL)), 1)
    AS avg_seconds_before_quitting,
  ROUND(AVG(IF(event_name = 'level_abandon', attempts, NULL)), 2)
    AS avg_attempts_before_quitting
FROM ev
WHERE level_id IS NOT NULL
GROUP BY level_id
ORDER BY abandons DESC
