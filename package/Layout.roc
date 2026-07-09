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
	ParentIndex.*,
	Pos,
	Size,
]
import Render
import Solver
import Stack
import Text

## TODO: replace with List.clear() once the builtin exists. Runtime listSublist
## keeps the allocation for unique/in-place zero-length sublists by setting
## length to 0, so this preserves capacity in the expected Layout reuse path.
## If the list is shared, sublist decrefs it and returns [], losing capacity.
list_clear : List(a) -> List(a)
list_clear = |list| list.sublist({ start: 0, len: 0 })

# --- Public API ---
Layout(draw) :: {
	nodes : List(LayoutNode),
	text_contents : List(Str),
	text_words : List(Text.Word),
	text_lines : List(Text.Line),
	child_indices : List(U64),
	pending_children : List(U64),
	node_ids : Dict(NodeId, U64),
	root_index : U64,
	stack : Stack(LayoutFrame),
}.{
	LayoutError : [InternalError, OutOfBounds, DuplicateNodeId, UnmatchedCloseBox]
	MeasureTextFn : { text : Str, size : F32, spacing : F32, font : U64 } => Render.TextSize
	TextSize : Render.TextSize
	NodeId : U64

	## Create empty Layout.
	new : () -> Layout(draw)
	new = || { nodes: [], text_contents: [], text_words: [], text_lines: [], child_indices: [], pending_children: [], node_ids: Dict.empty(), root_index: 0, stack: Stack.new() }

	## Create empty Layout with capacity reserved for internal builder lists.
	with_capacity : U64 -> Layout(draw)
	with_capacity = |capacity| {
		nodes: List.with_capacity(capacity),
		text_contents: List.with_capacity(capacity // 2),
		text_words: List.with_capacity(capacity),
		text_lines: List.with_capacity(capacity),
		child_indices: List.with_capacity(capacity // 2),
		pending_children: List.with_capacity(capacity // 2),
		node_ids: Dict.empty(),
		root_index: 0,
		stack: Stack.with_capacity(capacity // 2),
	}

	## Reset all frame-local layout state before building the next view.
	clear : Layout(draw) -> Layout(draw)
	clear = |layout| {
		..layout,
		nodes: list_clear(layout.nodes),
		text_contents: list_clear(layout.text_contents),
		text_words: list_clear(layout.text_words),
		text_lines: list_clear(layout.text_lines),
		child_indices: list_clear(layout.child_indices),
		pending_children: list_clear(layout.pending_children),
		node_ids: Dict.empty(),
		root_index: 0,
		stack: layout.stack.clear(),
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
	update! : Layout(draw), Element.ElementOp(msg), (NodeId -> Element.BoxStatus), MeasureTextFn => Try((Layout(draw), [Node(NodeId, [Events(List(Element.Event(msg))), NoEvent]), NoNode]), LayoutError)
	update! = |layout, op, status_fn, measure_text!| match op {
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
			Ok((add_text!(layout, node_id, content, measure_text!)?, Node(node_id, NoEvent)))
		}
		Image(cfg) => {
			node_id = next_auto_node_id(layout)?
			Ok((add_image(layout, node_id, cfg)?, Node(node_id, NoEvent)))
		}
	}

	## Phase 1: Solve layout — width, height, then position.
	solve : Layout(draw), { w : F32, h : F32 } -> Try(Layout(draw), LayoutError)
	solve = |layout, screen| {
		var $layout = { ..layout, nodes: Solver.solve_size_axis(layout.nodes, layout.child_indices, XAxis, screen)? }
		$layout = wrap_text_nodes($layout)?
		$layout = refresh_intrinsics($layout)?
		$layout = { ..$layout, nodes: Solver.solve_size_axis($layout.nodes, $layout.child_indices, XAxis, screen)? }
		$layout = { ..$layout, nodes: Solver.solve_size_axis($layout.nodes, $layout.child_indices, YAxis, screen)? }
		$layout = { ..$layout, nodes: Solver.solve_position($layout.nodes, $layout.child_indices)? }
		Ok($layout)
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

LayoutFrame : {
	index : U64,
	text : Element.TextConfig,
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

parent_from_stack : Layout(draw) -> ParentIndex
parent_from_stack = |layout| {
	match layout.stack.top() {
		Ok(frame) => Parent(frame.index)
		Err(OutOfBounds) => NoParent
	}
}

next_box_node_id : Layout(draw), Element.ElementId -> Try(NodeId, LayoutError)
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

next_auto_node_id : Layout(draw) -> Try(NodeId, LayoutError)
next_auto_node_id = |layout| next_box_node_id(layout, Auto)

close_box_node_id : Layout(draw) -> Try(NodeId, LayoutError)
close_box_node_id = |layout| {
	match layout.stack.top() {
		Err(OutOfBounds) => Err(UnmatchedCloseBox)
		Ok(frame) => {
			box_node = layout.nodes.get(frame.index)?
			Ok(box_node.id)
		}
	}
}

root_text_config : Element.TextConfig
root_text_config = { ..Element.default_text, font: resolve_font(Element.default_text.font, default_font) }

resolve_box_text : Layout(draw), Element.TextStyle -> Element.TextConfig
resolve_box_text = |layout, style| {
	parent_text_cfg = layout.stack.top().map_ok(|frame| frame.text).ok_or(root_text_config)
	match style {
		Font(text_cfg) => { ..text_cfg, font: resolve_font(text_cfg.font, parent_text_cfg.font) }
		Auto => parent_text_cfg
	}
}

resolve_font : Element.Font, Element.Font -> Element.Font
resolve_font = |cfg_font, fallback_font|
	if (Box.unbox(cfg_font)) == 0.U64 fallback_font else cfg_font

# --- Tree Builder ---

open_box : Layout(draw), Element.ElementId, Element.BoxConfig -> Try(Layout(draw), LayoutError)
open_box = |layout, id, cfg| {
	idx = layout.nodes.len()
	parent = parent_from_stack(layout)
	node_id = Identity.resolve(
		id,
		parent_node_id(layout, parent)?,
		parent_child_offset(layout, parent)?,
	)
	resolved_text = resolve_box_text(layout, cfg.text)
	resolved_cfg = { ..cfg, text: Auto }
	node = {
		id: node_id,
		kind: BoxNode(
			{
				layout: resolved_cfg.layout,
				background: resolved_cfg.background,
				radius: resolved_cfg.radius,
				border: resolved_cfg.border,
			},
		),
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
			stack: layout_with_id.stack.push({ index: idx, text: resolved_text }),
		},
	)
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
	match layout.stack.top() {
		Err(OutOfBounds) => Ok(layout)
		Ok(item) => {
			parent = layout.nodes.get(item.index)?
			nodes = layout.nodes.set(item.index, { ..parent, child_count: parent.child_count + 1 })?
			Ok({ ..layout, nodes, pending_children: layout.pending_children.append(child_idx) })
		}
	}
}

## Return the currently open box and the stack that remains after closing it.
pop_open_box : Layout(draw) -> Try({ node_index : U64, node : LayoutNode, stack : Stack(LayoutFrame) }, LayoutError)
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
finalize_child_range : Layout(draw), LayoutNode -> (Layout(draw), LayoutNode)
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
attach_closed_box : Layout(draw), U64, LayoutNode, Stack(LayoutFrame) -> Try(Layout(draw), LayoutError)
attach_closed_box = |layout, box_idx, node, stack| {
	nodes = layout.nodes.set(box_idx, node)?
	closed = { ..layout, nodes, stack }
	attach_child(closed, box_idx)
}

## Finalize a box and attach it to its parent.
close_box : Layout(draw) -> Try(Layout(draw), LayoutError)
close_box = |layout| {
	{ node_index, node, stack } = pop_open_box(layout)?
	(layout_ranged, node_with_child_range) = finalize_child_range(layout, node)
	intrinsic = Solver.box_intrinsic_size(node_with_child_range, get_box_layout(node_with_child_range)?, layout_ranged.nodes, layout_ranged.child_indices)?
	node_with_intrinsic = { ..node_with_child_range, intrinsic }
	attach_closed_box(layout_ranged, node_index, node_with_intrinsic, stack)
}

add_text! : Layout(draw), NodeId, Str, Layout.MeasureTextFn => Try(Layout(draw), LayoutError)
add_text! = |layout, node_id, content, measure_text!| {
	idx = layout.nodes.len()
	parent_text_cfg = layout.stack.top().map_ok(|frame| frame.text).ok_or(root_text_config)
	measured_text = Text.measure!(content, parent_text_cfg, measure_text!)
	measured = measured_text.preferred
	parent = parent_from_stack(layout)
	content_index = layout.text_contents.len()
	words_start = layout.text_words.len()
	lines_start = layout.text_lines.len()
	node = {
		id: node_id,
		kind: TextNode(
			{
				content_index,
				config: parent_text_cfg,
				line_height: measured_text.line_height,
				wrap_width: measured_text.wrap_width,
				min_width: measured_text.min_width,
				space_width: measured_text.space_width,
				words_start,
				words_count: measured_text.words.len(),
				lines_start,
				lines_count: measured_text.lines.len(),
			},
		),
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
			text_contents: layout_with_id.text_contents.append(content),
			text_words: layout_with_id.text_words.concat(measured_text.words),
			text_lines: layout_with_id.text_lines.concat(measured_text.lines),
		},
		idx,
	)
}

wrap_text_nodes : Layout(draw) -> Try(Layout(draw), LayoutError)
wrap_text_nodes = |layout| {
	var $nodes = layout.nodes
	var $lines = []
	for i in 0..<layout.nodes.len() {
		node = $nodes.get(i)?
		match node.kind {
			TextNode(text_data) => {
				content = layout.text_contents.get(text_data.content_index)?
				words = layout.text_words.sublist({ start: text_data.words_start, len: text_data.words_count })
				wrap_width = text_wrap_width($nodes, node)?
				lines_start = $lines.len()
				wrapped = Text.wrap(content, text_data.config, text_data.space_width, text_data.line_height, wrap_width, words)
				updated_data = { ..text_data, wrap_width, lines_start, lines_count: wrapped.len() }
				$nodes = $nodes.set(i, { ..node, kind: TextNode(updated_data) })?
				$lines = $lines.concat(wrapped)
			}
			_ => {}
		}
	}
	Ok({ ..layout, nodes: $nodes, text_lines: $lines })
}

text_wrap_width : List(LayoutNode), LayoutNode -> Try(F32, LayoutError)
text_wrap_width = |nodes, node| {
	constrain_text_wrap_width(nodes, node.parent, node.size.w)
}

constrain_text_wrap_width : List(LayoutNode), ParentIndex, F32 -> Try(F32, LayoutError)
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

refresh_intrinsics : Layout(draw) -> Try(Layout(draw), LayoutError)
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

add_image : Layout(draw), NodeId, Element.ImageConfig -> Try(Layout(draw), LayoutError)
add_image = |layout, id, cfg| {
	idx = layout.nodes.len()
	info = Assets.info(cfg.texture)
	measured = { w: info.width, h: info.height }
	parent = parent_from_stack(layout)
	node = {
		id: id,
		kind: ImageNode({ config: cfg }),
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
		},
		idx,
	)
}

get_box_layout : LayoutNode -> Try(Element.LayoutConfig, LayoutError)
get_box_layout = |node| match node.kind {
	BoxNode(box) => Ok(box.layout)
	_ => Err(InternalError)
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
		match node.kind {
			BoxNode(_) => if point_inside(point, node) and $result == NoHit {
				$result = Hit(i)
			}
			_ => {}
		}
	}
	Ok($result)
}

collect_box_ancestor_ids : List(LayoutNode), U64, List(U64) -> Try(List(U64), LayoutError)
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

is_image_node : LayoutNode -> Bool
is_image_node = |node| match node.kind {
	ImageNode(_) => Bool.True
	_ => Bool.False
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
		if !is_offscreen(node.position, node.size, screen) {
			match node.kind {
				BoxNode(box) => {
					if box.background.a > 0 {
						bg = if box.radius > 0 {
							RoundedRectangle(
								{
									x: node.position.x,
									y: node.position.y,
									width: node.size.w,
									height: node.size.h,
									radius: box.radius,
									color: box.background,
								},
							)
						} else {
							Rectangle(
								{
									x: node.position.x,
									y: node.position.y,
									width: node.size.w,
									height: node.size.h,
									color: box.background,
								},
							)
						}
						$commands = $commands.append(bg)
					}
					border_total = box.border.left + box.border.right + box.border.top + box.border.bottom
					if box.border.color.a > 0 and border_total > 0 {
						$border_commands = $border_commands.append(
							Border(
								{
									x: node.position.x,
									y: node.position.y,
									width: node.size.w,
									height: node.size.h,
									color: box.border.color,
									left: box.border.left,
									right: box.border.right,
									top: box.border.top,
									bottom: box.border.bottom,
									radius: box.radius,
								},
							),
						)
					}
				}
				TextNode(text_data) => {
					content = tree.text_contents.get(text_data.content_index)?
					for line_offset in 0..<text_data.lines_count {
						line = tree.text_lines.get(text_data.lines_start + line_offset)?
						config = text_data.config
						$commands = $commands.append(
							Text(
								{
									x: node.position.x + text_align_offset(config.align, node.size.w, line.width),
									y: node.position.y + line_offset.to_f32() * line.height,
									text: Text.line_text(content, line),
									font_size: config.font_size,
									spacing: config.spacing,
									color: config.color,
									font: config.font,
								},
							),
						)
					}
				}
				ImageNode({ config: cfg }) => {
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
			}
		}
	}
	Ok($commands.concat($border_commands))
}

## TESTS ##

solve_test_layout : Layout(draw), Size -> Try(Layout(draw), LayoutError)
solve_test_layout = |layout, screen| {
	var $layout = { ..layout, nodes: Solver.solve_size_axis(layout.nodes, layout.child_indices, XAxis, screen)? }
	$layout = wrap_text_nodes($layout)?
	$layout = refresh_intrinsics($layout)?
	$layout = { ..$layout, nodes: Solver.solve_size_axis($layout.nodes, $layout.child_indices, XAxis, screen)? }
	$layout = { ..$layout, nodes: Solver.solve_size_axis($layout.nodes, $layout.child_indices, YAxis, screen)? }
	$layout = { ..$layout, nodes: Solver.solve_position($layout.nodes, $layout.child_indices)? }
	Ok($layout)
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

test_text_cfg : Element.TextWrap -> Element.BoxConfig
test_text_cfg = |wrap| {
	Element.style
		.width(Fixed(4))
		.height(Fit({ min: 0, max: 10000 }))
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
		.width(Fit({ min: 0, max: 10000 }))
		.height(Fit({ min: 0, max: 10000 }))
		.pad((18, 18, 18, 18))
		.child_align({ x: Center, y: Center })
		.direction(Row)
		.font_size(24)
}

test_align_text_cfg : Element.TextAlign -> Element.BoxConfig
test_align_text_cfg = |align| {
	Element.style
		.width(Fixed(10))
		.height(Fit({ min: 0, max: 10000 }))
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

add_test_text : Layout(draw), Str, F32, List(Text.Word) -> Try(Layout(draw), LayoutError)
add_test_text = |layout, content, preferred_w, words| {
	idx = layout.nodes.len()
	node_id = next_auto_node_id(layout)?
	text_cfg = layout.stack.top().map_ok(|frame| frame.text).ok_or(root_text_config)
	parent = parent_from_stack(layout)
	content_index = layout.text_contents.len()
	words_start = layout.text_words.len()
	lines_start = layout.text_lines.len()
	lines = Text.wrap(content, text_cfg, 1, 10, preferred_w, words)
	node = {
		id: node_id,
		kind: TextNode(
			{
				content_index,
				config: text_cfg,
				line_height: 10,
				wrap_width: preferred_w,
				min_width: preferred_w,
				space_width: 1,
				words_start,
				words_count: words.len(),
				lines_start,
				lines_count: lines.len(),
			},
		),
		parent,
		child_start: 0,
		child_count: 0,
		intrinsic: { w: preferred_w, h: 10 },
		size: { w: 0, h: 0 },
		position: { x: 0, y: 0 },
		sizing_w: Fixed(preferred_w),
		sizing_h: Fixed(10),
	}
	layout_with_id = register_node_id(layout, node_id, idx)?
	attach_child(
		{
			..layout_with_id,
			nodes: layout_with_id.nodes.append(node),
			text_contents: layout_with_id.text_contents.append(content),
			text_words: layout_with_id.text_words.concat(words),
			text_lines: layout_with_id.text_lines.concat(lines),
		},
		idx,
	)
}

add_test_text_with_line_height : Layout(draw), Str, F32, F32, List(Text.Word) -> Try(Layout(draw), LayoutError)
add_test_text_with_line_height = |layout, content, preferred_w, line_h, words| {
	idx = layout.nodes.len()
	node_id = next_auto_node_id(layout)?
	text_cfg = layout.stack.top().map_ok(|frame| frame.text).ok_or(root_text_config)
	parent = parent_from_stack(layout)
	content_index = layout.text_contents.len()
	words_start = layout.text_words.len()
	lines_start = layout.text_lines.len()
	lines = Text.wrap(content, text_cfg, 1, line_h, preferred_w, words)
	node = {
		id: node_id,
		kind: TextNode(
			{
				content_index,
				config: text_cfg,
				line_height: line_h,
				wrap_width: preferred_w,
				min_width: preferred_w,
				space_width: 1,
				words_start,
				words_count: words.len(),
				lines_start,
				lines_count: lines.len(),
			},
		),
		parent,
		child_start: 0,
		child_count: 0,
		intrinsic: { w: preferred_w, h: line_h },
		size: { w: 0, h: 0 },
		position: { x: 0, y: 0 },
		sizing_w: Fixed(preferred_w),
		sizing_h: Fixed(line_h),
	}
	layout_with_id = register_node_id(layout, node_id, idx)?
	attach_child(
		{
			..layout_with_id,
			nodes: layout_with_id.nodes.append(node),
			text_contents: layout_with_id.text_contents.append(content),
			text_words: layout_with_id.text_words.concat(words),
			text_lines: layout_with_id.text_lines.concat(lines),
		},
		idx,
	)
}

build_text_layout : Element.BoxConfig, Str, F32, List(Text.Word), Size -> Try(Layout(draw), LayoutError)
build_text_layout = |root_cfg, content, preferred_w, words, screen| {
	var $tree = Layout.new()
	$tree = open_box($tree, Auto, root_cfg)?
	$tree = add_test_text($tree, content, preferred_w, words)?
	$tree = close_box($tree)?
	solve_test_layout($tree, screen)
}

build_button_text_layout : Str, F32, F32, List(Text.Word), Size -> Try(Layout(draw), LayoutError)
build_button_text_layout = |content, preferred_w, line_h, words, screen| {
	var $tree = Layout.new()
	$tree = open_box($tree, Auto, test_button_cfg)?
	$tree = add_test_text_with_line_height($tree, content, preferred_w, line_h, words)?
	$tree = close_box($tree)?
	solve_test_layout($tree, screen)
}

build_nested_fit_text_layout : Element.BoxConfig, Str, F32, List(Text.Word), Size -> Try(Layout(draw), LayoutError)
build_nested_fit_text_layout = |root_cfg, content, preferred_w, words, screen| {
	var $tree = Layout.new()
	$tree = open_box($tree, Auto, root_cfg)?
	$tree = open_box($tree, Auto, Element.style.width(Fit({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).direction(Col).child_align({ x: Start, y: Start }))?
	$tree = add_test_text($tree, content, preferred_w, words)?
	$tree = close_box($tree)?
	$tree = close_box($tree)?
	solve_test_layout($tree, screen)
}

text_line_count : Layout(draw), U64 -> U64
text_line_count = |tree, index| {
	match tree.nodes.get(index) {
		Ok(node) => match node.kind {
			TextNode(text_data) => text_data.lines_count
			_ => 0
		}
		Err(_) => 0
	}
}

node_height : Layout(draw), U64 -> F32
node_height = |tree, index| {
	match tree.nodes.get(index) {
		Ok(node) => node.size.h
		Err(_) => 0
	}
}

node_pos_y : Layout(draw), U64 -> F32
node_pos_y = |tree, index| {
	match tree.nodes.get(index) {
		Ok(node) => node.position.y
		Err(_) => 0
	}
}

first_text_command_y : Layout(draw) -> F32
first_text_command_y = |tree| {
	match tree.to_commands({ w: 1000, h: 1000 }) {
		Ok(commands) => {
			var $y = -1
			for command in commands {
				match command {
					Text(text_cmd) => if $y < 0 {
						$y = text_cmd.y
					}
					_ => {}
				}
			}
			$y
		}
		Err(_) => -1
	}
}

text_command_positions : Layout(draw) -> List({ x : F32, y : F32, text : Str })
text_command_positions = |tree| {
	match tree.to_commands({ w: 1000, h: 1000 }) {
		Ok(commands) => {
			var $positions = []
			for command in commands {
				match command {
					Text(text_cmd) => {
						$positions = $positions.append({ x: text_cmd.x, y: text_cmd.y, text: text_cmd.text })
					}
					_ => {}
				}
			}
			$positions
		}
		Err(_) => []
	}
}

node_width : Layout(draw), U64 -> F32
node_width = |tree, index| {
	match tree.nodes.get(index) {
		Ok(node) => node.size.w
		Err(_) => 0
	}
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

## Words wrapping breaks text into multiple line records after X sizing.
expect {
	words = [test_word(0, 3, 3), test_word(3, 3, 3), test_word(6, 2, 2)]
	match build_text_layout(test_text_cfg(Words), "aa bb cc", 8, words, { w: 100, h: 100 }) {
		Ok(tree) => text_line_count(tree, 1) == 3
		Err(_) => Bool.False
	}
}

## A single long word wider than the wrap width stays one overflowing line.
expect {
	words = [test_word(0, 6, 6)]
	match build_text_layout(test_text_cfg(Words), "abcdef", 6, words, { w: 100, h: 100 }) {
		Ok(tree) => text_line_count(tree, 1) == 1
		Err(_) => Bool.False
	}
}

## A fit-height parent grows after child text wraps.
expect {
	words = [test_word(0, 3, 3), test_word(3, 3, 3), test_word(6, 2, 2)]
	match build_text_layout(test_text_cfg(Words), "aa bb cc", 8, words, { w: 100, h: 100 }) {
		Ok(tree) => match tree.nodes.get(0) {
			Ok(root) => root.size.h == 30
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

## Text wraps against constrained ancestors even when its immediate Fit parent overflows.
expect {
	words = [test_word(0, 3, 3), test_word(3, 3, 3), test_word(6, 2, 2)]
	match build_nested_fit_text_layout(test_text_cfg(Words), "aa bb cc", 8, words, { w: 100, h: 100 }) {
		Ok(tree) => text_line_count(tree, 2) == 3 and node_width(tree, 1) == 4 and node_width(tree, 2) == 4
		Err(_) => Bool.False
	}
}

## Fit button height includes the measured text line height plus padding.
expect {
	words = [test_word(0, 9, 9)]
	match build_button_text_layout("click me", 9, 24, words, { w: 640, h: 420 }) {
		Ok(tree) => node_height(tree, 0) == 60 and node_height(tree, 1) == 24
		Err(_) => Bool.False
	}
}

## Centered button text is positioned inside the padded button bounds.
expect {
	words = [test_word(0, 9, 9)]
	match build_button_text_layout("click me", 9, 24, words, { w: 640, h: 420 }) {
		Ok(tree) => first_text_command_y(tree) == node_pos_y(tree, 0) + 18
		Err(_) => Bool.False
	}
}

## Explicit newlines create line breaks.
expect {
	words = [test_word(0, 2, 2), test_newline(2), test_word(3, 2, 2)]
	match build_text_layout(test_text_cfg(Words), "aa\nbb", 2, words, { w: 100, h: 100 }) {
		Ok(tree) => text_line_count(tree, 1) == 2
		Err(_) => Bool.False
	}
}

## Newlines mode ignores spaces as wrap opportunities.
expect {
	words = [test_word(0, 8, 8)]
	match build_text_layout(test_text_cfg(Newlines), "aa bb cc", 8, words, { w: 100, h: 100 }) {
		Ok(tree) => text_line_count(tree, 1) == 1
		Err(_) => Bool.False
	}
}

## Render extraction emits one text command per wrapped line with line-height y offsets.
expect {
	words = [test_word(0, 3, 3), test_word(3, 3, 3), test_word(6, 2, 2)]
	match build_text_layout(test_text_cfg(Words), "aa bb cc", 8, words, { w: 100, h: 100 }) {
		Ok(tree) => {
			positions = text_command_positions(tree)
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
	match build_text_layout(test_align_text_cfg(Center), "aaaaaaa bbbb", 12, words, { w: 100, h: 100 }) {
		Ok(tree) => {
			positions = text_command_positions(tree)
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
	match build_text_layout(test_align_text_cfg(Right), "aaaaaaa bbbb", 12, words, { w: 100, h: 100 }) {
		Ok(tree) => {
			positions = text_command_positions(tree)
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
	match build_text_layout(test_text_cfg(None), "aa\nbb", 5, words, { w: 100, h: 100 }) {
		Ok(tree) => text_line_count(tree, 1) == 1
		Err(_) => Bool.False
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
			and tree.text_contents.len() == 0
				and tree.text_words.len() == 0
					and tree.text_lines.len() == 0
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
			and tree.text_contents.len() == 0
				and tree.text_words.len() == 0
					and tree.text_lines.len() == 0
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

## Closing nested boxes with mixed child kinds should preserve direct-child
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
		var $tree = Layout.new()
		$tree = open_box($tree, Auto, root_cfg)?
		$tree = open_box($tree, Auto, base_cfg)?
		Ok($tree.stack.top().map_ok(|frame| frame.text).ok_or(root_text_config))
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
