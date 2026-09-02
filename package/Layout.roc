## Flat layout layout - flex-box layout solver.
## Uses a layout layout stack (flat List-of-structs) built via push/pop message API.
## Intrinsic sizes are computed during construction.
import Color
import Element
import Event
import Floating exposing [Clip.*, ZOrder.*]
import Identity exposing [NodeId]
import LayoutTypes exposing [
	Axis.*,
	Bounds,
	LayoutNode,
	LayoutNodeKind.*,
	ClipSource.*,
	FloatingTarget.*,
	ImageNodeData,
	ParentIndex.*,
	Placement.*,
	Pos,
	Size,
	TextNodeData,
	VisibleRegion.*,
]
import Solver
import Stack
import Text
import TextMeasureCache
import rrt.Font

# --- Public API ---
TextureLike(fields) : { width : F32, height : F32, ..fields }

ResolvedText := {
	font : Font,
	config : Text.Config,
}

Layout(texture) :: {
	nodes : List(LayoutNode(texture)),
	text_contents : List(Str),
	text_lines : List(Text.Line),
	text_cache : TextMeasureCache,
	root_text : ResolvedText,
	child_indices : List(U64),
	pending_children : List(U64),
	node_ids : Dict(NodeId, U64),
	root_indices : List(U64),
	stack : Stack(LayoutFrame),
}.{
	LayoutError : [InternalError, OutOfBounds, NodeIdNotFound(NodeId), DuplicateNodeId, UnmatchedCloseBox, AttachmentCycle]
	NodeId : U64

	## Create an empty layout with the real font inherited at its root.
	new : Font -> Layout(texture)
	new = |default_font| {
		root_text : ResolvedText
		root_text = {
			font: default_font,
			config: {
				font_size: Element.default_text.font_size,
				spacing: Element.default_text.spacing,
				color: Element.default_text.color,
				line_height: Element.default_text.line_height,
				align: Element.default_text.align,
				wrap: Element.default_text.wrap,
			},
		}
		{
			nodes: [],
			text_contents: [],
			text_lines: [],
			text_cache: TextMeasureCache.new(),
			root_text,
			child_indices: [],
			pending_children: [],
			node_ids: Dict.empty(),
			root_indices: [],
			stack: Stack.new(),
		}
	}

	## Deterministic layout used by package tests.
	test_layout : () -> Layout(texture)
	test_layout = || Layout.new(Font.stub)

	## Reset all frame-local layout state before building the next view.
	clear : Layout(texture) -> Layout(texture)
	clear = |layout| {
		..layout,
		nodes: layout.nodes.clear(),
		text_contents: layout.text_contents.clear(),
		text_lines: layout.text_lines.clear(),
		text_cache: layout.text_cache.next_generation(),
		child_indices: layout.child_indices.clear(),
		pending_children: layout.pending_children.clear(),
		node_ids: layout.node_ids.clear(),
		root_indices: layout.root_indices.clear(),
		stack: layout.stack.clear(),
	}

	## The most recently appended layout node.
	current_node_index : Layout(texture) -> Try(U64, LayoutError)
	current_node_index = |layout| {
		if layout.nodes.len() == 0 {
			Err(OutOfBounds)
		} else {
			Ok(layout.nodes.len() - 1)
		}
	}

	## The node index that will be assigned to the next appended layout node.
	next_node_index : Layout(texture) -> U64
	next_node_index = |layout| layout.nodes.len()

	## Push/pop UI messages to build the layout.
	update : Layout(TextureLike(fields)), Element.ElementOp(msg, TextureLike(fields)), (NodeId -> Element.BoxStatus), (NodeId -> LayoutTypes.Pos) -> Try((Layout(TextureLike(fields)), [Node(NodeId, [Events(List(Event.Handler(msg))), NoEvent]), NoNode]), LayoutError)
	update = |layout, op, status_fn, scroll_fn| match op {
		OpenBox(id, style_fn, events) => {
			node_id = next_box_node_id(layout, id)?
			status = status_fn(node_id)
			style = style_fn(status)
			node_events = match events.len() {
				0 => NoEvent
				_ => Events(events)
			}
			Ok((open_box_with_scroll(layout, id, style, scroll_fn(node_id))?, Node(node_id, node_events)))
		}
		CloseBox => {
			node_id = close_box_node_id(layout)?
			Ok((close_box(layout)?, Node(node_id, NoEvent)))
		}
		Text(content) => {
			node_id = next_auto_node_id(layout)?
			Ok((add_text(layout, node_id, content)?, Node(node_id, NoEvent)))
		}
		Image(cfg) => {
			node_id = next_auto_node_id(layout)?
			Ok((add_image(layout, node_id, cfg)?, Node(node_id, NoEvent)))
		}
	}

	## Phase 1: Solve layout — width, height, then position.
	solve : Layout(texture), { w : F32, h : F32 } -> Try(Layout(texture), LayoutError)
	solve = |layout, screen| {
		ordered_root_indices = Floating.roots_in_attachment_order(layout.nodes, layout.node_ids, layout.root_indices)?
		var $layout = layout

		for root_index in ordered_root_indices {
			$layout = size_root_sublayout_axis($layout, root_index, XAxis, screen)?
		}

		$layout = wrap_text_nodes($layout)?
		$layout = refresh_intrinsics($layout)?

		for root_index in ordered_root_indices {
			$layout = size_root_sublayout_axis($layout, root_index, YAxis, screen)?
		}

		$layout = { ..$layout, nodes: Solver.update_content_sizes($layout.nodes, $layout.child_indices)? }

		for root_index in ordered_root_indices {
			$layout = position_root_sublayout($layout, root_index, screen)?
		}

		Ok($layout)
	}

	## Compute conservative subtree paint bounds in node-list order.
	## The solved node list is DFS preorder, so a reverse scan visits every
	## child before its parent without another recursive traversal.
	compute_paint_bounds : Layout(texture) -> Try(List(Bounds), LayoutError)
	compute_paint_bounds = |layout| {
		result = compute_paint_data(layout)?
		Ok(result.paint_bounds)
	}

	## Compute paint bounds and per-box scissor need in one reverse pass.
	## `needs_clip[i]` is true when the box at `i` has overflow != Visible
	## and any direct child's paint escapes its own bounds. Renderer can then
	## decide `with_scissor` in O(1) instead of re-scanning children.
	compute_paint_data : Layout(texture) -> Try({ paint_bounds : List(Bounds), needs_clip : List(Bool) }, LayoutError)
	compute_paint_data = |layout| compute_layout_paint_data(layout)

	## Expose solved traversal storage to the renderer without putting drawing
	## behavior on Layout.
	render_data : Layout(texture) -> {
		nodes : List(LayoutNode(texture)),
		text_contents : List(Str),
		text_lines : List(Text.Line),
		child_indices : List(U64),
		node_ids : Dict(NodeId, U64),
		root_indices : List(U64),
	}
	render_data = |layout| {
		nodes: layout.nodes,
		text_contents: layout.text_contents,
		text_lines: layout.text_lines,
		child_indices: layout.child_indices,
		node_ids: layout.node_ids,
		root_indices: layout.root_indices,
	}

	## Shared viewport and clip visibility used by rendering, hit testing, and
	## debug inspection.
	visible_region : Bounds, Bounds, Floating.Clip -> LayoutTypes.VisibleRegion
	visible_region = |paint_bounds, viewport, clip| LayoutTypes.visible_region(paint_bounds, viewport, clip)

	## Return the deepest/latest box node ID containing the point.
	hit_test : Layout(texture), { x : F32, y : F32 } -> Try([Hit(NodeId), NoHit], LayoutError)
	hit_test = |layout, point| {
		match hit_index_at(layout, point)? {
			Hit(node_index) => {
				node = layout.nodes.get(node_index)?
				Ok(Hit(node.id))
			}
			NoHit => Ok(NoHit)
		}
	}

	## Return hovered node IDs from deepest to shallowest, continuing through
	## passthrough floating roots into lower roots.
	hover_path : Layout(texture), { x : F32, y : F32 } -> Try(List(NodeId), LayoutError)
	hover_path = |layout, point| {
		var $hovered = []
		for node_index in hit_indices_at(layout, point)? {
			path = collect_box_ancestor_ids(layout.nodes, node_index, [])?
			$hovered = $hovered.concat(path)
		}
		Ok($hovered)
	}

	## Return solved bounds for a node ID.
	node_bounds : Layout(texture), NodeId -> Try(Event.ElementBounds, [NodeIdNotFound(NodeId), OutOfBounds, ..])
	node_bounds = |layout, node_id| {
		node_index = index_for_node_id(layout, node_id)?
		node = layout.nodes.get(node_index)?
		Ok({ x: node.position.x, y: node.position.y, width: node.size.w, height: node.size.h })
	}

	## Return solved scrolling data for a stable node ID.
	get_scroll_container_data : Layout(texture), NodeId -> ScrollContainerData
	get_scroll_container_data = |layout, node_id| {
		match index_for_node_id(layout, node_id) {
			Err(_) => empty_scroll_container_data
			Ok(index) => match layout.nodes.get(index) {
				Err(_) => empty_scroll_container_data
				Ok(node) => match node.kind {
					BoxNode(box) => {
						scroll_position: node.scroll_offset,
						scroll_container_dimensions: node.size,
						content_dimensions: node.content_size,
						overflow: box.overflow,
						found: Bool.True,
					}
					_ => empty_scroll_container_data
				}
			}
		}
	}

	## List solved box nodes and their scrolling data.
	scroll_containers : Layout(texture) -> List(ScrollNodeData)
	scroll_containers = |layout| {
		layout.nodes.iter().fold(
			[],
			|items, node| match node.kind {
				BoxNode(box) => items.append({
					id: node.id,
					scroll_position: node.scroll_offset,
					scroll_container_dimensions: node.size,
					content_dimensions: node.content_size,
					overflow: box.overflow,
				})
				_ => items
			},
		)
	}
}

ScrollContainerData : {
	scroll_position : LayoutTypes.Pos,
	scroll_container_dimensions : Size,
	content_dimensions : Size,
	overflow : { x : Element.Overflow, y : Element.Overflow },
	found : Bool,
}

ScrollNodeData : {
	id : NodeId,
	scroll_position : LayoutTypes.Pos,
	scroll_container_dimensions : Size,
	content_dimensions : Size,
	overflow : { x : Element.Overflow, y : Element.Overflow },
}

