import rr.Math
import Frog
import Eagle
import Opossum

Enemy := [].{
	Kind := [Frog, Eagle, Opossum].{
		is_eq : _
	}
	Model : { id : U64, kind : Kind, pos : Math.Vec2, velocity : Math.Vec2, facing : F32, active : Bool, phase : F32 }

	new : U64, Kind, Math.Vec2 -> Model
	new = |id, kind, pos| { id, kind, pos, velocity: Math.zero, facing: 1, active: Bool.True, phase: 0 }

	body : Model -> Math.Rect
	body = |enemy| Math.rect(enemy.pos.x - 8, enemy.pos.y - 8, 16, 16)

	update : Model, Math.Vec2, Math.Rect, List(Math.Rect), List(Math.Rect), F32 -> Model
	update = |enemy, player, bounds, solids, one_way, dt| {
		if (!enemy.active) enemy else {
			match enemy.kind {
				Eagle => Eagle.update(enemy, player, dt)
				Frog => Frog.update(enemy, solids, one_way, dt)
				Opossum => Opossum.update(enemy, bounds, solids, one_way, dt)
			}
		}
	}
}
