## Screwbot: an interactive inverse-kinematics workbench.
##
## The solver produces a robot pose in ordinary joint-angle space, then stores
## the mechanism as roc-ray 3D PGA points, lines, a plane, and a translation
## motor. Terracotta renders the projected geometry and exposes its live PGA
## coefficients as a small inspection console.
##
## The 3D scene is drawn by `Element.canvas`, whose closure runs during
## `render!` with the frame and the node's resolved bounds. `SceneRenderer`
## turns that into the offscreen scene pass, bloom chain, and composite.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst",
	tc: "../../package/main.roc",
	roc: "nightly-2026-09-27-a3ce7f1",
}

import rr.App
import rr.Assets
import rr.Draw
import rr.Mouse
import rr.Physics

import tc.Color
import tc.Element exposing [box, style, text]
import tc.Event
import tc.Program exposing [View]
import tc.Theme
import tc.Widget

import RobotArm
import SceneCamera exposing [Point2]
import SceneRenderer
import Warehouse exposing [Bounds3]

## The small authored inputs are embedded from paths relative to this source
## file; the material textures are loaded from `examples/assets` at startup.
import "../assets/screwbot-scene.fs" as scene_shader_source : Str
import "../assets/screwbot-floor.fs" as floor_shader_source : Str
import "../assets/screwbot-robot.fs" as robot_shader_source : Str
import "../assets/screwbot-emissive.fs" as emissive_shader_source : Str
import "../assets/screwbot-blur.fs" as blur_shader_source : Str

Model : Program.State(AppModel, Msg)

AppModel : {
	theme : Theme,
	resources : SceneRenderer.Resources,
	crate_texture : Assets.Texture,
	floor_texture : Assets.Texture,
	wall_texture : Assets.Texture,
	white_texture : Assets.Texture,
	robot_texture : Assets.Texture,
	target : Physics.Point,
	arm : RobotArm,
	show_pga : Bool,
	camera : SceneCamera,
	orbit : OrbitState,
}

Msg : [
	AimTarget3D(F32, F32, F32),
	OrbitEnd,
	OrbitMove(F32, F32),
	PointerIdle,
	SetElbowUp(Bool),
	SetForeLength(F32),
	SetShowPga(Bool),
	SetTargetX(F32),
	SetTargetY(F32),
	SetTargetZ(F32),
	SetUpperLength(F32),
	SelectPose(PosePreset),
]

## Pointer-drag state for the orbit camera interaction.
OrbitState := [OrbitIdle, Orbiting(Point2)]

## A named target configuration exposed by the preset controls.
PosePreset := [AssemblyPose, FoldedPose, LongReachPose]

## The three warehouse-space axes available to the overlay renderer.
AxisLabel := [XAxis, YAxis, ZAxis]

## One planar surface projected through the scene camera, with a sort depth
## averaged over its four corners.
ProjectedFace : {
	depth : F32,
	top_left : Point2,
	bottom_left : Point2,
	bottom_right : Point2,
	top_right : Point2,
	tint : Color,
}

ink = 0xd8e5ff.Color

muted = 0x7584a3.Color

surface = 0x111a2e.Color

surface_high = 0x18243d.Color

workspace = SceneRenderer.background

grid = 0x1a2943.Color

cyan = 0x45d7ff.Color

blue = 0x5686ff.Color

violet = 0xa478ff.Color

amber = 0xffbe55.Color

green = 0x57e389.Color

red = 0xff647c.Color

shadow = 0x03060d.Color

clamp : F32, F32, F32 -> F32
clamp = |value, lo, hi| value.min(hi).max(lo)

## The scene is rendered at a fixed resolution and letterboxed into whatever
## bounds the canvas leaf resolves, so there is no window-size breakpoint.
scene_parameters : RobotArm, Physics.Point -> SceneRenderer.SceneParameters
scene_parameters = |arm, target_point| {
	solution = arm.solve(target_point)
	target = solution.target.coords()
	{

		## Held at zero: the current Program API exposes no per-frame
		## timestamp, so the shaders keep their initial animation phase.
		seconds: 0,
		target_uv: {
			x: (target.x - Warehouse.layout.min_x) / (Warehouse.layout.max_x - Warehouse.layout.min_x),
			y: (target.z - Warehouse.layout.min_z) / (Warehouse.layout.max_z - Warehouse.layout.min_z),
		},
		reachable_value: if solution.reachable 1 else 0,
		error_amount: clamp(solution.error / 80, 0, 1),
	}
}

## Parity fixture: the default target is reachable and has its expected floor
## UV. Shader time is a constant, so every snapshot shares one phase.
expect {
	arm = { upper_length: 132, fore_length: 118, elbow_up: False }
	target = Physics.point(145, 145, 60)
	initial = scene_parameters(arm, target)
	later = scene_parameters(arm, target)
	initial.seconds == 0
		and later.seconds == 0
			and initial.reachable_value == 1
				and initial.error_amount < 0.001
					and initial.target_uv.x > 0.778
						and initial.target_uv.x < 0.779
							and initial.target_uv.y == 0.625
								and initial.target_uv == later.target_uv
									and initial.reachable_value == later.reachable_value
										and initial.error_amount == later.error_amount
}

## Parity fixture: an unreachable target keeps its raw floor UV and selects the
## error/reachability shader branch.
expect {
	parameters = scene_parameters({ upper_length: 132, fore_length: 118, elbow_up: False }, Physics.point(500, 0, 0))
	parameters.reachable_value == 0
		and parameters.error_amount == 1
			and parameters.target_uv.x > 1.46
				and parameters.target_uv.y == 0.5
}

decimal : F32 -> Str
decimal = |value| match (value * 10).round_to_i64_try() {
	Ok(scaled) => (scaled.to_f32() / 10).to_str()
	Err(_) => value.to_str()
}

line : Point2, Point2, F32, Color -> SceneRenderer.Line
line = |start, end, thickness, color| { start, end, thickness, color, depth: SceneCamera.far_depth }

circle : Point2, F32, Color -> SceneRenderer.Circle
circle = |center, radius, color| { center, radius, color, depth: SceneCamera.far_depth }

radial_gradient : Point2, F32, Color, Color -> SceneRenderer.RadialGradient
radial_gradient = |center, radius, inner, outer| { center, radius, inner, outer }

world_line : SceneCamera, Physics.Point, Physics.Point, F32, Color -> SceneRenderer.Line
world_line = |camera, start, end, thickness, color| {
	..line(camera.project(start), camera.project(end), thickness, color),
	depth: (camera.depth(start) + camera.depth(end)) * 0.5,
}

grid_values : List(F32)
grid_values = [-240, -200, -160, -120, -80, -40, 0, 40, 80, 120, 160, 200, 240]

ground_grid : SceneCamera -> List(SceneRenderer.Line)
ground_grid = |camera| {
	along_x = grid_values.map(|z| world_line(camera, Physics.point(-260, 0, z), Physics.point(260, 0, z), 1, grid))
	along_z = grid_values.map(|x| world_line(camera, Physics.point(x, 0, -240), Physics.point(x, 0, 240), 1, grid))
	along_x.concat(along_z)
}

