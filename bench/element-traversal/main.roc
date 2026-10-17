## Allocation benchmark for Terrocotta element construction and traversal.
##
## Run through main.py so the Observatory capture is
## validated and summarized with the queries in sql/.
app [Model, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst",
	tc: "../../package/main.roc",
}

import rr.App
import rr.Draw
import rr.Trace

import tc.Element exposing [box]

Model : { operation_count : U64 }

Msg : []

program = { init!, update!, render! }

init! : App.Init(Model, [])
init! = App.init(App.default, |_io| Ok({ operation_count: 0 }))

update! : Model, App.Input(Msg), App.Io => Try(Model, [Exit(I64)])
update! = |model, _input, _io| {
	width_0 = require_count(trace_width!("element.width.n0.total", 0), 2)
	width_1 = require_count(trace_width!("element.width.n1.total", 1), 4)
	width_10 = require_count(trace_width!("element.width.n10.total", 10), 22)
	width_100 = require_count(trace_width!("element.width.n100.total", 100), 202)
	width_1000 = require_count(trace_width!("element.width.n1000.total", 1000), 2002)

	depth_1 = require_count(trace_depth!("element.depth.n1.total", 1), 2)
	depth_10 = require_count(trace_depth!("element.depth.n10.total", 10), 20)
	depth_100 = require_count(trace_depth!("element.depth.n100.total", 100), 200)

	balanced_1 = require_count(trace_balanced!("element.balanced.b4.d1.total", 4, 1), 2)
	balanced_3 = require_count(trace_balanced!("element.balanced.b4.d3.total", 4, 3), 42)
	balanced_5 = require_count(trace_balanced!("element.balanced.b4.d5.total", 4, 5), 682)

	width_split = require_count(trace_width_split!(100), 202)
	depth_split = require_count(trace_depth_split!(100), 200)
	balanced_split = require_count(trace_balanced_split!(4, 5), 682)

	# Controls distinguish empty-list representation costs from element traversal.
	empty_lists = trace_nested_empty_lists!("control.lists.empty.n1000", 1000)
	singleton_lists = trace_nested_singleton_lists!("control.lists.singleton.n1000", 1000)
	none_tags = trace_none_tags!("control.option.none.n1000", 1000)

	total = width_0 + width_1 + width_10 + width_100 + width_1000 + depth_1 + depth_10 + depth_100 + balanced_1 + balanced_3 + balanced_5 + width_split + depth_split + balanced_split + empty_lists + singleton_lists + none_tags
	Ok({ ..model, operation_count: total })
}

require_count : U64, U64 -> U64
require_count = |actual, expected| {
	if actual == expected {
		actual
	} else {
		crash "element traversal benchmark produced the wrong operation count"
	}
}

trace_width! : Str, U64 => U64
trace_width! = |label, count| {
	zone = Trace.begin!(label)
	container = width_tree(count)
	operation_count = consume(container)
	Trace.end!(zone)
	operation_count
}

width_tree : U64 -> Element.View([], [])
width_tree = |count| {
	var $leaves = List.with_capacity(count)
	for _ in 0..<count {
		$leaves = $leaves.append(box({ events: [] }, []))
	}
	box({ events: [] }, $leaves)
}

trace_depth! : Str, U64 => U64
trace_depth! = |label, depth| {
	zone = Trace.begin!(label)
	view = depth_tree(depth)
	operation_count = consume(view)
	Trace.end!(zone)
	operation_count
}

depth_tree : U64 -> Element.View([], [])
depth_tree = |depth| {
	if depth <= 1 {
		box({ events: [] }, [])
	} else {
		box({ events: [] }, [depth_tree(depth - 1)])
	}
}

trace_balanced! : Str, U64, U64 => U64
trace_balanced! = |label, branching, depth| {
	zone = Trace.begin!(label)
	view = balanced_tree(branching, depth)
	operation_count = consume(view)
	Trace.end!(zone)
	operation_count
}

balanced_tree : U64, U64 -> Element.View([], [])
balanced_tree = |branching, depth| {
	if depth <= 1 {
		box({ events: [] }, [])
	} else {
		var $children = List.with_capacity(branching)
		for _ in 0..<branching {
			$children = $children.append(balanced_tree(branching, depth - 1))
		}
		box({ events: [] }, $children)
	}
}

trace_width_split! : U64 => U64
trace_width_split! = |count| {
	leaves_zone = Trace.begin!("element.width.n100.build-leaves")
	var $leaves = List.with_capacity(count)
	for _ in 0..<count {
		$leaves = $leaves.append(box({ events: [] }, []))
	}
	Trace.end!(leaves_zone)

	root_zone = Trace.begin!("element.width.n100.build-root")
	container = box({ events: [] }, $leaves)
	Trace.end!(root_zone)

	consume_zone = Trace.begin!("element.width.n100.consume")
	operation_count = consume(container)
	Trace.end!(consume_zone)
	operation_count
}

trace_depth_split! : U64 => U64
trace_depth_split! = |depth| {
	build_zone = Trace.begin!("element.depth.n100.build")
	view = depth_tree(depth)
	Trace.end!(build_zone)

	consume_zone = Trace.begin!("element.depth.n100.consume")
	operation_count = consume(view)
	Trace.end!(consume_zone)
	operation_count
}

trace_balanced_split! : U64, U64 => U64
trace_balanced_split! = |branching, depth| {
	build_zone = Trace.begin!("element.balanced.b4.d5.build")
	view = balanced_tree(branching, depth)
	Trace.end!(build_zone)

	consume_zone = Trace.begin!("element.balanced.b4.d5.consume")
	operation_count = consume(view)
	Trace.end!(consume_zone)
	operation_count
}

consume : Element.View([], []) -> U64
consume = |view| {
	var $operation_count = 0
	for _ in view {
		$operation_count = $operation_count + 1
	}
	$operation_count
}

trace_nested_empty_lists! : Str, U64 => U64
trace_nested_empty_lists! = |label, count| {
	zone = Trace.begin!(label)
	empty : List(U64)
	empty = []
	var $lists = List.with_capacity(count)
	for _ in 0..<count {
		$lists = $lists.append(empty)
	}
	var $total_length = 0
	for list in $lists {
		$total_length = $total_length + list.len()
	}
	Trace.end!(zone)
	$total_length + $lists.len()
}

trace_nested_singleton_lists! : Str, U64 => U64
trace_nested_singleton_lists! = |label, count| {
	zone = Trace.begin!(label)
	var $lists = List.with_capacity(count)
	for index in 0..<count {
		$lists = $lists.append([index])
	}
	var $total_length = 0
	for list in $lists {
		$total_length = $total_length + list.len()
	}
	Trace.end!(zone)
	$total_length + $lists.len()
}

trace_none_tags! : Str, U64 => U64
trace_none_tags! = |label, count| {
	zone = Trace.begin!(label)
	no_events : [Events(List(U64)), None]
	no_events = None
	var $states = List.with_capacity(count)
	for _ in 0..<count {
		$states = $states.append(no_events)
	}
	var $total_length = 0
	for state in $states {
		$total_length = $total_length + match state {
			None => 0
			Events(events) => events.len()
		}
	}
	Trace.end!(zone)
	$total_length + $states.len()
}

render! : Model, Draw.Frame => Try({}, [Exit(I64)])
render! = |_model, _frame| Ok({})
