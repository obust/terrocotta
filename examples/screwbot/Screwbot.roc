## Screwbot application boundary: durable state, state transitions, and the
## canvas renderer. Views only lays out controls and places the canvas.
import rr.Draw

import tc.Renderer
import tc.Theme

import Palette
import RobotScene
import SceneCamera
import SceneDraw
import Warehouse

Screwbot := [].{
	## The mutable world is deliberately small. IK and shader parameters are
	## derived for a frame instead of being cached alongside the simulation.
	World : {
		robot : RobotScene.Model,
		camera : SceneCamera.Model,
	}

	Model : {
		theme : Theme,
		resources : Resources,
		world : World,
	}

	Msg : [RobotMsg(RobotScene.Msg), CameraMsg(SceneCamera.Msg)]

	Resources : {
		compositor : SceneDraw.Resources,
		warehouse : Warehouse.Resources,
		robot : RobotScene.Resources,
	}

	initial : Resources -> Model
	initial = |resources| {
		{
			theme: Theme.from_seed({ background: Palette.surface, text: Palette.ink, primary: Palette.cyan, success: Palette.green, warning: Palette.amber, danger: Palette.red }),
			resources,
			world: { robot: RobotScene.initial, camera: SceneCamera.initial },
		}
	}

	update : Model, Msg -> Model
	update = |model, msg| match msg {
		RobotMsg(robot_msg) => {
			robot = RobotScene.update(model.world.robot, robot_msg)
			{ ..model, world: { ..model.world, robot } }
		}
		CameraMsg(camera_msg) => { ..model, world: { ..model.world, camera: SceneCamera.update(model.world.camera, camera_msg) } }
	}

	render! : Draw.Frame, Renderer.Bounds, Model => Try({}, Draw.ScopeError)
	render! = |frame, bounds, model| {
		solution = RobotScene.solve(model.world.robot)
		parameters = RobotScene.parameters(solution)
		camera = model.world.camera.camera
		resources = model.resources.compositor

		## Frame pipeline: update GPU parameters, render the scene target, then
		## letterbox that target into the canvas.
		SceneDraw.write_scene_uniforms!(resources, parameters)
		fit = (bounds.size.w / SceneCamera.view_width).min(bounds.size.h / SceneCamera.view_height)
		frame.with_render_texture!(resources.scene_target, |scene_frame| {
			scene_frame.clear!(SceneDraw.ray_color(SceneDraw.background))
			Warehouse.render!(scene_frame, resources, model.resources.warehouse, camera)?
			RobotScene.render!(scene_frame, resources, model.resources.robot, model.world.robot, camera, solution)
		})?
		frame.texture!({
			texture: resources.scene_target.texture(),
			source: resources.scene_target.source(),
			dest: {
				x: bounds.position.x + (bounds.size.w - SceneCamera.view_width * fit) * 0.5,
				y: bounds.position.y + (bounds.size.h - SceneCamera.view_height * fit) * 0.5,
				width: SceneCamera.view_width * fit,
				height: SceneCamera.view_height * fit,
			},
			origin: { x: 0, y: 0 },
			rotation: 0,
			tint: SceneDraw.white_color,
		})
		Ok({})
	}
}
