## Source text and all state derived from it.
##
## Applying an edit rebuilds line geometry and syntax ranges together, so
## callers never observe highlights which refer to different content.
## File and clipboard boundaries normalize line endings before constructing or
## editing a buffer, so a logical newline here is always one LF byte. Source
## positions remain byte offsets; tab-aware helpers derive visual columns for
## display and pointer geometry.
import Highlight
import Syntax

Buffer := {
	content : Str,
	language : Highlight.Language,
	highlights : List(Syntax.HighlightSpan),
	line_starts : List(U64),
	line_lengths : List(U64),
}.{
	Edit : { start : U64, end : U64, replacement : Str }
	TabRounding : [Before, Nearest, After]

	tab_width : U64
	tab_width = 4

	tab_byte : U8
	tab_byte = 9 # "\t"

	create : Str, Highlight.Language -> Buffer
	create = create_buffer

	from_path : Str, Str -> Buffer
	from_path = |path, content| create_buffer(content, Highlight.language_for(path))

	apply_edit : Buffer, Edit -> Buffer
	apply_edit = apply_buffer_edit

	line_count : Buffer -> U64
	line_count = |buffer| buffer.line_starts.len()

	line_start : Buffer, U64 -> U64
	line_start = buffer_line_start

	line_length : Buffer, U64 -> U64
	line_length = buffer_line_length

	position_at : Buffer, U64 -> { line : U64, column : U64 }
	position_at = buffer_position_at

	offset_at : Buffer, U64, U64 -> U64
	offset_at = buffer_offset_at

	visual_column_at : Buffer, U64 -> U64
	visual_column_at = buffer_visual_column_at

	offset_at_visual_column : Buffer, U64, U64, TabRounding -> U64
	offset_at_visual_column = buffer_offset_at_visual_column

	visual_line_length : Buffer, U64 -> U64
	visual_line_length = |buffer, line| buffer_visual_column_at(buffer, buffer_line_start(buffer, line) + buffer_line_length(buffer, line))

	text_in : Buffer, U64, U64 -> Str
	text_in = buffer_text_in
}

create_buffer : Str, Highlight.Language -> Buffer
create_buffer = |content, language| {
	geometry = line_geometry(content)
	{
		content,
		language,
		highlights: Highlight.highlight(language, content),
		line_starts: geometry.starts,
		line_lengths: geometry.lengths,
	}
}

apply_buffer_edit : Buffer, Buffer.Edit -> Buffer
apply_buffer_edit = |buffer, edit| {
	bytes = buffer.content.to_utf8()
	start = U64.min(edit.start, bytes.len())
	end = U64.max(start, U64.min(edit.end, bytes.len()))
	before = bytes.sublist({ start: 0, len: start })
	after = bytes.sublist({ start: end, len: bytes.len() - end })
	content = Str.from_utf8_lossy(before.concat(edit.replacement.to_utf8()).concat(after))
	create_buffer(content, buffer.language)
}

line_geometry : Str -> { starts : List(U64), lengths : List(U64) }
line_geometry = |content| {
	bytes = content.to_utf8()
	var $starts = [0]
	var $lengths = []
	var $start = 0
	var $index = 0
	while $index < bytes.len() {
		if byte_at(bytes, $index) == 10 {
			$lengths = $lengths.append($index - $start)
			$start = $index + 1
			$starts = $starts.append($start)
		}
		$index = $index + 1
	}
	$lengths = $lengths.append(bytes.len() - $start)
	{ starts: $starts, lengths: $lengths }
}

buffer_line_start : Buffer, U64 -> U64
buffer_line_start = |buffer, line| buffer.line_starts.get(line).ok_or(0)

buffer_line_length : Buffer, U64 -> U64
buffer_line_length = |buffer, line| buffer.line_lengths.get(line).ok_or(0)

buffer_position_at : Buffer, U64 -> { line : U64, column : U64 }
buffer_position_at = |buffer, requested| {
	offset = U64.min(requested, buffer.content.count_utf8_bytes())
	line = line_index(buffer.line_starts, offset)
	{ line, column: offset - buffer_line_start(buffer, line) }
}

buffer_offset_at : Buffer, U64, U64 -> U64
buffer_offset_at = |buffer, requested_line, requested_column| {
	line_count = buffer.line_starts.len()
	line = if (line_count == 0) 0 else U64.min(requested_line, line_count - 1)
	buffer_line_start(buffer, line) + U64.min(requested_column, buffer_line_length(buffer, line))
}

buffer_visual_column_at : Buffer, U64 -> U64
buffer_visual_column_at = |buffer, requested_offset| {
	position = buffer_position_at(buffer, requested_offset)
	start = buffer_line_start(buffer, position.line)
	end = U64.min(start + position.column, start + buffer_line_length(buffer, position.line))
	visual_column_in(buffer.content.to_utf8(), start, end)
}

visual_column_in : List(U8), U64, U64 -> U64
visual_column_in = |bytes, start, end| {
	var $offset = start
	var $column = 0
	while $offset < end {
		$column = advance_column($column, byte_at(bytes, $offset))
		$offset = $offset + 1
	}
	$column
}

advance_column : U64, U8 -> U64
advance_column = |column, byte| if (byte == Buffer.tab_byte) column + Buffer.tab_width - column % Buffer.tab_width else column + 1

