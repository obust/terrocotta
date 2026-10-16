## Text measurement and wrapping helpers for layout.
import Element
import Color
import rr.Font

Text := [].{
	Config : {
		font_size : F32,
		spacing : F32,
		color : Color,
		line_height : F32,
		align : Element.TextAlign,
		wrap : Element.TextWrap,
	}
	SegmentKind : [Text, Space, HardBreak]

	## A measured source range with explicit line-breaking behavior. Phase 1
	## preserves the existing ASCII-space behavior; later phases can add richer
	## kinds without changing the cache shape.
	Segment : {
		start : U64,
		len : U64,
		width : F32,
		line_end_fit_width : F32,
		line_end_paint_width : F32,
		kind : SegmentKind,
	}

	Line : {
		start : U64,
		len : U64,
		width : F32,
		height : F32,
	}

	## A frame-local wrapped range. It is intentionally independent from the
	## persistent prepared cache.
	LineRange : {
		start : U64,
		len : U64,
		width : F32,
		height : F32,
	}

	LineStats : {
		line_count : U64,
		max_width : F32,
	}

	Measured : {
		preferred : { w : F32, h : F32 },
		line_height : F32,
		wrap_width : F32,
		min_width : F32,
		prepared : PreparedText,
		lines : List(Line),
	}

	LineMeasurement : {
		width : F32,
		height : F32,
	}

	PreparedText : {
		preferred : { w : F32, h : F32 },
		natural_line_height : F32,
		min_width : F32,
		space_width : F32,
		segments : List(Segment),
	}

	measure : Str, Config, Font -> Measured
	measure = |content, config, font| {
		prepared = prepare(content, config, font)
		line_h = apply_line_height(config, prepared.natural_line_height)
		lines = wrap(content, config, prepared.space_width, line_h, prepared.preferred.w, prepared)
		preferred_w = wrapped_width(lines)
		preferred_h = Text.wrapped_height(line_h, lines)
		min_width = match config.wrap {
			Words => prepared.min_width
			Newlines => preferred_w
			None => preferred_w
		}

		{
			preferred: { w: preferred_w, h: preferred_h },
			line_height: line_h,
			wrap_width: preferred_w,
			min_width,
			prepared,
			lines,
		}
	}

	## Measure one rendered line using the same metrics as the text renderer.
	## This is the API for carets, columns, and horizontal cursor placement.
	measure_line : Str, Config, Font -> LineMeasurement
	measure_line = |content, config, font| {
		raw = measure_raw(font, config, content)
		line_height = apply_line_height(config, measure_line_height(content, config, font))
		{ width: raw.width, height: line_height }
	}

	## Prepare all width-independent data once. The result is suitable for the
	## persistent cache and can be wrapped repeatedly at different widths.
	prepare : Str, Config, Font -> PreparedText
	prepare = |content, config, font| {
		space_raw = measure_raw(font, config, " ")
		# Font.measure adds spacing between every pair of codepoints. A word
		# separator has the space glyph plus the two spacing boundaries around
		# it, so use the same advance when laying out wrapped text.
		space_width = space_raw.width + config.spacing * 2
		prepare_segments(content, config, space_width, font)
	}

	apply_line_height : Config, F32 -> F32
	apply_line_height = |config, natural_line_height| {
		if config.line_height > 0 config.line_height else natural_line_height
	}

	## Compatibility wrapper for callers that still supply line metrics. All
	## break data itself comes from PreparedText.
	wrap : Str, Config, F32, F32, F32, PreparedText -> List(Line)
	wrap = |content, config, space_width, line_h, width, prepared| {
		walk_line_ranges(
			content,
			config,
			space_width,
			line_h,
			width,
			prepared,
			|range, lines| lines.append(range),
			[],
		)
	}

	## Stream width-dependent line ranges to a layout-owned accumulator without
	## retaining them in PreparedText or materializing a temporary line list.
	walk_line_ranges : Str, Config, F32, F32, F32, PreparedText, (LineRange, state -> state), state -> state
	walk_line_ranges = |content, config, space_width, line_h, width, prepared, visit, initial| {
		match config.wrap {
			Words => walk_words(width, prepared.segments, content, space_width, line_h, visit, initial)
			Newlines => walk_newlines(prepared.segments, content, space_width, line_h, visit, initial)
			None => visit(one_line(content, prepared.preferred.w, line_h), initial)
		}
	}

	measure_line_stats : Str, Config, F32, F32, F32, PreparedText -> LineStats
	measure_line_stats = |content, config, space_width, line_h, width, prepared| {
		walk_line_ranges(
			content,
			config,
			space_width,
			line_h,
			width,
			prepared,
			|range, stats| {
				line_count: stats.line_count + 1,
				max_width: max_f32(stats.max_width, range.width),
			},
			{ line_count: 0, max_width: 0 },
		)
	}

	wrapped_height : F32, List(Line) -> F32
	wrapped_height = |line_h, lines| {
		if lines.len() == 0 {
			0
		} else {
			line_h * lines.len().to_f32()
		}
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

wrapped_width : List(Text.Line) -> F32
wrapped_width = |lines| {
	var $width = 0
	for line in lines {
		$width = max_f32($width, line.width)
	}
	$width
}

measure_raw : Font, Text.Config, Str -> Font.Size
measure_raw = |font, config, content| {
	Font.measure(
		font,
		{
			text: content,
			size: config.font_size,
			spacing: config.spacing,
		},
	)
}

measure_line_height : Str, Text.Config, Font -> F32
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

measure_text_segment : Str, U64, U64, Text.Config, Font -> { segment : Text.Segment, width : F32 }
measure_text_segment = |content, start, len, config, font| {
	text = slice(content, start, len)
	raw = measure_raw(font, config, text)
	{
		segment: {
			start,
			len,
			width: raw.width,
			line_end_fit_width: raw.width,
			line_end_paint_width: raw.width,
			kind: Text,
		},
		width: raw.width,
	}
}

space_segment : U64, F32 -> Text.Segment
space_segment = |start, width| {
	start,
	len: 1,
	width,
	line_end_fit_width: 0,
	line_end_paint_width: 0,
	kind: Space,
}

hard_break_segment : U64 -> Text.Segment
hard_break_segment = |start| {
	start,
	len: 1,
	width: 0,
	line_end_fit_width: 0,
	line_end_paint_width: 0,
	kind: HardBreak,
}

prepare_segments : Str, Text.Config, F32, Font -> Text.PreparedText
prepare_segments = |content, config, space_width, font| {
	bytes = content.to_utf8()
	line_h = measure_line_height(content, config, font)
	var $segments = []
	var $preferred_w = 0
	var $current_w = 0
	var $min_width = 0
	var $line_count = 1.U64
	var $start = 0
	var $trailing_space = Bool.False

	for i in 0..<bytes.len() {
		byte = bytes.get(i).ok_or(0)
		if byte == 32 {
			len = i - $start
			if len > 0 {
				measured = measure_text_segment(content, $start, len, config, font)
				$segments = $segments.append(measured.segment)
				$current_w = $current_w + measured.width
				$min_width = max_f32($min_width, measured.width)
				$trailing_space = Bool.False
				$segments = $segments.append(space_segment(i, space_width))
				$current_w = $current_w + space_width
				$trailing_space = Bool.True
			}
			$start = i + 1
		} else if byte == 10 {
			len = i - $start
			if len > 0 {
				measured = measure_text_segment(content, $start, len, config, font)
				$segments = $segments.append(measured.segment)
				$current_w = $current_w + measured.width
				$min_width = max_f32($min_width, measured.width)
				$trailing_space = Bool.False
			}
			$segments = $segments.append(hard_break_segment(i))
			$preferred_w = max_f32($preferred_w, trim_preferred_width($current_w, $trailing_space, space_width))
			$current_w = 0
			$line_count = $line_count + 1
			$start = i + 1
			$trailing_space = Bool.False
		}
	}

	len = bytes.len() - $start
	if len > 0 {
		measured = measure_text_segment(content, $start, len, config, font)
		$segments = $segments.append(measured.segment)
		$current_w = $current_w + measured.width
		$min_width = max_f32($min_width, measured.width)
		$trailing_space = Bool.False
	}
	$preferred_w = max_f32($preferred_w, trim_preferred_width($current_w, $trailing_space, space_width))

	{
		preferred: { w: $preferred_w, h: line_h * $line_count.to_f32() },
		natural_line_height: line_h,
		min_width: $min_width,
		space_width,
		segments: $segments,
	}
}

trim_preferred_width : F32, Bool, F32 -> F32
trim_preferred_width = |width, has_trailing_space, space_width| if has_trailing_space width - space_width else width

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

walk_newlines : List(Text.Segment), Str, F32, F32, (Text.LineRange, state -> state), state -> state
walk_newlines = |segments, content, space_width, line_h, visit, initial| {
	var $state = initial
	var $line_start = 0
	var $line_end = 0
	var $line_width = 0
	var $has_text = Bool.False

	for segment in segments {
		match segment.kind {
			HardBreak => {
				$state = visit(trim_line(content, $line_start, $line_end, $line_width, space_width, line_h), $state)
				$line_start = segment.start + segment.len
				$line_end = $line_start
				$line_width = 0
				$has_text = Bool.False
			}
			Text => {
				if !$has_text {
					$line_start = segment.start
				}
				$line_end = segment.start + segment.len
				$line_width = $line_width + segment.width
				$has_text = Bool.True
			}
			Space => if $has_text {
				$line_end = segment.start + segment.len
				$line_width = $line_width + segment.width
			}
		}
	}

	visit(trim_line(content, $line_start, $line_end, $line_width, space_width, line_h), $state)
}

walk_words : F32, List(Text.Segment), Str, F32, F32, (Text.LineRange, state -> state), state -> state
walk_words = |width, segments, content, space_width, line_h, visit, initial| {
	var $state = initial
	var $line_count = 0.U64
	var $line_start = 0
	var $line_end = 0
	var $line_width = 0
	var $has_word = Bool.False

	for segment in segments {
		match segment.kind {
			HardBreak => {
				$state = visit(trim_line(content, $line_start, $line_end, $line_width, space_width, line_h), $state)
				$line_count = $line_count + 1
				$line_start = segment.start + segment.len
				$line_end = $line_start
				$line_width = 0
				$has_word = Bool.False
			}
			Text => {
				candidate = trim_line(content, $line_start, segment.start + segment.len, $line_width + segment.width, space_width, line_h)
				should_wrap = $has_word and width > 0 and candidate.width > width
				if should_wrap {
					$state = visit(trim_line(content, $line_start, $line_end, $line_width, space_width, line_h), $state)
					$line_count = $line_count + 1
					$line_start = segment.start
					$line_end = segment.start + segment.len
					$line_width = segment.width
				} else {
					if !$has_word {
						$line_start = segment.start
					}
					$line_end = segment.start + segment.len
					$line_width = $line_width + segment.width
				}
				$has_word = Bool.True
			}
			Space => if $has_word {
				$line_end = segment.start + segment.len
				$line_width = $line_width + segment.width
			}
		}
	}

	if $has_word or $line_count == 0 {
		visit(trim_line(content, $line_start, $line_end, $line_width, space_width, line_h), $state)
	} else {
		$state
	}
}

## TESTS ##

test_config : Element.TextWrap -> Text.Config
test_config = |wrap| { font_size: 5, spacing: 1, color: Color.black, line_height: 10, align: Left, wrap }

expect {
	config = test_config(None)
	Text.measure_line(" speed.", config, Font.stub).width == 41
}

## Preparation preserves source ranges while collapsing repeated ASCII spaces
## into one explicit Space segment per text run.
expect {
	prepared = Text.prepare("aa  bb\nc ", test_config(Words), Font.stub)
	match (prepared.segments.get(0), prepared.segments.get(1), prepared.segments.get(2), prepared.segments.get(3), prepared.segments.get(4), prepared.segments.get(5)) {
		(Ok(first), Ok(space), Ok(second), Ok(hard_break), Ok(last), Ok(trailing)) =>
			first.kind == Text
				and space.kind == Space
					and second.start == 4
						and hard_break.kind == HardBreak
							and last.kind == Text
								and trailing.kind == Space
		_ => Bool.False
	}
}

test_word : U64, U64, F32 -> Text.Segment
test_word = |start, len, width| {
	start,
	len,
	width,
	line_end_fit_width: width,
	line_end_paint_width: width,
	kind: Text,
}

test_newline : U64 -> Text.Segment
test_newline = |start| {
	start,
	len: 1,
	width: 0,
	line_end_fit_width: 0,
	line_end_paint_width: 0,
	kind: HardBreak,
}

test_prepared : List(Text.Segment) -> Text.PreparedText
test_prepared = |segments| {
	var $preferred_width = 0
	var $line_width = 0
	for segment in segments {
		match segment.kind {
			HardBreak => {
				$preferred_width = max_f32($preferred_width, $line_width)
				$line_width = 0
			}
			_ => {
				$line_width = $line_width + segment.width
			}
		}
	}
	{
		preferred: { w: max_f32($preferred_width, $line_width), h: 10 },
		natural_line_height: 10,
		min_width: 0,
		space_width: 1,
		segments,
	}
}

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
	lines = Text.wrap("hello", test_config(Words), 1, 10, 20, test_prepared(words))
	lines.len() == 1 and line_text_at("hello", lines, 0) == "hello"
}

## Words wrapping breaks at spaces and trims trailing spaces from rendered lines.
expect {
	words = [test_word(0, 3, 3), test_word(3, 3, 3), test_word(6, 2, 2)]
	lines = Text.wrap("aa bb cc", test_config(Words), 1, 10, 4, test_prepared(words))
	lines.len() == 3
		and line_text_at("aa bb cc", lines, 0) == "aa"
			and line_text_at("aa bb cc", lines, 1) == "bb"
				and line_text_at("aa bb cc", lines, 2) == "cc"
}

## Trailing spaces trimmed at word-wrap breaks do not count toward line width.
expect {
	words = [test_word(0, 3, 3), test_word(3, 2, 2)]
	lines = Text.wrap("aa b", test_config(Words), 1, 10, 4, test_prepared(words))
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
	lines = Text.wrap("foo bar ", test_config(Words), 1, 10, 7, test_prepared(words))
	lines.len() == 1
		and line_text_at("foo bar ", lines, 0) == "foo bar"
			and line_width_at(lines, 0) == 7
}

## Terminal-space text still wraps when its visible content exceeds the width.
expect {
	words = [test_word(0, 4, 4), test_word(4, 4, 4)]
	lines = Text.wrap("foo bar ", test_config(Words), 1, 10, 6, test_prepared(words))
	lines.len() == 2
		and line_text_at("foo bar ", lines, 0) == "foo"
			and line_text_at("foo bar ", lines, 1) == "bar"
}

## A single long word wider than the resolved width stays one overflowing line.
expect {
	words = [test_word(0, 6, 6)]
	lines = Text.wrap("abcdef", test_config(Words), 1, 10, 3, test_prepared(words))
	match lines.get(0) {
		Ok(line) => lines.len() == 1 and line.width == 6
		Err(_) => Bool.False
	}
}

## Text width helpers report the widest wrapped line, not the preferred width.
expect {
	words = [test_word(0, 3, 3), test_word(3, 3, 3), test_word(6, 2, 2)]
	lines = Text.wrap("aa bb cc", test_config(Words), 1, 10, 4, test_prepared(words))
	wrapped_width(lines) == 2 and Text.wrapped_height(10, lines) == 30
}

## Explicit newlines create line breaks.
expect {
	words = [test_word(0, 2, 2), test_newline(2), test_word(3, 2, 2)]
	lines = Text.wrap("aa\nbb", test_config(Words), 1, 10, 20, test_prepared(words))
	lines.len() == 2 and line_text_at("aa\nbb", lines, 0) == "aa" and line_text_at("aa\nbb", lines, 1) == "bb"
}

## Consecutive explicit newlines preserve empty lines with line height.
expect {
	words = [test_word(0, 2, 2), test_newline(2), test_newline(3), test_word(4, 2, 2)]
	lines = Text.wrap("aa\n\nbb", test_config(Words), 1, 10, 20, test_prepared(words))
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
	lines = Text.wrap("aa bb", test_config(Newlines), 1, 10, 3, test_prepared(words))
	lines.len() == 1 and line_text_at("aa bb", lines, 0) == "aa bb"
}

## Newlines mode preserves long explicit lines and reports their overflowing width.
expect {
	words = [test_word(0, 8, 8), test_newline(8), test_word(9, 2, 2)]
	lines = Text.wrap("aa bb cc\nzz", test_config(Newlines), 1, 10, 3, test_prepared(words))
	lines.len() == 2
		and line_text_at("aa bb cc\nzz", lines, 0) == "aa bb cc"
			and line_width_at(lines, 0) == 8
				and wrapped_width(lines) == 8
}

## None mode keeps one raw render line; embedded newlines are preserved.
expect {
	words = [test_word(0, 5, 5)]
	lines = Text.wrap("aa\nbb", test_config(None), 1, 10, 3, test_prepared(words))
	lines.len() == 1 and line_text_at("aa\nbb", lines, 0) == "aa\nbb"
}

## None mode width is based on the unwrapped preferred text width.
expect {
	words = [test_word(0, 2, 2), test_newline(2), test_word(3, 2, 2)]
	lines = Text.wrap("aa\nbb", test_config(None), 1, 10, 1, test_prepared(words))
	lines.len() == 1 and line_width_at(lines, 0) == 2 and line_height_at(lines, 0) == 10
}
