## Swept axis-separated collision with explicit one-way platform handling.
import rr.Math

Collision := [].{
	Result : { body : Math.Rect, hit_x : Bool, landed : Bool, hit_ceiling : Bool }

	move : Math.Rect, Math.Vec2, List(Math.Rect), List(Math.Rect) -> Result
	move = |body, delta, solids, one_way| {
		x = move_x(body, delta.x, solids)
		start = { ..body, x: x.position }
		y = move_y(start, delta.y, solids, one_way)
		{ body: { ..start, y: y.position }, hit_x: x.hit, landed: y.positive_hit, hit_ceiling: y.negative_hit }
	}
}

overlap : F32, F32, F32, F32 -> Bool
overlap = |a0, a1, b0, b1| a0 < b1 and a1 > b0

Axis : { position : F32, hit : Bool, positive_hit : Bool, negative_hit : Bool }

move_x : Math.Rect, F32, List(Math.Rect) -> Axis
move_x = |body, delta, solids| {
	var $position = body.x + delta
	var $hit = Bool.False
	for solid in solids {
		if overlap(body.y, Math.bottom(body), solid.y, Math.bottom(solid)) {
			if delta > 0 and Math.right(body) <= solid.x and $position + body.width >= solid.x {
				$position = F32.min($position, solid.x - body.width)
				$hit = Bool.True
			} else if delta < 0 and body.x >= Math.right(solid) and $position <= Math.right(solid) {
				$position = F32.max($position, Math.right(solid))
				$hit = Bool.True
			}
		}
	}
	{ position: $position, hit: $hit, positive_hit: delta > 0 and $hit, negative_hit: delta < 0 and $hit }
}

move_y : Math.Rect, F32, List(Math.Rect), List(Math.Rect) -> Axis
move_y = |body, delta, solids, one_way| {
	var $position = body.y + delta
	var $hit = Bool.False
	for solid in solids {
		if overlap(body.x, Math.right(body), solid.x, Math.right(solid)) {
			if delta > 0 and Math.bottom(body) <= solid.y and $position + body.height >= solid.y {
				$position = F32.min($position, solid.y - body.height)
				$hit = Bool.True
			} else if delta < 0 and body.y >= Math.bottom(solid) and $position <= Math.bottom(solid) {
				$position = F32.max($position, Math.bottom(solid))
				$hit = Bool.True
			}
		}
	}
	for one_way_rect in one_way {
		if overlap(body.x, Math.right(body), one_way_rect.x, Math.right(one_way_rect)) and delta > 0 and Math.bottom(body) <= one_way_rect.y and $position + body.height >= one_way_rect.y {
			$position = F32.min($position, one_way_rect.y - body.height)
			$hit = Bool.True
		}
	}
	{ position: $position, hit: $hit, positive_hit: delta > 0 and $hit, negative_hit: delta < 0 and $hit }
}

expect {
	r = Collision.move(Math.rect(0, 0, 20, 20), { x: 80, y: 0 }, [Math.rect(50, 0, 4, 20)], [])
	r.body.x == 30 and r.hit_x
}
