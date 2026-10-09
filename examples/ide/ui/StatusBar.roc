## Compact active-document status.
import tc.Element exposing [box, style, text]
import tc.Program exposing [View]

import ../App
import Colors

StatusBar := [].{
	view : App.ActiveTab, List(App.Tab) -> View(msg)
	view = |active, tabs| {
		{ path, language, state } = status(active, tabs)
		box(
			{
				style: |_| style
					.width(Grow({}))
					.height(Fixed(24))
					.direction(Row)
					.pad(0, 10, 0, 10)
					.gap(12)
					.font_size(12)
					.font_color(Colors.text_dim)
					.background(Colors.explorer)
					.border({ color: Colors.border, left: 0, right: 0, top: 1, bottom: 0 })
					.child_align({ x: Start, y: Center }),
			},
			[
				text(language),
				text("UTF-8"),
				text(state),
				box({ style: |_| style.width(Grow({})).height(Fit({})) }, []),
				text(path),
			],
		)
	}
}

status : App.ActiveTab, List(App.Tab) -> { path : Str, language : Str, state : Str }
status = |active, tabs| match active {
	NoActiveTab => { path: "No file open", language: "PLAIN TEXT", state: "Read only" }
	ActiveTab(path) => match tabs.find_first(|tab| tab.path == path) {
		Err(_) => { path, language: "PLAIN TEXT", state: "Read only" }
		Ok(tab) => match tab.document {
			Loading(_) => { path, language: "LOADING", state: "Read only" }
			Failed(_) => { path, language: "ERROR", state: "Read only" }
			Ready(document) => {
				language = match document.language {
					HtmlLanguage => "HTML"
					PlainText => "PLAIN TEXT"
				}
				{ path, language, state: "Read only" }
			}
		}
	}
}
