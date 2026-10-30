import rr.Draw
import rr.Math
import tc.Color

import ../GameAssets
import ../pickups/Pickup
import SpriteSheet
import SunnySprites

PickupView := [].{
	draw! : Draw.Frame, GameAssets, Pickup.Model => {}
	draw! = |frame, assets, pickup| {
		source = source_for(assets.sprites, Pickup.current_frame(pickup))
		SpriteSheet.draw!(frame, assets.atlas, source, { x: pickup.pos.x, y: pickup.pos.y + 6 }, 0.5, Bool.False, Color.white)
	}
}

source_for : SunnySprites.Manifest, Pickup.Frame -> Math.Rect
source_for = |manifest, pickup_frame| SunnySprites.frame(
	manifest,
	match pickup_frame {
		Pickup.Frame.Cherry1 => "cherry/cherry-1"
		Pickup.Frame.Cherry2 => "cherry/cherry-2"
		Pickup.Frame.Cherry3 => "cherry/cherry-3"
		Pickup.Frame.Cherry4 => "cherry/cherry-4"
		Pickup.Frame.Cherry5 => "cherry/cherry-5"
		Pickup.Frame.Cherry6 => "cherry/cherry-6"
		Pickup.Frame.Cherry7 => "cherry/cherry-7"
		Pickup.Frame.Gem1 => "gem/gem-1"
		Pickup.Frame.Gem2 => "gem/gem-2"
		Pickup.Frame.Gem3 => "gem/gem-3"
		Pickup.Frame.Gem4 => "gem/gem-4"
		Pickup.Frame.Gem5 => "gem/gem-5"
	},
).source
