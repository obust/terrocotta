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
		is_eq : _

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

	## Delivered to OnDragStart/OnDragMove/OnDragEnd handlers while a captured drag is in progress.
	DragEvent : {
		id : U64,
		position : Point,
		delta : Point, # `delta` is the per-frame pointer movement, zeroed on the start and end phases.
		target : EventTarget,
	}

	Handler(msg) : [
		OnClick(msg),
		OnHover(msg),
		OnPointer(Box(PointerEvent -> List(msg))),
		OnPointerEnter(msg),
		OnPointerLeave(msg),
		OnDragStart(Box(DragEvent -> List(msg))),
		OnDragMove(Box(DragEvent -> List(msg))),
		OnDragEnd(Box(DragEvent -> List(msg))),
		OnKeyPressed(U64, msg),
		OnKeyDown(U64, msg),
		OnKeyUp(U64, msg),
	]
}
