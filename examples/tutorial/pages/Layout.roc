## The lesson for interactive container and child sizing.
import tc.Element exposing [ChildAlign.*, Direction.*, ElementId.*, Sizing.*, box, style, text]
import tc.Program exposing [View]
import tc.Theme
import tc.Widget exposing [range_slider, select, slider]

import ../ui/Parts
import ../widgets/BoxId
import ../widgets/CodeBlock
import ../widgets/DemoFrame

Layout := [].{
	Bounds : { min : F32, max : F32 }
	SizingMode : [GrowMode, FitMode, FixedMode, PercentMode]
	AxisSizing : { mode : SizingMode, select_open : Bool, fit : Bounds, fixed : F32, percent : F32 }
	Child : { width : AxisSizing, height : AxisSizing }
	Children : { zero : Child, one : Child, two : Child }
	ChildIndex : [Child0, Child1, Child2]
	Model : { direction : Direction, direction_open : Bool, gap : F32, pad : F32, child_align : { x : ChildAlign, y : ChildAlign }, child_align_x_open : Bool, child_align_y_open : Bool, children : Children }
	Msg : [SetDirection(Direction), ToggleDirection(Bool), SetGap(F32), SetPad(F32), SetChildAlignX(ChildAlign), ToggleChildAlignX(Bool), SetChildAlignY(ChildAlign), ToggleChildAlignY(Bool), SetChildWidthMode(ChildIndex, SizingMode), ToggleChildWidthMode(ChildIndex, Bool), SetChildWidthFit(ChildIndex, Bounds), SetChildWidthFixed(ChildIndex, F32), SetChildWidthPercent(ChildIndex, F32), SetChildHeightMode(ChildIndex, SizingMode), ToggleChildHeightMode(ChildIndex, Bool), SetChildHeightFit(ChildIndex, Bounds), SetChildHeightFixed(ChildIndex, F32), SetChildHeightPercent(ChildIndex, F32)]

	initial : Model
	initial = {
		direction: Row,
		direction_open: False,
		gap: 12,
		pad: 16,
		child_align: { x: Center, y: Center },
		child_align_x_open: False,
		child_align_y_open: False,
		children: {
			zero: { width: default_axis(FitMode, { min: 48, max: 80 }, 64, 0.25), height: default_axis(FitMode, { min: 32, max: 60 }, 44, 0.25) },
			one: { width: default_axis(FixedMode, { min: 56, max: 96 }, 76, 0.3), height: default_axis(FixedMode, { min: 40, max: 72 }, 56, 0.3) },
			two: { width: default_axis(PercentMode, { min: 44, max: 88 }, 68, 0.25), height: default_axis(PercentMode, { min: 36, max: 64 }, 48, 0.25) },
		},
	}

	update : Model, Msg -> Model
	update = |model, message| match message {
		SetDirection(direction) => { ..model, direction }
		ToggleDirection(open) => { ..model, direction_open: open }
		SetGap(gap) => { ..model, gap: F32.max(0, F32.min(48, gap)) }
		SetPad(pad) => { ..model, pad: F32.max(0, F32.min(48, pad)) }
		SetChildAlignX(x) => { ..model, child_align: { ..model.child_align, x } }
		ToggleChildAlignX(open) => { ..model, child_align_x_open: open }
		SetChildAlignY(y) => { ..model, child_align: { ..model.child_align, y } }
		ToggleChildAlignY(open) => { ..model, child_align_y_open: open }
		SetChildWidthMode(index, mode) => { ..model, children: update_child(model.children, index, |child| { ..child, width: { ..child.width, mode } }) }
		ToggleChildWidthMode(index, select_open) => { ..model, children: update_child(model.children, index, |child| { ..child, width: { ..child.width, select_open } }) }
		SetChildWidthFit(index, fit) => { ..model, children: update_child(model.children, index, |child| { ..child, width: { ..child.width, fit } }) }
		SetChildWidthFixed(index, fixed) => { ..model, children: update_child(model.children, index, |child| { ..child, width: { ..child.width, fixed } }) }
		SetChildWidthPercent(index, percent) => { ..model, children: update_child(model.children, index, |child| { ..child, width: { ..child.width, percent } }) }
		SetChildHeightMode(index, mode) => { ..model, children: update_child(model.children, index, |child| { ..child, height: { ..child.height, mode } }) }
		ToggleChildHeightMode(index, select_open) => { ..model, children: update_child(model.children, index, |child| { ..child, height: { ..child.height, select_open } }) }
		SetChildHeightFit(index, fit) => { ..model, children: update_child(model.children, index, |child| { ..child, height: { ..child.height, fit } }) }
		SetChildHeightFixed(index, fixed) => { ..model, children: update_child(model.children, index, |child| { ..child, height: { ..child.height, fixed } }) }
		SetChildHeightPercent(index, percent) => { ..model, children: update_child(model.children, index, |child| { ..child, height: { ..child.height, percent } }) }
	}

	guide : Theme, Model -> View(Msg)
	guide = |theme, model| {
		direction_name = if model.direction == Row {
			"Row"
		} else {
			"Col"
		}
		box(
			{ style: |_| style.width(Grow({})).direction(Col).gap(theme.gap).child_align({ x: Start, y: Start }) },
			[
				Parts.heading(theme, "Layout"),
				Parts.copy("Change the container's direction, gap, padding, and child alignment. Each numbered child has its own fixed width and height."),
				DemoFrame.view(
					theme,
					[
						box(
							{
								id: Id("container"),
								style: |_| style
									.width(Fixed(360))
									.height(Fixed(180))
									.direction(model.direction)
									.gap(model.gap)
									.pad(model.pad, model.pad, model.pad, model.pad)
									.child_align(model.child_align)
									.background(Parts.transparent_example_fill(0))
									.border({ color: Parts.example_color(0), left: 1, right: 1, top: 1, bottom: 1 })
									.radius(theme.radius),
							},
							[
								chip(theme, "0", model.children.zero, 1),
								chip(theme, "1", model.children.one, 2),
								chip(theme, "2", model.children.two, 3),
								BoxId.view(Parts.example_color(0), "container"),
							],
						),
					],
				),
				CodeBlock.view(theme, "style\n    .direction(${direction_name})\n    .gap(${model.gap.to_str()})\n    .pad(${model.pad.to_str()}, ${model.pad.to_str()}, ${model.pad.to_str()}, ${model.pad.to_str()})\n    .child_align(...)"),
			],
		)
	}

	controls : Theme, Model -> View(Msg)
	controls = |theme, model| box(
		{ style: |_| style.width(Grow({})).direction(Col).gap(theme.gap).child_align({ x: Start, y: Start }) },
		[
			container_controls(theme, model),
			child_controls(theme, Child0, "Child 0", model.children.zero),
			child_controls(theme, Child1, "Child 1", model.children.one),
			child_controls(theme, Child2, "Child 2", model.children.two),
		],
	)
}

