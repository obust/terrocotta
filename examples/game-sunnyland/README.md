# Terrocotta: Sunnyland

Sunnyland is a planned 2D platformer vertical slice built with Terrocotta and
roc-ray. It follows the pure gameplay architecture of the neighboring
`examples/hollow-knight` demo while using the SunnyLand pixel-art pack and its
bundled Phaser showcase as the visual and level reference.

The target loop is to explore the supplied level, collect all six cherries and
six gems, avoid or stomp its frogs, eagles, and opossums, then return to the
house door. The finished example will include title, instructions, pause,
death, victory, and restart states.

This demo intentionally favors gameplay breadth over level size. The compact
Phaser level supplies the layout and placements, the Godot project inspires the
feature-oriented file organization, and `examples/hollow-knight` supplies the
pure gameplay architecture. The implementation budget goes toward complete
movement, enemy, collection, damage, objective, UI, audio, feedback, and state
systems rather than a longer route with repeated content.

## Status

The first playable vertical slice is implemented. Runtime assets are curated
under `assets/runtime/`; the source/reference bundles remain under `assets/`.
The pure simulation owns title, instructions, play, pause, death, victory,
pickup collection, stomp precedence, damage invulnerability, respawn, camera
clamping, and restart behavior.

## Planned run commands

Use Terrocotta's pinned Roc nightly (`nightly-2026-10-03-c507926`) and run from
the repository root:

```sh
roc check examples/game-sunnyland/main.roc
roc examples/game-sunnyland/main.roc
roc examples/game-sunnyland/main.roc -- --capture
```

Capture output is written beneath the repository's ignored `captures/`
directory. `tools/import_map.py` regenerates the checked-in map metadata from
the bundled Phaser map; runtime code does not parse JSON.

## Planned controls

- Move: left/right arrows or `A`/`D`
- Jump: `Space`; release early for a shorter jump
- Crouch: down arrow or `S` while grounded
- Confirm title/instructions: `Enter` or `Space`
- Pause/resume: `Escape`
- Restart while paused, dead, or victorious: `R`

## Planned architecture

- `main.roc` will own the Terrocotta lifecycle, input translation, asset
  loading, music playback, and interpretation of pure gameplay events.
- `Game.roc` will own the deterministic world and ordered update pipeline.
- Lowercase feature folders—`player/`, `enemies/`, `pickups/`, `world/`, and
  `ui/`—will group behavior in the same domain-oriented spirit as the bundled
  Godot project.
- `player/Fox.roc`, the modules under `enemies/`, and
  `pickups/Pickup.roc` will own entity behavior and animation.
- `world/Level.roc` and generated `world/LevelData.roc` will expose the
  imported level, collision geometry, spawns, and goal.
- `world/Render.roc` will draw a fixed pixel-art view with parallax and an
  integer-scaled, clamped camera.
- `ui/UI.roc` will provide the HUD and responsive
  title/pause/death/victory layers.

See [PLAN.md](PLAN.md) for the complete design and verification matrix.

## Assets and credits

SunnyLand artwork is by **ansimuz (Luis Zuno)** and comes from
[SunnyLand – Free Pixel Game Art Assets Pack](https://ansimuz.itch.io/sunny-land-pixel-game-art).
The asset page identifies the art pack as licensed under
[CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/).
Attribution is not required by CC0, but is included here in appreciation of the
creator.

The planned background track, `platformer_level03_loop.ogg`, is by
**Pascal Belisle**. Its bundled license permits project use with appropriate
credit. Pascal's supplied links are:

- <https://www.patreon.com/thetoadz>
- <https://www.soundcloud.com/thetoadz>

The artwork and music do not share the same license. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the preserved
[music license](LICENSES/Pascal-Belisle-Music.txt) before redistributing the
example or its assets.

The downloaded Godot and Phaser projects, source artwork, previews, editor
caches, and unrelated music under `assets/` are source/reference material.
They are not all intended to become runtime or distribution content.
