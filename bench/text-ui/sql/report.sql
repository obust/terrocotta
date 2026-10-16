SELECT name,
       wall_ns,
       active_ns
FROM annotations
WHERE kind = 2 AND name LIKE 'text-ui.%'
ORDER BY name;
