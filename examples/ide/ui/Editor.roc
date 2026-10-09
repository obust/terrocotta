## Read-only editor state, file loading, tabs, and source surface.
import rr.App as RayApp
import rr.Files
import rr.Font
import rr.Task
import tc.Element exposing [box, map, style]
import tc.Program exposing [View]

import ../syntax/Html
import Colors
import SourceView
import Tabs

Editor := [].{
	Language : [HtmlLanguage, PlainText]

	Document : {
		content : Str,
		language : Language,
		lines : List(Html.Line),
	}

	DocumentState : [Loading(U64), Ready(Document), Failed(Str)]

	Tab : {
		path : Str,
		title : Str,
		document : DocumentState,
	}

	Active : [NoActiveTab, ActiveTab(Str)]

	Model : {
		workspace : Files.ReadDir,
		tabs : List(Tab),
		active : Active,
		next_load_id : U64,
	}

	Msg : [Open(Str), FileLoaded(U64, Str, Try(Str, Files.ReadTextError)), ActivateTab(Str), CloseTab(Str), CloseActive]

	init! : Files.ReadDir, Str => Try(Model, Files.ReadTextError)
	init! = |workspace, initial_path| {
		initial_content = workspace.read_text!(initial_path)?
		initial_tab : Tab
		initial_tab = {
			path: initial_path,
			title: basename(initial_path),
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
				tab = { path, title: basename(path), document: Loading(load_id) }
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
						{ ..tab, document: document_state }
					} else {
						tab
					}
				},
			)
			{ ..model, tabs }
		}
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
			Ok(tab) => SourceView.view(font, tab)
			Err(_) => SourceView.empty
		}
		box(
			{ style: |_| style.direction(Col).background(Colors.source) },
			[
				Tabs.view(model.tabs, model.active) |> map(|message| match message {
					Activate(path) => ActivateTab(path)
					Close(path) => CloseTab(path)
				}),
				source,
			],
		)
	}

	document : Str, Str -> Document
	document = |path, content| {
		language = language_for(path)
		lines = match language {
			HtmlLanguage => Html.highlight(content)
			PlainText => Html.plain(content)
		}
		{ content, language, lines }
	}

	basename : Str -> Str
	basename = |path| match path.split_last("/") {
		Ok(parts) => parts.after
		Err(_) => path
	}

	language_for : Str -> Language
	language_for = |path| {
		lower = path.with_ascii_lowercased()
		if lower.ends_with(".html") or lower.ends_with(".htm") HtmlLanguage else PlainText
	}

	active_tab : Model -> Try(Tab, [NoTab])
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

	close : Model, Str -> Model
	close = |model, path| close_editor(model, path)
}

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

expect Editor.language_for("INDEX.HTML") == HtmlLanguage
expect Editor.language_for("assets/site.css") == PlainText
expect Editor.basename("components/card.html") == "card.html"

expect {
	tabs : List(Editor.Tab)
	tabs = [
		{ path: "a.html", title: "a.html", document: Failed("test") },
		{ path: "b.html", title: "b.html", document: Failed("test") },
	]
	tab_index(tabs, "b.html", 0) == Ok(1)
}

test_tab : Str -> Editor.Tab
test_tab = |path| { path, title: Editor.basename(path), document: Failed("test") }

test_model : List(Editor.Tab), Editor.Active -> Editor.Model
test_model = |tabs, active| { workspace: Files.ReadDir.stub, tabs, active, next_load_id: 0 }

expect {
	model = test_model([test_tab("a.html"), test_tab("b.html"), test_tab("c.html")], ActiveTab("b.html"))
	closed = Editor.close(model, "b.html")
	closed.tabs.map(|tab| tab.path) == ["a.html", "c.html"] and closed.active == ActiveTab("c.html")
}

expect {
	model = test_model([test_tab("a.html"), test_tab("b.html")], ActiveTab("b.html"))
	closed = Editor.close(model, "b.html")
	closed.tabs.map(|tab| tab.path) == ["a.html"] and closed.active == ActiveTab("a.html")
}

expect {
	model = test_model([test_tab("a.html")], ActiveTab("a.html"))
	closed = Editor.close(model, "a.html")
	closed.tabs.is_empty() and closed.active == NoActiveTab
}
