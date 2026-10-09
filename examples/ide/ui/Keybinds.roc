## Read-only keyboard shortcut reference.
import rr.Devices
import rr.Font
import rr.Keys
import tc.Color
import tc.Element exposing [box, style, text]
import tc.Program exposing [View]

import Colors

Keybinds := [].{
	Binding : { command : Str, shortcut : Str }

	Msg : [Dismiss]

	bindings : List(Binding)
	bindings = [
		{ command: "Command Palette", shortcut: "Cmd/Ctrl+Shift+P" },
		{ command: "Search File", shortcut: "Ctrl+P" },
		{ command: "Keyboard Shortcuts", shortcut: "Ctrl+K" },
		{ command: "Close Active Editor", shortcut: "Cmd+W" },
	]

	view : Font -> View(Msg)
	view = |font| box(
		{
			id: Id("keybinds-scrim"),
			style: |_| style
				.width(Grow({}))
				.height(Grow({}))
				.pad(72, 20, 20, 20)
				.background(Color.with_alpha(Colors.window, 210))
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
						.background(Colors.tab_bar)
						.border({ color: Colors.border, left: 1, right: 1, top: 1, bottom: 1 })
						.radius(7)
						.overflow(Hidden, Hidden),
				},
				[
					box(
						{
							style: |_| style
								.width(Grow({}))
								.height(Fixed(48))
								.pad(0, 14, 0, 14)
								.font_size(15)
								.font_color(Colors.text)
								.border({ color: Colors.border, left: 0, right: 0, top: 0, bottom: 1 })
								.child_align({ x: Start, y: Center }),
						},
						[text("Keyboard Shortcuts")],
					),
					box(
						{ style: |_| style.height(Fit({ max: 320 })).direction(Col).overflow(Hidden, Scroll) },
						Keybinds.bindings.map(binding_row),
					),
					box(
						{
							style: |_| style
								.width(Grow({}))
								.height(Fixed(28))
								.pad(0, 10, 0, 10)
								.font_size(11)
								.font_color(Colors.text_dim)
								.border({ color: Colors.border, left: 0, right: 0, top: 1, bottom: 0 })
								.child_align({ x: Start, y: Center }),
						},
						[text("Esc Close")],
					),
				],
			),
		],
	)
}

input_messages : Devices.Snapshot, bounds -> List(Keybinds.Msg)
input_messages = |input, _bounds| if Keys.key_pressed(input, KeyEscape) [Dismiss] else []

binding_row : Keybinds.Binding -> View(Keybinds.Msg)
binding_row = |binding| box(
	{
		style: |_| style
			.width(Grow({}))
			.height(Fixed(38))
			.pad(0, 14, 0, 14)
			.gap(12)
			.border({ color: Colors.border, left: 0, right: 0, top: 0, bottom: 1 })
			.child_align({ x: Start, y: Center }),
	},
	[
		box({ style: |_| style.width(Grow({})).height(Fit({})).font_color(Colors.text).child_align({ x: Start, y: Center }) }, [text(binding.command)]),
		box({ style: |_| style.width(Fit({})).height(Fit({})).font_size(12).font_color(Colors.text_dim) }, [text(binding.shortcut)]),
	],
)

expect input_messages(Devices.none.with_key_pressed(KeyEscape), { x: 0, y: 0, width: 0, height: 0 }) == [Dismiss]
