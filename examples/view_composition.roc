## Compose two independently routed instances of one counter view with
## Element.map.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0-rc3/3vVeddfDE6rraq5j8v1cGHtFNaQhC6dij1zGRN63NGP1.tar.zst",
	tc: "../package/main.roc",
	roc: "nightly-2026-08-23-fb208ba",
}

import rr.App

import tc.Element exposing [box, text, style, map]
import tc.Program exposing [View]
import tc.Theme
import tc.Widget exposing [button]

theme = Theme.dark

Counter := {}.{
	Message : [Increment, Decrement]

	Model : { label : Str, count : I32 }

	init : Str, I32 -> Model
	init = |label, count| { label: label, count: count }

	update : Model, Message -> Model
	update = |model, message| {
		match message {
			Decrement => { ..model, count: model.count - 1 }
			Increment => { ..model, count: model.count + 1 }
		}
	}

	view : Model -> View(Message)
	view = |model| {
		box(
			{ style: |_| style.width(Grow({})).height(Fit({})).direction(Col).gap(theme.gap) },
			[
				text(model.label),
				box(
					{
						style: |_| style.height(Fit({})).direction(Row).gap(theme.gap),
					},
					[
						button(theme, Primary, "-", [OnClick(Decrement)]),
						text(model.count.to_str()),
						button(theme, Primary, "+", [OnClick(Increment)]),
					],
				),
			],
		)
	}
}

AppModel : {
	left : Counter.Model,
	right : Counter.Model,
}

Msg : [
	Left(Counter.Message),
	Right(Counter.Message),
	Reset,
]

Model : Program.State(AppModel, Msg)

configure : List(Str) -> App.Config
configure = |_args|
	App.default
		.with_title("Element.map Example")
		.with_size({ width: 640, height: 420 })

init! : App.InitCallback(AppModel, [])
init! = |_startup| Ok({ left: Counter.init("Left", 0), right: Counter.init("Right", 10) })

update : AppModel, Msg -> AppModel
update = |model, msg|
	match msg {
		Left(left_msg) =>
			{ ..model, left: Counter.update(model.left, left_msg) }

		Right(right_msg) =>
			{ ..model, right: Counter.update(model.right, right_msg) }

		Reset => { left: Counter.init("Left", 0), right: Counter.init("Right", 10) }
	}

view : AppModel -> View(Msg)
view = |model|
	box(
		{
			style: |_| style
				.direction(Col)
				.gap(theme.gap)
				.background(theme.palette.background.base.fill)
				.font_size(theme.font_size)
				.font_color(theme.palette.background.base.content),
		},
		[
			box(
				{
					style: |_| style.height(Fit({})).direction(Row).gap(theme.gap),
				},
				[
					Counter.view(model.left) |> map(|msg| Left(msg)),
					Counter.view(model.right) |> map(|msg| Right(msg)),
				],
			),
			button(theme, Primary, "Reset", [OnClick(Reset)]),
		],
	)

expect {
	model = { left: Counter.init("Left", 0), right: Counter.init("Right", 10) }
	updated = update(model, Left(Increment))
	updated.left.count == 1 and updated.right.count == 10
}

expect {
	model = { left: Counter.init("Left", 0), right: Counter.init("Right", 10) }
	updated = update(model, Right(Decrement))
	updated.left.count == 0 and updated.right.count == 9
}

expect {
	model = { left: Counter.init("Left", 4), right: Counter.init("Right", 7) }
	updated = update(model, Reset)
	updated.left.count == 0
		and updated.left.label == "Left"
			and updated.right.count == 10
				and updated.right.label == "Right"
}

program = Program.new(configure, init!, update, view)
