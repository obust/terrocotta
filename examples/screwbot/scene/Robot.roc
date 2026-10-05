## Robot-arm component: owns the arm configuration and IK target, then draws
## the solved pose -- tapered link quads, joints, shadows, target crosshair,
## and optional PGA construction overlays. Its immutable texture is kept in
## the resource set, outside of the simulation state.
import rr.Assets
import rr.Draw
import rr.Physics

import tc.Color

import ../scene/RobotKinematics
import ../scene/Camera
import ../scene/Drawing exposing [circle, clamp, line, link_parallel, link_quad, link_tick, radial_gradient, shadow_on_ground, world_line]
import ../scene/Warehouse

Robot := [].{

	## Draw the dynamic arm directly into the active scene pass.
	render! = |frame, robot_shader, resources, camera, solution| {
		palette = fixed_colors
		draw_shadow!(frame, palette, camera, solution)?
		draw_arm!(frame, robot_shader, resources, palette, camera, solution)?
		draw_joints!(frame, palette, camera, solution)?
		draw_target!(frame, palette, camera, solution)?
		draw_pga_construction!(frame, palette, camera, solution)?
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
		random_state : U64,
		target : Physics.Point,
	}

	Msg : [
		SelectPose(PosePreset),
		RandomizeTarget,
		SetArm(RobotKinematics),
		SetTarget(Physics.Point),
	]

	init! : Assets.Store => Try(RobotAssets, [Exit(I64)])
	init! = |store| {
		white = Assets.load_texture!(store, "screwbot-white.png") ? |_| Exit(1)
		Ok({ white: white })
	}

	initial : RobotState
	initial = { arm: { upper_length: 132, fore_length: 118, elbow_up: False }, random_state: 0, target: Physics.point(145, 145, 60) }

	with_random_seed : RobotState, U64 -> RobotState
	with_random_seed = |model, random_state| { ..model, random_state }

	update : RobotState, Msg -> RobotState
	update = |model, msg| {
		match msg {
			SetTarget(target) => { ..model, target }
			SetArm(arm) => { ..model, arm }
			RandomizeTarget => random_target(model)
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
		warehouse = Warehouse.layout
		{
			## Held at zero: the current Program API exposes no per-frame
			## timestamp, so the shaders keep their initial animation phase.
			seconds: 0,
			target_uv: {
				x: (target.x - warehouse.position.x) / warehouse.size.width,
				y: (target.z - warehouse.position.z) / warehouse.size.depth,
			},
			reachable_value: if solution.reachable 1 else 0,
			error_amount: clamp(solution.error / 80, 0, 1),
		}
	}
}

random_target : Robot.RobotState -> Robot.RobotState
random_target = |model| {
	## Keep the recurrence bounded: Roc checks integer overflow in debug builds.
	next_state = ((model.random_state % 997) * 37 + 17) % 997
	index = next_state % 5
	target = match index {
		0 => Physics.point(120, 165, 40)
		1 => Physics.point(-175, 90, -70)
		2 => Physics.point(75, 190, 95)
		3 => Physics.point(-190, 135, 15)
		_ => Physics.point(-110, 70, -105)
	}
	{ ..model, random_state: next_state, target }
}

Colors : { amber : Color, blue : Color, cyan : Color, green : Color, ink : Color, muted : Color, red : Color, shadow : Color, surface_high : Color, violet : Color }

fixed_colors : Colors
fixed_colors = {
	amber: 0xaebdca.Color,
	blue: 0x6f8fa8.Color,
	cyan: 0x8faec2.Color,
	green: 0x91b6aa.Color,
	ink: 0xd5e0e8.Color,
	muted: 0x71889a.Color,
	red: 0xc29aa1.Color,
	shadow: Color.black,
	surface_high: 0x425667.Color,
	violet: 0x7b92a6.Color,
}

## A named target configuration exposed by the preset controls.
PosePreset := [AssemblyPose, FoldedPose, LongReachPose]

apply_pose_preset : Robot.RobotState, PosePreset -> Robot.RobotState
apply_pose_preset = |model, preset| match preset {
	AssemblyPose => { ..model, target: Physics.point(105, 155, 75) }
	FoldedPose => { ..model, target: Physics.point(65, 45, -55), arm: model.arm.with_elbow_up(True) }
	LongReachPose => { ..model, target: Physics.point(205, 105, 35), arm: model.arm.with_elbow_up(False) }
}

draw_shadow! : Draw.Frame, Colors, Camera, RobotKinematics.Solution => Try({}, Draw.ScopeError)
draw_shadow! = |frame, palette, camera, solution| {
	for shadow in shadow_lines(palette, camera, solution) {
		Drawing.draw_line!(frame, shadow, |point| point, 1)?
	}
	Ok({})
}

draw_arm! : Draw.Frame, Drawing.RobotShader, Robot.RobotAssets, Colors, Camera, RobotKinematics.Solution => Try({}, Draw.ScopeError)
draw_arm! = |frame, robot_shader, resources, palette, camera, solution| {
	for outline in arm_outlines(resources, camera, solution) {
		Drawing.draw_quad!(frame, outline, |point| point)?
	}
	Drawing.with_shader!(
		frame,
		robot_shader,
		|robot_frame| {
			for face in arm_faces(palette, resources, camera, solution) {
				Drawing.draw_quad!(robot_frame, face, |point| point)?
			}
			Ok({})
		},
	)
}

draw_joints! : Draw.Frame, Colors, Camera, RobotKinematics.Solution => Try({}, Draw.ScopeError)
draw_joints! = |frame, palette, camera, solution| {
	for glow in joint_glows(palette, camera, solution) {
		Drawing.draw_gradient!(frame, glow, |point| point, 1)?
	}
	for joint in joint_circles(palette, camera, solution) {
		Drawing.draw_circle!(frame, joint, |point| point, 1)?
	}
	Ok({})
}

draw_target! : Draw.Frame, Colors, Camera, RobotKinematics.Solution => Try({}, Draw.ScopeError)
draw_target! = |frame, palette, camera, solution| {
	for target_line in target_lines(palette, camera, solution) {
		Drawing.draw_line!(frame, target_line, |point| point, 1)?
	}
	Drawing.draw_circle!(frame, target_circle(palette, camera, solution), |point| point, 1)
}

draw_pga_construction! : Draw.Frame, Colors, Camera, RobotKinematics.Solution => Try({}, Draw.ScopeError)
draw_pga_construction! = |frame, palette, camera, solution| {
	for construction_line in pga_lines(palette, camera, solution) {
		Drawing.draw_line!(frame, construction_line, |point| point, 1)?
	}
	for motor in pga_motor_circles(palette, camera, solution) {
		Drawing.draw_circle!(frame, motor, |point| point, 1)?
	}
	Ok({})
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
arm_faces : Colors, Robot.RobotAssets, Camera, RobotKinematics.Solution -> List(Drawing.Quad)
arm_faces = |palette, resources, camera, solution| {
	base = camera.project(solution.base)
	elbow = camera.project(solution.elbow)
	tool = camera.project(solution.tool)
	[
		link_quad(resources.white, base, elbow, 27, 19, palette.blue),
		link_quad(resources.white, elbow, tool, 23, 15, palette.violet),
	]
}

arm_outlines : Robot.RobotAssets, Camera, RobotKinematics.Solution -> List(Drawing.Quad)
arm_outlines = |resources, camera, solution| {
	base = camera.project(solution.base)
	elbow = camera.project(solution.elbow)
	tool = camera.project(solution.tool)
	[
		link_quad(resources.white, base, elbow, 38, 30, 0x10192c.Color),
		link_quad(resources.white, elbow, tool, 33, 25, 0x211831.Color),
	]
}

joint_circles : Colors, Camera, RobotKinematics.Solution -> List(Drawing.Circle)
joint_circles = |palette, camera, solution| {
	base_screen = camera.project(solution.base)
	elbow_screen = camera.project(solution.elbow)
	tool_screen = camera.project(solution.tool)
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
	]
}

joint_glows : Colors, Camera, RobotKinematics.Solution -> List(Drawing.RadialGradient)
joint_glows = |palette, camera, solution| [
	radial_gradient(camera.project(solution.base), 62, palette.cyan.with_alpha(34), (0x45d7ff.Color).with_alpha(0)),
	radial_gradient(camera.project(solution.elbow), 44, palette.amber.with_alpha(26), (0xffbe55.Color).with_alpha(0)),
	radial_gradient(camera.project(solution.tool), 40, palette.violet.with_alpha(30), (0xa478ff.Color).with_alpha(0)),
]

target_lines : Colors, Camera, RobotKinematics.Solution -> List(Drawing.Line)
target_lines = |palette, camera, solution| {
	target = camera.project(solution.target)
	target_ground = camera.project(solution.target_ground)
	color = if solution.reachable palette.green else palette.red
	[
		world_line(camera, solution.target_ground, solution.target, 2, palette.muted),
		line({ x: target.x - 14, y: target.y }, { x: target.x + 14, y: target.y }, 2, color),
		line({ x: target.x, y: target.y - 14 }, { x: target.x, y: target.y + 14 }, 2, color),
		line(target_ground, target, 1, palette.muted),
	]
}

target_circle : Colors, Camera, RobotKinematics.Solution -> Drawing.Circle
target_circle = |palette, camera, solution| {
	color = if solution.reachable palette.green else palette.red
	circle(camera.project(solution.target), 6, color)
}

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
