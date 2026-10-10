## A small multi-line code editor: one buffer, one cursor, highlighted spans.
##
## Unlike the generic single-line TextInput widget, this component owns the
## editing surface. Text is rendered as syntax-colored spans and input events
## mutate the document cursor directly.
import rr.Font
import rr.Devices
import rr.Keys
import tc.Color
import tc.Element exposing [box, style, text]
import tc.Event
import tc.Program exposing [View]
import tc.TextMeasure
import tc.Unicode exposing [codepoints_to_str]

import ../Theme exposing [theme]
import ../syntax/Html

Cursor := { line : U64, column : U64 }.{
	is_eq : Cursor, Cursor -> Bool
	is_eq = |a, b| a.line == b.line and a.column == b.column
}

CodeMetrics := { glyph_advance : F32, line_height : F32 }

Document := {
	content : Str,
	language : [HtmlLanguage, PlainText],
	lines : List(Html.Line),
	cursor : Cursor,
	anchor : Cursor,
}

Msg : [
	TextInput(Event.TextInputEvent),
	InsertLineBreak,
	MoveLeft(Bool),
	MoveRight(Bool),
	MoveHome(Bool),
	MoveEnd(Bool),
	MoveUp(Bool),
	MoveDown(Bool),
	DeleteBackward,
	DeleteForward,
	PointerStart(Event.DragEvent, F32, F32),
	PointerMove(Event.DragEvent, F32, F32),
]

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
				OnInput(Box.box(editor_input_messages)),
				OnDragStart(Box.box(|event| PointerStart(event, metrics.glyph_advance, metrics.line_height))),
				OnDragMove(Box.box(|event| PointerMove(event, metrics.glyph_advance, metrics.line_height))),
				OnDragEnd(Box.box(|event| PointerMove(event, metrics.glyph_advance, metrics.line_height))),
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
			line_code(line, index, document, metrics),
			if active {
				cursor_view(local_cursor, metrics)
			} else box({ style: |_| style.width(Fixed(0)).height(Fixed(0)) }, []),
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

line_code : Html.Line, U64, Document, CodeMetrics -> View(Msg)
line_code = |line, index, document, metrics| {
	start = line_start(document.lines, index)
	selection = selection_range(document)
	segments = selected_segments(line, start, selection)
	content_end = start + line_text(line).count_utf8_bytes()
	newline_selected = index + 1 < document.lines.len() and selection.start <= content_end and selection.end > content_end
	views = segments.map(|segment| span_view(segment, metrics))
	children = if newline_selected {
		views.append(selection_gap_view(metrics))
	} else {
		views
	}
	box(
		{
			style: |_| style.width(Grow({ min: 642 })).height(Fixed(metrics.line_height)).direction(Row).child_align({ x: Start, y: Center }).cursor(IBeam),
		},
		children,
	)
}

selected_segments : Html.Line, U64, { start : U64, end : U64 } -> List({ text : Str, kind : Html.TokenKind, selected : Bool })
selected_segments = |line, line_start_offset, selection| {
	var $segments = []
	var $span_start = line_start_offset
	for span in line.spans {
		span_length = span.text.count_utf8_bytes()
		span_end = $span_start + span_length
		overlap_start = U64.max($span_start, U64.min(span_end, selection.start))
		overlap_end = U64.max($span_start, U64.min(span_end, selection.end))
		if overlap_end <= overlap_start {
			$segments = $segments.append({ text: span.text, kind: span.kind, selected: Bool.False })
		} else {
			$segments = append_segment($segments, span, 0, overlap_start - $span_start, Bool.False)
			$segments = append_segment($segments, span, overlap_start - $span_start, overlap_end - overlap_start, Bool.True)
			$segments = append_segment($segments, span, overlap_end - $span_start, span_end - overlap_end, Bool.False)
		}
		$span_start = span_end
	}
	$segments
}

