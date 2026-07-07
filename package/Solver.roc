## Pure layout geometry, sizing, and positioning.
import Element
import LayoutTypes exposing [
	Axis,
	Axis.*,
	LayoutNode,
	LayoutNodeKind.*,
	LayoutPayload,
	LayoutPayload.*,
	ParentIndex.*,
	Pos,
	Size,
]

SolverError : [InternalError, OutOfBounds]

Solver :: [].{

	box_intrinsic_size : LayoutNode, Element.LayoutConfig, List(LayoutNode), List(U64) -> Try(Size, SolverError)
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

	solve_size_axis : List(LayoutNode), List(LayoutPayload), List(U64), Axis, Size -> Try(List(LayoutNode), SolverError)
	solve_size_axis = |nodes, payloads, child_indices, axis, screen| {
		n = nodes.len()
		if n == 0 {
			Ok(nodes)
		} else {
			solve_size_axis_from(nodes, payloads, child_indices, 0, n, axis, screen)
		}
	}

	solve_position : List(LayoutNode), List(LayoutPayload), List(U64) -> Try(List(LayoutNode), SolverError)
	solve_position = |nodes, payloads, child_indices| {
		n = nodes.len()
		if n == 0 {
			Ok(nodes)
		} else {
			var $nodes = nodes
			for i in 0..<n {
				node = $nodes.get(i)?
				if node.parent == NoParent {
					$nodes = $nodes.set(i, { ..node, position: { x: 0, y: 0 } })?
				}
				if node.kind == BoxNode {
					$nodes = position_children($nodes, payloads, child_indices, i)?
				}
			}
			Ok($nodes)
		}
	}
}

# --- Sizing Helpers ---

is_grow_sizing : Element.Sizing -> Bool
is_grow_sizing = |s| match s {
	Grow(_) => Bool.True
	_ => Bool.False
}

