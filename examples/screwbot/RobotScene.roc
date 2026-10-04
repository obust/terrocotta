## Robot-arm component: owns the arm configuration, the IK target, and the
## robot's own textures, and draws the arm -- tapered link quads, joint
## assemblies, ground shadows, the target crosshair, and the optional PGA
## construction overlays -- as scene layers, plus the per-frame shader
## parameter snapshot the compositor broadcasts.
import rr.Assets
import rr.Physics

import tc.Color

import Palette exposing [amber, blue, cyan, green, ink, muted, red, shadow, surface_high, violet]
import RobotArm
import SceneCamera
import ScenePrimitives exposing [clamp, circle, line, link_parallel, link_quad, link_tick, radial_gradient, shadow_on_ground, world_line]
import SceneRenderer
import Warehouse

RobotScene := [].{

	## The texture the robot link quads sample.
	Resources : {
		white : Assets.Texture,
	}

	## Load the robot's textures from the app's asset store.
	load! : Assets.Store => Try(Resources, [Exit(I64)])
	load! = |store| {
		white = Assets.load_texture!(store, "screwbot-white.png").map_err(|_| Exit(1))?
		Ok({ white: white })
	}

	## The robot's own state: arm geometry, the IK target, and whether the PGA
	## construction overlay is visible.
	Model : {
		arm : RobotArm,
		target : Physics.Point,
		show_pga : Bool,
	}

	Msg : [
		AimTarget3D(F32, F32, F32),
		SelectPose(PosePreset),
		SetElbowUp(Bool),
		SetForeLength(F32),
		SetShowPga(Bool),
		SetTargetX(F32),
		SetTargetY(F32),
		SetTargetZ(F32),
		SetUpperLength(F32),
	]

	initial : Model
	initial = {
		arm: { upper_length: 132, fore_length: 118, elbow_up: False },
		target: Physics.point(145, 145, 60),
		show_pga: True,
	}

	update : Model, Msg -> Model
	update = |model, msg| {
		target = model.target.coords()
		match msg {
			AimTarget3D(x, y, z) => { ..model, target: Physics.point(x, y, z) }
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

	solve : Model -> RobotArm.Solution
	solve = |model| model.arm.solve(model.target)

	## The scene is rendered at a fixed resolution and letterboxed into whatever
	## bounds the canvas leaf resolves, so there is no window-size breakpoint.
	parameters : Model -> SceneRenderer.SceneParameters
	parameters = |model| RobotScene.scene_parameters(model.arm, model.target)

	## The robot's own layer: links, joints, crosshair, ground shadows, and the
	## joint glows.
	layer : Resources, SceneCamera, RobotArm.Solution -> SceneRenderer.Layer
	layer = |resources, camera, solution| {
		{
			..SceneRenderer.empty_layer,
			underlay_lines: shadow_lines(camera, solution),
			overlay_texture_quads: faces(resources, camera, solution),
			radial_gradients: joint_glows(camera, solution),
			lines: lines(camera, solution),
			circles: circles(camera, solution),
		}
	}

	## The optional PGA construction overlay.
	pga_layer : SceneCamera, RobotArm.Solution -> SceneRenderer.Layer
	pga_layer = |camera, solution| {
		{
			..SceneRenderer.empty_layer,
			lines: pga_lines(camera, solution),
			circles: pga_motor_circles(camera, solution),
		}
	}

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
}

## A named target configuration exposed by the preset controls.
PosePreset := [AssemblyPose, FoldedPose, LongReachPose]

apply_pose_preset : RobotScene.Model, PosePreset -> RobotScene.Model
apply_pose_preset = |model, preset| match preset {
	AssemblyPose => { ..model, target: Physics.point(105, 155, 75) }
	FoldedPose => { ..model, target: Physics.point(65, 45, -55), arm: model.arm.with_elbow_up(True) }
	LongReachPose => { ..model, target: Physics.point(205, 105, 35), arm: model.arm.with_elbow_up(False) }
}

lines : SceneCamera, RobotArm.Solution -> List(SceneRenderer.Line)
lines = |camera, solution| {
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

shadow_lines : SceneCamera, RobotArm.Solution -> List(SceneRenderer.Line)
shadow_lines = |camera, solution| {
	ground_base = shadow_on_ground(solution.base)
	ground_elbow = shadow_on_ground(solution.elbow)
	ground_tool = shadow_on_ground(solution.tool)
	[
		world_line(camera, ground_base, ground_elbow, 13, shadow.with_alpha(70)),
		world_line(camera, ground_elbow, ground_tool, 11, shadow.with_alpha(70)),
	]
}

## The robot links reuse the 2x2 white texture as an untextured proxy.
faces : RobotScene.Resources, SceneCamera, RobotArm.Solution -> List(SceneRenderer.Quad)
faces = |resources, camera, solution| {
	base = camera.project(solution.base)
	elbow = camera.project(solution.elbow)
	tool = camera.project(solution.tool)
	upper_depth = (camera.depth(solution.base) + camera.depth(solution.elbow)) * 0.5
	fore_depth = (camera.depth(solution.elbow) + camera.depth(solution.tool)) * 0.5
	[
		link_quad(resources.white, PlainMaterial, base, elbow, 38, 30, 0x10192c.Color, upper_depth),
		link_quad(resources.white, RobotMaterial, base, elbow, 27, 19, blue, upper_depth + 0.001),
		link_quad(resources.white, PlainMaterial, elbow, tool, 33, 25, 0x211831.Color, fore_depth),
		link_quad(resources.white, RobotMaterial, elbow, tool, 23, 15, violet, fore_depth + 0.001),
	]
}

circles : SceneCamera, RobotArm.Solution -> List(SceneRenderer.Circle)
circles = |camera, solution| {
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

joint_glows : SceneCamera, RobotArm.Solution -> List(SceneRenderer.RadialGradient)
joint_glows = |camera, solution| [
	radial_gradient(camera.project(solution.base), 62, cyan.with_alpha(34), (0x45d7ff.Color).with_alpha(0)),
	radial_gradient(camera.project(solution.elbow), 44, amber.with_alpha(26), (0xffbe55.Color).with_alpha(0)),
	radial_gradient(camera.project(solution.tool), 40, violet.with_alpha(30), (0xa478ff.Color).with_alpha(0)),
]

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

## Parity fixture: the default target is reachable and has its expected floor
## UV. Shader time is a constant, so every snapshot shares one phase.
expect {
	arm = { upper_length: 132, fore_length: 118, elbow_up: False }
	target = Physics.point(145, 145, 60)
	initial = RobotScene.scene_parameters(arm, target)
	later = RobotScene.scene_parameters(arm, target)
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
	parameters = RobotScene.scene_parameters({ upper_length: 132, fore_length: 118, elbow_up: False }, Physics.point(500, 0, 0))
	parameters.reachable_value == 0
		and parameters.error_amount == 1
			and parameters.target_uv.x > 1.46
				and parameters.target_uv.y == 0.5
}
