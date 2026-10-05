## The interactive viewport owns pointer interpretation and emits local input
## messages. Its canvas callback still renders immediately.
import rr.Mouse

import tc.Color
import tc.Element exposing [box, style, text]
import tc.Program exposing [View]

import tc.Palette as BuiltinPalette
import ../scene/RobotKinematics
import ../scene/Robot
import ../scene/Camera
import ../scene/RobotKinematics

Viewport := [].{
	Msg : [Robot(Robot.Msg), Camera(Camera.Msg)]

	view = |robot, camera_controller, solution, render_scene!| {
		camera = camera_controller.camera
		box(
			{
				id: LocalId("screwbot-BuiltinPalette.atom_dark.background.darken(8)"),
				style: |status|
					style.width(Grow({ min: 360, max: 10000 })).height(Grow({ min: 420, max: 10000 })).background(if status.hovered BuiltinPalette.atom_dark.background.darken(8).lighten(3) else BuiltinPalette.atom_dark.background.darken(8)).radius(14).border({ color: if status.focused BuiltinPalette.atom_dark.primary else BuiltinPalette.atom_dark.text.with_alpha(55), left: 1, right: 1, top: 1, bottom: 1 }).overflow(Hidden, Hidden),
				events: [
					OnPointer(
						Box.box(
							|event| if event.mouse.right {
								Camera(OrbitMove(event.position.x, event.position.y))
							} else if event.mouse.left {
								Robot(SetTarget(Camera.target_from_pointer(event, robot.target, camera)))
							} else {
								Camera(OrbitEnd)
							},
						),
					),
					OnPointerReleased(Mouse.Button.Right, Camera(OrbitEnd)),
				],
			},
			[
				box({}, [Element.canvas(|frame, bounds| render_scene!(frame, bounds))]),
				status_hud(solution),
			],
		)
	}

	status_hud = |solution| {
		state_color = if solution.reachable BuiltinPalette.atom_dark.success else BuiltinPalette.atom_dark.danger
		box(
			{
				id: LocalId("viewport-hud"),
				style: |_|
					style.width(Fit({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).background(BuiltinPalette.atom_dark.background.with_alpha(230)).border({ color: BuiltinPalette.atom_dark.primary.with_alpha(75), left: 1, right: 1, top: 1, bottom: 1 }).radius(7).pad(6, 9, 9, 9).gap(7).direction(Row).child_align({ x: Start, y: Center }).font_size(13).font_color(BuiltinPalette.atom_dark.text).spacing(1).floating(Floating({ target: Parent, config: { ..Element.default_floating_config, z_index: 10, offset: { x: 14, y: 14 }, capture: Passthrough, clip_to: AttachedParent } })),
			},
			[
				box({ style: |_| style.width(Fixed(7)).height(Fixed(7)).background(state_color).radius(100) }, []),
				text("PGA MOTOR // LIVE"),
			],
		)
	}
}
