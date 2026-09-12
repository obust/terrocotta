## Model-owned checkbox widget.
import ../Element exposing [View, box, text, style]
import ../Theme

Checkbox :: [].{

	## Display a model-owned checkbox with a text label.
	checkbox : Theme, Bool, Str, (Bool -> msg) -> View(msg, payload)
	checkbox = |theme, checked, content, on_change| {
		box_size = theme.font_size
		next_checked = if checked {
			False
		} else {
			True
		}
		indicator_colors = if checked {
			theme.palette.primary.base
		} else {
			theme.palette.background.weak
		}

		box(
			{
				style: |status| {
					var $box_style = style
						.width(Fit({}))
						.height(Fit({}))
						.font_size(theme.font_size)
						.font_color(theme.palette.background.base.content)
						.direction(Row)
						.gap(theme.gap / 2)
						.child_align({ x: Start, y: Center })

					if status.pressed {
						$box_style.background(theme.palette.background.weak.fill.deviate(44))
					} else if status.hovered {
						$box_style.background(theme.palette.background.weak.fill.deviate(24))
					} else {
						$box_style
					}
				},
				events: [OnClick(on_change(next_checked))],
			},
			[
				box(
					{
						style: |status| {
							indicator_fill = if status.pressed {
								indicator_colors.fill.deviate(44)
							} else if status.hovered {
								indicator_colors.fill.deviate(24)
							} else {
								indicator_colors.fill
							}

							style
								.width(Fixed(box_size))
								.height(Fixed(box_size))
								.background(indicator_fill)
								.radius(100)
								.border({ color: theme.palette.primary.base.fill, left: 2, right: 2, top: 2, bottom: 2 })
						},
					},
					[],
				),
				text(content),
			],
		)
	}
}

expect {
	view = Checkbox.checkbox(Theme.dark, True, "Enabled", |checked| checked)

	match view.collect() {
		[OpenBox(Auto, _, [OnClick(False)]), OpenBox(Auto, _, []), CloseBox, Text("Enabled"), CloseBox] => True
		_ => False
	}
}