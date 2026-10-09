## Editor state, file loading, tabs, and source surface.
import rr.App as RayApp
import rr.Files
import rr.Font
import rr.Task
import tc.Element exposing [box, map, style, text]
import tc.Program exposing [View]

import ../Theme exposing [theme]
import ../syntax/Html
import CodeEditor
import Tabs

Editor := [].{
	Language : [HtmlLanguage, PlainText]

	Document : CodeEditor.Document

	DocumentError : [UnsupportedByte({ offset : U64, byte : U8 })]

	TabId : U64

	SaveState : [Idle, Saving(Str), SaveFailed(Str)]

	LoadedFile : {
		buffer : Document,
		persisted : Str,
		save : SaveState,
	}

	FileState : [Loading, LoadFailed(Str), Loaded(LoadedFile)]

	Tab : {
		id : TabId,
		path : Str,
		file : FileState,
	}

	Active : [NoActiveTab, ActiveTab(TabId)]

	Model : {
		workspace : Files.Dir,
		tabs : List(Tab),
		active : Active,
		next_tab_id : TabId,
	}

	Msg : [Open(Str), FileLoaded(TabId, Try(Str, Files.ReadTextError)), ActivateTab(TabId), CloseTab(TabId), CloseActive, SaveActive, FileSaved(TabId, Str, Try({}, Files.WriteError)), CodeEdit(TabId, CodeEditor.Msg)]

	active_path : Model -> [NoActiveTab, ActiveTab(Str)]
	active_path = model_active_path

	init! : Files.Dir, Str => Try(Model, Files.ReadTextError)
	init! = |workspace, initial_path| {
		initial_content = workspace.read_text!(initial_path)?
		initial_tab : Tab
		initial_tab = {
			id: 0,
			path: initial_path,
			file: match document(initial_path, initial_content) {
				Ok(buffer) => Loaded({ buffer, persisted: initial_content, save: Idle })
				Err(error) => LoadFailed(document_error(error))
			},
		}
		Ok({ workspace, tabs: [initial_tab], active: ActiveTab(0), next_tab_id: 1 })
	}

	update! : Model, Msg, RayApp.Input(msg), (Msg -> msg) => Model
	update! = |model, message, input, map_msg| match message {
		Open(path) => match model.tabs.find_first(|tab| tab.path == path) {
			Ok(tab) => { ..model, active: ActiveTab(tab.id) }
			Err(_) => {
				id = model.next_tab_id
				workspace = model.workspace
				Task.spawn_with!(input, || FileLoaded(id, workspace.read_text!(path)), map_msg)
				tab : Tab
				tab = { id, path, file: Loading }
				{ ..model, tabs: model.tabs.append(tab), active: ActiveTab(id), next_tab_id: id + 1 }
			}
		}
		FileLoaded(id, result) => file_loaded(model, id, result)
		CodeEdit(id, code_message) => edit_document(model, id, code_message)
		SaveActive => save_active!(model, input, map_msg)
		FileSaved(id, snapshot, result) => file_saved(model, id, snapshot, result)
		ActivateTab(id) => if model.tabs.any(|tab| tab.id == id) { ..model, active: ActiveTab(id) } else model
		CloseTab(id) => close_editor(model, id)
		CloseActive => match model.active {
			NoActiveTab => model
			ActiveTab(id) => close_editor(model, id)
		}
	}

	view : Font, Model -> View(Msg)
	view = |font, model| {
		source = match active_tab(model) {
			Ok(tab) => match tab.file {
				Loaded(loaded) => CodeEditor.view(font, loaded.buffer) |> map(|message| CodeEdit(tab.id, message))
				Loading => box({ style: |_| style.width(Grow({})).height(Grow({})).child_align({ x: Center, y: Center }) }, [])
				LoadFailed(message) => box(
					{ style: |_| style.width(Grow({})).height(Grow({})).pad(theme.gap * 2, theme.gap * 2, theme.gap * 2, theme.gap * 2).font_color(theme.palette.danger.base.fill).child_align({ x: Center, y: Center }) },
					[text(message)],
				)
			}
			Err(_) => box({ style: |_| style.width(Grow({})).height(Grow({})).child_align({ x: Center, y: Center }) }, [])
		}
		box(
			{ style: |_| style.direction(Col).background(theme.palette.surface.base.fill) },
			[
				Tabs.view(
					model.tabs.map(|tab| {
						id: tab.id,
						title: basename(tab.path),
						dirty: is_dirty(tab),
						loading: match tab.file { Loading => Bool.True, _ => Bool.False },
					}),
					model.active,
				) |> map(|message| match message {
					Activate(id) => ActivateTab(id)
					Close(id) => CloseTab(id)
				}),
				source,
			],
		)
	}
}

document : Str, Str -> Try(Editor.Document, Editor.DocumentError)
document = |path, content| {
	validate_ascii(content)?
	language = language_for(path)
	lines = match language { HtmlLanguage => Html.highlight(content), PlainText => Html.plain(content) }
	Ok({ content, language, lines, cursor: { line: 0, column: 0 } })
}

