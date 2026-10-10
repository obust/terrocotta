## Small, dependency-free HTML highlighter for the IDE example.
##
## This is intentionally a lexer rather than an HTML parser. It emits ordered
## semantic byte ranges, makes progress on malformed input, and carries comments
## and quoted values across logical lines.
import Syntax

Html := [].{
	highlight : Str -> List(Syntax.HighlightSpan)
	highlight = tokenize
}

LexerState : [Data, ReadingTagName, TagBody, ReadingAttributeValue]

tokenize : Str -> List(Syntax.HighlightSpan)
tokenize = |source| {
	bytes = source.to_utf8()
	var $index = 0
	var $state = Data
	var $spans = []

	while $index < bytes.len() {
		match $state {
			Data => {
				if starts_at(bytes, $index, [60, 33, 45, 45]) {
					end = find_after(bytes, $index + 4, [45, 45, 62])
					$spans = append_span($spans, $index, end, Comment)
					$index = end
				} else if starts_ascii_caseless(bytes, $index, [60, 33, 100, 111, 99, 116, 121, 112, 101]) {
					end = scan_through(bytes, $index, 62)
					$spans = append_span($spans, $index, end, Directive)
					$index = end
				} else {
					byte = byte_at(bytes, $index)
					if byte == 60 {
						end = if byte_at(bytes, $index + 1) == 47 $index + 2 else $index + 1
						$spans = append_span($spans, $index, end, Punctuation)
						$index = end
						$state = ReadingTagName
					} else if byte == 38 {
						end = entity_end(bytes, $index)
						if end > $index + 1 {
							$spans = append_span($spans, $index, end, Escape)
						}
						$index = end
					} else {
						$index = scan_data(bytes, $index)
					}
				}
			}

			ReadingTagName => {
				byte = byte_at(bytes, $index)
				if is_space(byte) {
					$index = scan_space(bytes, $index)
				} else if byte == 62 {
					$spans = append_span($spans, $index, $index + 1, Punctuation)
					$index = $index + 1
					$state = Data
				} else {
					end = scan_name(bytes, $index)
					if end == $index {
						$spans = append_span($spans, $index, $index + 1, Punctuation)
						$index = $index + 1
					} else {
						$spans = append_span($spans, $index, end, Name)
						$index = end
						$state = TagBody
					}
				}
			}

			TagBody => {
				byte = byte_at(bytes, $index)
				if is_space(byte) {
					$index = scan_space(bytes, $index)
				} else if byte == 62 {
					$spans = append_span($spans, $index, $index + 1, Punctuation)
					$index = $index + 1
					$state = Data
				} else if byte == 47 and byte_at(bytes, $index + 1) == 62 {
					$spans = append_span($spans, $index, $index + 2, Punctuation)
					$index = $index + 2
					$state = Data
				} else if byte == 61 {
					$spans = append_span($spans, $index, $index + 1, Punctuation)
					$index = $index + 1
					$state = ReadingAttributeValue
				} else {
					end = scan_attribute_name(bytes, $index)
					if end == $index {
						$spans = append_span($spans, $index, $index + 1, Punctuation)
						$index = $index + 1
					} else {
						$spans = append_span($spans, $index, end, Property)
						$index = end
					}
				}
			}

			ReadingAttributeValue => {
				byte = byte_at(bytes, $index)
				if is_space(byte) {
					$index = scan_space(bytes, $index)
				} else if byte == 34 or byte == 39 {
					end = scan_quoted(bytes, $index, byte)
					$spans = append_span($spans, $index, end, Value)
					$index = end
					$state = TagBody
				} else if byte == 62 or (byte == 47 and byte_at(bytes, $index + 1) == 62) {
					$state = TagBody
				} else {
					end = scan_unquoted_value(bytes, $index)
					$spans = append_span($spans, $index, end, Value)
					$index = end
					$state = TagBody
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

scan_data : List(U8), U64 -> U64
scan_data = |bytes, start| {
	var $index = start
	while $index < bytes.len() and byte_at(bytes, $index) != 60 and byte_at(bytes, $index) != 38 {
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

scan_name : List(U8), U64 -> U64
scan_name = |bytes, start| {
	var $index = start
	while $index < bytes.len() {
		byte = byte_at(bytes, $index)
		if is_space(byte) or byte == 47 or byte == 62 {
			break
		}
		$index = $index + 1
	}
	$index
}

scan_attribute_name : List(U8), U64 -> U64
scan_attribute_name = |bytes, start| {
	var $index = start
	while $index < bytes.len() {
		byte = byte_at(bytes, $index)
		if is_space(byte) or byte == 47 or byte == 62 or byte == 61 {
			break
		}
		$index = $index + 1
	}
	$index
}

scan_unquoted_value : List(U8), U64 -> U64
scan_unquoted_value = |bytes, start| {
	var $index = start
	while $index < bytes.len() {
		byte = byte_at(bytes, $index)
		if is_space(byte) or byte == 47 or byte == 62 {
			break
		}
		$index = $index + 1
	}
	if $index == start start + 1 else $index
}

scan_quoted : List(U8), U64, U8 -> U64
scan_quoted = |bytes, start, quote| {
	var $index = start + 1
	var $done = Bool.False
	while $index < bytes.len() and !$done {
		if byte_at(bytes, $index) == quote {
			$index = $index + 1
			$done = Bool.True
		} else {
			$index = $index + 1
		}
	}
	$index
}

scan_through : List(U8), U64, U8 -> U64
scan_through = |bytes, start, terminal| {
	var $index = start
	var $done = Bool.False
	while $index < bytes.len() and !$done {
		if byte_at(bytes, $index) == terminal {
			$index = $index + 1
			$done = Bool.True
		} else {
			$index = $index + 1
		}
	}
	$index
}

entity_end : List(U8), U64 -> U64
entity_end = |bytes, start| {
	var $index = start + 1
	var $found = Bool.False
	limit = U64.min(bytes.len(), start + 34)
	while $index < limit and !$found {
		byte = byte_at(bytes, $index)
		if byte == 59 {
			$index = $index + 1
			$found = Bool.True
		} else if is_space(byte) or byte == 60 or byte == 38 {
			break
		} else {
			$index = $index + 1
		}
	}
	if $found $index else start + 1
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

starts_ascii_caseless : List(U8), U64, List(U8) -> Bool
starts_ascii_caseless = |bytes, start, needle| {
	if start + needle.len() > bytes.len() {
		Bool.False
	} else {
		var $index = 0
		var $matches = Bool.True
		while $index < needle.len() and $matches {
			$matches = lower_ascii(byte_at(bytes, start + $index)) == lower_ascii(byte_at(needle, $index))
			$index = $index + 1
		}
		$matches
	}
}

lower_ascii : U8 -> U8
lower_ascii = |byte| if byte >= 65 and byte <= 90 byte + 32 else byte

is_space : U8 -> Bool
is_space = |byte| byte == 32 or byte == 9 or byte == 10 or byte == 13

byte_at : List(U8), U64 -> U8
byte_at = |bytes, index| bytes.get(index).ok_or(0)

span_text : Str, Syntax.HighlightSpan -> Str
span_text = |source, span| Str.from_utf8_lossy(source.to_utf8().sublist({ start: span.start, len: span.end - span.start }))

expect {
	source = "<h1 class=\"hero\">Hi &amp;</h1>"
	spans = Html.highlight(source)
	Syntax.valid(source, spans) and spans.map(|span| { text: span_text(source, span), role: span.role }) == [
		{ text: "<", role: Punctuation },
		{ text: "h1", role: Name },
		{ text: "class", role: Property },
		{ text: "=", role: Punctuation },
		{ text: "\"hero\"", role: Value },
		{ text: ">", role: Punctuation },
		{ text: "&amp;", role: Escape },
		{ text: "</", role: Punctuation },
		{ text: "h1", role: Name },
		{ text: ">", role: Punctuation },
	]
}

expect {
	source = "<!-- one\ntwo -->"
	Html.highlight(source) == [{ start: 0, end: source.count_utf8_bytes(), role: Comment }]
}

expect Html.highlight("").is_empty()

expect {
	source = "<!DOCTYPE html>\n<p title=\"one\ntwo\">cafe</p>"
	spans = Html.highlight(source)
	Syntax.valid(source, spans) and match spans.first() {
		Ok({ start: 0, end: 15, role: Directive }) => Bool.True
		_ => Bool.False
	}
}

expect {
	source = "<div class=\"unfinished"
	Syntax.valid(source, Html.highlight(source))
}
