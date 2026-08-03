## Screwbot: an interactive inverse-kinematics workbench.
##
## The solver produces a robot pose in ordinary joint-angle space, then stores
## the mechanism as roc-ray 3D PGA points, lines, a plane, and a translation
## motor. Terracotta renders the projected geometry and exposes its live PGA
## coefficients as a small inspection console.
app [Model, program] {
    rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.8.3/E6ZmC6ZncTVFG875Xsf6jP2GuZCtLnncQ1YwVwKtT2J4.tar.zst",
    tc: "../package/main.roc",
}

import rr.Draw
import rr.Host
import rr.Physics

import tc.Color
import tc.Element exposing [Font, View, box, canvas, style, text]
import tc.Event
import tc.Program
import tc.Theme
import tc.Widget

Model : Program.State(Draw, AppModel, Msg)

AppModel : {
    theme : Theme,
    target : Physics.Point,
    upper_length : F32,
    fore_length : F32,
    elbow_up : Bool,
    show_pga : Bool,
}

Msg : [
    AimTarget(F32, F32),
    SetElbowUp(Bool),
    SetForeLength(F32),
    SetShowPga(Bool),
    SetTargetX(F32),
    SetTargetY(F32),
    SetTargetZ(F32),
    SetUpperLength(F32),
    PoseAssembly,
    PoseFolded,
    PoseReach,
]

Solution : {
    base : Physics.Point,
    elbow : Physics.Point,
    tool : Physics.Point,
    target : Physics.Point,
    target_ground : Physics.Point,
    ground : Physics.Plane,
    upper_axis : Physics.Line,
    fore_axis : Physics.Line,
    target_motor : Physics.Motor,
    base_angle : F32,
    shoulder_angle : F32,
    elbow_angle : F32,
    error : F32,
    reachable : Bool,
}

Point2 : { x : F32, y : F32 }

view_width : F32
view_width = 900

view_height : F32
view_height = 620

world_scale : F32
world_scale = 1.55

world_origin : Point2
world_origin = { x: 430, y: 500 }

ink = 0xd8e5ff.Color
muted = 0x7584a3.Color
surface = 0x111a2e.Color
surface_high = 0x18243d.Color
workspace = 0x080d19.Color
grid = 0x1a2943.Color
cyan = 0x45d7ff.Color
blue = 0x5686ff.Color
violet = 0xa478ff.Color
amber = 0xffbe55.Color
green = 0x57e389.Color
red = 0xff647c.Color
shadow = 0x03060d.Color

clamp : F32, F32, F32 -> F32
clamp = |value, lo, hi| F32.max(lo, F32.min(value, hi))

decimal : F32 -> Str
decimal = |value| {
    match F32.round_to_i64_try(value * 10) {
        Ok(scaled) => (I64.to_f32(scaled) / 10).to_str()
        Err(_) => value.to_str()
    }
}

atan2 : F32, F32 -> F32
atan2 = |y, x| {
    if x > 0 {
        F32.atan(y / x)
    } else if x < 0 and y >= 0 {
        F32.atan(y / x) + F32.pi
    } else if x < 0 {
        F32.atan(y / x) - F32.pi
    } else if y > 0 {
        F32.pi / 2
    } else if y < 0 {
        0 - F32.pi / 2
    } else {
        0
    }
}

solve : AppModel -> Solution
solve = |model| {
    target_offset = Physics.sub(model.target, Physics.origin)
    target_motor = Physics.translation(target_offset)
    target = Physics.apply_motor_point(target_motor, Physics.origin)
    target_coords = Physics.coords(target)

    radial = F32.sqrt(target_coords.x * target_coords.x + target_coords.z * target_coords.z)
    target_distance = F32.sqrt(radial * radial + target_coords.y * target_coords.y)
    max_reach = model.upper_length + model.fore_length
    min_reach = F32.abs(model.upper_length - model.fore_length)
    reachable = target_distance <= max_reach and target_distance >= min_reach

    elbow_cos = clamp(
        (target_distance * target_distance - model.upper_length * model.upper_length - model.fore_length * model.fore_length)
            / (2 * model.upper_length * model.fore_length),
        -1,
        1,
    )
    elbow_magnitude = F32.acos(elbow_cos)
    elbow_angle = if model.elbow_up { 0 - elbow_magnitude } else { elbow_magnitude }
    base_angle = atan2(target_coords.z, target_coords.x)
    shoulder_angle = atan2(target_coords.y, radial)
        - atan2(
            model.fore_length * F32.sin(elbow_angle),
            model.upper_length + model.fore_length * F32.cos(elbow_angle),
        )

    base_cos = F32.cos(base_angle)
    base_sin = F32.sin(base_angle)
    shoulder_radial = model.upper_length * F32.cos(shoulder_angle)
    elbow = Physics.point(
        shoulder_radial * base_cos,
        model.upper_length * F32.sin(shoulder_angle),
        shoulder_radial * base_sin,
    )

    tool_angle = shoulder_angle + elbow_angle
    fore_radial = model.fore_length * F32.cos(tool_angle)
    tool = Physics.add(
        elbow,
        Physics.vector(
            fore_radial * base_cos,
            model.fore_length * F32.sin(tool_angle),
            fore_radial * base_sin,
        ),
    )

    ground = Physics.plane_from_point_normal(Physics.origin, Physics.vector(0, 1, 0))

    {
        base: Physics.origin,
        elbow,
        tool,
        target,
        target_ground: Physics.project_point_plane(ground, target),
        ground,
        upper_axis: Physics.line_from_points(Physics.origin, elbow),
        fore_axis: Physics.line_from_points(elbow, tool),
        target_motor,
        base_angle,
        shoulder_angle,
        elbow_angle,
        error: Physics.distance(tool, target),
        reachable,
    }
}

