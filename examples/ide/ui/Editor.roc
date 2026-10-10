import rr.App as RayApp
import rr.Assets
import rr.Draw
import rr.Files
import rr.Font
import rr.Task
import tc.Color
import tc.Element exposing [box, map, style, text]
import tc.Program exposing [View]

import ../source/Buffer
import ../Theme exposing [theme]
import ../source/Highlight
import CodeEditor

Editor := [].{
	DocumentError : [UnsupportedByte({ offset : U64, byte : U8 })]

	TabId : U64

	SaveState : [Idle, Saving(Str), SaveFailed(Str)]

	HistoryState : { cursor : U64, anchor : U64 }

	HistoryEntry : {
		forward : Buffer.Edit,
		inverse : Buffer.Edit,
		before : HistoryState,
		after : HistoryState,
	}

	History : {
		entries : List(HistoryEntry),
		position : U64,
	}

	LoadedFile : {
		buffer : Buffer,
		editor : CodeEditor.State,
		persisted : Str,
		save : SaveState,
		history : History,
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
		font : Font,
		metrics : CodeEditor.FontMetrics,
		tabs : List(Tab),
		active : Active,
		next_tab_id : TabId,
	}

	Msg : [Open(Str), FileLoaded(TabId, Try(Str, Files.ReadTextError)), ActivateTab(TabId), CloseTab(TabId), CloseActive, SaveActive, FileSaved(TabId, Try({}, Files.WriteError)), CodeEdit(TabId, CodeEditor.Msg)]

	active_path : Model -> [NoActiveTab, ActiveTab(Str)]
	active_path = model_active_path

	active_tab : Model -> Try(Tab, [NoTab])
	active_tab = find_active_tab

	init! : Files.Dir, Assets.Store, Str => Try(Model, [PermissionDenied, PathInvalid, NotFound, ReadFailed, Busy, Unavailable, TooLarge, NotUtf8, FontLoadFailed, ResourceLimit])
	init! = |workspace, assets, initial_path| {
		font = Draw.load_store_font!(assets, { path: "JetBrainsMono-Regular.ttf", size: 36 })?
		metrics = CodeEditor.metrics(font)
		initial_content = workspace.read_text!(initial_path)?
		initial_tab : Tab
		initial_tab = {
			id: 0,
			path: initial_path,
			file: match document(initial_path, initial_content) {
				Ok(buffer) => Loaded(loaded_file(buffer, initial_content))
				Err(error) => LoadFailed(document_error(error))
			},
		}
		Ok({ workspace, font, metrics, tabs: [initial_tab], active: ActiveTab(0), next_tab_id: 1 })
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
		FileSaved(id, result) => file_saved(model, id, result)
		ActivateTab(id) => if model.tabs.any(|tab| tab.id == id) { ..model, active: ActiveTab(id) } else model
		CloseTab(id) => close_editor(model, id)
		CloseActive => match model.active {
			NoActiveTab => model
			ActiveTab(id) => close_editor(model, id)
		}
	}

	view : Model -> View(Msg)
	view = |model| {
		source = match find_active_tab(model) {
			Ok(tab) => match tab.file {
				Loaded(loaded) => CodeEditor.view(model.font, model.metrics, loaded.buffer, loaded.editor) |> map(|message| CodeEdit(tab.id, message))
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
				tabs_view(model.tabs, model.active),
				source,
			],
		)
	}
}

tabs_view : List(Editor.Tab), Editor.Active -> View(Editor.Msg)
tabs_view = |tabs, active| box(
	{
		style: |_| style
			.height(Fit({}))
			.direction(Row)
			.child_align({ x: Start, y: Center })
			.background(inactive_surface)
			.overflow(Scroll, Hidden),
	},
	tabs.map(|tab| tab_view(tab, active == ActiveTab(tab.id))).append(box({ style: |_| style.border({ color: theme.palette.edge.border, left: 0, right: 0, top: 0, bottom: 1 }) }, [])),
)

