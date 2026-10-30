import rr.Math
import SpriteFrames

SunnySprites := [].{
	Frame : { name : Str, source : Math.Rect, original_size : Math.Vec2, pivot : Math.Vec2 }
	Manifest : { frames : List(Frame) }

	atlas : Manifest
	atlas = { frames: SpriteFrames.atlas }

	atlas_props : Manifest
	atlas_props = { frames: SpriteFrames.atlas_props }

	frame : Manifest, Str -> Frame
	frame = |manifest, name| {
		match manifest.frames.find_first(|item| item.name == name) {
			Ok(found) => found
			Err(_) => crash "Missing Sunnyland sprite frame: ${name}"
		}
	}
}
