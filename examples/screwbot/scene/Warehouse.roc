## Physical dimensions of the Screwbot warehouse: the floor plane and walls
## the scene is laid out on.
import rr.Assets
import rr.Draw
import rr.Physics

import tc.Color
import ../scene/Camera
import ../scene/Drawing
import ../scene/FloorMaterial

Warehouse := {
	position : { x : F32, y : F32, z : F32 },
	size : { width : F32, height : F32, depth : F32 },
}.{

	## The warehouse is static, so it contributes render resources but no world
	## state.
	WarehouseAssets : {
		crate : Assets.Texture,
		floor : Assets.Texture,
		wall : Assets.Texture,
		white : Assets.Texture,
	}

	init! : Assets.Store => Try(WarehouseAssets, [Exit(I64)])
	init! = |store| {
		crate = Assets.load_texture!(store, "screwbot-crate-v2.png") ? |_| Exit(1)
		floor = Assets.load_texture!(store, "screwbot-floor.png") ? |_| Exit(1)
		wall = Assets.load_texture!(store, "screwbot-wall.png") ? |_| Exit(1)
		white = Assets.load_texture!(store, "screwbot-white.png") ? |_| Exit(1)
		Assets.set_texture_filter!(crate, Bilinear)
		Assets.set_texture_filter!(floor, Bilinear)
		Assets.set_texture_filter!(wall, Bilinear)
		Ok({ crate: crate, floor: floor, wall: wall, white: white })
	}

	## The warehouse owns plain geometry and needs only its floor shader.
	render! : Draw.Frame, FloorMaterial, WarehouseAssets, Camera => Try({}, Draw.ScopeError)
	render! = |frame, floor_shader, model, camera| {
		draw_floor!(frame, floor_shader, model, camera)?
		draw_walls!(frame, model, camera)?
		draw_crate!(frame, model, camera, Warehouse.right_lower_crate)?
		draw_crate!(frame, model, camera, Warehouse.right_upper_crate)?
		draw_crate!(frame, model, camera, Warehouse.left_crate)?
		Ok({})
	}
	Bounds3 := { min_x : F32, min_y : F32, min_z : F32, max_x : F32, max_y : F32, max_z : F32 }.{
		width : Bounds3 -> F32
		width = |bounds| bounds.max_x - bounds.min_x

		height : Bounds3 -> F32
		height = |bounds| bounds.max_y - bounds.min_y

		depth : Bounds3 -> F32
		depth = |bounds| bounds.max_z - bounds.min_z

	}

	layout : Warehouse
	layout = {
		position: { x: -260, y: 0, z: -240 },
		size: { width: 520, height: 350, depth: 480 },
	}

	target_uv : Physics.Point -> { x : F32, y : F32 }
	target_uv = |target| {
		coords = target.coords()
		{
			x: (coords.x - Warehouse.layout.position.x) / Warehouse.layout.size.width,
			y: (coords.z - Warehouse.layout.position.z) / Warehouse.layout.size.depth,
		}
	}

	Crate : { position : { x : F32, y : F32, z : F32 }, size : { width : F32, height : F32, depth : F32 }, face_tint : Color, front_tint : Color, side_tint : Color, casts_shadow : Bool, has_label : Bool }

	right_lower_crate : Crate
	right_lower_crate = { position: { x: 145, y: 0, z: -160 }, size: { width: 75, height: 58, depth: 72 }, side_tint: 0xa9a193.Color, front_tint: 0xbfb7a9.Color, face_tint: 0xd9d3c8.Color, casts_shadow: True, has_label: True }
	right_upper_crate : Crate
	right_upper_crate = { position: { x: 152, y: 58, z: -151 }, size: { width: 61, height: 50, depth: 57 }, side_tint: 0x968f84.Color, front_tint: 0xaca497.Color, face_tint: 0xc8c1b5.Color, casts_shadow: False, has_label: False }
	left_crate : Crate
	left_crate = { position: { x: -210, y: 0, z: 78 }, size: { width: 54, height: 68, depth: 67 }, side_tint: 0xa9a193.Color, front_tint: 0xbfb7a9.Color, face_tint: 0xd9d3c8.Color, casts_shadow: True, has_label: True }

}

