## Shared layout geometry and flat tree data types.
import Color
import Element
import Identity exposing [NodeId]

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
	}

	Axis : [XAxis, YAxis]

	# --- Flat Layout Node Types ---

	BoxNodeData : {
		layout : Element.LayoutConfig,
		background : Color,
		radius : F32,
		border : Element.BorderConfig,
		overflow : { x: Element.Overflow, y: Element.Overflow },
	}

	TextNodeData : {
		content_index : U64,
		config : Element.TextConfig,
		line_height : F32,
		wrap_width : F32,
		min_width : F32,
		lines_start : U64,
		lines_count : U64,
	}

	ImageNodeData : {
		config : Element.ImageConfig,
	}

	LayoutNodeKind : [BoxNode(BoxNodeData), TextNode(TextNodeData), ImageNode(ImageNodeData)]

	ParentIndex : [NoParent, Parent(U64)]

	FloatingTarget : [Root, Element(NodeId)]

	ClipSource : [Unclipped, Target, TargetAncestors]

	ResolvedFloatingConfig : {
		target : FloatingTarget,
		clip_source : ClipSource,
		z_index : I16,
		offset : Pos,
		expand : Size,
		attach_points : { element : Element.AttachPoint, target: Element.AttachPoint },
		capture : [Capture, Passthrough],
	}

	Placement : [Normal, Floating(ResolvedFloatingConfig)]

	LayoutNode : {
		id : NodeId,
		kind : LayoutNodeKind,
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