axis_letter : AxisLabel, Point2, Color, F32 -> List(SceneRenderer.Line)
axis_letter = |label, center, color, depth| {
	left = center.x - 5
	right = center.x + 5
	top = center.y - 7
	middle = center.y
	bottom = center.y + 7

	match label {
		XAxis => [
			{ ..line({ x: left, y: top }, { x: right, y: bottom }, 2.5, color), depth },
			{ ..line({ x: right, y: top }, { x: left, y: bottom }, 2.5, color), depth },
		]
		YAxis => [
			{ ..line({ x: left, y: top }, { x: center.x, y: middle }, 2.5, color), depth },
			{ ..line({ x: right, y: top }, { x: center.x, y: middle }, 2.5, color), depth },
			{ ..line({ x: center.x, y: middle }, { x: center.x, y: bottom }, 2.5, color), depth },
		]
		ZAxis => [
			{ ..line({ x: left, y: top }, { x: right, y: top }, 2.5, color), depth },
			{ ..line({ x: right, y: top }, { x: left, y: bottom }, 2.5, color), depth },
			{ ..line({ x: left, y: bottom }, { x: right, y: bottom }, 2.5, color), depth },
		]
	}
}

axis_with_label : SceneCamera, Physics.Point, AxisLabel, Color -> List(SceneRenderer.Line)
axis_with_label = |camera, end_world, label, color| {
	start = camera.project(Physics.origin)
	end = camera.project(end_world)
	dx = end.x - start.x
	dy = end.y - start.y
	length = (dx * dx + dy * dy).sqrt().max(1)
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
	depth = (camera.depth(Physics.origin) + camera.depth(end_world)) * 0.5

	[
		{ ..line(start, end, 4, color), depth },
		{ ..line(end, left_wing, 4, color), depth },
		{ ..line(end, right_wing, 4, color), depth },
	].concat(axis_letter(label, label_center, color, depth))
}

axis_lines : SceneCamera -> List(SceneRenderer.Line)
axis_lines = |camera| axis_with_label(camera, Physics.point(125, 0, 0), XAxis, red)
	.concat(axis_with_label(camera, Physics.point(0, 125, 0), YAxis, green))
	.concat(axis_with_label(camera, Physics.point(0, 0, 125), ZAxis, blue))

link_parallel : Point2, Point2, F32, F32, Color -> SceneRenderer.Line
link_parallel = |start, end, offset, thickness, color| {
	dx = end.x - start.x
	dy = end.y - start.y
	length = (dx * dx + dy * dy).sqrt().max(1)
	normal_x = (0 - dy) / length * offset
	normal_y = dx / length * offset
	line(
		{ x: start.x + normal_x, y: start.y + normal_y },
		{ x: end.x + normal_x, y: end.y + normal_y },
		thickness,
		color,
	)
}

link_tick : Point2, Point2, F32, F32, Color -> SceneRenderer.Line
link_tick = |start, end, along, width, color| {
	dx = end.x - start.x
	dy = end.y - start.y
	length = (dx * dx + dy * dy).sqrt().max(1)
	center = { x: start.x + dx * along, y: start.y + dy * along }
	normal_x = (0 - dy) / length * width * 0.5
	normal_y = dx / length * width * 0.5
	line(
		{ x: center.x - normal_x, y: center.y - normal_y },
		{ x: center.x + normal_x, y: center.y + normal_y },
		1.5,
		color,
	)
}

robot_lines : SceneCamera, RobotArm.Solution -> List(SceneRenderer.Line)
robot_lines = |camera, solution| {
	base_screen = camera.project(solution.base)
	elbow_screen = camera.project(solution.elbow)
	tool_screen = camera.project(solution.tool)
	target_screen = camera.project(solution.target)
	target_ground_screen = camera.project(solution.target_ground)

	tool_direction = solution.tool.sub(solution.elbow)
	tool_vector = tool_direction.components()
	tool_len = tool_direction.length().max(1)
	side = Physics.vector(0 - tool_vector.y / tool_len, tool_vector.x / tool_len, 0)
	finger_root = solution.tool.add(side.scale(9))
	finger_tip = solution.tool.add(side.scale(-9))
	forward = tool_direction.normalize()
	finger_one = finger_root.add(forward.scale(17))
	finger_two = finger_tip.add(forward.scale(17))
	upper_depth = (camera.depth(solution.base) + camera.depth(solution.elbow)) * 0.5
	fore_depth = (camera.depth(solution.elbow) + camera.depth(solution.tool)) * 0.5

	[
		{ ..link_parallel(base_screen, elbow_screen, -4, 2, ink.with_alpha(185)), depth: upper_depth + 0.003 },
		{ ..link_parallel(base_screen, elbow_screen, 4, 1.5, cyan.with_alpha(210)), depth: upper_depth + 0.004 },
		{ ..link_tick(base_screen, elbow_screen, 0.30, 15, shadow.with_alpha(180)), depth: upper_depth + 0.005 },
		{ ..link_tick(base_screen, elbow_screen, 0.56, 15, shadow.with_alpha(180)), depth: upper_depth + 0.005 },
		{ ..link_tick(base_screen, elbow_screen, 0.82, 14, shadow.with_alpha(180)), depth: upper_depth + 0.005 },
		{ ..link_parallel(elbow_screen, tool_screen, -3.5, 2, (0xffe0a3.Color).with_alpha(190)), depth: fore_depth + 0.003 },
		{ ..link_parallel(elbow_screen, tool_screen, 3.5, 1.5, violet.with_alpha(220)), depth: fore_depth + 0.004 },
		{ ..link_tick(elbow_screen, tool_screen, 0.34, 13, shadow.with_alpha(180)), depth: fore_depth + 0.005 },
		{ ..link_tick(elbow_screen, tool_screen, 0.68, 12, shadow.with_alpha(180)), depth: fore_depth + 0.005 },
		world_line(camera, solution.target_ground, solution.target, 2, muted),
		line(
			{ x: target_screen.x - 14, y: target_screen.y },
			{ x: target_screen.x + 14, y: target_screen.y },
			2,
			if solution.reachable {
				green
			} else {
				red
			},
		),
		line(
			{ x: target_screen.x, y: target_screen.y - 14 },
			{ x: target_screen.x, y: target_screen.y + 14 },
			2,
			if solution.reachable {
				green
			} else {
				red
			},
		),
		world_line(camera, finger_root, finger_one, 5, cyan),
		world_line(camera, finger_tip, finger_two, 5, cyan),
		line(target_ground_screen, target_screen, 1, muted),
	]
}

robot_shadow_lines : SceneCamera, RobotArm.Solution -> List(SceneRenderer.Line)
robot_shadow_lines = |camera, solution| {
	ground_base = shadow_on_ground(solution.base)
	ground_elbow = shadow_on_ground(solution.elbow)
	ground_tool = shadow_on_ground(solution.tool)
	[
		world_line(camera, ground_base, ground_elbow, 13, shadow.with_alpha(70)),
		world_line(camera, ground_elbow, ground_tool, 11, shadow.with_alpha(70)),
	]
}

