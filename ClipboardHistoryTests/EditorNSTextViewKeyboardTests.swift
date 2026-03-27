import XCTest
import AppKit
@testable import ClipboardHistory

@MainActor
final class EditorNSTextViewKeyboardTests: XCTestCase {
    private var windowsToClose: [NSWindow] = []

    override func tearDown() {
        windowsToClose.forEach { $0.close() }
        windowsToClose.removeAll()
        super.tearDown()
    }

    func testTabIndentsSelectedLines() {
        let editor = makeEditor(text: "alpha\nbeta", selection: NSRange(location: 0, length: 10))

        editor.keyDown(with: keyEvent(keyCode: 48, characters: "\t"))

        XCTAssertEqual(editor.string, "\talpha\n\tbeta")
    }

    func testShiftTabOutdentsSelectedLines() {
        let editor = makeEditor(text: "\talpha\n\tbeta", selection: NSRange(location: 0, length: 12))

        editor.keyDown(with: keyEvent(keyCode: 48, characters: "\t", modifiers: .shift))

        XCTAssertEqual(editor.string, "alpha\nbeta")
    }

    func testOptionUpMovesSelectedLineUp() {
        let editor = makeEditor(text: "one\ntwo\nthree", selection: NSRange(location: 4, length: 3))

        editor.keyDown(with: keyEvent(keyCode: 126, characters: "\u{F700}", modifiers: .option))

        XCTAssertEqual(editor.string, "two\none\nthree")
    }

    func testOptionDownMovesSelectedLineDown() {
        let editor = makeEditor(text: "one\ntwo\nthree", selection: NSRange(location: 4, length: 3))

        editor.keyDown(with: keyEvent(keyCode: 125, characters: "\u{F701}", modifiers: .option))

        XCTAssertEqual(editor.string, "one\nthree\ntwo")
    }

    func testCommandJJoinsLines() {
        let editor = makeEditor(text: "one\n two\nthree", selection: NSRange(location: 0, length: 14))

        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: 38, characters: "j", modifiers: .command))

        XCTAssertEqual(editor.string, "one two three")
    }

    func testCommandShiftJNormalizesForCommand() {
        let editor = makeEditor(text: "  one \n\n two\t three  ", selection: NSRange(location: 0, length: 23))

        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: 38, characters: "J", modifiers: [.command, .shift]))

        XCTAssertEqual(editor.string, "one two three")
    }

    func testCommandOptionTTrimsTrailingWhitespace() {
        let editor = makeEditor(text: "one   \ntwo\t \nthree  ", selection: NSRange(location: 0, length: 21))

        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: 17, characters: "t", modifiers: [.command, .option]))

        XCTAssertEqual(editor.string, "one\ntwo\nthree")
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

    func testEscapeCallsOnEscapeHandler() {
        let editor = makeEditor(text: "one\ntwo", selection: NSRange(location: 0, length: 0))
        var didEscape = false
        editor.onEscape = {
            didEscape = true
        }

        editor.keyDown(with: keyEvent(keyCode: 53, characters: "\u{1b}"))

        XCTAssertTrue(didEscape)
    }

    private func makeEditor(text: String, selection: NSRange) -> EditorNSTextView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 220))
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let editor = EditorNSTextView(frame: scrollView.bounds)
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
        editor.string = text
        editor.setSelectedRange(selection)

        scrollView.documentView = editor

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.makeFirstResponder(editor)
        windowsToClose.append(window)

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
}
