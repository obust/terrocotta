## Model-owned HSL/RGB channel sliders drawn with canvas gradients.
import ../Color
import ../Element exposing [View, box, text, style, canvas]
import ../Event
import ../Renderer
import ../Theme
import rr.Draw
import rr.Color as DrawingColor

ColorPicker :: [].{

	## Model-owned picker state; its HSLA representation stays in this module.
	State :: Hsla.{
		from_color : Color -> State
		from_color = |color| State.(Hsla.from_color(color))

		to_color : State -> Color
		to_color = |State.(color)| color.to_color()
	}

	Channel : [Red, Green, Blue, HslHue, HslSaturation, HslLightness, Alpha]

	## A channel gradient with a draggable, keyboard-adjustable circular handle.
	color_slider : Theme, { state : State, channel : Channel, on_change : State -> msg } -> View(msg, [Canvas(Box(Renderer.CanvasDraw)), ..payload])
	color_slider = |theme, config| {
		State.(stored) = config.state
		state = stored.normalized()
		channel = config.channel
		on_change = |color| (config.on_change)(State.(color))
		height = F32.max(16, theme.font_size)
		value = channel_value(state, channel)
		step = if channel == HslHue 1 else 0.01
		change_at = |event| on_change(with_channel(state, channel, pointer_value(channel, event.target.bounds, event.position)))
		draw! : Renderer.CanvasDraw
		draw! = |frame, bounds| {
			draw_track!(frame, bounds, state, channel)
			Ok({})
		}
		box(
			{
				style: |status| {
					base = style.width(Grow({ min: height * 6 })).height(Fixed(height)).radius(theme.radius)
					if status.focused {
						base.border({ color: theme.palette.primary.strong.fill, left: 1, right: 1, top: 1, bottom: 1 })
					} else {
						base
					}
				},
				events: [
					OnDragStart(Box.box(change_at)),
					OnDragMove(Box.box(change_at)),
					OnDragEnd(Box.box(change_at)),
					OnKeyPressed(KeyLeft, on_change(with_channel(state, channel, value - step))),
					OnKeyPressed(KeyRight, on_change(with_channel(state, channel, value + step))),
					OnKeyPressed(KeyHome, on_change(with_channel(state, channel, 0))),
					OnKeyPressed(KeyEnd, on_change(with_channel(state, channel, channel_max(channel)))),
				],
			},
			[canvas(draw!)],
		)
	}

	Config(msg) := { state : State, channels : List(Channel) ?? [HslHue, HslSaturation, HslLightness, Alpha], on_change : State -> msg }

	## A color preview and labeled channel sliders. The application owns the state.
	color_picker : Theme, Config(msg) -> View(msg, [Canvas(Box(Renderer.CanvasDraw)), ..payload])
	color_picker = |theme, config| {
		State.(stored) = config.state
		state = stored.normalized()
		preview! : Renderer.CanvasDraw
		preview! = |frame, bounds| {
			checker!(frame, bounds.position.x, bounds.position.y, bounds.size.w, bounds.size.h)
			frame.rectangle!({ x: bounds.position.x, y: bounds.position.y, width: bounds.size.w, height: bounds.size.h, style: Draw.filled(state.to_color().to_rrt()) })
			Ok({})
		}
		rows = config.channels.map(
			|channel| {
				value = channel_value(state, channel)
				shown = if channel == HslHue value else value * 100
				box(
					{ style: |_| style.direction(Col).child_align({ x: Start, y: Start }).height(Fit({})).gap(theme.gap / 2) },
					[
						ColorPicker.color_slider(theme, { state: config.state, channel, on_change: config.on_change }),
					],
				)
			},
		)
		box(
			{ style: |_| style.direction(Col).child_align({ x: Start, y: Start }).height(Fit({})).gap(theme.gap).font_size(theme.font_size).font_color(theme.palette.background.base.content) },
			[box({ style: |_| style.height(Fixed(theme.font_size * 3)) }, [canvas(preview!)])].concat(rows),
		)
	}
}

