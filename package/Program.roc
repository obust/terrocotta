## Platform-independent Model-View-Update state and stepping.
import Layout
import LayoutTypes
import Renderer
import Element
import Event
import Drag
import rrt.Devices
import rrt.Font
import rrt.Window
import rrt.Keys
import rrt.Mouse

TextureLike(fields) : { width : F32, height : F32, ..fields }

EventBindings(msg) : Dict(U64, List(Event.Handler(msg)))

ScrollState : {

	## Current horizontal and vertical content displacement.
	position : LayoutTypes.Pos,

	## Horizontal and vertical velocity retained for inertial scrolling.
	momentum : { x : F32, y : F32 },

	## Whether pointer-driven scrolling is currently active.
	pointer_active : Bool,

	## Pointer position captured when the current drag began.
	pointer_origin : LayoutTypes.Pos,

	## Scroll position captured when the current drag began.
	scroll_origin : LayoutTypes.Pos,

	## Time associated with the current inertial scroll motion.
	momentum_time : F32,
}

default_scroll_state : ScrollState
default_scroll_state = {
	position: { x: 0, y: 0 },
	momentum: { x: 0, y: 0 },
	pointer_active: Bool.False,
	pointer_origin: { x: 0, y: 0 },
	scroll_origin: { x: 0, y: 0 },
	momentum_time: 0,
}

Program :: [].{
	State(model, msg, texture) : {
		model : model,
		layout : Layout(texture),
		event_bindings : EventBindings(msg),
		hovered : List(U64),
		focused : U64,
		scroll : Dict(U64, ScrollState),
		drag : Drag.DragState,
		screen : LayoutTypes.Size,
	}

	## Adapt an argv-aware configure function and an application's init/update/view functions to
	## RocRay's current { init!, update!, render! } contract without importing
	## the platform.
	new = |configure, init!, update, view| {
		run! : startup => Try(State(model, msg, TextureLike(fields)), [Exit(I64), ..errors])
			where [startup.default_font! : startup => Try(Font, [AssetNotFound, AssetPathInvalid, AssetReadFailed, FontLoadFailed, ResourceLimit, ..])]
		run! = |startup| {
			font = startup.default_font!().map_err(|_| Exit(1))?
			model = init!(startup)?
			Ok({
				model,
				layout: Layout.new(font),
				event_bindings: Dict.empty(),
				hovered: [],
				focused: 0,
				scroll: Dict.empty(),
				drag: Idle,
				screen: { w: 0, h: 0 },
			})
		}

		update! : State(model, msg, TextureLike(fields)), { devices : Devices.Snapshot, window : Window.Snapshot, messages : List(msg), ..input } => Try(State(model, msg, TextureLike(fields)), [Exit(I64), ..])
		update! = |state, input| {
			{ mouse, .. } = input.devices
			screen = { w: input.window.size.width.to_f32(), h: input.window.size.height.to_f32() }

			scroll = update_scroll_containers(state.layout, state.scroll, mouse.position(), mouse.wheel_delta()).map_err(|_| Exit(1))?
			{ messages: event_messages, hovered, focused, drag } = handle_events(state.layout, state.event_bindings, input.devices, state.hovered, state.focused, state.drag).map_err(|_| Exit(1))?

			var $model = state.model
			for message in input.messages {
				$model = update($model, message)
			}
			for message in event_messages {
				$model = update($model, message)
			}

			var $layout = state.layout.clear()
			var $event_bindings = Dict.empty()
			for element_op in view($model) {
				($layout, node) = $layout.update(
					element_op,
					|node_id| get_box_status(node_id, hovered, focused, mouse),
					|node_id| scroll.get(node_id).map_ok(|item| item.position).ok_or({ x: 0, y: 0 }),
				).map_err(|_| Exit(1))?
				$event_bindings = match node {
					Node(node_id, Events(events)) => $event_bindings.insert(node_id, events)
					_ => $event_bindings
				}
			}

			$layout = $layout.solve(screen).map_err(|_| Exit(1))?
			Ok({ model: $model, layout: $layout, event_bindings: $event_bindings, hovered, focused, scroll, drag, screen })
		}

		render! = |state, frame| {
			Renderer.draw!(frame, state.layout, state.screen)
		}

		{
			init!: { config: configure, run! },
			update!,
			render!,
		}
	}

}

