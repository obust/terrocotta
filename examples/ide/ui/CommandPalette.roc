## Unified command palette and file finder overlay.
import rr.Font
import tc.Element exposing [box, map, style]
import tc.Program exposing [View]
import tc.Widget

import ../Workspace
import Commands
import Explorer
import Keybinds
import QuickOpen

CommandPalette := [].{
	PaletteCommand : Commands.PaletteCommand
	LauncherState : Commands.LauncherState

	Model : [Closed, QuickOpen(LauncherState), KeybindsOpen]

	Msg : [
		ShowFileFinder,
		ShowCommandPalette,
		ShowKeybinds,
		Hide,
		SetQuery(Widget.TextInputState),
		Select(U64),
		ChooseFile(Str),
		Execute(PaletteCommand),
	]

	empty_state : LauncherState
	empty_state = { query: { value: "", cursor: 0 }, selected: 0 }

	command_state : LauncherState
	command_state = { query: { value: ">", cursor: 1 }, selected: 0 }

	init : Model
	init = Closed

	open_files : Model
	open_files = QuickOpen(empty_state)

	open_commands : Model
	open_commands = QuickOpen(command_state)

	update : Model, Msg -> Model
	update = |model, message| match message {
		ShowFileFinder => open_files
		ShowCommandPalette => open_commands
		ShowKeybinds => KeybindsOpen
		Hide => Closed
		SetQuery(query) => match model {
			QuickOpen(state) => QuickOpen({ ..state, query, selected: 0 })
			_ => model
		}
		Select(selected) => match model {
			QuickOpen(state) => QuickOpen({ ..state, selected })
			_ => model
		}
		ChooseFile(_) => Closed
		Execute(_) => model
	}

	view : Font, List(Workspace.Node), Explorer.Icons, Model -> View(Msg)
	view = |font, nodes, icons, model| match model {
		Closed => empty_view
		QuickOpen(state) => QuickOpen.view(font, nodes, icons, state) |> map(quick_open_message)
		KeybindsOpen => Keybinds.view(font) |> map(|message| match message { Dismiss => Hide })
	}
}

empty_view : View(CommandPalette.Msg)
empty_view = box({ style: |_| style.width(Fixed(0)).height(Fixed(0)) }, [])

quick_open_message : QuickOpen.Msg -> CommandPalette.Msg
quick_open_message = |message| match message {
	QueryChanged(query) => SetQuery(query)
	Select(index) => Select(index)
	Choose(choice) => match choice {
		FileChoice(path) => ChooseFile(path)
		CommandChoice(command) => Execute(command)
	}
	Dismiss => Hide
}
