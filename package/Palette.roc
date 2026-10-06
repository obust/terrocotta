## Semantic palette derivation from a six-color authored seed.
import Color

Pair : { fill : Color, content : Color }
Scale : { weak : Pair, base : Pair, strong : Pair }
SurfaceRoles : { base : Pair, subtle : Pair, inverse : Pair }
TextRoles : { base : Color, muted : Color }
EdgeRoles : { border : Color, control : Color, focus : Color }

## The only authored theme input. Seed colors must be opaque.
Seed : { background : Color, text : Color, primary : Color, success : Color, warning : Color, danger : Color }

## Generated colors consumed by widgets. Roles describe intent, not luminance.
Palette := {
	surface : SurfaceRoles,
	text : TextRoles,
	edge : EdgeRoles,
	primary : Scale,
	success : Scale,
	warning : Scale,
	danger : Scale,
}.{
	is_eq : Palette, Palette -> Bool
	is_eq = |a, b| a.surface == b.surface and a.text == b.text and a.edge == b.edge and a.primary == b.primary and a.success == b.success and a.warning == b.warning and a.danger == b.danger

	## Generate a usable palette. This is total; use validate for diagnostics.
	from_seed : Seed -> Palette
	from_seed = |seed| {
		base = pair(seed.background, seed.text)
		subtle_fill = Color.mix(seed.background, seed.text, neutral_subtle_mix)
		subtle = pair_for(subtle_fill, seed)
		surfaces = { base, subtle, inverse: pair(seed.text, seed.background) }
		{
			surface: surfaces,
			text: { base: base.content, muted: muted_text(seed, surfaces) },
			edge: {
				border: Color.with_alpha(seed.text, divider_alpha),
				control: quiet_edge(seed.text, seed.background, surfaces),
				focus: focus_edge(seed.primary, seed.text, surfaces),
			},
			primary: scale(seed.primary, seed),
			success: scale(seed.success, seed),
			warning: scale(seed.warning, seed),
			danger: scale(seed.danger, seed),
		}
	}

	hovered : Palette, Pair -> Pair
	hovered = |_self, colors| apply_layer(colors, colors.content, hover_fill_alpha)
	focused : Palette, Pair -> Pair
	focused = |_self, colors| apply_layer(colors, colors.content, focus_fill_alpha)
	pressed : Palette, Pair -> Pair
	pressed = |_self, colors| apply_layer(colors, colors.content, pressed_fill_alpha)
	selected : Palette, Pair -> Pair
	selected = |self, colors| apply_layer(colors, self.primary.base.fill, selected_fill_alpha)
	disabled_content : Palette, Color -> Color
	disabled_content = |_self, content| Color.with_alpha(content, disabled_content_alpha)
	scrim : Palette -> Color
	scrim = |_self| Color.with_alpha(Color.black, scrim_alpha)

	light : Seed
	light = { background: Color.white, text: Color.black, primary: 0x5865F2.Color, success: 0x12664f.Color, warning: 0xb77e33.Color, danger: 0xc3423f.Color }
	dark : Seed
	dark = { background: 0x2B2D31.Color, text: 0xDDDDDD.Color, primary: 0x5865F2.Color, success: 0x12664f.Color, warning: 0xffc14e.Color, danger: 0xc3423f.Color }
	atom_light : Seed
	## Atom One Light UI colors. These are UI semantic roles, not syntax tokens.
	atom_light = { background: 0xfafafa.Color, text: 0x424242.Color, primary: 0x4078f2.Color, success: 0x3bba54.Color, warning: 0xc49331.Color, danger: 0xe04b3e.Color }
	atom_dark : Seed
	## Atom One Dark UI colors. These are UI semantic roles, not syntax tokens.
	atom_dark = { background: 0x282c34.Color, text: 0x9da5b4.Color, primary: 0x528bff.Color, success: 0x2ba143.Color, warning: 0xad7c0b.Color, danger: 0xd13c2e.Color }
	dracula : Seed
	## Dracula uses purple for primary UI emphasis; green/yellow/red retain status meaning.
	dracula = { background: 0x282A36.Color, text: 0xf8f8f2.Color, primary: 0xbd93f9.Color, success: 0x50fa7b.Color, warning: 0xf1fa8c.Color, danger: 0xff5555.Color }
	solarized_dark : Seed
	## Solarized Dark uses cyan for primary UI emphasis; green/yellow/red retain status meaning.
	solarized_dark = { background: 0x002b36.Color, text: 0x839496.Color, primary: 0x2aa198.Color, success: 0x859900.Color, warning: 0xb58900.Color, danger: 0xdc322f.Color }
}

