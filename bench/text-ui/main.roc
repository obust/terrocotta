## Text-heavy layout benchmark.
##
## The workload models a document/inbox screen with a sidebar, toolbar, a
## clipped scrolling list, and a fixed-size article sample. Successive primary
## zones retain one Layout so warm-cache, content-change, resize, and scroll
## costs exercise the same rebuild path used by Program.

app [Model, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst",
	tc: "../../package/main.roc",
}

import rr.App
import rr.Draw
import rr.Trace
import "corpus/gutenberg-alice.txt" as alice : Str
import "corpus/wikimedia-typography.json" as wiki : Str
import "corpus/rfc-5732.txt" as rfc : Str
import "corpus/python-introduction.html" as python_docs : Str
import tc.Element exposing [ChildAlign.*, Direction.*, ElementId.*, Overflow.*, box, style, text]
import tc.Layout

Model : { checksum : U64 }

Msg : []

Corpus : [Alice, Wiki, Rfc, Python, Mixed]

sample_bytes : U64
sample_bytes = 24000

sample_chunks : U64
sample_chunks = 4

sample_chunk_bytes : U64
sample_chunk_bytes = sample_bytes // sample_chunks

full_rows : U64
full_rows = 75

program = { init!, update!, render! }

init! : App.Init(Model, [])
init! = App.init(App.default, |_io| Ok({ checksum: 0 }))

update! : Model, App.Input(Msg), App.Io => Try(Model, [Exit(I64)])
update! = |model, _input, _io| {
	# The primary sequence deliberately carries the same Layout between zones.
	# Layout.clear retains canonical text measurements and advances generation.
	cold_layout = cold_scenario!("text-ui.cold-build", 960, full_rows, Bool.False, Mixed)?
	cold_checksum = layout_checksum(cold_layout)
	warm_layout = rebuild_scenario!("text-ui.warm-rebuild", cold_layout, 960, full_rows, Bool.False, Mixed, 0, 0)?
	warm_checksum = layout_checksum(warm_layout)
	changed_layout = rebuild_scenario!("text-ui.one-text-change", warm_layout, 960, full_rows, Bool.True, Mixed, 0, 0)?
	changed_checksum = layout_checksum(changed_layout)
	resized_layout = rebuild_scenario!("text-ui.warm-resize", changed_layout, 640, full_rows, Bool.True, Mixed, 0, 0)?
	rows_id = scroll_node_id(resized_layout)
	resized_checksum = layout_checksum(resized_layout)
	scrolled_layout = rebuild_scenario!("text-ui.retained-scroll", resized_layout, 640, full_rows, Bool.True, Mixed, rows_id, -320)?
	if !has_scroll_offset(scrolled_layout, -320) {
		crash "text UI benchmark did not retain the requested scroll offset"
	}
	scrolled_checksum = layout_checksum(scrolled_layout)
	swept_layout = resize_sweep_scenario!("text-ui.resize-sweep", scrolled_layout, full_rows, Bool.True, Mixed)?
	swept_checksum = layout_checksum(swept_layout)

	# Equal-byte cold diagnostics isolate corpus shape from input volume.
	alice_layout = cold_scenario!("text-ui.corpus.alice", 960, full_rows, Bool.False, Alice)?
	wiki_layout = cold_scenario!("text-ui.corpus.wikipedia", 960, full_rows, Bool.False, Wiki)?
	rfc_layout = cold_scenario!("text-ui.corpus.rfc", 960, full_rows, Bool.False, Rfc)?
	python_layout = cold_scenario!("text-ui.corpus.python", 960, full_rows, Bool.False, Python)?

	checksum = cold_checksum
		+ warm_checksum
		+ changed_checksum
		+ resized_checksum
		+ scrolled_checksum
		+ swept_checksum
		+ layout_checksum(alice_layout)
		+ layout_checksum(wiki_layout)
		+ layout_checksum(rfc_layout)
		+ layout_checksum(python_layout)
	Ok({ ..model, checksum })
}

render! : Model, Draw.Frame => Try({}, [Exit(I64)])
render! = |_model, _frame| Ok({})

