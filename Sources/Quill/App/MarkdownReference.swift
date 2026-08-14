import Foundation

/// The document opened by Help › Quill Markdown Reference. It is deliberately a
/// working example of every construct Quill styles, so it doubles as a way to
/// see what a theme looks like before committing to it.
enum MarkdownReference {
    static let text = #"""
    ---
    title: Quill Markdown Reference
    author: you
    ---

    # Quill

    A full-screen Markdown editor. Syntax markers hang in the left gutter, dimmed
    and right-aligned, so the text itself stays on one clean column.

    ## Headings

    Six levels, written with leading hashes. Notice how `#` and `######` both
    finish on the same column.

    ### Third level
    #### Fourth level
    ##### Fifth level
    ###### Sixth level

    Setext headings work too
    ========================

    ## Text

    You can write **bold**, _italic_, **_both at once_**, ~~struck out~~ and
    ==highlighted== text. Inline `code` uses the monospace face. Escaped
    characters like \*this\* stay literal. A backslash-free footnote reference
    looks like this[^1].

    [^1]: And the definition sits at the bottom, dimmed.

    Two trailing spaces force a hard break, which Quill marks faintly.

    ## Lists

    - A bulleted item
    - Another one
      - Nested one level
        - And two
    + Plus signs work
    * So do asterisks

    1. Ordered lists
    2. Count upward
       1. And nest
    3. Pressing Return continues the list; pressing it on an empty item ends it.

    - [ ] An open task
    - [x] A finished one, struck through
    - [ ] Click the checkbox to toggle it

    Term
    : A definition list item

    ## Quotes and callouts

    > A plain blockquote gets a bar in the margin.
    > It can run to several lines.

    >> Nested quotes get a second bar.

    > [!NOTE]
    > Useful information the reader should notice even when skimming.

    > [!TIP]
    > An optional shortcut that makes something easier.

    > [!IMPORTANT]
    > Necessary knowledge for getting the result you want.

    > [!WARNING]
    > Something with an outcome you should be careful about.

    > [!CAUTION]
    > A risk with real consequences.

    ## Code

    Inline `let x = 1` sits in the run of text. Fenced blocks get a panel:

    ```swift
    // Comments, strings, numbers and keywords are tinted.
    func greet(_ name: String) -> String {
        let count = 42
        return "Hello, \(name) and \(count)"
    }
    ```

    ```python
    # A different language, a different comment character.
    def total(items):
        return sum(item.price for item in items)
    ```

        Four-space indented code also renders as a block.

    ## Links and images

    An [inline link](https://example.com), a [reference link][ref], a bare
    autolink <https://example.com>, and an email <hello@example.com>.

    Hold Command and click any link to open it.

    ![An image reference](./diagram.png)

    [ref]: https://example.com

    ## Tables

    | Feature | Shortcut | Notes |
    | --- | --- | --- |
    | Bold | Cmd B | Wraps the word under the caret |
    | Link | Cmd K | Selects the placeholder URL |
    | Settings | Cmd T | The glass panel |
    | Focus mode | Shift Cmd F | Dims everything but this block |

    ## Rules

    Three or more dashes make a horizontal rule:

    ---

    Asterisks and underscores work as well:

    ***

    ## Math and HTML

    Inline math like $E = mc^2$ is tinted, and raw <em>HTML</em> is dimmed to the
    secondary colour so it reads as markup rather than prose.

    ## Getting around

    | | |
    | --- | --- |
    | Cmd T | Settings panel |
    | Ctrl Cmd ] | Next colour theme |
    | Ctrl Cmd [ | Next typography |
    | Cmd + / Cmd - | Text size |
    | Shift Cmd M | Show or hide syntax markers |
    | Ctrl Cmd F | Full screen |

    """#
}
