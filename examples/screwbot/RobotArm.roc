## A two-link robot arm and its inverse-kinematics solution.
import rr.Physics

RobotArm := {
	upper_length : F32,
	fore_length : F32,
	elbow_up : Bool,
}.{

	## The solved PGA geometry and joint angles for one target.
	Solution := {
		base : Physics.Point,
		elbow : Physics.Point,
		tool : Physics.Point,
		target : Physics.Point,
		target_ground : Physics.Point,
		ground : Physics.Plane,
		upper_axis : Physics.Line,
		fore_axis : Physics.Line,
		target_motor : Physics.Motor,
		base_angle : F32,
		shoulder_angle : F32,
		elbow_angle : F32,
		error : F32,
		reachable : Bool,
	}

	with_upper_length : RobotArm, F32 -> RobotArm
	with_upper_length = |arm, length| { ..arm, upper_length: length }

	with_fore_length : RobotArm, F32 -> RobotArm
	with_fore_length = |arm, length| { ..arm, fore_length: length }

	with_elbow_up : RobotArm, Bool -> RobotArm
	with_elbow_up = |arm, elbow_up| { ..arm, elbow_up }

	solve : RobotArm, Physics.Point -> Solution
	solve = |arm, requested_target| {
		target_offset = requested_target.sub(Physics.origin)
		target_motor = target_offset.translation()
		target = target_motor.apply_motor_point(Physics.origin)
		target_coords = target.coords()

		radial = (target_coords.x * target_coords.x + target_coords.z * target_coords.z).sqrt()
		target_distance = (radial * radial + target_coords.y * target_coords.y).sqrt()
		max_reach = arm.upper_length + arm.fore_length
		min_reach = (arm.upper_length - arm.fore_length).abs()
		reachable = target_distance <= max_reach and target_distance >= min_reach

		raw_elbow_cos = (target_distance * target_distance - arm.upper_length * arm.upper_length - arm.fore_length * arm.fore_length)
			/ (2 * arm.upper_length * arm.fore_length)
		elbow_cos = raw_elbow_cos.max(-1).min(1)
		elbow_magnitude = elbow_cos.acos()
		elbow_angle = if arm.elbow_up {
			0 - elbow_magnitude
		} else {
			elbow_magnitude
		}
		base_angle = atan2(target_coords.z, target_coords.x)
		shoulder_angle = atan2(target_coords.y, radial)
			- atan2(
				arm.fore_length * elbow_angle.sin(),
				arm.upper_length + arm.fore_length * elbow_angle.cos(),
			)

		base_cos = base_angle.cos()
		base_sin = base_angle.sin()
		shoulder_radial = arm.upper_length * shoulder_angle.cos()
		elbow = Physics.point(
			shoulder_radial * base_cos,
			arm.upper_length * shoulder_angle.sin(),
			shoulder_radial * base_sin,
		)

		tool_angle = shoulder_angle + elbow_angle
		fore_radial = arm.fore_length * tool_angle.cos()
		tool = elbow.add(
			Physics.vector(
				fore_radial * base_cos,
				arm.fore_length * tool_angle.sin(),
				fore_radial * base_sin,
			),
		)

		ground = Physics.origin.plane_from_point_normal(Physics.vector(0, 1, 0))

		{
			base: Physics.origin,
			elbow,
			tool,
			target,
			target_ground: ground.project_point_plane(target),
			ground,
			upper_axis: Physics.origin.line_from_points(elbow),
			fore_axis: elbow.line_from_points(tool),
			target_motor,
			base_angle,
			shoulder_angle,
			elbow_angle,
			error: tool.distance(target),
			reachable,
		}
	}
}

atan2 : F32, F32 -> F32
atan2 = |y, x| if x > 0 {
	(y / x).atan()
} else if x < 0 and y >= 0 {
	(y / x).atan() + F32.pi
} else if x < 0 {
	(y / x).atan() - F32.pi
} else if y > 0 {
	F32.pi / 2
} else if y < 0 {
	0 - F32.pi / 2
} else {
	0
}

## A target inside the arm's reach solves to the requested point.
expect {
	arm : RobotArm
	arm = { upper_length: 60, fore_length: 60, elbow_up: False }
	solution = arm.solve(Physics.point(100, 0, 0))
	solution.reachable and solution.error < 0.01
}

## A target beyond the arm's reach reports the remaining distance.
expect {
	arm : RobotArm
	arm = { upper_length: 60, fore_length: 60, elbow_up: False }
	solution = arm.solve(Physics.point(200, 0, 0))
	solution.reachable == False and solution.error > 79
}
