## Physical dimensions of the Screwbot warehouse: the floor plane and walls
## the scene is laid out on.
import rr.Assets
import rr.Draw
import rr.Physics

import tc.Color
import SceneCamera
import SceneDraw

Warehouse := {
	min_x : F32,
	max_x : F32,
	min_z : F32,
	max_z : F32,
	floor_y : F32,
	wall_height : F32,
	frame_height : F32,
	frame_inset_x : F32,
	frame_inset_z : F32,
	post_size : F32,
	beam_size : F32,
	fixture_y : F32,
}.{
	## The warehouse is static, so it contributes render resources but no world
	## state.
	Resources : {
		crate : Assets.Texture,
		floor : Assets.Texture,
		wall : Assets.Texture,
		white : Assets.Texture,
	}

	init! : Assets.Store => Try(Resources, [Exit(I64)])
	init! = |store| {
		crate = Assets.load_texture!(store, "screwbot-crate-v2.png").map_err(|_| Exit(1))?
		floor = Assets.load_texture!(store, "screwbot-floor.png").map_err(|_| Exit(1))?
		wall = Assets.load_texture!(store, "screwbot-wall.png").map_err(|_| Exit(1))?
		white = Assets.load_texture!(store, "screwbot-white.png").map_err(|_| Exit(1))?
		Assets.set_texture_filter!(crate, Bilinear)
		Assets.set_texture_filter!(floor, Bilinear)
		Assets.set_texture_filter!(wall, Bilinear)
		Ok({ crate, floor, wall, white })
	}

	## Direct warehouse renderer. Geometry helpers are restored below during the
	## SceneDraw merge.
	render! : Draw.Frame, SceneDraw.Resources, Resources, SceneCamera => Try({}, Draw.ScopeError)
	render! = |frame, compositor, model, camera| {
		SceneDraw.draw_quads!(frame, compositor, shell_textures(model, camera), |point| point, 1)?
		SceneDraw.draw_quads!(frame, compositor, crate_shadows(model, camera), |point| point, 1)?
		SceneDraw.draw_quads!(frame, compositor, crate_faces(model, camera), |point| point, 1)?
		SceneDraw.draw_quads!(frame, compositor, crate_tape(model, camera), |point| point, 1)?
		SceneDraw.draw_quads!(frame, compositor, crate_labels(model, camera), |point| point, 1)?
		Ok({})
	}
	Bounds3 := { min_x : F32, min_y : F32, min_z : F32, max_x : F32, max_y : F32, max_z : F32 }.{
		width : Bounds3 -> F32
		width = |bounds| bounds.max_x - bounds.min_x

		height : Bounds3 -> F32
		height = |bounds| bounds.max_y - bounds.min_y

		depth : Bounds3 -> F32
		depth = |bounds| bounds.max_z - bounds.min_z

		pallet_parts : Bounds3 -> List(Bounds3)
		pallet_parts = |bounds| {
			span_x = bounds.width()
			span_z = bounds.depth()
			slat_width = span_x * 0.16
			step = (span_x - slat_width) / 3
			upper_min_y = bounds.min_y + bounds.height() * 0.38
			runner_height = upper_min_y - bounds.min_y
			runner_depth = span_z * 0.15
			[
				{ ..bounds, min_x: bounds.min_x, max_x: bounds.min_x + slat_width, min_y: upper_min_y },
				{ ..bounds, min_x: bounds.min_x + step, max_x: bounds.min_x + step + slat_width, min_y: upper_min_y },
				{ ..bounds, min_x: bounds.min_x + step * 2, max_x: bounds.min_x + step * 2 + slat_width, min_y: upper_min_y },
				{ ..bounds, min_x: bounds.max_x - slat_width, min_y: upper_min_y },
				{ ..bounds, max_y: bounds.min_y + runner_height, min_z: bounds.min_z + span_z * 0.12, max_z: bounds.min_z + span_z * 0.12 + runner_depth },
				{ ..bounds, max_y: bounds.min_y + runner_height, min_z: bounds.max_z - span_z * 0.12 - runner_depth, max_z: bounds.max_z - span_z * 0.12 },
			]
		}
	}

	layout : Warehouse
	layout = {
		min_x: -260,
		max_x: 260,
		min_z: -240,
		max_z: 240,
		floor_y: -1,
		wall_height: 350,
		frame_height: 324,
		frame_inset_x: 22,
		frame_inset_z: 22,
		post_size: 14,
		beam_size: 12,
		fixture_y: 286,
	}

	carton_right_lower : Bounds3
	carton_right_lower = { min_x: 145, min_y: 0, min_z: -160, max_x: 220, max_y: 58, max_z: -88 }
	carton_right_upper : Bounds3
	carton_right_upper = { min_x: 152, min_y: 58, min_z: -151, max_x: 213, max_y: 108, max_z: -94 }
	carton_left : Bounds3
	carton_left = { min_x: -210, min_y: 0, min_z: 78, max_x: -156, max_y: 68, max_z: 145 }

	structure : Warehouse -> List(Bounds3)
	structure = |warehouse| {
		left = warehouse.min_x + warehouse.frame_inset_x
		right = warehouse.max_x - warehouse.frame_inset_x
		rear = warehouse.min_z + warehouse.frame_inset_z
		front = warehouse.max_z - warehouse.frame_inset_z
		top_y = warehouse.frame_height - warehouse.beam_size
		cross_y = warehouse.frame_height - warehouse.beam_size * 2
		[
			post_bounds(warehouse, left, rear), post_bounds(warehouse, right, rear), post_bounds(warehouse, left, front), post_bounds(warehouse, right, front),
			x_beam_bounds(warehouse, rear, top_y, warehouse.beam_size), x_beam_bounds(warehouse, front, top_y, warehouse.beam_size),
			z_beam_bounds(warehouse, left, top_y, warehouse.beam_size), z_beam_bounds(warehouse, right, top_y, warehouse.beam_size),
			x_beam_bounds(warehouse, -125, cross_y, warehouse.beam_size), x_beam_bounds(warehouse, 65, cross_y, warehouse.beam_size),
			fixture_bounds(warehouse, -125), fixture_bounds(warehouse, 65),
			hanger_bounds(warehouse, -100, -125), hanger_bounds(warehouse, 100, -125), hanger_bounds(warehouse, -100, 65), hanger_bounds(warehouse, 100, 65),
		]
	}
}