## Return whether an overflow mode permits user scrolling.
scrolls_axis : Element.Overflow -> Bool
scrolls_axis = |mode| match mode {
	Visible => Bool.False
	Hidden => Bool.False
	Scroll => Bool.True
}

## Clamp one retained scroll axis to its valid content range.
clamp_scroll_axis : Element.Overflow, F32, F32, F32 -> F32
clamp_scroll_axis = |mode, current, content, viewport| {
	if scrolls_axis(mode) {
		minimum = 0 - F32.max(content - viewport, 0)
		F32.min(0, F32.max(minimum, current))
	} else {
		0
	}
}

## Clamp retained state and apply each wheel axis to the deepest hovered
## container that scrolls on that axis.
update_scroll_containers : Layout(texture), Dict(U64, ScrollState), LayoutTypes.Pos, LayoutTypes.Pos -> Try(Dict(U64, ScrollState), Layout.LayoutError)
update_scroll_containers = |layout, scroll, pointer, wheel| {
	hovered = layout.hover_path(pointer)?
	containers = layout.scroll_containers()
	var $scroll = scroll
	for node in containers {
		{
			current = $scroll.get(node.id).ok_or(default_scroll_state)
			base_x = clamp_scroll_axis(node.overflow.x, current.position.x, node.content_dimensions.w, node.scroll_container_dimensions.w)
			base_y = clamp_scroll_axis(node.overflow.y, current.position.y, node.content_dimensions.h, node.scroll_container_dimensions.h)
			position = { x: base_x, y: base_y }
			$scroll = $scroll.insert(node.id, { ..current, position })
		}
	}
	if wheel.x != 0 {
		match deepest_scroll_target(containers, hovered, XAxis) {
			ScrollTarget(node_id) => {
				data = layout.get_scroll_container_data(node_id)
				current = $scroll.get(node_id).ok_or(default_scroll_state)
				next_x = clamp_scroll_axis(data.overflow.x, current.position.x + wheel.x * 10, data.content_dimensions.w, data.scroll_container_dimensions.w)
				$scroll = $scroll.insert(node_id, { ..current, position: { ..current.position, x: next_x } })
			}
			NoScrollTarget => {}
		}
	}
	if wheel.y != 0 {
		match deepest_scroll_target(containers, hovered, YAxis) {
			ScrollTarget(node_id) => {
				data = layout.get_scroll_container_data(node_id)
				current = $scroll.get(node_id).ok_or(default_scroll_state)
				next_y = clamp_scroll_axis(data.overflow.y, current.position.y + wheel.y * 10, data.content_dimensions.h, data.scroll_container_dimensions.h)
				$scroll = $scroll.insert(node_id, { ..current, position: { ..current.position, y: next_y } })
			}
			NoScrollTarget => {}
		}
	}
	Ok($scroll)
}

ScrollCandidate : {
	id : U64,
	scroll_container_dimensions : LayoutTypes.Size,
	content_dimensions : LayoutTypes.Size,
	overflow : { x : Element.Overflow, y : Element.Overflow },
	scroll_position : LayoutTypes.Pos,
}

## Select the deepest hovered container that can scroll on an axis.
deepest_scroll_target : List(ScrollCandidate), List(U64), LayoutTypes.Axis -> [ScrollTarget(U64), NoScrollTarget]
deepest_scroll_target = |containers, hovered, axis| {
	var $target = NoScrollTarget
	for node_id in hovered {
		if $target == NoScrollTarget {
			for data in containers {
				overflow = match axis {
					XAxis => data.overflow.x
					YAxis => data.overflow.y
				}
				if data.id == node_id and scrolls_axis(overflow) {
					$target = ScrollTarget(node_id)
				}
			}
		}
	}
	$target
}

default_box_status : Element.BoxStatus
default_box_status = { hovered: Bool.False, pressed: Bool.False, focused: Bool.False, disabled: Bool.False }

get_box_status : U64, List(U64), U64, Mouse.Snapshot -> Element.BoxStatus
get_box_status = |node_index, prev_hovered, focused, mouse| {
	hovered = prev_hovered.contains(node_index)
	{ hovered, pressed: hovered and mouse.button_down(Left), focused: node_index == focused, disabled: Bool.False }
}

