## Single-pane document tab strip.
import tc.Color
import tc.Element exposing [box, style, text]
import tc.Program exposing [View]

import ../Theme exposing [theme]

Tab := { id : U64, title : Str, dirty : Bool, loading : Bool }
Active : [NoActiveTab, ActiveTab(U64)]

Tabs := [].{
	Msg : [Activate(U64), Close(U64)]

	view : List(Tab), Active -> View(Msg)
	view = |tabs, active| box(
		{
			style: |_| style
				.height(Fit({}))
				.direction(Row)
				.child_align({ x: Start, y: Center })
				.background(inactive_surface)
				.overflow(Scroll, Hidden),
		},
		tabs.map(|tab| tab_view(tab, active == ActiveTab(tab.id))).append(box({ style: |_| style.border({ color: theme.palette.edge.border, left: 0, right: 0, top: 0, bottom: 1 }) }, [])),
	)
}

tab_view : Tab, Bool -> View(Tabs.Msg)
tab_view = |tab, active| box(
	{
		id: Id("tab:${tab.id.to_str()}"),
		style: |status| style
			.width(Fit({ min: 120, max: 220 }))
			.height(Fit({}))
			.pad(theme.gap, theme.gap, theme.gap, theme.gap + theme.gap / 2)
			.gap(theme.gap)
			.child_align({ x: Start, y: Center })
			.font_size(13)
			.font_color(if active theme.palette.surface.base.content else theme.palette.text.muted)
			.background(if active theme.palette.surface.base.fill else if status.hovered theme.palette.hovered(theme.palette.surface.base).fill else inactive_surface)
			.border({ color: theme.palette.edge.border, left: 0, right: 1, top: 0, bottom: if active 0 else 1 })
			.cursor(PointingHand),
		events: [OnClick(Activate(tab.id))],
	},
	[
		box(
			{
				style: |_| style.width(Grow({ min: 70, max: 170 })).height(Fit({})).text_wrap(None).child_align({ x: Start, y: Center }),
				events: [OnClick(Activate(tab.id))],
			},
			[text(tab_label(tab))],
		),
		box(
			{
				id: Id("tab-close:${tab.id.to_str()}"),
				style: |status| style
					.width(Fixed(20))
					.height(Fixed(20))
					.radius(3)
					.child_align({ x: Center, y: Center })
					.background(if status.hovered theme.palette.selected(theme.palette.surface.base).fill else inactive_surface)
					.cursor(PointingHand),
				events: [OnClick(Close(tab.id))],
			},
			[text("x")],
		),
	],
)

## Keep inactive tabs close to the editor surface. The theme's built-in
## subtle surface is intentionally stronger (about 10% toward text).
inactive_surface : Color
inactive_surface = Color.mix(theme.palette.surface.base.fill, theme.palette.surface.base.content, 12)

tab_label : Tab -> Str
tab_label = |tab| if tab.loading "${tab.title}  ..." else if tab.dirty "${tab.title} *" else tab.title
