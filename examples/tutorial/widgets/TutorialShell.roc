## Reusable tutorial shell and control-section widgets.
import tc.Element exposing [ElementId.*, box, style]
import tc.Program exposing [View]
import tc.Theme

TutorialShell := [].{
	controls_shell : Theme, F32, List(View(msg)) -> View(msg)
	controls_shell = |theme, width, children| box(
		{
			style: |_| style
				.width(Fixed(width))
				.direction(Col)
				.gap(theme.gap)
				.pad(16, 16, 16, 16)
				.child_align({ x: Start, y: Start })
				.background(theme.palette.surface.subtle.fill)
				.border({ color: theme.palette.edge.border, left: 1, right: 0, top: 0, bottom: 0 })
				.overflow(Hidden, Scroll),
		},
		children,
	)

	controls_section : Theme, ElementId, List(View(msg)) -> View(msg)
	controls_section = |theme, id, children| box(
		{
			id,
			style: |_| style
				.width(Grow({}))
				.height(Fit({}))
				.direction(Col)
				.gap(theme.gap / 2)
				.pad(theme.gap, theme.gap, theme.gap, theme.gap)
				.child_align({ x: Start, y: Start })
				.background(theme.palette.surface.base.fill)
				.radius(theme.radius),
		},
		children,
	)
}
