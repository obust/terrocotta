import rr.Math

Eagle := [].{
	Frame := [Attack1, Attack2, Attack3, Attack4].{
		is_eq : _
	}
	update = |eagle, player, dt| {
		phase = eagle.phase + dt
		{ ..eagle, phase, pos: { x: eagle.pos.x, y: eagle.pos.y + F32.sin(phase * 2) * 18 * dt }, facing: if player.x < eagle.pos.x -1 else 1 }
	}
	current_frame : { phase : F32, .. } -> Frame
	current_frame = |eagle| match frame_index(eagle.phase, 4, 12) {
		0 => Attack1
		1 => Attack2
		2 => Attack3
		_ => Attack4
	}
}

frame_index : F32, U64, F32 -> U64
frame_index = |time, count, fps| (F32.floor_to_u64_try(time * fps) ?? 0) % count
