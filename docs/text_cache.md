# Text measurement cache

Terrocotta rebuilds its layout every frame. Measuring every text node through
the host renderer on every rebuild would be unnecessarily expensive, so
`Layout` keeps a persistent `TextMeasureCache`.

The cache stores the parts of text measurement that are independent of the
available layout width. Line wrapping remains a layout operation and is
recomputed after the solver determines the width of a text node.

In short:

```text
text + font + font size + spacing
                │
                ▼
       TextMeasureCache lookup
          │              │
        miss             hit
          │              │
          ▼              │
  host text measurement  │
          │              │
          └──────┬───────┘
                 ▼
       canonical measurement
                 │
       + available node width
                 ▼
           wrapped lines
```

## What is cached

A cache key contains only values that affect the host's glyph measurement:

```roc
Key : {
    text : Str,
    font : U64,
    font_size : F32,
    spacing : F32,
}
```

Properties such as color, alignment, wrapping mode, and line height are not in
the key. They either do not change glyph widths or are applied later by the
layout code.

Each entry contains a canonical measurement:

- the preferred unwrapped width;
- the renderer's natural line height;
- the minimum word width;
- the width of a space;
- measured word runs and explicit newline markers;
- the natural line count and whether the text contains newlines.

Keeping measured word runs in the entry is what lets layout try different wrap
widths without calling the host renderer again.

## Cache lifecycle

`Layout.new()` creates one empty cache and captures the host's
`measure_text_raw!` function. The same cache then travels with the `Layout`
value.

When a text node is added, `Layout.add_text!` calls
`TextMeasureCache.get_or_create!`:

1. On a hit, it returns the stored canonical measurement and marks the entry as
   used in the current generation.
2. On a miss, `Text.measure_canonical!` measures the space, line height, and
   word runs through the host, then inserts the result.
3. `Layout` immediately derives the text node's intrinsic size from that
   canonical measurement.

After constraint solving determines the actual node width,
`Layout.wrap_text_nodes` reads the cached entry and calls `Text.wrap`. Wrapping
is deliberately not cached because it is cheap and depends on the width
assigned by the current layout.

At the beginning of the next frame, `Layout.clear()` removes frame-local nodes,
text contents, and wrapped lines, but advances the cache to its next
generation. Therefore repeated text can reuse measurements across frames.

## Eviction

The cache uses a small generational retention policy:

- an entry hit in an old generation is refreshed to the current generation;
- entries unused for more than three generations are pruned;
- the cache is capped at 4,096 entries;
- `reset()` clears all entries and returns to generation zero.

This is closer to a bounded "recently used" cache than permanent memoization.
It allows transient labels to disappear while stable UI text stays warm.

`reset()` is useful when measurements may have become globally invalid, for
example after replacing font resources or changing renderer behavior. Normal
changes to text, font, font size, or spacing do not require a reset because
they naturally produce a different key.

## Running example

Assume a monospace renderer where every character, including a space, is one
unit wide. During canonical measurement, Terrocotta splits these two strings
into word runs:

```text
"Roc makes UI fun"

 byte offset    0       4        10    13
                │       │        │     │
 word run      "Roc "  "makes "  "UI " "fun"
 measured width   4       6         3     3


"Cache once\nwrap twice"

 byte offset    0        6       10    11      16
                │        │       │     │       │
 word run      "Cache " "once"  "\n"  "wrap " "twice"
 measured width   6        4       0      5       5
```

Spaces are stored at the end of the preceding run. Newlines become their own
zero-width run. After both cache misses, the cache can be pictured as:

```text
+----------------------------------------- TextMeasureCache -------------------------------------------+
| key                              | canonical measurement                                             |
+----------------------------------+-------------------------------------------------------------------+
| "Roc makes UI fun"               | preferred width: 16                                               |
| font=0 size=16 spacing=0         | min width: 5, space width: 1                                      |
|                                  | words: ["Roc ":4, "makes ":6, "UI ":3, "fun":3]                   |
+----------------------------------+-------------------------------------------------------------------+
| "Cache once\nwrap twice"         | preferred width: 10                                               |
| font=0 size=16 spacing=0         | min width: 5, space width: 1                                      |
|                                  | words: ["Cache ":6, "once":4, "\n":0, "wrap ":5, "twice":5]       |
+----------------------------------+-------------------------------------------------------------------+
```

Now suppose layout assigns different widths to `"Roc makes UI fun"`. `Text.wrap`
reuses the same four measured runs each time:

```text
available width = 16       available width = 10       available width = 7

+----------------+         +----------+               +-------+
|Roc makes UI fun|         |Roc makes |               |Roc    |
+----------------+         |UI fun    |               |makes  |
                           +----------+               |UI fun |
                                                      +-------+
```

Trailing spaces are removed when a line is emitted. A single word wider than
the available width is not split; it remains on one overflowing line.

The explicit newline in the second entry is always a hard break. At an
available width of 6 it produces:

```text
+------+
|Cache |
|once  |
|wrap  |
|twice |
+------+
```

No host measurement occurs during either wrapping step. A later frame using
the same text and measurement-related configuration hits the table and can
wrap the stored runs again for its newly resolved width.

## Frame-local text data

The cache is not where `Layout` stores the text that it will render.
`Layout.text_contents` and `Layout.text_lines` are separate, frame-local lists:

- `text_contents` contains one source string for every text node;
- `text_lines` contains the wrapped lines for all text nodes in one flat list.

`TextNodeData` stores ranges into those lists instead of owning strings or line
lists itself:

```text
TextNodeData
  content_index ────────────────> text_contents[content_index]
  lines_start + lines_count ────> text_lines[lines_start..(lines_start + lines_count)]
```

For example, suppose the current frame contains our two text nodes. The first
is assigned width 10 and the second width 6. After wrapping, the frame-local
data can be pictured as:

```text
Layout.text_contents
+-------+---------------------------+
| index | content                   |
+-------+---------------------------+
| 0     | "Roc makes UI fun"        |
| 1     | "Cache once\nwrap twice"  |
+-------+---------------------------+

Layout.text_lines
+-------+-------+-------+-------+------------+
| index | start | len   | width | text       |
+-------+-------+-------+-------+------------+
| 0     | 0     | 9     | 9     | "Roc makes" |
| 1     | 10    | 6     | 6     | "UI fun"   |
| 2     | 0     | 5     | 5     | "Cache"    |
| 3     | 6     | 4     | 4     | "once"     |
| 4     | 11    | 4     | 4     | "wrap"     |
| 5     | 16    | 5     | 5     | "twice"    |
+-------+-------+-------+-------+------------+

Text node 0
  content_index: 0
  lines_start:   0
  lines_count:   2

Text node 1
  content_index: 1
  lines_start:   2
  lines_count:   4
```

Each line's `start` and `len` are byte offsets into that node's source string,
not into a combined text buffer. Rendering uses `content_index` to retrieve the
source, then slices it using the node's range of line records.

Unlike `TextMeasureCache`, these lists do not survive a frame boundary.
`Layout.clear()` empties both lists because the next view may contain different
text nodes or produce different wrapped lines. The canonical measurements stay
in the cache and can be reused while rebuilding them.

## Where to look next

- `package/TextMeasureCache.roc` implements keys, lookup, insertion,
  generations, and pruning.
- `package/Text.roc` performs canonical measurement and wraps measured words.
- `package/Layout.roc` owns the cache, preserves it across frames, and uses it
  while building and solving text nodes.
