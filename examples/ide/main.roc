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
		quick_open: QuickOpenClosed,
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

	ShowQuickOpen => {
		..model,
		quick_open: QuickOpenOpen({ query: { value: "", cursor: 0 }, selected: 0 }),
	}

	HideQuickOpen => { ..model, quick_open: QuickOpenClosed }

	SetQuickOpenQuery(query) => match model.quick_open {
		QuickOpenClosed => model
		QuickOpenOpen(state) => { ..model, quick_open: QuickOpenOpen({ ..state, query, selected: 0 }) }
	}

	SelectQuickOpen(selected) => match model.quick_open {
		QuickOpenClosed => model
		QuickOpenOpen(state) => { ..model, quick_open: QuickOpenOpen({ ..state, selected }) }
	}

	ChooseQuickOpen(path) => open_file!({ ..model, quick_open: QuickOpenClosed }, path, input)

	StartExplorerResize => { ..model, explorer_resizing: Bool.True }

	ResizeExplorer(delta) => { ..model, explorer_width: clamp_explorer_width(model.explorer_width + delta) }

	EndExplorerResize => { ..model, explorer_resizing: Bool.False }
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

	children = match model.quick_open {
		QuickOpenClosed => content
		QuickOpenOpen(state) => content.append(QuickOpen.view(model.font, model.tree, model.icons, state) |> map(quick_open_message))
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
				OnInput(Box.box(quick_open_input_messages)),
			],
		},
		children,
	)
}

quick_open_input_messages : Devices.Snapshot, Event.ElementBounds -> List(App.Msg)
quick_open_input_messages = |input, _bounds| {
	modifier_down = Keys.key_down(input, KeyLeftSuper)
		or Keys.key_down(input, KeyRightSuper)
			or Keys.key_down(input, KeyLeftControl)
				or Keys.key_down(input, KeyRightControl)
	if modifier_down and Keys.key_pressed(input, KeyP) [ShowQuickOpen] else []
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
header = |model| {
	path = match model.active {
		NoActiveTab => "No file open"
		ActiveTab(active_path) => active_path
	}
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
			box({ style: |_| style.width(Fit({})).height(Fit({})).font_color(Colors.accent) }, [text("SEV")]),
			text("/"),
			box({ style: |_| style.width(Fit({})).height(Fit({})).font_color(Colors.text_dim) }, [text("TERROCOTTA")]),
			box({ style: |_| style.width(Grow({})).height(Fit({})) }, []),
			box(
				{
					id: Id("quick-open-trigger"),
					style: |status| style
						.width(Fit({}))
						.height(Fixed(26))
						.pad(0, 10, 0, 10)
						.font_size(12)
						.font_color(if status.hovered Colors.text else Colors.text_dim)
						.background(if status.hovered Colors.surface_hover else Colors.tab_bar)
						.border({ color: Colors.border, left: 1, right: 1, top: 1, bottom: 1 })
						.radius(4)
						.child_align({ x: Center, y: Center })
						.cursor(PointingHand),
					events: [OnClick(ShowQuickOpen)],
				},
				[text("Open file   Cmd/Ctrl P")],
			),
			box({ style: |_| style.width(Grow({})).height(Fit({})) }, []),
			box({ style: |_| style.width(Fit({ max: 600 })).height(Fit({})).font_color(Colors.text_dim).text_wrap(None) }, [text(path)]),
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
	Choose(path) => ChooseQuickOpen(path)
	Dismiss => HideQuickOpen
	RetainFocus => ShowQuickOpen
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
	quick_open: QuickOpenClosed,
}

expect clamp_explorer_width(120) == 180
	and clamp_explorer_width(300) == 300
		and clamp_explorer_width(500) == 420

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
