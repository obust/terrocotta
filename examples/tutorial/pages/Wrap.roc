## The lesson for text wrapping modes.
import tc.Element exposing [TextWrap.*, box, style, text]
import tc.Program exposing [View]
import tc.Theme
import tc.Widget exposing [button]

import ../ui/Parts
import ../widgets/CodeBlock
import ../widgets/DemoFrame

Wrap := [].{
	Model : { wrap : TextWrap }
	Msg : [SetWrap(TextWrap)]

	initial : Model
	initial = { wrap: Words }

	update : Model, Msg -> Model
	update = |model, message| match message {
		SetWrap(wrap) => { ..model, wrap }
	}

	guide : Theme, Model -> View(Msg)
	guide = |theme, model| {
		(mode_name, sample) = match model.wrap {
			Words => ("Words", "Words wrap at spaces when the line reaches the available width. This is the usual paragraph setting.")
			Newlines => ("Newlines", "This sentence stays on one line until an explicit newline appears.\nThis is the second line.")
			None => ("None", "No automatic line breaking occurs for this deliberately long raw line.")
		}
		box(
			{ style: |_| style.width(Grow({})).direction(Col).gap(theme.gap).child_align({ x: Start, y: Start }) },
			[
				Parts.heading(theme, "Text wrap"),
				Parts.copy("Text wrapping controls where a text node may form a new line. Choose a mode, then compare the preview with its style."),
				DemoFrame.view(
					theme,
					[
						box(
							{ style: |_| style.width(Fixed(300)).font_size(18).text_wrap(model.wrap).background(theme.palette.surface.base.fill).pad(12, 12, 12, 12).radius(theme.radius) },
							[text(sample)],
						),
					],
				),
				CodeBlock.view(theme, "style\n    .text_wrap(${mode_name})"),
			],
		)
	}

	controls : Theme, Model -> View(Msg)
	controls = |theme, model| box(
		{ style: |_| style.width(Grow({})).direction(Col).gap(theme.gap).child_align({ x: Start, y: Start }) },
		[
			Parts.copy("Wrap mode"),
			button(
				theme,
				if model.wrap == Words {
					Primary
				} else {
					Secondary
				},
				False,
				"Words",
				[OnClick(SetWrap(Words))],
			),
			button(
				theme,
				if model.wrap == Newlines {
					Primary
				} else {
					Secondary
				},
				False,
				"Newlines",
				[OnClick(SetWrap(Newlines))],
			),
			button(
				theme,
				if model.wrap == None {
					Primary
				} else {
					Secondary
				},
				False,
				"None",
				[OnClick(SetWrap(None))],
			),
		],
	)
}
