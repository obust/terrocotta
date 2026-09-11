## Text measurement and wrapping helpers for layout.
import Element
import Color
import rr.Font as RrtFont

Text := [].{
	Config : {
		font_size : F32,
		spacing : F32,
		color : Color,
		line_height : F32,
		align : Element.TextAlign,
		wrap : Element.TextWrap,
	}
	Word : {
		start : U64,
		len : U64,
		width : F32,
		is_newline : Bool,
	}

	Line : {
		start : U64,
		len : U64,
		width : F32,
		height : F32,
	}

	Measured : {
		preferred : { w : F32, h : F32 },
		line_height : F32,
		wrap_width : F32,
		min_width : F32,
		space_width : F32,
		words : List(Word),
		lines : List(Line),
	}

	CanonicalMeasured : {
		preferred_width : F32,
		natural_line_height : F32,
		min_width : F32,
		space_width : F32,
		words : List(Word),
		line_count : U64,
		contains_newlines : Bool,
	}

	measure : Str, Config, RrtFont -> Measured
	measure = |content, config, font| {
		measured = measure_canonical(content, config, font)
		line_h = apply_line_height(config, measured.natural_line_height)
		lines = wrap(content, config, measured.space_width, line_h, measured.preferred_width, measured.words)
		preferred_w = Text.wrapped_width(lines)
		preferred_h = Text.wrapped_height(line_h, lines)
		min_width = match config.wrap {
			Words => measured.min_width
			Newlines => preferred_w
			None => preferred_w
		}

		{
			preferred: { w: preferred_w, h: preferred_h },
			line_height: line_h,
			wrap_width: preferred_w,
			min_width,
			space_width: measured.space_width,
			words: measured.words,
			lines,
		}
	}

	measure_canonical : Str, Config, RrtFont -> CanonicalMeasured
	measure_canonical = |content, config, font| {
		space_raw = measure_raw(font, config, " ")
		space_width = space_raw.width
		measure_words(content, config, space_width, font)
	}

	apply_line_height : Config, F32 -> F32
	apply_line_height = |config, natural_line_height| {
		if config.line_height > 0 config.line_height else natural_line_height
	}

	wrap : Str, Config, F32, F32, F32, List(Word) -> List(Line)
	wrap = |content, config, space_width, line_h, width, words| {
		match config.wrap {
			Words => wrap_words(width, words, content, space_width, line_h)
			Newlines => wrap_newlines(words, content, space_width, line_h)
			None => [one_line(content, preferred_width(words), line_h)]
		}
	}

	wrapped_height : F32, List(Line) -> F32
	wrapped_height = |line_h, lines| {
		if lines.len() == 0 {
			0
		} else {
			line_h * lines.len().to_f32()
		}
	}

	wrapped_width : List(Line) -> F32
	wrapped_width = |lines| {
		var $width = 0
		for line in lines {
			$width = max_f32($width, line.width)
		}
		$width
	}

	line_text : Str, Line -> Str
	line_text = |content, line| {
		slice(content, line.start, line.len)
	}

	## Compute the on-screen bounds for one line given the flattened box bounds.
	line_bounds : { x : F32, y : F32, width : F32, height : F32 }, Element.TextAlign, Line, U64 -> { position : { x : F32, y : F32 }, size : { w : F32, h : F32 } }
	line_bounds = |box, align, line, line_offset| {
		position: {
			x: box.x + align_offset(align, box.width, line.width),
			y: box.y + line_offset.to_f32() * line.height,
		},
		size: { w: line.width, h: line.height },
	}

	## Horizontal offset for a line based on its alignment within the box.
	align_offset : Element.TextAlign, F32, F32 -> F32
	align_offset = |align, box_width, text_width| match align {
		Left => 0
		Center => (box_width - text_width) * 0.5
		Right => box_width - text_width
	}
}

measure_raw : RrtFont, Text.Config, Str -> RrtFont.Size
measure_raw = |font, config, content| {
	RrtFont.measure(
		font,
		{
			text: content,
			size: config.font_size,
			spacing: config.spacing,
		},
	)
}

