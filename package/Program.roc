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
	keys : List(U8),
	mouse : {
		buttons : List(U8),
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
		target_fps: 2000,
		resizable: Bool.True,
		fullscreen: Bool.False,
		vsync: Bool.False,
		cursor_visible: Bool.True,
	}

	State(draw, cursor_host, model, msg) := {
		model : model,
		layout : Layout(draw),
		renderer : Render(draw),
		hovered : List(U64),
		focused : U64,
		scroll : Dict(U64, ScrollState),
	}.{
		set_cursor! : State(draw, cursor_host, model, msg), U8 => {}
			where [cursor_host.set_cursor_raw! : U8 => {}]
		set_cursor! = |self, cursor| {
			Host : cursor_host
			_ = self
			Host.set_cursor_raw!(cursor)
		}
	}

	new! : {
		config : Config,
		init! : Config => Try(m, [Exit(I64)]),
		view : m -> Element.View(msg),
		update : m, msg -> m,
	} -> {
		init! : {
			config : Config,
			run! : HostState(host) => Try(State(draw, cursor_host, m, msg), [Exit(I64)]),
		},
		render! : State(draw, cursor_host, m, msg), HostState(host) => Try(State(draw, cursor_host, m, msg), [Exit(I64), ..]),
	}
		where [
			draw.measure_text_raw! : Render.MeasureTextRaw => Render.TextSize,
			draw.begin_frame! : () => {},
			draw.clear! : ({ r : U8, g : U8, b : U8, a : U8 }) => {},
			draw.text_raw! : ({ pos : Render.Vector2, text : Str, size : F32, spacing : F32, color : { r : U8, g : U8, b : U8, a : U8 }, font : U64 }) => {},
			draw.rectangle_raw! : ({ x : F32, y : F32, width : F32, height : F32, color : { r : U8, g : U8, b : U8, a : U8 } }) => {},
			draw.rounded_rectangle_raw! : ({ x : F32, y : F32, width : F32, height : F32, radius : F32, segments : I32, color : { r : U8, g : U8, b : U8, a : U8 } }) => {},
			draw.rounded_rectangle_lines_raw! : ({ x : F32, y : F32, width : F32, height : F32, radius : F32, segments : I32, color : { r : U8, g : U8, b : U8, a : U8 }, thickness : F32 }) => {},
			draw.draw_texture_raw! : ({ texture : U64, source : Render.Rect, dest : Render.Rect, origin : Render.Vector2, rotation : F32, tint : { r : U8, g : U8, b : U8, a : U8 } }) => {},
			draw.begin_scissor_raw! : ({ x : F32, y : F32, width : F32, height : F32 }) => {},
			draw.end_scissor_raw! : () => {},
			draw.fps! : {
				pos : {x: F32, y: F32},
				size : F32,
				color : { r : U8, g : U8, b : U8, a : U8 },
			} => {},
			draw.end_frame! : () => {},
			cursor_host.set_cursor_raw! : U8 => {},
		]
	new! = |{ config, init!, view, update }| {
		screen = { w: config.width.to_f32(), h: config.height.to_f32() }

		run! = |_host| {
			Ok(
				{
					model: init!(config)?,
					layout: Layout.new(),
					renderer: Render.{},
					hovered: [],
					focused: 0,
					scroll: Dict.empty(),
				},
			)
		}

		render! = |state, host| {
			scroll = update_scroll_containers(state.layout, state.scroll, { x: host.mouse.x, y: host.mouse.y }, host.mouse.wheel).map_err(|_e| Exit(1))?

			var $layout = state.layout.clear()
			var $event_bindings = Dict.empty()

			for element_op in view(state.model) {
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
			var $model = state.model
			{ messages, hovered, focused } = handle_events($layout, $event_bindings, host, state.hovered, state.focused).map_err(|_e| Exit(1))?
			for message in messages {
				$model = update($model, message)
			}

			cursor = $layout.cursor_for_path(hovered).map_err(|_e| Exit(1))?
			State.set_cursor!(state, cursor_code(cursor))

			# render layout
			commands = $layout.to_commands(screen).map_err(|_e| Exit(1))?
			state.renderer.render!(commands)

			Ok({ model: $model, layout: $layout, renderer: state.renderer, hovered, focused, scroll })
		}

		{
			init!: { config, run! },
			render!,
		}
	}
}

## Map Terrocotta cursor intent to roc-ray's raw cursor code.
cursor_code : Element.Cursor -> U8
cursor_code = |cursor| match cursor {
	Default => 0
	Arrow => 1
	IBeam => 2
	Crosshair => 3
	Pointer => 4
	ResizeX => 5
	ResizeY => 6
	ResizeNwse => 7
	ResizeNesw => 8
	ResizeAll => 9
	NotAllowed => 10
}

expect cursor_code(Default) == 0
expect cursor_code(Arrow) == 1
expect cursor_code(IBeam) == 2
expect cursor_code(Crosshair) == 3
expect cursor_code(Pointer) == 4
expect cursor_code(ResizeX) == 5
expect cursor_code(ResizeY) == 6
expect cursor_code(ResizeNwse) == 7
expect cursor_code(ResizeNesw) == 8
expect cursor_code(ResizeAll) == 9
expect cursor_code(NotAllowed) == 10

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
update_scroll_containers : Layout(draw), Dict(U64, ScrollState), LayoutTypes.Pos, F32 -> Try(Dict(U64, ScrollState), Layout.LayoutError)
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
	overflow :  { x: Element.Overflow, y: Element.Overflow },
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

is_mouse_button_down = |states, button| has_input_state(states, button, 1)
is_mouse_button_pressed = |states, button| has_input_state(states, button, 2)
is_mouse_button_released = |states, button| has_input_state(states, button, 4)

is_key_down = |states, key| has_input_state(states, key, 1)
is_key_pressed = |states, key| has_input_state(states, key, 2)
is_key_released = |states, key| has_input_state(states, key, 4)

expect {
	states = [0, 7]
	is_key_down(states, 1)
		and is_key_pressed(states, 1)
		and is_key_released(states, 1)
		and !is_key_down(states, 0)
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
	if is_mouse_button_pressed(host.mouse.buttons, mouse_left_button) and hovered.len() > 0 {
		node_index = hovered.get(0)?
		$msgs = $msgs.concat(get_click_events(event_bindings, node_index))
	}

	focused = if is_mouse_button_pressed(host.mouse.buttons, mouse_left_button) {
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
		down: is_mouse_button_down(host.mouse.buttons, button),
		pressed: is_mouse_button_pressed(host.mouse.buttons, button),
		released: is_mouse_button_released(host.mouse.buttons, button),
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
					OnKeyPressed(key, msg) => if is_key_pressed(keys, Event.key_code(key)) {
						msgs.append(msg)
					} else {
						msgs
					}
					OnKeyDown(key, msg) => if is_key_down(keys, Event.key_code(key)) {
						msgs.append(msg)
					} else {
						msgs
					}
					OnKeyUp(key, msg) => if is_key_released(keys, Event.key_code(key)) {
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