validate_ascii : Str -> Try({}, Editor.DocumentError)
validate_ascii = |content| {
	var $offset = 0
	for byte in content.to_utf8() {
		if byte != 10 and (byte < 32 or byte > 126) {
			return Err(UnsupportedByte({ offset: $offset, byte }))
		}
		$offset = $offset + 1
	}
	Ok({})
}

document_error : Editor.DocumentError -> Str
document_error = |error| match error {
	UnsupportedByte({ offset, byte }) => "Cannot open this file: byte ${byte.to_str()} at offset ${offset.to_str()} is not printable ASCII or LF."
}

file_loaded : Editor.Model, Editor.TabId, Try(Str, Files.ReadTextError) -> Editor.Model
file_loaded = |model, id, result| {
	tabs = model.tabs.map(|tab| if tab.id == id {
		match tab.file {
			Loading => {
				file = match result {
					Ok(content) => match document(tab.path, content) {
						Ok(buffer) => Loaded({ buffer, persisted: content, save: Idle })
						Err(error) => LoadFailed(document_error(error))
					}
					Err(error) => LoadFailed(read_error(error))
				}
				{ ..tab, file }
			}
			_ => tab
		}
	} else tab)
	{ ..model, tabs }
}

edit_document : Editor.Model, Editor.TabId, CodeEditor.Msg -> Editor.Model
edit_document = |model, id, message| {
	tabs = model.tabs.map(|tab| if tab.id == id {
		match tab.file {
			Loaded(loaded) => { ..tab, file: Loaded({ ..loaded, buffer: CodeEditor.update(loaded.buffer, message) }) }
			_ => tab
		}
	} else tab)
	{ ..model, tabs }
}

save_active! : Editor.Model, RayApp.Input(msg), (Editor.Msg -> msg) => Editor.Model
save_active! = |model, input, map_msg| match active_tab(model) {
	Err(_) => model
	Ok(tab) => match tab.file {
		Loaded(loaded) => match loaded.save {
			Saving(_) => model
			Idle | SaveFailed(_) => if loaded.buffer.content == loaded.persisted {
				model
			} else {
				workspace = model.workspace
				id = tab.id
				path = tab.path
				snapshot = loaded.buffer.content
				Task.spawn_with!(input, || FileSaved(id, snapshot, workspace.write_text!(path, snapshot)), map_msg)
				mark_saving(model, id, snapshot)
			}
		}
		_ => model
	}
}

mark_saving : Editor.Model, Editor.TabId, Str -> Editor.Model
mark_saving = |model, id, snapshot| {
	tabs = model.tabs.map(|tab| if tab.id == id {
		match tab.file {
			Loaded(loaded) => { ..tab, file: Loaded({ ..loaded, save: Saving(snapshot) }) }
			_ => tab
		}
	} else tab)
	{ ..model, tabs }
}

file_saved : Editor.Model, Editor.TabId, Str, Try({}, Files.WriteError) -> Editor.Model
file_saved = |model, id, snapshot, result| {
	tabs = model.tabs.map(|tab| if tab.id == id {
		match tab.file {
			Loaded(loaded) => match loaded.save {
				Saving(expected) if expected == snapshot => match result {
					Ok(_) => { ..tab, file: Loaded({ ..loaded, persisted: snapshot, save: Idle }) }
					Err(error) => { ..tab, file: Loaded({ ..loaded, save: SaveFailed(write_error(error)) }) }
				}
				_ => tab
			}
			_ => tab
		}
	} else tab)
	{ ..model, tabs }
}

is_dirty : Editor.Tab -> Bool
is_dirty = |tab| match tab.file {
	Loaded(loaded) => loaded.buffer.content != loaded.persisted
	_ => Bool.False
}

basename : Str -> Str
basename = |path| match path.split_last("/") { Ok(parts) => parts.after, Err(_) => path }

language_for : Str -> Editor.Language
language_for = |path| {
	lower = path.with_ascii_lowercased()
	if lower.ends_with(".html") or lower.ends_with(".htm") HtmlLanguage else PlainText
}

active_tab : Editor.Model -> Try(Editor.Tab, [NoTab])
active_tab = |model| match model.active {
	NoActiveTab => Err(NoTab)
	ActiveTab(id) => model.tabs.find_first(|tab| tab.id == id).map_err(|_| NoTab)
}

model_active_path : Editor.Model -> [NoActiveTab, ActiveTab(Str)]
model_active_path = |model| match active_tab(model) {
	Ok(tab) => ActiveTab(tab.path)
	Err(_) => NoActiveTab
}

read_error : Files.ReadTextError -> Str
read_error = |error| match error {
	PermissionDenied => "Permission denied"
	PathInvalid => "The workspace path is invalid"
	NotFound => "The file no longer exists"
	ReadFailed => "The file could not be read"
	Busy => "The file service is busy"
	Unavailable => "The file service is unavailable"
	TooLarge => "This example opens files up to 64 KiB"
	NotUtf8 => "This file is not valid UTF-8"
}

