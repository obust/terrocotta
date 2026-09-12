## Themed modal dialog on a full-screen floating scrim.
import ../Color
import ../Element exposing [View, box, style]
import ../Theme

Modal :: [].{

	## Build a themed, centered dialog on a full-screen floating scrim.
	modal : Theme,
	{
		id : Element.ElementId,
		z_index : I16,
		scrim : Color,
		on_dismiss : [DismissWith(msg), NoDismiss],
	},
	View(msg, payload) -> View(msg, payload)
	modal = |theme, config, content| {
		scrim_events = match config.on_dismiss {
			DismissWith(message) => [OnClick(message)]
			NoDismiss => []
		}
		dialog_colors = theme.palette.background.base

		box(
			{
				id: config.id,
				style: |_| style
					.width(Grow({}))
					.height(Grow({}))
					.background(config.scrim)
					.floating(Floating({ target: Root, config: { ..Element.default_floating_config, z_index: config.z_index, capture: Capture } }))
					.child_align({ x: Center, y: Center }),
				events: scrim_events,
			},
			[
				box(
					{
						id: LocalId("dialog"),
						style: |_| style
							.width(Fit({ min: 0, max: 600 }))
							.height(Fit({}))
							.background(dialog_colors.fill)
							.font_size(theme.font_size)
							.font_color(dialog_colors.content)
							.radius(theme.radius)
							.direction(Col),
					},
					[content],
				),
			],
		)
	}
}