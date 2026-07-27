## Pure floating-root dependency, geometry, ordering, and clipping policy.
import Element
import Identity exposing [NodeId]
import LayoutTypes exposing [
	LayoutNode,
	LayoutNodeKind.*,
	FloatingClip.*,
	FloatingTarget.*,
	ParentIndex.*,
	Placement.*,
	Pos,
	ResolvedFloatingConfig,
	Size,
]

Floating := [].{

	ClipRect : [ClipRect({ position : Pos, size : Size }), NoClipRect]

	RootInfo : {
		index : U64,
		z_index : I16,
		expand : Size,
		clip : ClipRect,
		capture : [Capture, Passthrough],
	}

	## Return all roots with attachment dependencies ordered before dependents.
	attachment_order : List(LayoutNode), Dict(NodeId, U64), List(U64) -> Try(List(U64), [NodeIdNotFound(NodeId), TargetCycle, OutOfBounds, ..])
	attachment_order = |nodes, node_ids, roots| {
		var $states = Dict.empty()
		var $order = []
		for root_index in roots {
			resolved = resolve_root_order(nodes, node_ids, root_index, $states, $order)?
			$states = resolved.states
			$order = resolved.order
		}
		Ok($order)
	}

	## Return the current position and size of a resolved floating target.
	target_rect : List(LayoutNode), Dict(NodeId, U64), LayoutTypes.FloatingTarget, Size -> Try({ position : Pos, size : Size }, [NodeIdNotFound(NodeId), OutOfBounds, ..])
	target_rect = |nodes, node_ids, target, screen| match target {
		Root => Ok({ position: { x: 0, y: 0 }, size: screen })
		Element(id) => {
			index = node_index(node_ids, id)?
			node = nodes.get(index)?
			Ok({ position: node.position, size: node.size })
		}
	}

	## Position a floating root against its resolved attachment rectangle.
	position : LayoutNode, { position : Pos, size : Size }, ResolvedFloatingConfig -> Pos
	position = |root, target, config| {
		target_point = attach_point_pos(target.position, target.size, config.attach_points.target)
		element_factor = attach_point_factor(config.attach_points.element)
		{
			x: target_point.x - root.size.w * element_factor.x + config.offset.x,
			y: target_point.y - root.size.h * element_factor.y + config.offset.y,
		}
	}

	## Resolve and stably sort every layout root by z-index.
	roots_by_z : List(LayoutNode), Dict(NodeId, U64), List(U64), Bool -> Try(List(RootInfo), [NodeIdNotFound(NodeId), OutOfBounds, ..])
	roots_by_z = |nodes, node_ids, roots, descending| {
		var $ordered = []
		for root_index in roots {
			root = resolve_root_info(nodes, node_ids, root_index)?
			$ordered = insert_root_by_z($ordered, root, descending)
		}
		Ok($ordered)
	}

	## Resolve the clipping rectangle inherited by a floating root.
	clip_rect : List(LayoutNode), Dict(NodeId, U64), ResolvedFloatingConfig -> Try(ClipRect, [NodeIdNotFound(NodeId), OutOfBounds, ..])
	clip_rect = |nodes, node_ids, config| if config.clip == NoFloatingClip {
		Ok(NoClipRect)
	} else {
		match config.target {
			Root => Ok(NoClipRect)
			Element(id) => {
				target_index = node_index(node_ids, id)?
				node_clip_context(nodes, node_ids, target_index, config.clip == IncludeTarget)
			}
		}
	}
}

AttachmentResolutionStatus : [Resolving, Resolved]

## Resolve a stable node ID to its node-list index.
node_index : Dict(NodeId, U64), NodeId -> Try(U64, [NodeIdNotFound(NodeId), ..])
node_index = |node_ids, id|
	node_ids.get(id).map_err(|_| NodeIdNotFound(id))

## Append one root after recursively appending its attachment dependency.
resolve_root_order : List(LayoutNode), Dict(NodeId, U64), U64, Dict(U64, AttachmentResolutionStatus), List(U64) -> Try({ states : Dict(U64, AttachmentResolutionStatus), order : List(U64) }, [NodeIdNotFound(NodeId), TargetCycle, OutOfBounds, ..])
resolve_root_order = |nodes, node_ids, root_index, states, order| {
	root = nodes.get(root_index)?
	match states.get(root_index) {
		Ok(Resolved) => Ok({ states, order })
		Ok(Resolving) => Err(TargetCycle)
		Err(_) => {
			resolving = states.insert(root_index, Resolving)
			with_dependency = match root.placement {
				Normal => Ok({ states: resolving, order })
				Floating(config) => match config.target {
					Root => Ok({ states: resolving, order })
					Element(id) => {
						target_index = node_index(node_ids, id)?
						dependency = containing_root_index(nodes, target_index)?
						resolve_root_order(nodes, node_ids, dependency, resolving, order)
					}
				}
			}?
			Ok({
				states: with_dependency.states.insert(root_index, Resolved),
				order: with_dependency.order.append(root_index),
			})
		}
	}
}

