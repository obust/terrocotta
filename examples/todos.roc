## A todo list composed from independently routed views with Element.map:
## each entry is its own Todo component, and the new-entry form is another.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0-rc3/3vVeddfDE6rraq5j8v1cGHtFNaQhC6dij1zGRN63NGP1.tar.zst",
	tc: "../package/main.roc",
	roc: "nightly-2026-08-23-fb208ba",
}

import rr.App
import rr.Text

import tc.Element exposing [box, text, style, map]
import tc.Program exposing [View]
import tc.Theme
import tc.Widget

theme = Theme.dark

Todo := {}.{
	Message : [Toggle, Delete]

	Model : { title : Str, done : Bool }

	init : Str -> Model
	init = |title| { title: title, done: False }

	update : Model, Message -> Model
	update = |model, message|
		match message {
			Toggle => { ..model, done: !model.done }
			Delete => model
		}

	view : Model -> View(Message)
	view = |model| {
		box(
			{
				style: |_| style
					.height(Fit({}))
					.direction(Row)
					.child_align({ x: Start, y: Center })
					.gap(theme.gap),
			},
			[
				Widget.toggle(theme, model.done, |_| Toggle),
				text(model.title),
				box(
					{
						style: |_| style
							.width(Grow({}))
							.height(Fit({})),
					},
					[],
				),
				Widget.button(theme, Danger, "x", [OnClick(Delete)]),
			],
		)
	}
}

TodoForm := {}.{
	Message : [TextChanged(Widget.TextInputState)]

	Model : { value : Str, cursor : U64 }

	init : () -> Model
	init = || { value: "", cursor: 0 }

	update : Model, Message -> Model
	update = |_model, message|
		match message {
			TextChanged(state) => state
		}

	view : Model, Text.Font -> View(Message)
	view = |model, font| {
		Widget.input_text(
			theme,
			{
				id: Id("new-todo"),
				state: model,
				font,
				placeholder: "Add a todo...",
				on_change: |state| TextChanged(state),
			},
		)
	}
}

AppModel : {
	todos : List(Todo.Model),
	form : TodoForm.Model,
	font : Text.Font,
}

Msg : [
	TodoMessage(U64, Todo.Message),
	FormMessage(TodoForm.Message),
	AddTodo(Str),
]

Model : Program.State(AppModel, Msg)

configure : List(Str) -> App.Config
configure = |_args|
	App.default
		.with_title("Todo Example")
		.with_size({ width: 520, height: 540 })

init! : App.InitCallback(AppModel, [])
init! = |startup| {
	font = startup.default_font!().map_err(|_| Exit(1))?
	Ok({
		todos: [Todo.init("Learn Roc"), Todo.init("Learn Terrocotta"), Todo.init("Build application")],
		form: TodoForm.init(),
		font,
	})
}

update : AppModel, Msg -> AppModel
update = |model, msg|
	match msg {
		TodoMessage(index, todo_msg) =>
			match todo_msg {
				Delete => { ..model, todos: model.todos.drop_at(index) }

				Toggle =>
					match model.todos.get(index) {
						Ok(todo) => {
							todo_updated = Todo.update(todo, todo_msg)
							{ ..model, todos: model.todos.set(index, todo_updated).ok_or(model.todos) }

						}
						Err(_) => model
					}
				}

		FormMessage(form_msg) => { ..model, form: TodoForm.update(model.form, form_msg) }

		AddTodo(title) => {
			todos = if title.is_empty() model.todos else model.todos.append(Todo.init(title))
			{ ..model, todos, form: TodoForm.init() }
		}
	}

view : AppModel -> View(Msg)
view = |model| {
	completed_count = model.todos.keep_if(|todo| todo.done).len()
	active_count = model.todos.len() - completed_count
	box(
		{
			style: |_| style
				.direction(Col)
				.pad(theme.gap, theme.gap, theme.gap, theme.gap)
				.gap(theme.gap)
				.child_align({ x: Start, y: Start })
				.background(theme.palette.background.base.fill)
				.font_size(theme.font_size)
				.font_color(theme.palette.background.base.content),
		},
		[
			text("Todos (completed: ${completed_count.to_str()}, active: ${active_count.to_str()})"),
			box(
				{ style: |_| style.height(Fit({})).direction(Row).gap(theme.gap) },
				[
					TodoForm.view(model.form, model.font) |> map(|msg| FormMessage(msg)),
					Widget.button(theme, Primary, "Add", [OnClick(AddTodo(model.form.value))]),
				],
			),
			box(
				{ style: |_| style.direction(Col).height(Fit({})).gap(theme.gap).overflow(Hidden, Scroll) },
				model.todos.map_with_index(
					|todo, index| Todo.view(todo) |> map(|msg| TodoMessage(index, msg)),
				),
			),
		],
	)
}

program = Program.new(configure, init!, update, view)
