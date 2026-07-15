## Small generic helpers shared across the package.

Utils := [].{
	## Clamp a comparable value between inclusive minimum and maximum bounds.
	clamp : a, a, a -> a where [a.is_lt : a, a -> Bool, a.is_gt : a, a -> Bool]
	clamp = |value, min, max| {
		if value < min {
			min
		} else if value > max {
			max
		} else {
			value
		}
	}
}

expect {
	Utils.clamp(-1, 0, 10) == 0
}

expect {
	Utils.clamp(5, 0, 10) == 5
}

expect {
	Utils.clamp(11, 0, 10) == 10
}

expect {
	Utils.clamp(-0.25, 0.0, 1.0) == 0.0 and Utils.clamp(0.5, 0.0, 1.0) == 0.5 and Utils.clamp(1.25, 0.0, 1.0) == 1.0
}