## Find the independent layout root containing a node.
containing_root_index : List(LayoutNode), U64 -> Try(U64, [OutOfBounds, ..])
containing_root_index = |nodes, index| {
	node = nodes.get(index)?
	match node.parent {
		NoParent => Ok(index)
		Parent(parent_index) => containing_root_index(nodes, parent_index)
	}
}

## Map an attachment point to normalized horizontal and vertical factors.
attach_point_factor : Element.AttachPoint -> Pos
attach_point_factor = |point| match point {
	LeftTop => { x: 0, y: 0 }
	LeftCenter => { x: 0, y: 0.5 }
	LeftBottom => { x: 0, y: 1 }
	CenterTop => { x: 0.5, y: 0 }
	Center => { x: 0.5, y: 0.5 }
	CenterBottom => { x: 0.5, y: 1 }
	RightTop => { x: 1, y: 0 }
	RightCenter => { x: 1, y: 0.5 }
	RightBottom => { x: 1, y: 1 }
}

## Convert an attachment point into an absolute position inside a rectangle.
attach_point_pos : Pos, Size, Element.AttachPoint -> Pos
attach_point_pos = |position, size, point| {
	factor = attach_point_factor(point)
	{ x: position.x + size.w * factor.x, y: position.y + size.h * factor.y }
}

## Resolve the paint, clipping, ordering, and capture metadata for one root.
resolve_root_info : List(LayoutNode), Dict(NodeId, U64), U64 -> Try(Floating.RootInfo, [NodeIdNotFound(NodeId), OutOfBounds, ..])
resolve_root_info = |nodes, node_ids, index| {
	node = nodes.get(index)?
	match node.placement {
		Normal => Ok({
			index,
			z_index: 0,
			expand: { w: 0, h: 0 },
			clip: NoClipRect,
			capture: Passthrough,
		})
		Floating(config) => Ok({
			index,
			z_index: config.z_index,
			expand: config.expand,
			clip: Floating.clip_rect(nodes, node_ids, config)?,
			capture: config.capture,
		})
	}
}

## Insert resolved root metadata into stable ascending or descending z-order.
insert_root_by_z : List(Floating.RootInfo), Floating.RootInfo, Bool -> List(Floating.RootInfo)
insert_root_by_z = |roots, item, descending| {
	var $result = []
	var $inserted = Bool.False
	for current in roots {
		before = if descending {
			item.z_index > current.z_index or (item.z_index == current.z_index and item.index > current.index)
		} else {
			item.z_index < current.z_index or (item.z_index == current.z_index and item.index < current.index)
		}
		if before and !$inserted {
			$result = $result.append(item)
			$inserted = Bool.True
		}
		$result = $result.append(current)
	}
	if $inserted $result else $result.append(item)
}

## Find the clip inherited at a node, optionally including that node itself.
node_clip_context : List(LayoutNode), Dict(NodeId, U64), U64, Bool -> Try(Floating.ClipRect, [NodeIdNotFound(NodeId), OutOfBounds, ..])
node_clip_context = |nodes, node_ids, index, include_node| {
	node = nodes.get(index)?
	clips_here = if include_node {
		match node.kind {
			BoxNode(box) => box.overflow.x != Visible or box.overflow.y != Visible
			_ => Bool.False
		}
	} else {
		Bool.False
	}
	if clips_here {
		Ok(ClipRect({ position: node.position, size: node.size }))
	} else {
		match node.parent {
			Parent(parent_index) => node_clip_context(nodes, node_ids, parent_index, Bool.True)
			NoParent => match node.placement {
				Normal => Ok(NoClipRect)
				Floating(config) => Floating.clip_rect(nodes, node_ids, config)
			}
		}
	}
}

## TESTS ##

test_config : LayoutTypes.FloatingTarget, FloatingClip, I16 -> ResolvedFloatingConfig
test_config = |target, clip, z_index| {
	target,
	clip,
	z_index,
	offset: { x: 0, y: 0 },
	expand: { w: 0, h: 0 },
	attach_points: { element: LeftTop, target: LeftTop },
	capture: Passthrough,
}

