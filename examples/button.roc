## Button example with status-dependent styling.
app [Model, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.7/8gdZaHEpySPZUzMBCT6RkEF9CBpcbi5F3E7QmNu4NTCU.tar.zst",
	tc: "../package/main.roc",
}

import rr.Host
import rr.Draw

import tc.Color
import tc.Element exposing [box, text, View, style, default_font]
import tc.Program

theme = {
	base: { fill: Color.from_hex_rgb(0xf4f6f8), content: Color.from_hex_rgb(0x1f2933) },
	primary: {
		fill: Color.from_hex_rgb(0x2563eb),
		hover: Color.from_hex_rgb(0x1d4ed8),
		pressed: Color.from_hex_rgb(0x1e40af),
		focused: Color.from_hex_rgb(0xF54927),
		content: Color.white,
	},
	font_family: default_font,
	font_size: 24,
	gap: 18,
	radius: 12,
}

Model : Program.State(Draw, AppModel, Msg)

AppModel : {}

Msg : [Increment]

init! : Program.Config => Try(AppModel, [Exit(I64)])
init! = |_config| Ok({})

update : AppModel, Msg -> AppModel
update = |model, _msg| model

button : Str -> View(Msg)
button = |label| {
	box(
		Auto,
		|status| {
			var $box_style = style
				.width(Fit({ min: 0, max: 10000 }))
				.height(Fit({ min: 0, max: 10000 }))
				.pad((theme.gap, theme.gap, theme.gap, theme.gap))
				.child_align({ x: Center, y: Center })
				.direction(Row)
				.background(theme.primary.fill)
				.radius(theme.radius)
				.font_family(theme.font_family)
				.font_size(theme.font_size)
				.font_color(theme.primary.content)

			$box_style = if status.focused {
				$box_style.border({ color: theme.primary.focused, left: 1, right: 1, top: 1, bottom: 1 })
			} else {
				$box_style
			}

			if status.pressed {
				$box_style.background(theme.primary.pressed)
			} else if status.hovered {
				$box_style.background(theme.primary.hover)
			} else {
				$box_style
			}
		},
		[],
		[
			text(label),
		],
	)
}

view : AppModel -> View(Msg)
view = |_model| {
	box(
		Auto,
		|_| style.background(theme.base.fill),
		[],
		[
			button("hover and click me"),
		],
	)
}

program : {
	init! : { config : Program.Config, run! : Host => Try(Model, [Exit(I64)]) },
	render! : Model, Host => Try(Model, [Exit(I64), ..]),
}
program = Program.new!(
	{
		config: { ..Program.default, title: "Button Status Example", width: 640, height: 420 },
		init!,
		view,
		update,
	},
)
