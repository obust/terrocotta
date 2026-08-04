## Application-wide visual defaults derived from a palette seed.
import Color
import Element
import Palette

## A compact theme containing colors and common visual sizing defaults.
Theme := {
	## Semantic colors generated from a seed.
	palette : Palette.Palette,
	## Default font used by text elements.
	font : Element.Font,
	## Base text size in pixels.
	font_size : F32,
	## Default corner radius in pixels.
	radius : F32,
	## Default gap between adjacent UI elements in pixels.
	gap : F32,
}.{
    is_eq : Theme, Theme -> Bool
    is_eq = |a, b| {
        a.palette == b.palette and Element.font_key(a.font) == Element.font_key(b.font) and a.font_size == b.font_size and a.radius == b.radius and a.gap == b.gap
    }

	## Override the common visual settings while preserving the palette.
	configure : Theme, { font : Element.Font, font_size : F32, radius : F32, gap : F32 } -> Theme
	configure = |theme, config| {
		palette: theme.palette,
		font: config.font,
		font_size: config.font_size,
		radius: config.radius,
		gap: config.gap,
	}
	## Generate a theme from a palette seed.
	from_seed : {
		background : Color,
		text : Color,
		primary : Color,
		success : Color,
		warning : Color,
		danger : Color,
	} -> Theme
	from_seed = |seed| {
		palette: Palette.from_seed(seed),
		font: Element.default_font,
		font_size: 16,
		radius: 8,
		gap: 8,
	}

	## Built-in light theme.
	light : Theme
	light = Theme.from_seed(Palette.light)

	## Built-in dark theme.
	dark : Theme
	dark = Theme.from_seed(Palette.dark)
}

## The dark theme should preserve the dark seed background.
expect {
	Theme.dark.palette.background.base.fill == Palette.dark.background
}
