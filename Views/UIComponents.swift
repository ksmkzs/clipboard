//
//  UIComponents.swift
//  ClipboardHistory
//
//  Created by あいちゅ on 2026/02/27.
//

import SwiftUI
import AppKit

enum EditorCommand: String {
    case indent
    case outdent
    case moveLineUp
    case moveLineDown
    case joinLines
    case normalizeForCommand
    case trimTrailingWhitespace
}

extension Notification.Name {
    static let editorCommandRequested = Notification.Name("EditorCommandRequested")
}

// MARK: - 高度な背景ぼかしビュー (NSVisualEffectViewのラッパー)
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active // ウィンドウが非アクティブでもぼかしを維持する
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - キーボードイベントハンドリングビュー (NSViewのラッパー)
struct EventHandlingView: NSViewRepresentable {
    var isEditorActive: Bool
    var togglePinShortcut: HotKeyManager.Shortcut
    var togglePinnedAreaShortcut: HotKeyManager.Shortcut
    var editTextShortcut: HotKeyManager.Shortcut
    var deleteShortcut: HotKeyManager.Shortcut
    var undoShortcut: HotKeyManager.Shortcut
    var redoShortcut: HotKeyManager.Shortcut
    var joinLinesShortcut: HotKeyManager.Shortcut
    var normalizeForCommandShortcut: HotKeyManager.Shortcut
    var onLeftArrow: () -> Void
    var onRightArrow: () -> Void
    var onUpArrow: () -> Void
    var onDownArrow: () -> Void
    var onMovePinnedUp: () -> Void
    var onMovePinnedDown: () -> Void
    var onEnter: () -> Void
    var onCopyCommand: () -> Void
    var onClosePanel: () -> Void
    var onDelete: () -> Void
    var onTogglePin: () -> Void
    var onTogglePinnedArea: () -> Void
    var onToggleEditor: () -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onJoinLines: () -> Void
    var onNormalizeForCommand: () -> Void
    var onOpenSettings: () -> Void
    
    func makeNSView(context: Context) -> CustomKeyView {
        let view = CustomKeyView()
        view.isEditorActive = isEditorActive
        view.togglePinShortcut = togglePinShortcut
        view.togglePinnedAreaShortcut = togglePinnedAreaShortcut
        view.editTextShortcut = editTextShortcut
        view.deleteShortcut = deleteShortcut
        view.undoShortcut = undoShortcut
        view.redoShortcut = redoShortcut
        view.joinLinesShortcut = joinLinesShortcut
        view.normalizeForCommandShortcut = normalizeForCommandShortcut
        view.onLeftArrow = onLeftArrow
        view.onRightArrow = onRightArrow
        view.onUpArrow = onUpArrow
        view.onDownArrow = onDownArrow
        view.onMovePinnedUp = onMovePinnedUp
        view.onMovePinnedDown = onMovePinnedDown
        view.onEnter = onEnter
        view.onCopyCommand = onCopyCommand
        view.onClosePanel = onClosePanel
        view.onDelete = onDelete
        view.onTogglePin = onTogglePin
        view.onTogglePinnedArea = onTogglePinnedArea
        view.onToggleEditor = onToggleEditor
        view.onUndo = onUndo
        view.onRedo = onRedo
        view.onJoinLines = onJoinLines
        view.onNormalizeForCommand = onNormalizeForCommand
        view.onOpenSettings = onOpenSettings
        return view
    }
    
    func updateNSView(_ nsView: CustomKeyView, context: Context) {
        nsView.isEditorActive = isEditorActive
        nsView.togglePinShortcut = togglePinShortcut
        nsView.togglePinnedAreaShortcut = togglePinnedAreaShortcut
        nsView.editTextShortcut = editTextShortcut
        nsView.deleteShortcut = deleteShortcut
        nsView.undoShortcut = undoShortcut
        nsView.redoShortcut = redoShortcut
        nsView.joinLinesShortcut = joinLinesShortcut
        nsView.normalizeForCommandShortcut = normalizeForCommandShortcut
        nsView.onLeftArrow = onLeftArrow
        nsView.onRightArrow = onRightArrow
        nsView.onUpArrow = onUpArrow
        nsView.onDownArrow = onDownArrow
        nsView.onMovePinnedUp = onMovePinnedUp
        nsView.onMovePinnedDown = onMovePinnedDown
        nsView.onEnter = onEnter
        nsView.onCopyCommand = onCopyCommand
        nsView.onClosePanel = onClosePanel
        nsView.onDelete = onDelete
        nsView.onTogglePin = onTogglePin
        nsView.onTogglePinnedArea = onTogglePinnedArea
        nsView.onToggleEditor = onToggleEditor
        nsView.onUndo = onUndo
        nsView.onRedo = onRedo
        nsView.onJoinLines = onJoinLines
        nsView.onNormalizeForCommand = onNormalizeForCommand
        nsView.onOpenSettings = onOpenSettings
    }
}

