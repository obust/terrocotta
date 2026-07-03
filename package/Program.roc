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
        layout : Layout.Layout(draw, msg),
        renderer : Render.Renderer,
        pending_events : List(msg),
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
            for msg in view($model) {
                $layout = $layout.update!(msg, state.renderer).map_err(|_e| Exit(1))?
            }

            solved = $layout.solve!(screen).map_err(|_e| Exit(1))?
            commands = solved.to_commands(screen).map_err(|_e| Exit(1))?
            Render.render!(state.renderer, commands)
            pending_events = solved.click_events(host.mouse).map_err(|_e| Exit(1))?

            Ok({ model: $model, layout: $layout, renderer: state.renderer, pending_events })
        }
        { init!, render! }
    }
}
