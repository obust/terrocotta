# Screwbot

Screwbot is an interactive inverse-kinematics workbench. It renders a two-link
robot arm in a warehouse and exposes the arm pose, target, and PGA values in a
small control interface.

Run it with:

```sh
roc --no-cache examples/screwbot/main.roc
```

## File structure

```text
examples/screwbot/
  main.roc                 application startup and top-level UI composition
  assets/                   material textures and floor/robot shader sources
  scene/
    Scene.roc              durable workspace state, message routing, and frame orchestration
    Camera.roc             orbit camera state, projection, and pointer unprojection
    Drawing.roc            reusable immediate-mode scene primitives
    FloorMaterial.roc      floor shader program, uniform bindings, and frame inputs
    RobotMaterial.roc      robot shader program, uniform bindings, and frame inputs
    Robot.roc              robot-arm state, rendering, and derived render state
    RobotKinematics.roc    inverse-kinematics solver and PGA construction
    Warehouse.roc          warehouse assets and static environment rendering
  ui/
    Utils.roc              reusable Screwbot-styled UI building blocks
    Inspector.roc          target, arm, and PGA controls
    Topbar.roc             title and demo slogan
    Viewport.roc           pointer input and canvas presentation
```

`ui/` emits scene messages but does not mutate scene state. `scene/` owns the
interactive 3D workspace: its state, camera, inverse kinematics, and drawing.
`main.roc` loads resources and maps UI-local messages into the app's top-level
message type.

## Third-Party Assets

The following Screwbot material textures are provided by
[Poly Haven](https://polyhaven.com/) under the
[CC0 1.0 license](https://creativecommons.org/publicdomain/zero/1.0/).
Attribution is not required, but is included here to preserve provenance.

| Local file                                  | Asset                                  | Author             | Source                                        |
| ------------------------------------------- | -------------------------------------- | ------------------ | --------------------------------------------- |
| `screwbot-wall.png`       | Corrugated Iron 03, 1K diffuse PNG     | Charlotte Baglioni | https://polyhaven.com/a/corrugated_iron_03    |
| `screwbot-floor.png`      | Hangar Concrete Floor, 1K diffuse PNG  | Dimitrios Savva    | https://polyhaven.com/a/hangar_concrete_floor |
| `screwbot-crate-v2.png`   | Cardboard Box 01 model, 1K diffuse PNG | Rahul Chaudhary    | https://polyhaven.com/a/cardboard_box_01      |

Screwbot samples a clean rectangular portion of the Cardboard Box model's
diffuse atlas at runtime, then draws its own projected seams and tape. The
original texture file is otherwise unmodified.

Direct downloads:

- https://dl.polyhaven.org/file/ph-assets/Textures/png/1k/corrugated_iron_03/corrugated_iron_03_diff_1k.png
- https://dl.polyhaven.org/file/ph-assets/Textures/png/1k/hangar_concrete_floor/hangar_concrete_floor_diff_1k.png
- https://dl.polyhaven.org/file/ph-assets/Models/png/1k/cardboard_box_01/cardboard_box_01_diff_1k.png
