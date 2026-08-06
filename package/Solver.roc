## Pure layout geometry, sizing, and positioning.
import Element
import LayoutTypes exposing [
	Axis,
	Axis.*,
	LayoutNode,
	LayoutNodeKind.*,
	ParentIndex.*,
	Pos,
	Placement.*,
	Size,
]

SolverError : [InternalError, OutOfBounds]

Solver :: [].{

	box_intrinsic_size : LayoutNode, Element.LayoutConfig, List(LayoutNode), List(U64) -> Try(Size, [OutOfBounds, ..])
	box_intrinsic_size = |node, lc, nodes, child_indices| {
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
		Ok({ w: intrinsic_w, h: intrinsic_h })
	}

	## Position one independent root and its descendants from the supplied origin.
	solve_root_position : List(LayoutNode), List(U64), U64, Pos -> Try(List(LayoutNode), [OutOfBounds, ..])
	solve_root_position = |nodes, child_indices, root_index, position|
		position_subtree(nodes, child_indices, root_index, position)

	## Re-resolve one axis of an independent root and its descendants against an
	## attachment rectangle. Floating X sizes must be final before text wrapping.
	solve_root_size_axis : List(LayoutNode), List(U64), U64, Axis, Size -> Try(List(LayoutNode), [OutOfBounds, InternalError, ..])
	solve_root_size_axis = |nodes, child_indices, root_index, axis, available|
		resolve_root_axis_against(nodes, child_indices, root_index, axis, available)

	## Measure solved child content bounds for every layout node.
	update_content_sizes : List(LayoutNode), List(U64) -> Try(List(LayoutNode), [OutOfBounds, ..])
	update_content_sizes = |nodes, child_indices| update_content_size_range(nodes, child_indices, 0, nodes.len())
}

resolve_root_axis_against : List(LayoutNode), List(U64), U64, Axis, Size -> Try(List(LayoutNode), [OutOfBounds, InternalError, ..])
resolve_root_axis_against = |nodes, child_indices, root_index, axis, available| {
	root = nodes.get(root_index)?
	sizing = match axis {
		XAxis => root.sizing_w
		YAxis => root.sizing_h
	}
	intrinsic = match axis {
		XAxis => root.intrinsic.w
		YAxis => root.intrinsic.h
	}
	available_axis = match axis {
		XAxis => available.w
		YAxis => available.h
	}
	sized = set_size_along(root, axis, resolve_main_size(sizing, intrinsic, available_axis))
	var $nodes = nodes.set(root_index, sized)?
	$nodes = solve_descendant_axis($nodes, child_indices, root_index, axis)?
	Ok($nodes)
}

solve_descendant_axis : List(LayoutNode), List(U64), U64, Axis -> Try(List(LayoutNode), [OutOfBounds, InternalError, ..])
solve_descendant_axis = |nodes, child_indices, parent_index, axis| {
	parent = nodes.get(parent_index)?
	var $nodes = match parent.kind {
		BoxNode(data) => distribute_child_sizes_along(nodes, child_indices, parent, data.layout, axis)?
		_ => nodes
	}
	for offset in 0..<parent.child_count {
		child_index = child_indices.get(parent.child_start + offset)?
		$nodes = solve_descendant_axis($nodes, child_indices, child_index, axis)?
	}
	Ok($nodes)
}

# --- Sizing Helpers ---

is_grow_sizing : Element.Sizing -> Bool
is_grow_sizing = |s| match s {
	Grow(_) => Bool.True
	_ => Bool.False
}

