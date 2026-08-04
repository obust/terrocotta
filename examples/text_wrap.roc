## Text wrapping showcase with lorem ipsum paragraphs.
app [Model, program] {
    rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.8.1/4gGSRA3tcdoegEPjfkKnE8j8VC5YBW5BMZRtGs2fX5ZX.tar.zst",
	tc: "../package/main.roc",
}

import rr.Host
import rr.Draw
import tc.Color
import tc.Element exposing [Font, TextWrap.*, View, box, default_font, style, text]
import tc.Program
import tc.Theme

theme = Theme.light

font_path : Str
font_path = "examples/assets/Inter-Regular.ttf"

lorem : Str
lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Integer non sem vitae lacus gravida facilisis. Donec porttitor, justo sed luctus feugiat, nibh lorem malesuada enim, sed pulvinar erat lectus id massa."

newline_lorem : Str
newline_lorem = "Lorem ipsum dolor sit amet.\nInteger non sem vitae lacus.\nDonec porttitor justo sed luctus."

none_lorem : Str
none_lorem = "Short raw line."

Model : Program.State(AppModel, Msg)

AppModel : {
	font : Font,
}

Msg : [NoOp]

init! : Program.Config => Try(AppModel, [Exit(I64)])
init! = |_config| {
	font = Draw.load_font!({ path: font_path, size: 2 * 18 }).map_err(|_| Exit(1))?
	Ok({ font: font })
}

update : AppModel, Msg -> AppModel
update = |model, _msg| model

label : Str -> View(Msg)
label = |content| {
	box(
		Auto,
		|_| style
			.height(Fit({ min: 0, max: 10000 }))
			.child_align({ x: Start, y: Start })
			.font_color(theme.palette.primary.strong.fill)
			.font_size(theme.font_size)
			.text_wrap(None),
		[],
		[text(content)],
	)
}

paragraph : Element.TextWrap, Str -> View(Msg)
paragraph = |wrap_mode, content| {
	box(
		Auto,
		|_| style
			.height(Fit({ min: 0, max: 10000 }))
			.child_align({ x: Start, y: Start })
			.font_color(theme.palette.background.base.content)
			.font_size(theme.font_size)
			.text_wrap(wrap_mode),
		[],
		[text(content)],
	)
}

panel : Str, Element.TextWrap, Str -> View(Msg)
panel = |title, wrap_mode, content| {
	box(
		Auto,
		|_| style
			.height(Fit({ min: 0, max: 10000 }))
			.direction(Col)
			.gap(theme.gap)
			.pad((theme.gap, theme.gap, theme.gap, theme.gap))
			.background(theme.palette.background.weak.fill)
			.border({ color: theme.palette.primary.base.fill, left: 1, right: 1, top: 1, bottom: 1 })
			.radius(theme.radius),
		[],
		[
			label(title),
			paragraph(wrap_mode, content),
		],
	)
}

view : AppModel -> View(Msg)
view = |model| {
	box(
		Auto,
		|_| style
			.direction(Col)
			.gap(theme.gap)
			.pad((theme.gap, theme.gap, theme.gap, theme.gap))
			.background(theme.palette.background.base.fill)
			.font_family(model.font)
			.font_color(theme.palette.background.base.content)
			.font_size(theme.font_size),
		[],
		[
			label("Text wrapping"),
			paragraph(None, "Same lorem ipsum copy rendered with Words, Newlines, and None wrap modes."),
			box(
				Auto,
				|_| style
					.direction(Row)
					.child_align({ x: Start, y: Start })
					.gap(theme.gap),
				[],
				[
					panel("Words", Words, lorem),
					panel("Newlines", Newlines, newline_lorem),
					panel("None", None, none_lorem),
				],
			),
		],
	)
}

program : {
	init! : { config : Program.Config, run! : Host => Try(Model, [Exit(I64)]) },
	render! : Model, Host => Try(Model, [Exit(I64), ..]),
}
program = Program.new!(
	{
		config: { ..Program.default, title: "Text Wrap Example", width: 800, height: 600, resizable: Bool.True },
		init!,
		view,
		update,
	},
)