append_segment : List({ text : Str, kind : Html.TokenKind, selected : Bool }), Html.Span, U64, U64, Bool -> List({ text : Str, kind : Html.TokenKind, selected : Bool })
append_segment = |segments, span, start, length, selected| if length == 0 {
	segments
} else {
	text = Str.from_utf8_lossy(span.text.to_utf8().sublist({ start, len: length }))
	segments.append({ text, kind: span.kind, selected })
}

selection_gap_view : CodeMetrics -> View(Msg)
selection_gap_view = |metrics| box(
	{
		style: |_| style.width(Fixed(metrics.glyph_advance)).height(Fixed(metrics.line_height)).background(theme.palette.selected(theme.palette.surface.base).fill),
	},
	[],
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
	MoveLeft(selecting) => move_left(document, selecting)
	MoveRight(selecting) => move_right(document, selecting)
	MoveHome(selecting) => move_home(document, selecting)
	MoveEnd(selecting) => move_end(document, selecting)
	MoveUp(selecting) => move_vertical(document, -1, selecting)
	MoveDown(selecting) => move_vertical(document, 1, selecting)
	DeleteBackward => delete(document, 1)
	DeleteForward => delete(document, -1)
	PointerStart(event, advance, row_height) => start_selection_at_pointer(document, event, advance, row_height)
	PointerMove(event, advance, row_height) => extend_selection_to_pointer(document, event, advance, row_height)
}

apply_text_input : Document, Event.TextInputEvent -> Document
apply_text_input = |document, event| {
	inserted = codepoints_to_str(event.codepoints)
	if inserted.is_empty() document else insert(document, inserted)
}

editor_input_messages : Devices.Snapshot, Event.InputContext -> List(Msg)
editor_input_messages = |input, context| if !context.focused {
	[]
} else {
	selecting = Keys.key_down(input, KeyLeftShift) or Keys.key_down(input, KeyRightShift)
	var $messages = []
	if Keys.key_pressed(input, KeyLeft) {
		$messages = $messages.append(MoveLeft(selecting))
	}
	if Keys.key_pressed(input, KeyRight) {
		$messages = $messages.append(MoveRight(selecting))
	}
	if Keys.key_pressed(input, KeyHome) {
		$messages = $messages.append(MoveHome(selecting))
	}
	if Keys.key_pressed(input, KeyEnd) {
		$messages = $messages.append(MoveEnd(selecting))
	}
	if Keys.key_pressed(input, KeyUp) {
		$messages = $messages.append(MoveUp(selecting))
	}
	if Keys.key_pressed(input, KeyDown) {
		$messages = $messages.append(MoveDown(selecting))
	}
	if Keys.key_pressed(input, KeyBackspace) {
		$messages = $messages.append(DeleteBackward)
	}
	if Keys.key_pressed(input, KeyDelete) {
		$messages = $messages.append(DeleteForward)
	}
	if Keys.key_pressed(input, KeyEnter) {
		$messages = $messages.append(InsertLineBreak)
	}
	$messages
}

insert : Document, Str -> Document
insert = |document, value| {
	selection = selection_range(document)
	bytes = document.content.to_utf8()
	before = bytes.sublist({ start: 0, len: selection.start })
	after = bytes.sublist({ start: selection.end, len: bytes.len() - selection.end })
	content = Str.from_utf8_lossy(before.concat(value.to_utf8()).concat(after))
	refresh(content, document.language, selection.start + value.count_utf8_bytes())
}

delete : Document, I64 -> Document
delete = |document, amount| {
	selection = selection_range(document)
	bytes = document.content.to_utf8()
	if selection.start < selection.end {
		before = bytes.sublist({ start: 0, len: selection.start })
		after = bytes.sublist({ start: selection.end, len: bytes.len() - selection.end })
		refresh(Str.from_utf8_lossy(before.concat(after)), document.language, selection.start)
	} else if amount > 0 {
		offset = selection.start
		if offset == 0 document else {
			start = offset - 1
			before = bytes.sublist({ start: 0, len: start })
			after = bytes.sublist({ start: offset, len: bytes.len() - offset })
			refresh(Str.from_utf8_lossy(before.concat(after)), document.language, start)
		}
	} else if selection.start >= bytes.len() document else {
		offset = selection.start
		before = bytes.sublist({ start: 0, len: offset })
		after = bytes.sublist({ start: offset + 1, len: bytes.len() - offset - 1 })
		refresh(Str.from_utf8_lossy(before.concat(after)), document.language, offset)
	}
}

