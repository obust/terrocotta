import rr.Math

Pickup := [].{
	Kind := [Cherry, Gem].{
		is_eq : _
	}
	Frame := [Cherry1, Cherry2, Cherry3, Cherry4, Cherry5, Cherry6, Cherry7, Gem1, Gem2, Gem3, Gem4, Gem5].{
		is_eq : _
	}
	Model : { id : U64, kind : Kind, pos : Math.Vec2, active : Bool, phase : F32 }
	new : U64, Kind, Math.Vec2 -> Model
	new = |id, kind, pos| { id, kind, pos, active: Bool.True, phase: 0 }
	body : Model -> Math.Rect
	body = |pickup| Math.rect(pickup.pos.x - 6, pickup.pos.y - 6, 12, 12)
	update : Model, F32 -> Model
	update = |pickup, dt| { ..pickup, phase: pickup.phase + dt }
	current_frame : Model -> Frame
	current_frame = |pickup| match pickup.kind {
		Cherry => match frame_index(pickup.phase, 7, 12) {
			0 => Cherry1
			1 => Cherry2
			2 => Cherry3
			3 => Cherry4
			4 => Cherry5
			5 => Cherry6
			_ => Cherry7
		}
		Gem => match frame_index(pickup.phase, 5, 12) {
			0 => Gem1
			1 => Gem2
			2 => Gem3
			3 => Gem4
			_ => Gem5
		}
	}
}

frame_index : F32, U64, F32 -> U64
frame_index = |time, count, fps| (F32.floor_to_u64_try(time * fps) ?? 0) % count
