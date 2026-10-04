## Small drawing, formatting, and projection helpers shared by the Screwbot
## scene modules: short constructors for SceneRenderer's plain records plus
## the camera-projection wrappers the warehouse and robot layers build on.
import rr.Assets
import rr.Physics

import tc.Color
import tc.Event

import SceneCamera exposing [Point2]
import SceneRenderer

ScenePrimitives := [].{

	clamp : F32, F32, F32 -> F32
	clamp = |value, lo, hi| value.min(hi).max(lo)

	decimal : F32 -> Str
	decimal = |value| match (value * 10).round_to_i64_try() {
		Ok(scaled) => (scaled.to_f32() / 10).to_str()
		Err(_) => value.to_str()
	}

	degrees : F32 -> F32
	degrees = |radians| radians * 180 / F32.pi

	line : Point2, Point2, F32, Color -> SceneRenderer.Line
	line = |start, end, thickness, color| { start, end, thickness, color }

	circle : Point2, F32, Color -> SceneRenderer.Circle
	circle = |center, radius, color| { center, radius, color }

	radial_gradient : Point2, F32, Color, Color -> SceneRenderer.RadialGradient
	radial_gradient = |center, radius, inner, outer| { center, radius, inner, outer }

	world_line : SceneCamera, Physics.Point, Physics.Point, F32, Color -> SceneRenderer.Line
	world_line = |camera, start, end, thickness, color| {
		ScenePrimitives.line(camera.project(start), camera.project(end), thickness, color)
	}

	## One planar surface projected through the scene camera.
	ProjectedFace : {
		top_left : Point2,
		bottom_left : Point2,
		bottom_right : Point2,
		top_right : Point2,
		tint : Color,
	}

	projected_face : SceneCamera, Physics.Point, Physics.Point, Physics.Point, Physics.Point, Color -> ProjectedFace
	projected_face = |camera, top_left, bottom_left, bottom_right, top_right, tint| {
		top_left: camera.project(top_left),
		bottom_left: camera.project(bottom_left),
		bottom_right: camera.project(bottom_right),
		top_right: camera.project(top_right),
		tint,
	}

	face_quad : Assets.Texture, SceneRenderer.Material, ProjectedFace -> SceneRenderer.Quad
	face_quad = |texture_value, material, face| {
		texture: texture_value,
		material,
		top_left: face.top_left,
		bottom_left: face.bottom_left,
		bottom_right: face.bottom_right,
		top_right: face.top_right,
		tint: face.tint,
	}

	link_parallel : Point2, Point2, F32, F32, Color -> SceneRenderer.Line
	link_parallel = |start, end, offset, thickness, color| {
		dx = end.x - start.x
		dy = end.y - start.y
		length = (dx * dx + dy * dy).sqrt().max(1)
		normal_x = (0 - dy) / length * offset
		normal_y = dx / length * offset
		ScenePrimitives.line(
			{ x: start.x + normal_x, y: start.y + normal_y },
			{ x: end.x + normal_x, y: end.y + normal_y },
			thickness,
			color,
		)
	}

	link_tick : Point2, Point2, F32, F32, Color -> SceneRenderer.Line
	link_tick = |start, end, along, width, color| {
		dx = end.x - start.x
		dy = end.y - start.y
		length = (dx * dx + dy * dy).sqrt().max(1)
		center = { x: start.x + dx * along, y: start.y + dy * along }
		normal_x = (0 - dy) / length * width * 0.5
		normal_y = dx / length * width * 0.5
		ScenePrimitives.line(
			{ x: center.x - normal_x, y: center.y - normal_y },
			{ x: center.x + normal_x, y: center.y + normal_y },
			1.5,
			color,
		)
	}

	link_quad : Assets.Texture, SceneRenderer.Material, Point2, Point2, F32, F32, Color -> SceneRenderer.Quad
	link_quad = |texture_value, material, start, end, start_width, end_width, tint| {
		dx = end.x - start.x
		dy = end.y - start.y
		length = (dx * dx + dy * dy).sqrt().max(1)
		start_normal_x = (0 - dy) / length * start_width * 0.5
		start_normal_y = dx / length * start_width * 0.5
		end_normal_x = (0 - dy) / length * end_width * 0.5
		end_normal_y = dx / length * end_width * 0.5
		{
			texture: texture_value,
			material,
			top_left: { x: start.x + start_normal_x, y: start.y + start_normal_y },
			bottom_left: { x: start.x - start_normal_x, y: start.y - start_normal_y },
			bottom_right: { x: end.x - end_normal_x, y: end.y - end_normal_y },
			top_right: { x: end.x + end_normal_x, y: end.y + end_normal_y },
			tint,
		}
	}

	shadow_on_ground : Physics.Point -> Physics.Point
	shadow_on_ground = |point| {
		c = point.coords()
		Physics.point(c.x + c.y * 0.22, 1, c.z + c.y * 0.16)
	}

	target_from_pointer : Event.PointerEvent, Physics.Point, SceneCamera -> Physics.Point
	target_from_pointer = |event, current_target, camera| {
		relative = event.target.bounds.relative(event.position)
		scale_x = event.target.bounds.width / SceneCamera.view_width
		scale_y = event.target.bounds.height / SceneCamera.view_height
		canvas_scale = scale_x.min(scale_y).max(0.001)
		offset_x = (event.target.bounds.width - SceneCamera.view_width * canvas_scale) * 0.5
		offset_y = (event.target.bounds.height - SceneCamera.view_height * canvas_scale) * 0.5
		screen_x = (relative.x - offset_x) / canvas_scale
		screen_y = (relative.y - offset_y) / canvas_scale
		camera.target_at(current_target, { x: screen_x, y: screen_y })
	}
}
