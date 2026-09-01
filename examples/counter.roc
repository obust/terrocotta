## Minimal counter with increment and decrement buttons.
app [Model, Msg, program] {
	rr: platform "../../roc-ray/platform/main.roc",
	tc: "../package/main.roc",
	roc: "nightly-2026-08-31-86e69b4",
}

import rr.App
# import rr.Keys

import tc.Element exposing [box, text, View, style]
import tc.Program
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
configure = |_args| App.default.with_title("Counter Example").with_size({ width: 640, height: 420 })

init! : App.InitCallback(AppModel, [])
init! = |_startup| Ok({ count: 0 })

update : AppModel, Msg -> AppModel
update = |model, msg| match msg {
	Decrement => { ..model, count: model.count - 1 }
	Increment => { ..model, count: model.count + 1 }
}

view : AppModel -> View(Msg)
view = |model| {
	box(
		{
			style: |_| style
				.direction(Col)
				.background(theme.palette.background.base.fill)
				.font_size(theme.font_size)
				.font_color(theme.palette.background.base.content),
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
					button(theme, Primary, "-", [OnClick(Decrement)]),
					text("Count: ${model.count.to_str()}"),
					button(theme, Primary, "+", [OnClick(Increment)]),
				],
			),
		],
	)
}

program = Program.new(App.effects(), configure, init!, update, view)
