# IDE example

A Sev-inspired, read-only project browser built from Terrocotta elements. It
demonstrates a collapsible filesystem tree, document tabs, asynchronous file
loading, two-axis source scrolling, and a small pure-Roc HTML highlighter.

Run it from the repository root:

```sh
roc --no-cache examples/ide/main.roc
```

Capture one deterministic frame for visual review:

```sh
roc --no-cache examples/ide/main.roc -- --capture --host-hidden --host-frames=2
```

This writes `captures/ide_00000.png`.

The app has read-only access to `examples/ide/workspace`. Click a file to open
it, click a tab to activate it, and use the `x` affordance to close it. HTML and
HTM files are highlighted; other UTF-8 files are displayed as plain text. The
interface uses the bundled `Inter-Regular.ttf` as its default font.

The explorer uses flat, transparent 16 px PNG renderings of GitHub Octicons.
Attribution and licensing details are in `assets/ICONS.md`.

This first version intentionally omits editing, save, undo, split panes,
Tree-sitter, and language-server features.
