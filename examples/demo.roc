## Example demonstrating the Element.box / Element.text UI API
app [Model, program] {
    rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.7/8gdZaHEpySPZUzMBCT6RkEF9CBpcbi5F3E7QmNu4NTCU.tar.zst",
    tc: "../package/main.roc"
}

import rr.Host
import rr.App
import rr.Draw
import tc.Color
import tc.Element exposing [box, text, View, style, default_font]
import tc.Program
import tc.Render

RayDraw := [].{
    begin_frame! : {}
    begin_frame! = Draw.begin_frame!

    clear! : Color => {}
    clear! = |color| Draw.clear!({ r: color.r, g: color.g, b: color.b, a: color.a })

    measure_text_raw! : Render.MeasureTextRaw => Render.TextSize
    measure_text_raw! = |text| Draw.measure_text_raw!({ text: text.text, size: text.size, spacing: text.spacing, font: text.font })

    rectangle_raw! : Render.RectangleRaw => {}
    rectangle_raw! = |rect| Draw.rectangle_raw!({ x: rect.x, y: rect.y, width: rect.width, height: rect.height, color: { r: rect.color.r, g: rect.color.g, b: rect.color.b, a: rect.color.a } })

    rounded_rectangle_raw! : Render.RoundedRectangleRaw => {}
    rounded_rectangle_raw! = |rect| Draw.rounded_rectangle_raw!({ x: rect.x, y: rect.y, width: rect.width, height: rect.height, radius: rect.radius, segments: rect.segments, color: { r: rect.color.r, g: rect.color.g, b: rect.color.b, a: rect.color.a } })

    text_raw! : Render.TextRaw => {}
    text_raw! = |text| Draw.text_raw!({ pos: text.pos, text: text.text, size: text.size, spacing: text.spacing, color: { r: text.color.r, g: text.color.g, b: text.color.b, a: text.color.a }, font: text.font })

    draw_texture_raw! : Render.DrawTextureRaw => {}
    draw_texture_raw! = |texture| Draw.draw_texture_raw!({ texture: texture.texture, source: texture.source, dest: texture.dest, origin: texture.origin, rotation: texture.rotation, tint: { r: texture.tint.r, g: texture.tint.g, b: texture.tint.b, a: texture.tint.a } })

    end_frame! : {}
    end_frame! = Draw.end_frame!

    default_spacing! : {} -> F32
    default_spacing! = |_| Draw.default_spacing
}

Model : Program.State(RayDraw, AppModel)
AppModel : {}

view : AppModel -> View
view = |_| {
    box(
        style
            .width(Fit({ min: 0, max: 10000 }))
            .height(Fit({ min: 0, max: 10000 }))
            .pad((0, 0, 0, 0))
            .gap(0)
            .child_align({ x: Center, y: Center })
            .direction(Col)
            .background(Color.from_hex_rgb(0xf0f0f0))
            .radius(0),
        [
            box(
                style
                    .width(Fit({ min: 0, max: 10000 }))
                    .height(Fixed(60))
                    .pad((12, 12, 12, 12))
                    .gap(0)
                    .child_align({ x: Center, y: Center })
                    .direction(Row)
                    .background(Color.dark_gray)
                    .radius(0)
                    .font_family(default_font)
                    .font_size(28)
                    .font_color(Color.white),
                [
                    text("FlatTree Push/Pop Demo"),
                ],
            ),
            box(
                style
                    .width(Fit({ min: 0, max: 10000 }))
                    .height(Fit({ min: 0, max: 10000 }))
                    .pad((20, 20, 20, 20))
                    .gap(20)
                    .child_align({ x: Center, y: Center })
                    .direction(Row)
                    .background(Color.transparent)
                    .radius(0),
                [
                    box(
                        style
                            .width(Fixed(160))
                            .height(Fixed(70))
                            .pad((12, 12, 12, 12))
                            .gap(0)
                            .child_align({ x: Center, y: Center })
                            .direction(Row)
                            .background(Color.blue)
                            .radius(10)
                            .font_family(default_font)
                            .font_size(22)
                            .font_color(Color.white),
                        [
                            text("Box 1"),
                        ],
                    ),
                    box(
                        style
                            .width(Fixed(160))
                            .height(Fixed(70))
                            .pad((12, 12, 12, 12))
                            .gap(0)
                            .child_align({ x: Center, y: Center })
                            .direction(Row)
                            .background(Color.green)
                            .radius(10)
                            .font_family(default_font)
                            .font_size(22)
                            .font_color(Color.white),
                        [
                            text("Box 2"),
                        ],
                    ),
                    box(
                        style
                            .width(Fixed(160))
                            .height(Fixed(70))
                            .pad((12, 12, 12, 12))
                            .gap(0)
                            .child_align({ x: Center, y: Center })
                            .direction(Row)
                            .background(Color.from_hex_rgb(0xff8800))
                            .radius(10)
                            .font_family(default_font)
                            .font_size(22)
                            .font_color(Color.white),
                        [
                            text("Box 3"),
                        ],
                    ),
                ],
            ),
        ],
    )
}

update : AppModel, {} -> AppModel
update = |model, _| model

subscriptions : AppModel, Host -> List({})
subscriptions = |_model, _host| []

program : {
    init! : { config : Program.Config, run! : Host => Try(Model, [Exit(I64)]) },
    render! : Model, Host => Try(Model, [Exit(I64), ..]),
}
program = Program.new!({
    config: { ..App.default, title: "FlatTree Push/Pop Demo", width: 800, height: 600 },
    init: || {},
    view, update, subscriptions,
})
