## Lazily convert solved layout data into ordered semantic paint operations.
## Fallible side-table lookups are validated before iteration, while the
## traversal itself keeps only an explicit depth-first paint stack.
import Color
import Element exposing [Overflow.*, Sizing.*]
import Floating exposing [Clip.*, ZOrder.*]
import Identity exposing [NodeId]
import Layout
import LayoutTypes exposing [Bounds, LayoutNode, LayoutNodeKind.*, Placement.*, Size, TextNodeData, VisibleRegion.*]
import Text
import rr.Font

Paint := [].{
	Placement : {
		id : NodeId,
		bounds : Bounds,
		clip : Floating.Clip,
	}

	BackgroundStyle : {
		background : Color,
		radius : F32,
	}

	TextStyle : {
		font_size : F32,
		spacing : F32,
		color : Color,
	}

	BorderStyle : {
		border : Element.BorderConfig,
		radius : F32,
	}

	Op(payload) : [
		BeginScissor(Bounds),
		Background(Placement, BackgroundStyle),
		TextLine(Placement, Str, TextStyle, Font),
		Custom(Placement, payload),
		Border(Placement, BorderStyle),
		EndScissor,
	]

	## Lazily traverse a solved layout in semantic paint order.
	##
	## Paint order:
	##
	## 1. Visit roots back-to-front.
	## 2. Traverse each root depth-first.
	## 3. Emit operations by node kind:
	##    - Box: `Background`, children in declaration order, then `Border`.
	##    - Text: one `TextLine` per laid-out line, in line order.
	##    - Custom: one `Custom` operation.
	##
	## Clipping and culling:
	##
	## - A clipped root is surrounded by `BeginScissor` and `EndScissor`.
	## - A box whose descendants escape its overflow bounds surrounds its children
	##   and border with a scissor scope; its background remains outside the scope.
	## - A subtree outside the viewport or effective ancestor clip emits nothing.
	##
	## Evaluation:
	##
	## - Compute and validate traversal metadata before returning the iterator.
	## - Emit one operation at a time using an explicit depth-first stack.
	iter : Layout(payload), Size -> Try(Iter(Op(payload)), Layout.LayoutError)
	iter = |layout, screen| {
		paint_data = layout.compute_paint_data()?
		data = Data.from_layout(layout)
		roots = data.roots(BackToFront)?
		data.validate()?
		initial : PaintState(payload)
		initial = {
			data,
			paint_bounds: paint_data.paint_bounds,
			needs_clip: paint_data.needs_clip,
			roots,
			viewport: { position: { x: 0, y: 0 }, size: screen },
			root_offset: 0,
			stack: { items: [], len: 0 },
		}
		Ok(Iter.custom(initial, Unknown, next_operation))
	}
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

## Materialize the paint stream for tests without expanding Paint's API.
collect_operations : Layout(payload), Size -> Try(List(Paint.Op(payload)), Layout.LayoutError)
collect_operations = |layout, screen| Paint.iter(layout, screen).map_ok(|items| items.collect())

Cursor := {
	start : U64,
	offset : U64,
	total : U64,
}.{
	index : Cursor -> U64
	index = |cursor| cursor.start + cursor.offset

	remaining : Cursor -> U64
	remaining = |cursor| cursor.total - cursor.offset

	next : Cursor -> Cursor
	next = |cursor| { ..cursor, offset: cursor.offset + 1 }
}

Data(payload) := {
	nodes : List(LayoutNode(payload)),
	text_contents : List(Str),
	text_lines : List(Text.Line),
	child_indices : List(U64),
	node_ids : Dict(NodeId, U64),
	root_indices : List(U64),
}.{
	from_layout : Layout(payload) -> Data(payload)
	from_layout = |layout| layout.render_data()

	roots : Data(payload), Floating.ZOrder -> Try(List(Floating.RootLayer), Layout.LayoutError)
	roots = |data, order| Floating.roots_in_z_order(data.nodes, data.node_ids, data.root_indices, order)

	node : Data(payload), U64 -> Try(LayoutNode(payload), Layout.LayoutError)
	node = |data, index| data.nodes.get(index)

	## Validate and open a cursor over a node's direct children.
	children : Data(payload), LayoutNode(payload) -> Try(Cursor, Layout.LayoutError)
	children = |data, parent| {
		if parent.child_count > 0 {
			_ = data.child_indices.get(parent.child_start + parent.child_count - 1)?
		}
		Ok({ start: parent.child_start, offset: 0, total: parent.child_count })
	}

	## Advance a direct-child cursor without exposing child-index storage.
	next_child : Data(payload), Cursor -> Try([Done, Next({ index : U64, cursor : Cursor })], Layout.LayoutError)
	next_child = |data, cursor| {
		if cursor.remaining() == 0 {
			Ok(Done)
		} else {
			index = data.child_indices.get(cursor.index())?
			Ok(Next({ index, cursor: cursor.next() }))
		}
	}

	## Resolve text content and open a cursor over its laid-out lines.
	lines : Data(payload), TextNodeData -> Try({ content : Str, cursor : Cursor }, Layout.LayoutError)
	lines = |data, text| {
		content = data.text_contents.get(text.content_index)?
		if text.lines_count > 0 {
			_ = data.text_lines.get(text.lines_start + text.lines_count - 1)?
		}
		cursor = { start: text.lines_start, offset: 0, total: text.lines_count }
		Ok({ content, cursor })
	}

	## Advance a laid-out-line cursor without exposing line-table storage.
	next_line : Data(payload), Cursor -> Try([Done, Next({ line : Text.Line, cursor : Cursor })], Layout.LayoutError)
	next_line = |data, cursor| {
		if cursor.remaining() == 0 {
			Ok(Done)
		} else {
			line = data.text_lines.get(cursor.index())?
			Ok(Next({ line, cursor: cursor.next() }))
		}
	}

	## Validate side-table ranges before a paint iterator can be consumed.
	validate : Data(payload) -> Try({}, Layout.LayoutError)
	validate = |data| {
		for node_value in data.nodes {
			match node_value.kind {
				TextNode(text_data) => {
					_ = data.lines(text_data)?
				}
				_ => {}
			}
		}
		Ok({})
	}
}

PaintState(payload) : {
	data : Data(payload),
	paint_bounds : List(Bounds),
	needs_clip : List(Bool),
	roots : List(Floating.RootLayer),
	viewport : Bounds,
	root_offset : U64,
	stack : PaintStack,
}

PaintStack : {
	items : List(PaintStackFrame),
	len : U64,
}

PaintStackFrame : [
	VisitNode({ index : U64, clip : Floating.Clip }),
	VisitChildren(
		{
			cursor : Cursor,
			child_clip : Floating.Clip,
			placement : Paint.Placement,
			border : Paint.BorderStyle,
			should_clip : Bool,
			started : Bool,
		},
	),
	VisitTextLines(
		{
			content : Str,
			align : Element.TextAlign,
			font : Font,
			placement : Paint.Placement,
			style : Paint.TextStyle,
			cursor : Cursor,
		},
	),
	FinishScissor,
]

## Advance the explicit DFS paint stack until one semantic operation is ready.
next_operation : PaintState(payload) -> Try((Paint.Op(payload), PaintState(payload)), [NoMore])
next_operation = |state| {
	var $state = state
	while Bool.True {
		match pop_frame($state.stack) {
			Empty => match $state.roots.get($state.root_offset) {
				Err(_) => return Err(NoMore)
				Ok(root) => {
					$state = { ..$state, root_offset: $state.root_offset + 1 }
					visit = VisitNode({ index: root.index, clip: root.clip })
					match root.clip {
						Unclipped => {
							$state = { ..$state, stack: push_frame($state.stack, visit) }
						}
						Clipped(bounds) => {
							op = BeginScissor(bounds)
							$state = { ..$state, stack: push_frame($state.stack, FinishScissor) }
							$state = { ..$state, stack: push_frame($state.stack, visit) }
							return Ok((op, $state))
						}
					}
				}
			}
			Frame({ item, rest }) => {
				$state = { ..$state, stack: rest }
				match item {
					FinishScissor => return Ok((EndScissor, $state))
					VisitNode({ index, clip }) => {
						node = $state.data.node(index) ? |_| NoMore
						subtree_paint_bounds = $state.paint_bounds.get(index) ? |_| NoMore
						if LayoutTypes.visible_region(subtree_paint_bounds, $state.viewport, clip) != Culled {
							placement = { id: node.id, bounds: node_paint_bounds(node), clip }
							match node.kind {
								BoxNode(box) => {
									cursor = $state.data.children(node) ? |_| NoMore
									should_clip = $state.needs_clip.get(index) ? |_| NoMore
									children = VisitChildren({
										cursor,
										child_clip: effective_child_clip(placement, box),
										placement,
										border: border_style(box),
										should_clip,
										started: Bool.False,
									})
									$state = { ..$state, stack: push_frame($state.stack, children) }
									op = Background(placement, background_style(box))
									return Ok((op, $state))
								}
								TextNode(text_data) => {
									text = $state.data.lines(text_data) ? |_| NoMore
									if text.cursor.remaining() > 0 {
										lines = VisitTextLines({
											content: text.content,
											align: text_data.config.align,
											font: text_data.font,
											placement,
											style: text_style(text_data.config),
											cursor: text.cursor,
										})
										$state = { ..$state, stack: push_frame($state.stack, lines) }
									}
								}
								CustomNode(custom_data) => return Ok((Custom(placement, custom_data.payload), $state))
							}
						}
					}
					VisitChildren(children) => {
						if !children.started {
							next_children = VisitChildren({ ..children, started: Bool.True })
							$state = { ..$state, stack: push_frame($state.stack, next_children) }
							if children.should_clip {
								clip_bounds = match children.child_clip {
									Clipped(bounds) => bounds
									Unclipped => children.placement.bounds
								}
								op = BeginScissor(clip_bounds)
								return Ok((op, $state))
							}
						} else {
							child_step = $state.data.next_child(children.cursor) ? |_| NoMore
							match child_step {
								Next({ index: child_index, cursor }) => {
									next_children = VisitChildren({ ..children, cursor })
									visit = VisitNode({ index: child_index, clip: children.child_clip })
									$state = { ..$state, stack: push_frame(push_frame($state.stack, next_children), visit) }
								}
								Done => {
									op = Border(children.placement, children.border)
									$state = { ..$state, stack: if children.should_clip push_frame($state.stack, FinishScissor) else $state.stack }
									return Ok((op, $state))
								}
							}
						}
					}
					VisitTextLines(lines) => {
						line_result = $state.data.next_line(lines.cursor) ? |_| NoMore
						line_step = match line_result {
							Next(value) => value
							Done => return Err(NoMore)
						}
						line_bounds = Text.line_bounds(lines.placement.bounds.flatten(), lines.align, line_step.line, lines.cursor.offset)
						line_placement = { ..lines.placement, bounds: line_bounds }
						segment = Text.line_text(lines.content, line_step.line)
						op = TextLine(line_placement, segment, lines.style, lines.font)

						next_stack = if line_step.cursor.remaining() > 0 {
							push_frame($state.stack, VisitTextLines({ ..lines, cursor: line_step.cursor }))
						} else {
							$state.stack
						}
						$state = { ..$state, stack: next_stack }

						return Ok((op, $state))
					}
				}
			}
		}
	}
	Err(NoMore)
}

## Reuse stack slots after popping, so allocation grows with maximum traversal
## depth rather than with the number of paint operations.
push_frame : PaintStack, PaintStackFrame -> PaintStack
push_frame = |stack, item| {
	if stack.len < stack.items.len() {
		items = match stack.items.set(stack.len, item) {
			Ok(updated) => updated
			Err(_) => stack.items
		}
		{ items, len: stack.len + 1 }
	} else {
		{ items: stack.items.append(item), len: stack.len + 1 }
	}
}

pop_frame : PaintStack -> [Empty, Frame({ item : PaintStackFrame, rest : PaintStack })]
pop_frame = |stack| {
	if stack.len == 0 {
		Empty
	} else {
		match stack.items.get(stack.len - 1) {
			Err(_) => Empty
			Ok(item) => Frame({ item, rest: { ..stack, len: stack.len - 1 } })
		}
	}
}

## Compute the clip inherited by a box's descendants.
effective_child_clip : Paint.Placement, LayoutTypes.BoxNodeData -> Floating.Clip
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

## Expand a floating root's own painted rectangle by its declared expansion.
node_paint_bounds : LayoutNode(payload) -> Bounds
node_paint_bounds = |node| {
	bounds = { position: node.position, size: node.size }
	match node.placement {
		Normal => bounds
		Floating(config) => bounds.expand(config.expand)
	}
}

## Build and solve a public view for paint traversal tests.
build_test_layout = |view, screen| {
	var $layout = Layout.test_layout()
	status = { hovered: Bool.False, pressed: Bool.False, focused: Bool.False, disabled: Bool.False }
	for operation in view {
		($layout, _) = $layout.update(operation, |_| status, |_| { x: 0, y: 0 })?
	}
	$layout.solve(screen)
}

## Overflow scopes wrap children and the parent border, but not its background.
expect {
	root_style = Element.style
		.width(Fixed(100))
		.height(Fixed(60))
		.background(Color.gray)
		.radius(7)
		.border({ color: Color.black, left: 1, right: 2, top: 3, bottom: 4 })
		.overflow(Hidden, Hidden)
	child_style = Element.style
		.width(Fixed(90))
		.height(Fixed(80))
		.overflow(Visible, Visible)
	view : Element.View({}, {})
	view = Element.box(
		{ style: |_| root_style },
		[
			Element.box({ style: |_| child_style }, []),
			Element.box({ style: |_| child_style }, []),
		],
	)

	match build_test_layout(view, { w: 200, h: 200 }) {
		Ok(layout) => match collect_operations(layout, { w: 200, h: 200 }) {
			Ok(
				[
					Background(root_placement, root_background),
					BeginScissor(bounds),
					Background(_, _),
					Border(_, _),
					Background(_, _),
					Border(_, _),
					Border(border_placement, root_border),
					EndScissor,
				],
			) => bounds == root_placement.bounds
				and border_placement.id == root_placement.id
					and root_background == { background: Color.gray, radius: 7 }
						and root_border == { border: { color: Color.black, left: 1, right: 2, top: 3, bottom: 4 }, radius: 7 }
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

## Opaque custom payloads remain attached to their solved placement.
expect {
	view : Element.View({}, [Token(U64)])
	view = Element.box(
		{
			style: |_| Element.style
				.width(Fixed(40))
				.height(Fixed(30)),
		},
		[Element.custom(Token(7))],
	)

	match build_test_layout(view, { w: 100, h: 100 }) {
		Ok(layout) => match collect_operations(layout, { w: 100, h: 100 }) {
			Ok([Background(_, _), Custom(placement, Token(value)), Border(_, _)]) =>
				value == 7 and placement.bounds.size == { w: 40, h: 30 }
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}
