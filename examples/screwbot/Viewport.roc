## The interactive viewport owns pointer interpretation and emits local input
## messages. Its canvas callback still renders immediately.
import rr.Mouse

import tc.Color
import tc.Element exposing [box, style, text]
import tc.Program exposing [View]

import Palette exposing [cyan, green, grid, ink, red, surface, workspace]
import RobotArm
import RobotScene
import SceneCamera

Viewport := [].{
	Msg : [Robot(RobotScene.Msg), Camera(SceneCamera.Msg)]

	view = |robot, camera_controller, solution, render_scene!| {
		camera = camera_controller.camera
		box(
			{
				id: LocalId("screwbot-workspace"),
				style: |status|
					style.width(Grow({ min: 360, max: 10000 })).height(Grow({ min: 420, max: 10000 })).background(if status.hovered workspace.lighten(3) else workspace).radius(14).border({ color: if status.focused cyan else grid, left: 1, right: 1, top: 1, bottom: 1 }).overflow(Hidden, Hidden),
				events: [
					OnPointer(Box.box(|event| if event.mouse.right {
						Camera(OrbitMove(event.position.x, event.position.y))
					} else if event.mouse.left {
						Robot(SetTarget(SceneCamera.target_from_pointer(event, robot.target, camera)))
					} else {
						Camera(OrbitEnd)
					})),
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
		state_color = if solution.reachable green else red
		box(
			{
				id: LocalId("viewport-hud"),
				style: |_|
					style.width(Fit({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).background(surface.with_alpha(230)).border({ color: cyan.with_alpha(75), left: 1, right: 1, top: 1, bottom: 1 }).radius(7).pad(6, 9, 9, 9).gap(7).direction(Row).child_align({ x: Start, y: Center }).font_size(13).font_color(ink).spacing(1).floating(Floating({ target: Parent, config: { ..Element.default_floating_config, z_index: 10, offset: { x: 14, y: 14 }, capture: Passthrough, clip_to: AttachedParent } })),
			},
			[
				box({ style: |_| style.width(Fixed(7)).height(Fixed(7)).background(state_color).radius(100) }, []),
				text("PGA MOTOR // LIVE"),
			],
		)
	}
}