empty_scroll_container_data : ScrollContainerData
empty_scroll_container_data = {
	scroll_position: { x: 0, y: 0 },
	scroll_container_dimensions: { w: 0, h: 0 },
	content_dimensions: { w: 0, h: 0 },
	overflow: { x: Hidden, y: Hidden },
	found: Bool.False,
}

LayoutFrame : {
	index : U64,
	text : ResolvedText,
	child_offset : U64,
}

TextLayout : {
	line_height : F32,
	lines : List(Text.Line),
	preferred : Size,
	min_width : F32,
}

# --- Node Identity ---

## Synthetic parent node ID used to resolve identities at the layout root.
root_node_id : NodeId
root_node_id = 0

register_node_id : Layout(texture), NodeId, U64 -> Try(Layout(texture), [DuplicateNodeId, ..])
register_node_id = |layout, node_id, node_index| {
	match layout.node_ids.get(node_id) {
		Ok(_) => Err(DuplicateNodeId)
		Err(_) => Ok({ ..layout, node_ids: layout.node_ids.insert(node_id, node_index) })
	}
}

index_for_node_id : Layout(texture), NodeId -> Try(U64, [NodeIdNotFound(NodeId), ..])
index_for_node_id = |layout, node_id| {
	layout.node_ids.get(node_id).map_err(|_| NodeIdNotFound(node_id))
}

parent_node_id : Layout(texture), ParentIndex -> Try(NodeId, [OutOfBounds, ..])
parent_node_id = |layout, parent| match parent {
	NoParent => Ok(root_node_id)
	Parent(parent_idx) => {
		parent_node = layout.nodes.get(parent_idx)?
		Ok(parent_node.id)
	}
}

parent_child_offset : Layout(texture), ParentIndex -> Try(U64, [OutOfBounds, ..])
parent_child_offset = |layout, parent| match parent {
	NoParent => Ok(layout.root_indices.len())
	Parent(parent_idx) => {
		parent_node = layout.nodes.get(parent_idx)?
		offset = layout.stack.top()
			.map_ok(|frame| if frame.index == parent_idx frame.child_offset else parent_node.child_count)
			.ok_or(parent_node.child_count)
		Ok(offset)
	}
}

parent_from_stack : Layout(texture) -> ParentIndex
parent_from_stack = |layout| {
	match layout.stack.top() {
		Ok(frame) => Parent(frame.index)
		Err(OutOfBounds) => NoParent
	}
}

next_box_node_id : Layout(texture), Element.ElementId -> Try(NodeId, [OutOfBounds, ..])
next_box_node_id = |layout, id| {
	parent = parent_from_stack(layout)
	Ok(
		Identity.resolve(
			id,
			parent_node_id(layout, parent)?,
			parent_child_offset(layout, parent)?,
		),
	)
}

next_auto_node_id : Layout(texture) -> Try(NodeId, [OutOfBounds, ..])
next_auto_node_id = |layout| next_box_node_id(layout, Auto)

close_box_node_id : Layout(texture) -> Try(NodeId, [OutOfBounds, UnmatchedCloseBox, ..])
close_box_node_id = |layout| {
	match layout.stack.top() {
		Err(OutOfBounds) => Err(UnmatchedCloseBox)
		Ok(frame) => {
			box_node = layout.nodes.get(frame.index)?
			Ok(box_node.id)
		}
	}
}

resolve_box_text : Layout(texture), Element.TextStyle -> ResolvedText
resolve_box_text = |layout, style| {
	parent_text_cfg = layout.stack.top().map_ok(|frame| frame.text).ok_or(layout.root_text)
	match style {
		Auto => parent_text_cfg
		Font(text_cfg) => {
			font = match text_cfg.font {
				InheritFont => parent_text_cfg.font
				FontHandle(value) => value
			}
			{
				font,
				config: {
					font_size: text_cfg.font_size,
					spacing: text_cfg.spacing,
					color: text_cfg.color,
					line_height: text_cfg.line_height,
					align: text_cfg.align,
					wrap: text_cfg.wrap,
				},
			}
		}
	}
}

## Resolve a public floating declaration into the node's internal placement.
resolve_placement : Layout(texture), ParentIndex, Element.Floating -> Try(LayoutTypes.Placement, [OutOfBounds, ..])
resolve_placement = |layout, parent, declaration| match declaration {
	NoFloating => Ok(Normal)
	Floating({ target, config }) => {
		{ resolved_target, clip_source } = match target {
			Root => { resolved_target: Root, clip_source: Unclipped }
			Parent => {
				resolved_target: Element(parent_node_id(layout, parent)?),
				clip_source: if config.clip_to == AttachedParent Target else Unclipped,
			}
			Element(target_id) => {
				resolved_target: Element(Identity.resolve(target_id, parent_node_id(layout, parent)?, parent_child_offset(layout, parent)?)),
				clip_source: if config.clip_to == AttachedParent TargetAncestors else Unclipped,
			}
		}
		Ok(Floating(resolved_floating_config(config, resolved_target, clip_source)))
	}
}

## Copy public floating options into a target-resolved internal configuration.
resolved_floating_config : Element.FloatingConfig, LayoutTypes.FloatingTarget, LayoutTypes.ClipSource -> LayoutTypes.ResolvedFloatingConfig
resolved_floating_config = |config, target, clip_source| {
	target,
	clip_source,
	z_index: config.z_index,
	offset: config.offset,
	expand: config.expand,
	attach_points: config.attach_points,
	capture: config.capture,
}

# --- layout Builder ---

open_box : Layout(texture), Element.ElementId, Element.BoxConfig -> Try(Layout(texture), [OutOfBounds, DuplicateNodeId, ..])
open_box = |layout, id, cfg| open_box_with_scroll(layout, id, cfg, { x: 0, y: 0 })

## Open a box using its retained scroll offset.
open_box_with_scroll : Layout(texture), Element.ElementId, Element.BoxConfig, LayoutTypes.Pos -> Try(Layout(texture), [OutOfBounds, DuplicateNodeId, ..])
open_box_with_scroll = |layout, id, cfg, retained_offset| {
	idx = layout.nodes.len()
	parent = parent_from_stack(layout)
	node_id = Identity.resolve(
		id,
		parent_node_id(layout, parent)?,
		parent_child_offset(layout, parent)?,
	)
	resolved_text = resolve_box_text(layout, cfg.text)
	resolved_cfg = { ..cfg, text: Auto }
	placement = resolve_placement(layout, parent, cfg.floating)?
	layout_parent = match placement {
		Normal => parent
		Floating(_) => NoParent
	}
	node = {
		id: node_id,
		kind: BoxNode({
			layout: resolved_cfg.layout,
			background: resolved_cfg.background,
			radius: resolved_cfg.radius,
			border: resolved_cfg.border,
			overflow: resolved_cfg.overflow,
		}),
		parent: layout_parent,
		child_start: 0,
		child_count: 0,
		intrinsic: { w: 0, h: 0 },
		size: { w: 0, h: 0 },
		content_size: { w: 0, h: 0 },
		scroll_offset: if cfg.overflow.x == Visible and cfg.overflow.y == Visible { x: 0, y: 0 } else retained_offset,
		position: { x: 0, y: 0 },
		sizing_w: resolved_cfg.layout.width,
		sizing_h: resolved_cfg.layout.height,
		placement,
	}
	layout_with_id = register_node_id(layout, node_id, idx)?
	Ok({
		..layout_with_id,
		nodes: layout_with_id.nodes.append(node),
		stack: layout_with_id.stack.push({ index: idx, text: resolved_text, child_offset: 0 }),
	})
}

## Attach a leaf or completed box to the currently open parent.
##
## Nodes stay in DFS declaration order, so a parent's direct children are not
## contiguous in the node list. Instead, direct child indexes accumulate in
## pending_children while the parent is open. child_count records how many
## entries at the end of that list belong to the parent currently receiving
## the child.
attach_child : Layout(texture), U64 -> Try(Layout(texture), [OutOfBounds, ..])
attach_child = |layout, child_idx| {
	match layout.stack.top() {
		Err(OutOfBounds) => Ok(layout)
		Ok(item) => {
			parent = layout.nodes.get(item.index)?
			nodes = layout.nodes.set(item.index, { ..parent, child_count: parent.child_count + 1 })?
			stack = increment_top_child_offset(layout.stack)?
			Ok({ ..layout, nodes, stack, pending_children: layout.pending_children.append(child_idx) })
		}
	}
}

## Advance the open parent's stable child identity offset.
increment_top_child_offset : Stack(LayoutFrame) -> Try(Stack(LayoutFrame), [OutOfBounds, ..])
increment_top_child_offset = |stack| {
	index = stack.items.len() - 1
	frame = stack.items.get(index)?
	Ok({ items: stack.items.set(index, { ..frame, child_offset: frame.child_offset + 1 })? })
}

## Return the currently open box and the stack that remains after closing it.
pop_open_box : Layout(texture) -> Try({ node_index : U64, node : LayoutNode(texture), stack : Stack(LayoutFrame) }, [OutOfBounds, UnmatchedCloseBox, ..])
pop_open_box = |layout| {
	match layout.stack.pop() {
		Err(OutOfBounds) => Err(UnmatchedCloseBox)
		Ok({ item: frame, stack }) => {
			node = layout.nodes.get(frame.index)?
			Ok({ node_index: frame.index, node, stack })
		}
	}
}

## Move a closing box's pending children into the permanent child index list.
finalize_child_range : Layout(texture), LayoutNode(texture) -> (Layout(texture), LayoutNode(texture))
finalize_child_range = |layout, box_node| {
	pending_len = layout.pending_children.len()
	start_in_pending = pending_len - box_node.child_count
	box_child_indices = layout.pending_children.sublist({ start: start_in_pending, len: box_node.child_count })
	child_indices = layout.child_indices.concat(box_child_indices)
	node = { ..box_node, child_start: layout.child_indices.len() }
	pending_children = layout.pending_children.sublist({ start: 0, len: start_in_pending })
	({ ..layout, child_indices, pending_children }, node)
}

