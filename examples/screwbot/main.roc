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
	roc: "nightly-2026-10-03-c507926",
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst",
	tc: "../../package/main.roc",
}

import rr.App as RayApp
import rr.Assets
import rr.Draw

import tc.Color
import tc.Element exposing [box, map, style]
import tc.Palette as BuiltinPalette
import tc.Program
import tc.Theme

import ui/Inspector
import scene/Robot
import scene/Camera
import scene/Drawing
import scene/Scene
import ui/Topbar
import ui/Viewport
import scene/Warehouse

## The small authored inputs are embedded from paths relative to this source
## file; the material textures are loaded from the local `assets` directory at startup.
import "assets/screwbot-floor.fs" as floor_shader_source : Str
import "assets/screwbot-robot.fs" as robot_shader_source : Str

Model : Program.State(Scene.Model, Scene.Msg)

Msg : Scene.Msg

assets_dir = "examples/screwbot/assets"

configure : List(Str) -> RayApp.Config
configure = |_args|
	RayApp.default
		.with_title("Screwbot // PGA Kinematics Lab")
		.with_size({ width: 1280, height: 900 })
		.with_resizable(True)
		.with_permission(Directory(assets_dir, ReadOnly))

init! : RayApp.InitCallback(Scene.Model, [])
init! = |io| {
	random_seed = io.entropy!()
	directory = io.files().open_dir_read!(assets_dir) ? |_| Exit(1)
	store = Assets.open!(directory, IgnoreManifest) ? |_| Exit(1)
	warehouse = Warehouse.init!(store)?
	robot_assets = Robot.init!(store)?
	scene_target = Draw.RenderTexture.load!(Drawing.scene_size) ? |_| Exit(1)
	floor_shader = Draw.Shader.from_source!({ vertex_source: "", fragment_source: floor_shader_source }) ? |_| Exit(1)
	robot_shader = Draw.Shader.from_source!({ vertex_source: "", fragment_source: robot_shader_source }) ? |_| Exit(1)
	render_resources = {
		warehouse,
		robot: robot_assets,
		compositor: {
			scene_target,
			floor_shader: {
				program: floor_shader,
				time: floor_shader.uniform_f32!("time") ? |_| Exit(1),
				target_uv: floor_shader.uniform_vec2!("targetUv") ? |_| Exit(1),
				reachable: floor_shader.uniform_f32!("reachable") ? |_| Exit(1),
				error_amount: floor_shader.uniform_f32!("errorAmount") ? |_| Exit(1),
			},
			robot_shader: {
				program: robot_shader,
				time: robot_shader.uniform_f32!("time") ? |_| Exit(1),
				reachable: robot_shader.uniform_f32!("reachable") ? |_| Exit(1),
				error_amount: robot_shader.uniform_f32!("errorAmount") ? |_| Exit(1),
			},
		},
	}
	Ok({
		theme: Theme.from_seed(BuiltinPalette.atom_dark),
		render_resources,
		world: { robot: Robot.with_random_seed(Robot.initial, random_seed), camera_controller: Camera.initial },
	})
}

update : Scene.Model, Scene.Msg -> Scene.Model
update = |model, msg| match msg {
	RobotMsg(robot_msg) => {
		robot = Robot.update(model.world.robot, robot_msg)
		{ ..model, world: { ..model.world, robot } }
	}
	CameraMsg(camera_msg) => { ..model, world: { ..model.world, camera_controller: Camera.update(model.world.camera_controller, camera_msg) } }
}

## The app shell composes independently routed UI components. The components
## themselves know only their local messages, as in the todos example.
view : Scene.Model -> Program.View(Scene.Msg)
view = |model| {
	solution = Robot.solve(model.world.robot)
	viewport = Viewport.view(
		model.theme,
		model.world.robot,
		model.world.camera_controller,
		solution,
		|frame, bounds| Scene.render!(frame, bounds, model),
	)

	box(
		{
			style: |_|
				style.background(model.theme.palette.background.base.fill).direction(Col).child_align({ x: Start, y: Start }).font_size(17).font_color(model.theme.palette.background.base.content),
		},
		[
			Topbar.view(model.theme),
			box(
				{
					style: |_|
						style.width(Grow({ min: 0, max: 10000 })).height(Grow({ min: 0, max: 10000 })).direction(Row).overflow(Hidden, Hidden).child_align({ x: Start, y: Start }),
				},
				[
					viewport |> map(viewport_msg),
					Inspector.view(model.theme, model.world.robot, solution) |> map(|msg| RobotMsg(msg)),
				],
			),
		],
	)
}

viewport_msg : Viewport.Msg -> Scene.Msg
viewport_msg = |msg| match msg {
	Robot(robot_msg) => RobotMsg(robot_msg)
	Camera(camera_msg) => CameraMsg(camera_msg)
}

program = Program.new(configure, init!, update, view)