post_bounds : Warehouse, F32, F32 -> Warehouse.Bounds3
post_bounds = |warehouse, x, z| {
	half = warehouse.post_size * 0.5
	{ min_x: x - half, min_y: 0, min_z: z - half, max_x: x + half, max_y: warehouse.frame_height, max_z: z + half }
}

x_beam_bounds : Warehouse, F32, F32, F32 -> Warehouse.Bounds3
x_beam_bounds = |warehouse, z, min_y, size| {
	half = size * 0.5
	{ min_x: warehouse.min_x + warehouse.frame_inset_x - half, min_y, min_z: z - half, max_x: warehouse.max_x - warehouse.frame_inset_x + half, max_y: min_y + size, max_z: z + half }
}

z_beam_bounds : Warehouse, F32, F32, F32 -> Warehouse.Bounds3
z_beam_bounds = |warehouse, x, min_y, size| {
	half = size * 0.5
	{ min_x: x - half, min_y, min_z: warehouse.min_z + warehouse.frame_inset_z, max_x: x + half, max_y: min_y + size, max_z: warehouse.max_z - warehouse.frame_inset_z }
}

fixture_bounds : Warehouse, F32 -> Warehouse.Bounds3
fixture_bounds = |warehouse, z| { min_x: -112, min_y: warehouse.fixture_y - 5, min_z: z - 5, max_x: 112, max_y: warehouse.fixture_y + 5, max_z: z + 5 }

