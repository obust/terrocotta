## Rendering for the controlled single-line text input widget.
import ../Color
import ../Element exposing [View, box, text, style]
import ../Event
import ../Theme
import ../Unicode exposing [AsciiCursor, codepoints_to_str]
import rr.Font

InputText :: [].{
	Config(msg) := {
		state : { value : Str, cursor : U64 },
		font : Font,
		on_change : { value : Str, cursor : U64 } -> msg,
		id : Element.ElementId ?? Auto,
		placeholder : Str ?? "",
	}

	input_text : Theme, Config(msg) -> View(msg, payload)
	input_text = |theme, { id, font, state, placeholder, on_change }| {
		surface = theme.palette.background.weak
		content_color = theme.palette.background.base.content

		# placeholder
		(content, font_color) = if state.value.is_empty() {
			(placeholder, content_color.mix(surface.fill, 112))
		} else {
			(state.value, content_color)
		}

		# caret
		prefix = text_before_cursor(state.value, state.cursor)
		prefix_width = Font.measure(font, { text: prefix, size: theme.font_size, spacing: Element.default_text.spacing }).width
		caret_offset_x = theme.gap / 2 + prefix_width + 1

		box(
			{
				id,
				events: [OnTextInput(Box.box(|event| on_change(update(state, event))))],
				style: |status| {
					border_color = if status.focused {
						theme.palette.primary.strong.fill
					} else {
						Color.mix(surface.fill, content_color, 70)
					}
					style
						.width(Grow({ min: theme.font_size * 6, max: 10000 }))
						.height(Fixed(theme.font_size + theme.gap))
						.background(surface.fill)
						.font_size(theme.font_size)
						.font_color(font_color)
						.text_wrap(None)
						.radius(theme.radius)
						.pad(theme.gap / 4, theme.gap / 2, theme.gap / 4, theme.gap / 2)
						.direction(Row)
						.child_align({ x: Start, y: Center })
						.overflow(Hidden, Hidden)
						.border({ color: border_color, left: 1, right: 1, top: 1, bottom: 1 })
				},
			},
			[
				text(content),
				box(
					{
						style: |_| style
							.width(Fixed(1))
							.height(Fixed(theme.font_size))
							.background(content_color)
							.floating(
								Floating({
									target: Parent,
									config: {
										..Element.default_floating_config,
										offset: { x: caret_offset_x, y: 0 },
										attach_points: { element: LeftCenter, target: LeftCenter },
										capture: Passthrough,
										clip_to: AttachedParent,
									},
								}),
							),
					},
					[],
				),
			],
		)
	}
}

## Return the text before a normalized cursor.
text_before_cursor : Str, U64 -> Str
text_before_cursor = |value, pos| {
	cursor = AsciiCursor.new(value, pos)
	Str.from_utf8_lossy(value.to_utf8().sublist({ start: 0, len: cursor.byte_offset() }))
}

## Update input text state.
update : { value : Str, cursor : U64 }, Event.TextInputEvent -> { value : Str, cursor : U64 }
update = |state, event| {
	var $value = state.value
	var $cursor = AsciiCursor.new($value, state.cursor)
	for key in event.keys {
		($value, $cursor) = match key {
			KeyLeft => ($value, $cursor.previous())
			KeyRight => ($value, $cursor.next())
			KeyHome => ($value, $cursor.start())
			KeyEnd => ($value, $cursor.end())
			KeyBackspace => remove_before($value, $cursor)
			KeyDelete => remove_after($value, $cursor)
		}
	}

	event_text = codepoints_to_str(event.codepoints)
	($value, $cursor) = insert_text($value, $cursor, event_text)

	{ value: $value, cursor: $cursor.position() }
}

## Remove a byte range from a string.
remove_bytes : Str, U64, U64 -> Str
remove_bytes = |value, start, end| {
	bytes = value.to_utf8()
	before = bytes.sublist({ start: 0, len: start })
	after = bytes.sublist({ start: end, len: bytes.len() - end })
	Str.from_utf8_lossy(before.concat(after))
}

## Remove the ASCII character immediately before the cursor.
remove_before : Str, AsciiCursor -> (Str, AsciiCursor)
remove_before = |value, cursor| {
	if cursor.byte_offset() == 0 {
		(value, cursor)
	} else {
		start = cursor.previous().byte_offset()
		end = cursor.byte_offset()
		next_value = remove_bytes(value, start, end)
		(next_value, AsciiCursor.new(next_value, cursor.position() - 1))
	}
}

## Remove the ASCII character immediately after the cursor.
remove_after : Str, AsciiCursor -> (Str, AsciiCursor)
remove_after = |value, cursor| {
	if cursor.byte_offset() >= value.count_utf8_bytes() {
		(value, cursor)
	} else {
		start = cursor.byte_offset()
		end = cursor.next().byte_offset()
		next_value = remove_bytes(value, start, end)
		(next_value, AsciiCursor.new(next_value, cursor.position()))
	}
}

