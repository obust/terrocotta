
Stack(a) := {
	items : List(a),
}.{
	new : () -> Stack(a)
	new = || { items: [] }

	with_capacity : U64 -> Stack(a)
	with_capacity = |capacity| { items: List.with_capacity(capacity) }

	clear : Stack(a) -> Stack(a)
	clear = |self| { items: self.items.clear() }

	len : Stack(a) -> U64
	len = |self| self.items.len()

	push : Stack(a), a -> Stack(a)
	push = |self, item| { items: self.items.append(item) }

	top : Stack(a) -> Try(a, [OutOfBounds])
	top = |self| self.items.last().map_err(|_| OutOfBounds)

	pop : Stack(a) -> Try({ item : a, stack : Stack(a) }, [OutOfBounds])
	pop = |self| {
		match self.items.last() {
			Ok(item) => Ok({ item, stack: { items: self.items.sublist({ start: 0, len: self.items.len() - 1 }) } })
			Err(ListWasEmpty) => Err(OutOfBounds)
		}
	}
}
