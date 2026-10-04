## Screwbot: an interactive inverse-kinematics workbench.
##
## The solver produces a robot pose in ordinary joint-angle space, then stores
## the mechanism as roc-ray 3D PGA points, lines, a plane, and a translation
## motor. Terracotta renders the projected geometry and exposes its live PGA
## coefficients as a small inspection console.
##
## The 3D scene is drawn by `Element.canvas`, whose closure runs during
## `render!` with the frame and the node's resolved bounds. `SceneRenderer`
## turns that into the offscreen scene pass, bloom chain, and composite.
##
## The app shell below only wires the pieces together: `State` owns the model
## and routes messages, `Views` composes the UI, `Scene` stacks the
## per-component layers from `WarehouseScene` and `RobotScene`, and
## `resources!` loads the compositor pipeline while each component loads its
## own textures.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst",
	tc: "../../package/main.roc",
	roc: "nightly-2026-09-27-a3ce7f1",
}

import rr.App
import rr.Assets
import rr.Draw

import tc.Program

import RobotScene
import SceneRenderer
import State
import Views
import WarehouseScene

## The small authored inputs are embedded from paths relative to this source
## file; the material textures are loaded from `examples/assets` at startup.
import "../assets/screwbot-scene.fs" as scene_shader_source : Str
import "../assets/screwbot-floor.fs" as floor_shader_source : Str
import "../assets/screwbot-robot.fs" as robot_shader_source : Str
import "../assets/screwbot-emissive.fs" as emissive_shader_source : Str
import "../assets/screwbot-blur.fs" as blur_shader_source : Str

Model : Program.State(State.AppModel, State.Msg)

Msg : State.Msg

assets_dir = "examples/assets"

## Load every GPU resource up front. All of these effects are legal only in
## `init!`; the loaded shaders and render targets are then owned by the model
## for the lifetime of the app, and each component loads its own textures.
resources! : App.Io => Try(State.Resources, [Exit(I64)])
resources! = |io| {
	directory = io.files().open_dir_read!(assets_dir).map_err(|_| Exit(1))?
	store = Assets.open!(directory, IgnoreManifest).map_err(|_| Exit(1))?
	warehouse = WarehouseScene.load!(store)?
	robot_textures = RobotScene.load!(store)?

	scene_target = Draw.RenderTexture.load!(SceneRenderer.scene_size).map_err(|_| Exit(1))?
	bloom_a = Draw.RenderTexture.load!(SceneRenderer.bloom_size).map_err(|_| Exit(1))?
	bloom_b = Draw.RenderTexture.load!(SceneRenderer.bloom_size).map_err(|_| Exit(1))?

	floor_shader = Draw.Shader.from_source!({ vertex_source: "", fragment_source: floor_shader_source }).map_err(|_| Exit(1))?
	robot_shader = Draw.Shader.from_source!({ vertex_source: "", fragment_source: robot_shader_source }).map_err(|_| Exit(1))?
	emissive_shader = Draw.Shader.from_source!({ vertex_source: "", fragment_source: emissive_shader_source }).map_err(|_| Exit(1))?
	blur_shader = Draw.Shader.from_source!({ vertex_source: "", fragment_source: blur_shader_source }).map_err(|_| Exit(1))?
	composite_shader = Draw.Shader.from_source!({ vertex_source: "", fragment_source: scene_shader_source }).map_err(|_| Exit(1))?

	Ok({
		warehouse,
		robot_textures,
		compositor: {
			scene_target,
			bloom_a,
			bloom_b,
			floor_shader,
			robot_shader,
			emissive_shader,
			blur_shader,
			composite_shader,
			floor_time: floor_shader.uniform_f32!("time").map_err(|_| Exit(1))?,
			floor_target_uv: floor_shader.uniform_vec2!("targetUv").map_err(|_| Exit(1))?,
			floor_reachable: floor_shader.uniform_f32!("reachable").map_err(|_| Exit(1))?,
			floor_error: floor_shader.uniform_f32!("errorAmount").map_err(|_| Exit(1))?,
			robot_time: robot_shader.uniform_f32!("time").map_err(|_| Exit(1))?,
			robot_reachable: robot_shader.uniform_f32!("reachable").map_err(|_| Exit(1))?,
			robot_error: robot_shader.uniform_f32!("errorAmount").map_err(|_| Exit(1))?,
			blur_direction: blur_shader.uniform_vec2!("direction").map_err(|_| Exit(1))?,
			blur_resolution: blur_shader.uniform_vec2!("resolution").map_err(|_| Exit(1))?,
			composite_time: composite_shader.uniform_f32!("time").map_err(|_| Exit(1))?,
			composite_resolution: composite_shader.uniform_vec2!("resolution").map_err(|_| Exit(1))?,
			composite_bloom: composite_shader.uniform_texture!("bloomTexture").map_err(|_| Exit(1))?,
		},
	})
}

configure : List(Str) -> App.Config
configure = |_args|
	App.default
		.with_title("Screwbot // PGA Kinematics Lab")
		.with_size({ width: 1280, height: 900 })
		.with_resizable(True)
		.with_permission(Directory(assets_dir, ReadOnly))

init! : App.InitCallback(State.AppModel, [])
init! = |io| {
	resources = resources!(io)?
	Ok(State.initial(resources))
}

program = Program.new(configure, init!, State.update, Views.view)
