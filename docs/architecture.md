# Architecture

Terrocotta is a native UI runtime for Roc applications. It combines a
Model-View-Update application loop with an immediate mode layout and rendering pipeline.

## Model-View-Update

Applications define their state and behavior through three functions:

- `init: () -> Model`, which creates the initial model (aka application state).
- `view: Model -> View(Message)`, which derives the current UI from the model.
- `update: Model, Message -> Model`, which applies application messages to the model.

The runtime owns the feedback loop around those functions:

```mermaid
graph TD
    ModelState(( ))

    init ---|Model| ModelState

    ModelState --> view
    ModelState --> update

    view -->|"View(Message)"| interaction

    interaction -->|Message| update

    update --> ModelState
```

## Model

The model is the durable application state. It is created once by `init` and
then carried through the runtime loop.

```roc
Model : { count : I32 }

init : () -> Model
init = () -> { count : 0 }
```

## Update

`update` is the only place where application messages change that state. It
receives the current model and one `Message`, then returns the next model:

```roc
Message : [Increment]

update : Model, Message -> Model
update = |model, message|
    match message {
        Increment -> { count : model.count + 1 }
    }
```

## View

Application code builds a `View` from the built-in `box` and `text` elements,
plus `custom` leaves. Element and Layout remain generic over the leaf payload,
but the standard Program binds that parameter to its closed `Program.Payload`
union. `image` is a convenience wrapper around `custom(Image(value))`; it uses
structural `width` and `height` fields to configure a containing box but does
not add an image-specific layout node.

For example, this view derives UI from a small model and attaches an event that
can produce an application message:

```roc
view : Model -> View(Message)
view = |model|
    box({ style: |_| container_style }, [
        text(model.count.to_str()),
        box({ id: Id("increment"), style: |_| button_style, events: [OnClick(Increment)] }, [
            text("+"),
        ]),
    ])
```

The application-facing `Program.View(msg)` aliases the generic element view
with the program's supported payload type:

```roc
Program.View(msg) : Element.View(msg, Program.Payload)
```

This ensures the view's payload type unifies with `Program.Payload`, leaving
only the message type parameter exposed to applications.

Internally, the generic `Element.View(msg, payload)` is not a retained tree
data structure. It is an iterator of `ElementOp(msg, payload)` values:

```roc
View(msg, payload) : Iter(ElementOp(msg, payload))

ElementOp(msg, payload) : [
    OpenBox(ElementId, BoxStatus -> BoxConfig, List(Event.Handler(msg))),
    CloseBox,
    Text(Str),
    Custom(payload),
]
```

That means the view above is emitted as a flat stream:

```roc
OpenBox(|_| container_style, [])
Text("0")
OpenBox(|_| button_style, [OnClick(Increment)])
Text("+")
CloseBox
CloseBox
```

## Composing views

`Element.map` changes the message type produced by a view without changing its
elements or payload:

```roc
Element.map : Element.View(a, payload), (a -> b) -> Element.View(b, payload)
```

This lets a child component or page own its model, message type, update, and
view while the root application owns composition and routing. For example, a
self-contained counter can be embedded twice:

```roc
Counter := {}.{
    Message : [Increment, Decrement]

    Model : { label : Str, count : I32 }

    update : Model, Message -> Model
    update = |model, message|
        match message {
            Increment => { ..model, count: model.count + 1 }
            Decrement => { ..model, count: model.count - 1 }
        }

    view : Model -> View(Message)
    view = |model|
        box({}, [
            box({ events: [OnClick(Decrement)] }, [text("-")]),
            text("${model.label}: ${model.count.to_str()}"),
            box({ events: [OnClick(Increment)] }, [text("+")]),
        ])
}

AppModel : {
    left : Counter.Model,
    right : Counter.Model,
}

Msg : [Left(Counter.Message), Right(Counter.Message)]

update = |model, message|
    match message {
        Left(child_message) =>
            { ..model, left: Counter.update(model.left, child_message) }

        Right(child_message) =>
            { ..model, right: Counter.update(model.right, child_message) }
    }

view = |model|
    box({}, [
        Counter.view(model.left) |> Element.map(|message| Left(message)),
        Counter.view(model.right) |> Element.map(|message| Right(message)),
    ])
```

