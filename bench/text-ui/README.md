# Text UI benchmark

`text-ui` measures retained layout and text wrapping for a representative
document/inbox screen. It is intended to expose regressions in text measurement
caching, wrapping, layout rebuilding, resizing, and retained scrolling.

## Scope

The view contains a sidebar, toolbar, 75 variable-height preview rows in a fixed
420 px scrolling viewport, and four article text nodes.

- Measures element construction, canonical text measurement, cache reuse,
  wrapping, layout solving, and retained scroll positioning.
- Uses `Layout.test_layout()` and `Font.stub` for deterministic host-independent
  metrics.
- Does not measure production font rasterization, paint traversal, draw calls,
  GPU work, or interactive event handling. `render!` is intentionally empty.
- Runs against the RocRay headless backend with full allocation tracing.

## Running

Run the dedicated runner from the repository root:

```sh
python3 bench/text-ui/main.py
```

Useful maintenance commands:

```sh
python3 bench/text-ui/main.py --check
python3 bench/text-ui/main.py --update-baseline
python3 bench/text-ui/main.py --compare path/to/older/text-ui.rrstats
python3 bench/text-ui/main.py --output-dir path/to/results
```

## Workloads

The five primary zones form one retained-layout sequence.

### `text-ui.cold-build`

Constructs and solves the 960 px mixed-corpus view using a new layout and an
empty text-measurement cache. This is the cold reference for later zones.

### `text-ui.warm-rebuild`

Calls `Layout.clear()` and rebuilds identical content at 960 px. Canonical text
measurements survive into the next cache generation, so this zone exercises
cross-generation cache hits while still rebuilding and solving the full view.

### `text-ui.one-text-change`

Rebuilds at 960 px after appending `" Updated"` to row 37 only. One preview
requires a new canonical measurement; all unchanged text remains cacheable.

### `text-ui.warm-resize`

Rebuilds the changed view at 640 px. Canonical measurements remain cached, but
text is rewrapped and geometry is solved for the narrower viewport.

### `text-ui.retained-scroll`

Rebuilds the same 640 px view with the scrolling row container's stable node ID
and a retained vertical offset of -320 px. This measures rebuild and positioning
work, not input-device scroll handling.

### `text-ui.corpus.*`

Four independent cold builds use Alice in Wonderland, Wikipedia typography
JSON, RFC 5732, and Python tutorial HTML. They keep source-byte volume constant
to highlight sensitivity to word length, punctuation, markup, and line shape.

## Inputs

Article text is compile-time imported from frozen files under `corpus/`. Every
scenario consumes 24,000 source bytes split across four 6,000-byte text nodes.

- Mixed workloads use the first chunk from each source.
- Single-source diagnostics use four consecutive chunks from one source.
- JSON and HTML remain in their source formats rather than being converted to
  visible prose.
- Exact URLs, retrieval dates, formats, and licenses are recorded in
  `corpus/metadata.json` and `corpus/README.md`.
- Benchmark runs must not fetch network content.

## Correctness checks

The benchmark prevents successful-but-meaningless measurements by:

- asserting the expected node count after every build;
- requiring a real vertical scrolling container;
- verifying that the retained -320 px offset reaches that container;
- keeping node, child-index, text-node, and wrapped-line counts observable in
  the model checksum; and
- requiring every declared trace zone to complete exactly once through
  `sql/required-zones.sql`.

## Results and interpretation

Each run produces:

```text
results/<UTC timestamp>/
├── text-ui.rrstats
└── text-ui.json
```

The runner prints zone timing and allocation totals to stdout. Useful
comparisons include cold versus warm rebuild, warm rebuild versus one changed
text, and the same retained state before and after resize or scroll.

Corpus zones have equal source-byte volume but intentionally different content
shape. Differences between them should not be interpreted as parser or renderer
performance, and timing from unrelated machines or compiler pins is not
directly comparable.

## Allocation baseline

`baseline.json` records maximum allocation calls and requested bytes for every
required zone, together with capture metadata. A run fails when those limits
are exceeded or its metadata is incompatible.

After an intentional allocation or toolchain change, inspect the complete
report before updating the baseline:

```sh
python3 bench/text-ui/main.py --update-baseline
```

## Methodological limitations

- `Font.stub` does not represent production font shaping or rasterization.
- The headless backend excludes GPU and window-system behavior.
- Timing is a single instrumented observation and is informational, not a
  pass/fail threshold.
- Full allocation tracing adds overhead.
- The view resembles a document UI but is still synthetic.
- Raw JSON and HTML diagnose input shape rather than visible-document fidelity.

## File structure

```text
text-ui/
├── README.md
├── main.py
├── main.roc
├── baseline.json
├── sql/
│   ├── report.sql
│   └── required-zones.sql
├── corpus/
│   ├── README.md
│   ├── metadata.json
│   └── ... frozen samples
└── results/                  # generated and ignored
```
