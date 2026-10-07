## Entry point for the interactive Terrocotta tutorial.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst",
	tc: "../../package/main.roc",
}

import rr.App as RayApp
import tc.Element exposing [box, style]
import tc.Program

import App
import ui/Controls
import ui/Guide
import ui/Nav

Model : Program.State(App.Model, App.Msg)

Msg : App.Msg

configure : List(Str) -> RayApp.Config
configure = |_args|
	RayApp.default
		.with_title("Terrocotta Tutorial")
		.with_size({ width: 1280, height: 800 })
		.with_resizable(True)
		.with_permission(Directory("examples/assets", ReadOnly))
		.with_default_font({ path: "examples/assets/Inter-Regular.ttf", size: 36 })

view : App.Model -> Program.View(App.Msg)
view = |model| box(
	{
		style: |_| style
			.direction(Row)
			.background(App.theme.palette.surface.base.fill)
			.font_size(App.theme.font_size)
			.font_color(App.theme.palette.surface.base.content),
	},
	[Nav.view(model), Guide.view(model), Controls.view(model)],
)

program = Program.new(configure, App.init!, App.update, view)
