## Vertical layout widget.
import ../Element exposing [View, box, style]
import ../Theme

Column :: [].{

	## Lay out children vertically with the theme gap.
	column : Theme, List(View(msg, payload)) -> View(msg, payload)
	column = |theme, children| {
		box(
			{
				style: |_| style
					.width(Fit({}))
					.height(Fit({}))
					.direction(Col)
					.gap(theme.gap)
					.child_align({ x: Start, y: Start }),
			},
			children,
		)
	}
}