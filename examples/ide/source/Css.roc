## Small, dependency-free CSS highlighter for the IDE example.
##
## Like the HTML highlighter, this is a forgiving lexer. It emits ordered
## semantic byte ranges and carries comments and quoted values across lines.
import Syntax

Css := [].{
	highlight : Str -> List(Syntax.HighlightSpan)
	highlight = tokenize
}

LexerState : [Selector, PropertyName, PropertyValue]

tokenize : Str -> List(Syntax.HighlightSpan)
tokenize = |source| {
	bytes = source.to_utf8()
	var $index = 0
	var $state = Selector
	var $grouping_at_rule = Bool.False
	var $spans = []

	while $index < bytes.len() {
		if starts_at(bytes, $index, [47, 42]) {
			end = find_after(bytes, $index + 2, [42, 47])
			$spans = append_span($spans, $index, end, Comment)
			$index = end
		} else {
			byte = byte_at(bytes, $index)
			if is_space(byte) {
				$index = scan_space(bytes, $index)
			} else {
				match $state {
					Selector => {
						if byte == 123 {
							$spans = append_span($spans, $index, $index + 1, Punctuation)
							$index = $index + 1
							$state = if $grouping_at_rule Selector else PropertyName
							$grouping_at_rule = Bool.False
						} else if byte == 125 or byte == 59 {
							$spans = append_span($spans, $index, $index + 1, Punctuation)
							$index = $index + 1
							$grouping_at_rule = Bool.False
						} else if byte == 64 {
							end = scan_at_rule(bytes, $index)
							$spans = append_span($spans, $index, end, Directive)
							$grouping_at_rule = is_grouping_at_rule(slice(source, $index, end - $index).with_ascii_lowercased())
							$index = end
						} else {
							end = scan_until(bytes, $index, [32, 9, 10, 13, 64, 123, 125, 59, 47])
							next = if end == $index $index + 1 else end
							$spans = append_span($spans, $index, next, Name)
							$index = next
						}
					}

					PropertyName => {
						if byte == 125 {
							$spans = append_span($spans, $index, $index + 1, Punctuation)
							$index = $index + 1
							$state = Selector
						} else if byte == 58 {
							$spans = append_span($spans, $index, $index + 1, Punctuation)
							$index = $index + 1
							$state = PropertyValue
						} else if byte == 59 {
							$spans = append_span($spans, $index, $index + 1, Punctuation)
							$index = $index + 1
						} else {
							end = scan_until(bytes, $index, [32, 9, 10, 13, 58, 59, 125, 47])
							next = if end == $index $index + 1 else end
							$spans = append_span($spans, $index, next, Property)
							$index = next
						}
					}

					PropertyValue => {
						if byte == 34 or byte == 39 {
							end = scan_quoted(bytes, $index, byte)
							$spans = append_span($spans, $index, end, Value)
							$index = end
						} else if byte == 59 {
							$spans = append_span($spans, $index, $index + 1, Punctuation)
							$index = $index + 1
							$state = PropertyName
						} else if byte == 125 {
							$spans = append_span($spans, $index, $index + 1, Punctuation)
							$index = $index + 1
							$state = Selector
						} else {
							end = scan_until(bytes, $index, [32, 9, 10, 13, 34, 39, 59, 125, 47])
							next = if end == $index $index + 1 else end
							$spans = append_span($spans, $index, next, Value)
							$index = next
						}
					}
				}
			}
		}
	}

	$spans
}

append_span : List(Syntax.HighlightSpan), U64, U64, Syntax.HighlightRole -> List(Syntax.HighlightSpan)
append_span = |spans, start, end, role| {
	if end <= start {
		spans
	} else {
		match spans.last() {
			Ok(last) => if last.role == role and last.end == start {
				spans.drop_last(1).append({ start: last.start, end, role })
			} else {
				spans.append({ start, end, role })
			}
			Err(_) => spans.append({ start, end, role })
		}
	}
}

