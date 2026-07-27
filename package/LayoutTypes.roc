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
