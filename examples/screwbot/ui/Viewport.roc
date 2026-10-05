## The interactive viewport owns pointer interpretation and emits local input
## messages. Its canvas callback still renders immediately.
import rr.Mouse

import tc.Color
import tc.Element exposing [box, style, text]
import tc.Program exposing [View]
import tc.Theme

import ../scene/RobotKinematics
import ../scene/Robot
import ../scene/Camera
import ../scene/RobotKinematics

Viewport := [].{
	Msg : [Robot(Robot.Msg), Camera(Camera.Msg)]

	view = |theme, robot, camera, draw!| {
		box(
			{
				id: LocalId("screwbot-workspace"),
				style: |_| style.width(Grow({ min: 360, max: 10000 })).height(Grow({ min: 360, max: 10000 })).background(0x111111).overflow(Hidden, Hidden),
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
				Element.canvas(draw!),
				controls_overlay(theme),
			],
		)
	}
}

controls_overlay : Theme -> View(msg)
controls_overlay = |theme| {
	box(
		{
			style: |_|
				style
					.width(Fixed(250))
					.height(Fit({}))
					.background(theme.palette.background.strong.fill.with_alpha(120))
					.border({ color: theme.palette.background.weak.content.with_alpha(120), left: 1, right: 1, top: 1, bottom: 1 })
					.radius(theme.radius)
					.pad(theme.gap, theme.gap, theme.gap, theme.gap)
					.gap(theme.gap)
					.direction(Col)
					.child_align({ x: Start, y: Start })
					.floating(
						Floating({
							target: Parent,
							config: {
								..Element.default_floating_config,
								z_index: 10,
								offset: { x: 20, y: 20 },
								attach_points: { element: LeftTop, target: LeftTop },
								capture: Passthrough,
								clip_to: AttachedParent,
							},
						}),
					),
		},
		[
			box({ style: |_| style.width(Fit({})).height(Fit({})).font_size(12).font_color(theme.palette.background.weak.content) }, [text("CONTROLS")]),
			box({ style: |_| style.width(Fit({})).height(Fit({})).font_size(theme.font_size).font_color(theme.palette.background.strong.content) }, [text("Mouse Left:  Move target")]),
			box({ style: |_| style.width(Fit({})).height(Fit({})).font_size(theme.font_size).font_color(theme.palette.background.strong.content) }, [text("Mouse Right:  Orbit camera")]),
		],
	)
}
