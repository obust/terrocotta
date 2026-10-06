## The lesson for configuring a box outside normal layout flow.
import tc.Element exposing [AttachPoint.*, ElementId.*, box, default_floating_config, style]
import tc.Program exposing [View]
import tc.Theme
import tc.Widget exposing [select, slider]

import ../ui/Parts
import ../widgets/BoxId
import ../widgets/CodeBlock
import ../widgets/DemoFrame

Floating := [].{
	AttachPoints : { element : AttachPoint, target : AttachPoint }
	Model : { attach_points : AttachPoints, element_open : Bool, target_open : Bool, offset : { x : F32, y : F32 }, expand : { w : F32, h : F32 } }
	Msg : [SetAttachElement(AttachPoint), ToggleAttachElement(Bool), SetAttachTarget(AttachPoint), ToggleAttachTarget(Bool), SetOffsetX(F32), SetOffsetY(F32), SetExpandW(F32), SetExpandH(F32)]

	initial : Model
	initial = { attach_points: { element: Center, target: Center }, element_open: False, target_open: False, offset: { x: 0, y: 0 }, expand: { w: 0, h: 0 } }

	update : Model, Msg -> Model
	update = |model, message| match message {
		SetAttachElement(element) => { ..model, attach_points: { ..model.attach_points, element } }
		ToggleAttachElement(element_open) => { ..model, element_open }
		SetAttachTarget(target) => { ..model, attach_points: { ..model.attach_points, target } }
		ToggleAttachTarget(target_open) => { ..model, target_open }
		SetOffsetX(x) => { ..model, offset: { ..model.offset, x } }
		SetOffsetY(y) => { ..model, offset: { ..model.offset, y } }
		SetExpandW(w) => { ..model, expand: { ..model.expand, w } }
		SetExpandH(h) => { ..model, expand: { ..model.expand, h } }
	}

	guide : Theme, Model -> View(Msg)
	guide = |theme, model| {
		box(
			{ style: |_| style.width(Grow({})).direction(Col).gap(theme.gap).child_align({ x: Start, y: Start }) },
			[
				Parts.heading(theme, "Floating"),
				Parts.copy("A floating box is removed from normal layout and attached to a target. Configure both anchors, then adjust its offset and expanded hit area."),
				DemoFrame.view(
					theme,
					[
						box(
							{ id: Id("container"), style: |_| style.width(Fixed(340)).height(Fixed(160)).background(Parts.transparent_example_fill(0)).border({ color: Parts.example_color(0), left: 1, right: 1, top: 1, bottom: 1 }) },
							[
						box(
							{
								id: Id("floating"),
									style: |_| style.width(Fixed(110)).height(Fixed(44)).child_align({ x: Center, y: Center }).background(Parts.transparent_example_fill(1)).border({ color: Parts.example_color(1), left: 1, right: 1, top: 1, bottom: 1 }).font_color(theme.palette.surface.base.content).floating(Floating({ target: Parent, config: { ..default_floating_config, z_index: 10, attach_points: model.attach_points, offset: model.offset, expand: model.expand } })),
									},
									[BoxId.view(Parts.example_color(1), "floating")],
								),
								BoxId.view(Parts.example_color(0), "container"),
							],
						),
					],
				),
				CodeBlock.view(
					theme,
					CodeBlock.format(
						CodeBlock.box_node(
							"{ id: Id(\"container\"), style: |_| style... }",
							[
								CodeBlock.box_node(
									"{ id: Id(\"floating\"), style: |_| style.floating(Floating({ target: Parent, config: { ... }) }",
									[],
								),
							],
						),
					),
				),
			],
		)
	}

	controls : Theme, Model -> View(Msg)
	controls = |theme, model| box(
		{ style: |_| style.width(Grow({})).direction(Col).gap(theme.gap).child_align({ x: Start, y: Start }) },
		[
			Parts.controls_section(
				theme,
				Id("floating-controls"),
				[
					Parts.copy("Floating box"),
					Parts.code_text(theme, "attach_points : { element: ${attach_to_str(model.attach_points.element)}, target: ${attach_to_str(model.attach_points.target)} }"),
					box(
						{ style: |_| style.width(Grow({})).height(Fit({})).direction(Row).gap(theme.gap / 2).child_align({ x: Start, y: Start }) },
						[
							select(theme, { open: model.element_open, selected: attach_selected(model.attach_points.element), options: attach_options, on_toggle_open: |open| ToggleAttachElement(open), on_select: |selected| SetAttachElement(attach_from(selected)) }),
							select(theme, { open: model.target_open, selected: attach_selected(model.attach_points.target), options: attach_options, on_toggle_open: |open| ToggleAttachTarget(open), on_select: |selected| SetAttachTarget(attach_from(selected)) })
						],
					),
					Parts.code_text(theme, "offset : { x: ${model.offset.x.to_str()}, y: ${model.offset.y.to_str()} }"),
					box(
						{ style: |_| style.width(Grow({})).height(Fit({})).direction(Row).gap(theme.gap / 2).child_align({ x: Start, y: Start }) },
						[
    						slider(theme, model.offset.x, -80, 80, 4, |x| SetOffsetX(x)),
    						slider(theme, model.offset.y, -80, 80, 4, |y| SetOffsetY(y)),
						],
					),
					Parts.code_text(theme, "expand : { w: ${model.expand.w.to_str()}, h: ${model.expand.h.to_str()} }"),
					box(
						{ style: |_| style.width(Grow({})).height(Fit({})).direction(Row).gap(theme.gap / 2).child_align({ x: Start, y: Start }) },
						[
    						slider(theme, model.expand.w, 0, 80, 4, |w| SetExpandW(w)),
                            slider(theme, model.expand.h, 0, 80, 4, |h| SetExpandH(h))
						],
					),
				],
			),
		],
	)
}

attach_options : List(Str)
attach_options = ["LeftTop", "LeftCenter", "LeftBottom", "CenterTop", "Center", "CenterBottom", "RightTop", "RightCenter", "RightBottom"]

attach_selected : AttachPoint -> U64
attach_selected = |point| match point {
	LeftTop => 0
	LeftCenter => 1
	LeftBottom => 2
	CenterTop => 3
	Center => 4
	CenterBottom => 5
	RightTop => 6
	RightCenter => 7
	RightBottom => 8
}

attach_from : U64 -> AttachPoint
attach_from = |selected| match selected {
	0 => LeftTop
	1 => LeftCenter
	2 => LeftBottom
	3 => CenterTop
	4 => Center
	5 => CenterBottom
	6 => RightTop
	7 => RightCenter
	_ => RightBottom
}

attach_to_str : AttachPoint -> Str
attach_to_str = |point| match point {
	LeftTop => "LeftTop"
	LeftCenter => "LeftCenter"
	LeftBottom => "LeftBottom"
	CenterTop => "CenterTop"
	Center => "Center"
	CenterBottom => "CenterBottom"
	RightTop => "RightTop"
	RightCenter => "RightCenter"
	RightBottom => "RightBottom"
}