apply_bounds : F32, { min : F32, max : F32 } -> F32
apply_bounds = |value, bounds| {
	if value < bounds.min {
		bounds.min
	} else if value > bounds.max {
		bounds.max
	} else {
		value
	}
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
	Fit(b) => {
		capped = if parent_avail > 0 and content_size > parent_avail {
			parent_avail
		} else {
			content_size
		}
		apply_bounds(capped, b)
	}
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

set_size_along : LayoutNode, Axis, F32 -> LayoutNode
set_size_along = |node, axis, value| match axis {
	XAxis => { ..node, size: { ..node.size, w: value } }
	YAxis => { ..node, size: { ..node.size, h: value } }
}

sum_gap : F32, U64 -> F32
sum_gap = |gap, count|
	if count <= 1.U64 {
		0.0
	} else {
		gap * (count - 1.U64).to_f32()
	}

sum_children_intrinsic : List(LayoutNode), List(U64), U64, U64, Element.Direction -> Try(F32, [OutOfBounds, ..])
sum_children_intrinsic = |nodes, child_indices, start, count, dir| {
	var $sum = 0
	for offset in 0..<count {
		child_idx = child_indices.get(start + offset)?
		child = nodes.get(child_idx)?
		$sum = $sum + child.intrinsic.along(dir)
	}
	Ok($sum)
}

max_children_intrinsic : List(LayoutNode), List(U64), U64, U64, Element.Direction -> Try(F32, [OutOfBounds, ..])
max_children_intrinsic = |nodes, child_indices, start, count, dir| {
	var $max = 0
	for offset in 0..<count {
		child_idx = child_indices.get(start + offset)?
		child = nodes.get(child_idx)?
		val = child.intrinsic.across(dir)
		if val > $max {
			$max = val
		}
	}
	Ok($max)
}

sum_children_size : List(LayoutNode), List(U64), U64, U64, Element.Direction -> Try(F32, [OutOfBounds, ..])
sum_children_size = |nodes, child_indices, start, count, dir| {
	var $sum = 0
	for offset in 0..<count {
		child_idx = child_indices.get(start + offset)?
		child = nodes.get(child_idx)?
		$sum = $sum + child.size.along(dir)
	}
	Ok($sum)
}

# --- Solver Passes ---

## Position a subtree recursively after fixing its root at an absolute origin.
position_subtree : List(LayoutNode), List(U64), U64, Pos -> Try(List(LayoutNode), [OutOfBounds, ..])
position_subtree = |nodes, child_indices, index, position| {
	node = nodes.get(index)?
	positioned = { ..node, position }
	positioned_nodes = nodes.set(index, positioned)?
	position_descendants(positioned_nodes, child_indices, index)
}

## Position descendants whose root already has its final absolute position.
position_descendants : List(LayoutNode), List(U64), U64 -> Try(List(LayoutNode), [OutOfBounds, ..])
position_descendants = |nodes, child_indices, index| {
	node = nodes.get(index)?
	var $nodes = match node.kind {
		BoxNode(data) => position_children(nodes, child_indices, index, data.layout)?
		_ => nodes
	}
	for offset in 0..<node.child_count {
		child_index = child_indices.get(node.child_start + offset)?
		$nodes = position_descendants($nodes, child_indices, child_index)?
	}
	Ok($nodes)
}

ChildMetrics : { non_grow_sum : F32, grow_count : F32 }

compute_child_metrics : List(LayoutNode), List(U64), U64, U64, Axis, F32 -> Try(ChildMetrics, [OutOfBounds, ..])
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

distribute_child_sizes_along : List(LayoutNode), List(U64), LayoutNode, Element.LayoutConfig, Axis -> Try(List(LayoutNode), [OutOfBounds, ..])
distribute_child_sizes_along = |nodes, child_indices, parent, lc, axis| {
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

set_child_sizes_range : List(LayoutNode), List(U64), U64, U64, Axis, F32, F32 -> Try(List(LayoutNode), [OutOfBounds, ..])
set_child_sizes_range = |nodes, child_indices, start, count, axis, parent_avail, grow_fill| {
	if count == 0 {
		Ok(nodes)
	} else {
		child_idx = child_indices.get(start)?
		child = nodes.get(child_idx)?
		updated = {
			my_sizing = match axis {
				XAxis => child.sizing_w
				YAxis => child.sizing_h
			}
			my_intrinsic = match axis {
				XAxis => child.intrinsic.w
				YAxis => child.intrinsic.h
			}
			child_size = resolve_child_axis(my_sizing, my_intrinsic, parent_avail, grow_fill)
			set_size_along(child, axis, child_size)
		}
		new_nodes = nodes.set(child_idx, updated)?
		set_child_sizes_range(new_nodes, child_indices, start + 1.U64, count - 1.U64, axis, parent_avail, grow_fill)
	}
}

position_children : List(LayoutNode), List(U64), U64, Element.LayoutConfig -> Try(List(LayoutNode), [OutOfBounds, ..])
position_children = |nodes, child_indices, parent_idx, lc| {
	parent = nodes.get(parent_idx)?
	dir = lc.direction
	align_x = lc.child_align.x
	align_y = lc.child_align.y
	inner_w = parent.size.w - lc.pad.left - lc.pad.right
	inner_h = parent.size.h - lc.pad.top - lc.pad.bottom
	sum_along = sum_children_size(nodes, child_indices, parent.child_start, parent.child_count, dir)?
	gaps_val = sum_gap(lc.gap, parent.child_count)
	main_avail = match dir {
		Row => inner_w
		Col => inner_h
	}
	on_axis_extra = main_avail - sum_along - gaps_val
	start_cursor = axis_offset(
		on_axis_extra,
		match dir {
			Row => align_x
			Col => align_y
		},
	)
	position_child_range(
		nodes,
		child_indices,
		parent.child_start,
		parent.child_count,
		{
			dir,
			gap: lc.gap,
			content_x: parent.position.x + lc.pad.left + parent.scroll_offset.x,
			content_y: parent.position.y + lc.pad.top + parent.scroll_offset.y,
			inner_w,
			inner_h,
			cursor: start_cursor,
			align_x,
			align_y,
		},
	)
}

## Measure solved content sizes across a contiguous node range.
update_content_size_range : List(LayoutNode), List(U64), U64, U64 -> Try(List(LayoutNode), [OutOfBounds, ..])
update_content_size_range = |nodes, child_indices, start, end| {
	if start >= end {
		Ok(nodes)
	} else {
		node = nodes.get(start)?
		next = match node.kind {
			BoxNode(box) => {
				sum_along = sum_children_size(nodes, child_indices, node.child_start, node.child_count, box.layout.direction)?
				max_across = max_children_size(nodes, child_indices, node.child_start, node.child_count, box.layout.direction)?
				gaps = sum_gap(box.layout.gap, node.child_count)
				content = match box.layout.direction {
					Row => { w: sum_along + box.layout.pad.left + box.layout.pad.right + gaps, h: max_across + box.layout.pad.top + box.layout.pad.bottom }
					Col => { w: max_across + box.layout.pad.left + box.layout.pad.right, h: sum_along + box.layout.pad.top + box.layout.pad.bottom + gaps }
				}
				nodes.set(start, { ..node, content_size: content })?
			}
			_ => nodes.set(start, { ..node, content_size: node.intrinsic })?
		}
		update_content_size_range(next, child_indices, start + 1, end)
	}
}

## Return the largest solved child size across the layout direction.
max_children_size : List(LayoutNode), List(U64), U64, U64, Element.Direction -> Try(F32, [OutOfBounds, ..])
max_children_size = |nodes, child_indices, start, count, dir| {
	var $max = 0
	for offset in 0..<count {
		child = nodes.get(child_indices.get(start + offset)?)?
		value = child.size.across(dir)
		if value > $max { $max = value }
	}
	Ok($max)
}

PositionContext : {
	dir : Element.Direction,
	gap : F32,
	content_x : F32,
	content_y : F32,
	inner_w : F32,
	inner_h : F32,
	cursor : F32,
	align_x : Element.ChildAlign,
	align_y : Element.ChildAlign,
}

position_child_range : List(LayoutNode), List(U64), U64, U64, PositionContext -> Try(List(LayoutNode), [OutOfBounds, ..])
position_child_range = |nodes, child_indices, start, count, ctx| {
	if count == 0 {
		Ok(nodes)
	} else {
		child_idx = child_indices.get(start)?
		child = nodes.get(child_idx)?
		cross_off = cross_offset(
			match ctx.dir {
				Row => child.size.h
				Col => child.size.w
			},
			match ctx.dir {
				Row => ctx.inner_h
				Col => ctx.inner_w
			},
			match ctx.dir {
				Row => ctx.align_y
				Col => ctx.align_x
			},
		)
		child_x = match ctx.dir {
			Row => ctx.content_x + ctx.cursor
			Col => ctx.content_x + cross_off
		}
		child_y = match ctx.dir {
			Row => ctx.content_y + cross_off
			Col => ctx.content_y + ctx.cursor
		}
		step = match ctx.dir {
			Row => child.size.w
			Col => child.size.h
		}
		updated = { ..child, position: { x: child_x, y: child_y } }
		new_nodes = nodes.set(child_idx, updated)?
		next_ctx = { ..ctx, cursor: ctx.cursor + step + ctx.gap }
		position_child_range(new_nodes, child_indices, start + 1.U64, count - 1.U64, next_ctx)
	}
}

## TESTS ##

test_node : U64, LayoutNodeKind, ParentIndex, U64, U64, Size, Element.Sizing, Element.Sizing -> LayoutNode
test_node = |id, kind, parent, child_start, child_count, intrinsic, sizing_w, sizing_h| {
	{
		id,
		kind,
		parent,
		child_start,
		child_count,
		intrinsic,
		size: { w: 0, h: 0 },
		content_size: intrinsic,
		scroll_offset: { x: 0, y: 0 },
		position: { x: 0, y: 0 },
		sizing_w,
		sizing_h,
		placement: Normal,
	}
}

test_box_with_layout : U64, ParentIndex, U64, U64, Size, Element.LayoutConfig -> LayoutNode
test_box_with_layout = |id, parent, child_start, child_count, intrinsic, layout| {
	test_node(
		id,
		BoxNode(
			{
				layout: layout,
				background: Element.style.background,
				radius: Element.style.radius,
				border: Element.style.border,
				overflow: Element.style.overflow,
			},
		),
		parent,
		child_start,
		child_count,
		intrinsic,
		layout.width,
		layout.height,
	)
}

test_box : U64, ParentIndex, U64, U64, Size, Element.Sizing, Element.Sizing -> LayoutNode
test_box = |id, parent, child_start, child_count, intrinsic, sizing_w, sizing_h| {
	layout = { ..Element.style.layout, width: sizing_w, height: sizing_h }
	test_box_with_layout(id, parent, child_start, child_count, intrinsic, layout)
}

test_fixed_box : U64, ParentIndex, F32, F32 -> LayoutNode
test_fixed_box = |id, parent, w, h| {
	test_box(id, parent, 0, 0, { w, h }, Fixed(w), Fixed(h))
}

test_solve : List(LayoutNode), List(U64), Size -> Try(List(LayoutNode), [OutOfBounds, InternalError,..])
test_solve = |nodes, child_indices, screen| {
	var $nodes = Solver.solve_root_size_axis(nodes, child_indices, 0, XAxis, screen)?
	$nodes = Solver.solve_root_size_axis($nodes, child_indices, 0, YAxis, screen)?
	Solver.solve_root_position($nodes, child_indices, 0, { x: 0, y: 0 })
}

test_intrinsic_size : Element.Direction -> Bool
test_intrinsic_size = |direction| {
	cfg = Element.style
		.width(Fit({ min: 0, max: 1000 }))
		.height(Fit({ min: 0, max: 1000 }))
		.direction(direction)
		.gap(6)
		.pad((3, 4, 5, 7))
	parent = test_box_with_layout(1, NoParent, 0, 2, { w: 0, h: 0 }, cfg.layout)
	child_a = test_fixed_box(2, Parent(0), 10, 20)
	child_b = test_fixed_box(3, Parent(0), 15, 30)
	expected = match direction {
		Row => { w: 38, h: 42 }
		Col => { w: 22, h: 68 }
	}

	match Solver.box_intrinsic_size(parent, cfg.layout, [parent, child_a, child_b], [1, 2]) {
		Ok(size) => size == expected
		Err(_) => Bool.False
	}
}

## Intrinsic size should sum children along the layout direction and use the
## maximum child size across it, including padding and gaps.
expect {
	test_intrinsic_size(Row) and test_intrinsic_size(Col)
}

## Root percent sizing should resolve against the screen size on each axis.
expect {
	cfg = Element.style
		.width(Percent(0.5))
		.height(Percent(0.25))
	root = test_box_with_layout(1, NoParent, 0, 0, { w: 0, h: 0 }, cfg.layout)

	match test_solve([root], [], { w: 200, h: 80 }) {
		Ok(nodes) => match nodes.get(0) {
			Ok(node) => node.size == { w: 100, h: 20 } and node.position == { x: 0, y: 0 }
			Err(_) => Bool.False
		}
		Err(_) => Bool.False
	}
}

test_grow_distribution : Element.Direction -> Bool
test_grow_distribution = |direction| {
	root_cfg = match direction {
		Row => Element.style
			.width(Fixed(120))
			.height(Fixed(40))
			.direction(Row)
			.child_align({ x: Start, y: Start })
			.gap(5)
			.pad((10, 10, 0, 0))
		Col => Element.style
			.width(Fixed(40))
			.height(Fixed(120))
			.direction(Col)
			.child_align({ x: Start, y: Start })
			.gap(5)
			.pad((0, 0, 10, 10))
	}
	root = test_box_with_layout(1, NoParent, 0, 3, { w: 0, h: 0 }, root_cfg.layout)
	fixed = match direction {
		Row => test_fixed_box(2, Parent(0), 20, 10)
		Col => test_fixed_box(2, Parent(0), 10, 20)
	}
	grow_a = match direction {
		Row => test_box(3, Parent(0), 0, 0, { w: 0, h: 10 }, Grow({ min: 0, max: 1000 }), Fixed(10))
		Col => test_box(3, Parent(0), 0, 0, { w: 10, h: 0 }, Fixed(10), Grow({ min: 0, max: 1000 }))
	}
	grow_b = match direction {
		Row => test_box(4, Parent(0), 0, 0, { w: 0, h: 10 }, Grow({ min: 0, max: 1000 }), Fixed(10))
		Col => test_box(4, Parent(0), 0, 0, { w: 10, h: 0 }, Fixed(10), Grow({ min: 0, max: 1000 }))
	}

	match test_solve([root, fixed, grow_a, grow_b], [1, 2, 3], { w: 120, h: 40 }) {
		Ok(nodes) => match (nodes.get(1), nodes.get(2), nodes.get(3)) {
			(Ok(a), Ok(b), Ok(c)) => match direction {
				Row => {
					actual =
						\\a size: ${Str.inspect(a.size == { w: 20, h: 10 })}
						\\b size: ${Str.inspect(b.size == { w: 35, h: 10 })}
						\\c size: ${Str.inspect(c.size == { w: 35, h: 10 })}
						\\a position: ${Str.inspect(a.position == { x: 10, y: 0 })}
						\\b position: ${Str.inspect(b.position == { x: 35, y: 0 })}
						\\c position: ${Str.inspect(c.position == { x: 75, y: 0 })}

					expected =
						\\a size: True
						\\b size: True
						\\c size: True
						\\a position: True
						\\b position: True
						\\c position: True

					actual == expected
				}
				Col => {
					actual =
						\\a size: ${Str.inspect(a.size == { w: 10, h: 20 })}
						\\b size: ${Str.inspect(b.size == { w: 10, h: 35 })}
						\\c size: ${Str.inspect(c.size == { w: 10, h: 35 })}
						\\a position: ${Str.inspect(a.position == { x: 0, y: 10 })}
						\\b position: ${Str.inspect(b.position == { x: 0, y: 35 })}
						\\c position: ${Str.inspect(c.position == { x: 0, y: 75 })}

					expected =
						\\a size: True
						\\b size: True
						\\c size: True
						\\a position: True
						\\b position: True
						\\c position: True

					actual == expected
				}
			}
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

## Grow children should share remaining main-axis space after fixed children,
## padding, and gaps are accounted for.
expect {
	test_grow_distribution(Row) and test_grow_distribution(Col)
}

## Cross-axis grow should fill the parent's inner size, while main-axis center
## alignment should only use positive extra space.
expect {
	root_cfg = Element.style
		.width(Fixed(100))
		.height(Fixed(50))
		.direction(Row)
		.child_align({ x: Center, y: Start })
		.pad((5, 5, 3, 7))
	child = test_box(2, Parent(0), 0, 0, { w: 20, h: 0 }, Fixed(20), Grow({ min: 0, max: 1000 }))
	root = test_box_with_layout(1, NoParent, 0, 1, { w: 0, h: 0 }, root_cfg.layout)

	match test_solve([root, child], [1], { w: 100, h: 50 }) {
		Ok(nodes) => match nodes.get(1) {
			Ok(node) => node.size == { w: 20, h: 40 } and node.position == { x: 40, y: 3 }
			Err(_) => Bool.False
		}
		Err(_) => Bool.False
	}
}

## Nested boxes should be sized and positioned in DFS order, with child percent
## sizing resolving against the nearest parent's inner size.
expect {
	root_cfg = Element.style
		.width(Fixed(200))
		.height(Fixed(100))
		.direction(Row)
		.child_align({ x: Start, y: Start })
		.gap(4)
		.pad((10, 10, 5, 5))
	nested_cfg = Element.style
		.width(Percent(0.5))
		.height(Grow({ min: 0, max: 1000 }))
		.direction(Col)
		.child_align({ x: End, y: Start })
		.pad((2, 3, 4, 5))
	root = test_box_with_layout(1, NoParent, 1, 2, { w: 0, h: 0 }, root_cfg.layout)
	nested = test_box_with_layout(2, Parent(0), 0, 1, { w: 0, h: 0 }, nested_cfg.layout)
	leaf = test_fixed_box(3, Parent(1), 20, 10)
	sibling = test_fixed_box(4, Parent(0), 30, 20)

	match test_solve([root, nested, leaf, sibling], [2, 1, 3], { w: 200, h: 100 }) {
		Ok(nodes) => match (nodes.get(1), nodes.get(2), nodes.get(3)) {
			(Ok(n), Ok(l), Ok(s)) => {
				actual =
					\\nested size: ${Str.inspect(n.size == { w: 90, h: 90 })}
					\\nested position: ${Str.inspect(n.position == { x: 10, y: 5 })}
					\\leaf size: ${Str.inspect(l.size == { w: 20, h: 10 })}
					\\leaf position: ${Str.inspect(l.position == { x: 77, y: 9 })}
					\\sibling position: ${Str.inspect(s.position == { x: 104, y: 5 })}

				expected =
					\\nested size: True
					\\nested position: True
					\\leaf size: True
					\\leaf position: True
					\\sibling position: True

				actual == expected
			}
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

test_mixed_sizing : Element.Direction -> Bool
test_mixed_sizing = |direction| {
	root_cfg = match direction {
		Row => Element.style
			.width(Fixed(240))
			.height(Fixed(60))
			.direction(Row)
			.child_align({ x: Start, y: Start })
			.gap(5)
			.pad((10, 10, 0, 0))
		Col => Element.style
			.width(Fixed(60))
			.height(Fixed(240))
			.direction(Col)
			.child_align({ x: Start, y: Start })
			.gap(5)
			.pad((0, 0, 10, 10))
	}
	root = test_box_with_layout(1, NoParent, 0, 4, { w: 0, h: 0 }, root_cfg.layout)
	fixed = match direction {
		Row => test_fixed_box(2, Parent(0), 20, 10)
		Col => test_fixed_box(2, Parent(0), 10, 20)
	}
	percent = match direction {
		Row => test_box(3, Parent(0), 0, 0, { w: 0, h: 10 }, Percent(0.25), Fixed(10))
		Col => test_box(3, Parent(0), 0, 0, { w: 10, h: 0 }, Fixed(10), Percent(0.25))
	}
	fit = match direction {
		Row => test_box(4, Parent(0), 0, 0, { w: 30, h: 10 }, Fit({ min: 0, max: 1000 }), Fixed(10))
		Col => test_box(4, Parent(0), 0, 0, { w: 10, h: 30 }, Fixed(10), Fit({ min: 0, max: 1000 }))
	}
	grow = match direction {
		Row => test_box(5, Parent(0), 0, 0, { w: 0, h: 10 }, Grow({ min: 0, max: 1000 }), Fixed(10))
		Col => test_box(5, Parent(0), 0, 0, { w: 10, h: 0 }, Fixed(10), Grow({ min: 0, max: 1000 }))
	}

	match test_solve([root, fixed, percent, fit, grow], [1, 2, 3, 4], { w: 240, h: 60 }) {
		Ok(nodes) => match (nodes.get(1), nodes.get(2), nodes.get(3), nodes.get(4)) {
			(Ok(a), Ok(b), Ok(c), Ok(d)) => match direction {
				Row => {
					actual =
						\\fixed size: ${Str.inspect(a.size == { w: 20, h: 10 })}
						\\percent size: ${Str.inspect(b.size == { w: 55, h: 10 })}
						\\fit size: ${Str.inspect(c.size == { w: 30, h: 10 })}
						\\grow size: ${Str.inspect(d.size == { w: 100, h: 10 })}
						\\fixed position: ${Str.inspect(a.position == { x: 10, y: 0 })}
						\\percent position: ${Str.inspect(b.position == { x: 35, y: 0 })}
						\\fit position: ${Str.inspect(c.position == { x: 95, y: 0 })}
						\\grow position: ${Str.inspect(d.position == { x: 130, y: 0 })}

					expected =
						\\fixed size: True
						\\percent size: True
						\\fit size: True
						\\grow size: True
						\\fixed position: True
						\\percent position: True
						\\fit position: True
						\\grow position: True

					actual == expected
				}
				Col => {
					actual =
						\\fixed size: ${Str.inspect(a.size == { w: 10, h: 20 })}
						\\percent size: ${Str.inspect(b.size == { w: 10, h: 55 })}
						\\fit size: ${Str.inspect(c.size == { w: 10, h: 30 })}
						\\grow size: ${Str.inspect(d.size == { w: 10, h: 100 })}
						\\fixed position: ${Str.inspect(a.position == { x: 0, y: 10 })}
						\\percent position: ${Str.inspect(b.position == { x: 0, y: 35 })}
						\\fit position: ${Str.inspect(c.position == { x: 0, y: 95 })}
						\\grow position: ${Str.inspect(d.position == { x: 0, y: 130 })}

					expected =
						\\fixed size: True
						\\percent size: True
						\\fit size: True
						\\grow size: True
						\\fixed position: True
						\\percent position: True
						\\fit position: True
						\\grow position: True

					actual == expected
				}
			}
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

## Mixed fixed, percent, fit, and grow children should resolve from the same
## parent inner size and leave only remaining main-axis space for grow.
expect {
	test_mixed_sizing(Row) and test_mixed_sizing(Col)
}

## Solver should surface out-of-bounds child index data as an OutOfBounds error.
expect {
	root_cfg = Element.style
		.width(Fixed(100))
		.height(Fixed(50))
	root = test_box_with_layout(1, NoParent, 0, 1, { w: 0, h: 0 }, root_cfg.layout)

	match Solver.solve_root_size_axis([root], [99], 0, XAxis, { w: 100, h: 50 }) {
		Err(OutOfBounds) => Bool.True
		_ => Bool.False
	}
}
