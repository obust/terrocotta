## Theme-aware static widgets built on Element.
import widgets/Badge as Badge
import widgets/Button as Button
import widgets/Checkbox as Checkbox
import widgets/ColorPicker as ColorPicker
import widgets/Column as Column
import widgets/Heading as Heading
import widgets/InputText as InputText
import widgets/Label as Label
import widgets/Modal as Modal
import widgets/Panel as Panel
import widgets/Row as Row
import widgets/Select as Select
import widgets/Slider as Slider
import widgets/Toggle as Toggle

Widget := [].{

	## Model-owned value and UTF-8 byte cursor for a controlled text input.
	TextInputState : { value : Str, cursor : U64 }

	## Build a themed, centered dialog on a full-screen floating scrim.
	modal = Modal.modal

	## Display body text using the theme background content color.
	label = Label.label

	## Display larger heading text using the theme primary color.
	heading = Heading.heading

	input_text = InputText.input_text

	## Apply one text-input event to controlled input state without rendering a widget.
	update_text_input = InputText.update

	## Lay out children horizontally with the theme gap.
	row = Row.row

	## Lay out children vertically with the theme gap.
	column = Column.column

	## Group children on a weak background surface.
	panel = Panel.panel

	## Display a button-shaped command label with hover, press, and focus styling.
	button = Button.button

	## Display a model-owned checkbox with a text label.
	checkbox = Checkbox.checkbox

	## Display a model-owned toggle switch.
	toggle = Toggle.toggle

	## Display a compact semantic label.
	badge = Badge.badge

	## Display a horizontal slider for model-owned numeric values.
	slider = Slider.slider

	## Display a two-handle slider for an inclusive model-owned value range.
	range_slider = Slider.range_slider

	## Display a color preview.
	color_preview = ColorPicker.color_preview

	## Display a color channel slider.
	color_slider = ColorPicker.color_slider

	## Display a model-owned dropdown select with a collapsible option list.
	select = Select.select
}
