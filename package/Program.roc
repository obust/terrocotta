## Model-View-Update architecture runtime.
## Wires init, view, and update into the platform's { init!, render! } contract.
##
## Usage:
##   program = Program.new!({ config, init, view, update: update! })
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
		init : () -> m,
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
		{ init, view, update, config, renderer } = cfg

		screen = { w: config.width.to_f32(), h: config.height.to_f32() }

		init! = { config, run!: |_host| Ok({ model: init(), layout: Layout.new(), renderer, hovered: [], focused: 0 }) }
		render! = |state, host| {

			var $layout = state.layout.clear()
			var $event_bindings = Dict.empty()

			for element_op in view(state.model) {
				(node_index, node_status) = match element_op {
					OpenBox(_, _events) => {
						next_index = $layout.next_node_index()
						next_status = get_box_status(next_index, state.hovered, state.focused, host)
						(next_index, next_status)
					}
					_ => (0, default_box_status)
				}

				# update layout
				$layout = $layout.update!(element_op, node_status, state.renderer).map_err(|_e| Exit(1))?

				## bind events
				match element_op {
					OpenBox(_, events) => {
						$event_bindings = collect_event_bindings($event_bindings, node_index, events)
					}
					_ => {}
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
		{ init!, render! }
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

get_node_events : EventBindings(msg), U64 -> List(Element.Event(msg))
get_node_events = |bindings, node_index| {
	match bindings.get(node_index) {
		Ok(events) => events
		Err(_) => []
	}
}

collect_event_bindings : EventBindings(msg), U64, List(Element.Event(msg)) -> EventBindings(msg)
collect_event_bindings = |bindings, node_index, events| {
	if events.len() > 0 {
		bindings.insert(node_index, events)
	} else {
		bindings
	}
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

list_contains_u64 : List(U64), U64 -> Bool
list_contains_u64 = |items, needle| {
	var $found = Bool.False
	for item in items {
		if item == needle {
			$found = Bool.True
		}
	}
	$found
}

get_mouse_enter_events : EventBindings(msg), List(U64), List(U64) -> List(msg)
get_mouse_enter_events = |bindings, prev_hovered, next_hovered| {
	next_hovered.fold(
		[],
		|msgs, node_index| {
			if list_contains_u64(prev_hovered, node_index) {
				msgs
			} else {
				msgs.concat(
					get_node_events(bindings, node_index).fold(
						[],
						|node_msgs, event| {
							match event {
								OnMouseEnter(msg) => node_msgs.append(msg)
								_ => node_msgs
							}
						},
					),
				)
			}
		},
	)
}

get_mouse_leave_events : EventBindings(msg), List(U64), List(U64) -> List(msg)
get_mouse_leave_events = |bindings, prev_hovered, next_hovered| {
	prev_hovered.fold(
		[],
		|msgs, node_index| {
			if list_contains_u64(next_hovered, node_index) {
				msgs
			} else {
				msgs.concat(
					get_node_events(bindings, node_index).fold(
						[],
						|node_msgs, event| {
							match event {
								OnMouseLeave(msg) => node_msgs.append(msg)
								_ => node_msgs
							}
						},
					),
				)
			}
		},
	)
}

get_hover_events : EventBindings(msg), List(U64), Element.MouseEvent -> List(msg)
get_hover_events = |bindings, hovered, mouse_event| {
	hovered.fold(
		[],
		|msgs, node_index| {
			msgs.concat(
				get_node_events(bindings, node_index).fold(
					[],
					|node_msgs, event| {
						match event {
							OnHover(msg) => node_msgs.append(msg)
							OnHoverWith(callback) => node_msgs.append((Box.unbox(callback))(mouse_event))
							_ => node_msgs
						}
					},
				),
			)
		},
	)
}

get_click_events : EventBindings(msg), U64 -> List(msg)
get_click_events = |bindings, node_index| {
	get_node_events(bindings, node_index).fold(
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
	focused_bindings = match bindings.get(focused) {
		Ok(node_bindings) => node_bindings
		Err(_) => []
	}

	focused_bindings.fold(
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
