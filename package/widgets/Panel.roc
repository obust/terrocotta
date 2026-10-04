## Group children on a weak background surface.
import ../Element exposing [View, box, style]
import ../Theme

Panel :: [].{

	## Group children on a weak background surface.
	panel : Theme, List(View(msg, payload)) -> View(msg, payload)
	panel = |theme, children| {
		colors = theme.palette.background.weak

		box(
			{
				style: |_| style
					.width(Fit({}))
					.height(Fit({}))
					.background(colors.fill)
					.font_size(theme.font_size)
					.font_color(colors.content)
					.radius(theme.radius)
					.pad(theme.gap, theme.gap, theme.gap, theme.gap)
					.gap(theme.gap)
					.direction(Col)
					.child_align({ x: Start, y: Start }),
			},
			children,
		)
	}
}
