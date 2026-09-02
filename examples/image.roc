## Renders an image centered in a box with interactive width and height controls.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0-rc3/3vVeddfDE6rraq5j8v1cGHtFNaQhC6dij1zGRN63NGP1.tar.zst",
	tc: "../package/main.roc",
	roc: "nightly-2026-08-23-fb208ba",
}

import rr.App
import rr.Assets

import tc.Element exposing [View, box, image, style]
import tc.Program
import tc.Theme
import tc.Widget

theme = Theme.dark

size_options : List(Str)
size_options = ["100px", "200px", "300px", "400px", "Natural texture size (clipped)", "Fill container"]

ImageSizing : [Pixels(F32), Natural, Fill]

index_to_image_sizing : U64 -> ImageSizing
index_to_image_sizing = |index| match index {
	0 => Pixels(100)
	1 => Pixels(200)
	2 => Pixels(300)
	3 => Pixels(400)
	4 => Natural
	5 => Fill
	_ => Pixels(300)
}

resolve_image_sizing : ImageSizing, F32 -> Element.Sizing
resolve_image_sizing = |sizing, natural_size| match sizing {
	Pixels(value) => Fixed(value)
	Natural => Fixed(natural_size)
	Fill => Grow({})
}

Image(fields) : { width : F32, height : F32, ..fields }

## Application-owned image policy: the box participates in layout while the
## image leaf only paints into the box's resolved content bounds.
my_image : Image(fields), { width : ImageSizing, height : ImageSizing } -> View(msg, Image(fields))
my_image = |texture, config| {
	box(
		{
			style: |_| style
				.width(resolve_image_sizing(config.width, texture.width))
				.height(resolve_image_sizing(config.height, texture.height))
				.overflow(Hidden, Hidden)
				.border({ color: theme.palette.primary.base.fill, left: 2, right: 2, top: 2, bottom: 2 }),
		},
		[image(texture)],
	)
}

Model : Program.State(AppModel, Msg, Assets.Texture)

AppModel : {
	texture : Assets.Texture,
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
init! = |_startup| {
	store = Assets.Store.open!(Assets.working_directory("examples/assets"))?
	texture = Assets.load_texture!(store, "rocotta.png")?
	Ok({
		texture,
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

view : AppModel -> View(Msg, Assets.Texture)
view = |model| {
	box(
		{
			style: |_| style
				.direction(Col)
				.gap(theme.gap * 2)
				.pad(theme.gap * 2, theme.gap * 2, theme.gap * 2, theme.gap * 2)
				.background(theme.palette.background.base.fill)
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
					my_image(
						model.texture,
						{
							width: index_to_image_sizing(model.select_width.selected),
							height: index_to_image_sizing(model.select_height.selected),
						},
					),
				],
			),
		],
	)
}

program = Program.new(configure, init!, update, view)
