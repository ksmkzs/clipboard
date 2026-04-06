import SwiftUI
import SwiftData
import Carbon

struct HistoryRowView: View {
    static let maxInlineTextBytes = LargeTextPolicy.inlineThresholdBytes

    struct TextPreviewAnalysis: Equatable {
        let preview: String
        let shouldShowExpand: Bool
        let isInlineRestricted: Bool
    }

    enum PinnedDropIndicatorPosition {
        case before
        case after
    }

    let item: ClipboardItem
    let isSelected: Bool
    let isFocused: Bool
    let theme: InterfaceThemeDefinition
    let isCompact: Bool
    let badgeText: String?
    let pinLabel: String?
    let showPinLabelEditor: Bool
    let showsMetadata: Bool
    let isDetailPresented: Bool
    let isEditingText: Bool
    let pinnedDropIndicatorPosition: PinnedDropIndicatorPosition?
    let imageLoader: (String) -> NSImage?
    let onSelect: () -> Void
    let onToggleDetail: () -> Void
    let onBeginEditing: () -> Void
    let onCommitEditor: () -> Void
    let onCancelEditor: () -> Void
    let onCopyRaw: () -> Void
    let onToggleHelp: () -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onResetZoom: () -> Void
    let interfaceZoomScale: CGFloat
    let commitEditShortcut: HotKeyManager.Shortcut
    let indentShortcut: HotKeyManager.Shortcut
    let outdentShortcut: HotKeyManager.Shortcut
    let moveLineUpShortcut: HotKeyManager.Shortcut
    let moveLineDownShortcut: HotKeyManager.Shortcut
    let toggleMarkdownPreviewShortcut: HotKeyManager.Shortcut
    let joinLinesShortcut: HotKeyManager.Shortcut
    let normalizeForCommandShortcut: HotKeyManager.Shortcut
    @Binding var editorText: String
    let isMarkdownPreviewVisible: Bool
    let onRenamePin: (String) -> Void
    let onTabFromPinLabel: () -> Void
    let onToggleMarkdownPreview: () -> Void
    let onTogglePinned: () -> Void
    let onDelete: () -> Void
    @State private var pinLabelDraft = ""
    @State private var markdownPreviewWidth: CGFloat = 0

    private var zoomScale: CGFloat {
        max(0.8, min(interfaceZoomScale, 1.8))
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        value * zoomScale
    }

    private var markdownPreviewSidebarWidth: CGFloat {
        let fallback = scaled(228)
        let currentWidth = markdownPreviewWidth > 0 ? markdownPreviewWidth : fallback
        return min(max(currentWidth, scaled(160)), scaled(420))
    }

