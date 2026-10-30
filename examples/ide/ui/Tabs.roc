## A flat tab collection with a normalized active index.
##
## The backing List keeps rendering straightforward. Stable document IDs stay
## on the items themselves; this type owns only collection and selection logic.
Tabs(a) := {
	items : List(a),
	active_index : [NoIndex, Index(U64)],
	next_id : U64,
}.{
	from_list : List(a), [NoIndex, Index(U64)], U64 -> Tabs(a)
	from_list = |items, requested, next_id| {
		active_index = match requested {
			_ if items.is_empty() => NoIndex
			Index(index) if index < items.len() => Index(index)
			_ => Index(0)
		}
		{ items, active_index, next_id }
	}

	single : a, U64 -> Tabs(a)
	single = |item, next_id| { items: [item], active_index: Index(0), next_id }

	items : Tabs(a) -> List(a)
	items = |self| self.items

	active : Tabs(a) -> Try(a, [NoActiveTab])
	active = |self| match self.active_index {
		NoIndex => Err(NoActiveTab)
		Index(index) => self.items.get(index).map_err(|_| NoActiveTab)
	}

	is_active : Tabs(a), U64 -> Bool
	is_active = |self, index| self.active_index == Index(index)

	find : Tabs(a), (a -> Bool) -> Try(a, [NotFound])
	find = |self, predicate| self.items.find_first(predicate).map_err(|_| NotFound)

	activate : Tabs(a), (a -> Bool) -> Tabs(a)
	activate = |self, predicate| match find_index(self.items, predicate, 0) {
		Err(_) => self
		Ok(index) => { ..self, active_index: Index(index) }
	}

	open : Tabs(a), (U64 -> a) -> { tabs : Tabs(a), id : U64 }
	open = |self, make_item| {
		id = self.next_id
		next_items = self.items.append(make_item(id))
		{ tabs: { items: next_items, active_index: Index(next_items.len() - 1), next_id: id + 1 }, id }
	}

	update : Tabs(a), (a -> Bool), (a -> a) -> Tabs(a)
	update = |self, predicate, transform| { ..self, items: self.items.map(|item| if (predicate(item)) transform(item) else item) }

	close : Tabs(a), (a -> Bool) -> Tabs(a)
	close = |self, predicate| match find_index(self.items, predicate, 0) {
		Err(_) => self
		Ok(index) => {
			remaining = self.items.drop_at(index)
			active_index = match self.active_index {
				NoIndex => NoIndex
				Index(_current) if remaining.is_empty() => NoIndex
				Index(current) if index < current => Index(current - 1)
				Index(current) if index > current => Index(current)
				Index(_) if index < remaining.len() => Index(index)
				Index(_) => Index(remaining.len() - 1)
			}
			{ ..self, items: remaining, active_index }
		}
	}
}

find_index : List(a), (a -> Bool), U64 -> Try(U64, [NotFound])
find_index = |items, predicate, index| if index >= items.len() {
	Err(NotFound)
} else {
	match items.get(index) {
		Ok(item) => if (predicate(item)) Ok(index) else find_index(items, predicate, index + 1)
		Err(_) => Err(NotFound)
	}
}

expect {
	tabs = Tabs.from_list(["a", "b", "c"], Index(1), 3).close(|item| item == "b")
	tabs.items() == ["a", "c"] and tabs.active() == Ok("c")
}

expect {
	tabs = Tabs.from_list(["a", "b", "c"], Index(2), 3).close(|item| item == "a")
	tabs.items() == ["b", "c"] and tabs.active() == Ok("c")
}

expect {
	tabs = Tabs.single("a", 1).close(|_| Bool.True)
	tabs.items().is_empty() and tabs.active() == Err(NoActiveTab)
}

expect Tabs.from_list(["a"], NoIndex, 1).active() == Ok("a")

expect {
	opened = Tabs.from_list(["a"], Index(0), 7).open(|id| "tab-${id.to_str()}")
	opened.id == 7 and opened.tabs.items() == ["a", "tab-7"] and opened.tabs.active() == Ok("tab-7")
}
