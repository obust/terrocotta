## Scrollable list demonstration.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst",
	tc: "../package/main.roc",
}

import rr.App

import tc.Element exposing [box, text, style]
import tc.Program exposing [View]
import tc.Theme

theme = Theme.light

Model : Program.State({}, Msg)

Msg : []

update : {}, Msg -> {}
update = |model, _msg| model

row : U64 -> View(Msg)
row = |index| {
	box(
		{
			id: IdI("scroll-row", index),
			style: |_| style
				.height(Fit({}))
				.pad(theme.gap, theme.gap, theme.gap, theme.gap)
				.child_align({ x: Start, y: Center })
				.background(theme.palette.surface.subtle.fill),
		},
		[text("Scrollable row ${index.to_str()}")],
	)
}

view : {} -> View(Msg)
view = |_model| {
	var $rows = []
	for index in 1..<20 {
		$rows = $rows.append(row(index))
	}
	rows = (1..<20).iter().map(row).collect()
	box(
		{
			id: Id("page"),
			style: |_| style
				.direction(Col)
				.child_align({ x: Start, y: Start })
				.pad(theme.gap, theme.gap, theme.gap, theme.gap)
				.gap(theme.gap)
				.background(theme.palette.surface.base.fill)
				.font_size(theme.font_size)
				.font_color(theme.palette.surface.base.content),
		},
		[
			text("Move the pointer over the panel and use the mouse wheel."),
			box(
				{
					id: Id("scroll-container"),
					style: |_| style
						.direction(Col)
						.child_align({ x: Start, y: Start })
						.gap(theme.gap)
						.pad(theme.gap, theme.gap, theme.gap, theme.gap)
						.border({ color: theme.palette.primary.base.fill, left: 2, right: 2, top: 2, bottom: 2 })
						.radius(theme.radius)
						.overflow(Hidden, Scroll),
				},
				rows,
			),
		],
	)
}

configure : List(Str) -> App.Config
configure = |_args| App.default.with_title("Scrollable Container").with_size({ width: 720, height: 520 })

init! : App.InitCallback({}, [])
init! = |_startup| Ok({})

program = Program.new(configure, init!, update, view)
