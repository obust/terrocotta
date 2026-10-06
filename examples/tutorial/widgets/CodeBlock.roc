## Tutorial-local code presentation.
import tc.Color
import tc.Element exposing [box, style, text]
import tc.Program exposing [View]
import tc.Theme

CodeBlock := [].{
	## Minimal structural representation for guide snippets.
	Node := [Line(Str), Box(Str, List(Node))]

	## Present a Roc snippet without attempting syntax highlighting.
	code_block : Theme, Str -> View(msg)
	code_block = |theme, source| box(
		{
			style: |_| style
				.width(Grow({}))
				.height(Fit({}))
				.pad(12, 12, 12, 12)
				.background(0x17191d.Color)
				.font_color(0xd7e3f4.Color)
				.text_wrap(Newlines)
				.radius(theme.radius)
				.child_align({ x: Start, y: Start }),
		},
		[text(source)],
	)

	## Render a compact inline code token, similar to Markdown backticks.
	code_text : Theme, Str -> View(msg)
	code_text = |theme, content| box(
		{
			style: |_| style
				.width(Fit({}))
				.height(Fit({}))
				.pad(theme.gap / 4, theme.gap / 2, theme.gap / 4, theme.gap / 2)
				.background(theme.palette.primary.weak.fill)
				.font_color(theme.palette.primary.weak.content)
				.text_wrap(None)
				.child_align({ x: Start, y: Center })
				.radius(theme.radius),
		},
		[text(content)],
	)

	line : Str -> Node
	line = |source| Line(source)

	box_node : Str, List(Node) -> Node
	box_node = |config, children| Box(config, children)

	## Empty child lists remain inline. Only non-empty lists introduce lines and
	## tab indentation.
	format : Node -> Str
	format = |node| format_node(0, node)
}

format_node : U64, CodeBlock.Node -> Str
format_node = |depth, node| match node {
	Line(source) => source
	Box(config, children) => "box(${config}, ${format_children(depth, children)})"
}

format_children : U64, List(CodeBlock.Node) -> Str
format_children = |depth, children| {
	if children.len() == 0 {
		"[]"
	} else {
		"[\n${format_child_lines(depth + 1, children)}${tabs(depth)}]"
	}
}

format_child_lines : U64, List(CodeBlock.Node) -> Str
format_child_lines = |depth, children| {
	var $result = ""
	for child in children {
		$result = "${$result}${tabs(depth)}${format_node(depth, child)},\n"
	}
	$result
}

tabs : U64 -> Str
tabs = |depth| if depth == 0 "" else "\t${tabs(depth - 1)}"

expect {
	CodeBlock.format(CodeBlock.box_node("{ id: Id(\"empty\") }", [])) == "box({ id: Id(\"empty\") }, [])"
}

expect {
	CodeBlock.format(CodeBlock.box_node("{ id: Id(\"container\") }", [CodeBlock.box_node("{ id: Id(\"floating\") }", [CodeBlock.line("text(\"Floating badge\")")])]))
		== "box({ id: Id(\"container\") }, [\n\tbox({ id: Id(\"floating\") }, [\n\t\ttext(\"Floating badge\"),\n\t]),\n])"
}