write_error : Files.WriteError -> Str
write_error = |error| match error {
	PermissionDenied => "Permission denied"
	PathInvalid => "The workspace path is invalid"
	NotFound => "The file no longer exists"
	AccessRefused => "The file could not be replaced"
	NoSpace => "There is no space left to save the file"
	WriteFailed => "The file could not be written"
	Unavailable => "The file service is unavailable"
}

close_editor : Editor.Model, Editor.TabId -> Editor.Model
close_editor = |model, id| match tab_index(model.tabs, id, 0) {
	Err(_) => model
	Ok(index) => {
		tabs = model.tabs.drop_at(index)
		active = if model.active != ActiveTab(id) {
			model.active
		} else {
			match tabs.get(index) {
				Ok(tab) => ActiveTab(tab.id)
				Err(_) => match tabs.last() {
					Ok(tab) => ActiveTab(tab.id)
					Err(_) => NoActiveTab
				}
			}
		}
		{ ..model, tabs, active }
	}
}

tab_index : List(Editor.Tab), Editor.TabId, U64 -> Try(U64, [NotFound])
tab_index = |tabs, id, index| {
	if index >= tabs.len() {
		Err(NotFound)
	} else {
		match tabs.get(index) {
			Ok(tab) => if tab.id == id Ok(index) else tab_index(tabs, id, index + 1)
			Err(_) => Err(NotFound)
		}
	}
}

test_buffer : Str -> Editor.Document
test_buffer = |content| { content, language: PlainText, lines: Html.plain(content), cursor: { line: 0, column: 0 } }

test_tab : Editor.TabId, Str -> Editor.Tab
test_tab = |id, path| { id, path, file: LoadFailed("test") }

test_loaded_tab : Editor.TabId, Str, Str, Str, Editor.SaveState -> Editor.Tab
test_loaded_tab = |id, path, content, persisted, save| { id, path, file: Loaded({ buffer: test_buffer(content), persisted, save }) }

test_model : List(Editor.Tab), Editor.Active, Editor.TabId -> Editor.Model
test_model = |tabs, active, next_tab_id| { workspace: Files.Dir.stub, tabs, active, next_tab_id }

expect language_for("INDEX.HTML") == HtmlLanguage
expect language_for("assets/site.css") == PlainText
expect basename("components/card.html") == "card.html"

expect match document("notes.txt", "printable ASCII\nand LF") {
	Ok(loaded) => loaded.content == "printable ASCII\nand LF"
	Err(_) => Bool.False
}

expect match document("notes.txt", "a\tb") {
	Err(UnsupportedByte({ offset, byte })) => offset == 1 and byte == 9
	_ => Bool.False
}

expect match document("notes.txt", "a\r\nb") {
	Err(UnsupportedByte({ offset, byte })) => offset == 1 and byte == 13
	_ => Bool.False
}

expect match document("notes.txt", "café") {
	Err(UnsupportedByte({ offset, byte })) => offset == 3 and byte == 195
	_ => Bool.False
}

expect document_error(UnsupportedByte({ offset: 3, byte: 195 })) == "Cannot open this file: byte 195 at offset 3 is not printable ASCII or LF."

expect {
	model = test_model([test_tab(1, "a.html"), test_tab(2, "b.html"), test_tab(3, "c.html")], ActiveTab(2), 4)
	closed = close_editor(model, 2)
	closed.tabs.map(|tab| tab.path) == ["a.html", "c.html"] and closed.active == ActiveTab(3)
}

expect {
	model = test_model([test_tab(1, "a.html"), test_tab(2, "b.html")], ActiveTab(2), 3)
	closed = close_editor(model, 2)
	closed.tabs.map(|tab| tab.path) == ["a.html"] and closed.active == ActiveTab(1)
}

expect {
	model = test_model([test_tab(1, "a.html")], ActiveTab(1), 2)
	closed = close_editor(model, 1)
	closed.tabs.is_empty() and closed.active == NoActiveTab
}

expect {
	tab = test_loaded_tab(7, "a.html", "edited back", "edited back", Idle)
	!is_dirty(tab)
}

expect {
	model = test_model([test_loaded_tab(7, "a.html", "newer edit", "old", Saving("written snapshot"))], ActiveTab(7), 8)
	updated = file_saved(model, 7, "written snapshot", Ok({}))
	match updated.tabs.get(0) {
		Ok(tab) => match tab.file {
			Loaded(loaded) => loaded.persisted == "written snapshot" and loaded.buffer.content == "newer edit" and loaded.save == Idle and is_dirty(tab)
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

expect {
	model = test_model([test_loaded_tab(7, "a.html", "edited", "old", Saving("edited"))], ActiveTab(7), 8)
	updated = file_saved(model, 7, "edited", Err(NoSpace))
	match updated.tabs.get(0) {
		Ok(tab) => match tab.file {
			Loaded(loaded) => loaded.persisted == "old" and loaded.save == SaveFailed("There is no space left to save the file") and is_dirty(tab)
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

expect {
	reopened = test_model([{ id: 8, path: "a.html", file: Loading }], ActiveTab(8), 9)
	stale = file_loaded(reopened, 7, Ok("stale content"))
	match stale.tabs.get(0) {
		Ok(tab) => tab.file == Loading
		Err(_) => Bool.False
	}
}
