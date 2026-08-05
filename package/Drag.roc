## Retained pointer-drag state machine.
##
## Pointer input is normally purely positional: events fire for whatever
## element happens to be under the pointer on a given frame. This module adds
## a single retained gesture state. A press over an element with OnDrag*
## handlers captures the pointer: the element keeps receiving OnDragStart,
## OnDragMove, and OnDragEnd until the button is released, no matter where the
## pointer travels.
##
## See .vscode/DRAG.md for the full design.
import Element
import Event
import Layout
import LayoutTypes

Drag := [].{

	## Everything captured at press time and retained for the whole drag.
	DragInfo : {
		node_id : U64,
		## Pointer position when the drag began.
		pointer_origin : LayoutTypes.Pos,
		## Pointer position last frame.
		last_pointer : LayoutTypes.Pos,
	}

	DragState : [Idle, Dragging(DragInfo)]

	## Left button lifecycle for one frame: which transitions happened.
	MouseButton : [Idle, Pressed, Down, Released]

	## Per-frame snapshot derived from the structural mouse record by `advance`.
	MouseInput : {
		pointer : LayoutTypes.Pos,
		left : MouseButton,
	}

	## The phase tags routed through dispatch_drag.
	DragPhase : [Start, Move, End]

	## Advance the drag state machine one frame.
	##
	## Idle + left Pressed       -> capture_drag (or stay Idle on no handlers)
	## Idle + otherwise          -> Idle, no-op
	## Dragging + left Released  -> dispatch end phase, Idle
	## Dragging + left Down      -> dispatch move phase, stay Dragging
	## Dragging + left Idle      -> stay Dragging (lost frame)
	##
	## `hovered` is the frame's fresh hit-test path; it is only consulted on a
	## new press. Once captured, dispatch targets the captured node regardless
	## of what is under the pointer. The per-frame button snapshot is derived
	## from the structural mouse record passed in.
	advance :
		Layout(draw),
		Dict(U64, List(Event.Handler(msg))),
		List(U64),
		DragState,
		{
			x : F32,
			y : F32,
			buttons : List(U8),
			buttons_pressed : List(U8),
			buttons_released : List(U8),
			..
		}
		-> Try({ drag : DragState, messages : List(msg) }, Layout.LayoutError)
	advance = |layout, bindings, hovered, drag_state, mouse| {
		input = {
			pointer: { x: mouse.x, y: mouse.y },
			left: left_button(mouse),
		}
		match drag_state {
			Idle => {
				match input.left {
					Pressed => capture_drag(layout, bindings, hovered, input)
					_ => Ok({ drag: Idle, messages: [] })
				}
			}
			Dragging(info) => {
				match input.left {
					Released => {
						messages = dispatch_drag(layout, bindings, info, End, input.pointer)?
						Ok({ drag: Idle, messages })
					}
					Pressed | Down => {
						messages = dispatch_drag(layout, bindings, info, Move, input.pointer)?
						next_info = { ..info, last_pointer: input.pointer }
						Ok({ drag: Dragging(next_info), messages })
					}
					Idle => {
						# Pointer button data gap: stay captured, emit nothing.
						Ok({ drag: drag_state, messages: [] })
					}
				}
			}
		}
	}

	## Resolve a press into a capture, or stay Idle.
	##
	## Walk the hover path for the first element with any OnDrag* handler and
	## capture it as an app drag, dispatching OnDragStart this frame. Walking
	## the path means pressing a non-draggable child (e.g. a slider handle)
	## over a draggable ancestor still captures the ancestor. If nothing in the
	## path opts in, remain Idle and let normal click/hover handling proceed.
	capture_drag :
		Layout(draw),
		Dict(U64, List(Event.Handler(msg))),
		List(U64),
		MouseInput
		-> Try({ drag : DragState, messages : List(msg) }, Layout.LayoutError)
	capture_drag = |layout, bindings, hovered, input| {
		match find_drag_capture(bindings, hovered) {
			NotFound => Ok({ drag: Idle, messages: [] })
			Found(node_id) => {
				info = {
					node_id,
					pointer_origin: input.pointer,
					last_pointer: input.pointer,
				}
				messages = dispatch_drag(layout, bindings, info, Start, input.pointer)?
				Ok({ drag: Dragging(info), messages })
			}
		}
	}

	## Route a drag phase to the captured element's handlers.
	dispatch_drag :
		Layout(draw),
		Dict(U64, List(Event.Handler(msg))),
		DragInfo,
		DragPhase,
		LayoutTypes.Pos
		-> Try(List(msg), Layout.LayoutError)
	dispatch_drag = |layout, bindings, info, phase, pointer| {
		delta = match phase {
			Start => { x: 0, y: 0 }
			Move => { x: pointer.x - info.last_pointer.x, y: pointer.y - info.last_pointer.y }
			End => { x: 0, y: 0 }
		}
		event = drag_event(layout, info, pointer, delta)?
		Ok(dispatch_app_drag(bindings, info.node_id, phase, event))
	}

	## Build the drag event delivered to all three phases.
	drag_event :
		Layout(draw),
		DragInfo,
		LayoutTypes.Pos,
		LayoutTypes.Pos
		-> Try(Event.DragEvent, Layout.LayoutError)
	drag_event = |layout, info, pointer, delta| {
		Ok(
			{
				id: info.node_id,
				position: { x: pointer.x, y: pointer.y },
				delta: { x: delta.x, y: delta.y },
				target: {
					id: info.node_id,
					bounds: layout.node_bounds(info.node_id)?,
				},
			},
		)
	}

	## Call the OnDrag* handler box matching the current phase.
	dispatch_app_drag :
		Dict(U64, List(Event.Handler(msg))),
		U64,
		DragPhase,
		Event.DragEvent
		-> List(msg)
	dispatch_app_drag = |bindings, node_id, phase, event| {
		bindings
			.get(node_id)
			.ok_or([])
			.iter()
			.fold(
				[],
				|msgs, binding| {
					match (phase, binding) {
						(Start, OnDragStart(callback)) => msgs.concat((Box.unbox(callback))(event))
						(Move, OnDragMove(callback)) => msgs.concat((Box.unbox(callback))(event))
						(End, OnDragEnd(callback)) => msgs.concat((Box.unbox(callback))(event))
						_ => msgs
					}
				},
			)
	}

	## Whether an element opts into dragging by listing any OnDrag* handler.
	has_drag_handlers : List(Event.Handler(msg)) -> Bool
	has_drag_handlers = |handlers| {
		handlers
			.iter()
			.fold(Bool.False, |found, handler| {
				match handler {
					OnDragStart(_) | OnDragMove(_) | OnDragEnd(_) => Bool.True
					_ => found
				}
			})
	}

	## The first node in the hover path that opts into dragging.
	##
	## Draggable ancestors still capture when a non-draggable descendant is
	## pressed, so e.g. pressing a slider handle (which has no handlers) grabs
	## the slider track (which does).
	find_drag_capture : Dict(U64, List(Event.Handler(msg))), List(U64) -> [Found(U64), NotFound]
	find_drag_capture = |bindings, hovered| {
		hovered.fold_until(NotFound, |capture, node_id| {
			if has_drag_handlers(bindings.get(node_id).ok_or([])) {
				Break(Found(node_id))
			} else {
				Continue(capture)
			}
		})
	}

	## Whether a mouse button list reports the given button as active.
	mouse_button : List(U8), U64 -> Bool
	mouse_button = |states, button|
		match states.get(button) {
			Ok(state) => state == 1
			Err(_) => Bool.False
		}

	## Derive the left button lifecycle for this frame from the raw mouse state.
	left_button :
		{
			x : F32,
			y : F32,
			buttons : List(U8),
			buttons_pressed : List(U8),
			buttons_released : List(U8),
			..
		}
		-> MouseButton
	left_button = |mouse|
		if mouse_button(mouse.buttons_pressed, 0) {
			Pressed
		} else if mouse_button(mouse.buttons_released, 0) {
			Released
		} else if mouse_button(mouse.buttons, 0) {
			Down
		} else {
			Idle
		}
}

