## Model-owned dropdown select widget.
import ../Element exposing [View, box, text, style]
import ../Theme

Select :: [].{

	## Display a model-owned dropdown select with a collapsible option list.
	select : Theme,
	{
		open : Bool,
		selected : U64,
		options : List(Str),
		on_toggle_open : Bool -> msg,
		on_select : U64 -> msg,
	} -> View(msg, payload)
	select = |theme, config| {
		on_toggle_open = config.on_toggle_open
		on_select = config.on_select
		selected_label = config.options.get(config.selected).ok_or("")
		next_open = if config.open {
			False
		} else {
			True
		}
		select_options = config.options.map_with_index(
			|option, index| select_option(theme, option, index, config.selected == index, on_select, on_toggle_open),
		)
		spacer = box(
			{
				style: |_| style
					.width(Grow({}))
					.height(Fit({})),
			},
			[],
		)

		trigger_view = box(
			{
				style: |status| {
					trigger_colors = theme.palette.surface.subtle

					var $box_style = style
						.width(Grow({ min: theme.font_size * 6, max: 10000 }))
						.height(Fit({}))
						.background(trigger_colors.fill)
						.font_size(theme.font_size)
						.font_color(theme.palette.surface.base.content)
						.radius(theme.radius)
						.pad(theme.gap / 2, theme.gap, theme.gap / 2, theme.gap)
						.direction(Row)
						.child_align({ x: Center, y: Center })
						.border({ color: theme.palette.edge.control, left: 1, right: 1, top: 1, bottom: 1 })

					$box_style = if status.focused {
						$box_style.border({ color: theme.palette.edge.focus, left: 1, right: 1, top: 1, bottom: 1 })
					} else {
						$box_style
					}

					if status.pressed {
						$box_style.background(theme.palette.pressed(trigger_colors).fill)
					} else if status.hovered {
						$box_style.background(theme.palette.hovered(trigger_colors).fill)
					} else {
						$box_style
					}
				},
				events: [OnClick(on_toggle_open(next_open))],
			},
			if config.open {
				[text(selected_label), spacer, text("v"), select_panel(theme, select_options)]
			} else {
				[text(selected_label), spacer, text("v")]
			},
		)

		if config.open {
			trigger_view.concat(select_scrim(on_toggle_open))
		} else {
			trigger_view
		}
	}
}

## Build the floating dropdown panel for a select, attached to its trigger.
select_panel : Theme, List(View(msg, payload)) -> View(msg, payload)
select_panel = |theme, select_options| {
	box(
		{
			style: |status| {
    			border_color = if status.focused {
    				theme.palette.edge.focus
    			} else {
    				theme.palette.edge.control
    			}
    			style
    				.width(Grow({}))
    				.height(Fit({}))
    				.background(theme.palette.surface.base.fill)
    				.font_size(theme.font_size)
    				.font_color(theme.palette.surface.base.content)
    				.radius(theme.radius)
    				.border({ color: border_color, left: 1, right: 1, top: 1, bottom: 1 })
    				.direction(Col)
    				.child_align({ x: Start, y: Start })
    				.overflow(Hidden, Hidden)
    				.floating(
    					Floating({
    						target: Parent,
    						config: {
    							..Element.default_floating_config,
    							z_index: 50,
    							offset: { x: 0, y: theme.gap / 2 },
    							attach_points: { element: LeftTop, target: LeftBottom },
    							capture: Capture,
    						},
    					}),
    				)
			}
		},
		select_options,
	)
}

## Build the full-screen click-catcher that dismisses an open select.
select_scrim : (Bool -> msg) -> View(msg, payload)
select_scrim = |on_toggle_open| {
	box(
		{
			style: |_| style
				.width(Grow({}))
				.height(Grow({}))
				.floating(
					Floating({
						target: Root,
						config: {
							..Element.default_floating_config,
							z_index: 40,
							capture: Capture,
						},
					}),
				),
			events: [OnClick(on_toggle_open(False))],
		},
		[],
	)
}

## Render one selectable row for a select dropdown.
select_option : Theme, Str, U64, Bool, (U64 -> msg), (Bool -> msg) -> View(msg, payload)
select_option = |theme, label, index, is_selected, on_select, on_toggle_open| {
		selected_colors = theme.palette.selected(theme.palette.surface.subtle)
		content_color = theme.palette.surface.base.content

	box(
		{
			style: |status| {
				var $box_style = style
					.width(Grow({}))
					.height(Fit({}))
					.font_size(theme.font_size)
					.font_color(content_color)
					.radius(theme.radius)
					.pad(theme.gap / 4, theme.gap, theme.gap / 4, theme.gap / 2)

				if is_selected {
					$box_style.background(selected_colors.fill)
				} else if status.pressed {
					$box_style.background(theme.palette.pressed(selected_colors).fill)
				} else if status.hovered {
					$box_style.background(theme.palette.hovered(selected_colors).fill)
				} else {
					$box_style
				}
			},
			events: [OnClick(on_select(index)), OnClick(on_toggle_open(False))],
		},
		[
			text(label),
		],
	)
}

SelectMsg : [ToggleOpen(Bool), PickOption(U64)]

expect {
	view = Select.select(
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
		[OpenBox(Auto, _, [OnClick(ToggleOpen(True))]), Text("Red"), OpenBox(Auto, _, []), CloseBox, Text("v"), CloseBox] => True
		_ => False
	}
}

expect {
	view = Select.select(
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
			Text(">"),
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
	view = Select.select(
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
		[OpenBox(Auto, _, [OnClick(ToggleOpen(True))]), Text(""), OpenBox(Auto, _, []), CloseBox, Text(">"), CloseBox] => True
		_ => False
	}
}
