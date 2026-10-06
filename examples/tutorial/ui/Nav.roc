## The grouped lesson navigation column.
import tc.Element exposing [box, style]
import tc.Program exposing [View]

import ../Tutorial
import ../widgets/LessonNav

Nav := [].{
	view : Tutorial.AppModel -> View(Tutorial.Msg)
	view = |model| box(
		{
			style: |_| style.width(Fixed(284)).direction(Col).gap(20).pad(28, 20, 28, 20).child_align({ x: Start, y: Start }).background(Tutorial.theme.palette.surface.base.fill).border({ color: Tutorial.theme.palette.edge.border, left: 0, right: 1, top: 0, bottom: 0 }).overflow(Hidden, Scroll),
		},
		[
			LessonNav.section(
				Tutorial.theme,
				"LAYOUT",
				[
					lesson_button(model.lesson, LayoutLesson, "Layout"),
					lesson_button(model.lesson, FloatingLesson, "Floating"),
					lesson_button(model.lesson, TextLesson, "Text"),
				],
			),
			LessonNav.section(
				Tutorial.theme,
				"LEAFS",
				[
					lesson_button(model.lesson, ImageLesson, "Image"),
					LessonNav.item(Tutorial.theme, False, False, "Canvas", []),
				],
			),
		],
	)
}

lesson_button : Tutorial.Lesson, Tutorial.Lesson, Str -> View(Tutorial.Msg)
lesson_button = |current, lesson, label| LessonNav.item(Tutorial.theme, current == lesson, True, label, [OnClick(ChooseLesson(lesson))])
