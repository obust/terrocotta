## Screwbot-styled widget building blocks: cards, key/value readouts, labeled
## slider controls, and preset buttons shared by the header and sidebar.
import tc.Color
import tc.Element exposing [box, style, text]
import tc.Program exposing [View]
import tc.Theme
import tc.Widget

import tc.Palette as BuiltinPalette
import ../scene/Drawing exposing [decimal]

Utils := [].{

	# Keep dynamic children separate from the model-capturing card style. Combining
	# those in one helper currently triggers roc-lang/roc#10560 during codegen.
	content_stack : List(View(msg)) -> View(msg)
	content_stack = |children| box(
		{
			style: |_|
				style
					.width(Grow({ min: 0, max: 10000 }))
					.height(Fit({ min: 0, max: 10000 }))
					.gap(10)
					.direction(Col)
					.child_align({ x: Start, y: Start }),
		},
		children,
	)

	card : Str, View(msg) -> View(msg)
	card = |title, content| {
		title_view = box(
			{
				style: |_|
					style
						.width(Grow({ min: 0, max: 10000 }))
						.height(Fit({ min: 0, max: 10000 }))
						.border({ color: BuiltinPalette.atom_dark.text.with_alpha(55).with_alpha(210), left: 0, right: 0, top: 0, bottom: 1 })
						.pad(0, 0, 8, 0)
						.gap(8)
						.direction(Row)
						.child_align({ x: Start, y: Center })
						.font_color(BuiltinPalette.atom_dark.primary)
						.font_size(14)
						.spacing(2),
			},
			[
				box({ style: |_| style.width(Fixed(3)).height(Fixed(13)).background(BuiltinPalette.atom_dark.primary).radius(2) }, []),
				text(title),
			],
		)

		box(
			{
				style: |_|
					style
						.width(Grow({ min: 0, max: 10000 }))
						.height(Fit({ min: 0, max: 10000 }))
						.background(BuiltinPalette.atom_dark.background)
						.radius(12)
						.border({ color: BuiltinPalette.atom_dark.text.with_alpha(55), left: 1, right: 1, top: 1, bottom: 1 })
						.pad(12, 14, 12, 14)
						.gap(10)
						.direction(Col)
						.child_align({ x: Start, y: Start })
						.font_size(16)
						.font_color(BuiltinPalette.atom_dark.text),
			},
			[title_view, content],
		)
	}

	readout : Str, Str, Color -> View(msg)
	readout = |name, value, color| box(
		{
			style: |_|
				style
					.width(Grow({ min: 0, max: 10000 }))
					.height(Fit({ min: 0, max: 10000 }))
					.gap(6)
					.direction(Row)
					.child_align({ x: Start, y: Center }),
		},
		[
			box(
				{ style: |_| style.width(Fit({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).font_size(13).font_color(BuiltinPalette.atom_dark.text.with_alpha(170)).text_align(Left) },
				[text(name)],
			),
			box(
				{ style: |_| style.width(Grow({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).font_size(14).font_color(color).text_align(Right) },
				[text(value)],
			),
		],
	)

	control : Theme, Str, F32, F32, F32, F32, (F32 -> msg) -> View(msg)
	control = |theme, name, value, min, max, step, on_change| box(
		{
			style: |_|
				style
					.width(Grow({ min: 0, max: 10000 }))
					.height(Fit({ min: 0, max: 10000 }))
					.gap(7)
					.direction(Col)
					.child_align({ x: Start, y: Start }),
		},
		[
			Utils.readout(name, decimal(value), BuiltinPalette.atom_dark.text),
			Widget.slider(theme, value, min, max, step, on_change),
		],
	)

	coefficient_readout : Str, Str, Color -> View(msg)
	coefficient_readout = |basis, values, color| box(
		{
			style: |_|
				style
					.width(Grow({ min: 0, max: 10000 }))
					.height(Fit({ min: 0, max: 10000 }))
					.direction(Col)
					.gap(2)
					.child_align({ x: Start, y: Start }),
		},
		[
			box(
				{ style: |_| style.width(Grow({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).child_align({ x: Start, y: Center }).font_size(12).font_color(BuiltinPalette.atom_dark.text.with_alpha(170)).text_align(Left) },
				[text(basis)],
			),
			box(
				{ style: |_| style.width(Grow({ min: 0, max: 10000 })).height(Fit({ min: 0, max: 10000 })).child_align({ x: End, y: Center }).font_size(14).font_color(color).text_align(Right) },
				[text(values)],
			),
		],
	)

	preset_button : Bool, Str, msg -> View(msg)
	preset_button = |accent, label, msg| box(
		{
			style: |status| {
				base_fill = if accent {
					BuiltinPalette.atom_dark.primary.with_alpha(225)
				} else {
					BuiltinPalette.atom_dark.background.lighten(8)
				}
				fill = if status.pressed {
					base_fill.darken(20)
				} else if status.hovered {
					base_fill.lighten(12)
				} else {
					base_fill
				}
				style
					.width(Fit({ min: 0, max: 10000 }))
					.height(Fixed(30))
					.background(fill)
					.border({ color: if accent BuiltinPalette.atom_dark.primary else 0x2b3c5c.Color, left: 1, right: 1, top: 1, bottom: 1 })
					.radius(6)
					.pad(4, 10, 4, 10)
					.font_size(13)
					.font_color(if accent BuiltinPalette.atom_dark.background.darken(8) else BuiltinPalette.atom_dark.text)
					.spacing(1)
					.child_align({ x: Center, y: Center })
			},
			events: [OnClick(msg)],
		},
		[text(label)],
	)
}
