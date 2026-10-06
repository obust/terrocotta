## Application-wide visual defaults derived from a palette seed.
import Color
import Palette

## A compact theme containing colors and common visual sizing defaults.
Theme := {

	## Semantic colors generated from a seed.
	palette : Palette.Palette,

	## Base text size in pixels.
	font_size : F32,

	## Default corner radius in pixels.
	radius : F32,

	## Default gap between adjacent UI elements in pixels.
	gap : F32,
}.{
	is_eq : Theme, Theme -> Bool
	is_eq = |a, b| {
		a.palette == b.palette and a.font_size == b.font_size and a.radius == b.radius and a.gap == b.gap
	}

	## Generate a theme from a palette seed.
	from_seed : Palette.Seed -> Theme
	from_seed = |seed| {
		palette: Palette.from_seed(seed),
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

	## Built-in Atom One Light theme.
	atom_light : Theme
	atom_light = Theme.from_seed(Palette.atom_light)

	## Built-in Atom One Dark theme.
	atom_dark : Theme
	atom_dark = Theme.from_seed(Palette.atom_dark)

	## Built-in Dracula theme.
	dracula : Theme
	dracula = Theme.from_seed(Palette.dracula)

	## Built-in Solarized Dark theme.
	solarized_dark : Theme
	solarized_dark = Theme.from_seed(Palette.solarized_dark)
}

## The dark theme should preserve the dark seed background.
expect {
	Theme.dark.palette.surface.base.fill == Palette.dark.background
}
