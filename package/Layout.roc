## Flat layout tree - flex-box layout solver for Roc-Clay.
## Uses a flat Vec-of-structs layout tree built via push/pop message API.
## Intrinsic sizes are computed during construction; final size, position, and
## render passes are methods on Layout.
import Assets
import Color
import Element exposing [Font, default_font]
import Render

# --- Internal Geometry Types (Private) ---

Size := { w : F32, h : F32 }.{

	plus : Size, Size -> Size
	plus = |a, b| { w: a.w + b.w, h: a.h + b.h }

	minus : Size, Size -> Size
	minus = |a, b| { w: a.w - b.w, h: a.h - b.h }

	along : Size, Element.Direction -> F32
	along = |s, direction| match direction {
		Row => s.w
		Col => s.h
	}

	across : Size, Element.Direction -> F32
	across = |s, direction| match direction {
		Row => s.h
		Col => s.w
	}
}

Pos := { x : F32, y : F32 }.{
	plus : Pos, Pos -> Pos
	plus = |a, b| { x: a.x + b.x, y: a.y + b.y }
}

Axis : [XAxis, YAxis]

# --- Flat Layout Node Types (Private) ---

LayoutNodeKind : [BoxNode, TextNode, ImageNode]

LayoutPayload : [
	BoxPayload(Element.BoxConfig),
	TextPayload({ content : Str, config : Element.TextConfig }),
	ImagePayload(Element.ImageConfig),
]

ParentIndex : [NoParent, Parent(U64)]

LayoutNode : {
	kind : LayoutNodeKind,
	payload_index : U64,
	parent : ParentIndex,
	child_start : U64,
	child_count : U64,
	intrinsic : Size,
	size : Size,
	position : Pos,
	sizing_w : Element.Sizing,
	sizing_h : Element.Sizing,
}

# --- Generic Layout Helpers (Private) ---

is_grow_sizing : Element.Sizing -> Bool
is_grow_sizing = |s| match s {
	Grow(_) => Bool.True
	_ => Bool.False
}

apply_bounds : F32, { min : F32, max : F32 } -> F32
apply_bounds = |value, bounds| {
	if value < bounds.min bounds.min else if value > bounds.max bounds.max else value
}

text_align_offset : Element.TextAlign, F32, F32 -> F32
text_align_offset = |align, box_width, text_width| match align {
	Left => 0
	Center => (box_width - text_width) * 0.5
	Right => box_width - text_width
}

resolve_main_size : Element.Sizing, F32, F32 -> F32
resolve_main_size = |sizing, intrinsic, parent_avail| match sizing {
	Fixed(w) => w
	Fit(b) => apply_bounds(intrinsic, b)
	Grow(b) => apply_bounds(parent_avail, b)
	Percent(p) => parent_avail * p
}

resolve_child_axis : Element.Sizing, F32, F32, F32 -> F32
resolve_child_axis = |sizing, content_size, parent_avail, grow_fill| match sizing {
	Fixed(w) => w
	Fit(b) => apply_bounds(content_size, b)
	Grow(b) => apply_bounds(grow_fill, b)
	Percent(p) => parent_avail * p
}

cross_offset : F32, F32, Element.ChildAlign -> F32
cross_offset = |child_size, parent_size, alignment| match alignment {
	Start => 0
	Center => (parent_size - child_size) * 0.5
	End => parent_size - child_size
}

axis_offset : F32, Element.ChildAlign -> F32
axis_offset = |extra, alignment| {
	safe_extra = if extra > 0 extra else 0
	match alignment {
		Start => 0
		Center => safe_extra * 0.5
		End => safe_extra
	}
}

resolve_font : Font, Font -> Font
resolve_font = |cfg_font, default_font|
	if (Box.unbox(cfg_font)) == 0.U64 default_font else cfg_font

set_size_along : LayoutNode, Axis, F32 -> LayoutNode
set_size_along = |node, axis, value| match axis {
	XAxis => { ..node, size: { ..node.size, w: value } }
	YAxis => { ..node, size: { ..node.size, h: value } }
}

sum_children_intrinsic : List(LayoutNode), List(U64), U64, U64, Element.Direction -> Try(F32, Layout.LayoutError)
sum_children_intrinsic = |nodes, child_indices, start, count, dir| {
	var $sum = 0
	for offset in 0..<count {
		child_idx = child_indices.get(start + offset)?
		child = nodes.get(child_idx)?
		$sum = $sum + child.intrinsic.along(dir)
	}
	Ok($sum)
}

max_children_intrinsic : List(LayoutNode), List(U64), U64, U64, Element.Direction -> Try(F32, Layout.LayoutError)
max_children_intrinsic = |nodes, child_indices, start, count, dir| {
	var $max = 0
	for offset in 0..<count {
		child_idx = child_indices.get(start + offset)?
		child = nodes.get(child_idx)?
		val = child.intrinsic.across(dir)
		if val > $max { $max = val }
	}
	Ok($max)
}

