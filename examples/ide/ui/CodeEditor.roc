## A small multi-line code editor: one buffer, one cursor, highlighted spans.
##
## Unlike the generic single-line TextInput widget, this component owns the
## editing surface. The buffer is drawn immediately into a single canvas leaf:
## only the visible rows become draw work, and a color run costs one text draw
## regardless of how many spans produced it.
import rr.Font
import rr.Devices
import rr.Draw
import rr.Keys
import tc.Color
import tc.Element exposing [box, canvas, style]
import tc.Event
import tc.Program exposing [View]
import tc.Renderer
import tc.TextMeasure
import tc.Unicode exposing [codepoints_to_str]

import ../Theme exposing [theme]
import ../syntax/Css
import ../syntax/Html
import ../syntax/Syntax

font_size : F32
font_size = 14

spacing : F32
spacing = 0

gutter_width : F32
gutter_width = 58

gutter_text_right_pad : F32
gutter_text_right_pad = 12

Cursor := { line : U64, column : U64 }.{
	is_eq : Cursor, Cursor -> Bool
	is_eq = |a, b| a.line == b.line and a.column == b.column
}

FontMetrics := { glyph_advance : F32, line_height : F32 }

Document := {
	content : Str,
	language : [HtmlLanguage, CssLanguage, PlainText],
	lines : List(Syntax.Line),
	line_starts : List(U64),
	line_lengths : List(U64),
	cursor : Cursor,
	anchor : Cursor,
	scroll_y : F32,
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
	PointerStart(Event.DragEvent),
	PointerMove(Event.DragEvent),
	ScrollBy(F32, F32),
]

CodeEditor := [].{
	view : Font, FontMetrics, Document -> View(Msg)
	view = view_editor

	update : FontMetrics, Document, Msg -> Document
	update = update_document

	## Measure the fixed code metrics once for a font.
	metrics : Font -> FontMetrics
	metrics = metrics_for

	## Compute line start offsets and byte lengths for highlighted lines.
	line_geometry : List(Syntax.Line) -> { starts : List(U64), lengths : List(U64) }
	line_geometry = line_geometry_for
}

metrics_for : Font -> FontMetrics
metrics_for = |font| { glyph_advance: glyph_advance(font), line_height: code_line_height(font) }

line_geometry_for : List(Syntax.Line) -> { starts : List(U64), lengths : List(U64) }
line_geometry_for = |lines| {
	var $starts = []
	var $lengths = []
	var $offset = 0
	for line in lines {
		length = line_text(line).count_utf8_bytes()
		$starts = $starts.append($offset)
		$lengths = $lengths.append(length)
		$offset = $offset + length + 1
	}
	{ starts: $starts, lengths: $lengths }
}

view_editor : Font, FontMetrics, Document -> View(Msg)
view_editor = |font, metrics, document| {
	selection = selection_range(document)
	box(
		{
			id: Id("code-editor"),
			style: |_| style
				.width(Grow({}))
				.height(Grow({}))
				.background(theme.palette.surface.base.fill)
				.cursor(IBeam)
				.overflow(Hidden, Hidden),
			events: [
				OnTextInput(Box.box(|event| TextInput(event))),
				OnInput(Box.box(|input, context| editor_input_messages(input, context, metrics))),
				OnDragStart(Box.box(|event| PointerStart(event))),
				OnDragMove(Box.box(|event| PointerMove(event))),
				OnDragEnd(Box.box(|event| PointerMove(event))),
			],
		},
		[
			canvas(|frame, bounds| draw_editor!(frame, bounds, font, metrics, document, selection)),
		],
	)
}