buffer_offset_at_visual_column : Buffer, U64, U64, Buffer.TabRounding -> U64
buffer_offset_at_visual_column = |buffer, requested_line, requested_column, rounding| {
	line_count = buffer.line_starts.len()
	line = if (line_count == 0) 0 else U64.min(requested_line, line_count - 1)
	start = buffer_line_start(buffer, line)
	end = start + buffer_line_length(buffer, line)
	bytes = buffer.content.to_utf8()
	var $offset = start
	var $column = 0
	while $offset < end {
		next_column = advance_column($column, byte_at(bytes, $offset))
		if requested_column < next_column {
			return match rounding {
				Before => $offset
				After => $offset + 1
				Nearest => if (requested_column - $column < next_column - requested_column) $offset else $offset + 1
			}
		}
		$offset = $offset + 1
		$column = next_column
		if requested_column == $column {
			return $offset
		}
	}
	end
}

buffer_text_in : Buffer, U64, U64 -> Str
buffer_text_in = |buffer, requested_start, requested_end| {
	bytes = buffer.content.to_utf8()
	start = U64.min(requested_start, bytes.len())
	end = U64.max(start, U64.min(requested_end, bytes.len()))
	Str.from_utf8_lossy(bytes.sublist({ start, len: end - start }))
}

line_index : List(U64), U64 -> U64
line_index = |starts, offset| {
	if starts.len() == 0 {
		0
	} else {
		line_index_at(starts, offset, 0, starts.len())
	}
}

line_index_at : List(U64), U64, U64, U64 -> U64
line_index_at = |starts, offset, low, high| {
	if low >= high {
		if (low == 0) 0 else low - 1
	} else {
		mid = low + (high - low) // 2
		start = starts.get(mid).ok_or(0)
		if start <= offset {
			line_index_at(starts, offset, mid + 1, high)
		} else {
			line_index_at(starts, offset, low, mid)
		}
	}
}

byte_at : List(U8), U64 -> U8
byte_at = |bytes, index| bytes.get(index).ok_or(0)

expect {
	buffer = Buffer.create("one\ntwo\n", PlainText)
	buffer.line_starts == [0, 4, 8] and buffer.line_lengths == [3, 3, 0]
}

expect {
	buffer = Buffer.create("one\ntwo", PlainText)
	Buffer.position_at(buffer, 5) == { line: 1, column: 1 }
		and Buffer.offset_at(buffer, 1, 20) == 7
}

expect {
	buffer = Buffer.create("abc", PlainText)
	updated = Buffer.apply_edit(buffer, { start: 1, end: 2, replacement: "XY" })
	updated.content == "aXYc"
		and updated.line_starts == [0]
		and updated.line_lengths == [4]
}

expect {
	buffer = Buffer.from_path("style.css", ".a { color: red; }")
	updated = Buffer.apply_edit(buffer, { start: 12, end: 15, replacement: "blue" })
	updated.content == ".a { color: blue; }"
		and Syntax.valid(updated.content, updated.highlights)
		and updated.highlights.any(|span| span.role == Value and Buffer.text_in(updated, span.start, span.end) == "blue")
}

expect {
	buffer = Buffer.from_path("index.html", "\t<div>text</div>")
	buffer.highlights.any(|span| span.start == 2 and span.end == 5 and span.role == Name and Buffer.text_in(buffer, span.start, span.end) == "div")
}

expect {
	buffer = Buffer.create("\tab", PlainText)
	Buffer.visual_column_at(buffer, 0) == 0
		and Buffer.visual_column_at(buffer, 1) == 4
		and Buffer.visual_column_at(buffer, 2) == 5
		and Buffer.visual_line_length(buffer, 0) == 6
}

expect {
	buffer = Buffer.create("a\tb\t\tc", PlainText)
	[0, 1, 4, 5, 8, 12, 13].map_with_index(|expected, offset| Buffer.visual_column_at(buffer, offset) == expected).all(|value| value)
}

expect {
	buffer = Buffer.create("a\tb", PlainText)
	Buffer.offset_at_visual_column(buffer, 0, 1, Nearest) == 1
		and Buffer.offset_at_visual_column(buffer, 0, 2, Nearest) == 1
		and Buffer.offset_at_visual_column(buffer, 0, 3, Nearest) == 2
		and Buffer.offset_at_visual_column(buffer, 0, 2, Before) == 1
		and Buffer.offset_at_visual_column(buffer, 0, 2, After) == 2
		and Buffer.offset_at_visual_column(buffer, 0, 20, Nearest) == 3
}

expect {
	buffer = Buffer.create("\t\t", PlainText)
	Buffer.offset_at_visual_column(buffer, 0, 1, Nearest) == 0
		and Buffer.offset_at_visual_column(buffer, 0, 2, Nearest) == 1
		and Buffer.offset_at_visual_column(buffer, 0, 5, Nearest) == 1
		and Buffer.offset_at_visual_column(buffer, 0, 6, Nearest) == 2
}

expect {
	buffer = Buffer.create("\t\nx\ty", PlainText)
	Buffer.visual_line_length(buffer, 0) == 4
		and Buffer.visual_line_length(buffer, 1) == 5
		and Buffer.offset_at_visual_column(buffer, 20, 20, Before) == 5
}
