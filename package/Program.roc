## Model-View-Update architecture runtime.
## Wires init, view, and update into the platform's { init!, render! } contract.
##
## Usage:
##   program = Program.new!({ config, init!, view, update: update! })
import Layout
import Render
import Element
import Color

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

EventBindings(msg) : Dict(U64, List(Element.Event(msg)))

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
	new! = |cfg| {
		{ view, update, config, renderer, .. } = cfg

		screen = { w: config.width.to_f32(), h: config.height.to_f32() }

		run! = |_host|
			Ok(
				{
					model: cfg.init!(config)?,
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
			$layout = $layout.solve!(screen).map_err(|_e| Exit(1))?

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
	mouse_event = { x: host.mouse.x, y: host.mouse.y, left: host.mouse.left, middle: host.mouse.middle, right: host.mouse.right, wheel: host.mouse.wheel }
	hovered = layout.hover_path(pointer)?

	# OnMouseEnter/OnMouseLeave/OnHover
	var $msgs = get_mouse_enter_events(event_bindings, prev_hovered, hovered)
	$msgs = $msgs.concat(get_mouse_leave_events(event_bindings, prev_hovered, hovered))
	$msgs = $msgs.concat(get_hover_events(event_bindings, hovered, mouse_event))

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

get_mouse_enter_events : EventBindings(msg), List(U64), List(U64) -> List(msg)
get_mouse_enter_events = |bindings, prev_hovered, next_hovered| {
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
								OnMouseEnter(msg) => event_msgs.append(msg)
								_ => event_msgs
							}
						},
					)
			},
		)
}

get_mouse_leave_events : EventBindings(msg), List(U64), List(U64) -> List(msg)
get_mouse_leave_events = |bindings, prev_hovered, next_hovered| {
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
								OnMouseLeave(msg) => event_msgs.append(msg)
								_ => event_msgs
							}
						},
					)
			},
		)
}

get_hover_events : EventBindings(msg), List(U64), Element.MouseEvent -> List(msg)
get_hover_events = |bindings, hovered, mouse_event| {
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
								OnHoverWith(callback) => event_msgs.append((Box.unbox(callback))(mouse_event))
								_ => event_msgs
							}
						},
					)
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
