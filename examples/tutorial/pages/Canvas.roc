## The lesson for drawing in a canvas relative to its container.
import tc.Color
import rr.Assets
import rr.Draw

import tc.Element exposing [ElementId.*, box, canvas, style]
import tc.Program exposing [View]
import tc.Theme
import tc.Widget exposing [slider]

import ../UI

Canvas := [].{
	Model : { width : F32, height : F32 }
	Msg : [SetWidth(F32), SetHeight(F32)]

	init : Assets.Store -> Model
	init = |_store| { width: 320, height: 180 }

	update : Model, Msg -> Model
	update = |model, message| match message {
		SetWidth(width) => { ..model, width }
		SetHeight(height) => { ..model, height }
	}

	view : Theme, Model -> View(Msg)
	view = |theme, model| UI.page_layout(
		theme,
		guide(theme, model),
		controls(theme, model),
	)
}

guide : Theme, Canvas.Model -> List(View(Canvas.Msg))
guide = |theme, model| {
	[
		UI.heading(theme, "Canvas"),
		UI.p("A canvas fills its container and gives the drawing callback its resolved bounds. Use the frame to draw shapes and other primitives in that coordinate space."),
		UI.code_preview(
			theme,
			[
				box(
					{ id: Id("container"), style: |_| style.width(Fixed(model.width)).height(Fixed(model.height)).background(Color.with_alpha(UI.palette_color(0), 0)).border({ color: UI.palette_color(0), left: 1, right: 1, top: 1, bottom: 1 }) },
					[
						canvas(
							|frame, bounds| {
								{ x, y } = bounds.center()
								frame.circle!({ center: { x, y }, radius: 40, style: Draw.filled(UI.palette_color(1).to_rrt()) })
								Ok({})
							},
						),
						UI.box_id("container", UI.palette_color(0)),
					],
				),
			],
		),
		UI.code_block(
			theme,
			UI.format("box({ id: Id(\"container\"), style: |_| style... }, [canvas(|frame, bounds| { frame.circle!({ center: bounds.center(), radius: 40, style: Draw.filled(color) }) })])"),
		),
	]
}

controls : Theme, Canvas.Model -> List(View(Canvas.Msg))
controls = |theme, model| [
	UI.control_group(
		theme,
		UI.palette_color(0),
		[
			UI.box_id("container", UI.palette_color(0)),
			UI.code_text(theme, ".width(Fixed(${model.width.to_str()}))"),
			slider(theme, model.width, 180, 560, 20, |width| SetWidth(width)),
			UI.code_text(theme, ".height(Fixed(${model.height.to_str()}))"),
			slider(theme, model.height, 120, 320, 20, |height| SetHeight(height)),
		],
	),
]
