## Commands exposed through the unified Quick Open surface.
import tc.Widget

Commands := [].{
	PaletteCommand : [FindFile, ShowKeyboardShortcuts, CloseActiveEditor]

	LauncherState : {
		query : Widget.TextInputState,
		selected : U64,
	}

	Entry : {
		title : Str,
		category : Str,
		shortcut : Str,
		command : PaletteCommand,
	}

	entries : List(Entry)
	entries = [
		{ title: "Search File", category: "File", shortcut: "Cmd/Ctrl P", command: FindFile },
		{ title: "Show Keyboard Shortcuts", category: "Help", shortcut: "Cmd/Ctrl K", command: ShowKeyboardShortcuts },
		{ title: "Close Active Editor", category: "File", shortcut: "Cmd/Ctrl W", command: CloseActiveEditor },
	]

	matches : Str -> List(Entry)
	matches = |query| {
		needle = query.with_ascii_lowercased()
		Commands.entries.keep_if(
			|entry| {
				haystack = "${entry.category}: ${entry.title}".with_ascii_lowercased()
				needle.is_empty() or Str.contains(haystack, needle)
			},
		)
	}
}

expect Commands.matches("file").map(|entry| entry.command) == [FindFile, CloseActiveEditor]
expect Commands.matches("keyboard").map(|entry| entry.command) == [ShowKeyboardShortcuts]
