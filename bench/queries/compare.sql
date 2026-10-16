-- Compare matching zones. Open the newer capture as main and attach the older
-- capture as `baseline` before executing this query.
WITH current_zones AS (
    SELECT CAST(integer_value AS INTEGER) AS zone_id, name AS zone_name,
           active_ns
    FROM main.annotations
    WHERE kind = 2
), baseline_zones AS (
    SELECT CAST(integer_value AS INTEGER) AS zone_id, name AS zone_name,
           active_ns
    FROM baseline.annotations
    WHERE kind = 2
), current_activity AS (
    SELECT zone_id,
           sum(kind IN (0, 2, 3)) AS allocation_calls,
           sum(CASE WHEN kind IN (0, 2, 3) THEN bytes ELSE 0 END) AS allocated_bytes
    FROM main.allocation_events GROUP BY zone_id
), baseline_activity AS (
    SELECT zone_id,
           sum(kind IN (0, 2, 3)) AS allocation_calls,
           sum(CASE WHEN kind IN (0, 2, 3) THEN bytes ELSE 0 END) AS allocated_bytes
    FROM baseline.allocation_events GROUP BY zone_id
)
SELECT current_zones.zone_name,
       coalesce(baseline_activity.allocation_calls, 0) AS baseline_calls,
       coalesce(current_activity.allocation_calls, 0) AS current_calls,
       coalesce(current_activity.allocation_calls, 0) - coalesce(baseline_activity.allocation_calls, 0) AS calls_delta,
       coalesce(current_activity.allocation_calls, 0) * 1.0 / nullif(coalesce(baseline_activity.allocation_calls, 0), 0) AS calls_ratio,
       coalesce(baseline_activity.allocated_bytes, 0) AS baseline_bytes,
       coalesce(current_activity.allocated_bytes, 0) AS current_bytes,
       coalesce(current_activity.allocated_bytes, 0) - coalesce(baseline_activity.allocated_bytes, 0) AS bytes_delta,
       coalesce(current_activity.allocated_bytes, 0) * 1.0 / nullif(coalesce(baseline_activity.allocated_bytes, 0), 0) AS bytes_ratio,
       baseline_zones.active_ns AS baseline_active_ns,
       current_zones.active_ns AS current_active_ns
FROM current_zones
JOIN baseline_zones USING(zone_name)
LEFT JOIN current_activity ON current_activity.zone_id = current_zones.zone_id
LEFT JOIN baseline_activity ON baseline_activity.zone_id = baseline_zones.zone_id
ORDER BY current_zones.zone_name;
