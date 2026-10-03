## Example showcasing theme-aware widgets.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst",
	tc: "../package/main.roc",
}

import rr.App
import rr.Text
import tc.Color
import tc.Element exposing [box, style]
import tc.Program exposing [View]
import tc.Theme
import tc.Widget

Model : Program.State(AppModel, Msg)

AppModel : { theme : Theme, font : Text.Font, slider_value : F32, select_open : Bool, select_selected : U64, toggle_on : Bool, name : { value : Str, cursor : U64 }, color : Color }

Msg : [SetSliderValue(F32), SetTheme(Theme), ToggleSelect(Bool), SelectOption(U64), SetToggle(Bool), NameChanged(Widget.TextInputState), ColorChanged(Color)]

configure : List(Str) -> App.Config
configure = |_args| App.default
	.with_title("Widgets Example")
	.with_size({ width: 640, height: 500 })
	.with_resizable(True)
	.with_permission(Directory("examples/assets", ReadOnly))
	.with_default_font({ path: "examples/assets/Inter-Regular.ttf", size: 36 })

init! : App.InitCallback(AppModel, [])
init! = |io| {
	font = io.default_font!().map_err(|_| Exit(1))?
	model = {
		theme: Theme.dark,
		font,
		slider_value: 45,
		select_open: False,
		select_selected: 0,
		toggle_on: False,
		name: { value: "", cursor: 0 },
		color: 0xDE674B.Color,
	}
	Ok(model)
}

view : AppModel -> View(Msg)
view = |model| {
	theme = model.theme
	box(
		{
			style: |_| style
				.background(theme.palette.background.base.fill)
				.font_color(theme.palette.background.base.content)
				.direction(Row)
				.child_align({ x: Start, y: Start })
				.font_size(model.theme.font_size),
		},
		[
			box(
				{
					style: |_| style
						.width(Percent(0.5))
						.direction(Col)
						.gap(model.theme.gap)
						.pad(model.theme.gap, model.theme.gap, model.theme.gap, model.theme.gap)
						.child_align({ x: Start, y: Start }),
				},
				[
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
							Widget.button(theme, Primary, "OK", []),
							Widget.button(theme, Secondary, "Cancel", []),
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
					Widget.label(theme, "Toggle: ${if model.toggle_on "On" else "Off"}"),
					Widget.row(
						theme,
						[
							Widget.toggle(
								theme,
								model.toggle_on,
								|checked| SetToggle(checked),
							),
							Widget.label(theme, if model.theme == Theme.dark "Theme Dark enabled" else "Theme Dark disabled"),
						],
					),
					Widget.label(theme, "Slider: ${model.slider_value.to_str()}"),
					Widget.slider(
						theme,
						model.slider_value,
						0,
						100,
						1,
						|value| SetSliderValue(value),
					),
					Widget.label(theme, "Select"),
					Widget.select(
						theme,
						{
							open: model.select_open,
							selected: model.select_selected,
							options: ["Low", "Medium", "High"],
							on_toggle_open: |open| ToggleSelect(open),
							on_select: |index| SelectOption(index),
						},
					),
					Widget.label(theme, "Text input: ${model.name.value}"),
					Widget.input_text(
						theme,
						{
							id: Id("name"),
							font: model.font,
							state: model.name,
							placeholder: "Name",
							on_change: |state| NameChanged(state),
						},
					),
				],
			),
			box(
				{
					style: |_| style
						.width(Percent(0.5))
						.direction(Col)
						.pad(model.theme.gap, model.theme.gap, model.theme.gap, model.theme.gap)
						.gap(model.theme.gap)
						.child_align({ x: Start, y: Start }),
				},
				[
					box(
						{ style: |_| style.direction(Row).gap(model.theme.gap).height(Fit({})).child_align({ x: Start, y: Start }) },
						[
							Widget.label(model.theme, "Color: ${model.color.to_hex_str()}"),
							box({ style: |_| style.width(Fit({ min: 30 })) }, [Widget.color_preview(model.color)]),
						],
					),
					Widget.label(model.theme, "HSL"),
					Widget.color_slider(
						model.theme,
						{ color: model.color, channel: Hue, on_change: |next| ColorChanged(next) },
					),
					Widget.color_slider(
						model.theme,
						{ color: model.color, channel: Saturation, on_change: |next| ColorChanged(next) },
					),
					Widget.color_slider(
						model.theme,
						{ color: model.color, channel: Lightness, on_change: |next| ColorChanged(next) },
					),
					Widget.label(model.theme, "RGB"),
					Widget.color_slider(
						model.theme,
						{ color: model.color, channel: Red, on_change: |next| ColorChanged(next) },
					),
					Widget.color_slider(
						model.theme,
						{ color: model.color, channel: Green, on_change: |next| ColorChanged(next) },
					),
					Widget.color_slider(
						model.theme,
						{ color: model.color, channel: Blue, on_change: |next| ColorChanged(next) },
					),
					Widget.label(model.theme, "Alpha"),
					Widget.color_slider(
						model.theme,
						{ color: model.color, channel: Alpha, on_change: |next| ColorChanged(next) },
					),
				],
			),
		],
	)
}

update : AppModel, Msg -> AppModel
update = |model, msg| {
	match msg {
		SetSliderValue(value) => { ..model, slider_value: value }
		SetTheme(theme) => { ..model, theme: theme }
		ToggleSelect(open) => { ..model, select_open: open }
		SelectOption(index) => { ..model, select_open: False, select_selected: index }
		SetToggle(on) => { ..model, toggle_on: on }
		NameChanged(name) => { ..model, name }
		ColorChanged(color) => { ..model, color }
	}
}

program = Program.new(configure, init!, update, view)
