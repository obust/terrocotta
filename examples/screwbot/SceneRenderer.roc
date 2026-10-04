## Screwbot's shader pipeline and immediate scene drawing.
##
## The scene is described as plain records so the scene components can build it
## layer by layer. `draw!` consumes that description together with the resolved
## canvas bounds and issues host draw calls directly; Terrocotta's canvas leaf
## runs this closure during `render!`, so no retained command list is involved.
import rr.Assets
import rr.Color as RayColor
import rr.Draw
import rr.Math

import tc.Color
import tc.Layout

import SceneCamera exposing [Point2]

SceneRenderer := [].{

	## Resource-free scene values written to the shader uniforms each frame.
	##
	## `seconds` is a constant `0` for now: the current Program API has no
	## per-frame timestamp, so the floor ring and warning pulse hold their first
	## frame's phase instead of advancing with wall-clock time.
	SceneParameters : {
		seconds : F32,
		target_uv : { x : F32, y : F32 },
		reachable_value : F32,
		error_amount : F32,
	}

	## GPU resources owned by the model for the lifetime of the app: the
	## compositor pipeline (render targets, material shaders, uniforms).
	## Component textures are owned by the components themselves.
	Resources : {
		scene_target : Draw.RenderTexture,
		bloom_a : Draw.RenderTexture,
		bloom_b : Draw.RenderTexture,
		floor_shader : Draw.Shader,
		robot_shader : Draw.Shader,
		emissive_shader : Draw.Shader,
		blur_shader : Draw.Shader,
		composite_shader : Draw.Shader,
		floor_time : Draw.F32Uniform,
		floor_target_uv : Draw.Vec2Uniform,
		floor_reachable : Draw.F32Uniform,
		floor_error : Draw.F32Uniform,
		robot_time : Draw.F32Uniform,
		robot_reachable : Draw.F32Uniform,
		robot_error : Draw.F32Uniform,
		blur_direction : Draw.Vec2Uniform,
		blur_resolution : Draw.Vec2Uniform,
		composite_time : Draw.F32Uniform,
		composite_resolution : Draw.Vec2Uniform,
		composite_bloom : Draw.TextureUniform,
	}

	## Which material a projected quad samples, and which shader binds to it.
	Material := [CrateMaterial, FloorMaterial, PlainMaterial, RobotMaterial]

	## A planar surface projected through the scene camera, ordered for depth.
	Quad : {
		texture : Assets.Texture,
		material : Material,
		top_left : Point2,
		bottom_left : Point2,
		bottom_right : Point2,
		top_right : Point2,
		tint : Color,
		depth : F32,
	}

	## A projected stroke in scene viewport coordinates.
	Line : {
		start : Point2,
		end : Point2,
		thickness : F32,
		color : Color,
		depth : F32,
	}

	## A projected disc in scene viewport coordinates.
	Circle : {
		center : Point2,
		radius : F32,
		color : Color,
		depth : F32,
	}

	## An additive light pool projected onto the floor.
	RadialGradient : {
		center : Point2,
		radius : F32,
		inner : Color,
		outer : Color,
	}

	## The whole frame's worth of geometry, in scene viewport coordinates.
	##
	## `texture_quads` are the opaque warehouse surfaces, `underlay_lines` are
	## drawn over them but below the glows, and the remaining lists are sorted
	## together by depth.
	Scene : {
		parameters : SceneParameters,
		texture_quads : List(Quad),
		underlay_lines : List(Line),
		overlay_texture_quads : List(Quad),
		radial_gradients : List(RadialGradient),
		lines : List(Line),
		circles : List(Circle),
	}

	## One component's contribution to a frame: pure geometry, without the
	## global shader parameters. `Scene.combine` stacks a list of layers into
	## a `Scene` by concatenating each field in layer order.
	Layer : {
		texture_quads : List(Quad),
		underlay_lines : List(Line),
		overlay_texture_quads : List(Quad),
		radial_gradients : List(RadialGradient),
		lines : List(Line),
		circles : List(Circle),
	}

	empty_layer : Layer
	empty_layer = {
		texture_quads: [],
		underlay_lines: [],
		overlay_texture_quads: [],
		radial_gradients: [],
		lines: [],
		circles: [],
	}

	background : Color
	background = 0x080d19.Color

	bloom_size : { width : I32, height : I32 }
	bloom_size = { width: 450, height: 310 }

	scene_size : { width : I32, height : I32 }
	scene_size = { width: 900, height: 620 }

	## Draw one Screwbot frame into the canvas leaf's resolved bounds.
	draw! : Draw.Frame, Resources, Scene, F32, F32, F32, F32 => Try({}, Draw.ScopeError)
	draw! = |frame, resources, scene, canvas_x, canvas_y, canvas_width, canvas_height| {
		write_scene_uniforms!(resources, scene.parameters)

		# How the fixed scene viewport is fitted into the resolved canvas leaf.
		fit_x = canvas_width / SceneCamera.view_width
		fit_y = canvas_height / SceneCamera.view_height
		fit = min_f32(fit_x, fit_y)
		offset_x = canvas_x + (canvas_width - SceneCamera.view_width * fit) * 0.5
		offset_y = canvas_y + (canvas_height - SceneCamera.view_height * fit) * 0.5

		# The scene target is exactly the scene viewport, so scene coordinates
		# land in it unscaled.
		to_scene = |point| point
		scene_scale = 1

		frame.with_render_texture!(
			resources.scene_target,
			|scene_frame| {
				scene_frame.clear!(ray_color(SceneRenderer.background))
				draw_quads!(scene_frame, resources, scene.texture_quads, to_scene, scene_scale)?
				draw_lines!(scene_frame, scene.underlay_lines, to_scene, scene_scale)?
				draw_gradients!(scene_frame, scene.radial_gradients, to_scene, scene_scale)?
				draw_depth_items!(scene_frame, resources, scene.overlay_texture_quads, scene.lines, scene.circles, to_scene, scene_scale)?
				Ok({})
			},
		)?

		bloom_scale_x = SceneRenderer.bloom_size.width.to_f32() / SceneCamera.view_width
		bloom_scale_y = SceneRenderer.bloom_size.height.to_f32() / SceneCamera.view_height
		bloom_scale = min_f32(bloom_scale_x, bloom_scale_y)
		to_bloom = |point| {
			x: point.x * bloom_scale_x,
			y: point.y * bloom_scale_y,
		}
		bloom_dest = {
			x: 0,
			y: 0,
			width: SceneRenderer.bloom_size.width.to_f32(),
			height: SceneRenderer.bloom_size.height.to_f32(),
		}
		zero = { x: 0, y: 0 }

		frame.with_render_texture!(
			resources.bloom_a,
			|emission_frame| {
				emission_frame.clear!(transparent_color)
				emission_frame.with_shader!(
					resources.emissive_shader,
					|lit_frame| {
						lit_frame.with_blend_mode!(
							Draw.additive_blend,
							|blend_frame| {
								draw_gradients!(blend_frame, scene.radial_gradients, to_bloom, bloom_scale)?
								draw_lines!(blend_frame, scene.lines, to_bloom, bloom_scale)?
								draw_circles!(blend_frame, scene.circles, to_bloom, bloom_scale)?
								Ok({})
							},
						)?
						Ok({})
					},
				)?
				Ok({})
			},
		)?

		resources.blur_direction.set!({ x: 1, y: 0 })
		frame.with_render_texture!(
			resources.bloom_b,
			|blur_frame| {
				blur_frame.clear!(transparent_color)
				blur_frame.with_shader!(
					resources.blur_shader,
					|shader_frame| {
						shader_frame.texture!({
							texture: resources.bloom_a.texture(),
							source: resources.bloom_a.source(),
							dest: bloom_dest,
							origin: zero,
							rotation: 0,
							tint: white_color,
						})
						Ok({})
					},
				)?
				Ok({})
			},
		)?

		resources.blur_direction.set!({ x: 0, y: 1 })
		frame.with_render_texture!(
			resources.bloom_a,
			|blur_frame| {
				blur_frame.clear!(transparent_color)
				blur_frame.with_shader!(
					resources.blur_shader,
					|shader_frame| {
						shader_frame.texture!({
							texture: resources.bloom_b.texture(),
							source: resources.bloom_b.source(),
							dest: bloom_dest,
							origin: zero,
							rotation: 0,
							tint: white_color,
						})
						Ok({})
					},
				)?
				Ok({})
			},
		)?

		resources.composite_bloom.set!(resources.bloom_a.texture())
		frame.with_shader!(
			resources.composite_shader,
			|composite_frame| {
				composite_frame.texture!({
					texture: resources.scene_target.texture(),
					source: resources.scene_target.source(),
					dest: {
						x: offset_x,
						y: offset_y,
						width: SceneCamera.view_width * fit,
						height: SceneCamera.view_height * fit,
					},
					origin: zero,
					rotation: 0,
					tint: white_color,
				})
				Ok({})
			},
		)
	}
}

