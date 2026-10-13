## Document lifecycle and effect handling for the IDE's editor area.
##
## This module owns tabs, edit history, dirty state, clipboard effects, and
## asynchronous file loading and saving. CodeEditor owns interaction state and
## returns language-independent edit commands; Buffer owns source-derived data.
import rr.App as RayApp
import rr.Assets
import rr.Draw
import rr.Files
import rr.Font
import rr.Task
import rr.Window
import tc.Color
import tc.Element exposing [box, map, style, text]
import tc.Program exposing [View]

import ../source/Buffer
import ../source/LineEndings
import ../Theme exposing [theme]
import ../source/Highlight
import CodeEditor
import Tabs

Editor := [].{
	DocumentError : [UnsupportedByte({ offset : U64, byte : U8 }), LoneCarriageReturn(U64), MixedLineEndings]

	Document : {
		buffer : Buffer,
		content : Str,
		line_ending : LineEndings.LineEnding,
	}

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
		editor : CodeEditor.Model,
		persisted : Str,
		line_ending : LineEndings.LineEnding,
		save : SaveState,
		history : History,
	}

	FileState : [Loading, LoadFailed(Str), Loaded(LoadedFile)]

	Tab : {
		id : TabId,
		path : Str,
		file : FileState,
	}

	Model : {
		workspace : Files.Dir,
		clipboard : Window.Clipboard,
		font : Font,
		metrics : CodeEditor.FontMetrics,
		tabs : Tabs(Tab),
	}

	Msg : [Open(Str), FileLoaded(TabId, Try(Str, Files.ReadTextError)), ActivateTab(TabId), CloseTab(TabId), CloseActive, SaveActive, FileSaved(TabId, Try({}, Files.WriteError)), CodeEdit(TabId, CodeEditor.Msg)]

	active_path : Model -> [NoActiveTab, ActiveTab(Str)]
	active_path = model_active_path

	active_tab : Model -> Try(Tab, [NoTab])
	active_tab = find_active_tab

	init! : Files.Dir, Window.Clipboard, Assets.Store, Str => Try(Model, [PermissionDenied, PathInvalid, NotFound, ReadFailed, Busy, Unavailable, TooLarge, NotUtf8, FontLoadFailed, ResourceLimit])
	init! = |workspace, clipboard, assets, initial_path| {
		font = Draw.load_store_font!(assets, { path: "JetBrainsMono-Regular.ttf", size: 36 })?
		metrics = CodeEditor.metrics(font)
		initial_content = workspace.read_text!(initial_path)?
		initial_tab : Tab
		initial_tab = {
			id: 0,
			path: initial_path,
			file: match document(initial_path, initial_content) {
				Ok(decoded) => Loaded(loaded_file(decoded.buffer, decoded.content, decoded.line_ending))
				Err(error) => LoadFailed(document_error(error))
			},
		}
		Ok({ workspace, clipboard, font, metrics, tabs: Tabs.single(initial_tab, 1) })
	}

	update! : Model, Msg, RayApp.Input(msg), (Msg -> msg) => Model
	update! = |model, message, input, map_msg| match message {
		Open(path) => match model.tabs.find(|tab| tab.path == path) {
			Ok(_) => { ..model, tabs: model.tabs.activate(|tab| tab.path == path) }
			Err(_) => {
				opened = model.tabs.open(|id| { id, path, file: Loading })
				workspace = model.workspace
				Task.spawn_with!(input, || FileLoaded(opened.id, workspace.read_text!(path)), map_msg)
				{ ..model, tabs: opened.tabs }
			}
		}
		FileLoaded(id, result) => file_loaded(model, id, result)
		CodeEdit(id, code_message) => edit_document!(model, id, code_message)
		SaveActive => save_active!(model, input, map_msg)
		FileSaved(id, result) => file_saved(model, id, result)
		ActivateTab(id) => { ..model, tabs: model.tabs.activate(|tab| tab.id == id) }
		CloseTab(id) => { ..model, tabs: model.tabs.close(|tab| tab.id == id) }
		CloseActive => match model.tabs.active() {
			Err(_) => model
			Ok(tab) => { ..model, tabs: model.tabs.close(|candidate| candidate.id == tab.id) }
		}
	}

	view : Model -> View(Msg)
	view = |model| {
		source = match model.tabs.active() {
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
				tabs_view(model.tabs),
				source,
			],
		)
	}
}

