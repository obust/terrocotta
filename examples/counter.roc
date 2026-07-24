## Minimal counter with increment and decrement buttons.
app [Model, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.8.0/HXKssyTXxLLu4TStDfgo9uvjnkT5mGJoRqKcvV2khjcw.tar.zst",
	tc: "../package/main.roc",
}

import rr.Host
import rr.Draw

import tc.Color
import tc.Element exposing [box, text, View, style, default_font]
import tc.Program

theme = Theme.dark

Model : Program.State(Draw, AppModel, Msg)

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

button : Str, Msg -> View(Msg)
button = |label, click_msg| {
	box(
		Auto,
		|_| style
			.width(Fit({ min: theme.font_size, max: 10000 }))
			.pad((theme.gap, theme.gap, theme.gap, theme.gap))
			.background(theme.palette.primary.base.fill)
			.radius(theme.radius)
			.font_size(theme.font_size)
			.font_color(theme.palette.primary.base.content),
		[OnClick(click_msg)],
		[
			text(label),
		],
	)
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
		[],
		[
			box(
				Auto,
				|_| style
					.height(Fit({ min: 0, max: 10000 }))
					.gap(theme.gap)
					.direction(Row),
				[],
				[
					button("-", Decrement),
					text("Count: ${model.count.to_str()}"),
					button("+", Increment),
				],
			),
		],
	)
}

program : {
	init! : { config : Program.Config, run! : Host => Try(Model, [Exit(I64)]) },
	render! : Model, Host => Try(Model, [Exit(I64), ..]),
}
program = Program.new!(
	{
		config: { ..Program.default, title: "Counter Example", width: 640, height: 420 },
		init!,
		view,
		update,
	},
)