measure_line_height : Str, Text.Config, RrtFont -> F32
measure_line_height = |content, config, font| {
	sample = if bytes_len(content) > 0 "M" else " "
	(measure_raw(font, config, sample)).height
}

bytes_len : Str -> U64
bytes_len = |content| content.to_utf8().len()

slice : Str, U64, U64 -> Str
slice = |content, start, len| {
	bytes = content.to_utf8().sublist({ start, len })
	Str.from_utf8_lossy(bytes)
}

max_f32 : F32, F32 -> F32
max_f32 = |a, b| if a > b a else b

measure_run : Str, U64, U64, F32, U64, Text.Config, RrtFont -> { word : Text.Word, trimmed_width : F32 }
measure_run = |content, start, len, extra_width, trailing_len, config, font| {
	text = slice(content, start, len)
	raw = measure_raw(font, config, text)
	width = raw.width + extra_width
	{ word: { start, len: len + trailing_len, width, is_newline: Bool.False }, trimmed_width: raw.width }
}

newline_word : U64 -> Text.Word
newline_word = |start| { start, len: 1, width: 0, is_newline: Bool.True }

measure_words : Str, Text.Config, F32, RrtFont -> Text.CanonicalMeasured
measure_words = |content, config, space_width, font| {
	bytes = content.to_utf8()
	line_h = measure_line_height(content, config, font)
	var $words = []
	var $preferred_w = 0
	var $current_w = 0
	var $min_width = 0
	var $line_count = 1.U64
	var $start = 0

	for i in 0..<bytes.len() {
		byte = bytes.get(i).ok_or(0)
		if byte == 32 {
			len = i - $start
			if len > 0 {
				measured = measure_run(content, $start, len, space_width, 1, config, font)
				$words = $words.append(measured.word)
				$current_w = $current_w + measured.word.width
				$min_width = max_f32($min_width, measured.trimmed_width)
			}
			$start = i + 1
		} else if byte == 10 {
			len = i - $start
			if len > 0 {
				measured = measure_run(content, $start, len, 0, 0, config, font)
				$words = $words.append(measured.word)
				$current_w = $current_w + measured.word.width
				$min_width = max_f32($min_width, measured.trimmed_width)
			}
			$words = $words.append(newline_word(i))
			$preferred_w = max_f32($preferred_w, $current_w)
			$current_w = 0
			$line_count = $line_count + 1
			$start = i + 1
		}
	}

	len = bytes.len() - $start
	if len > 0 {
		measured = measure_run(content, $start, len, 0, 0, config, font)
		$words = $words.append(measured.word)
		$current_w = $current_w + measured.word.width
		$min_width = max_f32($min_width, measured.trimmed_width)
	}
	$preferred_w = max_f32($preferred_w, $current_w)

	{
		preferred_width: $preferred_w,
		natural_line_height: line_h,
		min_width: $min_width,
		space_width,
		words: $words,
		line_count: $line_count,
		contains_newlines: $line_count > 1,
	}
}

preferred_width : List(Text.Word) -> F32
preferred_width = |words| {
	var $width = 0
	var $line_width = 0
	for word in words {
		if word.is_newline {
			$width = max_f32($width, $line_width)
			$line_width = 0
		} else {
			$line_width = $line_width + word.width
		}
	}
	max_f32($width, $line_width)
}

one_line : Str, F32, F32 -> Text.Line
one_line = |content, width, line_h| {
	{ start: 0, len: bytes_len(content), width, height: line_h }
}

trim_line : Str, U64, U64, F32, F32, F32 -> Text.Line
trim_line = |content, start, end, width, space_width, line_h| {
	len = if end > start end - start else 0
	trimmed = if len > 0 {
		bytes = content.to_utf8()
		match bytes.get(start + len - 1) {
			Ok(32) => { len: len - 1, width: width - space_width }
			_ => { len, width }
		}
	} else {
		{ len, width }
	}
	{ start, len: trimmed.len, width: trimmed.width, height: line_h }
}

