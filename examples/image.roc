## Renders an image centered in a box with interactive width and height controls.
app [Model, Msg, program] {
	rr: platform "../../roc-ray/platform/main.roc",
	tc: "../package/main.roc",
	roc: "nightly-2026-08-31-86e69b4",
}

import rr.App
import rr.Assets
import rr.Text

import tc.Element exposing [View, box, image, style]
import tc.Program
import tc.Theme
import tc.Widget

theme = Theme.dark

size_options : List(Str)
size_options = ["100px", "200px", "300px", "400px", "Fit (natural texture size, clipped)", "Grow (fill container)"]

index_to_sizing : U64 -> Element.Sizing
index_to_sizing = |index| match index {
	0 => Fixed(100)
	1 => Fixed(200)
	2 => Fixed(300)
	3 => Fixed(400)
	4 => Fit({})
	5 => Grow({})
	_ => Fixed(300)
}

Model : Program.State(AppModel, Msg)

AppModel : {
	texture : Assets.Texture,
	font : Text.Font,
	select_width : { open : Bool, selected : U64 },
	select_height : { open : Bool, selected : U64 },
}

Msg : [
	ToggleWidthSelect(Bool),
	SelectWidth(U64),
	ToggleHeightSelect(Bool),
	SelectHeight(U64),
]

configure : List(Str) -> App.Config
configure = |_args| App.default.with_title("Image Example").with_size({ width: 700, height: 500 })

init! : App.InitCallback(AppModel, _)
init! = |startup| {
	store = Assets.Store.open!(Assets.working_directory("examples/assets"))?
	texture = Assets.load_texture!(store, "rocotta.png")?
	font = startup.default_font!()?
	Ok({
		texture,
		font,
		select_width: { open: False, selected: 2 },
		select_height: { open: False, selected: 2 },
	})
}

update : AppModel, Msg -> AppModel
update = |model, msg| match msg {
	ToggleWidthSelect(open) => { ..model, select_width: { ..model.select_width, open } }
	SelectWidth(index) => { ..model, select_width: { open: False, selected: index } }
	ToggleHeightSelect(open) => { ..model, select_height: { ..model.select_height, open } }
	SelectHeight(index) => { ..model, select_height: { open: False, selected: index } }
}

view : AppModel -> View(Msg)
view = |model| {
	box(
		{
			style: |_| style
				.direction(Col)
				.gap(theme.gap * 2)
				.pad(theme.gap * 2, theme.gap * 2, theme.gap * 2, theme.gap * 2)
				.background(theme.palette.background.base.fill)
				.font_family(model.font)
				.font_size(theme.font_size)
				.child_align({ x: Center, y: Center }),
		},
		[
			Widget.label(theme, "Container box: 300px x 300px"),
			# Controls header
			box(
				{
					style: |_| style
						.height(Fit({}))
						.direction(Row)
						.gap(theme.gap)
						.child_align({ x: Start, y: Center }),
				},
				[
					Widget.label(theme, "Image box:"),
					Widget.select(
						theme,
						{
							open: model.select_width.open,
							selected: model.select_width.selected,
							options: size_options,
							on_toggle_open: |open| ToggleWidthSelect(open),
							on_select: |index| SelectWidth(index),
						},
					),
					Widget.select(
						theme,
						{
							open: model.select_height.open,
							selected: model.select_height.selected,
							options: size_options,
							on_toggle_open: |open| ToggleHeightSelect(open),
							on_select: |index| SelectHeight(index),
						},
					),
				],
			),
			# Container box holding centered image
			box(
				{
					style: |_| style
						.width(Fixed(300))
						.height(Fixed(300))
						.background(theme.palette.background.weak.fill)
						.radius(theme.radius)
						.child_align({ x: Center, y: Center })
						.overflow(Hidden, Hidden),
				},
				[
					# Inner box sizing the image
					box(
						{
							style: |_| style
								.width(index_to_sizing(model.select_width.selected))
								.height(index_to_sizing(model.select_height.selected))
								.border({ color: theme.palette.primary.base.fill, left: 2, right: 2, top: 2, bottom: 2 }),
						},
						[
							image(model.texture),
						],
					),
				],
			),
		],
	)
}

program = Program.new(App.effects(), configure, init!, update, view)