## Replace a closed box node, restore builder state, and attach it to its parent.
attach_closed_box : Layout(texture), U64, LayoutNode(texture), Stack(LayoutFrame) -> Try(Layout(texture), [OutOfBounds, ..])
attach_closed_box = |layout, box_idx, node, stack| {
	nodes = layout.nodes.set(box_idx, node)?
	closed = { ..layout, nodes, stack }
	match node.placement {
		Normal => {
			next = attach_child(closed, box_idx)?
			if node.parent == NoParent {
				Ok({ ..next, root_indices: next.root_indices.append(box_idx) })
			} else {
				Ok(next)
			}
		}
		Floating(_) => {
			parent_stack = if closed.stack.len() > 0 increment_top_child_offset(closed.stack)? else closed.stack
			Ok({
				..closed,
				stack: parent_stack,
				root_indices: closed.root_indices.append(box_idx),
			})
		}
	}
}

## Finalize a box and attach it to its parent.
close_box : Layout(texture) -> Try(Layout(texture), [OutOfBounds, UnmatchedCloseBox, InternalError, ..])
close_box = |layout| {
	{ node_index, node, stack } = pop_open_box(layout)?
	(layout_ranged, node_with_child_range) = finalize_child_range(layout, node)
	intrinsic = Solver.box_intrinsic_size(node_with_child_range, get_box_layout(node_with_child_range)?, layout_ranged.nodes, layout_ranged.child_indices)?
	node_with_intrinsic = { ..node_with_child_range, intrinsic }
	attach_closed_box(layout_ranged, node_index, node_with_intrinsic, stack)
}

build_text_layout : Str, Text.Config, TextMeasureCache.Entry -> TextLayout
build_text_layout = |content, config, measured| {
	line_height = Text.apply_line_height(config, measured.natural_line_height)
	lines = Text.wrap(content, config, measured.space_width, line_height, measured.preferred_width, measured.words)
	preferred = {
		w: Text.wrapped_width(lines),
		h: Text.wrapped_height(line_height, lines),
	}
	min_width = match config.wrap {
		Words => measured.min_width
		Newlines => preferred.w
		None => preferred.w
	}
	{ line_height, lines, preferred, min_width }
}

build_text_node_data : Layout(texture), Font, Text.Config, TextLayout -> TextNodeData
build_text_node_data = |layout, font, config, text_layout| {
	{
		content_index: layout.text_contents.len(),
		font,
		config,
		line_height: text_layout.line_height,
		wrap_width: text_layout.preferred.w,
		min_width: text_layout.min_width,
		lines_start: layout.text_lines.len(),
		lines_count: text_layout.lines.len(),
	}
}

add_text : Layout(texture), NodeId, Str -> Try(Layout(texture), LayoutError)
add_text = |layout, node_id, content| {
	idx = layout.nodes.len()
	resolved_text = layout.stack.top().map_ok(|frame| frame.text).ok_or(layout.root_text)
	text_config = resolved_text.config
	font = resolved_text.font
	(text_cache, text_measure) = layout.text_cache.get_or_create(content, text_config, font)
	var $layout = layout
	$layout = { ..$layout, text_cache }
	text_layout = build_text_layout(content, text_config, text_measure)
	text_data = build_text_node_data($layout, resolved_text.font, text_config, text_layout)
	node = {
		id: node_id,
		kind: TextNode(text_data),
		parent: parent_from_stack($layout),
		child_start: 0,
		child_count: 0,
		intrinsic: text_layout.preferred,
		size: { w: 0, h: 0 },
		content_size: text_layout.preferred,
		scroll_offset: { x: 0, y: 0 },
		position: { x: 0, y: 0 },
		sizing_w: Fixed(text_layout.preferred.w),
		sizing_h: Fixed(text_layout.preferred.h),
		placement: Normal,
	}
	$layout = register_node_id($layout, node_id, idx)?
	attach_child(
		{
			..$layout,
			nodes: $layout.nodes.append(node),
			text_contents: $layout.text_contents.append(content),
			text_lines: $layout.text_lines.concat(text_layout.lines),
		},
		idx,
	)
}

wrap_text_nodes : Layout(texture) -> Try(Layout(texture), LayoutError)
wrap_text_nodes = |layout| {
	var $nodes = layout.nodes
	var $lines = []
	for i in 0..<layout.nodes.len() {
		node = $nodes.get(i)?
		match node.kind {
			TextNode(text_data) => {
				content = layout.text_contents.get(text_data.content_index)?
				measured = layout.text_cache.get(content, text_data.font.handle, text_data.config).map_err(|_| InternalError)?
				wrap_width = text_wrap_width($nodes, node)?
				lines_start = $lines.len()
				wrapped = Text.wrap(content, text_data.config, measured.space_width, text_data.line_height, wrap_width, measured.words)
				updated_data = { ..text_data, wrap_width, lines_start, lines_count: wrapped.len() }
				$nodes = $nodes.set(i, { ..node, kind: TextNode(updated_data) })?
				$lines = $lines.concat(wrapped)
			}
			_ => {}
		}
	}
	Ok({ ..layout, nodes: $nodes, text_lines: $lines })
}

text_wrap_width : List(LayoutNode(texture)), LayoutNode(texture) -> Try(F32, [OutOfBounds, ..])
text_wrap_width = |nodes, node| {
	constrain_text_wrap_width(nodes, node.parent, node.size.w)
}

constrain_text_wrap_width : List(LayoutNode(texture)), ParentIndex, F32 -> Try(F32, [OutOfBounds, ..])
constrain_text_wrap_width = |nodes, parent_ref, width| {
	match parent_ref {
		NoParent => Ok(width)
		Parent(parent_idx) => {
			parent = nodes.get(parent_idx)?
			next_width = match parent.kind {
				BoxNode(box) => {
					inner = parent.size.w - box.layout.pad.left - box.layout.pad.right
					if inner > 0 and width > inner {
						inner
					} else {
						width
					}
				}
				_ => width
			}
			constrain_text_wrap_width(nodes, parent.parent, next_width)
		}
	}
}

refresh_intrinsics : Layout(texture) -> Try(Layout(texture), [OutOfBounds, ..])
refresh_intrinsics = |layout| {
	var $nodes = layout.nodes
	node_count = $nodes.len()
	for offset in 0..<node_count {
		i = node_count - 1 - offset
		node = $nodes.get(i)?
		match node.kind {
			TextNode(text_data) => {
				lines = layout.text_lines.sublist({ start: text_data.lines_start, len: text_data.lines_count })
				height = Text.wrapped_height(text_data.line_height, lines)
				width = text_data.wrap_width
				updated_node = {
					..node,
					intrinsic: { w: width, h: height },
					size: { w: width, h: height },
					sizing_w: Fixed(width),
					sizing_h: Fixed(height),
				}
				$nodes = $nodes.set(i, updated_node)?
			}
			BoxNode(box) => {
				intrinsic = Solver.box_intrinsic_size(node, box.layout, $nodes, layout.child_indices)?
				$nodes = $nodes.set(i, { ..node, intrinsic })?
			}
			_ => {}
		}
	}
	Ok({ ..layout, nodes: $nodes })
}

add_image : Layout(TextureLike(fields)), NodeId, TextureLike(fields) -> Try(Layout(TextureLike(fields)), [OutOfBounds, DuplicateNodeId, ..])
add_image = |layout, id, texture| {
	idx = layout.nodes.len()
	measured = { w: texture.width, h: texture.height }
	parent = parent_from_stack(layout)
	image_data : ImageNodeData(TextureLike(fields))
	image_data = {
		texture: texture,
	}
	node = {
		id: id,
		kind: ImageNode(image_data),
		parent,
		child_start: 0,
		child_count: 0,
		intrinsic: measured,
		size: { w: 0, h: 0 },
		content_size: measured,
		scroll_offset: { x: 0, y: 0 },
		position: { x: 0, y: 0 },
		sizing_w: Grow({}),
		sizing_h: Grow({}),
		placement: Normal,
	}
	layout_with_id = register_node_id(layout, id, idx)?
	attach_child(
		{
			..layout_with_id,
			nodes: layout_with_id.nodes.append(node),
		},
		idx,
	)
}

get_box_layout : LayoutNode(texture) -> Try(Element.LayoutConfig, [InternalError, ..])
get_box_layout = |node| match node.kind {
	BoxNode(box) => Ok(box.layout)
	_ => Err(InternalError)
}

# --- Floating Root Placement ---

## Size one root axis against either the viewport or its attachment target.
size_root_sublayout_axis : Layout(texture), U64, LayoutTypes.Axis, Size -> Try(Layout(texture), LayoutError)
size_root_sublayout_axis = |layout, root_index, axis, screen| {
	root = layout.nodes.get(root_index)?
	available = match root.placement {
		Normal => screen
		Floating(config) => Floating.target_bounds(layout.nodes, layout.node_ids, config.target, screen)?.size
	}
	nodes = Solver.solve_root_size_axis(
		layout.nodes,
		layout.child_indices,
		root_index,
		axis,
		available,
	)?
	Ok({ ..layout, nodes })
}

## Position one root from the viewport or its already-positioned attachment target.
position_root_sublayout : Layout(texture), U64, Size -> Try(Layout(texture), LayoutError)
position_root_sublayout = |layout, root_index, screen| {
	root = layout.nodes.get(root_index)?
	position = match root.placement {
		Normal => { x: 0, y: 0 }
		Floating(config) => {
			target = Floating.target_bounds(layout.nodes, layout.node_ids, config.target, screen)?
			Floating.attached_position(root, target, config)
		}
	}
	nodes = Solver.solve_root_position(layout.nodes, layout.child_indices, root_index, position)?
	Ok({ ..layout, nodes })
}

## Resolve and stably sort every layout root by z-index.
roots_in_z_order : Layout(texture), Floating.ZOrder -> Try(List(Floating.RootLayer), LayoutError)
roots_in_z_order = |layout, z_order| {
	Floating.roots_in_z_order(layout.nodes, layout.node_ids, layout.root_indices, z_order)
}

# --- Hit Testing ---

## Return a layout node's solved bounds.
layout_node_bounds : LayoutNode(texture) -> Bounds
layout_node_bounds = |node| { position: node.position, size: node.size }

## Return the bounds painted by the node itself. Floating expansion changes
## the root's painted rectangle and clipping scope, so it is applied before
## descendant bounds are folded into the subtree result.
node_own_paint_bounds : LayoutNode(texture) -> Bounds
node_own_paint_bounds = |node| {
	bounds = layout_node_bounds(node)
	match node.placement {
		Normal => bounds
		Floating(config) => bounds.expand(config.expand)
	}
}

