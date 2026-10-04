## Compact semantic label widget.
import ../Element exposing [View, box, text, style]
import ../Theme
import Shared

Badge :: [].{

	## Display a compact semantic label.
	badge : Theme, [Primary, Secondary, Success, Warning, Danger], Str -> View(msg, payload)
	badge = |theme, variant, content| {
		colors = Shared.role_pair(theme, variant)

		box(
			{
				style: |_| style
					.width(Fit({}))
					.height(Fit({}))
					.background(colors.fill)
					.font_size(theme.font_size * 0.85)
					.font_color(colors.content)
					.radius(theme.radius)
					.pad(theme.gap / 4, theme.gap / 2, theme.gap / 4, theme.gap / 2),
			},
			[
				text(content),
			],
		)
	}
}
