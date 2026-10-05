## Robot-arm component: owns the arm configuration and IK target, then draws
## the solved pose -- tapered link quads, joints, shadows, target crosshair,
## and optional PGA construction overlays. Its immutable texture is kept in
## the resource set, outside of the simulation state.
import rr.Assets
import rr.Physics

import tc.Color
import tc.Theme

import ../scene/RobotKinematics
import ../scene/Camera
import ../scene/Drawing exposing [circle, clamp, line, link_parallel, link_quad, link_tick, radial_gradient, shadow_on_ground, world_line]
import ../scene/Warehouse

Robot := [].{

	## Draw the dynamic arm directly into the active scene pass.
	render! = |frame, compositor, resources, model, camera, solution, theme| {
		palette = theme_colors(theme)
		identity = |point| point
		Drawing.draw_lines!(frame, shadow_lines(palette, camera, solution), identity, 1)?
		Drawing.draw_quads!(frame, compositor, faces(palette, resources, camera, solution), identity, 1)?
		Drawing.draw_gradients!(frame, joint_glows(palette, camera, solution), identity, 1)?
		Drawing.draw_lines!(frame, lines(palette, camera, solution), identity, 1)?
		Drawing.draw_circles!(frame, circles(palette, camera, solution), identity, 1)?
		if model.show_pga {
			Drawing.draw_lines!(frame, pga_lines(palette, camera, solution), identity, 1)?
			Drawing.draw_circles!(frame, pga_motor_circles(palette, camera, solution), identity, 1)?
		}
		Ok({})
	}

	## Long-lived GPU data belongs to the resource set, not the simulation state.
	RobotAssets : {
		white : Assets.Texture,
	}

	## The robot's own simulation state: arm geometry, the IK target, and
	## whether the PGA construction overlay is visible.
	RobotState : {
		arm : RobotKinematics,
		target : Physics.Point,
		show_pga : Bool,
	}

	Msg : [
		SelectPose(PosePreset),
		SetArm(RobotKinematics),
		SetPgaVisible(Bool),
		SetTarget(Physics.Point),
	]

	init! : Assets.Store => Try(RobotAssets, [Exit(I64)])
	init! = |store| {
		white = Assets.load_texture!(store, "screwbot-white.png") ? |_| Exit(1)
		Ok({ white: white })
	}

	initial : RobotState
	initial = { arm: { upper_length: 132, fore_length: 118, elbow_up: False }, target: Physics.point(145, 145, 60), show_pga: True }

	update : RobotState, Msg -> RobotState
	update = |model, msg| {
		match msg {
			SetTarget(target) => { ..model, target }
			SetArm(arm) => { ..model, arm }
			SetPgaVisible(show_pga) => { ..model, show_pga }
			SelectPose(preset) => apply_pose_preset(model, preset)
		}
	}

	solve : RobotState -> RobotKinematics.Solution
	solve = |model| model.arm.solve(model.target)

	## The scene is rendered at a fixed resolution and letterboxed into whatever
	## bounds the canvas leaf resolves, so there is no window-size breakpoint.
	parameters : RobotKinematics.Solution -> Drawing.SceneParameters
	parameters = |solution| Robot.scene_parameters(solution)

	scene_parameters : RobotKinematics.Solution -> Drawing.SceneParameters
	scene_parameters = |solution| {
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
}

Colors : { amber : Color, blue : Color, cyan : Color, green : Color, ink : Color, muted : Color, red : Color, shadow : Color, surface_high : Color, violet : Color }

theme_colors : Theme -> Colors
theme_colors = |theme| {
	palette = theme.palette
	{ amber: palette.warning.base.fill, blue: palette.primary.strong.fill, cyan: palette.primary.base.fill, green: palette.success.base.fill, ink: palette.background.base.content, muted: palette.background.weak.content, red: palette.danger.base.fill, shadow: palette.background.base.fill.darken(18), surface_high: palette.background.weak.fill, violet: palette.primary.weak.fill }
}

## A named target configuration exposed by the preset controls.
PosePreset := [AssemblyPose, FoldedPose, LongReachPose]

apply_pose_preset : Robot.RobotState, PosePreset -> Robot.RobotState
apply_pose_preset = |model, preset| match preset {
	AssemblyPose => { ..model, target: Physics.point(105, 155, 75) }
	FoldedPose => { ..model, target: Physics.point(65, 45, -55), arm: model.arm.with_elbow_up(True) }
	LongReachPose => { ..model, target: Physics.point(205, 105, 35), arm: model.arm.with_elbow_up(False) }
}

lines : Colors, Camera, RobotKinematics.Solution -> List(Drawing.Line)
lines = |palette, camera, solution| {
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
	[
		link_parallel(base_screen, elbow_screen, -4, 2, palette.ink.with_alpha(185)),
		link_parallel(base_screen, elbow_screen, 4, 1.5, palette.cyan.with_alpha(210)),
		link_tick(base_screen, elbow_screen, 0.30, 15, palette.shadow.with_alpha(180)),
		link_tick(base_screen, elbow_screen, 0.56, 15, palette.shadow.with_alpha(180)),
		link_tick(base_screen, elbow_screen, 0.82, 14, palette.shadow.with_alpha(180)),
		link_parallel(elbow_screen, tool_screen, -3.5, 2, (0xffe0a3.Color).with_alpha(190)),
		link_parallel(elbow_screen, tool_screen, 3.5, 1.5, palette.violet.with_alpha(220)),
		link_tick(elbow_screen, tool_screen, 0.34, 13, palette.shadow.with_alpha(180)),
		link_tick(elbow_screen, tool_screen, 0.68, 12, palette.shadow.with_alpha(180)),
		world_line(camera, solution.target_ground, solution.target, 2, palette.muted),
		line(
			{ x: target_screen.x - 14, y: target_screen.y },
			{ x: target_screen.x + 14, y: target_screen.y },
			2,
			if solution.reachable {
				palette.green
			} else {
				palette.red
			},
		),
		line(
			{ x: target_screen.x, y: target_screen.y - 14 },
			{ x: target_screen.x, y: target_screen.y + 14 },
			2,
			if solution.reachable {
				palette.green
			} else {
				palette.red
			},
		),
		world_line(camera, finger_root, finger_one, 5, palette.cyan),
		world_line(camera, finger_tip, finger_two, 5, palette.cyan),
		line(target_ground_screen, target_screen, 1, palette.muted),
	]
}

shadow_lines : Colors, Camera, RobotKinematics.Solution -> List(Drawing.Line)
shadow_lines = |palette, camera, solution| {
	ground_base = shadow_on_ground(solution.base)
	ground_elbow = shadow_on_ground(solution.elbow)
	ground_tool = shadow_on_ground(solution.tool)
	[
		world_line(camera, ground_base, ground_elbow, 13, palette.shadow.with_alpha(70)),
		world_line(camera, ground_elbow, ground_tool, 11, palette.shadow.with_alpha(70)),
	]
}

## The robot links reuse the 2x2 white texture as an untextured proxy.
faces : Colors, Robot.RobotAssets, Camera, RobotKinematics.Solution -> List(Drawing.Quad)
faces = |palette, resources, camera, solution| {
	base = camera.project(solution.base)
	elbow = camera.project(solution.elbow)
	tool = camera.project(solution.tool)
	[
		link_quad(resources.white, PlainMaterial, base, elbow, 38, 30, 0x10192c.Color),
		link_quad(resources.white, RobotMaterial, base, elbow, 27, 19, palette.blue),
		link_quad(resources.white, PlainMaterial, elbow, tool, 33, 25, 0x211831.Color),
		link_quad(resources.white, RobotMaterial, elbow, tool, 23, 15, palette.violet),
	]
}

circles : Colors, Camera, RobotKinematics.Solution -> List(Drawing.Circle)
circles = |palette, camera, solution| {
	base_screen = camera.project(solution.base)
	elbow_screen = camera.project(solution.elbow)
	tool_screen = camera.project(solution.tool)
	target_screen = camera.project(solution.target)
	[
		circle(base_screen, 28, palette.shadow),
		circle(base_screen, 22, palette.surface_high),
		circle(base_screen, 14, palette.cyan),
		circle(base_screen, 4, palette.ink),
		circle(elbow_screen, 23, palette.shadow),
		circle(elbow_screen, 18, palette.surface_high),
		circle(elbow_screen, 10, palette.amber),
		circle(elbow_screen, 3, palette.ink),
		circle(tool_screen, 16, palette.shadow),
		circle(tool_screen, 12, palette.surface_high),
		circle(tool_screen, 6, palette.cyan),
		circle(
			target_screen,
			6,
			if solution.reachable {
				palette.green
			} else {
				palette.red
			},
		),
	]
}

joint_glows : Colors, Camera, RobotKinematics.Solution -> List(Drawing.RadialGradient)
joint_glows = |palette, camera, solution| [
	radial_gradient(camera.project(solution.base), 62, palette.cyan.with_alpha(34), (0x45d7ff.Color).with_alpha(0)),
	radial_gradient(camera.project(solution.elbow), 44, palette.amber.with_alpha(26), (0xffbe55.Color).with_alpha(0)),
	radial_gradient(camera.project(solution.tool), 40, palette.violet.with_alpha(30), (0xa478ff.Color).with_alpha(0)),
]

pga_lines : Colors, Camera, RobotKinematics.Solution -> List(Drawing.Line)
pga_lines = |palette, camera, solution| if solution.reachable {
	[world_line(camera, solution.base, solution.target, 1, palette.cyan.with_alpha(95))]
} else {
	[]
}

pga_motor_circles : Colors, Camera, RobotKinematics.Solution -> List(Drawing.Circle)
pga_motor_circles = |palette, camera, solution| {
	direction = solution.target.sub(solution.base)
	[
		circle(camera.project(solution.base.add(direction.scale(0.18))), 2.5, palette.cyan.with_alpha(45)),
		circle(camera.project(solution.base.add(direction.scale(0.34))), 3, palette.cyan.with_alpha(65)),
		circle(camera.project(solution.base.add(direction.scale(0.50))), 3.5, palette.cyan.with_alpha(90)),
		circle(camera.project(solution.base.add(direction.scale(0.66))), 3, palette.cyan.with_alpha(115)),
		circle(camera.project(solution.base.add(direction.scale(0.82))), 2.5, palette.cyan.with_alpha(145)),
	]
}

## Parity fixture: the default target is reachable and has its expected floor
## UV. Shader time is a constant, so every snapshot shares one phase.
expect {
	arm : RobotKinematics
	arm = { upper_length: 132, fore_length: 118, elbow_up: False }
	target = Physics.point(145, 145, 60)
	solution = arm.solve(target)
	initial = Robot.scene_parameters(solution)
	later = Robot.scene_parameters(solution)
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
	arm : RobotKinematics
	arm = { upper_length: 132, fore_length: 118, elbow_up: False }
	parameters = Robot.scene_parameters(arm.solve(Physics.point(500, 0, 0)))
	parameters.reachable_value == 0
		and parameters.error_amount == 1
			and parameters.target_uv.x > 1.46
				and parameters.target_uv.y == 0.5
}
