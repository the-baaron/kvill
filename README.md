# Quill

A full-screen Markdown editor for macOS. One file, one window, no sidebar.
Syntax markers hang in the left margin, dimmed and right-aligned, so
`#` and `######` finish on the same column and the text itself stays on one
clean line of measure.

```
 #   Quill
         A full-screen Markdown editor.

 ##  Headings
         Markers hang left of the column.
```

Native AppKit. No Electron, no web view, no bundled runtime.

## What it does

**Reads like a document, edits like plain text.** Bold is bold, headings are
headings, code sits in a panel. The Markdown underneath is never rewritten. What
you save is exactly what you typed.

**Markers appear where you are working.** `##`, `---`, code fences and `>` are
invisible until the caret enters that element, then they fade in dimmed in the
gutter. Nothing is inserted or removed to do this: the characters are still
there, kerned to zero width and painted in a clear colour.

**Every construct GitHub supports.** Headings (ATX and setext), bold, italic,
strikethrough, `==highlight==`, inline code, fenced code with a generic syntax
highlighter, indented code, links, reference links, autolinks, images,
footnotes, blockquotes at any depth, bulleted, ordered and task lists, tables,
horizontal rules, YAML front matter, definition lists, inline math, raw HTML,
and the five GitHub alerts:

> [!NOTE]
> Rendered as a tinted panel with an icon and a proper title, not as raw
> `[!NOTE]` text.

**Eight colour themes, five typefaces.** Paper, Ink, Sepia, Nord, the glass pair
Frost and Onyx that let the desktop show faintly through the way a native macOS
window does, and a high contrast pair for light and dark. The typefaces are Editorial (New
York), Grotesk (SF Pro),
Contrast (serif headings over a sans body), Typewriter (SF Mono) and Soft
(SF Rounded). Four text sizes, three measures. All of it app-wide and
remembered between launches, never per document.

**Chrome that stays out of the way.** A single glass dot in the top-right corner
springs open into three buttons as the pointer nears it, each holding a small
palette. A glass formatting bar appears over a selection. Content blurs and fades
under the top and bottom window edges. A word count sits quietly in the corner.
`⌘.` hides all of it, title bar included.

**Focus mode** dims every paragraph but the one you are in. **Typewriter
scrolling** keeps the caret centred, and the view scrolls past the end of the
document so the last line is never pinned to the bottom edge.

## Build

Requires macOS 14 or later to run, and the Xcode Command Line Tools to build.
Full Xcode is not needed.

```sh
git clone https://github.com/the-baaron/quill.git
cd quill
./build.sh
open build/Quill.app
```

To install it:

```sh
cp -R build/Quill.app /Applications/
```

Then either drop a `.md` file on the icon, or open Quill and choose
**Quill › Make Quill the Default Markdown Editor…** to make double-clicking work
everywhere. The app is ad-hoc signed, which is enough to run it locally; a
Developer ID signature would be needed to distribute it.

## Keyboard

| | |
| --- | --- |
| `⌘B` `⌘I` | Bold, italic |
| `⌃⌘S` `⌃⌘H` `⌃⌘C` | Strikethrough, highlight, inline code |
| `⌘K` `⇧⌘K` | Link, image |
| `⌘1`–`⌘6`, `⌘0` | Heading level, body text |
| `⇧⌘8` `⇧⌘7` `⇧⌘9` | Bulleted, numbered, task list |
| `⌘'` `⇧⌘C` `⌃⌘T` `⇧⌘-` | Quote, code block, table, rule |
| `⌘T` | Display options |
| `⌘.` | Hide every piece of interface |
| `⌃⌘]` `⌃⌘[` | Next theme, next typeface |
| `⌘+` `⌘-` `⌥⌘0` | Text size |
| `⇧⌘F` `⇧⌘Y` `⇧⌘M` | Focus mode, typewriter, always show markers |
| `⌃⌘F` | Full screen |

Return continues a list or quote and ends it on an empty item. Tab and Shift-Tab
indent list items. Clicking a checkbox toggles it. Command-clicking a link opens
it.

## How the gutter works

Every line's text starts on the same x position. Its marker is pushed into the
space to the left, right-aligned, using two paragraph indents and one kerned
space:

```
firstLineHeadIndent = contentX - gap - markerWidth   where the marker starts
headIndent          = contentX                       where wrapped lines resume
kern on last gap char = gap - naturalGapWidth        pins content to contentX
```

Because the marker's width is measured and compensated for, `#`, `######`,
`1.` and `100.` all leave the text on the same column. See
`Sources/Quill/Editor/MarkdownStyler.swift`.

## Layout of the source

```
Sources/Quill/
  Markdown/    line scanner, inline scanner, model types
  Editor/      styler (the gutter maths), text view, controller, commands
  Theme/       palettes, typography presets, derived metrics
  UI/          glass chrome: options bar, selection bar, panel, edge effects
  App/         NSDocument, window, menu bar, delegate, PNG renderer
```

## Rendering pages to PNG

The app can draw a document to an image without opening a window, which is how
the screenshots here are made:

```sh
./build/Quill.app/Contents/MacOS/Quill --render notes.md out.png \
  --theme ink --typography editorial --geometry 900x900 --scale 2 --offset 0
```

This draws the page only. The floating glass chrome is not included: those views
force the hierarchy to be layer-backed, and an off-screen layer-backed window
never runs a display pass, so there is nothing to capture.

## Images

Drag an image in and Quill writes the Markdown for it. A file already inside the
document's folder is referenced where it lies; anything from outside is copied
into an `images/` folder beside the document, under a name that is not already
taken. Image data dragged from a browser or Photos is written out the same way.

A line that is nothing but an image is drawn as the picture, with whatever text
the line carries falling underneath it as a centred caption. Put the caret in the
line and the Markdown reappears, so the path and the caption stay editable.

## Setext headings

`Title` over `=====` is converted to `# Title` when the file is opened, and `---`
under a paragraph is treated as a horizontal rule rather than promoting the line
above it to a heading. Both make setext headings awkward to live with in an
editor: the underline is a second line to keep in step, and typing a rule after a
paragraph silently turns it into a title. The conversion is left unsaved, so
opening a file never rewrites it on disk.

## Tables

A table row is one paragraph, so the moment it wraps a kerned grid becomes
meaningless. Quill measures every column, sets the table in the reading face
rather than a monospace one, and kerns each cell onto the grid with two
adjustments: one that puts the cell's first character exactly one padding past
the column edge, and one that fills the rest of the column. The pipes are then
invisible, because the columns say everything they said.

If the table would be wider than the measure, it is shrunk until it fits, down
to 58% of the body size. If it still will not fit, the grid is abandoned
altogether and the row falls back to plain monospace source with its pipes
showing, because half a grid looks worse than none.

## Roadmap

- Opening a folder shows a file tree, while opening a file stays one window,
  one file.

## Known limits

- Re-parsing and restyling run over the whole document on each edit. That is
  comfortably fast for normal notes; a multi-megabyte file will feel it.
- The emphasis matcher is a pragmatic approximation of the CommonMark flanking
  rules, not the full algorithm. It handles real prose, including `snake_case`,
  but a deliberately pathological nesting case may differ from a strict parser.
- Code highlighting is language-agnostic: comments, strings, numbers and a
  shared keyword set. It is not a per-language grammar.
- `--render` starts at the top of the document for a full-length file, but for a
  document only a little taller than the canvas it can begin a line or two in.
  It is a screenshot tool, so this has not been chased down.

## Licence

MIT. See [LICENSE](LICENSE).
