## UTF-8 byte-boundary and Unicode scalar helpers.
# import unicode.ByteRange
# import unicode.GeneralCategory
# import unicode.Grapheme
# import unicode.Scalar

Unicode := [].{

	## A cursor over byte boundaries in ASCII text.
	## The source is expected to contain only ASCII code points, so positions and
	## UTF-8 byte offsets are identical.
	AsciiCursor :: { source : Str, offset : U64 }.{

		## Create a cursor at the requested ASCII position. Clamps into [0, count].
		new : Str, U64 -> AsciiCursor
		new = |source, position| {
			byte_count = source.count_utf8_bytes()
			offset = if position > byte_count byte_count else position
			{ source, offset }
		}

		## Create a cursor from an ASCII byte offset. Clamps into [0, count].
		from_byte : Str, U64 -> AsciiCursor
		from_byte = |source, byte_offset| AsciiCursor.new(source, byte_offset)

		## Return the cursor's ASCII ordinal position.
		position : AsciiCursor -> U64
		position = |cursor| cursor.offset

		## Return the cursor's UTF-8 byte offset.
		byte_offset : AsciiCursor -> U64
		byte_offset = |cursor| cursor.offset

		## Count the number of ASCII positions in a string.
		count : Str -> U64
		count = |source| source.count_utf8_bytes()

		## Move to the previous ASCII position.
		previous : AsciiCursor -> AsciiCursor
		previous = |cursor| if cursor.offset == 0 {
			cursor
		} else {
			{ ..cursor, offset: cursor.offset - 1 }
		}

		## Move to the next ASCII position.
		next : AsciiCursor -> AsciiCursor
		next = |cursor| {
			byte_count = cursor.source.count_utf8_bytes()
			if cursor.offset >= byte_count {
				cursor
			} else {
				{ ..cursor, offset: cursor.offset + 1 }
			}
		}

		## Move to the start of the text.
		start : AsciiCursor -> AsciiCursor
		start = |cursor| { ..cursor, offset: 0 }

		## Move to the end of the text.
		end : AsciiCursor -> AsciiCursor
		end = |cursor| { ..cursor, offset: cursor.source.count_utf8_bytes() }
	}

	# ## A cursor over Unicode scalar boundaries in a UTF-8 text value.
	# ScalarCursor :: { source : Str, offset : U64 }.{

	# 	## Create a cursor at the Nth scalar boundary. Clamps into [0, count].
	# 	new : Str, U64 -> ScalarCursor
	# 	new = |source, position| {
	# 		byte_count = source.count_utf8_bytes()
	# 		var $offset = byte_count
	# 		var $i = 0
	# 		for located in Scalar.iter(source) {
	# 			if $i == position {
	# 				$offset = ByteRange.start(located.byte_range)
	# 			}
	# 			$i = $i + 1
	# 		}
	# 		{ source, offset: $offset }
	# 	}

	# 	## Return the cursor's scalar ordinal position.
	# 	position : ScalarCursor -> U64
	# 	position = |cursor| {
	# 		var $pos = 0
	# 		var $done = Bool.False
	# 		for located in Scalar.iter(cursor.source) {
	# 			if $done {
	# 				$pos
	# 			} else if ByteRange.end(located.byte_range) <= cursor.offset {
	# 				$pos = $pos + 1
	# 				$pos
	# 			} else {
	# 				$done = Bool.True
	# 				$pos
	# 			}
	# 		}
	# 		$pos
	# 	}

	# 	## Return the cursor's normalized UTF-8 byte offset.
	# 	byte_offset : ScalarCursor -> U64
	# 	byte_offset = |cursor| cursor.offset

	# 	## Count the number of Unicode scalars in a string.
	# 	count : Str -> U64
	# 	count = |source| {
	# 		var $n = 0
	# 		for _ in Scalar.iter(source) {
	# 			$n = $n + 1
	# 		}
	# 		$n
	# 	}

	# 	## Move to the previous Unicode scalar boundary.
	# 	previous : ScalarCursor -> ScalarCursor
	# 	previous = |cursor| {
	# 		var $offset = 0
	# 		var $done = Bool.False
	# 		for located in Scalar.iter(cursor.source) {
	# 			if $done {
	# 				$offset
	# 			} else if ByteRange.end(located.byte_range) <= cursor.offset {
	# 				$offset = ByteRange.start(located.byte_range)
	# 				$offset
	# 			} else {
	# 				$done = Bool.True
	# 				$offset
	# 			}
	# 		}
	# 		{ ..cursor, offset: $offset }
	# 	}

	# 	## Move to the next Unicode scalar boundary.
	# 	next : ScalarCursor -> ScalarCursor
	# 	next = |cursor| {
	# 		var $offset = cursor.offset
	# 		var $done = Bool.False
	# 		for located in Scalar.iter(cursor.source) {
	# 			if $done {
	# 				$offset
	# 			} else if ByteRange.start(located.byte_range) == cursor.offset {
	# 				$offset = ByteRange.end(located.byte_range)
	# 				$done = Bool.True
	# 				$offset
	# 			} else {
	# 				$offset
	# 			}
	# 		}
	# 		{ ..cursor, offset: $offset }
	# 	}

	# 	## Move to the start of the text.
	# 	start : ScalarCursor -> ScalarCursor
	# 	start = |cursor| { ..cursor, offset: 0 }

	# 	## Move to the end of the text.
	# 	end : ScalarCursor -> ScalarCursor
	# 	end = |cursor| { ..cursor, offset: cursor.source.count_utf8_bytes() }
	# }

	# ## A cursor over extended grapheme cluster boundaries in a UTF-8 text value.
	# GraphemeCursor :: { source : Str, offset : U64 }.{

	# 	## Create a cursor at the Nth cluster boundary. Clamps into [0, count].
	# 	new : Str, U64 -> GraphemeCursor
	# 	new = |source, position| {
	# 		byte_count = source.count_utf8_bytes()
	# 		var $offset = byte_count
	# 		var $i = 0
	# 		for range in Grapheme.iter_ranges(source) {
	# 			if $i == position {
	# 				$offset = ByteRange.start(range)
	# 			}
	# 			$i = $i + 1
	# 		}
	# 		{ source, offset: $offset }
	# 	}

	# 	## Create a cursor by snapping a byte offset forward to the nearest cluster boundary.
	# 	from_byte : Str, U64 -> GraphemeCursor
	# 	from_byte = |source, byte_off| {
	# 		{ source, offset: snap_forward(source, byte_off) }
	# 	}

	# 	## Return the cursor's cluster ordinal position.
	# 	position : GraphemeCursor -> U64
	# 	position = |cursor| {
	# 		var $pos = 0
	# 		var $done = Bool.False
	# 		for range in Grapheme.iter_ranges(cursor.source) {
	# 			if $done {
	# 				$pos
	# 			} else if ByteRange.end(range) <= cursor.offset {
	# 				$pos = $pos + 1
	# 				$pos
	# 			} else {
	# 				$done = Bool.True
	# 				$pos
	# 			}
	# 		}
	# 		$pos
	# 	}

	# 	## Return the cursor's normalized UTF-8 byte offset.
	# 	byte_offset : GraphemeCursor -> U64
	# 	byte_offset = |cursor| cursor.offset

	# 	## Count the number of grapheme clusters in a string.
	# 	count : Str -> U64
	# 	count = |source| {
	# 		var $n = 0
	# 		for _ in Grapheme.iter_ranges(source) {
	# 			$n = $n + 1
	# 		}
	# 		$n
	# 	}

	# 	## Move to the previous cluster boundary.
	# 	previous : GraphemeCursor -> GraphemeCursor
	# 	previous = |cursor| {
	# 		var $offset = 0
	# 		var $done = Bool.False
	# 		for range in Grapheme.iter_ranges(cursor.source) {
	# 			if $done {
	# 				$offset
	# 			} else if ByteRange.end(range) <= cursor.offset {
	# 				$offset = ByteRange.start(range)
	# 				$offset
	# 			} else {
	# 				$done = Bool.True
	# 				$offset
	# 			}
	# 		}
	# 		{ ..cursor, offset: $offset }
	# 	}

	# 	## Move to the next cluster boundary.
	# 	next : GraphemeCursor -> GraphemeCursor
	# 	next = |cursor| {
	# 		var $offset = cursor.offset
	# 		var $done = Bool.False
	# 		for range in Grapheme.iter_ranges(cursor.source) {
	# 			if $done {
	# 				$offset
	# 			} else if ByteRange.start(range) == cursor.offset {
	# 				$offset = ByteRange.end(range)
	# 				$done = Bool.True
	# 				$offset
	# 			} else {
	# 				$offset
	# 			}
	# 		}
	# 		{ ..cursor, offset: $offset }
	# 	}

	# 	## Move to the start of the text.
	# 	start : GraphemeCursor -> GraphemeCursor
	# 	start = |cursor| { ..cursor, offset: 0 }

	# 	## Move to the end of the text.
	# 	end : GraphemeCursor -> GraphemeCursor
	# 	end = |cursor| { ..cursor, offset: cursor.source.count_utf8_bytes() }
	# }

	# ## Return the smallest cluster boundary at or after a byte offset.
	# snap_forward : Str, U64 -> U64
	# snap_forward = |source, byte_off| {
	# 	total = source.count_utf8_bytes()
	# 	var $result = total
	# 	var $done = Bool.False
	# 	for range in Grapheme.iter_ranges(source) {
	# 		if $done {
	# 			$result
	# 		} else if ByteRange.start(range) >= byte_off {
	# 			$result = ByteRange.start(range)
	# 			$done = Bool.True
	# 			$result
	# 		} else {
	# 			$result
	# 		}
	# 	}
	# 	$result
	# }

	# ## Convert valid, non-control Unicode codepoints to a string.
	# codepoints_to_str : List(U32) -> Str
	# codepoints_to_str = |codepoints| codepoints.fold(
	# 	"",
	# 	|current, codepoint| {
	# 		match Scalar.from_u32(codepoint) {
	# 			Ok(scalar) => {
	# 				if GeneralCategory.of_scalar(scalar) != Cc {
	# 					match scalar.to_str() {
	# 						Ok(value) => current.concat(value)
	# 						Err(_) => current
	# 					}
	# 				} else {
	# 					current
	# 				}
	# 			}
	# 			Err(_) => current
	# 		}
	# 	},
	# )

	## Convert printable ASCII code points to a string, ignoring all others.
	## This assumes accepted code points are their own single-byte UTF-8 encoding.
	codepoints_to_str : List(U32) -> Str
	codepoints_to_str = |codepoints|
		Str.from_utf8_lossy(
			List.map(
				List.keep_if(codepoints, |codepoint| codepoint >= 32 and codepoint < 127),
				|codepoint| U32.to_u8_wrap(codepoint),
			),
		)
}

expect AsciiCursor.count("abc") == 3

expect AsciiCursor.new("ab", 99).byte_offset() == 2

expect AsciiCursor.from_byte("ab", 99).position() == 2

expect Unicode.codepoints_to_str([9, 10, 13, 65, 0x7F, 0xE9]) == "A"

expect {
	cursor = AsciiCursor.new("abc", 1)
	cursor.position() == 1
		and cursor.previous().position() == 0
			and cursor.next().position() == 2
}

expect {
	cursor = AsciiCursor.new("abc", 1)
	cursor.start().position() == 0 and cursor.end().position() == 3
}

expect {
	start = AsciiCursor.new("abc", 0)
	end = AsciiCursor.new("abc", 3)
	start.previous().position() == 0 and end.next().position() == 3
}

# GraphemeCursor tests are disabled with the temporary Unicode-free implementation.
