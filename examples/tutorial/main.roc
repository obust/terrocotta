## Entry point for the interactive Terrocotta tutorial.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst",
	tc: "../../package/main.roc",
}

import rr.App
import rr.Assets
import tc.Element exposing [box, style]
import tc.Program

import Tutorial
import pages/Image
import ui/Controls
import ui/Guide
import ui/Nav

Model : Program.State(Tutorial.AppModel, Tutorial.Msg)

Msg : Tutorial.Msg

configure : List(Str) -> App.Config
configure = |_args|
	App.default
		.with_title("Terrocotta Tutorial")
		.with_size({ width: 1280, height: 800 })
		.with_resizable(True)
		.with_permission(Directory("examples/assets", ReadOnly))
		.with_default_font({ path: "examples/assets/Inter-Regular.ttf", size: 36 })

init! : App.InitCallback(Tutorial.AppModel, _)
init! = |startup| {
	assets = Assets.open!(startup.files().open_dir_read!("examples/assets")?, IgnoreManifest)?
	image = Image.init!(assets)?
	Ok(Tutorial.initial(image))
}

view : Tutorial.AppModel -> Program.View(Tutorial.Msg)
view = |model| box(
	{
		style: |_| style
			.direction(Row)
			.background(Tutorial.theme.palette.surface.base.fill)
			.font_size(Tutorial.theme.font_size)
			.font_color(Tutorial.theme.palette.surface.base.content),
	},
	[Nav.view(model), Guide.view(model), Controls.view(model)],
)

program = Program.new(configure, init!, Tutorial.update, view)