tabs_view : Tabs(Editor.Tab) -> View(Editor.Msg)
tabs_view = |tabs| box(
	{
		style: |_| style
			.height(Fit({}))
			.direction(Row)
			.child_align({ x: Start, y: Center })
			.background(inactive_surface)
			.overflow(Scroll, Hidden),
	},
	tabs.items().map_with_index(|tab, index| tab_view(tab, tabs.is_active(index))).append(box({ style: |_| style.border({ color: theme.palette.edge.border, left: 0, right: 0, top: 0, bottom: 1 }) }, [])),
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

document : Str, Str -> Try(Editor.Document, Editor.DocumentError)
document = |path, content| {
	decoded = LineEndings.decode(content)?
	validate_ascii(decoded.content)?
	Ok({ buffer: Buffer.from_path(path, decoded.content), content: decoded.content, line_ending: decoded.line_ending })
}

validate_ascii : Str -> Try({}, Editor.DocumentError)
validate_ascii = |content| {
	var $offset = 0
	for byte in content.to_utf8() {
		if byte != Buffer.tab_byte and byte != 10 and (byte < 32 or byte > 126) {
			return Err(UnsupportedByte({ offset: $offset, byte }))
		}
		$offset = $offset + 1
	}
	Ok({})
}

document_error : Editor.DocumentError -> Str
document_error = |error| match error {
	UnsupportedByte({ offset, byte }) => "Cannot open this file: byte ${byte.to_str()} at offset ${offset.to_str()} is not printable ASCII, tab, or LF."
	LoneCarriageReturn(offset) => "Cannot open this file: carriage return at byte ${offset.to_str()} is not followed by LF."
	MixedLineEndings => "Cannot open this file: mixed LF and CRLF line endings are not supported."
}

file_loaded : Editor.Model, Editor.TabId, Try(Str, Files.ReadTextError) -> Editor.Model
file_loaded = |model, id, result| {
	tabs = model.tabs.update(
		|tab| tab.id == id,
		|tab|
			match tab.file {
				Loading => {
					file = match result {
						Ok(content) => match document(tab.path, content) {
							Ok(decoded) => Loaded(loaded_file(decoded.buffer, decoded.content, decoded.line_ending))
							Err(error) => LoadFailed(document_error(error))
						}
						Err(error) => LoadFailed(read_error(error))
					}
					{ ..tab, file }
				}
				_ => tab
			},
	)
	{ ..model, tabs }
}

edit_document! : Editor.Model, Editor.TabId, CodeEditor.Msg => Editor.Model
edit_document! = |model, id, message| match model.tabs.find(|tab| tab.id == id) {
	Err(_) => model
	Ok(tab) => match tab.file {
		Loading | LoadFailed(_) => model
		Loaded(loaded) => {
			(editor, command) = CodeEditor.update(model.metrics, loaded.buffer, loaded.editor, message)
			next = apply_code_command!(loaded, editor, command, model.metrics, model.clipboard)
			tabs = model.tabs.update(|candidate| candidate.id == id, |candidate| { ..candidate, file: Loaded(next) })
			{ ..model, tabs }
		}
	}
}

apply_code_command! : Editor.LoadedFile, CodeEditor.Model, CodeEditor.Command, CodeEditor.FontMetrics, Window.Clipboard => Editor.LoadedFile
apply_code_command! = |loaded, editor, command, metrics, clipboard| match command {
	NoCommand => { ..loaded, editor }
	Replace(edit) => apply_new_edit(loaded, editor, edit)
	Undo => undo_edit(loaded)
	Redo => redo_edit(loaded)
	Copy(text) => {
		_ = clipboard.set_text!(text)
		{ ..loaded, editor }
	}
	ReadClipboard => {
		unchanged = { ..loaded, editor }
		content = match clipboard.read_text!() {
			Err(_) => return unchanged
			Ok(value) => value
		}
		normalized = match clipboard_content(content) {
			Err(_) => return unchanged
			Ok(value) => value
		}
		(next_editor, next_command) = CodeEditor.update(metrics, loaded.buffer, editor, Paste(normalized))
		apply_code_command!(loaded, next_editor, next_command, metrics, clipboard)
	}
}

clipboard_content : Str -> Try(Str, Editor.DocumentError)
clipboard_content = |content| {
	decoded = LineEndings.decode(content)?
	validate_ascii(decoded.content)?
	Ok(decoded.content)
}

loaded_file : Buffer, Str, LineEndings.LineEnding -> Editor.LoadedFile
loaded_file = |buffer, persisted, line_ending| { buffer, editor: CodeEditor.initial, persisted, line_ending, save: Idle, history: { entries: [], position: 0 } }

history_state : CodeEditor.Model -> Editor.HistoryState
history_state = |editor| { cursor: editor.cursor, anchor: editor.anchor }

restore_history_state : CodeEditor.Model, Editor.HistoryState -> CodeEditor.Model
restore_history_state = |editor, saved| { ..editor, cursor: saved.cursor, anchor: saved.anchor }

apply_new_edit : Editor.LoadedFile, CodeEditor.Model, Buffer.Edit -> Editor.LoadedFile
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
save_active! = |model, input, map_msg| match model.tabs.active() {
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

				## Persist a snapshot rather than the live buffer. If the user edits
				## during the write, file_saved records only this snapshot as persisted.
				payload = save_payload(loaded)
				Task.spawn_with!(input, || FileSaved(id, workspace.write_text!(path, payload.encoded)), map_msg)
				mark_saving(model, id, payload.snapshot)
			}
		}
		_ => model
	}
}

