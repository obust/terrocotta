## Shared layout geometry and flat tree data types.
import Color
import Element
import Identity exposing [NodeId]
import Text
import rrt.Font

LayoutTypes := [].{

	# --- Internal Geometry Types ---

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

		is_eq : Size, Size -> Bool
		is_eq = |a, b| a.w == b.w and a.h == b.h
	}

	Pos := { x : F32, y : F32 }.{
		plus : Pos, Pos -> Pos
		plus = |a, b| { x: a.x + b.x, y: a.y + b.y }

		is_eq : Pos, Pos -> Bool
		is_eq = |a, b| a.x == b.x and a.y == b.y
	}

	Bounds := {
		position : Pos,
		size : Size,
	}.{
		contains : Bounds, Pos -> Bool
		contains = |bounds, point| {
			point.x >= bounds.position.x
				and point.x <= bounds.position.x + bounds.size.w
					and point.y >= bounds.position.y
						and point.y <= bounds.position.y + bounds.size.h
		}

		contains_bounds : Bounds, Bounds -> Bool
		contains_bounds = |outer, inner| {
			inner.position.x >= outer.position.x
				and inner.position.y >= outer.position.y
					and inner.position.x + inner.size.w <= outer.position.x + outer.size.w
						and inner.position.y + inner.size.h <= outer.position.y + outer.size.h
		}

		intersects : Bounds, Bounds -> Bool
		intersects = |a, b| {
			a.position.x < b.position.x + b.size.w
				and a.position.x + a.size.w > b.position.x
					and a.position.y < b.position.y + b.size.h
						and a.position.y + a.size.h > b.position.y
		}

		intersection : Bounds, Bounds -> Bounds
		intersection = |a, b| {
			x = F32.max(a.position.x, b.position.x)
			y = F32.max(a.position.y, b.position.y)
			right = F32.min(a.position.x + a.size.w, b.position.x + b.size.w)
			bottom = F32.min(a.position.y + a.size.h, b.position.y + b.size.h)
			{
				position: { x, y },
				size: {
					w: F32.max(0, right - x),
					h: F32.max(0, bottom - y),
				},
			}
		}

		union : Bounds, Bounds -> Bounds
		union = |a, b| {
			x = F32.min(a.position.x, b.position.x)
			y = F32.min(a.position.y, b.position.y)
			right = F32.max(a.position.x + a.size.w, b.position.x + b.size.w)
			bottom = F32.max(a.position.y + a.size.h, b.position.y + b.size.h)
			{
				position: { x, y },
				size: { w: right - x, h: bottom - y },
			}
		}

		is_empty : Bounds -> Bool
		is_empty = |bounds| bounds.size.w <= 0 or bounds.size.h <= 0

		expand : Bounds, Size -> Bounds
		expand = |bounds, amount| {
			position: {
				x: bounds.position.x - amount.w,
				y: bounds.position.y - amount.h,
			},
			size: {
				w: bounds.size.w + amount.w * 2,
				h: bounds.size.h + amount.h * 2,
			},
		}

		is_eq : Bounds, Bounds -> Bool
		is_eq = |a, b| a.position == b.position and a.size == b.size

		flatten : Bounds -> { x : F32, y : F32, width : F32, height : F32 }
		flatten = |bounds| {
			x: bounds.position.x,
			y: bounds.position.y,
			width: bounds.size.w,
			height: bounds.size.h,
		}

	}

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

	ImageNodeData(texture) : {
		texture : texture,
	}

	LayoutNodeKind(texture) : [BoxNode(BoxNodeData), TextNode(TextNodeData), ImageNode(ImageNodeData(texture))]

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

	LayoutNode(texture) : {
		id : NodeId,
		kind : LayoutNodeKind(texture),
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
