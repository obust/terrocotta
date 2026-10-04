## Screwbot application boundary: durable state, state transitions, and the
## canvas renderer. Views only lays out controls and places the canvas.
import rr.Draw

import tc.Renderer
import tc.Theme

import Palette
import RobotArm
import RobotScene
import SceneCamera
import SceneDraw
import Warehouse

Screwbot := [].{
	Model : {
		theme : Theme,
		compositor : SceneDraw.Resources,
		warehouse : Warehouse.Model,
		robot : RobotScene.Model,
		solution : RobotArm.Solution,
		camera : SceneCamera.Model,
	}

	Msg : [RobotMsg(RobotScene.Msg), CameraMsg(SceneCamera.Msg), PointerIdle]

	Resources : {
		compositor : SceneDraw.Resources,
		warehouse : Warehouse.Model,
		robot : RobotScene.Model,
	}

	initial : Resources -> Model
	initial = |resources| {
		{
			theme: Theme.from_seed({ background: Palette.surface, text: Palette.ink, primary: Palette.cyan, success: Palette.green, warning: Palette.amber, danger: Palette.red }),
			compositor: resources.compositor,
			warehouse: resources.warehouse,
			robot: resources.robot,
			solution: RobotScene.solve(resources.robot),
			camera: SceneCamera.initial,
		}
	}

	update : Model, Msg -> Model
	update = |model, msg| match msg {
		RobotMsg(robot_msg) => {
			robot = RobotScene.update(model.robot, robot_msg)
			{ ..model, robot, solution: RobotScene.solve(robot) }
		}
		CameraMsg(camera_msg) => { ..model, camera: SceneCamera.update(model.camera, camera_msg) }
		PointerIdle => model
	}

	render! : Draw.Frame, Renderer.Bounds, Model => Try({}, Draw.ScopeError)
	render! = |frame, bounds, model| {
		parameters = RobotScene.parameters(model.solution)
		camera = model.camera.camera
		SceneDraw.render!(
			frame,
			model.compositor,
			parameters,
			bounds.position.x,
			bounds.position.y,
			bounds.size.w,
			bounds.size.h,
			|scene_frame| {
				Warehouse.render!(scene_frame, model.compositor, model.warehouse, camera)?
				RobotScene.render!(scene_frame, model.compositor, model.robot, camera, model.solution)
			},
		)
	}
}
