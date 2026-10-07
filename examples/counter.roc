## Minimal counter with increment and decrement buttons.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst",
	tc: "../package/main.roc",
}

import rr.App
import rr.Capture
# import rr.Keys

import tc.Element exposing [box, text, style]
import tc.Program exposing [View]
import tc.Theme
import tc.Widget exposing [button]

theme = Theme.dark

Model : Program.State(AppModel, Msg)

AppModel : {
	count : I32,
}

Msg : [
	Decrement,
	Increment,
]

configure : List(Str) -> App.Config
configure = |args| {
	App.default
	    .with_title("Counter Example")
		.with_size({ width: 320, height: 210 })
	    .with_output_dir("captures")
}

init! : App.InitCallback(AppModel, [])
init! = |io| {
	Ok({ count: 0 })
}

update! : AppModel, Msg, App.Io, App.Input(Msg) => AppModel
update! = |model, msg, _io, _input| {
	match msg {
		Decrement => { ..model, count: model.count - 1 }
		Increment => { ..model, count: model.count + 1 }
	}
}

view : AppModel -> View(Msg)
view = |model| {
	box(
		{
			style: |_| style
				.direction(Col)
				.background(theme.palette.surface.base.fill)
				.font_size(theme.font_size)
				.font_color(theme.palette.surface.base.content),
		},
		[
			box(
				{
					style: |_| style
						.height(Fit({}))
						.gap(theme.gap)
						.direction(Row),
				},
				[
					button(theme, Primary, False, "-", [OnClick(Decrement)]),
					text("Count: ${model.count.to_str()}"),
					button(theme, Primary, False, "+", [OnClick(Increment)]),
				],
			),
		],
	)
}

program = Program.new(configure, init!, update!, view)
