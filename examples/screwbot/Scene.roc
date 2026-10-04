## Composition of one Screwbot frame: stacks the per-component layers into the
## single SceneRenderer.Scene handed to the canvas draw closure.
import RobotScene
import SceneCamera
import SceneRenderer
import WarehouseScene

Scene := [].{

	## The model slice needed to build one frame's scene.
	SceneInput : {
		warehouse : WarehouseScene.Resources,
		robot_resources : RobotScene.Resources,
		robot : RobotScene.Model,
		camera : SceneCamera,
	}

	## Stack a list of component layers into a complete scene. Each field is
	## concatenated in layer order; the depth-sorted and additive lists are
	## order-insensitive at draw time, while `texture_quads` and
	## `underlay_lines` draw in order, so list the layers back to front.
	combine : SceneRenderer.SceneParameters, List(SceneRenderer.Layer) -> SceneRenderer.Scene
	combine = |parameters, layers| {
		var $texture_quads = []
		var $underlay_lines = []
		var $overlay_texture_quads = []
		var $radial_gradients = []
		var $lines = []
		var $circles = []
		for layer in layers {
			$texture_quads = $texture_quads.concat(layer.texture_quads)
			$underlay_lines = $underlay_lines.concat(layer.underlay_lines)
			$overlay_texture_quads = $overlay_texture_quads.concat(layer.overlay_texture_quads)
			$radial_gradients = $radial_gradients.concat(layer.radial_gradients)
			$lines = $lines.concat(layer.lines)
			$circles = $circles.concat(layer.circles)
		}
		{
			parameters,
			texture_quads: $texture_quads,
			underlay_lines: $underlay_lines,
			overlay_texture_quads: $overlay_texture_quads,
			radial_gradients: $radial_gradients,
			lines: $lines,
			circles: $circles,
		}
	}

	## The complete scene for one frame, derived from the current model.
	scene_for : SceneInput -> SceneRenderer.Scene
	scene_for = |input| {
		camera = input.camera
		solution = RobotScene.solve(input.robot)

		layers = [
			WarehouseScene.shell_layer(input.warehouse, camera),
			WarehouseScene.props_layer(input.warehouse, camera),
			WarehouseScene.guides_layer(camera),
			RobotScene.layer(input.robot_resources, camera, solution),
		]
		all_layers = if input.robot.show_pga {
			layers.concat([RobotScene.pga_layer(camera, solution)])
		} else {
			layers
		}

		Scene.combine(RobotScene.parameters(input.robot), all_layers)
	}
}

## Combining no layers yields a blank scene.
expect {
	scene = Scene.combine({ seconds: 0, target_uv: { x: 0, y: 0 }, reachable_value: 1, error_amount: 0 }, [])
	scene.lines.len() == 0 and scene.texture_quads.len() == 0 and scene.circles.len() == 0
}
