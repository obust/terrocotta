## Sev-inspired read-only IDE example.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst",
	tc: "../../package/main.roc",
}

import rr.App as RayApp
import rr.Assets
import rr.Capture
import rr.Devices
import rr.Files
import rr.Font
import rr.Keys
import rr.Task
import tc.Element exposing [box, map, style, text]
import tc.Event
import tc.Program

import App
import Workspace
import ui/Colors
import ui/Explorer
import ui/Keybinds
import ui/QuickOpen
import ui/SourceView
import ui/StatusBar
import ui/Tabs

Model : Program.State(App.Model, App.Msg)

Msg : App.Msg

workspace_dir = "examples/ide/workspace"

font_path = "examples/ide/Inter-Regular.ttf"

assets_path = "examples/ide/assets"

capture_flag = "--capture"

capture_recording = Capture.default
	.with_path("ide.png")
	.with_format(Png)
	.with_max_frames(1)
	.with_scale(Full)
	.with_timing(FixedStep)

configure : List(Str) -> RayApp.Config
configure = |args| {
	base = RayApp.default
		.with_title("Sev / Terrocotta")
		.with_size({ width: 1280, height: 800 })
		.with_resizable(True)
		.with_exit_key(NoExitKey)
		.with_permission(Directory("examples/ide", ReadOnly))
		.with_default_font({ path: font_path, size: 36 })
		.with_output_dir("captures")
		.with_frame_pacing(Uncapped)
	if args.contains(capture_flag) base.with_recording(capture_recording) else base
}

init! : RayApp.InitCallback(
	App.Model,
	[
		PermissionDenied,
		PathInvalid,
		NotFound,
		NotADirectory,
		AccessRefused,
		OpenFailed,
		Unavailable,
		ReadFailed,
		Busy,
		TooLarge,
		NotUtf8,
		AssetPathInvalid,
		AssetNotFound,
		AssetReadFailed,
		FontLoadFailed,
		RootNotFound,
		RootNotDirectory,
		RootUnreadable,
		InvalidExpectedContentHash,
		ManifestMissing,
		ManifestUnreadable,
		ManifestMalformed,
		AssetSetMismatch,
		SchemaMismatch,
		ContentVersionMismatch,
		ContentHashMismatch,
		TextureLoadFailed,
		ResourceLimit,
	],
)
init! = |io| {
	if io.args!().contains(capture_flag) {
		_ = io.capture().start!(capture_recording) ? |_| Exit(1)
	}
	workspace = io.files().open_dir_read!(workspace_dir)?
	tree = Workspace.discover!(workspace)?
	font = io.default_font!()?
	assets = Assets.open!(io.files().open_dir_read!(assets_path)?, IgnoreManifest)?
	icons : App.ExplorerIcons
	icons = {
		file: Assets.load_texture!(assets, "file.png")?,
		directory_closed: Assets.load_texture!(assets, "directory-closed.png")?,
		directory_open: Assets.load_texture!(assets, "directory-open.png")?,
	}
	initial_path = "index.html"
	initial_content = workspace.read_text!(initial_path)?
	initial_tab : App.Tab
	initial_tab = {
		path: initial_path,
		title: App.basename(initial_path),
		document: Ready(App.document(initial_path, initial_content)),
	}
	Ok({
		workspace,
		tree,
		expanded: Set.empty(),
		tabs: [initial_tab],
		active: ActiveTab(initial_path),
		next_load_id: 1,
		font,
		icons,
		explorer_width: 260,
		explorer_resizing: Bool.False,
		overlay: OverlayClosed,
	})
}