link_quad : Assets.Texture, SceneRenderer.Material, Point2, Point2, F32, F32, Color, F32 -> SceneRenderer.Quad
link_quad = |texture_value, material, start, end, start_width, end_width, tint, depth| {
	dx = end.x - start.x
	dy = end.y - start.y
	length = (dx * dx + dy * dy).sqrt().max(1)
	start_normal_x = (0 - dy) / length * start_width * 0.5
	start_normal_y = dx / length * start_width * 0.5
	end_normal_x = (0 - dy) / length * end_width * 0.5
	end_normal_y = dx / length * end_width * 0.5
	{
		texture: texture_value,
		material,
		top_left: { x: start.x + start_normal_x, y: start.y + start_normal_y },
		bottom_left: { x: start.x - start_normal_x, y: start.y - start_normal_y },
		bottom_right: { x: end.x - end_normal_x, y: end.y - end_normal_y },
		top_right: { x: end.x + end_normal_x, y: end.y + end_normal_y },
		tint,
		depth,
	}
}

robot_faces : AppModel, SceneCamera, RobotArm.Solution -> List(SceneRenderer.Quad)
robot_faces = |model, camera, solution| {
	base = camera.project(solution.base)
	elbow = camera.project(solution.elbow)
	tool = camera.project(solution.tool)
	upper_depth = (camera.depth(solution.base) + camera.depth(solution.elbow)) * 0.5
	fore_depth = (camera.depth(solution.elbow) + camera.depth(solution.tool)) * 0.5
	[
		link_quad(model.robot_texture, PlainMaterial, base, elbow, 38, 30, 0x10192c.Color, upper_depth),
		link_quad(model.robot_texture, RobotMaterial, base, elbow, 27, 19, blue, upper_depth + 0.001),
		link_quad(model.robot_texture, PlainMaterial, elbow, tool, 33, 25, 0x211831.Color, fore_depth),
		link_quad(model.robot_texture, RobotMaterial, elbow, tool, 23, 15, violet, fore_depth + 0.001),
	]
}

pga_lines : SceneCamera, RobotArm.Solution -> List(SceneRenderer.Line)
pga_lines = |camera, solution| if solution.reachable {
	[world_line(camera, solution.base, solution.target, 1, cyan.with_alpha(95))]
} else {
	[]
}

pga_motor_circles : SceneCamera, RobotArm.Solution -> List(SceneRenderer.Circle)
pga_motor_circles = |camera, solution| {
	direction = solution.target.sub(solution.base)
	[
		circle(camera.project(solution.base.add(direction.scale(0.18))), 2.5, cyan.with_alpha(45)),
		circle(camera.project(solution.base.add(direction.scale(0.34))), 3, cyan.with_alpha(65)),
		circle(camera.project(solution.base.add(direction.scale(0.50))), 3.5, cyan.with_alpha(90)),
		circle(camera.project(solution.base.add(direction.scale(0.66))), 3, cyan.with_alpha(115)),
		circle(camera.project(solution.base.add(direction.scale(0.82))), 2.5, cyan.with_alpha(145)),
	]
}

shadow_on_ground : Physics.Point -> Physics.Point
shadow_on_ground = |point| {
	c = point.coords()
	Physics.point(c.x + c.y * 0.22, 1, c.z + c.y * 0.16)
}

robot_circles : AppModel, SceneCamera, RobotArm.Solution -> List(SceneRenderer.Circle)
robot_circles = |_model, camera, solution| {
	base_screen = camera.project(solution.base)
	elbow_screen = camera.project(solution.elbow)
	tool_screen = camera.project(solution.tool)
	target_screen = camera.project(solution.target)
	base_point_depth = camera.depth(solution.base)
	elbow_point_depth = camera.depth(solution.elbow)
	tool_point_depth = camera.depth(solution.tool)
	upper_depth = (base_point_depth + elbow_point_depth) * 0.5
	fore_depth = (elbow_point_depth + tool_point_depth) * 0.5
	# Keep each joint over its attached link while the complete assembly still
	# participates in scene-depth sorting against warehouse geometry.
	base_depth = base_point_depth.max(upper_depth) + 0.01
	elbow_depth = elbow_point_depth.max(upper_depth.max(fore_depth)) + 0.01
	tool_depth = tool_point_depth.max(fore_depth) + 0.01

	[
		{ ..circle(base_screen, 28, shadow), depth: base_depth },
		{ ..circle(base_screen, 22, surface_high), depth: base_depth + 0.001 },
		{ ..circle(base_screen, 14, cyan), depth: base_depth + 0.002 },
		{ ..circle(base_screen, 4, ink), depth: base_depth + 0.003 },
		{ ..circle(elbow_screen, 23, shadow), depth: elbow_depth },
		{ ..circle(elbow_screen, 18, surface_high), depth: elbow_depth + 0.001 },
		{ ..circle(elbow_screen, 10, amber), depth: elbow_depth + 0.002 },
		{ ..circle(elbow_screen, 3, ink), depth: elbow_depth + 0.003 },
		{ ..circle(tool_screen, 16, shadow), depth: tool_depth },
		{ ..circle(tool_screen, 12, surface_high), depth: tool_depth + 0.001 },
		{ ..circle(tool_screen, 6, cyan), depth: tool_depth + 0.002 },
		circle(
			target_screen,
			6,
			if solution.reachable {
				green
			} else {
				red
			},
		),
	]
}

target_from_pointer : Event.PointerEvent, Physics.Point, SceneCamera -> Physics.Point
target_from_pointer = |event, current_target, camera| {
	relative = event.target.bounds.relative(event.position)
	scale_x = event.target.bounds.width / SceneCamera.view_width
	scale_y = event.target.bounds.height / SceneCamera.view_height
	canvas_scale = scale_x.min(scale_y).max(0.001)
	offset_x = (event.target.bounds.width - SceneCamera.view_width * canvas_scale) * 0.5
	offset_y = (event.target.bounds.height - SceneCamera.view_height * canvas_scale) * 0.5
	screen_x = (relative.x - offset_x) / canvas_scale
	screen_y = (relative.y - offset_y) / canvas_scale
	camera.target_at(current_target, { x: screen_x, y: screen_y })
}

projected_face : SceneCamera, Physics.Point, Physics.Point, Physics.Point, Physics.Point, Color -> ProjectedFace
projected_face = |camera, top_left, bottom_left, bottom_right, top_right, tint| {
	depth: (camera.depth(top_left) + camera.depth(bottom_left) + camera.depth(bottom_right) + camera.depth(top_right)) / 4,
	top_left: camera.project(top_left),
	bottom_left: camera.project(bottom_left),
	bottom_right: camera.project(bottom_right),
	top_right: camera.project(top_right),
	tint,
}

