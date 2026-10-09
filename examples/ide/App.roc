## Durable IDE example state and messages.
import rr.Font
import tc.Theme

import ui/CommandPalette
import ui/Editor
import ui/Explorer
import ui/Topbar

App := [].{
	Model : {
		explorer : Explorer.Model,
		editor : Editor.Model,
		font : Font,
		command_palette : CommandPalette.Model,
	}

	Msg : [
		TopbarMessage(Topbar.Msg),
		ExplorerMessage(Explorer.Msg),
		EditorMessage(Editor.Msg),
		CommandPaletteMessage(CommandPalette.Msg),
	]

	theme = Theme.dark
}