tab_view : Editor.Tab, Bool -> View(Editor.Msg)
tab_view = |tab, active| box(
	{
		id: Id("tab:${tab.id.to_str()}"),
		style: |status| style
			.width(Fit({ min: 120, max: 220 }))
			.height(Fit({}))
			.pad(theme.gap, theme.gap, theme.gap, theme.gap + theme.gap / 2)
			.gap(theme.gap)
			.child_align({ x: Start, y: Center })
			.font_size(13)
			.font_color(if active theme.palette.surface.base.content else theme.palette.text.muted)
			.background(if active theme.palette.surface.base.fill else if status.hovered theme.palette.hovered(theme.palette.surface.base).fill else inactive_surface)
			.border({ color: theme.palette.edge.border, left: 0, right: 1, top: 0, bottom: if active 0 else 1 })
			.cursor(PointingHand),
		events: [OnClick(ActivateTab(tab.id))],
	},
	[
		box(
			{
				style: |_| style.width(Grow({ min: 70, max: 170 })).height(Fit({})).text_wrap(None).child_align({ x: Start, y: Center }),
				events: [OnClick(ActivateTab(tab.id))],
			},
			[text(tab_label(tab))],
		),
		box(
			{
				id: Id("tab-close:${tab.id.to_str()}"),
				style: |status| style
					.width(Fixed(20))
					.height(Fixed(20))
					.radius(3)
					.child_align({ x: Center, y: Center })
					.background(if status.hovered theme.palette.selected(theme.palette.surface.base).fill else inactive_surface)
					.cursor(PointingHand),
				events: [OnClick(CloseTab(tab.id))],
			},
			[text("x")],
		),
	],
)

## Keep inactive tabs close to the editor surface. The theme's built-in
## subtle surface is intentionally stronger (about 10% toward text).
inactive_surface : Color
inactive_surface = Color.mix(theme.palette.surface.base.fill, theme.palette.surface.base.content, 12)

tab_label : Editor.Tab -> Str
tab_label = |tab| {
	title = basename(tab.path)
	match tab.file {
		Loading => "${title}  ..."
		_ => if is_dirty(tab) "${title} *" else title
	}
}

document : Str, Str -> Try(Buffer, Editor.DocumentError)
document = |path, content| {
	validate_ascii(content)?
	Ok(Buffer.from_path(path, content))
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
						Ok(buffer) => Loaded(loaded_file(buffer, content))
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
			Loaded(loaded) => {
				outcome = CodeEditor.update(model.metrics, loaded.buffer, loaded.editor, message)
				next = match outcome.operation {
					NoOperation => { ..loaded, editor: outcome.state }
					Replace(edit) => apply_new_edit(loaded, outcome.state, edit)
					Undo => undo_edit(loaded)
					Redo => redo_edit(loaded)
				}
				{ ..tab, file: Loaded(next) }
			}
			_ => tab
		}
	} else tab)
	{ ..model, tabs }
}

loaded_file : Buffer, Str -> Editor.LoadedFile
loaded_file = |buffer, persisted| { buffer, editor: CodeEditor.initial, persisted, save: Idle, history: { entries: [], position: 0 } }

history_state : CodeEditor.State -> Editor.HistoryState
history_state = |editor| { cursor: editor.cursor, anchor: editor.anchor }

restore_history_state : CodeEditor.State, Editor.HistoryState -> CodeEditor.State
restore_history_state = |editor, saved| { ..editor, cursor: saved.cursor, anchor: saved.anchor }

apply_new_edit : Editor.LoadedFile, CodeEditor.State, Buffer.Edit -> Editor.LoadedFile
apply_new_edit = |loaded, editor, forward| {
	replaced = Buffer.text_in(loaded.buffer, forward.start, forward.end)
	inverse : Buffer.Edit
	inverse = { start: forward.start, end: forward.start + forward.replacement.count_utf8_bytes(), replacement: replaced }
	entry : Editor.HistoryEntry
	entry = { forward, inverse, before: history_state(loaded.editor), after: history_state(editor) }
	entries = loaded.history.entries.sublist({ start: 0, len: loaded.history.position }).append(entry)
	history : Editor.History
	history = { entries, position: entries.len() }
	{ ..loaded, buffer: Buffer.apply_edit(loaded.buffer, forward), editor, history }
}

undo_edit : Editor.LoadedFile -> Editor.LoadedFile
undo_edit = |loaded| if loaded.history.position == 0 {
	loaded
} else {
	position = loaded.history.position - 1
	match loaded.history.entries.get(position) {
		Err(_) => loaded
		Ok(entry) => {
			buffer = Buffer.apply_edit(loaded.buffer, entry.inverse)
			editor = restore_history_state(loaded.editor, entry.before)
			{ ..loaded, buffer, editor, history: { ..loaded.history, position } }
		}
	}
}

redo_edit : Editor.LoadedFile -> Editor.LoadedFile
redo_edit = |loaded| if loaded.history.position >= loaded.history.entries.len() {
	loaded
} else {
	match loaded.history.entries.get(loaded.history.position) {
		Err(_) => loaded
		Ok(entry) => {
			buffer = Buffer.apply_edit(loaded.buffer, entry.forward)
			editor = restore_history_state(loaded.editor, entry.after)
			{ ..loaded, buffer, editor, history: { ..loaded.history, position: loaded.history.position + 1 } }
		}
	}
}