sum_children_size : List(LayoutNode), List(U64), U64, U64, Element.Direction -> Try(F32, Layout.LayoutError)
sum_children_size = |nodes, child_indices, start, count, dir| {
	var $sum = 0
	for offset in 0..<count {
		child_idx = child_indices.get(start + offset)?
		child = nodes.get(child_idx)?
		$sum = $sum + child.size.along(dir)
	}
	Ok($sum)
}

is_offscreen : Pos, Size, Size -> Bool
is_offscreen = |offset, size, screen| {
	offset.x > screen.w or offset.y > screen.h or offset.x + size.w < 0 or offset.y + size.h < 0
}

sum_gap : F32, U64 -> F32
sum_gap = |gap, count|
	if count <= 1.U64 {
		0.0
	} else {
		gap * (count - 1.U64).to_f32()
	}

## TODO: replace with List.clear() once the builtin exists. Runtime listSublist
## keeps the allocation for unique/in-place zero-length sublists by setting
## length to 0, so this preserves capacity in the expected Layout reuse path.
## If the list is shared, sublist decrefs it and returns [], losing capacity.
list_clear : List(a) -> List(a)
list_clear = |list| list.sublist({ start: 0, len: 0 })

# --- Public API ---

Layout(draw) :: {
	nodes : List(LayoutNode),
	payloads : List(LayoutPayload),
	child_indices : List(U64),
	pending_children : List(U64),
	root_index : U64,
	stack : List(U64),
}.{
	LayoutError : [InternalError, OutOfBounds]
	MeasureTextRaw : Render.MeasureTextRaw
	TextSize : Render.TextSize

	## Create empty Layout.
	new : () -> Layout(draw)
	new = || { nodes: [], payloads: [], child_indices: [], pending_children: [], root_index: 0, stack: [] }

	## Create empty Layout with capacity reserved for internal builder lists.
	with_capacity : U64 -> Layout(draw)
	with_capacity = |capacity| {
		nodes: List.with_capacity(capacity),
		payloads: List.with_capacity(capacity),
		child_indices: List.with_capacity(capacity // 2),
		pending_children: List.with_capacity(capacity // 2),
		root_index: 0,
		stack: List.with_capacity(capacity // 2),
	}

	## Reset all frame-local layout state before building the next view.
	clear : Layout(draw) -> Layout(draw)
	clear = |layout| {
		..layout,
		nodes: list_clear(layout.nodes),
		payloads: list_clear(layout.payloads),
		child_indices: list_clear(layout.child_indices),
		pending_children: list_clear(layout.pending_children),
		root_index: 0,
		stack: list_clear(layout.stack),
	}

	## Push/pop UI messages to build the tree.
	update! : Layout(draw), Element.ViewMessage, Render.Renderer => Try(Layout(draw), LayoutError)
	update! = |layout, msg, renderer| match msg {
		OpenBox(cfg) => open_box(layout, cfg)
		CloseBox => close_box(layout)
		Text(content) => add_text!(layout, content, renderer)
		Image(cfg) => add_image(layout, cfg)
	}

	## Phase 1: Solve layout — size (X + Y), then position.
	## Returns a tree with all positions computed.
	solve! : Layout(draw), { w: F32, h: F32 } => Try(Layout(draw), LayoutError)
	solve! = |tree, screen| {
		var $tree = solve_size_axis(tree, XAxis, screen)?
		$tree = solve_size_axis($tree, YAxis, screen)?
		$tree = solve_position($tree)?
		Ok($tree)
	}

	## Phase 2: Extract render commands from a solved tree.
	to_commands : Layout(draw), { w: F32, h: F32 } -> Try(List(Render.Command), LayoutError)
	to_commands = |tree, screen| {
		emit_render_commands(tree, screen)
	}
}


open_box : Layout(draw), Element.BoxConfig -> Try(Layout(draw), LayoutError)
open_box = |layout, cfg| {
	idx = layout.nodes.len()
	parent = if layout.stack.len() == 0 {
		NoParent
	} else {
		Parent(layout.stack.get(layout.stack.len() - 1)?)
	}
	resolved_text = resolve_box_text(layout, parent, cfg.text)?
	resolved_cfg = { ..cfg, text: Font(resolved_text) }
	node = {
		kind: BoxNode,
		payload_index: idx,
		parent,
		child_start: 0,
		child_count: 0,
		intrinsic: { w: 0, h: 0 },
		size: { w: 0, h: 0 },
		position: { x: 0, y: 0 },
		sizing_w: resolved_cfg.layout.width,
		sizing_h: resolved_cfg.layout.height,
	}
	Ok({
		..layout,
		nodes: layout.nodes.append(node),
		payloads: layout.payloads.append(BoxPayload(resolved_cfg)),
		stack: layout.stack.append(idx),
	})
}

resolve_box_text : Layout(draw), ParentIndex, Element.TextStyle -> Try(Element.TextConfig, LayoutError)
resolve_box_text = |layout, parent, style| {
	match style {
		Font(cfg_text) => Ok({ ..cfg_text, font: resolve_font(cfg_text.font, default_font) })
		Auto => match parent {
			NoParent => Ok(Element.default_text)
			Parent(parent_idx) => {
				parent_node = layout.nodes.get(parent_idx)?
				match layout.payloads.get(parent_node.payload_index)? {
					BoxPayload(parent_cfg) => match parent_cfg.text {
						Font(parent_text) => Ok(parent_text)
						Auto => Err(InternalError)
					}
					_ => Err(InternalError)
				}
			}
		}
	}
}

parent_text_config : Layout(draw) -> Try(Element.TextConfig, LayoutError)
parent_text_config = |layout| {
	if layout.stack.len() == 0 {
		Ok(Element.default_text)
	} else {
		parent_idx = layout.stack.get(layout.stack.len() - 1)?
		parent_node = layout.nodes.get(parent_idx)?
		match layout.payloads.get(parent_node.payload_index)? {
			BoxPayload(parent_cfg) => match parent_cfg.text {
				Font(parent_text) => Ok(parent_text)
				Auto => Err(InternalError)
			}
			_ => Err(InternalError)
		}
	}
}


## Attach a leaf or completed box to the currently open parent.
##
## Nodes stay in DFS declaration order, so a parent's direct children are not
## contiguous in the node list. Instead, direct child indexes accumulate in
## pending_children while the parent is open. child_count records how many
## entries at the end of that list belong to the parent currently receiving
## the child.
attach_child : Layout(draw), U64 -> Try(Layout(draw), LayoutError)
attach_child = |layout, child_idx| {
	if layout.stack.len() == 0 {
		Ok(layout)
	} else {
		parent_idx = layout.stack.get(layout.stack.len() - 1)?
		parent = layout.nodes.get(parent_idx)?
		nodes = layout.nodes.set(parent_idx, { ..parent, child_count: parent.child_count + 1 })?
		Ok({ ..layout, nodes, pending_children: layout.pending_children.append(child_idx) })
	}
}

## Compute a box's intrinsic size after all direct children have been closed.
solve_box_intrinsic : LayoutNode, Element.BoxConfig, List(LayoutNode), List(U64) -> Try(LayoutNode, Layout.LayoutError)
solve_box_intrinsic = |node, cfg, nodes, child_indices| {
	lc = cfg.layout
	dir = lc.direction
	sum_along_val = sum_children_intrinsic(nodes, child_indices, node.child_start, node.child_count, dir)?
	max_across_val = max_children_intrinsic(nodes, child_indices, node.child_start, node.child_count, dir)?
	gaps_val = sum_gap(lc.gap, node.child_count)

	fit_w = match dir {
		Row => sum_along_val + lc.pad.left + lc.pad.right + gaps_val
		Col => max_across_val + lc.pad.left + lc.pad.right
	}
	fit_h = match dir {
		Row => max_across_val + lc.pad.top + lc.pad.bottom
		Col => sum_along_val + lc.pad.top + lc.pad.bottom + gaps_val
	}

	intrinsic_w = match lc.width {
		Fixed(w) => w
		Grow(_) => 0
		Fit(_) => fit_w
		Percent(_) => 0
	}
	intrinsic_h = match lc.height {
		Fixed(h) => h
		Grow(_) => 0
		Fit(_) => fit_h
		Percent(_) => 0
	}
	Ok({ ..node, intrinsic: { w: intrinsic_w, h: intrinsic_h } })
}

## Finalize one box's direct-child range, then attach that box to its parent.
##
## Closing a box takes its direct children from the end of pending_children and
## appends them to the permanent child_indices array. This gives every box one
## contiguous child range without reordering the DFS node list. The consumed
## pending entries are removed, the box's intrinsic size is computed from its
## finalized children, and the completed box is then treated as one child of
## the enclosing box.
close_box : Layout(draw) -> Try(Layout(draw), LayoutError)
close_box = |layout| {
	if layout.stack.len() == 0 {
		return Ok(layout)
	}

	box_idx = layout.stack.get(layout.stack.len() - 1)?
	box_node = layout.nodes.get(box_idx)?
	pending_len = layout.pending_children.len()
	start_in_pending = pending_len - box_node.child_count
	box_child_indices = layout.pending_children.sublist({ start: start_in_pending, len: box_node.child_count })
	child_indices = layout.child_indices.concat(box_child_indices)
	with_child_range = { ..box_node, child_start: layout.child_indices.len() }
	cfg = match layout.payloads.get(box_node.payload_index)? {
		BoxPayload(box_cfg) => Ok(box_cfg)
		_ => Err(InternalError)
	}?
	updated = solve_box_intrinsic(with_child_range, cfg, layout.nodes, child_indices)?
	nodes = layout.nodes.set(box_idx, updated)?
	closed = {
		..layout,
		nodes,
		child_indices,
		pending_children: layout.pending_children.sublist({ start: 0, len: start_in_pending }),
		stack: layout.stack.sublist({ start: 0, len: layout.stack.len() - 1 }),
	}
	attach_child(closed, box_idx)
}

add_text! : Layout(draw), Str, Render.Renderer => Try(Layout(draw), LayoutError)
add_text! = |layout, content, renderer| {
	idx = layout.nodes.len()
	resolved = parent_text_config(layout)?
	size_raw = (renderer.measure_text_raw)(
		{
			text: content,
			size: resolved.font_size,
			spacing: renderer.default_spacing,
			font: Box.unbox(resolved.font),
		},
	)
	measured = { w: size_raw.width, h: if resolved.line_height > 0 resolved.line_height else size_raw.height }
	parent = if layout.stack.len() == 0 {
		NoParent
	} else {
		Parent(layout.stack.get(layout.stack.len() - 1)?)
	}
	payload = TextPayload({ content, config: resolved })
	node = {
		kind: TextNode,
		payload_index: idx,
		parent,
		child_start: 0,
		child_count: 0,
		intrinsic: measured,
		size: { w: 0, h: 0 },
		position: { x: 0, y: 0 },
		sizing_w: Fixed(measured.w),
		sizing_h: Fixed(measured.h),
	}
	attach_child({
		..layout,
		nodes: layout.nodes.append(node),
		payloads: layout.payloads.append(payload),
	}, idx)
}

add_image : Layout(draw), Element.ImageConfig -> Try(Layout(draw), LayoutError)
add_image = |layout, cfg| {
	idx = layout.nodes.len()
	info = Assets.info(cfg.texture)
	measured = { w: info.width, h: info.height }
	parent = if layout.stack.len() == 0 {
		NoParent
	} else {
		Parent(layout.stack.get(layout.stack.len() - 1)?)
	}
	payload = ImagePayload(cfg)
	node = {
		kind: ImageNode,
		payload_index: idx,
		parent,
		child_start: 0,
		child_count: 0,
		intrinsic: measured,
		size: { w: 0, h: 0 },
		position: { x: 0, y: 0 },
		sizing_w: Fixed(measured.w),
		sizing_h: Fixed(measured.h),
	}
	attach_child({
		..layout,
		nodes: layout.nodes.append(node),
		payloads: layout.payloads.append(payload),
	}, idx)
}

# --- Private Solver Passes ---

resolve_parent_avail_along : List(LayoutNode), List(LayoutPayload), LayoutNode, Axis, Size -> Try(F32, LayoutError)
resolve_parent_avail_along = |nodes, payloads, node, axis, screen| {
	match node.parent {
		NoParent => Ok(match axis {
			XAxis => screen.w
			YAxis => screen.h
		})
		Parent(parent_idx) => {
			parent = nodes.get(parent_idx)?
			match payloads.get(parent.payload_index)? {
				BoxPayload(pcfg) => {
					lc = pcfg.layout
					parent_inner = match axis {
						XAxis => parent.size.w - lc.pad.left - lc.pad.right
						YAxis => parent.size.h - lc.pad.top - lc.pad.bottom
					}
					Ok(parent_inner)
				}
				_ => Err(InternalError)
			}
		}
	}
}

solve_size_axis : Layout(draw), Axis, Size -> Try(Layout(draw), LayoutError)
solve_size_axis = |tree, axis, screen| {
	n = tree.nodes.len()
	if n == 0 {
		Ok(tree)
	} else {
		nodes = solve_size_axis_from(tree.nodes, tree.payloads, tree.child_indices, 0, n, axis, screen)?
		Ok({ ..tree, nodes })
	}
}

## Resolve one node's size along an axis, returning the updated node list and node.
resolve_node_size_along : List(LayoutNode), List(LayoutPayload), U64, Axis, Size -> Try({ nodes : List(LayoutNode), node : LayoutNode }, LayoutError)
resolve_node_size_along = |nodes, payloads, index, axis, screen| {
	node = nodes.get(index)?
	match node.parent {
		# Non-root sizes have already been assigned by their parent.
		Parent(_) => Ok({ nodes, node })
		NoParent => {
			parent_avail_along = resolve_parent_avail_along(nodes, payloads, node, axis, screen)?
			my_sizing = match axis {
				XAxis => node.sizing_w
				YAxis => node.sizing_h
			}
			my_intrinsic = match axis {
				XAxis => node.intrinsic.w
				YAxis => node.intrinsic.h
			}
			my_size_along = resolve_main_size(my_sizing, my_intrinsic, parent_avail_along)
			updated = set_size_along(node, axis, my_size_along)
			Ok({ nodes: nodes.set(index, updated)?, node: updated })
		}
	}
}

## Walk nodes in DFS order, threading axis-size updates through the node list.
solve_size_axis_from : List(LayoutNode), List(LayoutPayload), List(U64), U64, U64, Axis, Size -> Try(List(LayoutNode), LayoutError)
solve_size_axis_from = |nodes, payloads, child_indices, index, end, axis, screen| {
	if index >= end {
		Ok(nodes)
	} else {
		resolved = resolve_node_size_along(nodes, payloads, index, axis, screen)?
		next_nodes = if resolved.node.kind == BoxNode {
			distribute_child_sizes_along(resolved.nodes, payloads, child_indices, resolved.node, axis)?
		} else {
			resolved.nodes
		}
		solve_size_axis_from(next_nodes, payloads, child_indices, index + 1, end, axis, screen)
	}
}

ChildMetrics : { non_grow_sum : F32, grow_count : F32 }

compute_child_metrics : List(LayoutNode), List(U64), U64, U64, Axis, F32 -> Try(ChildMetrics, LayoutError)
compute_child_metrics = |nodes, child_indices, start, count, axis, parent_avail| {
	if count == 0 {
		Ok({ non_grow_sum: 0, grow_count: 0 })
	} else {
		child_idx = child_indices.get(start)?
		c = nodes.get(child_idx)?
		my_sizing = match axis {
			XAxis => c.sizing_w
			YAxis => c.sizing_h
		}
		my_intrinsic = match axis {
			XAxis => c.intrinsic.w
			YAxis => c.intrinsic.h
		}
		is_grow = is_grow_sizing(my_sizing)
		child_size = resolve_child_axis(my_sizing, my_intrinsic, parent_avail, 0.0)

		rest = compute_child_metrics(nodes, child_indices, start + 1, count - 1, axis, parent_avail)?
		Ok(
			{
				non_grow_sum: (
					if is_grow {
						0.0
					} else {
						child_size
					},
				) + rest.non_grow_sum,
				grow_count: (
					if is_grow {
						1.0
					} else {
						0.0
					},
				) + rest.grow_count,
			},
		)
	}
}

distribute_child_sizes_along : List(LayoutNode), List(LayoutPayload), List(U64), LayoutNode, Axis -> Try(List(LayoutNode), LayoutError)
distribute_child_sizes_along = |nodes, payloads, child_indices, parent, axis| {
	match payloads.get(parent.payload_index)? {
		BoxPayload(cfg) => {
			lc = cfg.layout
			my_inner_along = match axis {
				XAxis => parent.size.w - lc.pad.left - lc.pad.right
				YAxis => parent.size.h - lc.pad.top - lc.pad.bottom
			}
			gaps_val = sum_gap(lc.gap, parent.child_count)

			metrics = compute_child_metrics(nodes, child_indices, parent.child_start, parent.child_count, axis, my_inner_along)?
			avail_for_grow = my_inner_along - metrics.non_grow_sum - gaps_val
			is_cross_axis = match (lc.direction, axis) {
				(Row, YAxis) => Bool.True
				(Col, XAxis) => Bool.True
				_ => Bool.False
			}
			grow_fill_val = if metrics.grow_count > 0 {
				if is_cross_axis {
					my_inner_along
				} else if avail_for_grow > 0 {
					avail_for_grow / metrics.grow_count
				} else {
					0.0
				}
			} else {
				0.0
			}

			set_child_sizes_range(nodes, child_indices, parent.child_start, parent.child_count, axis, my_inner_along, grow_fill_val)
		}
		_ => Err(InternalError)
	}
}

set_child_sizes_range : List(LayoutNode), List(U64), U64, U64, Axis, F32, F32 -> Try(List(LayoutNode), LayoutError)
set_child_sizes_range = |nodes, child_indices, start, count, axis, parent_avail, grow_fill| {
	if count == 0 {
		Ok(nodes)
	} else {
		child_idx = child_indices.get(start)?
		child = nodes.get(child_idx)?
		my_sizing = match axis {
			XAxis => child.sizing_w
			YAxis => child.sizing_h
		}
		my_intrinsic = match axis {
			XAxis => child.intrinsic.w
			YAxis => child.intrinsic.h
		}
		child_size = resolve_child_axis(my_sizing, my_intrinsic, parent_avail, grow_fill)
		updated = set_size_along(child, axis, child_size)
		new_nodes = nodes.set(child_idx, updated)?
		set_child_sizes_range(new_nodes, child_indices, start + 1.U64, count - 1.U64, axis, parent_avail, grow_fill)
	}
}

solve_position : Layout(draw) -> Try(Layout(draw), LayoutError)
solve_position = |tree| {
	n = tree.nodes.len()
	if n == 0 {
		Ok(tree)
	} else {
		var $nodes = tree.nodes
		for i in 0..<n {
			node = $nodes.get(i)?
			if node.parent == NoParent {
				$nodes = $nodes.set(i, { ..node, position: { x: 0, y: 0 } })?
			}
			if node.kind == BoxNode {
				$nodes = position_children($nodes, tree.payloads, tree.child_indices, i)?
			}
		}
		Ok({ ..tree, nodes: $nodes })
	}
}

position_children : List(LayoutNode), List(LayoutPayload), List(U64), U64 -> Try(List(LayoutNode), LayoutError)
position_children = |nodes, payloads, child_indices, parent_idx| {
	parent = nodes.get(parent_idx)?
	match payloads.get(parent.payload_index)? {
		BoxPayload(cfg) => {
			lc = cfg.layout
			dir = lc.direction
			gap = lc.gap
			align_x = lc.child_align.x
			align_y = lc.child_align.y
			content_x = parent.position.x + lc.pad.left
			content_y = parent.position.y + lc.pad.top
			inner_w = parent.size.w - lc.pad.left - lc.pad.right
			inner_h = parent.size.h - lc.pad.top - lc.pad.bottom
			sum_along = sum_children_size(nodes, child_indices, parent.child_start, parent.child_count, dir)?
			gaps_val = sum_gap(gap, parent.child_count)
			main_avail = match dir {
				Row => inner_w
				Col => inner_h
			}
			on_axis_extra = main_avail - sum_along - gaps_val
			start_cursor = axis_offset(on_axis_extra, match dir {
				Row => align_x
				Col => align_y
			})

			position_child_range(
				nodes,
				child_indices,
				parent.child_start,
				parent.child_count,
				dir,
				gap,
				content_x,
				content_y,
				inner_w,
				inner_h,
				start_cursor,
				align_x,
				align_y,
			)
		}
		_ => Err(InternalError)
	}
}

position_child_range : List(LayoutNode),
List(U64),
U64,
U64,
Element.Direction,
F32,
F32,
F32,
F32,
F32,
F32,
Element.ChildAlign,
Element.ChildAlign -> Try(List(LayoutNode), LayoutError)
position_child_range = |nodes, child_indices, start, count, dir, gap, cx, cy, iw, ih, cursor, align_x, align_y| {
	if count == 0 {
		Ok(nodes)
	} else {
		child_idx = child_indices.get(start)?
		child = nodes.get(child_idx)?
		cross_off = cross_offset(
			match dir {
				Row => child.size.h
				Col => child.size.w
			},
			match dir {
				Row => ih
				Col => iw
			},
			match dir {
				Row => align_y
				Col => align_x
			},
		)
		child_x = match dir {
			Row => cx + cursor
			Col => cx + cross_off
		}
		child_y = match dir {
			Row => cy + cross_off
			Col => cy + cursor
		}
		step = match dir {
			Row => child.size.w
			Col => child.size.h
		}
		updated = { ..child, position: { x: child_x, y: child_y } }
		new_nodes = nodes.set(child_idx, updated)?
		position_child_range(new_nodes, child_indices, start + 1.U64, count - 1.U64, dir, gap, cx, cy, iw, ih, cursor + step + gap, align_x, align_y)
	}
}

emit_render_commands : Layout(draw), Size -> Try(List(Render.Command), LayoutError)
emit_render_commands = |tree, screen| {
	var $commands = []
	var $border_commands = []
	for i in 0..<tree.nodes.len() {
		node = tree.nodes.get(i)?
		payload = tree.payloads.get(i)?
		if !is_offscreen(node.position, node.size, screen) {
			match (node.kind, payload) {
				(BoxNode, BoxPayload(cfg)) => {
					if cfg.background.a > 0 {
						bg = if cfg.radius > 0 {
							RoundedRectangle(
								{
									x: node.position.x,
									y: node.position.y,
									width: node.size.w,
									height: node.size.h,
									radius: cfg.radius,
									color: cfg.background,
								},
							)
						} else {
							Rectangle(
								{
									x: node.position.x,
									y: node.position.y,
									width: node.size.w,
									height: node.size.h,
									color: cfg.background,
								},
							)
						}
						$commands = $commands.append(bg)
					}
					border_total = cfg.border.left + cfg.border.right + cfg.border.top + cfg.border.bottom
					if cfg.border.color.a > 0 and border_total > 0 {
						$border_commands = $border_commands.append(
							Border(
								{
									x: node.position.x,
									y: node.position.y,
									width: node.size.w,
									height: node.size.h,
									color: cfg.border.color,
									left: cfg.border.left,
									right: cfg.border.right,
									top: cfg.border.top,
									bottom: cfg.border.bottom,
								},
							),
						)
					}
				}
				(TextNode, TextPayload({ content, config })) => {
					$commands = $commands.append(
						Text(
							{
								x: node.position.x + text_align_offset(config.align, node.size.w, node.intrinsic.w),
								y: node.position.y,
								text: content,
								font_size: config.font_size,
								color: config.color,
								font: config.font,
							},
						),
					)
				}
				(ImageNode, ImagePayload(cfg)) => {
					$commands = $commands.append(
						Image(
							{
								x: node.position.x,
								y: node.position.y,
								width: node.size.w,
								height: node.size.h,
								texture: cfg.texture,
								tint: cfg.tint,
							},
						),
					)
				}
				_ => {}
			}
		}
	}
	Ok($commands.concat($border_commands))
}

## TESTS ##

solve_test_layout : Layout(draw), Size -> Try(Layout(draw), LayoutError)
solve_test_layout = |tree, screen| {
	var $tree = solve_size_axis(tree, XAxis, screen)?
	$tree = solve_size_axis($tree, YAxis, screen)?
	solve_position($tree)
}

test_cfg : Element.Sizing, Element.Sizing, Element.Direction, Element.ChildAlign, Element.ChildAlign, F32, { left : F32, right : F32, top : F32, bottom : F32 } -> Element.BoxConfig
test_cfg = |width, height, direction, align_x, align_y, gap, pad| {
	base = Element.default_box
	{
		..base,
		layout: {
			..base.layout,
			width,
			height,
			direction,
			child_align: { x: align_x, y: align_y },
			gap,
			pad,
		},
	}
}

fixed_cfg : F32, F32 -> Element.BoxConfig
fixed_cfg = |w, h| test_cfg(Fixed(w), Fixed(h), Row, Start, Start, 0, Element.pad_all(0))

build_row : Element.BoxConfig, List(Element.BoxConfig) -> Try(Layout(draw), LayoutError)
build_row = |root_cfg, child_cfgs| {
	var $tree = Layout.new()
	$tree = open_box($tree, root_cfg)?
	for child_cfg in child_cfgs {
		$tree = open_box($tree, child_cfg)?
		$tree = close_box($tree)?
	}
	close_box($tree)
}

build_and_solve : Element.BoxConfig, List(Element.BoxConfig), Size -> Try(Layout(draw), LayoutError)
build_and_solve = |root_cfg, child_cfgs, screen| {
	tree = build_row(root_cfg, child_cfgs)?
	solve_test_layout(tree, screen)
}

## Closing boxes should preserve DFS node order while building contiguous
## direct-child ranges in child_indices.
expect {
	cfg = Element.default_box
	build = || {
		var $tree = Layout.new()
		$tree = open_box($tree, cfg)?       # root: 0
		$tree = open_box($tree, cfg)?       # first child: 1
		$tree = close_box($tree)?
		$tree = open_box($tree, cfg)?       # second child: 2
		$tree = open_box($tree, cfg)?       # grandchild: 3
		$tree = close_box($tree)?
		$tree = close_box($tree)?
		$tree = close_box($tree)?
		Ok($tree)
	}

	match build() {
		Ok(tree) => match (tree.nodes.get(0), tree.nodes.get(2)) {
			(Ok(r), Ok(s)) => tree.child_indices == [3, 1, 2]
				and r.child_start == 1
				and r.child_count == 2
				and s.child_start == 0
				and s.child_count == 1
			_ => Bool.False
		}
		_ => Bool.False
	}
}

## clear should reset all frame-local builder state before the next view build.
expect {
	cfg = Element.default_box
	build = || {
		var $tree = Layout.new()
		$tree = open_box($tree, cfg)?
		$tree = open_box($tree, cfg)?
		$tree = close_box($tree)?
		$tree = close_box($tree)?
		Ok($tree.clear())
	}

	match build() {
		Ok(tree) => tree.nodes.len() == 0
			and tree.payloads.len() == 0
			and tree.child_indices.len() == 0
			and tree.pending_children.len() == 0
			and tree.stack.len() == 0
			and tree.root_index == 0
		Err(_) => Bool.False
	}
}

## A box with Auto should use the nearest ancestor's resolved text style.
expect {
	base_cfg = Element.default_box
	root_cfg = {
		..base_cfg,
		text: Font({ ..Element.default_text, font_size: 17, line_height: 21 }),
	}
	build = || {
		var $tree = Layout.new()
		$tree = open_box($tree, root_cfg)?
		$tree = open_box($tree, base_cfg)?
		Ok($tree)
	}

	match build() {
		Ok(tree) => match tree.payloads.get(1) {
			Ok(BoxPayload(child_cfg)) => match child_cfg.text {
				Font(text_cfg) => text_cfg.font_size == 17 and text_cfg.line_height == 21
				Auto => Bool.False
			}
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

## Closing a Fit parent should compute intrinsic size from already-closed
## fixed-size children.
expect {
	base_cfg = Element.default_box
	root_cfg = base_cfg
	child_cfg = {
		..base_cfg,
		layout: {
			..base_cfg.layout,
			width: Fixed(10),
			height: Fixed(20),
		},
	}
	build = || {
		var $tree = Layout.new()
		$tree = open_box($tree, root_cfg)?
		$tree = open_box($tree, child_cfg)?
		$tree = close_box($tree)?
		$tree = close_box($tree)?
		Ok($tree)
	}

	match build() {
		Ok(tree) => match tree.nodes.get(0) {
			Ok(root) => root.intrinsic.w == 10 and root.intrinsic.h == 20
			Err(_) => Bool.False
		}
		Err(_) => Bool.False
	}
}

## Fixed-size children in a row should keep their configured dimensions and be
## placed sequentially along the X axis.
expect {
	root_cfg = fixed_cfg(100, 40)
	child_a = fixed_cfg(10, 20)
	child_b = fixed_cfg(15, 30)

	match build_and_solve(root_cfg, [child_a, child_b], { w: 100, h: 40 }) {
		Ok(tree) => match (tree.nodes.get(0), tree.nodes.get(1), tree.nodes.get(2)) {
			(Ok(root), Ok(a), Ok(b)) => root.size.w == 100
				and root.size.h == 40
				and a.size.w == 10
				and a.size.h == 20
				and b.size.w == 15
				and b.size.h == 30
				and a.position.x == 0
				and a.position.y == 0
				and b.position.x == 10
				and b.position.y == 0
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

## Parent padding and gap should offset row children from the content box
## and from each other.
expect {
	root_cfg = test_cfg(Fixed(100), Fixed(50), Row, Start, Start, 3, { left: 5, right: 2, top: 7, bottom: 4 })
	child_a = fixed_cfg(10, 10)
	child_b = fixed_cfg(20, 10)

	match build_and_solve(root_cfg, [child_a, child_b], { w: 100, h: 50 }) {
		Ok(tree) => match (tree.nodes.get(1), tree.nodes.get(2)) {
			(Ok(a), Ok(b)) => a.position == { x: 5, y: 7 }
				and b.position == { x: 18, y: 7 }
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

## Main-axis center alignment and cross-axis end alignment should move a single
## row child to the centered and bottommost available slot.
expect {
	root_cfg = test_cfg(Fixed(100), Fixed(50), Row, Center, End, 0, Element.pad_all(0))
	child = fixed_cfg(20, 10)

	match build_and_solve(root_cfg, [child], { w: 100, h: 50 }) {
		Ok(tree) => match tree.nodes.get(1) {
			Ok(node) => node.position == { x: 40, y: 40 }
			Err(_) => Bool.False
		}
		Err(_) => Bool.False
	}
}

## Column layout should stack children on Y and use X alignment for the cross
## axis.
expect {
	root_cfg = test_cfg(Fixed(50), Fixed(100), Col, End, Start, 4, Element.pad_all(0))
	child_a = fixed_cfg(10, 20)
	child_b = fixed_cfg(15, 30)

	match build_and_solve(root_cfg, [child_a, child_b], { w: 50, h: 100 }) {
		Ok(tree) => match (tree.nodes.get(1), tree.nodes.get(2)) {
			(Ok(a), Ok(b)) => a.position == { x: 40, y: 0 }
				and b.position == { x: 35, y: 24 }
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

## Row grow sizing should distribute remaining main-axis space equally after
## fixed children and gaps are accounted for.
expect {
	root_cfg = fixed_cfg(100, 20)
	fixed = fixed_cfg(10, 20)
	grow = test_cfg(Grow({ min: 0, max: 1000 }), Fixed(20), Row, Start, Start, 0, Element.pad_all(0))
	root_with_gap = { ..root_cfg, layout: { ..root_cfg.layout, gap: 5 } }

	match build_and_solve(root_with_gap, [fixed, grow, grow], { w: 100, h: 20 }) {
		Ok(tree) => match (tree.nodes.get(1), tree.nodes.get(2), tree.nodes.get(3)) {
			(Ok(a), Ok(b), Ok(c)) => a.size.w == 10
				and b.size.w == 40
				and c.size.w == 40
				and a.position.x == 0
				and b.position.x == 15
				and c.position.x == 60
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

## Percent sizing should resolve against the parent's available size on each
## axis.
expect {
	root_cfg = fixed_cfg(200, 100)
	percent = test_cfg(Percent(0.25), Percent(0.5), Row, Start, Start, 0, Element.pad_all(0))

	match build_and_solve(root_cfg, [percent], { w: 200, h: 100 }) {
		Ok(tree) => match tree.nodes.get(1) {
			Ok(child) => child.size == { w: 50, h: 50 }
			Err(_) => Bool.False
		}
		Err(_) => Bool.False
	}
}

## Fit sizing in a column should use max child width for the cross axis and sum
## child heights plus gaps for the main axis, including padding on both axes.
expect {
	root_cfg = test_cfg(Fit({ min: 0, max: 1000 }), Fit({ min: 0, max: 1000 }), Col, Start, Start, 6, { left: 3, right: 4, top: 5, bottom: 7 })
	child_a = fixed_cfg(10, 20)
	child_b = fixed_cfg(15, 30)

	match build_row(root_cfg, [child_a, child_b]) {
		Ok(tree) => match tree.nodes.get(0) {
			Ok(root) => root.intrinsic.w == 22 and root.intrinsic.h == 68
			Err(_) => Bool.False
		}
		Err(_) => Bool.False
	}
}
