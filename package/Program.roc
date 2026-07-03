## Elm Architecture runtime for roc-clay.
## Wires init, view, update, subscriptions into the platform's { init!, render! } contract.
##
## Usage:
##   program = Program.new!({ config, init, view, update: update!, subscriptions })
import Layout
import Render
import Element
import Color

HostState(host) : {
    keys_pressed : List(U8),
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
    }

    new! : {
        config : Config,
        renderer : Render.Renderer,
        init : () -> m,
        view : m -> Element.View(msg),
        update : m, msg -> m,
        subscriptions : m, HostState(host) -> List(msg),
    } -> {
        init! : {
            config : Config,
            run! : HostState(host) => Try(State(draw, m, msg), [Exit(I64)]),
        },
        render! : State(draw, m, msg), HostState(host) => Try(State(draw, m, msg), [Exit(I64), ..]),
    }
    new! = |cfg| {
        { init, view, update, subscriptions, config, renderer } = cfg

        screen = { w: config.width.to_f32(), h: config.height.to_f32() }

        init! = { config, run!: |_host| Ok({ model: init(), layout: Layout.new(), renderer, pending_events: [] }) }
        render! = |state, host| {
            var $model = state.model
            for msg in state.pending_events {
                $model = update($model, msg)
            }

            for msg in subscriptions($model, host) {
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
            pending_events = handle_events(solved, $event_bindings, host).map_err(|_e| Exit(1))?

            Ok({ model: $model, layout: $layout, renderer: state.renderer, pending_events })
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

get_node_events : List(EventBinding(msg)), U64 -> List(Element.Event(msg))
get_node_events = |bindings, node_index| {
    bindings.iter().keep_if(|binding| binding.node_index == node_index).map(|binding| binding.event).collect()
}


handle_events : Layout(draw), List(EventBinding(msg)), HostState(host) -> Try(List(msg), Layout.LayoutError)
handle_events = |layout, bindings, host| {
    var $msgs = []

    if is_mouse_button_pressed(host.mouse.buttons_pressed, 0) {
        pointer = { x: host.mouse.x, y: host.mouse.y }
        $msgs = $msgs.concat(get_click_events(layout, bindings, pointer)?)
    }

    Ok($msgs)
}


get_click_events : Layout(draw), List(EventBinding(msg)), { x: F32, y: F32 } -> Try(List(msg), Layout.LayoutError)
get_click_events = |layout, bindings, pointer| {
    match layout.hit_test(pointer)? {
        Hit(node_index) => {
            Ok(get_node_events(bindings, node_index).fold(
                [],
                |msgs, event| {
                    match event {
                        OnClick(msg) => msgs.append(msg)
                    }
                },
            ))
        }
        NoHit => Ok([])
    }
}
