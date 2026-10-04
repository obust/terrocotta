## Warehouse component: owns its textures and draws the static scenery --
## floor and walls, rack structure, cartons and decals, ground marks, the
## reference grid, and labeled world axes -- as shell/props/guides item lists
## projected through the scene camera into SceneRenderer records.
import rr.Assets
import rr.Physics

import tc.Color

import Palette exposing [amber, blue, cyan, green, grid, muted, red, shadow, violet]
import SceneCamera
import ScenePrimitives exposing [ProjectedFace, face_quad, projected_face, radial_gradient, world_line]
import SceneRenderer
import Warehouse exposing [Bounds3]

WarehouseScene := [].{

	## The room itself: floor and wall quads, the steel rack structure, and the
	## ambient light pools.
	shell_items : Warehouse.Model, SceneCamera -> List(SceneRenderer.Item)
	shell_items = |resources, camera| {
		shell_textures(resources, camera).map(|quad| BackdropQuad(quad))
			.concat(structure_faces(resources, camera).map(|quad| OverlayQuad(quad)))
			.concat(ambient_glows(camera).map(|gradient| Glow(gradient)))
	}

	## The stored goods: cartons with tape and labels, the pallet, and their
	## ground marks and shadows.
	props_items : Warehouse.Model, SceneCamera -> List(SceneRenderer.Item)
	props_items = |resources, camera| {
		ground_marks(resources, camera).map(|quad| BackdropQuad(quad))
			.concat(props_faces(resources, camera).map(|quad| OverlayQuad(quad)))
	}

	## The annotation overlay: aisle markings, the reference grid, fixture
	## posts, and the labeled world axes.
	guides_items : SceneCamera -> List(SceneRenderer.Item)
	guides_items = |camera| {
		underlay_lines(camera).map(|line| BackdropLine(line))
			.concat(fixture_lines(camera).map(|line| OverlayLine(line)))
			.concat(axis_lines(camera).map(|line| OverlayLine(line)))
	}
}

shell_textures : Warehouse.Model, SceneCamera -> List(SceneRenderer.Quad)
shell_textures = |resources, camera| [
	{
		texture: resources.floor,
		material: FloorMaterial,
		top_left: camera.project(Physics.point(Warehouse.layout.min_x, Warehouse.layout.floor_y, Warehouse.layout.min_z)),
		bottom_left: camera.project(Physics.point(Warehouse.layout.min_x, Warehouse.layout.floor_y, Warehouse.layout.max_z)),
		bottom_right: camera.project(Physics.point(Warehouse.layout.max_x, Warehouse.layout.floor_y, Warehouse.layout.max_z)),
		top_right: camera.project(Physics.point(Warehouse.layout.max_x, Warehouse.layout.floor_y, Warehouse.layout.min_z)),
		tint: (0xe1e7eb.Color).with_alpha(230),
	},
	{
		texture: resources.wall,
		material: PlainMaterial,
		top_left: camera.project(Physics.point(Warehouse.layout.min_x, Warehouse.layout.wall_height, Warehouse.layout.min_z - 2)),
		bottom_left: camera.project(Physics.point(Warehouse.layout.min_x, 0, Warehouse.layout.min_z - 2)),
		bottom_right: camera.project(Physics.point(Warehouse.layout.max_x, 0, Warehouse.layout.min_z - 2)),
		top_right: camera.project(Physics.point(Warehouse.layout.max_x, Warehouse.layout.wall_height, Warehouse.layout.min_z - 2)),
		tint: (0xd2d9df.Color).with_alpha(215),
	},
	{
		texture: resources.wall,
		material: PlainMaterial,
		top_left: camera.project(Physics.point(Warehouse.layout.min_x - 2, Warehouse.layout.wall_height, Warehouse.layout.max_z)),
		bottom_left: camera.project(Physics.point(Warehouse.layout.min_x - 2, 0, Warehouse.layout.max_z)),
		bottom_right: camera.project(Physics.point(Warehouse.layout.min_x - 2, 0, Warehouse.layout.min_z)),
		top_right: camera.project(Physics.point(Warehouse.layout.min_x - 2, Warehouse.layout.wall_height, Warehouse.layout.min_z)),
		tint: (0xb9c4cc.Color).with_alpha(195),
	},
]

structure_faces : Warehouse.Model, SceneCamera -> List(SceneRenderer.Quad)
structure_faces = |resources, camera| {
	steel = 0x30415b.Color

	var $bounds_faces = []
	for bounds in Warehouse.layout.structure() {
		$bounds_faces = $bounds_faces.concat(cuboid_faces(camera, bounds, steel))
	}
	$bounds_faces = $bounds_faces.concat(cuboid_faces(camera, { min_x: -34, min_y: -10, min_z: -34, max_x: 34, max_y: 0, max_z: 34 }, 0x263248.Color))

	textured_quads($bounds_faces.map(|face| { face, texture: resources.white, material: PlainMaterial }))
}