save_payload : Editor.LoadedFile -> { snapshot : Str, encoded : Str }
save_payload = |loaded| {
	snapshot = loaded.buffer.content
	{ snapshot, encoded: LineEndings.encode(snapshot, loaded.line_ending) }
}

mark_saving : Editor.Model, Editor.TabId, Str -> Editor.Model
mark_saving = |model, id, snapshot| {
	tabs = model.tabs.update(
		|tab| tab.id == id,
		|tab|
			match tab.file {
				Loaded(loaded) => { ..tab, file: Loaded({ ..loaded, save: Saving(snapshot) }) }
				_ => tab
			},
	)
	{ ..model, tabs }
}

file_saved : Editor.Model, Editor.TabId, Try({}, Files.WriteError) -> Editor.Model
file_saved = |model, id, result| {
	tabs = model.tabs.update(
		|tab| tab.id == id,
		|tab|
			match tab.file {
				Loaded(loaded) => match loaded.save {
					Saving(snapshot) => match result {
						Ok(_) => { ..tab, file: Loaded({ ..loaded, persisted: snapshot, save: Idle }) }
						Err(error) => { ..tab, file: Loaded({ ..loaded, save: SaveFailed(write_error(error)) }) }
					}
					_ => tab
				}
				_ => tab
			},
	)
	{ ..model, tabs }
}

is_dirty : Editor.Tab -> Bool
is_dirty = |tab| match tab.file {
	Loaded(loaded) => loaded.buffer.content != loaded.persisted
	_ => Bool.False
}

basename : Str -> Str
basename = |path| match path.split_last("/") {
	Ok(parts) => parts.after
	Err(_) => path
}

find_active_tab : Editor.Model -> Try(Editor.Tab, [NoTab])
find_active_tab = |model| model.tabs.active().map_err(|_| NoTab)

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

test_tab : Editor.TabId, Str -> Editor.Tab
test_tab = |id, path| { id, path, file: LoadFailed("test") }

test_loaded_tab : Editor.TabId, Str, Str, Str, Editor.SaveState -> Editor.Tab
test_loaded_tab = |id, path, content, persisted, save| { id, path, file: Loaded({ ..loaded_file(Buffer.from_path(path, content), persisted, Lf), save }) }

test_model : List(Editor.Tab), [NoIndex, Index(U64)], Editor.TabId -> Editor.Model
test_model = |items, active_index, next_tab_id| { workspace: Files.Dir.stub, clipboard: RayApp.Io.stub.clipboard(), font: Font.stub, metrics: CodeEditor.metrics(Font.stub), tabs: Tabs.from_list(items, active_index, next_tab_id) }

expect Highlight.language_for("INDEX.HTML") == HtmlLanguage
expect Highlight.language_for("assets/site.css") == CssLanguage
expect basename("components/card.html") == "card.html"

expect match document("notes.txt", "printable ASCII\nand LF") {
	Ok(decoded) => decoded.content == "printable ASCII\nand LF" and decoded.buffer.content == decoded.content and decoded.line_ending == Lf
	Err(_) => Bool.False
}

expect match document("notes.txt", "a\tb") {
	Ok(decoded) => decoded.content == "a\tb" and decoded.buffer.content == "a\tb"
	Err(_) => Bool.False
}

