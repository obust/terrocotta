## Screwbot: an interactive inverse-kinematics workbench.
##
## The solver produces a robot pose in ordinary joint-angle space, then stores
## the mechanism as roc-ray 3D PGA points, lines, a plane, and a translation
## motor. Terracotta renders the projected geometry and exposes its live PGA
## coefficients as a small inspection console.
##
## The 3D scene is drawn by `Element.canvas`, whose closure runs during
## `render!` with the frame and the node's resolved bounds. The app renders
## directly into an offscreen scene target, then composites it into the canvas.
##
## This file owns app startup, input routing, and UI composition. Direct draw
## calls stack the warehouse and robot; components load their assets at startup.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst",
	tc: "../../package/main.roc",
	roc: "nightly-2026-09-27-a3ce7f1",
}

import rr.App
import rr.Assets
import rr.Draw

import tc.Color
import tc.Element exposing [box, map, style]
import tc.Program
import tc.Theme

import Inspector
import Palette exposing [amber, cyan, green, ink, red, surface]
import RobotScene
import SceneCamera
import SceneDraw
import Screwbot
import Toolbar
import Viewport
import Warehouse

## The small authored inputs are embedded from paths relative to this source
## file; the material textures are loaded from `examples/assets` at startup.
import "../assets/screwbot-floor.fs" as floor_shader_source : Str
import "../assets/screwbot-robot.fs" as robot_shader_source : Str

Model : Program.State(Screwbot.Model, Screwbot.Msg)

Msg : Screwbot.Msg

assets_dir = "examples/assets"

configure : List(Str) -> App.Config
configure = |_args|
	App.default
		.with_title("Screwbot // PGA Kinematics Lab")
		.with_size({ width: 1280, height: 900 })
		.with_resizable(True)
		.with_permission(Directory(assets_dir, ReadOnly))

init! : App.InitCallback(Screwbot.Model, [])
init! = |io| {
	directory = io.files().open_dir_read!(assets_dir).map_err(|_| Exit(1))?
	store = Assets.open!(directory, IgnoreManifest).map_err(|_| Exit(1))?
	warehouse = Warehouse.init!(store)?
	robot_assets = RobotScene.init!(store)?
	scene_target = Draw.RenderTexture.load!(SceneDraw.scene_size).map_err(|_| Exit(1))?
	floor_shader = Draw.Shader.from_source!({ vertex_source: "", fragment_source: floor_shader_source }).map_err(|_| Exit(1))?
	robot_shader = Draw.Shader.from_source!({ vertex_source: "", fragment_source: robot_shader_source }).map_err(|_| Exit(1))?
	render_resources = {
		warehouse,
		robot: robot_assets,
		compositor: {
			scene_target,
			floor_shader: {
				program: floor_shader,
				time: floor_shader.uniform_f32!("time").map_err(|_| Exit(1))?,
				target_uv: floor_shader.uniform_vec2!("targetUv").map_err(|_| Exit(1))?,
				reachable: floor_shader.uniform_f32!("reachable").map_err(|_| Exit(1))?,
				error_amount: floor_shader.uniform_f32!("errorAmount").map_err(|_| Exit(1))?,
			},
			robot_shader: {
				program: robot_shader,
				time: robot_shader.uniform_f32!("time").map_err(|_| Exit(1))?,
				reachable: robot_shader.uniform_f32!("reachable").map_err(|_| Exit(1))?,
				error_amount: robot_shader.uniform_f32!("errorAmount").map_err(|_| Exit(1))?,
			},
		},
	}
	Ok({
		theme: Theme.from_seed({ background: surface, text: ink, primary: cyan, success: green, warning: amber, danger: red }),
		render_resources,
		world: { robot: RobotScene.initial, camera_controller: SceneCamera.initial },
	})
}

update : Screwbot.Model, Screwbot.Msg -> Screwbot.Model
update = |model, msg| match msg {
	RobotMsg(robot_msg) => {
		robot = RobotScene.update(model.world.robot, robot_msg)
		{ ..model, world: { ..model.world, robot } }
	}
	CameraMsg(camera_msg) => { ..model, world: { ..model.world, camera_controller: SceneCamera.update(model.world.camera_controller, camera_msg) } }
}

## The app shell composes independently routed UI components. The components
## themselves know only their local messages, as in the todos example.
view : Screwbot.Model -> Program.View(Screwbot.Msg)
view = |model| {
	solution = RobotScene.solve(model.world.robot)
	viewport = Viewport.view(
		model.world.robot,
		model.world.camera_controller,
		solution,
		|frame, bounds| Screwbot.render!(frame, bounds, model),
	)

	box(
		{
			style: |_|
				style.background(0x0a1020.Color).direction(Col).child_align({ x: Start, y: Start }).font_size(17).font_color(ink),
		},
		[
			Toolbar.view(model.theme, solution) |> map(|msg| RobotMsg(msg)),
			box(
				{
					style: |_|
						style.width(Grow({ min: 0, max: 10000 })).height(Grow({ min: 0, max: 10000 })).pad(16, 16, 16, 16).gap(16).direction(Row).overflow(Hidden, Hidden).child_align({ x: Start, y: Start }),
				},
				[
					viewport |> map(viewport_msg),
					Inspector.view(model.theme, model.world.robot, solution) |> map(|msg| RobotMsg(msg)),
				],
			),
		],
	)
}

viewport_msg : Viewport.Msg -> Screwbot.Msg
viewport_msg = |msg| match msg {
	Robot(robot_msg) => RobotMsg(robot_msg)
	Camera(camera_msg) => CameraMsg(camera_msg)
}

program = Program.new(configure, init!, update, view)
