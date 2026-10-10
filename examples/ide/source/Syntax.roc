## Language-agnostic syntax-highlight data for the IDE example.

Syntax := [].{
	HighlightRole : [Plain, Punctuation, Name, Property, Value, Comment, Directive, Escape]

	HighlightSpan : { start : U64, end : U64, role : HighlightRole }

	## Check the invariants expected by the source buffer and renderer.
	valid : Str, List(HighlightSpan) -> Bool
	valid = valid_spans
}

valid_spans : Str, List(Syntax.HighlightSpan) -> Bool
valid_spans = |source, spans| {
	limit = source.count_utf8_bytes()
	var $previous_end = 0
	var $valid = Bool.True
	for span in spans {
		if span.start >= span.end or span.end > limit or span.start < $previous_end {
			$valid = Bool.False
		}
		$previous_end = span.end
	}
	$valid
}

expect Syntax.valid("", [])
expect Syntax.valid("abc", [{ start: 0, end: 1, role: Name }, { start: 2, end: 3, role: Value }])
expect !Syntax.valid("abc", [{ start: 1, end: 3, role: Name }, { start: 2, end: 3, role: Value }])
