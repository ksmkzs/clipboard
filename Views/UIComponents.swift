//
//  UIComponents.swift
//  ClipboardHistory
//
//  Created by あいちゅ on 2026/02/27.
//

import SwiftUI
import AppKit
import WebKit
import Carbon

enum EditorCommand: String {
    case indent
    case outdent
    case moveLineUp
    case moveLineDown
    case toggleMarkdownPreview
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
    var newNoteShortcut: HotKeyManager.Shortcut
    var editTextShortcut: HotKeyManager.Shortcut
    var deleteShortcut: HotKeyManager.Shortcut
    var undoShortcut: HotKeyManager.Shortcut
    var redoShortcut: HotKeyManager.Shortcut
    var copyJoinedShortcut: HotKeyManager.Shortcut
    var copyNormalizedShortcut: HotKeyManager.Shortcut
    var joinLinesShortcut: HotKeyManager.Shortcut
    var normalizeForCommandShortcut: HotKeyManager.Shortcut
    var onLeftArrow: () -> Void
    var onRightArrow: () -> Void
    var onUpArrow: () -> Void
    var onDownArrow: () -> Void
    var onMovePinnedUp: () -> Void
    var onMovePinnedDown: () -> Void
    var onEnter: () -> Void
    var onPasteSelection: () -> Void
    var onCopyCommand: () -> Void
    var onCopyJoinedCommand: () -> Void
    var onCopyNormalizedCommand: () -> Void
    var onClosePanel: () -> Void
    var onDelete: () -> Void
    var onTogglePin: () -> Void
    var onTogglePinnedArea: () -> Void
    var onCreateNewNote: () -> Void
    var onToggleEditor: () -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onJoinLines: () -> Void
    var onNormalizeForCommand: () -> Void
    var onToggleHelp: () -> Void
    var onOpenSettings: () -> Void
    var onZoomIn: () -> Void
    var onZoomOut: () -> Void
    var onResetZoom: () -> Void
    
    func makeNSView(context: Context) -> CustomKeyView {
        let view = CustomKeyView()
        view.isEditorActive = isEditorActive
        view.togglePinShortcut = togglePinShortcut
        view.togglePinnedAreaShortcut = togglePinnedAreaShortcut
        view.newNoteShortcut = newNoteShortcut
        view.editTextShortcut = editTextShortcut
        view.deleteShortcut = deleteShortcut
        view.undoShortcut = undoShortcut
        view.redoShortcut = redoShortcut
        view.copyJoinedShortcut = copyJoinedShortcut
        view.copyNormalizedShortcut = copyNormalizedShortcut
        view.joinLinesShortcut = joinLinesShortcut
        view.normalizeForCommandShortcut = normalizeForCommandShortcut
        view.onLeftArrow = onLeftArrow
        view.onRightArrow = onRightArrow
        view.onUpArrow = onUpArrow
        view.onDownArrow = onDownArrow
        view.onMovePinnedUp = onMovePinnedUp
        view.onMovePinnedDown = onMovePinnedDown
        view.onEnter = onEnter
        view.onPasteSelection = onPasteSelection
        view.onCopyCommand = onCopyCommand
        view.onCopyJoinedCommand = onCopyJoinedCommand
        view.onCopyNormalizedCommand = onCopyNormalizedCommand
        view.onClosePanel = onClosePanel
        view.onDelete = onDelete
        view.onTogglePin = onTogglePin
        view.onTogglePinnedArea = onTogglePinnedArea
        view.onCreateNewNote = onCreateNewNote
        view.onToggleEditor = onToggleEditor
        view.onUndo = onUndo
        view.onRedo = onRedo
        view.onJoinLines = onJoinLines
        view.onNormalizeForCommand = onNormalizeForCommand
        view.onToggleHelp = onToggleHelp
        view.onOpenSettings = onOpenSettings
        view.onZoomIn = onZoomIn
        view.onZoomOut = onZoomOut
        view.onResetZoom = onResetZoom
        return view
    }
    
