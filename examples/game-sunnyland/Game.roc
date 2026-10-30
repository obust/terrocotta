import rr.Math
import world/Level
import player/Fox
import enemies/Enemy
import pickups/Pickup
import pickups/Feedback

Game := [].{
	State := [Title, Instructions, Playing, Paused, Dead, Won].{
		is_eq : _
	}
	Controls : { move_x : F32, down_down : Bool, jump_down : Bool, jump_pressed : Bool, confirm_pressed : Bool, pause_pressed : Bool, restart_pressed : Bool }
	Event := [GameStarted, Jumped, PickupCollected(Pickup.Kind, Math.Vec2), EnemyStomped(Enemy.Kind, Math.Vec2), PlayerHurt, PlayerRespawned, PlayerDied, AllPickupsCollected, WonEvent].{
		is_eq : _
	}
	World : { state : State, player : Fox.Model, enemies : List(Enemy.Model), pickups : List(Pickup.Model), effects : List(Feedback.Model), camera : Math.Vec2, elapsed : F32, collected : U64, total_pickups : U64, goal_flash : F32 }

	new : Level -> World
	new = |level| {
		state: Title,
		player: Fox.new(level.spawn),
		enemies: List.map(level.enemy_spawns, |s| Enemy.new(s.id, s.kind, s.pos)),
		pickups: List.map(level.pickup_spawns, |s| Pickup.new(s.id, s.kind, s.pos)),
		effects: [],
		camera: Level.camera_target(level, level.spawn),
		elapsed: 0,
		collected: 0,
		total_pickups: level.pickup_spawns.len(),
		goal_flash: 0,
	}

	update : Level, World, Controls, F32 -> (World, List(Event))
	update = |level, world, controls, raw_dt| {
		dt = Math.clamp(raw_dt, 0, 0.05)
		match world.state {
			Title => if controls.confirm_pressed ({ ..world, state: Instructions }, []) else (world, [])
			Instructions => if controls.confirm_pressed {
				({ ..world, state: Playing }, [GameStarted])
			} else (world, [])
			Paused => if controls.restart_pressed (Game.new(level), [GameStarted]) else if controls.pause_pressed ({ ..world, state: Playing }, []) else (world, [])
			Dead | Won => if controls.confirm_pressed (Game.new(level), [GameStarted]) else (world, [])
			Playing => if controls.pause_pressed ({ ..world, state: Paused }, []) else step(level, world, controls, dt)
		}
	}
}

overlap : Math.Rect, Math.Rect -> Bool
overlap = |a, b| Math.left(a) < Math.right(b) and Math.right(a) > Math.left(b) and Math.top(a) < Math.bottom(b) and Math.bottom(a) > Math.top(b)

step : Level, Game.World, Game.Controls, F32 -> (Game.World, List(Game.Event))
step = |level, world, controls, dt| {
	jumped = controls.jump_pressed and (world.player.grounded or world.player.coyote > 0)
	player = Fox.update(world.player, { move_x: controls.move_x, down_down: controls.down_down, jump_down: controls.jump_down, jump_pressed: controls.jump_pressed }, level.solids, level.one_way, dt)
	enemies = List.map(world.enemies, |enemy| Enemy.update(enemy, player.pos, level.bounds, level.solids, level.one_way, dt))
	pickups = List.map(world.pickups, |pickup| Pickup.update(pickup, dt))
	var $next_pickups = []
	var $next_effects = List.keep_if(List.map(world.effects, |effect| Feedback.update(effect, dt)), Feedback.active)
	var $events = if jumped [Game.Event.Jumped] else []
	var $collected = world.collected
	for pickup in pickups {
		if pickup.active and overlap(Fox.body(player), Pickup.body(pickup)) {
			$collected = $collected + 1
			$events = $events.append(Game.Event.PickupCollected(pickup.kind, pickup.pos))
			$next_effects = $next_effects.append(Feedback.spawn(pickup.pos))
			$next_pickups = $next_pickups.append({ ..pickup, active: Bool.False })
		} else {
			$next_pickups = $next_pickups.append(pickup)
		}
	}
	var $next_enemies = []
	var $next_player = player
	for enemy in enemies {
		if enemy.active and overlap(Fox.body($next_player), Enemy.body(enemy)) {
			is_stomp = $next_player.velocity.y > 0 and Math.bottom(Fox.body($next_player)) < enemy.pos.y
			if is_stomp {
				$next_player = { ..$next_player, velocity: { x: $next_player.velocity.x, y: -200 } }
				$events = $events.append(Game.Event.EnemyStomped(enemy.kind, enemy.pos))
				$next_enemies = $next_enemies.append({ ..enemy, active: Bool.False })
			} else if Fox.can_take_damage($next_player) {
				direction = if $next_player.pos.x < enemy.pos.x -1 else 1
				$next_player = Fox.damage($next_player, direction)
				$events = $events.append(Game.Event.PlayerHurt)
				$next_enemies = $next_enemies.append(enemy)
			} else {
				$next_enemies = $next_enemies.append(enemy)
			}
		} else {
			$next_enemies = $next_enemies.append(enemy)
		}
	}
	fallen = $next_player.pos.y > level.bounds.height + 24
	player2 = if fallen and $next_player.health > 1 Fox.respawn({ ..$next_player, health: $next_player.health - 1 }) else $next_player
	if fallen and $next_player.health > 1 {
		$events = $events.append(Game.Event.PlayerRespawned)
	} else if fallen {
		$events = $events.append(Game.Event.PlayerDied)
	}
	unlocked = $collected == world.total_pickups
	won = unlocked and overlap(Fox.body(player2), level.goal)
	dead = player2.health == 0
	state = if dead Dead else if won Won else Playing
	if $collected > world.collected and unlocked {
		$events = $events.append(Game.Event.AllPickupsCollected)
	}
	if won {
		$events = $events.append(Game.Event.WonEvent)
	}
	if dead and !fallen {
		$events = $events.append(Game.Event.PlayerDied)
	}
	({ ..world, state, player: player2, enemies: $next_enemies, pickups: $next_pickups, effects: $next_effects, collected: $collected, camera: Level.camera_target(level, player2.pos), elapsed: world.elapsed + dt, goal_flash: if unlocked 1 else Math.clamp(world.goal_flash - dt, 0, 1) }, $events)
}

neutral_controls : Game.Controls
neutral_controls = { move_x: 0, down_down: Bool.False, jump_down: Bool.False, jump_pressed: Bool.False, confirm_pressed: Bool.False, pause_pressed: Bool.False, restart_pressed: Bool.False }

expect Game.new(Level.room).total_pickups == Level.room.pickup_spawns.len()

expect {
	world = { ..Game.new(Level.room), state: Instructions }
	(next, events) = Game.update(Level.room, world, { ..neutral_controls, confirm_pressed: Bool.True }, 0)
	next.state == Playing and List.contains(events, GameStarted)
}

expect {
	initial = Game.new(Level.room)
	last = initial.pickups.get(initial.pickups.len() - 1).ok_or(Pickup.new(0, Gem, Math.zero))
	world = { ..initial, state: Playing, player: { ..initial.player, pos: last.pos }, enemies: [], pickups: [last], collected: initial.total_pickups - 1 }
	(next, events) = Game.update(Level.room, world, neutral_controls, 0)
	next.collected == initial.total_pickups and List.contains(events, AllPickupsCollected)
}
