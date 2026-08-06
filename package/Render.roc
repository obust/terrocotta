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
	ScissorStart({ x : F32, y : F32, width : F32, height : F32 }),
	ScissorEnd,
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
	spacing : F32,
	color : Color,
	font : Element.Font,
}

RenderImageRaw := {
	x : F32,
	y : F32,
	width : F32,
	height : F32,
	texture : Assets.Texture,
}

RenderMeasureTextRaw : {
	text : Str,
	size : F32,
	spacing : F32,
	font : U64,
}

RenderTextSize : { width : F32, height : F32 }

Render(draw) := {}.{
	Command : RenderCommandRaw
	BorderConfig : RenderBorderRaw
	TextConfig : RenderTextRawConfig
	Vector2 : RenderVector2
	Rect : RenderRect
	TextRaw : RenderTextRaw
	RectangleRaw : RenderRectangleRaw
	RoundedRectangleRaw : RenderRoundedRectangleRaw
	RoundedRectangleLinesRaw : RenderRoundedRectangleLinesRaw
	DrawTextureRaw : RenderDrawTextureRaw
	MeasureTextRaw : RenderMeasureTextRaw
	TextSize : RenderTextSize

	new : () -> Render(draw)
	new = || Render.{}

	render! : Render(draw), List(Command) => {}
		where [
			draw.begin_frame! : () => {},
			draw.clear! : ({ r : U8, g : U8, b : U8, a : U8 }) => {},
			draw.text_raw! : ({ pos : Vector2, text : Str, size : F32, spacing : F32, color : { r : U8, g : U8, b : U8, a : U8 }, font : U64 }) => {},
			draw.rectangle_raw! : ({ x : F32, y : F32, width : F32, height : F32, color : { r : U8, g : U8, b : U8, a : U8 } }) => {},
			draw.rounded_rectangle_raw! : ({ x : F32, y : F32, width : F32, height : F32, radius : F32, segments : I32, color : { r : U8, g : U8, b : U8, a : U8 } }) => {},
			draw.rounded_rectangle_lines_raw! : ({ x : F32, y : F32, width : F32, height : F32, radius : F32, segments : I32, color : { r : U8, g : U8, b : U8, a : U8 }, thickness : F32 }) => {},
			draw.draw_texture_raw! : ({ texture : U64, source : Rect, dest : Rect, origin : Vector2, rotation : F32, tint : { r : U8, g : U8, b : U8, a : U8 } }) => {},
			draw.begin_scissor_raw! : ({ x : F32, y : F32, width : F32, height : F32 }) => {},
			draw.end_scissor_raw! : () => {},
			draw.fps! : {
				pos : { x : F32, y : F32 },
				size : F32,
				color : { r : U8, g : U8, b : U8, a : U8 },
			} => {},
			draw.end_frame! : () => {},
		]
	render! = |self, commands| {
		Draw : draw
		_ = self
		Draw.begin_frame!()
		Draw.clear!(to_draw_color(0xffffff.Color)) # background
		var $scissors = []

		for command in commands {
			match command {
				Rectangle(r) =>
					Draw.rectangle_raw!({ x: r.x, y: r.y, width: r.width, height: r.height, color: to_draw_color(r.color) })
				RoundedRectangle(r) =>
					Draw.rounded_rectangle_raw!({ x: r.x, y: r.y, width: r.width, height: r.height, radius: r.radius, segments: 12, color: to_draw_color(r.color) })
				Border(b) => {
					uniform = b.left == b.right and b.left == b.top and b.left == b.bottom
					if b.radius > 0 and uniform and b.top > 0 {
						Draw.rounded_rectangle_lines_raw!({ x: b.x, y: b.y, width: b.width, height: b.height, radius: b.radius, segments: 12, color: to_draw_color(b.color), thickness: b.top })
					} else {
						# Clay's raylib renderer uses DrawRing for rounded corners with non-uniform
						# border widths. roc-ray does not expose DrawRing, so unsupported rounded
						# non-uniform borders fall back to square-corner side rectangles for now.
						if b.top > 0 {
							Draw.rectangle_raw!({ x: b.x, y: b.y, width: b.width, height: b.top, color: to_draw_color(b.color) })
						}
						if b.bottom > 0 {
							Draw.rectangle_raw!({ x: b.x, y: b.y + b.height - b.bottom, width: b.width, height: b.bottom, color: to_draw_color(b.color) })
						}
						if b.left > 0 {
							Draw.rectangle_raw!({ x: b.x, y: b.y, width: b.left, height: b.height, color: to_draw_color(b.color) })
						}
						if b.right > 0 {
							Draw.rectangle_raw!({ x: b.x + b.width - b.right, y: b.y, width: b.right, height: b.height, color: to_draw_color(b.color) })
						}
					}
				}
				Text(t) =>
					Draw.text_raw!({ pos: { x: t.x, y: t.y }, text: t.text, size: t.font_size, spacing: t.spacing, color: to_draw_color(t.color), font: Box.unbox(t.font) })
				Image(img) => {
					info = Assets.info(img.texture)
					Draw.draw_texture_raw!({
						texture: info.handle,
						source: { x: 0, y: 0, width: info.width, height: info.height },
						dest: { x: img.x, y: img.y, width: img.width, height: img.height },
						origin: { x: 0, y: 0 },
						rotation: 0,
						tint: to_draw_color(Color.white),
					})
				}
				ScissorStart(s) => {
					next = if $scissors.len() > 0 {
						intersection($scissors.get($scissors.len() - 1).ok_or(s), s)
					} else {
						s
					}
					if $scissors.len() > 0 {
						Draw.end_scissor_raw!()
					}
					Draw.begin_scissor_raw!(next)
					$scissors = $scissors.append(next)
				}
				ScissorEnd => {
					if $scissors.len() > 0 {
						Draw.end_scissor_raw!()
						$scissors = $scissors.sublist({ start: 0, len: $scissors.len() - 1 })
						if $scissors.len() > 0 {
							Draw.begin_scissor_raw!($scissors.get($scissors.len() - 1).ok_or({ x: 0, y: 0, width: 0, height: 0 }))
						}
					}
				}
			}
		}

		Draw.fps!({ pos: { x: 0, y: 0 }, size: 16, color: to_draw_color(Color.gray) })

		Draw.end_frame!()
	}
}

## Intersect a nested scissor rectangle with its active parent.
intersection : { x : F32, y : F32, width : F32, height : F32 }, { x : F32, y : F32, width : F32, height : F32 } -> { x : F32, y : F32, width : F32, height : F32 }
intersection = |a, b| {
	x = F32.max(a.x, b.x)
	y = F32.max(a.y, b.y)
	right = F32.min(a.x + a.width, b.x + b.width)
	bottom = F32.min(a.y + a.height, b.y + b.height)
	width = F32.max(0, right - x)
	height = F32.max(0, bottom - y)
	{ x, y, width, height }
}

# Color nominal to structural adapter
to_draw_color : Color -> { r : U8, g : U8, b : U8, a : U8 }
to_draw_color = |color| { r: color.r, g: color.g, b: color.b, a: color.a }
