## A small multi-line code editor view over a source-buffer snapshot.
##
## This component knows how to render generic semantic highlight ranges and
## translate interaction into edit intents. Language selection, text mutation,
## line geometry, and highlighting belong to Buffer.
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

import ../source/Buffer
import ../Theme exposing [theme]
import ../source/Syntax

font_size : F32
font_size = 14

spacing : F32
spacing = 0

gutter_width : F32
gutter_width = 58

gutter_text_right_pad : F32
gutter_text_right_pad = 12

FontMetrics := { glyph_advance : F32, line_height : F32 }

State := {
	cursor : U64,
	anchor : U64,
	scroll_y : F32,
}

Outcome := {
	state : State,
	edit : [NoEdit, Replace(Buffer.Edit)],
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
	view : Font, FontMetrics, Buffer, State -> View(Msg)
	view = view_editor

	update : FontMetrics, Buffer, State, Msg -> Outcome
	update = update_editor

	initial : State
	initial = { cursor: 0, anchor: 0, scroll_y: 0 }

	## Measure the fixed code metrics once for a font.
	metrics : Font -> FontMetrics
	metrics = metrics_for

	position : Buffer, State -> { line : U64, column : U64 }
	position = |buffer, editor| Buffer.position_at(buffer, editor.cursor)
}

metrics_for : Font -> FontMetrics
metrics_for = |font| { glyph_advance: glyph_advance(font), line_height: code_line_height(font) }

view_editor : Font, FontMetrics, Buffer, State -> View(Msg)
view_editor = |font, metrics, buffer, editor| {
	selection = selection_range(editor)
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
			canvas(|frame, bounds| draw_editor!(frame, bounds, font, metrics, buffer, editor, selection)),
		],
	)
}

draw_editor! : Draw.Frame, Renderer.Bounds, Font, FontMetrics, Buffer, State, { start : U64, end : U64 } => Try({}, Draw.ScopeError)
draw_editor! = |frame, bounds, font, metrics, buffer, editor, selection| {
	advance = metrics.glyph_advance
	line_h = metrics.line_height
	scroll_y = editor.scroll_y
	origin_x = bounds.position.x
	origin_y = bounds.position.y
	viewport_w = bounds.size.w
	viewport_h = bounds.size.h
	line_count = Buffer.line_count(buffer)
	cursor = Buffer.position_at(buffer, editor.cursor)

	fill_rect! = |x, y, rect_w, rect_h, color| frame.rectangle!({ x, y, width: rect_w, height: rect_h, style: Draw.filled(color) })
	draw_text! = |x, y, content, color| frame.text!({ pos: { x, y }, text: content, size: font_size, spacing: spacing, color, font })

	active_color = theme.palette.surface.base.content.with_alpha(12).to_rrt()
	selection_color = theme.palette.selected(theme.palette.surface.base).fill.to_rrt()
	gutter_color = theme.palette.text.muted.to_rrt()
	cursor_color = theme.palette.primary.base.fill.to_rrt()
	plain_color = highlight_color(Plain)

	first = if line_count == 0 {
		0
	} else {
		guess = F32.to_u64_try(scroll_y / line_h) ?? 0
		if guess < line_count guess else line_count - 1
	}
	rows = (F32.ceiling_to_u64_try(viewport_h / line_h) ?? 0) + 1
	span_count = buffer.highlights.len()
	first_offset = Buffer.line_start(buffer, first)
	var $highlight_index = 0
	while $highlight_index < span_count and buffer.highlights.get($highlight_index).ok_or({ start: 0, end: 0, role: Plain }).end <= first_offset {
		$highlight_index = $highlight_index + 1
	}

	var $i = first
	while $i < line_count and $i < first + rows {
		row_y = origin_y + $i.to_f32() * line_h - scroll_y
		active = cursor.line == $i

		if active {
			fill_rect!(origin_x, row_y, viewport_w, line_h, active_color)
		}

		line_off = Buffer.line_start(buffer, $i)
		line_len = Buffer.line_length(buffer, $i)
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

		var $position = line_off
		var $x = origin_x + gutter_width
		var $si = $highlight_index
		var $scanning = Bool.True
		while $si < span_count and $scanning {
			span = buffer.highlights.get($si).ok_or({ start: 0, end: 0, role: Plain })
			if span.start >= content_end {
				$scanning = Bool.False
			} else if span.end > line_off {
				start = U64.max(span.start, line_off)
				end = U64.min(span.end, content_end)
				if start > $position {
					plain = Buffer.text_in(buffer, $position, start)
					draw_text!($x, row_y, plain, plain_color.to_rrt())
					$x = $x + plain.count_utf8_bytes().to_f32() * advance
				}
				if end > start {
					highlighted = Buffer.text_in(buffer, start, end)
					draw_text!($x, row_y, highlighted, highlight_color(span.role).to_rrt())
					$x = $x + highlighted.count_utf8_bytes().to_f32() * advance
					$position = end
				}
			}
			if span.end <= content_end {
				$si = $si + 1
			} else {
				$scanning = Bool.False
			}
		}
		$highlight_index = $si
		if $position < content_end {
			plain = Buffer.text_in(buffer, $position, content_end)
			draw_text!($x, row_y, plain, plain_color.to_rrt())
		}

		if active {
			fill_rect!(origin_x + gutter_width + cursor.column.to_f32() * advance, row_y, 1, line_h, cursor_color)
		}

		$i = $i + 1
	}
	Ok({})
}

