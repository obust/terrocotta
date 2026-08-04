## Screwbot: an interactive inverse-kinematics workbench.
##
## The solver produces a robot pose in ordinary joint-angle space, then stores
## the mechanism as roc-ray 3D PGA points, lines, a plane, and a translation
## motor. Terracotta renders the projected geometry and exposes its live PGA
## coefficients as a small inspection console.
app [Model, program] {
	rr: platform "../../../roc-ray/platform/main.roc",
	tc: "../../package/main.roc",
}

import rr.App
import rr.Draw
import rr.Host
import rr.Physics
import rr.Assets

import tc.Color
import tc.Element exposing [Font, View, box, canvas, style, text]
import tc.Event
import tc.Program
import tc.Render
import tc.Theme
import tc.Widget

import RobotArm
import SceneCamera exposing [Point2]
import SceneRenderer
import Warehouse exposing [Bounds3]

Model :: Program.FrameState(AppModel, Msg, Draw.Frame)

AppModel : {
	theme : Theme,
	crate_texture : Element.Texture,
	floor_texture : Element.Texture,
	wall_texture : Element.Texture,
	white_texture : Element.Texture,
	robot_texture : Element.Texture,
	floor_time : Draw.F32Uniform,
	floor_target_uv : Draw.Vec2Uniform,
	floor_reachable : Draw.F32Uniform,
	floor_error : Draw.F32Uniform,
	robot_time : Draw.F32Uniform,
	robot_reachable : Draw.F32Uniform,
	robot_error : Draw.F32Uniform,
	composite_time : Draw.F32Uniform,
	target : Physics.Point,
	arm : RobotArm,
	show_pga : Bool,
	screen_width : F32,
	screen_height : F32,
	camera : SceneCamera,
	orbit : OrbitState,
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
	SelectPose(PosePreset),
]

## Pointer-drag state for the orbit camera interaction.
OrbitState := [OrbitIdle, Orbiting(Point2)]

## A named target configuration exposed by the preset controls.
PosePreset := [AssemblyPose, FoldedPose, LongReachPose]

ProjectedFace : {
	depth : F32,
	top_left : Point2,
	bottom_left : Point2,
	bottom_right : Point2,
	top_right : Point2,
	tint : Color,
}

## The three warehouse-space axes available to the overlay renderer.
AxisLabel := [XAxis, YAxis, ZAxis]

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
clamp = |value, lo, hi| F32.max(lo, F32.min(value, hi))

decimal : F32 -> Str
decimal = |value| {
	match F32.round_to_i64_try(value * 10) {
		Ok(scaled) => (I64.to_f32(scaled) / 10).to_str()
		Err(_) => value.to_str()
	}
}

line : Point2, Point2, F32, Color -> Element.CanvasLine
line = |start, end, thickness, color| { start, end, thickness, color, depth: SceneCamera.far_depth }

circle : Point2, F32, Color -> Element.CanvasCircle
circle = |center, radius, color| { center, radius, color, depth: SceneCamera.far_depth }

radial_gradient : Point2, F32, Color, Color -> Element.CanvasRadialGradient
radial_gradient = |center, radius, inner, outer| { center, radius, inner, outer }

world_line : SceneCamera, Physics.Point, Physics.Point, F32, Color -> Element.CanvasLine
world_line = |camera, start, end, thickness, color| {
	{
		..line(camera.project(start), camera.project(end), thickness, color),
		depth: (camera.depth(start) + camera.depth(end)) * 0.5,
	}
}

grid_values : List(F32)
grid_values = [-240, -200, -160, -120, -80, -40, 0, 40, 80, 120, 160, 200, 240]

ground_grid : SceneCamera -> List(Element.CanvasLine)
ground_grid = |camera| {
	along_x = grid_values.map(|z| world_line(camera, Physics.point(-260, 0, z), Physics.point(260, 0, z), 1, grid))
	along_z = grid_values.map(|x| world_line(camera, Physics.point(x, 0, -240), Physics.point(x, 0, 240), 1, grid))
	along_x.concat(along_z)
}

axis_letter : AxisLabel, Point2, Color, F32 -> List(Element.CanvasLine)
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

axis_with_label : SceneCamera, Physics.Point, AxisLabel, Color -> List(Element.CanvasLine)
axis_with_label = |camera, end_world, label, color| {
	start = camera.project(Physics.origin)
	end = camera.project(end_world)
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
	depth = (camera.depth(Physics.origin) + camera.depth(end_world)) * 0.5

	[
		{ ..line(start, end, 4, color), depth },
		{ ..line(end, left_wing, 4, color), depth },
		{ ..line(end, right_wing, 4, color), depth },
	].concat(axis_letter(label, label_center, color, depth))
}

axis_lines : SceneCamera -> List(Element.CanvasLine)
axis_lines = |camera| axis_with_label(camera, Physics.point(125, 0, 0), XAxis, red)
	.concat(axis_with_label(camera, Physics.point(0, 125, 0), YAxis, green))
	.concat(axis_with_label(camera, Physics.point(0, 0, 125), ZAxis, blue))

