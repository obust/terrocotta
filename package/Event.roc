## Pointer and UI event types used by Element views and Program dispatch.
import rrt.Keys
import rrt.Mouse

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

	PointerEvent : {
		position : Point,
		mouse : Mouse.Snapshot,
		target : EventTarget,
	}

	## Delivered to OnDragStart/OnDragMove/OnDragEnd handlers while a captured drag is in progress.
	DragEvent : {
		id : U64,
		position : Point,
		delta : Point, # `delta` is the per-frame pointer movement, zeroed on the start and end phases.
		target : EventTarget,
	}

	TextControlKey : [KeyLeft, KeyRight, KeyHome, KeyEnd, KeyBackspace, KeyDelete]

	## One cycle-local batch of committed text and control-key presses.
	TextInputEvent : {
		codepoints : List(U32),
		keys : List(TextControlKey),
	}

	Handler(msg) := [
		OnClick(msg),
		OnHover(msg),
		OnPointer(Box(PointerEvent -> msg)),
		OnPointerEnter(msg),
		OnPointerLeave(msg),
		OnPointerPressed(Mouse.Button, msg),
		OnPointerDown(Mouse.Button, msg),
		OnPointerReleased(Mouse.Button, msg),
		OnDragStart(Box(DragEvent -> msg)),
		OnDragMove(Box(DragEvent -> msg)),
		OnDragEnd(Box(DragEvent -> msg)),
		OnKeyPressed(Keys.Key, msg),
		OnKeyDown(Keys.Key, msg),
		OnKeyReleased(Keys.Key, msg),
		OnTextInput(Box(TextInputEvent -> msg)),
	].{

		## Transform every message this handler can produce.
		map : Handler(a), (a -> b) -> Handler(b)
		map = |handler, f|
			match handler {
				OnClick(msg) => OnClick(f(msg))
				OnHover(msg) => OnHover(f(msg))
				OnPointer(callback) => OnPointer(map_callback(callback, f))
				OnPointerEnter(msg) => OnPointerEnter(f(msg))
				OnPointerLeave(msg) => OnPointerLeave(f(msg))
				OnPointerPressed(button, msg) => OnPointerPressed(button, f(msg))
				OnPointerDown(button, msg) => OnPointerDown(button, f(msg))
				OnPointerReleased(button, msg) => OnPointerReleased(button, f(msg))
				OnDragStart(callback) => OnDragStart(map_callback(callback, f))
				OnDragMove(callback) => OnDragMove(map_callback(callback, f))
				OnDragEnd(callback) => OnDragEnd(map_callback(callback, f))
				OnKeyPressed(key, msg) => OnKeyPressed(key, f(msg))
				OnKeyDown(key, msg) => OnKeyDown(key, f(msg))
				OnKeyReleased(key, msg) => OnKeyReleased(key, f(msg))
				OnTextInput(callback) => OnTextInput(map_callback(callback, f))
			}
	}
}

## Transform the message produced by a callback.
map_callback : Box(input -> a), (a -> b) -> Box(input -> b)
map_callback = |callback, f| Box.box(|input| f((Box.unbox(callback))(input)))

expect {
	handler : Event.Handler(Str)
	handler = OnClick("save")
	mapped = handler.map(|msg| Parent(msg))
	match mapped {
		OnClick(Parent(msg)) => msg == "save"
		_ => False
	}
}

expect {
	handler : Event.Handler(Str)
	handler = OnPointerPressed(Right, "open")
	mapped = handler.map(|msg| Parent(msg))
	match mapped {
		OnPointerPressed(Right, Parent(msg)) => msg == "open"
		_ => False
	}
}

expect {
	handler : Event.Handler(Str)
	handler = OnKeyDown(Raw(12), "submit")
	mapped = handler.map(|msg| Parent(msg))
	match mapped {
		OnKeyDown(Raw(code), Parent(msg)) => code == 12 and msg == "submit"
		_ => False
	}
}

expect {
	handlers : List(Event.Handler(Str))
	handlers = [
		OnHover("hover"),
		OnPointerEnter("enter"),
		OnPointerLeave("leave"),
		OnPointerDown(Middle, "down"),
		OnPointerReleased(Left, "released"),
		OnKeyPressed(Raw(1), "pressed"),
		OnKeyReleased(Raw(2), "released-key"),
	]
	mapped = List.map(handlers, |handler| handler.map(|msg| Parent(msg)))

	match mapped {
		[
			OnHover(Parent("hover")),
			OnPointerEnter(Parent("enter")),
			OnPointerLeave(Parent("leave")),
			OnPointerDown(Middle, Parent("down")),
			OnPointerReleased(Left, Parent("released")),
			OnKeyPressed(Raw(1), Parent("pressed")),
			OnKeyReleased(Raw(2), Parent("released-key")),
		] => True
		_ => False
	}
}

expect {
	handler : Event.Handler(Str)
	handler = OnPointer(Box.box(|event| "${event.position.x.to_str()}:${event.target.id.to_str()}"))
	mapped = handler.map(|msg| Parent(msg))

	match mapped {
		OnPointer(callback) => {
			event : Event.PointerEvent
			event = {
				position: { x: 4, y: 8 },
				mouse: { buttons: [], left: False, middle: False, right: False, wheel: 0, wheel_x: 0, wheel_y: 0, delta_x: 0, delta_y: 0, x: 4, y: 8 },
				target: { id: 7, bounds: { x: 0, y: 0, width: 10, height: 10 } },
			}
			(Box.unbox(callback))(event) == Parent("4:7")
		}
		_ => False
	}
}

expect {
	handler : Event.Handler(Str)
	handler = OnDragMove(Box.box(|event| "${event.id.to_str()}:${event.delta.y.to_str()}"))
	mapped = handler.map(|msg| Parent(msg))

	match mapped {
		OnDragMove(callback) => {
			event : Event.DragEvent
			event = {
				id: 3,
				position: { x: 5, y: 6 },
				delta: { x: -1, y: 2 },
				target: { id: 9, bounds: { x: 1, y: 2, width: 30, height: 40 } },
			}
			(Box.unbox(callback))(event) == Parent("3:2")
		}
		_ => False
	}
}

expect {
	drag_event : Event.DragEvent
	drag_event = {
		id: 5,
		position: { x: 8, y: 13 },
		delta: { x: 1, y: -1 },
		target: { id: 21, bounds: { x: 0, y: 0, width: 34, height: 55 } },
	}
	handlers : List(Event.Handler(Str))
	handlers = [
		OnDragStart(Box.box(|event| event.id.to_str())),
		OnDragEnd(Box.box(|event| event.target.id.to_str())),
	]
	mapped = List.map(handlers, |handler| handler.map(|msg| Parent(msg)))

	match mapped {
		[OnDragStart(start_callback), OnDragEnd(end_callback)] =>
			(Box.unbox(start_callback))(drag_event) == Parent("5")
				and (Box.unbox(end_callback))(drag_event) == Parent("21")

		_ => False
	}
}

expect {
	handler : Event.Handler(Str)
	handler = OnTextInput(Box.box(|event| event.codepoints.len().to_str()))
	mapped = handler.map(|msg| Parent(msg))

	match mapped {
		OnTextInput(callback) =>
			(Box.unbox(callback))({ codepoints: [65, 66], keys: [KeyLeft] }) == Parent("2")
		_ => False
	}
}

expect {
	handler : Event.Handler(Str)
	handler = OnHover("item")
	mapped = handler.map(|msg| Child(msg)).map(|msg| Parent(msg))
	match mapped {
		OnHover(Parent(Child(msg))) => msg == "item"
		_ => False
	}
}