update_editor : FontMetrics, Buffer, State, Msg -> Outcome
update_editor = |metrics, buffer, editor, message| match message {
	TextInput(event) => apply_text_input(editor, event)
	InsertLineBreak => insert(editor, "\n")
	MoveLeft(selecting) => no_edit(move_left(buffer, editor, selecting))
	MoveRight(selecting) => no_edit(move_right(buffer, editor, selecting))
	MoveHome(selecting) => no_edit(move_home(buffer, editor, selecting))
	MoveEnd(selecting) => no_edit(move_end(buffer, editor, selecting))
	MoveUp(selecting) => no_edit(move_vertical(buffer, editor, -1, selecting))
	MoveDown(selecting) => no_edit(move_vertical(buffer, editor, 1, selecting))
	DeleteBackward => delete(buffer, editor, 1)
	DeleteForward => delete(buffer, editor, -1)
	PointerStart(event) => no_edit(start_selection_at_pointer(buffer, editor, event, metrics))
	PointerMove(event) => no_edit(extend_selection_to_pointer(buffer, editor, event, metrics))
	ScrollBy(delta, viewport_h) => no_edit(scroll_editor(buffer, editor, delta, viewport_h, metrics))
}

no_edit : State -> Outcome
no_edit = |state| { state, edit: NoEdit }

replace : State, Buffer.Edit -> Outcome
replace = |state, edit| { state, edit: Replace(edit) }

scroll_editor : Buffer, State, F32, F32, FontMetrics -> State
scroll_editor = |buffer, editor, delta, viewport_h, metrics| {
	content_h = Buffer.line_count(buffer).to_f32() * metrics.line_height
	max_scroll = F32.max(content_h - viewport_h, 0)
	next = F32.min(max_scroll, F32.max(0, editor.scroll_y + delta))
	{ ..editor, scroll_y: next }
}