## Fixed 100x60 root with 90-wide children from the test cases, and the hover
## path for a press at 97, 30 (inside the root, outside the children).
drag_test_scene : () -> Try({ layout : Layout(draw), hovered : List(U64) }, Layout.LayoutError)
drag_test_scene = || {
	root_cfg = Element.style.width(Fixed(100)).height(Fixed(60)).child_align({ x: Start, y: Start })
	child_cfg = Element.style.width(Fixed(90)).height(Fixed(20))
	layout = Layout.build_test_layout(root_cfg, [child_cfg], { w: 200, h: 200 })?
	hovered = layout.hover_path({ x: 97, y: 30 })?
	Ok({ layout, hovered })
}

## The press position used by the drag test cases.
drag_test_press : LayoutTypes.Pos
drag_test_press = { x: 97, y: 30 }

## Pressing an element with OnDragStart emits its message and captures it.
expect {
	match drag_test_scene() {
		Ok({ layout, hovered }) => {
			root_id = hovered.get(0)?
			bindings = Dict.empty().insert(root_id, [OnDragStart(Box.box(|_| ["start"]))])
			input = {
				x: drag_test_press.x,
				y: drag_test_press.y,
				buttons: [1],
				buttons_pressed: [1],
				buttons_released: [],
			}
			result = Drag.advance(layout, bindings, hovered, Idle, input)?
			result.messages == ["start"]
				and match result.drag {
					Dragging(info) => info.node_id == root_id
					Idle => Bool.False
				}
		}
		Err(_) => Bool.False
	}
}

