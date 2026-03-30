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

    func testCommandCCopiesSelectedText() {
        let editor = makeEditor(text: "one\ntwo\nthree", selection: NSRange(location: 4, length: 3))
        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let original {
                pasteboard.setString(original, forType: .string)
            }
        }

        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: 8, characters: "c", modifiers: .command))

        XCTAssertEqual(pasteboard.string(forType: .string), "two")
    }

    func testCommandXCutsSelectedText() {
        let editor = makeEditor(text: "one\ntwo\nthree", selection: NSRange(location: 4, length: 3))
        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let original {
                pasteboard.setString(original, forType: .string)
            }
        }

        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: 7, characters: "x", modifiers: .command))

        XCTAssertEqual(editor.string, "one\n\nthree")
        XCTAssertEqual(pasteboard.string(forType: .string), "two")
    }

    func testCommandVPastesClipboardText() {
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

        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: 9, characters: "v", modifiers: .command))

        XCTAssertEqual(editor.string, "one\ntwo\nthree")
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

    func testCommandDeleteRemovesToBeginningOfLine() {
        let editor = makeEditor(text: "one two", selection: NSRange(location: 7, length: 0))

        editor.keyDown(with: keyEvent(keyCode: 51, characters: "\u{8}", modifiers: .command))

        XCTAssertEqual(editor.string, "")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 0))
    }

    func testCommandZUndoesEditorCommandAndRedoRestoresIt() {
        let editor = makeEditor(text: "one\ntwo", selection: NSRange(location: 0, length: 7))

        editor.keyDown(with: keyEvent(keyCode: 48, characters: "\t"))
        XCTAssertEqual(editor.string, "\tone\n\ttwo")

        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: 6, characters: "z", modifiers: .command))
        XCTAssertEqual(editor.string, "one\ntwo")

        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: 6, characters: "Z", modifiers: [.command, .shift]))
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
        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: 7, characters: "x", modifiers: .command))
        XCTAssertEqual(editor.string, "\ngamma")
        XCTAssertEqual(pasteboard.string(forType: .string), "alpha\nbeta")

        editor.setSelectedRange(NSRange(location: 0, length: 0))
        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: 9, characters: "v", modifiers: .command))
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

        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: 6, characters: "z", modifiers: .command))
        XCTAssertEqual(editor.string, "  brew install  \n  git  \nprintf done ")

        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: 6, characters: "Z", modifiers: [.command, .shift]))
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
        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: 8, characters: "c", modifiers: .command))
        XCTAssertEqual(pasteboard.string(forType: .string), "alpha\nbeta\ngamma")

        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: 7, characters: "x", modifiers: .command))
        XCTAssertEqual(editor.string, "")

        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: 9, characters: "v", modifiers: .command))
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

        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: 6, characters: "z", modifiers: .command))
        XCTAssertEqual(editor.string, "alpha\nbeta\ngamma")

        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: 6, characters: "Z", modifiers: [.command, .shift]))
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
