## Screwbot views: the header, sidebar, viewport HUD, and the canvas-backed
## workspace, composed into the app's top-level view.
import rr.Mouse

import tc.Color
import tc.Element exposing [box, style, text]
import tc.Program exposing [View]
import tc.Widget

import Palette exposing [blue, cyan, green, grid, ink, muted, red, surface, workspace]
import RobotArm
import RobotScene
import SceneDraw exposing [decimal, degrees, target_from_pointer]
import Screwbot
import Ui exposing [card, coefficient_readout, content_stack, control, preset_button, readout]

Views := [].{

	view : Screwbot.Model -> View(Screwbot.Msg)
	view = |model| {
		solution = RobotScene.solve(model.world.robot)

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
}

viewport_hud : RobotArm.Solution -> View(Screwbot.Msg)
viewport_hud = |solution| {
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

## The canvas leaf's draw closure builds the scene at draw time, when the
## frame and the resolved bounds exist. It runs synchronously during `render!`.
scene_canvas : Screwbot.Model -> View(Screwbot.Msg)
scene_canvas = |model| {
	Element.canvas(
		|frame, bounds| Screwbot.render!(frame, bounds, model),
	)
}

workspace_view : Screwbot.Model, RobotArm.Solution -> View(Screwbot.Msg)
workspace_view = |model, solution| {
	camera = model.world.camera.camera
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
								CameraMsg(OrbitMove(event.position.x, event.position.y))
							} else if event.mouse.left {
								aim = target_from_pointer(event, model.world.robot.target, camera).coords()
								RobotMsg(AimTarget3D(aim.x, aim.y, aim.z))
							} else {
								PointerIdle
							}
						},
					),
				),
				OnPointerReleased(Mouse.Button.Right, CameraMsg(OrbitEnd)),
			],
		},
		[
			box({}, [scene_canvas(model)]),
			viewport_hud(solution),
		],
	)
}

pga_inspector : RobotArm.Solution -> View(Screwbot.Msg)
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

sidebar : Screwbot.Model, RobotArm.Solution -> View(Screwbot.Msg)
sidebar = |model, solution| {
	target = model.world.robot.target.coords()
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
	pga_section = if model.world.robot.show_pga {
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
					control(model.theme, "X", target.x, -230, 230, 1, |value| RobotMsg(SetTargetX(value))),
					control(model.theme, "Y", target.y, 5, 285, 1, |value| RobotMsg(SetTargetY(value))),
					control(model.theme, "Z", target.z, -160, 160, 1, |value| RobotMsg(SetTargetZ(value))),
				]),
			),
			card(
				"ARM CONFIGURATION",
				content_stack([
					control(model.theme, "upper link", model.world.robot.arm.upper_length, 60, 170, 1, |value| RobotMsg(SetUpperLength(value))),
					control(model.theme, "fore link", model.world.robot.arm.fore_length, 60, 170, 1, |value| RobotMsg(SetForeLength(value))),
					Widget.checkbox(model.theme, model.world.robot.arm.elbow_up, "Elbow-up branch", |checked| RobotMsg(SetElbowUp(checked))),
					Widget.checkbox(model.theme, model.world.robot.show_pga, "Show PGA construction", |checked| RobotMsg(SetShowPga(checked))),
				]),
			),
			pga_section,
		],
	)
}

header : Screwbot.Model, RobotArm.Solution -> View(Screwbot.Msg)
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
					preset_button(False, "ASSEMBLY", RobotMsg(SelectPose(AssemblyPose))),
					preset_button(False, "FOLDED", RobotMsg(SelectPose(FoldedPose))),
					preset_button(True, "LONG REACH", RobotMsg(SelectPose(LongReachPose))),
				],
			),
		],
	)
}
