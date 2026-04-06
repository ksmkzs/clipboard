//
//  UIComponents.swift
//  ClipboardHistory
//
//  Created by あいちゅ on 2026/02/27.
//

import SwiftUI
import AppKit
import Carbon
import WebKit

enum EditorCommand: String {
    case indent
    case outdent
    case moveLineUp
    case moveLineDown
    case toggleMarkdownPreview
    case joinLines
    case normalizeForCommand
    case trimTrailingWhitespace
    case setText
    case setSelectionLocation
    case save
    case saveAs
    case close
    case commit
}

extension Notification.Name {
    static let editorCommandRequested = Notification.Name("EditorCommandRequested")
    static let editorViewValidationRequested = Notification.Name("EditorViewValidationRequested")
}

final class MarkdownPreviewValidationState {
    static let shared = MarkdownPreviewValidationState()

    var selectedText: String?
    var scrollFraction: Double?
    var hasHorizontalOverflow: Bool?
    var promptVisible = false
    var promptURL: String?
    var lastOpenedURL: String?

    private init() {}

    func reset() {
        selectedText = nil
        scrollFraction = nil
        hasHorizontalOverflow = nil
        promptVisible = false
        promptURL = nil
        lastOpenedURL = nil
    }

    func resetPrompt() {
        promptVisible = false
        promptURL = nil
    }

    func respondToPrompt(open: Bool) {
        if open, let promptURL {
            lastOpenedURL = promptURL
        }
        promptVisible = false
        promptURL = nil
    }
}

final class PanelValidationState {
    static let shared = PanelValidationState()

    var selectionScopeRaw: String?
    var pinnedAreaVisible: Bool?

    private init() {}

    func reset() {
        selectionScopeRaw = nil
        pinnedAreaVisible = nil
    }
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
        DispatchQueue.main.async {
            guard let window = view.window, window.isKeyWindow, !view.isEditorActive else { return }
            window.makeFirstResponder(view)
        }
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
        DispatchQueue.main.async {
            guard let window = nsView.window, window.isKeyWindow, !nsView.isEditorActive else { return }
            let responder = window.firstResponder
            if CustomKeyView.shouldReclaimPanelFirstResponder(from: responder, in: window) {
                window.makeFirstResponder(nsView)
            }
        }
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

struct AttributedEditorPreviewTextView: NSViewRepresentable {
    let attributedText: NSAttributedString
    let fontSize: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.usesFindPanel = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.defaultParagraphStyle = {
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            return style
        }()
        textView.textStorage?.setAttributedString(attributedText)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.textStorage?.setAttributedString(attributedText)
        if textView.frame.width != nsView.contentSize.width {
            textView.frame = NSRect(origin: .zero, size: nsView.contentSize)
        }
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
    let orphanCodexDiscardShortcut: HotKeyManager.Shortcut
    let onEscape: () -> Void
    let onCommit: () -> Void
    let onSave: () -> Void
    let onSaveAs: () -> Void
    let onDiscardOrphanCodex: (() -> Void)?
    let onToggleMarkdownPreview: () -> Void
    let onToggleHelp: () -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onResetZoom: () -> Void
    let onSelectionChange: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSelectionChange: onSelectionChange)
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
        textView.orphanCodexDiscardShortcut = orphanCodexDiscardShortcut
        textView.onEscape = onEscape
        textView.onCommit = onCommit
        textView.onSave = onSave
        textView.onSaveAs = onSaveAs
        textView.onDiscardOrphanCodex = onDiscardOrphanCodex
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
        textView.orphanCodexDiscardShortcut = orphanCodexDiscardShortcut
        textView.onEscape = onEscape
        textView.onCommit = onCommit
        textView.onSave = onSave
        textView.onSaveAs = onSaveAs
        textView.onDiscardOrphanCodex = onDiscardOrphanCodex
        textView.onToggleMarkdownPreview = onToggleMarkdownPreview
        textView.onToggleHelp = onToggleHelp
        textView.onZoomIn = onZoomIn
        textView.onZoomOut = onZoomOut
        textView.onResetZoom = onResetZoom
        context.coordinator.onSelectionChange = onSelectionChange
        if text != context.coordinator.lastSyncedText {
            textView.string = text
            context.coordinator.lastSyncedText = text
        }
        if textView.frame.width != nsView.contentSize.width {
            textView.frame = NSRect(origin: .zero, size: nsView.contentSize)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var lastSyncedText: String
        var onSelectionChange: (Int) -> Void
        private var lastSelectionLocation: Int?

        init(text: Binding<String>, onSelectionChange: @escaping (Int) -> Void) {
            _text = text
            lastSyncedText = text.wrappedValue
            self.onSelectionChange = onSelectionChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let updated = textView.string
            lastSyncedText = updated
            text = updated
            textView.undoManager?.setActionName("Edit Text")
            textView.breakUndoCoalescing()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let location = textView.selectedRange().location
            guard location != lastSelectionLocation else { return }
            lastSelectionLocation = location
            onSelectionChange(location)
        }
    }
}

