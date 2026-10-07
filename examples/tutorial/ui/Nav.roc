## The grouped lesson navigation column.
import tc.Element exposing [ImageSizing.*, box, image, style, text]
import tc.Event
import tc.Program exposing [View]
import tc.Theme
import rr.Assets

import ../App

Nav := [].{
	nav_item : Theme, Bool, Bool, Str, List(Event.Handler(msg)) -> View(msg)
	nav_item = |theme, active, enabled, label, events| {
		color = if active {
			theme.palette.surface.base.content
		} else if enabled {
			theme.palette.surface.base.content
		} else {
			theme.palette.text.muted
		}
		box(
			{
				style: |status| {
					base = style.width(Grow({})).height(Fit({})).pad(6, 8, 6, 16).font_color(color).background(
						if active {
							theme.palette.primary.weak.fill
						} else {
							theme.palette.surface.base.fill
						},
					).radius(4).child_align({ x: Start, y: Center }).cursor(PointingHand)
					if enabled and status.hovered {
						base.background(theme.palette.surface.subtle.fill)
					} else {
						base
					}
				},
				events: if enabled {
					events
				} else {
					[]
				},
			},
			[text(label)],
		)
	}

	nav : Theme, Assets.Texture, App.PageId -> View(App.Msg)
	nav = |theme, mascot, page| box(
		{
			style: |_| style
				.width(Fixed(150))
				.direction(Col)
				.gap(theme.gap)
				.pad(theme.gap * 4, theme.gap * 2, theme.gap * 2, theme.gap * 2)
				.child_align({ x: Start, y: Start })
				.background(App.theme.palette.surface.base.fill)
				.border({ color: App.theme.palette.edge.border, left: 0, right: 1, top: 0, bottom: 0 })
				.overflow(Hidden, Scroll),
		},
		[
			box(
				{ style: |_| style.height(Fit({})).child_align({ x: Center, y: Center }) },
				[image(mascot, { width: Pixels(90), height: Pixels(90) })],
			),
			nav_button(page, LayoutPage, "Layout"),
			nav_button(page, FloatingPage, "Floating"),
			nav_button(page, TextPage, "Text"),
			nav_button(page, ImagePage, "Image"),
			nav_button(page, CanvasPage, "Canvas"),
		],
	)
}

nav_button : App.PageId, App.PageId, Str -> View(App.Msg)
nav_button = |current, page, label| Nav.nav_item(App.theme, current == page, True, label, [OnClick(ChoosePage(page))])
