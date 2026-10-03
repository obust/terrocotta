## Themed command button widget.
import ../Element exposing [View, box, text, style]
import ../Event
import ../Theme
import Shared
import rr.Mouse

Button :: [].{

	## Display a button-shaped command label with hover, press, and focus styling.
	button : Theme, [Primary, Secondary, Success, Warning, Danger], Str, List(Event.Handler(msg)) -> View(msg, payload)
	button = |theme, variant, content, events| {
		colors = Shared.role_pair(theme, variant)

		box(
			{
				style: |status| {
					var $box_style = style
						.width(Fit({}))
						.height(Fit({}))
						.background(colors.fill)
						.font_size(theme.font_size)
						.font_color(colors.content)
						.radius(theme.radius)
						.pad(theme.gap / 2, theme.gap, theme.gap / 2, theme.gap)
						.child_align({ x: Center, y: Center })
						.cursor(PointingHand)

					$box_style = if status.focused {
						$box_style.border({ color: theme.palette.primary.strong.fill, left: 1, right: 1, top: 1, bottom: 1 })
					} else {
						$box_style
					}

					if status.pressed {
						$box_style.background(colors.fill.deviate(44))
					} else if status.hovered {
						$box_style.background(colors.fill.deviate(24))
					} else {
						$box_style
					}
				},
				events: events,
			},
			[
				text(content),
			],
		)
	}
}

expect {
	view = Button.button(Theme.dark, Primary, "Save", [])

	match view.collect() {
		[OpenBox(Auto, _, []), Text("Save"), CloseBox] => True
		_ => False
	}
}
