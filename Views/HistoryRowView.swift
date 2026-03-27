import SwiftUI
import SwiftData
import Carbon

struct HistoryRowView: View {
    enum PinnedDropIndicatorPosition {
        case before
        case after
    }

    let item: ClipboardItem
    let isSelected: Bool
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
    let commitEditShortcut: HotKeyManager.Shortcut
    let indentShortcut: HotKeyManager.Shortcut
    let outdentShortcut: HotKeyManager.Shortcut
    let moveLineUpShortcut: HotKeyManager.Shortcut
    let moveLineDownShortcut: HotKeyManager.Shortcut
    let joinLinesShortcut: HotKeyManager.Shortcut
    let normalizeForCommandShortcut: HotKeyManager.Shortcut
    @Binding var editorText: String
    let onRenamePin: (String) -> Void
    let onTabFromPinLabel: () -> Void
    let onTogglePinned: () -> Void
    let onDelete: () -> Void
    @State private var pinLabelDraft = ""
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: isCompact ? 4 : 5) {
                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: isCompact ? 8 : 8.5, weight: .semibold))
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
                        .font(.system(size: isCompact ? 11 : 12, weight: .medium))
                        .foregroundStyle(item.isPinned ? Color(red: 0.84, green: 0.67, blue: 0.18) : .primary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? "Unpin" : "Pin")

                if item.type == .text {
                    if isEditingText {
                        Button(action: onCancelEditor) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: isCompact ? 10 : 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 18, height: 18)
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
                            .font(.system(size: isCompact ? 10 : 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help(isEditingText ? "Save text" : "Edit text")
                } else {
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: isCompact ? 10 : 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
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
                    .stroke(Color.white.opacity(isSelected ? 0.40 : 0.24), lineWidth: isSelected ? 1.1 : 0.9)
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
        }
        .onChange(of: pinLabel) { _, _ in
            syncPinLabelDraft()
        }
    }

    private var pinLabelField: some View {
        PinNameField(
            placeholder: isCompact ? "Pin name" : "Pinned name",
            text: $pinLabelDraft,
            fontSize: isCompact ? 10 : 10.5,
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
                .font(.system(size: isCompact ? 10 : 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12, height: 24, alignment: .center)
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
            if isEditingText {
                EditorTextView(
                    text: $editorText,
                    fontSize: isCompact ? 10 : 11,
                    commitShortcut: commitEditShortcut,
                    indentShortcut: indentShortcut,
                    outdentShortcut: outdentShortcut,
                    moveLineUpShortcut: moveLineUpShortcut,
                    moveLineDownShortcut: moveLineDownShortcut,
                    joinLinesShortcut: joinLinesShortcut,
                    normalizeForCommandShortcut: normalizeForCommandShortcut,
                    onEscape: onCancelEditor,
                    onCommit: onCommitEditor
                )
                    .frame(maxWidth: .infinity, minHeight: isCompact ? 108 : 140, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                    )
            } else
            if isDetailPresented {
                Text(text)
                    .lineLimit(nil)
                    .font(.system(size: isCompact ? 10 : 11))
                    .lineSpacing(0.5)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: isCompact ? 42 : 58, alignment: .topLeading)
            } else {
                Text(previewText(for: text))
                    .lineLimit(isCompact ? 3 : 4)
                    .font(.system(size: isCompact ? 10 : 11))
                    .lineSpacing(0.5)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: isCompact ? 42 : 58, alignment: .topLeading)
                    .foregroundColor(.primary)
            }
        } else if item.type == .image, let fileName = item.imageFileName {
            if let nsImage = imageLoader(fileName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: isCompact ? 46 : 64)
                    .cornerRadius(6)
            } else {
                Text("Unable to load image")
                    .font(.system(size: isCompact ? 10 : 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: isCompact ? 26 : 34, alignment: .topLeading)
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
        .font(.system(size: isCompact ? 8.5 : 9.5, weight: .medium))
        .foregroundStyle(.secondary)
    }

    private var dropIndicator: some View {
        Text(">-<")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.clear)
        .offset(y: pinnedDropIndicatorPosition == .before ? -9 : 9)
    }

    private var backgroundFillColor: Color {
        if isSelected {
            return Color(red: 0.72, green: 0.80, blue: 0.90).opacity(0.34)
        }
        return Color.white.opacity(0.20)
    }

    private var shouldShowExpandButton: Bool {
        guard item.type == .text, let text = item.textContent else { return false }
        let lineLimit = isCompact ? 3 : 4
        let explicitLineCount = text.split(whereSeparator: \.isNewline).count
        if explicitLineCount > lineLimit {
            return true
        }
        return text.count > (isCompact ? 220 : 420)
    }

    private func previewText(for text: String) -> String {
        let limit = isCompact ? 220 : 420
        guard text.count > limit else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<endIndex]) + "…"
    }

    private func syncPinLabelDraft() {
        let nextValue = pinLabel ?? ""
        if pinLabelDraft != nextValue {
            pinLabelDraft = nextValue
        }
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

    func makeNSView(context: Context) -> PinNameTextField {
        let field = PinNameTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize, weight: .semibold)
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.onTab = context.coordinator.handleTab
        return field
    }

    func updateNSView(_ nsView: PinNameTextField, context: Context) {
        nsView.placeholderString = placeholder
        nsView.font = .systemFont(ofSize: fontSize, weight: .semibold)
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.onTab = context.coordinator.handleTab
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

        func handleTab(_ value: String) {
            text = value
            onTab()
        }
    }
}

private final class PinNameTextField: NSTextField {
    var onTab: ((String) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Tab) {
            onTab?(stringValue)
            return
        }
        super.keyDown(with: event)
    }
}