## Compute paint bounds and per-box scissor need in one reverse pass.
## `needs_clip[i]` is true when the box at `i` has overflow != Visible
## and any direct child's paint escapes its own bounds. This is exactly
## the condition that previously required `children_escape_bounds` in the
## renderer, but now it is produced together with `paint_bounds` so the
## renderer can decide `with_scissor` in O(1).
compute_layout_paint_data : Layout(texture) -> Try({ paint_bounds : List(Bounds), needs_clip : List(Bool) }, Layout.LayoutError)
compute_layout_paint_data = |layout| {
	node_count = layout.nodes.len()
	var $paint_bounds = layout.nodes.map(node_own_paint_bounds)
	var $needs_clip = List.repeat(Bool.False, node_count)

	for offset in 0..<node_count {
		index = node_count - 1 - offset
		node = layout.nodes.get(index)?
		own_bounds = node_own_paint_bounds(node)
		var $subtree_bounds = own_bounds
		var $needs = Bool.False

		for child_offset in 0..<node.child_count {
			child_index = layout.child_indices.get(node.child_start + child_offset)?
			child_bounds_result = if child_index <= index {
				Err(InternalError)
			} else {
				$paint_bounds.get(child_index)
			}
			child_bounds = child_bounds_result?
			escaping = match node.kind {
				BoxNode(box) => if box.overflow.x != Visible or box.overflow.y != Visible {
					!child_bounds.is_empty() and !own_bounds.contains_bounds(child_bounds)
				} else {
					Bool.False
				}
				_ => Bool.False
			}
			if escaping {
				$needs = Bool.True
			}
			visible_child_bounds = match node.kind {
				BoxNode(box) => if box.overflow.x != Visible or box.overflow.y != Visible {
					own_bounds.intersection(child_bounds)
				} else {
					child_bounds
				}
				_ => child_bounds
			}

			if !visible_child_bounds.is_empty() {
				$subtree_bounds = $subtree_bounds.union(visible_child_bounds)
			}
		}

		$paint_bounds = $paint_bounds.set(index, $subtree_bounds)?
		node_needs = match node.kind {
			BoxNode(box) => (box.overflow.x != Visible or box.overflow.y != Visible) and $needs
			_ => Bool.False
		}
		$needs_clip = $needs_clip.set(index, node_needs)?
	}

	Ok({ paint_bounds: $paint_bounds, needs_clip: $needs_clip })
}

## Return the topmost box hit at a point.
hit_index_at : Layout(texture), Pos -> Try([Hit(U64), NoHit], LayoutError)
hit_index_at = |layout, point| {
	hits = hit_indices_at(layout, point)?
	match hits.get(0) {
		Ok(index) => Ok(Hit(index))
		Err(_) => Ok(NoHit)
	}
}

## Collect root hits until a capturing floating root blocks lower roots.
hit_indices_at : Layout(texture), Pos -> Try(List(U64), LayoutError)
hit_indices_at = |layout, point| {
	var $hits = []
	var $captured = Bool.False
	for root in roots_in_z_order(layout, FrontToBack)? {
		if !$captured {
			inside_clip = match root.clip {
				Unclipped => Bool.True
				Clipped(bounds) => bounds.contains(point)
			}
			if inside_clip {
				match hit_sublayout(layout.nodes, layout.child_indices, root.index, point, root.index, root.expand)? {
					NoHit => {}
					Hit(index) => {
						$hits = $hits.append(index)
						if root.capture == Capture {
							$captured = Bool.True
						}
					}
				}
			}
		}
	}
	Ok($hits)
}

## Find the deepest hit box within one root sublayout.
hit_sublayout : List(LayoutNode(texture)), List(U64), U64, Pos, U64, Size -> Try([Hit(U64), NoHit], LayoutError)
hit_sublayout = |nodes, child_indices, index, point, root_index, root_expand| {
	node = nodes.get(index)?
	var $result = NoHit
	for offset in 0..<node.child_count {
		child_offset = node.child_count - 1 - offset
		child_index = child_indices.get(node.child_start + child_offset)?
		if $result == NoHit {
			$result = hit_sublayout(nodes, child_indices, child_index, point, root_index, root_expand)?
		}
	}
	final_result = if $result == NoHit {
		match node.kind {
			BoxNode(_) => {
				inside = if index == root_index {
					root = nodes.get(root_index)?
					expand = match root.placement {
						Floating(_) => root_expand
						Normal => { w: 0, h: 0 }
					}
					layout_node_bounds(node).expand(expand).contains(point)
				} else {
					layout_node_bounds(node).contains(point)
				}
				visible = visible_through_ancestors(nodes, point, node.parent)?
				if inside and visible Hit(index) else NoHit
			}
			_ => NoHit
		}
	} else {
		$result
	}
	Ok(final_result)
}

## Check whether a point lies inside every clipping ancestor.
visible_through_ancestors : List(LayoutNode(texture)), Pos, ParentIndex -> Try(Bool, [OutOfBounds, ..])
visible_through_ancestors = |nodes, point, parent| match parent {
	NoParent => Ok(Bool.True)
	Parent(index) => {
		ancestor = nodes.get(index)?
		visible_here = match ancestor.kind {
			BoxNode(box) => if box.overflow.x != Visible or box.overflow.y != Visible layout_node_bounds(ancestor).contains(point) else Bool.True
			_ => Bool.True
		}
		if visible_here visible_through_ancestors(nodes, point, ancestor.parent) else Ok(Bool.False)
	}
}

collect_box_ancestor_ids : List(LayoutNode(texture)), U64, List(U64) -> Try(List(U64), LayoutError)
collect_box_ancestor_ids = |nodes, node_index, acc| {
	node = nodes.get(node_index)?
	next_acc = match node.kind {
		BoxNode(_) => acc.append(node.id)
		_ => acc
	}

	match node.parent {
		Parent(parent_index) => collect_box_ancestor_ids(nodes, parent_index, next_acc)
		NoParent => Ok(next_acc)
	}
}

is_image_node : LayoutNode(texture) -> Bool
is_image_node = |node| match node.kind {
	ImageNode(_) => Bool.True
	_ => Bool.False
}

## Check whether a node intersects every clipping ancestor.
node_intersects_ancestor_clips : List(LayoutNode(texture)), LayoutNode(texture), ParentIndex -> Try(Bool, [OutOfBounds, ..])
node_intersects_ancestor_clips = |nodes, node, parent| match parent {
	NoParent => Ok(Bool.True)
	Parent(index) => {
		ancestor = nodes.get(index)?
		intersects = match ancestor.kind {
			BoxNode(box) => if box.overflow.x != Visible or box.overflow.y != Visible {
				layout_node_bounds(node).intersects(layout_node_bounds(ancestor))
			} else {
				Bool.True
			}
			_ => Bool.True
		}
		if intersects node_intersects_ancestor_clips(nodes, node, ancestor.parent) else Ok(Bool.False)
	}
}

## TESTS ##

fixed_cfg : F32, F32 -> Element.BoxConfig
fixed_cfg = |w, h| {
	Element.style
		.width(Fixed(w))
		.height(Fixed(h))
		.child_align({ x: Start, y: Start })
}

build_row : Element.BoxConfig, List(Element.BoxConfig) -> Try(Layout(texture), LayoutError)
build_row = |root_cfg, child_cfgs| {
	var $layout = Layout.test_layout()
	$layout = open_box($layout, Auto, root_cfg)?
	for child_cfg in child_cfgs {
		$layout = open_box($layout, Auto, child_cfg)?
		$layout = close_box($layout)?
	}
	close_box($layout)
}

## Build a root box with flat child boxes and solve it against a screen.
build_and_solve : Element.BoxConfig, List(Element.BoxConfig), Size -> Try(Layout(texture), LayoutError)
build_and_solve = |root_cfg, child_cfgs, screen| {
	tree = build_row(root_cfg, child_cfgs)?
	tree.solve(screen)
}

## Build a solved vertical scroll container for layout tests.
build_scroll_column : Element.ElementId, LayoutTypes.Pos, Element.Overflow, F32, List(F32) -> Try(Layout(texture), LayoutError)
build_scroll_column = |id, offset, overflow_y, viewport_h, child_heights| {
	root_cfg = fixed_cfg(100, viewport_h)
		.direction(Col)
		.pad(5, 7, 11, 3)
		.gap(4)
		.overflow(Hidden, overflow_y)
	var $layout = Layout.test_layout()
	$layout = open_box_with_scroll($layout, id, root_cfg, offset)?
	for child_height in child_heights {
		$layout = open_box($layout, Auto, fixed_cfg(90, child_height))?
		$layout = close_box($layout)?
	}
	$layout = close_box($layout)?
	$layout.solve({ w: 200, h: 200 })
}

## A fixed vertical viewport keeps the complete content measurement, including
## padding and gaps, even when the content is taller than the viewport.
expect {
	match build_scroll_column(Id("measure-scroll"), { x: 0, y: 0 }, Scroll, 60, [20, 30, 40]) {
		Ok(layout) => match layout.nodes.get(0) {
			Ok(root) => root.size.h == 60 and root.content_size == { w: 100, h: 114 }
			Err(_) => Bool.False
		}
		Err(_) => Bool.False
	}
}