## HSLA color: hue in degrees (0–360), other components in 0–1.
## Component updates preserve hue through grayscale and black edits.
Hsla := { hue : F32, saturation : F32, lightness : F32, alpha : F32 }.{
	is_eq : _

	from_color : Color -> Hsla
	from_color = |color| {
		r = color.r.to_f32() / 255
		g = color.g.to_f32() / 255
		b = color.b.to_f32() / 255
		hi = F32.max(r, F32.max(g, b))
		lo = F32.min(r, F32.min(g, b))
		delta = hi - lo
		lightness = (hi + lo) / 2
		hue = if delta == 0 {
			0
		} else if hi == r {
			sector = (g - b) / delta
			(if sector < 0 sector + 6 else sector) * 60
		} else if hi == g {
			((b - r) / delta + 2) * 60
		} else {
			((r - g) / delta + 4) * 60
		}
		saturation = if delta == 0 0 else delta / (1 - F32.abs(2 * lightness - 1))
		{ hue, saturation, lightness, alpha: color.a.to_f32() / 255 }
	}

	to_color : Hsla -> Color
	to_color = |state| {
		s = state.normalized()
		chroma = (1 - F32.abs(2 * s.lightness - 1)) * s.saturation
		h = if s.hue == 360 0 else s.hue / 60
		x = chroma * (1 - F32.abs((h % 2) - 1))
		m = s.lightness - chroma / 2
		{ r, g, b } = match h {
			_ if h < 1 => { r: chroma, g: x, b: 0 }
			_ if h < 2 => { r: x, g: chroma, b: 0 }
			_ if h < 3 => { r: 0, g: chroma, b: x }
			_ if h < 4 => { r: 0, g: x, b: chroma }
			_ if h < 5 => { r: x, g: 0, b: chroma }
			_ => { r: chroma, g: 0, b: x }
		}
		Color.rgba(hsla_byte(r + m), hsla_byte(g + m), hsla_byte(b + m), hsla_byte(s.alpha))
	}

	normalized : Hsla -> Hsla
	normalized = |s| { hue: hsla_clamp(s.hue, 360), saturation: hsla_clamp(s.saturation, 1), lightness: hsla_clamp(s.lightness, 1), alpha: hsla_clamp(s.alpha, 1) }

	with_hue : Hsla, F32 -> Hsla
	with_hue = |self, value| { ..self.normalized(), hue: hsla_clamp(value, 360) }

	with_saturation : Hsla, F32 -> Hsla
	with_saturation = |self, value| { ..self.normalized(), saturation: hsla_clamp(value, 1) }

	with_lightness : Hsla, F32 -> Hsla
	with_lightness = |self, value| { ..self.normalized(), lightness: hsla_clamp(value, 1) }

	with_alpha : Hsla, F32 -> Hsla
	with_alpha = |self, value| { ..self.normalized(), alpha: hsla_clamp(value, 1) }
}

clamp : F32, F32 -> F32
clamp = |value, max| if value.is_finite() F32.min(max, F32.max(0, value)) else 0

byte : F32 -> U8
byte = |value| (clamp(value, 1) * 255).round_to_u8_try().ok_or(0)

channel_max : ColorPicker.Channel -> F32
channel_max = |channel| if channel == HslHue 360 else 1

## Use the same inset for pointer mapping and the visible handle's travel.
pointer_value : ColorPicker.Channel, Event.ElementBounds, Event.Point -> F32
pointer_value = |channel, bounds, point| {
	radius = F32.max(0, F32.min(bounds.height, bounds.width) / 2 - 1)
	width = bounds.width - radius * 2
	if width <= 0 {
		0
	} else {
		clamp((point.x - bounds.x - radius) / width, 1) * channel_max(channel)
	}
}

## RGB/saturation/alpha interpolate linearly; lightness has a midpoint and hue six sectors.
gradient_color : Hsla, ColorPicker.Channel, F32 -> DrawingColor.Rgba
gradient_color = |state, channel, progress| {
	if channel == HslHue {
		Hsla.to_color({ hue: progress * 360, saturation: 1, lightness: 0.5, alpha: 1 }).to_rrt()
	} else {
		color = with_channel(state, channel, progress * channel_max(channel)).to_color()
		(if channel == Alpha color else { ..color, a: 255 }).to_rrt()
	}
}

checker! : Draw.Frame, F32, F32, F32, F32 => {}
checker! = |frame, x, y, width, height| {
	var $row = 0.U64
	var $dy = 0.F32
	while $dy < height {
		var $col = 0.U64
		var $dx = 0.F32
		while $dx < width {
			color = if ($row + $col) % 2 == 0 DrawingColor.from_hex_rgb(0xB8B8B8) else DrawingColor.from_hex_rgb(0x777777)
			frame.rectangle!({ x: x + $dx, y: y + $dy, width: F32.min(5, width - $dx), height: F32.min(5, height - $dy), style: Draw.filled(color) })
			$dx = $dx + 5
			$col = $col + 1
		}
		$dy = $dy + 5
		$row = $row + 1
	}
}