save_active! : Editor.Model, RayApp.Input(msg), (Editor.Msg -> msg) => Editor.Model
save_active! = |model, input, map_msg| match find_active_tab(model) {
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
				Task.spawn_with!(input, || FileSaved(id, workspace.write_text!(path, snapshot)), map_msg)
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

file_saved : Editor.Model, Editor.TabId, Try({}, Files.WriteError) -> Editor.Model
file_saved = |model, id, result| {
	tabs = model.tabs.map(|tab| if tab.id == id {
		match tab.file {
			Loaded(loaded) => match loaded.save {
				Saving(snapshot) => match result {
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

find_active_tab : Editor.Model -> Try(Editor.Tab, [NoTab])
find_active_tab = |model| match model.active {
	NoActiveTab => Err(NoTab)
	ActiveTab(id) => model.tabs.find_first(|tab| tab.id == id).map_err(|_| NoTab)
}

model_active_path : Editor.Model -> [NoActiveTab, ActiveTab(Str)]
model_active_path = |model| match find_active_tab(model) {
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

test_tab : Editor.TabId, Str -> Editor.Tab
test_tab = |id, path| { id, path, file: LoadFailed("test") }

test_loaded_tab : Editor.TabId, Str, Str, Str, Editor.SaveState -> Editor.Tab
test_loaded_tab = |id, path, content, persisted, save| { id, path, file: Loaded({ ..loaded_file(Buffer.from_path(path, content), persisted), save }) }

test_model : List(Editor.Tab), Editor.Active, Editor.TabId -> Editor.Model
test_model = |tabs, active, next_tab_id| { workspace: Files.Dir.stub, font: Font.stub, metrics: CodeEditor.metrics(Font.stub), tabs, active, next_tab_id }

expect Highlight.language_for("INDEX.HTML") == HtmlLanguage
expect Highlight.language_for("assets/site.css") == CssLanguage
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
	model = test_model([test_loaded_tab(7, "style.css", ".a { color: red; }", ".a { color: red; }", Idle)], ActiveTab(7), 8)
	updated = edit_document(model, 7, InsertLineBreak)
	match updated.tabs.get(0) {
		Ok(tab) => match tab.file {
			Loaded(loaded) => loaded.buffer.content == "\n.a { color: red; }"
				and loaded.editor.cursor == 1
				and loaded.buffer.language == CssLanguage
				and match loaded.buffer.highlights.first() {
					Ok(span) => span.start == 1 and span.role == Name
					Err(_) => Bool.False
				}
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

expect {
	initial = loaded_file(Buffer.from_path("a.html", "abc"), "abc")
	editor = { ..initial.editor, cursor: 1, anchor: 1 }
	edited = apply_new_edit(initial, editor, { start: 0, end: 0, replacement: "X" })
	undone = undo_edit(edited)
	redone = redo_edit(undone)
	redone.buffer.content == "Xabc"
		and redone.editor.cursor == 1
		and redone.history.entries.len() == 1
		and redone.history.position == 1
}

expect {
	initial = loaded_file(Buffer.from_path("a.html", "abc"), "abc")
	editor = { ..initial.editor, cursor: 1, anchor: 1 }
	edited = apply_new_edit(initial, editor, { start: 0, end: 0, replacement: "X" })
	undone = undo_edit(edited)
	branched = apply_new_edit(undone, editor, { start: 0, end: 0, replacement: "Y" })
	branched.buffer.content == "Yabc"
		and branched.history.entries.len() == 1
		and branched.history.position == 1
}

expect {
	initial = loaded_file(Buffer.from_path("style.css", ".a { color: red; }"), ".a { color: red; }")
	selected = { ..initial, editor: { ..initial.editor, cursor: 15, anchor: 12 } }
	editor = { ..initial.editor, cursor: 16, anchor: 16 }
	edited = apply_new_edit(selected, editor, { start: 12, end: 15, replacement: "blue" })
	undone = undo_edit(edited)
	redone = redo_edit(undone)
	undone.buffer.content == ".a { color: red; }"
		and undone.editor.cursor == 15
		and undone.editor.anchor == 12
		and redone.buffer.content == ".a { color: blue; }"
		and redone.editor.cursor == 16
}

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
	model = test_model([test_loaded_tab(7, "a.html", "edited", "old", Saving("edited"))], ActiveTab(7), 8)
	model_active_path(model) == ActiveTab("a.html")
}

expect {
	model = test_model([test_loaded_tab(7, "a.html", "newer edit", "old", Saving("written snapshot"))], ActiveTab(7), 8)
	updated = file_saved(model, 7, Ok({}))
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
	updated = file_saved(model, 7, Err(NoSpace))
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
