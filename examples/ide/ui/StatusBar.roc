## Compact active-document status.
import tc.Element exposing [box, style, text]
import tc.Program exposing [View]

import ../Theme exposing [theme]
import Editor

StatusBar := [].{
	view : Editor.Model -> View(msg)
	view = |model| {
		{ path, language, state, position } = status(model.active, model.tabs)
		box(
			{
				style: |_| style
					.width(Grow({}))
					.height(Fixed(24))
					.direction(Row)
					.pad(0, theme.gap, 0, theme.gap)
					.gap(theme.gap + theme.gap / 2)
					.font_size(12)
					.font_color(theme.palette.text.muted)
					.background(theme.palette.surface.base.fill)
					.border({ color: theme.palette.edge.border, left: 0, right: 0, top: 1, bottom: 0 })
					.child_align({ x: Start, y: Center }),
			},
			[
				text(language),
				text("ASCII"),
				text(state),
				box({ style: |_| style.width(Grow({})).height(Fit({})) }, []),
				text(position),
				text(path),
			],
		)
	}
}

status : Editor.Active, List(Editor.Tab) -> { path : Str, language : Str, state : Str, position : Str }
status = |active, tabs| match active {
	NoActiveTab => { path: "No file open", language: "PLAIN TEXT", state: "", position: "" }
	ActiveTab(id) => match tabs.find_first(|tab| tab.id == id) {
		Err(_) => { path: "No file open", language: "PLAIN TEXT", state: "", position: "" }
		Ok(tab) => match tab.file {
			Loading => { path: tab.path, language: "LOADING", state: "Loading", position: "" }
			LoadFailed(_) => { path: tab.path, language: "ERROR", state: "Load failed", position: "" }
			Loaded(loaded) => {
				document = loaded.buffer
				language = match document.language {
					HtmlLanguage => "HTML"
					PlainText => "PLAIN TEXT"
				}
				state = match loaded.save {
					Saving(_) => "Saving"
					SaveFailed(_) => "Save failed"
					Idle => if loaded.buffer.content != loaded.persisted "Modified" else "Saved"
				}
				{ path: tab.path, language, state, position: cursor_position(document) }
			}
		}
	}
}

cursor_position : Editor.Document -> Str
cursor_position = |document| {
	"${(document.cursor.line + 1).to_str()}:${(document.cursor.column + 1).to_str()}"
}