update! : App.Model, App.Msg, RayApp.Io, RayApp.Input(App.Msg) => App.Model
update! = |model, message, _io, input| match message {
	ToggleDirectory(path) => {
		expanded = if model.expanded.contains(path) model.expanded.remove(path) else model.expanded.insert(path)
		{ ..model, expanded }
	}

	OpenFile(path) => open_file!(model, path, input)

	FileLoaded(load_id, path, result) => {
		tabs = model.tabs.map(
			|tab| {
				if tab.path == path and tab.document == Loading(load_id) {
					document = match result {
						Ok(content) => Ready(App.document(path, content))
						Err(error) => Failed(App.read_error(error))
					}
					{ ..tab, document }
				} else {
					tab
				}
			},
		)
		{ ..model, tabs }
	}

	ActivateTab(path) => { ..model, active: ActiveTab(path) }

	CloseTab(path) => close_tab(model, path)

	ShowFileFinder => {
		..model,
		overlay: QuickOpen(empty_launcher_state),
	}

	ShowCommandPalette => { ..model, overlay: QuickOpen(command_launcher_state) }

	ShowKeybinds => { ..model, overlay: KeybindsOpen }

	HideOverlay => { ..model, overlay: OverlayClosed }

	SetQuickOpenQuery(query) => match model.overlay {
		QuickOpen(state) => { ..model, overlay: QuickOpen({ ..state, query, selected: 0 }) }
		_ => model
	}

	SelectQuickOpen(selected) => match model.overlay {
		QuickOpen(state) => { ..model, overlay: QuickOpen({ ..state, selected }) }
		_ => model
	}

	ChooseFile(path) => open_file!({ ..model, overlay: OverlayClosed }, path, input)

	ExecuteCommand(command) => execute_command!(model, command, input)

	StartExplorerResize => { ..model, explorer_resizing: Bool.True }

	ResizeExplorer(delta) => { ..model, explorer_width: clamp_explorer_width(model.explorer_width + delta) }

	EndExplorerResize => { ..model, explorer_resizing: Bool.False }
}

empty_launcher_state : App.LauncherState
empty_launcher_state = { query: { value: "", cursor: 0 }, selected: 0 }

command_launcher_state : App.LauncherState
command_launcher_state = { query: { value: ">", cursor: 1 }, selected: 0 }

execute_command! : App.Model, App.PaletteCommand, RayApp.Input(App.Msg) => App.Model
execute_command! = |model, command, _input| match command {
	FindFile => { ..model, overlay: QuickOpen(empty_launcher_state) }
	ShowKeyboardShortcuts => { ..model, overlay: KeybindsOpen }
	CloseActiveEditor => match model.active {
		NoActiveTab => { ..model, overlay: OverlayClosed }
		ActiveTab(path) => close_tab({ ..model, overlay: OverlayClosed }, path)
	}
}

open_file! : App.Model, Str, RayApp.Input(App.Msg) => App.Model
open_file! = |model, path, input| match model.tabs.find_first(|tab| tab.path == path) {
	Ok(_) => { ..model, active: ActiveTab(path) }
	Err(_) => {
		load_id = model.next_load_id
		workspace = model.workspace
		Task.spawn!(input, || FileLoaded(load_id, path, workspace.read_text!(path)))
		tab : App.Tab
		tab = { path, title: App.basename(path), document: Loading(load_id) }
		{ ..model, tabs: model.tabs.append(tab), active: ActiveTab(path), next_load_id: load_id + 1 }
	}
}

clamp_explorer_width : F32 -> F32
clamp_explorer_width = |width| F32.max(180, F32.min(420, width))

close_tab : App.Model, Str -> App.Model
close_tab = |model, path| match tab_index(model.tabs, path, 0) {
	Err(_) => model
	Ok(index) => {
		tabs = model.tabs.drop_at(index)
		active = if model.active != ActiveTab(path) {
			model.active
		} else {
			match tabs.get(index) {
				Ok(tab) => ActiveTab(tab.path)
				Err(_) => match tabs.last() {
					Ok(tab) => ActiveTab(tab.path)
					Err(_) => NoActiveTab
				}
			}
		}
		{ ..model, tabs, active }
	}
}

tab_index : List(App.Tab), Str, U64 -> Try(U64, [NotFound])
tab_index = |tabs, path, index| {
	if index >= tabs.len() {
		Err(NotFound)
	} else {
		match tabs.get(index) {
			Ok(tab) => if tab.path == path Ok(index) else tab_index(tabs, path, index + 1)
			Err(_) => Err(NotFound)
		}
	}
}

