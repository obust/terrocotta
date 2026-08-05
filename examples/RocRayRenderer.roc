## Basic Terracotta renderer for current roc-ray frame capabilities.
## Resource-heavy applications can supply their own adapter, as Screwbot does.
import rr.Draw

import tc.Color
import tc.Element
import tc.Render

RayFont : [NoRayFont, LoadedRayFont(Draw.Font)]

RocRayRenderer := [].{
	default : Render.FrameAdapter(Draw.Frame)
	default = frame_adapter_for(NoRayFont)

	with_font : Draw.Font -> Render.FrameAdapter(Draw.Frame)
	with_font = |font| frame_adapter_for(LoadedRayFont(font))

	font : Draw.Font -> Element.Font
	font = |font| Element.custom_font({
		key: 1,
		measure!: |config| Draw.measure_text!({ text: config.text, size: config.size, spacing: config.spacing, font }),
		draw!: |_config| {},
	})
}

frame_adapter_for : RayFont -> Render.FrameAdapter(Draw.Frame)
frame_adapter_for = |ray_font| Render.frame_adapter({
	measure_text!: |config| match config.font {
		DefaultFont => Draw.measure_text!({ text: config.text, size: config.size, spacing: config.spacing, font: Draw.default_font })
		CustomFont(resource) => match ray_font {
			NoRayFont => Element.measure_font!(resource, { text: config.text, size: config.size, spacing: config.spacing })
			LoadedRayFont(font) => Draw.measure_text!({ text: config.text, size: config.size, spacing: config.spacing, font })
		}
	},
	render!: |frame, commands| {
		frame.clear!(Draw.from_rgba({ r: 255, g: 255, b: 255, a: 255 }))
		render_range!(frame, ray_font, commands, 0, commands.len())
		frame.fps!({ pos: { x: 0, y: 0 }, size: 16, color: ray_color(Color.gray) })
	},
})

ray_color : Color -> _
ray_color = |color| Draw.from_rgba({ r: color.r, g: color.g, b: color.b, a: color.a })

draw_rect! : Draw.Frame, F32, F32, F32, F32, Color => {}
draw_rect! = |frame, x, y, width, height, color| frame.rectangle!({ x, y, width, height, style: ray_color(color).filled() })

draw_command! : Draw.Frame, RayFont, Render.Command => {}
draw_command! = |frame, ray_font, command| match command {
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
	Shadow(shadow) => {
		shells : List(F32)
		shells = [4, 3, 2, 1]
		for shell in shells {
			t = shell / 4
			expand = shadow.spread + shadow.blur * t
			frame.rounded_rectangle!({
				x: shadow.x + shadow.offset_x - expand,
				y: shadow.y + shadow.offset_y - expand,
				width: shadow.width + expand * 2,
				height: shadow.height + expand * 2,
				radius: shadow.radius + expand,
				segments: 12,
				style: ray_color(shadow.color.with_alpha(shadow.color.a // 4)).filled(),
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
			if border.top > 0 draw_rect!(frame, border.x, border.y, border.width, border.top, border.color)
			if border.bottom > 0 draw_rect!(frame, border.x, border.y + border.height - border.bottom, border.width, border.bottom, border.color)
			if border.left > 0 draw_rect!(frame, border.x, border.y, border.left, border.height, border.color)
			if border.right > 0 draw_rect!(frame, border.x + border.width - border.right, border.y, border.right, border.height, border.color)
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
		CustomFont(resource) => match ray_font {
			NoRayFont => Element.draw_font!(
				resource,
				{
					pos: { x: item.x, y: item.y },
					text: item.text,
					size: item.font_size,
					spacing: item.spacing,
					color: item.color,
				},
			)
			LoadedRayFont(font) => frame.text!({
				pos: { x: item.x, y: item.y },
				text: item.text,
				size: item.font_size,
				spacing: item.spacing,
				color: ray_color(item.color),
				font,
				align: Draw.align_top_left,
			})
		}
	}
	# Typed textures and canvases need application-owned resource lookup. Apps
	# using them should provide a resource-aware adapter.
	Image(_) => {}
	Canvas(_) => {}
	ScissorStart(_) | ScissorEnd => {}
}

find_scissor_end : List(Render.Command), U64, U64 -> U64
find_scissor_end = |commands, index, depth| {
	if index >= commands.len() {
		commands.len()
	} else {
		match commands.get(index) {
			Err(_) => commands.len()
			Ok(command) => match command {
				ScissorStart(_) => find_scissor_end(commands, index + 1, depth + 1)
				ScissorEnd => if depth == 0 index else find_scissor_end(commands, index + 1, depth - 1)
				_ => find_scissor_end(commands, index + 1, depth)
			}
		}
	}
}

render_range! : Draw.Frame, RayFont, List(Render.Command), U64, U64 => {}
render_range! = |frame, ray_font, commands, index, end| {
	if index < end {
		match commands.get(index) {
			Err(_) => {}
			Ok(command) => match command {
				ScissorStart(bounds) => {
					_ = bounds
					close = find_scissor_end(commands, index + 1, 0)
					# Current Roc mis-specializes roc-ray's hosted scissor call when a
					# Draw.Frame crosses this adapter boundary. Preserve nested command
					# traversal until that compiler limitation is removed.
					render_range!(frame, ray_font, commands, index + 1, close)
					render_range!(frame, ray_font, commands, close + 1, end)
				}
				ScissorEnd => {}
				_ => {
					draw_command!(frame, ray_font, command)
					render_range!(frame, ray_font, commands, index + 1, end)
				}
			}
		}
	}
}