link_parallel : Point2, Point2, F32, F32, Color -> Element.CanvasLine
link_parallel = |start, end, offset, thickness, color| {
	dx = end.x - start.x
	dy = end.y - start.y
	length = F32.max(F32.sqrt(dx * dx + dy * dy), 1)
	normal_x = (0 - dy) / length * offset
	normal_y = dx / length * offset
	line(
		{ x: start.x + normal_x, y: start.y + normal_y },
		{ x: end.x + normal_x, y: end.y + normal_y },
		thickness,
		color,
	)
}

link_tick : Point2, Point2, F32, F32, Color -> Element.CanvasLine
link_tick = |start, end, along, width, color| {
	dx = end.x - start.x
	dy = end.y - start.y
	length = F32.max(F32.sqrt(dx * dx + dy * dy), 1)
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

robot_lines : SceneCamera, RobotArm.Solution -> List(Element.CanvasLine)
robot_lines = |camera, solution| {
	base_screen = camera.project(solution.base)
	elbow_screen = camera.project(solution.elbow)
	tool_screen = camera.project(solution.tool)
	target_screen = camera.project(solution.target)
	target_ground_screen = camera.project(solution.target_ground)

	tool_vector = Physics.components(Physics.sub(solution.tool, solution.elbow))
	tool_len = F32.max(Physics.length(Physics.sub(solution.tool, solution.elbow)), 1)
	side = Physics.vector(0 - tool_vector.y / tool_len, tool_vector.x / tool_len, 0)
	finger_root = Physics.add(solution.tool, Physics.scale(side, 9))
	finger_tip = Physics.add(solution.tool, Physics.scale(side, -9))
	forward = Physics.normalize(Physics.sub(solution.tool, solution.elbow))
	finger_one = Physics.add(finger_root, Physics.scale(forward, 17))
	finger_two = Physics.add(finger_tip, Physics.scale(forward, 17))
	upper_depth = (camera.depth(solution.base) + camera.depth(solution.elbow)) * 0.5
	fore_depth = (camera.depth(solution.elbow) + camera.depth(solution.tool)) * 0.5

	[
		{ ..link_parallel(base_screen, elbow_screen, -4, 2, Color.with_alpha(ink, 185)), depth: upper_depth + 0.003 },
		{ ..link_parallel(base_screen, elbow_screen, 4, 1.5, Color.with_alpha(cyan, 210)), depth: upper_depth + 0.004 },
		{ ..link_tick(base_screen, elbow_screen, 0.30, 15, Color.with_alpha(shadow, 180)), depth: upper_depth + 0.005 },
		{ ..link_tick(base_screen, elbow_screen, 0.56, 15, Color.with_alpha(shadow, 180)), depth: upper_depth + 0.005 },
		{ ..link_tick(base_screen, elbow_screen, 0.82, 14, Color.with_alpha(shadow, 180)), depth: upper_depth + 0.005 },
		{ ..link_parallel(elbow_screen, tool_screen, -3.5, 2, Color.with_alpha(0xffe0a3.Color, 190)), depth: fore_depth + 0.003 },
		{ ..link_parallel(elbow_screen, tool_screen, 3.5, 1.5, Color.with_alpha(violet, 220)), depth: fore_depth + 0.004 },
		{ ..link_tick(elbow_screen, tool_screen, 0.34, 13, Color.with_alpha(shadow, 180)), depth: fore_depth + 0.005 },
		{ ..link_tick(elbow_screen, tool_screen, 0.68, 12, Color.with_alpha(shadow, 180)), depth: fore_depth + 0.005 },
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

robot_shadow_lines : SceneCamera, RobotArm.Solution -> List(Element.CanvasLine)
robot_shadow_lines = |camera, solution| [
	world_line(camera, shadow_on_ground(solution.base), shadow_on_ground(solution.elbow), 22, Color.with_alpha(shadow, 150)),
	world_line(camera, shadow_on_ground(solution.elbow), shadow_on_ground(solution.tool), 19, Color.with_alpha(shadow, 140)),
]

link_quad : Element.Texture, Point2, Point2, F32, F32, Color, F32 -> Element.CanvasTextureQuad
link_quad = |texture_value, start, end, start_width, end_width, tint, depth| {
	dx = end.x - start.x
	dy = end.y - start.y
	length = F32.max(F32.sqrt(dx * dx + dy * dy), 1)
	start_normal_x = (0 - dy) / length * start_width * 0.5
	start_normal_y = dx / length * start_width * 0.5
	end_normal_x = (0 - dy) / length * end_width * 0.5
	end_normal_y = dx / length * end_width * 0.5
	{
		texture: texture_value,
		top_left: { x: start.x + start_normal_x, y: start.y + start_normal_y },
		bottom_left: { x: start.x - start_normal_x, y: start.y - start_normal_y },
		bottom_right: { x: end.x - end_normal_x, y: end.y - end_normal_y },
		top_right: { x: end.x + end_normal_x, y: end.y + end_normal_y },
		tint,
		depth,
	}
}

robot_faces : AppModel, SceneCamera, RobotArm.Solution -> List(Element.CanvasTextureQuad)
robot_faces = |model, camera, solution| {
	base = camera.project(solution.base)
	elbow = camera.project(solution.elbow)
	tool = camera.project(solution.tool)
	upper_depth = (camera.depth(solution.base) + camera.depth(solution.elbow)) * 0.5
	fore_depth = (camera.depth(solution.elbow) + camera.depth(solution.tool)) * 0.5
	[
		link_quad(model.robot_texture, base, elbow, 38, 30, 0x10192c.Color, upper_depth),
		link_quad(model.robot_texture, base, elbow, 27, 19, blue, upper_depth + 0.001),
		link_quad(model.robot_texture, elbow, tool, 33, 25, 0x211831.Color, fore_depth),
		link_quad(model.robot_texture, elbow, tool, 23, 15, violet, fore_depth + 0.001),
	]
}

pga_lines : SceneCamera, RobotArm.Solution -> List(Element.CanvasLine)
pga_lines = |camera, solution| {
	if solution.reachable {
		[world_line(camera, solution.base, solution.target, 1, Color.with_alpha(cyan, 95))]
	} else {
		[world_line(camera, solution.tool, solution.target, 2, red)]
	}
}

pga_motor_circles : SceneCamera, RobotArm.Solution -> List(Element.CanvasCircle)
pga_motor_circles = |camera, solution| {
	direction = Physics.sub(solution.target, solution.base)
	[
		circle(camera.project(Physics.add(solution.base, Physics.scale(direction, 0.18))), 2.5, Color.with_alpha(cyan, 45)),
		circle(camera.project(Physics.add(solution.base, Physics.scale(direction, 0.34))), 3, Color.with_alpha(cyan, 65)),
		circle(camera.project(Physics.add(solution.base, Physics.scale(direction, 0.50))), 3.5, Color.with_alpha(cyan, 90)),
		circle(camera.project(Physics.add(solution.base, Physics.scale(direction, 0.66))), 3, Color.with_alpha(cyan, 115)),
		circle(camera.project(Physics.add(solution.base, Physics.scale(direction, 0.82))), 2.5, Color.with_alpha(cyan, 145)),
	]
}

shadow_on_ground : Physics.Point -> Physics.Point
shadow_on_ground = |point| {
	c = Physics.coords(point)
	Physics.point(c.x + c.y * 0.22, 1, c.z + c.y * 0.16)
}

robot_circles : AppModel, SceneCamera, RobotArm.Solution -> List(Element.CanvasCircle)
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
	base_depth = F32.max(base_point_depth, upper_depth) + 0.01
	elbow_depth = F32.max(elbow_point_depth, F32.max(upper_depth, fore_depth)) + 0.01
	tool_depth = F32.max(tool_point_depth, fore_depth) + 0.01

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
	relative = Event.ElementBounds.relative(event.target.bounds, event.position)
	scale_x = event.target.bounds.width / SceneCamera.view_width
	scale_y = event.target.bounds.height / SceneCamera.view_height
	canvas_scale = F32.max(F32.min(scale_x, scale_y), 0.001)
	offset_x = (event.target.bounds.width - SceneCamera.view_width * canvas_scale) * 0.5
	offset_y = (event.target.bounds.height - SceneCamera.view_height * canvas_scale) * 0.5
	screen_x = (relative.x - offset_x) / canvas_scale
	screen_y = (relative.y - offset_y) / canvas_scale
	camera.target_at(current_target, { x: screen_x, y: screen_y })
}

projected_face : SceneCamera, Physics.Point, Physics.Point, Physics.Point, Physics.Point, Color -> ProjectedFace
projected_face = |camera, top_left, bottom_left, bottom_right, top_right, tint| {
	{
		depth: (camera.depth(top_left) + camera.depth(bottom_left) + camera.depth(bottom_right) + camera.depth(top_right)) / 4,
		top_left: camera.project(top_left),
		bottom_left: camera.project(bottom_left),
		bottom_right: camera.project(bottom_right),
		top_right: camera.project(top_right),
		tint,
	}
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
		projected_face(camera, p010, p011, p111, p110, Color.lighten(color, 38)),
		projected_face(camera, p011, p001, p101, p111, Color.lighten(color, 8)),
		projected_face(camera, p010, p000, p001, p011, Color.darken(color, 30)),
		projected_face(camera, p110, p111, p101, p100, Color.lighten(color, 18)),
		projected_face(camera, p010, p110, p100, p000, Color.darken(color, 12)),
		projected_face(camera, p001, p000, p100, p101, Color.darken(color, 45)),
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

face_quad : Element.Texture, ProjectedFace -> Element.CanvasTextureQuad
face_quad = |texture_value, face| {
	texture: texture_value,
	top_left: face.top_left,
	bottom_left: face.bottom_left,
	bottom_right: face.bottom_right,
	top_right: face.top_right,
	tint: face.tint,
	depth: face.depth,
}

carton_ground_shadow : AppModel, SceneCamera, Bounds3 -> Element.CanvasTextureQuad
carton_ground_shadow = |model, camera, bounds| {
	margin = 7
	offset_x = 7
	offset_z = 5
	face_quad(
		model.white_texture,
		projected_face(
			camera,
			Physics.point(bounds.min_x - margin + offset_x, Warehouse.layout.floor_y + 0.4, bounds.min_z - margin + offset_z),
			Physics.point(bounds.min_x - margin + offset_x, Warehouse.layout.floor_y + 0.4, bounds.max_z + margin + offset_z),
			Physics.point(bounds.max_x + margin + offset_x, Warehouse.layout.floor_y + 0.4, bounds.max_z + margin + offset_z),
			Physics.point(bounds.max_x + margin + offset_x, Warehouse.layout.floor_y + 0.4, bounds.min_z - margin + offset_z),
			Color.with_alpha(shadow, 105),
		),
	)
}

warehouse_ground_marks : AppModel, SceneCamera -> List(Element.CanvasTextureQuad)
warehouse_ground_marks = |model, camera| {
	light_pool = projected_face(
		camera,
		Physics.point(-185, 0.5, -165),
		Physics.point(-215, 0.5, 80),
		Physics.point(100, 0.5, 80),
		Physics.point(70, 0.5, -165),
		Color.with_alpha(cyan, 13),
	)
	safety_zone = projected_face(
		camera,
		Physics.point(-92, 0.8, -78),
		Physics.point(-92, 0.8, 78),
		Physics.point(92, 0.8, 78),
		Physics.point(92, 0.8, -78),
		Color.with_alpha(amber, 16),
	)
	[
		face_quad(model.white_texture, light_pool),
		face_quad(model.white_texture, safety_zone),
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
	tape_half = F32.max(2.5, width * 0.045)
	tape_color = Color.with_alpha(0xe1c38f.Color, 218)
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
		label = projected_face(camera, Physics.point(label_min_x, label_max_y, label_z), Physics.point(label_min_x, label_min_y, label_z), Physics.point(label_max_x, label_min_y, label_z), Physics.point(label_max_x, label_max_y, label_z), Color.with_alpha(0xdbe5e8.Color, 224))
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

warehouse_faces : AppModel, SceneCamera -> List(Element.CanvasTextureQuad)
warehouse_faces = |model, camera| {
	steel = 0x30415b.Color
	crate = 0xd9d3c8.Color

	var $structure_faces = []
	for bounds in Warehouse.layout.structure() {
		$structure_faces = $structure_faces.concat(cuboid_faces(camera, bounds, steel))
	}
	$structure_faces = $structure_faces.concat(cuboid_faces(camera, { min_x: -34, min_y: -10, min_z: -34, max_x: 34, max_y: 0, max_z: 34 }, 0x263248.Color))

	box_faces = cuboid_faces(camera, Warehouse.carton_right_lower, crate)
		.concat(cuboid_faces(camera, Warehouse.carton_right_upper, Color.darken(crate, 7)))
		.concat(cuboid_faces(camera, Warehouse.carton_left, crate))
	var $pallet_faces = []
	for bounds in Warehouse.pallet_left.pallet_parts() {
		$pallet_faces = $pallet_faces.concat(cuboid_faces(camera, bounds, 0x8f7254.Color))
	}
	decal_faces = carton_decal_faces(camera, Warehouse.carton_right_lower, True)
		.concat(carton_decal_faces(camera, Warehouse.carton_right_upper, False))
		.concat(carton_decal_faces(camera, Warehouse.carton_left, True))

	textured_faces = $structure_faces.map(|face| { face, texture: model.white_texture })
		.concat(box_faces.map(|face| { face, texture: model.crate_texture }))
		.concat($pallet_faces.map(|face| { face, texture: model.white_texture }))
		.concat(decal_faces.map(|face| { face, texture: model.white_texture }))

	textured_faces
		.sort_with(|a, b| if a.face.depth < b.face.depth LT else if a.face.depth > b.face.depth GT else EQ)
		.map(|item| face_quad(item.texture, item.face))
}

warehouse_underlay_lines : SceneCamera -> List(Element.CanvasLine)
warehouse_underlay_lines = |camera| {
	rear_seams = [-200, -120, -40, 40, 120, 200].map(
		|x|
			world_line(camera, Physics.point(x, 0, -241), Physics.point(x, 235, -241), 1, Color.with_alpha(muted, 45)),
	)
	safety = [
		world_line(camera, Physics.point(-92, 1.2, -78), Physics.point(92, 1.2, -78), 3, Color.with_alpha(amber, 155)),
		world_line(camera, Physics.point(92, 1.2, -78), Physics.point(92, 1.2, 78), 3, Color.with_alpha(amber, 155)),
		world_line(camera, Physics.point(92, 1.2, 78), Physics.point(-92, 1.2, 78), 3, Color.with_alpha(amber, 155)),
		world_line(camera, Physics.point(-92, 1.2, 78), Physics.point(-92, 1.2, -78), 3, Color.with_alpha(amber, 155)),
	]
	safety_stripes = [-66, -42, -18, 6, 30, 54].map(
		|z|
			world_line(camera, Physics.point(-92, 1.4, z - 10), Physics.point(-73, 1.4, z + 10), 3, Color.with_alpha(amber, 135)),
	)
	rear_seams.concat(safety).concat(safety_stripes)
}

warehouse_fixture_lines : SceneCamera -> List(Element.CanvasLine)
warehouse_fixture_lines = |camera| {
	lamp_cores = [-125, 65].map(
		|z|
			world_line(camera, Physics.point(-103, Warehouse.layout.fixture_y - 6, z), Physics.point(103, Warehouse.layout.fixture_y - 6, z), 4, Color.with_alpha(cyan, 235)),
	)
	lamp_cores
}

warehouse_glows : SceneCamera, RobotArm.Solution -> List(Element.CanvasRadialGradient)
warehouse_glows = |camera, solution| {
	lamp_a = camera.project(Physics.point(0, 280, -125))
	lamp_b = camera.project(Physics.point(0, 280, 65))
	floor_a = camera.project(Physics.point(-40, 2, -105))
	floor_b = camera.project(Physics.point(45, 2, 70))
	target = camera.project(solution.target)
	target_color = if solution.reachable {
		green
	} else {
		red
	}

	[
		radial_gradient(lamp_a, 105, Color.with_alpha(cyan, 32), Color.with_alpha(cyan, 0)),
		radial_gradient(lamp_b, 105, Color.with_alpha(cyan, 28), Color.with_alpha(cyan, 0)),
		radial_gradient(floor_a, 175, Color.with_alpha(cyan, 12), Color.with_alpha(cyan, 0)),
		radial_gradient(floor_b, 155, Color.with_alpha(blue, 9), Color.with_alpha(blue, 0)),
		radial_gradient(target, 48, Color.with_alpha(target_color, 38), Color.with_alpha(target_color, 0)),
	]
}

warehouse_textures : AppModel, SceneCamera -> List(Element.CanvasTextureQuad)
warehouse_textures = |model, camera| [
	{
		texture: model.floor_texture,
		top_left: camera.project(Physics.point(Warehouse.layout.min_x, Warehouse.layout.floor_y, Warehouse.layout.min_z)),
		bottom_left: camera.project(Physics.point(Warehouse.layout.min_x, Warehouse.layout.floor_y, Warehouse.layout.max_z)),
		bottom_right: camera.project(Physics.point(Warehouse.layout.max_x, Warehouse.layout.floor_y, Warehouse.layout.max_z)),
		top_right: camera.project(Physics.point(Warehouse.layout.max_x, Warehouse.layout.floor_y, Warehouse.layout.min_z)),
		tint: Color.with_alpha(0xe1e7eb.Color, 230),
		depth: 0,
	},
	{
		texture: model.wall_texture,
		top_left: camera.project(Physics.point(Warehouse.layout.min_x, Warehouse.layout.wall_height, Warehouse.layout.min_z - 2)),
		bottom_left: camera.project(Physics.point(Warehouse.layout.min_x, 0, Warehouse.layout.min_z - 2)),
		bottom_right: camera.project(Physics.point(Warehouse.layout.max_x, 0, Warehouse.layout.min_z - 2)),
		top_right: camera.project(Physics.point(Warehouse.layout.max_x, Warehouse.layout.wall_height, Warehouse.layout.min_z - 2)),
		tint: Color.with_alpha(0xd2d9df.Color, 215),
		depth: 0,
	},
	{
		texture: model.wall_texture,
		top_left: camera.project(Physics.point(Warehouse.layout.min_x - 2, Warehouse.layout.wall_height, Warehouse.layout.max_z)),
		bottom_left: camera.project(Physics.point(Warehouse.layout.min_x - 2, 0, Warehouse.layout.max_z)),
		bottom_right: camera.project(Physics.point(Warehouse.layout.min_x - 2, 0, Warehouse.layout.min_z)),
		top_right: camera.project(Physics.point(Warehouse.layout.min_x - 2, Warehouse.layout.wall_height, Warehouse.layout.min_z)),
		tint: Color.with_alpha(0xb9c4cc.Color, 195),
		depth: 0,
	},
]

viewport_hud : AppModel, RobotArm.Solution -> View(Msg)
viewport_hud = |model, solution| {
	state_color = if solution.reachable green else red
	box(
		LocalId("viewport-hud"),
		|_| style
			.width(Fit({ min: 0, max: 10000 }))
			.height(Fit({ min: 0, max: 10000 }))
			.background(Color.with_alpha(surface, 230))
			.shadow({ color: Color.with_alpha(shadow, 150), offset_x: 0, offset_y: 4, blur: 9, spread: 0 })
			.border({ color: Color.with_alpha(cyan, 75), left: 1, right: 1, top: 1, bottom: 1 })
			.radius(7)
			.pad((9, 9, 6, 6))
			.gap(7)
			.direction(Row)
			.child_align({ x: Start, y: Center })
			.font_family(model.theme.font)
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
		[],
		[
			box(Auto, |_| style.width(Fixed(7)).height(Fixed(7)).background(state_color).radius(100), [], []),
			text("PGA MOTOR // LIVE"),
		],
	)
}

workspace_view : AppModel, RobotArm.Solution -> View(Msg)
workspace_view = |model, solution| {
	camera = model.camera
	compact = model.screen_width < 1000
	underlay_lines = warehouse_underlay_lines(camera)
		.concat(robot_shadow_lines(camera, solution))
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

	box(
		Id("screwbot-workspace"),
		|status| style
			.width(Grow({ min: 360, max: 10000 }))
			.height(
				if compact {
					Fixed(F32.max(420, F32.min(560, model.screen_height * 0.62)))
				} else {
					Grow({ min: 420, max: 10000 })
				},
			)
			.background(
				if status.hovered {
					workspace.lighten(3)
				} else {
					workspace
				},
			)
			.shadow({ color: Color.with_alpha(shadow, 180), offset_x: 0, offset_y: 8, blur: 16, spread: 1 })
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
				view_width: SceneCamera.view_width,
				view_height: SceneCamera.view_height,
				texture_quads: warehouse_textures(model, camera).concat(warehouse_ground_marks(model, camera)),
				underlay_lines,
				overlay_texture_quads: warehouse_faces(model, camera).concat(robot_faces(model, camera, solution)),
				radial_gradients: warehouse_glows(camera, solution),
				lines: all_lines,
				circles: all_circles,
			}),
			viewport_hud(model, solution),
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
			.border({ color: Color.with_alpha(grid, 210), left: 0, right: 0, top: 0, bottom: 1 })
			.pad((0, 0, 0, 8))
			.gap(8)
			.direction(Row)
			.child_align({ x: Start, y: Center })
			.font_color(cyan)
			.font_size(14)
			.spacing(2),
		[],
		[
			box(Auto, |_| style.width(Fixed(3)).height(Fixed(13)).background(cyan).radius(2), [], []),
			text(title),
		],
	)

	box(
		Auto,
		|_| style
			.width(Grow({ min: 0, max: 10000 }))
			.height(Fit({ min: 0, max: 10000 }))
			.background(surface)
			.shadow({ color: Color.with_alpha(shadow, 145), offset_x: 0, offset_y: 5, blur: 10, spread: 0 })
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
			.direction(Col)
			.gap(2)
			.child_align({ x: Start, y: Start }),
		[],
		[
			box(
				Auto,
				|_| style
					.width(Grow({ min: 0, max: 10000 }))
					.height(Fit({ min: 0, max: 10000 }))
					.child_align({ x: Start, y: Center })
					.font_size(12)
					.font_color(muted)
					.text_align(Left),
				[],
				[text(basis)],
			),
			box(
				Auto,
				|_| style
					.width(Grow({ min: 0, max: 10000 }))
					.height(Fit({ min: 0, max: 10000 }))
					.child_align({ x: End, y: Center })
					.font_size(14)
					.font_color(color)
					.text_align(Right),
				[],
				[text(values)],
			),
		],
	)
}

pga_inspector : AppModel, RobotArm.Solution -> View(Msg)
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

sidebar : AppModel, RobotArm.Solution -> View(Msg)
sidebar = |model, solution| {
	target = Physics.coords(model.target)
	compact = model.screen_width < 1000
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
		pga_inspector(model, solution)
	} else {
		# Avoid roc-lang/roc#10596: local if bindings with an empty iterator
		# branch currently panic in postcheck on the latest nightly.
		content_stack([])
	}

	box(
		Auto,
		|_| style
			.width(
				if compact {
					Grow({ min: 360, max: 10000 })
				} else {
					Fixed(380)
				},
			)
			.height(
				if compact {
					Fit({ min: 0, max: 10000 })
				} else {
					Grow({ min: 0, max: 10000 })
				},
			)
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
	compact = model.screen_width < 1000

	box(
		Auto,
		|_| style
			.width(Grow({ min: 0, max: 10000 }))
			.height(Fixed(if compact 82 else 92))
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
				|_| style.width(Fit({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).direction(Row).gap(12).child_align({ x: Start, y: Center }),
				[],
				[
					box(Auto, |_| style.width(Fixed(4)).height(Fixed(if compact 42 else 50)).background(cyan).radius(2).shadow({ color: Color.with_alpha(cyan, 80), offset_x: 0, offset_y: 0, blur: 7, spread: 0 }), [], []),
					box(
						Auto,
						|_| style.width(Fit({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).direction(Col).gap(2).child_align({ x: Start, y: Start }),
						[],
						[
							box(Auto, |_| style.width(Fit({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).font_size(if compact 24 else 30).font_color(cyan), [], [text("SCREWBOT // PGA LAB")]),
							box(Auto, |_| style.width(Fit({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).font_size(15).font_color(muted), [], [text(if compact "LMB target  //  RMB orbit" else "LMB move target  //  RMB orbit warehouse  //  live 3D PGA")]),
						],
					),
				],
			),
			box(Auto, |_| style.width(Grow({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })), [], []),
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
				Auto,
				|_| style.width(Fit({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).background(workspace).border({ color: grid, left: 1, right: 1, top: 1, bottom: 1 }).radius(9).pad((4, 4, 4, 4)).gap(4).direction(Row).child_align({ x: Start, y: Center }),
				[],
				[
					preset_button(model, False, if compact "A" else "ASSEMBLY", AssemblyPose),
					preset_button(model, False, if compact "F" else "FOLDED", FoldedPose),
					preset_button(model, True, if compact "REACH" else "LONG REACH", LongReachPose),
				],
			),
		],
	)
}

preset_button : AppModel, Bool, Str, PosePreset -> View(Msg)
preset_button = |model, accent, label, preset| {
	box(
		Auto,
		|status| {
			base_fill = if accent {
				Color.with_alpha(cyan, 225)
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
				.pad((10, 10, 4, 4))
				.font_family(model.theme.font)
				.font_size(13)
				.font_color(if accent workspace else ink)
				.spacing(1)
				.child_align({ x: Center, y: Center })
		},
		[OnClick(SelectPose(preset))],
		[text(label)],
	)
}

view : AppModel -> View(Msg)
view = |model| {
	solution = RobotArm.solve(model.arm, model.target)
	compact = model.screen_width < 1000

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
					.pad(if compact (12, 12, 12, 12) else (16, 16, 16, 16))
					.gap(if compact 12 else 16)
					.direction(if compact Col else Row)
					.overflow(Hidden, if compact Scroll else Hidden)
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

apply_pose_preset : AppModel, PosePreset -> AppModel
apply_pose_preset = |model, preset| match preset {
	AssemblyPose => { ..model, target: Physics.point(105, 155, 75) }
	FoldedPose => { ..model, target: Physics.point(65, 45, -55), arm: model.arm.with_elbow_up(True) }
	LongReachPose => { ..model, target: Physics.point(205, 105, 35), arm: model.arm.with_elbow_up(False) }
}

begin_orbit : AppModel, Point2 -> AppModel
begin_orbit = |model, pointer| { ..model, orbit: Orbiting(pointer) }

drag_orbit : AppModel, Point2 -> AppModel
drag_orbit = |model, pointer| match model.orbit {
	OrbitIdle => model
	Orbiting(previous) => {
		dx = pointer.x - previous.x
		dy = pointer.y - previous.y
		{
			..model,
			camera: model.camera.orbit(dx, dy),
			orbit: Orbiting(pointer),
		}
	}
}

end_orbit : AppModel -> AppModel
end_orbit = |model| { ..model, orbit: OrbitIdle }

update : AppModel, Msg -> AppModel
update = |model, msg| {
	target = Physics.coords(model.target)

	match msg {
		AimTarget3D(x, y, z) => { ..model, target: Physics.point(x, y, z) }
		OrbitStart(x, y) => begin_orbit(model, { x, y })
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

font_path : Str
font_path = "examples/assets/Inter-Regular.ttf"

floor_texture_path : Str
floor_texture_path = "examples/assets/polyhaven-hangar-floor-1k.png"

crate_texture_path : Str
crate_texture_path = "examples/assets/polyhaven-cardboard-box-01-diffuse-1k.png"

wall_texture_path : Str
wall_texture_path = "examples/assets/polyhaven-corrugated-iron-03-1k.png"

white_texture_path : Str
white_texture_path = "examples/assets/screwbot-white.png"

scene_shader_path : Str
scene_shader_path = "examples/assets/screwbot-scene.fs"

floor_shader_path : Str
floor_shader_path = "examples/assets/screwbot-floor.fs"

robot_shader_path : Str
robot_shader_path = "examples/assets/screwbot-robot.fs"

emissive_shader_path : Str
emissive_shader_path = "examples/assets/screwbot-emissive.fs"

blur_shader_path : Str
blur_shader_path = "examples/assets/screwbot-blur.fs"

init! : Program.Config => Try({ model : AppModel, renderer : Render.FrameAdapter(Draw.Frame) }, [Exit(I64)])
init! = |config| {
	font_asset = Draw.load_font!({ path: font_path, size: 32 }).map_err(|_| Exit(1))?
	font = SceneRenderer.font(font_asset)
	crate_asset = Assets.Texture.load!(crate_texture_path).map_err(|_| Exit(1))?
	floor_asset = Assets.Texture.load!(floor_texture_path).map_err(|_| Exit(1))?
	wall_asset = Assets.Texture.load!(wall_texture_path).map_err(|_| Exit(1))?
	white_asset = Assets.Texture.load!(white_texture_path).map_err(|_| Exit(1))?
	crate_asset.set_filter!(Bilinear)
	floor_asset.set_filter!(Bilinear)
	wall_asset.set_filter!(Bilinear)
	crate_texture = SceneRenderer.crate_texture(crate_asset)
	floor_texture = SceneRenderer.floor_texture(floor_asset)
	wall_texture = SceneRenderer.wall_texture(wall_asset)
	white_texture = SceneRenderer.white_texture(white_asset)
	robot_texture = SceneRenderer.robot_texture(white_asset)

	scene_target = Draw.RenderTexture.load!({ width: 900, height: 620 }).map_err(|_| Exit(1))?
	bloom_a = Draw.RenderTexture.load!({ width: SceneRenderer.bloom_size.width, height: SceneRenderer.bloom_size.height }).map_err(|_| Exit(1))?
	bloom_b = Draw.RenderTexture.load!({ width: SceneRenderer.bloom_size.width, height: SceneRenderer.bloom_size.height }).map_err(|_| Exit(1))?

	floor_shader = Draw.Shader.load!({ vertex_path: "", fragment_path: floor_shader_path }).map_err(|_| Exit(1))?
	robot_shader = Draw.Shader.load!({ vertex_path: "", fragment_path: robot_shader_path }).map_err(|_| Exit(1))?
	emissive_shader = Draw.Shader.load!({ vertex_path: "", fragment_path: emissive_shader_path }).map_err(|_| Exit(1))?
	blur_shader = Draw.Shader.load!({ vertex_path: "", fragment_path: blur_shader_path }).map_err(|_| Exit(1))?
	composite_shader = Draw.Shader.load!({ vertex_path: "", fragment_path: scene_shader_path }).map_err(|_| Exit(1))?

	floor_time = floor_shader.uniform_f32!("time").map_err(|_| Exit(1))?
	floor_target_uv = floor_shader.uniform_vec2!("targetUv").map_err(|_| Exit(1))?
	floor_reachable = floor_shader.uniform_f32!("reachable").map_err(|_| Exit(1))?
	floor_error = floor_shader.uniform_f32!("errorAmount").map_err(|_| Exit(1))?
	robot_time = robot_shader.uniform_f32!("time").map_err(|_| Exit(1))?
	robot_reachable = robot_shader.uniform_f32!("reachable").map_err(|_| Exit(1))?
	robot_error = robot_shader.uniform_f32!("errorAmount").map_err(|_| Exit(1))?
	blur_direction = blur_shader.uniform_vec2!("direction").map_err(|_| Exit(1))?
	blur_resolution = blur_shader.uniform_vec2!("resolution").map_err(|_| Exit(1))?
	composite_time = composite_shader.uniform_f32!("time").map_err(|_| Exit(1))?
	composite_resolution = composite_shader.uniform_vec2!("resolution").map_err(|_| Exit(1))?
	composite_bloom = composite_shader.uniform_texture!("bloomTexture").map_err(|_| Exit(1))?
	blur_resolution.set!({ x: SceneRenderer.bloom_size.width.to_f32(), y: SceneRenderer.bloom_size.height.to_f32() })
	composite_resolution.set!({ x: SceneCamera.view_width, y: SceneCamera.view_height })
	composite_bloom.set!(bloom_a.texture())
	resources = {
		crate: crate_asset,
		floor: floor_asset,
		wall: wall_asset,
		white: white_asset,
		font: font_asset,
		scene_target,
		bloom_a,
		bloom_b,
		floor_shader,
		robot_shader,
		emissive_shader,
		blur_shader,
		composite_shader,
		blur_direction,
		composite_bloom,
	}
	app_theme = Theme.from_seed({
		background: surface,
		text: ink,
		primary: cyan,
		success: green,
		warning: amber,
		danger: red,
	}).configure({ font, font_size: 16, radius: 7, gap: 9 })
	model = {
		theme: app_theme,
		crate_texture,
		floor_texture,
		wall_texture,
		white_texture,
		robot_texture,
		floor_time,
		floor_target_uv,
		floor_reachable,
		floor_error,
		robot_time,
		robot_reachable,
		robot_error,
		composite_time,
		target: Physics.point(145, 145, 60),
		arm: { upper_length: 132, fore_length: 118, elbow_up: False },
		show_pga: True,
		screen_width: config.width.to_f32(),
		screen_height: config.height.to_f32(),
		camera: { yaw: 0.48, pitch: 0.34 },
		orbit: OrbitIdle,
	}
	Ok({ model, renderer: SceneRenderer.frame_adapter(resources) })
}

tc_program = Program.custom_frame!({
	config: {
		..Program.default,
		title: "Screwbot // PGA Kinematics Lab",
		width: 1280,
		height: 900,
		target_fps: 120,
		vsync: False,
	},
	init!,
	on_frame!: |model, frame| {
		seconds = U64.to_f32(frame.timestamp_nanos) / 1_000_000_000
		solution = RobotArm.solve(model.arm, model.target)
		target = Physics.coords(solution.target)
		target_uv = {
			x: (target.x - Warehouse.layout.min_x) / (Warehouse.layout.max_x - Warehouse.layout.min_x),
			y: (target.z - Warehouse.layout.min_z) / (Warehouse.layout.max_z - Warehouse.layout.min_z),
		}
		reachable_value = if solution.reachable 1 else 0
		error_amount = clamp(solution.error / 80, 0, 1)
		model.floor_time.set!(seconds)
		model.floor_target_uv.set!(target_uv)
		model.floor_reachable.set!(reachable_value)
		model.floor_error.set!(error_amount)
		model.robot_time.set!(seconds)
		model.robot_reachable.set!(reachable_value)
		model.robot_error.set!(error_amount)
		model.composite_time.set!(seconds)
		{
			..model,
			screen_width: frame.screen.width,
			screen_height: frame.screen.height,
		}
	},
	view,
	update,
})

init_for_ray! : App.Init(Model, [])
init_for_ray! = App.init(
	App.default
		.with_title("Screwbot // PGA Kinematics Lab")
		.with_size({ width: 1280, height: 900 })
		.with_frame_pacing(Capped(120))
		.with_resizable(True),
	|host| {
		tc_run! = tc_program.init!.run!
		tc_run!(host).map_ok(|state| Model.(state))
	},
)

render! : Model, Host, Draw.Frame => Try(Model, [Exit(I64), ..])
render! = |Model.(state), host, frame| {
	tc_render! = tc_program.render!
	tc_render!(state, host, frame).map_ok(|next_state| Model.(next_state))
}

program = {
	init!: init_for_ray!,
	render!,
}
