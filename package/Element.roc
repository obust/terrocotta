## UI types and helpers for the Roc-Clay layout engine.
## Provides text, box, and stack for building view trees as Iter(UIMessage).
import Color
import Event
import rrt.Font

Element := [].{

	Sizing : [
		# Size to content, clamped to min/max pixels.
		Fit({ min : F32 ?? 0, max : F32 ?? 10000 }),
		# Fill available space, clamped to min/max pixels.
		Grow({ min : F32 ?? 0, max : F32 ?? 10000 }),
		# Use an exact size in pixels.
		Fixed(F32),
		# Use a fraction of the parent's available size.
		Percent(F32),
	]

	Direction : [
		# Lay children out horizontally.
		Row,
		# Lay children out vertically.
		Col,
	]

	ChildAlign : [
		# Place children at the start of the available space.
		Start,
		# Place children in the center of the available space.
		Center,
		# Place children at the end of the available space.
		End,
	]

	TextAlign : [
		# Align text to the left edge.
		Left,
		# Align text to the center.
		Center,
		# Align text to the right edge.
		Right,
	]

	TextWrap : [
		# Break text on spaces and explicit newlines.
		Words,
		# Break text only on explicit newlines.
		Newlines,
		# Keep text as a single raw render line, preserving embedded newlines.
		None,
	]

	TextStyle : [Auto, Font(TextConfig)]

	Overflow : [Visible, Hidden, Scroll]

	AttachPoint : [
		LeftTop,
		LeftCenter,
		LeftBottom,
		CenterTop,
		Center,
		CenterBottom,
		RightTop,
		RightCenter,
		RightBottom,
	]

	FloatingConfig : {
		z_index : I16,
		offset : { x : F32, y : F32 },
		expand : { w : F32, h : F32 },
		attach_points : { element : AttachPoint, target : AttachPoint },
		capture : [Capture, Passthrough],
		clip_to : [NoClip, AttachedParent],
	}

	## Select the attachment rectangle for a floating element.
	FloatingTarget : [
		# Attach to the full layout viewport.
		Root,
		# Attach to the element's hierarchical parent.
		Parent,
		# Attach to a specific stable element ID.
		Element(ElementId),
	]

	## Remove an element from normal flow and attach it to a target rectangle.
	Floating : [
		NoFloating,
		Floating({ target : FloatingTarget, config : FloatingConfig }),
	]

	BoxStatus : {
		hovered : Bool,
		pressed : Bool,
		focused : Bool,
		disabled : Bool,
	}

	ElementId : [
		# Parent ID plus child offset; stable while parent identity and sibling order stay stable.
		Auto,
		# Globally scoped string ID.
		Id(Str),
		# Globally scoped string ID plus stable domain offset.
		IdI(Str, U64),
		# Parent-scoped string ID.
		LocalId(Str),
		# Parent-scoped string ID plus stable domain offset.
		LocalIdI(Str, U64),
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
		font : [InheritFont, FontHandle(Font)],
		# Text font size (in px).
		font_size : F32,
		# Space between glyphs (in px).
		spacing : F32,
		# Text color.
		color : Color,
		# Text box height (in px), or 0 to use the measured font height.
		line_height : F32,
		# Horizontal alignment inside the text box.
		align : TextAlign,
		# Controls where text may wrap into multiple render lines.
		wrap : TextWrap,
	}

	BoxConfig := {
		layout : LayoutConfig,
		background : Color,
		radius : F32,
		border : BorderConfig,
		text : TextStyle,
		overflow : { x : Overflow, y : Overflow },
		floating : Floating,
	}.{

		# LayoutConfig
		width : BoxConfig, Sizing -> BoxConfig
		width = |self, width| {
			{ ..self, layout: { ..self.layout, width: width } }
		}

		height : BoxConfig, Sizing -> BoxConfig
		height = |self, height| {
			{ ..self, layout: { ..self.layout, height: height } }
		}

		## Set padding in CSS order: top, right, bottom, left.
		pad : BoxConfig, F32, F32, F32, F32 -> BoxConfig
		pad = |self, top, right, bottom, left| {
			{ ..self, layout: { ..self.layout, pad: { top, right, bottom, left } } }
		}

		direction : BoxConfig, Direction -> BoxConfig
		direction = |self, direction| {
			{ ..self, layout: { ..self.layout, direction: direction } }
		}

		gap : BoxConfig, F32 -> BoxConfig
		gap = |self, gap| {
			{ ..self, layout: { ..self.layout, gap: gap } }
		}

		child_align : BoxConfig, { x : ChildAlign, y : ChildAlign } -> BoxConfig
		child_align = |self, align| {
			{ ..self, layout: { ..self.layout, child_align: align } }
		}

		# TextConfig
		font_family : BoxConfig, Font -> BoxConfig
		font_family = |self, font| {
			text = match self.text {
				Auto => default_text
				Font(cfg) => cfg
			}
			{ ..self, text: Font({ ..text, font: FontHandle(font) }) }
		}
		font_size : BoxConfig, F32 -> BoxConfig
		font_size = |self, size| {
			text = match self.text {
				Auto => default_text
				Font(cfg) => cfg
			}
			{ ..self, text: Font({ ..text, font_size: size }) }
		}
		spacing : BoxConfig, F32 -> BoxConfig
		spacing = |self, spacing| {
			text = match self.text {
				Auto => default_text
				Font(cfg) => cfg
			}
			{ ..self, text: Font({ ..text, spacing }) }
		}
		font_color : BoxConfig, Color -> BoxConfig
		font_color = |self, color| {
			text = match self.text {
				Auto => default_text
				Font(cfg) => cfg
			}
			{ ..self, text: Font({ ..text, color: color }) }
		}
		line_height : BoxConfig, F32 -> BoxConfig
		line_height = |self, line_height| {
			text = match self.text {
				Auto => default_text
				Font(cfg) => cfg
			}
			{ ..self, text: Font({ ..text, line_height: line_height }) }
		}
		text_align : BoxConfig, TextAlign -> BoxConfig
		text_align = |self, align| {
			text = match self.text {
				Auto => default_text
				Font(cfg) => cfg
			}
			{ ..self, text: Font({ ..text, align: align }) }
		}
		text_wrap : BoxConfig, TextWrap -> BoxConfig
		text_wrap = |self, wrap| {
			text = match self.text {
				Auto => default_text
				Font(cfg) => cfg
			}
			{ ..self, text: Font({ ..text, wrap: wrap }) }
		}

		# Box style
		background : BoxConfig, Color -> BoxConfig
		background = |self, color| {
			{ ..self, background: color }
		}

		radius : BoxConfig, F32 -> BoxConfig
		radius = |self, radius| {
			{ ..self, radius: radius }
		}

		border : BoxConfig, BorderConfig -> BoxConfig
		border = |self, border| {
			{ ..self, border: border }
		}

		## Set horizontal and vertical overflow behavior.
		overflow : BoxConfig, Overflow, Overflow -> BoxConfig
		overflow = |self, x, y| { ..self, overflow: { x, y } }

		## Remove this box from normal flow and attach it as a floating root.
		floating : BoxConfig, Floating -> BoxConfig
		floating = |self, value| { ..self, floating: value }

	}

	ElementOp(msg, texture) : [
		OpenBox(ElementId, BoxStatus -> BoxConfig, List(Event.Handler(msg))),
		CloseBox,
		Text(Str),
		Image(texture),
	]

	View(msg, texture) : Iter(ElementOp(msg, texture))

	## Attributes attached to a box. Omitted attributes use the standard box
	## identity, style, and event behavior.
	BoxAttr(msg) : {
		id : ElementId ?? Auto,
		style ?: BoxStatus -> BoxConfig,
		events ?: List(Event.Handler(msg)),
	}

	default_layout : LayoutConfig
	default_layout = {
		width: Grow({}),
		height: Grow({}),
		pad: { left: 0, right: 0, top: 0, bottom: 0 },
		gap: 0,
		child_align: { x: Center, y: Center },
		direction: Row,
	}

	default_text : TextConfig
	default_text = { font: InheritFont, font_size: 5, spacing: 1, color: Color.black, line_height: 0, align: Left, wrap: Words }

	default_floating_config : FloatingConfig
	default_floating_config = {
		z_index: 0,
		offset: { x: 0, y: 0 },
		expand: { w: 0, h: 0 },
		attach_points: { element: LeftTop, target: LeftTop },
		capture: Capture,
		clip_to: NoClip,
	}

	## Create a floating declaration for any attachment target.
	floating_at : FloatingTarget, I16, { element : Element.AttachPoint, target : Element.AttachPoint } -> Floating
	floating_at = |target, z, points| Floating({
		target,
		config: { ..default_floating_config, z_index: z, attach_points: points },
	})

	style : BoxConfig
	style = { layout: Element.default_layout, background: Color.transparent, radius: 0, border: { color: Color.transparent, left: 0, right: 0, top: 0, bottom: 0 }, text: Auto, overflow: { x: Hidden, y: Hidden }, floating: NoFloating }

	## Create a text leaf element.
	text : Str -> View(msg, texture)
	text = |content| [Text(content)].iter()

	## Create a image leaf element.
	image : texture -> View(msg, texture)
	image = |texture| [Image(texture)].iter()

	## Create a box container element.
	box : BoxAttr(msg), List(View(msg, texture)) -> View(msg, texture)
	box = |attr, children| {
		style_fn = attr.?style ?? |_| style
		events = attr.?events ?? []

		# Wrap children in OpenBox/CloseBox and flatten iterator
		open = Iter.single(OpenBox(attr.id, style_fn, events))
		view = children.fold(open, |acc, child| acc.concat(child))
		view.append(CloseBox)
	}
}