wrap_newlines : List(Text.Word), Str, F32, F32 -> List(Text.Line)
wrap_newlines = |words, content, space_width, line_h| {
	var $lines = []
	var $line_start = 0
	var $line_end = 0
	var $line_width = 0

	for word in words {
		if word.is_newline {
			$lines = $lines.append(trim_line(content, $line_start, $line_end, $line_width, space_width, line_h))
			$line_start = word.start + word.len
			$line_end = $line_start
			$line_width = 0
		} else {
			if $line_width == 0 and word.len > 0 {
				$line_start = word.start
			}
			$line_end = word.start + word.len
			$line_width = $line_width + word.width
		}
	}

	$lines.append(trim_line(content, $line_start, $line_end, $line_width, space_width, line_h))
}

wrap_words : F32, List(Text.Word), Str, F32, F32 -> List(Text.Line)
wrap_words = |width, words, content, space_width, line_h| {
	var $lines = []
	var $line_start = 0
	var $line_end = 0
	var $line_width = 0
	var $has_word = Bool.False

	for word in words {
		if word.is_newline {
			$lines = $lines.append(trim_line(content, $line_start, $line_end, $line_width, space_width, line_h))
			$line_start = word.start + word.len
			$line_end = $line_start
			$line_width = 0
			$has_word = Bool.False
		} else {
			candidate = trim_line(content, $line_start, word.start + word.len, $line_width + word.width, space_width, line_h)
			should_wrap = $has_word and width > 0 and candidate.width > width
			if should_wrap {
				$lines = $lines.append(trim_line(content, $line_start, $line_end, $line_width, space_width, line_h))
				$line_start = word.start
				$line_end = word.start + word.len
				$line_width = word.width
			} else {
				if !$has_word {
					$line_start = word.start
				}
				$line_end = word.start + word.len
				$line_width = $line_width + word.width
			}
			$has_word = Bool.True
		}
	}

	if $has_word or $lines.len() == 0 {
		$lines.append(trim_line(content, $line_start, $line_end, $line_width, space_width, line_h))
	} else {
		$lines
	}
}

## TESTS ##

test_config : Element.TextWrap -> Text.Config
test_config = |wrap| { font_size: 5, spacing: 1, color: Color.black, line_height: 10, align: Left, wrap }

test_word : U64, U64, F32 -> Text.Word
test_word = |start, len, width| { start, len, width, is_newline: Bool.False }

test_newline : U64 -> Text.Word
test_newline = |start| { start, len: 1, width: 0, is_newline: Bool.True }

line_text_at : Str, List(Text.Line), U64 -> Str
line_text_at = |content, lines, index| {
	match lines.get(index) {
		Ok(line) => Text.line_text(content, line)
		Err(_) => ""
	}
}

line_width_at : List(Text.Line), U64 -> F32
line_width_at = |lines, index| {
	match lines.get(index) {
		Ok(line) => line.width
		Err(_) => -1
	}
}

line_height_at : List(Text.Line), U64 -> F32
line_height_at = |lines, index| {
	match lines.get(index) {
		Ok(line) => line.height
		Err(_) => -1
	}
}

line_len_at : List(Text.Line), U64 -> U64
line_len_at = |lines, index| {
	match lines.get(index) {
		Ok(line) => line.len
		Err(_) => 999
	}
}

## Short text narrower than its resolved width stays on one line.
expect {
	words = [test_word(0, 5, 5)]
	lines = Text.wrap("hello", test_config(Words), 1, 10, 20, words)
	lines.len() == 1 and line_text_at("hello", lines, 0) == "hello"
}

## Words wrapping breaks at spaces and trims trailing spaces from rendered lines.
expect {
	words = [test_word(0, 3, 3), test_word(3, 3, 3), test_word(6, 2, 2)]
	lines = Text.wrap("aa bb cc", test_config(Words), 1, 10, 4, words)
	lines.len() == 3
		and line_text_at("aa bb cc", lines, 0) == "aa"
			and line_text_at("aa bb cc", lines, 1) == "bb"
				and line_text_at("aa bb cc", lines, 2) == "cc"
}

## Trailing spaces trimmed at word-wrap breaks do not count toward line width.
expect {
	words = [test_word(0, 3, 3), test_word(3, 2, 2)]
	lines = Text.wrap("aa b", test_config(Words), 1, 10, 4, words)
	lines.len() == 2
		and line_text_at("aa b", lines, 0) == "aa"
			and line_len_at(lines, 0) == 2
				and line_width_at(lines, 0) == 2
					and line_text_at("aa b", lines, 1) == "b"
						and line_width_at(lines, 1) == 2
}