draw_editor! : Draw.Frame, Renderer.Bounds, Font, FontMetrics, Document, { start : U64, end : U64 } => Try({}, Draw.ScopeError)
draw_editor! = |frame, bounds, font, metrics, document, selection| {
	advance = metrics.glyph_advance
	line_h = metrics.line_height
	scroll_y = document.scroll_y
	origin_x = bounds.position.x
	origin_y = bounds.position.y
	viewport_w = bounds.size.w
	viewport_h = bounds.size.h
	line_count = document.lines.len()

	fill_rect! = |x, y, rect_w, rect_h, color| frame.rectangle!({ x, y, width: rect_w, height: rect_h, style: Draw.filled(color) })
	draw_text! = |x, y, content, color| frame.text!({ pos: { x, y }, text: content, size: font_size, spacing: spacing, color, font })

	active_color = theme.palette.surface.base.content.with_alpha(12).to_rrt()
	selection_color = theme.palette.selected(theme.palette.surface.base).fill.to_rrt()
	gutter_color = theme.palette.text.muted.to_rrt()
	cursor_color = theme.palette.primary.base.fill.to_rrt()

	first = if line_count == 0 {
		0
	} else {
		guess = F32.to_u64_try(scroll_y / line_h) ?? 0
		if guess < line_count guess else line_count - 1
	}
	rows = (F32.ceiling_to_u64_try(viewport_h / line_h) ?? 0) + 1

	var $i = first
	while $i < line_count and $i < first + rows {
		row_y = origin_y + $i.to_f32() * line_h - scroll_y
		line = document.lines.get($i).ok_or({ spans: [] })
		active = document.cursor.line == $i

		if active {
			fill_rect!(origin_x, row_y, viewport_w, line_h, active_color)
		}

		line_off = line_start(document.line_starts, $i)
		line_len = line_length(document, $i)
		content_end = line_off + line_len
		if selection.end > selection.start {
			sel_start = U64.max(selection.start, line_off)
			sel_end = U64.min(selection.end, content_end)
			if sel_end > sel_start {
				start_col = sel_start - line_off
				run = sel_end - sel_start
				fill_rect!(origin_x + gutter_width + start_col.to_f32() * advance, row_y, run.to_f32() * advance, line_h, selection_color)
			}
			if $i + 1 < line_count and selection.start <= content_end and selection.end > content_end {
				fill_rect!(origin_x + gutter_width + line_len.to_f32() * advance, row_y, advance, line_h, selection_color)
			}
		}

		number = ($i + 1).to_str()
		number_w = number.count_utf8_bytes().to_f32() * advance
		draw_text!(origin_x + gutter_width - gutter_text_right_pad - number_w, row_y, number, gutter_color)

		var $si = 0
		var $x = origin_x + gutter_width
		span_count = line.spans.len()
		while $si < span_count {
			span = line.spans.get($si).ok_or({ text: "", kind: TextToken })
			color = token_color(span.kind)
			var $run = span.text
			var $sj = $si + 1
			while $sj < span_count and token_color(line.spans.get($sj).ok_or({ text: "", kind: TextToken }).kind) == color {
				$run = Str.concat($run, line.spans.get($sj).ok_or({ text: "", kind: TextToken }).text)
				$sj = $sj + 1
			}
			draw_text!($x, row_y, $run, color.to_rrt())
			$x = $x + $run.count_utf8_bytes().to_f32() * advance
			$si = $sj
		}

		if active {
			fill_rect!(origin_x + gutter_width + document.cursor.column.to_f32() * advance, row_y, 1, line_h, cursor_color)
		}

		$i = $i + 1
	}
	Ok({})
}

update_document : FontMetrics, Document, Msg -> Document
update_document = |metrics, document, message| match message {
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
	PointerStart(event) => start_selection_at_pointer(document, event, metrics)
	PointerMove(event) => extend_selection_to_pointer(document, event, metrics)
	ScrollBy(delta, viewport_h) => scroll_document(document, delta, viewport_h, metrics)
}

scroll_document : Document, F32, F32, FontMetrics -> Document
scroll_document = |document, delta, viewport_h, metrics| {
	content_h = document.lines.len().to_f32() * metrics.line_height
	max_scroll = F32.max(content_h - viewport_h, 0)
	next = F32.min(max_scroll, F32.max(0, document.scroll_y + delta))
	{ ..document, scroll_y: next }
}

apply_text_input : Document, Event.TextInputEvent -> Document
apply_text_input = |document, event| {
	inserted = codepoints_to_str(event.codepoints)
	if inserted.is_empty() document else insert(document, inserted)
}

