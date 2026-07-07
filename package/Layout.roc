## Flat layout tree - flex-box layout solver.
## Uses a layout tree stack (flat List-of-structs) built via push/pop message API.
## Intrinsic sizes are computed during construction.
import Assets
import Color
import Element exposing [default_font]
import Identity exposing [NodeId]
import LayoutTypes exposing [
	Axis.*,
	LayoutNode,
	LayoutNodeKind.*,
	LayoutPayload,
	LayoutPayload.*,
	ParentIndex.*,
	Pos,
	Size,
]
import Render
import Solver

# --- Frame List Helpers (Private) ---

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
	node_ids : Dict(NodeId, U64),
	root_index : U64,
	stack : List(U64),
}.{
	LayoutError(err) : [InternalError, OutOfBounds, DuplicateNodeId, UnmatchedCloseBox, ..err]
	MeasureTextRaw : Render.MeasureTextRaw
	TextSize : Render.TextSize
	NodeId : U64

	## Create empty Layout.
	new : () -> Layout(draw)
	new = || { nodes: [], payloads: [], child_indices: [], pending_children: [], node_ids: Dict.empty(), root_index: 0, stack: [] }

	## Create empty Layout with capacity reserved for internal builder lists.
	with_capacity : U64 -> Layout(draw)
	with_capacity = |capacity| {
		nodes: List.with_capacity(capacity),
		payloads: List.with_capacity(capacity),
		child_indices: List.with_capacity(capacity // 2),
		pending_children: List.with_capacity(capacity // 2),
		node_ids: Dict.empty(),
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
		node_ids: Dict.empty(),
		root_index: 0,
		stack: list_clear(layout.stack),
	}

	## The most recently appended layout node.
	current_node_index : Layout(draw) -> Try(U64, LayoutError)
	current_node_index = |layout| {
		if layout.nodes.len() == 0 {
			Err(OutOfBounds)
		} else {
			Ok(layout.nodes.len() - 1)
		}
	}

	## The node index that will be assigned to the next appended layout node.
	next_node_index : Layout(draw) -> U64
	next_node_index = |layout| layout.nodes.len()

	## Push/pop UI messages to build the tree.
	update! : Layout(draw), Element.ElementOp(msg), (NodeId -> Element.BoxStatus), Render.Renderer => Try((Layout(draw), [Node(NodeId, [Events(List(Element.Event(msg))), NoEvent]), NoNode]), LayoutError)
	update! = |layout, op, status_fn, renderer| match op {
		OpenBox(id, style_fn, events) => {
			node_id = next_box_node_id(layout, id)?
			status = status_fn(node_id)
			style = style_fn(status)
			node_events = match events.len() {
				0 => NoEvent
				_ => Events(events)
			}
			Ok((open_box(layout, id, style)?, Node(node_id, node_events)))
		}
		CloseBox => {
			node_id = close_box_node_id(layout)?
			Ok((close_box(layout)?, Node(node_id, NoEvent)))
		}
		Text(content) => {
			node_id = next_auto_node_id(layout)?
			Ok((add_text!(layout, node_id, content, renderer)?, Node(node_id, NoEvent)))
		}
		Image(cfg) => {
			node_id = next_auto_node_id(layout)?
			Ok((add_image(layout, node_id, cfg)?, Node(node_id, NoEvent)))
		}
	}

	## Phase 1: Solve layout — size (X + Y), then position.
	## Returns a layout with all positions computed.
	solve! : Layout(draw), { w : F32, h : F32 } => Try(Layout(draw), LayoutError)
	solve! = |layout, screen| {
		var $nodes = Solver.solve_size_axis(layout.nodes, layout.payloads, layout.child_indices, XAxis, screen)?
		$nodes = Solver.solve_size_axis($nodes, layout.payloads, layout.child_indices, YAxis, screen)?
		$nodes = Solver.solve_position($nodes, layout.payloads, layout.child_indices)?
		Ok({ ..layout, nodes: $nodes })
	}

	## Phase 2: Extract render commands from a solved layout.
	to_commands : Layout(draw), { w : F32, h : F32 } -> Try(List(Render.Command), LayoutError)
	to_commands = |layout, screen| {
		emit_render_commands(layout, screen)
	}

	## Return the deepest/latest box node ID containing the point.
	hit_test : Layout(draw), { x : F32, y : F32 } -> Try([Hit(NodeId), NoHit], LayoutError)
	hit_test = |layout, point| {
		match hit_index_at(layout, point)? {
			Hit(node_index) => {
				node = layout.nodes.get(node_index)?
				Ok(Hit(node.id))
			}
			NoHit => Ok(NoHit)
		}
	}

	## Return the hovered node ID ancestor path from deepest to shallowest.
	hover_path : Layout(draw), { x : F32, y : F32 } -> Try(List(NodeId), LayoutError)
	hover_path = |layout, point| {
		match hit_index_at(layout, point)? {
			Hit(node_index) => collect_box_ancestor_ids(layout.nodes, node_index, [])
			NoHit => Ok([])
		}
	}
}

# --- Node Identity ---

register_node_id : Layout(draw), NodeId, U64 -> Try(Layout(draw), LayoutError)
register_node_id = |layout, node_id, node_index| {
	match layout.node_ids.get(node_id) {
		Ok(_) => Err(DuplicateNodeId)
		Err(_) => Ok({ ..layout, node_ids: layout.node_ids.insert(node_id, node_index) })
	}
}

index_for_node_id : Layout(draw), NodeId -> Try(U64, LayoutError)
index_for_node_id = |layout, node_id| {
	layout.node_ids.get(node_id).map_err(|_| OutOfBounds)
}

parent_node_id : Layout(draw), ParentIndex -> Try(NodeId, LayoutError)
parent_node_id = |layout, parent| match parent {
	NoParent => Ok(0)
	Parent(parent_idx) => {
		parent_node = layout.nodes.get(parent_idx)?
		Ok(parent_node.id)
	}
}

parent_child_offset : Layout(draw), ParentIndex -> Try(U64, LayoutError)
parent_child_offset = |layout, parent| match parent {
	NoParent => Ok(layout.root_index)
	Parent(parent_idx) => {
		parent_node = layout.nodes.get(parent_idx)?
		Ok(parent_node.child_count)
	}
}

next_box_node_id : Layout(draw), Element.ElementId -> Try(NodeId, LayoutError)
next_box_node_id = |layout, id| {
	parent = if layout.stack.len() == 0 {
		NoParent
	} else {
		Parent(layout.stack.get(layout.stack.len() - 1)?)
	}
	Ok(
		Identity.resolve(
			id,
			parent_node_id(layout, parent)?,
			parent_child_offset(layout, parent)?,
		),
	)
}

next_auto_node_id : Layout(draw) -> Try(NodeId, LayoutError)
next_auto_node_id = |layout| next_box_node_id(layout, Auto)

close_box_node_id : Layout(draw) -> Try(NodeId, LayoutError)
close_box_node_id = |layout| {
	if layout.stack.len() == 0 {
		Err(UnmatchedCloseBox)
	} else {
		box_idx = layout.stack.get(layout.stack.len() - 1)?
		box_node = layout.nodes.get(box_idx)?
		Ok(box_node.id)
	}
}

# --- Tree Builder ---

open_box : Layout(draw), Element.ElementId, Element.BoxConfig -> Try(Layout(draw), LayoutError)
open_box = |layout, id, cfg| {
	idx = layout.nodes.len()
	parent = if layout.stack.len() == 0 {
		NoParent
	} else {
		Parent(layout.stack.get(layout.stack.len() - 1)?)
	}
	node_id = Identity.resolve(
		id,
		parent_node_id(layout, parent)?,
		parent_child_offset(layout, parent)?,
	)
	resolved_text = resolve_box_text(layout, parent, cfg.text)?
	resolved_cfg = { ..cfg, text: Font(resolved_text) }
	node = {
		id: node_id,
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
	layout_with_id = register_node_id(layout, node_id, idx)?
	Ok(
		{
			..layout_with_id,
			nodes: layout_with_id.nodes.append(node),
			payloads: layout_with_id.payloads.append(BoxPayload(resolved_cfg)),
			stack: layout_with_id.stack.append(idx),
		},
	)
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

resolve_font : Element.Font, Element.Font -> Element.Font
resolve_font = |cfg_font, fallback_font|
	if (Box.unbox(cfg_font)) == 0.U64 fallback_font else cfg_font

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

## Return the currently open box and the stack that remains after closing it.
pop_open_box : Layout(draw) -> Try({ box_idx : U64, box_node : LayoutNode, stack : List(U64) }, LayoutError)
pop_open_box = |layout| {
	if layout.stack.len() == 0 {
		return Err(UnmatchedCloseBox)
	}

	box_idx = layout.stack.get(layout.stack.len() - 1)?
	box_node = layout.nodes.get(box_idx)?
	stack = layout.stack.sublist({ start: 0, len: layout.stack.len() - 1 })
	Ok({ box_idx, box_node, stack })
}

## Move a closing box's pending children into the permanent child index list.
finalize_child_range : Layout(draw), LayoutNode -> { node : LayoutNode, child_indices : List(U64), pending_children : List(U64) }
finalize_child_range = |layout, box_node| {
	pending_len = layout.pending_children.len()
	start_in_pending = pending_len - box_node.child_count
	box_child_indices = layout.pending_children.sublist({ start: start_in_pending, len: box_node.child_count })
	child_indices = layout.child_indices.concat(box_child_indices)
	node = { ..box_node, child_start: layout.child_indices.len() }
	pending_children = layout.pending_children.sublist({ start: 0, len: start_in_pending })
	{ node, child_indices, pending_children }
}

## Read the box config payload for a layout node.
box_payload : Layout(draw), LayoutNode -> Try(Element.BoxConfig, LayoutError)
box_payload = |layout, box_node| {
	match layout.payloads.get(box_node.payload_index)? {
		BoxPayload(box_cfg) => Ok(box_cfg)
		_ => Err(InternalError)
	}
}

## Replace a closed box node, restore builder state, and attach it to its parent.
attach_closed_box : Layout(draw), U64, LayoutNode, List(U64), List(U64), List(U64) -> Try(Layout(draw), LayoutError)
attach_closed_box = |layout, box_idx, node, stack, child_indices, pending_children| {
	nodes = layout.nodes.set(box_idx, node)?
	closed = { ..layout, nodes, child_indices, pending_children, stack }
	attach_child(closed, box_idx)
}

## Finalize a box and attach it to its parent.
close_box : Layout(draw) -> Try(Layout(draw), LayoutError)
close_box = |layout| {
	{ box_idx, box_node, stack } = pop_open_box(layout)?
	{ node: with_child_range, child_indices, pending_children } = finalize_child_range(layout, box_node)
	cfg = box_payload(layout, box_node)?
	intrinsic = Solver.box_intrinsic_size(with_child_range, cfg.layout, layout.nodes, child_indices)?
	updated = { ..with_child_range, intrinsic }
	attach_closed_box(layout, box_idx, updated, stack, child_indices, pending_children)
}

add_text! : Layout(draw), NodeId, Str, Render.Renderer => Try(Layout(draw), LayoutError)
add_text! = |layout, node_id, content, renderer| {
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
		id: node_id,
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
	layout_with_id = register_node_id(layout, node_id, idx)?
	attach_child(
		{
			..layout_with_id,
			nodes: layout_with_id.nodes.append(node),
			payloads: layout_with_id.payloads.append(payload),
		},
		idx,
	)
}

add_image : Layout(draw), NodeId, Element.ImageConfig -> Try(Layout(draw), LayoutError)
add_image = |layout, id, cfg| {
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
		id: id,
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
	layout_with_id = register_node_id(layout, id, idx)?
	attach_child(
		{
			..layout_with_id,
			nodes: layout_with_id.nodes.append(node),
			payloads: layout_with_id.payloads.append(payload),
		},
		idx,
	)
}

# --- Hit Testing ---

point_inside : Pos, LayoutNode -> Bool
point_inside = |point, node| {
	point.x >= node.position.x
		and point.x <= node.position.x + node.size.w
			and point.y >= node.position.y
				and point.y <= node.position.y + node.size.h
}

hit_index_at : Layout(draw), Pos -> Try([Hit(U64), NoHit], LayoutError)
hit_index_at = |layout, point| {
	var $result = NoHit
	node_count = layout.nodes.len()
	for offset in 0..<node_count {
		i = node_count - 1 - offset
		node = layout.nodes.get(i)?
		if node.kind == BoxNode and point_inside(point, node) and $result == NoHit {
			$result = Hit(i)
		}
	}
	Ok($result)
}

collect_box_ancestor_ids : List(LayoutNode), U64, List(U64) -> Try(List(U64), LayoutError)
collect_box_ancestor_ids = |nodes, node_index, acc| {
	node = nodes.get(node_index)?
	next_acc = if node.kind == BoxNode {
		acc.append(node.id)
	} else {
		acc
	}

	match node.parent {
		Parent(parent_index) => collect_box_ancestor_ids(nodes, parent_index, next_acc)
		NoParent => Ok(next_acc)
	}
}

# --- Render Command Extraction (Private) ---

is_offscreen : Pos, Size, Size -> Bool
is_offscreen = |offset, size, screen| {
	offset.x > screen.w or offset.y > screen.h or offset.x + size.w < 0 or offset.y + size.h < 0
}

text_align_offset : Element.TextAlign, F32, F32 -> F32
text_align_offset = |align, box_width, text_width| match align {
	Left => 0
	Center => (box_width - text_width) * 0.5
	Right => box_width - text_width
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
									radius: cfg.radius,
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
	var $nodes = Solver.solve_size_axis(tree.nodes, tree.payloads, tree.child_indices, XAxis, screen)?
	$nodes = Solver.solve_size_axis($nodes, tree.payloads, tree.child_indices, YAxis, screen)?
	$nodes = Solver.solve_position($nodes, tree.payloads, tree.child_indices)?
	Ok({ ..tree, nodes: $nodes })
}

fixed_cfg : F32, F32 -> Element.BoxConfig
fixed_cfg = |w, h| {
	Element.style
		.width(Fixed(w))
		.height(Fixed(h))
		.child_align({ x: Start, y: Start })
}

build_row : Element.BoxConfig, List(Element.BoxConfig) -> Try(Layout(draw), LayoutError)
build_row = |root_cfg, child_cfgs| {
	var $tree = Layout.new()
	$tree = open_box($tree, Auto, root_cfg)?
	for child_cfg in child_cfgs {
		$tree = open_box($tree, Auto, child_cfg)?
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
	cfg = Element.style
	build = || {
		var $tree = Layout.new()
		$tree = open_box($tree, Auto, cfg)? # root: 0
		$tree = open_box($tree, Auto, cfg)? # first child: 1
		$tree = close_box($tree)?
		$tree = open_box($tree, Auto, cfg)? # second child: 2
		$tree = open_box($tree, Auto, cfg)? # grandchild: 3
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
	cfg = Element.style
	build = || {
		var $tree = Layout.new()
		$tree = open_box($tree, Auto, cfg)?
		$tree = open_box($tree, Auto, cfg)?
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

## Closing without an open box should be an error.
expect {
	match close_box(Layout.new()) {
		Err(UnmatchedCloseBox) => Bool.True
		_ => Bool.False
	}
}

## Solving an empty layout should be a no-op.
expect {
	match solve_test_layout(Layout.new(), { w: 100, h: 100 }) {
		Ok(tree) => tree.nodes.len() == 0
			and tree.payloads.len() == 0
				and tree.child_indices.len() == 0
					and tree.stack.len() == 0
		Err(_) => Bool.False
	}
}

## Duplicate explicit IDs in one layout generation should be rejected.
expect {
	cfg = Element.style
	build = || {
		var $tree = Layout.new()
		$tree = open_box($tree, Id("shared"), cfg)?
		$tree = close_box($tree)?
		open_box($tree, Id("shared"), cfg)
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
		var $tree = Layout.new()
		$tree = open_box($tree, Id("root"), cfg)?
		node = $tree.nodes.get(0)?
		node_index = index_for_node_id($tree, node.id)?
		Ok(node_index)
	}

	match build() {
		Ok(0) => Bool.True
		_ => Bool.False
	}
}

## Hit and hover queries on an empty layout should return empty results.
expect {
	tree = Layout.new()
	match (tree.hit_test({ x: 0, y: 0 }), tree.hover_path({ x: 0, y: 0 })) {
		(Ok(NoHit), Ok([])) => Bool.True
		_ => Bool.False
	}
}

## Hit testing should return the deepest/latest matching box.
expect {
	root_cfg = fixed_cfg(100, 100)
	child_cfg = fixed_cfg(50, 50)

	match build_and_solve(root_cfg, [child_cfg], { w: 100, h: 100 }) {
		Ok(tree) => {
			expected = tree.nodes.get(1)?
			match tree.hit_test({ x: 25, y: 25 }) {
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
		Ok(tree) => match tree.hit_test({ x: 101, y: 50 }) {
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
		Ok(tree) => {
			root = tree.nodes.get(0)?
			match tree.hit_test({ x: 100, y: 100 }) {
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
		Ok(tree) => {
			second = tree.nodes.get(2)?
			match tree.hit_test({ x: 50, y: 25 }) {
				Ok(Hit(node_id)) => node_id == second.id
				_ => Bool.False
			}
		}
		Err(_) => Bool.False
	}
}

## Hit testing should ignore non-box nodes and return the containing box.
expect {
	texture = Box.box({ handle: 1, width: 20, height: 20 })
	image_cfg = { texture, tint: Color.white }
	root_cfg = fixed_cfg(100, 100)
	build = || {
		var $tree = Layout.new()
		$tree = open_box($tree, Auto, root_cfg)?
		$tree = add_image($tree, 200, image_cfg)?
		$tree = close_box($tree)?
		solve_test_layout($tree, { w: 100, h: 100 })
	}

	match build() {
		Ok(tree) => {
			root = tree.nodes.get(0)?
			image = tree.nodes.get(1)?
			match tree.hit_test({ x: 10, y: 10 }) {
				Ok(Hit(node_id)) => node_id == root.id and node_id != image.id
				_ => Bool.False
			}
		}
		Err(_) => Bool.False
	}
}

## Hover paths should return node ancestors from deepest to shallowest.
expect {
	root_cfg = fixed_cfg(100, 100)
	child_cfg = fixed_cfg(50, 50)

	match build_and_solve(root_cfg, [child_cfg], { w: 100, h: 100 }) {
		Ok(tree) => {
			root = tree.nodes.get(0)?
			child = tree.nodes.get(1)?
			match tree.hover_path({ x: 25, y: 25 }) {
				Ok([child_id, root_id]) => child_id == child.id and root_id == root.id
				_ => Bool.False
			}
		}
		Err(_) => Bool.False
	}
}

## Extra closes after a balanced nested build should fail without corrupting the
## completed tree.
expect {
	cfg = Element.style
	build = || {
		var $tree = Layout.new()
		$tree = open_box($tree, Auto, cfg)?
		$tree = open_box($tree, Auto, cfg)?
		$tree = close_box($tree)?
		$tree = close_box($tree)?
		match close_box($tree) {
			Err(UnmatchedCloseBox) => Ok($tree)
			Ok(_) => Err(InternalError)
			Err(_) => Err(InternalError)
		}
	}

	match build() {
		Ok(tree) => tree.stack.len() == 0
			and tree.nodes.len() == 2
				and tree.child_indices == [1]
		Err(_) => Bool.False
	}
}

## Closing nested boxes with mixed child payloads should preserve direct-child
## ranges independently of DFS node order.
expect {
	texture = Box.box({ handle: 1, width: 8, height: 9 })
	image_cfg = { texture, tint: Color.white }
	root_cfg = Element.style
		.width(Fit({ min: 0, max: 1000 }))
		.height(Fit({ min: 0, max: 1000 }))
		.child_align({ x: Start, y: Start })
	nested_cfg = Element.style
		.width(Fit({ min: 0, max: 1000 }))
		.height(Fit({ min: 0, max: 1000 }))
		.child_align({ x: Start, y: Start })
	build = || {
		var $tree = Layout.new()
		$tree = open_box($tree, Auto, root_cfg)? # root: 0
		$tree = add_image($tree, 100, image_cfg)? # root child: 1
		$tree = open_box($tree, Auto, nested_cfg)? # root child: 2
		$tree = add_image($tree, 101, image_cfg)? # nested child: 3
		$tree = close_box($tree)?
		$tree = close_box($tree)?
		Ok($tree)
	}

	match build() {
		Ok(tree) => match (tree.nodes.get(0), tree.nodes.get(2), tree.nodes.get(1), tree.nodes.get(3)) {
			(Ok(root), Ok(nested), Ok(image_a), Ok(image_b)) => tree.child_indices == [3, 1, 2]
				and root.child_start == 1
					and root.child_count == 2
						and nested.child_start == 0
							and nested.child_count == 1
								and image_a.kind == ImageNode
									and image_b.kind == ImageNode
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
		var $tree = Layout.new()
		$tree = open_box($tree, Auto, root_cfg)?
		$tree = open_box($tree, Auto, base_cfg)?
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
	root_cfg = Element.style
		.width(Fit({ min: 0, max: 1000 }))
		.height(Fit({ min: 0, max: 1000 }))
	child_cfg = fixed_cfg(10, 20)
	build = || {
		var $tree = Layout.new()
		$tree = open_box($tree, Auto, root_cfg)?
		$tree = open_box($tree, Auto, child_cfg)?
		$tree = close_box($tree)?
		$tree = close_box($tree)?
		Ok($tree)
	}

	match build() {
		Ok(tree) => match tree.nodes.get(0) {
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
		Ok(tree) => match (tree.nodes.get(0), tree.nodes.get(1), tree.nodes.get(2)) {
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
		.pad((5, 2, 7, 4))
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
	root_cfg = Element.style
		.width(Fixed(100))
		.height(Fixed(50))
		.direction(Row)
		.child_align({ x: Center, y: End })
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
	root_cfg = Element.style
		.width(Fixed(50))
		.height(Fixed(100))
		.direction(Col)
		.child_align({ x: End, y: Start })
		.gap(4)
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
		Ok(tree) => match tree.nodes.get(1) {
			Ok(child) => child.size == { w: 50, h: 50 }
			Err(_) => Bool.False
		}
		Err(_) => Bool.False
	}
}
