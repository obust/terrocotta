import rr.Draw
import rr.Math
import tc.Color

import ../GameAssets
import ../player/Fox
import SpriteSheet
import SunnySprites

FoxView := [].{
	draw! : Draw.Frame, GameAssets, Fox.Model, F32 => {}
	draw! = |frame, assets, fox, elapsed| {
		flash = fox.invulnerable > 0 and F32.sin(elapsed * 30) > 0
		fox_frame = Fox.current_frame(fox)
		source = source_for(assets.sprites, fox_frame)
		tint = if flash Color.white.with_alpha(90) else Color.white
		SpriteSheet.draw!(frame, assets.atlas, source, { x: fox.pos.x, y: fox.pos.y + 8 }, 0.75, fox.facing < 0, tint)
	}
}

source_for : SunnySprites.Manifest, Fox.Frame -> Math.Rect
source_for = |manifest, fox_frame| SunnySprites.frame(
	manifest,
	match fox_frame {
		Fox.Frame.Idle1 => "player/idle/player-idle-1"
		Fox.Frame.Idle2 => "player/idle/player-idle-2"
		Fox.Frame.Idle3 => "player/idle/player-idle-3"
		Fox.Frame.Idle4 => "player/idle/player-idle-4"
		Fox.Frame.Run1 => "player/run/player-run-1"
		Fox.Frame.Run2 => "player/run/player-run-2"
		Fox.Frame.Run3 => "player/run/player-run-3"
		Fox.Frame.Run4 => "player/run/player-run-4"
		Fox.Frame.Run5 => "player/run/player-run-5"
		Fox.Frame.Run6 => "player/run/player-run-6"
		Fox.Frame.Crouch1 => "player/crouch/player-crouch-1"
		Fox.Frame.Crouch2 => "player/crouch/player-crouch-2"
		Fox.Frame.Rise => "player/jump/player-jump-1"
		Fox.Frame.Fall => "player/jump/player-jump-2"
		Fox.Frame.Hurt1 => "player/hurt/player-hurt-1"
		Fox.Frame.Hurt2 => "player/hurt/player-hurt-2"
	},
).source