move_left : Document, Bool -> Document
move_left = |document, selecting| {
	offset = cursor_offset(document)
	selection = selection_range(document)
	target = if !selecting and selection.start < selection.end selection.start else if offset > 0 offset - 1 else 0
	set_cursor(document, target, selecting)
}

move_right : Document, Bool -> Document
move_right = |document, selecting| {
	offset = cursor_offset(document)
	selection = selection_range(document)
	target = if !selecting and selection.start < selection.end selection.end else if offset < document.content.count_utf8_bytes() offset + 1 else offset
	set_cursor(document, target, selecting)
}

move_home : Document, Bool -> Document
move_home = |document, selecting| set_cursor(document, line_start(document.lines, document.cursor.line), selecting)

move_end : Document, Bool -> Document
move_end = |document, selecting| set_cursor(document, line_start(document.lines, document.cursor.line) + line_text(line_at(document.lines, document.cursor.line)).count_utf8_bytes(), selecting)

move_vertical : Document, I64, Bool -> Document
move_vertical = |document, delta, selecting| {
	line = document.cursor.line
	target = if delta < 0 {
		if line > 0 line - 1 else 0
	} else if line + 1 < document.lines.len() line + 1 else line
	column = document.cursor.column
	length = line_text(line_at(document.lines, target)).count_utf8_bytes()
	set_cursor(document, line_start(document.lines, target) + U64.min(column, length), selecting)
}

refresh : Str, [HtmlLanguage, PlainText], U64 -> Document
refresh = |content, language, cursor| {
	lines = match language {
		HtmlLanguage => Html.highlight(content)
		PlainText => Html.plain(content)
	}
	line = line_index(lines, cursor, 0, 0)
	position = { line, column: cursor - line_start(lines, line) }
	{ content, language, lines, cursor: position, anchor: position }
}

start_selection_at_pointer : Document, Event.DragEvent, F32, F32 -> Document
start_selection_at_pointer = |document, event, advance, row_height| {
	position = position_at_pointer(document, event.position, event.target.bounds, advance, row_height)
	{ ..document, cursor: position, anchor: position }
}

extend_selection_to_pointer : Document, Event.DragEvent, F32, F32 -> Document
extend_selection_to_pointer = |document, event, advance, row_height| {
	{ ..document, cursor: position_at_pointer(document, event.position, event.target.bounds, advance, row_height) }
}

position_at_pointer : Document, Event.Point, Event.ElementBounds, F32, F32 -> Cursor
position_at_pointer = |document, pointer, bounds, advance, row_height| {
	line_guess = line_from_pointer(pointer.y - bounds.y, 0, row_height)
	line = if line_guess < document.lines.len() line_guess else document.lines.len() - 1
	line_value = line_text(line_at(document.lines, line))
	line_length = line_value.count_utf8_bytes()
	column = pointer_column(pointer.x - bounds.x, line_length, advance)
	{ line, column }
}

cursor_offset : Document -> U64
cursor_offset = |document| line_start(document.lines, document.cursor.line) + document.cursor.column

set_cursor : Document, U64, Bool -> Document
set_cursor = |document, offset, selecting| {
	line = line_index(document.lines, offset, 0, 0)
	position = { line, column: offset - line_start(document.lines, line) }
	{ ..document, cursor: position, anchor: if selecting document.anchor else position }
}

selection_range : Document -> { start : U64, end : U64 }
selection_range = |document| {
	cursor = cursor_offset(document)
	anchor = line_start(document.lines, document.anchor.line) + document.anchor.column
	{ start: U64.min(cursor, anchor), end: U64.max(cursor, anchor) }
}

line_from_pointer : F32, U64, F32 -> U64
line_from_pointer = |relative_y, index, row_height| {
	if relative_y < row_height or relative_y < 0 {
		index
	} else {
		line_from_pointer(relative_y - row_height, index + 1, row_height)
	}
}

