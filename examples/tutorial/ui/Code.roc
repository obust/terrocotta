## Tutorial-local code presentation.
import tc.Color
import tc.Element exposing [box, style, text]
import tc.Program exposing [View]
import tc.Theme

Code := [].{
	code_preview : Theme, List(View(msg)) -> View(msg)
	code_preview = |theme, children| box(
		{
			style: |_| style
				.width(Grow({}))
				.height(Fixed(260))
				.direction(Col)
				.pad(theme.gap * 2, theme.gap, theme.gap * 2, theme.gap)
				.child_align({ x: Center, y: Center })
				# .background(theme.palette.surface.subtle.fill)
				.background(theme.palette.surface.base.fill.darken(40))
				.radius(theme.radius)
				.overflow(Hidden, Hidden),
		},
		children,
	)

	## Present a Roc snippet without attempting syntax highlighting.
	code_block : Theme, Str -> View(msg)
	code_block = |theme, source| box(
		{
			style: |_| style
				.width(Grow({}))
				.height(Fit({}))
				.pad(theme.gap, theme.gap, theme.gap, theme.gap)
				.background(theme.palette.surface.inverse.fill)
				.font_color(theme.palette.surface.inverse.content)
				.text_wrap(Words)
				.radius(theme.radius)
				.child_align({ x: Start, y: Start }),
		},
		[text(source)],
	)

	## Render a compact inline code token, similar to Markdown backticks.
	code_text : Theme, Str -> View(msg)
	code_text = |theme, content| box(
		{
			style: |_| style
				.width(Fit({}))
				.height(Fit({}))
				.pad(theme.gap / 4, theme.gap / 2, theme.gap / 4, theme.gap / 2)
				.background(theme.palette.surface.inverse.fill)
				.font_color(theme.palette.surface.inverse.content)
				.text_wrap(None)
				.child_align({ x: Start, y: Center })
				.radius(theme.radius),
		},
		[text(content)],
	)

}
