# IDE example

A Sev-inspired IDE built from Terrocotta elements. It demonstrates a
collapsible filesystem tree, document tabs, asynchronous file loading,
two-axis source scrolling, small pure-Roc HTML and CSS highlighters, an editable
code surface, and application-level command surfaces.

Run it from the repository root:

```sh
roc --no-cache examples/ide/main.roc
```

Capture one deterministic frame for visual review:

```sh
roc --no-cache examples/ide/main.roc -- --capture --host-hidden --host-frames=2
```

This writes `captures/ide_00000.png`.

The app has access to `examples/ide/workspace`. Click a file to open
it, click a tab to activate it, and use the `x` affordance to close it. HTML,
HTM, and CSS files are highlighted; other supported files are displayed as plain text.
Files containing anything other than printable ASCII and LF are rejected with
an error in the editor. The UI uses the bundled `Inter-Regular.ttf` font, while
the code editor uses `assets/JetBrainsMono-Regular.ttf`.

The demo editor intentionally accepts printable ASCII and LF only. This keeps
cursor and syntax-span positioning simple and makes the fixed-width font
advance explicit.

The source-buffer model owns text mutation, line geometry, language selection,
and semantic highlight ranges. The code editor renders buffer snapshots and
turns keyboard and pointer interaction into language-independent edit intents.

JetBrains Mono is distributed under the SIL Open Font License 1.1. The full
license text is included at `assets/JetBrainsMono-OFL.txt`.

Keyboard commands:

- `Cmd/Ctrl+Shift+P` opens Quick Open with a leading `>` for command search;
- `Cmd/Ctrl+P` opens the same Quick Open surface in file-search mode;
- `Cmd/Ctrl+K` opens the keyboard-shortcut reference;
- `Cmd/Ctrl+W` closes the active editor tab;
- `Cmd/Ctrl+S` saves the active editor; a `*` beside the tab title indicates
  unsaved changes;
- `Up`/`Down`, `Enter`, and `Escape` navigate an open command surface.

Each tab runs at most one save at a time. Editing can continue while it saves;
the status bar reports saving and failures.

Quick Open searches workspace files by default. Type `>` as the first character
to switch the existing overlay to command results; removing it switches back to
files.

The explorer uses flat, transparent 16 px PNG renderings of GitHub Octicons.
Attribution and licensing details are in `assets/ICONS.md`.

This first version intentionally omits undo, split panes, Tree-sitter,
and language-server features.