props_faces : Warehouse.Model, SceneCamera -> List(SceneRenderer.Quad)
props_faces = |resources, camera| {
	crate = 0xd9d3c8.Color

	box_faces = cuboid_faces(camera, Warehouse.carton_right_lower, crate)
		.concat(cuboid_faces(camera, Warehouse.carton_right_upper, crate.darken(7)))
		.concat(cuboid_faces(camera, Warehouse.carton_left, crate))
	var $pallet_faces = []
	for bounds in Warehouse.pallet_left.pallet_parts() {
		$pallet_faces = $pallet_faces.concat(cuboid_faces(camera, bounds, 0x8f7254.Color))
	}
	decal_faces = carton_decal_faces(camera, Warehouse.carton_right_lower, True)
		.concat(carton_decal_faces(camera, Warehouse.carton_right_upper, False))
		.concat(carton_decal_faces(camera, Warehouse.carton_left, True))

	textured_quads(
		box_faces.map(|face| { face, texture: resources.crate, material: PlainMaterial })
			.concat($pallet_faces.map(|face| { face, texture: resources.white, material: PlainMaterial }))
			.concat(decal_faces.map(|face| { face, texture: resources.white, material: PlainMaterial })),
	)
}

ground_marks : Warehouse.Model, SceneCamera -> List(SceneRenderer.Quad)
ground_marks = |resources, camera| {
	light_pool = projected_face(
		camera,
		Physics.point(-185, 0.5, -165),
		Physics.point(-215, 0.5, 80),
		Physics.point(100, 0.5, 80),
		Physics.point(70, 0.5, -165),
		cyan.with_alpha(13),
	)
	safety_zone = projected_face(
		camera,
		Physics.point(-92, 0.8, -78),
		Physics.point(-92, 0.8, 78),
		Physics.point(92, 0.8, 78),
		Physics.point(92, 0.8, -78),
		amber.with_alpha(16),
	)
	[
		face_quad(resources.white, PlainMaterial, light_pool),
		face_quad(resources.white, PlainMaterial, safety_zone),
		carton_ground_shadow(resources, camera, Warehouse.carton_right_lower),
		carton_ground_shadow(resources, camera, Warehouse.carton_left),
	]
}

underlay_lines : SceneCamera -> List(SceneRenderer.Line)
underlay_lines = |camera| {
	aisle = [
		world_line(camera, Physics.point(-128, 1, -150), Physics.point(-128, 1, 110), 2, muted.with_alpha(70)),
		world_line(camera, Physics.point(96, 1, -150), Physics.point(96, 1, 110), 2, muted.with_alpha(70)),
		world_line(camera, Physics.point(-128, 1, -150), Physics.point(96, 1, -150), 2, muted.with_alpha(50)),
		world_line(camera, Physics.point(-128, 1, 110), Physics.point(96, 1, 110), 2, muted.with_alpha(50)),
	]
	aisle.concat(ground_grid(camera))
}

fixture_lines : SceneCamera -> List(SceneRenderer.Line)
fixture_lines = |camera| {
	posts = [
		Physics.point(Warehouse.layout.min_x, 0, Warehouse.layout.min_z),
		Physics.point(Warehouse.layout.min_x, 0, Warehouse.layout.max_z),
		Physics.point(Warehouse.layout.max_x, 0, Warehouse.layout.min_z),
		Physics.point(Warehouse.layout.max_x, 0, Warehouse.layout.max_z),
	]
	posts
		.map(|corner| world_line(camera, corner, corner.add(Physics.vector(0, Warehouse.layout.wall_height, 0)), 2, grid.with_alpha(190)))
		.concat(
			posts.map(
				|corner| {
					world_line(
						camera,
						corner,
						corner.add(Physics.vector(20, 0, 20)),
						1,
						muted.with_alpha(80),
					)
				},
			),
		)
}

ambient_glows : SceneCamera -> List(SceneRenderer.RadialGradient)
ambient_glows = |camera| [
	radial_gradient(camera.project(Physics.point(0, 60, 0)), 210, cyan.with_alpha(16), (0x45d7ff.Color).with_alpha(0)),
	radial_gradient(camera.project(Physics.point(-150, 30, -120)), 130, blue.with_alpha(14), (0x5686ff.Color).with_alpha(0)),
]

