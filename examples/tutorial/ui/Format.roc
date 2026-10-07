## Small formatter for tutorial box snippets.

Format := [].{
	format : Str -> Str
	format = |source| match parse_expression(source, 0, 0) {
		Ok(result) => result.text
		Err(_) => source
	}
}

ParseResult : { text : Str, next : U64 }
ParseError : [InvalidFormat]

space_byte : U8
space_byte = 32
tab_byte : U8
tab_byte = 9
newline_byte : U8
newline_byte = 10
carriage_return_byte : U8
carriage_return_byte = 13
quote_byte : U8
quote_byte = 34
backslash_byte : U8
backslash_byte = 92
left_parenthesis_byte : U8
left_parenthesis_byte = 40
right_parenthesis_byte : U8
right_parenthesis_byte = 41
left_bracket_byte : U8
left_bracket_byte = 91
right_bracket_byte : U8
right_bracket_byte = 93
left_brace_byte : U8
left_brace_byte = 123
right_brace_byte : U8
right_brace_byte = 125
comma_byte : U8
comma_byte = 44

parse_expression : Str, U64, U64 -> Try(ParseResult, ParseError)
parse_expression = |source, start, depth| {
	index = skip_space(source, start)
	if starts_box(source, index) {
		parse_box(source, index, depth)
	} else {
		end = scan_opaque(source, index)?
		Ok({ text: slice(source, index, end - index), next: end })
	}
}

parse_box : Str, U64, U64 -> Try(ParseResult, ParseError)
parse_box = |source, start, depth| {
	config_start = start + 4
	comma_index = scan_to_comma(source, config_start)?
	config = trim(source, config_start, comma_index - config_start)
	children_start = skip_space(source, comma_index + 1)
	if byte_at(source, children_start) != left_bracket_byte {
		Err(InvalidFormat)
	} else {
		children = parse_children(source, children_start + 1, depth, config)
		match children {
			Err(error) => Err(error)
			Ok(result) => {
				closing = skip_space(source, result.next)
				if byte_at(source, closing) == right_parenthesis_byte {
					Ok({ ..result, next: closing + 1 })
				} else {
					Err(InvalidFormat)
				}
			}
		}
	}
}

parse_children : Str, U64, U64, Str -> Try(ParseResult, ParseError)
parse_children = |source, start, depth, config| {
	index = skip_space(source, start)
	if byte_at(source, index) == right_bracket_byte {
		Ok({ text: "box(${config}, [])", next: index + 1 })
	} else {
		var $index = index
		var $children = ""
		var $valid = Bool.True
		while $valid {
			child = parse_expression(source, $index, depth + 1)
			match child {
				Err(_) => { $valid = Bool.False }
				Ok(result) => {
					$children = "${$children}${tabs(depth + 1)}${result.text},\n"
					$index = skip_space(source, result.next)
					if byte_at(source, $index) == comma_byte {
						$index = skip_space(source, $index + 1)
					} else if byte_at(source, $index) == right_bracket_byte {
						$valid = Bool.False
					} else {
						$valid = Bool.False
					}
				}
			}
		}
		if byte_at(source, $index) == right_bracket_byte {
			Ok({ text: "box(${config}, [\n${$children}${tabs(depth)}])", next: $index + 1 })
		} else {
			Err(InvalidFormat)
		}
	}
}

starts_box : Str, U64 -> Bool
starts_box = |source, index| slice(source, index, 4) == "box("

scan_to_comma : Str, U64 -> Try(U64, ParseError)
scan_to_comma = |source, start| scan(source, start, comma_byte)

scan_opaque : Str, U64 -> Try(U64, ParseError)
scan_opaque = |source, start| scan(source, start, right_bracket_byte)

scan : Str, U64, U8 -> Try(U64, ParseError)
scan = |source, start, stop| {
	bytes = source.to_utf8()
	var $index = start
	var $stack = []
	var $quoted = Bool.False
	var $escaped = Bool.False
	var $done = Bool.False
	var $valid = Bool.True
	while $index < bytes.len() and $done == Bool.False and $valid {
		byte = bytes.get($index).ok_or(0)
		if $quoted {
			if $escaped {
				$escaped = Bool.False
			} else if byte == backslash_byte {
				$escaped = Bool.True
			} else if byte == quote_byte {
				$quoted = Bool.False
			}
		} else if byte == quote_byte {
			$quoted = Bool.True
		} else if is_opener(byte) {
			$stack = $stack.prepend(byte)
		} else if is_closer(byte) {
			match $stack.get(0) {
				Err(_) => {
					if byte == stop {
						$done = Bool.True
					} else {
						$valid = Bool.False
					}
				}
				Ok(opener) => if matching_delimiter(opener, byte) {
					$stack = $stack.drop_at(0)
				} else {
					$valid = Bool.False
				}
			}
		} else if byte == stop and $stack.len() == 0 {
				$done = Bool.True
		}
		if $done == Bool.False and $valid {
			$index = $index + 1
		}
	}
	if $valid and $done and $stack.len() == 0 {
		Ok($index)
	} else if $valid and $stack.len() == 0 and $index == bytes.len() {
		Ok($index)
	} else {
		Err(InvalidFormat)
	}
}

is_opener : U8 -> Bool
is_opener = |byte| byte == left_parenthesis_byte or byte == left_bracket_byte or byte == left_brace_byte

is_closer : U8 -> Bool
is_closer = |byte| byte == right_parenthesis_byte or byte == right_bracket_byte or byte == right_brace_byte

matching_delimiter : U8, U8 -> Bool
matching_delimiter = |opener, closer| {
	(opener == left_parenthesis_byte and closer == right_parenthesis_byte)
		or (opener == left_bracket_byte and closer == right_bracket_byte)
		or (opener == left_brace_byte and closer == right_brace_byte)
}

skip_space : Str, U64 -> U64
skip_space = |source, start| {
	bytes = source.to_utf8()
	var $index = start
	while $index < bytes.len() {
		byte = bytes.get($index).ok_or(0)
		if byte == space_byte or byte == tab_byte or byte == newline_byte or byte == carriage_return_byte {
			$index = $index + 1
		} else {
			break
		}
	}
	$index
}

trim : Str, U64, U64 -> Str
trim = |source, start, len| {
	begin = skip_space(source, start)
	end = start + len
	bytes = source.to_utf8()
	var $finish = end
	while $finish > begin {
		byte = bytes.get($finish - 1).ok_or(0)
		if byte == space_byte or byte == tab_byte or byte == newline_byte or byte == carriage_return_byte {
			$finish = $finish - 1
		} else {
			break
		}
	}
	slice(source, begin, $finish - begin)
}

slice : Str, U64, U64 -> Str
slice = |source, start, len| Str.from_utf8_lossy(source.to_utf8().sublist({ start, len }))

byte_at : Str, U64 -> U8
byte_at = |source, index| source.to_utf8().get(index).ok_or(0)

tabs : U64 -> Str
tabs = |depth| if depth == 0 "" else "\t${tabs(depth - 1)}"

expect {
	Format.format("box({ id: Id(\"empty\") }, [])") == "box({ id: Id(\"empty\") }, [])"
}

expect {
	Format.format("box({ id: Id(\"container\") }, [box({ id: Id(\"floating\") }, [text(\"Floating badge\")])])")
		== "box({ id: Id(\"container\") }, [\n\tbox({ id: Id(\"floating\") }, [\n\t\ttext(\"Floating badge\"),\n\t]),\n])"
}

expect {
	invalid = "box({ id: [)] }, [])"
	Format.format(invalid) == invalid
}
