import rr.Assets
import rr.Color as RayColor
import rr.Draw
import rr.Physics
import tc.Color
import tc.Palette as BuiltinPalette
import ../scene/Camera exposing [Point2]

Drawing := [].{
	SceneParameters : { seconds : F32, target_uv : { x : F32, y : F32 }, reachable : Bool, error_amount : F32 }
	Quad : { texture : Assets.Texture, top_left : Point2, bottom_left : Point2, bottom_right : Point2, top_right : Point2, tint : Color }
	Line : { start : Point2, end : Point2, thickness : F32, color : Color }
	Circle : { center : Point2, radius : F32, color : Color }
	RadialGradient : { center : Point2, radius : F32, inner : Color, outer : Color }
	background : Color
	background = BuiltinPalette.atom_dark.background.darken(8)
	scene_size : { width : I32, height : I32 }
	scene_size = { width: 900, height: 620 }

	white_color : RayColor.Rgba
	white_color = Draw.from_rgba({ r: 255, g: 255, b: 255, a: 255 })
	ray_color : Color -> RayColor.Rgba
	ray_color = |c| Draw.from_rgba({ r: c.r, g: c.g, b: c.b, a: c.a })
	draw_quad! = |frame, quad, project| {
		match Draw.ProjectiveQuad.from_corners({ top_left: project(quad.top_left), bottom_left: project(quad.bottom_left), bottom_right: project(quad.bottom_right), top_right: project(quad.top_right) }) {
			Ok(shape) => {
				frame.projective_texture!({ texture: quad.texture, source: { x: 0, y: 0, width: quad.texture.width.to_f32(), height: quad.texture.height.to_f32() }, quad: shape, tint: ray_color(quad.tint) })
				Ok({})
			}
			Err(_) => Ok({})
		}
	}

	draw_line! = |frame, line, project, scale| {
		frame.line!({ start: project(line.start), end: project(line.end), stroke: Draw.stroke(ray_color(line.color), line.thickness * scale) })
		Ok({})
	}
	draw_circle! = |frame, circle, project, scale| {
		frame.circle!({ center: project(circle.center), radius: circle.radius * scale, style: Draw.filled(ray_color(circle.color)) })
		Ok({})
	}
	draw_gradient! = |frame, value, project, scale| frame.with_blend_mode!(
		Draw.additive_blend,
		|blend_frame| {
			blend_frame.circle_gradient!({ center: project(value.center), radius: value.radius * scale, color_inner: ray_color(value.inner), color_outer: ray_color(value.outer) })
			Ok({})
		},
	)

	clamp : F32, F32, F32 -> F32
	clamp = |value, lo, hi| value.min(hi).max(lo)
	degrees : F32 -> F32
	degrees = |radians| radians * 180 / F32.pi
	line : Point2, Point2, F32, Color -> Drawing.Line
	line = |start, end, thickness, color| { start, end, thickness, color }
	circle : Point2, F32, Color -> Drawing.Circle
	circle = |center, radius, color| { center, radius, color }
	radial_gradient : Point2, F32, Color, Color -> Drawing.RadialGradient
	radial_gradient = |center, radius, inner, outer| { center, radius, inner, outer }
	world_line : Camera, Physics.Point, Physics.Point, F32, Color -> Drawing.Line
	world_line = |camera, start, end, thickness, color| line(camera.project(start), camera.project(end), thickness, color)
	shadow_on_ground : Physics.Point -> Physics.Point
	shadow_on_ground = |point| {
		c = point.coords()
		Physics.point(c.x + c.y * 0.22, 1, c.z + c.y * 0.16)
	}
	link_parallel : Point2, Point2, F32, F32, Color -> Drawing.Line
	link_parallel = |start, end, offset, thickness, color| {
		dx = end.x - start.x
		dy = end.y - start.y
		length = (dx * dx + dy * dy).sqrt().max(1)
		line({ x: start.x - dy / length * offset, y: start.y + dx / length * offset }, { x: end.x - dy / length * offset, y: end.y + dx / length * offset }, thickness, color)
	}
	link_tick : Point2, Point2, F32, F32, Color -> Drawing.Line
	link_tick = |start, end, along, width, color| {
		dx = end.x - start.x
		dy = end.y - start.y
		length = (dx * dx + dy * dy).sqrt().max(1)
		center = { x: start.x + dx * along, y: start.y + dy * along }
		line({ x: center.x + dy / length * width * 0.5, y: center.y - dx / length * width * 0.5 }, { x: center.x - dy / length * width * 0.5, y: center.y + dx / length * width * 0.5 }, 1.5, color)
	}
	link_quad : Assets.Texture, Point2, Point2, F32, F32, Color -> Drawing.Quad
	link_quad = |texture, start, end, start_width, end_width, tint| {
		dx = end.x - start.x
		dy = end.y - start.y
		length = (dx * dx + dy * dy).sqrt().max(1)
		snx = -dy / length * start_width * 0.5
		sny = dx / length * start_width * 0.5
		enx = -dy / length * end_width * 0.5
		eny = dx / length * end_width * 0.5
		{ texture, top_left: { x: start.x + snx, y: start.y + sny }, bottom_left: { x: start.x - snx, y: start.y - sny }, bottom_right: { x: end.x - enx, y: end.y - eny }, top_right: { x: end.x + enx, y: end.y + eny }, tint }
	}
}
