## Render command types and dispatch for Roc-Clay layout commands.
import Assets
import Color
import Element

RenderVector2 : { x : F32, y : F32 }

RenderRect : { x : F32, y : F32, width : F32, height : F32 }

RenderTextRaw : {
	pos : RenderVector2,
	text : Str,
	size : F32,
	spacing : F32,
	color : Color,
	font : U64,
}

RenderRectangleRaw : {
	x : F32,
	y : F32,
	width : F32,
	height : F32,
	color : Color,
}

RenderRoundedRectangleRaw : {
	x : F32,
	y : F32,
	width : F32,
	height : F32,
	radius : F32,
	segments : I32,
	color : Color,
}

RenderRoundedRectangleLinesRaw : {
	x : F32,
	y : F32,
	width : F32,
	height : F32,
	radius : F32,
	segments : I32,
	color : Color,
	thickness : F32,
}

RenderDrawTextureRaw : {
	texture : U64,
	source : RenderRect,
	dest : RenderRect,
	origin : RenderVector2,
	rotation : F32,
	tint : Color,
}

RenderCommandRaw := [
	Rectangle({ x : F32, y : F32, width : F32, height : F32, color : Color }),
	RoundedRectangle({ x : F32, y : F32, width : F32, height : F32, radius : F32, color : Color }),
	Border(RenderBorderRaw),
	Text(RenderTextRawConfig),
	Image(RenderImageRaw),
]

RenderBorderRaw := {
	x : F32,
	y : F32,
	width : F32,
	height : F32,
	radius : F32,
	color : Color,
	left : F32,
	right : F32,
	top : F32,
	bottom : F32,
}

RenderTextRawConfig := {
	x : F32,
	y : F32,
	text : Str,
	font_size : F32,
	color : Color,
	font : Element.Font,
}

RenderImageRaw := {
	x : F32,
	y : F32,
	width : F32,
	height : F32,
	texture : Assets.Texture,
	tint : Color,
}

RenderMeasureTextRaw : {
	text : Str,
	size : F32,
	spacing : F32,
	font : U64,
}

RenderTextSize : { width : F32, height : F32 }

RenderRenderer := {
	begin_frame : {} => {},
	clear : Color => {},
	measure_text_raw : RenderMeasureTextRaw => RenderTextSize,
	text_raw : RenderTextRaw => {},
	rectangle_raw : RenderRectangleRaw => {},
	rounded_rectangle_raw : RenderRoundedRectangleRaw => {},
	rounded_rectangle_lines_raw : RenderRoundedRectangleLinesRaw => {},
	draw_texture_raw : RenderDrawTextureRaw => {},
	end_frame : {} => {},
	default_spacing : F32,
}

Render := [].{
	Command : RenderCommandRaw
	BorderConfig : RenderBorderRaw
	TextConfig : RenderTextRawConfig
	ImageConfig : RenderImageRaw
	Vector2 : RenderVector2
	Rect : RenderRect
	TextRaw : RenderTextRaw
	RectangleRaw : RenderRectangleRaw
	RoundedRectangleRaw : RenderRoundedRectangleRaw
	RoundedRectangleLinesRaw : RenderRoundedRectangleLinesRaw
	DrawTextureRaw : RenderDrawTextureRaw
	MeasureTextRaw : RenderMeasureTextRaw
	TextSize : RenderTextSize
	Renderer : RenderRenderer

	render! : Renderer, List(Command) => {}
	render! = |renderer, commands| {
		(renderer.begin_frame)({})
		(renderer.clear)(Color.from_hex_rgb(0xffffff)) # background

		for command in commands {
			match command {
				Rectangle(r) =>
					(renderer.rectangle_raw)({ x: r.x, y: r.y, width: r.width, height: r.height, color: r.color })
				RoundedRectangle(r) =>
					(renderer.rounded_rectangle_raw)({ x: r.x, y: r.y, width: r.width, height: r.height, radius: r.radius, segments: 12, color: r.color })
				Border(b) => {
					uniform = b.left == b.right and b.left == b.top and b.left == b.bottom
					if b.radius > 0 and uniform and b.top > 0 {
						(renderer.rounded_rectangle_lines_raw)({ x: b.x, y: b.y, width: b.width, height: b.height, radius: b.radius, segments: 12, color: b.color, thickness: b.top })
					} else {
						# Clay's raylib renderer uses DrawRing for rounded corners with non-uniform
						# border widths. roc-ray does not expose DrawRing, so unsupported rounded
						# non-uniform borders fall back to square-corner side rectangles for now.
						if b.top > 0 {
							(renderer.rectangle_raw)({ x: b.x, y: b.y, width: b.width, height: b.top, color: b.color })
						}
						if b.bottom > 0 {
							(renderer.rectangle_raw)({ x: b.x, y: b.y + b.height - b.bottom, width: b.width, height: b.bottom, color: b.color })
						}
						if b.left > 0 {
							(renderer.rectangle_raw)({ x: b.x, y: b.y, width: b.left, height: b.height, color: b.color })
						}
						if b.right > 0 {
							(renderer.rectangle_raw)({ x: b.x + b.width - b.right, y: b.y, width: b.right, height: b.height, color: b.color })
						}
					}
				}
				Text(t) =>
					(renderer.text_raw)({ pos: { x: t.x, y: t.y }, text: t.text, size: t.font_size, spacing: renderer.default_spacing, color: t.color, font: Box.unbox(t.font) })
				Image(img) => {
					info = Assets.info(img.texture)
					(renderer.draw_texture_raw)(
						{
							texture: info.handle,
							source: { x: 0, y: 0, width: info.width, height: info.height },
							dest: { x: img.x, y: img.y, width: img.width, height: img.height },
							origin: { x: 0, y: 0 },
							rotation: 0,
							tint: img.tint,
						},
					)
				}
			}
		}

		(renderer.end_frame)({})
	}
}
