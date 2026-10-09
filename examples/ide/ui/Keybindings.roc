import rr.Keys

Keybindings := [].{
	Command : [ShowCommandPalette, FindFile, ShowKeyboardShortcuts, CloseActiveEditor, SaveFile]

	KeyChord : List(Keys.Key)

	CommandInfo : {
		command : Command,
		title : Str,
		chord : KeyChord,
	}

	registered : List(CommandInfo)
	registered = [
		{ command: ShowCommandPalette, title: "Command Palette", chord: [KeyLeftControl, KeyLeftShift, KeyP] },
		{ command: FindFile, title: "Search File", chord: [KeyLeftControl, KeyP] },
		{ command: ShowKeyboardShortcuts, title: "Keyboard Shortcuts", chord: [KeyLeftControl, KeyK] },
		{ command: CloseActiveEditor, title: "Close Active Editor", chord: [KeyLeftControl, KeyW] },
		{ command: SaveFile, title: "Save File", chord: [KeyLeftControl, KeyS] },
	]
}