apply_bounds : F32, { min : F32, max : F32 } -> F32
apply_bounds = |value, bounds| {
	if value < bounds.min bounds.min else if value > bounds.max bounds.max else value
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

sum_children_intrinsic : List(LayoutNode), List(U64), U64, U64, Element.Direction -> Try(F32, SolverError)
sum_children_intrinsic = |nodes, child_indices, start, count, dir| {
	var $sum = 0
	for offset in 0..<count {
		child_idx = child_indices.get(start + offset)?
		child = nodes.get(child_idx)?
		$sum = $sum + child.intrinsic.along(dir)
	}
	Ok($sum)
}

max_children_intrinsic : List(LayoutNode), List(U64), U64, U64, Element.Direction -> Try(F32, SolverError)
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

sum_children_size : List(LayoutNode), List(U64), U64, U64, Element.Direction -> Try(F32, SolverError)
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

resolve_parent_avail_along : List(LayoutNode), List(LayoutPayload), LayoutNode, Axis, Size -> Try(F32, SolverError)
resolve_parent_avail_along = |nodes, payloads, node, axis, screen| {
	match node.parent {
		NoParent => Ok(
			match axis {
				XAxis => screen.w
				YAxis => screen.h
			},
		)
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

## Resolve one node's size along an axis, returning the updated node list and node.
resolve_node_size_along : List(LayoutNode), List(LayoutPayload), U64, Axis, Size -> Try({ nodes : List(LayoutNode), node : LayoutNode }, SolverError)
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
solve_size_axis_from : List(LayoutNode), List(LayoutPayload), List(U64), U64, U64, Axis, Size -> Try(List(LayoutNode), SolverError)
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

compute_child_metrics : List(LayoutNode), List(U64), U64, U64, Axis, F32 -> Try(ChildMetrics, SolverError)
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

distribute_child_sizes_along : List(LayoutNode), List(LayoutPayload), List(U64), LayoutNode, Axis -> Try(List(LayoutNode), SolverError)
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

set_child_sizes_range : List(LayoutNode), List(U64), U64, U64, Axis, F32, F32 -> Try(List(LayoutNode), SolverError)
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

position_children : List(LayoutNode), List(LayoutPayload), List(U64), U64 -> Try(List(LayoutNode), SolverError)
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
Element.ChildAlign -> Try(List(LayoutNode), SolverError)
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

## TESTS ##

test_node : U64, LayoutNodeKind, ParentIndex, U64, U64, Size, Element.Sizing, Element.Sizing -> LayoutNode
test_node = |id, kind, parent, child_start, child_count, intrinsic, sizing_w, sizing_h| {
	{
		id,
		kind,
		payload_index: 0,
		parent,
		child_start,
		child_count,
		intrinsic,
		size: { w: 0, h: 0 },
		position: { x: 0, y: 0 },
		sizing_w,
		sizing_h,
	}
}

test_box : U64, ParentIndex, U64, U64, Size, Element.Sizing, Element.Sizing -> LayoutNode
test_box = |id, parent, child_start, child_count, intrinsic, sizing_w, sizing_h| {
	test_node(id, BoxNode, parent, child_start, child_count, intrinsic, sizing_w, sizing_h)
}

test_fixed_box : U64, ParentIndex, F32, F32 -> LayoutNode
test_fixed_box = |id, parent, w, h| {
	test_box(id, parent, 0, 0, { w, h }, Fixed(w), Fixed(h))
}

test_box_payload : Element.BoxConfig -> LayoutPayload
test_box_payload = |cfg| BoxPayload(cfg)

test_solve : List(LayoutNode), List(LayoutPayload), List(U64), Size -> Try(List(LayoutNode), SolverError)
test_solve = |nodes, payloads, child_indices, screen| {
	var $nodes = Solver.solve_size_axis(nodes, payloads, child_indices, XAxis, screen)?
	$nodes = Solver.solve_size_axis($nodes, payloads, child_indices, YAxis, screen)?
	Solver.solve_position($nodes, payloads, child_indices)
}

test_intrinsic_size : Element.Direction -> Bool
test_intrinsic_size = |direction| {
	cfg = Element.style
		.width(Fit({ min: 0, max: 1000 }))
		.height(Fit({ min: 0, max: 1000 }))
		.direction(direction)
		.gap(6)
		.pad((3, 4, 5, 7))
	parent = test_box(1, NoParent, 0, 2, { w: 0, h: 0 }, cfg.layout.width, cfg.layout.height)
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
	root = test_box(1, NoParent, 0, 0, { w: 0, h: 0 }, cfg.layout.width, cfg.layout.height)

	match test_solve([root], [test_box_payload(cfg)], [], { w: 200, h: 80 }) {
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
	root = test_box(1, NoParent, 0, 3, { w: 0, h: 0 }, root_cfg.layout.width, root_cfg.layout.height)
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

	match test_solve([root, fixed, grow_a, grow_b], [test_box_payload(root_cfg)], [1, 2, 3], { w: 120, h: 40 }) {
		Ok(nodes) => match (nodes.get(1), nodes.get(2), nodes.get(3)) {
			(Ok(a), Ok(b), Ok(c)) => match direction {
				Row => a.size == { w: 20, h: 10 }
					and b.size == { w: 35, h: 10 }
						and c.size == { w: 35, h: 10 }
							and a.position == { x: 10, y: 0 }
								and b.position == { x: 35, y: 0 }
									and c.position == { x: 75, y: 0 }
				Col => a.size == { w: 10, h: 20 }
					and b.size == { w: 10, h: 35 }
						and c.size == { w: 10, h: 35 }
							and a.position == { x: 0, y: 10 }
								and b.position == { x: 0, y: 35 }
									and c.position == { x: 0, y: 75 }
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
	root = test_box(1, NoParent, 0, 1, { w: 0, h: 0 }, root_cfg.layout.width, root_cfg.layout.height)

	match test_solve([root, child], [test_box_payload(root_cfg)], [1], { w: 100, h: 50 }) {
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
	root = test_box(1, NoParent, 1, 2, { w: 0, h: 0 }, root_cfg.layout.width, root_cfg.layout.height)
	nested = { ..test_box(2, Parent(0), 0, 1, { w: 0, h: 0 }, nested_cfg.layout.width, nested_cfg.layout.height), payload_index: 1 }
	leaf = test_fixed_box(3, Parent(1), 20, 10)
	sibling = test_fixed_box(4, Parent(0), 30, 20)

	match test_solve([root, nested, leaf, sibling], [test_box_payload(root_cfg), test_box_payload(nested_cfg)], [2, 1, 3], { w: 200, h: 100 }) {
		Ok(nodes) => match (nodes.get(1), nodes.get(2), nodes.get(3)) {
			(Ok(n), Ok(l), Ok(s)) => n.size == { w: 90, h: 90 }
				and n.position == { x: 10, y: 5 }
					and l.size == { w: 20, h: 10 }
						and l.position == { x: 77, y: 9 }
							and s.position == { x: 104, y: 5 }
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
	root = test_box(1, NoParent, 0, 4, { w: 0, h: 0 }, root_cfg.layout.width, root_cfg.layout.height)
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

	match test_solve([root, fixed, percent, fit, grow], [test_box_payload(root_cfg)], [1, 2, 3, 4], { w: 240, h: 60 }) {
		Ok(nodes) => match (nodes.get(1), nodes.get(2), nodes.get(3), nodes.get(4)) {
			(Ok(a), Ok(b), Ok(c), Ok(d)) => match direction {
				Row => a.size == { w: 20, h: 10 }
					and b.size == { w: 55, h: 10 }
						and c.size == { w: 30, h: 10 }
							and d.size == { w: 100, h: 10 }
								and a.position == { x: 10, y: 0 }
									and b.position == { x: 35, y: 0 }
										and c.position == { x: 95, y: 0 }
											and d.position == { x: 130, y: 0 }
				Col => a.size == { w: 10, h: 20 }
					and b.size == { w: 10, h: 55 }
						and c.size == { w: 10, h: 30 }
							and d.size == { w: 10, h: 100 }
								and a.position == { x: 0, y: 10 }
									and b.position == { x: 0, y: 35 }
										and c.position == { x: 0, y: 95 }
											and d.position == { x: 0, y: 130 }
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
	root = test_box(1, NoParent, 0, 1, { w: 0, h: 0 }, root_cfg.layout.width, root_cfg.layout.height)

	match Solver.solve_size_axis([root], [test_box_payload(root_cfg)], [99], XAxis, { w: 100, h: 50 }) {
		Err(OutOfBounds) => Bool.True
		_ => Bool.False
	}
}
