import rr.Draw
import rr.Math
import tc.Color

import ../GameAssets
import ../pickups/Feedback
import SpriteSheet
import SunnySprites

FeedbackView := [].{
	draw! : Draw.Frame, GameAssets, Feedback.Model => {}
	draw! = |frame, assets, effect| {
		source = source_for(assets.sprites, Feedback.current_frame(effect))
		SpriteSheet.draw!(frame, assets.atlas, source, effect.pos, 0.5, Bool.False, Color.white)
	}
}

source_for : SunnySprites.Manifest, Feedback.Frame -> Math.Rect
source_for = |manifest, feedback_frame| SunnySprites.frame(
	manifest,
	match feedback_frame {
		Feedback.Frame.Feedback1 => "item-feedback/item-feedback-1"
		Feedback.Frame.Feedback2 => "item-feedback/item-feedback-2"
		Feedback.Frame.Feedback3 => "item-feedback/item-feedback-3"
		Feedback.Frame.Feedback4 => "item-feedback/item-feedback-4"
	},
).source
