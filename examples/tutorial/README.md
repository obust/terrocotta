# Terrocotta Tutorial

The interactive Terrocotta tutorial introduces the library's layout and rendering primitives through live examples. Each lesson combines a preview, interactive controls, and the Roc code that produces the result.

## Running the tutorial

```sh
roc examples/tutorial/main.roc
```

You will need [Roc](https://roc-lang.org/) installed and available on your `PATH`.

## Lessons

The tutorial includes the following lessons:

- **Layout** — directions, sizing modes, gaps, padding, and alignment.
- **Text** — wrapping, alignment, font size, spacing, and line height.
- **Floating** — attachment points, offsets, expansion, and z-order.
- **Image** — natural, fixed, and fill sizing, plus child alignment.
- **Canvas** — drawing relative to a container's resolved bounds.

## Tutorial structure

- `main.roc`: application entry point, asset loading, and page routing.
- `App.roc`: shared application.
- `UI.roc`: UI components module.
- `pages/`: the individual interactive lessons.
- `ui/`: UI component definitions.
- `assets/`: images and the tutorial font.

## Asset licenses

- `bricks.png` — [CC0 Public Domain](https://pxhere.com/en/photo/1022074)
- `Inter-Regular.ttf` — [SIL Open Font License 1.1](https://scripts.sil.org/OFL)
- `rocotta.png` — project asset
