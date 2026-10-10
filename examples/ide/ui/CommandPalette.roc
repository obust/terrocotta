## Unified VS Code-style file finder and command palette.
import rr.Assets
import rr.Devices
import rr.Font
import rr.Keys
import tc.Color
import tc.Element exposing [ImageSizing.*, box, image, map, style, text]
import tc.Event
import tc.Program exposing [View]
import tc.Widget

import ../Theme exposing [theme]
import ../Workspace
import Explorer
import Keybindings

LauncherState := { query : Widget.TextInputState, selected : U64 }

Choice := [FileChoice(Str), CommandChoice(Keybindings.Command)]

Result := [FileResult(Str), CommandResult(Keybindings.CommandInfo)]

OverlayMsg := [QueryChanged(Widget.TextInputState), Select(U64), Choose(Choice), Dismiss]

CommandPalette := [].{
	Command : Keybindings.Command

	Model : [Closed, Open(LauncherState), KeybindsOpen]

	commands_for_input : Devices.Snapshot -> List(Command)
	commands_for_input = commands_from_input

	shortcut_for : Command -> Str
	shortcut_for = shortcut_for_command

	Msg : [
		ShowFileFinder,
		ShowCommandPalette,
		ShowKeybinds,
		Hide,
		SetQuery(Widget.TextInputState),
		Select(U64),
		ChooseFile(Str),
		Execute(Command),
	]

	init : Model
	init = Closed

	update : Model, Msg -> { model : Model, action : [NoAction, Run(Command)] }
	update = |model, message| match message {
		ShowFileFinder => { model: Open({ query: { value: "", cursor: 0 }, selected: 0 }), action: NoAction }
		ShowCommandPalette => { model: Open({ query: { value: ">", cursor: 1 }, selected: 0 }), action: NoAction }
		ShowKeybinds => { model: KeybindsOpen, action: NoAction }
		Hide => { model: Closed, action: NoAction }
		SetQuery(query) => {
			model: match model {
				Open(state) => Open({ ..state, query, selected: 0 })
				_ => model
			},
			action: NoAction,
		}
		Select(selected) => {
			model: match model {
				Open(state) => Open({ ..state, selected })
				_ => model
			},
			action: NoAction,
		}
		ChooseFile(path) => { model: Closed, action: Run(OpenFile(path)) }
		Execute(command) => { model: Closed, action: Run(command) }
	}

	view : Font, List(Workspace.Node), Explorer.Icons, Model -> View(Msg)
	view = |font, nodes, icons, model| match model {
		Closed => box({ style: |_| style.width(Fixed(0)).height(Fixed(0)) }, [])
		Open(state) => overlay_view(font, nodes, icons, state)
			|> map(
				|message| match message {
					QueryChanged(query) => SetQuery(query)
					Select(index) => Select(index)
					Choose(choice) => match choice {
						FileChoice(path) => ChooseFile(path)
						CommandChoice(command) => Execute(command)
					}
					Dismiss => Hide
				},
			)
		KeybindsOpen => keybinds_view(font)
	}

}

is_command_query : Str -> Bool
is_command_query = |query| query.starts_with(">")

command_query : Str -> Str
command_query = |query| {
	bytes = query.to_utf8()
	if bytes.is_empty() "" else Str.from_utf8_lossy(bytes.sublist({ start: 1, len: bytes.len() - 1 }))
}

search_results : List(Workspace.Node), Str -> List(Result)
search_results = |nodes, query| {
	if is_command_query(query) {
		command_matches(command_query(query)).map(|entry| CommandResult(entry))
	} else {
		needle = query.with_ascii_lowercased()
		collect_files(nodes)
			.keep_if(|path| needle.is_empty() or Str.contains(path.with_ascii_lowercased(), needle))
			.map(|path| FileResult(path))
	}
}

