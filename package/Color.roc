## RGBA Color.
##
## Channels are 8-bit sRGB values.
## Alpha is 0 for transparent and 255 for fully opaque.
## Aligned with raylib RGBA semantic.
Color := {

	## Red channel.
	r : U8,

	## Green channel.
	g : U8,

	## Blue channel.
	b : U8,

	## Alpha channel.
	a : U8,
}.{
	is_eq : Color, Color -> Bool
	is_eq = |a, b| a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a

	## Construct a color from red, green, blue, and alpha channels.
	rgba : U8, U8, U8, U8 -> Color
	rgba = |r, g, b, a| { r, g, b, a }

	## Construct an opaque color from red, green, and blue channels.
	rgb : U8, U8, U8 -> Color
	rgb = |r, g, b| Color.rgba(r, g, b, 255)

	## Return a copy of a color with a different alpha channel.
	with_alpha : Color, U8 -> Color
	with_alpha = |color, a| { r: color.r, g: color.g, b: color.b, a }

	## Mix one channel toward another channel by an amount from 0 to 255.
	mix_channel : U8, U8, U8 -> U8
	mix_channel = |from, to, amount| {
		from_u32 = from.to_u32()
		to_u32 = to.to_u32()
		amount_u32 = amount.to_u32()
		((from_u32 * (255 - amount_u32) + to_u32 * amount_u32) // 255).to_u8_wrap()
	}

	## Mix one color toward another color by an amount from 0 to 255.
	mix : Color, Color, U8 -> Color
	mix = |from, to, amount| {
		Color.rgba(
			Color.mix_channel(from.r, to.r, amount),
			Color.mix_channel(from.g, to.g, amount),
			Color.mix_channel(from.b, to.b, amount),
			Color.mix_channel(from.a, to.a, amount),
		)
	}

	## Mix a color toward white by an amount from 0 to 255.
	lighten : Color, U8 -> Color
	lighten = |color, amount| Color.mix(color, Color.white, amount)

	## Mix a color toward black by an amount from 0 to 255.
	darken : Color, U8 -> Color
	darken = |color, amount| Color.mix(color, Color.black, amount)

	## Compute an integer approximation of perceived luminance.
	brightness : Color -> U32
	brightness = |color| {
		# Integer approximation of perceived luminance.
		(299 * color.r.to_u32() + 587 * color.g.to_u32() + 114 * color.b.to_u32()) // 1000
	}

	## Return whether a color is darker than the midpoint brightness.
	is_dark : Color -> Bool
	is_dark = |color| Color.brightness(color) < 128

	## Compute absolute brightness difference between two colors.
	contrast : Color, Color -> U32
	contrast = |a, b| {
		a_brightness = Color.brightness(a)
		b_brightness = Color.brightness(b)

		if a_brightness > b_brightness {
			a_brightness - b_brightness
		} else {
			b_brightness - a_brightness
		}
	}

	## Pick the candidate color with higher contrast against a fill.
	pick_readable : Color, (Color, Color) -> Color
	pick_readable = |fill, candidates| {
		if Color.contrast(fill, candidates.0) >= Color.contrast(fill, candidates.1) {
			candidates.0
		} else {
			candidates.1
		}
	}

	## Lighten dark colors and darken light colors by an amount from 0 to 255.
	deviate : Color, U8 -> Color
	deviate = |color, amount| {
		if Color.is_dark(color) {
			Color.lighten(color, amount)
		} else {
			Color.darken(color, amount)
		}
	}

	## Construct an opaque color from a 0xRRGGBB integer.
	hex : U32 -> Color
	hex = |hex| {
		r = ((hex // 0x10000) % 0x100).to_u8_wrap()
		g = ((hex // 0x100) % 0x100).to_u8_wrap()
		b = (hex % 0x100).to_u8_wrap()
		Color.rgba(r, g, b, 255)
	}

	## Construct a color from a numeral interpreted as 0xRRGGBB.
	from_numeral : Numeral -> Try(Color, [InvalidNumeral(Str)])
	from_numeral = |numeral| match U32.from_numeral(numeral) {
		Ok(hexadecimal) => {
			if hexadecimal > 0xFFFFFF {
				Err(InvalidNumeral("Color numeral must fit in 24 bits (0x000000 to 0xFFFFFF)"))
			} else {
				Ok(Color.hex(hexadecimal))
			}
		}
		Err(err) => Err(err)
	}

	## Fully transparent black.
	transparent : Color
	transparent = Color.rgba(0, 0, 0, 0)

	## Opaque black.
	black : Color
	black = Color.rgb(0, 0, 0)

	## Opaque blue.
	blue : Color
	blue = Color.rgb(0, 121, 241)

	## Opaque dark gray.
	dark_gray : Color
	dark_gray = Color.rgb(80, 80, 80)

	## Opaque gray.
	gray : Color
	gray = Color.rgb(130, 130, 130)

	## Opaque green.
	green : Color
	green = Color.rgb(0, 228, 48)

	## Opaque light gray.
	light_gray : Color
	light_gray = Color.rgb(200, 200, 200)

	## Opaque orange.
	orange : Color
	orange = Color.rgb(255, 161, 0)

	## Opaque pink.
	pink : Color
	pink = Color.rgb(255, 109, 194)

	## Opaque purple.
	purple : Color
	purple = Color.rgb(200, 122, 255)

	## Opaque red.
	red : Color
	red = Color.rgb(230, 41, 55)

	## Opaque white.
	white : Color
	white = Color.rgb(255, 255, 255)

	## Opaque yellow.
	yellow : Color
	yellow = Color.rgb(253, 249, 0)
}

## Mixing fully toward black should keep black.
expect {
	Color.mix(Color.black, Color.white, 0) == Color.black
}

## Mixing fully toward white should produce white.
expect {
	Color.mix(Color.black, Color.white, 255) == Color.white
}

## Lightening black fully should produce white.
expect {
	Color.lighten(Color.black, 255) == Color.white
}

## Darkening white fully should produce black.
expect {
	Color.darken(Color.white, 255) == Color.black
}

## Deviating black fully should produce white.
expect {
	Color.deviate(Color.black, 255) == Color.white
}

## White should be picked as readable on black.
expect {
	Color.pick_readable(Color.black, (Color.white, Color.black)) == Color.white
}

## Hex numeral literal suffix constructs white.
expect {
	0xFFFFFF.Color == Color.white
}

## Hex numeral literal suffix constructs black.
expect {
	0x000000.Color == Color.black
}

## Hex numeral literal suffix constructs pure red.
expect {
	0xFF0000.Color == Color.rgb(255, 0, 0)
}