view : App.Model -> Program.View(App.Msg)
view = |model| {
	document = match App.active_tab(model) {
		Ok(tab) => SourceView.view(model.font, tab)
		Err(_) => SourceView.empty
	}

	content = [
		header(model),
		box(
			{ style: |_| style.direction(Row) },
			[
				Explorer.view(model.tree, model.expanded, model.active, model.icons, model.explorer_width) |> map(explorer_message),
				explorer_splitter(model.explorer_resizing),
				box(
					{ style: |_| style.direction(Col).background(Colors.source) },
					[
						Tabs.view(model.tabs, model.active) |> map(tabs_message),
						document,
					],
				),
			],
		),
		StatusBar.view(model.active, model.tabs),
	]

	children = match model.overlay {
		OverlayClosed => content
		QuickOpen(state) => content.append(QuickOpen.view(model.font, model.tree, model.icons, state) |> map(quick_open_message))
		KeybindsOpen => content.append(Keybinds.view(model.font) |> map(keybinds_message))
	}

	box(
		{
			style: |_| style
				.direction(Col)
				.background(Colors.window)
				.font_family(model.font)
				.font_size(14)
				.font_color(Colors.text),
			events: [
				OnInput(Box.box(shortcut_messages)),
			],
		},
		children,
	)
}

shortcut_messages : Devices.Snapshot, Event.ElementBounds -> List(App.Msg)
shortcut_messages = |input, _bounds| {
	modifier_down = Keys.key_down(input, KeyLeftSuper)
		or Keys.key_down(input, KeyRightSuper)
			or Keys.key_down(input, KeyLeftControl)
				or Keys.key_down(input, KeyRightControl)
	shift_down = Keys.key_down(input, KeyLeftShift) or Keys.key_down(input, KeyRightShift)
	if modifier_down and Keys.key_pressed(input, KeyP) {
		if shift_down [ShowCommandPalette] else [ShowFileFinder]
	} else if modifier_down and Keys.key_pressed(input, KeyK) {
		[ShowKeybinds]
	} else if modifier_down and !shift_down and Keys.key_pressed(input, KeyW) {
		[ExecuteCommand(CloseActiveEditor)]
	} else {
		[]
	}
}

explorer_splitter : Bool -> Program.View(App.Msg)
explorer_splitter = |resizing| box(
	{
		id: Id("explorer-splitter"),
		style: |status| style
			.width(Fixed(5))
			.height(Grow({}))
			.background(if resizing or status.hovered Colors.accent else Colors.border)
			.cursor(ResizeEastWest),
		events: [
			OnDragStart(Box.box(|_| StartExplorerResize)),
			OnDragMove(Box.box(|event| ResizeExplorer(event.delta.x))),
			OnDragEnd(Box.box(|_| EndExplorerResize)),
		],
	},
	[],
)

header : App.Model -> Program.View(App.Msg)
header = |_model| {
	command_events = [OnClick(ShowCommandPalette)]
	box(
		{
			style: |_| style
				.width(Grow({}))
				.height(Fixed(40))
				.direction(Row)
				.pad(0, 12, 0, 12)
				.gap(10)
				.background(Colors.explorer)
				.border({ color: Colors.border, left: 0, right: 0, top: 0, bottom: 1 })
				.child_align({ x: Start, y: Center }),
		},
		[
			box(
				{
					style: |_| style
						.width(Fit({}))
						.height(Fit({}))
						.direction(Row)
						.gap(10)
						.child_align({ x: Start, y: Center }),
				},
				[
					box({ style: |_| style.width(Fit({})).height(Fit({})).font_color(Colors.accent) }, [text("TERROCOTTA")]),
					text("/"),
					box({ style: |_| style.width(Fit({})).height(Fit({})).font_color(Colors.text_dim) }, [text("IDE")]),
				],
			),
			box(
				{
					id: Id("commands-trigger"),
					style: |status| style
						.width(Fixed(600))
						.height(Fixed(26))
						.pad(0, 10, 0, 10)
						.font_size(12)
						.font_color(if status.hovered Colors.text else Colors.text_dim)
						.background(if status.hovered Colors.surface_hover else Colors.surface_active)
						.border({ color: if status.hovered Colors.accent else Colors.border, left: 1, right: 1, top: 1, bottom: 1 })
						.radius(4)
						.direction(Row)
						.child_align({ x: Start, y: Center })
						.floating(Floating({ target: Parent, config: { ..Element.default_floating_config, z_index: 1, attach_points: { element: Center, target: Center } } }))
						.cursor(IBeam),
					events: command_events,
				},
				[
					box(
						{ style: |_| style.width(Grow({})).height(Fit({})).child_align({ x: Start, y: Center }), events: command_events },
						[text("Commands")],
					),
					box(
						{ style: |_| style.width(Fit({})).height(Fit({})).font_size(11).font_color(Colors.text_dim).child_align({ x: End, y: Center }), events: command_events },
						[text("Cmd/Ctrl+Shift+P")],
					),
				],
			),
			box({ style: |_| style.width(Grow({})).height(Fit({})) }, []),
		],
	)
}

