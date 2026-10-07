## The leaf-element lesson for sizing an image.
import tc.Color
import rr.Assets
import rr.App as RayApp
import rr.Task

import tc.Element exposing [ChildAlign.*, ElementId.*, ImageSizing.*, box, image, style, text]
import tc.Program exposing [View]
import tc.Theme
import tc.Widget

import ../UI

Image := [].{
	Model : {
		texture : Assets.Texture,
		width : AxisSizing,
		height : AxisSizing,
		child_align : { x : ChildAlign, y : ChildAlign },
		child_align_x_open : Bool,
		child_align_y_open : Bool,
	}
	SizingMode : [PixelsMode, NaturalMode, FillMode]
	AxisSizing : { mode : SizingMode, select_open : Bool, pixels : F32 }
	Msg : [ToggleWidth(Bool), SetWidthMode(SizingMode), SetWidthPixels(F32), ToggleHeight(Bool), SetHeightMode(SizingMode), SetHeightPixels(F32), SetChildAlignX(ChildAlign), ToggleChildAlignX(Bool), SetChildAlignY(ChildAlign), ToggleChildAlignY(Bool), ImageLoaded(Assets.Texture), ImageLoadFailed]

	init! : Assets.Store, RayApp.Input(msg), (Msg -> msg) => Model
	init! = |store, input, map_msg| {
		Task.spawn_with!(
			input,
			|| match Assets.load_texture!(store, "bricks.png") {
				Ok(texture) => ImageLoaded(texture)
				Err(_) => ImageLoadFailed
			},
			map_msg,
		)
		{ texture: Assets.Texture.stub, width: default_axis(320), height: default_axis(213), child_align: { x: Center, y: Center }, child_align_x_open: False, child_align_y_open: False }
	}

	update : Model, Msg -> Model
	update = |model, message| match message {
		ToggleWidth(select_open) => { ..model, width: { ..model.width, select_open } }
		SetWidthMode(mode) => { ..model, width: { ..model.width, mode } }
		SetWidthPixels(pixels) => { ..model, width: { ..model.width, pixels } }
		ToggleHeight(select_open) => { ..model, height: { ..model.height, select_open } }
		SetHeightMode(mode) => { ..model, height: { ..model.height, mode } }
		SetHeightPixels(pixels) => { ..model, height: { ..model.height, pixels } }
		SetChildAlignX(x) => { ..model, child_align: { ..model.child_align, x } }
		ToggleChildAlignX(open) => { ..model, child_align_x_open: open }
		SetChildAlignY(y) => { ..model, child_align: { ..model.child_align, y } }
		ToggleChildAlignY(open) => { ..model, child_align_y_open: open }
		ImageLoaded(texture) => { ..model, texture }
		ImageLoadFailed => model
	}

	view : Theme, Model -> View(Msg)
	view = |theme, model| UI.page_layout(theme, guide(theme, model), controls(theme, model))
}

guide : Theme, Model -> List(View(Msg))
guide = |theme, model| {
	width = sizing(model.width)
	height = sizing(model.height)
	[
		UI.heading(theme, "Image"),
		UI.p("An image element an intrinsic size. Choose Pixels, Natural, or Fill independently for each axis to control how it resolves its size inside the container."),
		UI.code_preview(
			theme,
			[
				box(
					{
						id: Id("container"),
						style: |_| style
							.width(Fixed(200))
							.height(Fixed(200))
							.background(Color.with_alpha(UI.palette_color(0), 0))
							.border({ color: UI.palette_color(0), left: 1, right: 1, top: 1, bottom: 1 })
							.child_align(model.child_align)
							.overflow(Visible, Visible),
					},
					[
						UI.box_id("container", UI.palette_color(0)),
						image(model.texture, { width, height }),
					],
				),
			],
		),
		UI.code_block(
			theme,
			UI.format("box({ id: Id(\"container\"), style: |_| style... }, [image(texture, { width: ..., height: ... })])"),
		),
	]
}

