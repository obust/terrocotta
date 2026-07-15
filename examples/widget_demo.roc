## Example showcasing theme-aware widgets.
app [Model, program] {
	# rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.7/8gdZaHEpySPZUzMBCT6RkEF9CBpcbi5F3E7QmNu4NTCU.tar.zst",
	rr: platform "../../roc-ray/platform/main-default.roc",
	tc: "../package/main.roc",
}

import rr.Host
import rr.Draw
import tc.Color
import tc.Element exposing [View, box, style]
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

Model : Program.State(RayDraw, AppModel, Msg)

AppModel : { volume : F32, enabled : Bool }

Msg : [SetVolume(F32), SetEnabled(Bool)]

theme_card : Theme, Str, AppModel -> View
theme_card = |theme, name, model| {
	Widget.panel(
		theme,
		[
			Widget.heading(theme, name),
			Widget.label(theme, "Widgets inherit font, spacing, radius, and semantic colors from Theme."),
			Widget.row(
				theme,
				[
					Widget.badge(theme, Primary, "Primary"),
					Widget.badge(theme, Success, "Success"),
					Widget.badge(theme, Warning, "Warning"),
					Widget.badge(theme, Danger, "Danger"),
				],
			),
			Widget.row(
				theme,
				[
					Widget.button(theme, Primary, "OK"),
					Widget.button(theme, Secondary, "Cancel"),
				],
			),
			Widget.label(theme, "Checkbox"),
			Widget.checkbox(
				theme,
				model.enabled,
				if model.enabled "Enabled" else "Disabled",
				|checked| SetEnabled(checked),
			),
			Widget.alert(theme, Warning, "This warning alert uses the theme warning role."),
			Widget.label(theme, "Progress"),
			Widget.progress_bar(theme, Primary, 0.7),
			Widget.progress_bar(theme, Success, 0.45),
			Widget.progress_bar(theme, Warning, 0.85),
			Widget.progress_bar(theme, Danger, 1.25),
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
			.pad((32, 32, 32, 32))
			.gap(24)
			.direction(Col)
			.child_align({ x: Start, y: Start }),
		[],
		[
			theme_card(Theme.light, "Light Theme", model),
			theme_card(Theme.dark, "Dark Theme", model),
		],
	)
}

update : AppModel, Msg -> AppModel
update = |model, msg| {
	match msg {
		SetVolume(value) => { ..model, volume: value }
		SetEnabled(checked) => { ..model, enabled: checked }
	}
}

init! : Program.Config => Try(AppModel, [Exit(I64)])
init! = |_config| Ok({ volume: 45, enabled: Bool.True })

program : {
	init! : { config : Program.Config, run! : Host => Try(Model, [Exit(I64)]) },
	render! : Model, Host => Try(Model, [Exit(I64), ..]),
}
program = Program.new!(
	{
		config: { ..Program.default, title: "Widget Theme Showcase", width: 900, height: 520 },
		renderer: ray_draw,
		init!,
		view,
		update,
	},
)
