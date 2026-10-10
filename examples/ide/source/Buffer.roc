## Source text and all state derived from it.
##
## Applying an edit rebuilds line geometry and syntax ranges together, so
## callers never observe highlights which refer to different content.
import Highlight
import Syntax

Buffer := [].{
	Buffer : {
		content : Str,
		language : Highlight.Language,
		highlights : List(Syntax.HighlightSpan),
		line_starts : List(U64),
		line_lengths : List(U64),
	}

	Edit : { start : U64, end : U64, replacement : Str }

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

	text_in : Buffer, U64, U64 -> Str
	text_in = buffer_text_in
}

create_buffer : Str, Highlight.Language -> Buffer.Buffer
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

apply_buffer_edit : Buffer.Buffer, Buffer.Edit -> Buffer.Buffer
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

buffer_line_start : Buffer.Buffer, U64 -> U64
buffer_line_start = |buffer, line| buffer.line_starts.get(line).ok_or(0)

buffer_line_length : Buffer.Buffer, U64 -> U64
buffer_line_length = |buffer, line| buffer.line_lengths.get(line).ok_or(0)

buffer_position_at : Buffer.Buffer, U64 -> { line : U64, column : U64 }
buffer_position_at = |buffer, requested| {
	offset = U64.min(requested, buffer.content.count_utf8_bytes())
	line = line_index(buffer.line_starts, offset)
	{ line, column: offset - buffer_line_start(buffer, line) }
}

buffer_offset_at : Buffer.Buffer, U64, U64 -> U64
buffer_offset_at = |buffer, requested_line, requested_column| {
	line_count = buffer.line_starts.len()
	line = if line_count == 0 0 else U64.min(requested_line, line_count - 1)
	buffer_line_start(buffer, line) + U64.min(requested_column, buffer_line_length(buffer, line))
}

buffer_text_in : Buffer.Buffer, U64, U64 -> Str
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
		if low == 0 0 else low - 1
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