neutral_subtle_mix : U8
neutral_subtle_mix = 26
semantic_weak_mix : U8
semantic_weak_mix = 46
semantic_strong_mix : U8
semantic_strong_mix = 26
divider_alpha : U8
divider_alpha = 64
hover_fill_alpha : U8
hover_fill_alpha = 20
focus_fill_alpha : U8
focus_fill_alpha = 20
selected_fill_alpha : U8
selected_fill_alpha = 46
pressed_fill_alpha : U8
pressed_fill_alpha = 56
disabled_content_alpha : U8
disabled_content_alpha = 102
scrim_alpha : U8
scrim_alpha = 128
minimum_text_contrast : F32
minimum_text_contrast = 4.5
minimum_edge_contrast : F32
minimum_edge_contrast = 3

pair : Color, Color -> Pair
pair = |fill, content| { fill, content }
pair_for : Color, Seed -> Pair
pair_for = |fill, seed| pair(fill, content_for(fill, seed))
content_for : Color, Seed -> Color
content_for = |fill, seed| {
	authored = higher_contrast(seed.text, seed.background, fill)
	if Color.contrast_ratio(fill, authored) >= minimum_text_contrast authored else higher_contrast(Color.black, Color.white, fill)
}
higher_contrast : Color, Color, Color -> Color
higher_contrast = |first, second, against| if Color.contrast_ratio(first, against) >= Color.contrast_ratio(second, against) first else second
scale : Color, Seed -> Scale
scale = |base_fill, seed| {
	weak_fill = Color.mix(seed.background, base_fill, semantic_weak_mix)
	strong_candidate = Color.mix(base_fill, seed.text, semantic_strong_mix)
	strong_fill = higher_contrast(base_fill, strong_candidate, seed.background)
	{ weak: pair_for(weak_fill, seed), base: pair_for(base_fill, seed), strong: pair_for(strong_fill, seed) }
}
muted_text : Seed, SurfaceRoles -> Color
muted_text = |seed, surfaces| furthest_toward(seed.text, seed.background, surfaces, minimum_text_contrast)
quiet_edge : Color, Color, SurfaceRoles -> Color
quiet_edge = |text, background, surfaces| furthest_toward(text, background, surfaces, minimum_edge_contrast)
focus_edge : Color, Color, SurfaceRoles -> Color
focus_edge = |primary, text, surfaces| first_toward(primary, text, surfaces, minimum_edge_contrast)
furthest_toward : Color, Color, SurfaceRoles, F32 -> Color
furthest_toward = |from, to, surfaces, minimum| {
	go = |amount| if amount < 0 {
		from
	} else {
		candidate = Color.mix(from, to, amount.to_u8_wrap())
		if neutral_contrast(candidate, surfaces) >= minimum candidate else go(amount - 1)
	}
	go(255)
}
first_toward : Color, Color, SurfaceRoles, F32 -> Color
first_toward = |from, to, surfaces, minimum| {
	go = |amount| if amount > 255 {
		from
	} else {
		candidate = Color.mix(from, to, amount.to_u8_wrap())
		if neutral_contrast(candidate, surfaces) >= minimum candidate else go(amount + 1)
	}
	go(0)
}
neutral_contrast : Color, SurfaceRoles -> F32
neutral_contrast = |color, surfaces| F32.min(Color.contrast_ratio(color, surfaces.base.fill), Color.contrast_ratio(color, surfaces.subtle.fill))
apply_layer : Pair, Color, U8 -> Pair
apply_layer = |colors, layer_color, opacity| pair(Color.composite_over(Color.with_alpha(layer_color, opacity), colors.fill), colors.content)

expect Palette.from_seed(Palette.solarized_dark).surface.base.fill == Palette.solarized_dark.background
expect Palette.from_seed(Palette.solarized_dark).primary.base.fill == Palette.solarized_dark.primary