cold_scenario! : Str, F32, U64, Bool, Corpus => Try(Layout.Layout([]), [Exit(I64)])
cold_scenario! = |label, width, rows, changed, corpus| {
	zone = Trace.begin!(label)
	layout = build_into(Layout.test_layout(), width, rows, changed, corpus, 0, 0).map_err(|_| Exit(1))?
	Trace.end!(zone)
	Ok(require_node_count(layout, rows))
}

rebuild_scenario! : Str, Layout.Layout([]), F32, U64, Bool, Corpus, U64, F32 => Try(Layout.Layout([]), [Exit(I64)])
rebuild_scenario! = |label, previous, width, rows, changed, corpus, retained_scroll_id, scroll_y| {
	zone = Trace.begin!(label)
	layout = build_into(previous.clear(), width, rows, changed, corpus, retained_scroll_id, scroll_y).map_err(|_| Exit(1))?
	Trace.end!(zone)
	Ok(require_node_count(layout, rows))
}

## Rebuild unchanged content at several widths using one retained layout. This
## isolates width-dependent wrapping after canonical text preparation is warm.
resize_sweep_scenario! : Str, Layout.Layout([]), U64, Bool, Corpus => Try(Layout.Layout([]), [Exit(I64)])
resize_sweep_scenario! = |label, previous, rows, changed, corpus| {
	zone = Trace.begin!(label)
	var $layout = previous
	for width in [960, 640, 480, 640, 960] {
		$layout = build_into($layout.clear(), width, rows, changed, corpus, 0, 0).map_err(|_| Exit(1))?
		$layout = require_node_count($layout, rows)
	}
	Trace.end!(zone)
	Ok($layout)
}

build_into : Layout.Layout([]), F32, U64, Bool, Corpus, U64, F32 => Try(Layout.Layout([]), Layout.LayoutError)
build_into = |initial, width, rows, changed, corpus, retained_scroll_id, scroll_y| {
	var $layout = initial
	view = document_view(width, rows, changed, corpus)
	for operation in Element.iter(view) {
		($layout, _node) = $layout.update(
			operation,
			|_id| default_status,
			|node_id| if node_id == retained_scroll_id { x: 0, y: scroll_y } else { x: 0, y: 0 },
		)?
	}
	$layout.solve({ w: width, h: 900 })
}

expected_node_count : U64 -> U64
expected_node_count = |rows| 17 + rows * 3 + sample_chunks

require_node_count : Layout.Layout([]), U64 -> Layout.Layout([])
require_node_count = |layout, rows| {
	if Layout.next_node_index(layout) == expected_node_count(rows) {
		layout
	} else {
		crash "text UI benchmark produced the wrong node count"
	}
}

layout_checksum : Layout.Layout([]) -> U64
layout_checksum = |layout| {
	data = layout.render_data()
	Layout.next_node_index(layout) + data.child_indices.len() + data.text_contents.len() + data.text_lines.len()
}

scroll_node_id : Layout.Layout([]) -> U64
scroll_node_id = |layout| {
	var $result = 0
	for node in layout.scroll_containers() {
		if node.overflow.y == Scroll {
			$result = node.id
		}
	}
	if $result == 0 {
		crash "text UI benchmark has no vertical scroll container"
	} else {
		$result
	}
}

has_scroll_offset : Layout.Layout([]), F32 -> Bool
has_scroll_offset = |layout, expected_y| {
	var $found = Bool.False
	for node in layout.scroll_containers() {
		if node.overflow.y == Scroll and node.scroll_position.y == expected_y {
			$found = Bool.True
		}
	}
	$found
}

default_status : Element.BoxStatus
default_status = { hovered: Bool.False, pressed: Bool.False, focused: Bool.False, disabled: Bool.False }

document_view : F32, U64, Bool, Corpus -> Element.View([], [])
document_view = |width, rows, changed, corpus| {
	box(
		{ id: Id("root"), style: |_| style.width(Fixed(width)).height(Fixed(900)).direction(Row).child_align({ x: Start, y: Start }) },
		[
			sidebar,
			box(
				{ id: Id("content"), style: |_| style.width(Grow({})).height(Grow({})).direction(Col).child_align({ x: Start, y: Start }).pad(24, 24, 20, 20).gap(12) },
				[
					toolbar,
					row_list(rows, changed),
					article(corpus),
				],
			),
		],
	)
}

