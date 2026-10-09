## Unified VS Code-style file finder and command palette.
import rr.Assets
import rr.Devices
import rr.Font
import rr.Keys
import tc.Color
import tc.Element exposing [ImageSizing.*, box, image, map, style, text]
import tc.Event
import tc.Program exposing [View]
import tc.Theme
import tc.Widget

import ../Workspace
import Colors
import Commands
import Explorer
import Keybinds

CommandPalette := [].{
	FileEntry : { path : Str, name : Str }

	Choice : [FileChoice(Str), CommandChoice(Commands.PaletteCommand)]

	Result : [FileResult(FileEntry), CommandResult(Commands.Entry)]

	OverlayMsg : [QueryChanged(Widget.TextInputState), Select(U64), Choose(Choice), Dismiss]

	files : List(Workspace.Node) -> List(FileEntry)
	files = collect_files

	is_command_query : Str -> Bool
	is_command_query = |query| query.starts_with(">")

	command_query : Str -> Str
	command_query = |query| {
		bytes = query.to_utf8()
		if bytes.is_empty() "" else Str.from_utf8_lossy(bytes.sublist({ start: 1, len: bytes.len() - 1 }))
	}

	results : List(Workspace.Node), Str -> List(Result)
	results = |nodes, query| {
		if CommandPalette.is_command_query(query) {
			Commands.matches(CommandPalette.command_query(query)).map(|entry| CommandResult(entry))
		} else {
			needle = query.with_ascii_lowercased()
			collect_files(nodes)
				.keep_if(|entry| needle.is_empty() or Str.contains(entry.path.with_ascii_lowercased(), needle))
				.map(|entry| FileResult(entry))
		}
	}

	overlay_view : Font, List(Workspace.Node), Explorer.Icons, Commands.LauncherState -> View(OverlayMsg)
	overlay_view = |font, nodes, icons, state| {
		options = CommandPalette.results(nodes, state.query.value)
		selected = normalize_selection(state.selected, options.len())
		command_mode = CommandPalette.is_command_query(state.query.value)
		input_theme = { ..Theme.dark, font_size: 14, radius: 4, gap: 8 }

		box(
			{
				id: Id("quick-open-scrim"),
				style: |_| style
					.pad(4, 20, 20, 20)
					.background(Color.with_alpha(Colors.window, 210))
					.child_align({ x: Center, y: Start })
					.floating(Floating({ target: Root, config: { ..Element.default_floating_config, z_index: 100, capture: Capture } })),
				events: [OnClick(Dismiss)],
			},
			[
				box(
					{
						id: Id("quick-open-dialog"),
						events: [OnInput(Box.box(|input, _bounds| input_messages(options, selected, state.query, input)))],
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
							{ style: |_| style.height(Fit({})).pad(3, 10, 7, 10) },
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
									.pad(0, 10, 0, 10)
									.font_size(11)
									.font_color(Colors.text_dim)
									.border({ color: Colors.border, left: 0, right: 0, top: 1, bottom: 0 })
									.child_align({ x: Start, y: Center }),
							},
							[text(if command_mode "Up/Down: Navigate   Enter: Run   Esc: Close" else "Up/Down: Navigate   Enter: Open   Esc: Close")],
						),
					],
				),
			],
		)
	}

	Model : [Closed, Open(Commands.LauncherState), KeybindsOpen]
	PaletteCommand : Commands.PaletteCommand

	Msg : [
	ShowFileFinder,
	ShowCommandPalette,
	ShowKeybinds,
	Hide,
	SetQuery(Widget.TextInputState),
	Select(U64),
	ChooseFile(Str),
	Execute(Commands.PaletteCommand),
]

	init : Model
	init = Closed

	update : Model, Msg -> Model
	update = |model, message| match message {
	ShowFileFinder => Open({ query: { value: "", cursor: 0 }, selected: 0 })
	ShowCommandPalette => Open({ query: { value: ">", cursor: 1 }, selected: 0 })
	ShowKeybinds => KeybindsOpen
	Hide => Closed
	SetQuery(query) => match model { Open(state) => Open({ ..state, query, selected: 0 }), _ => model }
	Select(selected) => match model { Open(state) => Open({ ..state, selected }), _ => model }
	ChooseFile(_) => Closed
	Execute(_) => model
}

	view : Font, List(Workspace.Node), Explorer.Icons, Model -> View(Msg)
	view = |font, nodes, icons, model| match model {
	Closed => box({ style: |_| style.width(Fixed(0)).height(Fixed(0)) }, [])
	Open(state) => overlay_view(font, nodes, icons, state) |> map(|message| match message {
		QueryChanged(query) => SetQuery(query)
		Select(index) => Select(index)
		Choose(choice) => match choice { FileChoice(path) => ChooseFile(path), CommandChoice(command) => Execute(command) }
		Dismiss => Hide
	})
	KeybindsOpen => Keybinds.view(font) |> map(|message| match message { Dismiss => Hide })
}

}

collect_files : List(Workspace.Node) -> List(CommandPalette.FileEntry)
collect_files = |nodes| nodes.map(
	|node| match node {
		File(file) => [{ path: file.path, name: file.name }]
		Directory(dir) => collect_files(dir.children)
	},
).join()

normalize_selection : U64, U64 -> U64
normalize_selection = |selected, count| if count == 0 0 else U64.min(selected, count - 1)

