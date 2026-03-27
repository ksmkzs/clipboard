//
//  ClipboardHistoryView.swift
//  ClipboardHistory
//
//  Created by あいちゅ on 2026/02/27.
//
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ClipboardHistoryView: View {
    private static let pinnedRowSpacing: CGFloat = 8
    private static let maxUndoOperations = 200

    private enum SelectionScope {
        case history
        case pinned
    }

    private enum UndoOperation {
        case delete(ClipboardDataManager.ItemSnapshot, beforePins: [ClipboardDataManager.PinStateSnapshot])
        case pinTransition(before: [ClipboardDataManager.PinStateSnapshot], after: [ClipboardDataManager.PinStateSnapshot])
        case textTransform(itemID: UUID, beforeText: String, afterText: String)
    }

    @ObservedObject var appDelegate: AppDelegate
    @Query(sort: \ClipboardItem.timestamp, order: .reverse) private var items: [ClipboardItem]
    
    var dataManager: ClipboardDataManager
    var onCopyRequest: (ClipboardItem) -> Void
    var onPasteRequest: (ClipboardItem) -> Void
    var onOpenSettings: () -> Void
    var onClosePanel: () -> Void
    var onSelectionChanged: (ClipboardItem?) -> Void = { _ in }
    @State private var selectedItemID: UUID?
    @State private var isPinnedAreaVisible = false
    @State private var pendingScrollTargetID: UUID?
    @State private var pendingPinnedScrollTargetID: UUID?
    @State private var toastMessage: String?
    @State private var toastDismissTask: DispatchWorkItem?
    @State private var pasteTargetName = "previous app"
    @State private var pasteTargetArrowSymbol = "arrow.down.left"
    @State private var historyDetailItemID: UUID?
    @State private var pinnedDetailItemID: UUID?
    @State private var selectionScope: SelectionScope = .history
    @State private var draggedPinnedItemID: UUID?
    @State private var pinnedDropTargetIndex: Int?
    @State private var pinnedRowFrames: [UUID: CGRect] = [:]
    @State private var undoStack: [UndoOperation] = []
    @State private var redoStack: [UndoOperation] = []
    @State private var editingItemID: UUID?
    @State private var editorDraftText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            HStack(spacing: 0) {
                mainHistoryList

                if isPinnedAreaVisible {
                    Divider()
                    pinnedSidebar
                }
            }
        }
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                Color.white.opacity(0.12)
            }
        )
        .overlay {
            Rectangle()
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand(perform: {
            handleEscapeAction()
        })
        .onReceive(NotificationCenter.default.publisher(for: .clipboardPanelWillOpen)) { _ in
            isPinnedAreaVisible = false
            historyDetailItemID = nil
            pinnedDetailItemID = nil
            editingItemID = nil
            editorDraftText = ""
            resetSelection(shouldScroll: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardPanelWillOpen)) { notification in
            if let targetName = notification.userInfo?["targetAppName"] as? String, !targetName.isEmpty {
                pasteTargetName = targetName
            } else {
                pasteTargetName = "previous app"
            }
            if let arrowSymbol = notification.userInfo?["targetArrowSymbol"] as? String, !arrowSymbol.isEmpty {
                pasteTargetArrowSymbol = arrowSymbol
            } else {
                pasteTargetArrowSymbol = "arrow.down.left"
            }

        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardPanelWillClose)) { _ in
            commitActiveEditorIfNeeded()
        }
        .background(EventHandlingView(
            isEditorActive: editingItemID != nil,
            togglePinShortcut: appDelegate.settings.togglePinShortcut,
            togglePinnedAreaShortcut: appDelegate.settings.togglePinnedAreaShortcut,
            editTextShortcut: appDelegate.settings.editTextShortcut,
            deleteShortcut: appDelegate.settings.deleteItemShortcut,
            undoShortcut: appDelegate.settings.undoShortcut,
            redoShortcut: appDelegate.settings.redoShortcut,
            joinLinesShortcut: appDelegate.settings.joinLinesShortcut,
            normalizeForCommandShortcut: appDelegate.settings.normalizeForCommandShortcut,
            onLeftArrow: { moveSelectionHorizontally(to: .history) },
            onRightArrow: { moveSelectionHorizontally(to: .pinned) },
            onUpArrow: { moveSelection(by: -1) },
            onDownArrow: { moveSelection(by: 1) },
            onMovePinnedUp: { movePinnedSelection(by: -1) },
            onMovePinnedDown: { movePinnedSelection(by: 1) },
            onEnter: { pasteSelectedItem() },
            onCopyCommand: { copySelectedItem() },
            onClosePanel: { handleEscapeAction() },
            onDelete: { deleteSelectedItem() },
            onTogglePin: { togglePinnedForSelectedItem() },
            onTogglePinnedArea: { togglePinnedAreaFromKeyboard() },
            onToggleEditor: { toggleEditorForSelectedItem() },
            onUndo: { undoLastOperation() },
            onRedo: { redoLastOperation() },
            onJoinLines: { joinSelectedItemLines() },
            onNormalizeForCommand: { normalizeSelectedItemForCommand() },
            onOpenSettings: onOpenSettings
        ))
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.14, green: 0.52, blue: 0.24).opacity(0.96))
                    .clipShape(Capsule())
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .trailing) {
            pinHandle
        }
        .animation(.easeOut(duration: 0.12), value: toastMessage)
    }

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                if isEditingSelectedText {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            editorHeaderPrimaryRow
                            editorHeaderSecondaryRow
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            editorHeaderPrimaryRow
                            editorHeaderSecondaryRow
                        }
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            standardHeaderPrimaryRow
                            standardHeaderSecondaryRow
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            standardHeaderPrimaryRow
                            standardHeaderSecondaryRow
                        }
                    }
                }

                insertTargetHint
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 28)

            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
            .padding(.top, 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.08))
    }

    private var editorHeaderPrimaryRow: some View {
        HStack(spacing: 10) {
            shortcutHint(icon: "xmark.circle", label: "Cancel", key: "Esc")
            shortcutHint(icon: "checkmark.circle", label: "Save", key: HotKeyManager.displayString(for: appDelegate.settings.commitEditShortcut))
            groupedShortcutHint(
                icons: ["arrow.uturn.backward", "arrow.uturn.forward"],
                label: "Undo / Redo",
                key: "⌘Z / ⌘⇧Z"
            )
            groupedShortcutHint(
                icons: ["increase.indent", "decrease.indent"],
                label: "Indent / Outdent",
                key: "\(HotKeyManager.displayString(for: appDelegate.settings.indentShortcut)) / \(HotKeyManager.displayString(for: appDelegate.settings.outdentShortcut))"
            )
        }
    }

    private var editorHeaderSecondaryRow: some View {
        HStack(spacing: 10) {
            groupedShortcutHint(
                icons: ["arrow.up", "arrow.down"],
                label: "Line Up / Down",
                key: "\(HotKeyManager.displayString(for: appDelegate.settings.moveLineUpShortcut)) / \(HotKeyManager.displayString(for: appDelegate.settings.moveLineDownShortcut))"
            )
            shortcutHint(icon: "link", label: "Join", key: HotKeyManager.displayString(for: appDelegate.settings.joinLinesShortcut))
            shortcutHint(icon: "terminal", label: "Normalize", key: HotKeyManager.displayString(for: appDelegate.settings.normalizeForCommandShortcut))
        }
    }

    private var standardHeaderPrimaryRow: some View {
        HStack(spacing: 10) {
            shortcutHint(icon: "xmark", label: "Close", key: "Esc")
            groupedShortcutHint(
                icons: ["arrow.uturn.backward", "arrow.uturn.forward"],
                label: "Undo / Redo",
                key: "\(HotKeyManager.displayString(for: appDelegate.settings.undoShortcut)) / \(HotKeyManager.displayString(for: appDelegate.settings.redoShortcut))"
            )
            shortcutHint(icon: "arrow.down.left", label: "Paste", key: "↩")
            shortcutHint(icon: "doc.on.doc", label: "Copy", key: "⌘C")
        }
    }

    private var standardHeaderSecondaryRow: some View {
        HStack(spacing: 10) {
            shortcutHint(icon: "pencil", label: "Edit", key: HotKeyManager.displayString(for: appDelegate.settings.editTextShortcut))
            shortcutHint(icon: "sidebar.right", label: "Pins", key: "Tab")
            shortcutHint(icon: "star", label: "Pin", key: "P")
            shortcutHint(icon: "trash", label: "Delete", key: "⌫")
            shortcutHint(icon: "link", label: "Join", key: HotKeyManager.displayString(for: appDelegate.settings.joinLinesShortcut))
            shortcutHint(icon: "terminal", label: "Normalize", key: HotKeyManager.displayString(for: appDelegate.settings.normalizeForCommandShortcut))
        }
    }

    private var mainHistoryList: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                Group {
                if historyItems.isEmpty {
                    emptyState(
                        title: "No clipboard history yet",
                        message: "Copy text or images and they will appear here."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(historyItems.enumerated()), id: \.element.id) { index, item in
                                HistoryRowView(
                                    item: item,
                                    isSelected: selectionScope == .history && item.id == selectedItemID,
                                    isCompact: false,
                                    badgeText: "#\(index + 1)",
                                    pinLabel: dataManager.pinLabel(for: item.id),
                                    showPinLabelEditor: false,
                                    showsMetadata: false,
                                    isDetailPresented: historyDetailItemID == item.id,
                                    isEditingText: editingItemID == item.id,
                                    pinnedDropIndicatorPosition: nil,
                                    imageLoader: { fileName in dataManager.loadImage(fileName: fileName) },
                                    onSelect: {
                                        selectItem(item.id, in: .history, shouldScroll: false)
                                    },
                                    onToggleDetail: {
                                        toggleDetail(for: item.id, in: .history)
                                    },
                                    onBeginEditing: {
                                        beginEditing(item.id)
                                    },
                                    onCommitEditor: {
                                        commitEditorIfNeeded(for: item.id)
                                    },
                                    onCancelEditor: {
                                        cancelEditorIfNeeded(for: item.id)
                                    },
                                    commitEditShortcut: appDelegate.settings.commitEditShortcut,
                                    indentShortcut: appDelegate.settings.indentShortcut,
                                    outdentShortcut: appDelegate.settings.outdentShortcut,
                                    moveLineUpShortcut: appDelegate.settings.moveLineUpShortcut,
                                    moveLineDownShortcut: appDelegate.settings.moveLineDownShortcut,
                                    joinLinesShortcut: appDelegate.settings.joinLinesShortcut,
                                    normalizeForCommandShortcut: appDelegate.settings.normalizeForCommandShortcut,
                                    editorText: Binding(
                                        get: { editingItemID == item.id ? editorDraftText : (item.textContent ?? "") },
                                        set: { editorDraftText = $0 }
                                    ),
                                    onRenamePin: { name in
                                        dataManager.setPinLabel(name, for: item.id)
                                    },
                                    onTabFromPinLabel: {},
                                    onTogglePinned: {
                                        togglePinned(item)
                                    },
                                    onDelete: {
                                        deleteItem(item.id)
                                    }
                                )
                                .id(item.id)
                            }
                        }
                        .padding(5)
                    }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                resetSelection(shouldScroll: true)
            }
            .onChange(of: selectedItemID) { _, newID in
                onSelectionChanged(selectedItem())
            }
            .onChange(of: items.count) { _, _ in
                normalizeSelection()
            }
            .onChange(of: pendingScrollTargetID) { _, newID in
                guard let newID else { return }
                proxy.scrollTo(newID)
                pendingScrollTargetID = nil
            }
        }
    }

    private var pinnedSidebar: some View {
        ScrollViewReader { proxy in
            Group {
                if pinnedItems.isEmpty {
                    emptyState(
                        title: "No pinned items",
                        message: "Pin items with the star to keep them easy to reach."
                    )
                    .frame(width: 180)
                } else {
                    GeometryReader { geometry in
                        ScrollView {
                            pinnedRows
                            .padding(.vertical, Self.pinnedRowSpacing)
                            .padding(.horizontal, 5)
                            .coordinateSpace(name: "PinnedListArea")
                            .onPreferenceChange(PinnedRowFramePreferenceKey.self) { pinnedRowFrames = $0 }
                            .onDrop(
                                of: [UTType.text.identifier],
                                delegate: PinnedListDropDelegate(
                                    pinnedItems: pinnedItems,
                                    rowFrames: pinnedRowFrames,
                                    rowSpacing: Self.pinnedRowSpacing,
                                    listWidth: geometry.size.width,
                                    draggedPinnedItemID: $draggedPinnedItemID,
                                    activeTargetIndex: $pinnedDropTargetIndex,
                                    onPerformMove: { movedID, orderedIDs in
                                        commitPinnedReorder(movedID: movedID, orderedIDs: orderedIDs)
                                    }
                                )
                            )
                        }
                        .overlay(alignment: .topLeading) {
                            if let activeTarget = pinnedDropTargets(in: geometry.size).first(where: { $0.index == pinnedDropTargetIndex }) {
                                PinnedDropGapView(isActive: true)
                                    .frame(width: activeTarget.lineWidth)
                                    .position(x: activeTarget.lineMidX, y: activeTarget.lineY)
                            }
                        }
                    }
                    .background(Color(red: 0.98, green: 0.96, blue: 0.76).opacity(0.18))
                    .frame(width: 150)
                }
            }
            .background(Color.clear)
            .onChange(of: pendingPinnedScrollTargetID) { _, newID in
                guard let newID else { return }
                proxy.scrollTo(newID)
                pendingPinnedScrollTargetID = nil
            }
        }
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }

    private var pinnedRows: some View {
        VStack(spacing: Self.pinnedRowSpacing) {
            ForEach(pinnedItems, id: \.id) { item in
                pinnedRow(for: item)
            }
        }
    }

    private func pinnedRow(for item: ClipboardItem) -> some View {
        HistoryRowView(
            item: item,
            isSelected: selectionScope == .pinned && item.id == selectedItemID,
            isCompact: true,
            badgeText: nil,
            pinLabel: dataManager.pinLabel(for: item.id),
            showPinLabelEditor: true,
            showsMetadata: false,
            isDetailPresented: pinnedDetailItemID == item.id,
            isEditingText: editingItemID == item.id,
            pinnedDropIndicatorPosition: nil,
            imageLoader: { fileName in dataManager.loadImage(fileName: fileName) },
            onSelect: {
                selectItem(item.id, in: .pinned, shouldScroll: false)
            },
            onToggleDetail: {
                toggleDetail(for: item.id, in: .pinned)
            },
            onBeginEditing: {
                beginEditing(item.id)
            },
            onCommitEditor: {
                commitEditorIfNeeded(for: item.id)
            },
            onCancelEditor: {
                cancelEditorIfNeeded(for: item.id)
            },
            commitEditShortcut: appDelegate.settings.commitEditShortcut,
            indentShortcut: appDelegate.settings.indentShortcut,
            outdentShortcut: appDelegate.settings.outdentShortcut,
            moveLineUpShortcut: appDelegate.settings.moveLineUpShortcut,
            moveLineDownShortcut: appDelegate.settings.moveLineDownShortcut,
            joinLinesShortcut: appDelegate.settings.joinLinesShortcut,
            normalizeForCommandShortcut: appDelegate.settings.normalizeForCommandShortcut,
            editorText: Binding(
                get: { editingItemID == item.id ? editorDraftText : (item.textContent ?? "") },
                set: { editorDraftText = $0 }
            ),
            onRenamePin: { name in
                dataManager.setPinLabel(name, for: item.id)
            },
            onTabFromPinLabel: {
                togglePinnedAreaFromKeyboard()
            },
            onTogglePinned: {
                togglePinned(item)
            },
            onDelete: {
                deleteItem(item.id)
            }
        )
        .id(item.id)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PinnedRowFramePreferenceKey.self,
                    value: [item.id: proxy.frame(in: .named("PinnedListArea"))]
                )
            }
        )
        .onDrag {
            draggedPinnedItemID = item.id
            return NSItemProvider(object: item.id.uuidString as NSString)
        }
    }

    private var pinHandle: some View {
        Button {
            isPinnedAreaVisible.toggle()
        } label: {
            Image(systemName: isPinnedAreaVisible ? "chevron.right" : "chevron.left")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 44)
                .background(Color.black.opacity(0.18))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 6)
        .help(isPinnedAreaVisible ? "Hide pins" : "Show pins")
    }

    private var insertTargetHint: some View {
        HStack(spacing: 6) {
            Image(systemName: pasteTargetArrowSymbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Paste into \(pasteTargetName)")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.16))
        .clipShape(Capsule())
    }

    private func shortcutHint(icon: String, label: String, key: String) -> some View {
        HStack(spacing: 5) {
            if icon.contains(" / ") {
                HStack(spacing: 2) {
                    ForEach(icon.components(separatedBy: " / "), id: \.self) { symbol in
                        Image(systemName: symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            } else {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary)
            Text(key)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func groupedShortcutHint(icons: [String], label: String, key: String) -> some View {
        HStack(spacing: 5) {
            HStack(spacing: 2) {
                ForEach(icons, id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary)
            Text(key)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var historyItems: [ClipboardItem] {
        items
    }

    private var pinnedItems: [ClipboardItem] {
        items
            .filter(\.isPinned)
            .sorted(by: pinnedComparator)
    }

    private var visibleItems: [ClipboardItem] {
        selectionScope == .pinned ? pinnedItems : historyItems
    }

    private var isEditingSelectedText: Bool {
        guard let editingItemID,
              let selectedItemID,
              editingItemID == selectedItemID,
              selectedItem()?.type == .text else {
            return false
        }
        return true
    }

    private var pinnedComparator: (ClipboardItem, ClipboardItem) -> Bool {
        { lhs, rhs in
            switch (lhs.pinOrder, rhs.pinOrder) {
            case let (left?, right?):
                if left != right {
                    return left < right
                }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }
            return lhs.timestamp > rhs.timestamp
        }
    }

    private func pinnedDropTargets(in availableSize: CGSize) -> [PinnedDropTarget] {
        let orderedFrames = pinnedItems.compactMap { pinnedRowFrames[$0.id] }
        guard !orderedFrames.isEmpty else { return [] }

        let lineWidth = max(0, availableSize.width - 2)
        let lineMidX = availableSize.width * 0.5
        let minimumTriggerHeight: CGFloat = 24

        func makeTarget(index: Int, gapTop: CGFloat, gapBottom: CGFloat) -> PinnedDropTarget {
            let lineY = (gapTop + gapBottom) * 0.5
            let gapHeight = max(0, gapBottom - gapTop)
            let triggerHeight = max(minimumTriggerHeight, gapHeight * 0.8)
            return PinnedDropTarget(
                index: index,
                lineMidX: lineMidX,
                lineWidth: lineWidth,
                lineY: lineY,
                triggerRect: CGRect(
                    x: 0,
                    y: lineY - triggerHeight * 0.5,
                    width: availableSize.width,
                    height: triggerHeight
                )
            )
        }

        var targets: [PinnedDropTarget] = []
        let firstGapTop = max(0, orderedFrames[0].minY - Self.pinnedRowSpacing)
        targets.append(makeTarget(index: 0, gapTop: firstGapTop, gapBottom: orderedFrames[0].minY))

        for index in 1..<orderedFrames.count {
            targets.append(
                makeTarget(
                    index: index,
                    gapTop: orderedFrames[index - 1].maxY,
                    gapBottom: orderedFrames[index].minY
                )
            )
        }

        let lastFrame = orderedFrames[orderedFrames.count - 1]
        targets.append(
            makeTarget(
                index: orderedFrames.count,
                gapTop: lastFrame.maxY,
                gapBottom: lastFrame.maxY + Self.pinnedRowSpacing
            )
        )
        return targets
    }

    private func pushUndo(_ operation: UndoOperation) {
        undoStack.append(operation)
        if undoStack.count > Self.maxUndoOperations {
            undoStack.removeFirst(undoStack.count - Self.maxUndoOperations)
        }
        redoStack.removeAll()
    }

    private func undoLastOperation() {
        guard let operation = undoStack.popLast() else { return }

        switch operation {
        case .delete(let snapshot, let beforePins):
            guard dataManager.restoreDeletedItem(snapshot) else { return }
            _ = dataManager.restorePinState(beforePins)
            selectItem(snapshot.id, in: snapshot.isPinned ? .pinned : .history, shouldScroll: true)
            redoStack.append(operation)
            showToast("Undo delete")
        case .pinTransition(let before, let after):
            guard dataManager.restorePinState(before) else { return }
            redoStack.append(.pinTransition(before: before, after: after))
            normalizeSelection()
            showToast("Undone")
        case .textTransform(let itemID, let beforeText, let afterText):
            guard dataManager.updateTextContent(beforeText, for: itemID) else { return }
            redoStack.append(.textTransform(itemID: itemID, beforeText: beforeText, afterText: afterText))
            selectItem(itemID, in: selectionScopeForItem(itemID), shouldScroll: false)
            showToast("Undone")
        }
    }

    private func redoLastOperation() {
        guard let operation = redoStack.popLast() else { return }

        switch operation {
        case .delete(let snapshot, _):
            guard dataManager.deleteItem(id: snapshot.id) else { return }
            undoStack.append(operation)
            normalizeSelection()
            showToast("Redone")
        case .pinTransition(_, let after):
            let before = dataManager.snapshotPinState()
            guard dataManager.restorePinState(after) else { return }
            undoStack.append(.pinTransition(before: before, after: after))
            normalizeSelection()
            showToast("Redone")
        case .textTransform(let itemID, let beforeText, let afterText):
            guard dataManager.updateTextContent(afterText, for: itemID) else { return }
            undoStack.append(.textTransform(itemID: itemID, beforeText: beforeText, afterText: afterText))
            selectItem(itemID, in: selectionScopeForItem(itemID), shouldScroll: false)
            showToast("Redone")
        }
    }

    private func togglePinned(_ item: ClipboardItem) {
        commitActiveEditorIfNeeded()
        let before = dataManager.snapshotPinState()
        _ = dataManager.setPinned(!item.isPinned, for: item.id)
        let after = dataManager.snapshotPinState()
        pushUndo(.pinTransition(before: before, after: after))
        showToast(item.isPinned ? "Unpinned" : "Pinned")
        if item.isPinned && selectionScope == .pinned {
            selectionScope = .history
        }
        if historyDetailItemID == item.id {
            historyDetailItemID = nil
        }
        if pinnedDetailItemID == item.id {
            pinnedDetailItemID = nil
        }
        normalizeSelection()
    }

    private func togglePinnedForSelectedItem() {
        guard let item = selectedItem() else { return }
        togglePinned(item)
    }

    private func deleteSelectedItem() {
        guard let selectedItemID else { return }
        commitActiveEditorIfNeeded()
        deleteItem(selectedItemID)
    }

    private func deleteItem(_ id: UUID) {
        guard let deletedSnapshot = dataManager.snapshotItem(id: id) else { return }
        let pinStateSnapshot = dataManager.snapshotPinState()
        guard dataManager.deleteItem(id: id) else { return }
        pushUndo(.delete(deletedSnapshot, beforePins: pinStateSnapshot))
        if historyDetailItemID == id {
            historyDetailItemID = nil
        }
        if pinnedDetailItemID == id {
            pinnedDetailItemID = nil
        }
        showToast("Deleted")
        normalizeSelection()
    }

    private func resetSelection(shouldScroll: Bool) {
        selectionScope = .history
        selectItem(historyItems.first?.id ?? (isPinnedAreaVisible ? pinnedItems.first?.id : nil), in: .history, shouldScroll: shouldScroll)
    }

    private func toggleDetail(for id: UUID, in scope: SelectionScope) {
        commitEditorIfNeeded(for: id)
        switch scope {
        case .history:
            if historyDetailItemID == id {
                historyDetailItemID = nil
            } else {
                historyDetailItemID = id
                selectItem(id, in: .history, shouldScroll: false)
            }
        case .pinned:
            if pinnedDetailItemID == id {
                pinnedDetailItemID = nil
            } else {
                pinnedDetailItemID = id
                selectItem(id, in: .pinned, shouldScroll: false)
            }
        }
    }

    private func moveSelection(by offset: Int) {
        guard !visibleItems.isEmpty else { return }

        let currentIndex = visibleItems.firstIndex(where: { $0.id == selectedItemID }) ?? 0
        let nextIndex = min(max(0, currentIndex + offset), visibleItems.count - 1)
        selectItem(visibleItems[nextIndex].id, in: selectionScope, shouldScroll: true)
    }

    private func movePinnedSelection(by offset: Int) {
        guard selectionScope == .pinned, !pinnedItems.isEmpty else { return }
        guard let selectedItemID,
              let currentIndex = pinnedItems.firstIndex(where: { $0.id == selectedItemID }) else {
            return
        }

        let nextIndex = min(max(0, currentIndex + offset), pinnedItems.count - 1)
        guard nextIndex != currentIndex else { return }

        var reorderedIDs = pinnedItems.map(\.id)
        let movedID = reorderedIDs.remove(at: currentIndex)
        reorderedIDs.insert(movedID, at: nextIndex)
        guard dataManager.reorderPinnedItems(reorderedIDs) else { return }
        selectItem(movedID, in: .pinned, shouldScroll: true)
    }

    private func moveSelectionHorizontally(to scope: SelectionScope) {
        switch scope {
        case .history:
            guard selectionScope != .history else { return }
            selectionScope = .history
            selectItem(historyItems.first?.id, in: .history, shouldScroll: true)
        case .pinned:
            guard !pinnedItems.isEmpty else { return }
            if !isPinnedAreaVisible {
                isPinnedAreaVisible = true
            }
            selectionScope = .pinned
            selectItem(selectedPinnedItemID() ?? pinnedItems.first?.id, in: .pinned, shouldScroll: true)
        }
    }

    private func togglePinnedAreaFromKeyboard() {
        if !isPinnedAreaVisible {
            isPinnedAreaVisible = true
            if let pinnedID = pinnedItems.first?.id {
                selectItem(pinnedID, in: .pinned, shouldScroll: true)
            }
            return
        }

        selectionScope = .history
        isPinnedAreaVisible = false
        selectItem(historyItems.first?.id, in: .history, shouldScroll: true)
    }

    private func commitPinnedReorder(movedID: UUID, orderedIDs: [UUID]) {
        let previousState = dataManager.snapshotPinState()
        guard withAnimation(.easeInOut(duration: 0.14), {
            dataManager.reorderPinnedItems(orderedIDs)
        }) else { return }
        let nextState = dataManager.snapshotPinState()
        pushUndo(.pinTransition(before: previousState, after: nextState))
        pinnedDropTargetIndex = nil
        selectItem(movedID, in: .pinned, shouldScroll: false)
        showToast("Pins reordered")
    }

    private func normalizeSelection() {
        guard !visibleItems.isEmpty else {
            selectItem(nil, in: selectionScope, shouldScroll: false)
            return
        }

        if let selectedItemID,
           visibleItems.contains(where: { $0.id == selectedItemID }) {
            return
        }

        if selectionScope == .pinned, let firstPinnedID = pinnedItems.first?.id {
            selectItem(firstPinnedID, in: .pinned, shouldScroll: true)
        } else if let latestHistoryID = historyItems.first?.id {
            selectItem(latestHistoryID, in: .history, shouldScroll: true)
        } else {
            selectItem(visibleItems.first?.id, in: selectionScope, shouldScroll: true)
        }
    }

    private func copySelectedItem() {
        commitActiveEditorIfNeeded()
        guard let selected = selectedItem() else { return }
        onCopyRequest(selected)
        showToast("Copied")
    }

    private func pasteSelectedItem() {
        commitActiveEditorIfNeeded()
        guard let selected = selectedItem() else { return }
        print("ClipboardHistoryView: pasteSelectedItem selected=\(selected.id)")
        showToast("Pasted")
        onPasteRequest(selected)
    }

    private func selectedItem() -> ClipboardItem? {
        guard let selectedItemID else { return nil }
        return visibleItems.first(where: { $0.id == selectedItemID }) ?? items.first(where: { $0.id == selectedItemID })
    }

    private func selectionScopeForItem(_ itemID: UUID) -> SelectionScope {
        pinnedItems.contains(where: { $0.id == itemID }) ? .pinned : .history
    }

    private func selectedPinnedItemID() -> UUID? {
        guard let selectedItemID,
              pinnedItems.contains(where: { $0.id == selectedItemID }) else {
            return nil
        }
        return selectedItemID
    }

    private func selectItem(_ id: UUID?, in scope: SelectionScope, shouldScroll: Bool) {
        if editingItemID != nil, editingItemID != id {
            commitActiveEditorIfNeeded()
        }
        selectionScope = scope
        selectedItemID = id
        if shouldScroll {
            switch scope {
            case .history:
                pendingScrollTargetID = id
                pendingPinnedScrollTargetID = nil
            case .pinned:
                pendingPinnedScrollTargetID = id
                pendingScrollTargetID = nil
            }
        } else {
            pendingScrollTargetID = nil
            pendingPinnedScrollTargetID = nil
        }
    }

    private func showToast(_ message: String) {
        toastDismissTask?.cancel()
        toastMessage = message.hasSuffix("!") ? message : "\(message)!"

        let task = DispatchWorkItem {
            toastMessage = nil
        }
        toastDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: task)
    }

    private func toggleEditorForSelectedItem() {
        guard let item = selectedItem(), item.type == .text else { return }
        if editingItemID == item.id {
            commitEditorIfNeeded(for: item.id)
        } else {
            beginEditing(item.id)
        }
    }

    private func applyTextTransformToSelectedItem(actionName: String, transform: (String) -> String) {
        guard editingItemID == nil,
              let item = selectedItem(),
              item.type == .text,
              let beforeText = item.textContent else {
            return
        }

        let afterText = transform(beforeText)
        guard afterText != beforeText else { return }
        guard dataManager.updateTextContent(afterText, for: item.id) else { return }
        pushUndo(.textTransform(itemID: item.id, beforeText: beforeText, afterText: afterText))
        selectItem(item.id, in: selectionScopeForItem(item.id), shouldScroll: false)
        showToast(actionName)
    }

    private func joinSelectedItemLines() {
        applyTextTransformToSelectedItem(actionName: "Joined") { text in
            text.replacingOccurrences(
                of: #"\s*\n\s*"#,
                with: " ",
                options: .regularExpression
            )
        }
    }

    private func normalizeSelectedItemForCommand() {
        applyTextTransformToSelectedItem(actionName: "Normalized") { text in
            text
                .replacingOccurrences(of: #"\s*\n\s*"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func beginEditing(_ itemID: UUID) {
        guard let item = items.first(where: { $0.id == itemID }),
              item.type == .text else { return }
        historyDetailItemID = nil
        pinnedDetailItemID = nil
        editingItemID = itemID
        editorDraftText = item.textContent ?? ""
        selectItem(itemID, in: pinnedItems.contains(where: { $0.id == itemID }) ? .pinned : .history, shouldScroll: false)
    }

    private func commitActiveEditorIfNeeded() {
        guard let editingItemID else { return }
        commitEditorIfNeeded(for: editingItemID)
    }

    private func commitEditorIfNeeded(for itemID: UUID) {
        guard editingItemID == itemID else { return }
        _ = dataManager.updateTextContent(editorDraftText, for: itemID)
        editingItemID = nil
        editorDraftText = ""
        showToast("Saved")
    }

    private func cancelEditorIfNeeded(for itemID: UUID) {
        guard editingItemID == itemID else { return }
        editingItemID = nil
        editorDraftText = ""
        showToast("Canceled")
    }

    private func handleEscapeAction() {
        if editingItemID != nil {
            cancelEditorIfNeeded(for: editingItemID!)
            return
        }
        onClosePanel()
    }

}

private struct PinnedDropGapView: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            Color.clear
            if isActive {
                HStack(spacing: 6) {
                    Text(">")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                    Rectangle()
                        .fill(Color.primary.opacity(0.42))
                        .frame(height: 1)
                    Text("<")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 16)
        .contentShape(Rectangle())
    }
}

private struct PinnedRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct PinnedDropTarget: Equatable {
    let index: Int
    let lineMidX: CGFloat
    let lineWidth: CGFloat
    let lineY: CGFloat
    let triggerRect: CGRect
}

private struct PinnedListDropDelegate: DropDelegate {
    let pinnedItems: [ClipboardItem]
    let rowFrames: [UUID: CGRect]
    let rowSpacing: CGFloat
    let listWidth: CGFloat
    @Binding var draggedPinnedItemID: UUID?
    @Binding var activeTargetIndex: Int?
    let onPerformMove: (UUID, [UUID]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggedPinnedItemID != nil
    }

    func dropEntered(info: DropInfo) {
        activeTargetIndex = targetIndex(for: info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        activeTargetIndex = targetIndex(for: info.location)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggedPinnedItemID = nil
            activeTargetIndex = nil
        }
        guard let draggedPinnedItemID,
              let fromIndex = pinnedItems.firstIndex(where: { $0.id == draggedPinnedItemID }),
              let rawDestination = targetIndex(for: info.location) else {
            return false
        }

        var orderedIDs = pinnedItems.map(\.id)
        let movedID = orderedIDs.remove(at: fromIndex)

        var destination = rawDestination
        if fromIndex < rawDestination {
            destination -= 1
        }
        destination = max(0, min(destination, orderedIDs.count))
        orderedIDs.insert(movedID, at: destination)
        onPerformMove(movedID, orderedIDs)
        return true
    }

    func dropExited(info: DropInfo) {
        activeTargetIndex = nil
        if !info.hasItemsConforming(to: [UTType.text.identifier]) {
            draggedPinnedItemID = nil
        }
    }

    private func targetIndex(for location: CGPoint) -> Int? {
        let orderedFrames = pinnedItems.compactMap { rowFrames[$0.id] }
        guard !orderedFrames.isEmpty else { return nil }

        return dropTargets(for: orderedFrames).first(where: { $0.triggerRect.contains(location) })?.index
    }

    private func dropTargets(for orderedFrames: [CGRect]) -> [PinnedDropTarget] {
        let lineWidth = max(0, listWidth - 2)
        let lineMidX = listWidth * 0.5
        let minimumTriggerHeight: CGFloat = 30

        func makeTarget(index: Int, gapTop: CGFloat, gapBottom: CGFloat) -> PinnedDropTarget {
            let lineY = (gapTop + gapBottom) * 0.5
            let gapHeight = max(0, gapBottom - gapTop)
            let triggerHeight = max(minimumTriggerHeight, gapHeight)
            return PinnedDropTarget(
                index: index,
                lineMidX: lineMidX,
                lineWidth: lineWidth,
                lineY: lineY,
                triggerRect: CGRect(
                    x: 0,
                    y: lineY - triggerHeight * 0.5,
                    width: listWidth,
                    height: triggerHeight
                )
            )
        }

        var targets: [PinnedDropTarget] = []
        let firstGapTop = max(0, orderedFrames[0].minY - rowSpacing)
        targets.append(makeTarget(index: 0, gapTop: firstGapTop, gapBottom: orderedFrames[0].minY))

        for index in 1..<orderedFrames.count {
            targets.append(
                makeTarget(
                    index: index,
                    gapTop: orderedFrames[index - 1].maxY,
                    gapBottom: orderedFrames[index].minY
                )
            )
        }

        let lastFrame = orderedFrames[orderedFrames.count - 1]
        targets.append(
            makeTarget(
                index: orderedFrames.count,
                gapTop: lastFrame.maxY,
                gapBottom: lastFrame.maxY + rowSpacing
            )
        )
        return targets
    }
}

extension Notification.Name {
    static let clipboardPanelWillOpen = Notification.Name("clipboardPanelWillOpen")
    static let clipboardPanelWillClose = Notification.Name("clipboardPanelWillClose")
}
