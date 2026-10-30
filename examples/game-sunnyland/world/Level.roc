import rr.Math
import ../enemies/Enemy
import ../pickups/Pickup
import LevelData

Level := {
	spawn : Math.Vec2,
	bounds : Math.Rect,
	tile_size : F32,
	tileset_columns : U64,
	solids : List(Math.Rect),
	one_way : List(Math.Rect),
	goal : Math.Rect,
	pickup_spawns : List({ id : U64, kind : Pickup.Kind, pos : Math.Vec2 }),
	enemy_spawns : List({ id : U64, kind : Enemy.Kind, pos : Math.Vec2 }),
}.{

	view_width : F32
	view_width = 288

	view_height : F32
	view_height = 192

	room : Level
	room = {
		spawn: { x: 54 * LevelData.tile_size, y: 9 * LevelData.tile_size },
		bounds: Math.rect(0, 0, U64.to_f32(LevelData.width) * LevelData.tile_size, U64.to_f32(LevelData.height) * LevelData.tile_size),
		tile_size: LevelData.tile_size,
		tileset_columns: 25,
		solids: collision_rects(LevelData.solid_runs),
		one_way: collision_rects(LevelData.one_way_runs),
		goal: Math.rect(48 * LevelData.tile_size, 8 * LevelData.tile_size, LevelData.tile_size, LevelData.tile_size * 2),
		pickup_spawns: [
			{ id: 1, kind: Cherry, pos: { x: 30 * LevelData.tile_size, y: 5 * LevelData.tile_size } },
			{ id: 2, kind: Cherry, pos: { x: 31 * LevelData.tile_size, y: 5 * LevelData.tile_size } },
			{ id: 3, kind: Cherry, pos: { x: 32 * LevelData.tile_size, y: 5 * LevelData.tile_size } },
			{ id: 4, kind: Cherry, pos: { x: 23 * LevelData.tile_size, y: 17 * LevelData.tile_size } },
			{ id: 5, kind: Cherry, pos: { x: 24 * LevelData.tile_size, y: 17 * LevelData.tile_size } },
			{ id: 6, kind: Cherry, pos: { x: 25 * LevelData.tile_size, y: 17 * LevelData.tile_size } },
			{ id: 7, kind: Gem, pos: { x: 3 * LevelData.tile_size, y: 6 * LevelData.tile_size } },
			{ id: 8, kind: Gem, pos: { x: 4 * LevelData.tile_size, y: 6 * LevelData.tile_size } },
			{ id: 9, kind: Gem, pos: { x: 5 * LevelData.tile_size, y: 6 * LevelData.tile_size } },
			{ id: 10, kind: Gem, pos: { x: 44 * LevelData.tile_size, y: 12 * LevelData.tile_size } },
			{ id: 11, kind: Gem, pos: { x: 42 * LevelData.tile_size, y: 13 * LevelData.tile_size } },
			{ id: 12, kind: Gem, pos: { x: 42 * LevelData.tile_size, y: 16 * LevelData.tile_size } },
		],
		enemy_spawns: [
			{ id: 1, kind: Frog, pos: { x: 15 * LevelData.tile_size, y: 9 * LevelData.tile_size } },
			{ id: 2, kind: Frog, pos: { x: 30 * LevelData.tile_size, y: 20 * LevelData.tile_size } },
			{ id: 3, kind: Eagle, pos: { x: 33 * LevelData.tile_size, y: 6 * LevelData.tile_size } },
			{ id: 4, kind: Eagle, pos: { x: 6 * LevelData.tile_size, y: 7 * LevelData.tile_size } },
			{ id: 5, kind: Opossum, pos: { x: 42 * LevelData.tile_size, y: 9 * LevelData.tile_size } },
			{ id: 6, kind: Opossum, pos: { x: 23 * LevelData.tile_size, y: 20 * LevelData.tile_size } },
		],
	}

	camera_target : Level, Math.Vec2 -> Math.Vec2
	camera_target = |level, wanted| {
		{ x: Math.clamp(wanted.x, view_width * 0.5, level.bounds.width - view_width * 0.5), y: Math.clamp(wanted.y, view_height * 0.5, level.bounds.height - view_height * 0.5) }
	}

}

collision_rects : List({ x : F32, y : F32, width : F32, height : F32 }) -> List(Math.Rect)
collision_rects = |runs| runs.map(|item| Math.rect(item.x, item.y, item.width, item.height))
