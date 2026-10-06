## Shared tutorial state and messages.
import tc.Theme

import pages/Floating
import pages/Image
import pages/Layout
import pages/Text

Tutorial := [].{
	Lesson : [LayoutLesson, TextLesson, FloatingLesson, ImageLesson]

	AppModel : {
		lesson : Lesson,
		layout : Layout.Model,
		text : Text.Model,
		floating : Floating.Model,
		image : Image.Model,
	}

	Msg : [ChooseLesson(Lesson), LayoutMessage(Layout.Msg), TextMessage(Text.Msg), FloatingMessage(Floating.Msg), ImageMessage(Image.Msg)]

	theme : Theme
	theme = Theme.dark

	initial = |image| { lesson: LayoutLesson, layout: Layout.initial, text: Text.initial, floating: Floating.initial, image }

	update : AppModel, Msg -> AppModel
	update = |model, msg| match msg {
		ChooseLesson(lesson) => { ..model, lesson }
		LayoutMessage(message) => { ..model, layout: Layout.update(model.layout, message) }
		TextMessage(message) => { ..model, text: Text.update(model.text, message) }
		FloatingMessage(message) => { ..model, floating: Floating.update(model.floating, message) }
		ImageMessage(message) => { ..model, image: Image.update(model.image, message) }
	}
}
