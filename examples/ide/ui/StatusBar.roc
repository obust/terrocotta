import tc.Element exposing [box, style, text]
import tc.Program exposing [View]

import ../Theme exposing [theme]
import Editor

StatusBar := [].{
	view : Editor.Model -> View(msg)
	view = |model| {
		status_view = |language, state, position, path| box(
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
		match Editor.active_tab(model) {
			Err(_) => status_view("PLAIN TEXT", "", "", "No file open")
			Ok(tab) => match tab.file {
				Loading => status_view("LOADING", "Loading", "", tab.path)
				LoadFailed(_) => status_view("ERROR", "Load failed", "", tab.path)
				Loaded(loaded) => {
					language = match loaded.buffer.language {
						HtmlLanguage => "HTML"
						PlainText => "PLAIN TEXT"
					}
					state = match loaded.save {
						Saving(_) => "Saving"
						SaveFailed(_) => "Save failed"
						Idle => if loaded.buffer.content != loaded.persisted "Modified" else "Saved"
					}
					position = "${(loaded.buffer.cursor.line + 1).to_str()}:${(loaded.buffer.cursor.column + 1).to_str()}"
					status_view(language, state, position, tab.path)
				}
			}
		}
	}
}
