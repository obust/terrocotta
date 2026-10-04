## Composition of one Screwbot frame: stacks the per-component item lists into
## the single SceneRenderer.Scene handed to the canvas draw closure.
import tc.Color

import RobotArm
import RobotScene
import SceneCamera
import SceneRenderer
import WarehouseScene
import Warehouse

Scene := [].{

	## The model slice needed to build one frame's scene.
	SceneInput : {
		warehouse : Warehouse.Model,
		robot : RobotScene.Model,
		show_pga : Bool,
		solution : RobotArm.Solution,
		camera : SceneCamera,
	}

	## The complete scene for one frame, derived from the current model: the
	## component item lists, stacked back to front, plus the robot's shader
	## parameter snapshot.
	scene_for : SceneInput -> SceneRenderer.Scene
	scene_for = |input| {
		camera = input.camera
		solution = input.solution

		item_lists = [
			WarehouseScene.shell_items(input.warehouse, camera),
			WarehouseScene.props_items(input.warehouse, camera),
			WarehouseScene.guides_items(camera),
			RobotScene.items(input.robot, camera, solution),
		]
		all_item_lists = if input.show_pga {
			item_lists.concat([RobotScene.pga_items(camera, solution)])
		} else {
			item_lists
		}

		{ parameters: RobotScene.parameters(solution), items: concat_all(all_item_lists) }
	}
}

concat_all : List(List(SceneRenderer.Item)) -> List(SceneRenderer.Item)
concat_all = |lists| {
	var $items = []
	for list in lists {
		$items = $items.concat(list)
	}
	$items
}

## Concatenation preserves order and keeps every item.
expect {
	line_a = BackdropLine({ start: { x: 0, y: 0 }, end: { x: 1, y: 1 }, thickness: 1, color: 0x000000.Color })
	line_b = OverlayLine({ start: { x: 2, y: 2 }, end: { x: 3, y: 3 }, thickness: 2, color: 0xffffff.Color })
	joined = concat_all([[], [line_a], [], [line_b]])
	joined.len() == 2
}
