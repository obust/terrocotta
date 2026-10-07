## The active lesson's controls column.
import tc.Element exposing [map]
import tc.Program exposing [View]

import ../App
import ../pages/Floating
import ../pages/Image
import ../pages/Layout
import ../pages/Text
import ../widgets/TutorialShell
import ../widgets/Typography

Controls := [].{
	view : App.Model -> View(App.Msg)
	view = |model| {
		content = match model.page {
			LayoutPage => Layout.controls(App.theme, model.layout) |> map(|msg| LayoutMessage(msg))
			TextPage => Text.controls(App.theme, model.text) |> map(|msg| TextMessage(msg))
			FloatingPage => Floating.controls(App.theme, model.floating) |> map(|msg| FloatingMessage(msg))
			ImagePage => Image.controls(App.theme, model.image) |> map(|msg| ImageMessage(msg))
		}
		TutorialShell.controls_shell(App.theme, 300, [Typography.title(App.theme, "Controls"), content])
	}
}
