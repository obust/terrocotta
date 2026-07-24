## Persistent cache for host text measurements.
import Element
import Text

TextMeasureCache :: {
	entries : Dict(Key, Entry),
	generation : U64,
	measure_text! : Text.MeasureTextFn,
}.{
	Key : {
		text : Str,
		font : U64,
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

	new : Text.MeasureTextFn -> TextMeasureCache
	new = |measure_text!| { entries: Dict.empty(), generation: 0, measure_text! }

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

	key : Str, Element.TextConfig -> Key
	key = |content, config| {
		{
			text: content,
			font: Box.unbox(config.font),
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
	insert : TextMeasureCache, Str, Element.TextConfig, Entry -> TextMeasureCache
	insert = |cache, content, config, entry| {
		cache_key = TextMeasureCache.key(content, config)
		current_entry = { ..entry, generation: cache.generation }
		{ ..cache, entries: cache.entries.insert(cache_key, current_entry) }
	}

	## Read an existing measurement without performing host measurement.
	lookup : TextMeasureCache, Str, Element.TextConfig -> Try(Entry, [MissingEntry])
	lookup = |cache, content, config| {
		cache.entries.get(TextMeasureCache.key(content, config)).map_err(|_| MissingEntry)
	}

	get! : TextMeasureCache, Str, Element.TextConfig => (TextMeasureCache, Entry)
	get! = |cache, content, config| {
		cache_key = TextMeasureCache.key(content, config)
		match cache.entries.get(cache_key) {
			Ok(entry) => TextMeasureCache.refresh_hit(cache, cache_key, entry)
			Err(_) => {
				measured = Text.measure_canonical!(content, config, cache.measure_text!)
				entry = TextMeasureCache.from_canonical(measured, cache.generation)
				({ ..cache, entries: cache.entries.insert(cache_key, entry) }, entry)
			}
		}
	}

	len : TextMeasureCache -> U64
	len = |cache| cache.entries.len()
}

test_measure_text! : Text.MeasureTextFn
test_measure_text! = |config| {
	{ width: config.text.to_utf8().len().to_f32(), height: config.size }
}

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
	cache_key = TextMeasureCache.key("cached text", Element.default_text)
	empty_entries = Dict.empty()
	entries = empty_entries.insert(cache_key, test_entry)
	cache_seed = { ..TextMeasureCache.new(test_measure_text!), entries }
	cache = cache_seed.next_generation()
	cache.entries.len() == 1
		and cache.generation == 1
}

## Reset clears entries and returns the cache to generation zero.
expect {
	key = TextMeasureCache.key("cached text", Element.default_text)
	entry = { ..test_entry, generation: 4 }
	entries = Dict.single(key, entry)
	cache = { ..TextMeasureCache.new(test_measure_text!), entries, generation: 4 }
	reset_cache = cache.reset()
	reset_cache.entries.len() == 0
		and reset_cache.generation == 0
}

## Test cache key hashing.
expect {
	base = Element.default_text
	base_key = TextMeasureCache.key("same text", base)
	render_key = TextMeasureCache.key("same text", { ..base,
	    color: { r: 1, g: 2, b: 3, a: 4 },
    	align: Right,
    	wrap: None,
    	line_height: 50
    })
	font_key = TextMeasureCache.key("same text", { ..base, font: Box.box(99) })
	size_key = TextMeasureCache.key("same text", { ..base, font_size: base.font_size + 1 })
	spacing_key = TextMeasureCache.key("same text", { ..base, spacing: base.spacing + 1 })
	content_key = TextMeasureCache.key("different text", base)

	base_key == render_key
    	and base_key != font_key
    		and base_key != size_key
    			and base_key != spacing_key
    				and base_key != content_key
}

## Cache hits from a previous generation refresh the entry generation.
expect {
	cache_key = TextMeasureCache.key("same text", Element.default_text)
	entries = Dict.empty().insert(cache_key, test_entry)
	cache = { ..TextMeasureCache.new(test_measure_text!), entries, generation: 1 }
	(refreshed_cache, refreshed_entry) = TextMeasureCache.refresh_hit(cache, cache_key, test_entry)
	match refreshed_cache.entries.get(cache_key) {
		Ok(stored_entry) => refreshed_entry.generation == cache.generation
			and stored_entry.generation == cache.generation
		Err(_) => Bool.False
	}
}

## Pure lookup returns seeded canonical measurements.
expect {
	cache = TextMeasureCache.new(test_measure_text!).insert("cached text", Element.default_text, test_entry)
	match cache.lookup("cached text", Element.default_text) {
		Ok(entry) => entry == test_entry
		Err(_) => Bool.False
	}
}

## Pure lookup reports a missing measurement without invoking the host.
expect {
	cache = TextMeasureCache.new(test_measure_text!)
	match cache.lookup("missing text", Element.default_text) {
		Err(MissingEntry) => Bool.True
		_ => Bool.False
	}
}

## Generation pruning drops entries older than the retention window.
expect {
	var $cache = TextMeasureCache.new(test_measure_text!)

	# add entry
	key = TextMeasureCache.key("old text", Element.default_text)
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
	for font_id in 0..<(TextMeasureCache.max_entries + 1) {
		cache_key = {
			text: "same text",
			font: font_id,
			font_size: 1,
			spacing: 0,
		}
		$entries = $entries.insert(cache_key, test_entry)
	}
	cache = { ..TextMeasureCache.new(test_measure_text!), entries: $entries }
	cache.prune().entries.len() == TextMeasureCache.max_entries
}
