## Small, dependency-free CSS highlighter for the IDE example.
##
## Like the HTML highlighter, this is a forgiving lexer. It preserves every
## source byte and carries comments and quoted values across logical lines.
import Syntax

Css := [].{
	highlight : Str -> List(Syntax.Line)
	highlight = |source| Syntax.lines(tokenize(source))
}

LexerState : [Selector, PropertyName, PropertyValue]

tokenize : Str -> List(Syntax.Span)
tokenize = |source| {
	bytes = source.to_utf8()
	var $index = 0
	var $state = Selector
	var $grouping_at_rule = Bool.False
	var $spans = []

	while $index < bytes.len() {
		if starts_at(bytes, $index, [47, 42]) {
			end = find_after(bytes, $index + 2, [42, 47])
			$spans = append_range($spans, source, $index, end, Comment)
			$index = end
		} else {
			byte = byte_at(bytes, $index)
			match $state {
				Selector => {
					if byte == 123 {
						$spans = append_range($spans, source, $index, $index + 1, Punctuation)
						$index = $index + 1
						$state = if $grouping_at_rule Selector else PropertyName
						$grouping_at_rule = Bool.False
					} else if byte == 125 or byte == 59 {
						$spans = append_range($spans, source, $index, $index + 1, Punctuation)
						$index = $index + 1
						$grouping_at_rule = Bool.False
					} else if byte == 64 {
						end = scan_at_rule(bytes, $index)
						$spans = append_range($spans, source, $index, end, CssAtRule)
						$grouping_at_rule = is_grouping_at_rule(slice(source, $index, end - $index).with_ascii_lowercased())
						$index = end
					} else {
						end = scan_until(bytes, $index, [64, 123, 125, 59, 47])
						$spans = append_range($spans, source, $index, if end == $index $index + 1 else end, CssSelector)
						$index = if end == $index $index + 1 else end
					}
				}

				PropertyName => {
					if byte == 125 {
						$spans = append_range($spans, source, $index, $index + 1, Punctuation)
						$index = $index + 1
						$state = Selector
					} else if byte == 58 {
						$spans = append_range($spans, source, $index, $index + 1, Punctuation)
						$index = $index + 1
						$state = PropertyValue
					} else if byte == 59 {
						$spans = append_range($spans, source, $index, $index + 1, Punctuation)
						$index = $index + 1
					} else {
						end = scan_until(bytes, $index, [58, 59, 125, 47])
						$spans = append_range($spans, source, $index, if end == $index $index + 1 else end, CssPropertyName)
						$index = if end == $index $index + 1 else end
					}
				}

				PropertyValue => {
					if byte == 34 or byte == 39 {
						end = scan_quoted(bytes, $index, byte)
						$spans = append_range($spans, source, $index, end, CssPropertyValue)
						$index = end
					} else if byte == 59 {
						$spans = append_range($spans, source, $index, $index + 1, Punctuation)
						$index = $index + 1
						$state = PropertyName
					} else if byte == 125 {
						$spans = append_range($spans, source, $index, $index + 1, Punctuation)
						$index = $index + 1
						$state = Selector
					} else {
						end = scan_until(bytes, $index, [34, 39, 59, 125, 47])
						$spans = append_range($spans, source, $index, if end == $index $index + 1 else end, CssPropertyValue)
						$index = if end == $index $index + 1 else end
					}
				}
			}
		}
	}

	$spans
}

append_range : List(Syntax.Span), Str, U64, U64, Syntax.TokenKind -> List(Syntax.Span)
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

scan_until : List(U8), U64, List(U8) -> U64
scan_until = |bytes, start, terminals| {
	var $index = start
	while $index < bytes.len() and !terminals.contains(byte_at(bytes, $index)) {
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

is_grouping_at_rule : Str -> Bool
is_grouping_at_rule = |name| name == "@media" or name == "@supports" or name == "@container" or name == "@layer" or name == "@scope" or name == "@document" or name == "@keyframes" or name.ends_with("-keyframes")

byte_at : List(U8), U64 -> U8
byte_at = |bytes, index| bytes.get(index).ok_or(0)

slice : Str, U64, U64 -> Str
slice = |source, start, len| Str.from_utf8_lossy(source.to_utf8().sublist({ start, len }))

line_source : Syntax.Line -> Str
line_source = |line| Str.join_with(line.spans.map(|span| span.text), "")

expect {
	match Css.highlight(":root {\n  color: #d8dee9;\n}") {
		[
			{ spans: [{ text: ":root ", kind: CssSelector }, { text: "{", kind: Punctuation }] },
			{ spans: [{ text: "  color", kind: CssPropertyName }, { text: ":", kind: Punctuation }, { text: " #d8dee9", kind: CssPropertyValue }, { text: ";", kind: Punctuation }] },
			{ spans: [{ text: "}", kind: Punctuation }] },
		] => Bool.True
		_ => Bool.False
	}
}

expect {
	source = "/* one\ntwo */\n.card { content: \"a; } b\"; }"
	lines = Css.highlight(source)
	lines.map(line_source) == source.split_on("\n") and match lines {
		[{ spans: [{ kind: Comment, .. }] }, { spans: [{ kind: Comment, .. }] }, ..] => Bool.True
		_ => Bool.False
	}
}

expect Css.highlight("").len() == 1

expect {
	match Css.highlight("@media screen;") {
		[{ spans: [{ text: "@media", kind: CssAtRule }, ..] }] => Bool.True
		_ => Bool.False
	}
}

expect {
	match Css.highlight("@media screen { .card { color: red; } }") {
		[{ spans }] => spans.contains({ text: " .card ", kind: CssSelector })
		_ => Bool.False
	}
}
