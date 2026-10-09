## Collapsible workspace tree.
import rr.Draw
import rr.Assets
import tc.Color
import tc.Element exposing [ImageSizing.*, box, canvas, image, style, text]
import tc.Event
import tc.Program exposing [View]

import ../App
import ../Workspace
import Colors

Explorer := [].{
	Msg : [Toggle(Str), Open(Str)]

	view : List(Workspace.Node), Set(Str), App.ActiveTab, App.ExplorerIcons, F32 -> View(Msg)
	view = |nodes, expanded, active, icons, width| box(
		{
			style: |_| style
				.width(Fixed(width))
				.direction(Col)
				.background(Colors.explorer),
		},
		[
			box(
				{ style: |_| style.width(Grow({})).height(Fixed(34)).pad(0, 12, 0, 12).font_size(12).font_color(Colors.text_dim).child_align({ x: Start, y: Center }) },
				[text("EXPLORER")],
			),
			box(
				{
					style: |_| style
						.width(Grow({}))
						.direction(Col)
						.child_align({ x: Start, y: Start })
						.overflow(Hidden, Scroll),
				},
				[
					box(
						{
							style: |_| style.width(Grow({})).height(Fixed(26)).pad(0, 10, 0, 10).gap(6).font_color(Colors.text).child_align({ x: Start, y: Center }),
						},
						[
							image(icons.directory_open, { width: Pixels(16), height: Pixels(16) }),
							text("workspace"),
						],
					),
				].concat(tree_views(nodes, expanded, active, icons, [])),
			),
		],
	)
}

tree_views : List(Workspace.Node), Set(Str), App.ActiveTab, App.ExplorerIcons, List(Bool) -> List(View(Explorer.Msg))
tree_views = |nodes, expanded, active, icons, guides| {
	last_index = if nodes.is_empty() 0 else nodes.len() - 1
	nodes.map_with_index(|node, index| node_views(node, expanded, active, icons, guides, index == last_index)).join()
}

node_views : Workspace.Node, Set(Str), App.ActiveTab, App.ExplorerIcons, List(Bool), Bool -> List(View(Explorer.Msg))
node_views = |node, expanded, active, icons, guides, is_last| {
	child_guides = guides.append(!is_last)
	match node {
		Directory(dir) => {
			is_open = expanded.contains(dir.path)
			icon = if is_open icons.directory_open else icons.directory_closed
			row = tree_row("tree-dir:${dir.path}", guides, is_last, icon, dir.name, Bool.False, [OnClick(Toggle(dir.path))])
			if is_open {
				[row].concat(tree_views(dir.children, expanded, active, icons, child_guides))
			} else {
				[row]
			}
		}
		File(file) => {
			selected = active == ActiveTab(file.path)
			[tree_row("tree-file:${file.path}", guides, is_last, icons.file, file.name, selected, [OnClick(Open(file.path))])]
		}
	}
}

tree_row : Str, List(Bool), Bool, Assets.Texture, Str, Bool, List(Event.Handler(Explorer.Msg)) -> View(Explorer.Msg)
tree_row = |id, guides, is_last, icon, label, selected, events| box(
	{
		id: Id(id),
		style: |status| style
			.width(Grow({}))
			.height(Fixed(26))
			.pad(0, 8, 0, 10)
			.gap(4)
			.child_align({ x: Start, y: Center })
			.font_size(14)
			.font_color(if selected Colors.text else Colors.text_dim)
			.background(if selected Colors.surface_active else if status.hovered Colors.surface_hover else Colors.explorer)
			.cursor(PointingHand),
		events,
	},
	[
		guide_view(guides, is_last, events),
		box(
			{
				style: |_| style.width(Fixed(18)).height(Fit({})).child_align({ x: Center, y: Center }),
				events,
			},
			[image(icon, { width: Pixels(16), height: Pixels(16) })],
		),
		box(
			{
				style: |_| style.width(Grow({})).height(Fit({})).text_wrap(None).child_align({ x: Start, y: Center }),
				events,
			},
			[text(label)],
		),
	],
)

## Draw the tree's box-drawing forms (│, ├──, and └──) as geometry. Inter stays
## the default font, while the guides do not depend on its 95-glyph ASCII atlas.
guide_view : List(Bool), Bool, List(Event.Handler(msg)) -> View(msg)
guide_view = |guides, is_last, events| {
	width = (guides.len().to_f32() + 1) * 16
	box(
		{
			style: |_| style.width(Fixed(width)).height(Fixed(26)),
			events,
		},
		[
			canvas(
				|frame, bounds| {
					color = Colors.text_dim.to_rrt()
					stroke = Draw.stroke(color, 1)
					top = bounds.position.y
					bottom = top + bounds.size.h
					middle = top + bounds.size.h / 2
					var $index = 0
					for continues in guides {
						if continues {
							x = bounds.position.x + 8 + $index.to_f32() * 16
							frame.line!({ start: { x, y: top }, end: { x, y: bottom }, stroke })
						}
						$index = $index + 1
					}
					branch_x = bounds.position.x + 8 + guides.len().to_f32() * 16
					frame.line!({ start: { x: branch_x, y: top }, end: { x: branch_x, y: middle }, stroke })
					if !is_last {
						frame.line!({ start: { x: branch_x, y: middle }, end: { x: branch_x, y: bottom }, stroke })
					}
					frame.line!({ start: { x: branch_x, y: middle }, end: { x: bounds.position.x + bounds.size.w, y: middle }, stroke })
					Ok({})
				},
			),
		],
	)
}
