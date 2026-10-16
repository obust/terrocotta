# Element traversal benchmark

`element-traversal` measures allocation and traversal behavior for Terrocotta
element trees without involving layout, text measurement, painting, or GPU
rendering. Every measured leaf is `box({ events: [] }, [])`.

Run it from the repository root with either entrypoint:

```sh
bench/bench.sh element-traversal
python3 bench/element-traversal/main.py
```

Both runners record the capture and structured report under this bundle's
`results/<UTC timestamp>/` directory, print the SQL report to stdout, and check
the committed `baseline.json`. Use `--update-baseline` only after reviewing an
intentional allocation change.

## Workloads

The benchmark covers:

- width: one root with 0, 1, 10, 100, or 1,000 leaf children;
- depth: single-child chains of 1, 10, or 100 boxes;
- balanced: four-way trees of depth 1, 3, or 5;
- separate construction and consumption zones for representative trees;
- nested empty lists, singleton lists, and an option-style `None` control.

The application verifies the exact emitted operation count for every tree. The
report normalizes allocation calls and bytes by both logical node count and
emitted operation count.

## Bundle contents

- `element-traversal.roc`: workload and operation-count assertions.
- `main.py`: standalone capture, SQL reporting, and baseline runner.
- `baseline.json`: deterministic per-zone allocation limits.
- `sql/required-zones.sql`: required completed-zone validation.
- `sql/report.sql`: normalized allocation and timing report.
