# Text UI benchmark

`text-ui` benchmarks the layout and text-wrapping portion of a document/inbox
screen. The view contains a sidebar, toolbar, 75 variable-height preview rows in
a fixed 420 px scrolling viewport, and four article text nodes. It deliberately
uses `Font.stub` and an empty `render!`, so it does not measure production font
rasterization, paint traversal, or GPU rendering.

Run it from the repository root:

```sh
bench/bench.sh text-ui
```

The bundle also has a standalone runner with the same capture and reporting
pipeline:

```sh
python3 bench/text-ui/main.py
```

It runs the Roc benchmark, executes the shared capture-health and allocation
queries plus `sql/required-zones.sql` and `sql/report.sql`, prints the report to
stdout, writes the capture and structured report under this bundle's `results/`
directory, and checks the committed `baseline.json`. Use `--update-baseline`
only after reviewing an intentional allocation change.

## Workloads

The five primary zones form one retained-layout sequence:

1. `text-ui.cold-build` constructs and solves the mixed-corpus view with an
   empty text-measurement cache.
2. `text-ui.warm-rebuild` calls `Layout.clear`, rebuilds identical content at
   the same width, and therefore exercises cross-generation cache hits.
3. `text-ui.one-text-change` rebuilds at the same width after changing only row
   37, producing one new preview measurement while other text remains cached.
4. `text-ui.warm-resize` rebuilds the changed view from 960 px to 640 px. Text
   measurements remain cached, but wrapping and solved geometry change.
5. `text-ui.retained-scroll` rebuilds the same 640 px view with the scrolling
   row container's stable node ID and a retained vertical offset of -320 px.

The benchmark asserts the expected node count, verifies that the scrolling node
receives its offset, and keeps a checksum of node, child-index, text-node, and
wrapped-line counts observable in the application model.

Four additional `text-ui.corpus.*` zones perform independent cold builds for
Alice in Wonderland, Wikipedia typography JSON, RFC 5732, and the Python tutorial
HTML. These diagnostic zones help distinguish general layout regressions from
input-shape-sensitive behavior.

## Corpus

Article text is compile-time imported from the frozen samples under `corpus/`.
Each workload consumes exactly 24,000 source bytes in four 6,000-byte text
nodes. Single-source diagnostics use consecutive chunks; the mixed workload
uses the first chunk from each source. Equal byte counts make comparisons less
sensitive to original file size, while punctuation, markup, line structure,
and word length deliberately remain different.

The vendored samples are:

- `gutenberg-alice.txt`
- `wikimedia-typography.json`
- `rfc-5732.txt`
- `python-introduction.html`

See `corpus/metadata.json` for exact URLs, retrieval date, and licensing.
The JSON and HTML fixtures intentionally remain in their source formats, so
their zones exercise punctuation and markup rather than extracted visible text.
Do not fetch web content during a benchmark run.

## Bundle contents

- `text-ui.roc`: workload implementation and semantic assertions.
- `main.py`: standalone capture, SQL reporting, and baseline runner.
- `baseline.json`: deterministic per-zone allocation limits.
- `sql/required-zones.sql`: required completed-zone validation.
- `sql/report.sql`: timing report for all text UI zones.
- `corpus/`: frozen inputs, provenance, and licensing notes.