hanger_bounds : Warehouse, F32, F32 -> Warehouse.Bounds3
hanger_bounds = |warehouse, x, z| { min_x: x - 3, min_y: warehouse.fixture_y + 5, min_z: z - 3, max_x: x + 3, max_y: warehouse.frame_height - warehouse.beam_size * 2, max_z: z + 3 }

shell_textures : Warehouse.Resources, SceneCamera -> List(SceneDraw.Quad)
shell_textures = |model, camera| [
	{ texture: model.floor, material: FloorMaterial, top_left: camera.project(Physics.point(Warehouse.layout.min_x, Warehouse.layout.floor_y, Warehouse.layout.min_z)), bottom_left: camera.project(Physics.point(Warehouse.layout.min_x, Warehouse.layout.floor_y, Warehouse.layout.max_z)), bottom_right: camera.project(Physics.point(Warehouse.layout.max_x, Warehouse.layout.floor_y, Warehouse.layout.max_z)), top_right: camera.project(Physics.point(Warehouse.layout.max_x, Warehouse.layout.floor_y, Warehouse.layout.min_z)), tint: 0xe1e7eb.Color },
	{ texture: model.wall, material: PlainMaterial, top_left: camera.project(Physics.point(Warehouse.layout.min_x, Warehouse.layout.wall_height, Warehouse.layout.min_z - 2)), bottom_left: camera.project(Physics.point(Warehouse.layout.min_x, 0, Warehouse.layout.min_z - 2)), bottom_right: camera.project(Physics.point(Warehouse.layout.max_x, 0, Warehouse.layout.min_z - 2)), top_right: camera.project(Physics.point(Warehouse.layout.max_x, Warehouse.layout.wall_height, Warehouse.layout.min_z - 2)), tint: 0xd2d9df.Color },
	{ texture: model.wall, material: PlainMaterial, top_left: camera.project(Physics.point(Warehouse.layout.min_x - 2, Warehouse.layout.wall_height, Warehouse.layout.max_z)), bottom_left: camera.project(Physics.point(Warehouse.layout.min_x - 2, 0, Warehouse.layout.max_z)), bottom_right: camera.project(Physics.point(Warehouse.layout.min_x - 2, 0, Warehouse.layout.min_z)), top_right: camera.project(Physics.point(Warehouse.layout.min_x - 2, Warehouse.layout.wall_height, Warehouse.layout.min_z)), tint: 0xb9c4cc.Color },
]

crate_faces : Warehouse.Resources, SceneCamera -> List(SceneDraw.Quad)
crate_faces = |model, camera| [
	crate_side(model, camera, Warehouse.carton_right_lower, 0xa9a193.Color),
	crate_front(model, camera, Warehouse.carton_right_lower, 0xbfb7a9.Color),
	crate_right(model, camera, Warehouse.carton_right_lower, 0xa9a193.Color),
	crate_face(model, camera, Warehouse.carton_right_lower, 0xd9d3c8.Color),
	crate_side(model, camera, Warehouse.carton_right_upper, 0x968f84.Color),
	crate_front(model, camera, Warehouse.carton_right_upper, 0xaca497.Color),
	crate_right(model, camera, Warehouse.carton_right_upper, 0x968f84.Color),
	crate_face(model, camera, Warehouse.carton_right_upper, 0xc8c1b5.Color),
	crate_side(model, camera, Warehouse.carton_left, 0xa9a193.Color),
	crate_front(model, camera, Warehouse.carton_left, 0xbfb7a9.Color),
	crate_right(model, camera, Warehouse.carton_left, 0xa9a193.Color),
	crate_face(model, camera, Warehouse.carton_left, 0xd9d3c8.Color),
]

crate_tape : Warehouse.Resources, SceneCamera -> List(SceneDraw.Quad)
crate_tape = |model, camera| [
	tape_face(model, camera, Warehouse.carton_right_lower),
	tape_front(model, camera, Warehouse.carton_right_lower),
	tape_face(model, camera, Warehouse.carton_right_upper),
	tape_front(model, camera, Warehouse.carton_right_upper),
	tape_face(model, camera, Warehouse.carton_left),
	tape_front(model, camera, Warehouse.carton_left),
]

