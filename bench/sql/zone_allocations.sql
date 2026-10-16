-- Allocation traffic attributed to each completed benchmark Trace zone.
-- Nested zones intentionally include their children's work.
WITH evidence AS (
    SELECT
        (SELECT status FROM measurement_status WHERE name = 'allocation_lifecycle') AS allocations,
        (SELECT status FROM measurement_status WHERE name = 'annotations') AS annotations
), zones AS (
    SELECT CAST(integer_value AS INTEGER) AS zone_id,
           name,
           phase,
           wall_ns,
           active_ns
    FROM annotations
    WHERE kind = 2
), activity AS (
    SELECT zone_id,
           sum(kind IN (0, 2, 3)) AS allocation_calls,
           sum(CASE WHEN kind IN (0, 2, 3) THEN bytes ELSE 0 END) AS allocated_bytes,
           sum(kind = 1) AS free_calls,
           sum(CASE WHEN kind = 1 THEN bytes ELSE 0 END) AS freed_bytes,
           sum(copied_bytes) AS copied_bytes
    FROM allocation_events
    GROUP BY zone_id
)
SELECT CASE
           WHEN evidence.allocations <> 'complete' THEN evidence.allocations
           WHEN evidence.annotations <> 'complete' THEN evidence.annotations
           ELSE 'complete'
       END AS evidence_status,
       zones.name AS zone_name,
       CASE zones.phase WHEN 1 THEN 'init!' WHEN 2 THEN 'update!'
                        WHEN 3 THEN 'render!' WHEN 4 THEN 'task' ELSE 'unknown' END AS phase,
       coalesce(activity.allocation_calls, 0) AS allocation_calls,
       coalesce(activity.allocated_bytes, 0) AS allocated_bytes,
       coalesce(activity.free_calls, 0) AS free_calls,
       coalesce(activity.freed_bytes, 0) AS freed_bytes,
       coalesce(activity.copied_bytes, 0) AS copied_bytes,
       zones.wall_ns,
       zones.active_ns
FROM evidence
CROSS JOIN zones
LEFT JOIN activity USING(zone_id)
ORDER BY zones.name;