draw_floor! : Draw.Frame, FloorMaterial, Warehouse.WarehouseAssets, Camera => Try({}, Draw.ScopeError)
draw_floor! = |frame, floor_shader, model, camera| {
	bounds = get_bounds(Warehouse.layout.position, Warehouse.layout.size)
	floor_y = bounds.min_y - 1
	floor = { texture: model.floor, top_left: camera.project(Physics.point(bounds.min_x, floor_y, bounds.min_z)), bottom_left: camera.project(Physics.point(bounds.min_x, floor_y, bounds.max_z)), bottom_right: camera.project(Physics.point(bounds.max_x, floor_y, bounds.max_z)), top_right: camera.project(Physics.point(bounds.max_x, floor_y, bounds.min_z)), tint: 0xe1e7eb.Color }
	frame.with_shader!(floor_shader.shader, |floor_frame| Drawing.draw_quad!(floor_frame, floor, |point| point))
}

draw_walls! : Draw.Frame, Warehouse.WarehouseAssets, Camera => Try({}, Draw.ScopeError)
draw_walls! = |frame, model, camera| {
	bounds = get_bounds(Warehouse.layout.position, Warehouse.layout.size)
	back_wall = { texture: model.wall, top_left: camera.project(Physics.point(bounds.min_x, bounds.max_y, bounds.min_z - 2)), bottom_left: camera.project(Physics.point(bounds.min_x, bounds.min_y, bounds.min_z - 2)), bottom_right: camera.project(Physics.point(bounds.max_x, bounds.min_y, bounds.min_z - 2)), top_right: camera.project(Physics.point(bounds.max_x, bounds.max_y, bounds.min_z - 2)), tint: 0xd2d9df.Color }
	side_wall = { texture: model.wall, top_left: camera.project(Physics.point(bounds.min_x - 2, bounds.max_y, bounds.max_z)), bottom_left: camera.project(Physics.point(bounds.min_x - 2, bounds.min_y, bounds.max_z)), bottom_right: camera.project(Physics.point(bounds.min_x - 2, bounds.min_y, bounds.min_z)), top_right: camera.project(Physics.point(bounds.min_x - 2, bounds.max_y, bounds.min_z)), tint: 0xb9c4cc.Color }
	Drawing.draw_quad!(frame, back_wall, |point| point)?
	Drawing.draw_quad!(frame, side_wall, |point| point)
}

draw_crate! : Draw.Frame, Warehouse.WarehouseAssets, Camera, Warehouse.Crate => Try({}, Draw.ScopeError)
draw_crate! = |frame, model, camera, crate| {
	bounds = get_bounds(crate.position, crate.size)
	if crate.casts_shadow {
		Drawing.draw_quad!(frame, crate_shadow(model, camera, bounds), |point| point)?
	}
	for face in crate_faces(model, camera, bounds, crate) {
		Drawing.draw_quad!(frame, face, |point| point)?
	}
	for tape in crate_tape(model, camera, bounds) {
		Drawing.draw_quad!(frame, tape, |point| point)?
	}
	Ok({})
}

get_bounds : { x : F32, y : F32, z : F32 }, { width : F32, height : F32, depth : F32 } -> Bounds3
get_bounds = |position, size| {
	{ min_x: position.x, min_y: position.y, min_z: position.z, max_x: position.x + size.width, max_y: position.y + size.height, max_z: position.z + size.depth }
}

crate_faces : Warehouse.WarehouseAssets, Camera, Warehouse.Bounds3, Warehouse.Crate -> List(Drawing.Quad)
crate_faces = |model, camera, bounds, crate| [
	crate_side(model, camera, bounds, crate.side_tint),
	crate_front(model, camera, bounds, crate.front_tint),
	crate_right(model, camera, bounds, crate.side_tint),
	crate_face(model, camera, bounds, crate.face_tint),
]

crate_tape : Warehouse.WarehouseAssets, Camera, Warehouse.Bounds3 -> List(Drawing.Quad)
crate_tape = |model, camera, bounds| [tape_face(model, camera, bounds), tape_front(model, camera, bounds)]

tape_face : Warehouse.WarehouseAssets, Camera, Warehouse.Bounds3 -> Drawing.Quad
tape_face = |model, camera, bounds| {
	mid = (bounds.min_x + bounds.max_x) * 0.5
	half = (bounds.max_x - bounds.min_x) * 0.045
	y = bounds.max_y + 0.9
	{ texture: model.white, top_left: camera.project(Physics.point(mid - half, y, bounds.min_z)), bottom_left: camera.project(Physics.point(mid - half, y, bounds.max_z)), bottom_right: camera.project(Physics.point(mid + half, y, bounds.max_z)), top_right: camera.project(Physics.point(mid + half, y, bounds.min_z)), tint: (0xe1c38f.Color).with_alpha(218) }
}

