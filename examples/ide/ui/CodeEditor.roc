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

Document := {
	content : Str,
	language : [HtmlLanguage, PlainText],
	lines : List(Html.Line),
	cursor_line : U64,
	cursor : U64,
}

Msg : [TextInput(Event.TextInputEvent), Key(Keys.Key), Pointer(Event.PointerEvent)]

CodeEditor := [].{
	view : Font, Document -> View(Msg)
	view = view_editor

	update : Document, Msg -> Document
	update = update_document
}

view_editor : Font, Document -> View(Msg)
view_editor = |font, document| box(
	{
		id: Id("code-editor"),
		style: |_| style
			.width(Grow({}))
			.height(Grow({}))
			.background(theme.palette.surface.base.fill)
			.font_family(font)
			.font_size(14)
			.spacing(0)
			.overflow(Scroll, Scroll)
			.child_align({ x: Start, y: Start }),
		events: [
			OnTextInput(Box.box(|event| TextInput(event))),
			OnKeyPressed(KeyEnter, Key(KeyEnter)),
			OnKeyPressed(KeyUp, Key(KeyUp)),
			OnKeyPressed(KeyDown, Key(KeyDown)),
			OnPointer(Box.box(|event| Pointer(event))),
		],
	},
	[
		box(
			{ style: |_| style.width(Fit({ min: 700 })).height(Fit({})).direction(Col).child_align({ x: Start, y: Start }) },
			document.lines.map_with_index(|line, index| line_view(font, line, index, document)),
		),
	],
)

line_view : Font, Html.Line, U64, Document -> View(Msg)
line_view = |font, line, index, document| {
	start = line_start(document.lines, index)
	active = document.cursor_line == index
	local_cursor = if document.cursor >= start document.cursor - start else 0
	box(
		{
			id: IdI("code-line", index),
			style: |_| style.width(Fit({ min: 700 })).height(Fixed(22)).direction(Row).child_align({ x: Start, y: Center }).background(if active theme.palette.surface.base.content.with_alpha(12) else theme.palette.surface.base.fill),
		},
		[
			box(
				{ style: |_| style.width(Fixed(58)).height(Fixed(22)).pad(0, theme.gap + theme.gap / 2, 0, theme.gap / 2).font_color(theme.palette.text.muted).text_align(Right).text_wrap(None).child_align({ x: End, y: Center }) },
				[text((index + 1).to_str())],
			),
			box(
				{ style: |_| style.width(Fit({ min: 642 })).height(Fixed(22)).direction(Row).child_align({ x: Start, y: Center }) },
				line.spans.map(|span| span_view(font, span)),
			),
			if active { cursor_view(font, local_cursor) } else box({ style: |_| style.width(Fixed(0)).height(Fixed(0)) }, []),
		],
	)
}

cursor_view : Font, U64 -> View(Msg)
cursor_view = |font, cursor| {
	offset = cursor.to_f32() * glyph_advance(font) + 58
	box(
		{
			style: |_| style.width(Fixed(1)).height(Fixed(18)).background(theme.palette.primary.base.fill).floating(Floating({ target: Parent, config: { ..Element.default_floating_config, offset: { x: offset, y: 0 }, attach_points: { element: LeftCenter, target: LeftCenter }, capture: Passthrough, clip_to: AttachedParent } })),
		},
		[],
	)
}