test_node : NodeId, ParentIndex, Placement, Element.LayoutConfig, Pos, Size -> LayoutNode
test_node = |id, parent, placement, layout, position, size| {
	{
		id,
		kind: BoxNode({
			layout,
			background: Element.style.background,
			radius: Element.style.radius,
			border: Element.style.border,
			overflow: { x: Visible, y: Visible },
		}),
		parent,
		child_start: 0,
		child_count: 0,
		intrinsic: size,
		size,
		content_size: size,
		scroll_offset: { x: 0, y: 0 },
		position,
		sizing_w: layout.width,
		sizing_h: layout.height,
		placement,
	}
}

## Attachment geometry aligns the configured element and target points.
expect {
	root = test_node(1, NoParent, Normal, Element.style.layout, { x: 0, y: 0 }, { w: 10, h: 6 })
	config = {
		..test_config(Root, NoFloatingClip, 0),
		offset: { x: 3, y: -2 },
		attach_points: { element: Center, target: RightBottom },
	}
	Floating.position(root, { position: { x: 20, y: 30 }, size: { w: 40, h: 10 } }, config)
		== { x: 58, y: 35 }
}

## A target descendant makes its containing floating root a dependency.
expect {
	normal = test_node(1, NoParent, Normal, Element.style.layout, { x: 0, y: 0 }, { w: 100, h: 100 })
	dependent = test_node(2, NoParent, Floating(test_config(Element(4), NoFloatingClip, -10)), Element.style.layout, { x: 0, y: 0 }, { w: 5, h: 5 })
	anchor = test_node(3, NoParent, Floating(test_config(Root, NoFloatingClip, 10)), Element.style.layout, { x: 0, y: 0 }, { w: 20, h: 20 })
	target = test_node(4, Parent(2), Normal, Element.style.layout, { x: 2, y: 2 }, { w: 5, h: 5 })
	node_ids = Dict.empty().insert(1, 0).insert(2, 1).insert(3, 2).insert(4, 3)

	Floating.attachment_order([normal, dependent, anchor, target], node_ids, [0, 1, 2])
		== Ok([0, 2, 1])
}

## Recursive attachment dependency resolution rejects cycles.
expect {
	a = test_node(1, NoParent, Floating(test_config(Element(2), NoFloatingClip, 0)), Element.style.layout, { x: 0, y: 0 }, { w: 10, h: 10 })
	b = test_node(2, NoParent, Floating(test_config(Element(1), NoFloatingClip, 0)), Element.style.layout, { x: 0, y: 0 }, { w: 10, h: 10 })
	node_ids = Dict.empty().insert(1, 0).insert(2, 1)

	match Floating.attachment_order([a, b], node_ids, [0, 1]) {
		Err(TargetCycle) => Bool.True
		_ => Bool.False
	}
}

## Target-ancestor clipping inherits the nearest clipping ancestor, excluding
## the target's own box.
expect {
	outer_layout = Element.style.layout
	outer_base = test_node(1, NoParent, Normal, outer_layout, { x: 10, y: 20 }, { w: 100, h: 80 })
	outer = {
		..outer_base,
		kind: BoxNode({
			layout: outer_layout,
			background: Element.style.background,
			radius: Element.style.radius,
			border: Element.style.border,
			overflow: { x: Hidden, y: Hidden },
		}),
	}
	target = test_node(2, Parent(0), Normal, Element.style.layout, { x: 15, y: 25 }, { w: 20, h: 20 })
	node_ids = Dict.empty().insert(1, 0).insert(2, 1)

	match Floating.clip_rect([outer, target], node_ids, test_config(Element(2), TargetAncestors, 0)) {
		Ok(ClipRect(rect)) => rect == { position: { x: 10, y: 20 }, size: { w: 100, h: 80 } }
		_ => Bool.False
	}
}

## Root metadata is sorted by z-index with node order as the stable tie-break.
expect {
	low = test_node(1, NoParent, Floating(test_config(Root, NoFloatingClip, -1)), Element.style.layout, { x: 0, y: 0 }, { w: 1, h: 1 })
	high_a = test_node(2, NoParent, Floating(test_config(Root, NoFloatingClip, 2)), Element.style.layout, { x: 0, y: 0 }, { w: 1, h: 1 })
	high_b = test_node(3, NoParent, Floating(test_config(Root, NoFloatingClip, 2)), Element.style.layout, { x: 0, y: 0 }, { w: 1, h: 1 })
	node_ids = Dict.empty().insert(1, 0).insert(2, 1).insert(3, 2)

	match Floating.roots_by_z([low, high_a, high_b], node_ids, [0, 1, 2], Bool.True) {
		Ok([a, b, c]) => [a.index, b.index, c.index] == [2, 1, 0]
		_ => Bool.False
	}
}
