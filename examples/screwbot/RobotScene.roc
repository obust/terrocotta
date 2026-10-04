## Robot-arm component: owns the arm configuration, the IK target, and the
## robot's own textures, and draws the arm -- tapered link quads, joint
## assemblies, ground shadows, the target crosshair, and the optional PGA
## construction overlays -- as scene items, plus the per-frame shader
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
	## Draw the dynamic arm directly into the active scene pass.
	render! = |frame, compositor, model, camera, solution| {
		identity = |point| point
		SceneRenderer.draw_lines!(frame, shadow_lines(camera, solution), identity, 1)?
		SceneRenderer.draw_quads!(frame, compositor, faces(model, camera, solution), identity, 1)?
		SceneRenderer.draw_gradients!(frame, joint_glows(camera, solution), identity, 1)?
		SceneRenderer.draw_lines!(frame, lines(camera, solution), identity, 1)?
		SceneRenderer.draw_circles!(frame, circles(camera, solution), identity, 1)?
		if model.show_pga {
			SceneRenderer.draw_lines!(frame, pga_lines(camera, solution), identity, 1)?
			SceneRenderer.draw_circles!(frame, pga_motor_circles(camera, solution), identity, 1)?
		}
		Ok({})
	}

	## The robot's own state: arm geometry, the IK target, and whether the PGA
	## construction overlay is visible, plus its one GPU texture.
	Model : {
		white : Assets.Texture,
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

	init! : Assets.Store => Try(Model, [Exit(I64)])
	init! = |store| {
		white = Assets.load_texture!(store, "screwbot-white.png").map_err(|_| Exit(1))?
		Ok({ white, arm: { upper_length: 132, fore_length: 118, elbow_up: False }, target: Physics.point(145, 145, 60), show_pga: True })
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
	parameters : RobotArm.Solution -> SceneRenderer.SceneParameters
	parameters = |solution| RobotScene.scene_parameters(solution)

	scene_parameters : RobotArm.Solution -> SceneRenderer.SceneParameters
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
	[
		link_parallel(base_screen, elbow_screen, -4, 2, ink.with_alpha(185)), link_parallel(base_screen, elbow_screen, 4, 1.5, cyan.with_alpha(210)),
		link_tick(base_screen, elbow_screen, 0.30, 15, shadow.with_alpha(180)), link_tick(base_screen, elbow_screen, 0.56, 15, shadow.with_alpha(180)), link_tick(base_screen, elbow_screen, 0.82, 14, shadow.with_alpha(180)),
		link_parallel(elbow_screen, tool_screen, -3.5, 2, (0xffe0a3.Color).with_alpha(190)), link_parallel(elbow_screen, tool_screen, 3.5, 1.5, violet.with_alpha(220)),
		link_tick(elbow_screen, tool_screen, 0.34, 13, shadow.with_alpha(180)), link_tick(elbow_screen, tool_screen, 0.68, 12, shadow.with_alpha(180)),
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
faces : RobotScene.Model, SceneCamera, RobotArm.Solution -> List(SceneRenderer.Quad)
faces = |model, camera, solution| {
	base = camera.project(solution.base)
	elbow = camera.project(solution.elbow)
	tool = camera.project(solution.tool)
	[
		link_quad(model.white, PlainMaterial, base, elbow, 38, 30, 0x10192c.Color),
		link_quad(model.white, RobotMaterial, base, elbow, 27, 19, blue),
		link_quad(model.white, PlainMaterial, elbow, tool, 33, 25, 0x211831.Color),
		link_quad(model.white, RobotMaterial, elbow, tool, 23, 15, violet),
	]
}

circles : SceneCamera, RobotArm.Solution -> List(SceneRenderer.Circle)
circles = |camera, solution| {
	base_screen = camera.project(solution.base)
	elbow_screen = camera.project(solution.elbow)
	tool_screen = camera.project(solution.tool)
	target_screen = camera.project(solution.target)
	[
		circle(base_screen, 28, shadow), circle(base_screen, 22, surface_high), circle(base_screen, 14, cyan), circle(base_screen, 4, ink),
		circle(elbow_screen, 23, shadow), circle(elbow_screen, 18, surface_high), circle(elbow_screen, 10, amber), circle(elbow_screen, 3, ink),
		circle(tool_screen, 16, shadow), circle(tool_screen, 12, surface_high), circle(tool_screen, 6, cyan),
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
	arm : RobotArm
	arm = { upper_length: 132, fore_length: 118, elbow_up: False }
	target = Physics.point(145, 145, 60)
	solution = arm.solve(target)
	initial = RobotScene.scene_parameters(solution)
	later = RobotScene.scene_parameters(solution)
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
	arm : RobotArm
	arm = { upper_length: 132, fore_length: 118, elbow_up: False }
	parameters = RobotScene.scene_parameters(arm.solve(Physics.point(500, 0, 0)))
	parameters.reachable_value == 0
		and parameters.error_amount == 1
			and parameters.target_uv.x > 1.46
				and parameters.target_uv.y == 0.5
}
