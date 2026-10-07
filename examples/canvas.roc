## A canvas circle follows the pointer through ordinary box events.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst",
	tc: "../package/main.roc",
}

import rr.App
import rr.Color
import rr.Draw
import tc.Element exposing [box, text, style]
import tc.Event
import tc.Program exposing [View]

Model : Program.State(AppModel, Msg)

AppModel : { pointer : Event.Point }

Msg : [MovePointer(Event.Point)]

configure : List(Str) -> App.Config
configure = |_args| App.default.with_title("Canvas").with_size({ width: 640, height: 480 })

init! : App.InitCallback(AppModel, [])
init! = |_io| Ok({ pointer: { x: 320, y: 240 } })

update! : AppModel, Msg, App.Io, App.Input(Msg) => AppModel
update! = |model, msg, _io, _input| {
	match msg {
		MovePointer(pointer) => { ..model, pointer }
	}
}

view : AppModel -> View(Msg)
view = |model| box(
	{
		style: |_| style.direction(Col).pad(24, 24, 24, 24).gap(16).background(0x202838).font_color(0xFFFFFF).font_size(18),
		events: [OnPointer(Box.box(|event| MovePointer(event.position)))],
	},
	[
		text("Move the pointer to move the circle."),
		box(
			{ style: |_| style.background(0x303C50) },
			[
				Element.canvas(
					|frame, _bounds| {
						frame.circle!({
							center: { x: model.pointer.x, y: model.pointer.y },
							radius: 20,
							style: Draw.filled(Color.orange),
						})
						Ok({})
					},
				),
			],
		),
	],
)

program = Program.new(configure, init!, update!, view)
