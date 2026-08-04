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
		on_frame: |model, _frame| model,
		view,
		update,
	})

	## Build a program whose renderer is initialized alongside the application
	## model and whose model can advance from the host clock every frame.
	##
	## Use this when the renderer retains host-owned resources such as shaders or
	## render targets. Existing applications should continue to use `new!`.
	custom! : {
		config : Config,
		init! : Config => Try({ model : m, renderer : Render.Adapter }, [Exit(I64)]),
		on_frame : m, Frame -> m,
		view : m -> Element.View(msg),
		update : m, msg -> m,
	} -> {
		init! : {
			config : Config,
			run! : HostState(host) => Try(State(m, msg), [Exit(I64)]),
		},
		render! : State(m, msg), HostState(host) => Try(State(m, msg), [Exit(I64), ..]),
	}
	custom! = |{ config, init!, on_frame, view, update }| {
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
						scroll: Dict.empty(),
					},
				),
			)
		}

		render! = |State.(state), host| {
			screen = { w: host.screen.width.to_f32(), h: host.screen.height.to_f32() }
			scroll = update_scroll_containers(state.layout, state.scroll, { x: host.mouse.x, y: host.mouse.y }, host.mouse.wheel).map_err(|_e| Exit(1))?
			frame = { delta_seconds: host.frame_time, timestamp_nanos: host.timestamp_nanos }

			var $layout = state.layout.clear()
			var $event_bindings = Dict.empty()
			var $model = on_frame(state.model, frame)

			for element_op in view($model) {
				# update layout
				($layout, node) = $layout.update!(
					element_op,
					|node_id| get_box_status(node_id, state.hovered, state.focused, host),
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
			{ messages, hovered, focused } = handle_events($layout, $event_bindings, host, state.hovered, state.focused).map_err(|_e| Exit(1))?
			for message in messages {
				$model = update($model, message)
			}

			# render layout
			commands = $layout.to_commands(screen).map_err(|_e| Exit(1))?
			Render.render!(state.renderer, commands)

			Ok(State.({ model: $model, layout: $layout, renderer: state.renderer, hovered, focused, scroll }))
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

get_box_status : U64, List(U64), U64, HostState(host) -> Element.BoxStatus
get_box_status = |node_index, prev_hovered, focused, host| {
	hovered = prev_hovered.contains(node_index)
	{ hovered, pressed: hovered and host.mouse.left, focused: node_index == focused, disabled: Bool.False }
}

has_input_state : List(U8), U64, U8 -> Bool
has_input_state = |states, index, mask|
	match states.get(index) {
		Ok(state) => U8.bitwise_and(state, mask) != 0
		Err(_) => Bool.False
	}

handle_events : Layout, EventBindings(msg), HostState(host), List(U64), U64 -> Try({ messages : List(msg), hovered : List(U64), focused : U64 }, Layout.LayoutError)
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

	Ok({ messages: $msgs, hovered, focused })
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

get_pointer_events : Layout, EventBindings(msg), List(U64), HostState(host) -> Try(List(msg), Layout.LayoutError)
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
