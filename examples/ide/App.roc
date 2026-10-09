## Durable IDE example state and messages.
import rr.Assets
import rr.Files
import rr.Font
import tc.Widget
import tc.Theme

import Workspace
import syntax/Html

App := [].{
	Language : [HtmlLanguage, PlainText]

	Document : {
		content : Str,
		language : Language,
		lines : List(Html.Line),
	}

	DocumentState : [Loading(U64), Ready(Document), Failed(Str)]

	Tab : {
		path : Str,
		title : Str,
		document : DocumentState,
	}

	ActiveTab : [NoActiveTab, ActiveTab(Str)]

	LauncherState : {
		query : Widget.TextInputState,
		selected : U64,
	}

	PaletteCommand : [FindFile, ShowKeyboardShortcuts, CloseActiveEditor]

	Overlay : [OverlayClosed, QuickOpen(LauncherState), KeybindsOpen]

	ExplorerIcons : {
		file : Assets.Texture,
		directory_closed : Assets.Texture,
		directory_open : Assets.Texture,
	}

	Model : {
		workspace : Files.ReadDir,
		tree : List(Workspace.Node),
		expanded : Set(Str),
		tabs : List(Tab),
		active : ActiveTab,
		next_load_id : U64,
		font : Font,
		icons : ExplorerIcons,
		explorer_width : F32,
		explorer_resizing : Bool,
		overlay : Overlay,
	}

	Msg : [
		ToggleDirectory(Str),
		OpenFile(Str),
		FileLoaded(U64, Str, Try(Str, Files.ReadTextError)),
		ActivateTab(Str),
		CloseTab(Str),
		ShowFileFinder,
		ShowCommandPalette,
		ShowKeybinds,
		HideOverlay,
		SetQuickOpenQuery(Widget.TextInputState),
		SelectQuickOpen(U64),
		ChooseFile(Str),
		ExecuteCommand(PaletteCommand),
		StartExplorerResize,
		ResizeExplorer(F32),
		EndExplorerResize,
	]

	document : Str, Str -> Document
	document = |path, content| {
		language = language_for(path)
		lines = match language {
			HtmlLanguage => Html.highlight(content)
			PlainText => Html.plain(content)
		}
		{ content, language, lines }
	}

	basename : Str -> Str
	basename = |path| match path.split_last("/") {
		Ok(parts) => parts.after
		Err(_) => path
	}

	language_for : Str -> Language
	language_for = |path| {
		lower = path.with_ascii_lowercased()
		if lower.ends_with(".html") or lower.ends_with(".htm") HtmlLanguage else PlainText
	}

	active_tab : Model -> Try(Tab, [NoTab])
	active_tab = |model| match model.active {
		NoActiveTab => Err(NoTab)
		ActiveTab(path) => model.tabs.find_first(|tab| tab.path == path).map_err(|_| NoTab)
	}

	read_error : Files.ReadTextError -> Str
	read_error = |error| match error {
		PermissionDenied => "Permission denied"
		PathInvalid => "The workspace path is invalid"
		NotFound => "The file no longer exists"
		ReadFailed => "The file could not be read"
		Busy => "The file service is busy"
		Unavailable => "The file service is unavailable"
		TooLarge => "This example opens UTF-8 files up to 64 KiB"
		NotUtf8 => "This file is not valid UTF-8"
	}

	theme = Theme.dark
}

language_for : Str -> App.Language
language_for = App.language_for

expect language_for("INDEX.HTML") == HtmlLanguage
expect language_for("assets/site.css") == PlainText
expect App.basename("components/card.html") == "card.html"