project : Physics.Point -> Point2
project = |point| {
    c = Physics.coords(point)
    {
        x: world_origin.x + world_scale * (c.x - c.z * 0.45),
        y: world_origin.y - world_scale * (c.y - c.z * 0.22),
    }
}

line : Point2, Point2, F32, Color -> Element.CanvasLine
line = |start, end, thickness, color| { start, end, thickness, color }

circle : Point2, F32, Color -> Element.CanvasCircle
circle = |center, radius, color| { center, radius, color }

world_line : Physics.Point, Physics.Point, F32, Color -> Element.CanvasLine
world_line = |start, end, thickness, color| line(project(start), project(end), thickness, color)

grid_values : List(F32)
grid_values = [-240, -200, -160, -120, -80, -40, 0, 40, 80, 120, 160, 200, 240]

ground_grid : List(Element.CanvasLine)
ground_grid = {
    along_x = grid_values.map(|z| world_line(Physics.point(-260, 0, z), Physics.point(260, 0, z), 1, grid))
    along_z = grid_values.map(|x| world_line(Physics.point(x, 0, -240), Physics.point(x, 0, 240), 1, grid))
    along_x.concat(along_z)
}

axis_lines : List(Element.CanvasLine)
axis_lines = [
    world_line(Physics.origin, Physics.point(95, 0, 0), 3, red),
    world_line(Physics.origin, Physics.point(0, 95, 0), 3, green),
    world_line(Physics.origin, Physics.point(0, 0, 95), 3, blue),
]

robot_lines : Solution -> List(Element.CanvasLine)
robot_lines = |solution| {
    base_screen = project(solution.base)
    elbow_screen = project(solution.elbow)
    tool_screen = project(solution.tool)
    target_screen = project(solution.target)
    target_ground_screen = project(solution.target_ground)

    tool_vector = Physics.components(Physics.sub(solution.tool, solution.elbow))
    tool_len = F32.max(Physics.length(Physics.sub(solution.tool, solution.elbow)), 1)
    side = Physics.vector(0 - tool_vector.y / tool_len, tool_vector.x / tool_len, 0)
    finger_root = Physics.add(solution.tool, Physics.scale(side, 9))
    finger_tip = Physics.add(solution.tool, Physics.scale(side, -9))
    forward = Physics.normalize(Physics.sub(solution.tool, solution.elbow))
    finger_one = Physics.add(finger_root, Physics.scale(forward, 17))
    finger_two = Physics.add(finger_tip, Physics.scale(forward, 17))

    [
        line({ x: base_screen.x + 4, y: base_screen.y + 6 }, { x: elbow_screen.x + 4, y: elbow_screen.y + 6 }, 20, shadow),
        line({ x: elbow_screen.x + 4, y: elbow_screen.y + 6 }, { x: tool_screen.x + 4, y: tool_screen.y + 6 }, 18, shadow),
        world_line(solution.base, solution.elbow, 18, blue),
        world_line(solution.base, solution.elbow, 8, cyan),
        world_line(solution.elbow, solution.tool, 16, violet),
        world_line(solution.elbow, solution.tool, 7, amber),
        world_line(solution.target_ground, solution.target, 2, muted),
        line({ x: target_screen.x - 14, y: target_screen.y }, { x: target_screen.x + 14, y: target_screen.y }, 2, if solution.reachable { green } else { red }),
        line({ x: target_screen.x, y: target_screen.y - 14 }, { x: target_screen.x, y: target_screen.y + 14 }, 2, if solution.reachable { green } else { red }),
        world_line(finger_root, finger_one, 5, cyan),
        world_line(finger_tip, finger_two, 5, cyan),
        line(target_ground_screen, target_screen, 1, muted),
    ]
}

