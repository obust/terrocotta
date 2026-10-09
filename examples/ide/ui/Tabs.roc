## Single-pane document tab strip.
import tc.Element exposing [box, style, text]
import tc.Program exposing [View]

import ../App
import Colors

Tabs := [].{
	Msg : [Activate(Str), Close(Str)]

	view : List(App.Tab), App.ActiveTab -> View(Msg)
	view = |tabs, active| box(
		{
			style: |_| style
				.width(Grow({}))
				.height(Fixed(38))
				.direction(Row)
				.child_align({ x: Start, y: Center })
				.background(Colors.tab_bar)
				.border({ color: Colors.border, left: 0, right: 0, top: 0, bottom: 1 })
				.overflow(Scroll, Hidden),
		},
		tabs.map(|tab| tab_view(tab, active == ActiveTab(tab.path))),
	)
}

tab_view : App.Tab, Bool -> View(Tabs.Msg)
tab_view = |tab, active| box(
	{
		id: Id("tab:${tab.path}"),
		style: |status| style
			.width(Fit({ min: 120, max: 220 }))
			.height(Fixed(38))
			.pad(0, 8, 0, 12)
			.gap(9)
			.child_align({ x: Start, y: Center })
			.font_size(13)
			.font_color(if active Colors.text else Colors.text_dim)
			.background(if active Colors.source else if status.hovered Colors.surface_hover else Colors.tab_bar)
			.border({ color: if active Colors.accent else Colors.border, left: 0, right: 1, top: 0, bottom: if active 2 else 0 })
			.cursor(PointingHand),
		events: [OnClick(Activate(tab.path))],
	},
	[
		box(
			{
				style: |_| style.width(Grow({ min: 70, max: 170 })).height(Fit({})).text_wrap(None).child_align({ x: Start, y: Center }),
				events: [OnClick(Activate(tab.path))],
			},
			[text(tab_label(tab))],
		),
		box(
			{
				id: Id("tab-close:${tab.path}"),
				style: |status| style
					.width(Fixed(20))
					.height(Fixed(20))
					.radius(3)
					.child_align({ x: Center, y: Center })
					.background(if status.hovered Colors.surface_active else Colors.tab_bar)
					.cursor(PointingHand),
				events: [OnClick(Close(tab.path))],
			},
			[text("x")],
		),
	],
)

tab_label : App.Tab -> Str
tab_label = |tab| match tab.document {
	Loading(_) => "${tab.title}  ..."
	_ => tab.title
}
