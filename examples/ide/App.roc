## Durable IDE example state and messages.
import rr.Font
import tc.Widget
import tc.Theme

import ui/Editor
import ui/Explorer
import ui/Topbar

App := [].{
	LauncherState : {
		query : Widget.TextInputState,
		selected : U64,
	}

	PaletteCommand : [FindFile, ShowKeyboardShortcuts, CloseActiveEditor]

	Overlay : [OverlayClosed, QuickOpen(LauncherState), KeybindsOpen]

	Model : {
		explorer : Explorer.Model,
		editor : Editor.Model,
		font : Font,
		overlay : Overlay,
	}

	Msg : [
		TopbarMessage(Topbar.Msg),
		ExplorerMessage(Explorer.Msg),
		EditorMessage(Editor.Msg),
		ShowFileFinder,
		ShowCommandPalette,
		ShowKeybinds,
		HideOverlay,
		SetQuickOpenQuery(Widget.TextInputState),
		SelectQuickOpen(U64),
		ChooseFile(Str),
		ExecuteCommand(PaletteCommand),
	]

	theme = Theme.dark
}
