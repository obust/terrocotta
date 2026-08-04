## Projection and orbit controls for the Screwbot warehouse scene.
import rr.Physics

SceneCamera := { yaw : F32, pitch : F32 }.{
	Point2 : { x : F32, y : F32 }

	view_width : F32
	view_width = 900

	view_height : F32
	view_height = 620

	far_depth : F32
	far_depth = 1150

	orbit : SceneCamera, F32, F32 -> SceneCamera
	orbit = |camera, delta_x, delta_y| {
		{
			..camera,
			yaw: clamp(camera.yaw + delta_x * 0.008, -1.15, 1.15),
			pitch: clamp(camera.pitch - delta_y * 0.006, 0.14, 0.95),
		}
	}

	project : SceneCamera, Physics.Point -> Point2
	project = |camera, point| {
		coordinates = Physics.coords(point)
		camera_basis = basis(camera)
		right = Physics.components(camera_basis.right)
		up = Physics.components(camera_basis.up)
		forward = Physics.components(camera_basis.forward)
		point_depth = coordinates.x * forward.x + coordinates.y * forward.y + coordinates.z * forward.z
		perspective = perspective_at_depth(point_depth)
		{
			x: world_origin.x + world_scale * perspective * (coordinates.x * right.x + coordinates.y * right.y + coordinates.z * right.z),
			y: world_origin.y - world_scale * perspective * (coordinates.x * up.x + coordinates.y * up.y + coordinates.z * up.z),
		}
	}

	depth : SceneCamera, Physics.Point -> F32
	depth = |camera, point| {
		coordinates = Physics.coords(point)
		forward = Physics.components(basis(camera).forward)
		coordinates.x * forward.x + coordinates.y * forward.y + coordinates.z * forward.z
	}

	## Unproject one viewport point onto the plane at the current target's depth.
	target_at : SceneCamera, Physics.Point, Point2 -> Physics.Point
	target_at = |camera, current_target, screen| {
		camera_basis = basis(camera)
		right = Physics.components(camera_basis.right)
		up = Physics.components(camera_basis.up)
		forward = Physics.components(camera_basis.forward)
		point_depth = SceneCamera.depth(camera, current_target)
		perspective = perspective_at_depth(point_depth)
		u = (screen.x - world_origin.x) / (world_scale * perspective)
		v = (world_origin.y - screen.y) / (world_scale * perspective)

		Physics.point(
			clamp(right.x * u + up.x * v + forward.x * point_depth, -230, 230),
			clamp(right.y * u + up.y * v + forward.y * point_depth, 5, 285),
			clamp(right.z * u + up.z * v + forward.z * point_depth, -190, 190),
		)
	}
}

CameraBasis : {
	right : Physics.Vector,
	up : Physics.Vector,
	forward : Physics.Vector,
}

world_scale : F32
world_scale = 1.55

world_origin : SceneCamera.Point2
world_origin = { x: 430, y: 450 }

clamp : F32, F32, F32 -> F32
clamp = |value, lo, hi| F32.max(lo, F32.min(value, hi))

basis : SceneCamera -> CameraBasis
basis = |camera| {
	sin_yaw = F32.sin(camera.yaw)
	cos_yaw = F32.cos(camera.yaw)
	sin_pitch = F32.sin(camera.pitch)
	cos_pitch = F32.cos(camera.pitch)

	{
		right: Physics.vector(cos_yaw, 0, 0 - sin_yaw),
		up: Physics.vector(0 - sin_yaw * sin_pitch, cos_pitch, 0 - cos_yaw * sin_pitch),
		forward: Physics.vector(sin_yaw * cos_pitch, sin_pitch, cos_yaw * cos_pitch),
	}
}

perspective_at_depth : F32 -> F32
perspective_at_depth = |point_depth| SceneCamera.far_depth / (SceneCamera.far_depth - point_depth)

expect {
	camera : SceneCamera
	camera = { yaw: 0, pitch: 0 }
	SceneCamera.project(camera, Physics.origin) == world_origin and SceneCamera.depth(camera, Physics.origin) == 0
}

expect {
	camera : SceneCamera
	camera = { yaw: 0, pitch: 0.5 }
	bounded = camera.orbit(1000, -1000)
	bounded.yaw == 1.15 and bounded.pitch == 0.95
}
