## The grouped lesson navigation column.
import tc.Element exposing [box, style]
import tc.Program exposing [View]

import ../App
import ../widgets/LessonNav

Nav := [].{
	view : App.Model -> View(App.Msg)
	view = |model| box(
		{
			style: |_| style.width(Fixed(284)).direction(Col).gap(20).pad(28, 20, 28, 20).child_align({ x: Start, y: Start }).background(App.theme.palette.surface.base.fill).border({ color: App.theme.palette.edge.border, left: 0, right: 1, top: 0, bottom: 0 }).overflow(Hidden, Scroll),
		},
		[
			LessonNav.section(
				App.theme,
				"LAYOUT",
				[
					lesson_button(model.page, LayoutPage, "Layout"),
					lesson_button(model.page, FloatingPage, "Floating"),
					lesson_button(model.page, TextPage, "Text"),
				],
			),
			LessonNav.section(
				App.theme,
				"LEAFS",
				[
					lesson_button(model.page, ImagePage, "Image"),
					LessonNav.item(App.theme, False, False, "Canvas", []),
				],
			),
		],
	)
}

lesson_button : App.Page, App.Page, Str -> View(App.Msg)
lesson_button = |current, page, label| LessonNav.item(App.theme, current == page, True, label, [OnClick(ChoosePage(page))])