overlay_view : Font, List(Workspace.Node), Explorer.Icons, LauncherState -> View(OverlayMsg)
overlay_view = |font, nodes, icons, state| {
	options = search_results(nodes, state.query.value)
	selected = normalize_selection(state.selected, options.len())
	command_mode = is_command_query(state.query.value)
	input_theme = { ..theme, font_size: 14, radius: 4, gap: 8 }

	overlay_shell(
		{
			id: "quick-open",
			top_padding: theme.gap / 2,
			font,
			dialog_fill: theme.palette.surface.subtle.fill,
			dismiss: Dismiss,
			dialog_events: [OnInput(Box.box(|input, _bounds| input_messages(options, selected, input)))],
		},
		[
			box(
				{ style: |_| style.height(Fit({})).pad(theme.gap / 2, theme.gap, theme.gap - theme.gap / 8, theme.gap) },
				[
					Widget.input_text(
						input_theme,
						{
							id: Id("quick-open-input"),
							font,
							state: state.query,
							placeholder: "Search files or type > for commands",
							on_change: |query| QueryChanged(query),
						},
					),
				],
			),
			results_view(options, selected, icons, command_mode),
			box(
				{
					style: |_| style
						.height(Fixed(28))
						.pad(0, theme.gap, 0, theme.gap)
						.font_size(11)
						.font_color(theme.palette.text.muted)
						.border({ color: theme.palette.edge.border, left: 0, right: 0, top: 1, bottom: 0 })
						.child_align({ x: Start, y: Center }),
				},
				[text(if command_mode "Up/Down: Navigate   Enter: Run   Esc: Close" else "Up/Down: Navigate   Enter: Open   Esc: Close")],
			),
		],
	)
}

OverlayConfig(msg) := {
	id : Str,
	top_padding : F32,
	font : Font,
	dialog_fill : Color,
	dismiss : msg,
	dialog_events : List(Event.Handler(msg)),
}

overlay_shell : OverlayConfig(msg), List(View(msg)) -> View(msg)
overlay_shell = |config, children| box(
	{
		id: Id("${config.id}-scrim"),
		style: |_| style
			.width(Grow({}))
			.height(Grow({}))
			.pad(config.top_padding, theme.gap * 2, theme.gap * 2, theme.gap * 2)
			.background(theme.palette.scrim())
			.font_family(config.font)
			.child_align({ x: Center, y: Start })
			.floating(Floating({ target: Root, config: { ..Element.default_floating_config, z_index: 100, capture: Capture } })),
		events: [OnClick(config.dismiss)],
	},
	[
		box(
			{
				id: Id("${config.id}-dialog"),
				events: config.dialog_events,
				style: |_| style
					.width(Grow({ min: 320, max: 620 }))
					.height(Fit({ max: 410 }))
					.direction(Col)
					.background(config.dialog_fill)
					.border({ color: theme.palette.edge.border, left: 1, right: 1, top: 1, bottom: 1 })
					.radius(7)
					.overflow(Hidden, Hidden),
			},
			children,
		),
	],
)

command_matches : Str -> List(Keybindings.CommandInfo)
command_matches = |query| {
	needle = query.with_ascii_lowercased()
	Keybindings.registered.keep_if(|entry| needle.is_empty() or Str.contains(entry.title.with_ascii_lowercased(), needle))
}

commands_from_input : Devices.Snapshot -> List(CommandPalette.Command)
commands_from_input = |input| match Keybindings.registered.find_first(|entry| key_chord_pressed(input, entry.chord)) {
	Ok(entry) => [entry.command]
	Err(_) => []
}

key_chord_pressed : Devices.Snapshot, Keybindings.KeyChord -> Bool
key_chord_pressed = |input, chord| {
	requires_shift = chord.contains(KeyLeftShift) or chord.contains(KeyRightShift)
	shift_down = Keys.key_down(input, KeyLeftShift) or Keys.key_down(input, KeyRightShift)
	modifiers_down = chord.drop_last(1).fold(Bool.True, |all_down, key| all_down and chord_key_down(input, key))
	match chord.last() {
		Ok(key) => shift_down == requires_shift and modifiers_down and Keys.key_pressed(input, key)
		Err(_) => Bool.False
	}
}

chord_key_down : Devices.Snapshot, Keys.Key -> Bool
chord_key_down = |input, key| match key {
	KeyLeftControl | KeyRightControl => Keys.key_down(input, KeyLeftSuper)
		or Keys.key_down(input, KeyRightSuper)
			or Keys.key_down(input, KeyLeftControl)
				or Keys.key_down(input, KeyRightControl)
	KeyLeftShift | KeyRightShift => Keys.key_down(input, KeyLeftShift) or Keys.key_down(input, KeyRightShift)
	_ => Keys.key_down(input, key)
}

shortcut_for_command : CommandPalette.Command -> Str
shortcut_for_command = |command| match Keybindings.registered.find_first(|entry| entry.command == command) {
	Ok(entry) => key_chord_label(entry.chord)
	Err(_) => ""
}

key_chord_label : Keybindings.KeyChord -> Str
key_chord_label = |chord| Str.join_with(chord.map(key_label), "+")

