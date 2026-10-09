## Sev-inspired read-only IDE example.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst",
	tc: "../../package/main.roc",
}

import rr.App as RayApp
import rr.Assets
import rr.Capture
import rr.Devices
import rr.Files
import rr.Font
import rr.Keys
import tc.Element exposing [box, map, style]
import tc.Event
import tc.Program

import App
import ui/Colors
import ui/Editor
import ui/Explorer
import ui/Keybinds
import ui/QuickOpen
import ui/StatusBar
import ui/Topbar

Model : Program.State(App.Model, App.Msg)

Msg : App.Msg

workspace_dir = "examples/ide/workspace"

font_path = "examples/ide/Inter-Regular.ttf"

assets_path = "examples/ide/assets"

capture_recording = Capture.default
	.with_path("ide.png")
	.with_format(Png)
	.with_max_frames(1)
	.with_scale(Full)
	.with_timing(FixedStep)

configure : List(Str) -> RayApp.Config
configure = |_args| {
	RayApp.default
		.with_title("Terrocotta IDE")
		.with_size({ width: 1280, height: 800 })
		.with_resizable(True)
		.with_exit_key(NoExitKey)
		.with_permission(Directory("examples/ide", ReadOnly))
		.with_default_font({ path: font_path, size: 36 })
		.with_output_dir("captures")
		.with_frame_pacing(Uncapped)
}

init! : RayApp.InitCallback(
	App.Model,
	[
		PermissionDenied,
		PathInvalid,
		NotFound,
		NotADirectory,
		AccessRefused,
		OpenFailed,
		Unavailable,
		ReadFailed,
		Busy,
		TooLarge,
		NotUtf8,
		AssetPathInvalid,
		AssetNotFound,
		AssetReadFailed,
		FontLoadFailed,
		RootNotFound,
		RootNotDirectory,
		RootUnreadable,
		InvalidExpectedContentHash,
		ManifestMissing,
		ManifestUnreadable,
		ManifestMalformed,
		AssetSetMismatch,
		SchemaMismatch,
		ContentVersionMismatch,
		ContentHashMismatch,
		TextureLoadFailed,
		ResourceLimit,
	],
)
init! = |io| {
    if io.args!().contains("--capture") {
		_ = io.capture().start!(capture_recording) ? |_| Exit(1)
	}
	workspace = io.files().open_dir_read!(workspace_dir)?
	font = io.default_font!()?
	assets = Assets.open!(io.files().open_dir_read!(assets_path)?, IgnoreManifest)?
	explorer = Explorer.init!(workspace, assets)?
	editor = Editor.init!(workspace, "index.html")?
	Ok({
		explorer,
		editor,
		font,
		overlay: OverlayClosed,
	})
}

update! : App.Model, App.Msg, RayApp.Io, RayApp.Input(App.Msg) => App.Model
update! = |model, message, _io, input| match message {
	TopbarMessage(ShowCommands) => { ..model, overlay: QuickOpen(command_launcher_state) }

	ExplorerMessage(Open(path)) => update_editor!(model, Open(path), input)

	ExplorerMessage(explorer_message) => { ..model, explorer: Explorer.update(model.explorer, explorer_message) }

	EditorMessage(editor_message) => update_editor!(model, editor_message, input)

	ShowFileFinder => {
		..model,
		overlay: QuickOpen(empty_launcher_state),
	}

	ShowCommandPalette => { ..model, overlay: QuickOpen(command_launcher_state) }

	ShowKeybinds => { ..model, overlay: KeybindsOpen }

	HideOverlay => { ..model, overlay: OverlayClosed }

	SetQuickOpenQuery(query) => match model.overlay {
		QuickOpen(state) => { ..model, overlay: QuickOpen({ ..state, query, selected: 0 }) }
		_ => model
	}

	SelectQuickOpen(selected) => match model.overlay {
		QuickOpen(state) => { ..model, overlay: QuickOpen({ ..state, selected }) }
		_ => model
	}

	ChooseFile(path) => update_editor!({ ..model, overlay: OverlayClosed }, Open(path), input)

	ExecuteCommand(command) => execute_command!(model, command, input)

}

empty_launcher_state : App.LauncherState
empty_launcher_state = { query: { value: "", cursor: 0 }, selected: 0 }

