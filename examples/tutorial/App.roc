## Shared tutorial application state and messages.
import tc.Theme
import rr.Assets

import pages/Floating
import pages/Image
import pages/Layout
import pages/Text
import pages/Canvas

App := [].{
	PageId : [LayoutPage, TextPage, FloatingPage, ImagePage, CanvasPage]

	Page : [
		PageLayout(Layout.Model),
		PageText(Text.Model),
		PageFloating(Floating.Model),
		PageImage(Image.Model),
		PageCanvas(Canvas.Model),
	]

	Model : { store : Assets.Store, mascot : Assets.Texture, page : Page }

	Msg : [ChoosePage(PageId), LayoutMessage(Layout.Msg), TextMessage(Text.Msg), FloatingMessage(Floating.Msg), ImageMessage(Image.Msg), CanvasMessage(Canvas.Msg)]

	theme : Theme
	theme = Theme.dark

	current_page : Model -> PageId
	current_page = |model| match model.page {
		PageLayout(_) => LayoutPage
		PageText(_) => TextPage
		PageFloating(_) => FloatingPage
		PageImage(_) => ImagePage
		PageCanvas(_) => CanvasPage
	}

}
