## Terracotta render-command adapter and shader pipeline for Screwbot.
import rr.Assets
import rr.Draw

import tc.Color
import tc.Element
import tc.Render

import SceneCamera

SceneRenderer :: [].{
	Resources : {
		crate : Assets.Texture,
		floor : Assets.Texture,
		wall : Assets.Texture,
		white : Assets.Texture,
		font : Draw.Font,
		scene_target : Draw.RenderTexture,
		bloom_a : Draw.RenderTexture,
		bloom_b : Draw.RenderTexture,
		floor_shader : Draw.Shader,
		robot_shader : Draw.Shader,
		emissive_shader : Draw.Shader,
		blur_shader : Draw.Shader,
		composite_shader : Draw.Shader,
		blur_direction : Draw.Vec2Uniform,
		composite_bloom : Draw.TextureUniform,
	}

	background : Color
	background = 0x080d19.Color

	bloom_size : { width : I32, height : I32 }
	bloom_size = { width: 450, height: 310 }

	crate_texture : Assets.Texture -> Element.Texture
	crate_texture = |texture| adapt_texture(crate_texture_key, texture)

	floor_texture : Assets.Texture -> Element.Texture
	floor_texture = |texture| adapt_texture(floor_texture_key, texture)

	wall_texture : Assets.Texture -> Element.Texture
	wall_texture = |texture| adapt_texture(wall_texture_key, texture)

	white_texture : Assets.Texture -> Element.Texture
	white_texture = |texture| adapt_texture(white_texture_key, texture)

	robot_texture : Assets.Texture -> Element.Texture
	robot_texture = |texture| adapt_texture(robot_texture_key, texture)

	font : Draw.Font -> Element.Font
	font = |font_value| adapt_font(font_value)

	frame_adapter : Resources -> Render.FrameAdapter(Draw.Frame)
	frame_adapter = |resources| Render.frame_adapter({
		measure_text!: |config| match config.font {
			DefaultFont => Draw.measure_text!({ text: config.text, size: config.size, spacing: config.spacing, font: Draw.default_font })
			CustomFont(_) => Draw.measure_text!({ text: config.text, size: config.size, spacing: config.spacing, font: resources.font })
		},
		render!: |frame, commands| render_commands!(frame, resources, commands),
	})
}

CanvasDepthItem : [
	DepthCircle(Element.CanvasCircle),
	DepthLine(Element.CanvasLine),
	DepthTextureQuad(Element.CanvasTextureQuad),
]

crate_texture_key : U64
crate_texture_key = 1

floor_texture_key : U64
floor_texture_key = 2

wall_texture_key : U64
wall_texture_key = 3

white_texture_key : U64
white_texture_key = 4

robot_texture_key : U64
robot_texture_key = 5

adapt_texture : U64, Assets.Texture -> Element.Texture
adapt_texture = |key, texture_value| Element.keyed_texture({
	key,
	width: texture_value.width(),
	height: texture_value.height(),
	draw!: |_command| {},
})

adapt_font : Draw.Font -> Element.Font
adapt_font = |font_value| Element.custom_font({
	key: 1,
	measure!: |config| Draw.measure_text!({
		text: config.text,
		size: config.size,
		spacing: config.spacing,
		font: font_value,
	}),
	draw!: |_config| {},
})

ray_color : Color -> _
ray_color = |color| Draw.from_rgba({ r: color.r, g: color.g, b: color.b, a: color.a })

canvas_depth : CanvasDepthItem -> F32
canvas_depth = |item| match item {
	DepthCircle(value) => value.depth
	DepthLine(value) => value.depth
	DepthTextureQuad(value) => value.depth
}

canvas_depth_items : List(Element.CanvasTextureQuad), List(Element.CanvasLine), List(Element.CanvasCircle) -> List(CanvasDepthItem)
canvas_depth_items = |quads, lines, circles| {
	quads.map(|quad| DepthTextureQuad(quad))
		.concat(lines.map(|value| DepthLine(value)))
		.concat(circles.map(|value| DepthCircle(value)))
		.sort_with(
			|a, b| {
				a_depth = canvas_depth(a)
				b_depth = canvas_depth(b)
				if a_depth < b_depth LT else if a_depth > b_depth GT else EQ
			},
		)
}

draw_rect! : Draw.Frame, F32, F32, F32, F32, Color => {}
draw_rect! = |frame, x, y, width, height, color| frame.rectangle!({ x, y, width, height, style: ray_color(color).filled() })

