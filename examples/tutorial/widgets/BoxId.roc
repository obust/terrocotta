## A centered diagnostic label for tutorial example boxes.
import tc.Color
import tc.Element exposing [box, default_floating_config, style, text]
import tc.Program exposing [View]

BoxId := [].{
	## Overlay a box's stable ID above its top-left corner in the matching border color.
	view : Color, Str -> View(msg)
	view = |color, id| box(
		{
			style: |_| style
				.width(Fit({}))
				.height(Fit({}))
				.font_size(11)
				.font_color(color)
				.floating(
					Floating({
						target: Parent,
						config: {
							..default_floating_config,
							z_index: 100,
							attach_points: { element: LeftBottom, target: LeftTop },
							capture: Passthrough,
						},
					}),
				),
		},
		[text(id)],
	)
}
