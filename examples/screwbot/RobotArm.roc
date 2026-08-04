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
		target_offset = Physics.sub(requested_target, Physics.origin)
		target_motor = Physics.translation(target_offset)
		target = Physics.apply_motor_point(target_motor, Physics.origin)
		target_coords = Physics.coords(target)

		radial = F32.sqrt(target_coords.x * target_coords.x + target_coords.z * target_coords.z)
		target_distance = F32.sqrt(radial * radial + target_coords.y * target_coords.y)
		max_reach = arm.upper_length + arm.fore_length
		min_reach = F32.abs(arm.upper_length - arm.fore_length)
		reachable = target_distance <= max_reach and target_distance >= min_reach

		elbow_cos = F32.max(
			-1,
			F32.min(
				(target_distance * target_distance - arm.upper_length * arm.upper_length - arm.fore_length * arm.fore_length)
					/ (2 * arm.upper_length * arm.fore_length),
				1,
			),
		)
		elbow_magnitude = F32.acos(elbow_cos)
		elbow_angle = if arm.elbow_up {
			0 - elbow_magnitude
		} else {
			elbow_magnitude
		}
		base_angle = atan2(target_coords.z, target_coords.x)
		shoulder_angle = atan2(target_coords.y, radial)
			- atan2(
				arm.fore_length * F32.sin(elbow_angle),
				arm.upper_length + arm.fore_length * F32.cos(elbow_angle),
			)

		base_cos = F32.cos(base_angle)
		base_sin = F32.sin(base_angle)
		shoulder_radial = arm.upper_length * F32.cos(shoulder_angle)
		elbow = Physics.point(
			shoulder_radial * base_cos,
			arm.upper_length * F32.sin(shoulder_angle),
			shoulder_radial * base_sin,
		)

		tool_angle = shoulder_angle + elbow_angle
		fore_radial = arm.fore_length * F32.cos(tool_angle)
		tool = Physics.add(
			elbow,
			Physics.vector(
				fore_radial * base_cos,
				arm.fore_length * F32.sin(tool_angle),
				fore_radial * base_sin,
			),
		)

		ground = Physics.plane_from_point_normal(Physics.origin, Physics.vector(0, 1, 0))

		{
			base: Physics.origin,
			elbow,
			tool,
			target,
			target_ground: Physics.project_point_plane(ground, target),
			ground,
			upper_axis: Physics.line_from_points(Physics.origin, elbow),
			fore_axis: Physics.line_from_points(elbow, tool),
			target_motor,
			base_angle,
			shoulder_angle,
			elbow_angle,
			error: Physics.distance(tool, target),
			reachable,
		}
	}
}

atan2 : F32, F32 -> F32
atan2 = |y, x| {
	if x > 0 {
		F32.atan(y / x)
	} else if x < 0 and y >= 0 {
		F32.atan(y / x) + F32.pi
	} else if x < 0 {
		F32.atan(y / x) - F32.pi
	} else if y > 0 {
		F32.pi / 2
	} else if y < 0 {
		0 - F32.pi / 2
	} else {
		0
	}
}

expect {
	arm : RobotArm
	arm = { upper_length: 60, fore_length: 60, elbow_up: False }
	solution = RobotArm.solve(arm, Physics.point(100, 0, 0))
	solution.reachable and solution.error < 0.01
}

expect {
	arm : RobotArm
	arm = { upper_length: 60, fore_length: 60, elbow_up: False }
	solution = RobotArm.solve(arm, Physics.point(200, 0, 0))
	solution.reachable == False and solution.error > 79
}