expect {
	view = Element.box(
		{},
		[],
	)

	match view.collect() {
		[OpenBox(Auto, style_fn, []), CloseBox] => {
			status = { hovered: False, pressed: False, focused: False, disabled: False }
			(style_fn(status)).radius == Element.style.radius
		}
		_ => Bool.False
	}
}

expect {
	sizing : Element.Sizing
	sizing = Fit({})
	match sizing {
		Fit(bounds) => bounds.min == 0 and bounds.max == 10000
		_ => False
	}
}

expect {
	sizing : Element.Sizing
	sizing = Grow({})
	match sizing {
		Grow(bounds) => bounds.min == 0 and bounds.max == 10000
		_ => False
	}
}

expect {
	view = Element.box(
		{
			events: [OnClick("save")],
			id: Id("button"),
			style: |_| Element.style.radius(7),
		},
		[],
	)

	match view.collect() {
		[OpenBox(Id("button"), style_fn, [OnClick("save")]), CloseBox] => {
			status = { hovered: False, pressed: False, focused: False, disabled: False }
			(style_fn(status)).radius == 7
		}
		_ => Bool.False
	}
}

expect {
	view = Element.box(
		{},
		[
			Element.box(
				{},
				[
					Element.text("hello"),
				],
			),
			Element.text("world"),
		],
	)

	match view.collect() {
		[OpenBox(Auto, _, []), OpenBox(Auto, _, []), Text("hello"), CloseBox, Text("world"), CloseBox] => Bool.True
		_ => Bool.False
	}
}