handle_events : Layout(texture), EventBindings(msg), Devices.Snapshot, List(U64), U64, Drag.DragState -> Try({ messages : List(msg), hovered : List(U64), focused : U64, drag : Drag.DragState }, Layout.LayoutError)
handle_events = |layout, event_bindings, devices, prev_hovered, prev_focused, prev_drag| {
	{ mouse, keys, text_input, .. } = devices

	root_index = 0
	pointer = mouse.position()
	hovered = layout.hover_path(pointer)?

	# OnPointerEnter/OnPointerLeave/OnHover
	var $msgs = get_pointer_enter_events(event_bindings, prev_hovered, hovered)
	$msgs = $msgs.concat(get_pointer_leave_events(event_bindings, prev_hovered, hovered))
	$msgs = $msgs.concat(get_hover_events(event_bindings, hovered))
	$msgs = $msgs.concat(get_pointer_events(layout, event_bindings, hovered, mouse)?)

	# Targeted pointer button events. OnClick retains its current primary-button
	# press behavior; the explicit phase handlers expose every mouse button.
	if mouse.button_pressed(Left) and hovered.len() > 0 {
		node_index = hovered.get(0)?
		$msgs = $msgs.concat(get_click_events(event_bindings, node_index))
	}
	if hovered.len() > 0 {
		node_index = hovered.get(0)?
		$msgs = $msgs.concat(get_pointer_button_events(event_bindings, node_index, mouse))
	}

	focused = if mouse.button_pressed(Left) {
		focus_target(event_bindings, hovered, root_index)
	} else {
		prev_focused
	}

	# Key events
	$msgs = $msgs.concat(get_key_events(event_bindings, focused, keys))
	$msgs = $msgs.concat(get_text_input_events(event_bindings, focused, keys, text_input))

	# Drag gestures
	{ drag, messages: drag_msgs } = Drag.advance(layout, event_bindings, hovered, prev_drag, mouse)?
	$msgs = $msgs.concat(drag_msgs)

	Ok({ messages: $msgs, hovered, focused, drag })
}

## Pick the deepest hovered node that is focusable (aka has key event bindings).
focus_target : EventBindings(msg), List(U64), U64 -> U64
focus_target = |bindings, hovered, root_index| {
	is_focusable = |event| match event {
		OnKeyPressed(_, _) | OnKeyDown(_, _) | OnKeyReleased(_, _) | OnTextInput(_) => Bool.True
		_ => Bool.False
	}
	hovered
		.find_last(
			|node_id|
				bindings
					.get(node_id)
					.ok_or([])
					.fold(Bool.False, |focusable, event| focusable or is_focusable(event)),
		)
		.ok_or(root_index)
}

pointer_event : Layout(texture), U64, Mouse.Snapshot -> Try(Event.PointerEvent, Layout.LayoutError)
pointer_event = |layout, node_id, mouse| {
	Ok({
		position: mouse.position(),
		mouse,
		target: {
			id: node_id,
			bounds: layout.node_bounds(node_id)?,
		},
	})
}

get_pointer_enter_events : EventBindings(msg), List(U64), List(U64) -> List(msg)
get_pointer_enter_events = |bindings, prev_hovered, next_hovered| {
	next_hovered
		.iter()
		.keep_if(|node_index| !prev_hovered.contains(node_index))
		.fold(
			[],
			|msgs, node_index| {
				bindings
					.get(node_index)
					.ok_or([])
					.iter()
					.fold(
						msgs,
						|event_msgs, event| {
							match event {
								OnPointerEnter(msg) => event_msgs.append(msg)
								_ => event_msgs
							}
						},
					)
			},
		)
}

get_pointer_leave_events : EventBindings(msg), List(U64), List(U64) -> List(msg)
get_pointer_leave_events = |bindings, prev_hovered, next_hovered| {
	prev_hovered
		.iter()
		.keep_if(|node_index| !next_hovered.contains(node_index))
		.fold(
			[],
			|msgs, node_index| {
				bindings
					.get(node_index)
					.ok_or([])
					.iter()
					.fold(
						msgs,
						|event_msgs, event| {
							match event {
								OnPointerLeave(msg) => event_msgs.append(msg)
								_ => event_msgs
							}
						},
					)
			},
		)
}

get_hover_events : EventBindings(msg), List(U64) -> List(msg)
get_hover_events = |bindings, hovered| {
	hovered
		.iter()
		.fold(
			[],
			|msgs, node_index| {
				bindings
					.get(node_index)
					.ok_or([])
					.iter()
					.fold(
						msgs,
						|event_msgs, event| {
							match event {
								OnHover(msg) => event_msgs.append(msg)
								_ => event_msgs
							}
						},
					)
			},
		)
}

