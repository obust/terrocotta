## Model-owned toggle switch widget.
import ../Element exposing [View, box, style]
import ../Color
import ../Theme
import rr.Mouse

Toggle :: [].{

	## Display a model-owned toggle switch.
	toggle : Theme, Bool, Bool, (Bool -> msg) -> View(msg, payload)
	toggle = |theme, checked, disabled, on_change| {
		track_size = theme.font_size
		knob_size = theme.font_size
		next_checked = match checked {
			True => False
			False => True
		}
		active_track_colors = match checked {
			True => theme.palette.primary.base
			False => theme.palette.surface.subtle
		}
		track_colors = match disabled {
			True => theme.palette.surface.subtle
			False => active_track_colors
		}
		handle_fill = match disabled {
			# True => Color.composite_over(theme.palette.disabled_content(theme.palette.surface.base.content), theme.palette.surface.base.fill)
			True => theme.palette.text.muted
			False => theme.palette.surface.inverse.fill
		}
		(target, offset) = match checked {
			True => (RightCenter, { x: -(knob_size / 2), y: 0 })
			False => (LeftCenter, { x: knob_size / 2, y: 0 })
		}
		events = match disabled {
			True => []
			False => [OnClick(on_change(next_checked))]
		}

		track_style = |status| {
			var $track = style
				.width(Fixed(track_size * 2))
				.height(Fixed(track_size))
				.background(track_colors.fill)
				.radius(100)
				.border({ color: theme.palette.edge.border, left: 1, right: 1, top: 1, bottom: 1 })
				.cursor(match disabled { True => NotAllowed False => PointingHand })

			match disabled {
				True => $track
				False => match status.pressed {
					True => $track.background(theme.palette.pressed(track_colors).fill)
					False => match status.hovered {
						True => $track.background(theme.palette.hovered(track_colors).fill)
						False => $track
					}
				}
			}
		}

		handle_style = |_status| style
			.width(Fixed(knob_size))
			.height(Fixed(knob_size))
			.background(handle_fill)
			.radius(100)
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

		box({ style: track_style, events }, [
			box({ style: handle_style, events }, []),
		])
	}
}

expect {
	view = Toggle.toggle(Theme.dark, True, False, |v| v)

	match view.collect() {
		[OpenBox(Auto, _, [OnClick(False)]), OpenBox(Auto, _, [OnClick(False)]), CloseBox, CloseBox] => True
		_ => False
	}
}
