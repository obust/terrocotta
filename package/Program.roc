## Elm Architecture runtime for roc-clay.
## Wires init, view, update, subscriptions into the platform's { init!, render! } contract.
##
## Usage:
##   program = Program.new!({ config, init, view, update: update!, subscriptions })
import Layout
import Render
import Element
import Color

ConfigRaw : {
    title : Str,
    width : I32,
    height : I32,
    target_fps : I32,
    resizable : Bool,
    fullscreen : Bool,
    vsync : Bool,
    cursor_visible : Bool,
}

Program := [].{

    Config : ConfigRaw

    MouseState(mouse) : {
        x : F32,
        y : F32,
        buttons_pressed : List(U8),
        ..mouse
    }

    State(draw, model, msg) : {
        model : model,
        layout : Layout.Layout(draw),
        renderer : Render.Renderer,
        pending_events : List(msg),
    }

    EventBinding(msg) : {
        node_index : U64,
        events : List(Element.Event(msg)),
    }

    new! : {
        config : Config,
        renderer : Render.Renderer,
        init : () -> m,
        view : m -> Element.View(msg),
        update : m, msg -> m,
        subscriptions : m, { mouse : MouseState(mouse), ..host } -> List(msg),
    } -> {
        init! : {
            config : Config,
            run! : { mouse : MouseState(mouse), ..host } => Try(State(draw, m, msg), [Exit(I64)]),
        },
        render! : State(draw, m, msg), { mouse : MouseState(mouse), ..host } => Try(State(draw, m, msg), [Exit(I64), ..]),
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
                match msg {
                    OpenBox(_box_cfg, events) => {
                        if events.len() > 0 {
                            $event_bindings = $event_bindings.append(
                                {
                                    node_index: $layout.next_node_index(),
                                    events,
                                },
                            )
                        }
                    }
                    _ => {}
                }
                $layout = $layout.update!(msg, state.renderer).map_err(|_e| Exit(1))?
            }

            solved = $layout.solve!(screen).map_err(|_e| Exit(1))?
            commands = solved.to_commands(screen).map_err(|_e| Exit(1))?
            Render.render!(state.renderer, commands)
            pending_events = click_events(solved, $event_bindings, host.mouse).map_err(|_e| Exit(1))?

            Ok({ model: $model, layout: $layout, renderer: state.renderer, pending_events })
        }
        { init!, render! }
    }
}

mouse_button_pressed : List(U8), U64 -> Bool
mouse_button_pressed = |states, button|
    match states.get(button) {
        Ok(state) => state == 1
        Err(_) => Bool.False
    }

events_for_node : List(Program.EventBinding(msg)), U64 -> List(Element.Event(msg))
events_for_node = |bindings, node_index| {
    var $events = []
    for binding in bindings {
        if binding.node_index == node_index {
            $events = binding.events
        }
    }
    $events
}

click_messages : List(Element.Event(msg)) -> List(msg)
click_messages = |events| {
    var $messages = []
    for event in events {
        match event {
            OnClick(msg) => {
                $messages = $messages.append(msg)
            }
        }
    }
    $messages
}

click_events : Layout.Layout(draw), List(Program.EventBinding(msg)), Program.MouseState(mouse) -> Try(List(msg), Layout.LayoutError)
click_events = |layout, bindings, mouse| {
    if mouse_button_pressed(mouse.buttons_pressed, 0) {
        match layout.hit_test({ x: mouse.x, y: mouse.y })? {
            Hit(node_index) => Ok(click_messages(events_for_node(bindings, node_index)))
            NoHit => Ok([])
        }
    } else {
        Ok([])
    }
}
