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
    ..host
}


MouseBindings(msg) : Dict(U64, List(Element.Event(msg)))

KeyBindings(msg) : List([
    KeyPressed(U64, msg),
    KeyDown(U64, msg),
    KeyUp(U64, msg),
])

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

        init! = { config, run!: |_host| Ok({ model: init(), layout: Layout.new(), renderer, hovered: [] }) }
        render! = |state, host| {

            var $layout = state.layout.clear()
            var $mouse_bindings = Dict.empty()
            var $key_bindings = []

            for element_op in view(state.model) {
                (node_index, node_status) = match element_op {
                    OpenBox(_, _events) => {
                        next_index = $layout.next_node_index()
                        next_status = get_box_status(next_index, state.hovered, host)
                        (next_index, next_status)
                    }
                    _ => (0, default_box_status)
                }

                # update layout
                $layout = $layout.update!(element_op, node_status, state.renderer).map_err(|_e| Exit(1))?

                ## bind events
                match element_op {
                    OpenBox(_, events) => {
                        ($mouse_bindings, $key_bindings) = collect_event_bindings($mouse_bindings, $key_bindings, node_index, events)
                    }
                    _ => {}
                }
            }

            # solve layout
            $layout = $layout.solve!(screen).map_err(|_e| Exit(1))?

            # event handling
            var $model = state.model
            { messages, hovered } = handle_events($layout, $mouse_bindings, $key_bindings, host, state.hovered).map_err(|_e| Exit(1))?
            for message in messages {
                $model = update($model, message)
            }

            # render layout
            commands = $layout.to_commands(screen).map_err(|_e| Exit(1))?
            Render.render!(state.renderer, commands)

            Ok({ model: $model, layout: $layout, renderer: state.renderer, hovered })
        }
        { init!, render! }
    }
}

default_box_status : Element.BoxStatus
default_box_status = { hovered: Bool.False, pressed: Bool.False, focused: Bool.False, disabled: Bool.False }