draw_track! : Draw.Frame, Renderer.Bounds, Hsla, ColorPicker.Channel => {}
draw_track! = |frame, bounds, state, channel| {
	radius = F32.max(0, F32.min(bounds.size.h, bounds.size.w) / 2 - 1)
	x = bounds.position.x + radius
	width = F32.max(0, bounds.size.w - radius * 2)
	cy = bounds.position.y + bounds.size.h / 2
	r = F32.max(0, radius - 2)
	y = cy - r
	start = gradient_color(state, channel, 0)
	end = gradient_color(state, channel, 1)
	if channel == Alpha {
		checker!(frame, x, y, width, r * 2)
		for cx in [x, x + width] {
			frame.circle!({ center: { x: cx, y: cy }, radius: r, style: Draw.filled(DrawingColor.from_hex_rgb(0xB8B8B8)) })
		}
	}
	frame.circle!({ center: { x, y: cy }, radius: r, style: Draw.filled(start) })
	frame.circle!({ center: { x: x + width, y: cy }, radius: r, style: Draw.filled(end) })
	segments = if channel == HslHue 6.U64 else if channel == HslLightness 2 else 1
	for index in 0..<segments {
		left = index.to_f32() / segments.to_f32()
		right = (index + 1).to_f32() / segments.to_f32()
		# Gradient rectangles use integer host coordinates; share rounded edges to avoid gaps.
		left_x = (x + width * left).round_to_i32_try().ok_or(0).to_f32()
		right_x = (x + width * right).round_to_i32_try().ok_or(0).to_f32()
		frame.rectangle_gradient_h!({ x: left_x, y, width: right_x - left_x, height: r * 2, color_left: gradient_color(state, channel, left), color_right: gradient_color(state, channel, right) })
	}
	center = { x: x + width * channel_value(state, channel) / channel_max(channel), y: cy }
	frame.circle!({ center, radius, style: Draw.outlined(DrawingColor.black, 1) })
	frame.circle!({ center, radius: F32.max(0, radius - 1), style: Draw.outlined(DrawingColor.white, 2) })
}

## Pointer endpoints and drag capture outside the track clamp to channel limits.
expect {
	bounds = { x: 10, y: 0, width: 114, height: 16 }
	pointer_value(HslHue, bounds, { x: 17, y: 8 }) == 0
		and pointer_value(HslHue, bounds, { x: 67, y: 8 }) == 180
			and pointer_value(HslHue, bounds, { x: 200, y: 8 }) == 360
				and pointer_value(Alpha, { ..bounds, width: 0 }, { x: 0, y: 0 }) == 0
}

channel_value : Hsla, ColorPicker.Channel -> F32
channel_value = |state, channel| {
	s = state.normalized()
	match channel {
		HslHue => s.hue
		HslSaturation => s.saturation
		HslLightness => s.lightness
		Alpha => s.alpha
		Red => s.to_color().r.to_f32() / 255
		Green => s.to_color().g.to_f32() / 255
		Blue => s.to_color().b.to_f32() / 255
	}
}

with_channel : Hsla, ColorPicker.Channel, F32 -> Hsla
with_channel = |state, channel, value| {
	s = state.normalized()
	v = clamp(value, channel_max(channel))
	match channel {
		HslHue => s.with_hue(v)
		HslSaturation => s.with_saturation(v)
		HslLightness => s.with_lightness(v)
		Alpha => s.with_alpha(v)
		_ => {
			color = s.to_color()
			updated = match channel {
				Red => { ..color, r: byte(v) }
				Green => { ..color, g: byte(v) }
				_ => { ..color, b: byte(v) }
			}
			next = Hsla.from_color(updated)
			{ ..next, hue: if next.saturation == 0 s.hue else next.hue, alpha: s.alpha }
		}
	}
}

## RGB channel editing changes only the selected component and preserves alpha.
expect {
	s = Hsla.from_color(Color.rgba(0, 0, 255, 81))
	with_channel(s, Red, 1).to_color() == Color.rgba(255, 0, 255, 81)
}

## Keep HSLA components finite and inside their editing ranges.
hsla_clamp : F32, F32 -> F32
hsla_clamp = |value, max| if value.is_finite() F32.min(max, F32.max(0, value)) else 0

hsla_byte : F32 -> U8
hsla_byte = |value| (hsla_clamp(value, 1) * 255).round_to_u8_try().ok_or(0)

## Primary colors and alpha survive conversion in both directions.
expect {
	[Color.rgb(255, 0, 0), Color.green, Color.rgb(0, 0, 255), Color.white, Color.black, Color.rgba(123, 47, 209, 81)]
		.all(|color| Hsla.from_color(color).to_color() == color)
}

## HSL edits retain hue at the achromatic endpoints and keep alpha independent.
expect {
	s = Hsla.from_color(Color.rgb(0, 0, 255))
	gray = s.with_saturation(0)
	gray.hue == 240 and gray.with_saturation(1).to_color() == Color.rgb(0, 0, 255)
		and s.with_lightness(0).with_lightness(0.5).to_color() == Color.rgb(0, 0, 255)
			and s.with_alpha(0).to_color().a == 0
}

## Component updates clamp inputs while preserving the remaining HSLA state.
expect {
	s = Hsla.from_color(Color.rgb(0, 0, 255))
	s.with_hue(400).hue == 360 and s.with_saturation(-1).saturation == 0
		and s.with_lightness(2).lightness == 1 and s.with_alpha(F32.nan).alpha == 0
			and s.with_hue(120).saturation == s.saturation and s.with_alpha(0.5).hue == s.hue
}