## A retained vertical offset moves children without changing their dimensions.
expect {
	match build_scroll_column(Id("position-scroll"), { x: 0, y: -20 }, Scroll, 60, [20, 30]) {
		Ok(layout) => match (layout.nodes.get(0), layout.nodes.get(1)) {
			(Ok(root), Ok(child)) => child.position.y == root.position.y + 5 - 20
				and child.size == { w: 90, h: 20 }
					and child.intrinsic == { w: 90, h: 20 }
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

## Rebuilding a stable-ID scroll container retains the supplied scroll offset.
expect {
	first = build_scroll_column(Id("persistent-scroll"), { x: 0, y: -12 }, Scroll, 60, [30, 30, 30])
	second = build_scroll_column(Id("persistent-scroll"), { x: 0, y: -12 }, Scroll, 60, [30, 30, 30])
	match (first, second) {
		(Ok(layout_a), Ok(layout_b)) => match (layout_a.nodes.get(0), layout_b.nodes.get(0), layout_a.nodes.get(1), layout_b.nodes.get(1)) {
			(Ok(root_a), Ok(root_b), Ok(child_a), Ok(child_b)) =>
				root_a.id == root_b.id
					and root_b.scroll_offset.y == -12
						and child_a.position.y == child_b.position.y
			_ => Bool.False
		}
		_ => Bool.False
	}
}

## A partially visible child remains hittable only through its clipped ancestor.
expect {
	match build_scroll_column(Id("hit-scroll"), { x: 0, y: -20 }, Scroll, 60, [40, 40]) {
		Ok(layout) => {
			child = layout.nodes.get(1)?
			visible_hit = match layout.hit_test({ x: 10, y: 2 }) {
				Ok(Hit(id)) => id == child.id
				_ => Bool.False
			}
			clipped_hit = match layout.hit_test({ x: 10, y: -2 }) {
				Ok(NoHit) => Bool.True
				_ => Bool.False
			}
			visible_hit and clipped_hit
		}
		Err(_) => Bool.False
	}
}

## Clipping overflow with an escaping descendant requires a host scissor scope.
expect {
	root_cfg = fixed_cfg(100, 60)
		.direction(Col)
		.background(Color.white)
		.border({ color: Color.black, left: 2, right: 2, top: 2, bottom: 2 })
		.overflow(Hidden, Scroll)
	child_cfg = fixed_cfg(90, 80).background(Color.gray).overflow(Visible, Visible)
	match build_and_solve(root_cfg, [child_cfg], { w: 200, h: 200 }) {
		Ok(layout) => {
			root = layout.nodes.get(0)?
			child = layout.nodes.get(1)?
			match root.kind {
				BoxNode(box) => box.overflow.x != Visible
					and box.overflow.y != Visible
						and layout_node_bounds(root) == { position: { x: 0, y: 0 }, size: { w: 100, h: 60 } }
							and !layout_node_bounds(root).contains_bounds(layout_node_bounds(child))
				_ => Bool.False
			}
		}
		Err(_) => Bool.False
	}
}

test_text_cfg : Element.TextWrap -> Element.BoxConfig
test_text_cfg = |wrap| {
	Element.style
		.width(Fixed(4))
		.height(Fit({}))
		.direction(Col)
		.child_align({ x: Start, y: Start })
		.font_size(10)
		.spacing(0)
		.line_height(10)
		.text_wrap(wrap)
}

test_button_cfg : Element.BoxConfig
test_button_cfg = {
	Element.style
		.width(Fit({}))
		.height(Fit({}))
		.pad(18, 18, 18, 18)
		.child_align({ x: Center, y: Center })
		.direction(Row)
		.font_size(24)
}

test_align_text_cfg : Element.TextAlign -> Element.BoxConfig
test_align_text_cfg = |align| {
	Element.style
		.width(Fixed(10))
		.height(Fit({}))
		.direction(Col)
		.child_align({ x: Start, y: Start })
		.font_size(10)
		.spacing(0)
		.line_height(10)
		.text_align(align)
		.text_wrap(Words)
}

test_word : U64, U64, F32 -> Text.Word
test_word = |start, len, width| { start, len, width, is_newline: Bool.False }

test_newline : U64 -> Text.Word
test_newline = |start| { start, len: 1, width: 0, is_newline: Bool.True }

seed_test_measurement : Layout(texture), Str, Font, Text.Config, F32, F32, List(Text.Word) -> Layout(texture)
seed_test_measurement = |layout, content, font, config, preferred_width, line_height, words| {
	entry : TextMeasureCache.Entry
	entry = {
		preferred_width,
		natural_line_height: line_height,
		min_width: preferred_width,
		space_width: 1,
		words,
		line_count: 1,
		contains_newlines: Bool.False,
		generation: 0,
	}
	{ ..layout, text_cache: layout.text_cache.insert(content, font.handle, config, entry) }
}

add_test_text : Layout(texture), Str, F32, List(Text.Word) -> Try(Layout(texture), LayoutError)
add_test_text = |layout, content, preferred_w, words| {
	idx = layout.nodes.len()
	node_id = next_auto_node_id(layout)?
	resolved_text = layout.stack.top().map_ok(|frame| frame.text).ok_or(layout.root_text)
	text_cfg = resolved_text.config
	parent = parent_from_stack(layout)
	content_index = layout.text_contents.len()
	lines_start = layout.text_lines.len()
	lines = Text.wrap(content, text_cfg, 1, 10, preferred_w, words)
	node = {
		id: node_id,
		kind: TextNode({
			content_index,
			font: resolved_text.font,
			config: text_cfg,
			line_height: 10,
			wrap_width: preferred_w,
			min_width: preferred_w,
			lines_start,
			lines_count: lines.len(),
		}),
		parent,
		child_start: 0,
		child_count: 0,
		intrinsic: { w: preferred_w, h: 10 },
		size: { w: 0, h: 0 },
		content_size: { w: 0, h: 0 },
		scroll_offset: { x: 0, y: 0 },
		position: { x: 0, y: 0 },
		sizing_w: Fixed(preferred_w),
		sizing_h: Fixed(10),
		placement: Normal,
	}
	layout_with_measurement = seed_test_measurement(layout, content, resolved_text.font, text_cfg, preferred_w, 10, words)
	layout_with_id = register_node_id(layout_with_measurement, node_id, idx)?
	attach_child(
		{
			..layout_with_id,
			nodes: layout_with_id.nodes.append(node),
			text_contents: layout_with_id.text_contents.append(content),
			text_lines: layout_with_id.text_lines.concat(lines),
		},
		idx,
	)
}

add_test_text_with_line_height : Layout(texture), Str, F32, F32, List(Text.Word) -> Try(Layout(texture), LayoutError)
add_test_text_with_line_height = |layout, content, preferred_w, line_h, words| {
	idx = layout.nodes.len()
	node_id = next_auto_node_id(layout)?
	resolved_text = layout.stack.top().map_ok(|frame| frame.text).ok_or(layout.root_text)
	text_cfg = resolved_text.config
	parent = parent_from_stack(layout)
	content_index = layout.text_contents.len()
	lines_start = layout.text_lines.len()
	lines = Text.wrap(content, text_cfg, 1, line_h, preferred_w, words)
	node = {
		id: node_id,
		kind: TextNode({
			content_index,
			font: resolved_text.font,
			config: text_cfg,
			line_height: line_h,
			wrap_width: preferred_w,
			min_width: preferred_w,
			lines_start,
			lines_count: lines.len(),
		}),
		parent,
		child_start: 0,
		child_count: 0,
		intrinsic: { w: preferred_w, h: line_h },
		size: { w: 0, h: 0 },
		content_size: { w: 0, h: 0 },
		scroll_offset: { x: 0, y: 0 },
		position: { x: 0, y: 0 },
		sizing_w: Fixed(preferred_w),
		sizing_h: Fixed(line_h),
		placement: Normal,
	}
	layout_with_measurement = seed_test_measurement(layout, content, resolved_text.font, text_cfg, preferred_w, line_h, words)
	layout_with_id = register_node_id(layout_with_measurement, node_id, idx)?
	attach_child(
		{
			..layout_with_id,
			nodes: layout_with_id.nodes.append(node),
			text_contents: layout_with_id.text_contents.append(content),
			text_lines: layout_with_id.text_lines.concat(lines),
		},
		idx,
	)
}

build_text_test_layout : Element.BoxConfig, Str, F32, List(Text.Word), Size -> Try(Layout(texture), LayoutError)
build_text_test_layout = |root_cfg, content, preferred_w, words, screen| {
	var $layout = Layout.test_layout()
	$layout = open_box($layout, Auto, root_cfg)?
	$layout = add_test_text($layout, content, preferred_w, words)?
	$layout = close_box($layout)?
	$layout.solve(screen)
}

build_button_text_layout : Str, F32, F32, List(Text.Word), Size -> Try(Layout(texture), LayoutError)
build_button_text_layout = |content, preferred_w, line_h, words, screen| {
	var $layout = Layout.test_layout()
	$layout = open_box($layout, Auto, test_button_cfg)?
	$layout = add_test_text_with_line_height($layout, content, preferred_w, line_h, words)?
	$layout = close_box($layout)?
	$layout.solve(screen)
}

build_nested_fit_text_layout : Element.BoxConfig, Str, F32, List(Text.Word), Size -> Try(Layout(texture), LayoutError)
build_nested_fit_text_layout = |root_cfg, content, preferred_w, words, screen| {
	var $layout = Layout.test_layout()
	$layout = open_box($layout, Auto, root_cfg)?
	$layout = open_box($layout, Auto, Element.style.width(Fit({})).height(Fit({})).direction(Col).child_align({ x: Start, y: Start }))?
	$layout = add_test_text($layout, content, preferred_w, words)?
	$layout = close_box($layout)?
	$layout = close_box($layout)?
	$layout.solve(screen)
}

text_line_count : Layout(texture), U64 -> U64
text_line_count = |layout, index| {
	match layout.nodes.get(index) {
		Ok(node) => match node.kind {
			TextNode(text_data) => text_data.lines_count
			_ => 0
		}
		Err(_) => 0
	}
}

node_height : Layout(texture), U64 -> F32
node_height = |layout, index| {
	match layout.nodes.get(index) {
		Ok(node) => node.size.h
		Err(_) => 0
	}
}

node_pos_y : Layout(texture), U64 -> F32
node_pos_y = |layout, index| {
	match layout.nodes.get(index) {
		Ok(node) => node.position.y
		Err(_) => 0
	}
}

text_line_positions : Layout(texture) -> List({ x : F32, y : F32, text : Str })
text_line_positions = |layout| {
	compute = || {
		node = layout.nodes.get(1)?
		text_data_result = match node.kind {
			TextNode(text_data) => Ok(text_data)
			_ => Err(InternalError)
		}
		text_data = text_data_result?
		content = layout.text_contents.get(text_data.content_index)?
		var $positions = []
		node_bounds = layout_node_bounds(node)
		for line_offset in 0..<text_data.lines_count {
			line = layout.text_lines.get(text_data.lines_start + line_offset)?
			line_bounds = Text.line_bounds(node_bounds.flatten(), text_data.config, line, line_offset)
			$positions = $positions.append({
				x: line_bounds.position.x,
				y: line_bounds.position.y,
				text: Text.line_text(content, line),
			})
		}
		Ok($positions)
	}
	match compute() {
		Ok(positions) => positions
		Err(_) => []
	}
}

node_width : Layout(texture), U64 -> F32
node_width = |layout, index| {
	match layout.nodes.get(index) {
		Ok(node) => node.size.w
		Err(_) => 0
	}
}

node_paint_bounds : Layout(texture), U64 -> Bounds
node_paint_bounds = |layout, index| {
	match layout.compute_paint_bounds() {
		Ok(bounds) => match bounds.get(index) {
			Ok(value) => value
			Err(_) => { position: { x: 0, y: 0 }, size: { w: 0, h: 0 } }
		}
		Err(_) => { position: { x: 0, y: 0 }, size: { w: 0, h: 0 } }
	}
}

## A leaf's paint bounds equal its solved presentation bounds.
expect {
	build = || {
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Auto, fixed_cfg(10, 20))?
		$layout = close_box($layout)?
		$layout.solve({ w: 100, h: 100 })
	}

	match build() {
		Ok(layout) => node_paint_bounds(layout, 0) == { position: { x: 0, y: 0 }, size: { w: 10, h: 20 } }
		Err(_) => Bool.False
	}
}

## An unclipped parent includes paint from a child escaping its own bounds.
expect {
	build = || {
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Auto, fixed_cfg(10, 10).overflow(Visible, Visible))?
		$layout = open_box($layout, Auto, fixed_cfg(5, 5))?
		$layout = close_box($layout)?
		$layout = close_box($layout)?
		$layout = $layout.solve({ w: 100, h: 100 })?
		child = $layout.nodes.get(1)?
		nodes = $layout.nodes.set(1, { ..child, position: { x: 15, y: 2 } })?
		Ok({ ..$layout, nodes })
	}

	match build() {
		Ok(layout) => node_paint_bounds(layout, 0) == { position: { x: 0, y: 0 }, size: { w: 20, h: 10 } }
		Err(_) => Bool.False
	}
}

## A clipping parent excludes child paint outside its own bounds.
expect {
	build = || {
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Auto, fixed_cfg(10, 10).overflow(Hidden, Hidden))?
		$layout = open_box($layout, Auto, fixed_cfg(5, 5))?
		$layout = close_box($layout)?
		$layout = close_box($layout)?
		$layout = $layout.solve({ w: 100, h: 100 })?
		child = $layout.nodes.get(1)?
		nodes = $layout.nodes.set(1, { ..child, position: { x: 15, y: 2 } })?
		Ok({ ..$layout, nodes })
	}

	match build() {
		Ok(layout) => node_paint_bounds(layout, 0) == { position: { x: 0, y: 0 }, size: { w: 10, h: 10 } }
		Err(_) => Bool.False
	}
}

