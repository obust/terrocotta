import rr.Math

Feedback := [].{
	Frame := [Feedback1, Feedback2, Feedback3, Feedback4].{
		is_eq : _
	}
	Model : { pos : Math.Vec2, elapsed : F32 }
	spawn : Math.Vec2 -> Model
	spawn = |pos| { pos, elapsed: 0 }
	update : Model, F32 -> Model
	update = |effect, dt| { ..effect, elapsed: effect.elapsed + dt }
	active : Model -> Bool
	active = |effect| effect.elapsed < 0.25
	current_frame : Model -> Frame
	current_frame = |effect| match (F32.floor_to_u64_try(effect.elapsed * 16) ?? 0) % 4 {
		0 => Feedback1
		1 => Feedback2
		2 => Feedback3
		_ => Feedback4
	}
}