expect match document("notes.txt", Str.from_utf8_lossy([97, 1, 98])) {
	Err(UnsupportedByte({ offset, byte })) => offset == 1 and byte == 1
	_ => Bool.False
}

expect match document("notes.txt", "a\r\nb") {
	Ok(decoded) => decoded.content == "a\nb" and decoded.buffer.content == "a\nb" and decoded.line_ending == Crlf
	_ => Bool.False
}

expect match document("notes.txt", "a\r\nb") {
	Ok(decoded) => {
		loaded = loaded_file(decoded.buffer, decoded.content, decoded.line_ending)
		loaded.persisted == "a\nb" and loaded.line_ending == Crlf and !loaded.buffer.content.to_utf8().contains(13)
	}
	Err(_) => Bool.False
}

expect match document("notes.txt", "café") {
	Err(UnsupportedByte({ offset, byte })) => offset == 3 and byte == 195
	_ => Bool.False
}

expect document_error(UnsupportedByte({ offset: 3, byte: 195 })) == "Cannot open this file: byte 195 at offset 3 is not printable ASCII, tab, or LF."
expect document_error(LoneCarriageReturn(3)) == "Cannot open this file: carriage return at byte 3 is not followed by LF."
expect document_error(MixedLineEndings) == "Cannot open this file: mixed LF and CRLF line endings are not supported."

expect match document("notes.txt", "a\rb") {
	Err(LoneCarriageReturn(offset)) => offset == 1
	_ => Bool.False
}

expect match document("notes.txt", "a\nb\r\n") {
	Err(MixedLineEndings) => Bool.True
	_ => Bool.False
}

expect clipboard_content("one\r\ntwo") == Ok("one\ntwo")
expect clipboard_content("one\ntwo") == Ok("one\ntwo")
expect clipboard_content("one\ttwo") == Ok("one\ttwo")
expect clipboard_content("one\rtwo") == Err(LoneCarriageReturn(3))
expect clipboard_content("one\ntwo\r\n") == Err(MixedLineEndings)

expect {
	loaded = loaded_file(Buffer.from_path("style.css", ".a { color: red; }"), ".a { color: red; }", Lf)
	(editor, command) = CodeEditor.update(test_model([], NoIndex, 0).metrics, loaded.buffer, loaded.editor, InsertLineBreak)
	match command {
		Replace(edit) => {
			updated = apply_new_edit(loaded, editor, edit)
			updated.buffer.content == "\n.a { color: red; }"
				and updated.editor.cursor == 1
					and updated.buffer.language == CssLanguage
						and match updated.buffer.highlights.first() {
							Ok(span) => span.start == 1 and span.role == Name
							Err(_) => Bool.False
						}
		}
		_ => Bool.False
	}
}

expect {
	initial = loaded_file(Buffer.from_path("a.html", "abc"), "abc", Lf)
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
	initial = loaded_file(Buffer.from_path("a.html", "abc"), "abc", Lf)
	editor = { ..initial.editor, cursor: 1, anchor: 1 }
	edited = apply_new_edit(initial, editor, { start: 0, end: 0, replacement: "X" })
	undone = undo_edit(edited)
	branched = apply_new_edit(undone, editor, { start: 0, end: 0, replacement: "Y" })
	branched.buffer.content == "Yabc"
		and branched.history.entries.len() == 1
			and branched.history.position == 1
}

expect {
	initial = loaded_file(Buffer.from_path("style.css", ".a { color: red; }"), ".a { color: red; }", Lf)
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
	model = test_model([test_tab(1, "a.html"), test_tab(2, "b.html"), test_tab(3, "c.html")], Index(1), 4)
	closed = { ..model, tabs: model.tabs.close(|tab| tab.id == 2) }
	closed.tabs.items().map(|tab| tab.path) == ["a.html", "c.html"] and closed.tabs.active().map_ok(|tab| tab.id) == Ok(3)
}

expect {
	model = test_model([test_tab(1, "a.html"), test_tab(2, "b.html")], Index(1), 3)
	closed = { ..model, tabs: model.tabs.close(|tab| tab.id == 2) }
	closed.tabs.items().map(|tab| tab.path) == ["a.html"] and closed.tabs.active().map_ok(|tab| tab.id) == Ok(1)
}

expect {
	model = test_model([test_tab(1, "a.html")], Index(0), 2)
	closed = { ..model, tabs: model.tabs.close(|tab| tab.id == 1) }
	closed.tabs.items().is_empty() and closed.tabs.active() == Err(NoActiveTab)
}

