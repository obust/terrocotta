## Read-only editor state, file loading, tabs, and source surface.
import rr.App as RayApp
import rr.Files
import rr.Font
import rr.Task
import tc.Element exposing [box, map, style]
import tc.Program exposing [View]

import ../Theme exposing [theme]
import ../syntax/Html
import CodeEditor
import Tabs

Editor := [].{
	Language : [HtmlLanguage, PlainText]

	Document : {
		content : Str,
		language : Language,
		lines : List(Html.Line),
		cursor : CodeEditor.Cursor,
	}

	DocumentState : [Loading(U64), Ready(Document), Failed(Str)]

	Tab : {
		path : Str,
		title : Str,
		saved_hash : U64,
		dirty : Bool,
		document : DocumentState,
	}

	Active : [NoActiveTab, ActiveTab(Str)]

	Model : {
		workspace : Files.Dir,
		tabs : List(Tab),
		active : Active,
		next_load_id : U64,
	}

	Msg : [Open(Str), FileLoaded(U64, Str, Try(Str, Files.ReadTextError)), ActivateTab(Str), CloseTab(Str), CloseActive, SaveActive, FileSaved(Str, U64, Try({}, Files.WriteError)), CodeEdit(Str, CodeEditor.Msg)]

	init! : Files.Dir, Str => Try(Model, Files.ReadTextError)
	init! = |workspace, initial_path| {
		initial_content = workspace.read_text!(initial_path)?
		initial_tab : Tab
		initial_tab = {
			path: initial_path,
			title: basename(initial_path),
			saved_hash: content_hash(initial_content),
			dirty: Bool.False,
			document: Ready(document(initial_path, initial_content)),
		}
		Ok({ workspace, tabs: [initial_tab], active: ActiveTab(initial_path), next_load_id: 1 })
	}

	update! : Model, Msg, RayApp.Input(msg), (Msg -> msg) => Model
	update! = |model, message, input, map_msg| match message {
		Open(path) => match model.tabs.find_first(|tab| tab.path == path) {
			Ok(_) => { ..model, active: ActiveTab(path) }
			Err(_) => {
				load_id = model.next_load_id
				workspace = model.workspace
				Task.spawn_with!(input, || FileLoaded(load_id, path, workspace.read_text!(path)), map_msg)
				tab : Tab
				tab = { path, title: basename(path), saved_hash: 0, dirty: Bool.False, document: Loading(load_id) }
				{ ..model, tabs: model.tabs.append(tab), active: ActiveTab(path), next_load_id: load_id + 1 }
			}
		}
		FileLoaded(load_id, path, result) => {
			tabs = model.tabs.map(
				|tab| {
					if tab.path == path and tab.document == Loading(load_id) {
						document_state = match result {
							Ok(content) => Ready(document(path, content))
							Err(error) => Failed(read_error(error))
						}
						saved_hash = match result {
							Ok(content) => content_hash(content)
							Err(_) => tab.saved_hash
						}
						{ ..tab, saved_hash, document: document_state }
					} else {
						tab
					}
				},
			)
			{ ..model, tabs }
		}
		CodeEdit(path, code_message) => edit_document(model, path, code_message)
		SaveActive => save_active!(model, input, map_msg)
		FileSaved(path, saved_hash, result) => saved(model, path, saved_hash, result)
		ActivateTab(path) => { ..model, active: ActiveTab(path) }
		CloseTab(path) => close(model, path)
		CloseActive => match model.active {
			NoActiveTab => model
			ActiveTab(path) => close(model, path)
		}
	}

	view : Font, Model -> View(Msg)
	view = |font, model| {
		source = match active_tab(model) {
			Ok(tab) => match tab.document {
			Ready(loaded) => CodeEditor.view(font, loaded) |> map(|message| CodeEdit(tab.path, message))
				Loading(_) => box({ style: |_| style.width(Grow({})).height(Grow({})).child_align({ x: Center, y: Center }) }, [])
				Failed(_) => box({ style: |_| style.width(Grow({})).height(Grow({})).child_align({ x: Center, y: Center }) }, [])
			}
		Err(_) => box({ style: |_| style.width(Grow({})).height(Grow({})).child_align({ x: Center, y: Center }) }, [])
		}
		box(
			{ style: |_| style.direction(Col).background(theme.palette.surface.base.fill) },
			[
				Tabs.view(model.tabs.map(|tab| { path: tab.path, title: tab.title, dirty: tab.dirty, document: map_document(tab.document) }), model.active) |> map(|message| match message {
					Activate(path) => ActivateTab(path)
					Close(path) => CloseTab(path)
				}),
				source,
			],
		)
	}

}

document : Str, Str -> Editor.Document
document = |path, content| {
	language = language_for(path)
	lines = match language { HtmlLanguage => Html.highlight(content), PlainText => Html.plain(content) }
	{ content, language, lines, cursor: { line: 0, column: 0 } }
}

map_document : Editor.DocumentState -> Tabs.DocumentState(Editor.Document)
map_document = |state| match state {
	Loading(id) => Loading(id)
	Ready(loaded_document) => Ready(loaded_document)
	Failed(error) => Failed(error)
}

