## VS Code-style title bar with a centered Commands trigger.
import tc.Element exposing [box, style, text]
import tc.Program exposing [View]

import Colors

Topbar := [].{
	Msg : [ShowCommands]

	view : View(Msg)
	view = {
		command_events = [OnClick(ShowCommands)]
		box(
			{
				style: |_| style
					.width(Grow({}))
					.height(Fixed(40))
					.direction(Row)
					.pad(0, 12, 0, 12)
					.gap(10)
					.background(Colors.explorer)
					.border({ color: Colors.border, left: 0, right: 0, top: 0, bottom: 1 })
					.child_align({ x: Start, y: Center }),
			},
			[
				box(
					{
						style: |_| style
							.width(Fit({}))
							.height(Fit({}))
							.direction(Row)
							.gap(10)
							.child_align({ x: Start, y: Center }),
					},
					[
						box({ style: |_| style.width(Fit({})).height(Fit({})).font_color(Colors.accent) }, [text("TERROCOTTA")]),
						text("/"),
						box({ style: |_| style.width(Fit({})).height(Fit({})).font_color(Colors.text_dim) }, [text("IDE")]),
					],
				),
				box(
					{
						id: Id("commands-trigger"),
						style: |status| style
							.width(Fixed(600))
							.height(Fixed(26))
							.pad(0, 10, 0, 10)
							.font_size(12)
							.font_color(if status.hovered Colors.text else Colors.text_dim)
							.background(if status.hovered Colors.surface_hover else Colors.surface_active)
							.border({ color: if status.hovered Colors.accent else Colors.border, left: 1, right: 1, top: 1, bottom: 1 })
							.radius(4)
							.direction(Row)
							.child_align({ x: Start, y: Center })
							.floating(Floating({ target: Parent, config: { ..Element.default_floating_config, z_index: 1, attach_points: { element: Center, target: Center } } }))
							.cursor(IBeam),
						events: command_events,
					},
					[
						box(
							{ style: |_| style.width(Grow({})).height(Fit({})).child_align({ x: Start, y: Center }), events: command_events },
							[text("Commands")],
						),
						box(
							{ style: |_| style.width(Fit({})).height(Fit({})).font_size(11).font_color(Colors.text_dim).child_align({ x: End, y: Center }), events: command_events },
							[text("Cmd/Ctrl+Shift+P")],
						),
					],
				),
				box({ style: |_| style.width(Grow({})).height(Fit({})) }, []),
			],
		)
	}
}
