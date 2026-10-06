## The active lesson's controls column.
import tc.Element exposing [map]
import tc.Program exposing [View]

import ../Tutorial
import ../pages/Floating
import ../pages/Image
import ../pages/Layout
import ../pages/Text
import ../ui/Parts

Controls := [].{
	view : Tutorial.AppModel -> View(Tutorial.Msg)
	view = |model| {
		content = match model.lesson {
			LayoutLesson => Layout.controls(Tutorial.theme, model.layout) |> map(|msg| LayoutMessage(msg))
			TextLesson => Text.controls(Tutorial.theme, model.text) |> map(|msg| TextMessage(msg))
			FloatingLesson => Floating.controls(Tutorial.theme, model.floating) |> map(|msg| FloatingMessage(msg))
			ImageLesson => Image.controls(Tutorial.theme, model.image) |> map(|msg| ImageMessage(msg))
		}
		Parts.controls_shell(Tutorial.theme, 300, [Parts.title(Tutorial.theme, "Controls"), content])
	}
}
