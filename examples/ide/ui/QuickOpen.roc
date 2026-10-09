## Floating file finder for the fixture workspace.
import rr.Assets
import rr.Devices
import rr.Font
import rr.Keys
import tc.Color
import tc.Element exposing [ImageSizing.*, box, image, style, text]
import tc.Event
import tc.Program exposing [View]
import tc.Theme
import tc.Widget

import ../App
import ../Workspace
import Colors

QuickOpen := [].{
	FileEntry : { path : Str, name : Str }

	Msg : [QueryChanged(Widget.TextInputState), Select(U64), Choose(Str), Dismiss, RetainFocus]

	files : List(Workspace.Node) -> List(FileEntry)
	files = collect_files

	matches : List(Workspace.Node), Str -> List(FileEntry)
	matches = |nodes, query| {
		needle = query.with_ascii_lowercased()
		collect_files(nodes).keep_if(
			|entry| needle.is_empty() or Str.contains(entry.path.with_ascii_lowercased(), needle),
		)
	}

	view : Font, List(Workspace.Node), App.ExplorerIcons, App.QuickOpenState -> View(Msg)
	view = |font, nodes, icons, state| {
		entries = QuickOpen.matches(nodes, state.query.value)
		selected = normalize_selection(state.selected, entries.len())
		input_theme = { ..Theme.dark, font_size: 14, radius: 4, gap: 8 }

		box(
			{
				id: Id("quick-open-scrim"),
				style: |_| style
					.width(Grow({}))
					.height(Grow({}))
					.pad(72, 20, 20, 20)
					.background(Color.with_alpha(Colors.window, 210))
					.child_align({ x: Center, y: Start })
					.floating(Floating({ target: Root, config: { ..Element.default_floating_config, z_index: 100, capture: Capture } })),
				events: [OnClick(Dismiss)],
			},
			[
				box(
					{
						id: Id("quick-open-dialog"),
						events: [OnInput(Box.box(|input, _bounds| input_messages(entries, selected, input)))],
						style: |_| style
							.width(Grow({ min: 320, max: 620 }))
							.height(Fit({ max: 410 }))
							.direction(Col)
							.background(Colors.tab_bar)
							.border({ color: Colors.border, left: 1, right: 1, top: 1, bottom: 1 })
							.radius(7)
							.overflow(Hidden, Hidden),
					},
					[
						box(
							{
								style: |_| style.width(Grow({})).height(Fit({})).pad(10, 10, 10, 10),
							},
							[
								Widget.input_text(
									input_theme,
									{
										id: Id("quick-open-input"),
										font,
										state: state.query,
										placeholder: "Search files by path",
										on_change: |query| QueryChanged(query),
									},
								),
							],
						),
						results_view(entries, selected, icons),
						box(
							{
								style: |_| style
									.width(Grow({}))
									.height(Fixed(28))
									.pad(0, 10, 0, 10)
									.font_size(11)
									.font_color(Colors.text_dim)
									.border({ color: Colors.border, left: 0, right: 0, top: 1, bottom: 0 })
									.child_align({ x: Start, y: Center }),
							},
							[text("Up/Down Navigate   Enter Open   Esc Close")],
						),
					],
				),
			],
		)
	}
}

collect_files : List(Workspace.Node) -> List(QuickOpen.FileEntry)
collect_files = |nodes| nodes.map(
	|node| match node {
		File(file) => [{ path: file.path, name: file.name }]
		Directory(dir) => collect_files(dir.children)
	},
).join()

normalize_selection : U64, U64 -> U64
normalize_selection = |selected, count| if count == 0 0 else U64.min(selected, count - 1)

next_selection : U64, U64 -> U64
next_selection = |selected, count| if count == 0 0 else (selected + 1) % count

previous_selection : U64, U64 -> U64
previous_selection = |selected, count| if count == 0 0 else if selected == 0 count - 1 else selected - 1

