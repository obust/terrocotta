## Read-only source surface with line gutter and syntax-colored spans.
import rr.Font
import tc.Color
import tc.Element exposing [box, style, text]
import tc.Program exposing [View]

import ../Theme exposing [theme]
import ../syntax/Html

Language : [HtmlLanguage, PlainText]
Document : { content : Str, language : Language, lines : List(Html.Line) }
DocumentState : [Loading(U64), Ready(Document), Failed(Str)]
Tab : { path : Str, title : Str, document : DocumentState }

SourceView := [].{
	view : Font, Tab -> View(msg)
	view = |font, tab| match tab.document {
		Loading(_) => centered("Loading ${tab.path}...", theme.palette.text.muted)
		Failed(message) => centered(message, theme.palette.danger.base.fill)
		Ready(document) => document_view(font, document)
	}

	empty : View(msg)
	empty = centered("Choose a file from Explorer", theme.palette.text.muted)
}

document_view : Font, Document -> View(msg)
document_view = |font, document| box(
	{
		id: Id("source-scroll"),
		style: |_| style
			.width(Grow({}))
			.height(Grow({}))
			.background(theme.palette.surface.base.fill)
			.font_family(font)
			.font_size(14)
			.line_height(22)
			.overflow(Scroll, Scroll)
			.child_align({ x: Start, y: Start }),
	},
	[
		box(
			{ style: |_| style.width(Fit({ min: 700 })).height(Fit({})).direction(Col).child_align({ x: Start, y: Start }) },
			document.lines.map_with_index(|line, index| line_view(line, index)),
		),
	],
)

line_view : Html.Line, U64 -> View(msg)
line_view = |line, index| box(
	{
		id: IdI("source-line", index),
		style: |_| style.width(Fit({ min: 700 })).height(Fixed(22)).direction(Row).child_align({ x: Start, y: Center }),
	},
	[
		box(
			{
				style: |_| style
					.width(Fixed(58))
					.height(Fixed(22))
					.pad(0, theme.gap + theme.gap / 2, 0, theme.gap / 2)
					.font_color(theme.palette.text.muted)
					.text_align(Right)
					.text_wrap(None)
					.child_align({ x: End, y: Center }),
			},
			[text((index + 1).to_str())],
		),
		box(
			{ style: |_| style.width(Fit({ min: 642 })).height(Fixed(22)).direction(Row).child_align({ x: Start, y: Center }) },
			line.spans.map(span_view),
		),
	],
)

span_view : Html.Span -> View(msg)
span_view = |span| box(
	{
		style: |_| style
			.width(Fit({}))
			.height(Fixed(22))
			.font_color(token_color(span.kind))
			.text_wrap(None)
			.child_align({ x: Start, y: Center }),
	},
	[text(span.text)],
)

token_color : Html.TokenKind -> Color
token_color = |kind| match kind {
	TextToken => theme.palette.surface.base.content
	Punctuation => theme.palette.text.muted
	TagName => theme.palette.primary.base.fill
	AttributeName => theme.palette.primary.strong.fill
	AttributeValue => theme.palette.success.base.fill
	Comment => theme.palette.text.muted
	Doctype => theme.palette.primary.weak.fill
	Entity => theme.palette.warning.base.fill
}

centered : Str, Color -> View(msg)
centered = |message, color| box(
	{ style: |_| style.width(Grow({})).height(Grow({})).background(theme.palette.surface.base.fill).font_color(color).child_align({ x: Center, y: Center }) },
	[text(message)],
)