pga_lines : Solution -> List(Element.CanvasLine)
pga_lines = |solution| {
    if solution.reachable {
        [world_line(solution.base, solution.target, 1, Color.with_alpha(cyan, 95))]
    } else {
        [world_line(solution.tool, solution.target, 2, red)]
    }
}

robot_circles : AppModel, Solution -> List(Element.CanvasCircle)
robot_circles = |model, solution| {
    base_screen = project(solution.base)
    elbow_screen = project(solution.elbow)
    tool_screen = project(solution.tool)
    target_screen = project(solution.target)

    [
        circle(base_screen, (model.upper_length + model.fore_length) * world_scale, Color.with_alpha(cyan, 12)),
        circle(base_screen, 18, surface_high),
        circle(base_screen, 11, cyan),
        circle(elbow_screen, 15, surface_high),
        circle(elbow_screen, 8, amber),
        circle(tool_screen, 11, surface_high),
        circle(tool_screen, 6, cyan),
        circle(target_screen, 6, if solution.reachable { green } else { red }),
    ]
}

target_from_pointer : Event.PointerEvent, Physics.Point -> { x : F32, y : F32 }
target_from_pointer = |event, current_target| {
    relative = Event.ElementBounds.relative(event.target.bounds, event.position)
    scale_x = event.target.bounds.width / view_width
    scale_y = event.target.bounds.height / view_height
    canvas_scale = F32.max(F32.min(scale_x, scale_y), 0.001)
    offset_x = (event.target.bounds.width - view_width * canvas_scale) * 0.5
    offset_y = (event.target.bounds.height - view_height * canvas_scale) * 0.5
    screen_x = (relative.x - offset_x) / canvas_scale
    screen_y = (relative.y - offset_y) / canvas_scale
    z = Physics.coords(current_target).z
    {
        x: clamp((screen_x - world_origin.x) / world_scale + z * 0.45, -230, 230),
        y: clamp((world_origin.y - screen_y) / world_scale + z * 0.22, 5, 285),
    }
}

workspace_view : AppModel, Solution -> View(Msg)
workspace_view = |model, solution| {
    lines = ground_grid.concat(axis_lines).concat(robot_lines(solution))
    all_lines = if model.show_pga { lines.concat(pga_lines(solution)) } else { lines }

    box(
        Id("screwbot-workspace"),
        |status| style
            .width(Grow({ min: 420, max: 10000 }))
            .height(Grow({ min: 420, max: 10000 }))
            .background(if status.hovered { workspace.lighten(3) } else { workspace })
            .radius(14)
            .border({ color: if status.focused { cyan } else { grid }, left: 1, right: 1, top: 1, bottom: 1 }),
        [
            OnPointer(
                Box.box(
                    |event| {
                        if event.buttons.left.down or event.buttons.left.pressed {
                            aim = target_from_pointer(event, model.target)
                            [AimTarget(aim.x, aim.y)]
                        } else {
                            []
                        }
                    },
                ),
            ),
        ],
        [
            canvas({
                width: Grow({ min: 0, max: 10000 }),
                height: Grow({ min: 0, max: 10000 }),
                view_width,
                view_height,
                lines: all_lines,
                circles: robot_circles(model, solution),
            }),
        ],
    )
}

# Keep dynamic children separate from the model-capturing card style. Combining
# those in one helper currently triggers roc-lang/roc#10560 during codegen.
content_stack : List(View(msg)) -> View(msg)
content_stack = |children| {
    box(
        Auto,
        |_| style
            .width(Grow({ min: 0, max: 10000 }))
            .height(Fit({ min: 0, max: 10000 }))
            .gap(10)
            .direction(Col)
            .child_align({ x: Start, y: Start }),
        [],
        children,
    )
}

card : AppModel, Str, View(Msg) -> View(Msg)
card = |model, title, content| {
    title_view = box(
        Auto,
        |_| style
            .width(Grow({ min: 0, max: 10000 }))
            .height(Fit({ min: 0, max: 10000 }))
            .font_color(cyan)
            .font_size(15)
            .spacing(2),
        [],
        [text(title)],
    )

    box(
        Auto,
        |_| style
            .width(Grow({ min: 0, max: 10000 }))
            .height(Fit({ min: 0, max: 10000 }))
            .background(surface)
            .radius(12)
            .border({ color: grid, left: 1, right: 1, top: 1, bottom: 1 })
            .pad((14, 14, 12, 12))
            .gap(10)
            .direction(Col)
            .child_align({ x: Start, y: Start })
            .font_family(model.theme.font)
            .font_size(16)
            .font_color(ink),
        [],
        [title_view, content],
    )
}