input_messages : List(QuickOpen.FileEntry), U64, Devices.Snapshot -> List(QuickOpen.Msg)
input_messages = |entries, selected, input| {
	count = entries.len()
	var $messages = []
	if Keys.key_pressed(input, KeyEscape) {
		$messages = $messages.append(Dismiss)
	}
	if Keys.key_pressed(input, KeyDown) {
		$messages = $messages.append(Select(next_selection(selected, count)))
	}
	if Keys.key_pressed(input, KeyUp) {
		$messages = $messages.append(Select(previous_selection(selected, count)))
	}
	if Keys.key_pressed(input, KeyEnter) {
		$messages = match entries.get(selected) {
			Ok(entry) => $messages.append(Choose(entry.path))
			Err(_) => $messages
		}
	}
	$messages
}

results_view : List(QuickOpen.FileEntry), U64, App.ExplorerIcons -> View(QuickOpen.Msg)
results_view = |entries, selected, icons| {
	children = if entries.is_empty() {
		[
			box(
				{
					style: |_| style.width(Grow({})).height(Fixed(64)).font_color(Colors.text_dim).child_align({ x: Center, y: Center }),
				},
				[text("No matching files")],
			),
		]
	} else {
		entries.map_with_index(|entry, index| result_row(entry, index, index == selected, icons.file))
	}

	box(
		{
			id: Id("quick-open-results"),
			style: |_| style
				.width(Grow({}))
				.height(Fit({ max: 300 }))
				.direction(Col)
				.child_align({ x: Start, y: Start })
				.overflow(Hidden, Scroll)
				.border({ color: Colors.border, left: 0, right: 0, top: 1, bottom: 0 }),
		},
		children,
	)
}

result_row : QuickOpen.FileEntry, U64, Bool, Assets.Texture -> View(QuickOpen.Msg)
result_row = |entry, index, selected, icon| {
	events : List(Event.Handler(QuickOpen.Msg))
	events = [OnClick(Choose(entry.path)), OnPointerEnter(Select(index))]
	box(
		{
			id: Id("quick-open-result:${entry.path}"),
			style: |status| style
				.width(Grow({}))
				.height(Fixed(34))
				.pad(0, 12, 0, 12)
				.gap(9)
				.font_size(13)
				.font_color(if selected Colors.text else Colors.text_dim)
				.background(if selected Colors.surface_active else if status.hovered Colors.surface_hover else Colors.tab_bar)
				.child_align({ x: Start, y: Center })
				.cursor(PointingHand),
			events,
		},
		[
			box(
				{ style: |_| style.width(Fixed(18)).height(Fixed(18)).child_align({ x: Center, y: Center }), events },
				[image(icon, { width: Pixels(16), height: Pixels(16) })],
			),
			box(
				{ style: |_| style.width(Grow({})).height(Fit({})).text_wrap(None).child_align({ x: Start, y: Center }), events },
				[text(entry.path)],
			),
		],
	)
}

expect normalize_selection(9, 3) == 2
expect next_selection(2, 3) == 0
expect previous_selection(0, 3) == 2

expect {
	entries : List(QuickOpen.FileEntry)
	entries = [
		{ path: "a.html", name: "a.html" },
		{ path: "b.html", name: "b.html" },
	]
	input_messages(entries, 0, Devices.none.with_key_pressed(KeyDown)) == [Select(1)]
		and input_messages(entries, 1, Devices.none.with_key_pressed(KeyEnter)) == [Choose("b.html")]
			and input_messages(entries, 0, Devices.none) == []
}

expect {
	nodes : List(Workspace.Node)
	nodes = [
		Directory({
			path: "components",
			name: "components",
			children: [File({ path: "components/card.html", name: "card.html" })],
		}),
		File({ path: "index.html", name: "index.html" }),
	]
	QuickOpen.matches(nodes, "CARD").map(|entry| entry.path) == ["components/card.html"]
}