command_launcher_state : App.LauncherState
command_launcher_state = { query: { value: ">", cursor: 1 }, selected: 0 }

execute_command! : App.Model, App.PaletteCommand, RayApp.Input(App.Msg) => App.Model
execute_command! = |model, command, input| match command {
	FindFile => { ..model, overlay: QuickOpen(empty_launcher_state) }
	ShowKeyboardShortcuts => { ..model, overlay: KeybindsOpen }
	CloseActiveEditor => {
		closed = { ..model, overlay: OverlayClosed }
		update_editor!(closed, CloseActive, input)
	}
}

update_editor! : App.Model, Editor.Msg, RayApp.Input(App.Msg) => App.Model
update_editor! = |model, message, input| {
	editor = Editor.update!(model.editor, message, input, |editor_message| EditorMessage(editor_message))
	{ ..model, editor }
}

view : App.Model -> Program.View(App.Msg)
view = |model| {
	content = [
		Topbar.view |> map(|message| TopbarMessage(message)),
		box(
			{ style: |_| style.direction(Row) },
			[
				Explorer.view(model.explorer, model.editor.active) |> map(|message| ExplorerMessage(message)),
				Explorer.splitter(model.explorer) |> map(|message| ExplorerMessage(message)),
				Editor.view(model.font, model.editor) |> map(|message| EditorMessage(message)),
			],
		),
		StatusBar.view(model.editor),
	]

	children = match model.overlay {
		OverlayClosed => content
		QuickOpen(state) => content.append(QuickOpen.view(model.font, model.explorer.tree, model.explorer.icons, state) |> map(quick_open_message))
		KeybindsOpen => content.append(Keybinds.view(model.font) |> map(keybinds_message))
	}

	box(
		{
			style: |_| style
				.direction(Col)
				.background(Colors.window)
				.font_family(model.font)
				.font_size(14)
				.font_color(Colors.text),
			events: [
				OnInput(Box.box(shortcut_messages)),
			],
		},
		children,
	)
}

shortcut_messages : Devices.Snapshot, Event.ElementBounds -> List(App.Msg)
shortcut_messages = |input, _bounds| {
	modifier_down = Keys.key_down(input, KeyLeftSuper)
		or Keys.key_down(input, KeyRightSuper)
			or Keys.key_down(input, KeyLeftControl)
				or Keys.key_down(input, KeyRightControl)
	shift_down = Keys.key_down(input, KeyLeftShift) or Keys.key_down(input, KeyRightShift)
	if modifier_down and Keys.key_pressed(input, KeyP) {
		if shift_down [ShowCommandPalette] else [ShowFileFinder]
	} else if modifier_down and Keys.key_pressed(input, KeyK) {
		[ShowKeybinds]
	} else if modifier_down and !shift_down and Keys.key_pressed(input, KeyW) {
		[ExecuteCommand(CloseActiveEditor)]
	} else {
		[]
	}
}

quick_open_message : QuickOpen.Msg -> App.Msg
quick_open_message = |message| match message {
	QueryChanged(query) => SetQuickOpenQuery(query)
	Select(index) => SelectQuickOpen(index)
	Choose(choice) => match choice {
		FileChoice(path) => ChooseFile(path)
		CommandChoice(command) => ExecuteCommand(command)
	}
	Dismiss => HideOverlay
}

keybinds_message : Keybinds.Msg -> App.Msg
keybinds_message = |message| match message {
	Dismiss => HideOverlay
}

program = Program.new(configure, init!, update!, view)

expect {
	bounds = { x: 0, y: 0, width: 1280, height: 800 }
	command_input = Devices.none.with_key_down(KeyLeftSuper).with_key_down(KeyLeftShift).with_key_pressed(KeyP)
	file_input = Devices.none.with_key_down(KeyLeftSuper).with_key_pressed(KeyP)
	keybinds_input = Devices.none.with_key_down(KeyLeftControl).with_key_pressed(KeyK)
	close_input = Devices.none.with_key_down(KeyLeftSuper).with_key_pressed(KeyW)
	shortcut_messages(command_input, bounds) == [ShowCommandPalette]
		and shortcut_messages(file_input, bounds) == [ShowFileFinder]
			and shortcut_messages(keybinds_input, bounds) == [ShowKeybinds]
				and shortcut_messages(close_input, bounds) == [ExecuteCommand(CloseActiveEditor)]
}
