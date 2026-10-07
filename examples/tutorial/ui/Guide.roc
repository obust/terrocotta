## The central tutorial content column.
import tc.Element exposing [box, map, style]
import tc.Program exposing [View]

import ../App
import ../pages/Floating
import ../pages/Image
import ../pages/Layout
import ../pages/Text
import ../widgets/Typography

Guide := [].{
	view : App.Model -> View(App.Msg)
	view = |model| {
		content = match model.page {
			LayoutPage => Layout.guide(App.theme, model.layout) |> map(|msg| LayoutMessage(msg))
			TextPage => Text.guide(App.theme, model.text) |> map(|msg| TextMessage(msg))
			FloatingPage => Floating.guide(App.theme, model.floating) |> map(|msg| FloatingMessage(msg))
			ImagePage => Image.guide(App.theme, model.image) |> map(|msg| ImageMessage(msg))
		}
		box(
			{ style: |_| style.width(Grow({ min: 420 })).direction(Col).pad(44, 48, 44, 48).child_align({ x: Center, y: Start }).overflow(Hidden, Scroll) },
			[
				box(
					{ style: |_| style.width(Grow({ min: 420, max: 672 })).direction(Col).gap(24).child_align({ x: Start, y: Start }) },
					[Typography.title(App.theme, "Guide"), content],
				),
			],
		)
	}
}
