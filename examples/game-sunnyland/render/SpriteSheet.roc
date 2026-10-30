## Atlas geometry is kept in one place so art and gameplay origins stay stable.
import rr.Draw
import rr.Math
import rr.Sprite
import tc.Color

SpriteSheet := [].{
	Frame : { source : Math.Rect, size : Math.Vec2, pivot : Math.Vec2 }
	centered : Math.Rect -> Frame
	centered = |source| { source, size: { x: source.width, y: source.height }, pivot: { x: source.width * 0.5, y: source.height } }
	draw! : Draw.Frame, Draw.Texture, Math.Rect, Math.Vec2, F32, Bool, Color => {}
	draw! = |frame, texture, source0, position, scale, flipped, tint| {
		source = if flipped { ..source0, width: 0 - source0.width } else source0
		Sprite.from_texture(texture)
			.source(source)
			.pos({ x: position.x - source0.width * scale * 0.5, y: position.y - source0.height * scale })
			.scale_xy({ x: scale, y: scale })
			.tint(tint.to_rrt())
			.draw!(frame)
	}
}