key_label : Keys.Key -> Str
key_label = |key| match key {
	KeyLeftControl | KeyRightControl => "Cmd/Ctrl"
	KeyLeftShift | KeyRightShift => "Shift"
	KeyP => "P"
	KeyK => "K"
	KeyW => "W"
	KeyS => "S"
	_ => ""
}

collect_files : List(Workspace.Node) -> List(Str)
collect_files = |nodes| nodes.map(
	|node| match node {
		File(file) => [file.path]
		Directory(dir) => collect_files(dir.children)
	},
).join()

normalize_selection : U64, U64 -> U64
normalize_selection = |selected, count| if count == 0 0 else U64.min(selected, count - 1)

next_selection : U64, U64 -> U64
next_selection = |selected, count| if count == 0 0 else (selected + 1) % count

previous_selection : U64, U64 -> U64
previous_selection = |selected, count| if count == 0 0 else if selected == 0 count - 1 else selected - 1

choice_for : Result -> Choice
choice_for = |result| match result {
	FileResult(path) => FileChoice(path)
	CommandResult(entry) => CommandChoice(entry.command)
}

input_messages : List(Result), U64, Devices.Snapshot -> List(OverlayMsg)
input_messages = |options, selected, input| {
	count = options.len()
	var $messages = []
	if Keys.key_pressed(input, KeyEscape) {
		$messages = $messages.append(Dismiss)
	}
	if Keys.key_pressed(input, KeyDown) {
		$messages = $messages.append(Select(next_selection(selected, count)))
	}
	if Keys.key_pressed(input, KeyUp) {
		$messages = $messages.append(Select(previous_selection(selected, count)))
	}
	if Keys.key_pressed(input, KeyEnter) {
		$messages = match options.get(selected) {
			Ok(result) => $messages.append(Choose(choice_for(result)))
			Err(_) => $messages
		}
	}
	$messages
}

results_view : List(Result), U64, Explorer.Icons, Bool -> View(OverlayMsg)
results_view = |options, selected, icons, command_mode| {
	children = if options.is_empty() {
		[
			box(
				{ style: |_| style.width(Grow({})).height(Fixed(64)).font_color(theme.palette.text.muted).child_align({ x: Center, y: Center }) },
				[text(if command_mode "No matching commands" else "No matching files")],
			),
		]
	} else {
		options.map_with_index(|result, index| result_row(result, index, index == selected, icons.file))
	}

	box(
		{
			id: Id("quick-open-results"),
			style: |_| style
				.width(Grow({}))
				.height(Fit({ max: 300 }))
				.direction(Col)
				.child_align({ x: Start, y: Start })
				.overflow(Hidden, Scroll)
				.border({ color: theme.palette.edge.border, left: 0, right: 0, top: 1, bottom: 0 }),
		},
		children,
	)
}

result_row : Result, U64, Bool, Assets.Texture -> View(OverlayMsg)
result_row = |result, index, selected, file_icon| {
	choice = choice_for(result)
	(label, detail, row_id) = match result {
		FileResult(path) => (path, "", "file:${path}")
		CommandResult(entry) => (entry.title, key_chord_label(entry.chord), "command:${entry.title}")
	}
	events : List(Event.Handler(OverlayMsg))
	events = [OnClick(Choose(choice)), OnPointerEnter(Select(index))]
	leading = match result {
		FileResult(_) => box(
			{ style: |_| style.width(Fixed(18)).height(Fixed(18)).child_align({ x: Center, y: Center }), events },
			[image(file_icon, { width: Pixels(16), height: Pixels(16) })],
		)
		CommandResult(_) => box(
			{ style: |_| style.width(Fixed(18)).height(Fixed(18)).font_color(theme.palette.primary.base.fill).child_align({ x: Center, y: Center }), events },
			[text(">")],
		)
	}
	box(
		{
			id: Id("quick-open:${row_id}"),
			style: |status| style
				.width(Grow({}))
				.height(Fit({}))
				.pad(theme.gap / 2, theme.gap / 2, theme.gap / 2, theme.gap / 2)
				.gap(theme.gap / 2)
				.font_size(13)
				.font_color(if selected theme.palette.surface.base.content else theme.palette.text.muted)
				.background(if selected theme.palette.selected(theme.palette.surface.base).fill else if status.hovered theme.palette.hovered(theme.palette.surface.base).fill else theme.palette.surface.subtle.fill)
				.cursor(PointingHand),
			events,
		},
		[
			leading,
			box(
				{ style: |_| style.width(Grow({})).height(Fit({})).text_wrap(None).child_align({ x: Start, y: Center }), events },
				[text(label)],
			),
			box(
				{ style: |_| style.width(Fit({})).height(Fit({})).font_size(11).pad(0, theme.gap / 2, 0, 0).font_color(theme.palette.text.muted), events },
				[text(detail)],
			),
		],
	)
}