tape_face : Warehouse.Resources, SceneCamera, Warehouse.Bounds3 -> SceneDraw.Quad
tape_face = |model, camera, bounds| {
	mid = (bounds.min_x + bounds.max_x) * 0.5
	half = (bounds.max_x - bounds.min_x) * 0.045
	y = bounds.max_y + 0.9
	{ texture: model.white, material: PlainMaterial, top_left: camera.project(Physics.point(mid - half, y, bounds.min_z)), bottom_left: camera.project(Physics.point(mid - half, y, bounds.max_z)), bottom_right: camera.project(Physics.point(mid + half, y, bounds.max_z)), top_right: camera.project(Physics.point(mid + half, y, bounds.min_z)), tint: 0xe1c38f.Color.with_alpha(218) }
}

tape_front : Warehouse.Resources, SceneCamera, Warehouse.Bounds3 -> SceneDraw.Quad
tape_front = |model, camera, bounds| {
	mid = (bounds.min_x + bounds.max_x) * 0.5
	half = (bounds.max_x - bounds.min_x) * 0.045
	{ texture: model.white, material: PlainMaterial, top_left: camera.project(Physics.point(mid - half, bounds.max_y, bounds.max_z + 1)), bottom_left: camera.project(Physics.point(mid - half, bounds.min_y, bounds.max_z + 1)), bottom_right: camera.project(Physics.point(mid + half, bounds.min_y, bounds.max_z + 1)), top_right: camera.project(Physics.point(mid + half, bounds.max_y, bounds.max_z + 1)), tint: 0xe1c38f.Color.with_alpha(218) }
}

crate_labels : Warehouse.Resources, SceneCamera -> List(SceneDraw.Quad)
crate_labels = |model, camera| [
	label_face(model, camera, Warehouse.carton_right_lower),
	barcode_face(model, camera, Warehouse.carton_right_lower, 0.54, 0.018),
	barcode_face(model, camera, Warehouse.carton_right_lower, 0.59, 0.029),
	label_face(model, camera, Warehouse.carton_left),
	barcode_face(model, camera, Warehouse.carton_left, 0.54, 0.018),
	barcode_face(model, camera, Warehouse.carton_left, 0.59, 0.029),
]

label_face : Warehouse.Resources, SceneCamera, Warehouse.Bounds3 -> SceneDraw.Quad
label_face = |model, camera, bounds| {
	width = bounds.width()
	x0 = bounds.min_x + width * 0.24
	x1 = bounds.min_x + width * 0.70
	y0 = bounds.min_y + bounds.height() * 0.37
	y1 = bounds.min_y + bounds.height() * 0.73
	z = bounds.max_z + 1.25
	{ texture: model.white, material: PlainMaterial, top_left: camera.project(Physics.point(x0, y1, z)), bottom_left: camera.project(Physics.point(x0, y0, z)), bottom_right: camera.project(Physics.point(x1, y0, z)), top_right: camera.project(Physics.point(x1, y1, z)), tint: 0xdbe5e8.Color.with_alpha(224) }
}

barcode_face : Warehouse.Resources, SceneCamera, Warehouse.Bounds3, F32, F32 -> SceneDraw.Quad
barcode_face = |model, camera, bounds, offset, span| {
	width = bounds.width()
	x0 = bounds.min_x + width * offset
	x1 = x0 + width * span
	y0 = bounds.min_y + bounds.height() * 0.40
	y1 = bounds.min_y + bounds.height() * 0.70
	z = bounds.max_z + 1.5
	{ texture: model.white, material: PlainMaterial, top_left: camera.project(Physics.point(x0, y1, z)), bottom_left: camera.project(Physics.point(x0, y0, z)), bottom_right: camera.project(Physics.point(x1, y0, z)), top_right: camera.project(Physics.point(x1, y1, z)), tint: 0x34404a.Color }
}