The wrapper tags preserve which child produced each message, so the parent can
send it to the corresponding child model. A multi-page application uses the
same pattern with one parent message constructor per page.

The implementation remains streaming: `Element.map` lazily transforms each
`ElementOp` and calls the nominal `Event.Handler.map` method only for handlers
on `OpenBox`. IDs, style functions, text, operation order, and custom payloads
pass through unchanged. It maps UI messages only; Terrocotta currently has no
managed effect or subscription abstraction. If those are added, they will
need their own message-mapping APIs.

## Layout

`Layout(payload)` consumes the `ElementOp(msg, payload)` iterator and builds a
flat contiguous node list.

At a high level, a layout node looks like this:

```roc
Layout(payload) : {
    nodes : List(LayoutNode(payload)),  # flat list of layout nodes
    stack : List(U64),  # stack of parent node indices
}

LayoutNode(payload) : {
    kind : [BoxNode, TextNode, CustomNode({ payload : payload })],
    parent : [NoParent, Parent(U64)],
    child_start : U64,
    child_count : U64,
    position : { x : U64, y : U64 },
    size : { width : U64, height : U64 },
    ...
}
```

The push/pop shape of the view iterator lets `Layout` build this representation
incrementally. `OpenBox` pushes a parent onto the layout stack, leaf messages add
children to the current parent, and `CloseBox` pops the stack.

Once the node list is built, layout solving fills in concrete sizes and
positions. Custom leaves are opaque, have zero intrinsic size, and grow into
the content bounds assigned by their parent box. Applications express natural
size or aspect-ratio policy by wrapping a custom leaf in an explicitly sized
box.

The flat representation is critical for performance. Rebuilding the UI each
frame does not require allocating a tree of heap objects; the runtime can reuse contiguous lists, append nodes in stream order, and walk layout data with good cache locality when solving constraints.

The layout implementation is a direct port of [Clay](https://github.com/nicbarker/clay) to Roc.

## Rendering

Rendering starts after layout has been solved. At that point, every layout node
has concrete position and size data.

`Renderer.draw!` uses the scoped recursive traversal and the host's
`with_scissor!` operation:

```roc
Renderer.draw!(frame, layout, screen)
```

As an alternative, `Paint.iter` converts the solved layout into a validated,
back-to-front stream of semantic paint operations. `Renderer.draw_paint!`
interprets that stream using push/pop scissors:

```roc
Renderer.draw_paint!(frame, layout, screen)
```

Both paths use the same background, text, border, and payload drawing functions.
They preserve root and child paint order, use conservative subtree bounds for
culling, and exhaustively interpret `Program.Payload` at each resolved
`Renderer.Placement`.
The linear path emits balanced `BeginScissor` and `EndScissor` operations and
maps them to `frame.begin_scissor!` and `frame.end_scissor!`.

## Runtime

At a high level, the runtime frame loop looks like this:

```roc
$model = init()
$layout = Layout.new()
$bindings = []

while Bool.True {
    $layout = $layout.clear()
    $bindings = $bindings.clear()

    # build layout from stream of ElementOp: [OpenBox(_, _), Text, Custom, CloseBox]
    for element_op in view($model) {
        $layout = $layout.update!(element_op)
        $bindings = collect_event_bindings($bindings, $layout, element_op)
    }

    # solve layout constraints
    $layout = $layout.solve!()

    # update model
    messages = user_interactions($layout, $bindings, host)
    for message in messages {
        $model = update($model, message)
    }

    # render layout
    render!($layout)
}
```
