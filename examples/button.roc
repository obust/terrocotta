## Button example with status-dependent styling.
app [Model, program] {
	#rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.7/8gdZaHEpySPZUzMBCT6RkEF9CBpcbi5F3E7QmNu4NTCU.tar.zst",
	rr: platform "../../roc-ray/platform/main-default.roc",
	tc: "../package/main.roc",
}

import rr.Host
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
	rounded_rectangle_lines_raw: RayDraw.rounded_rectangle_lines_raw!,
	rounded_rectangle_raw: RayDraw.rounded_rectangle_raw!,
	text_raw: RayDraw.text_raw!,
	draw_texture_raw: RayDraw.draw_texture_raw!,
	end_frame: RayDraw.end_frame!,
}

theme = {
	base: { fill: Color.from_hex_rgb(0xf4f6f8), content: Color.from_hex_rgb(0x1f2933) },
	primary: {
		fill: Color.from_hex_rgb(0x2563eb),
		hover: Color.from_hex_rgb(0x1d4ed8),
		pressed: Color.from_hex_rgb(0x1e40af),
		focused: Color.from_hex_rgb(0xF54927),
		content: Color.white,
	},
	font_family: default_font,
	font_size: 24,
	gap: 18,
	radius: 12,
}

Model : Program.State(RayDraw, AppModel, Msg)

AppModel : {}

Msg : [Increment]

init! : Program.Config => Try(AppModel, [Exit(I64)])
init! = |_config| Ok({})

update : AppModel, Msg -> AppModel
update = |model, _msg| model

button : Str -> View(Msg)
button = |label| {
	box(
		Auto,
		|status| {
			var $box_style = style
				.width(Fit({ min: 0, max: 10000 }))
				.height(Fit({ min: 0, max: 10000 }))
				.pad((theme.gap, theme.gap, theme.gap, theme.gap))
				.child_align({ x: Center, y: Center })
				.direction(Row)
				.background(theme.primary.fill)
				.radius(theme.radius)
				.font_family(theme.font_family)
				.font_size(theme.font_size)
				.font_color(theme.primary.content)

			$box_style = if status.focused {
				$box_style.border({ color: theme.primary.focused, left: 1, right: 1, top: 1, bottom: 1 })
			} else {
				$box_style
			}

			if status.pressed {
				$box_style.background(theme.primary.pressed)
			} else if status.hovered {
				$box_style.background(theme.primary.hover)
			} else {
				$box_style
			}
		},
		[],
		[
			text(label),
		],
	)
}

view : AppModel -> View(Msg)
view = |_model| {
	box(
		Auto,
		|_| style.background(theme.base.fill),
		[],
		[
			button("hover and click me"),
		],
	)
}

program : {
	init! : { config : Program.Config, run! : Host => Try(Model, [Exit(I64)]) },
	render! : Model, Host => Try(Model, [Exit(I64), ..]),
}
program = Program.new!(
	{
		config: { ..Program.default, title: "Button Status Example", width: 640, height: 420 },
		renderer: ray_draw,
		init!,
		view,
		update,
	},
)
