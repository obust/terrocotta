-- Is this capture trustworthy, and are the measurements used by this suite complete?
WITH capture AS (
    SELECT
        CAST((SELECT value FROM metadata WHERE key = 'schema_version') AS INTEGER) AS schema_version,
        CAST((SELECT value FROM metadata WHERE key = 'clean_shutdown') AS INTEGER) AS clean_shutdown,
        (SELECT value FROM metadata WHERE key = 'final_state') AS final_state,
        coalesce((SELECT writer_failed FROM recorder_health WHERE id = 1), 1) AS writer_failed,
        coalesce((SELECT output_limited FROM recorder_health WHERE id = 1), 1) AS output_limited,
        coalesce((SELECT omitted_events FROM recorder_health WHERE id = 1), 1) AS omitted_events
), trust AS (
    SELECT *,
        CASE
            WHEN schema_version <> 1 THEN 'unsupported'
            WHEN clean_shutdown <> 1 THEN 'untrusted'
            WHEN final_state <> 'complete' THEN 'untrusted'
            WHEN writer_failed <> 0 THEN 'untrusted'
            WHEN output_limited <> 0 THEN 'partial'
            WHEN omitted_events <> 0 THEN 'partial'
            ELSE 'complete'
        END AS evidence_status,
        CASE
            WHEN schema_version <> 1 THEN 'unsupported schema version'
            WHEN clean_shutdown <> 1 THEN 'capture did not shut down cleanly'
            WHEN final_state <> 'complete' THEN 'capture final state is not complete'
            WHEN writer_failed <> 0 THEN 'recorder writer failed'
            WHEN output_limited <> 0 THEN 'recorder output limit was reached'
            WHEN omitted_events <> 0 THEN 'recorder omitted events'
            ELSE 'capture finalized without recorded loss'
        END AS evidence_reason
    FROM capture
)
SELECT trust.evidence_status, trust.evidence_reason,
       trust.schema_version, trust.clean_shutdown, trust.final_state,
       measurement_status.name AS measurement,
       measurement_status.status AS measurement_status,
       measurement_status.reason AS measurement_reason,
       measurement_status.rows_recorded,
       measurement_status.omitted_events
FROM trust
CROSS JOIN measurement_status
ORDER BY measurement_status.name;
