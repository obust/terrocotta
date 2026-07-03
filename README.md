# Terrocotta - Clay meets Roc

Terrocotta is a library for building native application in [Roc](https://roc-lang.org/).

This is an **experimental project** for me to play with Roc and learn about GUI internals.

## Features

- Model-View-Update (MVU) architecture.
- [Clay](https://github.com/nicbarker/clay) layout engine ported to Roc.
  - [x] Stack-based node layout (capacity + exponential growth allocation)
  - [x] Flexbox
  - [ ] Scrollable
  - [ ] Mouse/Keyboard Events
  - [ ] Text warping
  - [ ] Transitions
- Rendering: [roc-ray](https://github.com/lukewilliamboswell/roc-ray) plateform built on [raylib](https://www.raylib.com/).

## Examples

Try out examples: `roc examples/demo.roc`