## The three warehouse-space axes available to the overlay renderer.
AxisLabel := [XAxis, YAxis, ZAxis]

grid_values : List(F32)
grid_values = [-240, -200, -160, -120, -80, -40, 0, 40, 80, 120, 160, 200, 240]

ground_grid : SceneCamera -> List(SceneRenderer.Line)
ground_grid = |camera| {
	along_x = grid_values.map(|z| world_line(camera, Physics.point(-260, 0, z), Physics.point(260, 0, z), 1, grid))
	along_z = grid_values.map(|x| world_line(camera, Physics.point(x, 0, -240), Physics.point(x, 0, 240), 1, grid))
	along_x.concat(along_z)
}

axis_lines : SceneCamera -> List(SceneRenderer.Line)
axis_lines = |camera| axis_with_label(camera, Physics.point(125, 0, 0), XAxis, red)
	.concat(axis_with_label(camera, Physics.point(0, 125, 0), YAxis, green))
	.concat(axis_with_label(camera, Physics.point(0, 0, 125), ZAxis, blue))

axis_letter : AxisLabel, SceneCamera.Point2, Color -> List(SceneRenderer.Line)
axis_letter = |label, center, color| {
	left = center.x - 5
	right = center.x + 5
	top = center.y - 7
	middle = center.y
	bottom = center.y + 7

	match label {
		XAxis => [
			ScenePrimitives.line({ x: left, y: top }, { x: right, y: bottom }, 2.5, color),
			ScenePrimitives.line({ x: right, y: top }, { x: left, y: bottom }, 2.5, color),
		]
		YAxis => [
			ScenePrimitives.line({ x: left, y: top }, { x: center.x, y: middle }, 2.5, color),
			ScenePrimitives.line({ x: right, y: top }, { x: center.x, y: middle }, 2.5, color),
			ScenePrimitives.line({ x: center.x, y: middle }, { x: center.x, y: bottom }, 2.5, color),
		]
		ZAxis => [
			ScenePrimitives.line({ x: left, y: top }, { x: right, y: top }, 2.5, color),
			ScenePrimitives.line({ x: right, y: top }, { x: left, y: bottom }, 2.5, color),
			ScenePrimitives.line({ x: left, y: bottom }, { x: right, y: bottom }, 2.5, color),
		]
	}
}

axis_with_label : SceneCamera, Physics.Point, AxisLabel, Color -> List(SceneRenderer.Line)
axis_with_label = |camera, end_world, label, color| {
	start = camera.project(Physics.origin)
	end = camera.project(end_world)
	dx = end.x - start.x
	dy = end.y - start.y
	length = (dx * dx + dy * dy).sqrt().max(1)
	unit_x = dx / length
	unit_y = dy / length
	wing = {
		x: end.x - unit_x * 13,
		y: end.y - unit_y * 13,
	}
	left_wing = {
		x: wing.x - unit_y * 6,
		y: wing.y + unit_x * 6,
	}
	right_wing = {
		x: wing.x + unit_y * 6,
		y: wing.y - unit_x * 6,
	}
	label_center = {
		x: end.x + unit_x * 22,
		y: end.y + unit_y * 22,
	}
	[
		ScenePrimitives.line(start, end, 4, color),
		ScenePrimitives.line(end, left_wing, 4, color),
		ScenePrimitives.line(end, right_wing, 4, color),
	].concat(axis_letter(label, label_center, color))
}

cuboid_faces : SceneCamera, Bounds3, Color -> List(ProjectedFace)
cuboid_faces = |camera, bounds, color| {
	p000 = Physics.point(bounds.min_x, bounds.min_y, bounds.min_z)
	p001 = Physics.point(bounds.min_x, bounds.min_y, bounds.max_z)
	p010 = Physics.point(bounds.min_x, bounds.max_y, bounds.min_z)
	p011 = Physics.point(bounds.min_x, bounds.max_y, bounds.max_z)
	p100 = Physics.point(bounds.max_x, bounds.min_y, bounds.min_z)
	p101 = Physics.point(bounds.max_x, bounds.min_y, bounds.max_z)
	p110 = Physics.point(bounds.max_x, bounds.max_y, bounds.min_z)
	p111 = Physics.point(bounds.max_x, bounds.max_y, bounds.max_z)

	faces = [
		projected_face(camera, p010, p011, p111, p110, color.lighten(38)),
		projected_face(camera, p011, p001, p101, p111, color.lighten(8)),
		projected_face(camera, p010, p000, p001, p011, color.darken(30)),
		projected_face(camera, p110, p111, p101, p100, color.lighten(18)),
		projected_face(camera, p010, p110, p100, p000, color.darken(12)),
		projected_face(camera, p001, p000, p100, p101, color.darken(45)),
	]

	# Cull back faces in projected space. Besides reducing overdraw, this removes
	# the layered-card appearance caused by drawing all six opaque cuboid sides.
	faces.keep_if(
		|face| {
			left_x = face.bottom_left.x - face.top_left.x
			left_y = face.bottom_left.y - face.top_left.y
			diagonal_x = face.bottom_right.x - face.top_left.x
			diagonal_y = face.bottom_right.y - face.top_left.y
			left_x * diagonal_y - left_y * diagonal_x < -0.01
		},
	)
}