cuboid_faces : SceneCamera, Bounds3, Color -> List(ProjectedFace)
cuboid_faces = |camera, bounds, color| {
	p000 = Physics.point(bounds.min_x, bounds.min_y, bounds.min_z)
	p001 = Physics.point(bounds.min_x, bounds.min_y, bounds.max_z)
	p010 = Physics.point(bounds.min_x, bounds.max_y, bounds.min_z)
	p011 = Physics.point(bounds.min_x, bounds.max_y, bounds.max_z)
	p100 = Physics.point(bounds.max_x, bounds.min_y, bounds.min_z)
	p101 = Physics.point(bounds.max_x, bounds.min_y, bounds.max_z)
	p110 = Physics.point(bounds.max_x, bounds.max_y, bounds.min_z)
	p111 = Physics.point(bounds.max_x, bounds.max_y, bounds.max_z)

	faces = [
		projected_face(camera, p010, p011, p111, p110, color.lighten(38)),
		projected_face(camera, p011, p001, p101, p111, color.lighten(8)),
		projected_face(camera, p010, p000, p001, p011, color.darken(30)),
		projected_face(camera, p110, p111, p101, p100, color.lighten(18)),
		projected_face(camera, p010, p110, p100, p000, color.darken(12)),
		projected_face(camera, p001, p000, p100, p101, color.darken(45)),
	]

	# Cull back faces in projected space. Besides reducing overdraw, this removes
	# the layered-card appearance caused by drawing all six opaque cuboid sides.
	faces.keep_if(
		|face| {
			left_x = face.bottom_left.x - face.top_left.x
			left_y = face.bottom_left.y - face.top_left.y
			diagonal_x = face.bottom_right.x - face.top_left.x
			diagonal_y = face.bottom_right.y - face.top_left.y
			left_x * diagonal_y - left_y * diagonal_x < -0.01
		},
	)
}

face_quad : Assets.Texture, SceneRenderer.Material, ProjectedFace -> SceneRenderer.Quad
face_quad = |texture_value, material, face| {
	texture: texture_value,
	material,
	top_left: face.top_left,
	bottom_left: face.bottom_left,
	bottom_right: face.bottom_right,
	top_right: face.top_right,
	tint: face.tint,
	depth: face.depth,
}

carton_ground_shadow : AppModel, SceneCamera, Bounds3 -> SceneRenderer.Quad
carton_ground_shadow = |model, camera, bounds| {
	margin = 7
	offset_x = 7
	offset_z = 5
	face_quad(
		model.white_texture,
		PlainMaterial,
		projected_face(
			camera,
			Physics.point(bounds.min_x - margin + offset_x, Warehouse.layout.floor_y + 0.4, bounds.min_z - margin + offset_z),
			Physics.point(bounds.min_x - margin + offset_x, Warehouse.layout.floor_y + 0.4, bounds.max_z + margin + offset_z),
			Physics.point(bounds.max_x + margin + offset_x, Warehouse.layout.floor_y + 0.4, bounds.max_z + margin + offset_z),
			Physics.point(bounds.max_x + margin + offset_x, Warehouse.layout.floor_y + 0.4, bounds.min_z - margin + offset_z),
			shadow.with_alpha(105),
		),
	)
}

warehouse_ground_marks : AppModel, SceneCamera -> List(SceneRenderer.Quad)
warehouse_ground_marks = |model, camera| {
	light_pool = projected_face(
		camera,
		Physics.point(-185, 0.5, -165),
		Physics.point(-215, 0.5, 80),
		Physics.point(100, 0.5, 80),
		Physics.point(70, 0.5, -165),
		cyan.with_alpha(13),
	)
	safety_zone = projected_face(
		camera,
		Physics.point(-92, 0.8, -78),
		Physics.point(-92, 0.8, 78),
		Physics.point(92, 0.8, 78),
		Physics.point(92, 0.8, -78),
		amber.with_alpha(16),
	)
	[
		face_quad(model.white_texture, PlainMaterial, light_pool),
		face_quad(model.white_texture, PlainMaterial, safety_zone),
		carton_ground_shadow(model, camera, Warehouse.carton_right_lower),
		carton_ground_shadow(model, camera, Warehouse.carton_left),
	]
}

carton_decal_faces : SceneCamera, Bounds3, Bool -> List(ProjectedFace)
carton_decal_faces = |camera, bounds, has_label| {
	mid_x = (bounds.min_x + bounds.max_x) * 0.5
	width = bounds.width()
	height = bounds.height()
	front_z = bounds.max_z + 0.9
	top_y = bounds.max_y + 0.9
	tape_half = (width * 0.045).max(2.5)
	tape_color = (0xe1c38f.Color).with_alpha(218)
	tape_faces = [
		projected_face(camera, Physics.point(mid_x - tape_half, bounds.max_y, front_z), Physics.point(mid_x - tape_half, bounds.min_y, front_z), Physics.point(mid_x + tape_half, bounds.min_y, front_z), Physics.point(mid_x + tape_half, bounds.max_y, front_z), tape_color),
		projected_face(camera, Physics.point(mid_x - tape_half, top_y, bounds.min_z), Physics.point(mid_x - tape_half, top_y, bounds.max_z), Physics.point(mid_x + tape_half, top_y, bounds.max_z), Physics.point(mid_x + tape_half, top_y, bounds.min_z), tape_color),
	]

	if has_label {
		label_min_x = bounds.min_x + width * 0.24
		label_max_x = bounds.min_x + width * 0.70
		label_min_y = bounds.min_y + height * 0.37
		label_max_y = bounds.min_y + height * 0.73
		label_z = front_z + 0.35
		label = projected_face(camera, Physics.point(label_min_x, label_max_y, label_z), Physics.point(label_min_x, label_min_y, label_z), Physics.point(label_max_x, label_min_y, label_z), Physics.point(label_max_x, label_max_y, label_z), (0xdbe5e8.Color).with_alpha(224))
		bar_width = width * 0.018
		bar_a_x = label_min_x + width * 0.30
		bar_b_x = label_min_x + width * 0.35
		ink_z = label_z + 0.2
		bar_a = projected_face(camera, Physics.point(bar_a_x, label_max_y - 2, ink_z), Physics.point(bar_a_x, label_min_y + 2, ink_z), Physics.point(bar_a_x + bar_width, label_min_y + 2, ink_z), Physics.point(bar_a_x + bar_width, label_max_y - 2, ink_z), 0x34404a.Color)
		bar_b = projected_face(camera, Physics.point(bar_b_x, label_max_y - 2, ink_z), Physics.point(bar_b_x, label_min_y + 2, ink_z), Physics.point(bar_b_x + bar_width * 1.6, label_min_y + 2, ink_z), Physics.point(bar_b_x + bar_width * 1.6, label_max_y - 2, ink_z), 0x34404a.Color)
		tape_faces.concat([label, bar_a, bar_b])
	} else {
		tape_faces
	}
}

