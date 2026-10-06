## Tailwind-inspired navigation primitives for tutorial lessons.
import tc.Element exposing [box, style, text]
import tc.Event
import tc.Program exposing [View]
import tc.Theme

LessonNav := [].{
	section : Theme, Str, List(View(msg)) -> View(msg)
	section = |theme, label, children| box(
		{ style: |_| style.width(Grow({})).height(Fit({})).direction(Col).gap(4).pad(0, 0, theme.gap, 0).child_align({ x: Start, y: Start }) },
		[
			box(
				{ style: |_| style.width(Grow({})).height(Fit({})).font_size(11).spacing(1.5).font_color(theme.palette.text.muted).child_align({ x: Start, y: Start }) },
				[text(label)],
			),
			box(
				{ style: |_| style.width(Grow({})).height(Fit({})).direction(Col).gap(2).child_align({ x: Start, y: Start }) },
				children,
			),
		],
	)

	item : Theme, Bool, Bool, Str, List(Event.Handler(msg)) -> View(msg)
	item = |theme, active, enabled, label, events| {
		color = if active {
			theme.palette.surface.base.content
		} else if enabled {
			theme.palette.surface.base.content
		} else {
			theme.palette.text.muted
		}
		box(
			{
				style: |status| {
					base = style.width(Grow({})).height(Fit({})).pad(6, 8, 6, 16).font_color(color).background(
						if active {
							theme.palette.primary.weak.fill
						} else {
							theme.palette.surface.base.fill
						},
					).radius(4).child_align({ x: Start, y: Center })
					if enabled and status.hovered {
						base.background(theme.palette.surface.subtle.fill)
					} else {
						base
					}
				},
				events: if enabled {
					events
				} else {
					[]
				},
			},
			[text(label)],
		)
	}
}