edit_document : Editor.Model, Str, CodeEditor.Msg -> Editor.Model
edit_document = |model, path, message| {
	tabs = model.tabs.map(
		|tab| if tab.path == path {
			match tab.document {
				Ready(loaded) => {
					updated = CodeEditor.update(loaded, message)
					{ ..tab, dirty: content_hash(updated.content) != tab.saved_hash, document: Ready(updated) }
				}
				_ => tab
			}
		} else tab,
	)
	{ ..model, tabs }
}

save_active! : Editor.Model, RayApp.Input(msg), (Editor.Msg -> msg) => Editor.Model
save_active! = |model, input, map_msg| match active_tab(model) {
	Err(_) => model
	Ok(tab) => match tab.document {
		Ready(saved_document) if tab.dirty => {
			workspace = model.workspace
			path = tab.path
			saved_hash = content_hash(saved_document.content)
			Task.spawn_with!(input, || FileSaved(path, saved_hash, workspace.write_text!(path, saved_document.content)), map_msg)
			model
		}
		_ => model
	}
}

saved : Editor.Model, Str, U64, Try({}, Files.WriteError) -> Editor.Model
saved = |model, path, saved_hash, result| match result {
	Ok(_) => { ..model, tabs: model.tabs.map(|tab| if tab.path == path { ..tab, saved_hash, dirty: tab_current_hash(tab) != saved_hash } else tab) }
	Err(_) => model
}

tab_current_hash : Editor.Tab -> U64
tab_current_hash = |tab| match tab.document {
	Ready(current_document) => content_hash(current_document.content)
	_ => tab.saved_hash
}

content_hash : Str -> U64
content_hash = |content| content.to_utf8().fold(2166136261, |hash, byte| ((hash * 16777619) + byte.to_u64()) % 4294967291)

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
	ActiveTab(path) => model.tabs.find_first(|tab| tab.path == path).map_err(|_| NoTab)
}

read_error : Files.ReadTextError -> Str
read_error = |error| match error {
	PermissionDenied => "Permission denied"
	PathInvalid => "The workspace path is invalid"
	NotFound => "The file no longer exists"
	ReadFailed => "The file could not be read"
	Busy => "The file service is busy"
	Unavailable => "The file service is unavailable"
	TooLarge => "This example opens UTF-8 files up to 64 KiB"
	NotUtf8 => "This file is not valid UTF-8"
}

close : Editor.Model, Str -> Editor.Model
close = |model, path| close_editor(model, path)

close_editor : Editor.Model, Str -> Editor.Model
close_editor = |model, path| match tab_index(model.tabs, path, 0) {
	Err(_) => model
	Ok(index) => {
		tabs = model.tabs.drop_at(index)
		active = if model.active != ActiveTab(path) {
			model.active
		} else {
			match tabs.get(index) {
				Ok(tab) => ActiveTab(tab.path)
				Err(_) => match tabs.last() {
					Ok(tab) => ActiveTab(tab.path)
					Err(_) => NoActiveTab
				}
			}
		}
		{ ..model, tabs, active }
	}
}

tab_index : List(Editor.Tab), Str, U64 -> Try(U64, [NotFound])
tab_index = |tabs, path, index| {
	if index >= tabs.len() {
		Err(NotFound)
	} else {
		match tabs.get(index) {
			Ok(tab) => if tab.path == path Ok(index) else tab_index(tabs, path, index + 1)
			Err(_) => Err(NotFound)
		}
	}
}

expect language_for("INDEX.HTML") == HtmlLanguage
expect language_for("assets/site.css") == PlainText
expect basename("components/card.html") == "card.html"

expect {
	tabs : List(Editor.Tab)
	tabs = [
		{ path: "a.html", title: "a.html", saved_hash: 0, dirty: Bool.False, document: Failed("test") },
		{ path: "b.html", title: "b.html", saved_hash: 0, dirty: Bool.False, document: Failed("test") },
	]
	tab_index(tabs, "b.html", 0) == Ok(1)
}

test_tab : Str -> Editor.Tab
test_tab = |path| { path, title: basename(path), saved_hash: 0, dirty: Bool.False, document: Failed("test") }

test_model : List(Editor.Tab), Editor.Active -> Editor.Model
test_model = |tabs, active| { workspace: Files.Dir.stub, tabs, active, next_load_id: 0 }

expect {
	model = test_model([test_tab("a.html"), test_tab("b.html"), test_tab("c.html")], ActiveTab("b.html"))
	closed = close(model, "b.html")
	closed.tabs.map(|tab| tab.path) == ["a.html", "c.html"] and closed.active == ActiveTab("c.html")
}

expect {
	model = test_model([test_tab("a.html"), test_tab("b.html")], ActiveTab("b.html"))
	closed = close(model, "b.html")
	closed.tabs.map(|tab| tab.path) == ["a.html"] and closed.active == ActiveTab("a.html")
}

expect {
	model = test_model([test_tab("a.html")], ActiveTab("a.html"))
	closed = close(model, "a.html")
	closed.tabs.is_empty() and closed.active == NoActiveTab
}
