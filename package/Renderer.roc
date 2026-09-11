## Settled post-solve rendering context and direct semantic host operations.
import Color
import Floating exposing [Clip.*, ZOrder.*]
import Identity exposing [NodeId]
import Layout
import LayoutTypes exposing [Bounds, LayoutNode, LayoutNodeKind.*, Placement.*, Size, VisibleRegion.*]
import Paint exposing [Op.*]
import Text
import rrt.Drawing
import rrt.Font
import rrt.Math
import rrt.Texture

RenderData(payload) : {
	nodes : List(LayoutNode(payload)),
	text_contents : List(Str),
	text_lines : List(Text.Line),
	child_indices : List(U64),
	node_ids : Dict(NodeId, U64),
	root_indices : List(U64),
}

background_style : LayoutTypes.BoxNodeData -> Paint.BackgroundStyle
background_style = |box| { background: box.background, radius: box.radius }

text_style : Text.Config -> Paint.TextStyle
text_style = |config| {
	font_size: config.font_size,
	spacing: config.spacing,
	color: config.color,
}

border_style : LayoutTypes.BoxNodeData -> Paint.BorderStyle
border_style = |box| { border: box.border, radius: box.radius }

Renderer := [].{
	Bounds : LayoutTypes.Bounds

	Clip : Floating.Clip

	Placement : Paint.Placement

	## Payload understood by Terrocotta's program renderer. Layout remains
	## polymorphic over this value; only the renderer interprets its cases.
	Payload : [Image(Texture)]

	## Draw a solved layout through the scoped recursive traversal.
	draw! : frame, Layout(Payload), Size => Try({}, [Exit(I64), ..])
		where [
			frame.rectangle! : frame, Drawing.Rectangle => {},
			frame.rounded_rectangle! : frame, Drawing.RoundedRectangle => {},
			frame.text! : frame, Drawing.Text => {},
			frame.texture! : frame, Drawing.TextureDraw => {},
			frame.with_scissor! : frame, Math.Rect, (frame => Try({}, [ScopeLimit])) => Try({}, [ScopeLimit]),
		]
	draw! = |frame, layout, screen| {
		paint_data = layout.compute_paint_data().map_err(|_| Exit(1))?
		data = layout.render_data()
		roots = Floating.roots_in_z_order(data.nodes, data.node_ids, data.root_indices, BackToFront).map_err(|_| Exit(1))?
		for root in roots {
			match root.clip {
				Unclipped => draw_node!(frame, data, root.index, screen, Unclipped, paint_data.paint_bounds, paint_data.needs_clip)?
				Clipped(bounds) => {
					frame.with_scissor!(
						bounds.flatten(),
						|scissor_frame| {
							draw_node!(scissor_frame, data, root.index, screen, Clipped(bounds), paint_data.paint_bounds, paint_data.needs_clip).map_err(|_| ScopeLimit)?
							Ok({})
						},
					).map_err(|_| Exit(1))?
				}
			}
		}
		Ok({})
	}

	## Draw a solved layout by interpreting its linear Paint operation stream.
	draw_paint! : frame, Layout(Payload), Size => Try({}, [Exit(I64), ..])
		where [
			frame.rectangle! : frame, Drawing.Rectangle => {},
			frame.rounded_rectangle! : frame, Drawing.RoundedRectangle => {},
			frame.text! : frame, Drawing.Text => {},
			frame.texture! : frame, Drawing.TextureDraw => {},
			frame.begin_scissor! : frame, Math.Rect => {},
			frame.end_scissor! : frame => {},
		]
	draw_paint! = |frame, layout, screen| {
		paint = Paint.iter(layout, screen).map_err(|_| Exit(1))?
		for operation in paint {
			match operation {
				BeginScissor(bounds) => frame.begin_scissor!(bounds.flatten())
				Background(placement, style) => Renderer.draw_background!(frame, placement, style)
				TextLine(placement, content, style, font) => Renderer.draw_text!(frame, placement, content, style, font)
				Custom(placement, payload) => Renderer.draw_payload!(frame, placement, payload)
				Border(placement, style) => Renderer.draw_border!(frame, placement, style)
				EndScissor => frame.end_scissor!()
			}
		}
		Ok({})
	}

	## Interpret one payload from the program's closed payload set.
	draw_payload! : frame, Placement, Payload => {}
		where [
			frame.texture! : frame, Drawing.TextureDraw => {},
		]
	draw_payload! = |frame, placement, payload| match payload {
		Image(texture) => {
			bounds = placement.bounds
			frame.texture!({
				texture,
				source: { x: 0, y: 0, width: texture.width, height: texture.height },
				dest: { x: bounds.position.x, y: bounds.position.y, width: bounds.size.w, height: bounds.size.h },
				origin: { x: 0, y: 0 },
				rotation: 0,
				tint: { r: 255, g: 255, b: 255, a: 255 },
			})
		}
	}

	## Draw one semantic background operation directly to the host frame.
	draw_background! : frame, Placement, Paint.BackgroundStyle => {}
		where [
			frame.rectangle! : frame, Drawing.Rectangle => {},
			frame.rounded_rectangle! : frame, Drawing.RoundedRectangle => {},
		]
	draw_background! = |frame, placement, style| {
		if style.background.a > 0 {
			bounds = placement.bounds
			if style.radius > 0 {
				frame.rounded_rectangle!({
					x: bounds.position.x,
					y: bounds.position.y,
					width: bounds.size.w,
					height: bounds.size.h,
					radius: style.radius,
					segments: 12,
					style: { fill: Fill(Color.to_rrt(style.background)), stroke: NoStroke },
				})
			} else {
				frame.rectangle!({
					x: bounds.position.x,
					y: bounds.position.y,
					width: bounds.size.w,
					height: bounds.size.h,
					style: { fill: Fill(Color.to_rrt(style.background)), stroke: NoStroke },
				})
			}
		}
	}

	## Draw text at its resolved placement.
	draw_text! : frame, Placement, Str, Paint.TextStyle, Font => {}
		where [
			frame.text! : frame, Drawing.Text => {},
		]
	draw_text! = |frame, placement, content, style, font| {
		draw_text : Drawing.Text
		draw_text = {
			pos: { x: placement.bounds.position.x, y: placement.bounds.position.y },
			text: content,
			size: style.font_size,
			spacing: style.spacing,
			color: Color.to_rrt(style.color),
			font,
		}
		frame.text!(draw_text)
	}

	## Draw the box border above its content.
	draw_border! : frame, Placement, Paint.BorderStyle => {}
		where [
			frame.rectangle! : frame, Drawing.Rectangle => {},
			frame.rounded_rectangle! : frame, Drawing.RoundedRectangle => {},
		]
	draw_border! = |frame, placement, style| {
		border_config = style.border
		border_total = border_config.left + border_config.right + border_config.top + border_config.bottom
		if border_config.color.a > 0 and border_total > 0 {
			bounds = placement.bounds
			uniform = border_config.left == border_config.right and border_config.left == border_config.top and border_config.left == border_config.bottom
			if style.radius > 0 and uniform and border_config.top > 0 {
				frame.rounded_rectangle!({
					x: bounds.position.x,
					y: bounds.position.y,
					width: bounds.size.w,
					height: bounds.size.h,
					radius: style.radius,
					segments: 12,
					style: { fill: NoFill, stroke: Stroke({ color: Color.to_rrt(border_config.color), thickness: border_config.top }) },
				})
			} else {
				if border_config.top > 0 {
					frame.rectangle!({ x: bounds.position.x, y: bounds.position.y, width: bounds.size.w, height: border_config.top, style: { fill: Fill(Color.to_rrt(border_config.color)), stroke: NoStroke } })
				}
				if border_config.bottom > 0 {
					frame.rectangle!({ x: bounds.position.x, y: bounds.position.y + bounds.size.h - border_config.bottom, width: bounds.size.w, height: border_config.bottom, style: { fill: Fill(Color.to_rrt(border_config.color)), stroke: NoStroke } })
				}
				if border_config.left > 0 {
					frame.rectangle!({ x: bounds.position.x, y: bounds.position.y, width: border_config.left, height: bounds.size.h, style: { fill: Fill(Color.to_rrt(border_config.color)), stroke: NoStroke } })
				}
				if border_config.right > 0 {
					frame.rectangle!({ x: bounds.position.x + bounds.size.w - border_config.right, y: bounds.position.y, width: border_config.right, height: bounds.size.h, style: { fill: Fill(Color.to_rrt(border_config.color)), stroke: NoStroke } })
				}
			}
		}
	}
}