readout : Str, Str, Color -> View(Msg)
readout = |name, value, color| {
    box(
        Auto,
        |_| style
            .width(Grow({ min: 0, max: 10000 }))
            .height(Fit({ min: 0, max: 10000 }))
            .direction(Row)
            .child_align({ x: Start, y: Center })
            .font_size(16),
        [],
        [
            box(Auto, |_| style.width(Grow({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).font_size(16).font_color(muted), [], [text(name)]),
            box(Auto, |_| style.width(Fit({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).font_size(16).font_color(color), [], [text(value)]),
        ],
    )
}

control : AppModel, Str, F32, F32, F32, F32, (F32 -> Msg) -> View(Msg)
control = |model, name, value, min, max, step, on_change| {
    box(
        Auto,
        |_| style
            .width(Grow({ min: 0, max: 10000 }))
            .height(Fit({ min: 0, max: 10000 }))
            .gap(7)
            .direction(Col)
            .child_align({ x: Start, y: Start }),
        [],
        [
            readout(name, decimal(value), ink),
            Widget.slider(model.theme, value, min, max, step, on_change),
        ],
    )
}

degrees : F32 -> F32
degrees = |radians| radians * 180 / F32.pi

pga_inspector : AppModel, Solution -> View(Msg)
pga_inspector = |model, solution| {
    target = Physics.point_coeffs(solution.target)
    upper = Physics.line_coeffs(solution.upper_axis)
    motor = Physics.motor_coeffs(solution.target_motor)
    plane = Physics.plane_coeffs(solution.ground)

    card(
        model,
        "PGA LIVE COEFFICIENTS",
        content_stack([
            readout("P target 032/013/021", "${decimal(target.e032)}  ${decimal(target.e013)}  ${decimal(target.e021)}", green),
            readout("L upper 23/31/12", "${decimal(upper.e23)}  ${decimal(upper.e31)}  ${decimal(upper.e12)}", blue),
            readout("T motor 01/02/03", "${decimal(motor.e01)}  ${decimal(motor.e02)}  ${decimal(motor.e03)}", cyan),
            readout("plane 0/1/2/3", "${decimal(plane.e0)}  ${decimal(plane.e1)}  ${decimal(plane.e2)}  ${decimal(plane.e3)}", green),
        ]),
    )
}

sidebar : AppModel, Solution -> View(Msg)
sidebar = |model, solution| {
    target = Physics.coords(model.target)
    state_color = if solution.reachable { green } else { red }
    state_label = if solution.reachable { "SOLVED" } else { "OUT OF REACH" }

    box(
        Auto,
        |_| style
            .width(Fixed(380))
            .height(Grow({ min: 0, max: 10000 }))
            .gap(12)
            .direction(Col)
            .overflow(Hidden, Scroll)
            .child_align({ x: Start, y: Start }),
        [],
        [
            card(
                model,
                "SOLVER STATUS",
                content_stack([
                    readout("state", state_label, state_color),
                    readout("tool error", "${decimal(solution.error)} mm", state_color),
                    readout("base yaw", "${decimal(degrees(solution.base_angle))} deg", ink),
                    readout("shoulder", "${decimal(degrees(solution.shoulder_angle))} deg", ink),
                    readout("elbow", "${decimal(degrees(solution.elbow_angle))} deg", ink),
                ]),
            ),
            card(
                model,
                "TARGET / DRAG IN VIEWPORT",
                content_stack([
                    control(model, "X", target.x, -230, 230, 1, |value| SetTargetX(value)),
                    control(model, "Y", target.y, 5, 285, 1, |value| SetTargetY(value)),
                    control(model, "Z", target.z, -160, 160, 1, |value| SetTargetZ(value)),
                ]),
            ),
            card(
                model,
                "ARM CONFIGURATION",
                content_stack([
                    control(model, "upper link", model.upper_length, 60, 170, 1, |value| SetUpperLength(value)),
                    control(model, "fore link", model.fore_length, 60, 170, 1, |value| SetForeLength(value)),
                    Widget.checkbox(model.theme, model.elbow_up, "Elbow-up branch", |checked| SetElbowUp(checked)),
                    Widget.checkbox(model.theme, model.show_pga, "Show PGA construction", |checked| SetShowPga(checked)),
                ]),
            ),
            if model.show_pga { pga_inspector(model, solution) } else { [].iter() },
        ],
    )
}

header : AppModel, Solution -> View(Msg)
header = |model, solution| {
    status_color = if solution.reachable { green } else { red }

    box(
        Auto,
        |_| style
            .width(Grow({ min: 0, max: 10000 }))
            .height(Fixed(92))
            .background(surface)
            .border({ color: grid, left: 0, right: 0, top: 0, bottom: 1 })
            .pad((20, 20, 12, 12))
            .gap(14)
            .direction(Row)
            .child_align({ x: Start, y: Center })
            .font_family(model.theme.font)
            .font_color(ink),
        [],
        [
            box(
                Auto,
                |_| style.width(Fit({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).direction(Col).gap(2).child_align({ x: Start, y: Start }),
                [],
                [
                    box(Auto, |_| style.width(Fit({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).font_size(30).font_color(cyan), [], [text("SCREWBOT // PGA LAB")]),
                    box(Auto, |_| style.width(Fit({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).font_size(15).font_color(muted), [], [text("3D inverse kinematics, inspectable geometric algebra")]),
                ],
            ),
            box(Auto, |_| style.width(Grow({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })), [], []),
            Widget.badge(model.theme, if solution.reachable { Success } else { Danger }, if solution.reachable { "TARGET LOCK" } else { "LIMIT" }),
            Widget.button(model.theme, Secondary, "ASSEMBLY", [OnClick(PoseAssembly)]),
            Widget.button(model.theme, Secondary, "FOLDED", [OnClick(PoseFolded)]),
            Widget.button(model.theme, Primary, "LONG REACH", [OnClick(PoseReach)]),
            circle_status(status_color),
        ],
    )
}

circle_status : Color -> View(Msg)
circle_status = |color| {
    box(
        Auto,
        |_| style.width(Fixed(10)).height(Fixed(10)).background(color).radius(100),
        [],
        [],
    )
}

view : AppModel -> View(Msg)
view = |model| {
    solution = solve(model)

    box(
        Auto,
        |_| style
            .background(0x0a1020.Color)
            .direction(Col)
            .child_align({ x: Start, y: Start })
            .font_family(model.theme.font)
            .font_size(17)
            .font_color(ink),
        [],
        [
            header(model, solution),
            box(
                Auto,
                |_| style
                    .width(Grow({ min: 0, max: 10000 }))
                    .height(Grow({ min: 0, max: 10000 }))
                    .pad((16, 16, 16, 16))
                    .gap(16)
                    .direction(Row)
                    .child_align({ x: Start, y: Start }),
                [],
                [
                    workspace_view(model, solution),
                    sidebar(model, solution),
                ],
            ),
        ],
    )
}

update : AppModel, Msg -> AppModel
update = |model, msg| {
    target = Physics.coords(model.target)

    match msg {
        AimTarget(x, y) => { ..model, target: Physics.point(x, y, target.z) }
        SetTargetX(x) => { ..model, target: Physics.point(x, target.y, target.z) }
        SetTargetY(y) => { ..model, target: Physics.point(target.x, y, target.z) }
        SetTargetZ(z) => { ..model, target: Physics.point(target.x, target.y, z) }
        SetUpperLength(length) => { ..model, upper_length: length }
        SetForeLength(length) => { ..model, fore_length: length }
        SetElbowUp(elbow_up) => { ..model, elbow_up }
        SetShowPga(show_pga) => { ..model, show_pga }
        PoseAssembly => { ..model, target: Physics.point(105, 155, 75) }
        PoseFolded => { ..model, target: Physics.point(65, 45, -55), elbow_up: True }
        PoseReach => { ..model, target: Physics.point(205, 105, 35), elbow_up: False }
    }
}

font_path : Str
font_path = "examples/assets/Inter-Regular.ttf"

init! : Program.Config => Try(AppModel, [Exit(I64)])
init! = |_config| {
    font = Draw.load_font!({ path: font_path, size: 32 }).map_err(|_| Exit(1))?
    Ok({
        theme: { ..Theme.dark, font, font_size: 16, radius: 7, gap: 9 },
        target: Physics.point(145, 145, 60),
        upper_length: 132,
        fore_length: 118,
        elbow_up: False,
        show_pga: True,
    })
}

program : {
    init! : { config : Program.Config, run! : Host => Try(Model, [Exit(I64)]) },
    render! : Model, Host => Try(Model, [Exit(I64), ..]),
}
program = Program.new!(
    {
        config: {
            ..Program.default,
            title: "Screwbot // PGA Kinematics Lab",
            width: 1280,
            height: 900,
            target_fps: 120,
            vsync: True,
        },
        init!,
        view,
        update,
    },
)
