## UI types and helpers for the Roc-Clay layout engine.
## Provides text, box, and stack for building view trees as Iter(UIMessage).
import Color
import Assets

Element := [].{

	Font : Box(U64)

	default_font : Font
	default_font = Box.box(0)

	Sizing : [Fit({ min : F32, max : F32 }), Grow({ min : F32, max : F32 }), Fixed(F32), Percent(F32)]

	Direction : [Row, Col]

	ChildAlign : [Start, Center, End]

	TextAlign : [Left, Center, Right]

	TextStyle : [Auto, Font(TextConfig)]

	PointerEvent : {
		x : F32,
		y : F32,
		left_down : Bool,
	}

	Event(msg) : [
		OnClick(msg),
	]

	BorderConfig : {
		# Border color.
		color : Color,
		# Left border width.
		left : F32,
		# Right border width.
		right : F32,
		# Top border width.
		top : F32,
		# Bottom border width.
		bottom : F32,
	}

	ImageConfig : {
		texture : Assets.Texture,
		tint : Color.Color,
	}

	LayoutConfig : {
		# Width inside its parent.
		width : Sizing,
		# Height is inside its parent.
		height : Sizing,
		# Adds inner space between this element's bounds and its children.
		pad : { left : F32, right : F32, top : F32, bottom : F32 },
		# Chooses whether children are laid out horizontally or vertically.
		direction : Direction,
		# Gap between adjacent children along the layout direction.
		gap : F32,
		# Aligns children inside the remaining inner space.
		child_align : { x : ChildAlign, y : ChildAlign },
	}

	TextConfig : {
		# Text font.
		font : Font,
		# Text font size (in px).
		font_size : F32,
		# Text color.
		color : Color,
		# Text box height (in px), or 0 to use the measured font height.
		line_height : F32,
		# Horizontal alignment inside the text box.
		align : TextAlign,
	}

	BoxConfig(msg) := {
		layout : LayoutConfig,
		background : Color,
		radius : F32,
		border : BorderConfig,
		text : TextStyle,
		events : List(Event(msg)),
	}.{

		# LayoutConfig
		width : BoxConfig(msg), Sizing -> BoxConfig(msg)
		width = |self, width| {
			{ ..self, layout: { ..self.layout, width: width } }
		}

		height : BoxConfig(msg), Sizing -> BoxConfig(msg)
		height = |self, height| {
			{ ..self, layout: { ..self.layout, height: height } }
		}

		pad : BoxConfig(msg), (F32, F32, F32, F32) -> BoxConfig(msg)
		pad = |self, padding| {
			{ ..self, layout: { ..self.layout, pad: { left: padding.0, right: padding.1, top: padding.2, bottom: padding.3 } } }
		}

		direction : BoxConfig(msg), Direction -> BoxConfig(msg)
		direction = |self, direction| {
			{ ..self, layout: { ..self.layout, direction: direction } }
		}

		gap : BoxConfig(msg), F32 -> BoxConfig(msg)
		gap = |self, gap| {
			{ ..self, layout: { ..self.layout, gap: gap } }
		}

		child_align : BoxConfig(msg), {x: ChildAlign, y: ChildAlign } -> BoxConfig(msg)
		child_align = |self, align| {
			{ ..self, layout: { ..self.layout, child_align: align } }
		}

		# TextConfig
		font_family : BoxConfig(msg), Font -> BoxConfig(msg)
		font_family = |self, font| {
			text = match self.text {
				Auto =>  default_text,
				Font(cfg) => cfg,
			}
			{ ..self, text: Font({ ..text, font: font }) }
		}
		font_size : BoxConfig(msg), F32 -> BoxConfig(msg)
		font_size = |self, size| {
			text = match self.text {
				Auto =>  default_text,
				Font(cfg) => cfg,
			}
			{ ..self, text: Font({ ..text, font_size: size }) }
		}
		font_color : BoxConfig(msg), Color -> BoxConfig(msg)
		font_color = |self, color| {
			text = match self.text {
				Auto =>  default_text,
				Font(cfg) => cfg,
			}
			{ ..self, text: Font({ ..text, color: color }) }
		}
		line_height : BoxConfig(msg), F32 -> BoxConfig(msg)
		line_height = |self, line_height| {
			text = match self.text {
				Auto =>  default_text,
				Font(cfg) => cfg,
			}
			{ ..self, text: Font({ ..text, line_height: line_height }) }
		}
		text_align : BoxConfig(msg), TextAlign -> BoxConfig(msg)
		text_align = |self, align| {
			text = match self.text {
				Auto =>  default_text,
				Font(cfg) => cfg,
			}
			{ ..self, text: Font({ ..text, align: align }) }
		}

		# Box style
		background : BoxConfig(msg), Color -> BoxConfig(msg)
		background = |self, color| {
			{ ..self, background: color }
		}

		radius : BoxConfig(msg), F32 -> BoxConfig(msg)
		radius = |self, radius| {
			{ ..self, radius: radius }
		}

		border : BoxConfig(msg), BorderConfig -> BoxConfig(msg)
		border = |self, border| {
			{ ..self, border: border }
		}

	}

	ViewMessage(msg) : [
		OpenBox(BoxConfig(msg)),
		CloseBox,
		Text(Str),
		Image(ImageConfig),
	]

	View(msg) : Iter(ViewMessage(msg))

	default_layout : LayoutConfig
	default_layout = {
		width: Fit({ min: 0, max: 10000 }),
		height: Fit({ min: 0, max: 10000 }),
		pad: { left: 0, right: 0, top: 0, bottom: 0 },
		gap: 0,
		child_align: { x: Start, y: Start },
		direction: Row,
	}

	default_text : TextConfig
	default_text = { font: default_font, font_size: 5, color: Color.black, line_height: 0, align: Left }

	style : BoxConfig(msg)
	style = { layout: Element.default_layout, background: Color.transparent, radius: 0, border: { color: Color.transparent, left: 0, right: 0, top: 0, bottom: 0 }, text: Auto, events: [] }

	default_box : BoxConfig(msg)
	default_box = Element.style

	pad_all : F32 -> { left : F32, right : F32, top : F32, bottom : F32 }
	pad_all = |v| { left: v, right: v, top: v, bottom: v }

	pad_xy : F32, F32 -> { left : F32, right : F32, top : F32, bottom : F32 }
	pad_xy = |x, y| { left: x, right: x, top: y, bottom: y }

	## Create a single-element Iter containing a Text message.
	text : Str -> View(msg)
	text = |content| [Text(content)].iter()

	box : BoxConfig(msg), List(View(msg)) -> View(msg)
	box = |cfg, children| {
		# Wrap children in OpenBox/CloseBox and flatten iterator
		open = Iter.single(OpenBox(cfg))
		view = children.fold(open, |acc, child| acc.concat(child))
		view.append(CloseBox)
	}
}

expect {
	view = Element.box(Element.style, [])

	match view.collect() {
		[OpenBox(_), CloseBox] => Bool.True
		_ => Bool.False
	}
}

expect {
	view = Element.box(
		Element.style,
		[
			Element.box(
				Element.style,
				[
					Element.text("hello"),
				],
			),
			Element.text("world"),
		],
	)

	match view.collect() {
		[OpenBox(_), OpenBox(_), Text("hello"), CloseBox, Text("world"), CloseBox] => Bool.True
		_ => Bool.False
	}
}
