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
		robot : RobotScene.RobotState,
		camera_controller : SceneCamera.CameraController,
	}

	Model : {
		theme : Theme,
		render_resources : RenderResources,
		world : World,
	}

	Msg : [RobotMsg(RobotScene.Msg), CameraMsg(SceneCamera.Msg)]

	RenderResources : {
		compositor : SceneDraw.SceneCompositor,
		warehouse : Warehouse.WarehouseAssets,
		robot : RobotScene.RobotAssets,
	}

	initial : RenderResources -> Model
	initial = |render_resources| {
		{
			theme: Theme.from_seed({ background: Palette.surface, text: Palette.ink, primary: Palette.cyan, success: Palette.green, warning: Palette.amber, danger: Palette.red }),
			render_resources,
			world: { robot: RobotScene.initial, camera_controller: SceneCamera.initial },
		}
	}

	update : Model, Msg -> Model
	update = |model, msg| match msg {
		RobotMsg(robot_msg) => {
			robot = RobotScene.update(model.world.robot, robot_msg)
			{ ..model, world: { ..model.world, robot } }
		}
		CameraMsg(camera_msg) => { ..model, world: { ..model.world, camera_controller: SceneCamera.update(model.world.camera_controller, camera_msg) } }
	}

	render! : Draw.Frame, Renderer.Bounds, Model => Try({}, Draw.ScopeError)
	render! = |frame, bounds, model| {
		solution = RobotScene.solve(model.world.robot)
		parameters = RobotScene.parameters(solution)
		camera = model.world.camera_controller.camera
		compositor = model.render_resources.compositor

		## Frame pipeline: update GPU parameters, render the scene target, then
		## letterbox that target into the canvas.
		SceneDraw.write_scene_uniforms!(compositor, parameters)
		fit = (bounds.size.w / SceneCamera.view_width).min(bounds.size.h / SceneCamera.view_height)
		frame.with_render_texture!(compositor.scene_target, |scene_frame| {
			scene_frame.clear!(SceneDraw.ray_color(SceneDraw.background))
			Warehouse.render!(scene_frame, compositor, model.render_resources.warehouse, camera)?
			RobotScene.render!(scene_frame, compositor, model.render_resources.robot, model.world.robot, camera, solution)
		})?
		frame.texture!({
			texture: compositor.scene_target.texture(),
			source: compositor.scene_target.source(),
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
