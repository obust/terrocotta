## A small multi-line code editor: one buffer, one cursor, highlighted spans.
##
## Unlike the generic single-line TextInput widget, this component owns the
## editing surface. Text is rendered as syntax-colored spans and input events
## mutate the document cursor directly.
import rr.Font
import rr.Keys
import tc.Color
import tc.Element exposing [box, style, text]
import tc.Event
import tc.Program exposing [View]
import tc.TextMeasure
import tc.Unicode exposing [codepoints_to_str]

import ../Theme exposing [theme]
import ../syntax/Html

Cursor := { line : U64, column : U64 }

CodeMetrics := { glyph_advance : F32, line_height : F32 }

Document := {
	content : Str,
	language : [HtmlLanguage, PlainText],
	lines : List(Html.Line),
	cursor : Cursor,
}

Msg : [TextInput(Event.TextInputEvent), InsertLineBreak, MoveUp, MoveDown, Pointer(Event.PointerEvent, F32, F32)]

CodeEditor := [].{
	view : Font, Document -> View(Msg)
	view = view_editor

	update : Document, Msg -> Document
	update = update_document
}

view_editor : Font, Document -> View(Msg)
view_editor = |font, document| {
	metrics = { glyph_advance: glyph_advance(font), line_height: code_line_height(font) }
	box(
		{
			id: Id("code-editor"),
			style: |_| style
				.width(Grow({}))
				.height(Grow({}))
				.background(theme.palette.surface.base.fill)
				.font_family(font)
				.font_size(14)
				.spacing(0)
				.cursor(IBeam)
				.overflow(Scroll, Scroll)
				.child_align({ x: Start, y: Start }),
			events: [
				OnTextInput(Box.box(|event| TextInput(event))),
				OnKeyPressed(KeyEnter, InsertLineBreak),
				OnKeyPressed(KeyUp, MoveUp),
				OnKeyPressed(KeyDown, MoveDown),
				OnPointer(Box.box(|event| Pointer(event, metrics.glyph_advance, metrics.line_height))),
			],
		},
		[
			box(
				{ style: |_| style.width(Fit({ min: 700 })).height(Fit({})).direction(Col).child_align({ x: Start, y: Start }) },
				document.lines.map_with_index(|line, index| line_editor(line, index, document, metrics)),
			),
		],
	)
}

line_editor : Html.Line, U64, Document, CodeMetrics -> View(Msg)
line_editor = |line, index, document, metrics| {
	active = document.cursor.line == index
	local_cursor = document.cursor.column
	box(
		{
			id: IdI("code-line", index),
			style: |_| style.width(Grow({ min: 700 })).height(Fixed(metrics.line_height)).direction(Row).child_align({ x: Start, y: Center }).cursor(IBeam).background(if active theme.palette.surface.base.content.with_alpha(12) else theme.palette.surface.base.fill),
		},
		[
			line_number(index, metrics.line_height),
			line_code(line, metrics),
			if active { cursor_view(local_cursor, metrics) } else box({ style: |_| style.width(Fixed(0)).height(Fixed(0)) }, []),
		],
	)
}

line_number : U64, F32 -> View(Msg)
line_number = |index, row_height| box(
	{
		style: |_| style.width(Fixed(58)).height(Fixed(row_height)).pad(0, theme.gap + theme.gap / 2, 0, theme.gap / 2).font_color(theme.palette.text.muted).text_align(Right).text_wrap(None).child_align({ x: End, y: Center }).cursor(IBeam),
	},
	[text((index + 1).to_str())],
)

line_code : Html.Line, CodeMetrics -> View(Msg)
line_code = |line, metrics| box(
	{
		style: |_| style.width(Grow({ min: 642 })).height(Fixed(metrics.line_height)).direction(Row).child_align({ x: Start, y: Center }).cursor(IBeam),
	},
	line.spans.map(|span| span_view(span, metrics)),
)

cursor_view : U64, CodeMetrics -> View(Msg)
cursor_view = |cursor, metrics| {
	offset = cursor.to_f32() * metrics.glyph_advance + 58
	box(
		{
			style: |_| style.width(Fixed(1)).height(Fixed(metrics.line_height)).background(theme.palette.primary.base.fill).floating(Floating({ target: Parent, config: { ..Element.default_floating_config, offset: { x: offset, y: 0 }, attach_points: { element: LeftCenter, target: LeftCenter }, capture: Passthrough, clip_to: AttachedParent } })),
		},
		[],
	)
}