struct RawSelectableTextView: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let lineLimit: Int?
    let textColor: NSColor

    func makeNSView(context: Context) -> RawTextContainerView {
        let view = RawTextContainerView()
        view.configure(
            text: text,
            fontSize: fontSize,
            lineLimit: lineLimit,
            textColor: textColor
        )
        return view
    }

    func updateNSView(_ nsView: RawTextContainerView, context: Context) {
        nsView.configure(
            text: text,
            fontSize: fontSize,
            lineLimit: lineLimit,
            textColor: textColor
        )
    }
}

struct EditorTextView: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let commitShortcut: HotKeyManager.Shortcut
    let indentShortcut: HotKeyManager.Shortcut
    let outdentShortcut: HotKeyManager.Shortcut
    let moveLineUpShortcut: HotKeyManager.Shortcut
    let moveLineDownShortcut: HotKeyManager.Shortcut
    let joinLinesShortcut: HotKeyManager.Shortcut
    let normalizeForCommandShortcut: HotKeyManager.Shortcut
    let onEscape: () -> Void
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = EditorNSTextView()
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.commitShortcut = commitShortcut
        textView.indentShortcut = indentShortcut
        textView.outdentShortcut = outdentShortcut
        textView.moveLineUpShortcut = moveLineUpShortcut
        textView.moveLineDownShortcut = moveLineDownShortcut
        textView.joinLinesShortcut = joinLinesShortcut
        textView.normalizeForCommandShortcut = normalizeForCommandShortcut
        textView.onEscape = onEscape
        textView.onCommit = onCommit
        textView.string = text
        context.coordinator.lastSyncedText = text

        scrollView.documentView = textView

        DispatchQueue.main.async {
            scrollView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? EditorNSTextView else { return }
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.commitShortcut = commitShortcut
        textView.indentShortcut = indentShortcut
        textView.outdentShortcut = outdentShortcut
        textView.moveLineUpShortcut = moveLineUpShortcut
        textView.moveLineDownShortcut = moveLineDownShortcut
        textView.joinLinesShortcut = joinLinesShortcut
        textView.normalizeForCommandShortcut = normalizeForCommandShortcut
        textView.onEscape = onEscape
        textView.onCommit = onCommit
        if text != context.coordinator.lastSyncedText {
            textView.string = text
            context.coordinator.lastSyncedText = text
        }
        if textView.frame.width != nsView.contentSize.width {
            textView.frame = NSRect(origin: .zero, size: nsView.contentSize)
        }
        DispatchQueue.main.async {
            if nsView.window?.firstResponder !== textView {
                nsView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var lastSyncedText: String

        init(text: Binding<String>) {
            _text = text
            lastSyncedText = text.wrappedValue
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let updated = textView.string
            lastSyncedText = updated
            text = updated
            textView.undoManager?.setActionName("Edit Text")
            textView.breakUndoCoalescing()
        }
    }
}

final class EditorNSTextView: NSTextView {
    var onEscape: (() -> Void)?
    var onCommit: (() -> Void)?
    var commitShortcut = AppSettings.default.commitEditShortcut
    var indentShortcut = AppSettings.default.indentShortcut
    var outdentShortcut = AppSettings.default.outdentShortcut
    var moveLineUpShortcut = AppSettings.default.moveLineUpShortcut
    var moveLineDownShortcut = AppSettings.default.moveLineDownShortcut
    var joinLinesShortcut = AppSettings.default.joinLinesShortcut
    var normalizeForCommandShortcut = AppSettings.default.normalizeForCommandShortcut
    private var editorCommandObserver: NSObjectProtocol?

    deinit {
        if let editorCommandObserver {
            NotificationCenter.default.removeObserver(editorCommandObserver)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if editorCommandObserver == nil {
            editorCommandObserver = NotificationCenter.default.addObserver(
                forName: .editorCommandRequested,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let rawValue = notification.userInfo?["command"] as? String,
                      let command = EditorCommand(rawValue: rawValue) else { return }
                self.applyEditorCommand(command)
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }

        if HotKeyManager.event(event, matches: commitShortcut) {
            onCommit?()
            return
        }

        if HotKeyManager.event(event, matches: indentShortcut) {
            applyEditorCommand(.indent)
            return
        }

        if HotKeyManager.event(event, matches: outdentShortcut) {
            applyEditorCommand(.outdent)
            return
        }

        if HotKeyManager.event(event, matches: moveLineUpShortcut) {
            applyEditorCommand(.moveLineUp)
            return
        }

        if HotKeyManager.event(event, matches: moveLineDownShortcut) {
            applyEditorCommand(.moveLineDown)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) && !modifiers.contains(.option) && !modifiers.contains(.control) {
            switch event.keyCode {
            case 123:
                moveToBeginningOfLine(nil)
                return
            case 124:
                moveToEndOfLine(nil)
                return
            case 51:
                deleteToBeginningOfLine(nil)
                return
            default:
                break
            }
        }

        if modifiers.contains(.option) && !modifiers.contains(.command) && !modifiers.contains(.control) {
            switch event.keyCode {
            case 123:
                moveWordLeft(nil)
                return
            case 124:
                moveWordRight(nil)
                return
            case 51:
                deleteWordBackward(nil)
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        if key == "z" {
            if modifiers.contains(.shift) {
                if let undoManager, undoManager.canRedo {
                    undoManager.redo()
                    return true
                }
            } else if let undoManager, undoManager.canUndo {
                undoManager.undo()
                return true
            }
        } else if HotKeyManager.event(event, matches: joinLinesShortcut) {
            applyEditorCommand(.joinLines)
            return true
        } else if HotKeyManager.event(event, matches: normalizeForCommandShortcut) {
            applyEditorCommand(.normalizeForCommand)
            return true
        } else if key == "a", !modifiers.contains(.shift), !modifiers.contains(.option), !modifiers.contains(.control) {
            selectAll(nil)
            return true
        } else if key == "c", !modifiers.contains(.shift), !modifiers.contains(.option), !modifiers.contains(.control) {
            copy(nil)
            return true
        } else if key == "x", !modifiers.contains(.shift), !modifiers.contains(.option), !modifiers.contains(.control) {
            cut(nil)
            return true
        } else if key == "v", !modifiers.contains(.shift), !modifiers.contains(.option), !modifiers.contains(.control) {
            paste(nil)
            return true
        } else if key == "t", modifiers.contains(.option) {
            applyEditorCommand(.trimTrailingWhitespace)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    private func applyEditorCommand(_ command: EditorCommand) {
        switch command {
        case .indent:
            transformSelectedLines(actionName: "Indent Lines") { lines in
                lines.map { "\t" + $0 }
            }
        case .outdent:
            transformSelectedLines(actionName: "Outdent Lines") { lines in
                lines.map { line in
                    if line.hasPrefix("\t") {
                        return String(line.dropFirst())
                    }
                    if line.hasPrefix("    ") {
                        return String(line.dropFirst(4))
                    }
                    return line
                }
            }
        case .moveLineUp:
            moveSelectedLines(direction: -1)
        case .moveLineDown:
            moveSelectedLines(direction: 1)
        case .joinLines:
            transformSelectionOrAll(actionName: "Join Lines") { text in
                text.replacingOccurrences(
                    of: #"\s*\n\s*"#,
                    with: " ",
                    options: .regularExpression
                )
            }
        case .normalizeForCommand:
            transformSelectionOrAll(actionName: "Normalize for Command") { text in
                text
                    .replacingOccurrences(of: #"\s*\n\s*"#, with: " ", options: .regularExpression)
                    .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        case .trimTrailingWhitespace:
            transformSelectionOrAll(actionName: "Trim Trailing Whitespace") { text in
                text.replacingOccurrences(
                    of: #"[ \t]+(?=\n|$)"#,
                    with: "",
                    options: .regularExpression
                )
            }
        }
    }

    private func transformSelectedLines(actionName: String, transform: ([String]) -> [String]) {
        let nsText = string as NSString
        let selected = selectedRange()
        let lineRange = nsText.lineRange(for: selected)
        let original = nsText.substring(with: lineRange)
        let originalLines = original.components(separatedBy: "\n")
        let transformed = transform(originalLines).joined(separator: "\n")
        replace(range: lineRange, with: transformed, actionName: actionName)
        setSelectedRange(NSRange(location: lineRange.location, length: transformed.count))
    }

    private func transformSelectionOrAll(actionName: String, transform: (String) -> String) {
        let selected = selectedRange()
        let targetRange: NSRange
        if selected.length > 0 {
            targetRange = selected
        } else {
            targetRange = NSRange(location: 0, length: (string as NSString).length)
        }
        let original = (string as NSString).substring(with: targetRange)
        let transformed = transform(original)
        replace(range: targetRange, with: transformed, actionName: actionName)
        setSelectedRange(NSRange(location: targetRange.location, length: transformed.count))
    }

    private func moveSelectedLines(direction: Int) {
        let selected = selectedRange()
        var lines = string.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return }

        func lineIndex(for location: Int) -> Int {
            let nsText = string as NSString
            let clamped = max(0, min(location, nsText.length))
            let prefix = nsText.substring(to: clamped)
            return prefix.reduce(into: 0) { count, character in
                if character == "\n" {
                    count += 1
                }
            }
        }

        func startLocation(for lineIndex: Int, in lines: [String]) -> Int {
            guard lineIndex > 0 else { return 0 }
            return lines[..<lineIndex].reduce(0) { partial, line in
                partial + line.count + 1
            }
        }

        let selectionEnd = selected.length > 0 ? selected.location + selected.length - 1 : selected.location
        let startLine = lineIndex(for: selected.location)
        let endLine = lineIndex(for: selectionEnd)
        guard startLine <= endLine, endLine < lines.count else { return }

        let movingLines = Array(lines[startLine...endLine])
        lines.removeSubrange(startLine...endLine)

        let targetStartLine: Int
        let actionName: String
        if direction < 0 {
            guard startLine > 0 else { return }
            targetStartLine = startLine - 1
            actionName = "Move Line Up"
        } else {
            guard endLine < lines.count else { return }
            targetStartLine = startLine + 1
            actionName = "Move Line Down"
        }

        lines.insert(contentsOf: movingLines, at: targetStartLine)

        let newString = lines.joined(separator: "\n")
        let newSelectionLocation = startLocation(for: targetStartLine, in: lines)
        let newSelectionLength = movingLines.joined(separator: "\n").count

        replace(
            range: NSRange(location: 0, length: (string as NSString).length),
            with: newString,
            actionName: actionName
        )
        setSelectedRange(NSRange(location: newSelectionLocation, length: newSelectionLength))
    }

    private func replace(range: NSRange, with replacement: String, actionName: String) {
        let previousString = string
        let previousSelection = selectedRange()
        let currentUndoManager = undoManager

        currentUndoManager?.registerUndo(withTarget: self) { target in
            target.restoreEditorState(string: previousString, selection: previousSelection, actionName: actionName)
        }
        currentUndoManager?.setActionName(actionName)

        if let textStorage {
            textStorage.replaceCharacters(in: range, with: replacement)
            didChangeText()
        } else {
            string = (string as NSString).replacingCharacters(in: range, with: replacement)
        }
    }

    private func restoreEditorState(string: String, selection: NSRange, actionName: String) {
        let currentString = self.string
        let currentSelection = selectedRange()
        let currentUndoManager = undoManager
        currentUndoManager?.registerUndo(withTarget: self) { target in
            target.restoreEditorState(string: currentString, selection: currentSelection, actionName: actionName)
        }
        currentUndoManager?.setActionName(actionName)
        self.string = string
        didChangeText()
        setSelectedRange(selection)
    }
}

final class RawTextContainerView: NSView {
    private let textView = NSTextView()
    private let textContainer = NSTextContainer()
    private let layoutManager = NSLayoutManager()
    private let textStorage = NSTextStorage()
    private var measuredHeight: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false

        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 0

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer = textContainer
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        addSubview(textView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: max(1, measuredHeight))
    }

    override func layout() {
        super.layout()
        textContainer.containerSize = NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
        updateTextViewFrame()
    }

    func configure(text: String, fontSize: CGFloat, lineLimit: Int?, textColor: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = lineLimit == nil ? .byWordWrapping : .byTruncatingTail
        paragraph.lineSpacing = 0.5

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        textStorage.setAttributedString(NSAttributedString(string: text, attributes: attributes))
        textContainer.maximumNumberOfLines = lineLimit ?? 0
        layoutManager.ensureLayout(for: textContainer)
        measuredHeight = measuredTextHeight(forWidth: max(bounds.width, 1))
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func updateTextViewFrame() {
        layoutManager.ensureLayout(for: textContainer)
        measuredHeight = measuredTextHeight(forWidth: max(bounds.width, 1))
        let height = max(bounds.height, measuredHeight)
        textView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: height)
        invalidateIntrinsicContentSize()
    }

    private func measuredTextHeight(forWidth width: CGFloat) -> CGFloat {
        textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        return ceil(layoutManager.usedRect(for: textContainer).height)
    }
}

// MARK: - 実際のキーイベントを受け取る AppKit View
class CustomKeyView: NSView {
    var isEditorActive = false
    var togglePinShortcut = AppSettings.default.togglePinShortcut
    var togglePinnedAreaShortcut = AppSettings.default.togglePinnedAreaShortcut
    var editTextShortcut = AppSettings.default.editTextShortcut
    var deleteShortcut = AppSettings.default.deleteItemShortcut
    var undoShortcut = AppSettings.default.undoShortcut
    var redoShortcut = AppSettings.default.redoShortcut
    var joinLinesShortcut = AppSettings.default.joinLinesShortcut
    var normalizeForCommandShortcut = AppSettings.default.normalizeForCommandShortcut
    var onLeftArrow: (() -> Void)?
    var onRightArrow: (() -> Void)?
    var onUpArrow: (() -> Void)?
    var onDownArrow: (() -> Void)?
    var onMovePinnedUp: (() -> Void)?
    var onMovePinnedDown: (() -> Void)?
    var onEnter: (() -> Void)?
    var onCopyCommand: (() -> Void)?
    var onClosePanel: (() -> Void)?
    var onDelete: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var onTogglePinnedArea: (() -> Void)?
    var onToggleEditor: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onJoinLines: (() -> Void)?
    var onNormalizeForCommand: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    private var localKeyMonitor: Any?
    
    // このViewがキーイベントを受け取れるようにする
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installLocalKeyMonitorIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    deinit {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
    }

    private func installLocalKeyMonitorIfNeeded() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let window = self.window,
                  window.isKeyWindow,
                  NSApp.isActive else {
                return event
            }

            if self.isEditorActive {
                return event
            }

            if self.handlePanelKeyDown(event) || self.handlePanelKeyEquivalent(event) {
                return nil
            }
            return event
        }
    }

    @discardableResult
    private func handlePanelKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if modifiers.contains(.shift) {
            switch event.keyCode {
            case 126:
                onMovePinnedUp?()
                return true
            case 125:
                onMovePinnedDown?()
                return true
            default:
                break
            }
        }

        if HotKeyManager.event(event, matches: togglePinnedAreaShortcut) {
            onTogglePinnedArea?()
            return true
        }

        if HotKeyManager.event(event, matches: deleteShortcut) {
            onDelete?()
            return true
        }

        if HotKeyManager.event(event, matches: togglePinShortcut) {
            onTogglePin?()
            return true
        }

        if HotKeyManager.event(event, matches: editTextShortcut) {
            onToggleEditor?()
            return true
        }

        if HotKeyManager.event(event, matches: joinLinesShortcut) {
            onJoinLines?()
            return true
        }

        if HotKeyManager.event(event, matches: normalizeForCommandShortcut) {
            onNormalizeForCommand?()
            return true
        }

        switch event.keyCode {
        case 123:
            onLeftArrow?()
            return true
        case 124:
            onRightArrow?()
            return true
        case 126:
            onUpArrow?()
            return true
        case 125:
            onDownArrow?()
            return true
        case 36, 76:
            print("Panel key handler: Enter")
            onEnter?()
            return true
        case 53:
            onClosePanel?()
            return true
        default:
            return false
        }
    }

    @discardableResult
    private func handlePanelKeyEquivalent(_ event: NSEvent) -> Bool {
        if let key = event.charactersIgnoringModifiers?.lowercased(),
           key == "c",
           event.modifierFlags.contains(.command) {
            onCopyCommand?()
            return true
        }

        if HotKeyManager.event(event, matches: undoShortcut) {
            onUndo?()
            return true
        }

        if HotKeyManager.event(event, matches: redoShortcut) {
            onRedo?()
            return true
        }

        if let key = event.charactersIgnoringModifiers,
           key == ",",
           event.modifierFlags.contains(.command) {
            onOpenSettings?()
            return true
        }

        return false
    }
    
    override func keyDown(with event: NSEvent) {
        if isEditorActive {
            if event.keyCode == 53 {
                onClosePanel?()
                return
            }
            super.keyDown(with: event)
            return
        }

        if !handlePanelKeyDown(event) {
            super.keyDown(with: event)
        }
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isEditorActive {
            if let firstResponderView = window?.firstResponder as? NSView,
               firstResponderView !== self {
                return firstResponderView.performKeyEquivalent(with: event)
            }
            return false
        }

        if handlePanelKeyEquivalent(event) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}
