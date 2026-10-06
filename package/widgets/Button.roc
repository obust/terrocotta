## Themed command button widget.
import ../Element exposing [View, box, text, style]
import ../Event
import ../Color
import ../Theme
import rr.Mouse

Button :: [].{

	## Display a button-shaped command label with hover, press, and focus styling.
	button : Theme, [Primary, Secondary], Bool, Str, List(Event.Handler(msg)) -> View(msg, payload)
	button = |theme, variant, disabled, content, events| {
		base_colors = match variant {
			Primary => theme.palette.primary.base
			Secondary => theme.palette.surface.subtle
		}
		colors = if disabled {
			{
				fill: Color.composite_over(theme.palette.disabled_content(base_colors.content), base_colors.fill),
				content: base_colors.content,
			}
		} else {
			base_colors
		}
		content_color = if disabled theme.palette.disabled_content(colors.content) else colors.content

		box(
			{
				style: |status| {
					var $box_style = style
						.width(Fit({}))
						.height(Fit({}))
						.background(colors.fill)
						.font_size(theme.font_size)
						.font_color(content_color)
						.radius(theme.radius)
						.pad(theme.gap / 2, theme.gap, theme.gap / 2, theme.gap)
						.child_align({ x: Center, y: Center })
						.border({ color: theme.palette.edge.control, left: 1, right: 1, top: 1, bottom: 1 })
						.cursor(if disabled NotAllowed else PointingHand)

					$box_style = if status.focused {
					$box_style.border({ color: theme.palette.edge.focus, left: 1, right: 1, top: 1, bottom: 1 })
					} else {
						$box_style
					}

					if disabled {
						$box_style
					} else if status.pressed {
						$box_style.background(theme.palette.pressed(colors).fill)
					} else if status.hovered {
						$box_style.background(theme.palette.hovered(colors).fill)
					} else {
						$box_style
					}
				},
				events: if disabled [] else events,
			},
			[
				text(content),
			],
		)
	}
}

expect {
	view = Button.button(Theme.dark, Primary, False, "Save", [])

	match view.collect() {
		[OpenBox(Auto, _, []), Text("Save"), CloseBox] => True
		_ => False
	}
}
