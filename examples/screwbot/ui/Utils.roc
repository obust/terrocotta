## Screwbot-styled widget building blocks: cards, key/value readouts, labeled
## slider controls, and preset buttons shared by the header and sidebar.
import tc.Color
import tc.Element exposing [box, style, text]
import tc.Program exposing [View]
import tc.Theme
import tc.Widget

Utils := [].{
	decimal : F32, U64 -> Str
	decimal = |value, digits| {
		match value.to_str().split_on(".") {
			[whole, fractional] => if digits == 0 {
				whole
			} else {
				match Str.from_utf8(fractional.to_utf8().take_first(digits)) {
					Ok(truncated) => "${whole}.${truncated}"
					Err(_) => whole
				}
			}
			[whole] => whole
			_ => value.to_str()
		}
	}

	card : Theme, Str, List(View(msg)) -> View(msg)
	card = |theme, title, children| {
		title_ = box(
			{
				style: |_|
					style
						.height(Fit({}))
						.border({ color: theme.palette.edge.border, left: 0, right: 0, top: 0, bottom: 1 })
						.pad(0, 0, theme.gap, 0)
						.child_align({ x: Start, y: Center })
						.font_color(theme.palette.primary.base.fill)
						.font_size(theme.font_size * 1.1),
			},
			[
				text(title),
			],
		)

		content = box(
			{
				style: |_|
					style
						.height(Fit({}))
						.direction(Col)
						.gap(theme.gap)
						.child_align({ x: Start, y: Start })
						.font_size(14),
			},
			children,
		)

		box(
			{
				style: |_|
					style
						.height(Fit({}))
						.background(theme.palette.surface.base.fill)
						.radius(theme.radius)
						.border({ color: theme.palette.edge.control, left: 1, right: 1, top: 1, bottom: 1 })
						.pad(theme.gap, theme.gap, theme.gap, theme.gap)
						.gap(theme.gap)
						.direction(Col)
						.child_align({ x: Start, y: Start })
						.font_size(16)
						.font_color(theme.palette.surface.base.content),
			},
			[title_, content],
		)
	}

	readout : Theme, Str, Str, Color -> View(msg)
	readout = |theme, name, value, color| box(
		{
			style: |_|
				style
					.height(Fit({}))
					.gap(theme.gap)
					.direction(Row)
					.child_align({ x: Start, y: Center }),
		},
		[
			box(
				{ style: |_| style.width(Fit({})).height(Fit({})).font_size(theme.font_size).font_color(theme.palette.text.muted).child_align({ x: Start, y: Center }) },
				[text(name)],
			),
			box(
				{ style: |_| style.width(Grow({})).height(Fit({})).font_size(theme.font_size).font_color(color).child_align({ x: End, y: Center }) },
				[text(value)],
			),
		],
	)

	control : Theme, Str, F32, F32, F32, F32, (F32 -> msg) -> View(msg)
	control = |theme, name, value, min, max, step, on_change| box(
		{
			style: |_|
				style
					.height(Fit({}))
					.gap(theme.gap)
					.direction(Col)
					.child_align({ x: Start, y: Start }),
		},
		[
			Utils.readout(theme, name, Utils.decimal(value, 0), theme.palette.surface.base.content),
			Widget.slider(theme, value, min, max, step, on_change),
		],
	)

	coefficient_readout : Theme, Str, Str, Color -> View(msg)
	coefficient_readout = |theme, basis, values, color| box(
		{
			style: |_|
				style
					.height(Fit({}))
					.direction(Row)
					.gap(theme.gap)
					.child_align({ x: Start, y: Start }),
		},
		[
			box(
				{ style: |_| style.width(Grow({})).height(Fit({})).child_align({ x: Start, y: Center }).font_size(theme.font_size).font_color(theme.palette.text.muted).text_align(Left) },
				[text(basis)],
			),
			box(
				{ style: |_| style.width(Grow({})).height(Fit({})).child_align({ x: End, y: Center }).font_size(theme.font_size).font_color(color).text_align(Right) },
				[text(values)],
			),
		],
	)

}

expect {
	Utils.decimal(12.349.F32, 2) == "12.34"
		and Utils.decimal(-12.349.F32, 2) == "-12.34"
			and Utils.decimal(12.999.F32, 0) == "12"
}