explorer_message : Explorer.Msg -> App.Msg
explorer_message = |message| match message {
	Toggle(path) => ToggleDirectory(path)
	Open(path) => OpenFile(path)
}

tabs_message : Tabs.Msg -> App.Msg
tabs_message = |message| match message {
	Activate(path) => ActivateTab(path)
	Close(path) => CloseTab(path)
}

quick_open_message : QuickOpen.Msg -> App.Msg
quick_open_message = |message| match message {
	QueryChanged(query) => SetQuickOpenQuery(query)
	Select(index) => SelectQuickOpen(index)
	Choose(choice) => match choice {
		FileChoice(path) => ChooseFile(path)
		CommandChoice(command) => ExecuteCommand(command)
	}
	Dismiss => HideOverlay
}

keybinds_message : Keybinds.Msg -> App.Msg
keybinds_message = |message| match message {
	Dismiss => HideOverlay
}

program = Program.new(configure, init!, update!, view)

expect {
	tabs : List(App.Tab)
	tabs = [
		{ path: "a.html", title: "a.html", document: Failed("test") },
		{ path: "b.html", title: "b.html", document: Failed("test") },
	]
	tab_index(tabs, "b.html", 0) == Ok(1)
}

test_tab : Str -> App.Tab
test_tab = |path| { path, title: App.basename(path), document: Failed("test") }

test_model : List(App.Tab), App.ActiveTab -> App.Model
test_model = |tabs, active| {
	workspace: Files.ReadDir.stub,
	tree: [],
	expanded: Set.empty(),
	tabs,
	active,
	next_load_id: 0,
	font: Font.stub,
	icons: {
		file: Assets.Texture.stub,
		directory_closed: Assets.Texture.stub,
		directory_open: Assets.Texture.stub,
	},
	explorer_width: 260,
	explorer_resizing: Bool.False,
	overlay: OverlayClosed,
}

expect clamp_explorer_width(120) == 180
	and clamp_explorer_width(300) == 300
		and clamp_explorer_width(500) == 420

expect {
	bounds = { x: 0, y: 0, width: 1280, height: 800 }
	command_input = Devices.none.with_key_down(KeyLeftSuper).with_key_down(KeyLeftShift).with_key_pressed(KeyP)
	file_input = Devices.none.with_key_down(KeyLeftSuper).with_key_pressed(KeyP)
	keybinds_input = Devices.none.with_key_down(KeyLeftControl).with_key_pressed(KeyK)
	close_input = Devices.none.with_key_down(KeyLeftSuper).with_key_pressed(KeyW)
	shortcut_messages(command_input, bounds) == [ShowCommandPalette]
		and shortcut_messages(file_input, bounds) == [ShowFileFinder]
			and shortcut_messages(keybinds_input, bounds) == [ShowKeybinds]
				and shortcut_messages(close_input, bounds) == [ExecuteCommand(CloseActiveEditor)]
}

expect {
	model = test_model([test_tab("a.html"), test_tab("b.html"), test_tab("c.html")], ActiveTab("b.html"))
	closed = close_tab(model, "b.html")
	closed.tabs.map(|tab| tab.path) == ["a.html", "c.html"] and closed.active == ActiveTab("c.html")
}

expect {
	model = test_model([test_tab("a.html"), test_tab("b.html")], ActiveTab("b.html"))
	closed = close_tab(model, "b.html")
	closed.tabs.map(|tab| tab.path) == ["a.html"] and closed.active == ActiveTab("a.html")
}

expect {
	model = test_model([test_tab("a.html")], ActiveTab("a.html"))
	closed = close_tab(model, "a.html")
	closed.tabs.is_empty() and closed.active == NoActiveTab
}
