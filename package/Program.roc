## Model-View-Update architecture runtime.
## Wires init, view, and update into the platform's { init!, render! } contract.
##
## Usage:
##   program = Program.new!({ config, init!, view, update: update! })
import Layout
import Render
import Element
import Color
import Event

HostState(host) : {
	keys : List(U8),
	keys_pressed : List(U8),
	keys_released : List(U8),
	mouse : {
		buttons : List(U8),
		buttons_pressed : List(U8),
		buttons_released : List(U8),
		left : Bool,
		middle : Bool,
		right : Bool,
		wheel : F32,
		x : F32,
		y : F32,
	},
	..host,
}

EventBindings(msg) : Dict(U64, List(Event.Handler(msg)))

Program :: [].{

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
		target_fps: 240,
		resizable: Bool.True,
		fullscreen: Bool.False,
		vsync: Bool.False,
		cursor_visible: Bool.True,
	}

	State(draw, model, msg) : {
		model : model,
		layout : Layout.Layout(draw),
		renderer : Render.Renderer,
		hovered : List(U64),
		focused : U64,
	}

	new! : {
		config : Config,
		renderer : Render.Renderer,
		init! : Config => Try(m, [Exit(I64)]),
		view : m -> Element.View(msg),
		update : m, msg -> m,
	} -> {
		init! : {
			config : Config,
			run! : HostState(host) => Try(State(draw, m, msg), [Exit(I64)]),
		},
		render! : State(draw, m, msg), HostState(host) => Try(State(draw, m, msg), [Exit(I64), ..]),
	}
	new! = |program| {
		{ view, update, config, renderer, init!, .. } = program

		screen = { w: config.width.to_f32(), h: config.height.to_f32() }

		run! = |_host|
			Ok(
				{
					model: init!(config)?,
					layout: Layout.new(),
					renderer,
					hovered: [],
					focused: 0,
				},
			)

		render! = |state, host| {

			var $layout = state.layout.clear()
			var $event_bindings = Dict.empty()

			for element_op in view(state.model) {
				# update layout
				($layout, node) = $layout.update!(
					element_op,
					|node_id| get_box_status(node_id, state.hovered, state.focused, host),
					renderer.measure_text_raw,
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
			var $model = state.model
			{ messages, hovered, focused } = handle_events($layout, $event_bindings, host, state.hovered, state.focused).map_err(|_e| Exit(1))?
			for message in messages {
				$model = update($model, message)
			}

			# render layout
			commands = $layout.to_commands(screen).map_err(|_e| Exit(1))?
			Render.render!(state.renderer, commands)

			Ok({ model: $model, layout: $layout, renderer: state.renderer, hovered, focused })
		}

		{
			init!: { config, run! },
			render!,
		}
	}
}

default_box_status : Element.BoxStatus
default_box_status = { hovered: Bool.False, pressed: Bool.False, focused: Bool.False, disabled: Bool.False }

get_box_status : U64, List(U64), U64, HostState(host) -> Element.BoxStatus
get_box_status = |node_index, prev_hovered, focused, host| {
	hovered = prev_hovered.contains(node_index)
	{ hovered, pressed: hovered and host.mouse.left, focused: node_index == focused, disabled: Bool.False }
}

is_mouse_button_pressed : List(U8), U64 -> Bool
is_mouse_button_pressed = |states, button|
	match states.get(button) {
		Ok(state) => state == 1
		Err(_) => Bool.False
	}

is_key_pressed : List(U8), U64 -> Bool
is_key_pressed = |states, key|
	match states.get(key) {
		Ok(state) => state == 1
		Err(_) => Bool.False
	}

handle_events : Layout(draw), EventBindings(msg), HostState(host), List(U64), U64 -> Try({ messages : List(msg), hovered : List(U64), focused : U64 }, Layout.LayoutError)
handle_events = |layout, event_bindings, host, prev_hovered, prev_focused| {
	root_index = 0
	pointer = { x: host.mouse.x, y: host.mouse.y }
	hovered = layout.hover_path(pointer)?

	# OnPointerEnter/OnPointerLeave/OnHover
	var $msgs = get_pointer_enter_events(event_bindings, prev_hovered, hovered)
	$msgs = $msgs.concat(get_pointer_leave_events(event_bindings, prev_hovered, hovered))
	$msgs = $msgs.concat(get_hover_events(event_bindings, hovered))
	$msgs = $msgs.concat(get_pointer_events(layout, event_bindings, hovered, host)?)

	# OnClick
	mouse_left_button = 0
	if is_mouse_button_pressed(host.mouse.buttons_pressed, mouse_left_button) and hovered.len() > 0 {
		node_index = hovered.get(0)?
		$msgs = $msgs.concat(get_click_events(event_bindings, node_index))
	}

	focused = if is_mouse_button_pressed(host.mouse.buttons_pressed, mouse_left_button) {
		hovered.get(0).ok_or(root_index)
	} else {
		prev_focused
	}

	# Key events
	$msgs = $msgs.concat(get_key_events(event_bindings, focused, host.keys_pressed, host.keys, host.keys_released))

	Ok({ messages: $msgs, hovered, focused })
}

pointer_button_state : HostState(host), U64 -> Event.PointerButtonState
pointer_button_state = |host, button| {
	{
		down: is_mouse_button_pressed(host.mouse.buttons, button),
		pressed: is_mouse_button_pressed(host.mouse.buttons_pressed, button),
		released: is_mouse_button_pressed(host.mouse.buttons_released, button),
	}
}

pointer_buttons : HostState(host) -> Event.PointerButtons
pointer_buttons = |host| {
	{
		left: pointer_button_state(host, 0),
		middle: pointer_button_state(host, 1),
		right: pointer_button_state(host, 2),
	}
}

pointer_event : Layout(draw), U64, HostState(host) -> Try(Event.PointerEvent, Layout.LayoutError)
pointer_event = |layout, node_id, host| {
	Ok(
		{
			position: { x: host.mouse.x, y: host.mouse.y },
			buttons: pointer_buttons(host),
			target: {
				id: node_id,
				bounds: layout.node_bounds(node_id)?,
			},
		},
	)
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

get_pointer_events : Layout(draw), EventBindings(msg), List(U64), HostState(host) -> Try(List(msg), Layout.LayoutError)
get_pointer_events = |layout, bindings, hovered, host| {
	var $msgs = []
	for node_index in hovered {
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

get_key_events : EventBindings(msg), U64, List(U8), List(U8), List(U8) -> List(msg)
get_key_events = |bindings, focused, keys_pressed, keys_down, keys_released| {
	bindings
		.get(focused)
		.ok_or([])
		.iter()
		.fold(
			[],
			|msgs, binding| {
				match binding {
					OnKeyPressed(key, msg) => if is_key_pressed(keys_pressed, key) {
						msgs.append(msg)
					} else {
						msgs
					}
					OnKeyDown(key, msg) => if is_key_pressed(keys_down, key) {
						msgs.append(msg)
					} else {
						msgs
					}
					OnKeyUp(key, msg) => if is_key_pressed(keys_released, key) {
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

expect {
	bindings =
		Dict.empty()
			.insert(1, [OnPointerLeave("leave-one")])
			.insert(2, [OnPointerLeave("leave-two")])

	get_pointer_leave_events(bindings, [2, 1], [1]) == ["leave-two"]
}