## Conservative subtree paint bounds keep a visible-overflow child from being
## culled with its offscreen parent.
expect {
	build = || {
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Auto, fixed_cfg(10, 10).overflow(Visible, Visible))?
		$layout = open_box($layout, Auto, fixed_cfg(5, 5).background(Color.white))?
		$layout = close_box($layout)?
		$layout = close_box($layout)?
		$layout = $layout.solve({ w: 100, h: 100 })?
		root = $layout.nodes.get(0)?
		child = $layout.nodes.get(1)?
		var $nodes = $layout.nodes.set(0, { ..root, position: { x: -20, y: 0 } })?
		$nodes = $nodes.set(1, { ..child, position: { x: 1, y: 2 } })?
		updated = { ..$layout, nodes: $nodes }
		paint_bounds = updated.compute_paint_bounds()?
		Ok(paint_bounds.get(0)?)
	}

	match build() {
		Ok(bounds) => LayoutTypes.visible_region(
			bounds,
			{ position: { x: 0, y: 0 }, size: { w: 100, h: 100 } },
			Unclipped,
		) != Culled
		_ => Bool.False
	}
}

## A clipping offscreen parent safely culls the same escaped child.
expect {
	build = || {
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Auto, fixed_cfg(10, 10).overflow(Hidden, Hidden))?
		$layout = open_box($layout, Auto, fixed_cfg(5, 5).background(Color.white))?
		$layout = close_box($layout)?
		$layout = close_box($layout)?
		$layout = $layout.solve({ w: 100, h: 100 })?
		root = $layout.nodes.get(0)?
		child = $layout.nodes.get(1)?
		var $nodes = $layout.nodes.set(0, { ..root, position: { x: -20, y: 0 } })?
		$nodes = $nodes.set(1, { ..child, position: { x: 1, y: 2 } })?
		updated = { ..$layout, nodes: $nodes }
		paint_bounds = updated.compute_paint_bounds()?
		Ok(paint_bounds.get(0)?)
	}

	match build() {
		Ok(bounds) => LayoutTypes.visible_region(
			bounds,
			{ position: { x: 0, y: 0 }, size: { w: 100, h: 100 } },
			Unclipped,
		) == Culled
		_ => Bool.False
	}
}

## Closing boxes should preserve DFS node order while building contiguous
## direct-child ranges in child_indices.
expect {
	cfg = Element.style
	build = || {
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Auto, cfg)? # root: 0
		$layout = open_box($layout, Auto, cfg)? # first child: 1
		$layout = close_box($layout)?
		$layout = open_box($layout, Auto, cfg)? # second child: 2
		$layout = open_box($layout, Auto, cfg)? # grandchild: 3
		$layout = close_box($layout)?
		$layout = close_box($layout)?
		$layout = close_box($layout)?
		Ok($layout)
	}

	match build() {
		Ok(layout) => match (layout.nodes.get(0), layout.nodes.get(2)) {
			(Ok(r), Ok(s)) => layout.child_indices == [3, 1, 2]
				and r.child_start == 1
					and r.child_count == 2
						and s.child_start == 0
							and s.child_count == 1
			_ => Bool.False
		}
		_ => Bool.False
	}
}

## Words wrapping breaks text into multiple line records after X sizing.
expect {
	words = [test_word(0, 3, 3), test_word(3, 3, 3), test_word(6, 2, 2)]
	match build_text_test_layout(test_text_cfg(Words), "aa bb cc", 8, words, { w: 100, h: 100 }) {
		Ok(layout) => text_line_count(layout, 1) == 3
		Err(_) => Bool.False
	}
}

## Repeated text nodes share one canonical cache entry.
expect {
	build = || {
		content = "same text"
		words = [test_word(0, 9, 9)]
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Auto, test_text_cfg(Words))?
		$layout = add_test_text($layout, content, 9, words)?
		$layout = add_test_text($layout, content, 9, words)?
		$layout = close_box($layout)?
		Ok($layout)
	}
	match build() {
		Ok(layout) => layout.text_cache.len() == 1
		Err(_) => Bool.False
	}
}

## Clearing frame-local text data retains recent canonical measurements.
expect {
	build = || {
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Auto, test_text_cfg(Words))?
		$layout = add_test_text($layout, "cached", 6, [test_word(0, 6, 6)])?
		$layout = close_box($layout)?
		Ok($layout.clear())
	}
	match build() {
		Ok(layout) => layout.text_contents.len() == 0
			and layout.text_lines.len() == 0
				and layout.text_cache.len() == 1
		Err(_) => Bool.False
	}
}

