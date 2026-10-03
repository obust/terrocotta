## Model-owned slider widget for numeric values.
import ../Element exposing [View, box, style]
import ../Event
import ../Theme
import ../Utils
import rr.Mouse

Slider :: [].{

	## Display a horizontal slider for model-owned numeric values.
	slider = |theme, value, min, max, step, on_change| {
		track = theme.palette.background.weak
		fill = theme.palette.primary.base
		range = normalize_range(min, max)
		normalized_value = normalize_slider_value(value, min, max, step)
		progress = value_to_progress(normalized_value, range.min, range.max)

		box(
			{
				style: |status| {
					var $box_style = style
						.width(Grow({ min: theme.font_size * 6, max: 10000 }))
						.height(Fixed(theme.font_size // 2))
						.background(track.fill)
						.radius(theme.radius)
						.direction(Row)
						.child_align({ x: Start, y: Center })
						.cursor(ResizeEastWest)

					$box_style = if status.focused {
						$box_style.border({ color: theme.palette.primary.strong.fill, left: 1, right: 1, top: 1, bottom: 1 })
					} else {
						$box_style
					}

					if status.pressed {
						$box_style.background(track.fill.deviate(44))
					} else if status.hovered {
						$box_style.background(track.fill.deviate(24))
					} else {
						$box_style.background(track.fill.deviate(14))
					}
				},
				events: [
					OnDragStart(Box.box(|event| on_change(slider_value_from_position(min, max, step, event.target.bounds, event.position)))),
					OnDragMove(Box.box(|event| on_change(slider_value_from_position(min, max, step, event.target.bounds, event.position)))),
					OnDragEnd(Box.box(|event| on_change(slider_value_from_position(min, max, step, event.target.bounds, event.position)))),
				],
			},
			[
				box(
					{
						style: |status| {
							fill_color = if status.pressed {
								fill.fill.deviate(44)
							} else if status.hovered {
								fill.fill.deviate(24)
							} else {
								fill.fill
							}

							style
								.width(Percent(progress))
								.height(Grow({}))
								.background(fill_color)
								.radius(theme.radius)
						},
					},
					[
						box(
							{
								style: |status| {
									handle_fill = if status.pressed {
										fill.fill.deviate(44)
									} else if status.hovered {
										fill.fill.deviate(24)
									} else {
										fill.fill
									}

									style
										.width(Fixed(theme.font_size // 2))
										.height(Fixed(theme.font_size // 2))
										.background(handle_fill)
										.radius(100)
										.border({ color: theme.palette.primary.strong.fill, left: 1, right: 1, top: 1, bottom: 1 })
										.floating(
											Floating({
												target: Parent,
												config: {
													..Element.default_floating_config,
													z_index: 100,
													attach_points: { element: Center, target: RightCenter },
													capture: Passthrough,
													expand: { w: 4, h: 4 },
												},
											}),
										)
								},
							},
							[],
						),
					],
				),
			],
		)
	}
}

value_to_progress : F32, F32, F32 -> F32
value_to_progress = |value, min, max| {
	if max <= min {
		0
	} else {
		Utils.clamp((value - min) / (max - min), 0, 1)
	}
}

progress_to_value : F32, F32, F32 -> F32
progress_to_value = |progress, min, max| {
	if max <= min {
		min
	} else {
		min + Utils.clamp(progress, 0, 1) * (max - min)
	}
}

snap_to_step : F32, F32, F32 -> F32
snap_to_step = |value, min, step| {
	if step <= 0 {
		value
	} else {
		snap_to_step_help(value, min, step)
	}
}

normalize_range : F32, F32 -> { min : F32, max : F32 }
normalize_range = |min, max| {
	if max <= min {
		{ min, max: min }
	} else {
		{ min, max }
	}
}

normalize_slider_value : F32, F32, F32, F32 -> F32
normalize_slider_value = |value, min, max, step| {
	range = normalize_range(min, max)
	clamped = Utils.clamp(value, range.min, range.max)
	Utils.clamp(snap_to_step(clamped, range.min, step), range.min, range.max)
}

snap_to_step_help : F32, F32, F32 -> F32
snap_to_step_help = |value, current, step| {
	next = current + step
	midpoint = current + (step / 2)

	if value < midpoint {
		current
	} else if value <= next {
		next
	} else {
		snap_to_step_help(value, next, step)
	}
}

## Map a pointer position over a slider's track bounds onto a snapped value.
slider_value_from_position : F32, F32, F32, Event.ElementBounds, Event.Point -> F32
slider_value_from_position = |min, max, step, bounds, position| {
	range = normalize_range(min, max)
	if range.max <= range.min or bounds.width <= 0 {
		range.min
	} else {
		relative = Event.ElementBounds.relative(bounds, position)
		progress = Utils.clamp(relative.x / bounds.width, 0, 1)
		value = progress_to_value(progress, range.min, range.max)
		normalize_slider_value(value, range.min, range.max, step)
	}
}

expect {
	view = Slider.slider(Theme.dark, 50, 0, 100, 1, |v| v)

	match view.collect() {
		[OpenBox(Auto, _, [OnDragStart(_), OnDragMove(_), OnDragEnd(_)]), OpenBox(Auto, _, []), OpenBox(Auto, _, []), CloseBox, CloseBox, CloseBox] => True
		_ => False
	}
}

expect {
	value_to_progress(50, 0, 100) == 0.5 and value_to_progress(150, 0, 100) == 1 and value_to_progress(1, 2, 2) == 0
}

expect {
	progress_to_value(0.75, 0, 100) == 75 and progress_to_value(1.5, 0, 100) == 100 and progress_to_value(0.5, 4, 2) == 4
}

expect {
	snap_to_step(53, 0, 10) == 50 and snap_to_step(55, 0, 10) == 60 and snap_to_step(53, 0, 0) == 53
}

expect {
	bounds = { x: 0, y: 0, width: 100, height: 10 }

	slider_value_from_position(0, 100, 10, bounds, { x: 55, y: 5 }) == 60
		and slider_value_from_position(20, 80, 5, bounds, { x: 50, y: 5 }) == 50
}
