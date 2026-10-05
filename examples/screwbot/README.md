# Screwbot

Screwbot is an interactive inverse-kinematics workbench. It renders a two-link
robot arm in a warehouse and exposes the arm pose, target, and PGA values in a
small control interface.

## File structure

```text
examples/screwbot/
  main.roc                 application startup and top-level UI composition
  Palette.roc              shared visual palette
  scene/
    Scene.roc              durable workspace state, message routing, and frame orchestration
    Camera.roc             orbit camera state, projection, and pointer unprojection
    Drawing.roc            reusable immediate-mode scene primitives and GPU materials
    Robot.roc              robot-arm configuration and inverse-kinematics solver
    RobotRenderer.roc      robot assets, visual primitives, and robot rendering
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