scan_until : List(U8), U64, List(U8) -> U64
scan_until = |bytes, start, terminals| {
	var $index = start
	while $index < bytes.len() and !terminals.contains(byte_at(bytes, $index)) {
		$index = $index + 1
	}
	$index
}

scan_space : List(U8), U64 -> U64
scan_space = |bytes, start| {
	var $index = start
	while $index < bytes.len() and is_space(byte_at(bytes, $index)) {
		$index = $index + 1
	}
	$index
}

scan_at_rule : List(U8), U64 -> U64
scan_at_rule = |bytes, start| {
	var $index = start + 1
	while $index < bytes.len() {
		byte = byte_at(bytes, $index)
		if !is_name_byte(byte) {
			break
		}
		$index = $index + 1
	}
	$index
}

scan_quoted : List(U8), U64, U8 -> U64
scan_quoted = |bytes, start, quote| {
	var $index = start + 1
	var $escaped = Bool.False
	var $done = Bool.False
	while $index < bytes.len() and !$done {
		byte = byte_at(bytes, $index)
		if $escaped {
			$escaped = Bool.False
		} else if byte == 92 {
			$escaped = Bool.True
		} else if byte == quote {
			$done = Bool.True
		}
		$index = $index + 1
	}
	$index
}

find_after : List(U8), U64, List(U8) -> U64
find_after = |bytes, start, needle| {
	var $index = start
	var $found = Bool.False
	while $index < bytes.len() and !$found {
		if starts_at(bytes, $index, needle) {
			$index = U64.min(bytes.len(), $index + needle.len())
			$found = Bool.True
		} else {
			$index = $index + 1
		}
	}
	$index
}

starts_at : List(U8), U64, List(U8) -> Bool
starts_at = |bytes, start, needle| {
	if start + needle.len() > bytes.len() {
		Bool.False
	} else {
		var $index = 0
		var $matches = Bool.True
		while $index < needle.len() and $matches {
			$matches = byte_at(bytes, start + $index) == byte_at(needle, $index)
			$index = $index + 1
		}
		$matches
	}
}

is_name_byte : U8 -> Bool
is_name_byte = |byte| (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or (byte >= 48 and byte <= 57) or byte == 45 or byte == 95

is_space : U8 -> Bool
is_space = |byte| byte == 32 or byte == 9 or byte == 10 or byte == 13

is_grouping_at_rule : Str -> Bool
is_grouping_at_rule = |name| name == "@media" or name == "@supports" or name == "@container" or name == "@layer" or name == "@scope" or name == "@document" or name == "@keyframes" or name.ends_with("-keyframes")

byte_at : List(U8), U64 -> U8
byte_at = |bytes, index| bytes.get(index).ok_or(0)

slice : Str, U64, U64 -> Str
slice = |source, start, len| Str.from_utf8_lossy(source.to_utf8().sublist({ start, len }))

span_text : Str, Syntax.HighlightSpan -> Str
span_text = |source, span| slice(source, span.start, span.end - span.start)

has_highlight : Str, List(Syntax.HighlightSpan), Str, Syntax.HighlightRole -> Bool
has_highlight = |source, spans, expected, role| spans.any(|span| span.role == role and span_text(source, span) == expected)

expect {
	source = ":root {\n  color: #d8dee9;\n}"
	spans = Css.highlight(source)
	Syntax.valid(source, spans)
		and has_highlight(source, spans, ":root", Name)
		and has_highlight(source, spans, "color", Property)
		and has_highlight(source, spans, "#d8dee9", Value)
}

expect {
	source = "/* one\ntwo */\n.card { content: \"a; } b\"; }"
	spans = Css.highlight(source)
	Syntax.valid(source, spans) and match spans.first() {
		Ok(span) => span.role == Comment and span_text(source, span) == "/* one\ntwo */"
		_ => Bool.False
	}
}

expect Css.highlight("").is_empty()

expect {
	source = "@media screen;"
	has_highlight(source, Css.highlight(source), "@media", Directive)
}

expect {
	source = "@media screen { .card { color: red; } }"
	spans = Css.highlight(source)
	Syntax.valid(source, spans) and has_highlight(source, spans, ".card", Name)
}
