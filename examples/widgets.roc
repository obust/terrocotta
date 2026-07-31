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
