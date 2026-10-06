## The leaf-element lesson for sizing an image.
import rr.Assets

import tc.Element exposing [ElementId.*, ImageSizing.*, box, image, style, text]
import tc.Program exposing [View]
import tc.Theme
import tc.Widget

import ../widgets/BoxId
import ../widgets/CodeBlock exposing [code_block, code_text]
import ../widgets/DemoFrame
import ../widgets/ExampleColors
import ../widgets/TutorialShell
import ../widgets/Typography

Image := [].{
	Model : {
		texture : Assets.Texture,
		width : AxisSizing,
		height : AxisSizing,
	}
	SizingMode : [PixelsMode, NaturalMode, FillMode]
	AxisSizing : { mode : SizingMode, select_open : Bool, pixels : F32 }
	Msg : [ToggleWidth(Bool), SetWidthMode(SizingMode), SetWidthPixels(F32), ToggleHeight(Bool), SetHeightMode(SizingMode), SetHeightPixels(F32)]

	init! = |assets| {
		texture = Assets.load_texture!(assets, "rocotta.png")?
		Ok({ texture, width: default_axis(200), height: default_axis(200) })
	}

	update : Model, Msg -> Model
	update = |model, message| match message {
		ToggleWidth(select_open) => { ..model, width: { ..model.width, select_open } }
		SetWidthMode(mode) => { ..model, width: { ..model.width, mode } }
		SetWidthPixels(pixels) => { ..model, width: { ..model.width, pixels } }
		ToggleHeight(select_open) => { ..model, height: { ..model.height, select_open } }
		SetHeightMode(mode) => { ..model, height: { ..model.height, mode } }
		SetHeightPixels(pixels) => { ..model, height: { ..model.height, pixels } }
	}

	guide : Theme, Model -> View(Msg)
	guide = |theme, model| {
		width = sizing(model.width)
		height = sizing(model.height)
		box(
			{ style: |_| style.width(Grow({})).direction(Col).gap(theme.gap).child_align({ x: Start, y: Start }) },
			[
				Typography.heading(theme, "Image"),
				Typography.p("The image leaf owns its natural dimensions. Choose a sizing policy for each axis to see how its containing box resolves the final image bounds."),
				DemoFrame.view(
					theme,
					[
						box(
							{ id: Id("container"), style: |_| style.width(Fixed(220)).height(Fixed(220)).background(ExampleColors.transparent_example_fill(0)).border({ color: ExampleColors.example_color(0), left: 1, right: 1, top: 1, bottom: 1 }).child_align({ x: Center, y: Center }).overflow(Hidden, Hidden) },
							[image(model.texture, { width, height }), BoxId.view(ExampleColors.example_color(0), "container")],
						),
					],
				),
				code_block(
					theme,
					CodeBlock.format(
						CodeBlock.box_node(
							"{ id: Id(\"container\"), style: |_| style... }",
							[CodeBlock.line("image(texture, { width: ..., height: ... })")],
						),
					),
				),
			],
		)
	}

	controls : Theme, Model -> View(Msg)
	controls = |theme, model| box(
		{ style: |_| style.width(Grow({})).height(Fit({})).direction(Col).gap(theme.gap).child_align({ x: Start, y: Start }) },
		[
			TutorialShell.controls_section(
				theme,
				LocalId("container"),
				[
					Typography.p("Container"),
					code_text(theme, ".width(Fixed(220))"),
					code_text(theme, ".height(Fixed(220))"),
				],
			),
			TutorialShell.controls_section(
				theme,
				LocalId("child-image"),
				[
					Typography.p("Child image"),
					axis_controls(theme, "width", model.width, |open| ToggleWidth(open), |mode| SetWidthMode(mode), |pixels| SetWidthPixels(pixels)),
					axis_controls(theme, "height", model.height, |open| ToggleHeight(open), |mode| SetHeightMode(mode), |pixels| SetHeightPixels(pixels)),
				],
			),
		],
	)
}

default_axis : F32 -> AxisSizing
default_axis = |pixels| { mode: PixelsMode, select_open: False, pixels }

sizing_mode_options : List(Str)
sizing_mode_options = ["Pixels", "Natural", "Fill"]

axis_controls : Theme, Str, AxisSizing, (Bool -> Msg), (SizingMode -> Msg), (F32 -> Msg) -> View(Msg)
axis_controls = |theme, axis, sizing_value, on_toggle, on_mode, on_pixels| box(
	{ style: |_| style.width(Grow({})).height(Fit({})).direction(Col).gap(theme.gap / 4).child_align({ x: Start, y: Start }) },
	[
		code_text(theme, "${axis}: ${sizing_name(sizing_value)}"),
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
