## Shared token and line representation for the IDE example highlighters.

Syntax := [].{
	TokenKind : [TextToken, Punctuation, TagName, AttributeName, AttributeValue, Comment, Doctype, Entity, CssSelector, CssPropertyName, CssPropertyValue, CssAtRule]

	Span : { text : Str, kind : TokenKind }

	Line : { spans : List(Span) }

	lines : List(Span) -> List(Line)
	lines = spans_to_lines

	plain : Str -> List(Line)
	plain = |source| spans_to_lines([{ text: source, kind: TextToken }])
}

spans_to_lines : List(Syntax.Span) -> List(Syntax.Line)
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

byte_at : List(U8), U64 -> U8
byte_at = |bytes, index| bytes.get(index).ok_or(0)

slice : Str, U64, U64 -> Str
slice = |source, start, len| Str.from_utf8_lossy(source.to_utf8().sublist({ start, len }))
