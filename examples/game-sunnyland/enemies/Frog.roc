import rr.Math
import ../core/Collision

Frog := [].{
	Frame := [Idle1, Idle2, Idle3, Idle4, Rise, Fall].{
		is_eq : _
	}
	update = |frog, solids, one_way, dt| {
		phase = frog.phase + dt
		jumping = F32.sin(phase * 3) > 0.97 and frog.velocity.y == 0
		jump_x = if F32.sin(phase * 2) < 0 -100 else 100
		prepared = if jumping { ..frog, facing: if jump_x < 0 1 else -1, velocity: { x: jump_x, y: -200 } } else frog
		{ ..ground_update(prepared, prepared.velocity.x, solids, one_way, dt), phase }
	}
	current_frame : { phase : F32, velocity : Math.Vec2, .. } -> Frame
	current_frame = |frog| if frog.velocity.y < 0 Rise else if frog.velocity.y > 0 Fall else match frame_index(frog.phase, 4, 6) {
		0 => Idle1
		1 => Idle2
		2 => Idle3
		_ => Idle4
	}
}

ground_update = |frog, horizontal_speed, solids, one_way, dt| {
	vertical_speed = frog.velocity.y + 500 * dt
	result = Collision.move(Math.rect(frog.pos.x - 8, frog.pos.y - 8, 16, 16), { x: horizontal_speed * dt, y: vertical_speed * dt }, solids, one_way)
	{ ..frog, pos: { x: result.body.x + 8, y: result.body.y + 8 }, velocity: { x: if result.landed or result.hit_x 0 else horizontal_speed, y: if result.landed 0 else vertical_speed } }
}

frame_index : F32, U64, F32 -> U64
frame_index = |time, count, fps| (F32.floor_to_u64_try(time * fps) ?? 0) % count
