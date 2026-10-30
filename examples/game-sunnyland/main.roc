app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst",
	tc: "../../package/main.roc",
}

import rr.App as RayApp
import rr.Capture
import rr.Devices
import rr.Math
import tc.Color
import tc.Element exposing [box, canvas, style]
import tc.Program

import GameAssets
import Game
import world/Level
import world/Render
import UI

AppModel : { assets : GameAssets, level : Level, world : Game.World }

Model : Program.State(AppModel, Msg)

Msg : [Frame(Game.Controls), Ui(UI.Msg)]

capture_recording = Capture.default.with_path("sunnyland.png").with_format(Png).with_max_frames(12).with_scale(Full).with_timing(FixedStep)

configure : List(Str) -> RayApp.Config
configure = |_args| RayApp.default
	.with_title("Terrocotta: Sunnyland")
	.with_size({ width: 1152, height: 768 })
	.with_resizable(Bool.True)
	.with_exit_key(NoExitKey)
	.with_permission(Directory(GameAssets.assets_dir, ReadOnly))
	.with_output_dir("captures")
	.with_frame_pacing(Uncapped)

axis : Bool, Bool -> F32
axis = |negative, positive| if negative and positive 0 else if negative -1 else if positive 1 else 0

read_controls : Devices.Snapshot -> Game.Controls
read_controls = |input| {
	left = input.key_down(KeyLeft) or input.key_down(KeyA)
	right = input.key_down(KeyRight) or input.key_down(KeyD)
	{
		move_x: axis(left, right),
		down_down: input.key_down(KeyDown) or input.key_down(KeyS),
		jump_down: input.key_down(KeySpace),
		jump_pressed: input.key_pressed(KeySpace),
		confirm_pressed: input.key_pressed(KeyEnter),
		pause_pressed: input.key_pressed(KeyEscape),
		restart_pressed: input.key_pressed(KeyR),
	}
}

init! = |io| {
	if io.args!().contains("--capture") {
		_ = io.capture().start!(capture_recording) ? |_| Exit(1)
	}
	assets = GameAssets.load!(io)?
	level = Level.room
	initial_world = Game.new(level)
	world = if io.args!().contains("--capture-play") {
		{ ..initial_world, state: Playing }
	} else initial_world
	Ok({ assets, level, world })
}

handle_event! : GameAssets, Game.Event => {}
handle_event! = |assets, event| match event {
	GameStarted => if !assets.music.is_playing!() {
		assets.music.set_looping!(Bool.True)
		assets.music.set_volume!(0.45)
		assets.music.play!()
	}
	Jumped | PickupCollected(_, _) | EnemyStomped(_, _) | PlayerHurt | PlayerRespawned | PlayerDied | AllPickupsCollected | WonEvent => {}
}

update! : AppModel, Msg, RayApp.Io, RayApp.Input(Msg) => AppModel
update! = |model, message, _io, input| match message {
	Frame(controls) => {
		(world, events) = Game.update(model.level, model.world, controls, input.time.elapsed_seconds)
		for event in events {
			handle_event!(model.assets, event)
		}
		{ ..model, world }
	}
	Ui(Resume) => { ..model, world: { ..model.world, state: Playing } }
	Ui(Restart) => {
		handle_event!(model.assets, GameStarted)
		{ ..model, world: Game.new(model.level) }
	}
}

view : AppModel -> Program.View(Msg)
view = |model| box(
	{
		style: |_| style.width(Grow({ min: 0, max: 100000 })).height(Grow({ min: 0, max: 100000 })).background(Color.rgb(16, 28, 34)).overflow(Hidden, Hidden),
		events: [OnInput(Box.box(|input, _context| [Frame(read_controls(input))]))],
	},
	List.concat([canvas(|frame, bounds| Render.draw!(frame, bounds, model.assets, model.level, model.world))], UI.view(model.world, model.assets).map(|layer| layer.map(|message| Ui(message)))),
)

program = Program.new(configure, init!, update!, view)

expect axis(Bool.True, Bool.True) == 0
expect axis(Bool.True, Bool.False) == -1
expect axis(Bool.False, Bool.True) == 1