    private var inlineEditorHeight: CGFloat {
        scaled(isCompact ? 108 : 140)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: isCompact ? 4 : 5) {
                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: scaled(isCompact ? 8 : 8.5), weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                if showPinLabelEditor {
                    pinLabelField
                }

                HStack(alignment: .top, spacing: 4) {
                    leadingActionColumn

                    VStack(alignment: .leading, spacing: isCompact ? 4 : 5) {
                        itemContent
                        if showsMetadata {
                            metaLine
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            VStack(spacing: 8) {
                Button(action: onTogglePinned) {
                    Image(systemName: item.isPinned ? "star.fill" : "star")
                        .font(.system(size: scaled(isCompact ? 11 : 12), weight: .medium))
                        .foregroundStyle(item.isPinned ? Color(red: 0.84, green: 0.67, blue: 0.18) : .primary)
                        .frame(width: scaled(18), height: scaled(18))
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? "Unpin" : "Pin")

                if item.type == .text {
                    if isEditingText {
                        Button(action: onCancelEditor) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: scaled(isCompact ? 10 : 11), weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: scaled(18), height: scaled(18))
                        }
                        .buttonStyle(.plain)
                        .help("Cancel editing")
                    }

                    Button(action: {
                        if isEditingText {
                            onCommitEditor()
                        } else {
                            onBeginEditing()
                        }
                    }) {
                        Image(systemName: isEditingText ? "checkmark.circle" : "pencil")
                            .font(.system(size: scaled(isCompact ? 10 : 11), weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: scaled(18), height: scaled(18))
                    }
                    .buttonStyle(.plain)
                    .disabled(isLargeTextItem && !isEditingText)
                    .help(isEditingText ? "Save text" : "Edit text")
                } else {
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                Button(action: onDelete) {
                    Image(systemName: "delete.left")
                        .font(.system(size: scaled(isCompact ? 10 : 11), weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: scaled(18), height: scaled(18))
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, isCompact ? 8 : 9)
        .padding(.vertical, isCompact ? 7 : 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(backgroundFillColor)
        )
        .overlay(
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderStrokeColor, lineWidth: borderLineWidth)
                if pinnedDropIndicatorPosition == .before {
                    dropIndicator
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                if pinnedDropIndicatorPosition == .after {
                    dropIndicator
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onAppear {
            syncPinLabelDraft()
            if markdownPreviewWidth == 0 {
                markdownPreviewWidth = scaled(228)
            }
        }
        .onChange(of: pinLabel) { _, _ in
            syncPinLabelDraft()
        }
        .animation(nil, value: theme.titleEnglish)
    }

    private var pinLabelField: some View {
        PinNameField(
            placeholder: isCompact ? "Pin name" : "Pinned name",
            text: $pinLabelDraft,
            fontSize: scaled(isCompact ? 10 : 10.5),
            onSubmit: {
                onRenamePin(pinLabelDraft)
            },
            onTab: {
                onRenamePin(pinLabelDraft)
                onTabFromPinLabel()
            }
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.08))
        )
    }

    private var expandButton: some View {
        Button(action: onToggleDetail) {
            Image(systemName: isDetailPresented ? "chevron.down" : "chevron.right")
                .font(.system(size: scaled(isCompact ? 10 : 11), weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: scaled(12), height: scaled(24), alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isDetailPresented ? "Close detail" : "Open detail")
    }

    @ViewBuilder
    private var leadingActionColumn: some View {
        VStack(spacing: 2) {
            if shouldShowExpandButton {
                expandButton
            } else {
                Color.clear
                    .frame(width: 12, height: 24)
            }
        }
    }

    @ViewBuilder
    private var itemContent: some View {
        if item.type == .text, let text = item.textContent {
            let previewAnalysis = textPreviewAnalysis
            if isEditingText {
                editorContent
            } else
            if isDetailPresented {
                if previewAnalysis?.isInlineRestricted == true {
                    largeTextDetail(preview: previewAnalysis?.preview ?? "")
                } else {
                    Text(text)
                        .lineLimit(nil)
                        .font(.system(size: scaled(isCompact ? 10 : 11)))
                        .lineSpacing(0.5)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, minHeight: scaled(isCompact ? 42 : 58), alignment: .topLeading)
                }
            } else {
                Text(previewText(for: text))
                    .lineLimit(isCompact ? 3 : 4)
                    .font(.system(size: scaled(isCompact ? 10 : 11)))
                    .lineSpacing(0.5)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: scaled(isCompact ? 42 : 58), alignment: .topLeading)
                    .foregroundColor(.primary)
            }
        } else if item.type == .image, let fileName = item.imageFileName {
            if let nsImage = imageLoader(fileName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: scaled(isCompact ? 46 : 64))
                    .cornerRadius(6)
            } else {
                Text("Unable to load image")
                    .font(.system(size: scaled(isCompact ? 10 : 11)))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: scaled(isCompact ? 26 : 34), alignment: .topLeading)
            }
        }
    }

    private var metaLine: some View {
        HStack(spacing: 8) {
            if showsMetadata {
                Text(item.type == .text ? "TEXT" : "IMAGE")
                if item.isPinned {
                    Text("PINNED")
                }
                Spacer()
                Text(item.timestamp.formatted(date: .omitted, time: .shortened))
            }
        }
        .font(.system(size: scaled(isCompact ? 8.5 : 9.5), weight: .medium))
        .foregroundStyle(.secondary)
    }

    private var dropIndicator: some View {
        Text(">-<")
            .font(.system(size: scaled(9), weight: .bold, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.clear)
        .offset(y: pinnedDropIndicatorPosition == .before ? -9 : 9)
    }

    private var backgroundFillColor: Color {
        if isSelected {
            return theme.selectedFill
        }
        if isFocused {
            return theme.focusFill
        }
        return theme.cardFill
    }

    private var borderStrokeColor: Color {
        if isSelected {
            return Color.white.opacity(0.40)
        }
        if isFocused {
            return Color.white.opacity(0.30)
        }
        return Color.white.opacity(0.24)
    }

    private var borderLineWidth: CGFloat {
        if isSelected {
            return 1.1
        }
        if isFocused {
            return 1.0
        }
        return 0.9
    }

    private var shouldShowExpandButton: Bool {
        textPreviewAnalysis?.shouldShowExpand ?? false
    }

    @ViewBuilder
    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isMarkdownPreviewVisible {
                HStack {
                    Spacer(minLength: 0)
                    Text("Markdown Preview")
                        .font(.system(size: scaled(isCompact ? 10 : 11), weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: markdownPreviewSidebarWidth, alignment: .leading)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                editorTextPane
                if isMarkdownPreviewVisible {
                    MarkdownPreviewResizeHandle { delta in
                        markdownPreviewWidth = min(
                            max(markdownPreviewSidebarWidth - delta, scaled(160)),
                            scaled(420)
                        )
                    }
                    markdownPreviewPane
                }
            }
        }
    }

    private var editorTextPane: some View {
        EditorTextView(
            text: $editorText,
            fontSize: scaled(isCompact ? 10 : 11),
            commitShortcut: commitEditShortcut,
            indentShortcut: indentShortcut,
            outdentShortcut: outdentShortcut,
            moveLineUpShortcut: moveLineUpShortcut,
            moveLineDownShortcut: moveLineDownShortcut,
            toggleMarkdownPreviewShortcut: toggleMarkdownPreviewShortcut,
            joinLinesShortcut: joinLinesShortcut,
            normalizeForCommandShortcut: normalizeForCommandShortcut,
            orphanCodexDiscardShortcut: AppSettings.defaultOrphanCodexDiscardShortcut,
            onEscape: onCancelEditor,
            onCommit: onCommitEditor,
            onSave: {},
            onSaveAs: {},
            onDiscardOrphanCodex: nil,
            onToggleMarkdownPreview: onToggleMarkdownPreview,
            onToggleHelp: onToggleHelp,
            onZoomIn: onZoomIn,
            onZoomOut: onZoomOut,
            onResetZoom: onResetZoom,
            onSelectionChange: { _ in }
        )
        // Keep inline editors at a fixed height so typing does not reflow the outer list
        // and cause row-disappearance / parent-scroll jitter.
        .frame(
            maxWidth: .infinity,
            minHeight: inlineEditorHeight,
            maxHeight: inlineEditorHeight,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
        )
    }

    private var markdownPreviewPane: some View {
        MarkdownPreviewSidebar(
            title: nil,
            markdown: editorText,
            width: markdownPreviewSidebarWidth,
            minHeight: inlineEditorHeight,
            fontScale: zoomScale,
            scrollProgress: nil,
            scrollRequestID: 0
        )
        .frame(height: inlineEditorHeight, alignment: .top)
    }

    private func previewText(for text: String) -> String {
        guard let analysis = textPreviewAnalysis else { return text }
        if analysis.shouldShowExpand {
            return analysis.preview + "…"
        }
        return analysis.preview
    }

    private func syncPinLabelDraft() {
        let nextValue = pinLabel ?? ""
        if pinLabelDraft != nextValue {
            pinLabelDraft = nextValue
        }
    }

    private var isLargeTextItem: Bool {
        item.isLargeText || (item.textByteCount > Self.maxInlineTextBytes)
    }

    private var textPreviewAnalysis: TextPreviewAnalysis? {
        guard item.type == .text, let text = item.textContent else { return nil }
        let analysis = Self.analyzeTextPreview(
            text,
            previewLimit: isCompact ? 220 : 420,
            lineLimit: isCompact ? 3 : 4
        )
        if isLargeTextItem && !analysis.isInlineRestricted {
            return TextPreviewAnalysis(
                preview: analysis.preview,
                shouldShowExpand: true,
                isInlineRestricted: true
            )
        }
        return analysis
    }

    static func analyzeTextPreview(_ text: String, previewLimit: Int, lineLimit: Int) -> TextPreviewAnalysis {
        let exceedsInlineThreshold = textExceedsInlineThreshold(text)
        guard previewLimit > 0 else {
            return TextPreviewAnalysis(
                preview: "",
                shouldShowExpand: !text.isEmpty,
                isInlineRestricted: exceedsInlineThreshold
            )
        }

        var preview = String()
        preview.reserveCapacity(min(previewLimit, 512))

        var characterCount = 0
        var lineCount = 1
        var utf8Count = 0

        for character in text {
            utf8Count += String(character).utf8.count
            characterCount += 1

            if characterCount <= previewLimit {
                preview.append(character)
            } else {
                return TextPreviewAnalysis(
                    preview: preview,
                    shouldShowExpand: true,
                    isInlineRestricted: exceedsInlineThreshold || utf8Count > maxInlineTextBytes
                )
            }

            if character.isNewline {
                lineCount += 1
                if lineCount > lineLimit {
                    return TextPreviewAnalysis(
                        preview: preview,
                        shouldShowExpand: true,
                        isInlineRestricted: exceedsInlineThreshold || utf8Count > maxInlineTextBytes
                    )
                }
            }
        }

        return TextPreviewAnalysis(
            preview: preview,
            shouldShowExpand: false,
            isInlineRestricted: exceedsInlineThreshold || utf8Count > maxInlineTextBytes
        )
    }

    private static func textExceedsInlineThreshold(_ text: String) -> Bool {
        guard let thresholdIndex = text.utf8.index(
            text.utf8.startIndex,
            offsetBy: maxInlineTextBytes,
            limitedBy: text.utf8.endIndex
        ) else {
            return false
        }
        return thresholdIndex != text.utf8.endIndex
    }

    private func largeTextDetail(preview: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Large clipboard item", systemImage: "exclamationmark.triangle")
                .font(.system(size: scaled(isCompact ? 10.5 : 11.5), weight: .semibold))
            Text("This text is too large to render or edit safely in the app. Copy and paste still work.")
                .font(.system(size: scaled(isCompact ? 10 : 11)))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(preview + "…")
                .font(.system(size: scaled(isCompact ? 10 : 11), design: .monospaced))
                .lineSpacing(0.5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(8)
                .background(Color.black.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Button("Copy raw", action: onCopyRaw)
                .buttonStyle(.borderedProminent)
                .controlSize(isCompact ? .small : .regular)
        }
        .frame(maxWidth: .infinity, minHeight: scaled(isCompact ? 72 : 92), alignment: .topLeading)
    }

}

extension HistoryRowView: Equatable {
    static func == (lhs: HistoryRowView, rhs: HistoryRowView) -> Bool {
        lhs.item.id == rhs.item.id &&
        lhs.item.type == rhs.item.type &&
        lhs.item.isPinned == rhs.item.isPinned &&
        lhs.item.pinOrder == rhs.item.pinOrder &&
        lhs.item.timestamp == rhs.item.timestamp &&
        lhs.item.textContent == rhs.item.textContent &&
        lhs.item.isLargeText == rhs.item.isLargeText &&
        lhs.item.textByteCount == rhs.item.textByteCount &&
        lhs.item.textStorageFileName == rhs.item.textStorageFileName &&
        lhs.item.imageFileName == rhs.item.imageFileName &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isFocused == rhs.isFocused &&
        lhs.isCompact == rhs.isCompact &&
        lhs.badgeText == rhs.badgeText &&
        lhs.pinLabel == rhs.pinLabel &&
        lhs.showPinLabelEditor == rhs.showPinLabelEditor &&
        lhs.showsMetadata == rhs.showsMetadata &&
        lhs.isDetailPresented == rhs.isDetailPresented &&
        lhs.isEditingText == rhs.isEditingText &&
        lhs.isMarkdownPreviewVisible == rhs.isMarkdownPreviewVisible &&
        lhs.pinnedDropIndicatorPosition == rhs.pinnedDropIndicatorPosition &&
        lhs.editorText == rhs.editorText
    }
}

private struct PinNameField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let fontSize: CGFloat
    let onSubmit: () -> Void
    let onTab: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onTab: onTab)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize, weight: .semibold)
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.placeholderString = placeholder
        nsView.font = .systemFont(ofSize: fontSize, weight: .semibold)
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        let onSubmit: () -> Void
        let onTab: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void, onTab: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
            self.onTab = onTab
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
            onSubmit()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                text = textView.string
                onTab()
                return true
            }
            return false
        }
    }
}
