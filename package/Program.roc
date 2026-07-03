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

    State(draw, model) : {
        model : model,
        layout : Layout(draw),
        renderer : Render(draw),
    }

    new! : {
        config : Config,
        init : () -> m,
        view : m -> Element.View,
        update : m, msg -> m,
        subscriptions : m, host -> List(msg),
    } -> {
        init! : {
            config : Config,
            run! : host => Try(State(draw, m), [Exit(I64)]),
        },
        render! : State(draw, m), host => Try(State(draw, m), [Exit(I64), ..]),
    }
    new! = |cfg| {
        { init, view, update, subscriptions, config } = cfg

        screen = { w: config.width.to_f32(), h: config.height.to_f32() }

        init! = { config, run!: |_host| Ok({ model: init(), layout: Layout.new(), renderer: {} }) }
        render! = |state, host| {
            var $model = state.model
            for msg in subscriptions($model, host) {
                $model = update($model, msg)
            }

            var $layout = state.layout.clear()
            for msg in view($model) {
                $layout = $layout.update!(msg).map_err(|_e| Exit(1))?
            }

            solved = $layout.solve!(screen).map_err(|_e| Exit(1))?
            commands = solved.to_commands(screen).map_err(|_e| Exit(1))?
            state.renderer.render!(commands)

            Ok({ model: $model, layout: $layout, renderer: state.renderer })
        }
        { init!, render! }
    }
}
