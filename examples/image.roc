## Renders the bricks texture centered in a box with interactive width and height controls.
## The container Box uses aspect_ratio = natural w/h of bricks.jpg so proportions are preserved.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0-rc3/3vVeddfDE6rraq5j8v1cGHtFNaQhC6dij1zGRN63NGP1.tar.zst",
	tc: "../package/main.roc",
	roc: "nightly-2026-08-23-fb208ba",
}

import rr.App
import rr.Assets

import tc.Element exposing [box, image, style]
import tc.Program exposing [View]
import tc.Theme
import tc.Widget

theme = Theme.dark

size_options : List(Str)
size_options = ["100px", "200px", "300px", "400px", "Natural texture size (clipped)", "Fill container"]

index_to_image_sizing : U64 -> Element.ImageSizing
index_to_image_sizing = |index| match index {
	0 => Pixels(100)
	1 => Pixels(200)
	2 => Pixels(300)
	3 => Pixels(400)
	4 => Natural
	5 => Fill
	_ => Pixels(300)
}

Model : Program.State(AppModel, Msg)

AppModel : {
	texture : Assets.Texture,
	select_width : { open : Bool, selected : U64 },
	select_height : { open : Bool, selected : U64 },
	aspect_enabled : Bool,
}

Msg : [
	ToggleWidthSelect(Bool),
	SelectWidth(U64),
	ToggleHeightSelect(Bool),
	SelectHeight(U64),
	ToggleAspect(Bool),
]

configure : List(Str) -> App.Config
configure = |_args| App.default.with_title("Image + Aspect Ratio Example").with_size({ width: 700, height: 560 })

init! : App.InitCallback(AppModel, _)
init! = |_startup| {
	store = Assets.Store.open!(Assets.working_directory("examples/assets"))?
	texture = Assets.load_texture!(store, "bricks.jpg")?
	Ok({
		texture,
		select_width: { open: False, selected: 2 },
		select_height: { open: False, selected: 2 },
		aspect_enabled: True,
	})
}

update : AppModel, Msg -> AppModel
update = |model, msg| match msg {
	ToggleWidthSelect(open) => { ..model, select_width: { ..model.select_width, open } }
	SelectWidth(index) => { ..model, select_width: { open: False, selected: index } }
	ToggleHeightSelect(open) => { ..model, select_height: { ..model.select_height, open } }
	SelectHeight(index) => { ..model, select_height: { open: False, selected: index } }
	ToggleAspect(enabled) => { ..model, aspect_enabled: enabled }
}

to_sizing : Element.ImageSizing, F32 -> Element.Sizing
to_sizing = |sizing, natural| match sizing {
	Pixels(v) => Fixed(v)
	Natural => Fixed(natural)
	Fill => Grow({})
}

view : AppModel -> View(Msg)
view = |model| {
	# Original image aspect ratio — w / h from the loaded bricks.jpg texture.
	# Toggle off => None (stretch), on => Ratio(w/h) preserves proportions.
	# When preserving, height is derived from width via aspect (h = w / r),
	# so the height select is ignored and the container keeps proportions.
	w = model.texture.width.to_f32()
	h = model.texture.height.to_f32()
	aspect = if model.aspect_enabled {
		if h == 0 {
			None
		} else {
			Ratio(w / h)
		}
	} else {
		None
	}
	outer_width = to_sizing(index_to_image_sizing(model.select_width.selected), w)
	outer_height = if model.aspect_enabled {
		Grow({})
	} else {
		to_sizing(index_to_image_sizing(model.select_height.selected), h)
	}

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
			Widget.label(theme, "Container box: 300px x 300px  •  bricks.jpg with aspect_ratio on container Box"),
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
					Widget.checkbox(theme, model.aspect_enabled, "Preserve aspect (natural)", |checked| ToggleAspect(checked)),
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
					# Aspect-ratio container Box — the image Custom leaf takes whatever this Box assigns.
					# This mirrors Clay: .aspectRatio on the Box, not on the Custom(Image) leaf.
					# When aspect is set, one axis is derived: h = w / r  or  w = h * r.
					box(
						{
							style: |_| style
								.width(outer_width)
								.height(outer_height)
								.aspect_ratio(aspect)
								.overflow(Hidden, Hidden),
						},
						[
							image(
								model.texture,
								{ width: Fill, height: Fill },
							),
						],
					),
				],
			),
			Widget.label(
				theme,
				if model.aspect_enabled {
					"Aspect ON: natural w/h — h = w / r, w = h * r — try 300px + Fill"
				} else {
					"Aspect OFF: image stretches to fill box — toggle to preserve proportions"
				},
			),
		],
	)
}

program = Program.new(configure, init!, update, view)
