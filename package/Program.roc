## Model-View-Update architecture runtime.
## Wires init, view, and update into the platform's { init!, render! } contract.
##
## Usage:
##   program = Program.new!({ config, init!, view, update: update! })
import Layout
import LayoutTypes
import Render
import Element
import Color
import Event

HostState(host) : {
	frame_time : F32,
	timestamp_nanos : U64,
	screen : { width : I32, height : I32 },
	keys : List(U8),
	mouse : {
		buttons : List(U8),
		left : Bool,
		middle : Bool,
		right : Bool,
		wheel : F32,
		wheel_x : F32,
		wheel_y : F32,
		delta_x : F32,
		delta_y : F32,
		x : F32,
		y : F32,
	},
	..host,
}

EventBindings(msg) : Dict(U64, List(Event.Handler(msg)))

## The pointer handler and mouse button retained for an active drag.
PointerCapture := [NoPointerCapture, CapturedPointer(U64, U64)]

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

	## Timing supplied to the optional pure per-frame model update.
	Frame : {
		delta_seconds : F32,
		timestamp_nanos : U64,
		screen : { width : F32, height : F32 },
	}

	Config : {
		title : Str,
		width : I32,
		height : I32,
		target_fps : I32,
		resizable : Bool,
		fullscreen : Bool,
		vsync : Bool,
		cursor_visible : Bool,
	}

	default : Config
	default = {
		title: "Terrocotta App",
		width: 800,
		height: 600,
		target_fps: 1000,
		resizable: Bool.True,
		fullscreen: Bool.False,
		vsync: Bool.False,
		cursor_visible: Bool.True,
	}

	State(model, msg) :: {
		model : model,
		layout : Layout,
		renderer : Render.Adapter,
		hovered : List(U64),
		focused : U64,
		pointer_capture : PointerCapture,
		scroll : Dict(U64, ScrollState),
	}

	## Program state for renderers which require a platform-owned capability on
	## every frame. The capability itself is never retained in the model.
	FrameState(model, msg, draw_frame) :: {
		model : model,
		layout : Layout,
		renderer : Render.FrameAdapter(draw_frame),
		hovered : List(U64),
		focused : U64,
		pointer_capture : PointerCapture,
		scroll : Dict(U64, ScrollState),
	}

	new! : {
		config : Config,
		renderer : Render.Adapter,
		init! : Config => Try(m, [Exit(I64)]),
		view : m -> Element.View(msg),
		update : m, msg -> m,
	} -> {
		init! : {
			config : Config,
			run! : HostState(host) => Try(State(m, msg), [Exit(I64)]),
		},
		render! : State(m, msg), HostState(host) => Try(State(m, msg), [Exit(I64), ..]),
	}
	new! = |{ config, renderer, init!, view, update }| Program.custom!({
		config,
		init!: |cfg| init!(cfg).map_ok(|model| { model, renderer }),
		on_frame!: |model, _frame| model,
		view,
		update,
	})

	## Build a program whose renderer is initialized alongside the application
	## model and whose model can advance from host timing and screen state each
	## frame. `on_frame!` may also update retained renderer resources such as
	## cached shader uniforms.
	##
	## Use this when the renderer retains host-owned resources such as shaders or
	## render targets. Existing applications should continue to use `new!`.
	custom! : {
		config : Config,
		init! : Config => Try({ model : m, renderer : Render.Adapter }, [Exit(I64)]),
		on_frame! : m, Frame => m,
		view : m -> Element.View(msg),
		update : m, msg -> m,
	} -> {
		init! : {
			config : Config,
			run! : HostState(host) => Try(State(m, msg), [Exit(I64)]),
		},
		render! : State(m, msg), HostState(host) => Try(State(m, msg), [Exit(I64), ..]),
	}
	custom! = |{ config, init!, on_frame!, view, update }| {
		run! = |_host| {
			initialized = init!(config)?
			model = initialized.model
			renderer = initialized.renderer
			Ok(
				State.(
					{
						model,
						layout: Layout.new(renderer),
						renderer,
						hovered: [],
						focused: 0,
						pointer_capture: NoPointerCapture,
						scroll: Dict.empty(),
					},
				),
			)
		}

		render! = |State.(state), host| {
			screen = { w: host.screen.width.to_f32(), h: host.screen.height.to_f32() }
			scroll = update_scroll_containers(state.layout, state.scroll, { x: host.mouse.x, y: host.mouse.y }, host.mouse.wheel).map_err(|_e| Exit(1))?
			frame = {
				delta_seconds: host.frame_time,
				timestamp_nanos: host.timestamp_nanos,
				screen: { width: screen.w, height: screen.h },
			}

			var $layout = state.layout.clear()
			var $event_bindings = Dict.empty()
			var $model = on_frame!(state.model, frame)

			for element_op in view($model) {
				# update layout
				($layout, node) = $layout.update!(
					element_op,
					|node_id| get_box_status(node_id, state.hovered, state.focused, state.pointer_capture, host),
					|node_id| scroll.get(node_id).map_ok(|item| item.position).ok_or({ x: 0, y: 0 }),
				).map_err(|_e| Exit(1))?

				## bind events
				$event_bindings = match node {
					Node(node_id, Events(events)) => {
						$event_bindings.insert(node_id, events)
					}
					_ => $event_bindings
				}
			}

			# solve layout
			$layout = $layout.solve(screen).map_err(|_e| Exit(1))?

			# event handling
			{ messages, hovered, focused, pointer_capture } = handle_events($layout, $event_bindings, host, state.hovered, state.focused, state.pointer_capture).map_err(|_e| Exit(1))?
			for message in messages {
				$model = update($model, message)
			}

			# render layout
			commands = $layout.to_commands(screen).map_err(|_e| Exit(1))?
			Render.render!(state.renderer, commands)

			Ok(State.({ model: $model, layout: $layout, renderer: state.renderer, hovered, focused, pointer_capture, scroll }))
		}

		{
			init!: { config, run! },
			render!,
		}
	}

	## Build a program around a renderer whose drawing operations require a
	## platform-owned per-frame capability. This mirrors `custom!`, but threads
	## that capability only through the render call.
	custom_frame! : {
		config : Config,
		init! : Config => Try({ model : m, renderer : Render.FrameAdapter(draw_frame) }, [Exit(I64)]),
		on_frame! : m, Frame => m,
		view : m -> Element.View(msg),
		update : m, msg -> m,
	} -> {
		init! : {
			config : Config,
			run! : HostState(host) => Try(FrameState(m, msg, draw_frame), [Exit(I64)]),
		},
		render! : FrameState(m, msg, draw_frame), HostState(host), draw_frame => Try(FrameState(m, msg, draw_frame), [Exit(I64), ..]),
	}
	custom_frame! = |{ config, init!, on_frame!, view, update }| {
		run! = |_host| {
			initialized = init!(config)?
			model = initialized.model
			renderer = initialized.renderer
			Ok(
				FrameState.(
					{
						model,
						layout: Layout.new_frame(renderer),
						renderer,
						hovered: [],
						focused: 0,
						pointer_capture: NoPointerCapture,
						scroll: Dict.empty(),
					},
				),
			)
		}

		render! = |FrameState.(state), host, draw_frame| {
			screen = { w: host.screen.width.to_f32(), h: host.screen.height.to_f32() }
			scroll = update_scroll_containers(state.layout, state.scroll, { x: host.mouse.x, y: host.mouse.y }, host.mouse.wheel).map_err(|_e| Exit(1))?
			frame_info = {
				delta_seconds: host.frame_time,
				timestamp_nanos: host.timestamp_nanos,
				screen: { width: screen.w, height: screen.h },
			}

			var $layout = state.layout.clear()
			var $event_bindings = Dict.empty()
			var $model = on_frame!(state.model, frame_info)

			for element_op in view($model) {
				($layout, node) = $layout.update!(
					element_op,
					|node_id| get_box_status(node_id, state.hovered, state.focused, state.pointer_capture, host),
					|node_id| scroll.get(node_id).map_ok(|item| item.position).ok_or({ x: 0, y: 0 }),
				).map_err(|_e| Exit(1))?

				$event_bindings = match node {
					Node(node_id, Events(events)) => $event_bindings.insert(node_id, events)
					_ => $event_bindings
				}
			}

			$layout = $layout.solve(screen).map_err(|_e| Exit(1))?
			{ messages, hovered, focused, pointer_capture } = handle_events($layout, $event_bindings, host, state.hovered, state.focused, state.pointer_capture).map_err(|_e| Exit(1))?
			for message in messages {
				$model = update($model, message)
			}

			commands = $layout.to_commands(screen).map_err(|_e| Exit(1))?
			Render.render_frame!(state.renderer, draw_frame, commands)

			Ok(FrameState.({ model: $model, layout: $layout, renderer: state.renderer, hovered, focused, pointer_capture, scroll }))
		}

		{
			init!: { config, run! },
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

## Clamp retained state and apply wheel input to the deepest hovered container.
update_scroll_containers : Layout, Dict(U64, ScrollState), LayoutTypes.Pos, F32 -> Try(Dict(U64, ScrollState), Layout.LayoutError)
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
	if wheel != 0 {
		match deepest_vertical_scroll_target(containers, hovered) {
			ScrollTarget(node_id) => {
				data = layout.get_scroll_container_data(node_id)
				current = $scroll.get(node_id).ok_or(default_scroll_state)
				next_y = clamp_scroll_axis(data.overflow.y, current.position.y + wheel * 10, data.content_dimensions.h, data.scroll_container_dimensions.h)
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

## Select the deepest hovered container that can scroll vertically.
deepest_vertical_scroll_target : List(ScrollCandidate), List(U64) -> [ScrollTarget(U64), NoScrollTarget]
deepest_vertical_scroll_target = |containers, hovered| {
	var $target = NoScrollTarget
	for node_id in hovered {
		if $target == NoScrollTarget {
			for data in containers {
				if data.id == node_id and scrolls_axis(data.overflow.y) {
					$target = ScrollTarget(node_id)
				}
			}
		}
	}
	$target
}

default_box_status : Element.BoxStatus
default_box_status = { hovered: Bool.False, pressed: Bool.False, focused: Bool.False, disabled: Bool.False }

get_box_status : U64, List(U64), U64, PointerCapture, HostState(host) -> Element.BoxStatus
get_box_status = |node_index, prev_hovered, focused, pointer_capture, host| {
	hovered = prev_hovered.contains(node_index)
	captured = match pointer_capture {
		NoPointerCapture => Bool.False
		CapturedPointer(captured_node, _) => captured_node == node_index
	}
	{ hovered, pressed: (hovered or captured) and host.mouse.left, focused: node_index == focused, disabled: Bool.False }
}

has_input_state : List(U8), U64, U8 -> Bool
has_input_state = |states, index, mask|
	match states.get(index) {
		Ok(state) => U8.bitwise_and(state, mask) != 0
		Err(_) => Bool.False
	}

handle_events : Layout, EventBindings(msg), HostState(host), List(U64), U64, PointerCapture -> Try({ messages : List(msg), hovered : List(U64), focused : U64, pointer_capture : PointerCapture }, Layout.LayoutError)
handle_events = |layout, event_bindings, host, prev_hovered, prev_focused, prev_pointer_capture| {
	root_index = 0
	pointer = { x: host.mouse.x, y: host.mouse.y }
	hovered = layout.hover_path(pointer)?
	# A new press follows the normal hover path once, then captures subsequent
	# drag frames. Existing capture is validated against the rebuilt view.
	pointer_capture_for_frame = match prev_pointer_capture {
		NoPointerCapture => NoPointerCapture
		CapturedPointer(_, _) => capture_for_pointer_events(prev_pointer_capture, event_bindings, hovered, host.mouse.buttons)
	}

	# OnPointerEnter/OnPointerLeave/OnHover
	var $msgs = get_pointer_enter_events(event_bindings, prev_hovered, hovered)
	$msgs = $msgs.concat(get_pointer_leave_events(event_bindings, prev_hovered, hovered))
	$msgs = $msgs.concat(get_hover_events(event_bindings, hovered))
	$msgs = $msgs.concat(get_pointer_events(layout, event_bindings, hovered, pointer_capture_for_frame, host)?)

	# OnClick
	mouse_left_button = 0
	if has_input_state(host.mouse.buttons, mouse_left_button, 2) and hovered.len() > 0 {
		node_index = hovered.get(0)?
		$msgs = $msgs.concat(get_click_events(event_bindings, node_index))
	}

	focused = if has_input_state(host.mouse.buttons, mouse_left_button, 2) {
		hovered.get(0).ok_or(root_index)
	} else {
		prev_focused
	}

	# Key events
	$msgs = $msgs.concat(get_key_events(event_bindings, focused, host.keys))
	pointer_capture_candidate = match pointer_capture_for_frame {
		CapturedPointer(_, _) => pointer_capture_for_frame
		NoPointerCapture => capture_for_pointer_events(NoPointerCapture, event_bindings, hovered, host.mouse.buttons)
	}
	pointer_capture = capture_after_pointer_events(pointer_capture_candidate, host.mouse.buttons)

	Ok({ messages: $msgs, hovered, focused, pointer_capture })
}

has_pointer_handler : EventBindings(msg), U64 -> Bool
has_pointer_handler = |bindings, node_index| {
	bindings
		.get(node_index)
		.ok_or([])
		.iter()
		.fold(
			Bool.False,
			|found, binding| if found {
				Bool.True
			} else {
				match binding {
					OnPointer(_) => Bool.True
					_ => Bool.False
				}
			},
		)
}

deepest_pointer_handler : EventBindings(msg), List(U64) -> [NoPointerHandler, PointerHandler(U64)]
deepest_pointer_handler = |bindings, hovered| {
	hovered.iter().fold(
		NoPointerHandler,
		|found, node_index| match found {
			PointerHandler(_) => found
			NoPointerHandler => if has_pointer_handler(bindings, node_index) PointerHandler(node_index) else NoPointerHandler
		},
	)
}

pressed_pointer_button : List(U8) -> [NoPointerButton, PointerButton(U64)]
pressed_pointer_button = |buttons| {
	if has_input_state(buttons, 0, 2) {
		PointerButton(0)
	} else if has_input_state(buttons, 1, 2) {
		PointerButton(1)
	} else if has_input_state(buttons, 2, 2) {
		PointerButton(2)
	} else {
		NoPointerButton
	}
}

## Start capture at the deepest pointer handler, or retain the existing drag.
capture_for_pointer_events : PointerCapture, EventBindings(msg), List(U64), List(U8) -> PointerCapture
capture_for_pointer_events = |previous, bindings, hovered, buttons| match previous {
	CapturedPointer(node_index, _button) => if has_pointer_handler(bindings, node_index) previous else NoPointerCapture
	NoPointerCapture => match pressed_pointer_button(buttons) {
		NoPointerButton => NoPointerCapture
		PointerButton(button) => match deepest_pointer_handler(bindings, hovered) {
			NoPointerHandler => NoPointerCapture
			PointerHandler(node_index) => CapturedPointer(node_index, button)
		}
	}
}

## Release capture after its initiating button is released or no longer held.
capture_after_pointer_events : PointerCapture, List(U8) -> PointerCapture
capture_after_pointer_events = |capture, buttons| match capture {
	NoPointerCapture => NoPointerCapture
	CapturedPointer(node_index, button) => {
		down = has_input_state(buttons, button, 1)
		pressed = has_input_state(buttons, button, 2)
		if down or pressed CapturedPointer(node_index, button) else NoPointerCapture
	}
}

pointer_event_nodes : List(U64), PointerCapture -> List(U64)
pointer_event_nodes = |hovered, pointer_capture| match pointer_capture {
	NoPointerCapture => hovered
	CapturedPointer(node_index, _) => [node_index]
}

pointer_button_state : HostState(host), U64 -> Event.PointerButtonState
pointer_button_state = |host, button| {
	{
		down: has_input_state(host.mouse.buttons, button, 1),
		pressed: has_input_state(host.mouse.buttons, button, 2),
		released: has_input_state(host.mouse.buttons, button, 4),
	}
}

pointer_buttons : HostState(host) -> Event.PointerButtons
pointer_buttons = |host| {
	{
		left: pointer_button_state(host, 0),
		middle: pointer_button_state(host, 2),
		right: pointer_button_state(host, 1),
	}
}

pointer_event : Layout, U64, HostState(host) -> Try(Event.PointerEvent, Layout.LayoutError)
pointer_event = |layout, node_id, host| {
	Ok({
		position: { x: host.mouse.x, y: host.mouse.y },
		buttons: pointer_buttons(host),
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

get_pointer_events : Layout, EventBindings(msg), List(U64), PointerCapture, HostState(host) -> Try(List(msg), Layout.LayoutError)
get_pointer_events = |layout, bindings, hovered, pointer_capture, host| {
	pointer_nodes = pointer_event_nodes(hovered, pointer_capture)
	var $msgs = []
	for node_index in pointer_nodes {
		event = pointer_event(layout, node_index, host)?
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
					OnKeyPressed(key, msg) => if has_input_state(keys, key, 2) {
						msgs.append(msg)
					} else {
						msgs
					}
					OnKeyDown(key, msg) => if has_input_state(keys, key, 1) {
						msgs.append(msg)
					} else {
						msgs
					}
					OnKeyUp(key, msg) => if has_input_state(keys, key, 4) {
						msgs.append(msg)
					} else {
						msgs
					}
					_ => msgs
				}
			},
		)
}

expect {
	bindings =
		Dict.empty()
			.insert(1, [OnPointerEnter("enter-one")])
			.insert(2, [OnPointerEnter("enter-two")])

	get_pointer_enter_events(bindings, [1], [2, 1]) == ["enter-two"]
}

## A press captures the deepest hovered pointer handler rather than a visual
## child without its own handler.
expect {
	bindings = Dict.empty().insert(2, [OnPointer(Box.box(|_event| [1.U64]))])
	match capture_for_pointer_events(NoPointerCapture, bindings, [3, 2, 1], [2.U8, 0.U8, 0.U8]) {
		CapturedPointer(node_index, button) => node_index == 2 and button == 0
		NoPointerCapture => Bool.False
	}
}

## Captured drags route outside the hover path and end when the button lifts.
expect {
	capture = CapturedPointer(2, 0)
	held = capture_after_pointer_events(capture, [1.U8, 0.U8, 0.U8])
	released = capture_after_pointer_events(capture, [4.U8, 0.U8, 0.U8])
	held_ok = match held {
		CapturedPointer(node_index, button) => node_index == 2 and button == 0
		NoPointerCapture => Bool.False
	}
	released_ok = match released {
		NoPointerCapture => Bool.True
		CapturedPointer(_, _) => Bool.False
	}
	pointer_event_nodes([9, 1], capture) == [2]
		and held_ok
			and released_ok
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
	deepest_vertical_scroll_target([outer, inner], [2, 1]) == ScrollTarget(2)
}

expect {
	bindings =
		Dict.empty()
			.insert(1, [OnPointerLeave("leave-one")])
			.insert(2, [OnPointerLeave("leave-two")])

	get_pointer_leave_events(bindings, [2, 1], [1]) == ["leave-two"]
}
