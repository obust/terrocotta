## The app shell composes independently routed UI components, like the todos
## example. It alone knows how component messages reach the world.
import tc.Color
import tc.Element exposing [box, map, style]
import tc.Program exposing [View]

import Palette exposing [ink]
import Inspector
import RobotScene
import Screwbot
import Toolbar
import Viewport

Views := [].{
	view : Screwbot.Model -> View(Screwbot.Msg)
	view = |model| {
		solution = RobotScene.solve(model.world.robot)
		viewport = Viewport.view(
			model.world.robot,
			model.world.camera_controller,
			solution,
			|frame, bounds| Screwbot.render!(frame, bounds, model),
		)

		box(
			{
				style: |_|
					style.background(0x0a1020.Color).direction(Col).child_align({ x: Start, y: Start }).font_size(17).font_color(ink),
			},
			[
				Toolbar.view(model.theme, solution) |> map(|msg| RobotMsg(msg)),
				box(
					{
						style: |_|
							style.width(Grow({ min: 0, max: 10000 })).height(Grow({ min: 0, max: 10000 })).pad(16, 16, 16, 16).gap(16).direction(Row).overflow(Hidden, Hidden).child_align({ x: Start, y: Start }),
					},
					[
						viewport |> map(viewport_msg),
						Inspector.view(model.theme, model.world.robot, solution) |> map(|msg| RobotMsg(msg)),
					],
				),
			],
		)
	}
}

viewport_msg : Viewport.Msg -> Screwbot.Msg
viewport_msg = |msg| match msg {
	Robot(robot_msg) => RobotMsg(robot_msg)
	Camera(camera_msg) => CameraMsg(camera_msg)
}
