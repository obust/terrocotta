## Reusable tutorial typography widgets.
import tc.Element exposing [box, style, text]
import tc.Program exposing [View]
import tc.Theme

Typography := [].{
	title : Theme, Str -> View(msg)
	title = |theme, content| box(
		{ style: |_| style.width(Grow({})).height(Fit({})).font_size(theme.font_size * 3).font_color(theme.palette.primary.base.fill).child_align({ x: Start, y: Start }) },
		[text(content)],
	)

	heading : Theme, Str -> View(msg)
	heading = |theme, content| box(
		{ style: |_| style
		    .width(Fit({}))
			.height(Fit({}))
			.font_size(theme.font_size * 1.8)
			.font_color(theme.palette.primary.base.fill)
			.pad(0, 0, theme.gap, 0)
			.border({ color: theme.palette.primary.base.fill, top: 0, right: 0, bottom: 4, left: 0}) },
		[text(content)],
	)

	p : Str -> View(msg)
	p = |content| box(
		{ style: |_| style.width(Grow({})).height(Fit({})).text_wrap(Words).child_align({ x: Start, y: Start }) },
		[text(content)],
	)
}