crate_face : Warehouse.Resources, SceneCamera, Warehouse.Bounds3, Color -> SceneDraw.Quad
crate_face = |model, camera, bounds, tint| {
	{ texture: model.crate, material: PlainMaterial, top_left: camera.project(Physics.point(bounds.min_x, bounds.max_y, bounds.min_z)), bottom_left: camera.project(Physics.point(bounds.min_x, bounds.max_y, bounds.max_z)), bottom_right: camera.project(Physics.point(bounds.max_x, bounds.max_y, bounds.max_z)), top_right: camera.project(Physics.point(bounds.max_x, bounds.max_y, bounds.min_z)), tint }
}

crate_front : Warehouse.Resources, SceneCamera, Warehouse.Bounds3, Color -> SceneDraw.Quad
crate_front = |model, camera, bounds, tint| {
	{ texture: model.crate, material: PlainMaterial, top_left: camera.project(Physics.point(bounds.min_x, bounds.max_y, bounds.max_z)), bottom_left: camera.project(Physics.point(bounds.min_x, bounds.min_y, bounds.max_z)), bottom_right: camera.project(Physics.point(bounds.max_x, bounds.min_y, bounds.max_z)), top_right: camera.project(Physics.point(bounds.max_x, bounds.max_y, bounds.max_z)), tint }
}

crate_side : Warehouse.Resources, SceneCamera, Warehouse.Bounds3, Color -> SceneDraw.Quad
crate_side = |model, camera, bounds, tint| {
	{ texture: model.crate, material: PlainMaterial, top_left: camera.project(Physics.point(bounds.min_x, bounds.max_y, bounds.min_z)), bottom_left: camera.project(Physics.point(bounds.min_x, bounds.min_y, bounds.min_z)), bottom_right: camera.project(Physics.point(bounds.min_x, bounds.min_y, bounds.max_z)), top_right: camera.project(Physics.point(bounds.min_x, bounds.max_y, bounds.max_z)), tint }
}

crate_right : Warehouse.Resources, SceneCamera, Warehouse.Bounds3, Color -> SceneDraw.Quad
crate_right = |model, camera, bounds, tint| {
	{ texture: model.crate, material: PlainMaterial, top_left: camera.project(Physics.point(bounds.max_x, bounds.max_y, bounds.max_z)), bottom_left: camera.project(Physics.point(bounds.max_x, bounds.min_y, bounds.max_z)), bottom_right: camera.project(Physics.point(bounds.max_x, bounds.min_y, bounds.min_z)), top_right: camera.project(Physics.point(bounds.max_x, bounds.max_y, bounds.min_z)), tint }
}

crate_shadows : Warehouse.Resources, SceneCamera -> List(SceneDraw.Quad)
crate_shadows = |model, camera| [
	crate_shadow(model, camera, Warehouse.carton_right_lower),
	crate_shadow(model, camera, Warehouse.carton_left),
]

crate_shadow : Warehouse.Resources, SceneCamera, Warehouse.Bounds3 -> SceneDraw.Quad
crate_shadow = |model, camera, bounds| {
	margin = 7
	{ texture: model.white, material: PlainMaterial, top_left: camera.project(Physics.point(bounds.min_x - margin + 7, Warehouse.layout.floor_y + 0.4, bounds.min_z - margin + 5)), bottom_left: camera.project(Physics.point(bounds.min_x - margin + 7, Warehouse.layout.floor_y + 0.4, bounds.max_z + margin + 5)), bottom_right: camera.project(Physics.point(bounds.max_x + margin + 7, Warehouse.layout.floor_y + 0.4, bounds.max_z + margin + 5)), top_right: camera.project(Physics.point(bounds.max_x + margin + 7, Warehouse.layout.floor_y + 0.4, bounds.min_z - margin + 5)), tint: 0x000000.Color.with_alpha(105) }
}
