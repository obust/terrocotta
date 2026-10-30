# Sunnyland Demo Implementation Plan

## Goal

Build a polished, self-contained Sunnyland platformer vertical slice in Roc,
Terrocotta, and roc-ray. The game should use the licensed assets already under
`examples/game-sunnyland/assets`, reproduce the character of the bundled Phaser
demo, and follow the architecture and quality bar of `examples/hollow-knight`.

The finished demo should provide a complete loop:

1. title and instructions;
2. traverse the supplied Sunnyland level;
3. collect every cherry and gem while avoiding or stomping enemies;
4. return to the house door to win;
5. pause, die, win, and restart without restarting the process.

This plan deliberately adds a small objective and end state to the original
Phaser showcase, whose instruction card says that it has no objective. That
makes the example useful as a game architecture reference rather than only an
asset viewer.

The demo prioritizes breadth of game design over level-design depth. Its value
comes from showing many small, complete systems working together—not from a
long level, repeated encounters, or a large amount of authored content. The
compact Phaser level is therefore intentional.

## Reference material and decisions

- Gameplay/layout reference:
  `assets/sunny-land/game.js` and
  `assets/sunny-land/assets/maps/map.json`.
- File organization and asset-boundary reference:
  `assets/GodotProject`. Its larger `World/world.tscn` is not the gameplay
  level source for this demo.
- Art reference/source pack: `assets/Sunny-land-files/Assets`.
- Architectural reference: every Roc module in `../hollow-knight`, especially
  `main.roc`, `Game.roc`, `Knight.roc`, `Collision.roc`, `Render.roc`, and
  `UI.roc`.
- The bundled Phaser map is the level source of truth: 58 by 25 tiles, 16 px
  tiles, for a 928 by 400 px world.
- Prefer adding or completing a distinct gameplay system over extending the
  route. New level sections, repeated pickups, and repeated encounters do not
  justify delaying a complete title-to-victory loop.
- Use a fixed 288 by 192 logical view, matching the Phaser demo. Scale it by an
  integer whenever the window permits and letterbox the remainder so pixel art
  stays sharp.
- Use the existing packed `atlas.png` and `atlas-props.png`; describe only the
  frames the game needs in Roc. Do not add a runtime JSON parser just to read
  TexturePacker metadata.
- Convert the Tiled JSON into checked-in Roc data at development time. Runtime
  code must not depend on Tiled, Phaser, Godot, Python, or a JSON package.
- Gameplay is deterministic. Enemy phases, effects, camera shake, and capture
  output must not depend on random numbers or wall-clock time.
- Keyboard is the initial input target. Gamepad support is a follow-up, not a
  launch requirement.

## Scope

### Included

- Fox idle, run, crouch, rise, fall, and hurt animations.
- Horizontal movement, gravity, jump buffering, coyote time, and variable jump
  height while retaining the approximate Phaser values as the tuning baseline.
- Tile collision, including the one-way platform tile set declared by the
  Phaser reference.
- Opossum patrol/bounce behavior, periodic frog jumps, and vertically bobbing
  eagles that face the player.
- Stomp-to-defeat, bounce after a successful stomp, contact damage, knockback,
  invulnerability, three health points, and fall recovery.
- Animated cherries and gems, collection feedback, and a counter HUD.
- Parallax background and middleground, tilemap, props, sprites, and pixel-art
  presentation.
- Title, instructions, playing, paused, dead, and won states.
- Background music, pause/restart controls, deterministic effects, camera
  follow, and capture modes.
- Pure-logic expectations for collision, state transitions, collection,
  stomping, damage gating, camera clamping, and victory.
- A README with run instructions, controls, credits, and asset provenance.

### Not included in the first vertical slice

- Combat other than stomping.
- Fox roll, wall grab, climbing, dizzy, or victory sprite states.
- Moving platforms, crates, switches, doors with general-purpose scripting, or
  multiple levels.
