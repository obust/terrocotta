## Minimal counter with increment and decrement buttons.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0-rc5/8x22d4JXTKSiPvj3Bd3br2u7rEL3baUzEvmSBrCBDvqV.tar.zst",
	tc: "../package/main.roc",
	roc: "nightly-2026-09-07-14d9829",
}

import rr.App
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

program = Program.new(configure, init!, update, view)