resource_texture : SceneRenderer.Resources, Element.Texture -> Assets.Texture
resource_texture = |resources, texture_value| {
	key = Element.texture_key(texture_value)
	if key == crate_texture_key {
		resources.crate
	} else if key == floor_texture_key {
		resources.floor
	} else if key == wall_texture_key {
		resources.wall
	} else {
		resources.white
	}
}

draw_projective_texture! : Draw.Frame, Element.Texture, SceneRenderer.Resources, Draw.ProjectiveQuadCorners, Color => {}
draw_projective_texture! = |frame, texture_value, resources, corners, tint| match Draw.ProjectiveQuad.from_corners(corners) {
	Ok(quad) => {
		texture_asset = resource_texture(resources, texture_value)
		source = if Element.texture_key(texture_value) == crate_texture_key {
			# Crop a coherent taped-cardboard island from the model's UV atlas.
			{ x: 710, y: 300, width: 220, height: 145 }
		} else {
			texture_asset.rect()
		}
		frame.projective_texture!({
			texture: texture_asset,
			source,
			quad,
			tint: ray_color(tint),
		})
	}
	Err(_) => {}
}

draw_render_command! : Draw.Frame, SceneRenderer.Resources, Render.Command => {}
draw_render_command! = |frame, resources, command| match command {
	Rectangle(rect) => draw_rect!(frame, rect.x, rect.y, rect.width, rect.height, rect.color)
	RoundedRectangle(rect) => frame.rounded_rectangle!({
		x: rect.x,
		y: rect.y,
		width: rect.width,
		height: rect.height,
		radius: rect.radius,
		segments: 12,
		style: ray_color(rect.color).filled(),
	})
	Shadow(item) => {
		# Four translucent shells approximate a soft shadow without a blur pass.
		shells : List(F32)
		shells = [4, 3, 2, 1]
		for shell in shells {
			t = shell / 4
			expand = item.spread + item.blur * t
			frame.rounded_rectangle!({
				x: item.x + item.offset_x - expand,
				y: item.y + item.offset_y - expand,
				width: item.width + expand * 2,
				height: item.height + expand * 2,
				radius: item.radius + expand,
				segments: 12,
				style: ray_color(item.color.with_alpha(item.color.a // 4)).filled(),
			})
		}
	}
	Border(border) => {
		uniform = border.left == border.right and border.left == border.top and border.left == border.bottom
		if border.radius > 0 and uniform and border.top > 0 {
			frame.rounded_rectangle!({
				x: border.x,
				y: border.y,
				width: border.width,
				height: border.height,
				radius: border.radius,
				segments: 12,
				style: ray_color(border.color).outlined(border.top),
			})
		} else {
			if border.top > 0 {
				draw_rect!(frame, border.x, border.y, border.width, border.top, border.color)
			}
			if border.bottom > 0 {
				draw_rect!(frame, border.x, border.y + border.height - border.bottom, border.width, border.bottom, border.color)
			}
			if border.left > 0 {
				draw_rect!(frame, border.x, border.y, border.left, border.height, border.color)
			}
			if border.right > 0 {
				draw_rect!(frame, border.x + border.width - border.right, border.y, border.right, border.height, border.color)
			}
		}
	}
	Text(item) => match item.font {
		DefaultFont => frame.text!({
			pos: { x: item.x, y: item.y },
			text: item.text,
			size: item.font_size,
			spacing: item.spacing,
			color: ray_color(item.color),
			font: Draw.default_font,
			align: Draw.align_top_left,
		})
		CustomFont(_) => frame.text!({
			pos: { x: item.x, y: item.y },
			text: item.text,
			size: item.font_size,
			spacing: item.spacing,
			color: ray_color(item.color),
			font: resources.font,
			align: Draw.align_top_left,
		})
	}
	Image(image) => {
		texture_asset = resource_texture(resources, image.texture)
		frame.texture!({
			texture: texture_asset.view(),
			source: Element.texture_rect(image.texture),
			dest: { x: image.x, y: image.y, width: image.width, height: image.height },
			origin: { x: 0, y: 0 },
			rotation: 0,
			tint: ray_color(image.tint),
		})
	}
	Canvas(canvas_config) => {
		scale_x = if canvas_config.view_width > 0 canvas_config.width / canvas_config.view_width else 1
		scale_y = if canvas_config.view_height > 0 canvas_config.height / canvas_config.view_height else 1
		scale = scale_x.min(scale_y)
		offset_x = canvas_config.x + (canvas_config.width - canvas_config.view_width * scale) * 0.5
		offset_y = canvas_config.y + (canvas_config.height - canvas_config.view_height * scale) * 0.5
		target_scale_x = SceneCamera.view_width / canvas_config.view_width
		target_scale_y = SceneCamera.view_height / canvas_config.view_height
		target_scale = target_scale_x.min(target_scale_y)
		to_target = |point| { x: point.x * target_scale_x, y: point.y * target_scale_y }

		frame.with_render_texture!(
			resources.scene_target,
			|scene_frame| {
				scene_frame.clear!(ray_color(SceneRenderer.background))

				for quad in canvas_config.texture_quads {
					corners = {
						top_left: to_target(quad.top_left),
						bottom_left: to_target(quad.bottom_left),
						bottom_right: to_target(quad.bottom_right),
						top_right: to_target(quad.top_right),
					}
					if Element.texture_key(quad.texture) == floor_texture_key {
						scene_frame.with_shader!(
							resources.floor_shader,
							|material_frame| {
								draw_projective_texture!(material_frame, quad.texture, resources, corners, quad.tint)
								Ok({})
							},
						) ?? {}
					} else {
						draw_projective_texture!(scene_frame, quad.texture, resources, corners, quad.tint)
					}
				}
				for line in canvas_config.underlay_lines {
					scene_frame.line!({
						start: to_target(line.start),
						end: to_target(line.end),
						stroke: ray_color(line.color).stroke(line.thickness * target_scale),
					})
				}
				scene_frame.with_blend_mode!(
					Draw.additive_blend,
					|blend_frame| {
						for gradient in canvas_config.radial_gradients {
							blend_frame.circle_gradient!({
								center: to_target(gradient.center),
								radius: gradient.radius * target_scale,
								color_inner: ray_color(gradient.inner),
								color_outer: ray_color(gradient.outer),
							})
						}
						Ok({})
					},
				) ?? {}
				for item in canvas_depth_items(canvas_config.overlay_texture_quads, canvas_config.lines, canvas_config.circles) {
					match item {
						DepthTextureQuad(quad) => {
							corners = {
								top_left: to_target(quad.top_left),
								bottom_left: to_target(quad.bottom_left),
								bottom_right: to_target(quad.bottom_right),
								top_right: to_target(quad.top_right),
							}
							if Element.texture_key(quad.texture) == robot_texture_key {
								scene_frame.with_shader!(
									resources.robot_shader,
									|material_frame| {
										draw_projective_texture!(material_frame, quad.texture, resources, corners, quad.tint)
										Ok({})
									},
								) ?? {}
							} else {
								draw_projective_texture!(scene_frame, quad.texture, resources, corners, quad.tint)
							}
						}
						DepthLine(value) => scene_frame.line!({
							start: to_target(value.start),
							end: to_target(value.end),
							stroke: ray_color(value.color).stroke(value.thickness * target_scale),
						})
						DepthCircle(value) => scene_frame.circle!({
							center: to_target(value.center),
							radius: value.radius * target_scale,
							style: ray_color(value.color).filled(),
						})
					}
				}
				Ok({})
			},
		) ?? {}

		bloom_scale_x = SceneRenderer.bloom_size.width.to_f32() / canvas_config.view_width
		bloom_scale_y = SceneRenderer.bloom_size.height.to_f32() / canvas_config.view_height
		bloom_scale = bloom_scale_x.min(bloom_scale_y)
		to_bloom = |point| { x: point.x * bloom_scale_x, y: point.y * bloom_scale_y }
		transparent = Draw.from_rgba({ r: 0, g: 0, b: 0, a: 0 })
		white_draw = Draw.from_rgba({ r: 255, g: 255, b: 255, a: 255 })

		frame.with_render_texture!(
			resources.bloom_a,
			|emission_frame| {
				emission_frame.clear!(transparent)
				emission_frame.with_shader!(
					resources.emissive_shader,
					|lit_frame| {
						lit_frame.with_blend_mode!(
							Draw.additive_blend,
							|blend_frame| {
								for gradient in canvas_config.radial_gradients {
									blend_frame.circle_gradient!({
										center: to_bloom(gradient.center),
										radius: gradient.radius * bloom_scale,
										color_inner: ray_color(gradient.inner),
										color_outer: ray_color(gradient.outer),
									})
								}
								for line in canvas_config.lines {
									blend_frame.line!({
										start: to_bloom(line.start),
										end: to_bloom(line.end),
										stroke: ray_color(line.color).stroke(line.thickness * bloom_scale),
									})
								}
								for circle in canvas_config.circles {
									blend_frame.circle!({
										center: to_bloom(circle.center),
										radius: circle.radius * bloom_scale,
										style: ray_color(circle.color).filled(),
									})
								}
								Ok({})
							},
						)?
						Ok({})
					},
				)?
				Ok({})
			},
		) ?? {}

		bloom_dest = { x: 0, y: 0, width: SceneRenderer.bloom_size.width.to_f32(), height: SceneRenderer.bloom_size.height.to_f32() }
		zero = { x: 0, y: 0 }
		resources.blur_direction.set!({ x: 1, y: 0 })
		frame.with_render_texture!(
			resources.bloom_b,
			|blur_frame| {
				blur_frame.clear!(transparent)
				blur_frame.with_shader!(
					resources.blur_shader,
					|shader_frame| {
						shader_frame.texture!({
							texture: resources.bloom_a.texture(),
							source: resources.bloom_a.source(),
							dest: bloom_dest,
							origin: zero,
							rotation: 0,
							tint: white_draw,
						})
						Ok({})
					},
				)?
				Ok({})
			},
		) ?? {}

		resources.blur_direction.set!({ x: 0, y: 1 })
		frame.with_render_texture!(
			resources.bloom_a,
			|blur_frame| {
				blur_frame.clear!(transparent)
				blur_frame.with_shader!(
					resources.blur_shader,
					|shader_frame| {
						shader_frame.texture!({
							texture: resources.bloom_b.texture(),
							source: resources.bloom_b.source(),
							dest: bloom_dest,
							origin: zero,
							rotation: 0,
							tint: white_draw,
						})
						Ok({})
					},
				)?
				Ok({})
			},
		) ?? {}

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
						width: canvas_config.view_width * scale,
						height: canvas_config.view_height * scale,
					},
					origin: zero,
					rotation: 0,
					tint: white_draw,
				})
				Ok({})
			},
		) ?? {}
	}
	ScissorStart(_) => {}
	ScissorEnd => {}
}

