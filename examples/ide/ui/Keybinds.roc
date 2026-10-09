## Read-only keyboard shortcut reference.
import rr.Devices
import rr.Font
import rr.Keys
import tc.Color
import tc.Element exposing [box, style, text]
import tc.Program exposing [View]

import ../Theme exposing [theme]

Keybinds := [].{
	Binding : { command : Str, shortcut : Str }

	Msg : [Dismiss]

	view : Font -> View(Msg)
	view = |font| box(
		{
			id: Id("keybinds-scrim"),
			style: |_| style
				.width(Grow({}))
				.height(Grow({}))
				.pad(theme.gap * 9, theme.gap * 2, theme.gap * 2, theme.gap * 2)
				.background(theme.palette.scrim())
				.font_family(font)
				.child_align({ x: Center, y: Start })
				.floating(Floating({ target: Root, config: { ..Element.default_floating_config, z_index: 100, capture: Capture } })),
			events: [OnClick(Dismiss)],
		},
		[
			box(
				{
					id: Id("keybinds-dialog"),
					events: [OnInput(Box.box(input_messages))],
					style: |_| style
						.width(Grow({ min: 320, max: 620 }))
						.height(Fit({ max: 410 }))
						.direction(Col)
						.background(theme.palette.surface.base.fill)
						.border({ color: theme.palette.edge.border, left: 1, right: 1, top: 1, bottom: 1 })
						.radius(7)
						.overflow(Hidden, Hidden),
				},
				[
					box(
						{
							style: |_| style
								.width(Grow({}))
								.height(Fixed(48))
								.pad(0, theme.gap + theme.gap / 2, 0, theme.gap + theme.gap / 2)
								.font_size(15)
								.font_color(theme.palette.surface.base.content)
								.border({ color: theme.palette.edge.border, left: 0, right: 0, top: 0, bottom: 1 })
								.child_align({ x: Start, y: Center }),
						},
						[text("Keyboard Shortcuts")],
					),
					box(
						{ style: |_| style.height(Fit({ max: 320 })).direction(Col).overflow(Hidden, Scroll) },
						bindings.map(binding_row),
					),
					box(
						{
							style: |_| style
								.width(Grow({}))
								.height(Fixed(28))
							.pad(0, theme.gap, 0, theme.gap)
								.font_size(11)
							.font_color(theme.palette.text.muted)
							.border({ color: theme.palette.edge.border, left: 0, right: 0, top: 1, bottom: 0 })
								.child_align({ x: Start, y: Center }),
						},
						[text("Esc Close")],
					),
				],
			),
		],
	)
}

bindings : List(Keybinds.Binding)
bindings = [
	{ command: "Command Palette", shortcut: "Cmd/Ctrl+Shift+P" },
	{ command: "Search File", shortcut: "Ctrl+P" },
	{ command: "Keyboard Shortcuts", shortcut: "Ctrl+K" },
	{ command: "Close Active Editor", shortcut: "Cmd+W" },
]

input_messages : Devices.Snapshot, bounds -> List(Keybinds.Msg)
input_messages = |input, _bounds| if Keys.key_pressed(input, KeyEscape) [Dismiss] else []

binding_row : Keybinds.Binding -> View(Keybinds.Msg)
binding_row = |binding| box(
	{
		style: |_| style
			.width(Grow({}))
			.height(Fixed(38))
			.pad(0, theme.gap + theme.gap / 2, 0, theme.gap + theme.gap / 2)
			.gap(theme.gap + theme.gap / 2)
			.border({ color: theme.palette.edge.border, left: 0, right: 0, top: 0, bottom: 1 })
			.child_align({ x: Start, y: Center }),
	},
	[
		box({ style: |_| style.width(Grow({})).height(Fit({})).font_color(theme.palette.surface.base.content).child_align({ x: Start, y: Center }) }, [text(binding.command)]),
		box({ style: |_| style.width(Fit({})).height(Fit({})).font_size(12).font_color(theme.palette.text.muted) }, [text(binding.shortcut)]),
	],
)

expect input_messages(Devices.none.with_key_pressed(KeyEscape), { x: 0, y: 0, width: 0, height: 0 }) == [Dismiss]