tape_front : Warehouse.WarehouseAssets, Camera, Warehouse.Bounds3 -> Drawing.Quad
tape_front = |model, camera, bounds| {
	mid = (bounds.min_x + bounds.max_x) * 0.5
	half = (bounds.max_x - bounds.min_x) * 0.045
	{ texture: model.white, top_left: camera.project(Physics.point(mid - half, bounds.max_y, bounds.max_z + 1)), bottom_left: camera.project(Physics.point(mid - half, bounds.min_y, bounds.max_z + 1)), bottom_right: camera.project(Physics.point(mid + half, bounds.min_y, bounds.max_z + 1)), top_right: camera.project(Physics.point(mid + half, bounds.max_y, bounds.max_z + 1)), tint: (0xe1c38f.Color).with_alpha(218) }
}

crate_face : Warehouse.WarehouseAssets, Camera, Warehouse.Bounds3, Color -> Drawing.Quad
crate_face = |model, camera, bounds, tint| {
	{ texture: model.crate, top_left: camera.project(Physics.point(bounds.min_x, bounds.max_y, bounds.min_z)), bottom_left: camera.project(Physics.point(bounds.min_x, bounds.max_y, bounds.max_z)), bottom_right: camera.project(Physics.point(bounds.max_x, bounds.max_y, bounds.max_z)), top_right: camera.project(Physics.point(bounds.max_x, bounds.max_y, bounds.min_z)), tint }
}

crate_front : Warehouse.WarehouseAssets, Camera, Warehouse.Bounds3, Color -> Drawing.Quad
crate_front = |model, camera, bounds, tint| {
	{ texture: model.crate, top_left: camera.project(Physics.point(bounds.min_x, bounds.max_y, bounds.max_z)), bottom_left: camera.project(Physics.point(bounds.min_x, bounds.min_y, bounds.max_z)), bottom_right: camera.project(Physics.point(bounds.max_x, bounds.min_y, bounds.max_z)), top_right: camera.project(Physics.point(bounds.max_x, bounds.max_y, bounds.max_z)), tint }
}

crate_side : Warehouse.WarehouseAssets, Camera, Warehouse.Bounds3, Color -> Drawing.Quad
crate_side = |model, camera, bounds, tint| {
	{ texture: model.crate, top_left: camera.project(Physics.point(bounds.min_x, bounds.max_y, bounds.min_z)), bottom_left: camera.project(Physics.point(bounds.min_x, bounds.min_y, bounds.min_z)), bottom_right: camera.project(Physics.point(bounds.min_x, bounds.min_y, bounds.max_z)), top_right: camera.project(Physics.point(bounds.min_x, bounds.max_y, bounds.max_z)), tint }
}

crate_right : Warehouse.WarehouseAssets, Camera, Warehouse.Bounds3, Color -> Drawing.Quad
crate_right = |model, camera, bounds, tint| {
	{ texture: model.crate, top_left: camera.project(Physics.point(bounds.max_x, bounds.max_y, bounds.max_z)), bottom_left: camera.project(Physics.point(bounds.max_x, bounds.min_y, bounds.max_z)), bottom_right: camera.project(Physics.point(bounds.max_x, bounds.min_y, bounds.min_z)), top_right: camera.project(Physics.point(bounds.max_x, bounds.max_y, bounds.min_z)), tint }
}

crate_shadow : Warehouse.WarehouseAssets, Camera, Warehouse.Bounds3 -> Drawing.Quad
crate_shadow = |model, camera, bounds| {
	margin = 7
	floor_y = Warehouse.layout.position.y - 1
	{ texture: model.white, top_left: camera.project(Physics.point(bounds.min_x - margin + 7, floor_y + 0.4, bounds.min_z - margin + 5)), bottom_left: camera.project(Physics.point(bounds.min_x - margin + 7, floor_y + 0.4, bounds.max_z + margin + 5)), bottom_right: camera.project(Physics.point(bounds.max_x + margin + 7, floor_y + 0.4, bounds.max_z + margin + 5)), top_right: camera.project(Physics.point(bounds.max_x + margin + 7, floor_y + 0.4, bounds.min_z - margin + 5)), tint: (0x000000.Color).with_alpha(105) }
}