get_box_status : U64, List(U64), HostState(host) -> Element.BoxStatus
get_box_status = |node_index, prev_hovered, host| {
    hovered = prev_hovered.contains(node_index)
    { hovered, pressed: hovered and host.mouse.left, focused: Bool.False, disabled: Bool.False }
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

get_node_events : MouseBindings(msg), U64 -> List(Element.Event(msg))
get_node_events = |bindings, node_index| {
    match bindings.get(node_index) {
        Ok(events) => events
        Err(_) => []
    }
}

get_mouse_events : List(Element.Event(msg)) -> List(Element.Event(msg))
get_mouse_events = |events| {
    events.fold([], |mouse_events, event| {
        match event {
            OnHover(_) => mouse_events.append(event)
            OnHoverWith(_) => mouse_events.append(event)
            OnMouseEnter(_) => mouse_events.append(event)
            OnMouseLeave(_) => mouse_events.append(event)
            OnClick(_) => mouse_events.append(event)
            _ => mouse_events
        }
    })
}

get_key_bindings : List(Element.Event(msg)) -> KeyBindings(msg)
get_key_bindings = |events| {
    events.fold([], |key_bindings, event| {
        match event {
            OnKeyPressed(key, msg) => key_bindings.append(KeyPressed(key, msg))
            OnKeyDown(key, msg) => key_bindings.append(KeyDown(key, msg))
            OnKeyUp(key, msg) => key_bindings.append(KeyUp(key, msg))
            _ => key_bindings
        }
    })
}

collect_event_bindings : MouseBindings(msg), KeyBindings(msg), U64, List(Element.Event(msg)) -> (MouseBindings(msg), KeyBindings(msg))
collect_event_bindings = |mouse_bindings, key_bindings, node_index, events| {
    mouse_events = get_mouse_events(events)
    mouse_bindings2 = if mouse_events.len() > 0 {
        mouse_bindings.insert(node_index, mouse_events)
    } else {
        mouse_bindings
    }

    key_events = get_key_bindings(events)
    key_bindings2 = if key_events.len() > 0 {
        key_bindings.concat(key_events)
    } else {
        key_bindings
    }

    (mouse_bindings2, key_bindings2)
}


handle_events : Layout(draw), MouseBindings(msg), KeyBindings(msg), HostState(host), List(U64) -> Try({ messages : List(msg), hovered : List(U64) }, Layout.LayoutError)
handle_events = |layout, mouse_bindings, key_bindings, host, prev_hovered| {
    pointer = { x: host.mouse.x, y: host.mouse.y }
    mouse_event = { x: host.mouse.x, y: host.mouse.y, left: host.mouse.left, middle: host.mouse.middle, right: host.mouse.right, wheel: host.mouse.wheel }
    hovered = layout.hover_path(pointer)?
    # OnMouseEnter/OnMouseLeave/OnHover
    var $msgs = get_mouse_enter_events(mouse_bindings, prev_hovered, hovered)
    $msgs = $msgs.concat(get_mouse_leave_events(mouse_bindings, prev_hovered, hovered))
    $msgs = $msgs.concat(get_hover_events(mouse_bindings, hovered, mouse_event))

    # OnClick
    mouse_left_button = 0
    if is_mouse_button_pressed(host.mouse.buttons_pressed, mouse_left_button) and hovered.len() > 0 {
        node_index = hovered.get(0)?
        $msgs = $msgs.concat(get_click_events(mouse_bindings, node_index))
    }

    # Key events
    $msgs = $msgs.concat(get_key_events(key_bindings, host.keys_pressed, host.keys, host.keys_released))

    Ok({ messages: $msgs, hovered })
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

get_mouse_enter_events : MouseBindings(msg), List(U64), List(U64) -> List(msg)
get_mouse_enter_events = |bindings, prev_hovered, next_hovered| {
    next_hovered.fold([], |msgs, node_index| {
        if list_contains_u64(prev_hovered, node_index) {
            msgs
        } else {
            msgs.concat(
                get_node_events(bindings, node_index).fold([], |node_msgs, event| {
                    match event {
                        OnMouseEnter(msg) => node_msgs.append(msg)
                        _ => node_msgs
                    }
                }),
            )
        }
    })
}

get_mouse_leave_events : MouseBindings(msg), List(U64), List(U64) -> List(msg)
get_mouse_leave_events = |bindings, prev_hovered, next_hovered| {
    prev_hovered.fold([], |msgs, node_index| {
        if list_contains_u64(next_hovered, node_index) {
            msgs
        } else {
            msgs.concat(
                get_node_events(bindings, node_index).fold([], |node_msgs, event| {
                    match event {
                        OnMouseLeave(msg) => node_msgs.append(msg)
                        _ => node_msgs
                    }
                }),
            )
        }
    })
}

get_hover_events : MouseBindings(msg), List(U64), Element.MouseEvent -> List(msg)
get_hover_events = |bindings, hovered, mouse_event| {
    hovered.fold([], |msgs, node_index| {
        msgs.concat(
            get_node_events(bindings, node_index).fold([], |node_msgs, event| {
                match event {
                    OnHover(msg) => node_msgs.append(msg)
                    OnHoverWith(callback) => node_msgs.append((Box.unbox(callback))(mouse_event))
                    _ => node_msgs
                }
            }),
        )
    })
}

get_click_events : MouseBindings(msg), U64 -> List(msg)
get_click_events = |bindings, node_index| {
    get_node_events(bindings, node_index).fold([], |msgs, event| {
        match event {
            OnClick(msg) => msgs.append(msg)
            _ => msgs
        }
    })
}

get_key_events : KeyBindings(msg), List(U8), List(U8), List(U8) -> List(msg)
get_key_events = |bindings, keys_pressed, keys_down, keys_released| {
    # NOTE: This currently dispatches to every matching key binding. Once
    # focus exists, key events should dispatch only to the focused node/path.
    bindings.fold([], |msgs, binding| {
        match binding {
            KeyPressed(key, msg) => if is_key_pressed(keys_pressed, key) {
                msgs.append(msg)
            } else {
                msgs
            }
            KeyDown(key, msg) => if is_key_pressed(keys_down, key) {
                msgs.append(msg)
            } else {
                msgs
            }
            KeyUp(key, msg) => if is_key_pressed(keys_released, key) {
                msgs.append(msg)
            } else {
                msgs
            }
        }
    })
}
