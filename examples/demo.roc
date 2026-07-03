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

Render : tc.Render(pf.Draw)

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
