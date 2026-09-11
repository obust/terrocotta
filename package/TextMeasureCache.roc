## Persistent cache for host text measurements.
import Text
import rr.Font

TextMeasureCache :: {
	entries : Dict(Key, Entry),
	generation : U64,
}.{
	Key : {
		text : Str,
		font : Font.FontHandle,
		font_size : F32,
		spacing : F32,
	}

	Entry : {
		preferred_width : F32,
		natural_line_height : F32,
		min_width : F32,
		space_width : F32,
		words : List(Text.Word),
		line_count : U64,
		contains_newlines : Bool,
		generation : U64,
	}

	retain_generations : U64
	retain_generations = 3

	max_entries : U64
	max_entries = 4096

	new : () -> TextMeasureCache
	new = || { entries: Dict.empty(), generation: 0 }

	next_generation : TextMeasureCache -> TextMeasureCache
	next_generation = |cache| TextMeasureCache.prune({ ..cache, generation: cache.generation + 1 })

	reset : TextMeasureCache -> TextMeasureCache
	reset = |cache| { ..cache, entries: Dict.empty(), generation: 0 }

	prune : TextMeasureCache -> TextMeasureCache
	prune = |cache| {
		min_generation = if cache.generation > TextMeasureCache.retain_generations {
			cache.generation - TextMeasureCache.retain_generations
		} else {
			0
		}
		entries = cache.entries.keep_if(|(_key, entry)| entry.generation >= min_generation)
		capped_entries = if entries.len() > TextMeasureCache.max_entries {
			Dict.from_list(entries.to_list().take_last(TextMeasureCache.max_entries))
		} else {
			entries
		}
		{ ..cache, entries: capped_entries }
	}

	key : Str, Font.FontHandle, Text.Config -> Key
	key = |content, font_handle, config| {
		{
			text: content,
			font: font_handle,
			font_size: config.font_size,
			spacing: config.spacing,
		}
	}

	from_canonical : Text.CanonicalMeasured, U64 -> Entry
	from_canonical = |measured, generation| {
		{
			preferred_width: measured.preferred_width,
			natural_line_height: measured.natural_line_height,
			min_width: measured.min_width,
			space_width: measured.space_width,
			words: measured.words,
			line_count: measured.line_count,
			contains_newlines: measured.contains_newlines,
			generation,
		}
	}

	refresh_hit : TextMeasureCache, Key, Entry -> (TextMeasureCache, Entry)
	refresh_hit = |cache, cache_key, entry| {
		if entry.generation == cache.generation {
			(cache, entry)
		} else {
			refreshed = { ..entry, generation: cache.generation }
			({ ..cache, entries: cache.entries.insert(cache_key, refreshed) }, refreshed)
		}
	}

	## Insert an already measured entry. This is useful for deterministic callers
	## that cannot perform host effects, such as pure layout tests.
	insert : TextMeasureCache, Str, Font.FontHandle, Text.Config, Entry -> TextMeasureCache
	insert = |cache, content, font_handle, config, entry| {
		cache_key = TextMeasureCache.key(content, font_handle, config)
		current_entry = { ..entry, generation: cache.generation }
		{ ..cache, entries: cache.entries.insert(cache_key, current_entry) }
	}

	## Read an existing measurement without performing host measurement.
	get : TextMeasureCache, Str, Font.FontHandle, Text.Config -> Try(Entry, [KeyNotFound, ..])
	get = |cache, content, font_handle, config| {
		cache.entries.get(TextMeasureCache.key(content, font_handle, config))
	}

	get_or_create : TextMeasureCache, Str, Text.Config, Font -> (TextMeasureCache, Entry)
	get_or_create = |cache, content, config, font| {
		cache_key = TextMeasureCache.key(content, font.handle, config)
		match cache.entries.get(cache_key) {
			Ok(entry) => TextMeasureCache.refresh_hit(cache, cache_key, entry)
			Err(_) => {
				measured = Text.measure_canonical(content, config, font)
				entry = TextMeasureCache.from_canonical(measured, cache.generation)
				({ ..cache, entries: cache.entries.insert(cache_key, entry) }, entry)
			}
		}
	}

	len : TextMeasureCache -> U64
	len = |cache| cache.entries.len()
}

test_config : Text.Config
test_config = { font_size: 5, spacing: 1, color: { r: 0, g: 0, b: 0, a: 255 }, line_height: 0, align: Left, wrap: Words }