## A captured drag keeps emitting OnDragMove with a live per-frame delta even
## when the pointer leaves the captured element.
expect {
	match drag_test_scene() {
		Ok({ layout, hovered }) => {
			root_id = hovered.get(0)?
			bindings = Dict.empty().insert(
				root_id,
				[
					OnDragStart(Box.box(|_| [])),
					OnDragMove(Box.box(|event| [event])),
					OnDragEnd(Box.box(|_| [])),
				],
			)
			press_input = {
				x: drag_test_press.x,
				y: drag_test_press.y,
				buttons: [1],
				buttons_pressed: [1],
				buttons_released: [],
			}
			move_input = {
				x: 150,
				y: 150,
				buttons: [1],
				buttons_pressed: [],
				buttons_released: [],
			}
			started = Drag.advance(layout, bindings, hovered, Idle, press_input)?
			moved = Drag.advance(layout, bindings, [root_id], started.drag, move_input)?
			match moved.messages.get(0) {
				Ok(event) =>
					event.delta.y == 120
						and event.delta.x == 53
							and event.position == { x: 150, y: 150 }
				Err(_) => Bool.False
			}
		}
		Err(_) => Bool.False
	}
}

## Releasing the button emits OnDragEnd with a zero delta and clears the drag.
expect {
	match drag_test_scene() {
		Ok({ layout, hovered }) => {
			root_id = hovered.get(0)?
			bindings = Dict.empty().insert(
				root_id,
				[
					OnDragStart(Box.box(|_| [])),
					OnDragEnd(Box.box(|event| if event.delta == { x: 0, y: 0 } { ["end"] } else { ["bad"] })),
				],
			)
			press_input = {
				x: drag_test_press.x,
				y: drag_test_press.y,
				buttons: [1],
				buttons_pressed: [1],
				buttons_released: [],
			}
			release_input = {
				x: 150,
				y: 150,
				buttons: [],
				buttons_pressed: [],
				buttons_released: [1],
			}
			started = Drag.advance(layout, bindings, hovered, Idle, press_input)?
			released = Drag.advance(layout, bindings, [root_id], started.drag, release_input)?
			released.messages == ["end"]
				and match released.drag {
					Idle => Bool.True
					Dragging(_) => Bool.False
				}
		}
		Err(_) => Bool.False
	}
}

