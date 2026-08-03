## Screwbot: an interactive inverse-kinematics workbench.
##
## The solver produces a robot pose in ordinary joint-angle space, then stores
## the mechanism as roc-ray 3D PGA points, lines, a plane, and a translation
## motor. Terracotta renders the projected geometry and exposes its live PGA
## coefficients as a small inspection console.
app [Model, program] {
    rr: platform "../../roc-ray/platform/main-default.roc",
    tc: "../package/main.roc",
}

import rr.Draw
import rr.Host
import rr.Physics
import rr.Assets

import tc.Color
import tc.Element exposing [Font, View, box, canvas, style, text]
import tc.Event
import tc.Program
import tc.Theme
import tc.Widget

Model : Program.State(Draw, AppModel, Msg)

AppModel : {
    theme : Theme,
    floor_texture : Assets.Texture,
    wall_texture : Assets.Texture,
    white_texture : Assets.Texture,
    target : Physics.Point,
    upper_length : F32,
    fore_length : F32,
    elbow_up : Bool,
    show_pga : Bool,
    camera_yaw : F32,
    camera_pitch : F32,
    orbit : [OrbitIdle, Orbiting(Point2)],
}

Msg : [
    AimTarget3D(F32, F32, F32),
    OrbitEnd,
    OrbitMove(F32, F32),
    OrbitStart(F32, F32),
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

OrbitCamera : { yaw : F32, pitch : F32 }

CameraBasis : {
    right : Physics.Vector,
    up : Physics.Vector,
    forward : Physics.Vector,
}

ProjectedFace : {
    depth : F32,
    top_left : Point2,
    bottom_left : Point2,
    bottom_right : Point2,
    top_right : Point2,
    tint : Color,
}

AxisLabel : [XAxis, YAxis, ZAxis]

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

camera_basis : OrbitCamera -> CameraBasis
camera_basis = |camera| {
    sin_yaw = F32.sin(camera.yaw)
    cos_yaw = F32.cos(camera.yaw)
    sin_pitch = F32.sin(camera.pitch)
    cos_pitch = F32.cos(camera.pitch)

    {
        right: Physics.vector(cos_yaw, 0, 0 - sin_yaw),
        up: Physics.vector(0 - sin_yaw * sin_pitch, cos_pitch, 0 - cos_yaw * sin_pitch),
        forward: Physics.vector(sin_yaw * cos_pitch, sin_pitch, cos_yaw * cos_pitch),
    }
}

camera_for : AppModel -> OrbitCamera
camera_for = |model| { yaw: model.camera_yaw, pitch: model.camera_pitch }

project : OrbitCamera, Physics.Point -> Point2
project = |camera, point| {
    c = Physics.coords(point)
    basis = camera_basis(camera)
    right = Physics.components(basis.right)
    up = Physics.components(basis.up)
    {
        x: world_origin.x + world_scale * (c.x * right.x + c.y * right.y + c.z * right.z),
        y: world_origin.y - world_scale * (c.x * up.x + c.y * up.y + c.z * up.z),
    }
}

camera_depth : OrbitCamera, Physics.Point -> F32
camera_depth = |camera, point| {
    c = Physics.coords(point)
    forward = Physics.components(camera_basis(camera).forward)
    c.x * forward.x + c.y * forward.y + c.z * forward.z
}

line : Point2, Point2, F32, Color -> Element.CanvasLine
line = |start, end, thickness, color| { start, end, thickness, color }

circle : Point2, F32, Color -> Element.CanvasCircle
circle = |center, radius, color| { center, radius, color }

world_line : OrbitCamera, Physics.Point, Physics.Point, F32, Color -> Element.CanvasLine
world_line = |camera, start, end, thickness, color| line(project(camera, start), project(camera, end), thickness, color)

grid_values : List(F32)
grid_values = [-240, -200, -160, -120, -80, -40, 0, 40, 80, 120, 160, 200, 240]

ground_grid : OrbitCamera -> List(Element.CanvasLine)
ground_grid = |camera| {
    along_x = grid_values.map(|z| world_line(camera, Physics.point(-260, 0, z), Physics.point(260, 0, z), 1, grid))
    along_z = grid_values.map(|x| world_line(camera, Physics.point(x, 0, -240), Physics.point(x, 0, 240), 1, grid))
    along_x.concat(along_z)
}

axis_letter : AxisLabel, Point2, Color -> List(Element.CanvasLine)
axis_letter = |label, center, color| {
    left = center.x - 5
    right = center.x + 5
    top = center.y - 7
    middle = center.y
    bottom = center.y + 7

    match label {
        XAxis => [
            line({ x: left, y: top }, { x: right, y: bottom }, 2.5, color),
            line({ x: right, y: top }, { x: left, y: bottom }, 2.5, color),
        ]
        YAxis => [
            line({ x: left, y: top }, { x: center.x, y: middle }, 2.5, color),
            line({ x: right, y: top }, { x: center.x, y: middle }, 2.5, color),
            line({ x: center.x, y: middle }, { x: center.x, y: bottom }, 2.5, color),
        ]
        ZAxis => [
            line({ x: left, y: top }, { x: right, y: top }, 2.5, color),
            line({ x: right, y: top }, { x: left, y: bottom }, 2.5, color),
            line({ x: left, y: bottom }, { x: right, y: bottom }, 2.5, color),
        ]
    }
}

axis_with_label : OrbitCamera, Physics.Point, AxisLabel, Color -> List(Element.CanvasLine)
axis_with_label = |camera, end_world, label, color| {
    start = project(camera, Physics.origin)
    end = project(camera, end_world)
    dx = end.x - start.x
    dy = end.y - start.y
    length = F32.max(F32.sqrt(dx * dx + dy * dy), 1)
    unit_x = dx / length
    unit_y = dy / length
    wing = {
        x: end.x - unit_x * 13,
        y: end.y - unit_y * 13,
    }
    left_wing = {
        x: wing.x - unit_y * 6,
        y: wing.y + unit_x * 6,
    }
    right_wing = {
        x: wing.x + unit_y * 6,
        y: wing.y - unit_x * 6,
    }
    label_center = {
        x: end.x + unit_x * 22,
        y: end.y + unit_y * 22,
    }

    [
        line(start, end, 4, color),
        line(end, left_wing, 4, color),
        line(end, right_wing, 4, color),
    ].concat(axis_letter(label, label_center, color))
}

axis_lines : OrbitCamera -> List(Element.CanvasLine)
axis_lines = |camera| axis_with_label(camera, Physics.point(125, 0, 0), XAxis, red)
    .concat(axis_with_label(camera, Physics.point(0, 125, 0), YAxis, green))
    .concat(axis_with_label(camera, Physics.point(0, 0, 125), ZAxis, blue))

robot_lines : OrbitCamera, Solution -> List(Element.CanvasLine)
robot_lines = |camera, solution| {
    target_screen = project(camera, solution.target)
    target_ground_screen = project(camera, solution.target_ground)

    tool_vector = Physics.components(Physics.sub(solution.tool, solution.elbow))
    tool_len = F32.max(Physics.length(Physics.sub(solution.tool, solution.elbow)), 1)
    side = Physics.vector(0 - tool_vector.y / tool_len, tool_vector.x / tool_len, 0)
    finger_root = Physics.add(solution.tool, Physics.scale(side, 9))
    finger_tip = Physics.add(solution.tool, Physics.scale(side, -9))
    forward = Physics.normalize(Physics.sub(solution.tool, solution.elbow))
    finger_one = Physics.add(finger_root, Physics.scale(forward, 17))
    finger_two = Physics.add(finger_tip, Physics.scale(forward, 17))

    [
        world_line(camera, shadow_on_ground(solution.base), shadow_on_ground(solution.elbow), 22, Color.with_alpha(shadow, 150)),
        world_line(camera, shadow_on_ground(solution.elbow), shadow_on_ground(solution.tool), 19, Color.with_alpha(shadow, 140)),
        world_line(camera, solution.base, solution.elbow, 18, blue),
        world_line(camera, solution.base, solution.elbow, 8, cyan),
        world_line(camera, solution.elbow, solution.tool, 16, violet),
        world_line(camera, solution.elbow, solution.tool, 7, amber),
        world_line(camera, solution.target_ground, solution.target, 2, muted),
        line({ x: target_screen.x - 14, y: target_screen.y }, { x: target_screen.x + 14, y: target_screen.y }, 2, if solution.reachable { green } else { red }),
        line({ x: target_screen.x, y: target_screen.y - 14 }, { x: target_screen.x, y: target_screen.y + 14 }, 2, if solution.reachable { green } else { red }),
        world_line(camera, finger_root, finger_one, 5, cyan),
        world_line(camera, finger_tip, finger_two, 5, cyan),
        line(target_ground_screen, target_screen, 1, muted),
    ]
}

pga_lines : OrbitCamera, Solution -> List(Element.CanvasLine)
pga_lines = |camera, solution| {
    if solution.reachable {
        [world_line(camera, solution.base, solution.target, 1, Color.with_alpha(cyan, 95))]
    } else {
        [world_line(camera, solution.tool, solution.target, 2, red)]
    }
}

shadow_on_ground : Physics.Point -> Physics.Point
shadow_on_ground = |point| {
    c = Physics.coords(point)
    Physics.point(c.x + c.y * 0.22, 1, c.z + c.y * 0.16)
}

robot_circles : AppModel, OrbitCamera, Solution -> List(Element.CanvasCircle)
robot_circles = |model, camera, solution| {
    base_screen = project(camera, solution.base)
    elbow_screen = project(camera, solution.elbow)
    tool_screen = project(camera, solution.tool)
    target_screen = project(camera, solution.target)

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

target_from_pointer : Event.PointerEvent, Physics.Point, OrbitCamera -> Physics.Point
target_from_pointer = |event, current_target, camera| {
    relative = Event.ElementBounds.relative(event.target.bounds, event.position)
    scale_x = event.target.bounds.width / view_width
    scale_y = event.target.bounds.height / view_height
    canvas_scale = F32.max(F32.min(scale_x, scale_y), 0.001)
    offset_x = (event.target.bounds.width - view_width * canvas_scale) * 0.5
    offset_y = (event.target.bounds.height - view_height * canvas_scale) * 0.5
    screen_x = (relative.x - offset_x) / canvas_scale
    screen_y = (relative.y - offset_y) / canvas_scale
    u = (screen_x - world_origin.x) / world_scale
    v = (world_origin.y - screen_y) / world_scale
    basis = camera_basis(camera)
    right = Physics.components(basis.right)
    up = Physics.components(basis.up)
    forward = Physics.components(basis.forward)
    depth = camera_depth(camera, current_target)

    Physics.point(
        clamp(right.x * u + up.x * v + forward.x * depth, -230, 230),
        clamp(right.y * u + up.y * v + forward.y * depth, 5, 285),
        clamp(right.z * u + up.z * v + forward.z * depth, -190, 190),
    )
}

projected_face : OrbitCamera, Physics.Point, Physics.Point, Physics.Point, Physics.Point, Color -> ProjectedFace
projected_face = |camera, top_left, bottom_left, bottom_right, top_right, tint| {
    {
        depth: (camera_depth(camera, top_left) + camera_depth(camera, bottom_left) + camera_depth(camera, bottom_right) + camera_depth(camera, top_right)) / 4,
        top_left: project(camera, top_left),
        bottom_left: project(camera, bottom_left),
        bottom_right: project(camera, bottom_right),
        top_right: project(camera, top_right),
        tint,
    }
}

cuboid_faces : OrbitCamera, { min_x : F32, min_y : F32, min_z : F32, max_x : F32, max_y : F32, max_z : F32 }, Color -> List(ProjectedFace)
cuboid_faces = |camera, bounds, color| {
    p000 = Physics.point(bounds.min_x, bounds.min_y, bounds.min_z)
    p001 = Physics.point(bounds.min_x, bounds.min_y, bounds.max_z)
    p010 = Physics.point(bounds.min_x, bounds.max_y, bounds.min_z)
    p011 = Physics.point(bounds.min_x, bounds.max_y, bounds.max_z)
    p100 = Physics.point(bounds.max_x, bounds.min_y, bounds.min_z)
    p101 = Physics.point(bounds.max_x, bounds.min_y, bounds.max_z)
    p110 = Physics.point(bounds.max_x, bounds.max_y, bounds.min_z)
    p111 = Physics.point(bounds.max_x, bounds.max_y, bounds.max_z)

    [
        projected_face(camera, p010, p011, p111, p110, Color.lighten(color, 38)),
        projected_face(camera, p011, p001, p101, p111, Color.lighten(color, 8)),
        projected_face(camera, p010, p000, p001, p011, Color.darken(color, 30)),
        projected_face(camera, p110, p100, p101, p111, Color.lighten(color, 18)),
        projected_face(camera, p010, p000, p100, p110, Color.darken(color, 12)),
        projected_face(camera, p001, p000, p100, p101, Color.darken(color, 45)),
    ]
}

warehouse_faces : AppModel, OrbitCamera -> List(Element.CanvasTextureQuad)
warehouse_faces = |model, camera| {
    steel = 0x263650.Color
    beam = 0x35445d.Color
    crate = 0x9a6635.Color
    pallet = 0x574634.Color

    light_pool = projected_face(
        camera,
        Physics.point(-185, 0.5, -165),
        Physics.point(-215, 0.5, 80),
        Physics.point(100, 0.5, 80),
        Physics.point(70, 0.5, -165),
        Color.with_alpha(cyan, 15),
    )
    safety_zone = projected_face(
        camera,
        Physics.point(-92, 0.8, -78),
        Physics.point(-92, 0.8, 78),
        Physics.point(92, 0.8, 78),
        Physics.point(92, 0.8, -78),
        Color.with_alpha(amber, 18),
    )

    faces = [light_pool, safety_zone]
        .concat(cuboid_faces(camera, { min_x: -242, min_y: 0, min_z: -224, max_x: -222, max_y: 260, max_z: -204 }, beam))
        .concat(cuboid_faces(camera, { min_x: 222, min_y: 0, min_z: -224, max_x: 242, max_y: 260, max_z: -204 }, beam))
        .concat(cuboid_faces(camera, { min_x: -238, min_y: 238, min_z: -220, max_x: 238, max_y: 256, max_z: -204 }, steel))
        .concat(cuboid_faces(camera, { min_x: -238, min_y: 238, min_z: -10, max_x: 238, max_y: 252, max_z: 8 }, steel))
        .concat(cuboid_faces(camera, { min_x: 145, min_y: 0, min_z: -160, max_x: 220, max_y: 58, max_z: -88 }, crate))
        .concat(cuboid_faces(camera, { min_x: 152, min_y: 58, min_z: -151, max_x: 213, max_y: 108, max_z: -94 }, Color.darken(crate, 8)))
        .concat(cuboid_faces(camera, { min_x: -218, min_y: 0, min_z: 68, max_x: -148, max_y: 14, max_z: 155 }, pallet))
        .concat(cuboid_faces(camera, { min_x: -210, min_y: 14, min_z: 78, max_x: -156, max_y: 82, max_z: 145 }, crate))
        .concat(cuboid_faces(camera, { min_x: -34, min_y: -10, min_z: -34, max_x: 34, max_y: 0, max_z: 34 }, 0x263248.Color))

    faces
        .sort_with(|a, b| if a.depth < b.depth LT else if a.depth > b.depth GT else EQ)
        .map(|face| {
            texture: model.white_texture,
            top_left: face.top_left,
            bottom_left: face.bottom_left,
            bottom_right: face.bottom_right,
            top_right: face.top_right,
            tint: face.tint,
        })
}

warehouse_lines : OrbitCamera -> List(Element.CanvasLine)
warehouse_lines = |camera| {
    rear_seams = [-200, -120, -40, 40, 120, 200].map(|x|
        world_line(camera, Physics.point(x, 0, -241), Physics.point(x, 235, -241), 1, Color.with_alpha(muted, 45)),
    )
    roof_trusses = [-180, 0, 180].map(|z|
        world_line(camera, Physics.point(-235, 248, z), Physics.point(235, 248, z), 5, 0x35445d.Color),
    )
    lights = [-125, 55].map(|z|
        world_line(camera, Physics.point(-115, 238, z), Physics.point(115, 238, z), 7, Color.with_alpha(cyan, 155)),
    )
    safety = [
        world_line(camera, Physics.point(-92, 1.2, -78), Physics.point(92, 1.2, -78), 3, Color.with_alpha(amber, 155)),
        world_line(camera, Physics.point(92, 1.2, -78), Physics.point(92, 1.2, 78), 3, Color.with_alpha(amber, 155)),
        world_line(camera, Physics.point(92, 1.2, 78), Physics.point(-92, 1.2, 78), 3, Color.with_alpha(amber, 155)),
        world_line(camera, Physics.point(-92, 1.2, 78), Physics.point(-92, 1.2, -78), 3, Color.with_alpha(amber, 155)),
    ]
    rear_seams.concat(roof_trusses).concat(lights).concat(safety)
}

warehouse_textures : AppModel, OrbitCamera -> List(Element.CanvasTextureQuad)
warehouse_textures = |model, camera| [
    {
        texture: model.floor_texture,
        top_left: project(camera, Physics.point(-260, -1, -240)),
        bottom_left: project(camera, Physics.point(-260, -1, 240)),
        bottom_right: project(camera, Physics.point(260, -1, 240)),
        top_right: project(camera, Physics.point(260, -1, -240)),
        tint: Color.with_alpha(Color.white, 200),
    },
    {
        texture: model.wall_texture,
        top_left: project(camera, Physics.point(-260, 270, -242)),
        bottom_left: project(camera, Physics.point(-260, 0, -242)),
        bottom_right: project(camera, Physics.point(260, 0, -242)),
        top_right: project(camera, Physics.point(260, 270, -242)),
        tint: Color.with_alpha(0xaac2df.Color, 175),
    },
    {
        texture: model.wall_texture,
        top_left: project(camera, Physics.point(-262, 270, 240)),
        bottom_left: project(camera, Physics.point(-262, 0, 240)),
        bottom_right: project(camera, Physics.point(-262, 0, -240)),
        top_right: project(camera, Physics.point(-262, 270, -240)),
        tint: Color.with_alpha(0x7892b5.Color, 145),
    },
]

workspace_view : AppModel, Solution -> View(Msg)
workspace_view = |model, solution| {
    camera = camera_for(model)
    scene_lines = warehouse_lines(camera)
        .concat(ground_grid(camera))
        .concat(axis_lines(camera))
        .concat(robot_lines(camera, solution))
    all_lines = if model.show_pga { scene_lines.concat(pga_lines(camera, solution)) } else { scene_lines }

    box(
        Id("screwbot-workspace"),
        |status| style
            .width(Grow({ min: 420, max: 10000 }))
            .height(Grow({ min: 420, max: 10000 }))
            .background(if status.hovered { workspace.lighten(3) } else { workspace })
            .radius(14)
            .border({ color: if status.focused { cyan } else { grid }, left: 1, right: 1, top: 1, bottom: 1 })
            .overflow(Hidden, Hidden),
        [
            OnPointer(
                Box.box(
                    |event| {
                        if event.buttons.right.pressed {
                            [OrbitStart(event.position.x, event.position.y)]
                        } else if event.buttons.right.down {
                            [OrbitMove(event.position.x, event.position.y)]
                        } else if event.buttons.right.released {
                            [OrbitEnd]
                        } else if event.buttons.left.down or event.buttons.left.pressed {
                            aim = Physics.coords(target_from_pointer(event, model.target, camera))
                            [AimTarget3D(aim.x, aim.y, aim.z)]
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
                texture_quads: warehouse_textures(model, camera).concat(warehouse_faces(model, camera)),
                lines: all_lines,
                circles: robot_circles(model, camera, solution),
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
            .gap(12)
            .child_align({ x: Start, y: Center })
            .font_size(16),
        [],
        [
            box(
                Auto,
                |_| style
                    .width(Grow({ min: 0, max: 10000 }))
                    .height(Fit({ min: 0, max: 10000 }))
                    .child_align({ x: Start, y: Center })
                    .font_size(16)
                    .font_color(muted)
                    .text_align(Left),
                [],
                [text(name)],
            ),
            box(
                Auto,
                |_| style
                    .width(Fixed(160))
                    .height(Fit({ min: 0, max: 10000 }))
                    .child_align({ x: End, y: Center })
                    .font_size(16)
                    .font_color(color),
                [],
                [text(value)],
            ),
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

coefficient_readout : Str, Str, Color -> View(Msg)
coefficient_readout = |basis, values, color| {
    box(
        Auto,
        |_| style
            .width(Grow({ min: 0, max: 10000 }))
            .height(Fit({ min: 0, max: 10000 }))
            .direction(Row)
            .gap(8)
            .child_align({ x: Start, y: Center }),
        [],
        [
            box(
                Auto,
                |_| style
                    .width(Grow({ min: 0, max: 10000 }))
                    .height(Fit({ min: 0, max: 10000 }))
                    .child_align({ x: Start, y: Center })
                    .font_size(14)
                    .font_color(muted)
                    .text_align(Left),
                [],
                [text(basis)],
            ),
            box(
                Auto,
                |_| style
                    .width(Fixed(150))
                    .height(Fit({ min: 0, max: 10000 }))
                    .child_align({ x: End, y: Center })
                    .font_size(14)
                    .font_color(color),
                [],
                [text(values)],
            ),
        ],
    )
}

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
            coefficient_readout("P target 032/013/021", "${decimal(target.e032)}  ${decimal(target.e013)}  ${decimal(target.e021)}", green),
            coefficient_readout("L upper 23/31/12", "${decimal(upper.e23)}  ${decimal(upper.e31)}  ${decimal(upper.e12)}", blue),
            coefficient_readout("T motor 01/02/03", "${decimal(motor.e01)}  ${decimal(motor.e02)}  ${decimal(motor.e03)}", cyan),
            coefficient_readout("plane 0/1/2/3", "${decimal(plane.e0)}  ${decimal(plane.e1)}  ${decimal(plane.e2)}  ${decimal(plane.e3)}", green),
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
                    box(Auto, |_| style.width(Fit({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).font_size(15).font_color(muted), [], [text("LMB move target  //  RMB orbit warehouse  //  live 3D PGA")]),
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
        AimTarget3D(x, y, z) => { ..model, target: Physics.point(x, y, z) }
        OrbitStart(x, y) => { ..model, orbit: Orbiting({ x, y }) }
        OrbitMove(x, y) => match model.orbit {
            OrbitIdle => model
            Orbiting(previous) => {
                dx = x - previous.x
                dy = y - previous.y
                {
                    ..model,
                    camera_yaw: clamp(model.camera_yaw + dx * 0.008, -1.15, 1.15),
                    camera_pitch: clamp(model.camera_pitch - dy * 0.006, 0.14, 0.95),
                    orbit: Orbiting({ x, y }),
                }
            }
        }
        OrbitEnd => { ..model, orbit: OrbitIdle }
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

floor_texture_path : Str
floor_texture_path = "examples/assets/screwbot-floor.png"

wall_texture_path : Str
wall_texture_path = "examples/assets/screwbot-wall.png"

white_texture_path : Str
white_texture_path = "examples/assets/screwbot-white.png"

init! : Program.Config => Try(AppModel, [Exit(I64)])
init! = |_config| {
    font = Draw.load_font!({ path: font_path, size: 32 }).map_err(|_| Exit(1))?
    floor_texture = Assets.load_texture!(floor_texture_path).map_err(|_| Exit(1))?
    wall_texture = Assets.load_texture!(wall_texture_path).map_err(|_| Exit(1))?
    white_texture = Assets.load_texture!(white_texture_path).map_err(|_| Exit(1))?
    Ok({
        theme: { ..Theme.dark, font, font_size: 16, radius: 7, gap: 9 },
        floor_texture,
        wall_texture,
        white_texture,
        target: Physics.point(145, 145, 60),
        upper_length: 132,
        fore_length: 118,
        elbow_up: False,
        show_pga: True,
        camera_yaw: 0.48,
        camera_pitch: 0.34,
        orbit: OrbitIdle,
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
            vsync: False,
        },
        init!,
        view,
        update,
    },
)