min_f32 : F32, F32 -> F32
min_f32 = |a, b| if a < b a else b

transparent_color : RayColor.Rgba
transparent_color = Draw.from_rgba({ r: 0, g: 0, b: 0, a: 0 })

white_color : RayColor.Rgba
white_color = Draw.from_rgba({ r: 255, g: 255, b: 255, a: 255 })

ray_color : Color -> RayColor.Rgba
ray_color = |color| Draw.from_rgba({ r: color.r, g: color.g, b: color.b, a: color.a })

## Push one scene snapshot into the retained shader uniforms.
write_scene_uniforms! : SceneRenderer.Resources, SceneRenderer.SceneParameters => {}
write_scene_uniforms! = |resources, parameters| {
	resources.floor_time.set!(parameters.seconds)
	resources.floor_target_uv.set!(parameters.target_uv)
	resources.floor_reachable.set!(parameters.reachable_value)
	resources.floor_error.set!(parameters.error_amount)
	resources.robot_time.set!(parameters.seconds)
	resources.robot_reachable.set!(parameters.reachable_value)
	resources.robot_error.set!(parameters.error_amount)
	resources.composite_time.set!(parameters.seconds)
	resources.blur_resolution.set!({ x: SceneRenderer.bloom_size.width.to_f32(), y: SceneRenderer.bloom_size.height.to_f32() })
	resources.composite_resolution.set!({ x: SceneCamera.view_width, y: SceneCamera.view_height })
}

