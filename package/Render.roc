## Render command types and dispatch for Roc-Clay layout commands.
import Assets
import Color
import Element

Vector2 : { x : F32, y : F32 }

Rect : { x : F32, y : F32, width : F32, height : F32 }

TextRaw : {
	pos : Vector2,
	text : Str,
	size : F32,
	spacing : F32,
	color : Color,
	font : U64,
}

RectangleRaw : {
	x : F32,
	y : F32,
	width : F32,
	height : F32,
	color : Color,
}

RoundedRectangleRaw : {
	x : F32,
	y : F32,
	width : F32,
	height : F32,
	radius : F32,
	segments : I32,
	color : Color,
}

DrawTextureRaw : {
	texture : U64,
	source : Rect,
	dest : Rect,
	origin : Vector2,
	rotation : F32,
	tint : Color,
}

Command : [
	Rectangle({ x : F32, y : F32, width : F32, height : F32, color : Color }),
	RoundedRectangle({ x : F32, y : F32, width : F32, height : F32, radius : F32, color : Color }),
	Border(BorderRaw),
	Text(TextRawConfig),
	Image(ImageRaw),
]

BorderRaw : {
	x : F32,
	y : F32,
	width : F32,
	height : F32,
	color : Color,
	left : F32,
	right : F32,
	top : F32,
	bottom : F32,
}

TextRawConfig : {
	x : F32,
	y : F32,
	text : Str,
	font_size : F32,
	color : Color,
	font : Element.Font,
}

ImageRaw : {
	x : F32,
	y : F32,
	width : F32,
	height : F32,
	texture : Assets.Texture,
	tint : Color,
}

MeasureTextRaw : {
	text : Str,
	size : F32,
	spacing : F32,
	font : U64,
}

TextSize : { width : F32, height : F32 }

Render(draw) :: {}.{
	new : () -> Render(draw)
	new = ||{}

	render! : Render(draw), List(Command) => {}
		where [
			draw.begin_frame! : () => {},
			draw.clear! : {r: U8, g: U8, b: U8, a: U8} => {},
			draw.text_raw! : TextRaw => {},
			draw.rectangle_raw! : RectangleRaw => {},
			draw.rounded_rectangle_raw! : RoundedRectangleRaw => {},
			draw.draw_texture_raw! : DrawTextureRaw => {},
			draw.end_frame! : () => {},
		]
	render! = |_, commands| {
		Draw : draw

		Draw.begin_frame!()
		white = { r: 255, g: 255, b: 255, a: 255 }
		Draw.clear!(white) # background

		for command in commands {
			match command {
				Rectangle(r) =>
					Draw.rectangle_raw!({ x: r.x, y: r.y, width: r.width, height: r.height, color: r.color })
				RoundedRectangle(r) =>
					Draw.rounded_rectangle_raw!({ x: r.x, y: r.y, width: r.width, height: r.height, radius: r.radius, segments: 12, color: r.color })
				Border(b) => {
					if b.top > 0 {
						Draw.rectangle_raw!({ x: b.x, y: b.y, width: b.width, height: b.top, color: b.color })
					}
					if b.bottom > 0 {
						Draw.rectangle_raw!({ x: b.x, y: b.y + b.height - b.bottom, width: b.width, height: b.bottom, color: b.color })
					}
					if b.left > 0 {
						Draw.rectangle_raw!({ x: b.x, y: b.y, width: b.left, height: b.height, color: b.color })
					}
					if b.right > 0 {
						Draw.rectangle_raw!({ x: b.x + b.width - b.right, y: b.y, width: b.right, height: b.height, color: b.color })
					}
				}
				Text(t) =>
					Draw.text_raw!({ pos: { x: t.x, y: t.y }, text: t.text, size: t.font_size, spacing: 1, color: t.color, font: Box.unbox(t.font) })
				Image(img) => {
					info = Assets.info(img.texture)
					Draw.draw_texture_raw!(
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

		Draw.end_frame!()
	}
}
