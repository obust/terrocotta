import rr.Draw
import tc.Color

import ../GameAssets
import ../world/Level
import ../world/LevelData
import SpriteSheet
import SunnySprites

LevelView := [].{
	draw! : Draw.Frame, GameAssets, Level => {}
	draw! = |frame, assets, level| {
		draw_background!(frame, assets, level)
		draw_tilemap!(frame, assets.tileset, level)
		draw_goal_door!(frame, assets, level)
	}
}

sky_color = 0x8ed6ed.Color

middle_top : F32
middle_top = 96

draw_background! : Draw.Frame, GameAssets, Level => {}
draw_background! = |frame, assets, level| {
	frame.rectangle!({ x: level.bounds.x, y: level.bounds.y, width: level.bounds.width, height: level.bounds.height, style: Draw.filled(sky_color.to_rrt()) })
	frame.texture!({ texture: assets.back, source: texture_source(assets.back), dest: level.bounds, origin: { x: 0, y: 0 }, rotation: 0, tint: Color.white.to_rrt() })
	frame.texture!({ texture: assets.middle, source: texture_source(assets.middle), dest: { x: level.bounds.x, y: level.bounds.y + middle_top, width: level.bounds.width, height: level.bounds.height - middle_top }, origin: { x: 0, y: 0 }, rotation: 0, tint: Color.white.to_rrt() })
}

texture_source = |texture| { x: 0, y: 0, width: texture.width.to_f32(), height: texture.height.to_f32() }

draw_goal_door! : Draw.Frame, GameAssets, Level => {}
draw_goal_door! = |frame, assets, level| {
	door_anchor = { x: level.goal.x + level.goal.width * 0.5, y: level.goal.y + level.goal.height }
	SpriteSheet.draw!(frame, assets.atlas_props, SunnySprites.frame(assets.prop_sprites, "door").source, door_anchor, 0.75, Bool.False, Color.white)
}

draw_tilemap! : Draw.Frame, Draw.Texture, Level => {}
draw_tilemap! = |frame, texture, level| {
	var $y = 0
	for row in LevelData.tile_rows {
		var $x = 0
		for tile in row {
			if tile.gid > 0 {
				index = tile.gid - 1
				column = index % level.tileset_columns
				row_index = index / level.tileset_columns
				source = {
					x: U64.to_f32(column) * level.tile_size,
					y: U64.to_f32(row_index) * level.tile_size,
					width: if (tile.flags == 2147483648) 0 - level.tile_size else level.tile_size,
					height: level.tile_size,
				}
				frame.texture!({ texture, source, dest: { x: level.bounds.x + U64.to_f32($x) * level.tile_size, y: level.bounds.y + U64.to_f32($y) * level.tile_size, width: level.tile_size, height: level.tile_size }, origin: { x: 0, y: 0 }, rotation: 0, tint: Color.white.to_rrt() })
			}
			$x = $x + 1
		}
		$y = $y + 1
	}
}