enum MarkdownPreviewScrollSync {
    static func progress(for text: String, selectionLocation: Int) -> CGFloat {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let nsText = normalized as NSString
        guard nsText.length > 0 else { return 0 }

        let clampedLocation = max(0, min(selectionLocation, nsText.length))
        let prefix = nsText.substring(to: clampedLocation)
        let currentLineIndex = prefix.reduce(into: 0) { count, character in
            if character == "\n" {
                count += 1
            }
        }
        let totalLines = max(1, normalized.components(separatedBy: "\n").count)
        guard totalLines > 1 else { return 0 }
        return min(1, max(0, CGFloat(currentLineIndex) / CGFloat(totalLines - 1)))
    }
}

struct MarkdownPreviewSidebar: View {
    let title: String?
    let markdown: String
    let width: CGFloat
    let minHeight: CGFloat
    let fontScale: CGFloat
    let scrollProgress: CGFloat?
    let scrollRequestID: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 11 * fontScale, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 2)
            }

            MarkdownWebPreview(
                markdown: markdown,
                fontScale: fontScale,
                scrollProgress: scrollProgress,
                scrollRequestID: scrollRequestID
            )
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
    let scrollProgress: CGFloat?
    let scrollRequestID: Int

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
        load(markdown, fontScale: fontScale, scrollProgress: scrollProgress, scrollRequestID: scrollRequestID, into: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        load(markdown, fontScale: fontScale, scrollProgress: scrollProgress, scrollRequestID: scrollRequestID, into: nsView, coordinator: context.coordinator)
    }

    private func load(
        _ markdown: String,
        fontScale: CGFloat,
        scrollProgress: CGFloat?,
        scrollRequestID: Int,
        into webView: WKWebView,
        coordinator: Coordinator
    ) {
        let html = MarkdownPreviewRenderer.documentHTML(for: markdown, fontScale: fontScale)
        coordinator.pendingScrollProgress = scrollProgress.map { min(1, max(0, $0)) }
        coordinator.pendingScrollRequestID = scrollRequestID
        if coordinator.lastHTML != html {
            coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)
            return
        }
        coordinator.applyPendingScrollIfNeeded(to: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML = ""
        var pendingScrollProgress: CGFloat?
        var pendingScrollRequestID: Int = .min
        var appliedScrollRequestID: Int = .min

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                if ProcessInfo.processInfo.arguments.contains("--validation-hooks") {
                    MarkdownPreviewValidationState.shared.promptVisible = true
                    MarkdownPreviewValidationState.shared.promptURL = url.absoluteString
                    decisionHandler(.cancel)
                    return
                }
                let alert = NSAlert()
                alert.messageText = "Open link?"
                alert.informativeText = url.absoluteString
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Open")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyPendingScrollIfNeeded(to: webView, force: true)
        }

        func applyPendingScrollIfNeeded(to webView: WKWebView, force: Bool = false) {
            guard force || appliedScrollRequestID != pendingScrollRequestID else { return }
            guard let progress = pendingScrollProgress else { return }
            let script = """
            (function() {
              const root = document.scrollingElement || document.documentElement || document.body;
              if (!root) { return; }
              const maxScroll = Math.max(0, root.scrollHeight - window.innerHeight);
              root.scrollTop = maxScroll * \(Double(progress));
            })();
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
            appliedScrollRequestID = pendingScrollRequestID
        }
    }
}
enum MarkdownPreviewRenderer {
    private struct PreparedMarkdown {
        let lines: [String]
        let referenceLinks: [String: String]
        let footnotes: [(id: String, text: String)]
    }

    private struct RenderContext {
        let referenceLinks: [String: String]
        let footnotes: [(id: String, text: String)]
    }

    fileprivate struct MarkdownListItem {
        enum TaskState {
            case checked
            case unchecked
        }

        let text: String
        let taskState: TaskState?
        let nestedLines: [String]
    }

    fileprivate struct ListMarker {
        enum Kind {
            case unordered
            case ordered(start: Int)
        }

        let kind: Kind
        let indent: Int
        let contentIndent: Int
        let text: String
        let taskState: MarkdownListItem.TaskState?
    }

    fileprivate enum TableAlignment {
        case leading
        case center
        case trailing
        case none
    }

    private struct MatchCapture {
        let fullMatch: String
        let captures: [String]

        init(match: NSTextCheckingResult, in text: String) {
            self.fullMatch = Range(match.range, in: text).map { String(text[$0]) } ?? ""
            self.captures = (1..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    private struct CodeFence {
        let delimiter: Character
        let count: Int
        let info: String
    }

    static func documentHTML(for markdown: String, fontScale: CGFloat = 1.0) -> String {
        let prepared = prepare(markdown)
        let body = renderDocumentBody(prepared)
        let baseFontSize = 13 * max(0.8, min(fontScale, 1.8))
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: dark; }
        html, body { margin: 0; padding: 0; background: transparent; color: rgba(255,255,255,0.92); font-family: -apple-system, BlinkMacSystemFont, \"Helvetica Neue\", sans-serif; font-size: \(String(format: "%.2f", baseFontSize))px; line-height: 1.55; -webkit-user-select: text; user-select: text; }
        body { padding: 10px 12px 12px; cursor: text; }
        h1,h2,h3,h4,h5,h6 { margin: 0 0 10px; line-height: 1.25; font-weight: 700; color: rgba(255,255,255,0.96); }
        h1 { font-size: 1.8em; }
        h2 { font-size: 1.45em; }
        h3 { font-size: 1.2em; }
        p, ul, ol, pre, blockquote, table { margin: 0 0 12px; }
        ul, ol { padding-left: 1.35rem; }
        li + li { margin-top: 4px; }
        li > ul, li > ol { margin-top: 6px; margin-bottom: 0; }
        ul.task-list { list-style: none; padding-left: 0; }
        ul.task-list li { display: flex; align-items: flex-start; gap: 0.55rem; }
        ul.task-list li input[type="checkbox"] { margin: 0.18rem 0 0; width: 0.95rem; height: 0.95rem; accent-color: rgba(157, 201, 255, 0.95); }
        ul.task-list li .task-label { flex: 1; min-width: 0; }
        blockquote { padding: 0 0 0 12px; border-left: 3px solid rgba(255,255,255,0.18); color: rgba(255,255,255,0.78); }
        code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.92em; background: rgba(12,18,26,0.58); color: rgba(246,247,249,0.94); padding: 1px 5px; border-radius: 4px; }
        pre { background: linear-gradient(180deg, rgba(16,23,34,0.96), rgba(11,18,29,0.96)); border: 1px solid rgba(255,255,255,0.08); box-shadow: inset 0 1px 0 rgba(255,255,255,0.04); padding: 13px 14px; border-radius: 10px; overflow-x: auto; white-space: pre; }
        pre code { display: block; white-space: pre; background: transparent; color: rgba(244,247,250,0.96); padding: 0; border-radius: 0; font-size: 0.9em; line-height: 1.65; }
        table { width: 100%; border-collapse: collapse; border-spacing: 0; overflow: hidden; border-radius: 10px; border: 1px solid rgba(255,255,255,0.10); background: rgba(11,18,29,0.40); }
        th, td { padding: 8px 10px; border-bottom: 1px solid rgba(255,255,255,0.08); vertical-align: top; text-align: left; }
        th { font-weight: 700; color: rgba(255,255,255,0.96); background: rgba(255,255,255,0.04); }
        tbody tr:last-child td { border-bottom: 0; }
        .align-center { text-align: center; }
        .align-right { text-align: right; }
        hr { border: 0; border-top: 1px solid rgba(255,255,255,0.12); margin: 14px 0; }
        a { color: rgba(157, 201, 255, 0.95); text-decoration: none; }
        a:hover { text-decoration: underline; }
        .muted { color: rgba(255,255,255,0.54); }
        .footnotes { margin-top: 18px; padding-top: 12px; border-top: 1px solid rgba(255,255,255,0.10); }
        .footnotes ol { margin: 0; }
        .footnote-ref { font-size: 0.82em; vertical-align: super; }
        </style>
        </head>
        <body>\(body.isEmpty ? "<p class=\"muted\">Nothing to preview.</p>" : body)</body>
        </html>
        """
    }

    static func attributedPreview(for markdown: String, fontScale: CGFloat = 1.0) -> NSAttributedString {
        let html = documentHTML(for: markdown, fontScale: fontScale)
        guard let data = html.data(using: .utf8),
              let attributed = try? NSMutableAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return NSAttributedString(string: markdown)
        }
        return attributed
    }

    private static func prepare(_ markdown: String) -> PreparedMarkdown {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var filtered: [String] = []
        var referenceLinks: [String: String] = [:]
        var footnotes: [(id: String, text: String)] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let (id, text) = footnoteDefinition(from: trimmed) {
                var parts = [text]
                index += 1
                while index < lines.count {
                    let continuation = lines[index]
                    if continuation.hasPrefix("    ") {
                        parts.append(String(continuation.dropFirst(4)))
                        index += 1
                    } else if continuation.hasPrefix("\t") {
                        parts.append(String(continuation.dropFirst()))
                        index += 1
                    } else {
                        break
                    }
                }
                footnotes.append((id: id, text: parts.joined(separator: "\n")))
                continue
            }

            if let (label, url) = referenceDefinition(from: trimmed) {
                referenceLinks[label.lowercased()] = url
                index += 1
                continue
            }

            filtered.append(line)
            index += 1
        }

        return PreparedMarkdown(lines: filtered, referenceLinks: referenceLinks, footnotes: footnotes)
    }

    private static func renderDocumentBody(_ prepared: PreparedMarkdown) -> String {
        let context = RenderContext(referenceLinks: prepared.referenceLinks, footnotes: prepared.footnotes)
        var body = renderBlocks(prepared.lines, context: context)
        if !prepared.footnotes.isEmpty {
            let items = prepared.footnotes.map { footnote in
                "<li id=\"fn-\(escapeAttribute(footnote.id))\">\(renderBlocks(footnote.text.components(separatedBy: "\n"), context: context))</li>"
            }.joined()
            body.append("\n<div class=\"footnotes\"><ol>\(items)</ol></div>")
        }
        return body
    }

    private static func renderBlocks(_ lines: [String], context: RenderContext) -> String {
        var html: [String] = []
        var index = 0

        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let fence = codeFenceOpener(from: trimmed) {
                let language = fence.info
                index += 1
                var codeLines: [String] = []
                while index < lines.count {
                    let codeLine = lines[index]
                    if isCodeFenceCloser(
                        trimmed: codeLine.trimmingCharacters(in: .whitespaces),
                        matching: fence
                    ) {
                        index += 1
                        break
                    }
                    codeLines.append(codeLine)
                    index += 1
                }
                let languageClass = language.isEmpty ? "" : " class=\"language-\(escapeAttribute(language))\""
                html.append("<pre><code\(languageClass)>\(escapeHTML(codeLines.joined(separator: "\n")))</code></pre>")
                continue
            }

            if let heading = heading(trimmed) {
                html.append("<h\(heading.level)>\(renderInline(heading.text, context: context))</h\(heading.level)>")
                index += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                html.append("<hr>")
                index += 1
                continue
            }

            if canStartTable(lines: lines, at: index) {
                let (tableHTML, nextIndex) = renderTable(lines: lines, start: index, context: context)
                html.append(tableHTML)
                index = nextIndex
                continue
            }

            if isBlockquoteLine(rawLine) {
                let (quoteHTML, nextIndex) = renderBlockquote(lines: lines, start: index, context: context)
                html.append(quoteHTML)
                index = nextIndex
                continue
            }

            if let marker = parseListMarker(from: rawLine) {
                let (listHTML, nextIndex) = renderList(lines: lines, start: index, marker: marker, context: context)
                html.append(listHTML)
                index = nextIndex
                continue
            }

            let (paragraphHTML, nextIndex) = renderParagraph(lines: lines, start: index, context: context)
            html.append(paragraphHTML)
            index = nextIndex
        }

        return html.joined(separator: "\n")
    }

    private static func renderParagraph(lines: [String], start: Int, context: RenderContext) -> (String, Int) {
        var paragraphLines: [String] = []
        var index = start

        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("```") || heading(trimmed) != nil || isHorizontalRule(trimmed) || isBlockquoteLine(rawLine) || parseListMarker(from: rawLine) != nil || canStartTable(lines: lines, at: index) {
                break
            }
            paragraphLines.append(rawLine)
            index += 1
        }

        var content = ""
        for position in paragraphLines.indices {
            let rawLine = paragraphLines[position]
            let isLast = position == paragraphLines.indices.last
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
            content.append(renderInline(renderedLine, context: context))
            if !isLast {
                content.append(hasHardBreak ? "<br>" : " ")
            }
        }

        return ("<p>\(content)</p>", index)
    }

    private static func renderBlockquote(lines: [String], start: Int, context: RenderContext) -> (String, Int) {
        var quoteLines: [String] = []
        var index = start

        while index < lines.count, isBlockquoteLine(lines[index]) {
            var stripped = lines[index].trimmingCharacters(in: .whitespaces)
            stripped.removeFirst()
            if stripped.first == " " {
                stripped.removeFirst()
            }
            quoteLines.append(stripped)
            index += 1
        }

        return ("<blockquote>\(renderBlocks(quoteLines, context: context))</blockquote>", index)
    }

    private static func renderList(
        lines: [String],
        start: Int,
        marker firstMarker: ListMarker,
        context: RenderContext
    ) -> (String, Int) {
        var items: [MarkdownListItem] = []
        var index = start
        let isOrdered = firstMarker.kind.isOrdered
        let listStartNumber = firstMarker.kind.startNumber

        while index < lines.count {
            guard let marker = parseListMarker(from: lines[index]),
                  marker.indent == firstMarker.indent,
                  marker.kind.isOrdered == isOrdered else {
                break
            }

            index += 1
            var nestedLines: [String] = []
            while index < lines.count {
                let nextLine = lines[index]
                let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)

                if nextTrimmed.isEmpty {
                    nestedLines.append("")
                    index += 1
                    continue
                }

                if let sibling = parseListMarker(from: nextLine) {
                    if sibling.indent == firstMarker.indent && sibling.kind.isOrdered == isOrdered {
                        break
                    }
                    if sibling.indent == firstMarker.indent {
                        break
                    }
                    if sibling.indent < firstMarker.indent {
                        break
                    }
                } else if leadingWhitespaceCount(in: nextLine) <= firstMarker.indent {
                    break
                }

                nestedLines.append(strippingLeadingWhitespace(from: nextLine, count: marker.contentIndent))
                index += 1
            }

            items.append(MarkdownListItem(text: marker.text, taskState: marker.taskState, nestedLines: nestedLines))
        }

        let listTag = isOrdered ? "ol" : "ul"
        var attributes = ""
        if isOrdered, let listStartNumber, listStartNumber != 1 {
            attributes.append(" start=\"\(listStartNumber)\"")
        }
        if !items.isEmpty && items.allSatisfy({ $0.taskState != nil }) {
            attributes.append(" class=\"task-list\"")
        }

        let content = items.map { item -> String in
            let nestedHTML = item.nestedLines.isEmpty ? "" : renderBlocks(item.nestedLines, context: context)
            if let taskState = item.taskState {
                let checkedAttribute = taskState == .checked ? " checked" : ""
                let labelHTML = item.text.isEmpty ? "" : renderInline(item.text, context: context)
                let labelContent = [labelHTML, nestedHTML].filter { !$0.isEmpty }.joined()
                return "<li><input type=\"checkbox\" disabled\(checkedAttribute)><span class=\"task-label\">\(labelContent)</span></li>"
            }

            if nestedHTML.isEmpty {
                return "<li>\(renderInline(item.text, context: context))</li>"
            }

            let lead = item.text.isEmpty ? "" : "<div>\(renderInline(item.text, context: context))</div>"
            return "<li>\(lead)\(nestedHTML)</li>"
        }.joined()

        return ("<\(listTag)\(attributes)>\(content)</\(listTag)>", index)
    }

    private static func renderTable(lines: [String], start: Int, context: RenderContext) -> (String, Int) {
        let headerCells = tableCells(from: lines[start])
        let alignments = tableAlignments(from: lines[start + 1])
        var index = start + 2
        var rows: [[String]] = []

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || !trimmed.contains("|") {
                break
            }
            rows.append(tableCells(from: lines[index]))
            index += 1
        }

        let headerHTML = zipLongest(headerCells, alignments).map { cell, alignment in
            "<th\(alignment.cssClassAttribute)>\(renderInline(cell, context: context))</th>"
        }.joined()
        let bodyHTML = rows.map { row in
            let rowHTML = zipLongest(row, alignments).map { cell, alignment in
                "<td\(alignment.cssClassAttribute)>\(renderInline(cell, context: context))</td>"
            }.joined()
            return "<tr>\(rowHTML)</tr>"
        }.joined()

        return ("<table><thead><tr>\(headerHTML)</tr></thead><tbody>\(bodyHTML)</tbody></table>", index)
    }

    private static func renderInline(_ text: String, context: RenderContext) -> String {
        var placeholders: [String: String] = [:]
        var placeholderCounter = 0

        func reserve(_ html: String) -> String {
            let token = "\u{7}MD\(placeholderCounter)\u{7}"
            placeholderCounter += 1
            placeholders[token] = html
            return token
        }

        var protectedText = protectEscapes(in: text, reserve: reserve)
        protectedText = protectCodeSpans(in: protectedText, reserve: reserve)

        var html = escapeHTML(protectedText)
        html = replacingMatches(in: html, pattern: #"!\[([^\]]*)\]\(([^)\s]+)\)"#) { _ in
            #"<span class="muted">[Image unsupported]</span>"#
        }
        html = replacingMatches(in: html, pattern: #"!\[([^\]]*)\]\[([^\]]+)\]"#) { _ in
            #"<span class="muted">[Image unsupported]</span>"#
        }
        html = replacingMatches(in: html, pattern: #"&lt;(https?://[^&<>]+)&gt;"#) { match in
            let url = match.captures[0]
            return #"<a href="\#(url)">\#(url)</a>"#
        }
        html = replacingMatches(in: html, pattern: #"\[([^\]]+)\]\(([^)\s]+)\)"#) { match in
            #"<a href="\#(match.captures[1])">\#(match.captures[0])</a>"#
        }
        html = replacingMatches(in: html, pattern: #"\[([^\]]+)\]\[([^\]]+)\]"#) { match in
            let label = match.captures[1].lowercased()
            guard let url = context.referenceLinks[label] else { return match.fullMatch }
            return #"<a href="\#(escapeAttribute(url))">\#(match.captures[0])</a>"#
        }
        html = replacingMatches(in: html, pattern: #"\[([^\]]+)\]\[\]"#) { match in
            let label = match.captures[0].lowercased()
            guard let url = context.referenceLinks[label] else { return match.fullMatch }
            return #"<a href="\#(escapeAttribute(url))">\#(match.captures[0])</a>"#
        }
        html = replacingMatches(in: html, pattern: #"\[\^([^\]]+)\]"#) { match in
            let id = match.captures[0]
            if context.footnotes.contains(where: { $0.id == id }) {
                return "<sup class=\"footnote-ref\"><a href=\"#fn-\(escapeAttribute(id))\">[\(escapeHTML(id))]</a></sup>"
            }
            return "<sup class=\"footnote-ref\">[\(escapeHTML(id))]</sup>"
        }
        html = replacingMatches(in: html, pattern: #"\*\*\*([^*]+)\*\*\*"#) { match in
            #"<strong><em>\#(match.captures[0])</em></strong>"#
        }
        html = replacingMatches(in: html, pattern: #"___([^_]+)___"#) { match in
            #"<strong><em>\#(match.captures[0])</em></strong>"#
        }
        html = replacingMatches(in: html, pattern: #"\*\*([^*]+)\*\*"#) { match in
            #"<strong>\#(match.captures[0])</strong>"#
        }
        html = replacingMatches(in: html, pattern: #"__([^_]+)__"#) { match in
            #"<strong>\#(match.captures[0])</strong>"#
        }
        html = replacingMatches(in: html, pattern: #"\*([^*\n]+)\*"#) { match in
            #"<em>\#(match.captures[0])</em>"#
        }
        html = replacingMatches(in: html, pattern: #"_([^_\n]+)_"#) { match in
            #"<em>\#(match.captures[0])</em>"#
        }
        html = replacingMatches(in: html, pattern: #"~~([^~]+)~~"#) { match in
            #"<del>\#(match.captures[0])</del>"#
        }

        for (token, replacement) in placeholders {
            html = html.replacingOccurrences(of: token, with: replacement)
        }
        return html
    }

    private static func referenceDefinition(from line: String) -> (String, String)? {
        guard let match = firstMatch(in: line, pattern: #"^\[([^\]]+)\]:\s+(\S+)\s*$"#) else { return nil }
        return (match.captures[0].trimmingCharacters(in: .whitespaces), match.captures[1].trimmingCharacters(in: .whitespaces))
    }

    private static func footnoteDefinition(from line: String) -> (String, String)? {
        guard let match = firstMatch(in: line, pattern: #"^\[\^([^\]]+)\]:\s*(.+)$"#) else { return nil }
        return (match.captures[0], match.captures[1])
    }

    private static func codeFenceOpener(from line: String) -> CodeFence? {
        guard let delimiter = line.first, delimiter == "`" || delimiter == "~" else { return nil }
        let count = line.prefix { $0 == delimiter }.count
        guard count >= 3 else { return nil }
        let info = String(line.dropFirst(count)).trimmingCharacters(in: .whitespaces)
        return CodeFence(delimiter: delimiter, count: count, info: info)
    }

    private static func isCodeFenceCloser(trimmed line: String, matching fence: CodeFence) -> Bool {
        guard line.first == fence.delimiter else { return false }
        let count = line.prefix { $0 == fence.delimiter }.count
        guard count >= fence.count else { return false }
        return line.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        let level = hashes.count
        guard (1...6).contains(level) else { return nil }
        let remainder = line.dropFirst(level)
        guard remainder.first == " " else { return nil }
        return (level, String(remainder.dropFirst()).trimmingCharacters(in: .whitespaces))
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        line == "---" || line == "***" || line == "___"
    }

    private static func canStartTable(lines: [String], at index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        let header = lines[index].trimmingCharacters(in: .whitespaces)
        let separator = lines[index + 1].trimmingCharacters(in: .whitespaces)
        return header.contains("|") && isTableSeparatorLine(separator)
    }

    private static func isTableSeparatorLine(_ line: String) -> Bool {
        guard line.contains("|") else { return false }
        let cells = tableCells(from: line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return false }
            let core = trimmed.replacingOccurrences(of: ":", with: "")
            return core.count >= 3 && core.allSatisfy { $0 == "-" }
        }
    }

    private static func tableCells(from line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }
        var cells: [String] = []
        var currentCell = ""
        var index = trimmed.startIndex
        var activeCodeSpanFenceLength: Int?

        while index < trimmed.endIndex {
            let character = trimmed[index]

            if character == "\\" {
                let nextIndex = trimmed.index(after: index)
                if nextIndex < trimmed.endIndex {
                    currentCell.append(character)
                    currentCell.append(trimmed[nextIndex])
                    index = trimmed.index(after: nextIndex)
                    continue
                }
            }

            if character == "`" {
                let runStart = index
                var runLength = 0
                while index < trimmed.endIndex, trimmed[index] == "`" {
                    runLength += 1
                    index = trimmed.index(after: index)
                }
                currentCell.append(contentsOf: trimmed[runStart..<index])

                if let currentFenceLength = activeCodeSpanFenceLength {
                    if runLength == currentFenceLength {
                        activeCodeSpanFenceLength = nil
                    }
                } else {
                    activeCodeSpanFenceLength = runLength
                }
                continue
            }

            if character == "|", activeCodeSpanFenceLength == nil {
                cells.append(currentCell.trimmingCharacters(in: .whitespaces))
                currentCell = ""
                index = trimmed.index(after: index)
                continue
            }

            currentCell.append(character)
            index = trimmed.index(after: index)
        }

        cells.append(currentCell.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func tableAlignments(from separatorLine: String) -> [TableAlignment] {
        tableCells(from: separatorLine).map { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            let leading = trimmed.hasPrefix(":")
            let trailing = trimmed.hasSuffix(":")
            switch (leading, trailing) {
            case (true, true): return .center
            case (false, true): return .trailing
            case (true, false): return .leading
            default: return .none
            }
        }
    }

    private static func isBlockquoteLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(">")
    }

    private static func parseListMarker(from line: String) -> ListMarker? {
        let indent = leadingWhitespaceCount(in: line)
        let stripped = String(line.dropFirst(indent))
        guard !stripped.isEmpty else { return nil }

        if let marker = stripped.first, marker == "-" || marker == "*" || marker == "+" {
            guard stripped.dropFirst().first == " " else { return nil }
            let content = String(stripped.dropFirst(2))
            let taskState: MarkdownListItem.TaskState?
            let text: String
            if content.hasPrefix("[ ] ") {
                taskState = .unchecked
                text = String(content.dropFirst(4))
            } else if content.lowercased().hasPrefix("[x] ") {
                taskState = .checked
                text = String(content.dropFirst(4))
            } else {
                taskState = nil
                text = content
            }
            return ListMarker(
                kind: .unordered,
                indent: indent,
                contentIndent: indent + 2,
                text: text,
                taskState: taskState
            )
        }

        var digits = ""
        var currentIndex = stripped.startIndex
        while currentIndex < stripped.endIndex, stripped[currentIndex].isNumber {
            digits.append(stripped[currentIndex])
            currentIndex = stripped.index(after: currentIndex)
        }
        guard !digits.isEmpty, currentIndex < stripped.endIndex, stripped[currentIndex] == "." else { return nil }
        currentIndex = stripped.index(after: currentIndex)
        guard currentIndex < stripped.endIndex, stripped[currentIndex] == " " else { return nil }
        let contentStart = stripped.index(after: currentIndex)
        return ListMarker(
            kind: .ordered(start: Int(digits) ?? 1),
            indent: indent,
            contentIndent: indent + digits.count + 2,
            text: String(stripped[contentStart...]),
            taskState: nil
        )
    }

    private static func protectEscapes(in text: String, reserve: (String) -> String) -> String {
        let escapable = Set("\\`*_{}[]()#+-.!>|")
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let nextIndex = text.index(after: index)
            if character == "\\", nextIndex < text.endIndex {
                let nextCharacter = text[nextIndex]
                if escapable.contains(nextCharacter) {
                    result.append(contentsOf: reserve(escapeHTML(String(nextCharacter))))
                    index = text.index(after: nextIndex)
                    continue
                }
            }
            result.append(character)
            index = nextIndex
        }
        return result
    }

    private static func protectCodeSpans(in text: String, reserve: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "`([^`]+)`") else {
            return text
        }
        var working = text
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: range).reversed() {
            guard match.numberOfRanges == 2,
                  let contentRange = Range(match.range(at: 1), in: text),
                  let matchRange = Range(match.range, in: working) else { continue }
            let placeholder = reserve("<code>\(escapeHTML(String(text[contentRange])))</code>")
            working.replaceSubrange(matchRange, with: placeholder)
        }
        return working
    }

    private static func replacingMatches(
        in text: String,
        pattern: String,
        transform: (MatchCapture) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).reversed()
        for match in matches {
            guard let range = Range(match.range, in: result) else { continue }
            let capture = MatchCapture(match: match, in: result)
            result.replaceSubrange(range, with: transform(capture))
        }
        return result
    }

    private static func firstMatch(in text: String, pattern: String) -> MatchCapture? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) else {
            return nil
        }
        return MatchCapture(match: match, in: text)
    }

    private static func zipLongest(_ cells: [String], _ alignments: [TableAlignment]) -> [(String, TableAlignment)] {
        let count = max(cells.count, alignments.count)
        return (0..<count).map { index in
            let cell = index < cells.count ? cells[index] : ""
            let alignment = index < alignments.count ? alignments[index] : .none
            return (cell, alignment)
        }
    }

    private static func leadingWhitespaceCount(in text: String) -> Int {
        text.prefix { $0 == " " || $0 == "\t" }.count
    }

    private static func strippingLeadingWhitespace(from text: String, count: Int) -> String {
        var remaining = count
        var index = text.startIndex
        while index < text.endIndex, remaining > 0 {
            let character = text[index]
            guard character == " " || character == "\t" else { break }
            remaining -= 1
            index = text.index(after: index)
        }
        return String(text[index...])
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

private extension MarkdownPreviewRenderer.ListMarker.Kind {
    var isOrdered: Bool {
        if case .ordered = self {
            return true
        }
        return false
    }

    var startNumber: Int? {
        if case let .ordered(start) = self {
            return start
        }
        return nil
    }
}

private extension MarkdownPreviewRenderer.TableAlignment {
    var cssClassAttribute: String {
        switch self {
        case .leading, .none:
            return ""
        case .center:
            return " class=\"align-center\""
        case .trailing:
            return " class=\"align-right\""
        }
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
    var onSave: (() -> Void)?
    var onSaveAs: (() -> Void)?
    var onDiscardOrphanCodex: (() -> Void)?
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
    var orphanCodexDiscardShortcut = AppSettings.defaultOrphanCodexDiscardShortcut
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
                if let targetWindowNumber = notification.userInfo?["targetWindowNumber"] as? Int,
                   self.window?.windowNumber != targetWindowNumber {
                    return
                }
                let payloadText = notification.userInfo?["text"] as? String
                self.applyEditorCommand(command, payloadText: payloadText)
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

        if modifiers == [.command] {
            switch key {
            case "a":
                selectAll(nil)
                return true
            case "c":
                copy(nil)
                return true
            case "x":
                cut(nil)
                return true
            case "v":
                paste(nil)
                return true
            default:
                break
            }
        }

        if key == "s", modifiers.contains(.shift), !modifiers.contains(.option), !modifiers.contains(.control) {
            onSaveAs?()
            return true
        } else if key == "s", !modifiers.contains(.shift), !modifiers.contains(.option), !modifiers.contains(.control) {
            onSave?()
            return true
        } else if HotKeyManager.event(event, matches: toggleMarkdownPreviewShortcut) {
            applyEditorCommand(.toggleMarkdownPreview)
            return true
        } else if HotKeyManager.event(event, matches: joinLinesShortcut) {
            applyEditorCommand(.joinLines)
            return true
        } else if HotKeyManager.event(event, matches: normalizeForCommandShortcut) {
            applyEditorCommand(.normalizeForCommand)
            return true
        } else if onDiscardOrphanCodex != nil, HotKeyManager.event(event, matches: orphanCodexDiscardShortcut) {
            onDiscardOrphanCodex?()
            return true
        } else if key == "t", modifiers.contains(.option) {
            applyEditorCommand(.trimTrailingWhitespace)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    private func applyEditorCommand(_ command: EditorCommand, payloadText: String? = nil) {
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
        case .setText:
            replaceAllText(payloadText ?? "")
        case .setSelectionLocation:
            let location = Int(payloadText ?? "") ?? 0
            let clamped = max(0, min(location, (string as NSString).length))
            setSelectedRange(NSRange(location: clamped, length: 0))
        case .save:
            onSave?()
        case .saveAs:
            onSaveAs?()
        case .close:
            onEscape?()
        case .commit:
            onCommit?()
        }
    }

    private func replaceAllText(_ newText: String) {
        guard string != newText else { return }
        replaceCharacters(in: NSRange(location: 0, length: (string as NSString).length), with: newText)
        didChangeText()
        setSelectedRange(NSRange(location: (newText as NSString).length, length: 0))
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
    
    override var acceptsFirstResponder: Bool {
        return true
    }

    static func shouldReclaimPanelFirstResponder(from responder: NSResponder?, in window: NSWindow) -> Bool {
        guard let responder else { return true }
        if responder === window || responder === window.contentView {
            return true
        }
        if let textView = responder as? NSTextView {
            return !textView.isEditable
        }
        return false
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
