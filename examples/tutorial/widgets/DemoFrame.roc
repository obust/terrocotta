## A neutral frame that separates a lesson's live example from its guide text.
import tc.Element exposing [box, style]
import tc.Program exposing [View]
import tc.Theme

DemoFrame := [].{
	view : Theme, List(View(msg)) -> View(msg)
	view = |theme, children| box(
		{
			style: |_| style
				.width(Grow({}))
				.height(Fixed(260))
				.direction(Col)
				.pad(16, 16, 16, 16)
				.child_align({ x: Center, y: Center })
				.background(theme.palette.surface.subtle.fill)
				.border({ color: theme.palette.edge.border, left: 1, right: 1, top: 1, bottom: 1 })
				.radius(theme.radius)
				.overflow(Hidden, Hidden),
		},
		children,
	)
}
