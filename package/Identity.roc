## Stable node identity derivation for layout elements.
import Element

Identity :: [].{

	NodeId : U64

	# Roc traps on integer overflow, so the hash mixer bounds intermediate values
	# before multiplying instead of relying on wrapping U64 arithmetic.
	# 2048 leaves headroom for the 131x byte mixer and 33x33 finalizer path.
	hash_mod : U64
	hash_mod = U64.highest // 2048

	finalize_hash : U64 -> NodeId
	finalize_hash = |hash| {
		var $finalized = hash % hash_mod
		$finalized = ($finalized * 33) + 17
		$finalized = (($finalized % hash_mod) * 33) + ($finalized // 2048)
		$finalized = ($finalized * 33) + 19
		$finalized + 1
	}

	hash_u64 : U64, U64 -> NodeId
	hash_u64 = |value, seed| {
		var $hash = (seed % hash_mod) + (value % hash_mod)
		$hash = ($hash * 109) + 37
		finalize_hash($hash)
	}

	hash_str_with_offset : Str, U64, U64 -> NodeId
	hash_str_with_offset = |label, offset, seed| {
		var $hash = (seed % hash_mod) + (offset % hash_mod)
		for byte in label.to_utf8() {
			$hash = (($hash % hash_mod) * 131) + byte.to_u64() + 7
		}
		finalize_hash($hash)
	}

	hash_str : Str, U64 -> NodeId
	hash_str = |label, seed| hash_str_with_offset(label, 0, seed)

	resolve : Element.ElementId, NodeId, U64 -> NodeId
	resolve = |id, parent, child_offset| match id {
		Auto => hash_u64(child_offset, parent)
		Id(label) => hash_str(label, 0)
		IdI(label, offset) => hash_str_with_offset(label, offset, 0)
		LocalId(label) => hash_str(label, parent)
		LocalIdI(label, offset) => hash_str_with_offset(label, offset, parent)
	}
}

# Auto IDs should be stable for the same parent and child offset.
expect {
	Identity.resolve(Auto, 42, 3) == Identity.resolve(Auto, 42, 3)
}

# Auto IDs should include the child offset.
expect {
	Identity.resolve(Auto, 42, 3) != Identity.resolve(Auto, 42, 4)
}

# Global string IDs should ignore parent and child offset.
expect {
	Identity.resolve(Id("save"), 1, 0) == Identity.resolve(Id("save"), 99, 20)
}

# Indexed global IDs should include the explicit offset.
expect {
	Identity.resolve(IdI("row", 1), 0, 0) != Identity.resolve(IdI("row", 2), 0, 0)
}

# Local IDs should include the parent ID.
expect {
	Identity.resolve(LocalId("label"), 10, 0) != Identity.resolve(LocalId("label"), 11, 0)
}

# Indexed local IDs should include both parent ID and explicit offset.
expect {
	parent = 10
	Identity.resolve(LocalIdI("label", 1), parent, 0) != Identity.resolve(LocalIdI("label", 2), parent, 0)
}

# Hashing should stay inside checked U64 arithmetic for maximum-sized inputs.
expect {
	Identity.resolve(Auto, U64.highest, U64.highest) > 0
		and Identity.resolve(IdI("max", U64.highest), U64.highest, U64.highest) > 0
}
