## Static body-text label widget.
import ../Element exposing [View, box, text]
import ../Theme
import Shared

Label :: [].{

	## Display body text using the theme background content color.
	label : Theme, Str -> View(msg, payload)
	label = |theme, content| {
		box(
			{
				style: |_| Shared.text_style(theme, theme.font_size, theme.palette.surface.base)
					.width(Fit({}))
					.height(Fit({})),
			},
			[
				text(content),
			],
		)
	}
}
