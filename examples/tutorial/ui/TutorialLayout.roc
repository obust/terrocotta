## Reusable tutorial shell and control-section widgets.
import tc.Color
import tc.Element exposing [box, style]
import tc.Program exposing [View]
import tc.Theme

TutorialLayout := [].{
	page_layout : Theme, List(View(msg)), List(View(msg)) -> View(msg)
	page_layout = |theme, guide, controls| box(
		{ style: |_| style.direction(Row) },
		[
		    # guide
			box(
				{ style: |_| style.width(Grow({ min: 420 })).direction(Col).pad(theme.gap * 4, theme.gap * 4, theme.gap * 4, theme.gap * 4).child_align({ x: Center, y: Start }).overflow(Hidden, Scroll) },
				[
					box(
						{ style: |_| style.width(Grow({ min: 420, max: 672 })).direction(Col).gap(theme.gap).child_align({ x: Start, y: Start }) },
						guide,
					),
				],
			),
			# controls
			box(
				{
					style: |_| style
						.width(Fit({ min: 350 }))
						.direction(Col)
						.gap(theme.gap * 3)
						.pad(theme.gap * 4, theme.gap * 2, theme.gap * 2, theme.gap * 2)
						.child_align({ x: Start, y: Start })
						.background(theme.palette.surface.base.fill.darken(10))
						.border({ color: theme.palette.edge.border, left: 1, right: 0, top: 0, bottom: 0 })
						.overflow(Hidden, Scroll),
				},
				controls,
			)
		],
	)

	control_group : Theme, Color, List(View(msg)) -> View(msg)
	control_group = |theme, color, children| box(
		{
			style: |_| style
				.width(Grow({}))
				.height(Fit({}))
				.direction(Col)
				.gap(theme.gap)
				.pad(theme.gap, theme.gap, theme.gap, theme.gap)
				.child_align({ x: Start, y: Start })
				.background(theme.palette.surface.base.fill.darken(40))
				.border({ color, left: 1, right: 1, top: 1, bottom: 1 })
		},
		children,
	)
}
