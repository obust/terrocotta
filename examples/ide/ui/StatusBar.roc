import tc.Element exposing [box, style, text]
import tc.Program exposing [View]

import ../Theme exposing [theme]
import Editor

StatusBar := [].{
	view : Editor.Model -> View(msg)
	view = |model| {
		{ path, language, state, position } = match Editor.active_tab(model) {
			Err(_) => { path: "No file open", language: "PLAIN TEXT", state: "", position: "" }
			Ok(tab) => match tab.file {
				Loading => { path: tab.path, language: "LOADING", state: "Loading", position: "" }
				LoadFailed(_) => { path: tab.path, language: "ERROR", state: "Load failed", position: "" }
				Loaded(loaded) => {
					loaded_language = match loaded.buffer.language {
						HtmlLanguage => "HTML"
						PlainText => "PLAIN TEXT"
					}
					save_state = match loaded.save {
						Saving(_) => "Saving"
						SaveFailed(_) => "Save failed"
						Idle => if loaded.buffer.content != loaded.persisted "Modified" else "Saved"
					}
					cursor = "${(loaded.buffer.cursor.line + 1).to_str()}:${(loaded.buffer.cursor.column + 1).to_str()}"
					{ path: tab.path, language: loaded_language, state: save_state, position: cursor }
				}
			}
		}
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
