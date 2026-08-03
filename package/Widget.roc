## Theme-aware static widgets built on Element.
import Color
import Element exposing [View, box, text, style]
import Event
import Theme
import Utils

Widget := [].{

	## Semantic widget color variants.
	Variant : [Primary, Secondary, Success, Warning, Danger]

	## Build a themed, centered dialog on a full-screen floating scrim.
	modal : Theme, {
		id : Element.ElementId,
		z_index : I16,
		scrim : Color,
		on_dismiss : [DismissWith(msg), NoDismiss],
	}, View(msg) -> View(msg)
	modal = |theme, config, content| {
		scrim_events = match config.on_dismiss {
			DismissWith(message) => [OnClick(message)]
			NoDismiss => []
		}
		dialog_colors = theme.palette.background.base

		box(
			config.id,
			|_| style
				.width(Grow({ min: 0, max: 10000 }))
				.height(Grow({ min: 0, max: 10000 }))
				.background(config.scrim)
				.floating(Floating({ target: Root, config: { ..Element.default_floating_config, z_index: config.z_index, capture: Capture } }))
				.child_align({ x: Center, y: Center }),
			scrim_events,
			[
				box(
					LocalId("dialog"),
					|_| style
						.width(Fit({ min: 0, max: 600 }))
						.height(Fit({ min: 0, max: 10000 }))
						.background(dialog_colors.fill)
						.font_family(theme.font)
						.font_size(theme.font_size)
						.font_color(dialog_colors.content)
						.radius(theme.radius)
						.direction(Col),
					[],
					[content],
				),
			],
		)
	}

	## Display body text using the theme background content color.
	label : Theme, Str -> View
	label = |theme, content| {
		box(
			Auto,
			|_| text_style(theme, theme.font_size, theme.palette.background.base)
				.width(Fit({ min: 0, max: 10000 }))
				.height(Fit({ min: 0, max: 10000 })),
			[],
			[
				text(content),
			],
		)
	}

	## Display larger heading text using the theme primary color.
	heading : Theme, Str -> View
	heading = |theme, content| {
		box(
			Auto,
			|_| text_style(theme, theme.font_size * 1.5, theme.palette.primary.strong)
				.width(Fit({ min: 0, max: 10000 }))
				.height(Fit({ min: 0, max: 10000 })),
			[],
			[
				text(content),
			],
		)
	}

	## Lay out children horizontally with the theme gap.
	row : Theme, List(View) -> View
	row = |theme, children| {
		box(
			Auto,
			|_| style
				.width(Fit({ min: 0, max: 10000 }))
				.height(Fit({ min: 0, max: 10000 }))
				.direction(Row)
				.gap(theme.gap)
				.child_align({ x: Start, y: Start }),
			[],
			children,
		)
	}

	## Lay out children vertically with the theme gap.
	column : Theme, List(View) -> View
	column = |theme, children| {
		box(
			Auto,
			|_| style
				.width(Fit({ min: 0, max: 10000 }))
				.height(Fit({ min: 0, max: 10000 }))
				.direction(Col)
				.gap(theme.gap)
				.child_align({ x: Start, y: Start }),
			[],
			children,
		)
	}

	## Group children on a weak background surface.
	panel : Theme, List(View) -> View
	panel = |theme, children| {
		colors = theme.palette.background.weak

		box(
			Auto,
			|_| style
				.width(Fit({ min: 0, max: 10000 }))
				.height(Fit({ min: 0, max: 10000 }))
				.background(colors.fill)
				.font_family(theme.font)
				.font_size(theme.font_size)
				.font_color(colors.content)
				.radius(theme.radius)
				.pad((theme.gap, theme.gap, theme.gap, theme.gap))
				.gap(theme.gap)
				.direction(Col)
				.child_align({ x: Start, y: Start }),
			[],
			children,
		)
	}

	## Display a button-shaped command label with hover, press, and focus styling.
	button : Theme, Variant, Str, List(Event.Handler) -> View
	button = |theme, variant, content, events| {
		colors = role_pair(theme, variant)

		box(
			Auto,
			|status| {
				var $box_style = style
					.width(Fit({ min: 0, max: 10000 }))
					.height(Fit({ min: 0, max: 10000 }))
					.background(colors.fill)
					.font_family(theme.font)
					.font_size(theme.font_size)
					.font_color(colors.content)
					.cursor(Pointer)
					.radius(theme.radius)
					.pad((theme.gap, theme.gap, theme.gap / 2, theme.gap / 2))
					.child_align({ x: Center, y: Center })

				$box_style = if status.focused {
					$box_style.border({ color: theme.palette.primary.strong.fill, left: 1, right: 1, top: 1, bottom: 1 })
				} else {
					$box_style
				}

				if status.pressed {
					$box_style.background(colors.fill.deviate(44))
				} else if status.hovered {
					$box_style.background(colors.fill.deviate(24))
				} else {
					$box_style
				}
			},
			events,
			[
				text(content),
			],
		)
	}

	## Display a model-owned checkbox with a text label.
	checkbox : Theme, Bool, Str, (Bool -> msg) -> View(msg)
	checkbox = |theme, checked, content, on_change| {
		box_size = theme.font_size
		next_checked = if checked { False } else { True }
		indicator_colors = if checked {
			theme.palette.primary.base
		} else {
			theme.palette.background.weak
		}

		box(
			Auto,
			|status| {
				var $box_style = style
					.width(Fit({ min: 0, max: 10000 }))
					.height(Fit({ min: 0, max: 10000 }))
					.font_family(theme.font)
					.font_size(theme.font_size)
					.font_color(theme.palette.background.base.content)
					.direction(Row)
					.gap(theme.gap / 2)
					.child_align({ x: Start, y: Center })

				if status.pressed {
					$box_style.background(theme.palette.background.weak.fill.deviate(44))
				} else if status.hovered {
					$box_style.background(theme.palette.background.weak.fill.deviate(24))
				} else {
					$box_style
				}
			},
			[OnClick(on_change(next_checked))],
			[
				box(
					Auto,
					|status| {
						indicator_fill = if status.pressed {
							indicator_colors.fill.deviate(44)
						} else if status.hovered {
							indicator_colors.fill.deviate(24)
						} else {
							indicator_colors.fill
						}

						style
							.width(Fixed(box_size))
							.height(Fixed(box_size))
							.background(indicator_fill)
							.radius(100)
							.border({ color: theme.palette.primary.base.fill, left: 2, right: 2, top: 2, bottom: 2 })
					},
					[],
					[],
				),
				text(content),
			],
		)
	}

	## Display a model-owned toggle switch.
	toggle : Theme, Bool, (Bool -> msg) -> View(msg)
	toggle = |theme, checked, on_change| {
		track_size = theme.font_size
		knob_size = theme.font_size
		next_checked = if checked { False } else { True }
		track_colors = if checked {
			theme.palette.primary.base
		} else {
			theme.palette.background.weak
		}

		box(
			Auto,
			|status| {
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
			[OnClick(on_change(next_checked))],
			[
				box(
					Auto,
					|_| {
						target = if checked { RightCenter } else { LeftCenter }
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
							.floating(Floating({
								target: Parent,
								config: {
									..Element.default_floating_config,
									z_index: 100,
									attach_points: { element: Center, target },
									offset,
									capture: Passthrough,
								},
							}))
					},
					[OnClick(on_change(next_checked))],
					[],
				),
			],
		)
	}

	## Display a compact semantic label.
	badge : Theme, Variant, Str -> View
	badge = |theme, variant, content| {
		colors = role_pair(theme, variant)

		box(
			Auto,
			|_| style
				.width(Fit({ min: 0, max: 10000 }))
				.height(Fit({ min: 0, max: 10000 }))
				.background(colors.fill)
				.font_family(theme.font)
				.font_size(theme.font_size * 0.85)
				.font_color(colors.content)
				.radius(theme.radius)
				.pad((theme.gap / 2, theme.gap / 2, theme.gap / 4, theme.gap / 4)),
			[],
			[
				text(content),
			],
		)
	}

	## Display a horizontal slider for model-owned numeric values.
	slider = |theme, value, min, max, step, on_change| {
		track = theme.palette.background.weak
		fill = theme.palette.primary.base
		range = normalize_range(min, max)
		normalized_value = normalize_slider_value(value, min, max, step)
		progress = value_to_progress(normalized_value, range.min, range.max)

		box(
			Auto,
			|status| {
				var $box_style = style
					.width(Grow({ min: theme.font_size * 6, max: 10000 }))
					.height(Fixed(theme.font_size // 2))
					.background(track.fill)
					.radius(theme.radius)
					.direction(Row)
					.child_align({ x: Start, y: Center })

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
			[
				OnPointer(
					Box.box(
						|event| {
							if event.buttons.left.down {
								[on_change(pointer_value(min, max, step, event))]
							} else {
								[]
							}
						},
					),
				),
			],
			[
				box(
					Auto,
					|status| {
						fill_color = if status.pressed {
							fill.fill.deviate(44)
						} else if status.hovered {
							fill.fill.deviate(24)
						} else {
							fill.fill
						}

						style
							.width(Percent(progress))
							.height(Grow({ min: 0, max: 10000 }))
							.background(fill_color)
							.radius(theme.radius)
					},
					[],
					[
						box(
							Auto,
							|status| {
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
									.floating(Floating({
										target: Parent,
										config: {
											..Element.default_floating_config,
											z_index: 100,
											attach_points: { element: Center, target: RightCenter },
											capture: Passthrough,
											expand: { w: 4, h: 4 },
										},
									}))
							},
							[],
							[],
						),
					],
				),
			],
		)
	}

	## Display a model-owned dropdown select with a collapsible option list.
	select : Theme, {
		open : Bool,
		selected : U64,
		options : List(Str),
		on_toggle_open : Bool -> msg,
		on_select : U64 -> msg,
	} -> View(msg)
	select = |theme, config| {
		on_toggle_open = config.on_toggle_open
		on_select = config.on_select
		selected_label = config.options.get(config.selected).ok_or("")
		next_open = if config.open { False } else { True }
		select_options = config.options.map_with_index(
			|option, index| select_option(theme, option, index, config.selected == index, on_select, on_toggle_open),
		)
		spacer = box(
		    Auto,
			|_| style
    		    .width(Grow({ min: 0, max: 10000 }))
    			.height(Fit({ min: 0, max: 10000 })),
			[],
			[]
		)

		trigger_view = box(
			Auto,
			|status| {
				trigger_colors = theme.palette.background.weak

				var $box_style = style
					.width(Grow({ min: theme.font_size * 6, max: 10000 }))
					.height(Fit({ min: 0, max: 10000 }))
					.background(trigger_colors.fill)
					.font_family(theme.font)
					.font_size(theme.font_size)
					.font_color(theme.palette.background.base.content)
					.radius(theme.radius)
					.pad((theme.gap, theme.gap, theme.gap / 2, theme.gap / 2))
					.direction(Row)
					.child_align({ x: Center, y: Center })
					.border({ color: theme.palette.primary.strong.fill, left: 1, right: 1, top: 1, bottom: 1 })

				$box_style = if status.focused {
					$box_style.border({ color: theme.palette.primary.strong.fill, left: 1, right: 1, top: 1, bottom: 1 })
				} else {
					$box_style
				}

				if status.pressed {
					$box_style.background(trigger_colors.fill.deviate(44))
				} else if status.hovered {
					$box_style.background(trigger_colors.fill.deviate(24))
				} else {
					$box_style
				}
			},
			[OnClick(on_toggle_open(next_open))],
			if config.open {
				[text(selected_label), spacer, text(">"), select_panel(theme, select_options)]
			} else {
				[text(selected_label), spacer, text(">")]
			},
		)

		if config.open {
			trigger_view.concat(select_scrim(on_toggle_open))
		} else {
			trigger_view
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
	Utils.clamp(Widget.snap_to_step(clamped, range.min, step), range.min, range.max)
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

pointer_value : F32, F32, F32, Event.PointerEvent -> F32
pointer_value = |min, max, step, event| {
	range = normalize_range(min, max)
	if range.max <= range.min or event.target.bounds.width <= 0 {
		range.min
	} else {
		relative = Event.ElementBounds.relative(event.target.bounds, event.position)
		progress = Utils.clamp(relative.x / event.target.bounds.width, 0, 1)
		value = Widget.progress_to_value(progress, range.min, range.max)
		normalize_slider_value(value, range.min, range.max, step)
	}
}

expect {
	view = Widget.button(Theme.dark, Primary, "Save", [])

	match view.collect() {
	    # check ElementOp strem
		[OpenBox(Auto, style_fn, []), Text("Save"), CloseBox] => {
		    # check style cursor
			status = { hovered: False, pressed: False, focused: False, disabled: False }
			(style_fn(status)).cursor == Pointer
		}
		_ => False
	}
}

expect {
	view = Widget.checkbox(Theme.dark, True, "Enabled", |checked| checked)

	match view.collect() {
		[OpenBox(Auto, _, [OnClick(False)]), OpenBox(Auto, _, []), CloseBox, Text("Enabled"), CloseBox] => True
		_ => False
	}
}

expect {
	view = Widget.toggle(Theme.dark, True, |v| v)

	match view.collect() {
		[OpenBox(Auto, _, [OnClick(False)]), OpenBox(Auto, _, [OnClick(False)]), CloseBox, CloseBox] => True
		_ => False
	}
}

expect {
	view = Widget.slider(Theme.dark, 50, 0, 100, 1, |v| v)

	match view.collect() {
		[OpenBox(Auto, _, [OnPointer(_)]), OpenBox(Auto, _, []), OpenBox(Auto, _, []), CloseBox, CloseBox, CloseBox] => True
		_ => False
	}
}

SelectMsg : [ToggleOpen(Bool), PickOption(U64)]

expect {
	view = Widget.select(
		Theme.dark,
		{
			open: False,
			selected: 0,
			options: ["Red", "Green", "Blue"],
			on_toggle_open: |open| ToggleOpen(open),
			on_select: |index| PickOption(index),
		},
	)

	match view.collect() {
		[OpenBox(Auto, _, [OnClick(ToggleOpen(True))]), Text("Red"), OpenBox(Auto, _, []), CloseBox, Text("▾"), CloseBox] => True
		_ => False
	}
}

expect {
	view = Widget.select(
		Theme.dark,
		{
			open: True,
			selected: 1,
			options: ["Red", "Green", "Blue"],
			on_toggle_open: |open| ToggleOpen(open),
			on_select: |index| PickOption(index),
		},
	)

	match view.collect() {
		[
			OpenBox(Auto, _, [OnClick(ToggleOpen(False))]),
			Text("Green"),
			OpenBox(Auto, _, []),
			CloseBox,
			Text("▾"),
			OpenBox(Auto, _, []),
			OpenBox(Auto, _, [OnClick(PickOption(0)), OnClick(ToggleOpen(False))]),
			Text("Red"),
			CloseBox,
			OpenBox(Auto, _, [OnClick(PickOption(1)), OnClick(ToggleOpen(False))]),
			Text("Green"),
			CloseBox,
			OpenBox(Auto, _, [OnClick(PickOption(2)), OnClick(ToggleOpen(False))]),
			Text("Blue"),
			CloseBox,
			CloseBox,
			CloseBox,
			OpenBox(Auto, _, [OnClick(ToggleOpen(False))]),
			CloseBox,
		] => True
		_ => False
	}
}

expect {
	view = Widget.select(
		Theme.dark,
		{
			open: False,
			selected: 99,
			options: ["Red", "Green"],
			on_toggle_open: |open| ToggleOpen(open),
			on_select: |index| PickOption(index),
		},
	)

	match view.collect() {
		[OpenBox(Auto, _, [OnClick(ToggleOpen(True))]), Text(""), OpenBox(Auto, _, []), CloseBox, Text("▾"), CloseBox] => True
		_ => False
	}
}

expect {
	Utils.clamp(-0.25, 0.0, 1.0) == 0.0 and Utils.clamp(0.5, 0.0, 1.0) == 0.5 and Utils.clamp(1.25, 0.0, 1.0) == 1.0
}

expect {
	Widget.value_to_progress(50, 0, 100) == 0.5 and Widget.value_to_progress(150, 0, 100) == 1 and Widget.value_to_progress(1, 2, 2) == 0
}

expect {
	Widget.progress_to_value(0.75, 0, 100) == 75 and Widget.progress_to_value(1.5, 0, 100) == 100 and Widget.progress_to_value(0.5, 4, 2) == 4
}

expect {
	Widget.snap_to_step(53, 0, 10) == 50 and Widget.snap_to_step(55, 0, 10) == 60 and Widget.snap_to_step(53, 0, 0) == 53
}

expect {
	config = {
		value: 0,
		min: 0,
		max: 100,
		step: 10,
		on_change: |value| value,
	}

	event = {
		position: { x: 55, y: 5 },
		buttons: {
			left: { down: False, pressed: True, released: False },
			middle: { down: False, pressed: False, released: False },
			right: { down: False, pressed: False, released: False },
		},
		target: { id: 1, bounds: { x: 0, y: 0, width: 100, height: 10 } },
	}

	pointer_value(config.min, config.max, config.step, event) == 60
}

## A fill/content pair used by themed widgets.
Pair : {
	fill : Color,
	content : Color,
}

## Return the palette pair for a semantic variant.
role_pair : Theme, Variant -> Pair
role_pair = |theme, variant| {
	match variant {
		Primary => theme.palette.primary.base
		Secondary => theme.palette.background.strong
		Success => theme.palette.success.base
		Warning => theme.palette.warning.base
		Danger => theme.palette.danger.base
	}
}

## Base text style shared by themed text widgets.
text_style : Theme, F32, Pair -> Element.BoxConfig
text_style = |theme, size, colors| {
	style
		.font_family(theme.font)
		.font_size(size)
		.font_color(colors.content)
}

## Build the floating dropdown panel for a select, attached to its trigger.
select_panel : Theme, List(View(msg)) -> View(msg)
select_panel = |theme, select_options| {
	box(
		Auto,
		|_| style
			.width(Grow({ min: 0, max: 10000 }))
			.height(Fit({ min: 0, max: 10000 }))
			.background(theme.palette.background.base.fill)
			.font_family(theme.font)
			.font_size(theme.font_size)
			.font_color(theme.palette.background.base.content)
			.radius(theme.radius)
			.border({ color: theme.palette.primary.strong.fill, left: 1, right: 1, top: 1, bottom: 1 })
			#.pad((theme.gap / 2, theme.gap / 2, theme.gap / 2, theme.gap / 2))
			.direction(Col)
			.child_align({ x: Start, y: Start })
			.overflow(Hidden, Hidden)
			.floating(Floating({
				target: Parent,
				config: {
					..Element.default_floating_config,
					z_index: 50,
					offset: { x: 0, y: theme.gap / 2 },
					attach_points: { element: LeftTop, target: LeftBottom },
					capture: Capture,
				},
			})),
		[],
		select_options,
	)
}

## Build the full-screen click-catcher that dismisses an open select.
select_scrim : (Bool -> msg) -> View(msg)
select_scrim = |on_toggle_open| {
	box(
		Auto,
		|_| style
			.width(Grow({ min: 0, max: 10000 }))
			.height(Grow({ min: 0, max: 10000 }))
			.floating(Floating({
				target: Root,
				config: {
					..Element.default_floating_config,
					z_index: 40,
					capture: Capture,
				},
			})),
		[OnClick(on_toggle_open(False))],
		[],
	)
}

## Render one selectable row for a select dropdown.
select_option : Theme, Str, U64, Bool, (U64 -> msg), (Bool -> msg) -> View(msg)
select_option = |theme, label, index, is_selected, on_select, on_toggle_open| {
	selected_colors = if is_selected {
		theme.palette.primary.base
	} else {
		theme.palette.background.weak
	}
	content_color = if is_selected {
		selected_colors.content
	} else {
		theme.palette.background.base.content
	}

	box(
		Auto,
		|status| {
			var $box_style = style
				.width(Grow({ min: 0, max: 10000 }))
				.height(Fit({ min: 0, max: 10000 }))
				.font_family(theme.font)
				.font_size(theme.font_size)
				.font_color(content_color)
				.radius(theme.radius)
				.pad((theme.gap / 2, theme.gap, theme.gap / 4, theme.gap / 4))

			if is_selected {
				$box_style.background(selected_colors.fill)
			} else if status.pressed {
				$box_style.background(selected_colors.fill.deviate(44))
			} else if status.hovered {
				$box_style.background(selected_colors.fill.deviate(24))
			} else {
				$box_style
			}
		},
		[OnClick(on_select(index)), OnClick(on_toggle_open(False))],
		[
			text(label),
		],
	)
}
