## Sev-inspired read-only IDE example.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst",
	tc: "../../package/main.roc",
}

import rr.App as RayApp
import tc.Program

import App

Model : Program.State(App.Model, App.Msg)

Msg : App.Msg

configure : List(Str) -> RayApp.Config
configure = |_args| {
	RayApp.default
		.with_title("Terrocotta IDE")
		.with_size({ width: 1280, height: 800 })
		.with_resizable(True)
		.with_exit_key(NoExitKey)
		.with_permission(Directory("examples/ide", ReadOnly))
		.with_default_font({ path: "examples/ide/Inter-Regular.ttf", size: 36 })
		.with_output_dir("captures")
		.with_frame_pacing(Uncapped)
}

program = Program.new(configure, App.init!, App.update!, App.view)