- Save files, settings menus, localization, touch controls, or gamepad input.
- A general Tiled/TexturePacker runtime loader.
- Sound effects not present in the supplied reference demo.

## Controls

- Move: left/right arrows or `A`/`D`.
- Jump: `Space`; releasing early shortens the jump.
- Crouch: down arrow or `S` while grounded and stationary.
- Pause/resume: `Escape`.
- Confirm title/instructions: `Enter` or `Space`.
- Restart while paused, dead, or won: `R`.

The title/instruction art mentions arrow keys and Space, so those remain the
canonical controls; WASD is an accessibility convenience.

## Architecture

Keep the same boundary as Hollow Knight: impure loading/audio/input in
`main.roc`, a pure gameplay model in `Game.roc`, world-only drawing in
`Render.roc`, and responsive interface elements in `UI.roc`.

| Sunnyland module | Responsibility | Hollow Knight analogue |
| --- | --- | --- |
| `main.roc` | Terrocotta lifecycle, raw input translation, asset loading, music, event interpretation, capture flags | `main.roc` |
| `GameAssets.roc` | The only runtime asset paths and loaded handles | `GameAssets.roc` |
| `Game.roc` | Pure world/state machine and ordered frame update | `Game.roc` |
| `player/Fox.roc` | Player state, movement, animation selection, body, drawing | `Knight.roc` |
| `enemies/Enemy.roc` | Shared enemy model and dispatch across enemy kinds | `CrystalCrawler.roc` |
| `enemies/Frog.roc`, `Eagle.roc`, `Opossum.roc` | Type-specific movement, bodies, animation, and drawing | `CrystalCrawler.roc` |
| `pickups/Pickup.roc` | Cherry/gem state, animation, body, collection | part of `Game.roc` in spirit |
| `pickups/Feedback.roc` | Collection feedback animation | `Effects.roc` |
| `core/Collision.roc` | Swept rectangle and one-way platform resolution | `Collision.roc` |
| `world/Level.roc` | Authored level interface, collision geometry, spawns, goal, camera limits | `Level.roc` |
| `world/LevelData.roc` | Generated tile IDs and imported map constants | no direct analogue |
| `core/Animation.roc` | Small clip/time helper | `Animation.roc` |
| `core/SpriteSheet.roc` | Atlas frame geometry/origin helpers | `SpriteSheet.roc` |
| `world/Tiles.roc` | Named atlas/tile frames and tile rendering metadata | frame tables in `Knight.roc`/`CrystalCrawler.roc` |
| `world/Render.roc` | Letterboxed pixel view, parallax, tilemap, props, entities, effects | `Render.roc` |
| `ui/UI.roc` | HUD and title/pause/dead/won overlays | `UI.roc` |

All folders use lowercase names; Roc module filenames retain their conventional
capitalization. `core/Animation.roc`, `core/Collision.roc`, and
`core/SpriteSheet.roc` should begin as adapted copies, not imports from the
sibling example. Each example must remain independently understandable and
runnable.

The intended top-level organization is:

```text
game-sunnyland/
├── main.roc
├── Game.roc
├── GameAssets.roc
├── core/
├── player/
├── enemies/
├── pickups/
├── world/
├── ui/
├── LICENSES/
└── assets/runtime/
    ├── player/
    ├── enemies/
    ├── pickups/
    ├── world/background/
    ├── world/props/
    └── music/
```

## Core data model

`Game.World` should own only deterministic, serializable gameplay state:

- `state : [Title, Instructions, Playing, Paused, Dead, Won]`;
- `player : Fox.Model`;
- `enemies : List(Enemy.Model)`;
- `pickups : List(Pickup.Model)`;
- `effects : List(Effects.Model)`;
- `camera : Math.Vec2`;
- `elapsed : F32`;
- `collected : U64` and `total_pickups : U64`;
- short timers for hit-stop, shake, goal flash, and transition debounce.