## A terminal space discarded during rendering does not force the last word to wrap.
expect {
	words = [test_word(0, 4, 4), test_word(4, 4, 4)]
	lines = Text.wrap("foo bar ", test_config(Words), 1, 10, 7, words)
	lines.len() == 1
		and line_text_at("foo bar ", lines, 0) == "foo bar"
			and line_width_at(lines, 0) == 7
}

## Terminal-space text still wraps when its visible content exceeds the width.
expect {
	words = [test_word(0, 4, 4), test_word(4, 4, 4)]
	lines = Text.wrap("foo bar ", test_config(Words), 1, 10, 6, words)
	lines.len() == 2
		and line_text_at("foo bar ", lines, 0) == "foo"
			and line_text_at("foo bar ", lines, 1) == "bar"
}

## A single long word wider than the resolved width stays one overflowing line.
expect {
	words = [test_word(0, 6, 6)]
	lines = Text.wrap("abcdef", test_config(Words), 1, 10, 3, words)
	match lines.get(0) {
		Ok(line) => lines.len() == 1 and line.width == 6
		Err(_) => Bool.False
	}
}

## Text width helpers report the widest wrapped line, not the preferred width.
expect {
	words = [test_word(0, 3, 3), test_word(3, 3, 3), test_word(6, 2, 2)]
	lines = Text.wrap("aa bb cc", test_config(Words), 1, 10, 4, words)
	Text.wrapped_width(lines) == 2 and Text.wrapped_height(10, lines) == 30
}

## Explicit newlines create line breaks.
expect {
	words = [test_word(0, 2, 2), test_newline(2), test_word(3, 2, 2)]
	lines = Text.wrap("aa\nbb", test_config(Words), 1, 10, 20, words)
	lines.len() == 2 and line_text_at("aa\nbb", lines, 0) == "aa" and line_text_at("aa\nbb", lines, 1) == "bb"
}

## Consecutive explicit newlines preserve empty lines with line height.
expect {
	words = [test_word(0, 2, 2), test_newline(2), test_newline(3), test_word(4, 2, 2)]
	lines = Text.wrap("aa\n\nbb", test_config(Words), 1, 10, 20, words)
	lines.len() == 3
		and line_text_at("aa\n\nbb", lines, 0) == "aa"
			and line_text_at("aa\n\nbb", lines, 1) == ""
				and line_width_at(lines, 1) == 0
					and line_height_at(lines, 1) == 10
						and line_text_at("aa\n\nbb", lines, 2) == "bb"
}

## Newlines mode ignores spaces as wrap opportunities.
expect {
	words = [test_word(0, 5, 5)]
	lines = Text.wrap("aa bb", test_config(Newlines), 1, 10, 3, words)
	lines.len() == 1 and line_text_at("aa bb", lines, 0) == "aa bb"
}

## Newlines mode preserves long explicit lines and reports their overflowing width.
expect {
	words = [test_word(0, 8, 8), test_newline(8), test_word(9, 2, 2)]
	lines = Text.wrap("aa bb cc\nzz", test_config(Newlines), 1, 10, 3, words)
	lines.len() == 2
		and line_text_at("aa bb cc\nzz", lines, 0) == "aa bb cc"
			and line_width_at(lines, 0) == 8
				and Text.wrapped_width(lines) == 8
}

## None mode keeps one raw render line; embedded newlines are preserved.
expect {
	words = [test_word(0, 5, 5)]
	lines = Text.wrap("aa\nbb", test_config(None), 1, 10, 3, words)
	lines.len() == 1 and line_text_at("aa\nbb", lines, 0) == "aa\nbb"
}

## None mode width is based on the unwrapped preferred text width.
expect {
	words = [test_word(0, 2, 2), test_newline(2), test_word(3, 2, 2)]
	lines = Text.wrap("aa\nbb", test_config(None), 1, 10, 1, words)
	lines.len() == 1 and line_width_at(lines, 0) == 2 and line_height_at(lines, 0) == 10
}