pointer_column : F32, U64, F32 -> U64
pointer_column = |relative_x, line_length, advance| {
	# The line number gutter is 58px wide. Since the editor is ASCII-only and
	# uses a monospace font, each character occupies the same measured advance.
	content_x = relative_x - 58
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

span_view : { text : Str, kind : Html.TokenKind, selected : Bool }, CodeMetrics -> View(Msg)
span_view = |span, metrics| {
	width = span.text.count_utf8_bytes().to_f32() * metrics.glyph_advance
	box({ style: |_| style.width(Fixed(width)).height(Fixed(metrics.line_height)).font_color(token_color(span.kind)).text_wrap(None).child_align({ x: Start, y: Center }).cursor(IBeam).background(if span.selected theme.palette.selected(theme.palette.surface.base).fill else Color.transparent) }, [text(span.text)])
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
test_document = |content| { content, language: PlainText, lines: Html.plain(content), cursor: { line: 0, column: 0 }, anchor: { line: 0, column: 0 } }

expect {
	inserted = insert(test_document("ab"), "X")
	inserted.content == "Xab"
}

expect {
	document = { ..test_document("one\ntwo"), cursor: { line: 1, column: 0 }, anchor: { line: 1, column: 0 } }
	updated = insert(document, "!")
	updated.content == "one\n!two" and updated.cursor.line == 1 and updated.cursor.column == 1
}

expect {
	document = { ..test_document("abc"), cursor: { line: 0, column: 2 }, anchor: { line: 0, column: 2 } }
	delete(document, 1).content == "ac"
}

expect {
	document = { ..test_document("one\ntwo\nthree"), cursor: { line: 0, column: 1 }, anchor: { line: 0, column: 1 } }
	first = move_vertical(document, 1, Bool.False)
	second = move_vertical(first, 1, Bool.False)
	first.cursor.line == 1 and first.cursor.column == 1 and second.cursor.line == 2 and second.cursor.column == 1
}

expect {
	document = { ..test_document("abcd"), cursor: { line: 0, column: 1 }, anchor: { line: 0, column: 3 } }
	updated = insert(document, "X")
	updated.content == "aXd" and updated.cursor.column == 2 and updated.anchor == updated.cursor
}

expect {
	document = { ..test_document("one\ntwo"), cursor: { line: 0, column: 2 }, anchor: { line: 1, column: 1 } }
	updated = delete(document, 1)
	updated.content == "onwo" and updated.cursor == { line: 0, column: 2 } and updated.anchor == updated.cursor
}

expect {
	document = { ..test_document("abcd"), cursor: { line: 0, column: 1 }, anchor: { line: 0, column: 1 } }
	selected = move_right(document, Bool.True)
	collapsed = move_left(selected, Bool.False)
	selected.cursor.column == 2 and selected.anchor.column == 1 and collapsed.cursor.column == 1 and collapsed.anchor == collapsed.cursor
}

expect {
	input = Devices.none.with_key_down(KeyLeftShift).with_key_pressed(KeyRight)
	context : Event.InputContext
	context = { bounds: { x: 0, y: 0, width: 0, height: 0 }, focused: Bool.True }
	match editor_input_messages(input, context) {
		[MoveRight(selecting)] => selecting
		_ => Bool.False
	}
}

expect {
	input = Devices.none.with_key_pressed(KeyRight)
	context : Event.InputContext
	context = { bounds: { x: 0, y: 0, width: 0, height: 0 }, focused: Bool.False }
	editor_input_messages(input, context).is_empty()
}

expect {
	line : Html.Line
	line = { spans: [{ text: "abcd", kind: TextToken }] }
	match selected_segments(line, 10, { start: 11, end: 13 }) {
		[
			{ text: "a", selected: Bool.False, .. },
			{ text: "bc", selected: Bool.True, .. },
			{ text: "d", selected: Bool.False, .. },
		] => Bool.True
		_ => Bool.False
	}
}
