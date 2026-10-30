## Detection and conversion at text input and output boundaries.
##
## Editor buffers always contain LF. This module translates consistent CRLF
## input to that representation and restores a document's external style when
## it is saved.
LineEndings := [].{
	LineEnding : [Lf, Crlf]

	Decoded : {
		content : Str,
		line_ending : LineEnding,
	}

	DecodeError : [LoneCarriageReturn(U64), MixedLineEndings]

	decode : Str -> Try(Decoded, DecodeError)
	decode = decode_content

	encode : Str, LineEnding -> Str
	encode = encode_content
}

carriage_return_byte : U8
carriage_return_byte = 13

decode_content : Str -> Try(LineEndings.Decoded, LineEndings.DecodeError)
decode_content = |source| {
	## Replacing CRLF with two bytes preserves offsets. Any CR or LF left in the
	## mask is therefore a lone CR or a bare LF, respectively.
	mask = Str.replace_each(source, "\r\n", "  ")
	match mask.to_utf8().find_first_index(|byte| byte == carriage_return_byte) {
		Ok(offset) => return Err(LoneCarriageReturn(offset))
		Err(_) => {}
	}

	has_crlf = mask != source
	if has_crlf and Str.contains(mask, "\n") {
		Err(MixedLineEndings)
	} else {
		Ok({
			content: if (has_crlf) Str.replace_each(source, "\r\n", "\n") else source,
			line_ending: if (has_crlf) Crlf else Lf,
		})
	}
}

encode_content : Str, LineEndings.LineEnding -> Str
encode_content = |content, line_ending| {
	bytes = content.to_utf8()
	if bytes.contains(carriage_return_byte) {
		crash "LineEndings.encode expected normalized LF content"
	}

	match line_ending {
		Lf => content
		Crlf => Str.replace_each(content, "\n", "\r\n")
	}
}

expect LineEndings.decode("") == Ok({ content: "", line_ending: Lf })
expect LineEndings.decode("one line") == Ok({ content: "one line", line_ending: Lf })
expect LineEndings.decode("one\ntwo\nthree") == Ok({ content: "one\ntwo\nthree", line_ending: Lf })
expect LineEndings.decode("one\r\ntwo\r\nthree") == Ok({ content: "one\ntwo\nthree", line_ending: Crlf })
expect LineEndings.decode("one\n") == Ok({ content: "one\n", line_ending: Lf })
expect LineEndings.decode("one\r\n") == Ok({ content: "one\n", line_ending: Crlf })
expect LineEndings.decode("one\ntwo\r\n") == Err(MixedLineEndings)
expect LineEndings.decode("one\r\ntwo\n") == Err(MixedLineEndings)
expect LineEndings.decode("\rone") == Err(LoneCarriageReturn(0))
expect LineEndings.decode("one\rtwo") == Err(LoneCarriageReturn(3))
expect LineEndings.decode("one\r") == Err(LoneCarriageReturn(3))
expect LineEndings.encode("one\ntwo\n", Lf) == "one\ntwo\n"
expect LineEndings.encode("one\ntwo\n", Crlf) == "one\r\ntwo\r\n"

expect {
	source = "one\ntwo\n"
	match LineEndings.decode(source) {
		Ok(decoded) => LineEndings.encode(decoded.content, decoded.line_ending) == source
		Err(_) => Bool.False
	}
}

expect {
	source = "one\r\ntwo\r\n"
	match LineEndings.decode(source) {
		Ok(decoded) => LineEndings.encode(decoded.content, decoded.line_ending) == source
		Err(_) => Bool.False
	}
}