container_controls : Theme, Model -> View(Msg)
container_controls = |theme, model| Parts.controls_section(
	theme,
	Id("container"),
	[
		Parts.copy("Container"),
		Parts.code_text(theme, ".direction(${direction_name(model.direction)})"),
		select(theme, { open: model.direction_open, selected: direction_selected(model.direction), options: direction_options, on_toggle_open: |open| ToggleDirection(open), on_select: |index| SetDirection(direction_from(index)) }),
		Parts.code_text(theme, ".gap(${model.gap.to_str()})"),
		slider(theme, model.gap, 0, 48, 4, |gap| SetGap(gap)),
		Parts.code_text(theme, ".pad(${model.pad.to_str()}, ${model.pad.to_str()}, ${model.pad.to_str()}, ${model.pad.to_str()})"),
		slider(theme, model.pad, 0, 48, 4, |pad| SetPad(pad)),
		Parts.code_text(theme, ".child_align({ x: ${align_name(model.child_align.x)}, y: ${align_name(model.child_align.y)} })"),
		box(
			{ style: |_| style.width(Grow({})).height(Fit({})).direction(Row).gap(theme.gap / 2).child_align({ x: Start, y: Start }) },
			[
				select(theme, { open: model.child_align_x_open, selected: align_selected(model.child_align.x), options: align_options, on_toggle_open: |open| ToggleChildAlignX(open), on_select: |index| SetChildAlignX(align_from(index)) }),
				select(theme, { open: model.child_align_y_open, selected: align_selected(model.child_align.y), options: align_options, on_toggle_open: |open| ToggleChildAlignY(open), on_select: |index| SetChildAlignY(align_from(index)) }),
			],
		),
	],
)

update_child : Children, ChildIndex, (Child -> Child) -> Children
update_child = |children, index, change| match index {
	Child0 => { ..children, zero: change(children.zero) }
	Child1 => { ..children, one: change(children.one) }
	Child2 => { ..children, two: change(children.two) }
}

direction_options : List(Str)
direction_options = ["Row", "Column"]

direction_selected : Direction -> U64
direction_selected = |direction| if direction == Row 0 else 1

direction_from : U64 -> Direction
direction_from = |index| if index == 0 Row else Col

direction_name : Direction -> Str
direction_name = |direction| if direction == Row "Row" else "Col"

align_options : List(Str)
align_options = ["Start", "Center", "End"]

align_selected : ChildAlign -> U64
align_selected = |align| match align {
	Start => 0
	Center => 1
	End => 2
}

align_from : U64 -> ChildAlign
align_from = |index| match index {
	0 => Start
	1 => Center
	_ => End
}

