# Screwbot

Screwbot is an interactive inverse-kinematics workbench. It renders a two-link
robot arm in a warehouse and exposes the arm pose, target, and PGA values in a
small control interface.

## File structure

```text
examples/screwbot/
  main.roc                 application startup and top-level UI composition
  scene/
    Scene.roc              durable workspace state, message routing, and frame orchestration
    Camera.roc             orbit camera state, projection, and pointer unprojection
    Drawing.roc            reusable immediate-mode scene primitives
    FloorMaterial.roc      floor shader program, uniform bindings, and frame inputs
    RobotMaterial.roc      robot shader program, uniform bindings, and frame inputs
    Robot.roc              robot-arm state, rendering, and shader inputs
    RobotKinematics.roc    inverse-kinematics solver and PGA construction
    Warehouse.roc          warehouse assets and static environment rendering
  ui/
    Utils.roc              reusable Screwbot-styled UI building blocks
    Inspector.roc          target, arm, and PGA controls
    Topbar.roc             title, status, and pose controls
    Viewport.roc           pointer input and canvas presentation
```

`ui/` emits scene messages but does not mutate scene state. `scene/` owns the
interactive 3D workspace: its state, camera, inverse kinematics, assets, and
drawing. `main.roc` loads resources and maps UI-local messages into the app's
top-level message type.
