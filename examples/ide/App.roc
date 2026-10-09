## Durable IDE example state, messages, and application theme.
import rr.Font
import rr.App as RayApp
import rr.Assets
import rr.Capture
import rr.Devices
import rr.Draw
import tc.Element exposing [box, map, style]
import tc.Event
import tc.Program exposing [View]

import ui/CommandPalette
import ui/Editor
import ui/Explorer
import ui/StatusBar
import ui/Topbar
import Theme

App := [].{
	Model : {
		explorer : Explorer.Model,
		editor : Editor.Model,
		font : Font,
		code_font : Font,
		command_palette : CommandPalette.Model,
	}

	Msg : [
		TopbarMessage(Topbar.Msg),
		ExplorerMessage(Explorer.Msg),
		EditorMessage(Editor.Msg),
		CommandPaletteMessage(CommandPalette.Msg),
	]

	theme = Theme.theme

	workspace_dir = "examples/ide/workspace"
	assets_path = "examples/ide/assets"

	capture_recording = Capture.default
		.with_path("ide.png")
		.with_format(Png)
		.with_max_frames(1)
		.with_scale(Full)
		.with_timing(FixedStep)

	init! : RayApp.InitCallback(
		Model,
		[
			PermissionDenied, PathInvalid, NotFound, NotADirectory, AccessRefused,
			OpenFailed, Unavailable, ReadFailed, Busy, TooLarge, NotUtf8,
			NoSpace, WriteFailed,
			AssetPathInvalid, AssetNotFound, AssetReadFailed, FontLoadFailed,
			RootNotFound, RootNotDirectory, RootUnreadable, InvalidExpectedContentHash,
			ManifestMissing, ManifestUnreadable, ManifestMalformed, AssetSetMismatch,
			SchemaMismatch, ContentVersionMismatch, ContentHashMismatch,
			TextureLoadFailed, ResourceLimit,
		],
	)
	init! = |io| {
		if io.args!().contains("--capture") {
			_ = io.capture().start!(capture_recording) ? |_| Exit(1)
		}
		workspace = io.files().open_dir!(workspace_dir)?
		read_workspace = io.files().open_dir_read!(workspace_dir)?
		font = io.default_font!()?
		assets = Assets.open!(io.files().open_dir_read!(assets_path)?, IgnoreManifest)?
		code_font = Draw.load_store_font!(assets, { path: "JetBrainsMono-Regular.ttf", size: 36 })?
		explorer = Explorer.init!(read_workspace, assets)?
		editor = Editor.init!(workspace, "index.html")?
		Ok({ explorer, editor, font, code_font, command_palette: CommandPalette.init })
	}

	update! : Model, Msg, RayApp.Io, RayApp.Input(Msg) => Model
	update! = |model, message, _io, input| match message {
		TopbarMessage(ShowCommands) => { ..model, command_palette: CommandPalette.update(model.command_palette, ShowCommandPalette) }
		ExplorerMessage(Open(path)) => update_editor!(model, Open(path), input)
		ExplorerMessage(explorer_message) => { ..model, explorer: Explorer.update(model.explorer, explorer_message) }
		EditorMessage(editor_message) => update_editor!(model, editor_message, input)
		CommandPaletteMessage(palette_message) => handle_command_palette!(model, palette_message, input)
	}

	execute_command! : Model, CommandPalette.Command, RayApp.Input(Msg) => Model
	execute_command! = |model, command, input| match command {
		ShowCommandPalette => { ..model, command_palette: CommandPalette.update(model.command_palette, ShowCommandPalette) }
		FindFile => { ..model, command_palette: CommandPalette.update(model.command_palette, ShowFileFinder) }
		ShowKeyboardShortcuts => { ..model, command_palette: CommandPalette.update(model.command_palette, ShowKeybinds) }
		CloseActiveEditor => {
			closed = { ..model, command_palette: CommandPalette.update(model.command_palette, Hide) }
			update_editor!(closed, CloseActive, input)
		}
		SaveFile => update_editor!(model, SaveActive, input)
	}

	handle_command_palette! : Model, CommandPalette.Msg, RayApp.Input(Msg) => Model
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

	update_editor! : Model, Editor.Msg, RayApp.Input(Msg) => Model
	update_editor! = |model, message, input| {
		editor = Editor.update!(model.editor, message, input, |editor_message| EditorMessage(editor_message))
		{ ..model, editor }
	}

	view : Model -> View(Msg)
	view = |model| {
		content = [
			Topbar.view(CommandPalette.shortcut_for(ShowCommandPalette)) |> map(|message| TopbarMessage(message)),
			box({ style: |_| style.direction(Row) }, [
				Explorer.view(model.explorer, model.editor.active) |> map(|message| ExplorerMessage(message)),
				Explorer.splitter(model.explorer) |> map(|message| ExplorerMessage(message)),
				Editor.view(model.code_font, model.editor) |> map(|message| EditorMessage(message)),
			]),
			StatusBar.view(model.editor),
		]
		children = match model.command_palette {
			Closed => content
			_ => content.append(CommandPalette.view(model.font, model.explorer.tree, model.explorer.icons, model.command_palette) |> map(|message| CommandPaletteMessage(message)))
		}
		box({
			style: |_| style.direction(Col).background(theme.palette.surface.base.fill).font_family(model.font).font_size(14).font_color(theme.palette.surface.base.content),
			events: [OnInput(Box.box(shortcut_messages))],
		}, children)
	}

}

shortcut_messages : Devices.Snapshot, Event.ElementBounds -> List(App.Msg)
shortcut_messages = |input, _bounds| CommandPalette.commands_for_input(input).map(|command| CommandPaletteMessage(Execute(command)))
