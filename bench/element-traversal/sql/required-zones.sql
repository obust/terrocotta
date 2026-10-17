-- Missing, duplicated, or aborted benchmark zones make a capture invalid.
WITH expected(name) AS (VALUES
    ('element.width.n0.total'),
    ('element.width.n1.total'),
    ('element.width.n10.total'),
    ('element.width.n100.total'),
    ('element.width.n1000.total'),
    ('element.depth.n1.total'),
    ('element.depth.n10.total'),
    ('element.depth.n100.total'),
    ('element.balanced.b4.d1.total'),
    ('element.balanced.b4.d3.total'),
    ('element.balanced.b4.d5.total'),
    ('element.width.n100.build-leaves'),
    ('element.width.n100.build-root'),
    ('element.width.n100.consume'),
    ('element.depth.n100.build'),
    ('element.depth.n100.consume'),
    ('element.balanced.b4.d5.build'),
    ('element.balanced.b4.d5.consume'),
    ('control.lists.empty.n1000'),
    ('control.lists.singleton.n1000'),
    ('control.option.none.n1000')
), observed AS (
    SELECT name,
           sum(kind = 2) AS completed,
           sum(kind = 5) AS aborted
    FROM annotations
    WHERE kind IN (2, 5)
    GROUP BY name
)
SELECT expected.name,
       coalesce(observed.completed, 0) AS completed,
       coalesce(observed.aborted, 0) AS aborted
FROM expected
LEFT JOIN observed USING(name)
WHERE coalesce(observed.completed, 0) <> 1
   OR coalesce(observed.aborted, 0) <> 0
ORDER BY expected.name;
