import rr.Draw
import rr.Math
import tc.Color

import ../GameAssets
import ../enemies/Eagle
import ../enemies/Enemy
import ../enemies/Frog
import ../enemies/Opossum
import SpriteSheet
import SunnySprites

EnemyView := [].{
	draw! : Draw.Frame, GameAssets, Enemy.Model => {}
	draw! = |frame, assets, enemy| match enemy.kind {
		Frog => SpriteSheet.draw!(frame, assets.atlas, frog_source(assets.sprites, Frog.current_frame(enemy)), { x: enemy.pos.x, y: enemy.pos.y + 11 }, 0.5, enemy.facing < 0, Color.white)
		Eagle => SpriteSheet.draw!(frame, assets.atlas, eagle_source(assets.sprites, Eagle.current_frame(enemy)), { x: enemy.pos.x, y: enemy.pos.y + 8 }, 0.5, enemy.facing < 0, Color.white)
		Opossum => SpriteSheet.draw!(frame, assets.atlas, opossum_source(assets.sprites, Opossum.current_frame(enemy)), { x: enemy.pos.x, y: enemy.pos.y + 8 }, 0.5, enemy.facing > 0, Color.white)
	}
}

frog_source : SunnySprites.Manifest, Frog.Frame -> Math.Rect
frog_source = |manifest, frog_frame| SunnySprites.frame(
	manifest,
	match frog_frame {
		Frog.Frame.Idle1 => "frog/idle/frog-idle-1"
		Frog.Frame.Idle2 => "frog/idle/frog-idle-2"
		Frog.Frame.Idle3 => "frog/idle/frog-idle-3"
		Frog.Frame.Idle4 => "frog/idle/frog-idle-4"
		Frog.Frame.Rise => "frog/jump/frog-jump-1"
		Frog.Frame.Fall => "frog/jump/frog-jump-2"
	},
).source

eagle_source : SunnySprites.Manifest, Eagle.Frame -> Math.Rect
eagle_source = |manifest, eagle_frame| SunnySprites.frame(
	manifest,
	match eagle_frame {
		Eagle.Frame.Attack1 => "eagle/eagle-attack-1"
		Eagle.Frame.Attack2 => "eagle/eagle-attack-2"
		Eagle.Frame.Attack3 => "eagle/eagle-attack-3"
		Eagle.Frame.Attack4 => "eagle/eagle-attack-4"
	},
).source

opossum_source : SunnySprites.Manifest, Opossum.Frame -> Math.Rect
opossum_source = |manifest, opossum_frame| SunnySprites.frame(
	manifest,
	match opossum_frame {
		Opossum.Frame.Run1 => "opossum/opossum-1"
		Opossum.Frame.Run2 => "opossum/opossum-2"
		Opossum.Frame.Run3 => "opossum/opossum-3"
		Opossum.Frame.Run4 => "opossum/opossum-4"
		Opossum.Frame.Run5 => "opossum/opossum-5"
		Opossum.Frame.Run6 => "opossum/opossum-6"
	},
).source