update_document : Document, Msg -> Document
update_document = |document, message| match message {
	TextInput(event) => apply_text_input(document, event)
	InsertLineBreak => insert(document, "\n")
	MoveUp => move_vertical(document, -1)
	MoveDown => move_vertical(document, 1)
	Pointer(event, advance, row_height) => document_at_pointer(document, event, advance, row_height)
}

apply_text_input : Document, Event.TextInputEvent -> Document
apply_text_input = |document, event| {
	var $next = document
	for key in event.keys {
		$next = apply_control($next, key)
	}
	inserted = codepoints_to_str(event.codepoints)
	if inserted.is_empty() $next else insert($next, inserted)
}

apply_control : Document, Event.TextControlKey -> Document
apply_control = |document, key| match key {
	KeyLeft => move_left(document)
	KeyRight => move_right(document)
	KeyHome => move_home(document)
	KeyEnd => move_end(document)
	KeyBackspace => delete(document, 1)
	KeyDelete => delete(document, -1)
}

insert : Document, Str -> Document
insert = |document, value| {
	offset = cursor_offset(document)
	bytes = document.content.to_utf8()
	before = bytes.sublist({ start: 0, len: offset })
	after = bytes.sublist({ start: offset, len: bytes.len() - offset })
	content = Str.from_utf8_lossy(before.concat(value.to_utf8()).concat(after))
	refresh(content, document.language, offset + value.count_utf8_bytes())
}

delete : Document, I64 -> Document
delete = |document, amount| {
	offset = cursor_offset(document)
	bytes = document.content.to_utf8()
	if amount > 0 {
		if offset == 0 document else {
			start = offset - 1
			before = bytes.sublist({ start: 0, len: start })
			after = bytes.sublist({ start: offset, len: bytes.len() - offset })
			refresh(Str.from_utf8_lossy(before.concat(after)), document.language, start)
		}
	} else if offset >= bytes.len() document else {
		before = bytes.sublist({ start: 0, len: offset })
		after = bytes.sublist({ start: offset + 1, len: bytes.len() - offset - 1 })
		refresh(Str.from_utf8_lossy(before.concat(after)), document.language, offset)
	}
}

move_left : Document -> Document
move_left = |document| {
	offset = cursor_offset(document)
	set_cursor(document, if offset > 0 offset - 1 else 0)
}

move_right : Document -> Document
move_right = |document| {
	offset = cursor_offset(document)
	set_cursor(document, if offset < document.content.count_utf8_bytes() offset + 1 else offset)
}

move_home : Document -> Document
move_home = |document| set_cursor(document, line_start(document.lines, document.cursor.line))

move_end : Document -> Document
move_end = |document| set_cursor(document, line_start(document.lines, document.cursor.line) + line_text(line_at(document.lines, document.cursor.line)).count_utf8_bytes())

move_vertical : Document, I64 -> Document
move_vertical = |document, delta| {
	line = document.cursor.line
	target = if delta < 0 { if line > 0 line - 1 else 0 } else if line + 1 < document.lines.len() line + 1 else line
	column = document.cursor.column
	length = line_text(line_at(document.lines, target)).count_utf8_bytes()
	{ ..document, cursor: { line: target, column: if column < length column else length } }
}

refresh : Str, [HtmlLanguage, PlainText], U64 -> Document
refresh = |content, language, cursor| {
	lines = match language { HtmlLanguage => Html.highlight(content), PlainText => Html.plain(content) }
	line = line_index(lines, cursor, 0, 0)
	{ content, language, lines, cursor: { line, column: cursor - line_start(lines, line) } }
}

document_at_pointer : Document, Event.PointerEvent, F32, F32 -> Document
document_at_pointer = |document, event, advance, row_height| if !event.mouse.left {
	document
} else {
	line_guess = line_from_pointer(event.position.y - event.target.bounds.y, 0, row_height)
	line = if line_guess < document.lines.len() line_guess else document.lines.len() - 1
	line_value = line_text(line_at(document.lines, line))
	line_length = line_value.count_utf8_bytes()
	column = pointer_column(event, line_length, advance)
	{ ..document, cursor: { line, column } }
}