keybinds_view : Font -> View(CommandPalette.Msg)
keybinds_view = |font| overlay_shell(
	{
		id: "keybinds",
		top_padding: theme.gap * 9,
		font,
		dialog_fill: theme.palette.surface.base.fill,
		dismiss: Hide,
		dialog_events: [OnInput(Box.box(keybind_input_messages))],
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
			Keybindings.registered.map(keybind_row),
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
)

keybind_input_messages : Devices.Snapshot, bounds -> List(CommandPalette.Msg)
keybind_input_messages = |input, _bounds| if Keys.key_pressed(input, KeyEscape) [Hide] else []

keybind_row : Keybindings.CommandInfo -> View(CommandPalette.Msg)
keybind_row = |entry| box(
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
		box({ style: |_| style.width(Grow({})).height(Fit({})).font_color(theme.palette.surface.base.content).child_align({ x: Start, y: Center }) }, [text(entry.title)]),
		box({ style: |_| style.width(Fit({})).height(Fit({})).font_size(12).font_color(theme.palette.text.muted) }, [text(key_chord_label(entry.chord))]),
	],
)

expect is_command_query(">close")
expect !is_command_query("close")
expect command_query(">keyboard") == "keyboard"
expect command_matches("file").map(|entry| entry.command) == [FindFile, SaveFile]

expect {
	chosen = CommandPalette.update(Open({ query: { value: "index", cursor: 5 }, selected: 0 }), ChooseFile("index.html"))
	chosen.model == Closed and chosen.action == Run(OpenFile("index.html"))
}

expect {
	chosen = CommandPalette.update(Open({ query: { value: ">save", cursor: 5 }, selected: 0 }), Execute(SaveFile))
	chosen.model == Closed and chosen.action == Run(SaveFile)
}

expect {
	command_input = Devices.none.with_key_down(KeyLeftSuper).with_key_down(KeyLeftShift).with_key_pressed(KeyP)
	file_input = Devices.none.with_key_down(KeyLeftSuper).with_key_pressed(KeyP)
	keybinds_input = Devices.none.with_key_down(KeyLeftControl).with_key_pressed(KeyK)
	close_input = Devices.none.with_key_down(KeyLeftSuper).with_key_pressed(KeyW)
	save_input = Devices.none.with_key_down(KeyLeftSuper).with_key_pressed(KeyS)
	commands_from_input(command_input) == [ShowCommandPalette]
		and commands_from_input(file_input) == [FindFile]
			and commands_from_input(keybinds_input) == [ShowKeyboardShortcuts]
				and commands_from_input(close_input) == [CloseActiveEditor]
					and commands_from_input(save_input) == [SaveFile]
}

expect Keybindings.registered.map(|entry| key_chord_label(entry.chord)) == [
	"Cmd/Ctrl+Shift+P",
	"Cmd/Ctrl+P",
	"Cmd/Ctrl+K",
	"Cmd/Ctrl+W",
	"Cmd/Ctrl+S",
]

expect {
	nodes : List(Workspace.Node)
	nodes = [File({ path: "index.html", name: "index.html" })]
	match (search_results(nodes, "INDEX").map(choice_for), search_results(nodes, ">keyboard").map(choice_for)) {
		([FileChoice("index.html")], [CommandChoice(ShowKeyboardShortcuts)]) => Bool.True
		_ => Bool.False
	}
}

expect keybind_input_messages(Devices.none.with_key_pressed(KeyEscape), { x: 0, y: 0, width: 0, height: 0 }) == [Hide]

expect {
	options : List(Result)
	options = [FileResult("a.html"), FileResult("b.html")]
	match (
		input_messages(options, 0, Devices.none.with_key_pressed(KeyDown)),
		input_messages(options, 1, Devices.none.with_key_pressed(KeyEnter)),
		input_messages(options, 0, Devices.none.with_text_input([62])),
	) {
		([Select(1)], [Choose(FileChoice("b.html"))], []) => Bool.True
		_ => Bool.False
	}
}
