## Model-owned toggle switch widget.
import ../Element exposing [View, box, style]
import ../Theme

Toggle :: [].{

	## Display a model-owned toggle switch.
	toggle : Theme, Bool, (Bool -> msg) -> View(msg, payload)
	toggle = |theme, checked, on_change| {
		track_size = theme.font_size
		knob_size = theme.font_size
		next_checked = if checked {
			False
		} else {
			True
		}
		track_colors = if checked {
			theme.palette.primary.base
		} else {
			theme.palette.background.weak
		}

		box(
			{
				style: |status| {
					var $box_style = style
						.width(Fixed(track_size * 2))
						.height(Fixed(track_size))
						.background(track_colors.fill)
						.radius(100)

					$box_style = if status.focused {
						$box_style.border({ color: theme.palette.primary.strong.fill, left: 1, right: 1, top: 1, bottom: 1 })
					} else {
						$box_style
					}

					if status.pressed {
						$box_style.background(track_colors.fill.deviate(44))
					} else if status.hovered {
						$box_style.background(track_colors.fill.deviate(24))
					} else {
						$box_style
					}
				},
				events: [OnClick(on_change(next_checked))],
			},
			[
				box(
					{
						style: |_| {
							target = if checked {
								RightCenter
							} else {
								LeftCenter
							}
							inset = knob_size / 2
							offset = if checked {
								{ x: -inset, y: 0 }
							} else {
								{ x: inset, y: 0 }
							}

							style
								.width(Fixed(knob_size))
								.height(Fixed(knob_size))
								.background(theme.palette.background.base.fill)
								.radius(100)
								.border({ color: theme.palette.primary.strong.fill, left: 1, right: 1, top: 1, bottom: 1 })
								.floating(
									Floating({
										target: Parent,
										config: {
											..Element.default_floating_config,
											z_index: 100,
											attach_points: { element: Center, target },
											offset,
											capture: Passthrough,
										},
									}),
								)
						},
						events: [OnClick(on_change(next_checked))],
					},
					[],
				),
			],
		)
	}
}

expect {
	view = Toggle.toggle(Theme.dark, True, |v| v)

	match view.collect() {
		[OpenBox(Auto, _, [OnClick(False)]), OpenBox(Auto, _, [OnClick(False)]), CloseBox, CloseBox] => True
		_ => False
	}
}