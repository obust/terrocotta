import tc.Element exposing [box, style, text]
import tc.Program exposing [View]

import ../Theme exposing [theme]
import CodeEditor
import Editor

StatusBar := [].{
	view : Editor.Model -> View(msg)
	view = |model| {
		status_view = |position, path| box(
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
				box({ style: |_| style.width(Grow({})).height(Fit({})) }, []),
				text(position),
				text(path),
			],
		)
		match Editor.active_tab(model) {
			Err(_) => status_view("", "No file open")
			Ok(tab) => match tab.file {
				Loading => status_view("", tab.path)
				LoadFailed(_) => status_view("", tab.path)
				Loaded(loaded) => {
					cursor = CodeEditor.position(loaded.buffer, loaded.editor)
					position = "${(cursor.line + 1).to_str()}:${(cursor.column + 1).to_str()}"
					status_view(position, tab.path)
				}
			}
		}
	}
}