expect {
	tab = test_loaded_tab(7, "a.html", "edited back", "edited back", Idle)
	!is_dirty(tab)
}

expect {
	model = test_model([test_loaded_tab(7, "a.html", "edited", "old", Saving("edited"))], Index(0), 8)
	model_active_path(model) == ActiveTab("a.html")
}

expect {
	model = test_model([test_loaded_tab(7, "a.html", "newer edit", "old", Saving("written snapshot"))], Index(0), 8)
	updated = file_saved(model, 7, Ok({}))
	match updated.tabs.items().get(0) {
		Ok(tab) => match tab.file {
			Loaded(loaded) => loaded.persisted == "written snapshot" and loaded.buffer.content == "newer edit" and loaded.save == Idle and is_dirty(tab)
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

expect {
	loaded = loaded_file(Buffer.from_path("a.html", "one\ntwo\n"), "old\n", Lf)
	payload = save_payload(loaded)
	payload.snapshot == "one\ntwo\n" and payload.encoded == "one\ntwo\n"
}

expect {
	loaded = loaded_file(Buffer.from_path("a.html", "one\ntwo\n"), "old\n", Crlf)
	payload = save_payload(loaded)
	payload.snapshot == "one\ntwo\n" and payload.encoded == "one\r\ntwo\r\n"
}

expect {
	decoded = document("a.html", "a\tb\r\n")
	match decoded {
		Ok(value) => {
			loaded = loaded_file(value.buffer, value.content, value.line_ending)
			payload = save_payload(loaded)
			payload.snapshot == "a\tb\n" and payload.encoded == "a\tb\r\n"
		}
		Err(_) => Bool.False
	}
}

expect {
	initial = loaded_file(Buffer.from_path("a.html", "abcd"), "abcd", Lf)
	selected = { ..initial.editor, cursor: 3, anchor: 1 }
	(next_editor, command) = CodeEditor.update(test_model([], NoIndex, 0).metrics, initial.buffer, selected, InsertTab)
	match command {
		Replace(edit) => {
			edited = apply_new_edit({ ..initial, editor: selected }, next_editor, edit)
			undone = undo_edit(edited)
			redone = redo_edit(undone)
			edited.buffer.content == "a\td"
				and edited.editor.cursor == 2
					and undone.buffer.content == "abcd"
						and redone.buffer.content == "a\td"
		}
		_ => Bool.False
	}
}

expect {
	initial = loaded_file(Buffer.from_path("a.html", "one\ntwo"), "one\ntwo", Crlf)
	edited = apply_new_edit(initial, { ..initial.editor, cursor: 4, anchor: 4 }, { start: 3, end: 3, replacement: "\n" })
	payload = save_payload(edited)
	payload.snapshot == "one\n\ntwo" and payload.encoded == "one\r\n\r\ntwo"
}

expect {
	model = test_model(
		[
			{
				id: 7,
				path: "a.html",
				file: Loaded({ ..loaded_file(Buffer.from_path("a.html", "newer\nedit"), "old\n", Crlf), save: Saving("written\nsnapshot") }),
			},
		],
		Index(0),
		8,
	)
	updated = file_saved(model, 7, Ok({}))
	match updated.tabs.items().get(0) {
		Ok(tab) => match tab.file {
			Loaded(loaded) => loaded.persisted == "written\nsnapshot"
				and loaded.buffer.content == "newer\nedit"
					and loaded.line_ending == Crlf
						and loaded.save == Idle
							and is_dirty(tab)
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

expect {
	model = test_model([test_loaded_tab(7, "a.html", "edited", "old", Saving("edited"))], Index(0), 8)
	updated = file_saved(model, 7, Err(NoSpace))
	match updated.tabs.items().get(0) {
		Ok(tab) => match tab.file {
			Loaded(loaded) => loaded.persisted == "old" and loaded.save == SaveFailed("There is no space left to save the file") and is_dirty(tab)
			_ => Bool.False
		}
		Err(_) => Bool.False
	}
}

expect {
	reopened = test_model([{ id: 8, path: "a.html", file: Loading }], Index(0), 9)
	stale = file_loaded(reopened, 7, Ok("stale content"))
	match stale.tabs.items().get(0) {
		Ok(tab) => tab.file == Loading
		Err(_) => Bool.False
	}
}
