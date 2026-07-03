## Elm Architecture runtime for roc-clay.
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


EventBinding(msg) : {
    node_index : U64,
    event : Element.Event(msg),
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

    State(draw, model, msg) : {
        model : model,
        layout : Layout.Layout(draw),
        renderer : Render.Renderer,
        pending_events : List(msg),
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

        init! = { config, run!: |_host| Ok({ model: init(), layout: Layout.new(), renderer, pending_events: [], hovered: [] }) }
        render! = |state, host| {
            var $model = state.model
            for msg in state.pending_events {
                $model = update($model, msg)
            }

            var $layout = state.layout.clear()
            var $event_bindings = []
            for msg in view($model) {
                event_list = match msg {
                    OpenBox(_, open_events) => open_events
                    _ => []
                }

                # update layout
                $layout = $layout.update!(msg, state.renderer).map_err(|_e| Exit(1))?

                # bind events
                for event in event_list {
                    $event_bindings = $event_bindings.append(
                        {
                            node_index: $layout.current_node_index().map_err(|_e| Exit(1))?,
                            event,
                        },
                    )
                }
            }

            solved = $layout.solve!(screen).map_err(|_e| Exit(1))?
            commands = solved.to_commands(screen).map_err(|_e| Exit(1))?
            Render.render!(state.renderer, commands)
            event_result = handle_events(solved, $event_bindings, host, state.hovered).map_err(|_e| Exit(1))?

            Ok({ model: $model, layout: $layout, renderer: state.renderer, pending_events: event_result.messages, hovered: event_result.hovered })
        }
        { init!, render! }
    }
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

get_node_events : List(EventBinding(msg)), U64 -> List(Element.Event(msg))
get_node_events = |bindings, node_index| {
    bindings.iter().keep_if(|binding| binding.node_index == node_index).map(|binding| binding.event).collect()
}


handle_events : Layout(draw), List(EventBinding(msg)), HostState(host), List(U64) -> Try({ messages : List(msg), hovered : List(U64) }, Layout.LayoutError)
handle_events = |layout, bindings, host, previous_hovered| {
    pointer = { x: host.mouse.x, y: host.mouse.y }
    mouse_event = { x: host.mouse.x, y: host.mouse.y, left: host.mouse.left, middle: host.mouse.middle, right: host.mouse.right, wheel: host.mouse.wheel }
    hovered = layout.hover_path(pointer)?

    # OnMouseEnter/OnMouseLeave/OnHover
    var $msgs = get_mouse_enter_events(bindings, previous_hovered, hovered)
    $msgs = $msgs.concat(get_mouse_leave_events(bindings, previous_hovered, hovered))
    $msgs = $msgs.concat(get_hover_events(bindings, hovered, mouse_event))

    # OnClick
    mouse_left_button = 0
    if is_mouse_button_pressed(host.mouse.buttons_pressed, mouse_left_button) and hovered.len() > 0 {
        node_index = hovered.get(0)?
        $msgs = $msgs.concat(get_click_events(bindings, node_index))
    }

    # Key events
    $msgs = $msgs.concat(get_key_events(bindings, host.keys_pressed, host.keys, host.keys_released))

    Ok({ messages: $msgs, hovered: hovered })
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

get_mouse_enter_events : List(EventBinding(msg)), List(U64), List(U64) -> List(msg)
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

get_mouse_leave_events : List(EventBinding(msg)), List(U64), List(U64) -> List(msg)
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

get_hover_events : List(EventBinding(msg)), List(U64), Element.MouseEvent -> List(msg)
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

get_click_events : List(EventBinding(msg)), U64 -> List(msg)
get_click_events = |bindings, node_index| {
    get_node_events(bindings, node_index).fold([], |msgs, event| {
        match event {
            OnClick(msg) => msgs.append(msg)
            _ => msgs
        }
    })
}

get_key_events : List(EventBinding(msg)), List(U8), List(U8), List(U8) -> List(msg)
get_key_events = |bindings, keys_pressed, keys_down, keys_released| {
    # NOTE: This currently dispatches to every matching key binding. Once
    # focus exists, key events should dispatch only to the focused node/path.
    bindings.fold([], |msgs, binding| {
        match binding.event {
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
    })
}
