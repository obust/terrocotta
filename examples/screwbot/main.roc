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
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.11.1/4NWnSt7bKCyVx4xDFH89pV11ekYbiGQ43kdjfZ9NBJQn.tar.zst",
	tc: "../../package/main.roc",
}

import rr.App as RayApp
import rr.Capture
import rr.Assets
import rr.Draw
import rr.Shader

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

capture_recording = Capture.default
	.with_path("screwbot.png")
	.with_format(Png)
	.with_max_frames(1)
	.with_scale(Full)
	.with_timing(FixedStep)

configure : List(Str) -> RayApp.Config
configure = |_args| {
	RayApp.default
		.with_title("Screwbot // PGA Kinematics Lab")
		.with_size({ width: 1280, height: 900 })
		.with_resizable(True)
		.with_permission(Directory(assets_dir, ReadOnly))
		.with_output_dir("captures")
		.with_frame_pacing(Uncapped)
}

init! : RayApp.InitCallback(
	Scene.Model,
	[
		PermissionDenied,
		PathInvalid,
		NotFound,
		NotADirectory,
		AccessRefused,
		OpenFailed,
		Unavailable,
		RootNotFound,
		RootNotDirectory,
		RootUnreadable,
		InvalidExpectedContentHash,
		ManifestMissing,
		ManifestUnreadable,
		ManifestMalformed,
		AssetSetMismatch,
		SchemaMismatch,
		ContentVersionMismatch,
		ContentHashMismatch,
		ReadFailed,
		TextureLoadFailed,
		RenderTextureLoadFailed,
		ShaderLoadFailed,
		UniformNotFound(Str),
		UniformReflectionUnavailable,
		UniformTypeMismatch({ name : Str, expected : Shader.ShaderUniformType, actual : Shader.ShaderUniformType }),
		UnsupportedUniformType(Str),
		ResourceLimit,
	],
)
init! = |io| {
	if io.args!().contains("--capture") {
		_ = io.capture().start!(capture_recording) ? |_| Exit(1)
	}
	random_seed = io.entropy!()
	directory = io.files().open_dir_read!(assets_dir)?
	store = Assets.open!(directory, IgnoreManifest)?
	warehouse = Warehouse.init!(store)?
	robot_assets = Robot.init!(store)?
	scene_target = Draw.RenderTexture.load!(Drawing.scene_size)?
	floor_shader = Shader.from_source!({ vertex_source: "", fragment_source: floor_shader_source }, { time: 0.F32, target_uv: { x: 0.F32, y: 0.F32 }, reachable: 0.F32, error_amount: 0.F32 })?
	robot_shader = Shader.from_source!({ vertex_source: "", fragment_source: robot_shader_source }, { time: 0.F32, reachable: 0.F32, error_amount: 0.F32 })?
	render_resources = {
		warehouse,
		robot: robot_assets,
		scene_target,
		shaders: {
			floor: floor_shader,
			robot: robot_shader,
		},
	}
	Ok({
		theme: Theme.from_seed(BuiltinPalette.atom_dark),
		render_resources,
		world: { robot: Robot.with_random_seed(Robot.initial, random_seed), camera_controller: Camera.initial },
	})
}

update! : Scene.Model, Scene.Msg, RayApp.Io, RayApp.Input(Scene.Msg) => Scene.Model
update! = |model, msg, _io, _input| {
	match msg {
		RobotMsg(robot_msg) => {
			robot = Robot.update(model.world.robot, robot_msg)
			{ ..model, world: { ..model.world, robot } }
		}
		CameraMsg(camera_msg) => { ..model, world: { ..model.world, camera_controller: Camera.update(model.world.camera_controller, camera_msg) } }
	}
}

## The app shell composes independently routed UI components. The components
## themselves know only their local messages, as in the todos example.
view : Scene.Model -> Program.View(Scene.Msg)
view = |model| {
	solution = Robot.solve(model.world.robot)
	viewport = Viewport.view(
		model.theme,
		model.world.robot,
		model.world.camera_controller.camera,
		|frame, bounds| Scene.render!(frame, bounds, model, solution),
	)

	box(
		{ style: |_| style.background(model.theme.palette.surface.base.fill).direction(Col) },
		[
			Topbar.view(model.theme),
			box(
				{ style: |_| style.direction(Row) },
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

program = Program.new(configure, init!, update!, view)