next_selection : U64, U64 -> U64
next_selection = |selected, count| if count == 0 0 else (selected + 1) % count

previous_selection : U64, U64 -> U64
previous_selection = |selected, count| if count == 0 0 else if selected == 0 count - 1 else selected - 1

choice_for : CommandPalette.Result -> CommandPalette.Choice
choice_for = |result| match result {
	FileResult(entry) => FileChoice(entry.path)
	CommandResult(entry) => CommandChoice(entry.command)
}

input_messages : List(CommandPalette.Result), U64, Widget.TextInputState, Devices.Snapshot -> List(CommandPalette.OverlayMsg)
input_messages = |results, selected, query, input| {
	count = results.len()
	var $messages = []
	control_keys = text_control_keys(input)
	if !input.text_input.is_empty() or !control_keys.is_empty() {
		next_query = Widget.update_text_input(query, { codepoints: input.text_input, keys: control_keys })
		$messages = $messages.append(QueryChanged(next_query))
	}
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
		$messages = match results.get(selected) {
			Ok(result) => $messages.append(Choose(choice_for(result)))
			Err(_) => $messages
		}
	}
	$messages
}

text_control_keys : Devices.Snapshot -> List(Event.TextControlKey)
text_control_keys = |input| {
	var $keys = []
	if Keys.key_pressed(input, KeyLeft) {
		$keys = $keys.append(KeyLeft)
	}
	if Keys.key_pressed(input, KeyRight) {
		$keys = $keys.append(KeyRight)
	}
	if Keys.key_pressed(input, KeyHome) {
		$keys = $keys.append(KeyHome)
	}
	if Keys.key_pressed(input, KeyEnd) {
		$keys = $keys.append(KeyEnd)
	}
	if Keys.key_pressed(input, KeyBackspace) {
		$keys = $keys.append(KeyBackspace)
	}
	if Keys.key_pressed(input, KeyDelete) {
		$keys = $keys.append(KeyDelete)
	}
	$keys
}

results_view : List(CommandPalette.Result), U64, Explorer.Icons, Bool -> View(CommandPalette.OverlayMsg)
results_view = |results, selected, icons, command_mode| {
	children = if results.is_empty() {
		[
			box(
				{ style: |_| style.width(Grow({})).height(Fixed(64)).font_color(Colors.text_dim).child_align({ x: Center, y: Center }) },
				[text(if command_mode "No matching commands" else "No matching files")],
			),
		]
	} else {
		results.map_with_index(|result, index| result_row(result, index, index == selected, icons.file))
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
				.border({ color: Colors.border, left: 0, right: 0, top: 1, bottom: 0 }),
		},
		children,
	)
}

result_row : CommandPalette.Result, U64, Bool, Assets.Texture -> View(CommandPalette.OverlayMsg)
result_row = |result, index, selected, file_icon| {
	choice = choice_for(result)
	(label, detail, row_id) = match result {
		FileResult(entry) => (entry.path, "", "file:${entry.path}")
		CommandResult(entry) => (entry.title, "${entry.shortcut}", "command:${entry.category}:${entry.title}")
	}
	events : List(Event.Handler(CommandPalette.OverlayMsg))
	events = [OnClick(Choose(choice)), OnPointerEnter(Select(index))]
	leading = match result {
		FileResult(_) => box(
			{ style: |_| style.width(Fixed(18)).height(Fixed(18)).child_align({ x: Center, y: Center }), events },
			[image(file_icon, { width: Pixels(16), height: Pixels(16) })],
		)
		CommandResult(_) => box(
			{ style: |_| style.width(Fixed(18)).height(Fixed(18)).font_color(Colors.accent).child_align({ x: Center, y: Center }), events },
			[text(">")],
		)
	}
	box(
		{
			id: Id("quick-open:${row_id}"),
			style: |status| style
				.width(Grow({}))
				.height(Fit({}))
				.pad(4, 4, 4, 4)
				.gap(4)
				.font_size(13)
				.font_color(if selected Colors.text else Colors.text_dim)
				.background(if selected Colors.surface_active else if status.hovered Colors.surface_hover else Colors.tab_bar)
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
				{ style: |_| style.width(Fit({})).height(Fit({})).font_size(11).pad(0, 4, 0, 0).font_color(Colors.text_dim), events },
				[text(detail)],
			),
		],
	)
}

expect CommandPalette.is_command_query(">close")
expect !CommandPalette.is_command_query("close")
expect CommandPalette.command_query(">keyboard") == "keyboard"

expect {
	nodes : List(Workspace.Node)
	nodes = [File({ path: "index.html", name: "index.html" })]
	CommandPalette.results(nodes, "INDEX").map(choice_for) == [FileChoice("index.html")]
		and CommandPalette.results(nodes, ">keyboard").map(choice_for) == [CommandChoice(ShowKeyboardShortcuts)]
}

expect {
	results : List(CommandPalette.Result)
	results = [FileResult({ path: "a.html", name: "a.html" }), FileResult({ path: "b.html", name: "b.html" })]
	query = { value: "", cursor: 0 }
	input_messages(results, 0, query, Devices.none.with_key_pressed(KeyDown)) == [Select(1)]
		and input_messages(results, 1, query, Devices.none.with_key_pressed(KeyEnter)) == [Choose(FileChoice("b.html"))]
			and input_messages(results, 0, query, Devices.none.with_text_input([62])) == [QueryChanged({ value: ">", cursor: 1 })]
}