## A text node whose measurement was invalidated cannot be wrapped.
expect {
	build = || {
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Auto, test_text_cfg(Words))?
		$layout = add_test_text($layout, "missing", 7, [test_word(0, 7, 7)])?
		$layout = close_box($layout)?
		Ok({ ..$layout, text_cache: $layout.text_cache.reset() })
	}
	match build() {
		Ok(layout) => match layout.solve({ w: 100, h: 100 }) {
			Err(InternalError) => Bool.True
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

## A single long word wider than the wrap width stays one overflowing line.
expect {
	words = [test_word(0, 6, 6)]
	match build_text_test_layout(test_text_cfg(Words), "abcdef", 6, words, { w: 100, h: 100 }) {
		Ok(layout) => text_line_count(layout, 1) == 1
		Err(_) => Bool.False
	}
}

## A fit-height parent grows after child text wraps.
expect {
	words = [test_word(0, 3, 3), test_word(3, 3, 3), test_word(6, 2, 2)]
	match build_text_test_layout(test_text_cfg(Words), "aa bb cc", 8, words, { w: 100, h: 100 }) {
		Ok(layout) => match layout.nodes.get(0) {
			Ok(root) => root.size.h == 30
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

## Floating widths are resolved against their attachment target before text
## wrapping, matching Clay's per-axis floating sizing.
expect {
	words = [test_word(0, 3, 3), test_word(3, 3, 3), test_word(6, 2, 2)]
	target_cfg = fixed_cfg(4, 100)
	floating_cfg = Element.style
		.width(Grow({ min: 0, max: 1000 }))
		.height(Fit({ min: 0, max: 1000 }))
		.child_align({ x: Start, y: Start })
		.floating(Floating({ target: Parent, config: Element.default_floating_config }))
	build = || {
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Id("target"), target_cfg)?
		$layout = open_box($layout, Id("floating"), floating_cfg)?
		$layout = add_test_text($layout, "aa bb cc", 8, words)?
		$layout = close_box($layout)?
		$layout = close_box($layout)?
		$layout.solve({ w: 100, h: 100 })
	}

	match build() {
		Ok(layout) => node_width(layout, 1) == 4
			and node_height(layout, 1) == 30
				and text_line_count(layout, 2) == 3
		Err(_) => Bool.False
	}
}

## Multiple roots retain back-to-front z-order independently of declaration
## order.
expect {
	high_floating = {
		..Element.default_floating_config,
		z_index: 10,
	}
	low_floating = {
		..Element.default_floating_config,
		z_index: -10,
	}
	build = || {
		var $layout = Layout.test_layout()
		$layout = open_box(
			$layout,
			Id("terminal-high"),
			fixed_cfg(10, 10).background(Color.white).floating(Floating({ target: Root, config: high_floating })),
		)?
		$layout = close_box($layout)?
		$layout = open_box(
			$layout,
			Id("terminal-low"),
			fixed_cfg(10, 10).background(Color.gray).floating(Floating({ target: Root, config: low_floating })),
		)?
		$layout = close_box($layout)?
		$layout = $layout.solve({ w: 100, h: 100 })?
		roots_in_z_order($layout, BackToFront)
	}

	match build() {
		Ok([low, high]) => low.index == 1 and high.index == 0
		_ => Bool.False
	}
}

## Floating expansion is included exactly once in the root's computed paint
## bounds.
expect {
	floating_config = {
		..Element.default_floating_config,
		offset: { x: -15, y: 20 },
		expand: { w: 10, h: 5 },
	}
	cfg = fixed_cfg(10, 10)
		.floating(Floating({ target: Root, config: floating_config }))
	build = || {
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Id("paint-expanded"), cfg)?
		$layout = close_box($layout)?
		$layout.solve({ w: 100, h: 100 })
	}

	match build() {
		Ok(layout) => node_paint_bounds(layout, 0)
			== { position: { x: -25, y: 15 }, size: { w: 30, h: 20 } }
		Err(_) => Bool.False
	}
}

## Floating attachment dependencies are positioned before their dependents,
## regardless of declaration order or z-index.
expect {
	points = { element: LeftTop, target: RightTop }
	dependent_config = {
		..Element.default_floating_config,
		z_index: -10,
		attach_points: points,
	}
	anchor_config = {
		..Element.default_floating_config,
		z_index: 10,
		offset: { x: 30, y: 20 },
	}
	build = || {
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Id("dependency-root"), fixed_cfg(100, 100))?
		$layout = open_box(
			$layout,
			Id("dependent"),
			fixed_cfg(5, 5).floating(Floating({ target: Element(Id("anchor")), config: dependent_config })),
		)?
		$layout = close_box($layout)?
		$layout = open_box($layout, Id("anchor"), fixed_cfg(10, 10).floating(Floating({ target: Root, config: anchor_config })))?
		$layout = close_box($layout)?
		$layout = close_box($layout)?
		$layout.solve({ w: 100, h: 100 })
	}

	match build() {
		Ok(layout) => match (layout.nodes.get(1), layout.nodes.get(2)) {
			(Ok(dependent), Ok(anchor)) =>
				anchor.position == { x: 30, y: 20 } and dependent.position == { x: 40, y: 20 }
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

## Floating roots are sized once after their attachment target's root, even
## when a dependent is declared before its floating target.
expect {
	grow_width = Element.style
		.width(Grow({ min: 0, max: 1000 }))
		.height(Fixed(10))
	build = || {
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Id("size-order-root"), fixed_cfg(100, 100))?
		$layout = open_box($layout, Id("size-target"), fixed_cfg(30, 10))?
		$layout = close_box($layout)?
		$layout = open_box(
			$layout,
			Id("size-dependent"),
			grow_width.floating(Floating({ target: Element(Id("size-anchor")), config: Element.default_floating_config })),
		)?
		$layout = close_box($layout)?
		$layout = open_box(
			$layout,
			Id("size-anchor"),
			grow_width.floating(Floating({ target: Element(Id("size-target")), config: Element.default_floating_config })),
		)?
		$layout = close_box($layout)?
		$layout = close_box($layout)?
		$layout.solve({ w: 100, h: 100 })
	}

	match build() {
		Ok(layout) => match (layout.nodes.get(2), layout.nodes.get(3)) {
			(Ok(dependent), Ok(anchor)) => dependent.size.w == 30 and anchor.size.w == 30
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

## Passthrough floating roots contribute hover hits without hiding lower roots;
## capture stops traversal after the floating root is hit.
expect {
	build = |capture| {
		floating_config = {
			..Element.default_floating_config,
			z_index: 1,
			capture,
		}
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Id("capture-base"), fixed_cfg(100, 100))?
		$layout = open_box($layout, Id("capture-overlay"), fixed_cfg(100, 100).floating(Floating({ target: Root, config: floating_config })))?
		$layout = close_box($layout)?
		$layout = close_box($layout)?
		$layout.solve({ w: 100, h: 100 })
	}

	match (build(Passthrough), build(Capture)) {
		(Ok(passthrough_layout), Ok(capture_layout)) => {
			overlay = passthrough_layout.nodes.get(1)?
			base = passthrough_layout.nodes.get(0)?
			match (passthrough_layout.hover_path({ x: 5, y: 5 }), capture_layout.hover_path({ x: 5, y: 5 })) {
				(Ok([overlay_id, base_id]), Ok([captured_id])) =>
					overlay_id == overlay.id and base_id == base.id and captured_id == overlay.id
				_ => Bool.False
			}
		}
		_ => Bool.False
	}
}

## Text wraps against constrained ancestors even when its immediate Fit parent overflows.
expect {
	words = [test_word(0, 3, 3), test_word(3, 3, 3), test_word(6, 2, 2)]
	match build_nested_fit_text_layout(test_text_cfg(Words), "aa bb cc", 8, words, { w: 100, h: 100 }) {
		Ok(layout) => text_line_count(layout, 2) == 3 and node_width(layout, 1) == 4 and node_width(layout, 2) == 4
		Err(_) => Bool.False
	}
}

## Fit button height includes the measured text line height plus padding.
expect {
	words = [test_word(0, 9, 9)]
	match build_button_text_layout("click me", 9, 24, words, { w: 640, h: 420 }) {
		Ok(layout) => node_height(layout, 0) == 60 and node_height(layout, 1) == 24
		Err(_) => Bool.False
	}
}

## Centered button text is positioned inside the padded button bounds.
expect {
	words = [test_word(0, 9, 9)]
	match build_button_text_layout("click me", 9, 24, words, { w: 640, h: 420 }) {
		Ok(layout) => node_pos_y(layout, 1) == node_pos_y(layout, 0) + 18
		Err(_) => Bool.False
	}
}

## Explicit newlines create line breaks.
expect {
	words = [test_word(0, 2, 2), test_newline(2), test_word(3, 2, 2)]
	match build_text_test_layout(test_text_cfg(Words), "aa\nbb", 2, words, { w: 100, h: 100 }) {
		Ok(layout) => text_line_count(layout, 1) == 2
		Err(_) => Bool.False
	}
}

## Newlines mode ignores spaces as wrap opportunities.
expect {
	words = [test_word(0, 8, 8)]
	match build_text_test_layout(test_text_cfg(Newlines), "aa bb cc", 8, words, { w: 100, h: 100 }) {
		Ok(layout) => text_line_count(layout, 1) == 1
		Err(_) => Bool.False
	}
}

## Settled line placement applies line-height y offsets to wrapped text.
expect {
	words = [test_word(0, 3, 3), test_word(3, 3, 3), test_word(6, 2, 2)]
	match build_text_test_layout(test_text_cfg(Words), "aa bb cc", 8, words, { w: 100, h: 100 }) {
		Ok(layout) => {
			positions = text_line_positions(layout)
			match (positions.get(0), positions.get(1), positions.get(2)) {
				(Ok(a), Ok(b), Ok(c)) => positions.len() == 3
					and a.text == "aa"
						and b.text == "bb"
							and c.text == "cc"
								and a.y == 0
									and b.y == 10
										and c.y == 20
				_ => Bool.False
			}
		}
		Err(_) => Bool.False
	}
}

## Center text alignment uses each wrapped line width.
expect {
	words = [test_word(0, 8, 8), test_word(8, 4, 4)]
	match build_text_test_layout(test_align_text_cfg(Center), "aaaaaaa bbbb", 12, words, { w: 100, h: 100 }) {
		Ok(layout) => {
			positions = text_line_positions(layout)
			match (positions.get(0), positions.get(1)) {
				(Ok(a), Ok(b)) => positions.len() == 2 and a.x == 1.5 and b.x == 3
				_ => Bool.False
			}
		}
		Err(_) => Bool.False
	}
}

## Right text alignment uses each wrapped line width.
expect {
	words = [test_word(0, 8, 8), test_word(8, 4, 4)]
	match build_text_test_layout(test_align_text_cfg(Right), "aaaaaaa bbbb", 12, words, { w: 100, h: 100 }) {
		Ok(layout) => {
			positions = text_line_positions(layout)
			match (positions.get(0), positions.get(1)) {
				(Ok(a), Ok(b)) => positions.len() == 2 and a.x == 3 and b.x == 6
				_ => Bool.False
			}
		}
		Err(_) => Bool.False
	}
}

## None mode keeps embedded newlines as one raw render line.
expect {
	words = [test_word(0, 5, 5)]
	match build_text_test_layout(test_text_cfg(None), "aa\nbb", 5, words, { w: 100, h: 100 }) {
		Ok(layout) => text_line_count(layout, 1) == 1
		Err(_) => Bool.False
	}
}

## clear should reset all frame-local builder state before the next view build.
expect {
	cfg = Element.style
	build = || {
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Auto, cfg)?
		$layout = open_box($layout, Auto, cfg)?
		$layout = close_box($layout)?
		$layout = close_box($layout)?
		Ok($layout.clear())
	}

	match build() {
		Ok(layout) => layout.nodes.len() == 0
			and layout.text_contents.len() == 0
				and layout.text_lines.len() == 0
					and layout.child_indices.len() == 0
						and layout.pending_children.len() == 0
							and layout.stack.len() == 0
								and layout.root_indices.len() == 0
		Err(_) => Bool.False
	}
}

## Closing without an open box should be an error.
expect {
	match close_box(Layout.test_layout()) {
		Err(UnmatchedCloseBox) => Bool.True
		_ => Bool.False
	}
}

## Solving an empty layout should be a no-op.
expect {
	match Layout.test_layout().solve({ w: 100, h: 100 }) {
		Ok(layout) => layout.nodes.len() == 0
			and layout.text_contents.len() == 0
				and layout.text_lines.len() == 0
					and layout.child_indices.len() == 0
						and layout.stack.len() == 0
		Err(_) => Bool.False
	}
}

## Duplicate explicit IDs in one layout generation should be rejected.
expect {
	cfg = Element.style
	build = || {
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Id("shared"), cfg)?
		$layout = close_box($layout)?
		open_box($layout, Id("shared"), cfg)
	}

	match build() {
		Err(DuplicateNodeId) => Bool.True
		_ => Bool.False
	}
}

## Registered node IDs should resolve back to their current-frame node index.
expect {
	cfg = Element.style
	build = || {
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Id("root"), cfg)?
		node = $layout.nodes.get(0)?
		node_index = index_for_node_id($layout, node.id)?
		Ok(node_index)
	}

	match build() {
		Ok(0) => Bool.True
		_ => Bool.False
	}
}

## Hit and hover queries on an empty layout should return empty results.
expect {
	layout = Layout.test_layout()
	match (layout.hit_test({ x: 0, y: 0 }), layout.hover_path({ x: 0, y: 0 })) {
		(Ok(NoHit), Ok([])) => Bool.True
		_ => Bool.False
	}
}

## Hit testing should return the deepest/latest matching box.
expect {
	root_cfg = fixed_cfg(100, 100)
	child_cfg = fixed_cfg(50, 50)

	match build_and_solve(root_cfg, [child_cfg], { w: 100, h: 100 }) {
		Ok(layout) => {
			expected = layout.nodes.get(1)?
			match layout.hit_test({ x: 25, y: 25 }) {
				Ok(Hit(node_id)) => node_id == expected.id
				_ => Bool.False
			}
		}
		Err(_) => Bool.False
	}
}

## Hit testing outside every box should return NoHit.
expect {
	root_cfg = fixed_cfg(100, 100)

	match build_and_solve(root_cfg, [], { w: 100, h: 100 }) {
		Ok(layout) => match layout.hit_test({ x: 101, y: 50 }) {
			Ok(NoHit) => Bool.True
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

## Hit testing should include box boundaries.
expect {
	root_cfg = fixed_cfg(100, 100)

	match build_and_solve(root_cfg, [], { w: 100, h: 100 }) {
		Ok(layout) => {
			root = layout.nodes.get(0)?
			match layout.hit_test({ x: 100, y: 100 }) {
				Ok(Hit(node_id)) => node_id == root.id
				_ => Bool.False
			}
		}
		Err(_) => Bool.False
	}
}

## Overlapping sibling boxes should hit the latest matching sibling.
expect {
	root_cfg = fixed_cfg(100, 100)
	child_cfg = fixed_cfg(50, 50)

	match build_and_solve(root_cfg, [child_cfg, child_cfg], { w: 100, h: 100 }) {
		Ok(layout) => {
			second = layout.nodes.get(2)?
			match layout.hit_test({ x: 50, y: 25 }) {
				Ok(Hit(node_id)) => node_id == second.id
				_ => Bool.False
			}
		}
		Err(_) => Bool.False
	}
}

## Hit testing should ignore non-box nodes and return the containing box.
expect {
	texture = { width: 20, height: 20 }
	root_cfg = fixed_cfg(100, 100)
	build = || {
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Auto, root_cfg)?
		$layout = add_image($layout, 200, texture)?
		$layout = close_box($layout)?
		$layout.solve({ w: 100, h: 100 })
	}

	match build() {
		Ok(layout) => {
			root = layout.nodes.get(0)?
			image = layout.nodes.get(1)?
			match layout.hit_test({ x: 10, y: 10 }) {
				Ok(Hit(node_id)) => node_id == root.id and node_id != image.id
				_ => Bool.False
			}
		}
		Err(_) => Bool.False
	}
}

## Image nodes should fill the parent box's inner size.
expect {
	texture = { width: 1024, height: 1024 }
	root_cfg = Element.style
		.width(Fixed(300))
		.height(Fixed(300))
	build = || {
		var $tree = Layout.test_layout()
		$tree = open_box($tree, Auto, root_cfg)?
		$tree = add_image($tree, 200, texture)?
		$tree = close_box($tree)?
		$tree.solve({ w: 300, h: 300 })
	}

	match build() {
		Ok(tree) => {
			image = tree.nodes.get(1)?
			image.size.w == 300 and image.size.h == 300
		}
		Err(_) => Bool.False
	}
}

## Solving preserves image texture metadata and fills the parent bounds.
expect {
	texture = { width: 32, height: 16 }
	root_cfg = fixed_cfg(100, 50)
	build = || {
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Auto, root_cfg)?
		$layout = add_image($layout, 200, texture)?
		$layout = close_box($layout)?
		$layout.solve({ w: 100, h: 50 })
	}

	match build() {
		Ok(layout) => {
			image = layout.nodes.get(1)?
			match image.kind {
				ImageNode(image_data) => image.size.w == 100
					and image.size.h == 50
						and image_data.texture.width == 32
							and image_data.texture.height == 16
				_ => Bool.False
			}
		}
		_ => Bool.False
	}
}

## Hover paths should return node ancestors from deepest to shallowest.
expect {
	root_cfg = fixed_cfg(100, 100)
	child_cfg = fixed_cfg(50, 50)

	match build_and_solve(root_cfg, [child_cfg], { w: 100, h: 100 }) {
		Ok(layout) => {
			root = layout.nodes.get(0)?
			child = layout.nodes.get(1)?
			match layout.hover_path({ x: 25, y: 25 }) {
				Ok([child_id, root_id]) => child_id == child.id and root_id == root.id
				_ => Bool.False
			}
		}
		Err(_) => Bool.False
	}
}

## Extra closes after a balanced nested build should fail without corrupting the
## completed layout.
expect {
	cfg = Element.style
	build = || {
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Auto, cfg)?
		$layout = open_box($layout, Auto, cfg)?
		$layout = close_box($layout)?
		$layout = close_box($layout)?
		match close_box($layout) {
			Err(UnmatchedCloseBox) => Ok($layout)
			Ok(_) => Err(InternalError)
			Err(_) => Err(InternalError)
		}
	}

	match build() {
		Ok(layout) => layout.stack.len() == 0
			and layout.nodes.len() == 2
				and layout.child_indices == [1]
		Err(_) => Bool.False
	}
}

## Closing nested boxes with mixed child kinds should preserve direct-child
## ranges independently of DFS node order.
expect {
	texture = { width: 8, height: 9 }
	root_cfg = Element.style
		.width(Fit({ min: 0, max: 1000 }))
		.height(Fit({ min: 0, max: 1000 }))
		.child_align({ x: Start, y: Start })
	nested_cfg = Element.style
		.width(Fit({ min: 0, max: 1000 }))
		.height(Fit({ min: 0, max: 1000 }))
		.child_align({ x: Start, y: Start })
	build = || {
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Auto, root_cfg)? # root: 0
		$layout = add_image($layout, 100, texture)? # root child: 1
		$layout = open_box($layout, Auto, nested_cfg)? # root child: 2
		$layout = add_image($layout, 101, texture)? # nested child: 3
		$layout = close_box($layout)?
		$layout = close_box($layout)?
		Ok($layout)
	}

	match build() {
		Ok(layout) => match (layout.nodes.get(0), layout.nodes.get(2), layout.nodes.get(1), layout.nodes.get(3)) {
			(Ok(root), Ok(nested), Ok(image_a), Ok(image_b)) => layout.child_indices == [3, 1, 2]
				and root.child_start == 1
					and root.child_count == 2
						and nested.child_start == 0
							and nested.child_count == 1
								and is_image_node(image_a)
									and is_image_node(image_b)
										and root.intrinsic == { w: 16, h: 9 }
											and nested.intrinsic == { w: 8, h: 9 }
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

## A box with Auto should use the nearest ancestor's resolved text style.
expect {
	base_cfg = Element.style
	root_cfg = {
		..base_cfg,
		text: Font({ ..Element.default_text, font_size: 17, line_height: 21 }),
	}
	build = || {
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Auto, root_cfg)?
		$layout = open_box($layout, Auto, base_cfg)?
		Ok($layout.stack.top().map_ok(|frame| frame.text.config).ok_or($layout.root_text.config))
	}

	match build() {
		Ok(text_cfg) => text_cfg.font_size == 17 and text_cfg.line_height == 21
		Err(_) => Bool.False
	}
}

## Closing a Fit parent should compute intrinsic size from already-closed
## fixed-size children.
expect {
	root_cfg = Element.style
		.width(Fit({ min: 0, max: 1000 }))
		.height(Fit({ min: 0, max: 1000 }))
	child_cfg = fixed_cfg(10, 20)
	build = || {
		var $layout = Layout.test_layout()
		$layout = open_box($layout, Auto, root_cfg)?
		$layout = open_box($layout, Auto, child_cfg)?
		$layout = close_box($layout)?
		$layout = close_box($layout)?
		Ok($layout)
	}

	match build() {
		Ok(layout) => match layout.nodes.get(0) {
			Ok(root) => root.intrinsic == { w: 10, h: 20 }
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
		Ok(layout) => match (layout.nodes.get(0), layout.nodes.get(1), layout.nodes.get(2)) {
			(Ok(root), Ok(a), Ok(b)) => root.size == { w: 100, h: 40 }
				and a.size == { w: 10, h: 20 }
					and b.size == { w: 15, h: 30 }
						and a.position == { x: 0, y: 0 }
							and b.position == { x: 10, y: 0 }
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

## Parent padding and gap should offset row children from the content box
## and from each other.
expect {
	root_cfg = Element.style
		.width(Fixed(100))
		.height(Fixed(50))
		.direction(Row)
		.child_align({ x: Start, y: Start })
		.gap(3)
		.pad(7, 2, 4, 5)
	child_a = fixed_cfg(10, 10)
	child_b = fixed_cfg(20, 10)

	match build_and_solve(root_cfg, [child_a, child_b], { w: 100, h: 50 }) {
		Ok(layout) => match (layout.nodes.get(1), layout.nodes.get(2)) {
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
	root_cfg = Element.style
		.width(Fixed(100))
		.height(Fixed(50))
		.direction(Row)
		.child_align({ x: Center, y: End })
	child = fixed_cfg(20, 10)

	match build_and_solve(root_cfg, [child], { w: 100, h: 50 }) {
		Ok(layout) => match layout.nodes.get(1) {
			Ok(node) => node.position == { x: 40, y: 40 }
			Err(_) => Bool.False
		}
		Err(_) => Bool.False
	}
}

## Column layout should stack children on Y and use X alignment for the cross
## axis.
expect {
	root_cfg = Element.style
		.width(Fixed(50))
		.height(Fixed(100))
		.direction(Col)
		.child_align({ x: End, y: Start })
		.gap(4)
	child_a = fixed_cfg(10, 20)
	child_b = fixed_cfg(15, 30)

	match build_and_solve(root_cfg, [child_a, child_b], { w: 50, h: 100 }) {
		Ok(layout) => match (layout.nodes.get(1), layout.nodes.get(2)) {
			(Ok(a), Ok(b)) => a.position == { x: 40, y: 0 }
				and b.position == { x: 35, y: 24 }
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

## Percent sizing should resolve against the parent's available size on each
## axis.
expect {
	root_cfg = fixed_cfg(200, 100)
	percent = Element.style
		.width(Percent(0.25))
		.height(Percent(0.5))
		.direction(Row)
		.child_align({ x: Start, y: Start })

	match build_and_solve(root_cfg, [percent], { w: 200, h: 100 }) {
		Ok(layout) => match layout.nodes.get(1) {
			Ok(child) => child.size == { w: 50, h: 50 }
			Err(_) => Bool.False
		}
		Err(_) => Bool.False
	}
}