find_scissor_end : List(Render.Command), U64, U64, U64 -> U64
find_scissor_end = |commands, index, depth, end| if index >= end {
	end
} else {
	match commands.get(index) {
		Err(_) => end
		Ok(ScissorStart(_)) => find_scissor_end(commands, index + 1, depth + 1, end)
		Ok(ScissorEnd) => if depth == 1 index else find_scissor_end(commands, index + 1, depth - 1, end)
		Ok(_) => find_scissor_end(commands, index + 1, depth, end)
	}
}

draw_render_range! : Draw.Frame, SceneRenderer.Resources, List(Render.Command), U64, U64, Render.Rect, Bool => {}
draw_render_range! = |frame, resources, commands, index, end, parent_clip, has_parent_clip| if index < end {
	match commands.get(index) {
		Err(_) => {}
		Ok(ScissorStart(bounds)) => {
			closing = find_scissor_end(commands, index + 1, 1, end)
			clip = if has_parent_clip Render.intersect(parent_clip, bounds) else bounds
			# Keep the nested range semantics while avoiding the current Roc hosted-
			# extern specialization panic triggered by `Frame.with_scissor!` here.
			draw_render_range!(frame, resources, commands, index + 1, closing, clip, True)
			draw_render_range!(frame, resources, commands, closing + 1, end, parent_clip, has_parent_clip)
		}
		Ok(ScissorEnd) => {}
		Ok(command) => {
			draw_render_command!(frame, resources, command)
			draw_render_range!(frame, resources, commands, index + 1, end, parent_clip, has_parent_clip)
		}
	}
}

render_commands! : Draw.Frame, SceneRenderer.Resources, List(Render.Command) => {}
render_commands! = |frame, resources, commands| {
	frame.clear!(Draw.from_rgba({ r: 255, g: 255, b: 255, a: 255 }))
	draw_render_range!(frame, resources, commands, 0, commands.len(), { x: 0, y: 0, width: 0, height: 0 }, False)
}
