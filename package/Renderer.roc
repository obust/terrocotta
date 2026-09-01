## Settled post-solve rendering context and direct semantic host operations.
import Color
import Floating exposing [Clip.*, ZOrder.*]
import Identity exposing [NodeId]
import Layout
import LayoutTypes exposing [Bounds, LayoutNode, LayoutNodeKind.*, Placement.*, Size, VisibleRegion.*]
import Text
import rrt.Drawing
import rrt.Font
import rrt.Math

Renderer := [].{
	Bounds : LayoutTypes.Bounds

	Clip : Floating.Clip

	Placement : {
		id : NodeId,
		bounds : Bounds,
		clip : Clip,
	}

	Data : {
		nodes : List(LayoutNode),
		text_contents : List(Str),
		text_lines : List(Text.Line),
		child_indices : List(U64),
		node_ids : Dict(NodeId, U64),
		root_indices : List(U64),
	}

	## Draw a solved layout through RocRay's package-owned rendering effects.
	draw! : Drawing.Effects, Layout, Size => Try({}, [Exit(I64), ..])
	draw! = |effects, layout, screen| {
		paint_data = layout.compute_paint_data().map_err(|_| Exit(1))?
		paint_bounds = paint_data.paint_bounds
		needs_clip = paint_data.needs_clip
		data = layout.render_data()
		roots = Floating.roots_in_z_order(data.nodes, data.node_ids, data.root_indices, BackToFront).map_err(|_| Exit(1))?
		for root in roots {
			match root.clip {
				Unclipped => draw_node!(effects, data, root.index, screen, Unclipped, paint_bounds, needs_clip)?
				Clipped(bounds) => {
					effects.with_scissor!(
						bounds.flatten(),
						|scoped_effects| {
							draw_node!(scoped_effects, data, root.index, screen, Clipped(bounds), paint_bounds, needs_clip).map_err(|_| ScopeLimit)?
							Ok({})
						},
					).map_err(|_| Exit(1))?
				}
			}
		}
		Ok({})
	}

	## Draw one semantic background operation through the supplied effects.
	draw_background! : Drawing.Effects, Placement, LayoutTypes.BoxNodeData => {}
	draw_background! = |effects, placement, box| {
		if box.background.a > 0 {
			bounds = placement.bounds
			if box.radius > 0 {
				effects.rounded_rectangle!({
					x: bounds.position.x,
					y: bounds.position.y,
					width: bounds.size.w,
					height: bounds.size.h,
					radius: box.radius,
					segments: 12,
					style: { fill: Fill(Color.to_rrt(box.background)), stroke: NoStroke },
				})
			} else {
				effects.rectangle!({
					x: bounds.position.x,
					y: bounds.position.y,
					width: bounds.size.w,
					height: bounds.size.h,
					style: { fill: Fill(Color.to_rrt(box.background)), stroke: NoStroke },
				})
			}
		}
	}

	## Draw text at its resolved placement.
	draw_text! : Drawing.Effects, Placement, Str, Text.Config, Font => {}
	draw_text! = |effects, placement, content, config, font| {
		draw_text : Drawing.Text
		draw_text = {
			pos: { x: placement.bounds.position.x, y: placement.bounds.position.y },
			text: content,
			size: config.font_size,
			spacing: config.spacing,
			color: Color.to_rrt(config.color),
			font,
		}
		effects.text!(draw_text)
	}

	## Draw a texture at its resolved placement.
	draw_image! : Drawing.Effects, Placement, LayoutTypes.ImageNodeData => {}
	draw_image! = |effects, placement, image_config| {
		bounds = placement.bounds
		texture = image_config.texture
		effects.texture!({
			texture,
			source: { x: 0, y: 0, width: texture.width, height: texture.height },
			dest: { x: bounds.position.x, y: bounds.position.y, width: bounds.size.w, height: bounds.size.h },
			origin: { x: 0, y: 0 },
			rotation: 0,
			tint: Color.to_rrt(Color.white),
		})
	}

	## Draw the box border above its content.
	draw_border! : Drawing.Effects, Placement, LayoutTypes.BoxNodeData => {}
	draw_border! = |effects, placement, box| {
		border_config = box.border
		border_total = border_config.left + border_config.right + border_config.top + border_config.bottom
		if border_config.color.a > 0 and border_total > 0 {
			bounds = placement.bounds
			uniform = border_config.left == border_config.right and border_config.left == border_config.top and border_config.left == border_config.bottom
			if box.radius > 0 and uniform and border_config.top > 0 {
				effects.rounded_rectangle!({
					x: bounds.position.x,
					y: bounds.position.y,
					width: bounds.size.w,
					height: bounds.size.h,
					radius: box.radius,
					segments: 12,
					style: { fill: NoFill, stroke: Stroke({ color: Color.to_rrt(border_config.color), thickness: border_config.top }) },
				})
			} else {
				if border_config.top > 0 {
					effects.rectangle!({ x: bounds.position.x, y: bounds.position.y, width: bounds.size.w, height: border_config.top, style: { fill: Fill(Color.to_rrt(border_config.color)), stroke: NoStroke } })
				}
				if border_config.bottom > 0 {
					effects.rectangle!({ x: bounds.position.x, y: bounds.position.y + bounds.size.h - border_config.bottom, width: bounds.size.w, height: border_config.bottom, style: { fill: Fill(Color.to_rrt(border_config.color)), stroke: NoStroke } })
				}
				if border_config.left > 0 {
					effects.rectangle!({ x: bounds.position.x, y: bounds.position.y, width: border_config.left, height: bounds.size.h, style: { fill: Fill(Color.to_rrt(border_config.color)), stroke: NoStroke } })
				}
				if border_config.right > 0 {
					effects.rectangle!({ x: bounds.position.x + bounds.size.w - border_config.right, y: bounds.position.y, width: border_config.right, height: bounds.size.h, style: { fill: Fill(Color.to_rrt(border_config.color)), stroke: NoStroke } })
				}
			}
		}
	}
}

