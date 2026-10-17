-- Normalize total-tree zones by logical node and emitted operation counts.
WITH expected(zone_name, shape, size, nodes, operations) AS (VALUES
    ('element.width.n0.total', 'width', 0, 1, 2),
    ('element.width.n1.total', 'width', 1, 2, 4),
    ('element.width.n10.total', 'width', 10, 11, 22),
    ('element.width.n100.total', 'width', 100, 101, 202),
    ('element.width.n1000.total', 'width', 1000, 1001, 2002),
    ('element.depth.n1.total', 'depth', 1, 1, 2),
    ('element.depth.n10.total', 'depth', 10, 10, 20),
    ('element.depth.n100.total', 'depth', 100, 100, 200),
    ('element.balanced.b4.d1.total', 'balanced-b4', 1, 1, 2),
    ('element.balanced.b4.d3.total', 'balanced-b4', 3, 21, 42),
    ('element.balanced.b4.d5.total', 'balanced-b4', 5, 341, 682)
), zones AS (
    SELECT CAST(integer_value AS INTEGER) AS zone_id, name AS zone_name,
           wall_ns, active_ns
    FROM annotations
    WHERE kind = 2
), activity AS (
    SELECT zone_id,
           sum(kind IN (0, 2, 3)) AS allocation_calls,
           sum(CASE WHEN kind IN (0, 2, 3) THEN bytes ELSE 0 END) AS allocated_bytes
    FROM allocation_events
    GROUP BY zone_id
)
SELECT expected.shape,
       expected.size,
       expected.nodes,
       expected.operations,
       activity.allocation_calls,
       activity.allocated_bytes,
       activity.allocation_calls * 1.0 / expected.nodes AS calls_per_node,
       activity.allocated_bytes * 1.0 / expected.nodes AS bytes_per_node,
       activity.allocation_calls * 1.0 / expected.operations AS calls_per_operation,
       activity.allocated_bytes * 1.0 / expected.operations AS bytes_per_operation,
       zones.active_ns
FROM expected
JOIN zones USING(zone_name)
JOIN activity USING(zone_id)
ORDER BY CASE expected.shape WHEN 'width' THEN 1 WHEN 'depth' THEN 2 ELSE 3 END,
         expected.size;
