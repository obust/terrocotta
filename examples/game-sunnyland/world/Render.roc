import rr.Camera
import rr.Draw
import tc.Color
import tc.Geom exposing [Bounds]

import ../GameAssets
import ../Game
import ../render/EnemyView
import ../render/FeedbackView
import ../render/FoxView
import ../render/LevelView
import ../render/PickupView
import Level

Render := [].{
	draw! : Draw.Frame, Bounds, GameAssets, Level, Game.World => Try({}, Draw.ScopeError)
	draw! = |frame, bounds, assets, level, world| {
		frame.rectangle!({ x: bounds.position.x, y: bounds.position.y, width: bounds.size.w, height: bounds.size.h, style: Draw.filled((0x7fc8e8.Color).to_rrt()) })
		fit = (bounds.size.w / Level.view_width).min(bounds.size.h / Level.view_height)
		camera = Camera.new({ target: world.camera, offset: { x: bounds.position.x + bounds.size.w * 0.5, y: bounds.position.y + bounds.size.h * 0.5 }, rotation: 0, zoom: fit })
		frame.with_camera!(
			camera,
			|world_frame| {
				draw_world!(world_frame, assets, level, world)
				Ok({})
			},
		)?
		Ok({})
	}
}

draw_world! : Draw.Frame, GameAssets, Level, Game.World => {}
draw_world! = |frame, assets, level, world| {
	LevelView.draw!(frame, assets, level)
	for pickup in world.pickups {
		if pickup.active {
			PickupView.draw!(frame, assets, pickup)
		}
	}
	for enemy in world.enemies {
		if enemy.active {
			EnemyView.draw!(frame, assets, enemy)
		}
	}
	FoxView.draw!(frame, assets, world.player, world.elapsed)
	for effect in world.effects {
		FeedbackView.draw!(frame, assets, effect)
	}
}
