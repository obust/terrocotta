## Public tutorial UI façade.
import tc.Color
import tc.Element
import tc.Event
import tc.Program exposing [View]
import tc.Theme

import ui/BoxId
import ui/Code
import ui/Colors
import ui/TutorialLayout
import ui/Format
import ui/Typography

UI := [].{
	box_id : Str, Color -> View(msg)
	box_id = BoxId.box_id

	code_block : Theme, Str -> View(msg)
	code_block = Code.code_block

	code_text : Theme, Str -> View(msg)
	code_text = Code.code_text

	format : Str -> Str
	format = Format.format

	code_preview : Theme, List(View(msg)) -> View(msg)
	code_preview = Code.code_preview

	palette_color : U64 -> Color
	palette_color = Colors.palette_color

	page_layout : Theme, List(View(msg)), List(View(msg)) -> View(msg)
	page_layout = TutorialLayout.page_layout

	control_group : Theme, Color, List(View(msg)) -> View(msg)
	control_group = TutorialLayout.control_group

	title : Theme, Str -> View(msg)
	title = Typography.title

	heading : Theme, Str -> View(msg)
	heading = Typography.heading

	p : Str -> View(msg)
	p = Typography.p
}