update_document : Document, Msg -> Document
update_document = |document, message| match message {
	TextInput(event) => apply_text_input(document, event)
	Key(key) => apply_key(document, key)
	Pointer(event) => document_at_pointer(document, event)
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

apply_key : Document, Keys.Key -> Document
apply_key = |document, key| match key {
	KeyEnter => insert(document, "\n")
	KeyBackspace => delete(document, 1)
	KeyDelete => delete(document, -1)
	KeyLeft => move_left(document)
	KeyRight => move_right(document)
	KeyHome => move_home(document)
	KeyEnd => move_end(document)
	KeyUp => move_vertical(document, -1)
	KeyDown => move_vertical(document, 1)
	_ => document
}

insert : Document, Str -> Document
insert = |document, value| {
	bytes = document.content.to_utf8()
	before = bytes.sublist({ start: 0, len: document.cursor })
	after = bytes.sublist({ start: document.cursor, len: bytes.len() - document.cursor })
	content = Str.from_utf8_lossy(before.concat(value.to_utf8()).concat(after))
	refresh(content, document.language, document.cursor + value.count_utf8_bytes())
}

delete : Document, I64 -> Document
delete = |document, amount| {
	bytes = document.content.to_utf8()
	if amount > 0 {
		if document.cursor == 0 document else {
			start = document.cursor - 1
			before = bytes.sublist({ start: 0, len: start })
			after = bytes.sublist({ start: document.cursor, len: bytes.len() - document.cursor })
			refresh(Str.from_utf8_lossy(before.concat(after)), document.language, start)
		}
	} else if document.cursor >= bytes.len() document else {
		before = bytes.sublist({ start: 0, len: document.cursor })
		after = bytes.sublist({ start: document.cursor + 1, len: bytes.len() - document.cursor - 1 })
		refresh(Str.from_utf8_lossy(before.concat(after)), document.language, document.cursor)
	}
}

move_left : Document -> Document
move_left = |document| { ..document, cursor: if document.cursor > 0 document.cursor - 1 else 0 }

move_right : Document -> Document
move_right = |document| { ..document, cursor: if document.cursor < document.content.count_utf8_bytes() document.cursor + 1 else document.cursor }

move_home : Document -> Document
move_home = |document| { ..document, cursor: line_start(document.lines, document.cursor_line) }

move_end : Document -> Document
move_end = |document| { ..document, cursor: line_start(document.lines, document.cursor_line) + line_text(line_at(document.lines, document.cursor_line)).count_utf8_bytes() }

move_vertical : Document, I64 -> Document
move_vertical = |document, delta| {
	line = document.cursor_line
	target = if delta < 0 { if line > 0 line - 1 else 0 } else if line + 1 < document.lines.len() line + 1 else line
	column = document.cursor - line_start(document.lines, line)
	start = line_start(document.lines, target)
	length = line_text(line_at(document.lines, target)).count_utf8_bytes()
	{ ..document, cursor_line: target, cursor: start + if column < length column else length }
}

refresh : Str, [HtmlLanguage, PlainText], U64 -> Document
refresh = |content, language, cursor| {
	lines = match language { HtmlLanguage => Html.highlight(content), PlainText => Html.plain(content) }
	line = line_index(lines, cursor, 0, 0)
	{ content, language, lines, cursor_line: line, cursor }
}

document_at_pointer : Document, Event.PointerEvent -> Document
document_at_pointer = |document, event| if !event.mouse.left {
	document
} else {
	line_guess = if event.position.y <= event.target.bounds.y 0 else ((event.position.y - event.target.bounds.y) / 22).round_to_u64_try().ok_or(0)
	line = if line_guess < document.lines.len() line_guess else document.lines.len() - 1
	{ ..document, cursor_line: line, cursor: line_start(document.lines, line) + line_text(line_at(document.lines, line)).count_utf8_bytes() }
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

span_view : Font, Html.Span -> View(Msg)
span_view = |font, span| {
	width = span.text.count_utf8_bytes().to_f32() * glyph_advance(font)
	box({ style: |_| style.width(Fixed(width)).height(Fixed(22)).font_color(token_color(span.kind)).text_wrap(None).child_align({ x: Start, y: Center }) }, [text(span.text)])
}

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
test_document = |content| { content, language: PlainText, lines: Html.plain(content), cursor_line: 0, cursor: 0 }

expect {
	inserted = insert(test_document("ab"), "X")
	inserted.content == "Xab"
}

expect {
	document = { ..test_document("one\ntwo"), cursor: 4, cursor_line: 1 }
	updated = insert(document, "!")
	updated.content == "one\n!two" and updated.cursor_line == 1
}

expect {
	document = { ..test_document("abc"), cursor: 2, cursor_line: 0 }
	delete(document, 1).content == "ac"
}

expect {
	document = { ..test_document("one\ntwo\nthree"), cursor: 1, cursor_line: 0 }
	first = move_vertical(document, 1)
	second = move_vertical(first, 1)
	first.cursor_line == 1 and first.cursor == 5 and second.cursor_line == 2 and second.cursor == 9
}
