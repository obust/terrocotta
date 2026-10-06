## The central tutorial content column.
import tc.Element exposing [box, map, style]
import tc.Program exposing [View]

import ../Tutorial
import ../pages/Floating
import ../pages/Image
import ../pages/Layout
import ../pages/Wrap
import ../ui/Parts

Guide := [].{
	view : Tutorial.AppModel -> View(Tutorial.Msg)
	view = |model| {
		content = match model.lesson {
			LayoutLesson => Layout.guide(Tutorial.theme, model.layout) |> map(|msg| LayoutMessage(msg))
			TextWrapLesson => Wrap.guide(Tutorial.theme, model.text_wrap) |> map(|msg| TextWrapMessage(msg))
			FloatingLesson => Floating.guide(Tutorial.theme, model.floating) |> map(|msg| FloatingMessage(msg))
			ImageLesson => Image.guide(Tutorial.theme, model.image) |> map(|msg| ImageMessage(msg))
		}
		box(
			{ style: |_| style.width(Grow({ min: 420 })).direction(Col).pad(44, 48, 44, 48).child_align({ x: Center, y: Start }).overflow(Hidden, Scroll) },
			[
				box(
					{ style: |_| style.width(Grow({ min: 420, max: 672 })).direction(Col).gap(24).child_align({ x: Start, y: Start }) },
					[Parts.title(Tutorial.theme, "Guide"), content],
				),
			],
		)
	}
}