## A press over an element without drag handlers stays Idle and produces no
## messages, letting normal click/hover handling proceed.
expect {
	match drag_test_scene() {
		Ok({ layout, hovered }) => {
			root_id = hovered.get(0)?
			bindings = Dict.empty().insert(root_id, [OnClick("click")])
			input = {
				x: drag_test_press.x,
				y: drag_test_press.y,
				buttons: [1],
				buttons_pressed: [1],
				buttons_released: [],
			}
			result = Drag.advance(layout, bindings, hovered, Idle, input)?
			result.messages == []
				and match result.drag {
					Idle => Bool.True
					Dragging(_) => Bool.False
				}
		}
		Err(_) => Bool.False
	}
}

## A missing left button press never captures, even over a handler-bearing box.
expect {
	match drag_test_scene() {
		Ok({ layout, hovered }) => {
			root_id = hovered.get(0)?
			bindings = Dict.empty().insert(root_id, [OnDragStart(Box.box(|_| ["start"]))])
			input = {
				x: drag_test_press.x,
				y: drag_test_press.y,
				buttons: [],
				buttons_pressed: [],
				buttons_released: [],
			}
			result = Drag.advance(layout, bindings, hovered, Idle, input)?
			result.messages == []
				and match result.drag {
					Idle => Bool.True
					Dragging(_) => Bool.False
				}
		}
		Err(_) => Bool.False
	}
}

## A lost frame mid-drag (no button data) keeps the capture alive silently.
expect {
	match drag_test_scene() {
		Ok({ layout, hovered }) => {
			root_id = hovered.get(0)?
			bindings = Dict.empty().insert(
				root_id,
				[
					OnDragStart(Box.box(|_| [])),
					OnDragMove(Box.box(|_| ["move"])),
				],
			)
			press_input = {
				x: drag_test_press.x,
				y: drag_test_press.y,
				buttons: [1],
				buttons_pressed: [1],
				buttons_released: [],
			}
			gap_input = {
				x: 150,
				y: 150,
				buttons: [],
				buttons_pressed: [],
				buttons_released: [],
			}
			started = Drag.advance(layout, bindings, hovered, Idle, press_input)?
			gapped = Drag.advance(layout, bindings, [root_id], started.drag, gap_input)?
			gapped.messages == []
				and match gapped.drag {
					Dragging(info) => info.last_pointer == drag_test_press
					Idle => Bool.False
				}
		}
		Err(_) => Bool.False
	}
}

## Pressing a non-draggable child over a draggable ancestor captures the
## ancestor, not the topmost hovered node (a slider handle over its track).
expect {
	match drag_test_scene() {
		Ok(scene) => {
			layout = scene.layout
			hovered = layout.hover_path({ x: 5, y: 5 })?
			child_id = hovered.get(0)?
			parent_id = hovered.get(1)?
			bindings =
				Dict.empty()
					.insert(child_id, [OnClick("click")])
					.insert(parent_id, [OnDragStart(Box.box(|_| ["start"]))])
			input = {
				x: 5,
				y: 5,
				buttons: [1],
				buttons_pressed: [1],
				buttons_released: [],
			}
			result = Drag.advance(layout, bindings, hovered, Idle, input)?
			result.messages == ["start"]
				and match result.drag {
					Dragging(info) => info.node_id == parent_id
					Idle => Bool.False
				}
		}
		Err(_) => Bool.False
	}
}

## has_drag_handlers detects any OnDrag* handler, and the test scene resolves
## to the fixed root bounds.
expect {
	match drag_test_scene() {
		Ok({ layout, hovered }) => {
			root_id = hovered.get(0)?
			Drag.has_drag_handlers([OnClick("click"), OnDragMove(Box.box(|_| []))])
				and !Drag.has_drag_handlers([OnClick("click")])
					and layout.node_bounds(root_id) == Ok({ x: 0, y: 0, width: 100, height: 60 })
		}
		Err(_) => Bool.False
	}
}
