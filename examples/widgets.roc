## Example showcasing theme-aware widgets.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0-rc3/3vVeddfDE6rraq5j8v1cGHtFNaQhC6dij1zGRN63NGP1.tar.zst",
	tc: "../package/main.roc",
	roc: "nightly-2026-08-23-fb208ba",
}

import rr.App
import rr.Text
import tc.Color
import tc.Element exposing [View, box, style]
import tc.Program
import tc.Theme
import tc.Widget

Model : Program.State(AppModel, Msg)

AppModel : { theme : Theme, font : Text.Font, slider_value : F32, select_open : Bool, select_selected : U64, toggle_on : Bool, name : { value : Str, cursor : U64 } }

Msg : [SetSliderValue(F32), SetTheme(Theme), ToggleSelect(Bool), SelectOption(U64), SetToggle(Bool), NameChanged(Widget.TextInputState)]

configure : List(Str) -> App.Config
configure = |_args| App.default
    .with_title("Widgets Example")
    .with_size({ width: 640, height: 500 })
    .with_resizable(True)
    .with_default_font({ path: "examples/assets/Inter-Regular.ttf", size: 36 })


init! : App.InitCallback(AppModel, [])
init! = |startup| {
	font = startup.default_font!().map_err(|_| Exit(1))?
	model = {
		theme: Theme.dark,
		font,
		slider_value: 45,
		select_open: False,
		select_selected: 0,
		toggle_on: False,
		name: { value: "", cursor: 0 },
	}
	Ok(model)
}

theme_card : Theme, Str, AppModel -> View(Msg, Program.Payload)
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
	)
}

view : AppModel -> View(Msg, Program.Payload)
view = |model| {
	box(
		{
			style: |_| style
				.background(0x242424.Color)
				.pad(model.theme.gap, model.theme.gap, model.theme.gap, model.theme.gap)
				.gap(model.theme.gap)
				.direction(Col)
				.child_align({ x: Start, y: Start })
				.font_size(model.theme.font_size),
		},
		[
			theme_card(model.theme, "Widget Demo", model),
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
	}
}

program = Program.new(configure, init!, update, view)
