## Shared tutorial application state and messages.
import tc.Theme
import rr.Assets

import pages/Floating
import pages/Image
import pages/Layout
import pages/Text

App := [].{
	Page : [LayoutPage, TextPage, FloatingPage, ImagePage]

	Model : {
		page : Page,
		layout : Layout.Model,
		text : Text.Model,
		floating : Floating.Model,
		image : Image.Model,
	}

	Msg : [ChoosePage(Page), LayoutMessage(Layout.Msg), TextMessage(Text.Msg), FloatingMessage(Floating.Msg), ImageMessage(Image.Msg)]

	theme : Theme
	theme = Theme.dark

	init! = |startup| {
		assets = Assets.open!(startup.files().open_dir_read!("examples/assets")?, IgnoreManifest)?
		image = Image.init!(assets)?
		Ok({ page: LayoutPage, layout: Layout.initial, text: Text.initial, floating: Floating.initial, image })
	}

	update : Model, Msg -> Model
	update = |model, msg| match msg {
		ChoosePage(page) => { ..model, page }
		LayoutMessage(message) => { ..model, layout: Layout.update(model.layout, message) }
		TextMessage(message) => { ..model, text: Text.update(model.text, message) }
		FloatingMessage(message) => { ..model, floating: Floating.update(model.floating, message) }
		ImageMessage(message) => { ..model, image: Image.update(model.image, message) }
	}
}
