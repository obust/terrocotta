## Minimal counter with increment and decrement buttons.
app [Model, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.7/8gdZaHEpySPZUzMBCT6RkEF9CBpcbi5F3E7QmNu4NTCU.tar.zst",
	tc: "../package/main.roc",
}

import rr.Host
import rr.App
import rr.Draw
import tc.Color
import tc.Element exposing [box, text, View, style, default_font]
import tc.Layout
import tc.Program
import tc.Render

RayDraw := [].{
	begin_frame! : {} => {}
	begin_frame! = |_| Draw.begin_frame!()

	clear! : Color => {}
	clear! = |color| Draw.clear!({ r: color.r, g: color.g, b: color.b, a: color.a })

	measure_text_raw! : Layout.MeasureTextFn
	measure_text_raw! = |text| Draw.measure_text_raw!({ text: text.text, size: text.size, spacing: text.spacing, font: text.font })

	rectangle_raw! : Render.RectangleRaw => {}
	rectangle_raw! = |rect| Draw.rectangle_raw!({ x: rect.x, y: rect.y, width: rect.width, height: rect.height, color: { r: rect.color.r, g: rect.color.g, b: rect.color.b, a: rect.color.a } })

	rounded_rectangle_raw! : Render.RoundedRectangleRaw => {}
	rounded_rectangle_raw! = |rect| Draw.rounded_rectangle_raw!({ x: rect.x, y: rect.y, width: rect.width, height: rect.height, radius: rect.radius, segments: rect.segments, color: { r: rect.color.r, g: rect.color.g, b: rect.color.b, a: rect.color.a } })

	rounded_rectangle_lines_raw! : Render.RoundedRectangleLinesRaw => {}
	rounded_rectangle_lines_raw! = |rect| Draw.rounded_rectangle_lines_raw!({ x: rect.x, y: rect.y, width: rect.width, height: rect.height, radius: rect.radius, segments: rect.segments, color: { r: rect.color.r, g: rect.color.g, b: rect.color.b, a: rect.color.a }, thickness: rect.thickness })

	text_raw! : Render.TextRaw => {}
	text_raw! = |text| Draw.text_raw!({ pos: text.pos, text: text.text, size: text.size, spacing: text.spacing, color: { r: text.color.r, g: text.color.g, b: text.color.b, a: text.color.a }, font: text.font })

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
	base: { fill: Color.from_hex_rgb(0xCCCCCC), content: Color.from_hex_rgb(0x1f2933) },
	primary: { fill: Color.from_hex_rgb(0x2563eb), content: Color.white },
	font_family: default_font,
	font_size: 18,
	gap: 14,
	radius: 8,
}

Model : Program.State(RayDraw, AppModel, Msg)

AppModel : {
	count : I32,
}

Msg : [
	Decrement,
	Increment,
]

init : () -> AppModel
init = || { count: 0 }

update : AppModel, Msg -> AppModel
update = |model, msg| match msg {
	Decrement => { ..model, count: model.count - 1 }
	Increment => { ..model, count: model.count + 1 }
}

button : Str, Msg -> View(Msg)
button = |label, click_msg| {
	box(
		Auto,
		|_| style
			.width(Fit({ min: theme.font_size, max: 10000 }))
			.pad((theme.gap, theme.gap, theme.gap, theme.gap))
			.background(theme.primary.fill)
			.radius(theme.radius)
			.font_size(theme.font_size)
			.font_color(theme.primary.content),
		[OnClick(click_msg)],
		[
			text(label),
		],
	)
}

view : AppModel -> View(Msg)
view = |model| {
	box(
		Auto,
		|_| style
			.direction(Col)
			.background(theme.base.fill)
			.font_family(theme.font_family)
			.font_size(theme.font_size)
			.font_color(theme.base.content),
		[],
		[
			box(
				Auto,
				|_| style
					.height(Fit({ min: 0, max: 10000 }))
					.gap(theme.gap)
					.direction(Row),
				[],
				[
					button("-", Decrement),
					text("Count: ${model.count.to_str()}"),
					button("+", Increment),
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
		config: { ..App.default, title: "Counter Example", width: 640, height: 420 },
		renderer: ray_draw,
		init,
		view,
		update,
	},
)
