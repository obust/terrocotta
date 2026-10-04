# Screwbot parity and benchmark runbook

This runbook keeps source-level assertions separate from GPU image comparison.
It records no benchmark results.

## Automated source checks

Run:

```sh
roc test examples/screwbot/main.roc
```

The `expect`s in the app and its local modules cover the deterministic scene
contract:

- `main.roc`: an unreachable target at `{ x: 500, y: 0, z: 0 }` selects the
  error/reachability shader branch and keeps its raw out-of-range floor UV;
- `main.roc`: the shader `seconds` value is pinned to `0`, so the animated floor
  ring and warning pulse hold their first frame's phase;
- `SceneCamera.roc`: projection and picking round-trip through the default
  camera orbit;
- `RobotArm.roc`: solver reachability and joint-space solution for reachable and
  unreachable targets;
- `Warehouse.roc`: layout part counts and carton dimensions;
- `SceneRenderer.roc`: an empty scene stays empty, and the empty-scene
  expectation avoids record equality so it holds without comparing GPU handles.

`Text.Metrics` has its own platform-level pure and headless tests for the
proportional `iii`/`WWW`, multibyte, newline, NUL, and font-lifetime rules. The
Screwbot renderer receives that prepared scalar snapshot; it does not implement
another text measurement algorithm.

## Current-API differences from the original port

These are deliberate, and the fixture matrix below is written against the ported
behaviour rather than the pre-migration one.

| Original | Ported | Reason |
| --- | --- | --- |
| Time advanced from a frame timestamp | `seconds` is the constant `0` | The current `Program` API exposes no per-frame timestamp and no `OnTick`; adding one would mean changing core `Event`/`Program` and forcing a relayout every frame |
| Compact layout below `1000px`, wide at `1000px` and above | Single row layout with a fixed `380`-pixel sidebar | `AppModel` no longer carries screen dimensions, and the user chose the minimal port |
| Manifest-validated asset store, `SCREWBOT_ASSET_ROOT` | `IgnoreManifest` store over `examples/assets` | See `docs/screwbot_assets.md` |
| Retained `Render.Command` list interpreted each frame | Immediate `Element.canvas` closure issuing `Draw.Frame` calls | The current renderer is immediate; there is no retained command list |

## Native visual fixture matrix

Native captures require a GPU-backed, fixed-step recording. Do not use the
host's `--headless` mode: it intentionally renders no pixels. Use the default
camera and arm `{ upper_length: 132, fore_length: 118, elbow_up: False }`.

| Fixture | Window | Target | Required observation |
| --- | --- | --- | --- |
| reachable-start | `1280 × 900` | `{145, 145, 60}` | Reachable floor ring and robot status |
| unreachable | `1280 × 900` | `{500, 0, 0}` | Raw out-of-range floor UV and error status |
| proportional-text | `1280 × 900` | `{145, 145, 60}` | `iii`, `WWW`, `é`, and a newline specimen using the UI font |

There is no longer a time-varying fixture or a compact/wide pair, because the
ported app has neither an advancing clock nor a layout breakpoint. The text
specimen is a visual fixture, not a second measurement implementation: it
verifies that layout and drawing both consume the same prepared font metrics.

The capture fixture must script the model values and window dimensions before
each frame.

For each row, capture matching images from the pre-change and candidate native
builds on the same OS, GPU, driver, framebuffer scale, and fixed-step cadence.
Hide the system pointer. Compare linearized RGBA images after removing capture
metadata. Accept at most a two-level channel difference for 99.9% of pixels and
an eight-level difference for the remaining edge pixels; any larger difference,
changed text wrapping/baseline, or changed arrangement fails the fixture.
Cross-driver captures are separate baselines, not inputs to this comparison.

## Future native benchmark record

Only collect a performance record after the matching visual fixture passes.
Warm up the same fixed-step scenario, then record a steady-state sample with
separate update and render trace ranges. Each sample must include:

- update duration and render duration;
- scene uniform writes, specifically the two resolution writes, two
  blur-direction writes, and the bloom sampler binding, plus the floor and robot
  parameter writes;
- allocations and reallocations in update and render when allocator probes are
  available.

Retained-command counts and retained command payload bytes no longer apply: the
renderer is immediate, so there is no retained command buffer to measure.

The current public API exposes none of the timing or allocator probes required
to publish those values. This repository therefore contains no native timing,
allocation, or comparative-performance result.