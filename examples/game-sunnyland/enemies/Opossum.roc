import rr.Math
import ../core/Collision

Opossum := [].{
	Frame := [Run1, Run2, Run3, Run4, Run5, Run6].{
		is_eq : _
	}
	update = |opossum, bounds, solids, one_way, dt| {
		phase = opossum.phase + dt
		direction = if opossum.pos.x < bounds.x + 8 or opossum.pos.x > Math.right(bounds) - 8 0 - opossum.facing else opossum.facing
		prepared = { ..opossum, facing: direction, velocity: { x: direction * 60, y: opossum.velocity.y } }
		{ ..ground_update(prepared, direction * 60, solids, one_way, dt), phase }
	}
	current_frame : { phase : F32, .. } -> Frame
	current_frame = |opossum| match frame_index(opossum.phase, 6, 12) {
		0 => Run1
		1 => Run2
		2 => Run3
		3 => Run4
		4 => Run5
		_ => Run6
	}
}

ground_update = |opossum, horizontal_speed, solids, one_way, dt| {
	vertical_speed = opossum.velocity.y + 500 * dt
	result = Collision.move(Math.rect(opossum.pos.x - 8, opossum.pos.y - 8, 16, 16), { x: horizontal_speed * dt, y: vertical_speed * dt }, solids, one_way)
	{ ..opossum, pos: { x: result.body.x + 8, y: result.body.y + 8 }, facing: if result.hit_x 0 - opossum.facing else opossum.facing, velocity: { x: if result.hit_x 0 else horizontal_speed, y: if result.landed 0 else vertical_speed } }
}

frame_index : F32, U64, F32 -> U64
frame_index = |time, count, fps| (F32.floor_to_u64_try(time * fps) ?? 0) % count