cursor_offset : Document -> U64
cursor_offset = |document| line_start(document.lines, document.cursor.line) + document.cursor.column

set_cursor : Document, U64 -> Document
set_cursor = |document, offset| {
	line = line_index(document.lines, offset, 0, 0)
	{ ..document, cursor: { line, column: offset - line_start(document.lines, line) } }
}

line_from_pointer : F32, U64, F32 -> U64
line_from_pointer = |relative_y, index, row_height| {
	if relative_y < row_height or relative_y < 0 {
		index
	} else {
		line_from_pointer(relative_y - row_height, index + 1, row_height)
	}
}

pointer_column : Event.PointerEvent, U64, F32 -> U64
pointer_column = |event, line_length, advance| {
	# The line number gutter is 58px wide. Since the editor is ASCII-only and
	# uses a monospace font, each character occupies the same measured advance.
	content_x = event.position.x - event.target.bounds.x - 58
	if content_x <= 0 or line_length == 0 {
		0
	} else {
		column = (content_x / advance).round_to_u64_try().ok_or(0)
		if column < line_length column else line_length
	}
}

line_index : List(Html.Line), U64, U64, U64 -> U64
line_index = |lines, cursor, index, start| {
	if index + 1 >= lines.len() or cursor < start + line_text(line_at(lines, index)).count_utf8_bytes() + 1 index else line_index(lines, cursor, index + 1, start + line_text(line_at(lines, index)).count_utf8_bytes() + 1)
}

line_start : List(Html.Line), U64 -> U64
line_start = |lines, target| line_start_at(lines, target, 0, 0)

line_start_at : List(Html.Line), U64, U64, U64 -> U64
line_start_at = |lines, target, index, start| if index >= target or index >= lines.len() start else line_start_at(lines, target, index + 1, start + line_text(line_at(lines, index)).count_utf8_bytes() + 1)

line_at : List(Html.Line), U64 -> Html.Line
line_at = |lines, index| lines.get(index).ok_or({ spans: [] })

line_text : Html.Line -> Str
line_text = |line| line.spans.fold("", |content, span| Str.concat(content, span.text))

span_view : Html.Span, CodeMetrics -> View(Msg)
span_view = |span, metrics| {
	width = span.text.count_utf8_bytes().to_f32() * metrics.glyph_advance
	box({ style: |_| style.width(Fixed(width)).height(Fixed(metrics.line_height)).font_color(token_color(span.kind)).text_wrap(None).child_align({ x: Start, y: Center }).cursor(IBeam) }, [text(span.text)])
}

code_line_height : Font -> F32
code_line_height = |font| TextMeasure.measure_line("M", { font_size: 14, spacing: 0 }, font).height

glyph_advance : Font -> F32
glyph_advance = |font| TextMeasure.measure_line(
	"M",
	{ font_size: 14, spacing: 0 },
	font,
).width

token_color : Html.TokenKind -> Color
token_color = |kind| match kind {
	TextToken => theme.palette.surface.base.content
	Punctuation => theme.palette.text.muted
	TagName => theme.palette.primary.base.fill
	AttributeName => theme.palette.primary.strong.fill
	AttributeValue => theme.palette.success.base.fill
	Comment => theme.palette.text.muted
	Doctype => theme.palette.primary.base.fill
	Entity => theme.palette.warning.base.fill
}

test_document : Str -> Document
test_document = |content| { content, language: PlainText, lines: Html.plain(content), cursor: { line: 0, column: 0 } }

expect {
	inserted = insert(test_document("ab"), "X")
	inserted.content == "Xab"
}

expect {
	document = { ..test_document("one\ntwo"), cursor: { line: 1, column: 0 } }
	updated = insert(document, "!")
	updated.content == "one\n!two" and updated.cursor.line == 1 and updated.cursor.column == 1
}

expect {
	document = { ..test_document("abc"), cursor: { line: 0, column: 2 } }
	delete(document, 1).content == "ac"
}

expect {
	document = { ..test_document("one\ntwo\nthree"), cursor: { line: 0, column: 1 } }
	first = move_vertical(document, 1)
	second = move_vertical(first, 1)
	first.cursor.line == 1 and first.cursor.column == 1 and second.cursor.line == 2 and second.cursor.column == 1
}
