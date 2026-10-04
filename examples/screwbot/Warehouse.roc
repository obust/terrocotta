## Physical dimensions of the Screwbot warehouse: the floor plane and walls
## the scene is laid out on.
import rr.Assets

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
	Model : {
		crate : Assets.Texture,
		floor : Assets.Texture,
		wall : Assets.Texture,
		white : Assets.Texture,
	}

	init! : Assets.Store => Try(Model, [Exit(I64)])
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
	carton_left = { min_x: -210, min_y: 14, min_z: 78, max_x: -156, max_y: 82, max_z: 145 }
	pallet_left : Bounds3
	pallet_left = { min_x: -218, min_y: 0, min_z: 68, max_x: -148, max_y: 14, max_z: 155 }

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