get_pointer_events : Layout(texture), EventBindings(msg), List(U64), Mouse.Snapshot -> Try(List(msg), Layout.LayoutError)
get_pointer_events = |layout, bindings, hovered, mouse| {
	var $msgs = []
	for node_index in hovered {
		event = pointer_event(layout, node_index, mouse)?
		$msgs = $msgs.concat(
			bindings
				.get(node_index)
				.ok_or([])
				.iter()
				.fold(
					[],
					|event_msgs, binding| {
						match binding {
							OnPointer(callback) => event_msgs.concat((Box.unbox(callback))(event))
							_ => event_msgs
						}
					},
				),
		)
	}
	Ok($msgs)
}

get_pointer_button_events : EventBindings(msg), U64, Mouse.Snapshot -> List(msg)
get_pointer_button_events = |bindings, node_index, mouse| {
	bindings
		.get(node_index)
		.ok_or([])
		.iter()
		.fold(
			[],
			|msgs, event| {
				match event {
					OnPointerPressed(button, msg) => if mouse.button_pressed(button) msgs.append(msg) else msgs
					OnPointerDown(button, msg) => if mouse.button_down(button) msgs.append(msg) else msgs
					OnPointerReleased(button, msg) => if mouse.button_released(button) msgs.append(msg) else msgs
					_ => msgs
				}
			},
		)
}

get_click_events : EventBindings(msg), U64 -> List(msg)
get_click_events = |bindings, node_index| {
	bindings
		.get(node_index)
		.ok_or([])
		.iter()
		.fold(
			[],
			|msgs, event| {
				match event {
					OnClick(msg) => msgs.append(msg)
					_ => msgs
				}
			},
		)
}

get_key_events : EventBindings(msg), U64, List(U8) -> List(msg)
get_key_events = |bindings, focused, keys| {
	bindings
		.get(focused)
		.ok_or([])
		.iter()
		.fold(
			[],
			|msgs, binding| {
				match binding {
					OnKeyPressed(key, msg) => if Keys.key_pressed({ keys: keys }, key) {
						msgs.append(msg)
					} else {
						msgs
					}
					OnKeyDown(key, msg) => if Keys.key_down({ keys: keys }, key) {
						msgs.append(msg)
					} else {
						msgs
					}
					OnKeyReleased(key, msg) => if Keys.key_released({ keys: keys }, key) {
						msgs.append(msg)
					} else {
						msgs
					}
					_ => msgs
				}
			},
		)
}

get_text_control_keys : List(U8) -> List(Event.TextControlKey)
get_text_control_keys = |keys| {
	var $control_keys = []
	if Keys.key_pressed(
		{
			keys: keys,
		},
		KeyLeft,
	) {
		$control_keys = $control_keys.append(KeyLeft)
	}
	if Keys.key_pressed(
		{
			keys: keys,
		},
		KeyRight,
	) {
		$control_keys = $control_keys.append(KeyRight)
	}
	if Keys.key_pressed(
		{
			keys: keys,
		},
		KeyHome,
	) {
		$control_keys = $control_keys.append(KeyHome)
	}
	if Keys.key_pressed(
		{
			keys: keys,
		},
		KeyEnd,
	) {
		$control_keys = $control_keys.append(KeyEnd)
	}
	if Keys.key_pressed(
		{
			keys: keys,
		},
		KeyBackspace,
	) {
		$control_keys = $control_keys.append(KeyBackspace)
	}
	if Keys.key_pressed(
		{
			keys: keys,
		},
		KeyDelete,
	) {
		$control_keys = $control_keys.append(KeyDelete)
	}
	$control_keys
}

get_text_input_events : EventBindings(msg), U64, List(U8), List(U32) -> List(msg)
get_text_input_events = |bindings, focused, key_states, codepoints| {
	control_keys = get_text_control_keys(key_states)
	if codepoints.is_empty() and control_keys.is_empty() {
		[]
	} else {
		bindings
			.get(focused)
			.ok_or([])
			.iter()
			.fold(
				[],
				|msgs, binding| {
					match binding {
						OnTextInput(callback) => msgs.append((Box.unbox(callback))({ codepoints, keys: control_keys }))
						_ => msgs
					}
				},
			)
	}
}