## Insert ASCII text at the cursor and advance by its byte length.
insert_text : Str, AsciiCursor, Str -> (Str, AsciiCursor)
insert_text = |value, cursor, content| {
	if content.is_empty() {
		(value, cursor)
	} else {
		bytes = value.to_utf8()
		content_bytes = content.to_utf8()
		offset = cursor.byte_offset()
		before = bytes.sublist({ start: 0, len: offset })
		after = bytes.sublist({ start: offset, len: bytes.len() - offset })
		next_value = Str.from_utf8_lossy(before.concat(content_bytes).concat(after))
		next_offset = offset + content_bytes.len()
		(next_value, AsciiCursor.from_byte(next_value, next_offset))
	}
}

text_input_event : List(U32), List(Event.TextControlKey) -> Event.TextInputEvent
text_input_event = |codepoints, keys| { codepoints, keys }

state_is = |state, value, cursor| state.value == value and state.cursor == cursor

## A batch preserves printable ASCII code-point order and ignores other input.
expect {
	next = update(
		{ value: "ab", cursor: 1 },
		text_input_event([0xE9, 0x1F426, 99], []),
	)
	state_is(next, "acb", 2)
}

## Movement crosses one ASCII byte at a time.
expect {
	state = { value: "abc", cursor: 2 }
	left = update(state, text_input_event([], [KeyLeft]))
	right = update(left, text_input_event([], [KeyRight]))
	state_is(left, "abc", 1) and state_is(right, "abc", 2)
}

## Backspace and Delete remove exactly one adjacent ASCII character.
expect {
	backspaced = update(
		{ value: "abcd", cursor: 2 },
		text_input_event([], [KeyBackspace]),
	)
	deleted = update(
		{ value: "abcd", cursor: 1 },
		text_input_event([], [KeyDelete]),
	)
	state_is(backspaced, "acd", 1) and state_is(deleted, "acd", 1)
}

## Boundary deletions are no-ops; Home and End set exact byte boundaries.
expect {
	at_start = { value: "a", cursor: 0 }
	at_end = { value: "a", cursor: 1 }
	backspace_start = update(at_start, text_input_event([], [KeyBackspace]))
	delete_end = update(at_end, text_input_event([], [KeyDelete]))
	home = update(at_end, text_input_event([], [KeyHome]))
	end = update(at_start, text_input_event([], [KeyEnd]))
	state_is(backspace_start, "a", 0)
		and state_is(delete_end, "a", 1)
			and home.cursor == 0
				and end.cursor == 1
}

## Single-line controls and invalid Unicode scalars are ignored.
expect {
	next = update(
		{ value: "", cursor: 0 },
		text_input_event([9, 10, 13, 0x7F, 0xD800, 0x110000, 65], []),
	)
	state_is(next, "A", 1)
}

## Stale and out-of-range cursors clamp to a valid boundary.
expect {
	out_of_range = update({ value: "a", cursor: 99 }, text_input_event([], []))
	stale = update({ value: "abc", cursor: 5 }, text_input_event([], []))
	state_is(out_of_range, "a", 1) and state_is(stale, "abc", 3)
}

## An idle batch preserves an already valid state exactly.
expect {
	next = update({ value: "hello", cursor: 2 }, text_input_event([], []))
	state_is(next, "hello", 2)
}

## Unicode grapheme behavior is disabled with the temporary ASCII cursor.

InputTextTestMsg : [InputChanged({ value : Str, cursor : U64 })]

test_status : Bool -> Element.BoxStatus
test_status = |focused| { hovered: Bool.False, pressed: Bool.False, focused, disabled: Bool.False }

## Enabled inputs own the stable ID and one batched handler, and render the value.
expect {
	view = InputText.input_text(
		Theme.dark,
		{
			id: Id("name"),
			font: Font.stub,
			state: { value: "aéb", cursor: 3 },
			placeholder: "Name",
			on_change: |state| InputChanged(state),
		},
	)
	match view.collect() {
		[
			OpenBox(Id("name"), _, [OnTextInput(_)]),
			Text("aéb"),
			OpenBox(Auto, _, []),
			CloseBox,
			CloseBox,
		] => Bool.True
		_ => Bool.False
	}
}

## Focus styling changes the outer border.
expect {
	view = InputText.input_text(
		Theme.dark,
		{
			id: Id("styled-name"),
			font: Font.stub,
			state: { value: "Roc", cursor: 3 },
			placeholder: "Name",
			on_change: |state| InputChanged(state),
		},
	)
	match view.collect() {
		[OpenBox(_, outer_style, _), ..] => {
			unfocused = test_status(False)
			focused = test_status(True)
			(outer_style(unfocused)).border.color != (outer_style(focused)).border.color
		}
		_ => Bool.False
	}
}

## Empty inputs render their placeholder and retain input handling.
expect {
	view = InputText.input_text(
		Theme.dark,
		{
			id: Id("empty-name"),
			font: Font.stub,
			state: { value: "", cursor: 0 },
			placeholder: "Name",
			on_change: |state| InputChanged(state),
		},
	)
	match view.collect() {
		[
			OpenBox(Id("empty-name"), _, [OnTextInput(_)]),
			Text("Name"),
			OpenBox(Auto, _, []),
			CloseBox,
			CloseBox,
		] => Bool.True
		_ => Bool.False
	}
}
