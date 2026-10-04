## Screwbot application state: the model wires the component models and
## resources together, and `update` routes each wrapped message to the
## component that owns it.
import tc.Theme

import Palette
import RobotScene
import SceneCamera
import SceneRenderer
import WarehouseScene

State := [].{

	AppModel : {
		theme : Theme,
		compositor : SceneRenderer.Resources,
		warehouse : WarehouseScene.Resources,
		robot_textures : RobotScene.Resources,
		robot : RobotScene.Model,
		camera : SceneCamera.Model,
	}

	Msg : [
		RobotMsg(RobotScene.Msg),
		CameraMsg(SceneCamera.Msg),
		PointerIdle,
	]

	## The GPU resources loaded at startup: the compositor pipeline plus each
	## component's own textures.
	Resources : {
		compositor : SceneRenderer.Resources,
		warehouse : WarehouseScene.Resources,
		robot_textures : RobotScene.Resources,
	}

	initial : Resources -> AppModel
	initial = |resources| {
		theme: Theme.from_seed({
			background: Palette.surface,
			text: Palette.ink,
			primary: Palette.cyan,
			success: Palette.green,
			warning: Palette.amber,
			danger: Palette.red,
		}),
		compositor: resources.compositor,
		warehouse: resources.warehouse,
		robot_textures: resources.robot_textures,
		robot: RobotScene.initial,
		camera: SceneCamera.initial,
	}

	update : AppModel, Msg -> AppModel
	update = |model, msg| match msg {
		RobotMsg(robot_msg) => { ..model, robot: RobotScene.update(model.robot, robot_msg) }
		CameraMsg(camera_msg) => { ..model, camera: SceneCamera.update(model.camera, camera_msg) }
		PointerIdle => model
	}
}
