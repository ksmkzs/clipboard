import XCTest
import AppKit
import Carbon
@testable import ClipboardHistory

@MainActor
final class EditorNSTextViewKeyboardTests: XCTestCase {
    private final class TestUndoResponder: NSResponder {
        private let testUndoManager = UndoManager()

        override init() {
            super.init()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var undoManager: UndoManager? {
            testUndoManager
        }
    }

    private var undoResponders: [NSResponder] = []

    override func tearDown() {
        undoResponders.removeAll()
        super.tearDown()
    }

    func testTabIndentsSelectedLines() {
        let editor = makeEditor(text: "alpha\nbeta", selection: NSRange(location: 0, length: 10))

        editor.keyDown(with: keyEvent(keyCode: 48, characters: "\t"))

        XCTAssertEqual(editor.string, "\talpha\n\tbeta")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 12))
    }

    func testTabWithCaretOnlyIndentsCurrentLineWithoutSelectingWholeBlock() {
        let editor = makeEditor(text: "alpha\nbeta", selection: NSRange(location: 2, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 48, characters: "\t"))

        XCTAssertEqual(editor.string, "\talpha\nbeta")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 3, length: 0))
    }

    func testShiftTabOutdentsSelectedLines() {
        let editor = makeEditor(text: "\talpha\n\tbeta", selection: NSRange(location: 0, length: 12))

        editor.keyDown(with: keyEvent(keyCode: 48, characters: "\t", modifiers: .shift))

        XCTAssertEqual(editor.string, "alpha\nbeta")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 10))
    }

    func testShiftTabOutdentsSingleLeadingSpace() {
        let editor = makeEditor(text: " alpha", selection: NSRange(location: 2, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 48, characters: "\t", modifiers: .shift))

        XCTAssertEqual(editor.string, "alpha")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 1, length: 0))
    }

    func testShiftTabOutdentsTwoLeadingSpaces() {
        let editor = makeEditor(text: "  alpha", selection: NSRange(location: 3, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 48, characters: "\t", modifiers: .shift))

        XCTAssertEqual(editor.string, "alpha")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 1, length: 0))
    }

    func testShiftTabOutdentsThreeLeadingSpaces() {
        let editor = makeEditor(text: "   alpha", selection: NSRange(location: 4, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 48, characters: "\t", modifiers: .shift))

        XCTAssertEqual(editor.string, "alpha")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 1, length: 0))
    }

    func testOptionUpMovesSelectedLineUp() {
        let editor = makeEditor(text: "one\ntwo\nthree", selection: NSRange(location: 4, length: 3))

        editor.keyDown(with: keyEvent(keyCode: 126, characters: "\u{F700}", modifiers: .option))

        XCTAssertEqual(editor.string, "two\none\nthree")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 3))
    }

    func testOptionDownMovesSelectedLineDown() {
        let editor = makeEditor(text: "one\ntwo\nthree", selection: NSRange(location: 4, length: 3))

        editor.keyDown(with: keyEvent(keyCode: 125, characters: "\u{F701}", modifiers: .option))

        XCTAssertEqual(editor.string, "one\nthree\ntwo")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 10, length: 3))
    }

    func testOptionDownWithCaretOnlyMovesCurrentLineAndKeepsCaretCollapsed() {
        let editor = makeEditor(text: "one\ntwo\nthree", selection: NSRange(location: 5, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 125, characters: "\u{F701}", modifiers: .option))

        XCTAssertEqual(editor.string, "one\nthree\ntwo")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 11, length: 0))
    }

    func testCommandJJoinsLinesByTrimmingLineEdgesAndRemovingBreaks() {
        let editor = makeEditor(text: "one\n two\nthree", selection: NSRange(location: 0, length: 14))

        _ = editor.performKeyEquivalent(with: keyEvent(matching: AppSettings.default.joinLinesShortcut))

        XCTAssertEqual(editor.string, "onetwothree")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 11))
    }

    func testMarkdownPreviewRendererRendersHeadingAndEmphasisAsBlockHTML() {
        let html = MarkdownPreviewRenderer.documentHTML(for: "# a\n*a*")

        XCTAssertTrue(html.contains("<h1>a</h1>"))
        XCTAssertTrue(html.contains("<p><em>a</em></p>"))
    }

    func testMarkdownPreviewRendererRendersListAndCodeFence() {
        let html = MarkdownPreviewRenderer.documentHTML(for: "- alpha\n- beta\n\n```swift\nprint(1)\n```")

        XCTAssertTrue(html.contains("<ul><li>alpha</li><li>beta</li></ul>"))
        XCTAssertTrue(html.contains("<pre><code class=\"language-swift\">print(1)</code></pre>"))
    }

    func testMarkdownPreviewRendererRendersTaskListCheckboxes() {
        let html = MarkdownPreviewRenderer.documentHTML(for: "- [ ] todo\n- [x] done")

        XCTAssertTrue(html.contains("<ul class=\"task-list\">"))
        XCTAssertTrue(html.contains("<input type=\"checkbox\" disabled>"))
        XCTAssertTrue(html.contains("<input type=\"checkbox\" disabled checked>"))
        XCTAssertTrue(html.contains("<span class=\"task-label\">todo</span>"))
        XCTAssertTrue(html.contains("<span class=\"task-label\">done</span>"))
    }

    func testMarkdownPreviewRendererPreservesNestedUnorderedListStructure() {
        let markdown = """
        - top level item A
        - top level item B
          - nested item B.1
          - nested item B.2
            - nested item B.2.a
        - top level item C
        """
        let html = MarkdownPreviewRenderer.documentHTML(for: markdown)

        XCTAssertTrue(html.contains("<ul><li>top level item A</li><li><div>top level item B</div><ul><li>nested item B.1</li><li><div>nested item B.2</div><ul><li>nested item B.2.a</li></ul></li></ul></li><li>top level item C</li></ul>"))
    }

    func testMarkdownPreviewRendererPreservesMixedOrderedAndUnorderedLists() {
        let markdown = """
        1. ordered
        2. ordered
           - unordered nested
           - unordered nested
        3. ordered again
        - unordered
        - unordered
          1. ordered nested
          2. ordered nested
        - unordered again
        """
        let html = MarkdownPreviewRenderer.documentHTML(for: markdown)

        XCTAssertTrue(
            html.contains("<ol><li>ordered</li><li><div>ordered</div><ul><li>unordered nested</li><li>unordered nested</li></ul></li><li>ordered again</li></ol>\n<ul><li>unordered</li><li><div>unordered</div><ol><li>ordered nested</li><li>ordered nested</li></ol></li><li>unordered again</li></ul>"),
            html
        )
    }

    func testMarkdownPreviewRendererPreservesNestedOrderedListStructure() {
        let markdown = """
        1. level 1
           1. level 2
              1. level 3
           2. level 2b
        2. level 1b
        """
        let html = MarkdownPreviewRenderer.documentHTML(for: markdown)

        XCTAssertTrue(
            html.contains("<ol><li><div>level 1</div><ol><li><div>level 2</div><ol><li>level 3</li></ol></li><li>level 2b</li></ol></li><li>level 1b</li></ol>"),
            html
        )
    }

    func testMarkdownPreviewRendererRendersBlockquoteWithNestedListAndNestedQuote() {
        let markdown = """
        > 単一引用です。
        > 2 行目も引用です。
        >
        > 引用の中に list
        > - item 1
        > - item 2
        >
        > > nested quote
        > > with another line
        """
        let html = MarkdownPreviewRenderer.documentHTML(for: markdown)

        XCTAssertTrue(html.contains("<blockquote><p>単一引用です。 2 行目も引用です。</p>"))
        XCTAssertTrue(html.contains("<p>引用の中に list</p>\n<ul><li>item 1</li><li>item 2</li></ul>"))
        XCTAssertTrue(html.contains("<blockquote><p>nested quote with another line</p></blockquote>"))
    }

    func testMarkdownPreviewRendererRendersMultipleCodeFencesWithoutFlattening() {
        let markdown = """
        ```swift
        print(1)
        ```

        ```json
        {"kind":"markdown"}
        ```
        """
        let html = MarkdownPreviewRenderer.documentHTML(for: markdown)

        XCTAssertTrue(html.contains("<pre><code class=\"language-swift\">print(1)</code></pre>"))
        XCTAssertTrue(html.contains("<pre><code class=\"language-json\">{&quot;kind&quot;:&quot;markdown&quot;}</code></pre>"))
    }

    func testMarkdownPreviewRendererSupportsLongerOuterFenceContainingInnerFence() {
        let markdown = """
        ````markdown
        ```swift
        print("nested fence example")
        ```
        ````
        """
        let html = MarkdownPreviewRenderer.documentHTML(for: markdown)

        XCTAssertTrue(
            html.contains("<pre><code class=\"language-markdown\">```swift\nprint(&quot;nested fence example&quot;)\n```</code></pre>"),
            html
        )
        XCTAssertFalse(html.contains("<p>print(&quot;nested fence example&quot;)</p>"), html)
    }

    func testMarkdownPreviewRendererRendersTables() {
        let markdown = """
        | Column A | Column B | Column C |
        | --- | ---: | :---: |
        | 123 | ok | short |
        | inline `code` | **bold** | ~~strike~~ |
        """
        let html = MarkdownPreviewRenderer.documentHTML(for: markdown)

        XCTAssertTrue(html.contains("<table><thead><tr><th>Column A</th><th class=\"align-right\">Column B</th><th class=\"align-center\">Column C</th></tr></thead>"), html)
        XCTAssertTrue(html.contains("<td>inline <code>code</code></td>"), html)
        XCTAssertTrue(html.contains("<td class=\"align-right\">ok</td>"), html)
        XCTAssertTrue(html.contains("<td class=\"align-center\"><del>strike</del></td>"), html)
    }

    func testMarkdownPreviewRendererDoesNotSplitTableCellsOnPipesInsideCodeSpans() {
        let markdown = """
        | Column A | Column B |
        | --- | --- |
        | `a|b` | c |
        """
        let html = MarkdownPreviewRenderer.documentHTML(for: markdown)

        XCTAssertTrue(
            html.contains("<table><thead><tr><th>Column A</th><th>Column B</th></tr></thead><tbody><tr><td><code>a|b</code></td><td>c</td></tr></tbody></table>"),
            html
        )
    }

    func testMarkdownPreviewRendererDoesNotSplitTableCellsOnEscapedPipes() {
        let markdown = """
        | Column A | Column B |
        | --- | --- |
        | a\\|b | c |
        """
        let html = MarkdownPreviewRenderer.documentHTML(for: markdown)

        XCTAssertTrue(
            html.contains("<table><thead><tr><th>Column A</th><th>Column B</th></tr></thead><tbody><tr><td>a|b</td><td>c</td></tr></tbody></table>"),
            html
        )
    }

    func testMarkdownPreviewRendererRendersHorizontalRules() {
        let markdown = """
        before

        ---

        between

        ***

        after
        """
        let html = MarkdownPreviewRenderer.documentHTML(for: markdown)

        XCTAssertTrue(html.contains("<p>before</p>"), html)
        XCTAssertTrue(html.contains("<hr>"), html)
        XCTAssertEqual(html.components(separatedBy: "<hr>").count - 1, 2, html)
        XCTAssertTrue(html.contains("<p>after</p>"), html)
    }

    func testMarkdownPreviewRendererPreservesMixedJapaneseAndEnglishContent() {
        let markdown = """
        Markdown プレビューが、日本語の段落、English sentences、`inline code`、**強調**、*斜体* を同時に含むときに崩れないかを見ます。

        - 日本語だけの項目
        - English only item
        - 日本語 and English mixed item
        """
        let html = MarkdownPreviewRenderer.documentHTML(for: markdown)

        XCTAssertTrue(html.contains("Markdown プレビューが、日本語の段落、English sentences、<code>inline code</code>、<strong>強調</strong>、<em>斜体</em>"), html)
        XCTAssertTrue(html.contains("<li>日本語だけの項目</li>"), html)
        XCTAssertTrue(html.contains("<li>English only item</li>"), html)
        XCTAssertTrue(html.contains("<li>日本語 and English mixed item</li>"), html)
    }

    func testMarkdownPreviewRendererPreservesDeepNestedStructure() {
        let markdown = """
        1. level 1
           - level 2 bullet
             1. level 3 ordered
                - level 4 bullet
                  - [ ] level 5 task
                    > nested quote under task
        """
        let html = MarkdownPreviewRenderer.documentHTML(for: markdown)

        XCTAssertTrue(html.contains("<ol><li><div>level 1</div>"), html)
        XCTAssertTrue(html.contains("<ul><li><div>level 2 bullet</div>"), html)
        XCTAssertTrue(html.contains("<ol><li><div>level 3 ordered</div>"), html)
        XCTAssertTrue(html.contains("<ul><li><div>level 4 bullet</div>"), html)
        XCTAssertTrue(html.contains("<ul class=\"task-list\">"), html)
        XCTAssertTrue(html.contains("level 5 task"), html)
        XCTAssertTrue(html.contains("<blockquote><p>nested quote under task</p></blockquote>"), html)
    }

    func testMarkdownPreviewRendererResolvesReferenceStyleLinksAndFootnotes() {
        let markdown = """
        [OpenAI][openai] [GitHub][github]

        [openai]: https://openai.com/
        [github]: https://github.com/

        脚注風の記法です。[^note]

        [^note]: 実装によってはそのまま文字列として見える可能性があります。
        """
        let html = MarkdownPreviewRenderer.documentHTML(for: markdown)

        XCTAssertTrue(html.contains("<a href=\"https://openai.com/\">OpenAI</a>"), html)
        XCTAssertTrue(html.contains("<a href=\"https://github.com/\">GitHub</a>"), html)
        XCTAssertTrue(html.contains("<sup class=\"footnote-ref\"><a href=\"#fn-note\">[note]</a></sup>"), html)
        XCTAssertTrue(html.contains("<div class=\"footnotes\"><ol><li id=\"fn-note\"><p>実装によってはそのまま文字列として見える可能性があります。</p></li></ol></div>"), html)
    }

    func testMarkdownPreviewRendererHonorsEscapedMarkdownPunctuation() {
        let html = MarkdownPreviewRenderer.documentHTML(for: "エスケープ: \\*これは italic ではない\\* \\# これは見出しではない \\[link\\]")

        XCTAssertTrue(html.contains("<p>エスケープ: *これは italic ではない* # これは見出しではない [link]</p>"))
        XCTAssertFalse(html.contains("<em>"))
        XCTAssertFalse(html.contains("<h1>"))
        XCTAssertFalse(html.contains("<a href="))
    }

    func testMarkdownPreviewRendererDoesNotRenderImages() {
        let html = MarkdownPreviewRenderer.documentHTML(for: "![alt](https://example.com/image.png)")

        XCTAssertFalse(html.contains("<img"))
        XCTAssertTrue(html.contains("[Image unsupported]"))
    }

    func testMarkdownPreviewRendererProducesFullHTMLDocumentForWebView() {
        let html = MarkdownPreviewRenderer.documentHTML(for: "# a\n*a*")

        XCTAssertTrue(html.contains("<!doctype html>"))
        XCTAssertTrue(html.contains("<body><h1>a</h1>\n<p><em>a</em></p></body>"))
        XCTAssertFalse(html.contains("<body># a"))
    }

    func testMarkdownPreviewRendererKeepsSoftBreakAsParagraphWhitespace() {
        let html = MarkdownPreviewRenderer.documentHTML(for: "alpha\nbeta")

        XCTAssertTrue(html.contains("<p>alpha beta</p>"))
    }

    func testMarkdownPreviewRendererUsesHardBreakForTrailingTwoSpaces() {
        let html = MarkdownPreviewRenderer.documentHTML(for: "alpha  \nbeta")

        XCTAssertTrue(html.contains("<p>alpha<br>beta</p>"))
    }

    func testMarkdownPreviewRendererUsesHardBreakForTrailingBackslash() {
        let html = MarkdownPreviewRenderer.documentHTML(for: "alpha\\\nbeta")

        XCTAssertTrue(html.contains("<p>alpha<br>beta</p>"))
    }

    func testMarkdownPreviewAttributedPreviewPreservesHeadingBoldAndCodeTraits() {
        let preview = MarkdownPreviewRenderer.attributedPreview(for: "# Heading\n\nBody **Bold** `code`")
        let text = preview.string as NSString

        let headingIndex = text.range(of: "Heading").location
        let bodyIndex = text.range(of: "Body").location
        let boldIndex = text.range(of: "Bold").location
        let codeIndex = text.range(of: "code").location

        let headingFont = preview.attribute(.font, at: headingIndex, effectiveRange: nil) as? NSFont
        let bodyFont = preview.attribute(.font, at: bodyIndex, effectiveRange: nil) as? NSFont
        let boldFont = preview.attribute(.font, at: boldIndex, effectiveRange: nil) as? NSFont
        let codeFont = preview.attribute(.font, at: codeIndex, effectiveRange: nil) as? NSFont

        XCTAssertNotNil(headingFont)
        XCTAssertNotNil(bodyFont)
        XCTAssertNotNil(boldFont)
        XCTAssertNotNil(codeFont)
        XCTAssertGreaterThan(headingFont?.pointSize ?? 0, bodyFont?.pointSize ?? 0)
        XCTAssertTrue(NSFontManager.shared.traits(of: boldFont!).contains(.boldFontMask))
        XCTAssertTrue(codeFont?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
    }

    func testCommandJWithCaretOnlyDoesNotSelectWholeDocument() {
        let editor = makeEditor(text: "one\n two\nthree", selection: NSRange(location: 2, length: 0))

        _ = editor.performKeyEquivalent(with: keyEvent(matching: AppSettings.default.joinLinesShortcut))

        XCTAssertEqual(editor.string, "onetwothree")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 0))
    }

    func testCommandShiftJTrimsEachLineAndPreservesLineBreaks() {
        let editor = makeEditor(
            text: "  brew install  \n  git  \nprintf done ",
            selection: NSRange(location: 0, length: 37)
        )

        _ = editor.performKeyEquivalent(with: keyEvent(matching: AppSettings.default.normalizeForCommandShortcut))

        XCTAssertEqual(editor.string, "brew install\ngit\nprintf done")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 28))
    }

    func testCommandShiftJWithCaretOnlyKeepsCaretCollapsed() {
        let editor = makeEditor(
            text: "  a b   c  \n d",
            selection: NSRange(location: 2, length: 0)
        )

        _ = editor.performKeyEquivalent(with: keyEvent(matching: AppSettings.default.normalizeForCommandShortcut))

        XCTAssertEqual(editor.string, "a b   c\nd")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 0))
    }

    func testCommandOptionTTrimsTrailingWhitespace() {
        let editor = makeEditor(text: "one   \ntwo\t \nthree  ", selection: NSRange(location: 0, length: 21))

        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: 17, characters: "t", modifiers: [.command, .option]))

        XCTAssertEqual(editor.string, "one\ntwo\nthree")
    }

    func testCommandReturnCallsCommitHandler() {
        let editor = makeEditor(text: "one\ntwo", selection: NSRange(location: 0, length: 0))
        var didCommit = false
        editor.onCommit = {
            didCommit = true
        }

        editor.keyDown(with: keyEvent(keyCode: 36, characters: "\r", modifiers: .command))

        XCTAssertTrue(didCommit)
    }

    func testCommandSCallsSaveHandler() {
        let editor = makeEditor(text: "draft", selection: NSRange(location: 0, length: 0))
        var didSave = false
        editor.onSave = {
            didSave = true
        }

        let handled = editor.performKeyEquivalent(
            with: keyEvent(keyCode: UInt16(kVK_ANSI_S), characters: "s", modifiers: .command)
        )

        XCTAssertTrue(handled)
        XCTAssertTrue(didSave)
    }

    func testCommandOptionPCallsMarkdownPreviewHandler() {
        let editor = makeEditor(text: "# Title", selection: NSRange(location: 0, length: 0))
        var didTogglePreview = false
        editor.toggleMarkdownPreviewShortcut = AppSettings.default.toggleMarkdownPreviewShortcut
        editor.onToggleMarkdownPreview = {
            didTogglePreview = true
        }

        let handled = editor.performKeyEquivalent(
            with: keyEvent(keyCode: UInt16(kVK_ANSI_P), characters: "p", modifiers: [.command, .option])
        )

        XCTAssertTrue(handled)
        XCTAssertTrue(didTogglePreview)
    }

    func testCommandShiftDCallsOrphanDiscardHandler() {
        let editor = makeEditor(text: "draft", selection: NSRange(location: 0, length: 0))
        var didDiscard = false
        editor.orphanCodexDiscardShortcut = AppSettings.defaultOrphanCodexDiscardShortcut
        editor.onDiscardOrphanCodex = {
            didDiscard = true
        }

        let handled = editor.performKeyEquivalent(
            with: keyEvent(
                keyCode: UInt16(kVK_ANSI_D),
                characters: "d",
                modifiers: [.command, .shift]
            )
        )

        XCTAssertTrue(handled)
        XCTAssertTrue(didDiscard)
    }

    func testMarkdownPreviewScrollProgressTracksSelectionByLine() {
        let text = "alpha\nbeta\ngamma\ndelta"

        XCTAssertEqual(MarkdownPreviewScrollSync.progress(for: text, selectionLocation: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(MarkdownPreviewScrollSync.progress(for: text, selectionLocation: 8), 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(MarkdownPreviewScrollSync.progress(for: text, selectionLocation: (text as NSString).length), 1, accuracy: 0.0001)
    }

    func testCommandLeftMovesToBeginningOfLine() {
        let editor = makeEditor(text: "one\ntwo\nthree", selection: NSRange(location: 6, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 123, characters: "\u{F702}", modifiers: .command))

        XCTAssertEqual(editor.selectedRange(), NSRange(location: 4, length: 0))
    }

    func testCommandRightMovesToEndOfLine() {
        let editor = makeEditor(text: "one\ntwo\nthree", selection: NSRange(location: 5, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 124, characters: "\u{F703}", modifiers: .command))

        XCTAssertEqual(editor.selectedRange(), NSRange(location: 7, length: 0))
    }

    func testCommandShiftLeftExtendsSelectionToBeginningOfLine() {
        let editor = makeEditor(text: "one\ntwo\nthree", selection: NSRange(location: 6, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 123, characters: "\u{F702}", modifiers: [.command, .shift]))

        XCTAssertEqual(editor.selectedRange(), NSRange(location: 4, length: 2))
    }

    func testCommandShiftRightExtendsSelectionToEndOfLine() {
        let editor = makeEditor(text: "one\ntwo\nthree", selection: NSRange(location: 5, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 124, characters: "\u{F703}", modifiers: [.command, .shift]))

        XCTAssertEqual(editor.selectedRange(), NSRange(location: 5, length: 2))
    }

    func testLeftArrowMovesOneCharacterLeft() {
        let editor = makeEditor(text: "one\ntwo", selection: NSRange(location: 5, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 123, characters: "\u{F702}"))

        XCTAssertEqual(editor.selectedRange(), NSRange(location: 4, length: 0))
    }

    func testRightArrowMovesOneCharacterRight() {
        let editor = makeEditor(text: "one\ntwo", selection: NSRange(location: 4, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 124, characters: "\u{F703}"))

        XCTAssertEqual(editor.selectedRange(), NSRange(location: 5, length: 0))
    }

    func testShiftLeftArrowExtendsSelectionLeft() {
        let editor = makeEditor(text: "one\ntwo", selection: NSRange(location: 5, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 123, characters: "\u{F702}", modifiers: .shift))

        XCTAssertEqual(editor.selectedRange(), NSRange(location: 4, length: 1))
    }

    func testShiftRightArrowExtendsSelectionRight() {
        let editor = makeEditor(text: "one\ntwo", selection: NSRange(location: 4, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 124, characters: "\u{F703}", modifiers: .shift))

        XCTAssertEqual(editor.selectedRange(), NSRange(location: 4, length: 1))
    }

    func testOptionLeftMovesToPreviousWordBoundary() {
        let editor = makeEditor(text: "one two", selection: NSRange(location: 7, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 123, characters: "\u{F702}", modifiers: .option))

        XCTAssertEqual(editor.selectedRange(), NSRange(location: 4, length: 0))
    }

    func testOptionRightMovesToNextWordBoundary() {
        let editor = makeEditor(text: "one two", selection: NSRange(location: 4, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 124, characters: "\u{F703}", modifiers: .option))

        XCTAssertEqual(editor.selectedRange(), NSRange(location: 7, length: 0))
    }

    func testCommandASelectsAllText() {
        let editor = makeEditor(text: "one\ntwo\nthree", selection: NSRange(location: 5, length: 0))

        editor.selectAll(nil)

        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 13))
    }

    func testCommandAKeyEquivalentSelectsAllText() {
        let editor = makeEditor(text: "one\ntwo\nthree", selection: NSRange(location: 5, length: 0))

        let handled = editor.performKeyEquivalent(
            with: keyEvent(keyCode: UInt16(kVK_ANSI_A), characters: "a", modifiers: .command)
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 13))
    }

    func testCopyActionCopiesSelectedText() {
        let editor = makeEditor(text: "one\ntwo\nthree", selection: NSRange(location: 4, length: 3))
        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let original {
                pasteboard.setString(original, forType: .string)
            }
        }
        pasteboard.clearContents()
        pasteboard.setString("sentinel", forType: .string)

        editor.copy(nil)

        XCTAssertEqual(pasteboard.string(forType: .string), "two")
    }

    func testCommandCKeyEquivalentIsHandled() {
        let editor = makeEditor(text: "one\ntwo\nthree", selection: NSRange(location: 4, length: 3))

        let handled = editor.performKeyEquivalent(
            with: keyEvent(keyCode: UInt16(kVK_ANSI_C), characters: "c", modifiers: .command)
        )

        XCTAssertTrue(handled)
    }

    func testCutActionCutsSelectedText() {
        let editor = makeEditor(text: "one\ntwo\nthree", selection: NSRange(location: 4, length: 3))
        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let original {
                pasteboard.setString(original, forType: .string)
            }
        }
        pasteboard.clearContents()
        pasteboard.setString("sentinel", forType: .string)

        editor.cut(nil)

        XCTAssertEqual(editor.string, "one\n\nthree")
        XCTAssertEqual(pasteboard.string(forType: .string), "two")
    }

    func testCommandXKeyEquivalentCutsSelection() {
        let editor = makeEditor(text: "one\ntwo\nthree", selection: NSRange(location: 4, length: 3))
        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let original {
                pasteboard.setString(original, forType: .string)
            }
        }

        let handled = editor.performKeyEquivalent(
            with: keyEvent(keyCode: UInt16(kVK_ANSI_X), characters: "x", modifiers: .command)
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(editor.string, "one\n\nthree")
    }

    func testPasteActionPastesClipboardText() {
        let editor = makeEditor(text: "one\nthree", selection: NSRange(location: 4, length: 0))
        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let original {
                pasteboard.setString(original, forType: .string)
            }
        }
        pasteboard.clearContents()
        pasteboard.setString("two\n", forType: .string)

        editor.paste(nil)

        XCTAssertEqual(editor.string, "one\ntwo\nthree")
    }

    func testCommandVKeyEquivalentIsHandled() {
        let editor = makeEditor(text: "one\nthree", selection: NSRange(location: 4, length: 0))
        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let original {
                pasteboard.setString(original, forType: .string)
            }
        }
        pasteboard.clearContents()
        pasteboard.setString("two\n", forType: .string)

        let handled = editor.performKeyEquivalent(
            with: keyEvent(keyCode: UInt16(kVK_ANSI_V), characters: "v", modifiers: .command)
        )

        XCTAssertTrue(handled)
    }

    func testDeleteRemovesPreviousCharacter() {
        let editor = makeEditor(text: "one two", selection: NSRange(location: 4, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 51, characters: "\u{8}"))

        XCTAssertEqual(editor.string, "onetwo")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 3, length: 0))
    }

    func testOptionDeleteRemovesPreviousWord() {
        let editor = makeEditor(text: "one two", selection: NSRange(location: 7, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 51, characters: "\u{8}", modifiers: .option))

        XCTAssertEqual(editor.string, "one ")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 4, length: 0))
    }

    func testDeleteToBeginningOfLineActionRemovesLinePrefix() {
        let editor = makeEditor(text: "one two", selection: NSRange(location: 7, length: 0))

        editor.deleteToBeginningOfLine(nil)

        XCTAssertEqual(editor.string, "")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 0))
    }

    func testUndoAndRedoRestoreEditorCommand() {
        let editor = makeEditor(text: "one\ntwo", selection: NSRange(location: 0, length: 7))

        editor.keyDown(with: keyEvent(keyCode: 48, characters: "\t"))
        XCTAssertEqual(editor.string, "\tone\n\ttwo")

        editor.undoManager?.undo()
        XCTAssertEqual(editor.string, "one\ntwo")

        editor.undoManager?.redo()
        XCTAssertEqual(editor.string, "\tone\n\ttwo")
    }

    func testComplexEditorWorkflowRequiresStructuralCommandsClipboardAndUndoRedoToStayConsistent() {
        let editor = makeEditor(
            text: "alpha\nbeta\ngamma",
            selection: NSRange(location: 6, length: 4)
        )
        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let original {
                pasteboard.setString(original, forType: .string)
            }
        }

        editor.keyDown(with: keyEvent(keyCode: 125, characters: "\u{F701}", modifiers: .option))
        XCTAssertEqual(editor.string, "alpha\ngamma\nbeta")

        editor.keyDown(with: keyEvent(keyCode: 126, characters: "\u{F700}", modifiers: .option))
        XCTAssertEqual(editor.string, "alpha\nbeta\ngamma")

        editor.setSelectedRange(NSRange(location: 0, length: 16))
        editor.keyDown(with: keyEvent(keyCode: 48, characters: "\t"))
        XCTAssertEqual(editor.string, "\talpha\n\tbeta\n\tgamma")

        editor.keyDown(with: keyEvent(keyCode: 48, characters: "\t", modifiers: .shift))
        XCTAssertEqual(editor.string, "alpha\nbeta\ngamma")

        editor.setSelectedRange(NSRange(location: 0, length: 10))
        editor.cut(nil)
        XCTAssertEqual(editor.string, "\ngamma")
        XCTAssertEqual(pasteboard.string(forType: .string), "alpha\nbeta")

        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.paste(nil)
        XCTAssertEqual(editor.string, "alpha\nbeta\ngamma")
    }

    func testComplexNavigationWorkflowRequiresCaretAndSelectionToRemainCorrect() {
        let editor = makeEditor(text: "one two\nthree", selection: NSRange(location: 7, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 123, characters: "\u{F702}", modifiers: .option))
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 4, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 124, characters: "\u{F703}", modifiers: .option))
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 7, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 123, characters: "\u{F702}", modifiers: .command))
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 124, characters: "\u{F703}", modifiers: .command))
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 7, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 123, characters: "\u{F702}", modifiers: .shift))
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 6, length: 1))

        editor.setSelectedRange(NSRange(location: 7, length: 0))
        editor.keyDown(with: keyEvent(keyCode: 51, characters: "\u{8}", modifiers: .option))
        XCTAssertEqual(editor.string, "one \nthree")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 4, length: 0))
    }

    func testComplexNormalizeWorkflowPreservesLineBreaksAndUndoRedo() {
        let editor = makeEditor(
            text: "  brew install  \n  git  \nprintf done ",
            selection: NSRange(location: 0, length: 37)
        )

        _ = editor.performKeyEquivalent(with: keyEvent(matching: AppSettings.default.normalizeForCommandShortcut))
        XCTAssertEqual(editor.string, "brew install\ngit\nprintf done")

        editor.undoManager?.undo()
        XCTAssertEqual(editor.string, "  brew install  \n  git  \nprintf done ")

        editor.undoManager?.redo()
        XCTAssertEqual(editor.string, "brew install\ngit\nprintf done")
    }

    func testComplexWhitespaceWorkflowRequiresOutdentTrimJoinAndUndoBoundariesToStayStable() {
        let editor = makeEditor(
            text: "  alpha  \n beta \n\tgamma",
            selection: NSRange(location: 0, length: 23)
        )

        editor.keyDown(with: keyEvent(keyCode: 48, characters: "\t", modifiers: .shift))
        XCTAssertEqual(editor.string, "alpha  \nbeta \ngamma")

        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: 17, characters: "t", modifiers: [.command, .option]))
        XCTAssertEqual(editor.string, "alpha\nbeta\ngamma")

        _ = editor.performKeyEquivalent(with: keyEvent(matching: AppSettings.default.joinLinesShortcut))
        XCTAssertEqual(editor.string, "alphabetagamma")
        XCTAssertTrue(editor.undoManager?.canUndo ?? false)
        XCTAssertTrue(editor.undoManager?.undoActionName == "Join Lines" || editor.undoManager?.undoActionName == "Trim Trailing Whitespace")
    }

    func testComplexPrimaryCommandWorkflowRequiresNavigationSelectionClipboardTransformAndCommitToAllRemainConsistent() {
        let editor = makeEditor(
            text: "alpha\nbeta\ngamma",
            selection: NSRange(location: 0, length: 16)
        )
        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let original {
                pasteboard.setString(original, forType: .string)
            }
        }

        var didCommit = false
        var didToggleHelp = false
        editor.onCommit = { didCommit = true }
        editor.onToggleHelp = { didToggleHelp = true }

        editor.keyDown(with: keyEvent(keyCode: 48, characters: "\t"))
        XCTAssertEqual(editor.string, "\talpha\n\tbeta\n\tgamma")

        editor.keyDown(with: keyEvent(keyCode: 48, characters: "\t", modifiers: .shift))
        XCTAssertEqual(editor.string, "alpha\nbeta\ngamma")

        editor.setSelectedRange(NSRange(location: 6, length: 4))
        editor.keyDown(with: keyEvent(keyCode: 125, characters: "\u{F701}", modifiers: .option))
        XCTAssertEqual(editor.string, "alpha\ngamma\nbeta")

        editor.keyDown(with: keyEvent(keyCode: 126, characters: "\u{F700}", modifiers: .option))
        XCTAssertEqual(editor.string, "alpha\nbeta\ngamma")

        editor.setSelectedRange(NSRange(location: 0, length: 16))
        editor.copy(nil)
        XCTAssertEqual(pasteboard.string(forType: .string), "alpha\nbeta\ngamma")

        editor.cut(nil)
        XCTAssertEqual(editor.string, "")

        editor.paste(nil)
        XCTAssertEqual(editor.string, "alpha\nbeta\ngamma")

        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.keyDown(with: keyEvent(keyCode: 124, characters: "\u{F703}", modifiers: .command))
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 5, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 123, characters: "\u{F702}", modifiers: .option))
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 124, characters: "\u{F703}", modifiers: .shift))
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 1))

        editor.setSelectedRange(NSRange(location: 0, length: 16))
        _ = editor.performKeyEquivalent(with: keyEvent(matching: AppSettings.default.joinLinesShortcut))
        XCTAssertEqual(editor.string, "alphabetagamma")

        editor.undoManager?.undo()
        XCTAssertEqual(editor.string, "alpha\nbeta\ngamma")

        editor.undoManager?.redo()
        XCTAssertEqual(editor.string, "alphabetagamma")

        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: 44, characters: "/", modifiers: .command))
        XCTAssertTrue(didToggleHelp)

        editor.keyDown(with: keyEvent(keyCode: 36, characters: "\r", modifiers: .command))
        XCTAssertTrue(didCommit)
    }

    func testEscapeCallsOnEscapeHandler() {
        let editor = makeEditor(text: "one\ntwo", selection: NSRange(location: 0, length: 0))
        var didEscape = false
        editor.onEscape = {
            didEscape = true
        }

        editor.keyDown(with: keyEvent(keyCode: 53, characters: "\u{1b}"))

        XCTAssertTrue(didEscape)
    }

    func testCommandQuestionMarkCallsHelpHandler() {
        let editor = makeEditor(text: "one\ntwo", selection: NSRange(location: 0, length: 0))
        var didToggleHelp = false
        editor.onToggleHelp = {
            didToggleHelp = true
        }

        _ = editor.performKeyEquivalent(
            with: keyEvent(keyCode: 44, characters: "?", modifiers: [.command, .shift])
        )

        XCTAssertTrue(didToggleHelp)
    }

    func testCommandSlashCallsHelpHandler() {
        let editor = makeEditor(text: "one\ntwo", selection: NSRange(location: 0, length: 0))
        var didToggleHelp = false
        editor.onToggleHelp = {
            didToggleHelp = true
        }

        _ = editor.performKeyEquivalent(
            with: keyEvent(keyCode: 44, characters: "/", modifiers: .command)
        )

        XCTAssertTrue(didToggleHelp)
    }

    func testCommandEqualsCallsZoomInHandler() {
        let editor = makeEditor(text: "one", selection: NSRange(location: 0, length: 0))
        var didZoom = false
        editor.onZoomIn = { didZoom = true }

        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: UInt16(kVK_ANSI_Equal), characters: "=", modifiers: .command))

        XCTAssertTrue(didZoom)
    }

    func testCommandMinusCallsZoomOutHandler() {
        let editor = makeEditor(text: "one", selection: NSRange(location: 0, length: 0))
        var didZoom = false
        editor.onZoomOut = { didZoom = true }

        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: UInt16(kVK_ANSI_Minus), characters: "-", modifiers: .command))

        XCTAssertTrue(didZoom)
    }

    func testCommandZeroCallsResetZoomHandler() {
        let editor = makeEditor(text: "one", selection: NSRange(location: 0, length: 0))
        var didReset = false
        editor.onResetZoom = { didReset = true }

        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: UInt16(kVK_ANSI_0), characters: "0", modifiers: .command))

        XCTAssertTrue(didReset)
    }

    func testNormalizeCommandTextTrimsEachLineAndPreservesLineBreaks() {
        let result = normalizeCommandText("  brew install  \n  git  \nprintf done ")
        XCTAssertEqual(result, "brew install\ngit\nprintf done")
    }

    func testJoinLinesTextTrimsEachLineAndRemovesBreaks() {
        let result = joinLinesText("  a b   c  \n d")
        XCTAssertEqual(result, "a b   cd")
    }

    private func makeEditor(text: String, selection: NSRange) -> EditorNSTextView {
        let editor = EditorNSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 220))
        editor.font = .systemFont(ofSize: 12)
        editor.textColor = .labelColor
        editor.insertionPointColor = .labelColor
        editor.drawsBackground = false
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.allowsUndo = true
        editor.isEditable = true
        editor.isSelectable = true
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 6, height: 6)
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.lineFragmentPadding = 0
        let undoResponder = TestUndoResponder()
        editor.nextResponder = undoResponder
        undoResponders.append(undoResponder)
        editor.string = text
        editor.setSelectedRange(selection)

        return editor
    }

    private func keyEvent(
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters.lowercased(),
            isARepeat: false,
            keyCode: keyCode
        )
        return try! XCTUnwrap(event)
    }

    private func keyEvent(matching shortcut: HotKeyManager.Shortcut) -> NSEvent {
        let modifiers = modifierFlags(matching: shortcut)
        let characters: String

        switch shortcut.keyCode {
        case UInt32(kVK_ANSI_C):
            characters = modifiers.contains(NSEvent.ModifierFlags.shift) ? "C" : "c"
        case UInt32(kVK_ANSI_J):
            characters = modifiers.contains(NSEvent.ModifierFlags.shift) ? "J" : "j"
        case UInt32(kVK_ANSI_P):
            characters = modifiers.contains(NSEvent.ModifierFlags.shift) ? "P" : "p"
        case UInt32(kVK_Return):
            characters = "\r"
        case UInt32(kVK_Tab):
            characters = "\t"
        default:
            characters = ""
        }

        return keyEvent(
            keyCode: UInt16(shortcut.keyCode),
            characters: characters,
            modifiers: modifiers
        )
    }

    private func modifierFlags(matching shortcut: HotKeyManager.Shortcut) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if shortcut.modifiers & UInt32(cmdKey) != 0 {
            flags.insert(.command)
        }
        if shortcut.modifiers & UInt32(shiftKey) != 0 {
            flags.insert(.shift)
        }
        if shortcut.modifiers & UInt32(optionKey) != 0 {
            flags.insert(.option)
        }
        if shortcut.modifiers & UInt32(controlKey) != 0 {
            flags.insert(.control)
        }
        return flags
    }

}