## Paint one node and its descendants through scoped host scissors.
draw_node! : frame, RenderData(Renderer.Payload), U64, Size, Floating.Clip, List(Bounds), List(Bool) => Try({}, [Exit(I64), ..])
	where [
		frame.rectangle! : frame, Drawing.Rectangle => {},
		frame.rounded_rectangle! : frame, Drawing.RoundedRectangle => {},
		frame.text! : frame, Drawing.Text => {},
		frame.texture! : frame, Drawing.TextureDraw => {},
		frame.with_scissor! : frame, Math.Rect, (frame => Try({}, [ScopeLimit])) => Try({}, [ScopeLimit]),
	]
draw_node! = |frame, data, index, screen, clip, paint_bounds, needs_clip| {
	node = data.nodes.get(index).map_err(|_| Exit(1))?
	subtree_paint_bounds = paint_bounds.get(index).map_err(|_| Exit(1))?
	viewport = { position: { x: 0, y: 0 }, size: screen }
	if LayoutTypes.visible_region(subtree_paint_bounds, viewport, clip) == Culled {
		Ok({})
	} else {
		placement = { id: node.id, bounds: node_paint_bounds(node), clip }
		match node.kind {
			BoxNode(box) => {
				Renderer.draw_background!(frame, placement, background_style(box))
				child_clip = effective_child_clip(placement, box)
				should_clip = needs_clip.get(index).map_err(|_| Exit(1))?

				draw_inner! = |inner_frame| {
					for offset in 0..<node.child_count {
						child_index = data.child_indices.get(node.child_start + offset).map_err(|_| Exit(1))?
						draw_node!(inner_frame, data, child_index, screen, child_clip, paint_bounds, needs_clip)?
					}
					Renderer.draw_border!(inner_frame, placement, border_style(box))
					Ok({})
				}

				if should_clip {
					clip_bounds = match child_clip {
						Clipped(bounds) => bounds
						Unclipped => placement.bounds
					}
					frame.with_scissor!(
						clip_bounds.flatten(),
						|scissor_frame| {
							draw_inner!(scissor_frame).map_err(|_| ScopeLimit)?
							Ok({})
						},
					).map_err(|_| Exit(1))?
				} else {
					draw_inner!(frame)?
				}
			}
			TextNode(text_data) => {
				content = data.text_contents.get(text_data.content_index).map_err(|_| Exit(1))?
				style = text_style(text_data.config)
				for line_offset in 0..<text_data.lines_count {
					line = data.text_lines.get(text_data.lines_start + line_offset).map_err(|_| Exit(1))?
					line_bounds = Text.line_bounds(placement.bounds.flatten(), text_data.config.align, line, line_offset)
					line_placement = { ..placement, bounds: line_bounds }
					segment = Text.line_text(content, line)
					Renderer.draw_text!(frame, line_placement, segment, style, text_data.font)
				}
			}
			CustomNode(custom_data) => Renderer.draw_payload!(frame, placement, custom_data.payload)
		}
		Ok({})
	}
}

## Compute the clip children inherit from their parent box.
effective_child_clip : Renderer.Placement, LayoutTypes.BoxNodeData -> Floating.Clip
effective_child_clip = |placement, box| {
	if box.overflow.x != Visible or box.overflow.y != Visible {
		match placement.clip {
			Unclipped => Clipped(placement.bounds)
			Clipped(ancestor_bounds) => Clipped(ancestor_bounds.intersection(placement.bounds))
		}
	} else {
		placement.clip
	}
}

## Return the node's paint bounds, expanding for floating attachments.
node_paint_bounds : LayoutNode(payload) -> Bounds
node_paint_bounds = |node| {
	bounds = { position: node.position, size: node.size }
	match node.placement {
		Normal => bounds
		Floating(config) => bounds.expand(config.expand)
	}
}