## Depth-sorted overlay items, so the robot arm occludes the PGA scaffolding.
DepthItem := [
	DepthQuad(SceneRenderer.Quad),
	DepthLine(SceneRenderer.Line),
	DepthCircle(SceneRenderer.Circle),
]

depth_item_depth : DepthItem -> F32
depth_item_depth = |item| match item {
	DepthQuad(quad) => quad.depth
	DepthLine(value) => value.depth
	DepthCircle(value) => value.depth
}

depth_items : List(SceneRenderer.Quad), List(SceneRenderer.Line), List(SceneRenderer.Circle) -> List(DepthItem)
depth_items = |quads, lines, circles| {
	quads.map(|quad| DepthQuad(quad))
		.concat(lines.map(|value| DepthLine(value)))
		.concat(circles.map(|value| DepthCircle(value)))
		.sort_with(
			|a, b| {
				a_depth = depth_item_depth(a)
				b_depth = depth_item_depth(b)
				if a_depth < b_depth Before else if a_depth > b_depth After else Same
			},
		)
}

## Bind the material shader a quad asks for, or fall through to a plain blit.
with_material! : Draw.Frame, SceneRenderer.Resources, SceneRenderer.Material, (Draw.Frame => Try({}, Draw.ScopeError)) => Try({}, Draw.ScopeError)
with_material! = |frame, resources, material, draw_body| match material {
	FloorMaterial => frame.with_shader!(resources.floor_shader, draw_body)
	RobotMaterial => frame.with_shader!(resources.robot_shader, draw_body)
	_ => draw_body(frame)
}

quad_source : SceneRenderer.Material, Assets.Texture -> Draw.Rect
quad_source = |material, texture_value| match material {
	# Crop a coherent taped-cardboard island from the model's UV atlas.
	CrateMaterial => { x: 710, y: 300, width: 220, height: 145 }
	_ => { x: 0, y: 0, width: texture_value.width.to_f32(), height: texture_value.height.to_f32() }
}

