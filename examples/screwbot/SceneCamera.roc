## Projection and orbit controls for the Screwbot warehouse scene.
import rr.Physics
import tc.Event

SceneCamera := { yaw : F32, pitch : F32 }.{
	Point2 : { x : F32, y : F32 }

	## Pointer-drag state for the orbit camera interaction.
	DragState := [DragIdle, Dragging(Point2)]

	## The orbit controller: camera projection plus pointer-drag state.
	CameraController : {
		camera : SceneCamera,
		drag : DragState,
	}

	Msg : [OrbitMove(F32, F32), OrbitEnd]

	initial : CameraController
	initial = { camera: { yaw: 0.48, pitch: 0.34 }, drag: DragIdle }

	## The first right-drag move both starts the orbit and is not itself a
	## delta, so the camera does not jump on the initial press.
	update : CameraController, Msg -> CameraController
	update = |model, msg| match msg {
		OrbitMove(x, y) => {
			position = { x, y }
			match model.drag {
				DragIdle => { ..model, drag: Dragging(position) }
				Dragging(previous) => {
					dx = position.x - previous.x
					dy = position.y - previous.y
					{ camera: model.camera.orbit(dx, dy), drag: Dragging(position) }
				}
			}
		}
		OrbitEnd => match model.drag {
			DragIdle => model
			Dragging(_) => { ..model, drag: DragIdle }
		}
	}

	view_width : F32
	view_width = 900

	view_height : F32
	view_height = 620

	far_depth : F32
	far_depth = 1150

	orbit : SceneCamera, F32, F32 -> SceneCamera
	orbit = |camera, delta_x, delta_y| {
		..camera,
		yaw: clamp(camera.yaw + delta_x * 0.008, -1.15, 1.15),
		pitch: clamp(camera.pitch - delta_y * 0.006, 0.14, 0.95),
	}

	project : SceneCamera, Physics.Point -> Point2
	project = |camera, point| {
		coordinates = point.coords()
		camera_basis = basis(camera)
		right = camera_basis.right.components()
		up = camera_basis.up.components()
		forward = camera_basis.forward.components()
		point_depth = coordinates.x * forward.x + coordinates.y * forward.y + coordinates.z * forward.z
		perspective = perspective_at_depth(point_depth)
		{
			x: world_origin.x + world_scale * perspective * (coordinates.x * right.x + coordinates.y * right.y + coordinates.z * right.z),
			y: world_origin.y - world_scale * perspective * (coordinates.x * up.x + coordinates.y * up.y + coordinates.z * up.z),
		}
	}

	depth : SceneCamera, Physics.Point -> F32
	depth = |camera, point| {
		coordinates = point.coords()
		forward = basis(camera).forward.components()
		coordinates.x * forward.x + coordinates.y * forward.y + coordinates.z * forward.z
	}

	## Unproject one viewport point onto the plane at the current target's depth.
	target_at : SceneCamera, Physics.Point, Point2 -> Physics.Point
	target_at = |camera, current_target, screen| {
		camera_basis = basis(camera)
		right = camera_basis.right.components()
		up = camera_basis.up.components()
		forward = camera_basis.forward.components()
		point_depth = camera.depth(current_target)
		perspective = perspective_at_depth(point_depth)
		u = (screen.x - world_origin.x) / (world_scale * perspective)
		v = (world_origin.y - screen.y) / (world_scale * perspective)

		Physics.point(
			clamp(right.x * u + up.x * v + forward.x * point_depth, -230, 230),
			clamp(right.y * u + up.y * v + forward.y * point_depth, 5, 285),
			clamp(right.z * u + up.z * v + forward.z * point_depth, -190, 190),
		)
	}

	## Convert a pointer in a letterboxed canvas back into a world-space target.
	## This stays with projection and unprojection rather than the draw helpers.
	target_from_pointer : Event.PointerEvent, Physics.Point, SceneCamera -> Physics.Point
	target_from_pointer = |event, current_target, camera| {
		relative = event.target.bounds.relative(event.position)
		scale = (event.target.bounds.width / SceneCamera.view_width).min(event.target.bounds.height / SceneCamera.view_height).max(0.001)
		offset_x = (event.target.bounds.width - SceneCamera.view_width * scale) * 0.5
		offset_y = (event.target.bounds.height - SceneCamera.view_height * scale) * 0.5
		camera.target_at(current_target, { x: (relative.x - offset_x) / scale, y: (relative.y - offset_y) / scale })
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
clamp = |value, lo, hi| value.min(hi).max(lo)

basis : SceneCamera -> CameraBasis
basis = |camera| {
	sin_yaw = camera.yaw.sin()
	cos_yaw = camera.yaw.cos()
	sin_pitch = camera.pitch.sin()
	cos_pitch = camera.pitch.cos()

	{
		right: Physics.vector(cos_yaw, 0, 0 - sin_yaw),
		up: Physics.vector(0 - sin_yaw * sin_pitch, cos_pitch, 0 - cos_yaw * sin_pitch),
		forward: Physics.vector(sin_yaw * cos_pitch, sin_pitch, cos_yaw * cos_pitch),
	}
}

perspective_at_depth : F32 -> F32
perspective_at_depth = |point_depth| SceneCamera.far_depth / (SceneCamera.far_depth - point_depth)

## The origin projects to the viewport origin at zero scene depth.
expect {
	camera : SceneCamera
	camera = { yaw: 0, pitch: 0 }
	camera.project(Physics.origin) == world_origin and camera.depth(Physics.origin) == 0
}

## Orbit updates remain inside the configured yaw and pitch limits.
expect {
	camera : SceneCamera
	camera = { yaw: 0, pitch: 0.5 }
	bounded = camera.orbit(1000, -1000)
	bounded.yaw == 1.15 and bounded.pitch == 0.95
}
