## Theme-aware static widgets built on Element.
import Color
import Element exposing [View, box, text, style]
import Theme

Widget := [].{

	## Semantic widget color variants.
	Variant : [Primary, Secondary, Success, Warning, Danger]

	## Display body text using the theme background content color.
	label : Theme, Str -> View
	label = |theme, content| {
		box(
			text_style(theme, theme.font_size, theme.palette.background.base),
			[
				text(content),
			],
		)
	}

	## Display larger heading text using the theme primary color.
	heading : Theme, Str -> View
	heading = |theme, content| {
		box(
			text_style(theme, theme.font_size * 1.5, theme.palette.primary.strong),
			[
				text(content),
			],
		)
	}

	## Lay out children horizontally with the theme gap.
	row : Theme, List(View) -> View
	row = |theme, children| {
		box(style.direction(Row).gap(theme.gap), children)
	}

	## Lay out children vertically with the theme gap.
	column : Theme, List(View) -> View
	column = |theme, children| {
		box(style.direction(Col).gap(theme.gap), children)
	}

	## Group children on a weak background surface.
	panel : Theme, List(View) -> View
	panel = |theme, children| {
		colors = theme.palette.background.weak

		box(
			style
				.background(colors.fill)
				.font_family(theme.font)
				.font_size(theme.font_size)
				.font_color(colors.content)
				.radius(theme.radius)
				.pad((theme.gap, theme.gap, theme.gap, theme.gap))
				.gap(theme.gap)
				.direction(Col),
			children,
		)
	}

	## Display a non-interactive button-shaped command label.
	button : Theme, Variant, Str -> View
	button = |theme, variant, content| {
		colors = role_pair(theme, variant)

		box(
			style
				.background(colors.fill)
				.font_family(theme.font)
				.font_size(theme.font_size)
				.font_color(colors.content)
				.radius(theme.radius)
				.pad((theme.gap, theme.gap, theme.gap / 2, theme.gap / 2)),
			[
				text(content),
			],
		)
	}

	## Display a compact semantic label.
	badge : Theme, Variant, Str -> View
	badge = |theme, variant, content| {
		colors = role_pair(theme, variant)

		box(
			style
				.background(colors.fill)
				.font_family(theme.font)
				.font_size(theme.font_size * 0.85)
				.font_color(colors.content)
				.radius(theme.radius)
				.pad((theme.gap / 2, theme.gap / 2, theme.gap / 4, theme.gap / 4)),
			[
				text(content),
			],
		)
	}

	## Display a semantic message block.
	alert : Theme, Variant, Str -> View
	alert = |theme, variant, content| {
		colors = role_pair(theme, variant)

		box(
			style
				.background(colors.fill)
				.font_family(theme.font)
				.font_size(theme.font_size)
				.font_color(colors.content)
				.radius(theme.radius)
				.pad((theme.gap, theme.gap, theme.gap, theme.gap)),
			[
				text(content),
			],
		)
	}
}

expect {
	view = Widget.button(Theme.dark, Primary, "Save")

	match view.collect() {
		[OpenBox(_), Text("Save"), CloseBox] => Bool.True
		_ => Bool.False
	}
}

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
		Secondary => theme.palette.background.strong
		Success => theme.palette.success.base
		Warning => theme.palette.warning.base
		Danger => theme.palette.danger.base
	}
}

## Base text style shared by themed text widgets.
text_style : Theme, F32, Pair -> Element.BoxConfig
text_style = |theme, size, colors| {
	style
		.font_family(theme.font)
		.font_size(size)
		.font_color(colors.content)
}