draw_quad! : Draw.Frame, SceneRenderer.Quad, (Point2 -> Point2) => Try({}, Draw.ScopeError)
draw_quad! = |frame, quad, project| match Draw.ProjectiveQuad.from_corners({
	top_left: project(quad.top_left),
	bottom_left: project(quad.bottom_left),
	bottom_right: project(quad.bottom_right),
	top_right: project(quad.top_right),
}) {
	Ok(quad_value) => Ok(
		frame.projective_texture!({
			texture: quad.texture,
			source: quad_source(quad.material, quad.texture),
			quad: quad_value,
			tint: ray_color(quad.tint),
		}),
	)
	Err(_) => Ok({})
}

draw_quads! : Draw.Frame, SceneRenderer.Resources, List(SceneRenderer.Quad), (Point2 -> Point2), F32 => Try({}, Draw.ScopeError)
draw_quads! = |frame, resources, quads, project, _scale| {
	for quad in quads {
		with_material!(frame, resources, quad.material, |material_frame| draw_quad!(material_frame, quad, project))?
	}
	Ok({})
}

draw_lines! : Draw.Frame, List(SceneRenderer.Line), (Point2 -> Point2), F32 => Try({}, Draw.ScopeError)
draw_lines! = |frame, lines, project, scale| {
	for line in lines {
		frame.line!({
			start: project(line.start),
			end: project(line.end),
			stroke: Draw.stroke(ray_color(line.color), line.thickness * scale),
		})
	}
	Ok({})
}

draw_circles! : Draw.Frame, List(SceneRenderer.Circle), (Point2 -> Point2), F32 => Try({}, Draw.ScopeError)
draw_circles! = |frame, circles, project, scale| {
	for circle in circles {
		frame.circle!({
			center: project(circle.center),
			radius: circle.radius * scale,
			style: Draw.filled(ray_color(circle.color)),
		})
	}
	Ok({})
}

draw_gradients! : Draw.Frame, List(SceneRenderer.RadialGradient), (Point2 -> Point2), F32 => Try({}, Draw.ScopeError)
draw_gradients! = |frame, gradients, project, scale| {
	frame.with_blend_mode!(
		Draw.additive_blend,
		|blend_frame| {
			for gradient in gradients {
				blend_frame.circle_gradient!({
					center: project(gradient.center),
					radius: gradient.radius * scale,
					color_inner: ray_color(gradient.inner),
					color_outer: ray_color(gradient.outer),
				})
			}
			Ok({})
		},
	)
}

draw_depth_items! : Draw.Frame, SceneRenderer.Resources, List(SceneRenderer.Quad), List(SceneRenderer.Line), List(SceneRenderer.Circle), (Point2 -> Point2), F32 => Try({}, Draw.ScopeError)
draw_depth_items! = |frame, resources, quads, lines, circles, project, scale| {
	for item in depth_items(quads, lines, circles) {
		match item {
			DepthQuad(quad) => with_material!(frame, resources, quad.material, |material_frame| draw_quad!(material_frame, quad, project))?
			DepthLine(value) => frame.line!({
				start: project(value.start),
				end: project(value.end),
				stroke: Draw.stroke(ray_color(value.color), value.thickness * scale),
			})
			DepthCircle(value) => frame.circle!({
				center: project(value.center),
				radius: value.radius * scale,
				style: Draw.filled(ray_color(value.color)),
			})
		}
	}
	Ok({})
}

## The scene target is a fixed 900x620 surface, letterboxed into the canvas.
expect {
	resources_bloom_width = SceneRenderer.bloom_size.width.to_f32()
	scene_width = SceneRenderer.scene_size.width.to_f32()
	resources_bloom_width / scene_width == 0.5
}

## A blank scene is drawable; it carries no geometry at all.
expect {
	scene : SceneRenderer.Scene
	scene = {
		parameters: {
			seconds: 0,
			target_uv: { x: 0, y: 0 },
			reachable_value: 1,
			error_amount: 0,
		},
		texture_quads: [],
		underlay_lines: [],
		overlay_texture_quads: [],
		radial_gradients: [],
		lines: [],
		circles: [],
	}
	scene.lines.len() == 0 and scene.overlay_texture_quads.len() == 0
}
