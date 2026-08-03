## Scrollable list demonstration.
app [Model, program] {
    rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.8.3/E6ZmC6ZncTVFG875Xsf6jP2GuZCtLnncQ1YwVwKtT2J4.tar.zst",
    tc: "../package/main.roc",
}

import rr.Host
import rr.Draw

import tc.Element exposing [box, text, View, style]
import tc.Program
import tc.Theme

theme = Theme.light

Model : Program.State(Draw, {}, Msg)

Msg : []

init! : Program.Config => Try({}, [Exit(I64)])
init! = |_config| Ok({})

update : {}, Msg -> {}
update = |model, _msg| model

row : U64 -> View(Msg)
row = |index| {
	box(
		IdI("scroll-row", index),
		|_| style
			.height(Fit({ min: 0, max: 10000 }))
			.pad((theme.gap, theme.gap, theme.gap, theme.gap))
			.child_align({ x: Start, y: Center })
			.background(theme.palette.background.weak.fill)
		[],
		[text("Scrollable row ${index.to_str()}")],
	)
}

view : {} -> View(Msg)
view = |_model| {
	rows = (1..<20).map(row).collect()
	box(
		Id("page"),
		|_| style
			.direction(Col)
			.child_align({ x: Start, y: Start })
			.pad((theme.gap, theme.gap, theme.gap, theme.gap))
			.gap(theme.gap)
			.background(theme.palette.background.base.fill)
			.font_family(theme.font)
			.font_size(theme.font_size)
			.font_color(theme.palette.background.base.content),
		[],
		[
			text("Move the pointer over the panel and use the mouse wheel."),
			box(
				Id("scroll-container"),
				|_| style
					.direction(Col)
					.child_align({ x: Start, y: Start })
					.gap(theme.gap)
					.pad((theme.gap, theme.gap, theme.gap, theme.gap))
					.border({ color: theme.palette.primary.base.fill, left: 2, right: 2, top: 2, bottom: 2 })
					.radius(theme.radius)
					.overflow(Hidden, Scroll),
				[],
				rows,
			),
		],
	)
}

program : {
	init! : { config : Program.Config, run! : Host => Try(Model, [Exit(I64)]) },
	render! : Model, Host => Try(Model, [Exit(I64), ..]),
}
program = Program.new!({
	config: { ..Program.default, title: "Scrollable Container", width: 720, height: 520 },
	init!,
	view,
	update,
})