## Paint one node and its descendants through the scoped effects handle.
draw_node! : Drawing.Effects, Renderer.Data, U64, Size, Floating.Clip, List(Bounds), List(Bool) => Try({}, [Exit(I64), ..])
draw_node! = |effects, data, index, screen, clip, paint_bounds, needs_clip| {
	node = data.nodes.get(index).map_err(|_| Exit(1))?
	subtree_paint_bounds = paint_bounds.get(index).map_err(|_| Exit(1))?
	viewport = { position: { x: 0, y: 0 }, size: screen }
	if LayoutTypes.visible_region(subtree_paint_bounds, viewport, clip) == Culled {
		Ok({})
	} else {
		placement = { id: node.id, bounds: node_paint_bounds(node), clip }
		match node.kind {
			BoxNode(box) => {
				# Paint the box fill behind all descendant content.
				Renderer.draw_background!(effects, placement, box)

				# Descendants inherit the ancestor clip plus this box's overflow clip.
				child_clip = effective_child_clip(placement, box)
				should_clip = needs_clip.get(index).map_err(|_| Exit(1))?

				draw_inner! = |inner_effects| {
					# Paint children in declaration order
					parent = data.nodes.get(index).map_err(|_| Exit(1))?
					for offset in 0..<parent.child_count {
						child_index = data.child_indices.get(parent.child_start + offset).map_err(|_| Exit(1))?
						draw_node!(inner_effects, data, child_index, screen, child_clip, paint_bounds, needs_clip)?
					}
					# Paint parent border above children (inside host scissor when clipping).
					Renderer.draw_border!(inner_effects, placement, box)
					Ok({})
				}

				# Establish a host scissor only when descendants would escape this box.
				# `needs_clip` is precomputed in `Layout.compute_paint_data` together
				# with `paint_bounds` so the renderer does O(1) work here.
				if should_clip {
					clip_bounds = match child_clip {
						Clipped(bounds) => bounds
						Unclipped => placement.bounds
					}
					effects.with_scissor!(
						clip_bounds.flatten(),
						|scoped_effects| {
							draw_inner!(scoped_effects).map_err(|_| ScopeLimit)?
							Ok({})
						},
					).map_err(|_| Exit(1))?
				} else {
					draw_inner!(effects)?
				}
			}
			TextNode(text_data) => {
				# Resolve content
				content = data.text_contents.get(text_data.content_index).map_err(|_| Exit(1))?

				# Place and draw each content slice (aka line)
				for line_offset in 0..<text_data.lines_count {
					line = data.text_lines.get(text_data.lines_start + line_offset).map_err(|_| Exit(1))?
					line_bounds = Text.line_bounds(placement.bounds.flatten(), text_data.config, line, line_offset)
					line_placement = { ..placement, bounds: line_bounds }
					segment = Text.line_text(content, line)
					Renderer.draw_text!(effects, line_placement, segment, text_data.config, text_data.font)
				}
			}
			ImageNode(image) => Renderer.draw_image!(effects, placement, image)
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
node_paint_bounds : LayoutNode -> Bounds
node_paint_bounds = |node| {
	bounds = { position: node.position, size: node.size }
	match node.placement {
		Normal => bounds
		Floating(config) => bounds.expand(config.expand)
	}
}
