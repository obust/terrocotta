## Minimal floating-root demonstration.
app [Model, program] {
	rr: platform "../../roc-ray/platform/main-default.roc",
	tc: "../package/main.roc",
}

import rr.Host
import rr.Draw

import tc.Color
import tc.Element exposing [box, text, View, style, default_floating_config]
import tc.Program
import tc.Theme

theme = Theme.light

Model : Program.State(Draw, {}, Msg)

Msg : []

init! : Program.Config => Try({}, [Exit(I64)])
init! = |_config| Ok({})

update : {}, Msg -> {}
update = |model, _msg| model

view : {} -> View(Msg)
view = |_model| {
	box(
		Id("page"),
		|_| style
			.direction(Col)
			.child_align({ x: Start, y: Start })
			.pad((theme.gap, theme.gap, theme.gap, theme.gap))
			.background(theme.palette.background.base.fill)
			.font_family(theme.font)
			.font_size(theme.font_size)
			.font_color(theme.palette.background.base.content),
		[],
		[
			text("This text remains in normal layout."),
			box(
				Id("floating-card"),
				|_| style
					.width(Fixed(280))
					.height(Fit({ min: 0, max: 10000 }))
					.pad((theme.gap, theme.gap, theme.gap, theme.gap))
					.background(theme.palette.primary.base.fill)
					.font_color(theme.palette.primary.base.content)
					.radius(theme.radius)
						.floating(Floating({
							target: Root,
							config: {
								..default_floating_config,
								z_index: 100,
								attach_points: { element: Center, target: Center },
							},
						})),
				[],
				[text("I am a centered floating root.")],
			),
		],
	)
}

program : {
	init! : { config : Program.Config, run! : Host => Try(Model, [Exit(I64)]) },
	render! : Model, Host => Try(Model, [Exit(I64), ..]),
}
program = Program.new!({
	config: { ..Program.default, title: "Floating Root", width: 720, height: 520 },
	init!,
	view,
	update,
})