warehouse_faces : AppModel, SceneCamera -> List(SceneRenderer.Quad)
warehouse_faces = |model, camera| {
	steel = 0x30415b.Color
	crate = 0xd9d3c8.Color

	var $structure_faces = []
	for bounds in Warehouse.layout.structure() {
		$structure_faces = $structure_faces.concat(cuboid_faces(camera, bounds, steel))
	}
	$structure_faces = $structure_faces.concat(cuboid_faces(camera, { min_x: -34, min_y: -10, min_z: -34, max_x: 34, max_y: 0, max_z: 34 }, 0x263248.Color))

	box_faces = cuboid_faces(camera, Warehouse.carton_right_lower, crate)
		.concat(cuboid_faces(camera, Warehouse.carton_right_upper, crate.darken(7)))
		.concat(cuboid_faces(camera, Warehouse.carton_left, crate))
	var $pallet_faces = []
	for bounds in Warehouse.pallet_left.pallet_parts() {
		$pallet_faces = $pallet_faces.concat(cuboid_faces(camera, bounds, 0x8f7254.Color))
	}
	decal_faces = carton_decal_faces(camera, Warehouse.carton_right_lower, True)
		.concat(carton_decal_faces(camera, Warehouse.carton_right_upper, False))
		.concat(carton_decal_faces(camera, Warehouse.carton_left, True))

	textured_faces = $structure_faces.map(|face| { face, texture: model.white_texture, material: PlainMaterial })
		.concat(box_faces.map(|face| { face, texture: model.crate_texture, material: CrateMaterial }))
		.concat($pallet_faces.map(|face| { face, texture: model.white_texture, material: PlainMaterial }))
		.concat(decal_faces.map(|face| { face, texture: model.white_texture, material: PlainMaterial }))

	textured_faces
		.sort_with(|a, b| if a.face.depth < b.face.depth Before else if a.face.depth > b.face.depth After else Same)
		.map(|item| face_quad(item.texture, item.material, item.face))
}

warehouse_underlay_lines : SceneCamera -> List(SceneRenderer.Line)
warehouse_underlay_lines = |camera| {
	aisle = [
		world_line(camera, Physics.point(-128, 1, -150), Physics.point(-128, 1, 110), 2, muted.with_alpha(70)),
		world_line(camera, Physics.point(96, 1, -150), Physics.point(96, 1, 110), 2, muted.with_alpha(70)),
		world_line(camera, Physics.point(-128, 1, -150), Physics.point(96, 1, -150), 2, muted.with_alpha(50)),
		world_line(camera, Physics.point(-128, 1, 110), Physics.point(96, 1, 110), 2, muted.with_alpha(50)),
	]
	aisle.concat(ground_grid(camera))
}

warehouse_fixture_lines : SceneCamera -> List(SceneRenderer.Line)
warehouse_fixture_lines = |camera| {
	posts = [
		Physics.point(Warehouse.layout.min_x, 0, Warehouse.layout.min_z),
		Physics.point(Warehouse.layout.min_x, 0, Warehouse.layout.max_z),
		Physics.point(Warehouse.layout.max_x, 0, Warehouse.layout.min_z),
		Physics.point(Warehouse.layout.max_x, 0, Warehouse.layout.max_z),
	]
	posts
		.map(|corner| world_line(camera, corner, corner.add(Physics.vector(0, Warehouse.layout.wall_height, 0)), 2, grid.with_alpha(190)))
		.concat(
			posts.map(
				|corner| {
					world_line(
						camera,
						corner,
						corner.add(Physics.vector(20, 0, 20)),
						1,
						muted.with_alpha(80),
					)
				},
			),
		)
}

warehouse_glows : SceneCamera, RobotArm.Solution -> List(SceneRenderer.RadialGradient)
warehouse_glows = |camera, solution| {
	[
		radial_gradient(camera.project(Physics.point(0, 60, 0)), 210, cyan.with_alpha(16), (0x45d7ff.Color).with_alpha(0)),
		radial_gradient(camera.project(solution.base), 62, cyan.with_alpha(34), (0x45d7ff.Color).with_alpha(0)),
		radial_gradient(camera.project(solution.elbow), 44, amber.with_alpha(26), (0xffbe55.Color).with_alpha(0)),
		radial_gradient(camera.project(solution.tool), 40, violet.with_alpha(30), (0xa478ff.Color).with_alpha(0)),
		radial_gradient(camera.project(Physics.point(-150, 30, -120)), 130, blue.with_alpha(14), (0x5686ff.Color).with_alpha(0)),
	]
}

warehouse_textures : AppModel, SceneCamera -> List(SceneRenderer.Quad)
warehouse_textures = |model, camera| [
	{
		texture: model.floor_texture,
		material: FloorMaterial,
		top_left: camera.project(Physics.point(Warehouse.layout.min_x, Warehouse.layout.floor_y, Warehouse.layout.min_z)),
		bottom_left: camera.project(Physics.point(Warehouse.layout.min_x, Warehouse.layout.floor_y, Warehouse.layout.max_z)),
		bottom_right: camera.project(Physics.point(Warehouse.layout.max_x, Warehouse.layout.floor_y, Warehouse.layout.max_z)),
		top_right: camera.project(Physics.point(Warehouse.layout.max_x, Warehouse.layout.floor_y, Warehouse.layout.min_z)),
		tint: (0xe1e7eb.Color).with_alpha(230),
		depth: 0,
	},
	{
		texture: model.wall_texture,
		material: PlainMaterial,
		top_left: camera.project(Physics.point(Warehouse.layout.min_x, Warehouse.layout.wall_height, Warehouse.layout.min_z - 2)),
		bottom_left: camera.project(Physics.point(Warehouse.layout.min_x, 0, Warehouse.layout.min_z - 2)),
		bottom_right: camera.project(Physics.point(Warehouse.layout.max_x, 0, Warehouse.layout.min_z - 2)),
		top_right: camera.project(Physics.point(Warehouse.layout.max_x, Warehouse.layout.wall_height, Warehouse.layout.min_z - 2)),
		tint: (0xd2d9df.Color).with_alpha(215),
		depth: 0,
	},
	{
		texture: model.wall_texture,
		material: PlainMaterial,
		top_left: camera.project(Physics.point(Warehouse.layout.min_x - 2, Warehouse.layout.wall_height, Warehouse.layout.max_z)),
		bottom_left: camera.project(Physics.point(Warehouse.layout.min_x - 2, 0, Warehouse.layout.max_z)),
		bottom_right: camera.project(Physics.point(Warehouse.layout.min_x - 2, 0, Warehouse.layout.min_z)),
		top_right: camera.project(Physics.point(Warehouse.layout.min_x - 2, Warehouse.layout.wall_height, Warehouse.layout.min_z)),
		tint: (0xb9c4cc.Color).with_alpha(195),
		depth: 0,
	},
]

## The complete scene for one frame, derived from the current model.
scene_for : AppModel, RobotArm.Solution -> SceneRenderer.Scene
scene_for = |model, solution| {
	camera = model.camera
	scene_lines = warehouse_fixture_lines(camera)
		.concat(axis_lines(camera))
		.concat(robot_lines(camera, solution))
	all_lines = if model.show_pga {
		scene_lines.concat(pga_lines(camera, solution))
	} else {
		scene_lines
	}
	all_circles = if model.show_pga {
		pga_motor_circles(camera, solution).concat(robot_circles(model, camera, solution))
	} else {
		robot_circles(model, camera, solution)
	}

	{
		parameters: scene_parameters(model.arm, model.target),
		texture_quads: warehouse_textures(model, camera).concat(warehouse_ground_marks(model, camera)),
		underlay_lines: warehouse_underlay_lines(camera)
			.concat(robot_shadow_lines(camera, solution)),
		overlay_texture_quads: warehouse_faces(model, camera).concat(robot_faces(model, camera, solution)),
		radial_gradients: warehouse_glows(camera, solution),
		lines: all_lines,
		circles: all_circles,
	}
}