    func updateNSView(_ nsView: CustomKeyView, context: Context) {
        nsView.isEditorActive = isEditorActive
        nsView.togglePinShortcut = togglePinShortcut
        nsView.togglePinnedAreaShortcut = togglePinnedAreaShortcut
        nsView.newNoteShortcut = newNoteShortcut
        nsView.editTextShortcut = editTextShortcut
        nsView.deleteShortcut = deleteShortcut
        nsView.undoShortcut = undoShortcut
        nsView.redoShortcut = redoShortcut
        nsView.copyJoinedShortcut = copyJoinedShortcut
        nsView.copyNormalizedShortcut = copyNormalizedShortcut
        nsView.joinLinesShortcut = joinLinesShortcut
        nsView.normalizeForCommandShortcut = normalizeForCommandShortcut
        nsView.onLeftArrow = onLeftArrow
        nsView.onRightArrow = onRightArrow
        nsView.onUpArrow = onUpArrow
        nsView.onDownArrow = onDownArrow
        nsView.onMovePinnedUp = onMovePinnedUp
        nsView.onMovePinnedDown = onMovePinnedDown
        nsView.onEnter = onEnter
        nsView.onPasteSelection = onPasteSelection
        nsView.onCopyCommand = onCopyCommand
        nsView.onCopyJoinedCommand = onCopyJoinedCommand
        nsView.onCopyNormalizedCommand = onCopyNormalizedCommand
        nsView.onClosePanel = onClosePanel
        nsView.onDelete = onDelete
        nsView.onTogglePin = onTogglePin
        nsView.onTogglePinnedArea = onTogglePinnedArea
        nsView.onCreateNewNote = onCreateNewNote
        nsView.onToggleEditor = onToggleEditor
        nsView.onUndo = onUndo
        nsView.onRedo = onRedo
        nsView.onJoinLines = onJoinLines
        nsView.onNormalizeForCommand = onNormalizeForCommand
        nsView.onToggleHelp = onToggleHelp
        nsView.onOpenSettings = onOpenSettings
        nsView.onZoomIn = onZoomIn
        nsView.onZoomOut = onZoomOut
        nsView.onResetZoom = onResetZoom
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
    let toggleMarkdownPreviewShortcut: HotKeyManager.Shortcut
    let joinLinesShortcut: HotKeyManager.Shortcut
    let normalizeForCommandShortcut: HotKeyManager.Shortcut
    let onEscape: () -> Void
    let onCommit: () -> Void
    let onToggleMarkdownPreview: () -> Void
    let onToggleHelp: () -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onResetZoom: () -> Void

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
        textView.toggleMarkdownPreviewShortcut = toggleMarkdownPreviewShortcut
        textView.joinLinesShortcut = joinLinesShortcut
        textView.normalizeForCommandShortcut = normalizeForCommandShortcut
        textView.onEscape = onEscape
        textView.onCommit = onCommit
        textView.onToggleMarkdownPreview = onToggleMarkdownPreview
        textView.onToggleHelp = onToggleHelp
        textView.onZoomIn = onZoomIn
        textView.onZoomOut = onZoomOut
        textView.onResetZoom = onResetZoom
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
        textView.toggleMarkdownPreviewShortcut = toggleMarkdownPreviewShortcut
        textView.joinLinesShortcut = joinLinesShortcut
        textView.normalizeForCommandShortcut = normalizeForCommandShortcut
        textView.onEscape = onEscape
        textView.onCommit = onCommit
        textView.onToggleMarkdownPreview = onToggleMarkdownPreview
        textView.onToggleHelp = onToggleHelp
        textView.onZoomIn = onZoomIn
        textView.onZoomOut = onZoomOut
        textView.onResetZoom = onResetZoom
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

struct MarkdownPreviewSidebar: View {
    let title: String?
    let markdown: String
    let width: CGFloat
    let minHeight: CGFloat
    let fontScale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 11 * fontScale, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 2)
            }

