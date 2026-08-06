## Renders an image centered in a box with interactive width and height controls.
app [Model, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.8.3/E6ZmC6ZncTVFG875Xsf6jP2GuZCtLnncQ1YwVwKtT2J4.tar.zst",
	tc: "../package/main.roc",
}

import rr.Host
import rr.Draw exposing [load_font!]
import rr.Assets as RRAssets
import tc.Element exposing [Font, View, box, image, style]
import tc.Program
import tc.Theme
import tc.Widget
import tc.Assets exposing [Texture]

theme = Theme.dark

image_path : Str
image_path = "examples/assets/rocotta.png"

font_path : Str
font_path = "examples/assets/Inter-Regular.ttf"

size_options : List(Str)
size_options = ["100px", "200px", "300px", "400px", "Fit (natural texture size, clipped)", "Grow (fill container)"]

index_to_sizing : U64 -> Element.Sizing
index_to_sizing = |index| match index {
	0 => Fixed(100)
	1 => Fixed(200)
	2 => Fixed(300)
	3 => Fixed(400)
	4 => Fit({ min: 0, max: 10000 })
	5 => Grow({ min: 0, max: 10000 })
	_ => Fixed(300)
}

Model : Program.State(Draw, AppModel, Msg)

AppModel : {
	font : Font,
	texture : Texture,
	select_width : { open : Bool, selected : U64 },
	select_height : { open : Bool, selected : U64 },
}

Msg : [
	ToggleWidthSelect(Bool),
	SelectWidth(U64),
	ToggleHeightSelect(Bool),
	SelectHeight(U64),
]

init! : Program.Config => Try(AppModel, [Exit(I64)])
init! = |_config| {
	Ok({
		font: load_font!({ path: font_path, size: 2 * 16 }).map_err(|_| Exit(1))?,
		texture: RRAssets.load_texture!(image_path).map_err(|_| Exit(1))?,
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
		Auto,
		|_| style
			.direction(Col)
			.gap(theme.gap * 2)
			.pad((theme.gap * 2, theme.gap * 2, theme.gap * 2, theme.gap * 2))
			.background(theme.palette.background.base.fill)
			.font_family(model.font)
			.font_size(theme.font_size)
			.child_align({ x: Center, y: Center }),
		[],
		[
			Widget.label(theme, "Container box: 300px x 300px"),
			# Controls header
			box(
				Auto,
				|_| style
					.height(Fit({ min: 0, max: 10000 }))
					.direction(Row)
					.gap(theme.gap)
					.child_align({ x: Start, y: Center }),
				[],
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
				Auto,
				|_| style
					.width(Fixed(300))
					.height(Fixed(300))
					.background(theme.palette.background.weak.fill)
					.radius(theme.radius)
					.child_align({ x: Center, y: Center })
					.overflow(Hidden, Hidden),
				[],
				[
					# Inner box sizing the image
					box(
						Auto,
						|_| style
							.width(index_to_sizing(model.select_width.selected))
							.height(index_to_sizing(model.select_height.selected))
							.border({ color: theme.palette.primary.base.fill, left: 2, right: 2, top: 2, bottom: 2 }),
						[],
						[
							image(model.texture),
						],
					),
				],
			),
		],
	)
}

program : {
	init! : { config : Program.Config, run! : Host => Try(Model, [Exit(I64)]) },
	render! : Model, Host => Try(Model, [Exit(I64), ..]),
}
program = Program.new!({
	config: { ..Program.default, title: "Image Example", width: 700, height: 500 },
	init!,
	view,
	update,
})
