import rr.Assets
import rr.Color as RayColor
import rr.Draw
import tc.Color
import SceneCamera exposing [Point2]

SceneRenderer := [].{
	SceneParameters : { seconds : F32, target_uv : { x : F32, y : F32 }, reachable_value : F32, error_amount : F32 }
	Resources : { scene_target : Draw.RenderTexture, floor_shader : Draw.Shader, robot_shader : Draw.Shader, floor_time : Draw.F32Uniform, floor_target_uv : Draw.Vec2Uniform, floor_reachable : Draw.F32Uniform, floor_error : Draw.F32Uniform, robot_time : Draw.F32Uniform, robot_reachable : Draw.F32Uniform, robot_error : Draw.F32Uniform }
	Material := [FloorMaterial, PlainMaterial, RobotMaterial]
	Quad : { texture : Assets.Texture, material : Material, top_left : Point2, bottom_left : Point2, bottom_right : Point2, top_right : Point2, tint : Color }
	Line : { start : Point2, end : Point2, thickness : F32, color : Color }
	Circle : { center : Point2, radius : F32, color : Color }
	RadialGradient : { center : Point2, radius : F32, inner : Color, outer : Color }
	background : Color
	background = 0x080d19.Color
	scene_size : { width : I32, height : I32 }
	scene_size = { width: 900, height: 620 }
}

white_color : RayColor.Rgba
white_color = Draw.from_rgba({ r: 255, g: 255, b: 255, a: 255 })
ray_color : Color -> RayColor.Rgba
ray_color = |c| Draw.from_rgba({ r: c.r, g: c.g, b: c.b, a: c.a })
min_f32 : F32, F32 -> F32
min_f32 = |a, b| if a < b a else b

write_scene_uniforms! : SceneRenderer.Resources, SceneRenderer.SceneParameters => {}
write_scene_uniforms! = |r, p| {
	r.floor_time.set!(p.seconds)
	r.floor_target_uv.set!(p.target_uv)
	r.floor_reachable.set!(p.reachable_value)
	r.floor_error.set!(p.error_amount)
	r.robot_time.set!(p.seconds)
	r.robot_reachable.set!(p.reachable_value)
	r.robot_error.set!(p.error_amount)
}

render! = |frame, resources, parameters, x, y, width, height, draw_scene!| {
	write_scene_uniforms!(resources, parameters)
	fit = min_f32(width / SceneCamera.view_width, height / SceneCamera.view_height)
	frame.with_render_texture!(resources.scene_target, |scene_frame| {
		scene_frame.clear!(ray_color(SceneRenderer.background))
		draw_scene!(scene_frame)?
		Ok({})
	})?
	frame.texture!({ texture: resources.scene_target.texture(), source: resources.scene_target.source(), dest: { x: x + (width - SceneCamera.view_width * fit) * 0.5, y: y + (height - SceneCamera.view_height * fit) * 0.5, width: SceneCamera.view_width * fit, height: SceneCamera.view_height * fit }, origin: { x: 0, y: 0 }, rotation: 0, tint: white_color })
	Ok({})
}

with_material! = |frame, resources, material, body| match material {
	FloorMaterial => frame.with_shader!(resources.floor_shader, body)
	RobotMaterial => frame.with_shader!(resources.robot_shader, body)
	_ => body(frame)
}

draw_quads! = |frame, resources, quads, project, _scale| {
	for quad in quads {
		match Draw.ProjectiveQuad.from_corners({ top_left: project(quad.top_left), bottom_left: project(quad.bottom_left), bottom_right: project(quad.bottom_right), top_right: project(quad.top_right) }) {
			Ok(shape) => with_material!(frame, resources, quad.material, |material_frame| {
				material_frame.projective_texture!({ texture: quad.texture, source: { x: 0, y: 0, width: quad.texture.width.to_f32(), height: quad.texture.height.to_f32() }, quad: shape, tint: ray_color(quad.tint) })
				Ok({})
			})?
			Err(_) => Ok({})?
		}
	}
	Ok({})
}

draw_lines! = |frame, lines, project, scale| { for line in lines { frame.line!({ start: project(line.start), end: project(line.end), stroke: Draw.stroke(ray_color(line.color), line.thickness * scale) }) } Ok({}) }
draw_circles! = |frame, circles, project, scale| { for circle in circles { frame.circle!({ center: project(circle.center), radius: circle.radius * scale, style: Draw.filled(ray_color(circle.color)) }) } Ok({}) }
draw_gradients! = |frame, values, project, scale| frame.with_blend_mode!(Draw.additive_blend, |blend_frame| { for value in values { blend_frame.circle_gradient!({ center: project(value.center), radius: value.radius * scale, color_inner: ray_color(value.inner), color_outer: ray_color(value.outer) }) } Ok({}) })