            MarkdownWebPreview(markdown: markdown, fontScale: fontScale)
                .frame(width: width)
                .frame(minHeight: minHeight, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0.94, green: 0.95, blue: 0.98).opacity(0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                )
        }
    }
}

struct MarkdownWebPreview: NSViewRepresentable {
    let markdown: String
    let fontScale: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        if #available(macOS 13.3, *) {
            webView.isInspectable = false
        }
        load(markdown, into: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        load(markdown, into: nsView, coordinator: context.coordinator)
    }

    private func load(_ markdown: String, into webView: WKWebView, coordinator: Coordinator) {
        let html = MarkdownPreviewRenderer.documentHTML(for: markdown, fontScale: fontScale)
        guard coordinator.lastHTML != html else { return }
        coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML = ""

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

enum MarkdownPreviewRenderer {
    private struct MarkdownListItem {
        enum TaskState {
            case checked
            case unchecked
        }

        let text: String
        let taskState: TaskState?
    }

    static func documentHTML(for markdown: String, fontScale: CGFloat = 1.0) -> String {
        let body = renderBlocks(markdown)
        let baseFontSize = 13 * max(0.8, min(fontScale, 1.8))
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: dark; }
        html, body { margin: 0; padding: 0; background: transparent; color: rgba(255,255,255,0.92); font-family: -apple-system, BlinkMacSystemFont, \"Helvetica Neue\", sans-serif; font-size: \(String(format: "%.2f", baseFontSize))px; line-height: 1.55; }
        body { padding: 10px 12px 12px; }
        h1,h2,h3,h4,h5,h6 { margin: 0 0 10px; line-height: 1.25; font-weight: 700; color: rgba(255,255,255,0.96); }
        h1 { font-size: 1.8em; }
        h2 { font-size: 1.45em; }
        h3 { font-size: 1.2em; }
        p, ul, ol, pre, blockquote { margin: 0 0 12px; }
        ul, ol { padding-left: 1.35rem; }
        li + li { margin-top: 4px; }
        ul.task-list { list-style: none; padding-left: 0; }
        ul.task-list li { display: flex; align-items: flex-start; gap: 0.55rem; }
        ul.task-list li input[type="checkbox"] { margin: 0.18rem 0 0; width: 0.95rem; height: 0.95rem; accent-color: rgba(157, 201, 255, 0.95); }
        ul.task-list li .task-label { flex: 1; min-width: 0; }
        blockquote { padding: 0 0 0 12px; border-left: 3px solid rgba(255,255,255,0.18); color: rgba(255,255,255,0.78); }
        code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.92em; background: rgba(12,18,26,0.58); color: rgba(246,247,249,0.94); padding: 1px 5px; border-radius: 4px; }
        pre { background: linear-gradient(180deg, rgba(16,23,34,0.96), rgba(11,18,29,0.96)); border: 1px solid rgba(255,255,255,0.08); box-shadow: inset 0 1px 0 rgba(255,255,255,0.04); padding: 13px 14px; border-radius: 10px; overflow-x: auto; white-space: pre; }
        pre code { display: block; white-space: pre; background: transparent; color: rgba(244,247,250,0.96); padding: 0; border-radius: 0; font-size: 0.9em; line-height: 1.65; }
        hr { border: 0; border-top: 1px solid rgba(255,255,255,0.12); margin: 14px 0; }
        a { color: rgba(157, 201, 255, 0.95); text-decoration: none; }
        a:hover { text-decoration: underline; }
        .muted { color: rgba(255,255,255,0.54); }
        </style>
        </head>
        <body>\(body.isEmpty ? "<p class=\"muted\">Nothing to preview.</p>" : body)</body>
        </html>
        """
    }

    private static func renderBlocks(_ markdown: String) -> String {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var html: [String] = []
        var paragraphLines: [String] = []
        var unorderedItems: [MarkdownListItem] = []
        var orderedItems: [String] = []
        var quoteLines: [String] = []
        var codeLines: [String] = []
        var codeFenceLanguage = ""
        var inCodeBlock = false

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            var content = ""
            for index in paragraphLines.indices {
                let rawLine = paragraphLines[index]
                let isLast = index == paragraphLines.indices.last
                let hasEscapedBreak = rawLine.hasSuffix("\\")
                let trailingSpaces = trailingWhitespaceCount(in: rawLine)
                let hasHardBreak = hasEscapedBreak || trailingSpaces >= 2

                var renderedLine = rawLine
                if hasEscapedBreak {
                    renderedLine.removeLast()
                }
                if hasHardBreak {
                    renderedLine = String(renderedLine.dropLast(min(2, trailingSpaces)))
                }
                renderedLine = renderedLine.trimmingCharacters(in: .whitespaces)
                content.append(renderInline(renderedLine))
                if !isLast {
                    content.append(hasHardBreak ? "<br>" : " ")
                }
            }
            html.append("<p>\(content)</p>")
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func flushUnorderedList() {
            guard !unorderedItems.isEmpty else { return }
            let isTaskList = unorderedItems.allSatisfy { $0.taskState != nil }
            let content = unorderedItems.map { item -> String in
                if let taskState = item.taskState {
                    let checkedAttribute = taskState == .checked ? " checked" : ""
                    return "<li><input type=\"checkbox\" disabled\(checkedAttribute)><span class=\"task-label\">\(renderInline(item.text))</span></li>"
                }
                return "<li>\(renderInline(item.text))</li>"
            }.joined()
            let classAttribute = isTaskList ? " class=\"task-list\"" : ""
            html.append("<ul\(classAttribute)>\(content)</ul>")
            unorderedItems.removeAll(keepingCapacity: true)
        }

        func flushOrderedList() {
            guard !orderedItems.isEmpty else { return }
            let content = orderedItems.map { "<li>\(renderInline($0))</li>" }.joined()
            html.append("<ol>\(content)</ol>")
            orderedItems.removeAll(keepingCapacity: true)
        }

        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            let content = quoteLines.map { renderInline($0) }.joined(separator: "<br>")
            html.append("<blockquote><p>\(content)</p></blockquote>")
            quoteLines.removeAll(keepingCapacity: true)
        }

        func flushCodeBlock() {
            guard inCodeBlock else { return }
            let languageClass = codeFenceLanguage.isEmpty ? "" : " class=\"language-\(escapeAttribute(codeFenceLanguage))\""
            let content = escapeHTML(codeLines.joined(separator: "\n"))
            html.append("<pre><code\(languageClass)>\(content)</code></pre>")
            codeLines.removeAll(keepingCapacity: true)
            codeFenceLanguage = ""
            inCodeBlock = false
        }

        func flushAllTextBlocks() {
            flushParagraph()
            flushUnorderedList()
            flushOrderedList()
            flushQuote()
        }

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if inCodeBlock {
                if trimmed.hasPrefix("```") {
                    flushCodeBlock()
                } else {
                    codeLines.append(rawLine)
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                flushAllTextBlocks()
                inCodeBlock = true
                codeFenceLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                continue
            }

            if trimmed.isEmpty {
                flushAllTextBlocks()
                continue
            }

            if let heading = heading(trimmed) {
                flushAllTextBlocks()
                html.append("<h\(heading.level)>\(renderInline(heading.text))</h\(heading.level)>")
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushAllTextBlocks()
                html.append("<hr>")
                continue
            }

            if let quote = blockquoteLine(trimmed) {
                flushParagraph()
                flushUnorderedList()
                flushOrderedList()
                quoteLines.append(quote)
                continue
            }

            if let unordered = unorderedListLine(trimmed) {
                flushParagraph()
                flushOrderedList()
                flushQuote()
                unorderedItems.append(unordered)
                continue
            }

            if let ordered = orderedListLine(trimmed) {
                flushParagraph()
                flushUnorderedList()
                flushQuote()
                orderedItems.append(ordered)
                continue
            }

            paragraphLines.append(rawLine)
        }

        flushCodeBlock()
        flushAllTextBlocks()
        return html.joined(separator: "\n")
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        let level = hashes.count
        guard (1...6).contains(level) else { return nil }
        let remainder = line.dropFirst(level)
        guard remainder.first == " " else { return nil }
        return (level, String(remainder.dropFirst()).trimmingCharacters(in: .whitespaces))
    }

    private static func unorderedListLine(_ line: String) -> MarkdownListItem? {
        guard line.count >= 2 else { return nil }
        let marker = line.first!
        guard marker == "-" || marker == "*" || marker == "+" else { return nil }
        guard line.dropFirst().first == " " else { return nil }
        let content = String(line.dropFirst(2))
        if content.hasPrefix("[ ] ") {
            return MarkdownListItem(text: String(content.dropFirst(4)), taskState: .unchecked)
        }
        if content.lowercased().hasPrefix("[x] ") {
            return MarkdownListItem(text: String(content.dropFirst(4)), taskState: .checked)
        }
        return MarkdownListItem(text: content, taskState: nil)
    }

    private static func orderedListLine(_ line: String) -> String? {
        var digits = ""
        var index = line.startIndex
        while index < line.endIndex, line[index].isNumber {
            digits.append(line[index])
            index = line.index(after: index)
        }
        guard !digits.isEmpty, index < line.endIndex, line[index] == "." else { return nil }
        index = line.index(after: index)
        guard index < line.endIndex, line[index] == " " else { return nil }
        return String(line[line.index(after: index)...])
    }

    private static func blockquoteLine(_ line: String) -> String? {
        guard line.hasPrefix(">") else { return nil }
        return String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func renderInline(_ text: String) -> String {
        let codePattern = try? NSRegularExpression(pattern: "`([^`]+)`")
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var codeSegments: [String] = []
        var withPlaceholders = text

        if let codePattern {
            let matches = codePattern.matches(in: text, range: range).reversed()
            for match in matches {
                guard match.numberOfRanges == 2,
                      let contentRange = Range(match.range(at: 1), in: text),
                      let matchRange = Range(match.range, in: withPlaceholders) else { continue }
                let placeholder = "\u{0}CODE\(codeSegments.count)\u{0}"
                codeSegments.append("<code>\(escapeHTML(String(text[contentRange])))</code>")
                withPlaceholders.replaceSubrange(matchRange, with: placeholder)
            }
        }

        var html = escapeHTML(withPlaceholders)
        html = replace(html, pattern: #"!\[([^\]]*)\]\(([^)\s]+)\)"#, template: #"<img alt="$1" src="$2">"#)
        html = replace(html, pattern: #"\[([^\]]+)\]\(([^)\s]+)\)"#, template: #"<a href="$2">$1</a>"#)
        html = replace(html, pattern: #"\*\*([^*]+)\*\*"#, template: #"<strong>$1</strong>"#)
        html = replace(html, pattern: #"__([^_]+)__"#, template: #"<strong>$1</strong>"#)
        html = replace(html, pattern: #"\*([^*\n]+)\*"#, template: #"<em>$1</em>"#)
        html = replace(html, pattern: #"_([^_\n]+)_"#, template: #"<em>$1</em>"#)
        html = replace(html, pattern: #"~~([^~]+)~~"#, template: #"<del>$1</del>"#)

        for (index, codeHTML) in codeSegments.enumerated() {
            html = html.replacingOccurrences(of: "\u{0}CODE\(index)\u{0}", with: codeHTML)
        }
        return html
    }

    private static func replace(_ text: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func escapeAttribute(_ text: String) -> String {
        escapeHTML(text)
    }

    private static func trailingWhitespaceCount(in text: String) -> Int {
        text.reversed().prefix { $0 == " " || $0 == "\t" }.count
    }
}

final class EditorNSTextView: NSTextView {
    private struct LineInfo {
        let fullRange: NSRange
        let contentRange: NSRange
        let terminatorRange: NSRange
    }

    var onEscape: (() -> Void)?
    var onCommit: (() -> Void)?
    var onToggleMarkdownPreview: (() -> Void)?
    var onToggleHelp: (() -> Void)?
    var onZoomIn: (() -> Void)?
    var onZoomOut: (() -> Void)?
    var onResetZoom: (() -> Void)?
    var commitShortcut = AppSettings.default.commitEditShortcut
    var indentShortcut = AppSettings.default.indentShortcut
    var outdentShortcut = AppSettings.default.outdentShortcut
    var moveLineUpShortcut = AppSettings.default.moveLineUpShortcut
    var moveLineDownShortcut = AppSettings.default.moveLineDownShortcut
    var toggleMarkdownPreviewShortcut = AppSettings.default.toggleMarkdownPreviewShortcut
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
        if isZoomInShortcut(event) {
            onZoomIn?()
            return true
        }
        if isZoomOutShortcut(event) {
            onZoomOut?()
            return true
        }
        if isZoomResetShortcut(event) {
            onResetZoom?()
            return true
        }
        if isHelpShortcut(event) {
            onToggleHelp?()
            return true
        }

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
        } else if HotKeyManager.event(event, matches: toggleMarkdownPreviewShortcut) {
            applyEditorCommand(.toggleMarkdownPreview)
            return true
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
            indentSelectedLines()
        case .outdent:
            outdentSelectedLines()
        case .moveLineUp:
            moveSelectedLines(direction: -1)
        case .moveLineDown:
            moveSelectedLines(direction: 1)
        case .toggleMarkdownPreview:
            onToggleMarkdownPreview?()
        case .joinLines:
            transformSelectionOrAll(actionName: "Join Lines") { text in
                joinLinesText(text)
            }
        case .normalizeForCommand:
            transformSelectionOrAll(actionName: "Normalize for Command") { text in
                normalizeCommandText(text)
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

    private func indentSelectedLines() {
        transformSelectedLines(actionName: "Indent Lines") { line in
            .init(text: "\t" + line, leadingDelta: 1)
        }
    }

    private func outdentSelectedLines() {
        transformSelectedLines(actionName: "Outdent Lines") { line in
            if line.hasPrefix("\t") {
                return .init(text: String(line.dropFirst()), leadingDelta: -1)
            }
            let leadingSpaces = line.prefix { $0 == " " }.count
            let removedCount = min(4, leadingSpaces)
            guard removedCount > 0 else {
                return .init(text: line, leadingDelta: 0)
            }
            return .init(text: String(line.dropFirst(removedCount)), leadingDelta: -removedCount)
        }
    }

    private struct LineTransformResult {
        let text: String
        let leadingDelta: Int
    }

    private func transformSelectedLines(
        actionName: String,
        transformLine: (String) -> LineTransformResult
    ) {
        let nsText = string as NSString
        let selected = selectedRange()
        let lineInfos = lineInfosIntersectingSelection(selected, in: nsText)
        guard let firstLine = lineInfos.first, let lastLine = lineInfos.last else { return }

        let transformedLines: [(info: LineInfo, result: LineTransformResult, terminator: String)] = lineInfos.map { info in
            let originalLine = nsText.substring(with: info.contentRange)
            let result = transformLine(originalLine)
            let terminator = nsText.substring(with: info.terminatorRange)
            return (info, result, terminator)
        }

        let replacementParts: [String] = transformedLines.map { transformed in
            transformed.result.text + transformed.terminator
        }
        let replacement = replacementParts.joined()
        let replacementRange = NSRange(
            location: firstLine.fullRange.location,
            length: NSMaxRange(lastLine.fullRange) - firstLine.fullRange.location
        )

        replace(range: replacementRange, with: replacement, actionName: actionName)

        if selected.length == 0 {
            let caretLine = transformedLines[0]
            let caretColumn = max(0, selected.location - caretLine.info.contentRange.location)
            let shiftedColumn = max(0, min(caretLine.result.text.count, caretColumn + caretLine.result.leadingDelta))
            setSelectedRange(NSRange(location: caretLine.info.contentRange.location + shiftedColumn, length: 0))
            return
        }

        let selectionStart = firstLine.contentRange.location
        let selectedLength = transformedLines.enumerated().reduce(0) { partial, entry in
            let (index, transformed) = entry
            let terminatorLength = index < transformedLines.count - 1 ? transformed.terminator.count : 0
            return partial + transformed.result.text.count + terminatorLength
        }
        setSelectedRange(NSRange(location: selectionStart, length: max(0, selectedLength)))
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
        if selected.length > 0 {
            setSelectedRange(NSRange(location: targetRange.location, length: transformed.count))
        } else {
            let collapsedLocation = min(selected.location, (transformed as NSString).length)
            setSelectedRange(NSRange(location: collapsedLocation, length: 0))
        }
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

        let selectionEnd: Int
        if selected.length > 0 {
            let selectedText = (string as NSString).substring(with: selected)
            if selectedText.hasSuffix("\n") || selectedText.hasSuffix("\r") {
                selectionEnd = max(selected.location, selected.location + selected.length - 2)
            } else {
                selectionEnd = selected.location + selected.length - 1
            }
        } else {
            selectionEnd = selected.location
        }
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
        if selected.length == 0 {
            let originalLineStart = startLocation(for: startLine, in: string.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
            let caretColumn = max(0, selected.location - originalLineStart)
            let clampedColumn = min(caretColumn, lines[targetStartLine].count)
            setSelectedRange(NSRange(location: newSelectionLocation + clampedColumn, length: 0))
        } else {
            setSelectedRange(NSRange(location: newSelectionLocation, length: newSelectionLength))
        }
    }

    private func lineInfosIntersectingSelection(_ selection: NSRange, in text: NSString) -> [LineInfo] {
        if text.length == 0 {
            return [LineInfo(fullRange: NSRange(location: 0, length: 0), contentRange: NSRange(location: 0, length: 0), terminatorRange: NSRange(location: 0, length: 0))]
        }

        let effectiveRange: NSRange
        if selection.length == 0 {
            effectiveRange = text.lineRange(for: selection)
        } else {
            let startRange = text.lineRange(for: NSRange(location: selection.location, length: 0))
            let selectionEndIndex = max(selection.location, min(text.length - 1, selection.location + selection.length - 1))
            let endRange = text.lineRange(for: NSRange(location: selectionEndIndex, length: 0))
            effectiveRange = NSUnionRange(startRange, endRange)
        }

        var infos: [LineInfo] = []
        var cursor = effectiveRange.location
        let upperBound = NSMaxRange(effectiveRange)

        while cursor < upperBound {
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: cursor, length: 0))
            infos.append(
                LineInfo(
                    fullRange: NSRange(location: lineStart, length: lineEnd - lineStart),
                    contentRange: NSRange(location: lineStart, length: contentsEnd - lineStart),
                    terminatorRange: NSRange(location: contentsEnd, length: lineEnd - contentsEnd)
                )
            )
            cursor = max(lineEnd, cursor + 1)
        }

        return infos
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

func normalizeCommandText(_ text: String) -> String {
    standardizedLines(text)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .joined(separator: "\n")
}

func joinLinesText(_ text: String) -> String {
    standardizedLines(text)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .joined()
}

private func standardizedLines(_ text: String) -> [String] {
    text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .components(separatedBy: "\n")
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
    var newNoteShortcut = AppSettings.default.newNoteShortcut
    var editTextShortcut = AppSettings.default.editTextShortcut
    var deleteShortcut = AppSettings.default.deleteItemShortcut
    var undoShortcut = AppSettings.default.undoShortcut
    var redoShortcut = AppSettings.default.redoShortcut
    var copyJoinedShortcut = AppSettings.default.copyJoinedShortcut
    var copyNormalizedShortcut = AppSettings.default.copyNormalizedShortcut
    var joinLinesShortcut = AppSettings.default.joinLinesShortcut
    var normalizeForCommandShortcut = AppSettings.default.normalizeForCommandShortcut
    var onLeftArrow: (() -> Void)?
    var onRightArrow: (() -> Void)?
    var onUpArrow: (() -> Void)?
    var onDownArrow: (() -> Void)?
    var onMovePinnedUp: (() -> Void)?
    var onMovePinnedDown: (() -> Void)?
    var onEnter: (() -> Void)?
    var onPasteSelection: (() -> Void)?
    var onCopyCommand: (() -> Void)?
    var onCopyJoinedCommand: (() -> Void)?
    var onCopyNormalizedCommand: (() -> Void)?
    var onClosePanel: (() -> Void)?
    var onDelete: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var onTogglePinnedArea: (() -> Void)?
    var onCreateNewNote: (() -> Void)?
    var onToggleEditor: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onJoinLines: (() -> Void)?
    var onNormalizeForCommand: (() -> Void)?
    var onToggleHelp: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onZoomIn: (() -> Void)?
    var onZoomOut: (() -> Void)?
    var onResetZoom: (() -> Void)?
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

        if HotKeyManager.event(event, matches: newNoteShortcut) {
            onCreateNewNote?()
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
        if isZoomInShortcut(event) {
            onZoomIn?()
            return true
        }

        if isZoomOutShortcut(event) {
            onZoomOut?()
            return true
        }

        if isZoomResetShortcut(event) {
            onResetZoom?()
            return true
        }

        if isHelpShortcut(event) {
            onToggleHelp?()
            return true
        }

        if let characters = event.charactersIgnoringModifiers,
           characters == "\r" || characters == "\u{3}" {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers == .command {
                onPasteSelection?()
                return true
            }
        }

        if HotKeyManager.event(event, matches: copyJoinedShortcut) {
            onCopyJoinedCommand?()
            return true
        }

        if HotKeyManager.event(event, matches: copyNormalizedShortcut) {
            onCopyNormalizedCommand?()
            return true
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if let key = event.charactersIgnoringModifiers?.lowercased(),
           key == "c",
           modifiers == .command {
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
        if isZoomInShortcut(event) {
            onZoomIn?()
            return true
        }
        if isZoomOutShortcut(event) {
            onZoomOut?()
            return true
        }
        if isZoomResetShortcut(event) {
            onResetZoom?()
            return true
        }
        if isHelpShortcut(event) {
            onToggleHelp?()
            return true
        }

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

private func isHelpShortcut(_ event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard modifiers.contains(.command),
          !modifiers.contains(.option),
          !modifiers.contains(.control) else {
        return false
    }
    let directCharacters = event.characters ?? ""
    let ignoringModifiers = event.charactersIgnoringModifiers ?? ""
    return event.keyCode == 44 || directCharacters == "?" || directCharacters == "/" || ignoringModifiers == "/"
}

private func isZoomInShortcut(_ event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard modifiers == .command else { return false }
    return event.keyCode == UInt16(kVK_ANSI_Equal)
}

private func isZoomOutShortcut(_ event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard modifiers == .command else { return false }
    return event.keyCode == UInt16(kVK_ANSI_Minus)
}

private func isZoomResetShortcut(_ event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard modifiers == .command else { return false }
    return event.keyCode == UInt16(kVK_ANSI_0)
}
