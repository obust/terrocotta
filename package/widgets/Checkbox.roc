## Model-owned checkbox widget.
import ../Element exposing [View, box, text, canvas, style]
import ../Color
import ../Renderer
import ../Theme
import rr.Draw
import rr.Mouse

Checkbox :: [].{

	## Display a model-owned checkbox with a text label.
	checkbox : Theme, Bool, Str, (Bool -> msg) -> View(msg, [Canvas(Box(Renderer.CanvasDraw)), ..payload])
	checkbox = |theme, checked, content, on_change| {
		box_size = theme.font_size
		next_checked = if checked {
			False
		} else {
			True
		}
		indicator_colors = if checked {
			theme.palette.primary.base
		} else {
			theme.palette.background.weak
		}

		draw_check! : Renderer.CanvasDraw
		draw_check! = |frame, bounds| {
			{ x, y } = bounds.position
			{ w, h } = bounds.size
			color = indicator_colors.content.to_rrt()
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
				style: |status| style
					.width(Fit({}))
					.height(Fit({}))
					.font_size(theme.font_size)
					.font_color(theme.palette.background.base.content)
					.direction(Row)
					.gap(theme.gap / 2)
					.child_align({ x: Start, y: Center }),
			},
			[
				box(
					{
						style: |status| {
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
								.radius(theme.radius)
								.border({ color: theme.palette.primary.base.fill, left: 2, right: 2, top: 2, bottom: 2 })
								.cursor(PointingHand)
						},
						events: [OnClick(on_change(next_checked))],
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
	view = Checkbox.checkbox(Theme.dark, True, "Enabled", |checked| checked)

	match view.collect() {
		[OpenBox(Auto, _, [OnClick(False)]), OpenBox(Auto, _, [OnClick(False)]), Custom(Canvas(_)), CloseBox, Text("Enabled"), CloseBox] => True
		_ => False
	}
}

## Unchecked boxes omit the checkmark and emit the checked value.
expect {
	view = Checkbox.checkbox(Theme.dark, False, "Enabled", |checked| checked)
	match view.collect() {
		[OpenBox(Auto, _, [OnClick(True)]), OpenBox(Auto, _, [OnClick(True)]), CloseBox, Text("Enabled"), CloseBox] => True
		_ => False
	}
}
