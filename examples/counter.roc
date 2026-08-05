## Minimal counter with increment and decrement buttons.
app [Model, program] {
	rr: platform "../../roc-ray/platform/main.roc",
	tc: "../package/main.roc",
}

import rr.App
import rr.Host
import rr.Draw

import tc.Color
import tc.Element exposing [box, text, View, style, default_font]
import tc.Program
import tc.Theme
import tc.Widget exposing [button]

import RocRayApp
import RocRayRenderer

theme = Theme.dark

Model : Program.FrameState(AppModel, Msg, Draw.Frame)

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
					button(theme, Primary, "-", [OnClick(Decrement)]),
					text("Count: ${model.count.to_str()}"),
					button(theme, Primary, "+", [OnClick(Increment)]),
				],
			),
		],
	)
}

config : Program.Config
config = { ..Program.default, title: "Counter Example", width: 640, height: 420 }

tc_program = Program.new_frame!({
	config,
	renderer: RocRayRenderer.default,
	init!,
	view,
	update,
})

program = {
	init!: App.init(RocRayApp.config(config), |host| (tc_program.init!.run!)(host)),
	render!: |model, host, frame| (tc_program.render!)(model, host, frame),
}