apply_text_input : State, Event.TextInputEvent -> Outcome
apply_text_input = |editor, event| {
	inserted = codepoints_to_str(event.codepoints)
	if inserted.is_empty() no_edit(editor) else insert(editor, inserted)
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

insert : State, Str -> Outcome
insert = |editor, value| {
	selection = selection_range(editor)
	offset = selection.start + value.count_utf8_bytes()
	next = { ..editor, cursor: offset, anchor: offset }
	replace(next, { start: selection.start, end: selection.end, replacement: value })
}

delete : Buffer, State, I64 -> Outcome
delete = |buffer, editor, amount| {
	selection = selection_range(editor)
	if selection.start < selection.end {
		next = { ..editor, cursor: selection.start, anchor: selection.start }
		replace(next, { start: selection.start, end: selection.end, replacement: "" })
	} else if amount > 0 {
		offset = selection.start
		if offset == 0 {
			no_edit(editor)
		} else {
			start = offset - 1
			next = { ..editor, cursor: start, anchor: start }
			replace(next, { start, end: offset, replacement: "" })
		}
	} else if selection.start >= buffer.content.count_utf8_bytes() {
		no_edit(editor)
	} else {
		offset = selection.start
		replace(editor, { start: offset, end: offset + 1, replacement: "" })
	}
}

move_left : Buffer, State, Bool -> State
move_left = |buffer, editor, selecting| {
	selection = selection_range(editor)
	target = if !selecting and selection.start < selection.end selection.start else if editor.cursor > 0 editor.cursor - 1 else 0
	set_cursor(buffer, editor, target, selecting)
}

move_right : Buffer, State, Bool -> State
move_right = |buffer, editor, selecting| {
	selection = selection_range(editor)
	limit = buffer.content.count_utf8_bytes()
	target = if !selecting and selection.start < selection.end selection.end else if editor.cursor < limit editor.cursor + 1 else editor.cursor
	set_cursor(buffer, editor, target, selecting)
}

move_home : Buffer, State, Bool -> State
move_home = |buffer, editor, selecting| {
	position = Buffer.position_at(buffer, editor.cursor)
	set_cursor(buffer, editor, Buffer.line_start(buffer, position.line), selecting)
}

move_end : Buffer, State, Bool -> State
move_end = |buffer, editor, selecting| {
	position = Buffer.position_at(buffer, editor.cursor)
	end = Buffer.line_start(buffer, position.line) + Buffer.line_length(buffer, position.line)
	set_cursor(buffer, editor, end, selecting)
}

move_vertical : Buffer, State, I64, Bool -> State
move_vertical = |buffer, editor, delta, selecting| {
	position = Buffer.position_at(buffer, editor.cursor)
	line_count = Buffer.line_count(buffer)
	target_line = if delta < 0 {
		if position.line > 0 position.line - 1 else 0
	} else if position.line + 1 < line_count {
		position.line + 1
	} else {
		position.line
	}
	target = Buffer.offset_at(buffer, target_line, position.column)
	set_cursor(buffer, editor, target, selecting)
}

start_selection_at_pointer : Buffer, State, Event.DragEvent, FontMetrics -> State
start_selection_at_pointer = |buffer, editor, event, metrics| {
	offset = offset_at_pointer(buffer, editor, event.position, event.target.bounds, metrics)
	{ ..editor, cursor: offset, anchor: offset }
}

extend_selection_to_pointer : Buffer, State, Event.DragEvent, FontMetrics -> State
extend_selection_to_pointer = |buffer, editor, event, metrics| {
	{ ..editor, cursor: offset_at_pointer(buffer, editor, event.position, event.target.bounds, metrics) }
}

offset_at_pointer : Buffer, State, Event.Point, Event.ElementBounds, FontMetrics -> U64
offset_at_pointer = |buffer, editor, pointer, bounds, metrics| {
	relative_y = pointer.y - bounds.y + editor.scroll_y
	line_guess = line_from_pointer(relative_y, 0, metrics.line_height)
	line_count = Buffer.line_count(buffer)
	line = if line_count == 0 0 else if line_guess < line_count line_guess else line_count - 1
	length = Buffer.line_length(buffer, line)
	column = pointer_column(pointer.x - bounds.x, length, metrics.glyph_advance)
	Buffer.offset_at(buffer, line, column)
}

set_cursor : Buffer, State, U64, Bool -> State
set_cursor = |buffer, editor, requested, selecting| {
	offset = U64.min(requested, buffer.content.count_utf8_bytes())
	{ ..editor, cursor: offset, anchor: if selecting editor.anchor else offset }
}

selection_range : State -> { start : U64, end : U64 }
selection_range = |editor| { start: U64.min(editor.cursor, editor.anchor), end: U64.max(editor.cursor, editor.anchor) }

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
	content_x = relative_x - gutter_width
	if content_x <= 0 or length == 0 {
		0
	} else {
		column = (content_x / advance).round_to_u64_try().ok_or(0)
		if column < length column else length
	}
}

