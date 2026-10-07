## The lesson for text wrapping modes.
import tc.Color
import rr.Assets

import tc.Element exposing [ChildAlign.*, ElementId.*, TextAlign.*, TextWrap.*, box, style, text]
import tc.Program exposing [View]
import tc.Theme
import tc.Widget exposing [select, slider]

import ../UI

Text := [].{
	Model : { wrap : TextWrap, wrap_open : Bool, child_align : { x : ChildAlign, y : ChildAlign }, child_align_x_open : Bool, child_align_y_open : Bool, font_size : F32, spacing : F32, line_height : F32, align : TextAlign, align_open : Bool }
	Msg : [SetWrap(TextWrap), ToggleWrap(Bool), SetChildAlignX(ChildAlign), ToggleChildAlignX(Bool), SetChildAlignY(ChildAlign), ToggleChildAlignY(Bool), SetFontSize(F32), SetSpacing(F32), SetLineHeight(F32), SetAlign(TextAlign), ToggleAlign(Bool)]

	init : Assets.Store -> Model
	init = |_store| { wrap: Words, wrap_open: False, child_align: { x: Start, y: Start }, child_align_x_open: False, child_align_y_open: False, font_size: 18, spacing: 1, line_height: 24, align: Left, align_open: False }

	update : Model, Msg -> Model
	update = |model, message| match message {
		SetWrap(wrap) => { ..model, wrap }
		ToggleWrap(wrap_open) => { ..model, wrap_open }
		SetChildAlignX(x) => { ..model, child_align: { ..model.child_align, x } }
		ToggleChildAlignX(child_align_x_open) => { ..model, child_align_x_open }
		SetChildAlignY(y) => { ..model, child_align: { ..model.child_align, y } }
		ToggleChildAlignY(child_align_y_open) => { ..model, child_align_y_open }
		SetFontSize(font_size) => { ..model, font_size }
		SetSpacing(spacing) => { ..model, spacing }
		SetLineHeight(line_height) => { ..model, line_height }
		SetAlign(align) => { ..model, align }
		ToggleAlign(align_open) => { ..model, align_open }
	}

	view : Theme, Model -> View(Msg)
	view = |theme, model| UI.page_layout(
	    theme,
		guide(theme, model),
		controls(theme, model)
	)
}

guide : Theme, Model -> List(View(Msg))
guide = |theme, model| {
	sample = "Lorem ipsum dolor sit amet consectetur adipiscing elit. \nSit amet consectetur adipiscing elit quisque faucibus ex. \nAdipiscing elit quisque faucibus ex sapien vitae pellentesque."
	[
		UI.heading(theme, "Text"),
		UI.p("A text element inherits typography properties from the box hierarchy. Use font size, spacing, and line height to shape the text; text alignment and wrapping control its lines, while child alignment positions the text element inside its parent."),
		UI.code_preview(
			theme,
			[
				box(
					{ id: Id("container"), style: |_| style.width(Fixed(300)).font_size(model.font_size).spacing(model.spacing).line_height(model.line_height).text_align(model.align).text_wrap(model.wrap).child_align(model.child_align).background(Color.with_alpha(UI.palette_color(0), 0)).border({ color: UI.palette_color(0), left: 1, right: 1, top: 1, bottom: 1 }).pad(12, 12, 12, 12) },
					[UI.box_id("container", UI.palette_color(0)), text(sample)],
				),
			],
		),
		UI.code_block(
			theme,
			UI.format("box({ id: Id(\"container\"), style: |_| style... }, [text(\"Lorem ipsum ...\")])"),
		),
	]
}

controls : Theme, Model -> List(View(Msg))
controls = |theme, model| [
	UI.control_group(
		theme,
		UI.palette_color(0),
		[
		UI.box_id("container", UI.palette_color(0)),
		UI.code_text(theme, ".child_align({ x: ${child_align_name(model.child_align.x)}, y: ${child_align_name(model.child_align.y)} })"),
			box(
				{ style: |_| style.width(Grow({})).height(Fit({})).direction(Row).gap(theme.gap / 2).child_align({ x: Start, y: Start }) },
				[
					select(theme, { open: model.child_align_x_open, selected: child_align_selected(model.child_align.x), options: child_align_options, on_toggle_open: |open| ToggleChildAlignX(open), on_select: |index| SetChildAlignX(child_align_from(index)) }),
					select(theme, { open: model.child_align_y_open, selected: child_align_selected(model.child_align.y), options: child_align_options, on_toggle_open: |open| ToggleChildAlignY(open), on_select: |index| SetChildAlignY(child_align_from(index)) }),
				],
			),
		UI.code_text(theme, ".text_wrap(${wrap_name(model.wrap)})"),
			select(theme, { open: model.wrap_open, selected: wrap_selected(model.wrap), options: wrap_options, on_toggle_open: |open| ToggleWrap(open), on_select: |index| SetWrap(wrap_from(index)) }),
		UI.code_text(theme, ".text_align(${align_name(model.align)})"),
			select(theme, { open: model.align_open, selected: align_selected(model.align), options: align_options, on_toggle_open: |open| ToggleAlign(open), on_select: |index| SetAlign(align_from(index)) }),
		UI.code_text(theme, ".font_size(${model.font_size.to_str()})"),
			slider(theme, model.font_size, 10, 32, 2, |font_size| SetFontSize(font_size)),
		UI.code_text(theme, ".line_height(${model.line_height.to_str()})"),
			slider(theme, model.line_height, 12, 40, 4, |line_height| SetLineHeight(line_height)),
		UI.code_text(theme, ".spacing(${model.spacing.to_str()})"),
			slider(theme, model.spacing, 0, 4, 0.5, |spacing| SetSpacing(spacing)),
		],
	),
]

wrap_options : List(Str)
wrap_options = ["Words", "Newlines", "None"]

wrap_selected : TextWrap -> U64
wrap_selected = |wrap| match wrap {
	Words => 0
	Newlines => 1
	None => 2
}

wrap_from : U64 -> TextWrap
wrap_from = |index| match index {
	0 => Words
	1 => Newlines
	_ => None
}

wrap_name : TextWrap -> Str
wrap_name = |wrap| match wrap {
	Words => "Words"
	Newlines => "Newlines"
	None => "None"
}

child_align_options : List(Str)
child_align_options = ["Start", "Center", "End"]

child_align_selected : ChildAlign -> U64
child_align_selected = |align| match align {
	Start => 0
	Center => 1
	End => 2
}

child_align_from : U64 -> ChildAlign
child_align_from = |index| match index {
	0 => Start
	1 => Center
	_ => End
}

child_align_name : ChildAlign -> Str
child_align_name = |align| match align {
	Start => "Start"
	Center => "Center"
	End => "End"
}

align_options : List(Str)
align_options = ["Left", "Center", "Right"]

align_selected : TextAlign -> U64
align_selected = |align| match align {
	Left => 0
	Center => 1
	Right => 2
}

align_from : U64 -> TextAlign
align_from = |index| match index {
	0 => Left
	1 => Center
	_ => Right
}

align_name : TextAlign -> Str
align_name = |align| match align {
	Left => "Left"
	Center => "Center"
	Right => "Right"
}
