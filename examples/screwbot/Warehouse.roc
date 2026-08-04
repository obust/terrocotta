## Physical dimensions and fixed props for the Screwbot warehouse.
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

	## An axis-aligned volume in warehouse world space.
	Bounds3 := {
		min_x : F32,
		min_y : F32,
		min_z : F32,
		max_x : F32,
		max_y : F32,
		max_z : F32,
	}.{
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
		fixture_a_z = -125
		fixture_b_z = 65
		[
			post_bounds(warehouse, left, rear),
			post_bounds(warehouse, right, rear),
			post_bounds(warehouse, left, front),
			post_bounds(warehouse, right, front),
			x_beam_bounds(warehouse, rear, top_y, warehouse.beam_size),
			x_beam_bounds(warehouse, front, top_y, warehouse.beam_size),
			z_beam_bounds(warehouse, left, top_y, warehouse.beam_size),
			z_beam_bounds(warehouse, right, top_y, warehouse.beam_size),
			x_beam_bounds(warehouse, fixture_a_z, cross_y, warehouse.beam_size),
			x_beam_bounds(warehouse, fixture_b_z, cross_y, warehouse.beam_size),
			fixture_bounds(warehouse, fixture_a_z),
			fixture_bounds(warehouse, fixture_b_z),
			hanger_bounds(warehouse, -100, fixture_a_z),
			hanger_bounds(warehouse, 100, fixture_a_z),
			hanger_bounds(warehouse, -100, fixture_b_z),
			hanger_bounds(warehouse, 100, fixture_b_z),
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
	left = warehouse.min_x + warehouse.frame_inset_x
	right = warehouse.max_x - warehouse.frame_inset_x
	{ min_x: left - half, min_y, min_z: z - half, max_x: right + half, max_y: min_y + size, max_z: z + half }
}

z_beam_bounds : Warehouse, F32, F32, F32 -> Warehouse.Bounds3
z_beam_bounds = |warehouse, x, min_y, size| {
	half = size * 0.5
	rear = warehouse.min_z + warehouse.frame_inset_z
	front = warehouse.max_z - warehouse.frame_inset_z
	{ min_x: x - half, min_y, min_z: rear, max_x: x + half, max_y: min_y + size, max_z: front }
}

fixture_bounds : Warehouse, F32 -> Warehouse.Bounds3
fixture_bounds = |warehouse, z| {
	{ min_x: -112, min_y: warehouse.fixture_y - 5, min_z: z - 5, max_x: 112, max_y: warehouse.fixture_y + 5, max_z: z + 5 }
}

hanger_bounds : Warehouse, F32, F32 -> Warehouse.Bounds3
hanger_bounds = |warehouse, x, z| {
	{ min_x: x - 3, min_y: warehouse.fixture_y + 5, min_z: z - 3, max_x: x + 3, max_y: warehouse.frame_height - warehouse.beam_size * 2, max_z: z + 3 }
}

## The composed warehouse frame contains every post, beam, fixture, and hanger.
expect Warehouse.layout.structure().len() == 16

## The lower-right carton retains its configured width.
expect Warehouse.carton_right_lower.width() == 75

## The pallet expands into four slats and two runners.
expect Warehouse.pallet_left.pallet_parts().len() == 6
