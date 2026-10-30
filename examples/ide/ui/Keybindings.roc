## Shared command and keyboard-shortcut registry.
##
## Input dispatch, shortcut labels, the command palette, and the keyboard-help
## overlay all derive from `registered`, keeping behavior and presentation in
## sync. Contexts prevent an editor command from firing as a global command.
import rr.Keys
import rr.Devices

Keybindings := [].{
	Command : [ShowCommandPalette, FindFile, ShowKeyboardShortcuts, CloseActiveEditor, SaveFile, OpenFile(Str), Copy, Paste, Undo, Redo]

	Context : [Global, Editor]

	KeyChord : List(Keys.Key)

	CommandInfo : {
		command : Command,
		title : Str,
		context : Context,
		chords : List(KeyChord),
	}

	registered : List(CommandInfo)
	registered = [
		{ command: ShowCommandPalette, title: "Command Palette", context: Global, chords: [[KeyLeftControl, KeyLeftShift, KeyP]] },
		{ command: FindFile, title: "Search File", context: Global, chords: [[KeyLeftControl, KeyP]] },
		{ command: ShowKeyboardShortcuts, title: "Keyboard Shortcuts", context: Global, chords: [[KeyLeftControl, KeyK]] },
		{ command: CloseActiveEditor, title: "Close Active Editor", context: Global, chords: [[KeyLeftControl, KeyW]] },
		{ command: SaveFile, title: "Save File", context: Global, chords: [[KeyLeftControl, KeyS]] },
		{ command: Copy, title: "Copy", context: Editor, chords: [[KeyLeftControl, KeyC]] },
		{ command: Paste, title: "Paste", context: Editor, chords: [[KeyLeftControl, KeyV]] },
		{ command: Undo, title: "Undo", context: Editor, chords: [[KeyLeftControl, KeyZ]] },
		{ command: Redo, title: "Redo", context: Editor, chords: [[KeyLeftControl, KeyLeftShift, KeyZ], [KeyLeftControl, KeyY]] },
	]

	commands_for : Devices.Snapshot, Context -> List(Command)
	commands_for = commands_for_context

	shortcut_for : Command -> Str
	shortcut_for = |command| match registered.find_first(|entry| entry.command == command) {
		Ok(entry) => chords_label(entry.chords)
		Err(_) => ""
	}

	chords_label : List(KeyChord) -> Str
	chords_label = |chords| Str.join_with(chords.map(chord_label), " / ")
}

commands_for_context : Devices.Snapshot, Keybindings.Context -> List(Keybindings.Command)
commands_for_context = |input, context| match Keybindings.registered.find_first(|entry| entry.context == context and entry.chords.any(|chord| chord_pressed(input, chord))) {
	Ok(entry) => [entry.command]
	Err(_) => []
}

chord_pressed : Devices.Snapshot, Keybindings.KeyChord -> Bool
chord_pressed = |input, chord| {
	requires_shift = chord.contains(KeyLeftShift) or chord.contains(KeyRightShift)
	shift_down = Keys.key_down(input, KeyLeftShift) or Keys.key_down(input, KeyRightShift)
	modifiers_down = chord.drop_last(1).fold(Bool.True, |all_down, key| all_down and chord_key_down(input, key))
	match chord.last() {
		Ok(key) => shift_down == requires_shift and modifiers_down and Keys.key_pressed(input, key)
		Err(_) => Bool.False
	}
}

chord_key_down : Devices.Snapshot, Keys.Key -> Bool
chord_key_down = |input, key| match key {
	KeyLeftControl | KeyRightControl => Keys.key_down(input, KeyLeftSuper)
		or Keys.key_down(input, KeyRightSuper)
		or Keys.key_down(input, KeyLeftControl)
		or Keys.key_down(input, KeyRightControl)
	KeyLeftShift | KeyRightShift => Keys.key_down(input, KeyLeftShift) or Keys.key_down(input, KeyRightShift)
	_ => Keys.key_down(input, key)
}

chord_label : Keybindings.KeyChord -> Str
chord_label = |chord| Str.join_with(chord.map(key_label), "+")

key_label : Keys.Key -> Str
key_label = |key| match key {
	KeyLeftControl | KeyRightControl => "Cmd/Ctrl"
	KeyLeftShift | KeyRightShift => "Shift"
	KeyP => "P"
	KeyK => "K"
	KeyW => "W"
	KeyS => "S"
	KeyC => "C"
	KeyV => "V"
	KeyZ => "Z"
	KeyY => "Y"
	_ => ""
}

expect Keybindings.commands_for(Devices.none.with_key_down(KeyLeftSuper).with_key_pressed(KeyC), Editor) == [Copy]

expect Keybindings.commands_for(Devices.none.with_key_down(KeyLeftSuper).with_key_pressed(KeyC), Global).is_empty()

expect Keybindings.commands_for(Devices.none.with_key_down(KeyLeftControl).with_key_down(KeyLeftShift).with_key_pressed(KeyZ), Editor) == [Redo]

expect Keybindings.commands_for(Devices.none.with_key_down(KeyLeftControl).with_key_pressed(KeyY), Editor) == [Redo]
