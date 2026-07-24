## Example showcasing theme-aware widgets.
app [Model, program] {
    rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.8.0/HXKssyTXxLLu4TStDfgo9uvjnkT5mGJoRqKcvV2khjcw.tar.zst",
	tc: "../package/main.roc",
}

import rr.Host
import rr.Draw
import tc.Color
import tc.Element exposing [Font, View, box, style]
import tc.Layout
import tc.Program
import tc.Render
import tc.Theme
import tc.Widget

RayDraw := [].{
	begin_frame! : {} => {}
	begin_frame! = |_| Draw.begin_frame!()

	clear! : Color => {}
	clear! = |color| Draw.clear!({ r: color.r, g: color.g, b: color.b, a: color.a })

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

	draw_fps! : { pos: { x: F32, y: F32 }, size: F32, color: Color } => {}
	draw_fps! = |fps| Draw.fps!({ pos: fps.pos, size: fps.size, color: { r: fps.color.r, g: fps.color.g, b: fps.color.b, a: fps.color.a } })
}

Model : Program.State(Draw, AppModel, Msg)

AppModel : { theme: Theme, font: Font, volume : F32 }

Msg : [SetVolume(F32), SetTheme(Theme)]

theme_card : Theme, Str, AppModel -> View
theme_card = |theme, name, model| {
	Widget.panel(
		theme,
		[
		    Widget.label(theme, "Heading"),
			Widget.heading(theme, name),
			Widget.label(theme, "Badge"),
			Widget.row(
				theme,
				[
					Widget.badge(theme, Primary, "Primary"),
					Widget.badge(theme, Success, "Success"),
					Widget.badge(theme, Warning, "Warning"),
					Widget.badge(theme, Danger, "Danger"),
				],
			),
			Widget.label(theme, "Button"),
			Widget.row(
				theme,
				[
					Widget.button(theme, Primary, "OK"),
					Widget.button(theme, Secondary, "Cancel"),
				],
			),
			Widget.label(theme, "Checkbox"),
			Widget.row(
				theme,
				[
    				Widget.checkbox(
    					theme,
    					model.theme == Theme.light,
    					"Theme Light",
    					|checked| if checked SetTheme(Theme.light) else SetTheme(Theme.dark),
    				),
    				Widget.checkbox(
    					theme,
    					model.theme == Theme.dark,
    					"Theme Dark",
    					|checked| if checked SetTheme(Theme.dark) else SetTheme(Theme.light),
    				),
				],
			),
			Widget.label(theme, "Slider"),
			Widget.slider(
				theme,
				model.volume,
				0,
				100,
				1,
				|value| SetVolume(value),
			),
		],
	)
}

view : AppModel -> View
view = |model| {
	box(
		Auto,
		|_| style
			.background(Color.from_hex_rgb(0x242424))
			.pad((model.theme.gap, model.theme.gap, model.theme.gap, model.theme.gap))
			.gap(model.theme.gap)
			.direction(Col)
			.child_align({ x: Start, y: Start })
            .font_family(model.font)
            .font_size(model.theme.font_size),
		[],
		[
			theme_card(model.theme, "Light Theme", model),
			#theme_card(Theme.dark, "Dark Theme", model),
		],
	)
}

update : AppModel, Msg -> AppModel
update = |model, msg| {
	match msg {
		SetVolume(value) => { ..model, volume: value }
		SetTheme(theme) => { ..model, theme: theme }
	}
}

font_path : Str
font_path = "examples/assets/Inter-Regular.ttf"
init! : Program.Config => Try(AppModel, [Exit(I64)])
init! = |_config| Ok({
    theme: Theme.dark,
    font: Draw.load_font!({ path: font_path, size: 2 * 16 }).map_err(|_| Exit(1))?,
    volume: 45
})

program : {
	init! : { config : Program.Config, run! : Host => Try(Model, [Exit(I64)]) },
	render! : Model, Host => Try(Model, [Exit(I64), ..]),
}
program = Program.new!(
	{
		config: { ..Program.default, title: "Widget Theme Showcase", width: 900, height: 520 },
		init!,
		view,
		update,
	},
)
