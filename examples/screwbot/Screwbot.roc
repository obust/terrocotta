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

	Msg : [RobotMsg(RobotScene.Msg), CameraMsg(SceneCamera.Msg), PointerIdle]

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
		PointerIdle => model
	}

	render! : Draw.Frame, Renderer.Bounds, Model => Try({}, Draw.ScopeError)
	render! = |frame, bounds, model| {
		solution = RobotScene.solve(model.world.robot)
		parameters = RobotScene.parameters(solution)
		camera = model.world.camera.camera
		SceneDraw.render!(
			frame,
			model.resources.compositor,
			parameters,
			bounds.position.x,
			bounds.position.y,
			bounds.size.w,
			bounds.size.h,
			|scene_frame| {
				Warehouse.render!(scene_frame, model.resources.compositor, model.resources.warehouse, camera)?
				RobotScene.render!(scene_frame, model.resources.compositor, model.resources.robot, model.world.robot, camera, solution)
			},
		)
	}
}
