## Pointer and UI event types used by Element views and Program dispatch.

Event := [].{
	Point : {
		x : F32,
		y : F32,
	}

	ElementBounds := {
		x : F32,
		y : F32,
		width : F32,
		height : F32,
	}.{
		relative : ElementBounds, Point -> Point
		relative = |bounds, position| {
			{ x: position.x - bounds.x, y: position.y - bounds.y }
		}

		contains : ElementBounds, Point -> Bool
		contains = |bounds, position| {
			position.x >= bounds.x
				and position.x <= bounds.x + bounds.width
					and position.y >= bounds.y
						and position.y <= bounds.y + bounds.height
		}
	}

	EventTarget : {
		id : U64,
		bounds : ElementBounds,
	}

	PointerButtonState : {
		down : Bool,
		pressed : Bool,
		released : Bool,
	}

	PointerButtons : {
		left : PointerButtonState,
		middle : PointerButtonState,
		right : PointerButtonState,
	}

	PointerEvent : {
		position : Point,
		buttons : PointerButtons,
		target : EventTarget,
	}

	Handler(msg) : [
	    OnClick(msg),
		OnHover(msg),
		OnPointer(Box(PointerEvent -> List(msg))),
		OnPointerEnter(msg),
		OnPointerLeave(msg),
		OnKeyPressed(U64, msg),
		OnKeyDown(U64, msg),
		OnKeyUp(U64, msg),
	]
}
