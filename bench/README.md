# Performance benchmarks

Each top-level `bench/*.roc` file or `bench/<name>/<name>.roc` bundle is an
independently runnable benchmark. The shared runner discovers them
automatically, records their RocRay Observatory traces, validates the SQLite
captures, and checks deterministic allocations.

```text
bench/
  *.roc                                benchmark entrypoints
  bench.sh                             discovery and capture runner
  report.py                            read-only validation and reporting
  baselines/<benchmark>.json           committed allocation limits
  queries/capture_health.sql           shared capture-integrity query
  queries/zone_allocations.sql         shared per-zone allocation query
  queries/compare.sql                  shared capture comparison
  queries/<benchmark>-required-zones.sql
  queries/<benchmark>-report.sql       benchmark-specific report
  <benchmark>/                         optional self-contained bundle
    <benchmark>.roc                    bundled entrypoint
    README.md                           workload documentation
    baseline.json                       committed allocation limits
    main.py                             optional standalone runner
    sql/required-zones.sql              zone validation query
    sql/report.sql                      benchmark report query
    ...                                 benchmark-specific fixtures
  results/                             ignored generated captures and JSON
```

## Running benchmarks

List available benchmarks:

```sh
bench/bench.sh --list
```

With no names, the runner executes every discovered benchmark. Pass one or more
names to select a subset:

```sh
bench/bench.sh
bench/bench.sh element-traversal
bench/bench.sh element-traversal another-benchmark
```

Each flat benchmark writes its default capture and JSON report to a timestamped
directory under `bench/results/`. A bundled benchmark keeps generated output in
its own `<bundle>/results/` directory. Generated results are not committed.

The runner rejects captures that did not finalize cleanly, lost events, lack
required measurement evidence, or have missing, duplicated, or aborted trace
zones. Benchmark applications should also verify their semantic work—for
example, `element-traversal.roc` checks its emitted operation counts.

Allocation calls and requested bytes are checked against the benchmark's
committed baseline. Timing is reported but is not a pass/fail signal.

To compare a run with captures from another run directory, pass the directory
that directly contains the benchmark's `.rrstats` file:

```sh
bench/bench.sh --compare-dir bench/results/OLDER_RUN
```

After an intentional allocation change or compiler/platform update, inspect the
reports and regenerate limits for all or selected benchmarks:

```sh
bench/bench.sh --update-baselines
bench/bench.sh --update-baselines element-traversal
```

## Adding a benchmark

Small benchmarks can use the flat layout. For a benchmark named `layout-cache`,
add:

1. `bench/layout-cache.roc`, with stable, uniquely named `Trace` zones.
2. `bench/queries/layout-cache-required-zones.sql`, which returns one row for
   every missing, duplicated, or aborted required zone and no rows on success.
3. `bench/queries/layout-cache-report.sql`, which returns the benchmark-specific
   measurements to display and include in the JSON report.
4. `bench/baselines/layout-cache.json`, generated after reviewing a complete run
   with `bench/bench.sh --update-baselines layout-cache`.

No runner or source-check allowlist needs updating. `scripts/check.sh` discovers
all benchmark entrypoints and compiles them.

Benchmarks with dedicated fixtures or documentation should instead keep their
material together under `bench/layout-cache/` as `layout-cache.roc`,
`README.md`, `baseline.json`, `sql/required-zones.sql`, `sql/report.sql`, and any
local assets. It may also provide a standalone `main.py`. The shared runner
exposes either layout under the same `layout-cache` name.

The reusable SQL can also be run directly, for example:

```sh
sqlite3 -header -column capture.rrstats \
  < bench/queries/element-traversal-report.sql
```

## Element traversal workload

`element-traversal` covers:

- width: one root with 0, 1, 10, 100, or 1,000 leaf children;
- depth: single-child chains of 1, 10, or 100 boxes;
- balanced: four-way trees of depth 1, 3, or 5;
- construction and consumption phase splits for representative trees;
- nested empty lists, singleton lists, and an option-style `None` control.

Every leaf uses `box({ events: [] }, [])`, exposing different traversal
complexities while keeping empty-list representation costs visible.

## Text UI workload

The self-contained [`text-ui`](text-ui/README.md) bundle benchmarks retained
text layout, wrapping, resize, and scroll behavior against frozen corpus data.
