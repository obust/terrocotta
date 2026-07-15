# Terrocotta - Clay meets Roc

Terrocotta is a library for building native application in [Roc](https://roc-lang.org/).

This is an **experimental project** for me to play with Roc and learn about GUI internals.

## Features

- Model-View-Update (MVU) architecture.
- [Clay](https://github.com/nicbarker/clay) layout engine ported to Roc.
  - [x] Stack-based node layout (capacity + exponential growth allocation)
  - [x] Flexbox
  - [x] Mouse/Keyboard Events
  - [ ] Scrollable
  - [ ] Text wraping
  - [ ] Floating
  - [ ] Transitions
- Rendering: [roc-ray](https://github.com/lukewilliamboswell/roc-ray) plateform built on [raylib](https://www.raylib.com/).
- [x] Status based styling (hovered/pressed/focused)
- [x] Theming
- Widgets
  - [x] Slider
  - [x] Checkbox
  - [ ] Toggle
  - [ ] Select
  - [ ] Input Text

## Documentation

- [Architecture Overview](docs/architecture.md)

## Examples

Try out examples:
- `roc examples/counter.roc`
- `roc examples/button.roc`
- `roc examples/text_wrap.roc`

## Testing

```bash
roc test package/main.roc
```
