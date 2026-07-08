## Shared layout geometry and flat tree data types.
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
	}

	Pos := { x : F32, y : F32 }.{
		plus : Pos, Pos -> Pos
		plus = |a, b| { x: a.x + b.x, y: a.y + b.y }
	}

	Axis : [XAxis, YAxis]

	# --- Flat Layout Node Types ---

	LayoutNodeKind : [BoxNode, TextNode, ImageNode]

	LayoutPayload : [
		BoxPayload(Element.BoxConfig),
		TextPayload({ content : Str, config : Element.TextConfig }),
		ImagePayload(Element.ImageConfig),
	]

	ParentIndex : [NoParent, Parent(U64)]

	LayoutNode : {
		id : NodeId,
		kind : LayoutNodeKind,
		parent : ParentIndex,
		child_start : U64,
		child_count : U64,
		intrinsic : Size,
		size : Size,
		position : Pos,
		sizing_w : Element.Sizing,
		sizing_h : Element.Sizing,
	}
}