carton_ground_shadow : Warehouse.Model, SceneCamera, Bounds3 -> SceneRenderer.Quad
carton_ground_shadow = |resources, camera, bounds| {
	margin = 7
	offset_x = 7
	offset_z = 5
	face_quad(
		resources.white,
		PlainMaterial,
		projected_face(
			camera,
			Physics.point(bounds.min_x - margin + offset_x, Warehouse.layout.floor_y + 0.4, bounds.min_z - margin + offset_z),
			Physics.point(bounds.min_x - margin + offset_x, Warehouse.layout.floor_y + 0.4, bounds.max_z + margin + offset_z),
			Physics.point(bounds.max_x + margin + offset_x, Warehouse.layout.floor_y + 0.4, bounds.max_z + margin + offset_z),
			Physics.point(bounds.max_x + margin + offset_x, Warehouse.layout.floor_y + 0.4, bounds.min_z - margin + offset_z),
			shadow.with_alpha(105),
		),
	)
}

carton_decal_faces : SceneCamera, Bounds3, Bool -> List(ProjectedFace)
carton_decal_faces = |camera, bounds, has_label| {
	mid_x = (bounds.min_x + bounds.max_x) * 0.5
	width = bounds.width()
	height = bounds.height()
	front_z = bounds.max_z + 0.9
	top_y = bounds.max_y + 0.9
	tape_half = (width * 0.045).max(2.5)
	tape_color = (0xe1c38f.Color).with_alpha(218)
	tape_faces = [
		projected_face(camera, Physics.point(mid_x - tape_half, bounds.max_y, front_z), Physics.point(mid_x - tape_half, bounds.min_y, front_z), Physics.point(mid_x + tape_half, bounds.min_y, front_z), Physics.point(mid_x + tape_half, bounds.max_y, front_z), tape_color),
		projected_face(camera, Physics.point(mid_x - tape_half, top_y, bounds.min_z), Physics.point(mid_x - tape_half, top_y, bounds.max_z), Physics.point(mid_x + tape_half, top_y, bounds.max_z), Physics.point(mid_x + tape_half, top_y, bounds.min_z), tape_color),
	]

	if has_label {
		label_min_x = bounds.min_x + width * 0.24
		label_max_x = bounds.min_x + width * 0.70
		label_min_y = bounds.min_y + height * 0.37
		label_max_y = bounds.min_y + height * 0.73
		label_z = front_z + 0.35
		label = projected_face(camera, Physics.point(label_min_x, label_max_y, label_z), Physics.point(label_min_x, label_min_y, label_z), Physics.point(label_max_x, label_min_y, label_z), Physics.point(label_max_x, label_max_y, label_z), (0xdbe5e8.Color).with_alpha(224))
		bar_width = width * 0.018
		bar_a_x = label_min_x + width * 0.30
		bar_b_x = label_min_x + width * 0.35
		ink_z = label_z + 0.2
		bar_a = projected_face(camera, Physics.point(bar_a_x, label_max_y - 2, ink_z), Physics.point(bar_a_x, label_min_y + 2, ink_z), Physics.point(bar_a_x + bar_width, label_min_y + 2, ink_z), Physics.point(bar_a_x + bar_width, label_max_y - 2, ink_z), 0x34404a.Color)
		bar_b = projected_face(camera, Physics.point(bar_b_x, label_max_y - 2, ink_z), Physics.point(bar_b_x, label_min_y + 2, ink_z), Physics.point(bar_b_x + bar_width * 1.6, label_min_y + 2, ink_z), Physics.point(bar_b_x + bar_width * 1.6, label_max_y - 2, ink_z), 0x34404a.Color)
		tape_faces.concat([label, bar_a, bar_b])
	} else {
		tape_faces
	}
}

textured_quads : List({ face : ProjectedFace, texture : Assets.Texture, material : SceneRenderer.Material }) -> List(SceneRenderer.Quad)
textured_quads = |textured_faces| {
	textured_faces.map(|item| face_quad(item.texture, item.material, item.face))
}
