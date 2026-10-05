## Scene coordination: durable workspace state, state transitions, and the
## direct canvas renderer. The app shell lays out and routes UI components.
import rr.Draw

import tc.Renderer
import tc.Theme

import ../scene/Robot
import ../scene/Camera
import ../scene/Drawing
import ../scene/Warehouse

Scene := [].{

	## The mutable world is deliberately small. IK and shader parameters are
	## derived for a frame instead of being cached alongside the simulation.
	World : {
		robot : Robot.RobotState,
		camera_controller : Camera.CameraController,
	}

	Model : {
		theme : Theme,
		render_resources : RenderResources,
		world : World,
	}

	Msg : [RobotMsg(Robot.Msg), CameraMsg(Camera.Msg)]

	RenderResources : {
		compositor : Drawing.SceneCompositor,
		warehouse : Warehouse.WarehouseAssets,
		robot : Robot.RobotAssets,
	}

	render! : Draw.Frame, Renderer.Bounds, Model => Try({}, Draw.ScopeError)
	render! = |frame, bounds, model| {
		solution = Robot.solve(model.world.robot)
		parameters = Robot.parameters(solution)
		camera = model.world.camera_controller.camera
		compositor = model.render_resources.compositor

		## Frame pipeline: update GPU parameters, render the scene target, then
		## letterbox that target into the canvas.
		Drawing.write_scene_uniforms!(compositor, parameters)
		fit = (bounds.size.w / Camera.view_width).min(bounds.size.h / Camera.view_height)
		frame.with_render_texture!(
			compositor.scene_target,
			|scene_frame| {
				scene_frame.clear!(Drawing.ray_color(Drawing.background))
				Warehouse.render!(scene_frame, compositor, model.render_resources.warehouse, camera)?
				Robot.render!(scene_frame, compositor, model.render_resources.robot, camera, solution)
			},
		)?
		frame.texture!({
			texture: compositor.scene_target.texture(),
			source: compositor.scene_target.source(),
			dest: {
				x: bounds.position.x + (bounds.size.w - Camera.view_width * fit) * 0.5,
				y: bounds.position.y + (bounds.size.h - Camera.view_height * fit) * 0.5,
				width: Camera.view_width * fit,
				height: Camera.view_height * fit,
			},
			origin: { x: 0, y: 0 },
			rotation: 0,
			tint: Drawing.white_color,
		})
		Ok({})
	}
}
