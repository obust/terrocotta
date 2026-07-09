## Text wrapping showcase with lorem ipsum paragraphs.
app [Model, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.7/8gdZaHEpySPZUzMBCT6RkEF9CBpcbi5F3E7QmNu4NTCU.tar.zst",
	tc: "../package/main.roc",
}

import rr.Host
import rr.Draw
import tc.Color
import tc.Element exposing [Font, TextWrap.*, View, box, default_font, style, text]
import tc.Layout
import tc.Program
import tc.Render

RayDraw := [].{
	begin_frame! : {} => {}
	begin_frame! = |_| Draw.begin_frame!()

	clear! : Color => {}
	clear! = |color| Draw.clear!({ r: color.r, g: color.g, b: color.b, a: color.a })

	measure_text_raw! : Layout.MeasureTextFn
	measure_text_raw! = |text_cfg| Draw.measure_text_raw!({ text: text_cfg.text, size: text_cfg.size, spacing: text_cfg.spacing, font: text_cfg.font })

	rectangle_raw! : Render.RectangleRaw => {}
	rectangle_raw! = |rect| Draw.rectangle_raw!({ x: rect.x, y: rect.y, width: rect.width, height: rect.height, color: { r: rect.color.r, g: rect.color.g, b: rect.color.b, a: rect.color.a } })

	rounded_rectangle_raw! : Render.RoundedRectangleRaw => {}
	rounded_rectangle_raw! = |rect| Draw.rounded_rectangle_raw!({ x: rect.x, y: rect.y, width: rect.width, height: rect.height, radius: rect.radius, segments: rect.segments, color: { r: rect.color.r, g: rect.color.g, b: rect.color.b, a: rect.color.a } })

	rounded_rectangle_lines_raw! : Render.RoundedRectangleLinesRaw => {}
	rounded_rectangle_lines_raw! = |rect| Draw.rounded_rectangle_lines_raw!({ x: rect.x, y: rect.y, width: rect.width, height: rect.height, radius: rect.radius, segments: rect.segments, color: { r: rect.color.r, g: rect.color.g, b: rect.color.b, a: rect.color.a }, thickness: rect.thickness })

	text_raw! : Render.TextRaw => {}
	text_raw! = |text_cfg| Draw.text_raw!({ pos: text_cfg.pos, text: text_cfg.text, size: text_cfg.size, spacing: text_cfg.spacing, color: { r: text_cfg.color.r, g: text_cfg.color.g, b: text_cfg.color.b, a: text_cfg.color.a }, font: text_cfg.font })

	draw_texture_raw! : Render.DrawTextureRaw => {}
	draw_texture_raw! = |texture| Draw.draw_texture_raw!({ texture: texture.texture, source: texture.source, dest: texture.dest, origin: texture.origin, rotation: texture.rotation, tint: { r: texture.tint.r, g: texture.tint.g, b: texture.tint.b, a: texture.tint.a } })

	end_frame! : {} => {}
	end_frame! = |_| Draw.end_frame!()
}

ray_draw : Render.Renderer
ray_draw = {
	begin_frame: RayDraw.begin_frame!,
	clear: RayDraw.clear!,
	measure_text_raw: RayDraw.measure_text_raw!,
	rectangle_raw: RayDraw.rectangle_raw!,
	rounded_rectangle_raw: RayDraw.rounded_rectangle_raw!,
	rounded_rectangle_lines_raw: RayDraw.rounded_rectangle_lines_raw!,
	text_raw: RayDraw.text_raw!,
	draw_texture_raw: RayDraw.draw_texture_raw!,
	end_frame: RayDraw.end_frame!,
}

theme = {
	page: Color.from_hex_rgb(0xf6f2e8),
	ink: Color.from_hex_rgb(0x172026),
	panel: Color.from_hex_rgb(0xffffff),
	panel_alt: Color.from_hex_rgb(0xe9f4f1),
	border: Color.from_hex_rgb(0xc9d2cc),
	accent: Color.from_hex_rgb(0x2b7a78),
}

font_path : Str
font_path = "examples/assets/Inter-Regular.ttf"

lorem : Str
lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Integer non sem vitae lacus gravida facilisis. Donec porttitor, justo sed luctus feugiat, nibh lorem malesuada enim, sed pulvinar erat lectus id massa."

newline_lorem : Str
newline_lorem = "Lorem ipsum dolor sit amet.\nInteger non sem vitae lacus.\nDonec porttitor justo sed luctus."

none_lorem : Str
none_lorem = "Short raw line."

Model : Program.State(RayDraw, AppModel, Msg)

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
			.width(Fit({ min: 0, max: 10000 }))
			.height(Fit({ min: 0, max: 10000 }))
			.child_align({ x: Start, y: Start })
			.font_size(18)
			.line_height(24)
			.font_color(theme.accent)
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
			.width(Fit({ min: 0, max: 10000 }))
			.height(Fit({ min: 0, max: 10000 }))
			.child_align({ x: Start, y: Start })
			.font_size(16)
			.line_height(22)
			.font_color(theme.ink)
			.text_wrap(wrap_mode),
		[],
		[text(content)],
	)
}

panel : Str, Element.TextWrap, Str, Color -> View(Msg)
panel = |title, wrap_mode, content, fill| {
	box(
		Auto,
		|_| style
			.width(Fixed(260))
			.height(Fit({ min: 0, max: 10000 }))
			.direction(Col)
			.child_align({ x: Start, y: Start })
			.gap(12)
			.pad((18, 18, 18, 18))
			.background(fill)
			.border({ color: theme.border, left: 1, right: 1, top: 1, bottom: 1 })
			.radius(8),
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
			.child_align({ x: Start, y: Start })
			.gap(22)
			.pad((28, 28, 28, 28))
			.background(theme.page)
			.font_family(model.font)
			.font_color(theme.ink),
		[],
		[
			box(
				Auto,
				|_| style
					.width(Fit({ min: 0, max: 10000 }))
					.height(Fit({ min: 0, max: 10000 }))
					.direction(Col)
					.child_align({ x: Start, y: Start })
					.gap(6)
					.text_wrap(None),
				[],
				[
					label("Text wrapping"),
					paragraph(None, "Same lorem ipsum copy rendered with Words, Newlines, and None wrap modes."),
				],
			),
			box(
				Auto,
				|_| style
					.width(Fit({ min: 0, max: 10000 }))
					.height(Fit({ min: 0, max: 10000 }))
					.direction(Row)
					.child_align({ x: Start, y: Start })
					.gap(18),
				[],
				[
					panel("Words", Words, lorem, theme.panel),
					panel("Newlines", Newlines, newline_lorem, theme.panel_alt),
					panel("None", None, none_lorem, theme.panel),
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
		config: { ..Program.default, title: "Text Wrap Example", width: 920, height: 560, resizable: Bool.True },
		renderer: ray_draw,
		init!,
		view,
		update,
	},
)
