## Larger heading text widget.
import ../Element exposing [View, box, text]
import ../Theme
import Shared

Heading :: [].{

	## Display larger heading text using the theme primary color.
	heading : Theme, Str -> View(msg, payload)
	heading = |theme, content| {
		box(
			{
				style: |_| Shared.text_style(theme, theme.font_size * 1.5, theme.palette.primary.strong)
					.width(Fit({}))
					.height(Fit({})),
			},
			[
				text(content),
			],
		)
	}
}
