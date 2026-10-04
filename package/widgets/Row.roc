## Horizontal layout widget.
import ../Element exposing [View, box, style]
import ../Theme

Row :: [].{

	## Lay out children horizontally with the theme gap.
	row : Theme, List(View(msg, payload)) -> View(msg, payload)
	row = |theme, children| {
		box(
			{
				style: |_| style
					.width(Fit({}))
					.height(Fit({}))
					.direction(Row)
					.gap(theme.gap)
					.child_align({ x: Start, y: Start }),
			},
			children,
		)
	}
}