controls : Theme, Model -> List(View(Msg))
controls = |theme, model| [
	UI.control_group(
		theme,
		UI.palette_color(0),
		[
			UI.box_id("container", UI.palette_color(0)),
			UI.code_text(theme, ".width(Fixed(200))"),
			UI.code_text(theme, ".height(Fixed(200))"),
			UI.code_text(theme, ".overflow(Visible, Visible)"),
			UI.code_text(theme, ".child_align({ x: ${child_align_name(model.child_align.x)}, y: ${child_align_name(model.child_align.y)} })"),
			box(
				{ style: |_| style.width(Grow({})).height(Fit({})).direction(Row).gap(theme.gap / 2).child_align({ x: Start, y: Start }) },
				[
					Widget.select(theme, { open: model.child_align_x_open, selected: child_align_selected(model.child_align.x), options: child_align_options, on_toggle_open: |open| ToggleChildAlignX(open), on_select: |index| SetChildAlignX(child_align_from(index)) }),
					Widget.select(theme, { open: model.child_align_y_open, selected: child_align_selected(model.child_align.y), options: child_align_options, on_toggle_open: |open| ToggleChildAlignY(open), on_select: |index| SetChildAlignY(child_align_from(index)) }),
				],
			),
		],
	),
	UI.control_group(
		theme,
		UI.palette_color(1),
		[
			UI.box_id("image", UI.palette_color(1)),
			axis_controls(theme, "width", model.width, |open| ToggleWidth(open), |mode| SetWidthMode(mode), |pixels| SetWidthPixels(pixels)),
			axis_controls(theme, "height", model.height, |open| ToggleHeight(open), |mode| SetHeightMode(mode), |pixels| SetHeightPixels(pixels)),
		],
	),
]

child_align_options : List(Str)
child_align_options = ["Start", "Center", "End"]

child_align_selected : ChildAlign -> U64
child_align_selected = |align| match align {
	Start => 0
	Center => 1
	End => 2
}

child_align_from : U64 -> ChildAlign
child_align_from = |index| match index {
	0 => Start
	1 => Center
	_ => End
}

child_align_name : ChildAlign -> Str
child_align_name = |align| match align {
	Start => "Start"
	Center => "Center"
	End => "End"
}

default_axis : F32 -> AxisSizing
default_axis = |pixels| { mode: PixelsMode, select_open: False, pixels }

sizing_mode_options : List(Str)
sizing_mode_options = ["Pixels", "Natural", "Fill"]

axis_controls : Theme, Str, AxisSizing, (Bool -> Msg), (SizingMode -> Msg), (F32 -> Msg) -> View(Msg)
axis_controls = |theme, axis, sizing_value, on_toggle, on_mode, on_pixels| box(
	{ style: |_| style.width(Grow({})).height(Fit({})).direction(Col).gap(theme.gap / 4).child_align({ x: Start, y: Start }) },
	[
		UI.code_text(theme, "${axis}: ${sizing_name(sizing_value)}"),
		Widget.select(theme, { open: sizing_value.select_open, selected: sizing_mode_selected(sizing_value.mode), options: sizing_mode_options, on_toggle_open: on_toggle, on_select: |selected| on_mode(sizing_mode_from(selected)) }),
		pixels_control(theme, sizing_value, on_pixels),
	],
)

pixels_control : Theme, AxisSizing, (F32 -> Msg) -> View(Msg)
pixels_control = |theme, sizing_value, on_pixels| match sizing_value.mode {
	PixelsMode => Widget.slider(theme, sizing_value.pixels, 20, 400, 10, on_pixels)
	NaturalMode | FillMode => box({ style: |_| style.width(Fit({})).height(Fit({})) }, [])
}

sizing_mode_selected : SizingMode -> U64
sizing_mode_selected = |mode| match mode {
	PixelsMode => 0
	NaturalMode => 1
	FillMode => 2
}

sizing_mode_from : U64 -> SizingMode
sizing_mode_from = |selected| match selected {
	0 => PixelsMode
	1 => NaturalMode
	_ => FillMode
}

sizing : AxisSizing -> ImageSizing
sizing = |sizing_value| match sizing_value.mode {
	PixelsMode => Pixels(sizing_value.pixels)
	NaturalMode => Natural
	FillMode => Fill
}

sizing_name : AxisSizing -> Str
sizing_name = |sizing_value| match sizing_value.mode {
	PixelsMode => "Pixels(${sizing_value.pixels.to_str()})"
	NaturalMode => "Natural"
	FillMode => "Fill"
}
