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

import App exposing [theme]
import ui/CommandPalette
import ui/Editor
import ui/Explorer
import ui/StatusBar
import ui/Topbar

Model : Program.State(AppModel, AppMsg)

Msg : AppMsg

AppModel : {
	explorer : Explorer.Model,
	editor : Editor.Model,
	font : Font,
	command_palette : CommandPalette.Model,
}

AppMsg : [
	TopbarMessage(Topbar.Msg),
	ExplorerMessage(Explorer.Msg),
	EditorMessage(Editor.Msg),
	CommandPaletteMessage(CommandPalette.Msg),
]

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
	AppModel,
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
		command_palette: CommandPalette.init,
	})
}

update! : AppModel, AppMsg, RayApp.Io, RayApp.Input(AppMsg) => AppModel
update! = |model, message, _io, input| match message {
	TopbarMessage(ShowCommands) => { ..model, command_palette: CommandPalette.update(model.command_palette, ShowCommandPalette) }

	ExplorerMessage(Open(path)) => update_editor!(model, Open(path), input)

	ExplorerMessage(explorer_message) => { ..model, explorer: Explorer.update(model.explorer, explorer_message) }

	EditorMessage(editor_message) => update_editor!(model, editor_message, input)

	CommandPaletteMessage(palette_message) => handle_command_palette!(model, palette_message, input)

}

execute_command! : AppModel, CommandPalette.PaletteCommand, RayApp.Input(AppMsg) => AppModel
execute_command! = |model, command, input| match command {
	FindFile => { ..model, command_palette: CommandPalette.update(model.command_palette, ShowFileFinder) }
	ShowKeyboardShortcuts => { ..model, command_palette: CommandPalette.update(model.command_palette, ShowKeybinds) }
	CloseActiveEditor => {
		closed = { ..model, command_palette: CommandPalette.update(model.command_palette, Hide) }
		update_editor!(closed, CloseActive, input)
	}
}

handle_command_palette! : AppModel, CommandPalette.Msg, RayApp.Input(AppMsg) => AppModel
handle_command_palette! = |model, message, input| match message {
	ShowFileFinder => { ..model, command_palette: CommandPalette.update(model.command_palette, message) }
	ShowCommandPalette => { ..model, command_palette: CommandPalette.update(model.command_palette, message) }
	ShowKeybinds => { ..model, command_palette: CommandPalette.update(model.command_palette, message) }
	Hide => { ..model, command_palette: CommandPalette.update(model.command_palette, message) }
	SetQuery(_) => { ..model, command_palette: CommandPalette.update(model.command_palette, message) }
	Select(_) => { ..model, command_palette: CommandPalette.update(model.command_palette, message) }
	ChooseFile(path) => update_editor!({ ..model, command_palette: CommandPalette.update(model.command_palette, message) }, Open(path), input)
	Execute(command) => execute_command!(model, command, input)
}

update_editor! : AppModel, Editor.Msg, RayApp.Input(AppMsg) => AppModel
update_editor! = |model, message, input| {
	editor = Editor.update!(model.editor, message, input, |editor_message| EditorMessage(editor_message))
	{ ..model, editor }
}

view : AppModel -> Program.View(AppMsg)
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

	children = match model.command_palette {
		Closed => content
		_ => content.append(CommandPalette.view(model.font, model.explorer.tree, model.explorer.icons, model.command_palette) |> map(|message| CommandPaletteMessage(message)))
	}

	box(
		{
			style: |_| style
				.direction(Col)
				.background(theme.palette.surface.base.fill)
				.font_family(model.font)
				.font_size(14)
				.font_color(theme.palette.surface.base.content),
			events: [
				OnInput(Box.box(shortcut_messages)),
			],
		},
		children,
	)
}

shortcut_messages : Devices.Snapshot, Event.ElementBounds -> List(AppMsg)
shortcut_messages = |input, _bounds| {
	modifier_down = Keys.key_down(input, KeyLeftSuper)
		or Keys.key_down(input, KeyRightSuper)
			or Keys.key_down(input, KeyLeftControl)
				or Keys.key_down(input, KeyRightControl)
	shift_down = Keys.key_down(input, KeyLeftShift) or Keys.key_down(input, KeyRightShift)
	if modifier_down and Keys.key_pressed(input, KeyP) {
		if shift_down [CommandPaletteMessage(ShowCommandPalette)] else [CommandPaletteMessage(ShowFileFinder)]
	} else if modifier_down and Keys.key_pressed(input, KeyK) {
		[CommandPaletteMessage(ShowKeybinds)]
	} else if modifier_down and !shift_down and Keys.key_pressed(input, KeyW) {
		[CommandPaletteMessage(Execute(CloseActiveEditor))]
	} else {
		[]
	}
}

program = Program.new(configure, init!, update!, view)

expect {
	bounds = { x: 0, y: 0, width: 1280, height: 800 }
	command_input = Devices.none.with_key_down(KeyLeftSuper).with_key_down(KeyLeftShift).with_key_pressed(KeyP)
	file_input = Devices.none.with_key_down(KeyLeftSuper).with_key_pressed(KeyP)
	keybinds_input = Devices.none.with_key_down(KeyLeftControl).with_key_pressed(KeyK)
	close_input = Devices.none.with_key_down(KeyLeftSuper).with_key_pressed(KeyW)
	shortcut_messages(command_input, bounds) == [CommandPaletteMessage(ShowCommandPalette)]
		and shortcut_messages(file_input, bounds) == [CommandPaletteMessage(ShowFileFinder)]
			and shortcut_messages(keybinds_input, bounds) == [CommandPaletteMessage(ShowKeybinds)]
				and shortcut_messages(close_input, bounds) == [CommandPaletteMessage(Execute(CloseActiveEditor))]
}