test_word : U64, U64, F32 -> Text.Word
test_word = |start, len, width| { start, len, width, is_newline: Bool.False }

test_entry : TextMeasureCache.Entry
test_entry = {
	preferred_width: 10,
	natural_line_height: 5,
	min_width: 6,
	space_width: 1,
	words: [test_word(0, 6, 6)],
	line_count: 1,
	contains_newlines: Bool.False,
	generation: 0,
}

## Advancing the cache preserves current entries and increments its generation.
expect {
	cache_key = TextMeasureCache.key("cached text", Font.stub.handle, test_config)
	empty_entries = Dict.empty()
	entries = empty_entries.insert(cache_key, test_entry)
	cache_seed = { ..TextMeasureCache.new(), entries }
	cache = cache_seed.next_generation()
	cache.entries.len() == 1
		and cache.generation == 1
}

## Reset clears entries and returns the cache to generation zero.
expect {
	key = TextMeasureCache.key("cached text", Font.stub.handle, test_config)
	entry = { ..test_entry, generation: 4 }
	entries = Dict.single(key, entry)
	cache = { ..TextMeasureCache.new(), entries, generation: 4 }
	reset_cache = cache.reset()
	reset_cache.entries.len() == 0
		and reset_cache.generation == 0
}

## Test cache key hashing.
expect {
	base = test_config
	base_key = TextMeasureCache.key("same text", Font.stub.handle, base)
	render_key = TextMeasureCache.key("same text", Font.stub.handle, { ..base, color: { r: 1, g: 2, b: 3, a: 4 }, align: Right, wrap: None, line_height: 50 })
	size_key = TextMeasureCache.key("same text", Font.stub.handle, { ..base, font_size: base.font_size + 1 })
	spacing_key = TextMeasureCache.key("same text", Font.stub.handle, { ..base, spacing: base.spacing + 1 })
	content_key = TextMeasureCache.key("different text", Font.stub.handle, base)

	base_key == render_key
		and base_key != size_key
				and base_key != spacing_key
					and base_key != content_key
}

## Cache hits from a previous generation refresh the entry generation.
expect {
	cache_key = TextMeasureCache.key("same text", Font.stub.handle, test_config)
	entries = Dict.empty().insert(cache_key, test_entry)
	cache = { ..TextMeasureCache.new(), entries, generation: 1 }
	(refreshed_cache, refreshed_entry) = TextMeasureCache.refresh_hit(cache, cache_key, test_entry)
	match refreshed_cache.entries.get(cache_key) {
		Ok(stored_entry) => refreshed_entry.generation == cache.generation
			and stored_entry.generation == cache.generation
		Err(_) => Bool.False
	}
}

## Pure lookup returns seeded canonical measurements.
expect {
	cache = TextMeasureCache.new().insert("cached text", Font.stub.handle, test_config, test_entry)
	match cache.get("cached text", Font.stub.handle, test_config) {
		Ok(entry) => entry == test_entry
		Err(_) => Bool.False
	}
}

## Pure lookup reports a missing measurement without invoking the host.
expect {
	cache = TextMeasureCache.new()
	match cache.get("missing text", Font.stub.handle, test_config) {
		Err(KeyNotFound) => Bool.True
		_ => Bool.False
	}
}

## Generation pruning drops entries older than the retention window.
expect {
	var $cache = TextMeasureCache.new()

	# add entry
	key = TextMeasureCache.key("old text", Font.stub.handle, test_config)
	entries = Dict.single(key, test_entry)
	$cache = { ..$cache, entries }

	# check generation eviction
	for _ in 0..<TextMeasureCache.retain_generations {
		$cache = $cache.next_generation()
	}
	check_retrained = $cache.entries.len() == 1

	$cache = $cache.next_generation()
	check_evicted = $cache.entries.len() == 0

	check_retrained and check_evicted
}

## Pruning applies the hard entry cap even when every entry is current.
expect {
	var $entries = Dict.empty()
	for entry_id in 0..<(TextMeasureCache.max_entries + 1) {
		cache_key = {
			text: "same text",
			font: Font.stub.handle,
			font_size: entry_id.to_f32(),
			spacing: 0,
		}
		$entries = $entries.insert(cache_key, test_entry)
	}
	cache = { ..TextMeasureCache.new(), entries: $entries }
	cache.prune().entries.len() == TextMeasureCache.max_entries
}
