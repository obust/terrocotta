## Minimal counter with increment and decrement buttons.
app [Model, program] {
    rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.8.3/E6ZmC6ZncTVFG875Xsf6jP2GuZCtLnncQ1YwVwKtT2J4.tar.zst",
    tc: "../package/main.roc",
}

import rr.Host
import rr.Draw

import tc.Color
import tc.Element exposing [box, text, View, style, default_font]
import tc.Program
import tc.Theme
import tc.Widget exposing [button]

theme = Theme.dark

Model : Program.State(Draw, Host, AppModel, Msg)

AppModel : {
	count : I32,
}

Msg : [
	Decrement,
	Increment,
]

init! : Program.Config => Try(AppModel, [Exit(I64)])
init! = |_config| Ok({ count: 0 })

update : AppModel, Msg -> AppModel
update = |model, msg| match msg {
	Decrement => { ..model, count: model.count - 1 }
	Increment => { ..model, count: model.count + 1 }
}

view : AppModel -> View(Msg)
view = |model| {
	box(
		Auto,
		|_| style
			.direction(Col)
			.background(theme.palette.background.base.fill)
			.font_family(theme.font)
			.font_size(theme.font_size)
			.font_color(theme.palette.background.base.content),
		[
			OnKeyPressed(Keys.key_code(KeyUp), Increment),
			OnKeyPressed(Keys.key_code(KeyDown), Decrement),
		],
		[
			box(
				Auto,
				|_| style
					.height(Fit({ min: 0, max: 10000 }))
					.gap(theme.gap)
					.direction(Row),
				[],
				[
					button(theme, Primary, "-", [OnClick(Decrement)]),
					text("Count: ${model.count.to_str()}"),
					button(theme, Primary, "+", [OnClick(Increment)]),
				],
			),
		],
	)
}

program = Program.new!(
	{
		config: { ..Program.default, title: "Counter Example", width: 640, height: 420 },
		init!,
		view,
		update,
	},
)