code_line_height : Font -> F32
code_line_height = |font| TextMeasure.measure_line("M", { font_size: font_size, spacing: spacing }, font).height

glyph_advance : Font -> F32
glyph_advance = |font| TextMeasure.measure_line(
	"M",
	{ font_size: font_size, spacing: spacing },
	font,
).width

highlight_color : Syntax.HighlightRole -> Color
highlight_color = |role| match role {
	Plain => theme.palette.surface.base.content
	Punctuation => theme.palette.text.muted
	Name => theme.palette.primary.base.fill
	Property => theme.palette.primary.strong.fill
	Value => theme.palette.success.base.fill
	Comment => theme.palette.text.muted
	Directive => theme.palette.warning.base.fill
	Escape => theme.palette.warning.base.fill
}

test_buffer : Str -> Buffer
test_buffer = |content| Buffer.from_path("test.txt", content)

test_state : U64, U64 -> State
test_state = |cursor, anchor| { cursor, anchor, scroll_y: 0 }

apply_outcome : Buffer, Outcome -> { buffer : Buffer, state : State }
apply_outcome = |buffer, outcome| match outcome.edit {
	NoEdit => { buffer, state: outcome.state }
	Replace(edit) => { buffer: Buffer.apply_edit(buffer, edit), state: outcome.state }
}

test_metrics : FontMetrics
test_metrics = { glyph_advance: 1, line_height: 1 }

expect {
	buffer = test_buffer("ab")
	updated = apply_outcome(buffer, insert(test_state(0, 0), "X"))
	updated.buffer.content == "Xab" and updated.state.cursor == 1
}

expect {
	buffer = test_buffer("one\ntwo")
	updated = apply_outcome(buffer, insert(test_state(4, 4), "!"))
	position = Buffer.position_at(updated.buffer, updated.state.cursor)
	updated.buffer.content == "one\n!two" and position == { line: 1, column: 1 }
}

expect {
	buffer = test_buffer("abc")
	updated = apply_outcome(buffer, delete(buffer, test_state(2, 2), 1))
	updated.buffer.content == "ac"
}

expect {
	buffer = test_buffer("one\ntwo\nthree")
	first = move_vertical(buffer, test_state(1, 1), 1, Bool.False)
	second = move_vertical(buffer, first, 1, Bool.False)
	Buffer.position_at(buffer, first.cursor) == { line: 1, column: 1 }
		and Buffer.position_at(buffer, second.cursor) == { line: 2, column: 1 }
}

expect {
	buffer = test_buffer("abcd")
	updated = apply_outcome(buffer, insert(test_state(1, 3), "X"))
	updated.buffer.content == "aXd" and updated.state.cursor == 2 and updated.state.anchor == 2
}

expect {
	buffer = test_buffer("one\ntwo")
	updated = apply_outcome(buffer, delete(buffer, test_state(2, 5), 1))
	updated.buffer.content == "onwo" and updated.state.cursor == 2 and updated.state.anchor == 2
}

expect {
	buffer = test_buffer("abcd")
	selected = move_right(buffer, test_state(1, 1), Bool.True)
	collapsed = move_left(buffer, selected, Bool.False)
	selected.cursor == 2 and selected.anchor == 1 and collapsed.cursor == 1 and collapsed.anchor == 1
}

expect {
	buffer = test_buffer("one\ntwo\nthree")
	scrolled = scroll_editor(buffer, CodeEditor.initial, 100, 10, { glyph_advance: 1, line_height: 10 })
	scrolled.scroll_y == 20
}

expect {
	buffer = test_buffer("one\ntwo\nthree")
	scrolled = scroll_editor(buffer, CodeEditor.initial, -50, 10, { glyph_advance: 1, line_height: 10 })
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
