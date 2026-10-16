# Performance benchmarks

Each benchmark is a self-contained `bench/<name>/` bundle with its own Python
runner. The runner records a RocRay Observatory capture, validates and queries
the SQLite data through the shared `report.py`, checks deterministic allocation
limits, and writes generated results inside the bundle.

```text
bench/
  report.py                            shared validation and reporting
  sql/capture_health.sql               shared capture-integrity query
  sql/zone_allocations.sql             shared per-zone allocation query
  sql/compare.sql                      shared capture comparison
  <benchmark>/
    main.py                             dedicated benchmark runner
    main.roc                            Roc workload entrypoint
    README.md                           workload documentation
    baseline.json                       committed allocation limits
    sql/required-zones.sql              zone validation query
    sql/report.sql                      benchmark report query
    results/<UTC timestamp>/            ignored captures and JSON reports
    ...                                 benchmark-specific fixtures
```

## Running benchmarks

Run benchmarks through their dedicated entrypoints:

```sh
python3 bench/element-traversal/main.py
python3 bench/text-ui/main.py
```

Each run creates `<bundle>/results/<UTC timestamp>/<name>.rrstats` and a JSON
report beside it. Generated results are not committed. The runner rejects
captures that did not finalize cleanly, lost events, lack required measurement
evidence, or have missing, duplicated, or aborted trace zones.

Allocation calls and requested bytes are checked against the bundle's committed
`baseline.json`. Timing is reported but is not a pass/fail signal.

Compare against an earlier capture with:

```sh
python3 bench/text-ui/main.py \
  --compare bench/text-ui/results/OLDER_RUN/text-ui.rrstats
```

After an intentional allocation change or compiler/platform update, inspect the
report and regenerate that benchmark's limits:

```sh
python3 bench/text-ui/main.py --update-baseline
```

Use `--output-dir DIR` to override the bundle-local results directory and
`--check` to validate the bundle without executing its Roc workload.

## Adding a benchmark

For a benchmark named `layout-cache`, add a self-contained
`bench/layout-cache/` bundle containing:

1. `main.roc`, with stable, uniquely named `Trace` zones and semantic checks.
2. `main.py`, which launches the workload and calls `bench/report.py`.
3. `sql/required-zones.sql`, which returns every missing, duplicated, or
   aborted required zone and no rows on success.
4. `sql/report.sql`, which returns benchmark-specific measurements.
5. `baseline.json`, generated after reviewing a successful run.
6. `README.md`, describing scope, workloads, and interpretation.

The reusable SQL can also be run directly, for example:

```sh
sqlite3 -header -column capture.rrstats \
  < bench/element-traversal/sql/report.sql
```

## Element traversal workload

The self-contained [`element-traversal`](element-traversal/README.md) bundle
measures construction and traversal across wide, deep, and balanced element
trees, with list-representation controls and normalized allocation reporting.

## Text UI workload

The self-contained [`text-ui`](text-ui/README.md) bundle benchmarks retained
text layout, wrapping, resize, and scroll behavior against frozen corpus data.
