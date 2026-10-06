## Shared semantic color roles and text styling helpers for themed widgets.
import ../Color
import ../Element exposing [style]
import ../Theme

Shared := [].{

	## Semantic widget color variants.
	Variant : [Primary, Secondary, Success, Warning, Danger]

	## A fill/content pair used by themed widgets.
	Pair : {
		fill : Color,
		content : Color,
	}

	## Return the palette pair for a semantic variant.
	role_pair : Theme, Variant -> Pair
	role_pair = |theme, variant| {
		match variant {
			Primary => theme.palette.primary.base
			Secondary => theme.palette.surface.inverse
			Success => theme.palette.success.base
			Warning => theme.palette.warning.base
			Danger => theme.palette.danger.base
		}
	}

	## Base text style shared by themed text widgets.
	text_style : Theme, F32, Pair -> Element.BoxConfig
	text_style = |_theme, size, colors| {
		style
			.font_size(size)
			.font_color(colors.content)
	}
}