viewport_hud : AppModel, RobotArm.Solution -> View(Msg)
viewport_hud = |_model, solution| {
	state_color = if solution.reachable green else red
	box(
		{
			id: LocalId("viewport-hud"),
			style: |_|
				style
					.width(Fit({ min: 0, max: 10000 }))
					.height(Fit({ min: 0, max: 10000 }))
					.background(surface.with_alpha(230))
					.border({ color: cyan.with_alpha(75), left: 1, right: 1, top: 1, bottom: 1 })
					.radius(7)
					.pad(6, 9, 9, 9)
					.gap(7)
					.direction(Row)
					.child_align({ x: Start, y: Center })
					.font_size(13)
					.font_color(ink)
					.spacing(1)
					.floating(
						Floating({
							target: Parent,
							config: {
								..Element.default_floating_config,
								z_index: 10,
								offset: { x: 14, y: 14 },
								capture: Passthrough,
								clip_to: AttachedParent,
							},
						}),
					),
		},
		[
			box(
				{ style: |_| style.width(Fixed(7)).height(Fixed(7)).background(state_color).radius(100) },
				[],
			),
			text("PGA MOTOR // LIVE"),
		],
	)
}

## The canvas leaf's draw closure captures only the resources and the scene.
## It runs synchronously during `render!` with the frame and resolved bounds.
scene_canvas : AppModel -> View(Msg)
scene_canvas = |model| {
	solution = model.arm.solve(model.target)
	scene = scene_for(model, solution)
	resources = model.resources
	Element.canvas(
		|frame, bounds| {
			SceneRenderer.draw!(
				frame,
				resources,
				scene,
				bounds.position.x,
				bounds.position.y,
				bounds.size.w,
				bounds.size.h,
			)
		},
	)
}

workspace_view : AppModel, RobotArm.Solution -> View(Msg)
workspace_view = |model, solution| {
	camera = model.camera
	box(
		{
			id: LocalId("screwbot-workspace"),
			style: |status|
				style
					.width(Grow({ min: 360, max: 10000 }))
					.height(Grow({ min: 420, max: 10000 }))
					.background(
						if status.hovered {
							workspace.lighten(3)
						} else {
							workspace
						},
					)
					.radius(14)
					.border({
						color: if status.focused {
							cyan
						} else {
							grid
						},
						left: 1,
						right: 1,
						top: 1,
						bottom: 1,
					})
					.overflow(Hidden, Hidden),
			events: [
				OnPointer(
					Box.box(
						|event| {
							if event.mouse.right {
								OrbitMove(event.position.x, event.position.y)
							} else if event.mouse.left {
								aim = target_from_pointer(event, model.target, camera).coords()
								AimTarget3D(aim.x, aim.y, aim.z)
							} else {
								PointerIdle
							}
						},
					),
				),
				OnPointerReleased(Mouse.Button.Right, OrbitEnd),
			],
		},
		[
			box(
				{
					style: |_|
						style
							.width(Grow({ min: 0, max: 10000 }))
							.height(Grow({ min: 0, max: 10000 }))
							.overflow(Hidden, Hidden),
				},
				[scene_canvas(model)],
			),
			viewport_hud(model, solution),
		],
	)
}

# Keep dynamic children separate from the model-capturing card style. Combining
# those in one helper currently triggers roc-lang/roc#10560 during codegen.
content_stack : List(View(msg)) -> View(msg)
content_stack = |children| box(
	{
		style: |_|
			style
				.width(Grow({ min: 0, max: 10000 }))
				.height(Fit({ min: 0, max: 10000 }))
				.gap(10)
				.direction(Col)
				.child_align({ x: Start, y: Start }),
	},
	children,
)

card : Str, View(Msg) -> View(Msg)
card = |title, content| {
	title_view = box(
		{
			style: |_|
				style
					.width(Grow({ min: 0, max: 10000 }))
					.height(Fit({ min: 0, max: 10000 }))
					.border({ color: grid.with_alpha(210), left: 0, right: 0, top: 0, bottom: 1 })
					.pad(0, 0, 8, 0)
					.gap(8)
					.direction(Row)
					.child_align({ x: Start, y: Center })
					.font_color(cyan)
					.font_size(14)
					.spacing(2),
		},
		[
			box({ style: |_| style.width(Fixed(3)).height(Fixed(13)).background(cyan).radius(2) }, []),
			text(title),
		],
	)

	box(
		{
			style: |_|
				style
					.width(Grow({ min: 0, max: 10000 }))
					.height(Fit({ min: 0, max: 10000 }))
					.background(surface)
					.radius(12)
					.border({ color: grid, left: 1, right: 1, top: 1, bottom: 1 })
					.pad(12, 14, 12, 14)
					.gap(10)
					.direction(Col)
					.child_align({ x: Start, y: Start })
					.font_size(16)
					.font_color(ink),
		},
		[title_view, content],
	)
}

