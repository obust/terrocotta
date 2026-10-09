## Capability-scoped workspace discovery for the IDE example.
import rr.Files

Workspace := [].{
	Node := [
		Directory({ path : Str, name : Str, children : List(Node) }),
		File({ path : Str, name : Str }),
	]

	discover! : Files.ReadDir => Try(List(Node), Files.ListError)
	discover! = |root| {
		result = discover_dir!(root, "", 0, 2000)?
		Ok(result.nodes)
	}

	join : Str, Str -> Str
	join = join_path
}

discover_dir! : Files.ReadDir, Str, U64, U64 => Try({ nodes : List(Workspace.Node), remaining : U64 }, Files.ListError)
discover_dir! = |root, path, depth, allowance| {
	if depth >= 12 or allowance == 0 {
		Ok({ nodes: [], remaining: allowance })
	} else {
		entries = root.list!(path)?
		visible = sort_entries(entries.keep_if(|entry| !entry.name.starts_with(".") and entry.kind != Other))
		var $nodes = []
		var $remaining = allowance
		for entry in visible {
			if $remaining == 0 {
				break
			}
			entry_path = join_path(path, entry.name)
			match entry.kind {
				File => {
					$nodes = $nodes.append(File({ path: entry_path, name: entry.name }))
					$remaining = $remaining - 1
				}
				Dir => {
					children = discover_dir!(root, entry_path, depth + 1, $remaining - 1)?
					$nodes = $nodes.append(Directory({ path: entry_path, name: entry.name, children: children.nodes }))
					$remaining = children.remaining
				}
				Other => {}
			}
		}
		Ok({ nodes: $nodes, remaining: $remaining })
	}
}

join_path : Str, Str -> Str
join_path = |parent, name| if parent == "" name else "${parent}/${name}"

compare_entries : Files.Entry, Files.Entry -> [LT, EQ, GT]
compare_entries = |a, b| match (a.kind, b.kind) {
	(Dir, File) => LT
	(File, Dir) => GT
	(Dir, Other) => LT
	(File, Other) => LT
	(Other, Dir) => GT
	(Other, File) => GT
	_ => compare_text(a.name.with_ascii_lowercased(), b.name.with_ascii_lowercased())
}

## Keep sorting explicit here. The compiler version currently used by this
## repository leaves `List.sort_with` input order unchanged for this platform
## record/tag shape even though the comparator itself returns the right order.
sort_entries : List(Files.Entry) -> List(Files.Entry)
sort_entries = |entries| entries.fold([], insert_entry)

insert_entry : List(Files.Entry), Files.Entry -> List(Files.Entry)
insert_entry = |sorted, entry| {
	var $result = []
	var $inserted = Bool.False
	for current in sorted {
		if !$inserted and compare_entries(entry, current) == LT {
			$result = $result.append(entry)
			$inserted = Bool.True
		}
		$result = $result.append(current)
	}
	if !$inserted {
		$result = $result.append(entry)
	}
	$result
}

compare_text : Str, Str -> [LT, EQ, GT]
compare_text = |a, b| {
	a_bytes = a.to_utf8()
	b_bytes = b.to_utf8()
	var $index = 0
	var $order = EQ
	while $index < a_bytes.len() and $index < b_bytes.len() and $order == EQ {
		a_byte = a_bytes.get($index).ok_or(0)
		b_byte = b_bytes.get($index).ok_or(0)
		$order = if a_byte < b_byte LT else if a_byte > b_byte GT else EQ
		$index = $index + 1
	}
	if $order != EQ {
		$order
	} else if a_bytes.len() < b_bytes.len() {
		LT
	} else if a_bytes.len() > b_bytes.len() {
		GT
	} else {
		EQ
	}
}

expect Workspace.join("components", "card.html") == "components/card.html"

expect {
	entries : List(Files.Entry)
	entries = [
		{ name: "index.html", kind: File },
		{ name: "about.html", kind: File },
		{ name: "components", kind: Dir },
		{ name: "assets", kind: Dir },
	]
	sorted = sort_entries(entries).map(|entry| entry.name)
	sorted == ["assets", "components", "about.html", "index.html"]
}

expect compare_text("about", "index") == LT
expect compare_entries({ name: "assets", kind: Dir }, { name: "index.html", kind: File }) == LT
