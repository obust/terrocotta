## Minimal floating-root demonstration.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst",
	tc: "../package/main.roc",
}

import rr.App

import tc.Element exposing [box, text, style, default_floating_config]
import tc.Widget exposing [column, row, button]
import tc.Program exposing [View]
import tc.Theme

theme = Theme.light

Model : Program.State(AppModel, Msg)

AppModel : { attach : Element.AttachPoint }

Msg : Element.AttachPoint

update! : AppModel, Msg, App.Io, App.Input(Msg) => AppModel
update! = |model, msg, _io, _input| {
	{ ..model, attach: msg }
}

view : AppModel -> View(Msg)
view = |model| {
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
			text("Attachment points:"),
			column(
				theme,
				[
					row(
						theme,
						[
							button(theme, Secondary, False, "LeftTop", [OnClick(LeftTop)]),
							button(theme, Secondary, False, "CenterTop", [OnClick(CenterTop)]),
							button(theme, Secondary, False, "RightTop", [OnClick(RightTop)]),
						],
					),
					row(
						theme,
						[
							button(theme, Secondary, False, "LeftCenter", [OnClick(LeftCenter)]),
							button(theme, Secondary, False, "Center", [OnClick(Center)]),
							button(theme, Secondary, False, "RightCenter", [OnClick(RightCenter)]),
						],
					),
					row(
						theme,
						[
							button(theme, Secondary, False, "LeftBottom", [OnClick(LeftBottom)]),
							button(theme, Secondary, False, "CenterBottom", [OnClick(CenterBottom)]),
							button(theme, Secondary, False, "RightBottom", [OnClick(RightBottom)]),
						],
					),
				],
			),
			text("Container:"),
			box(
				{
					id: Id("floating-container"),
					style: |_| style
					# .width(Grow({}))
					# .height(Grow({}))
						.font_size(theme.font_size)
						.border({ color: theme.palette.primary.base.fill, top: 2, left: 2, right: 2, bottom: 2 })
						.radius(theme.radius),
				},
				[
					box(
						{
							id: Id("floating-card"),
							style: |_| style
								.width(Fit({}))
								.height(Fit({}))
								.pad(theme.gap, theme.gap, theme.gap, theme.gap)
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
						},
						[text("floating")],
					),
				],
			),
		],
	)
}

configure : List(Str) -> App.Config
configure = |_args| App.default.with_title("Floating Root").with_size({ width: 720, height: 520 })

init! : App.InitCallback(AppModel, [])
init! = |_startup| Ok({ attach: Center })

program = Program.new(configure, init!, update!, view)
