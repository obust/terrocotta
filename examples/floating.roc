## Minimal floating-root demonstration.
app [Model, program] {
    rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.8.3/E6ZmC6ZncTVFG875Xsf6jP2GuZCtLnncQ1YwVwKtT2J4.tar.zst",
	tc: "../package/main.roc",
}

import rr.Host
import rr.Draw

import tc.Color
import tc.Element exposing [box, text, View, style, default_floating_config]
import tc.Widget exposing [column, row, button]
import tc.Program
import tc.Theme

theme = Theme.light

Model : Program.State(Draw, AppModel, Msg)

AppModel : { attach : Element.AttachPoint }

Msg : Element.AttachPoint

init! : Program.Config => Try(AppModel, [Exit(I64)])
init! = |_config| Ok({ attach: Center })

update : AppModel, Msg -> AppModel
update = |model, msg| {
	{ ..model, attach: msg }
}


view : AppModel -> View(Msg)
view = |model| {
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
			text("Attachment points:"),
			column(
				theme,
				[
					row(
						theme,
						[
							button(theme, Secondary, "LeftTop", [OnClick(LeftTop)]),
							button(theme, Secondary, "CenterTop", [OnClick(CenterTop)]),
							button(theme, Secondary, "RightTop", [OnClick(RightTop)]),
						],
					),
					row(
						theme,
						[
							button(theme, Secondary, "LeftCenter", [OnClick(LeftCenter)]),
							button(theme, Secondary, "Center", [OnClick(Center)]),
							button(theme, Secondary, "RightCenter", [OnClick(RightCenter)]),
						],
					),
					row(
						theme,
						[
							button(theme, Secondary, "LeftBottom", [OnClick(LeftBottom)]),
							button(theme, Secondary, "CenterBottom", [OnClick(CenterBottom)]),
							button(theme, Secondary, "RightBottom", [OnClick(RightBottom)]),
						],
					),
				],
			),
			text("Container:"),
			box(
				Id("floating-container"),
				|_| style
				# .width(Grow({min: 0, max: 10000}))
				# .height(Grow({min: 0, max: 10000}))
					.font_size(theme.font_size)
					.border({ color: theme.palette.primary.base.fill, top: 2, left: 2, right: 2, bottom: 2})
					.radius(theme.radius),
				[],
				[
					box(
						Id("floating-card"),
						|_| style
							.width(Fit({ min: 0, max: 10000 }))
							.height(Fit({ min: 0, max: 10000 }))
							.pad((theme.gap, theme.gap, theme.gap, theme.gap))
							.background(theme.palette.primary.base.fill)
							.font_color(theme.palette.primary.base.content)
							.font_size(theme.font_size)
							.radius(theme.radius)
							.floating(
								Floating({
									target: Parent,
									config: {
										..default_floating_config,
										z_index: 100,
										attach_points: { element: model.attach, target: model.attach },
									},
								}),
							),
						[],
						[text("floating")],
					),
				],
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
