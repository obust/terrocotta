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