expect {
	bindings =
		Dict.empty()
			.insert(1, [OnPointerEnter("enter-one")])
			.insert(2, [OnPointerEnter("enter-two")])

	get_pointer_enter_events(bindings, [1], [2, 1]) == ["enter-two"]
}

## Scroll positions clamp at the top and bottom limits.
expect {
	clamp_scroll_axis(Scroll, 15, 140, 60) == 0
		and clamp_scroll_axis(Scroll, -200, 140, 60) == -80
}

## A retained position is clamped upward when content shrinks.
expect {
	clamp_scroll_axis(Scroll, -80, 90, 60) == -30
}

## Scroll overflow stays clamped when content fits and moves when it overflows.
expect {
	scrolls_axis(Scroll)
		and clamp_scroll_axis(Scroll, -20, 60, 60) == 0
			and scrolls_axis(Scroll)
				and clamp_scroll_axis(Scroll, -20, 100, 60) == -20
}

## The deepest hovered scrollable container wins wheel routing.
expect {
	outer = {
		id: 1,
		scroll_container_dimensions: { w: 100, h: 100 },
		content_dimensions: { w: 100, h: 300 },
		overflow: { x: Hidden, y: Scroll },
		scroll_position: { x: 0, y: 0 },
	}
	inner = {
		id: 2,
		scroll_container_dimensions: { w: 80, h: 80 },
		content_dimensions: { w: 80, h: 200 },
		overflow: { x: Hidden, y: Scroll },
		scroll_position: { x: 0, y: 0 },
	}
	deepest_scroll_target([outer, inner], [2, 1], YAxis) == ScrollTarget(2)
}

## Wheel routing selects independently by axis.
expect {
	horizontal = {
		id: 3,
		scroll_container_dimensions: { w: 100, h: 100 },
		content_dimensions: { w: 300, h: 100 },
		overflow: { x: Scroll, y: Hidden },
		scroll_position: { x: 0, y: 0 },
	}
	deepest_scroll_target([horizontal], [3], XAxis) == ScrollTarget(3)
		and deepest_scroll_target([horizontal], [3], YAxis) == NoScrollTarget
}

## Packed key bits are queried directly through rrt.Keys.
expect {
	bindings = Dict.empty().insert(
		1,
		[
			OnKeyPressed(Raw(0), "pressed"),
			OnKeyDown(Raw(0), "down"),
			OnKeyReleased(Raw(0), "released"),
		],
	)
	get_key_events(bindings, 1, [7]) == ["pressed", "down", "released"]
}

## Committed text is batched once for the focused text-input handler.
expect {
	bindings = Dict.empty().insert(
		1,
		[OnTextInput(Box.box(|event| event))],
	)
	key_states = Devices.none.with_key_pressed(KeyLeft).with_key_pressed(KeyBackspace).keys
	get_text_input_events(bindings, 1, [], [0xE9, 0x1F426]) == [{ codepoints: [0xE9, 0x1F426], keys: [] }]
		and get_text_input_events(bindings, 1, key_states, []) == [{ codepoints: [], keys: [KeyLeft, KeyBackspace] }]
			and get_text_input_events(bindings, 1, [], []) == []
				and get_text_input_events(bindings, 2, [], [65]) == []
}

pointer_button_test_mouse : Mouse.Snapshot
pointer_button_test_mouse = {
	buttons: [3, 4],
	left: Bool.True,
	middle: Bool.False,
	right: Bool.False,
	wheel: 0,
	wheel_x: 0,
	wheel_y: 0,
	delta_x: 2,
	delta_y: 3,
	x: 10,
	y: 20,
}

## Pointer phase handlers share RocRay's packed mouse-button semantics.
expect {
	bindings = Dict.empty().insert(
		1,
		[
			OnPointerPressed(Left, "left-pressed"),
			OnPointerDown(Left, "left-down"),
			OnPointerReleased(Right, "right-released"),
			OnPointerReleased(Left, "left-released"),
		],
	)
	get_pointer_button_events(bindings, 1, pointer_button_test_mouse) == ["left-pressed", "left-down", "right-released"]
}

expect {
	bindings =
		Dict.empty()
			.insert(1, [OnPointerLeave("leave-one")])
			.insert(2, [OnPointerLeave("leave-two")])

	get_pointer_leave_events(bindings, [2, 1], [1]) == ["leave-two"]
}