sidebar : Element.View([], [])
sidebar = box(
	{ id: Id("sidebar"), style: |_| style.width(Fixed(240)).height(Grow({})).direction(Col).child_align({ x: Start, y: Start }).pad(18, 18, 18, 18).gap(10) },
	[
		text("DOCUMENTS"),
		text("Inbox                 24"),
		text("Reading list          8"),
		text("Drafts                3"),
		text("Projects"),
		text("Research"),
		text("Archive"),
		text("Settings"),
	],
)

toolbar : Element.View([], [])
toolbar = box(
	{ id: Id("toolbar"), style: |_| style.width(Grow({})).height(Fixed(44)).direction(Row).child_align({ x: Start, y: Center }).gap(18) },
	[
		text("All documents"),
		text("Search documents and notes"),
		text("Sort: recently updated"),
	],
)

row_list : U64, Bool -> Element.View([], [])
row_list = |rows, changed| {
	var $children = List.with_capacity(rows)
	for index in 0..<rows {
		$children = $children.append(
			box(
				{ id: IdI("row", index), style: |_| style.width(Grow({})).height(Fit({})).direction(Col).child_align({ x: Start, y: Start }).gap(4) },
				[
					text(row_title(index)),
					text(preview_text(index, changed)),
				],
			),
		)
	}
	box(
		{ id: Id("rows"), style: |_| style.width(Grow({})).height(Fixed(420)).direction(Col).child_align({ x: Start, y: Start }).gap(10).overflow(Hidden, Scroll) },
		$children,
	)
}

article : Corpus -> Element.View([], [])
article = |corpus| {
	var $paragraphs = List.with_capacity(sample_chunks)
	for content in corpus_chunks(corpus) {
		$paragraphs = $paragraphs.append(text(content))
	}
	box({ id: Id("article"), style: |_| style.width(Grow({})).height(Fit({})).direction(Col).child_align({ x: Start, y: Start }).gap(8) }, $paragraphs)
}

corpus_chunks : Corpus -> List(Str)
corpus_chunks = |corpus| match corpus {
	Alice => chunks_from(alice)
	Wiki => chunks_from(wiki)
	Rfc => chunks_from(rfc)
	Python => chunks_from(python_docs)
	Mixed => [sample_slice(alice, 0), sample_slice(wiki, 0), sample_slice(rfc, 0), sample_slice(python_docs, 0)]
}

chunks_from : Str -> List(Str)
chunks_from = |source| [
	sample_slice(source, 0),
	sample_slice(source, sample_chunk_bytes),
	sample_slice(source, sample_chunk_bytes * 2),
	sample_slice(source, sample_chunk_bytes * 3),
]

sample_slice : Str, U64 -> Str
sample_slice = |source, start| Str.from_utf8_lossy(source.to_utf8().sublist({ start, len: sample_chunk_bytes }))

row_title : U64 -> Str
row_title = |index| match index % 6 {
	0 => "Layout engine notes"
	1 => "A practical guide to text measurement"
	2 => "Rendering performance review"
	3 => "Weekly project summary"
	4 => "Typography and responsive geometry"
	_ => "Benchmark methodology and results"
}

preview_text : U64, Bool -> Str
preview_text = |index, changed| {
	base = match index % 5 {
		0 => "This item contains a short summary with a few words and a predictable ending."
		1 => "A medium-length preview demonstrates ordinary wrapping in a content column whose width changes with the viewport."
		2 => "Longer previews are useful because they create variable-height rows and force the solver to propagate intrinsic sizes through several nested boxes."
		3 => "Short metadata lines, status labels, and repeated controls represent the high-frequency text found in document and inbox interfaces."
		_ => "The final variant includes punctuation, numbers 1440x900, and mixed word lengths so line breaking is not dominated by one repeated shape."
	}
	if changed and index == 37 {
		Str.concat(base, " Updated")
	} else {
		base
	}
}
