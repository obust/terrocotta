## Theme-aware static widgets built on Element.
import Color
import Element exposing [View, box, text, style]
import Theme
import Utils

Widget := [].{

	## Semantic widget color variants.
	Variant : [Primary, Secondary, Success, Warning, Danger]

	## Display body text using the theme background content color.
	label : Theme, Str -> View
	label = |theme, content| {
		box(
			Auto,
			|_| text_style(theme, theme.font_size, theme.palette.background.base)
				.width(Fit({ min: 0, max: 10000 }))
				.height(Fit({ min: 0, max: 10000 })),
			[],
			[
				text(content),
			],
		)
	}

	## Display larger heading text using the theme primary color.
	heading : Theme, Str -> View
	heading = |theme, content| {
		box(
			Auto,
			|_| text_style(theme, theme.font_size * 1.5, theme.palette.primary.strong)
				.width(Fit({ min: 0, max: 10000 }))
				.height(Fit({ min: 0, max: 10000 })),
			[],
			[
				text(content),
			],
		)
	}

	## Lay out children horizontally with the theme gap.
	row : Theme, List(View) -> View
	row = |theme, children| {
		box(
			Auto,
			|_| style
				.width(Fit({ min: 0, max: 10000 }))
				.height(Fit({ min: 0, max: 10000 }))
				.direction(Row)
				.gap(theme.gap)
				.child_align({ x: Start, y: Start }),
			[],
			children,
		)
	}

	## Lay out children vertically with the theme gap.
	column : Theme, List(View) -> View
	column = |theme, children| {
		box(
			Auto,
			|_| style
				.width(Fit({ min: 0, max: 10000 }))
				.height(Fit({ min: 0, max: 10000 }))
				.direction(Col)
				.gap(theme.gap)
				.child_align({ x: Start, y: Start }),
			[],
			children,
		)
	}

	## Group children on a weak background surface.
	panel : Theme, List(View) -> View
	panel = |theme, children| {
		colors = theme.palette.background.weak

		box(
			Auto,
			|_| style
				.width(Fit({ min: 0, max: 10000 }))
				.height(Fit({ min: 0, max: 10000 }))
				.background(colors.fill)
				.font_family(theme.font)
				.font_size(theme.font_size)
				.font_color(colors.content)
				.radius(theme.radius)
				.pad((theme.gap, theme.gap, theme.gap, theme.gap))
				.gap(theme.gap)
				.direction(Col)
				.child_align({ x: Start, y: Start }),
			[],
			children,
		)
	}

	## Display a button-shaped command label with hover, press, and focus styling.
	button : Theme, Variant, Str -> View
	button = |theme, variant, content| {
		colors = role_pair(theme, variant)

		box(
			Auto,
			|status| {
				var $box_style = style
					.width(Fit({ min: 0, max: 10000 }))
					.height(Fit({ min: 0, max: 10000 }))
					.background(colors.fill)
					.font_family(theme.font)
					.font_size(theme.font_size)
					.font_color(colors.content)
					.radius(theme.radius)
					.pad((theme.gap, theme.gap, theme.gap / 2, theme.gap / 2))
					.child_align({ x: Center, y: Center })

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
			[],
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
			Auto,
			|_| style
				.width(Fit({ min: 0, max: 10000 }))
				.height(Fit({ min: 0, max: 10000 }))
				.background(colors.fill)
				.font_family(theme.font)
				.font_size(theme.font_size * 0.85)
				.font_color(colors.content)
				.radius(theme.radius)
				.pad((theme.gap / 2, theme.gap / 2, theme.gap / 4, theme.gap / 4)),
			[],
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
			Auto,
			|_| style
				.width(Fit({ min: 0, max: 10000 }))
				.height(Fit({ min: 0, max: 10000 }))
				.background(colors.fill)
				.font_family(theme.font)
				.font_size(theme.font_size)
				.font_color(colors.content)
				.radius(theme.radius)
				.pad((theme.gap, theme.gap, theme.gap, theme.gap)),
			[],
			[
				text(content),
			],
		)
	}

	## Display a determinate progress bar with progress clamped to 0..1.
	progress_bar : Theme, Variant, F32 -> View
	progress_bar = |theme, variant, progress| {
		track = theme.palette.background.weak
		fill = role_pair(theme, variant)
		clamped_progress = Utils.clamp(progress, 0, 1)

		box(
			Auto,
			|_| style
				.width(Grow({ min: theme.font_size * 6, max: 10000 }))
				.height(Fixed(theme.font_size))
				.background(track.fill)
				.radius(theme.radius)
				.direction(Row)
				.child_align({ x: Start, y: Center }),
			[],
			[
				box(
					Auto,
					|_| style
						.width(Percent(clamped_progress))
						.height(Grow({ min: 0, max: 10000 }))
						.background(fill.fill)
						.radius(theme.radius),
					[],
					[],
				),
			],
		)
	}
}

expect {
	view = Widget.button(Theme.dark, Primary, "Save")

	match view.collect() {
		[OpenBox(Auto, _, []), Text("Save"), CloseBox] => Bool.True
		_ => Bool.False
	}
}

expect {
	view = Widget.progress_bar(Theme.dark, Primary, 0.5)

	match view.collect() {
		[OpenBox(Auto, _, []), OpenBox(Auto, _, []), CloseBox, CloseBox] => Bool.True
		_ => Bool.False
	}
}

expect {
	Utils.clamp(-0.25, 0.0, 1.0) == 0.0 and Utils.clamp(0.5, 0.0, 1.0) == 0.5 and Utils.clamp(1.25, 0.0, 1.0) == 1.0
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
