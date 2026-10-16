# Element traversal benchmark

`element-traversal` measures the allocation and traversal behavior of
Terrocotta element trees across wide, deep, and balanced shapes. It separates
representative construction and consumption phases and includes controls for
collection representation costs.

## Scope

- Measures pure `Element.View` construction and iteration into element
  operations.
- Uses empty box leaves: `box({ events: [] }, [])`.
- Includes whole-workload zones and selected construction/consumption splits.
- Does not perform layout, text measurement, painting, rendering, event
  dispatch, or GPU work. `render!` is intentionally empty.
- Runs against the RocRay headless backend with full allocation tracing.

## Running

Run the dedicated runner from the repository root:

```sh
python3 bench/element-traversal/main.py
```

Useful maintenance commands:

```sh
python3 bench/element-traversal/main.py --check
python3 bench/element-traversal/main.py --update-baseline
python3 bench/element-traversal/main.py \
  --compare path/to/older/element-traversal.rrstats
python3 bench/element-traversal/main.py --output-dir path/to/results
```

## Workloads

### Width

`element.width.n*.total` constructs one root with 0, 1, 10, 100, or 1,000
direct leaf children and consumes the resulting operation stream. A tree with
`n` leaves has `n + 1` logical nodes and emits `2 × (n + 1)` open/close
operations.

The 100-leaf case also records:

- `element.width.n100.build-leaves`
- `element.width.n100.build-root`
- `element.width.n100.consume`

### Depth

`element.depth.n*.total` constructs single-child chains of depth 1, 10, and 100. A depth-`n` chain has `n` nodes and emits `2n` operations.

The depth-100 case also records separate `build` and `consume` zones.

### Balanced

`element.balanced.b4.d*.total` constructs four-way trees of depth 1, 3, and 5.
Those cases contain 1, 21, and 341 logical nodes and emit 2, 42, and 682
operations respectively.

The depth-5 case also records separate `build` and `consume` zones.

### Representation controls

- `control.lists.empty.n1000` stores 1,000 shared empty lists.
- `control.lists.singleton.n1000` stores 1,000 allocated singleton lists.
- `control.option.none.n1000` stores 1,000 `None` values with the same broad
  option shape used for event lists.

These controls make empty-list and tagged-union representation costs visible
beside element-tree measurements.

## Inputs

All inputs are deterministic and generated in `main.roc`; the benchmark uses no
fixtures, randomness, clock input, or network access. Shape, depth, branching
factor, and control counts are fixed constants encoded by the traced calls.

## Correctness checks

The benchmark:

- calculates the exact expected operation count for every total-tree workload;
- crashes if an actual count differs;
- consumes every constructed tree so construction cannot become dead work;
- keeps the aggregate operation count observable in the model; and
- requires every declared trace zone to complete exactly once through
  `sql/required-zones.sql`.

## Results and interpretation

Each run produces:

```text
results/<UTC timestamp>/
├── element-traversal.rrstats
└── element-traversal.json
```

`sql/report.sql` reports allocation calls, requested bytes, and active time for
total-tree zones. It normalizes allocations by both logical node count and
emitted operation count, making scaling across sizes and shapes easier to
compare. Split zones help attribute a regression to construction or traversal.

The representation controls are diagnostic reference workloads, not substitutes
for the tree zones. Timing from unrelated machines or compiler pins is not
directly comparable.

## Allocation baseline

`baseline.json` records maximum allocation calls and requested bytes for every
required zone, together with capture metadata. A run fails when those limits
are exceeded or its metadata is incompatible.

After an intentional allocation or toolchain change, inspect the complete
report before updating the baseline:

```sh
python3 bench/element-traversal/main.py --update-baseline
```

## Methodological limitations

- The trees contain empty boxes rather than production widget styles, events,
  text, images, or custom payloads.
- The headless backend excludes rendering and GPU behavior.
- Timing is a single instrumented observation and is informational, not a
  pass/fail threshold.
- Full allocation tracing adds overhead.
- Recursive deep-tree construction may measure different compiler/runtime
  behavior from wide iterative construction as well as tree shape itself.

## File structure

```text
element-traversal/
├── README.md
├── main.py
├── main.roc
├── baseline.json
├── sql/
│   ├── report.sql
│   └── required-zones.sql
└── results/                  # generated and ignored
```