readout : Str, Str, Color -> View(Msg)
readout = |name, value, color| box(
	{
		style: |_|
			style
				.width(Grow({ min: 0, max: 10000 }))
				.height(Fit({ min: 0, max: 10000 }))
				.gap(6)
				.direction(Row)
				.child_align({ x: Start, y: Center }),
	},
	[
		box(
			{ style: |_| style.width(Fit({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).font_size(13).font_color(muted).text_align(Left) },
			[text(name)],
		),
		box(
			{ style: |_| style.width(Grow({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).font_size(14).font_color(color).text_align(Right) },
			[text(value)],
		),
	],
)

control : AppModel, Str, F32, F32, F32, F32, (F32 -> Msg) -> View(Msg)
control = |model, name, value, min, max, step, on_change| box(
	{
		style: |_|
			style
				.width(Grow({ min: 0, max: 10000 }))
				.height(Fit({ min: 0, max: 10000 }))
				.gap(7)
				.direction(Col)
				.child_align({ x: Start, y: Start }),
	},
	[
		readout(name, decimal(value), ink),
		Widget.slider(model.theme, value, min, max, step, on_change),
	],
)

degrees : F32 -> F32
degrees = |radians| radians * 180 / F32.pi

coefficient_readout : Str, Str, Color -> View(Msg)
coefficient_readout = |basis, values, color| box(
	{
		style: |_|
			style
				.width(Grow({ min: 0, max: 10000 }))
				.height(Fit({ min: 0, max: 10000 }))
				.direction(Col)
				.gap(2)
				.child_align({ x: Start, y: Start }),
	},
	[
		box(
			{ style: |_| style.width(Grow({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).child_align({ x: Start, y: Center }).font_size(12).font_color(muted).text_align(Left) },
			[text(basis)],
		),
		box(
			{ style: |_| style.width(Grow({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).child_align({ x: End, y: Center }).font_size(14).font_color(color).text_align(Right) },
			[text(values)],
		),
	],
)

pga_inspector : RobotArm.Solution -> View(Msg)
pga_inspector = |solution| {
	target = solution.target.point_coeffs()
	upper = solution.upper_axis.line_coeffs()
	motor = solution.target_motor.motor_coeffs()
	plane = solution.ground.plane_coeffs()

	card(
		"PGA LIVE COEFFICIENTS",
		content_stack([
			coefficient_readout("P target 032/013/021", "${decimal(target.e032)}  ${decimal(target.e013)}  ${decimal(target.e021)}", green),
			coefficient_readout("L upper 23/31/12", "${decimal(upper.e23)}  ${decimal(upper.e31)}  ${decimal(upper.e12)}", blue),
			coefficient_readout("T motor 01/02/03", "${decimal(motor.e01)}  ${decimal(motor.e02)}  ${decimal(motor.e03)}", cyan),
			coefficient_readout("plane 0/1/2/3", "${decimal(plane.e0)}  ${decimal(plane.e1)}  ${decimal(plane.e2)}  ${decimal(plane.e3)}", green),
		]),
	)
}

sidebar : AppModel, RobotArm.Solution -> View(Msg)
sidebar = |model, solution| {
	target = model.target.coords()
	state_color = if solution.reachable {
		green
	} else {
		red
	}
	state_label = if solution.reachable {
		"SOLVED"
	} else {
		"OUT OF REACH"
	}
	pga_section = if model.show_pga {
		pga_inspector(solution)
	} else {
		# Avoid roc-lang/roc#10596: local if bindings with an empty iterator
		# branch currently panic in postcheck on the latest nightly.
		content_stack([])
	}

	box(
		{
			style: |_|
				style
					.width(Fixed(380))
					.height(Grow({ min: 0, max: 10000 }))
					.gap(12)
					.direction(Col)
					.overflow(Hidden, Scroll)
					.child_align({ x: Start, y: Start }),
		},
		[
			card(
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
				"TARGET / DRAG IN VIEWPORT",
				content_stack([
					control(model, "X", target.x, -230, 230, 1, |value| SetTargetX(value)),
					control(model, "Y", target.y, 5, 285, 1, |value| SetTargetY(value)),
					control(model, "Z", target.z, -160, 160, 1, |value| SetTargetZ(value)),
				]),
			),
			card(
				"ARM CONFIGURATION",
				content_stack([
					control(model, "upper link", model.arm.upper_length, 60, 170, 1, |value| SetUpperLength(value)),
					control(model, "fore link", model.arm.fore_length, 60, 170, 1, |value| SetForeLength(value)),
					Widget.checkbox(model.theme, model.arm.elbow_up, "Elbow-up branch", |checked| SetElbowUp(checked)),
					Widget.checkbox(model.theme, model.show_pga, "Show PGA construction", |checked| SetShowPga(checked)),
				]),
			),
			pga_section,
		],
	)
}

header : AppModel, RobotArm.Solution -> View(Msg)
header = |model, solution| {
	box(
		{
			style: |_|
				style
					.width(Grow({ min: 0, max: 10000 }))
					.height(Fixed(92))
					.background(surface)
					.border({ color: grid, left: 0, right: 0, top: 0, bottom: 1 })
					.pad(12, 20, 12, 20)
					.gap(14)
					.direction(Row)
					.child_align({ x: Start, y: Center })
					.font_color(ink),
		},
		[
			box(
				{
					style: |_|
						style
							.width(Fit({ min: 0, max: 10000 }))
							.height(Fit({ min: 0, max: 10000 }))
							.direction(Row)
							.gap(12)
							.child_align({ x: Start, y: Center }),
				},
				[
					box({ style: |_| style.width(Fixed(4)).height(Fixed(50)).background(cyan).radius(2) }, []),
					box(
						{
							style: |_|
								style
									.width(Fit({ min: 0, max: 10000 }))
									.height(Fit({ min: 0, max: 10000 }))
									.direction(Col)
									.gap(2)
									.child_align({ x: Start, y: Start }),
						},
						[
							box(
								{ style: |_| style.width(Fit({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).font_size(30).font_color(cyan) },
								[text("SCREWBOT // PGA LAB")],
							),
							box(
								{ style: |_| style.width(Fit({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).font_size(15).font_color(muted) },
								[text("LMB move target  //  RMB orbit warehouse  //  live 3D PGA")],
							),
						],
					),
				],
			),
			box({ style: |_| style.width(Grow({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })) }, []),
			Widget.badge(
				model.theme,
				if solution.reachable {
					Success
				} else {
					Danger
				},
				if solution.reachable {
					"TARGET LOCK"
				} else {
					"LIMIT"
				},
			),
			box(
				{
					style: |_|
						style
							.width(Fit({ min: 0, max: 10000 }))
							.height(Fit({ min: 0, max: 10000 }))
							.background(workspace)
							.border({ color: grid, left: 1, right: 1, top: 1, bottom: 1 })
							.radius(9)
							.pad(4, 4, 4, 4)
							.gap(4)
							.direction(Row)
							.child_align({ x: Start, y: Center }),
				},
				[
					preset_button(False, "ASSEMBLY", AssemblyPose),
					preset_button(False, "FOLDED", FoldedPose),
					preset_button(True, "LONG REACH", LongReachPose),
				],
			),
		],
	)
}

preset_button : Bool, Str, PosePreset -> View(Msg)
preset_button = |accent, label, preset| box(
	{
		style: |status| {
			base_fill = if accent {
				cyan.with_alpha(225)
			} else {
				surface_high
			}
			fill = if status.pressed {
				base_fill.darken(20)
			} else if status.hovered {
				base_fill.lighten(12)
			} else {
				base_fill
			}
			style
				.width(Fit({ min: 0, max: 10000 }))
				.height(Fixed(30))
				.background(fill)
				.border({ color: if accent cyan else 0x2b3c5c.Color, left: 1, right: 1, top: 1, bottom: 1 })
				.radius(6)
				.pad(4, 10, 4, 10)
				.font_size(13)
				.font_color(if accent workspace else ink)
				.spacing(1)
				.child_align({ x: Center, y: Center })
		},
		events: [OnClick(SelectPose(preset))],
	},
	[text(label)],
)

view : AppModel -> View(Msg)
view = |model| {
	solution = model.arm.solve(model.target)

	box(
		{
			style: |_|
				style
					.background(0x0a1020.Color)
					.direction(Col)
					.child_align({ x: Start, y: Start })
					.font_size(17)
					.font_color(ink),
		},
		[
			header(model, solution),
			box(
				{
					style: |_|
						style
							.width(Grow({ min: 0, max: 10000 }))
							.height(Grow({ min: 0, max: 10000 }))
							.pad(16, 16, 16, 16)
							.gap(16)
							.direction(Row)
							.overflow(Hidden, Hidden)
							.child_align({ x: Start, y: Start }),
				},
				[
					workspace_view(model, solution),
					sidebar(model, solution),
				],
			),
		],
	)
}

apply_pose_preset : AppModel, PosePreset -> AppModel
apply_pose_preset = |model, preset| match preset {
	AssemblyPose => { ..model, target: Physics.point(105, 155, 75) }
	FoldedPose => { ..model, target: Physics.point(65, 45, -55), arm: model.arm.with_elbow_up(True) }
	LongReachPose => { ..model, target: Physics.point(205, 105, 35), arm: model.arm.with_elbow_up(False) }
}

## The first right-drag move both starts the orbit and is not itself a delta,
## so the camera does not jump on the initial press.
drag_orbit : AppModel, Point2 -> AppModel
drag_orbit = |model, position| match model.orbit {
	OrbitIdle => { ..model, orbit: Orbiting(position) }
	Orbiting(previous) => {
		dx = position.x - previous.x
		dy = position.y - previous.y
		{
			..model,
			camera: model.camera.orbit(dx, dy),
			orbit: Orbiting(position),
		}
	}
}

end_orbit : AppModel -> AppModel
end_orbit = |model| { ..model, orbit: OrbitIdle }

update : AppModel, Msg -> AppModel
update = |model, msg| {
	target = model.target.coords()
	match msg {
		AimTarget3D(x, y, z) => { ..model, target: Physics.point(x, y, z) }
		PointerIdle => model
		OrbitMove(x, y) => drag_orbit(model, { x, y })
		OrbitEnd => end_orbit(model)
		SetTargetX(x) => { ..model, target: Physics.point(x, target.y, target.z) }
		SetTargetY(y) => { ..model, target: Physics.point(target.x, y, target.z) }
		SetTargetZ(z) => { ..model, target: Physics.point(target.x, target.y, z) }
		SetUpperLength(length) => { ..model, arm: model.arm.with_upper_length(length) }
		SetForeLength(length) => { ..model, arm: model.arm.with_fore_length(length) }
		SetElbowUp(elbow_up) => { ..model, arm: model.arm.with_elbow_up(elbow_up) }
		SetShowPga(show_pga) => { ..model, show_pga }
		SelectPose(preset) => apply_pose_preset(model, preset)
	}
}

assets_dir = "examples/assets"

## Load every GPU resource up front. All of these effects are legal only in
## `init!`; the loaded textures, shaders, and render targets are then owned by
## the model for the lifetime of the app.
resources! : App.Io => Try(SceneRenderer.Resources, [Exit(I64)])
resources! = |io| {
	directory = io.files().open_dir_read!(assets_dir).map_err(|_| Exit(1))?
	store = Assets.open!(directory, IgnoreManifest).map_err(|_| Exit(1))?
	crate = Assets.load_texture!(store, "screwbot-crate-v2.png").map_err(|_| Exit(1))?
	floor = Assets.load_texture!(store, "screwbot-floor.png").map_err(|_| Exit(1))?
	wall = Assets.load_texture!(store, "screwbot-wall.png").map_err(|_| Exit(1))?
	white = Assets.load_texture!(store, "screwbot-white.png").map_err(|_| Exit(1))?
	Assets.set_texture_filter!(crate, Bilinear)
	Assets.set_texture_filter!(floor, Bilinear)
	Assets.set_texture_filter!(wall, Bilinear)

	scene_target = Draw.RenderTexture.load!(SceneRenderer.scene_size).map_err(|_| Exit(1))?
	bloom_a = Draw.RenderTexture.load!(SceneRenderer.bloom_size).map_err(|_| Exit(1))?
	bloom_b = Draw.RenderTexture.load!(SceneRenderer.bloom_size).map_err(|_| Exit(1))?

	floor_shader = Draw.Shader.from_source!({ vertex_source: "", fragment_source: floor_shader_source }).map_err(|_| Exit(1))?
	robot_shader = Draw.Shader.from_source!({ vertex_source: "", fragment_source: robot_shader_source }).map_err(|_| Exit(1))?
	emissive_shader = Draw.Shader.from_source!({ vertex_source: "", fragment_source: emissive_shader_source }).map_err(|_| Exit(1))?
	blur_shader = Draw.Shader.from_source!({ vertex_source: "", fragment_source: blur_shader_source }).map_err(|_| Exit(1))?
	composite_shader = Draw.Shader.from_source!({ vertex_source: "", fragment_source: scene_shader_source }).map_err(|_| Exit(1))?

	Ok({
		crate,
		floor,
		wall,
		white,
		scene_target,
		bloom_a,
		bloom_b,
		floor_shader,
		robot_shader,
		emissive_shader,
		blur_shader,
		composite_shader,
		floor_time: floor_shader.uniform_f32!("time").map_err(|_| Exit(1))?,
		floor_target_uv: floor_shader.uniform_vec2!("targetUv").map_err(|_| Exit(1))?,
		floor_reachable: floor_shader.uniform_f32!("reachable").map_err(|_| Exit(1))?,
		floor_error: floor_shader.uniform_f32!("errorAmount").map_err(|_| Exit(1))?,
		robot_time: robot_shader.uniform_f32!("time").map_err(|_| Exit(1))?,
		robot_reachable: robot_shader.uniform_f32!("reachable").map_err(|_| Exit(1))?,
		robot_error: robot_shader.uniform_f32!("errorAmount").map_err(|_| Exit(1))?,
		blur_direction: blur_shader.uniform_vec2!("direction").map_err(|_| Exit(1))?,
		blur_resolution: blur_shader.uniform_vec2!("resolution").map_err(|_| Exit(1))?,
		composite_time: composite_shader.uniform_f32!("time").map_err(|_| Exit(1))?,
		composite_resolution: composite_shader.uniform_vec2!("resolution").map_err(|_| Exit(1))?,
		composite_bloom: composite_shader.uniform_texture!("bloomTexture").map_err(|_| Exit(1))?,
	})
}

configure : List(Str) -> App.Config
configure = |_args|
	App.default
		.with_title("Screwbot // PGA Kinematics Lab")
		.with_size({ width: 1280, height: 900 })
		.with_resizable(True)
		.with_permission(Directory(assets_dir, ReadOnly))

init! : App.InitCallback(AppModel, [])
init! = |io| {
	resources = resources!(io)?
	Ok({
		theme: Theme.from_seed({
			background: surface,
			text: ink,
			primary: cyan,
			success: green,
			warning: amber,
			danger: red,
		}),
		resources,
		crate_texture: resources.crate,
		floor_texture: resources.floor,
		wall_texture: resources.wall,
		white_texture: resources.white,

		## The robot links reuse the 2x2 white texture as an untextured proxy.
		robot_texture: resources.white,
		target: Physics.point(145, 145, 60),
		arm: { upper_length: 132, fore_length: 118, elbow_up: False },
		show_pga: True,
		camera: { yaw: 0.48, pitch: 0.34 },
		orbit: OrbitIdle,
	})
}

program = Program.new(configure, init!, update, view)
