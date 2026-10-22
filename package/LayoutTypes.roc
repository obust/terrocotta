## Shared layout geometry and flat tree data types.
import Color
import Element
import Geom exposing [Bounds, Pos, Size]
import Identity exposing [NodeId]
import Text
import rr.Font
import rr.Mouse

LayoutTypes := [].{

	VisibleRegion : [Visible(Bounds), Culled]

	## Intersect conservative paint bounds with the viewport and effective clip.
	## Edge-touching and zero-area rectangles are culled.
	visible_region : Bounds, Bounds, [Clipped(Bounds), Unclipped] -> VisibleRegion
	visible_region = |paint_bounds, viewport, clip| {
		in_viewport = paint_bounds.intersection(viewport)
		visible = match clip {
			Unclipped => in_viewport
			Clipped(bounds) => in_viewport.intersection(bounds)
		}

		if visible.is_empty() {
			Culled
		} else {
			Visible(visible)
		}
	}

	Axis : [XAxis, YAxis]

	# --- Flat Layout Node Types ---

	BoxNodeData : {
		layout : Element.LayoutConfig,
		background : Color,
		radius : F32,
		border : Element.BorderConfig,
		overflow : { x : Element.Overflow, y : Element.Overflow },
		cursor : Mouse.Cursor,
	}

	TextNodeData : {
		content_index : U64,
		font : Font,
		config : Text.Config,
		line_height : F32,
		wrap_width : F32,
		min_width : F32,
		lines_start : U64,
		lines_count : U64,
	}

	CustomNodeData(payload) : {
		payload : payload,
	}

	LayoutNodeKind(payload) : [BoxNode(BoxNodeData), TextNode(TextNodeData), CustomNode(CustomNodeData(payload))]

	ParentIndex : [NoParent, Parent(U64)]

	FloatingTarget : [Root, Element(NodeId)]

	ClipSource : [Unclipped, Target, TargetAncestors]

	ResolvedFloatingConfig : {
		target : FloatingTarget,
		clip_source : ClipSource,
		z_index : I16,
		offset : Pos,
		expand : Size,
		attach_points : { element : Element.AttachPoint, target : Element.AttachPoint },
		capture : [Capture, Passthrough],
	}

	Placement : [Normal, Floating(ResolvedFloatingConfig)]

	LayoutNode(payload) : {
		id : NodeId,
		kind : LayoutNodeKind(payload),
		parent : ParentIndex,
		child_start : U64,
		child_count : U64,
		intrinsic : Size,
		size : Size,
		content_size : Size,
		scroll_offset : Pos,
		position : Pos,
		sizing_w : Element.Sizing,
		sizing_h : Element.Sizing,
		placement : Placement,
	}
}

## Visibility intersects paint bounds with both viewport and effective clip.
expect {
	paint = { position: { x: 5, y: 5 }, size: { w: 20, h: 20 } }
	viewport = { position: { x: 0, y: 0 }, size: { w: 20, h: 20 } }
	clip = { position: { x: 10, y: 0 }, size: { w: 20, h: 12 } }

	LayoutTypes.visible_region(paint, viewport, Clipped(clip))
		== Visible({ position: { x: 10, y: 5 }, size: { w: 10, h: 7 } })
}

## Edge-touching and zero-area paint bounds are culled.
expect {
	viewport = { position: { x: 0, y: 0 }, size: { w: 10, h: 10 } }
	edge_touching = { position: { x: 10, y: 2 }, size: { w: 5, h: 5 } }
	zero_width = { position: { x: 2, y: 2 }, size: { w: 0, h: 5 } }

	LayoutTypes.visible_region(edge_touching, viewport, Unclipped) == Culled
		and LayoutTypes.visible_region(zero_width, viewport, Unclipped) == Culled
}