editor_input_messages : Devices.Snapshot, Event.InputContext, FontMetrics -> List(Msg)
editor_input_messages = |input, context, metrics| {
	keyboard = if context.focused keyboard_messages(input) else []
	over_editor = context.bounds.contains(input.mouse.position())
	wheel = input.mouse.wheel_delta().y
	if over_editor and wheel != 0 {
		keyboard.append(ScrollBy(0 - wheel * metrics.line_height, context.bounds.height))
	} else {
		keyboard
	}
}

keyboard_messages : Devices.Snapshot -> List(Msg)
keyboard_messages = |input| {
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
	refresh(content, document.language, selection.start + value.count_utf8_bytes(), document.scroll_y)
}

delete : Document, I64 -> Document
delete = |document, amount| {
	selection = selection_range(document)
	bytes = document.content.to_utf8()
	if selection.start < selection.end {
		before = bytes.sublist({ start: 0, len: selection.start })
		after = bytes.sublist({ start: selection.end, len: bytes.len() - selection.end })
		refresh(Str.from_utf8_lossy(before.concat(after)), document.language, selection.start, document.scroll_y)
	} else if amount > 0 {
		offset = selection.start
		if offset == 0 document else {
			start = offset - 1
			before = bytes.sublist({ start: 0, len: start })
			after = bytes.sublist({ start: offset, len: bytes.len() - offset })
			refresh(Str.from_utf8_lossy(before.concat(after)), document.language, start, document.scroll_y)
		}
	} else if selection.start >= bytes.len() document else {
		offset = selection.start
		before = bytes.sublist({ start: 0, len: offset })
		after = bytes.sublist({ start: offset + 1, len: bytes.len() - offset - 1 })
		refresh(Str.from_utf8_lossy(before.concat(after)), document.language, offset, document.scroll_y)
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
move_home = |document, selecting| set_cursor(document, line_start(document.line_starts, document.cursor.line), selecting)

move_end : Document, Bool -> Document
move_end = |document, selecting| set_cursor(document, line_start(document.line_starts, document.cursor.line) + line_length(document, document.cursor.line), selecting)

move_vertical : Document, I64, Bool -> Document
move_vertical = |document, delta, selecting| {
	line = document.cursor.line
	target = if delta < 0 {
		if line > 0 line - 1 else 0
	} else if line + 1 < document.lines.len() line + 1 else line
	column = document.cursor.column
	length = line_length(document, target)
	set_cursor(document, line_start(document.line_starts, target) + U64.min(column, length), selecting)
}

refresh : Str, [HtmlLanguage, CssLanguage, PlainText], U64, F32 -> Document
refresh = |content, language, cursor, scroll_y| {
	lines = match language {
		HtmlLanguage => Html.highlight(content)
		CssLanguage => Css.highlight(content)
		PlainText => Syntax.plain(content)
	}
	geometry = line_geometry_for(lines)
	line = line_index(geometry.starts, cursor)
	position = { line, column: cursor - line_start(geometry.starts, line) }
	{ content, language, lines, line_starts: geometry.starts, line_lengths: geometry.lengths, cursor: position, anchor: position, scroll_y }
}

start_selection_at_pointer : Document, Event.DragEvent, FontMetrics -> Document
start_selection_at_pointer = |document, event, metrics| {
	position = position_at_pointer(document, event.position, event.target.bounds, metrics)
	{ ..document, cursor: position, anchor: position }
}

extend_selection_to_pointer : Document, Event.DragEvent, FontMetrics -> Document
extend_selection_to_pointer = |document, event, metrics| {
	{ ..document, cursor: position_at_pointer(document, event.position, event.target.bounds, metrics) }
}

position_at_pointer : Document, Event.Point, Event.ElementBounds, FontMetrics -> Cursor
position_at_pointer = |document, pointer, bounds, metrics| {
	relative_y = pointer.y - bounds.y + document.scroll_y
	line_guess = line_from_pointer(relative_y, 0, metrics.line_height)
	line = if line_guess < document.lines.len() line_guess else document.lines.len() - 1
	length = line_length(document, line)
	column = pointer_column(pointer.x - bounds.x, length, metrics.glyph_advance)
	{ line, column }
}

cursor_offset : Document -> U64
cursor_offset = |document| line_start(document.line_starts, document.cursor.line) + document.cursor.column

set_cursor : Document, U64, Bool -> Document
set_cursor = |document, offset, selecting| {
	line = line_index(document.line_starts, offset)
	position = { line, column: offset - line_start(document.line_starts, line) }
	{ ..document, cursor: position, anchor: if selecting document.anchor else position }
}

selection_range : Document -> { start : U64, end : U64 }
selection_range = |document| {
	cursor = cursor_offset(document)
	anchor = line_start(document.line_starts, document.anchor.line) + document.anchor.column
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
pointer_column = |relative_x, length, advance| {
	# The line number gutter is 58px wide. Since the editor is ASCII-only and
	# uses a monospace font, each character occupies the same measured advance.
	content_x = relative_x - 58
	if content_x <= 0 or length == 0 {
		0
	} else {
		column = (content_x / advance).round_to_u64_try().ok_or(0)
		if column < length column else length
	}
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

line_start : List(U64), U64 -> U64
line_start = |starts, target| starts.get(target).ok_or(0)

line_length : Document, U64 -> U64
line_length = |document, index| document.line_lengths.get(index).ok_or(0)

line_text : Syntax.Line -> Str
line_text = |line| line.spans.fold("", |content, span| Str.concat(content, span.text))

code_line_height : Font -> F32
code_line_height = |font| TextMeasure.measure_line("M", { font_size: font_size, spacing: spacing }, font).height

glyph_advance : Font -> F32
glyph_advance = |font| TextMeasure.measure_line(
	"M",
	{ font_size: font_size, spacing: spacing },
	font,
).width

token_color : Syntax.TokenKind -> Color
token_color = |kind| match kind {
	TextToken => theme.palette.surface.base.content
	Punctuation => theme.palette.text.muted
	TagName => theme.palette.primary.base.fill
	AttributeName => theme.palette.primary.strong.fill
	AttributeValue => theme.palette.success.base.fill
	Comment => theme.palette.text.muted
	Doctype => theme.palette.primary.base.fill
	Entity => theme.palette.warning.base.fill
	CssSelector => theme.palette.primary.base.fill
	CssPropertyName => theme.palette.primary.strong.fill
	CssPropertyValue => theme.palette.success.base.fill
	CssAtRule => theme.palette.warning.base.fill
}

test_document : Str -> Document
test_document = |content| {
	lines = Syntax.plain(content)
	geometry = line_geometry_for(lines)
	{ content, language: PlainText, lines, line_starts: geometry.starts, line_lengths: geometry.lengths, cursor: { line: 0, column: 0 }, anchor: { line: 0, column: 0 }, scroll_y: 0 }
}

test_metrics : FontMetrics
test_metrics = { glyph_advance: 1, line_height: 1 }

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
	document = test_document("one\ntwo\nthree")
	scrolled = scroll_document(document, 100, 10, { glyph_advance: 1, line_height: 10 })
	scrolled.scroll_y == 20
}

expect {
	document = test_document("one\ntwo\nthree")
	scrolled = scroll_document(document, -50, 10, { glyph_advance: 1, line_height: 10 })
	scrolled.scroll_y == 0
}

expect {
	input = Devices.none.with_key_down(KeyLeftShift).with_key_pressed(KeyRight)
	context : Event.InputContext
	context = { bounds: { x: 0, y: 0, width: 0, height: 0 }, focused: Bool.True }
	match editor_input_messages(input, context, test_metrics) {
		[MoveRight(selecting)] => selecting
		_ => Bool.False
	}
}

expect {
	input = Devices.none.with_key_pressed(KeyRight)
	context : Event.InputContext
	context = { bounds: { x: 0, y: 0, width: 0, height: 0 }, focused: Bool.False }
	editor_input_messages(input, context, test_metrics).is_empty()
}