Use stable numeric IDs for enemies and pickups. Collision/collection code must
be idempotent within a frame, and an entity that is defeated or collected must
not participate in later collision passes.

The pure update returns `(World, List(Event))`. Initial events should include:

- `GameStarted`;
- `Jumped`;
- `PickupCollected(Pickup.Kind, Math.Vec2)`;
- `EnemyStomped(Enemy.Kind, Math.Vec2)`;
- `PlayerHurt`;
- `PlayerRespawned`;
- `PlayerDied`;
- `AllPickupsCollected`;
- `WonEvent`.

Only `main.roc` may interpret events as audio requests. Render feedback is
represented in `World` so captures remain deterministic.

## Ordered frame update

Document and preserve this order in `Game.step`:

1. handle title/instructions/pause/restart state transitions;
2. clamp `dt` to at most 0.05 seconds;
3. consume active hit-stop without advancing the simulation;
4. update Fox intent, timers, velocity, and swept tile collision;
5. detect out-of-bounds/fall recovery;
6. update enemies against level collision;
7. resolve descending player/enemy overlaps as stomps;
8. resolve remaining enemy contact as player damage;
9. resolve pickups and spawn collection effects;
10. unlock/flash the house goal when all pickups are collected;
11. detect the player entering the unlocked goal;
12. update effects, camera target, shake, elapsed time, and terminal state;
13. emit events in gameplay order.

This ordering prevents the same overlap from being both a stomp and damage,
prevents collected objects from being collected twice, and makes victory lose
to death if both would otherwise happen on one frame.

## Physics and collision

Start tuning from the Phaser values: gravity 500 px/s², run speed 150 px/s,
jump impulse -170 px/s, enemy ground speed 60 px/s, frog impulse around
`(-/+100, -200)`, and stomp rebound -200 px/s. Adjust only after the exact map
is playable at the 288 by 192 logical view.

Add modest platformer forgiveness without changing the visual identity:

- coyote time: about 0.08 s;
- jump buffer: about 0.10 s;
- early-release gravity multiplier or upward velocity cut;
- acceleration/deceleration short enough to preserve the original brisk feel;
- damage invulnerability: about 0.75 s;
- respawn at the latest safe grounded position after a pit fall.

Generate collision rectangles from the map rather than testing every tile every
frame. Merge adjacent full-solid tiles into horizontal runs. Keep one-way
platform runs separate; they collide only while the body is descending and its
previous bottom was at or above the platform top. Strip Tiled flip flags before
looking up a tile GID, while retaining the flags for rendering.

Never infer collision from transparent pixels. The Phaser full-solid and
top-only GID lists are authoritative for the imported level.

## Level and objective

Reproduce the bundled Phaser placements first:

- player spawn at tile `(54, 9)`;
- cherries at `(30,5)`, `(31,5)`, `(32,5)`, `(23,17)`, `(24,17)`, `(25,17)`;
- gems at `(3,6)`, `(4,6)`, `(5,6)`, `(44,12)`, `(42,13)`, `(42,16)`;
- frogs at `(15,9)` and `(30,20)`;
- eagles at `(33,6)` and `(6,7)`;
- opossums at `(42,9)` and `(23,20)`;
- the seven decorative prop placements from `decorWorld`.

Add one explicit goal rectangle at the visible house door near tile 48. It is
decorative/locked until all 12 pickups are collected. When unlocked, the HUD
changes from the counter to “Return home”; entering it changes the state to
`Won`.

The Fox begins with three health points. Enemy contact removes one and applies
knockback. Falling below the map removes one and restores the last safe
position. Reaching zero health enters `Dead`. A successful stomp defeats the
enemy and rebounds the Fox; enemies are optional for victory.

## Rendering

Draw in this order:

1. solid letterbox color;
2. tiled `back.png` at a slow camera factor;
3. tiled `middle.png` at a medium camera factor;
4. tilemap using `tileset.png` and Tiled flip flags;
5. decorative props;
6. pickups and behind-player effects;
7. enemies;
8. Fox with invulnerability flash;
9. foreground effects and goal feedback;
10. Terrocotta HUD/overlays outside the world camera.

Use nearest-neighbor texture sampling and integer camera coordinates. Compute
zoom as the largest whole-number scale that fits the available canvas; if the
window is smaller than the logical view, fall back to fit scaling rather than
rendering nothing. Clamp the camera to the 928 by 400 world and avoid fractional
world offsets that cause pixel shimmer.

The HUD should be simple Terrocotta UI rather than new bitmap art: health,
pickup count (`n / 12`), current objective, and a compact controls hint. Title
and instruction screens should use the provided Sunnyland bitmap panels, with
Terrocotta buttons/text supplying readable confirm and restart actions.

## Assets and licensing

Create a small runtime asset directory containing only what the game loads:

- `atlas/atlas.png`;
- `atlas/atlas-props.png`;
- `environment/back.png`;
- `environment/middle.png`;
- `environment/tileset.png`;
- title/instruction/credit bitmap panels;
- `sound/platformer_level03_loop.ogg`;
- copied license/credit text.

Do not ship `.godot`, `.idea`, `.DS_Store`, PSD, Aseprite source, previews,
duplicate sprite exports, coupon files, or unrelated music as runtime content.
Keep any original source bundle outside the runtime directory until repository
policy decides whether it should be retained or ignored; do not delete it as
part of gameplay implementation.

The current itch.io page identifies the art pack as CC0:
<https://ansimuz.itch.io/sunny-land-pixel-game-art>. The music used by the
Phaser demo has a separate local license requiring appropriate credit. The
README and in-game credits must name Pascal Belisle and include the supplied
Patreon/SoundCloud references. Preserve the local license text alongside the
runtime music even though the art itself does not require attribution.

## Implementation phases

### Phase 0 — Asset manifest and import tooling

- Add `README.md` with provisional controls, source URL, and credits.
- Curate the runtime asset subset without modifying the source bundle.
- Add a small map import script and document its input/output.
- Generate `LevelData.roc` from `map.json`, including dimensions, normalized
  GIDs, flip flags, merged solid runs, and merged one-way runs.
- Transcribe/verify required TexturePacker frames into `SunnySprites.roc`.
- Add assertions in the importer for map size, tileset size/columns, known GID
  ranges, spawn bounds, and expected pickup/enemy counts.

Exit gate: the generated data is reproducible, runtime files have no absolute
paths, and every loaded asset has documented provenance.

### Phase 1 — Runnable shell and rendered world

- Implement `GameAssets.roc`, `Level.roc`, minimal `Game.roc`, `Render.roc`,
  and `main.roc` following the Hollow Knight lifecycle.
- Configure a resizable window, no implicit exit key, asset directory
  permission, uncapped pacing, and optional capture output.
- Render pixel-perfect background layers, full tilemap, props, and a clamped
  debug camera.
- Add `--capture`, `--capture-left`, and `--capture-right` positions so both
  ends and the middle of the wide level can be reviewed quickly.

Exit gate: `roc check` passes and captures show the full authored level with no
tile seams, incorrect flips, sampling blur, or camera exposure outside bounds.

### Phase 2 — Fox movement and collision

- Adapt `Animation.roc`, `SpriteSheet.roc`, and swept `Collision.roc`.
- Implement Fox model, input, motion, collision body, facing, animation, and
  drawing.
- Add full-solid and one-way platform handling, safe-position tracking, and
  camera follow.
- Add jump buffer, coyote time, variable jump, and crouch.

Exit gate: the entire map is traversable, the Fox cannot tunnel through tiles
at the maximum clamped `dt`, one-way platforms work from both directions, and
animation/camera motion remain pixel stable.

### Phase 3 — Pickups, enemies, damage, and effects

