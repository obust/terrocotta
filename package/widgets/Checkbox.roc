## Model-owned checkbox widget.
import ../Element exposing [View, box, text, canvas, style]
import ../Color
import ../Renderer
import ../Theme
import rr.Draw
import rr.Mouse

Checkbox :: [].{

	## Display a model-owned checkbox with a text label.
	checkbox : Theme, Bool, Bool, Str, (Bool -> msg) -> View(msg, [Canvas(Box(Renderer.CanvasDraw)), ..payload])
	checkbox = |theme, checked, disabled, content, on_change| {
		box_size = theme.font_size
		next_checked = if checked {
			False
		} else {
			True
		}
		active_indicator_colors = if checked {
			theme.palette.primary.base
		} else {
			theme.palette.surface.subtle
		}
		indicator_colors = if disabled theme.palette.surface.subtle else active_indicator_colors

		draw_check! : Renderer.CanvasDraw
		draw_check! = |frame, bounds| {
			{ x, y } = bounds.position
			{ w, h } = bounds.size
			color = (if disabled theme.palette.disabled_content(indicator_colors.content) else indicator_colors.content).to_rrt()
			thickness = F32.max(1, F32.min(w, h) / 8)
			stroke = Draw.stroke(color, thickness)
			start = { x: x + w * 0.22, y: y + h * 0.52 }
			knee = { x: x + w * 0.43, y: y + h * 0.72 }
			end = { x: x + w * 0.78, y: y + h * 0.28 }
			frame.line!({ start: start, end: knee, stroke })
			frame.line!({ start: knee, end: end, stroke })
			frame.circle!({ center: knee, radius: thickness / 2, style: Draw.filled(color) })
			Ok({})
		}

		box(
			{
				style: |_status| style
					.width(Fit({}))
					.height(Fit({}))
					.font_size(theme.font_size)
					.font_color(if disabled theme.palette.disabled_content(theme.palette.surface.base.content) else theme.palette.surface.base.content)
					.direction(Row)
					.gap(theme.gap / 2)
					.child_align({ x: Start, y: Center }),
			},
			[
				box(
					{
						style: |status| {
							indicator_fill = if disabled {
								indicator_colors.fill
							} else if status.pressed {
								theme.palette.pressed(indicator_colors).fill
							} else if status.hovered {
								theme.palette.hovered(indicator_colors).fill
							} else {
								indicator_colors.fill
							}

							style
								.width(Fixed(box_size))
								.height(Fixed(box_size))
								.background(indicator_fill)
								.radius(theme.radius)
								.border({ color: theme.palette.edge.control, left: 1, right: 1, top: 1, bottom: 1 })
								.cursor(if disabled NotAllowed else PointingHand)
						},
						events: if disabled [] else [OnClick(on_change(next_checked))],
					},
					if checked [canvas(draw_check!)] else [],
				),
				text(content),
			],
		)
	}
}

## Checked boxes draw a canvas checkmark and emit the unchecked value.
expect {
	view = Checkbox.checkbox(Theme.dark, True, False, "Enabled", |checked| checked)

	match view.collect() {
		[OpenBox(Auto, _, [OnClick(False)]), OpenBox(Auto, _, [OnClick(False)]), Custom(Canvas(_)), CloseBox, Text("Enabled"), CloseBox] => True
		_ => False
	}
}

## Unchecked boxes omit the checkmark and emit the checked value.
expect {
	view = Checkbox.checkbox(Theme.dark, False, False, "Enabled", |checked| checked)
	match view.collect() {
		[OpenBox(Auto, _, [OnClick(True)]), OpenBox(Auto, _, [OnClick(True)]), CloseBox, Text("Enabled"), CloseBox] => True
		_ => False
	}
}
