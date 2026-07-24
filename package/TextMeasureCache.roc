## Persistent cache for host text measurements.
import Element
import Text

TextMeasureCache := {
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
}

test_measure_text! : Text.MeasureTextFn
test_measure_text! = |config| {
	{ width: config.text.to_utf8().len().to_f32(), height: config.size }
}

test_word : U64, U64, F32 -> Text.Word
test_word = |start, len, width| { start, len, width, is_newline: Bool.False }

## Text measurement cache can be advanced and reset directly.
expect {
	cache_key = TextMeasureCache.key("cached text", Element.default_text)
	entry = {
		preferred_width: 10,
		natural_line_height: 5,
		min_width: 6,
		space_width: 1,
		words: [test_word(0, 6, 6)],
		line_count: 1,
		contains_newlines: Bool.False,
		generation: 0,
	}
	empty_entries = Dict.empty()
	entries = empty_entries.insert(cache_key, entry)
	cache_seed = { ..TextMeasureCache.new(test_measure_text!), entries }
	cache = cache_seed.next_generation()
	reset_cache = cache.reset()
	cache.entries.len() == 1
		and cache.generation == 1
			and reset_cache.entries.len() == 0
				and reset_cache.generation == 0
}

## Wrapping policy and explicit line height are excluded from measurement keys.
expect {
	cfg_a = { ..Element.default_text, wrap: Words, line_height: 0 }
	cfg_b = { ..Element.default_text, wrap: None, line_height: 50 }
	TextMeasureCache.key("same text", cfg_a) == TextMeasureCache.key("same text", cfg_b)
}

## Cache hits from a previous generation refresh the entry generation.
expect {
	cache_key = TextMeasureCache.key("same text", Element.default_text)
	entry = {
		preferred_width: 10,
		natural_line_height: 5,
		min_width: 6,
		space_width: 1,
		words: [test_word(0, 6, 6)],
		line_count: 1,
		contains_newlines: Bool.False,
		generation: 0,
	}
	entries = Dict.empty().insert(cache_key, entry)
	cache = { ..TextMeasureCache.new(test_measure_text!), entries, generation: 1 }
	(refreshed_cache, refreshed_entry) = TextMeasureCache.refresh_hit(cache, cache_key, entry)
	match refreshed_cache.entries.get(cache_key) {
		Ok(stored_entry) => refreshed_entry.generation == cache.generation
			and stored_entry.generation == cache.generation
		Err(_) => Bool.False
	}
}

## Generation pruning drops entries older than the retention window.
expect {
	cache_key = TextMeasureCache.key("old text", Element.default_text)
	entry = {
		preferred_width: 10,
		natural_line_height: 5,
		min_width: 6,
		space_width: 1,
		words: [test_word(0, 6, 6)],
		line_count: 1,
		contains_newlines: Bool.False,
		generation: 0,
	}
	entries = Dict.empty().insert(cache_key, entry)
	cache_seed = { ..TextMeasureCache.new(test_measure_text!), entries }
	var $cache = cache_seed
	for _ in 0..<(TextMeasureCache.retain_generations + 1) {
		$cache = $cache.next_generation()
	}
	$cache.entries.len() == 0
}
