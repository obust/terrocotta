## Public two-dimensional geometry shared by layout, rendering, and canvases.
Geom := [].{

	Pos := { x : F32, y : F32 }.{
		plus : Pos, Pos -> Pos
		plus = |a, b| { x: a.x + b.x, y: a.y + b.y }

		is_eq : Pos, Pos -> Bool
		is_eq = |a, b| a.x == b.x and a.y == b.y
	}

	Size := { w : F32, h : F32 }.{
		plus : Size, Size -> Size
		plus = |a, b| { w: a.w + b.w, h: a.h + b.h }

		minus : Size, Size -> Size
		minus = |a, b| { w: a.w - b.w, h: a.h - b.h }

		is_eq : Size, Size -> Bool
		is_eq = |a, b| a.w == b.w and a.h == b.h
	}

	Bounds := {
		position : Pos,
		size : Size,
	}.{
		contains : Bounds, Pos -> Bool
		contains = |bounds, point| {
			point.x >= bounds.position.x
				and point.x <= bounds.position.x + bounds.size.w
				and point.y >= bounds.position.y
				and point.y <= bounds.position.y + bounds.size.h
		}

		contains_bounds : Bounds, Bounds -> Bool
		contains_bounds = |outer, inner| {
			inner.position.x >= outer.position.x
				and inner.position.y >= outer.position.y
				and inner.position.x + inner.size.w <= outer.position.x + outer.size.w
				and inner.position.y + inner.size.h <= outer.position.y + outer.size.h
		}

		intersects : Bounds, Bounds -> Bool
		intersects = |a, b| {
			a.position.x < b.position.x + b.size.w
				and a.position.x + a.size.w > b.position.x
				and a.position.y < b.position.y + b.size.h
				and a.position.y + a.size.h > b.position.y
		}

		intersection : Bounds, Bounds -> Bounds
		intersection = |a, b| {
			x = F32.max(a.position.x, b.position.x)
			y = F32.max(a.position.y, b.position.y)
			right = F32.min(a.position.x + a.size.w, b.position.x + b.size.w)
			bottom = F32.min(a.position.y + a.size.h, b.position.y + b.size.h)
			{
				position: { x, y },
				size: {
					w: F32.max(0, right - x),
					h: F32.max(0, bottom - y),
				},
			}
		}

		union : Bounds, Bounds -> Bounds
		union = |a, b| {
			x = F32.min(a.position.x, b.position.x)
			y = F32.min(a.position.y, b.position.y)
			right = F32.max(a.position.x + a.size.w, b.position.x + b.size.w)
			bottom = F32.max(a.position.y + a.size.h, b.position.y + b.size.h)
			{
				position: { x, y },
				size: { w: right - x, h: bottom - y },
			}
		}

		is_empty : Bounds -> Bool
		is_empty = |bounds| bounds.size.w <= 0 or bounds.size.h <= 0

		expand : Bounds, Size -> Bounds
		expand = |bounds, amount| {
			position: {
				x: bounds.position.x - amount.w,
				y: bounds.position.y - amount.h,
			},
			size: {
				w: bounds.size.w + amount.w * 2,
				h: bounds.size.h + amount.h * 2,
			},
		}

		is_eq : Bounds, Bounds -> Bool
		is_eq = |a, b| a.position == b.position and a.size == b.size

		flatten : Bounds -> { x : F32, y : F32, width : F32, height : F32 }
		flatten = |bounds| {
			x: bounds.position.x,
			y: bounds.position.y,
			width: bounds.size.w,
			height: bounds.size.h,
		}

		center : Bounds -> Pos
		center = |bounds| {
			x: bounds.position.x + bounds.size.w / 2,
			y: bounds.position.y + bounds.size.h / 2,
		}
	}
}
