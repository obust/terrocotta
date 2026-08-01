## Semantic color palettes inspired by iced.
##
## A Seed contains the small set of colors authored by the application.
## Palette expands those colors into fill/content pairs that can be used
## directly by UI elements.
import Color

## A generated palette of semantic color scales ready for UI styling.
Palette := {

	## Neutral colors for application backgrounds and surfaces.
	background : Scale,

	## Accent colors for primary actions and focus states.
	primary : Scale,

	## Accent colors for successful or positive states.
	success : Scale,

	## Accent colors for cautionary or pending states.
	warning : Scale,

	## Accent colors for destructive or error states.
	danger : Scale,
}.{
    is_eq : Palette, Palette -> Bool
    is_eq = |a, b| {
        a.background == b.background and
            a.primary == b.primary and
                a.success == b.success and
                    a.warning == b.warning and
                        a.danger == b.danger
    }

	## Generate a usable palette from a compact authored seed.
	from_seed : Seed -> Palette
	from_seed = |seed| {
		weak_background = Color.mix(seed.background, seed.text, 26)

		{
			background: {
				weak: pair(weak_background, Color.pick_readable(weak_background, (seed.text, seed.background))),
				base: pair(seed.background, seed.text),
				strong: pair(seed.text, seed.background),
			},
			primary: scale(seed.primary, seed),
			success: scale(seed.success, seed),
			warning: scale(seed.warning, seed),
			danger: scale(seed.danger, seed),
		}
	}

	## Built-in light seed.
	light : Seed
	light = {
		background: Color.white,
		text: Color.black,
		primary: 0x5865F2.Color,
		success: 0x12664f.Color,
		warning: 0xb77e33.Color,
		danger: 0xc3423f.Color,
	}

	## Built-in dark seed.
	dark : Seed
	dark = {
		background: 0x2B2D31.Color,
		text: 0xDDDDDD.Color,
		primary: 0x5865F2.Color,
		success: 0x12664f.Color,
		warning: 0xffc14e.Color,
		danger: 0xc3423f.Color,
	}

	## Built-in [Atom One Light](https://github.com/atom/one-light-syntax) seed.
	atom_light : Seed
	atom_light = {
		background: 0xfafafa.Color, # syntax-bg
		text: 0x383a42.Color, # syntax-fg
		primary: 0x0184bc.Color, # blue
		success: 0x50a14f.Color, # green
		warning: 0xc18401.Color, # orange
		danger: 0xe45649.Color, # red
	}

	## Built-in [Atom One Dark](https://github.com/atom/one-dark-syntax) seed from.
	atom_dark : Seed
	atom_dark = {
		background: 0x282c34.Color, # syntax-bg
		text: 0xabb2bf.Color, # syntax-fg
		primary: 0x61afef.Color, # blue
		success: 0x98c379.Color, # green
		warning: 0xe5c07b.Color, # orange
		danger: 0xe06c75.Color, # red
	}

	## Built-in [Dracula](https://draculatheme.com) seed.
	dracula : Seed
	dracula = {
		background: 0x282A36.Color, # BACKGROUND
		text: 0xf8f8f2.Color, # FOREGROUND
		primary: 0xbd93f9.Color, # PURPLE
		success: 0x50fa7b.Color, # GREEN
		warning: 0xf1fa8c.Color, # YELLOW
		danger: 0xff5555.Color, # RED
	}

	## Built-in [Solarized Dark](https://ethanschoonover.com/solarized) seed.
	solarized_dark : Seed
	solarized_dark = {
		background: 0x002b36.Color,
		text: 0x839496.Color,
		primary: 0x2aa198.Color,
		success: 0x859900.Color,
		warning: 0xb58900.Color,
		danger: 0xdc322f.Color,
	}
}

## A fill color paired with readable content for that fill.
Pair : {

	## Surface or shape fill color.
	fill : Color,

	## Foreground content color intended to be readable on fill.
	content : Color,
}

## A weak/base/strong set of color pairs for one semantic role.
Scale : {

	## Low-emphasis variant of the base color.
	weak : Pair,

	## Main variant of the semantic color.
	base : Pair,

	## High-emphasis variant of the base color.
	strong : Pair,
}

## Authored input colors used to generate a Palette.
Seed : {

	## Main application background color.
	background : Color,

	## Default foreground text color.
	text : Color,

	## Base color for primary UI states.
	primary : Color,

	## Base color for success UI states.
	success : Color,

	## Base color for warning UI states.
	warning : Color,

	## Base color for danger UI states.
	danger : Color,
}

## Construct a Pair without modifying its content color.
pair : Color, Color -> Pair
pair = |fill, content| { fill, content }

## Generate a semantic color scale from a base color and mixing with seed background/text colors.
scale : Color, Seed -> Scale
scale = |base, seed| {
	weak = Color.mix(seed.background, base, 46)
	strong = Color.deviate(base, 26)

	{
		weak: pair(weak, Color.pick_readable(weak, (seed.text, seed.background))),
		base: pair(base, Color.pick_readable(base, (seed.text, seed.background))),
		strong: pair(strong, Color.pick_readable(strong, (seed.text, seed.background))),
	}
}

## Solarized Dark background base should preserve the seed background.
expect {
	Palette.from_seed(Palette.solarized_dark).background.base.fill == Palette.solarized_dark.background
}

## Solarized Dark primary base should preserve the seed primary color.
expect {
	Palette.from_seed(Palette.solarized_dark).primary.base.fill == Palette.solarized_dark.primary
}
