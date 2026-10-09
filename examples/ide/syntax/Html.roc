## Small, dependency-free HTML highlighter for the IDE example.
##
## This is intentionally a lexer rather than an HTML parser. It preserves the
## source text, makes progress on malformed input, and carries comments and
## quoted values across logical lines before the renderer splits them.

Html := [].{
	TokenKind : [TextToken, Punctuation, TagName, AttributeName, AttributeValue, Comment, Doctype, Entity]

	Span : { text : Str, kind : TokenKind }

	Line : { spans : List(Span) }

	highlight : Str -> List(Line)
	highlight = |source| spans_to_lines(tokenize(source))

	plain : Str -> List(Line)
	plain = |source| spans_to_lines([{ text: source, kind: TextToken }])
}

LexerState : [Data, ReadingTagName, TagBody, ReadingAttributeValue]

tokenize : Str -> List(Html.Span)
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
					$spans = append_range($spans, source, $index, end, Comment)
					$index = end
				} else if starts_ascii_caseless(bytes, $index, [60, 33, 100, 111, 99, 116, 121, 112, 101]) {
					end = scan_through(bytes, $index, 62)
					$spans = append_range($spans, source, $index, end, Doctype)
					$index = end
				} else {
					byte = byte_at(bytes, $index)
					if byte == 60 {
						end = if byte_at(bytes, $index + 1) == 47 $index + 2 else $index + 1
						$spans = append_range($spans, source, $index, end, Punctuation)
						$index = end
						$state = ReadingTagName
					} else if byte == 38 {
						end = entity_end(bytes, $index)
						kind = if end > $index + 1 Entity else TextToken
						$spans = append_range($spans, source, $index, end, kind)
						$index = end
					} else {
						end = scan_data(bytes, $index)
						$spans = append_range($spans, source, $index, end, TextToken)
						$index = end
					}
				}
			}

			ReadingTagName => {
				byte = byte_at(bytes, $index)
				if is_space(byte) {
					end = scan_space(bytes, $index)
					# Keep spacing with the token which follows it. A standalone
					# whitespace text box has zero intrinsic width in the current
					# layout engine, while leading space in a token is measured.
					$spans = append_range($spans, source, $index, end, TagName)
					$index = end
				} else if byte == 62 {
					$spans = append_range($spans, source, $index, $index + 1, Punctuation)
					$index = $index + 1
					$state = Data
				} else {
					end = scan_name(bytes, $index)
					if end == $index {
						$spans = append_range($spans, source, $index, $index + 1, Punctuation)
						$index = $index + 1
					} else {
						$spans = append_range($spans, source, $index, end, TagName)
						$index = end
						$state = TagBody
					}
				}
			}

			TagBody => {
				byte = byte_at(bytes, $index)
				if is_space(byte) {
					end = scan_space(bytes, $index)
					$spans = append_range($spans, source, $index, end, AttributeName)
					$index = end
				} else if byte == 62 {
					$spans = append_range($spans, source, $index, $index + 1, Punctuation)
					$index = $index + 1
					$state = Data
				} else if byte == 47 and byte_at(bytes, $index + 1) == 62 {
					$spans = append_range($spans, source, $index, $index + 2, Punctuation)
					$index = $index + 2
					$state = Data
				} else if byte == 61 {
					$spans = append_range($spans, source, $index, $index + 1, Punctuation)
					$index = $index + 1
					$state = ReadingAttributeValue
				} else {
					end = scan_attribute_name(bytes, $index)
					if end == $index {
						$spans = append_range($spans, source, $index, $index + 1, Punctuation)
						$index = $index + 1
					} else {
						$spans = append_range($spans, source, $index, end, AttributeName)
						$index = end
					}
				}
			}

			ReadingAttributeValue => {
				byte = byte_at(bytes, $index)
				if is_space(byte) {
					end = scan_space(bytes, $index)
					$spans = append_range($spans, source, $index, end, AttributeValue)
					$index = end
				} else if byte == 34 or byte == 39 {
					end = scan_quoted(bytes, $index, byte)
					$spans = append_range($spans, source, $index, end, AttributeValue)
					$index = end
					$state = TagBody
				} else if byte == 62 or (byte == 47 and byte_at(bytes, $index + 1) == 62) {
					$state = TagBody
				} else {
					end = scan_unquoted_value(bytes, $index)
					$spans = append_range($spans, source, $index, end, AttributeValue)
					$index = end
					$state = TagBody
				}
			}
		}
	}

	$spans
}

append_range : List(Html.Span), Str, U64, U64, Html.TokenKind -> List(Html.Span)
append_range = |spans, source, start, end, kind| {
	if end <= start {
		spans
	} else {
		content = slice(source, start, end - start)
		match spans.last() {
			Ok(last) => if last.kind == kind {
				spans.drop_last(1).append({ text: Str.concat(last.text, content), kind })
			} else {
				spans.append({ text: content, kind })
			}
			Err(_) => spans.append({ text: content, kind })
		}
	}
}

spans_to_lines : List(Html.Span) -> List(Html.Line)
spans_to_lines = |spans| {
	var $lines = []
	var $current = []
	for span in spans {
		bytes = span.text.to_utf8()
		var $start = 0
		var $index = 0
		while $index < bytes.len() {
			if byte_at(bytes, $index) == 10 {
				end = if $index > $start and byte_at(bytes, $index - 1) == 13 $index - 1 else $index
				if end > $start {
					$current = append_range($current, span.text, $start, end, span.kind)
				}
				$lines = $lines.append({ spans: $current })
				$current = []
				$start = $index + 1
			}
			$index = $index + 1
		}
		if $start < bytes.len() {
			$current = append_range($current, span.text, $start, bytes.len(), span.kind)
		}
	}
	$lines.append({ spans: $current })
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

slice : Str, U64, U64 -> Str
slice = |source, start, len| Str.from_utf8_lossy(source.to_utf8().sublist({ start, len }))

line_source : Html.Line -> Str
line_source = |line| Str.join_with(line.spans.map(|span| span.text), "")

expect {
	match Html.highlight("<h1 class=\"hero\">Hi &amp;</h1>") {
		[{ spans }] => match spans {
			[
				{ text: "<", kind: Punctuation },
				{ text: "h1", kind: TagName },
				{ text: " class", kind: AttributeName },
				{ text: "=", kind: Punctuation },
				{ text: "\"hero\"", kind: AttributeValue },
				{ text: ">", kind: Punctuation },
				{ text: "Hi ", kind: TextToken },
				{ text: "&amp;", kind: Entity },
				{ text: "</", kind: Punctuation },
				{ text: "h1", kind: TagName },
				{ text: ">", kind: Punctuation },
			] => Bool.True
			_ => Bool.False
		}
		_ => Bool.False
	}
}

expect {
	match Html.highlight("<!-- one\ntwo -->") {
		[{ spans: [{ kind: Comment, .. }] }, { spans: [{ kind: Comment, .. }] }] => Bool.True
		_ => Bool.False
	}
}

expect Html.highlight("").len() == 1

expect {
	lines = Html.highlight("<!DOCTYPE html>\n<p title=\"one\ntwo\">cafe</p>")
	lines.map(line_source) == ["<!DOCTYPE html>", "<p title=\"one", "two\">cafe</p>"]
}

expect {
	match Html.highlight("<!DOCTYPE html>") {
		[{ spans: [{ text: "<!DOCTYPE html>", kind: Doctype }] }] => Bool.True
		_ => Bool.False
	}
}

expect line_source(Html.highlight("<div class=\"unfinished").get(0).ok_or({ spans: [] })) == "<div class=\"unfinished"
