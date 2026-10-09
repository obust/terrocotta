## VS Code-style title bar with a centered Commands trigger.
import tc.Element exposing [box, style, text]
import tc.Program exposing [View]

import ../Theme exposing [theme]

Topbar := [].{
	Msg : [ShowCommands]

	view : Str -> View(Msg)
	view = |command_shortcut| {
		command_events = [OnClick(ShowCommands)]
		box(
			{
				style: |_| style
					.width(Grow({}))
					.height(Fixed(40))
					.direction(Row)
					.pad(0, theme.gap + theme.gap / 2, 0, theme.gap + theme.gap / 2)
					.gap(theme.gap)
					.background(theme.palette.surface.base.fill)
					.border({ color: theme.palette.edge.border, left: 0, right: 0, top: 0, bottom: 1 })
					.child_align({ x: Start, y: Center }),
			},
			[
				box(
					{
						style: |_| style
							.width(Fit({}))
							.height(Fit({}))
							.direction(Row)
							.gap(theme.gap)
							.child_align({ x: Start, y: Center }),
					},
					[
						box({ style: |_| style.width(Fit({})).height(Fit({})).font_color(theme.palette.primary.base.fill) }, [text("TERROCOTTA")]),
						text("/"),
						box({ style: |_| style.width(Fit({})).height(Fit({})).font_color(theme.palette.text.muted) }, [text("IDE")]),
					],
				),
				box(
					{
						id: Id("commands-trigger"),
						style: |status| style
							.width(Fixed(600))
							.height(Fixed(26))
							.pad(0, theme.gap, 0, theme.gap)
							.font_size(12)
							.font_color(if status.hovered theme.palette.surface.base.content else theme.palette.text.muted)
							.background(if status.hovered theme.palette.hovered(theme.palette.surface.base).fill else theme.palette.surface.subtle.fill)
							.border({ color: if status.hovered theme.palette.primary.base.fill else theme.palette.edge.border, left: 1, right: 1, top: 1, bottom: 1 })
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
							{ style: |_| style.width(Fit({})).height(Fit({})).font_size(11).font_color(theme.palette.text.muted).child_align({ x: End, y: Center }), events: command_events },
							[text(command_shortcut)],
						),
					],
				),
				box({ style: |_| style.width(Grow({})).height(Fit({})) }, []),
			],
		)
	}
}
