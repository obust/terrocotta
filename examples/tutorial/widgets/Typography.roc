## Reusable tutorial typography widgets.
import tc.Element exposing [box, style, text]
import tc.Program exposing [View]
import tc.Theme

Typography := [].{
	title : Theme, Str -> View(msg)
	title = |theme, content| box(
		{ style: |_| style.width(Grow({})).height(Fit({})).font_size(24).font_color(theme.palette.primary.base.fill).child_align({ x: Start, y: Start }) },
		[text(content)],
	)

	heading : Theme, Str -> View(msg)
	heading = |theme, content| box(
		{ style: |_| style.width(Grow({})).height(Fit({})).font_size(20).font_color(theme.palette.primary.base.fill).child_align({ x: Start, y: Start }) },
		[text(content)],
	)

	p : Str -> View(msg)
	p = |content| box(
		{ style: |_| style.width(Grow({})).height(Fit({})).text_wrap(Words).child_align({ x: Start, y: Start }) },
		[text(content)],
	)
}
