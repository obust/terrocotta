## Entry point for the interactive Terrocotta tutorial.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst",
	tc: "../../package/main.roc",
}

import rr.App as RayApp
import rr.Capture
import rr.Assets
import tc.Element exposing [box, map, style]
import tc.Program

import App
import UI
import pages/Image
import pages/Layout
import pages/Floating
import pages/Text
import pages/Canvas
import ui/Nav

Model : Program.State(App.Model, App.Msg)

Msg : App.Msg

capture_recording = Capture.default.with_path("tutorial-main.png").with_format(Png).with_max_frames(1).with_scale(Full).with_timing(FixedStep)

configure : List(Str) -> RayApp.Config
configure = |args| {
	RayApp.default
		.with_title("Terrocotta Tutorial")
		.with_size({ width: 1280, height: 800 })
		.with_resizable(True)
		.with_permission(Directory("examples/tutorial/assets", ReadOnly))
		.with_default_font({ path: "examples/tutorial/assets/Inter-Regular.ttf", size: 36 })
		.with_output_dir("captures")
}

init! = |io| {

    recording = Capture.default.with_path("tutorial.png").with_format(Png).with_max_frames(1).with_scale(Full)
    _ = io.capture().start!(recording) ? |_| Exit(1)

	store = Assets.open!(io.files().open_dir_read!("examples/tutorial/assets")?, IgnoreManifest)?
	mascot = Assets.load_texture!(store, "rocotta.png")?
	Ok({
	    store,
		mascot,
		page: PageLayout(Layout.init(store))
	})
}

update! : App.Model, App.Msg, RayApp.Io, RayApp.Input(App.Msg) => App.Model
update! = |model, message, _io, input| {
	next_model = match (model.page, message) {
		(_, ChoosePage(next_page)) => {
			match next_page {
				LayoutPage => { ..model, page: PageLayout(Layout.init(model.store)) }
				TextPage => { ..model, page: PageText(Text.init(model.store)) }
				FloatingPage => { ..model, page: PageFloating(Floating.init(model.store)) }
				ImagePage => { ..model, page: PageImage(Image.init!(model.store, input, |image_message| ImageMessage(image_message))) }
				CanvasPage => { ..model, page: PageCanvas(Canvas.init(model.store)) }
			}
		}
		(PageLayout(layout_model), LayoutMessage(layout_message)) => {
			{ ..model, page: PageLayout(Layout.update(layout_model, layout_message)) }
		}
		(PageText(text_model), TextMessage(text_message)) => {
			{ ..model, page: PageText(Text.update(text_model, text_message)) }
		}
		(PageFloating(floating_model), FloatingMessage(floating_message)) => {
			{ ..model, page: PageFloating(Floating.update(floating_model, floating_message)) }
		}
		(PageImage(image_model), ImageMessage(image_message)) => {
			{ ..model, page: PageImage(Image.update(image_model, image_message)) }
		}
		(PageCanvas(canvas_model), CanvasMessage(canvas_message)) => {
			{ ..model, page: PageCanvas(Canvas.update(canvas_model, canvas_message)) }
		}
		_ => model
	}
	next_model
}

view : App.Model -> Program.View(App.Msg)
view = |model| {
	page_view = match model.page {
		PageLayout(page) => Layout.view(App.theme, page) |> map(|message| LayoutMessage(message))
		PageText(page) => Text.view(App.theme, page) |> map(|message| TextMessage(message))
		PageFloating(page) => Floating.view(App.theme, page) |> map(|message| FloatingMessage(message))
		PageImage(page) => Image.view(App.theme, page) |> map(|message| ImageMessage(message))
		PageCanvas(page) => Canvas.view(App.theme, page) |> map(|message| CanvasMessage(message))
	}
	box(
		{
			style: |_| style
				.direction(Row)
				.background(App.theme.palette.surface.base.fill)
				.font_size(App.theme.font_size)
				.font_color(App.theme.palette.surface.base.content),
		},
		[Nav.nav(App.theme, model.mascot, App.current_page(model)), page_view],
	)
}

program = Program.new(configure, init!, update!, view)
