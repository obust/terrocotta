WITH expected(name) AS (VALUES
    ('text-ui.cold-build'),
    ('text-ui.warm-rebuild'),
    ('text-ui.one-text-change'),
    ('text-ui.warm-resize'),
    ('text-ui.retained-scroll'),
    ('text-ui.resize-sweep'),
    ('text-ui.corpus.alice'),
    ('text-ui.corpus.wikipedia'),
    ('text-ui.corpus.rfc'),
    ('text-ui.corpus.python')
), observed AS (
    SELECT name, sum(kind = 2) AS completed, sum(kind = 5) AS aborted
    FROM annotations
    WHERE kind IN (2, 5)
    GROUP BY name
)
SELECT expected.name, coalesce(observed.completed, 0) AS completed,
       coalesce(observed.aborted, 0) AS aborted
FROM expected LEFT JOIN observed USING(name)
WHERE coalesce(observed.completed, 0) <> 1 OR coalesce(observed.aborted, 0) <> 0
ORDER BY expected.name;