align_name : ChildAlign -> Str
align_name = |align| match align {
	Start => "Start"
	Center => "Center"
	End => "End"
}

child_controls : Theme, ChildIndex, Str, Child -> View(Msg)
child_controls = |theme, index, label, child| Parts.controls_section(
	theme,
	child_controls_id(index),
	[
		Parts.copy(label),
		axis_controls(
			theme,
			"width",
			child.width,
			|open| ToggleChildWidthMode(index, open),
			|mode| SetChildWidthMode(index, mode),
			|fit| SetChildWidthFit(index, fit),
			|fixed| SetChildWidthFixed(index, fixed),
			|percent| SetChildWidthPercent(index, percent),
		),
		axis_controls(
			theme,
			"height",
			child.height,
			|open| ToggleChildHeightMode(index, open),
			|mode| SetChildHeightMode(index, mode),
			|fit| SetChildHeightFit(index, fit),
			|fixed| SetChildHeightFixed(index, fixed),
			|percent| SetChildHeightPercent(index, percent),
		),
	],
)

axis_controls : Theme, Str, AxisSizing, (Bool -> Msg), (SizingMode -> Msg), (Bounds -> Msg), (F32 -> Msg), (F32 -> Msg) -> View(Msg)
axis_controls = |theme, axis, sizing, on_toggle, on_mode, on_fit, on_fixed, on_percent| box(
	{ style: |_| style.width(Grow({})).height(Fit({})).direction(Col).gap(theme.gap / 4).child_align({ x: Start, y: Start }) },
	[
		Parts.code_text(theme, ".${axis}(${sizing_code(sizing)})"),
		select(theme, { open: sizing.select_open, selected: sizing_mode_selected(sizing.mode), options: sizing_mode_options, on_toggle_open: on_toggle, on_select: |selected| on_mode(sizing_mode_from(selected)) }),
		axis_value_control(theme, sizing, on_fit, on_fixed, on_percent),
	],
)

axis_value_control : Theme, AxisSizing, (Bounds -> Msg), (F32 -> Msg), (F32 -> Msg) -> View(Msg)
axis_value_control = |theme, sizing, on_fit, on_fixed, on_percent| match sizing.mode {
	GrowMode => box({ style: |_| style.width(Fit({})).height(Fit({})) }, [])
	FitMode => range_slider(theme, sizing.fit, 0, 160, 8, on_fit)
	FixedMode => slider(theme, sizing.fixed, 20, 160, 4, on_fixed)
	PercentMode => slider(theme, sizing.percent, 0, 1, 0.05, on_percent)
}

default_axis : SizingMode, Bounds, F32, F32 -> AxisSizing
default_axis = |mode, fit, fixed, percent| { mode, select_open: False, fit, fixed, percent }

sizing_mode_options : List(Str)
sizing_mode_options = ["Grow", "Fit", "Fixed", "Percent"]

sizing_mode_selected : SizingMode -> U64
sizing_mode_selected = |mode| match mode {
	GrowMode => 0
	FitMode => 1
	FixedMode => 2
	PercentMode => 3
}

sizing_mode_from : U64 -> SizingMode
sizing_mode_from = |selected| match selected {
	0 => GrowMode
	1 => FitMode
	2 => FixedMode
	_ => PercentMode
}

sizing_code : AxisSizing -> Str
sizing_code = |sizing| match sizing.mode {
	GrowMode => "Grow({})"
	FitMode => "Fit({ min: ${sizing.fit.min.to_str()}, max: ${sizing.fit.max.to_str()} })"
	FixedMode => "Fixed(${sizing.fixed.to_str()})"
	PercentMode => "Percent(${sizing.percent.to_str()})"
}

child_controls_id : ChildIndex -> ElementId
child_controls_id = |index| match index {
	Child0 => Id("child-0")
	Child1 => Id("child-1")
	Child2 => Id("child-2")
}

chip : Theme, Str, Child, U64 -> View(msg)
chip = |theme, content, child, color_index| box(
	{ id: Id("child-${content}"), style: |_| style.width(to_sizing(child.width)).height(to_sizing(child.height)).child_align({ x: Center, y: Center }).background(Parts.transparent_example_fill(color_index)).border({ color: Parts.example_color(color_index), left: 1, right: 1, top: 1, bottom: 1 }).font_color(theme.palette.surface.base.content) },
	[BoxId.view(Parts.example_color(color_index), "child-${content}")],
)

to_sizing : AxisSizing -> Sizing
to_sizing = |axis| match axis.mode {
	GrowMode => Grow({})
	FitMode => Fit({ min: axis.fit.min, max: axis.fit.max })
	FixedMode => Fixed(axis.fixed)
	PercentMode => Percent(axis.percent)
}