- Add animated cherry/gem models and exact reference placements.
- Add all three enemy behaviors and exact reference placements.
- Implement stomp precedence, rebound, contact damage, invulnerability,
  knockback, safe respawn, health, death, enemy-death effects, and pickup
  effects.
- Add deterministic hit-stop/shake sparingly for stomp and damage feedback.
- Emit gameplay events even if some initially have no sound effect.

Exit gate: all 12 pickups can be collected, all six enemies can be stomped,
damage cannot repeat during invulnerability, and no overlap produces both a
stomp and damage in one frame.

### Phase 4 — Complete game loop and UI

- Implement title, instructions, pause, dead, and won states.
- Add HUD, objective messaging, health, pickup count, and pointer-driven
  Resume/Restart controls using the same floating-layer approach as Hollow
  Knight.
- Unlock the house goal after all pickups and implement victory/restart.
- Start/loop music once, with a deliberate pause policy; avoid restarting it on
  every gameplay reset.
- Ensure controls do not leak through overlays or advance two states with one
  held key.

Exit gate: title-to-win and title-to-death-to-restart loops work using keyboard
and pointer controls, with no process restart and no stale entity state.

### Phase 5 — Verification and polish

- Tune movement/enemy timings against the Phaser reference.
- Add pure `expect` coverage for important invariants and edge cases.
- Run formatter/checks and play through at multiple window sizes.
- Capture title, action, damage, all-collected, dead, and won frames.
- Review captures at native pixels for blur, seams, unstable pivots, clipping,
  HUD overlap, and unreadable text.
- Finalize README controls, architecture notes, asset credits, and limitations.

Exit gate: all acceptance criteria below pass and the example can be understood
without reading the Hollow Knight source first.

## Verification matrix

Automated checks:

- `roc fmt --check examples/game-sunnyland`
- `roc check examples/game-sunnyland/main.roc`
- importer reproducibility check: regenerating `LevelData.roc` produces no diff;
- `expect` tests embedded beside pure logic.

Required pure cases:

- opposing movement keys cancel;
- jump buffer and coyote window expire at the documented times;
- full-solid collision resolves on all four sides;
- one-way platforms block only a descending body crossing their top;
- Tiled GID flip bits are removed for lookup and preserved for drawing;
- a stomp wins over contact damage and is applied once;
- invulnerability prevents repeated health loss;
- a pickup is counted once and inactive afterward;
- the goal stays locked at 11/12 and unlocks at 12/12;
- death wins over victory if both are requested in one update;
- restart recreates every initial entity and timer;
- camera clamping works at every world edge.

Manual checks:

- complete a no-damage collection run;
- intentionally collide with every enemy type from the side and above;
- fall into every open pit and verify recovery/death behavior;
- traverse every one-way platform upward and downward;
- resize between small, 16:9, ultrawide, and high-DPI windows;
- pause during jump, damage flash, collection effect, and goal unlock;
- verify music does not multiply after repeated restarts;
- verify all capture modes are deterministic across two runs.

## Completion criteria

The first vertical slice is complete when:

- it runs from the repository root with documented commands;
- it uses only curated, licensed Sunnyland runtime assets;
- the supplied map, pickup placements, enemy roster, and recognizable Phaser
  behaviors are present;
- the title/play/pause/dead/won/restart loop is complete;
- all 12 pickups can be collected and the house goal can be reached;
- rendering remains crisp and camera-safe under resizing;
- pure gameplay behavior is covered by focused expectations;
- `roc fmt --check` and `roc check` pass;
- credits satisfy the separate music license;
- no editor cache, machine-specific path, or generated capture is required to
  run the example.

## Deferred follow-ups

After the vertical slice is stable, good optional extensions are gamepad input,
Fox roll/wall interactions, additional Sunnyland music, richer sound effects,
multiple authored levels, a reusable Tiled importer, or a time/score challenge.
None should be started before the completion criteria above are met.
