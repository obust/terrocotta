import rr.Math
import ../Collision

Fox := [].{
	State := [Idle, Run, Crouch, Rise, Fall, Hurt].{
		is_eq : _
	}
	Frame := [Idle1, Idle2, Idle3, Idle4, Run1, Run2, Run3, Run4, Run5, Run6, Crouch1, Crouch2, Rise, Fall, Hurt1, Hurt2].{
		is_eq : _
	}
	Input : { move_x : F32, down_down : Bool, jump_down : Bool, jump_pressed : Bool }
	Model : {
		pos : Math.Vec2,
		velocity : Math.Vec2,
		facing : F32,
		grounded : Bool,
		health : U64,
		invulnerable : F32,
		coyote : F32,
		jump_buffer : F32,
		safe_pos : Math.Vec2,
		state : State,
		state_time : F32,
	}

	width : F32
	width = 12
	height : F32
	height = 16
	gravity : F32
	gravity = 500
	run_speed : F32
	run_speed = 150
	jump_speed : F32
	jump_speed = 185
	hurt_duration : F32
	hurt_duration = 2 / 15

	new : Math.Vec2 -> Model
	new = |pos| { pos, velocity: Math.zero, facing: 1, grounded: Bool.True, health: 3, invulnerable: 0, coyote: 0.08, jump_buffer: 0, safe_pos: pos, state: Idle, state_time: 0 }

	body : Model -> Math.Rect
	body = |fox| Math.rect(fox.pos.x - width * 0.5, fox.pos.y - height * 0.5, width, height)

	current_frame : Model -> Frame
	current_frame = |fox| {
		match fox.state {
			Idle => match frame_index(fox.state_time, 4, frame_rate(Idle)) {
				0 => Idle1
				1 => Idle2
				2 => Idle3
				_ => Idle4
			}
			Run => match frame_index(fox.state_time, 6, frame_rate(Run)) {
				0 => Run1
				1 => Run2
				2 => Run3
				3 => Run4
				4 => Run5
				_ => Run6
			}
			Crouch => match frame_index(fox.state_time, 2, frame_rate(Crouch)) {
				0 => Crouch1
				_ => Crouch2
			}
			Rise => Rise
			Fall => Fall
			Hurt => match frame_index(fox.state_time, 2, frame_rate(Hurt)) {
				0 => Hurt1
				_ => Hurt2
			}
		}
	}

	can_take_damage : Model -> Bool
	can_take_damage = |fox| fox.invulnerable <= 0

	damage : Model, F32 -> Model
	damage = |fox, direction| { ..fox, health: if (fox.health > 0) fox.health - 1 else 0, invulnerable: 0.75, velocity: { x: direction * 100, y: -100 }, state: Hurt, state_time: 0 }

	respawn : Model -> Model
	respawn = |fox| { ..fox, pos: fox.safe_pos, velocity: Math.zero, grounded: Bool.False, invulnerable: 0.75 }

	update : Model, Input, List(Math.Rect), List(Math.Rect), F32 -> Model
	update = |fox, input, solids, one_way, dt| {
		buffer = if (input.jump_pressed) 0.1 else F32.max(0, fox.jump_buffer - dt)
		coyote = if (fox.grounded) 0.08 else F32.max(0, fox.coyote - dt)
		jump = input.jump_pressed and (fox.grounded or coyote > 0)
		vy0 = if (jump) 0 - jump_speed else fox.velocity.y + gravity * dt
		vy = if (!input.jump_down and vy0 < 0) vy0 + gravity * 1.4 * dt else vy0
		vx = input.move_x * run_speed
		result = Collision.move(body(fox), { x: vx * dt, y: vy * dt }, solids, one_way)
		grounded = result.landed
		pos = { x: result.body.x + width * 0.5, y: result.body.y + height * 0.5 }
		facing = if (input.move_x != 0) input.move_x else fox.facing
		state = if (fox.state == Hurt and fox.state_time < hurt_duration) Hurt else if (!grounded and vy < 0) Rise else if (!grounded) Fall else if (input.down_down and input.move_x == 0) Crouch else if (input.move_x != 0) Run else Idle
		{ ..fox, pos, velocity: { x: if (result.hit_x) 0 else vx, y: if (grounded or result.hit_ceiling) 0 else vy }, facing, grounded, coyote, jump_buffer: buffer, state, state_time: if (fox.state != state) 0 else fox.state_time + dt, invulnerable: F32.max(0, fox.invulnerable - dt) }
	}

}

frame_index : F32, U64, F32 -> U64
frame_index = |time, count, fps| (F32.floor_to_u64_try(time * fps) ?? 0) % count

frame_rate : Fox.State -> F32
frame_rate = |state| match state {
	Fox.State.Idle => 12
	Fox.State.Run | Fox.State.Hurt => 15
	Fox.State.Crouch => 10
	Fox.State.Rise | Fox.State.Fall => 1
}

expect {
	fox = Fox.new(Math.zero)
	Fox.current_frame(fox) == Fox.Frame.Idle1
}

expect {
	fox = { ..Fox.new(Math.zero), state_time: 0.25 }
	Fox.current_frame(fox) == Fox.Frame.Idle4
}

expect {
	fox = { ..Fox.new(Math.zero), state: Run, state_time: 0.34 }
	Fox.current_frame(fox) == Fox.Frame.Run6
}

expect {
	fox = { ..Fox.new(Math.zero), state: Hurt, state_time: 0.07 }
	Fox.current_frame(fox) == Fox.Frame.Hurt2
}
