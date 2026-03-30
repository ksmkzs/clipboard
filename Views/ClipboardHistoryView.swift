//
//  ClipboardHistoryView.swift
//  ClipboardHistory
//
//  Created by あいちゅ on 2026/02/27.
//
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardHistoryView: View {
    private static let pinnedRowSpacing: CGFloat = 8
    private static let maxUndoOperations = 200
    private static let toastDisplayDuration: TimeInterval = 1.2
    private static let maxVisibleToasts = 3
    private static let maxInlineTextBytes = HistoryRowView.maxInlineTextBytes

    private enum SelectionScope {
        case history
        case pinned
    }

    private enum UndoOperation {
        case delete(ClipboardDataManager.ItemSnapshot, beforePins: [ClipboardDataManager.PinStateSnapshot])
        case pinTransition(before: [ClipboardDataManager.PinStateSnapshot], after: [ClipboardDataManager.PinStateSnapshot])
        case textTransform(itemID: UUID, beforeText: String, afterText: String)
    }

    private enum ToastStyle: Equatable {
        case success
        case copy
        case joinedCopy
        case normalizedCopy
        case warning
        case danger

        var backgroundColor: Color {
            switch self {
            case .success:
                return Color(red: 0.14, green: 0.52, blue: 0.24).opacity(0.96)
            case .copy:
                return Color(red: 0.77, green: 0.60, blue: 0.14).opacity(0.97)
            case .joinedCopy:
                return Color(red: 0.76, green: 0.44, blue: 0.13).opacity(0.97)
            case .normalizedCopy:
                return Color(red: 0.19, green: 0.49, blue: 0.64).opacity(0.97)
            case .warning:
                return Color(red: 0.72, green: 0.45, blue: 0.12).opacity(0.97)
            case .danger:
                return Color(red: 0.64, green: 0.18, blue: 0.20).opacity(0.97)
            }
        }
    }

    private struct ToastEntry: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let style: ToastStyle
    }

    @ObservedObject var appDelegate: AppDelegate
    var dataManager: ClipboardDataManager
    var onCopyRequest: (ClipboardItem) -> Void
    var onCopyTextRequest: (String, String) -> Void
    var onPasteRequest: (ClipboardItem) -> Void
    var onOpenSettings: () -> Void
    var onClosePanel: () -> Void
    var onSelectionChanged: (ClipboardItem?) -> Void = { _ in }
    @State private var items: [ClipboardItem] = []
    @State private var selectedItemID: UUID?
    @State private var focusedItemID: UUID?
    @State private var isPinnedAreaVisible = false
    @State private var pendingScrollTargetID: UUID?
    @State private var pendingPinnedScrollTargetID: UUID?
    @State private var toastEntries: [ToastEntry] = []
    @State private var toastDismissTasks: [UUID: DispatchWorkItem] = [:]
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
    @State private var isMarkdownPreviewVisible = false
    @State private var cachedHistoryItems: [ClipboardItem] = []
    @State private var cachedPinnedItems: [ClipboardItem] = []
    @State private var cachedAllItemsByID: [UUID: ClipboardItem] = [:]
    @State private var cachedPinnedItemIDs: Set<UUID> = []
    @State private var cachedHistoryItemIndexByID: [UUID: Int] = [:]
    @State private var cachedPinnedItemIndexByID: [UUID: Int] = [:]

    private var interfaceZoomScale: CGFloat {
        CGFloat(appDelegate.settings.clampedInterfaceZoomScale)
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        value * interfaceZoomScale
    }

    private var theme: InterfaceThemeDefinition {
        appDelegate.settings.interfaceTheme
    }
    
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
                theme.panelOverlay
            }
        )
        .overlay {
            Rectangle()
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(nil, value: appDelegate.settings.interfaceThemePreset.rawValue)
        .onExitCommand(perform: {
            handleEscapeAction()
        })
        .onReceive(NotificationCenter.default.publisher(for: .clipboardPanelWillOpen)) { _ in
            isPinnedAreaVisible = false
            historyDetailItemID = nil
            pinnedDetailItemID = nil
            editingItemID = nil
            editorDraftText = ""
            isMarkdownPreviewVisible = false
            refreshItemsFromStore()
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
        .onReceive(NotificationCenter.default.publisher(for: .clipboardItemsDidChange)) { _ in
            refreshItemsFromStore()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardManualNoteCreated)) { notification in
            guard let itemID = notification.userInfo?["itemID"] as? UUID else { return }
            refreshItemsFromStore()
            isPinnedAreaVisible = false
            selectionScope = .history
            commitSelection(itemID, in: .history, shouldScroll: true)
            showToast("New note")
        }
        .background(EventHandlingView(
            isEditorActive: editingItemID != nil,
            togglePinShortcut: appDelegate.settings.togglePinShortcut,
            togglePinnedAreaShortcut: appDelegate.settings.togglePinnedAreaShortcut,
            newNoteShortcut: appDelegate.settings.newNoteShortcut,
            editTextShortcut: appDelegate.settings.editTextShortcut,
            deleteShortcut: appDelegate.settings.deleteItemShortcut,
            undoShortcut: appDelegate.settings.undoShortcut,
            redoShortcut: appDelegate.settings.redoShortcut,
            copyJoinedShortcut: appDelegate.settings.copyJoinedShortcut,
            copyNormalizedShortcut: appDelegate.settings.copyNormalizedShortcut,
            joinLinesShortcut: appDelegate.settings.joinLinesShortcut,
            normalizeForCommandShortcut: appDelegate.settings.normalizeForCommandShortcut,
            onLeftArrow: { moveSelectionHorizontally(to: .history) },
            onRightArrow: { moveSelectionHorizontally(to: .pinned) },
            onUpArrow: { moveSelection(by: -1) },
            onDownArrow: { moveSelection(by: 1) },
            onMovePinnedUp: { movePinnedSelection(by: -1) },
            onMovePinnedDown: { movePinnedSelection(by: 1) },
            onEnter: { commitFocusedSelection() },
            onPasteSelection: { pasteSelectedItem() },
            onCopyCommand: { copySelectedItem() },
            onCopyJoinedCommand: { copyJoinedSelectedItem() },
            onCopyNormalizedCommand: { copyNormalizedSelectedItem() },
            onClosePanel: { handleEscapeAction() },
            onDelete: { deleteSelectedItem() },
            onTogglePin: { togglePinnedForSelectedItem() },
            onTogglePinnedArea: { togglePinnedAreaFromKeyboard() },
            onCreateNewNote: { appDelegate.createNewNoteFromAnyState() },
            onToggleEditor: { toggleEditorForSelectedItem() },
            onUndo: { undoLastOperation() },
            onRedo: { redoLastOperation() },
            onJoinLines: { joinSelectedItemLines() },
            onNormalizeForCommand: { normalizeSelectedItemForCommand() },
            onToggleHelp: { toggleHelpOverlay() },
            onOpenSettings: onOpenSettings,
            onZoomIn: { appDelegate.increaseInterfaceZoom() },
            onZoomOut: { appDelegate.decreaseInterfaceZoom() },
            onResetZoom: { appDelegate.resetInterfaceZoom() }
        ))
        .overlay(alignment: .bottom) {
            if !toastEntries.isEmpty {
                VStack(spacing: 6) {
                    ForEach(toastEntries.suffix(Self.maxVisibleToasts)) { toast in
                        Text(toast.message)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(toast.style.backgroundColor)
                            .clipShape(Capsule())
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .overlay(alignment: .trailing) {
            pinHandle
        }
        .overlay(alignment: .bottom) {
            WindowResizeCue(text: "↕")
                .padding(.bottom, 6)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .trailing) {
            WindowResizeCue(text: "↔")
                .padding(.trailing, 28)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            WindowResizeCue(text: "⤡")
                .padding(.trailing, 8)
                .padding(.bottom, 6)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.14), value: toastEntries)
        .onAppear {
            refreshItemsFromStore()
        }
        .onChange(of: selectedItemID) { _, _ in
            onSelectionChanged(selectedItem())
        }
    }

    private var header: some View {
        ClipboardHeaderSection(
            settings: appDelegate.settings,
            zoomScale: interfaceZoomScale,
            isEditingSelectedText: isEditingSelectedText,
            pasteTargetName: pasteTargetName,
            pasteTargetArrowSymbol: pasteTargetArrowSymbol,
            onToggleHelp: { toggleHelpOverlay() },
            onOpenSettings: onOpenSettings
        )
    }

    private var mainHistoryList: some View {
        HistoryListSection(
            historyItems: historyItems,
            pinLabelsByID: pinLabelsByID,
            selectedItemID: selectedItemID,
            focusedItemID: focusedItemID,
            isHistoryFocus: selectionScope == .history,
            historyDetailItemID: historyDetailItemID,
            editingItemID: editingItemID,
            settings: appDelegate.settings,
            theme: theme,
            interfaceZoomScale: interfaceZoomScale,
            editorDraftText: Binding(get: { editorDraftText }, set: { editorDraftText = $0 }),
            isMarkdownPreviewVisible: isMarkdownPreviewVisible,
            pendingScrollTargetID: $pendingScrollTargetID,
            imageLoader: { fileName in dataManager.loadImage(fileName: fileName) },
            onSelect: { itemID in
                commitSelection(itemID, in: .history, shouldScroll: false)
            },
            onToggleDetail: { itemID in
                toggleDetail(for: itemID, in: .history)
            },
            onBeginEditing: beginEditing,
            onCommitEditor: commitEditorIfNeeded,
            onCancelEditor: cancelEditorIfNeeded,
            onToggleMarkdownPreview: toggleMarkdownPreview,
            onCopyRaw: onCopyRequest,
            onToggleHelp: toggleHelpOverlay,
            onZoomIn: { appDelegate.increaseInterfaceZoom() },
            onZoomOut: { appDelegate.decreaseInterfaceZoom() },
            onResetZoom: { appDelegate.resetInterfaceZoom() },
            onRenamePin: { itemID, name in
                dataManager.setPinLabel(name, for: itemID)
            },
            onTogglePinned: { item in
                togglePinned(item)
            },
            onDelete: deleteItem,
            onFirstAppear: {
                resetSelection(shouldScroll: true)
            }
        )
    }

    private var pinnedSidebar: some View {
        PinnedSidebarSection(
            pinnedItems: pinnedItems,
            pinLabelsByID: pinLabelsByID,
            selectedItemID: selectedItemID,
            focusedItemID: focusedItemID,
            isPinnedFocus: selectionScope == .pinned,
            pinnedDetailItemID: pinnedDetailItemID,
            editingItemID: editingItemID,
            settings: appDelegate.settings,
            theme: theme,
            interfaceZoomScale: interfaceZoomScale,
            editorDraftText: Binding(get: { editorDraftText }, set: { editorDraftText = $0 }),
            isMarkdownPreviewVisible: isMarkdownPreviewVisible,
            draggedPinnedItemID: $draggedPinnedItemID,
            pinnedDropTargetIndex: $pinnedDropTargetIndex,
            pinnedRowFrames: $pinnedRowFrames,
            pendingPinnedScrollTargetID: $pendingPinnedScrollTargetID,
            imageLoader: { fileName in dataManager.loadImage(fileName: fileName) },
            onSelect: { itemID in
                commitSelection(itemID, in: .pinned, shouldScroll: false)
            },
            onToggleDetail: { itemID in
                toggleDetail(for: itemID, in: .pinned)
            },
            onBeginEditing: beginEditing,
            onCommitEditor: commitEditorIfNeeded,
            onCancelEditor: cancelEditorIfNeeded,
            onToggleMarkdownPreview: toggleMarkdownPreview,
            onCopyRaw: onCopyRequest,
            onToggleHelp: toggleHelpOverlay,
            onZoomIn: { appDelegate.increaseInterfaceZoom() },
            onZoomOut: { appDelegate.decreaseInterfaceZoom() },
            onResetZoom: { appDelegate.resetInterfaceZoom() },
            onRenamePin: { itemID, name in
                dataManager.setPinLabel(name, for: itemID)
            },
            onTabFromPinLabel: {
                togglePinnedAreaFromKeyboard()
            },
            onTogglePinned: { item in
                togglePinned(item)
            },
            onDelete: deleteItem,
            makeDropTargets: pinnedDropTargets,
            onPerformMove: commitPinnedReorder
        )
    }

    private var pinHandle: some View {
        Button {
            isPinnedAreaVisible.toggle()
        } label: {
            Image(systemName: isPinnedAreaVisible ? "chevron.right" : "chevron.left")
                .font(.system(size: scaled(11), weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: scaled(16), height: scaled(44))
                .background(Color.black.opacity(0.18))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.trailing, scaled(6))
        .help(isPinnedAreaVisible ? "Hide pins" : "Show pins")
    }


    private var historyItems: [ClipboardItem] {
        cachedHistoryItems
    }

    private var pinnedItems: [ClipboardItem] {
        cachedPinnedItems
    }

    private var totalItemCount: Int {
        items.count
    }

    private var allItems: [ClipboardItem] {
        items
    }

    private var allItemsByID: [UUID: ClipboardItem] {
        cachedAllItemsByID
    }

    private var pinLabelsByID: [UUID: String] {
        dataManager.pinLabelsByID()
    }

    private var pinnedItemIDs: Set<UUID> {
        cachedPinnedItemIDs
    }

    private var visibleItemIDs: Set<UUID> {
        Set(visibleItems.map(\.id))
    }

    private var historyItemIndexByID: [UUID: Int] {
        cachedHistoryItemIndexByID
    }

    private var pinnedItemIndexByID: [UUID: Int] {
        cachedPinnedItemIndexByID
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

    private func pinnedDropTargets(in availableSize: CGSize) -> [PinnedDropTarget] {
        let orderedFrames = pinnedItems.compactMap { pinnedRowFrames[$0.id] }
        return PinnedDropTarget.makeTargets(
            orderedFrames: orderedFrames,
            rowSpacing: Self.pinnedRowSpacing,
            listWidth: availableSize.width,
            minimumTriggerHeight: 24,
            triggerHeightScale: 0.8
        )
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
            refreshItemsFromStore()
            commitSelection(snapshot.id, in: snapshot.isPinned ? .pinned : .history, shouldScroll: true)
            redoStack.append(operation)
            showToast("Undo delete")
        case .pinTransition(let before, let after):
            guard dataManager.restorePinState(before) else { return }
            refreshItemsFromStore()
            redoStack.append(.pinTransition(before: before, after: after))
            normalizeSelection()
            showToast("Undone")
        case .textTransform(let itemID, let beforeText, let afterText):
            guard dataManager.updateTextContent(beforeText, for: itemID) else { return }
            refreshItemsFromStore()
            redoStack.append(.textTransform(itemID: itemID, beforeText: beforeText, afterText: afterText))
            commitSelection(itemID, in: selectionScopeForItem(itemID), shouldScroll: false)
            showToast("Undone")
        }
    }

    private func redoLastOperation() {
        guard let operation = redoStack.popLast() else { return }

        switch operation {
        case .delete(let snapshot, _):
            guard dataManager.deleteItem(id: snapshot.id) else { return }
            refreshItemsFromStore()
            undoStack.append(operation)
            normalizeSelection()
            showToast("Redone")
        case .pinTransition(_, let after):
            let before = currentPinStateSnapshot()
            guard dataManager.restorePinState(after) else { return }
            refreshItemsFromStore()
            undoStack.append(.pinTransition(before: before, after: after))
            normalizeSelection()
            showToast("Redone")
        case .textTransform(let itemID, let beforeText, let afterText):
            guard dataManager.updateTextContent(afterText, for: itemID) else { return }
            refreshItemsFromStore()
            undoStack.append(.textTransform(itemID: itemID, beforeText: beforeText, afterText: afterText))
            commitSelection(itemID, in: selectionScopeForItem(itemID), shouldScroll: false)
            showToast("Redone")
        }
    }

    private func togglePinned(_ item: ClipboardItem) {
        commitActiveEditorIfNeeded()
        let before = currentPinStateSnapshot()
        _ = dataManager.setPinned(!item.isPinned, for: item.id)
        refreshItemsFromStore()
        let after = currentPinStateSnapshot()
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
        let pinStateSnapshot = currentPinStateSnapshot()
        guard dataManager.deleteItem(id: id) else { return }
        refreshItemsFromStore()
        pushUndo(.delete(deletedSnapshot, beforePins: pinStateSnapshot))
        if historyDetailItemID == id {
            historyDetailItemID = nil
        }
        if pinnedDetailItemID == id {
            pinnedDetailItemID = nil
        }
        showToast("Deleted", style: .danger)
        normalizeSelection()
    }

    private func resetSelection(shouldScroll: Bool) {
        selectionScope = .history
        let initialID = historyItems.first?.id ?? (isPinnedAreaVisible ? pinnedItems.first?.id : nil)
        commitSelection(initialID, in: .history, shouldScroll: shouldScroll)
    }

    private func toggleDetail(for id: UUID, in scope: SelectionScope) {
        commitEditorIfNeeded(for: id)
        switch scope {
        case .history:
            if historyDetailItemID == id {
                historyDetailItemID = nil
            } else {
                historyDetailItemID = id
                commitSelection(id, in: .history, shouldScroll: false)
            }
        case .pinned:
            if pinnedDetailItemID == id {
                pinnedDetailItemID = nil
            } else {
                pinnedDetailItemID = id
                commitSelection(id, in: .pinned, shouldScroll: false)
            }
        }
    }

    private func moveSelection(by offset: Int) {
        guard !visibleItems.isEmpty else { return }
        let currentIndex: Int
        switch selectionScope {
        case .history:
            currentIndex = focusedItemID.flatMap { historyItemIndexByID[$0] } ?? 0
        case .pinned:
            currentIndex = focusedItemID.flatMap { pinnedItemIndexByID[$0] } ?? 0
        }
        let nextIndex = min(max(0, currentIndex + offset), visibleItems.count - 1)
        focusItem(visibleItems[nextIndex].id, in: selectionScope, shouldScroll: true)
    }

    private func movePinnedSelection(by offset: Int) {
        guard selectionScope == .pinned, !pinnedItems.isEmpty else { return }
        guard let focusedItemID,
              let currentIndex = pinnedItemIndexByID[focusedItemID] else {
            return
        }

        let nextIndex = min(max(0, currentIndex + offset), pinnedItems.count - 1)
        guard nextIndex != currentIndex else { return }

        var reorderedIDs = pinnedItems.map(\.id)
        let movedID = reorderedIDs.remove(at: currentIndex)
        reorderedIDs.insert(movedID, at: nextIndex)
        guard dataManager.reorderPinnedItems(reorderedIDs) else { return }
        focusItem(movedID, in: .pinned, shouldScroll: true)
    }

    private func moveSelectionHorizontally(to scope: SelectionScope) {
        switch scope {
        case .history:
            guard selectionScope != .history else { return }
            selectionScope = .history
            focusItem(historyItems.first?.id, in: .history, shouldScroll: true)
        case .pinned:
            guard !pinnedItems.isEmpty else { return }
            if !isPinnedAreaVisible {
                isPinnedAreaVisible = true
            }
            selectionScope = .pinned
            focusItem(focusedPinnedItemID() ?? selectedPinnedItemID() ?? pinnedItems.first?.id, in: .pinned, shouldScroll: true)
        }
    }

    private func togglePinnedAreaFromKeyboard() {
        if !isPinnedAreaVisible {
            isPinnedAreaVisible = true
            if let pinnedID = pinnedItems.first?.id {
                focusItem(pinnedID, in: .pinned, shouldScroll: true)
            }
            return
        }

        selectionScope = .history
        isPinnedAreaVisible = false
        focusItem(historyItems.first?.id, in: .history, shouldScroll: true)
        if let selectedItemID, pinnedItemIDs.contains(selectedItemID) {
            commitSelection(historyItems.first?.id, in: .history, shouldScroll: true)
        }
    }

    private func commitPinnedReorder(movedID: UUID, orderedIDs: [UUID]) {
        let previousState = currentPinStateSnapshot()
        guard withAnimation(.easeInOut(duration: 0.14), {
            dataManager.reorderPinnedItems(orderedIDs)
        }) else { return }
        refreshItemsFromStore()
        let nextState = currentPinStateSnapshot()
        pushUndo(.pinTransition(before: previousState, after: nextState))
        pinnedDropTargetIndex = nil
        commitSelection(movedID, in: .pinned, shouldScroll: false)
        showToast("Pins reordered")
    }

    private func normalizeSelection() {
        guard !visibleItems.isEmpty else {
            focusItem(nil, in: selectionScope, shouldScroll: false)
            selectedItemID = nil
            return
        }

        if let focusedItemID,
           visibleItemIDs.contains(focusedItemID) {
            // keep focus
        } else if selectionScope == .pinned, let firstPinnedID = pinnedItems.first?.id {
            focusItem(firstPinnedID, in: .pinned, shouldScroll: true)
        } else if let latestHistoryID = historyItems.first?.id {
            focusItem(latestHistoryID, in: .history, shouldScroll: true)
        } else {
            focusItem(visibleItems.first?.id, in: selectionScope, shouldScroll: true)
        }

        if let selectedItemID,
           allItemsByID[selectedItemID] != nil,
           !(selectionScopeForItem(selectedItemID) == .pinned && !isPinnedAreaVisible) {
            return
        }

        commitFocusedSelection()
    }

    private func copySelectedItem() {
        commitActiveEditorIfNeeded()
        guard let selected = selectedItem() else { return }
        onCopyRequest(selected)
        showToast("Copied", style: .copy)
    }

    private func copyJoinedSelectedItem() {
        copyTransformedSelectedText(actionName: "Joined") { text in
            joinLinesText(text)
        }
    }

    private func copyNormalizedSelectedItem() {
        copyTransformedSelectedText(actionName: "Normalized") { text in
            normalizeCommandText(text)
        }
    }

    private func pasteSelectedItem() {
        commitActiveEditorIfNeeded()
        guard let selected = selectedItem() else { return }
        showToast("Pasted", style: .success)
        onPasteRequest(selected)
    }

    private func selectedItem() -> ClipboardItem? {
        guard let selectedItemID else { return nil }
        return allItemsByID[selectedItemID]
    }

    private func focusedItem() -> ClipboardItem? {
        guard let focusedItemID else { return nil }
        return allItemsByID[focusedItemID]
    }

    private func rebuildItemCaches(using allItems: [ClipboardItem]) {
        let pinnedItems = allItems
            .filter(\.isPinned)
            .sorted(by: pinnedComparator)
        cachedHistoryItems = allItems
        cachedPinnedItems = pinnedItems
        cachedAllItemsByID = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        cachedPinnedItemIDs = Set(pinnedItems.map(\.id))
        cachedHistoryItemIndexByID = Dictionary(uniqueKeysWithValues: allItems.enumerated().map { ($0.element.id, $0.offset) })
        cachedPinnedItemIndexByID = Dictionary(uniqueKeysWithValues: pinnedItems.enumerated().map { ($0.element.id, $0.offset) })
        normalizeSelection()
    }

    private func refreshItemsFromStore() {
        let fetchedItems = dataManager.allItems()
        items = fetchedItems
        rebuildItemCaches(using: fetchedItems)
    }

    private func currentPinStateSnapshot() -> [ClipboardDataManager.PinStateSnapshot] {
        items.map {
            ClipboardDataManager.PinStateSnapshot(
                itemID: $0.id,
                isPinned: $0.isPinned,
                pinOrder: $0.pinOrder
            )
        }
    }

    private func selectionScopeForItem(_ itemID: UUID) -> SelectionScope {
        pinnedItemIDs.contains(itemID) ? .pinned : .history
    }

    private func selectedPinnedItemID() -> UUID? {
        guard let selectedItemID,
              pinnedItemIDs.contains(selectedItemID) else {
            return nil
        }
        return selectedItemID
    }

    private func focusedPinnedItemID() -> UUID? {
        guard let focusedItemID,
              pinnedItemIDs.contains(focusedItemID) else {
            return nil
        }
        return focusedItemID
    }

    private func focusItem(_ id: UUID?, in scope: SelectionScope, shouldScroll: Bool) {
        selectionScope = scope
        focusedItemID = id
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

    private func commitSelection(_ id: UUID?, in scope: SelectionScope, shouldScroll: Bool) {
        if editingItemID != nil, editingItemID != id {
            commitActiveEditorIfNeeded()
        }
        selectedItemID = id
        focusItem(id, in: scope, shouldScroll: shouldScroll)
    }

    private func commitFocusedSelection() {
        guard let focusedItemID,
              let item = allItemsByID[focusedItemID] else {
            normalizeSelection()
            return
        }
        commitSelection(item.id, in: selectionScopeForItem(item.id), shouldScroll: false)
    }

    private func showToast(_ message: String, style: ToastStyle = .success) {
        let toast = ToastEntry(
            message: message.hasSuffix("!") ? message : "\(message)!",
            style: style
        )
        toastEntries.append(toast)
        if toastEntries.count > Self.maxVisibleToasts + 2 {
            let overflow = toastEntries.count - (Self.maxVisibleToasts + 2)
            let removed = toastEntries.prefix(overflow)
            for toast in removed {
                toastDismissTasks[toast.id]?.cancel()
                toastDismissTasks.removeValue(forKey: toast.id)
            }
            toastEntries.removeFirst(overflow)
        }

        let task = DispatchWorkItem {
            toastEntries.removeAll { $0.id == toast.id }
            toastDismissTasks.removeValue(forKey: toast.id)
        }
        toastDismissTasks[toast.id] = task
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.toastDisplayDuration, execute: task)
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
              !item.isLargeText,
              let beforeText = dataManager.resolvedText(for: item) else {
            return
        }

        let afterText = transform(beforeText)
        guard afterText != beforeText else { return }
        guard dataManager.updateTextContent(afterText, for: item.id) else { return }
        refreshItemsFromStore()
        pushUndo(.textTransform(itemID: item.id, beforeText: beforeText, afterText: afterText))
        commitSelection(item.id, in: selectionScopeForItem(item.id), shouldScroll: false)
        showToast(actionName)
    }

    private func copyTransformedSelectedText(actionName: String, transform: (String) -> String) {
        commitActiveEditorIfNeeded()
        guard let item = selectedItem(),
              item.type == .text,
              let beforeText = dataManager.resolvedText(for: item) else {
            return
        }

        onCopyTextRequest(transform(beforeText), actionName)
        let style: ToastStyle
        switch actionName {
        case "Joined", "Copied joined text":
            style = .joinedCopy
        case "Normalized", "Copied normalized text":
            style = .normalizedCopy
        default:
            style = .copy
        }
        showToast(actionName, style: style)
    }

    private func joinSelectedItemLines() {
        applyTextTransformToSelectedItem(actionName: "Joined") { text in
            joinLinesText(text)
        }
    }

    private func normalizeSelectedItemForCommand() {
        applyTextTransformToSelectedItem(actionName: "Normalized") { text in
            normalizeCommandText(text)
        }
    }

    private func beginEditing(_ itemID: UUID) {
        guard let item = allItemsByID[itemID],
              item.type == .text else { return }
        if item.isLargeText || item.textByteCount > Self.maxInlineTextBytes {
            showToast("Editing disabled for large item", style: .warning)
            return
        }
        historyDetailItemID = nil
        pinnedDetailItemID = nil
        editingItemID = itemID
        editorDraftText = dataManager.resolvedText(for: item) ?? ""
        isMarkdownPreviewVisible = false
        commitSelection(itemID, in: pinnedItemIDs.contains(itemID) ? .pinned : .history, shouldScroll: false)
    }

    private func commitActiveEditorIfNeeded() {
        guard let editingItemID else { return }
        commitEditorIfNeeded(for: editingItemID)
    }

    private func commitEditorIfNeeded(for itemID: UUID) {
        guard editingItemID == itemID else { return }
        _ = dataManager.updateTextContent(editorDraftText, for: itemID)
        refreshItemsFromStore()
        editingItemID = nil
        editorDraftText = ""
        isMarkdownPreviewVisible = false
        showToast("Saved", style: .success)
    }

    private func cancelEditorIfNeeded(for itemID: UUID) {
        guard editingItemID == itemID else { return }
        editingItemID = nil
        editorDraftText = ""
        isMarkdownPreviewVisible = false
        showToast("Canceled", style: .danger)
    }

    private func toggleMarkdownPreview() {
        guard editingItemID != nil else { return }
        isMarkdownPreviewVisible.toggle()
    }

    private func handleEscapeAction() {
        if editingItemID != nil {
            cancelEditorIfNeeded(for: editingItemID!)
            return
        }
        onClosePanel()
    }

    private func toggleHelpOverlay() {
        NotificationCenter.default.post(
            name: .clipboardHelpRequested,
            object: nil,
            userInfo: ["isEditingSelectedText": isEditingSelectedText]
        )
    }

}

private struct ClipboardHeaderSection: View {
    let settings: AppSettings
    let zoomScale: CGFloat
    let isEditingSelectedText: Bool
    let pasteTargetName: String
    let pasteTargetArrowSymbol: String
    let onToggleHelp: () -> Void
    let onOpenSettings: () -> Void

    private func scaled(_ value: CGFloat) -> CGFloat {
        value * zoomScale
    }

    private var theme: InterfaceThemeDefinition {
        settings.interfaceTheme
    }

    var body: some View {
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

                if !isEditingSelectedText {
                    insertTargetHint
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 28)

            HStack(spacing: 10) {
                Button(action: onToggleHelp) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: scaled(13), weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Keyboard help")

                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: scaled(13), weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.top, 1)
        }
        .padding(.horizontal, scaled(12))
        .padding(.vertical, scaled(6))
        .background(theme.headerFill)
    }

    private var editorHeaderPrimaryRow: some View {
        HStack(spacing: 10) {
            shortcutHint(
                icon: "xmark.circle",
                label: t("Cancel", "キャンセル"),
                key: "Esc"
            )
            shortcutHint(
                icon: "checkmark.circle",
                label: t("Confirm", "確定"),
                key: HotKeyManager.displayString(for: settings.commitEditShortcut)
            )
            groupedShortcutHint(
                icons: ["arrow.uturn.backward", "arrow.uturn.forward"],
                label: t("Undo / Redo", "取り消し / やり直し"),
                key: "⌘Z / ⌘⇧Z"
            )
        }
    }

    private var editorHeaderSecondaryRow: some View {
        HStack(spacing: 10) {
            shortcutHint(
                icon: "increase.indent",
                label: t("Indent", "インデント"),
                key: HotKeyManager.displayString(for: settings.indentShortcut)
            )
            shortcutHint(
                icon: "decrease.indent",
                label: t("Outdent", "アウトデント"),
                key: HotKeyManager.displayString(for: settings.outdentShortcut)
            )
            groupedShortcutHint(
                icons: ["arrow.up", "arrow.down"],
                label: t("Move Line", "行移動"),
                key: "\(HotKeyManager.displayString(for: settings.moveLineUpShortcut)) / \(HotKeyManager.displayString(for: settings.moveLineDownShortcut))"
            )
            shortcutHint(
                icon: "doc.richtext",
                label: t("Markdown Preview", "Markdown プレビュー"),
                key: HotKeyManager.displayString(for: settings.toggleMarkdownPreviewShortcut)
            )
            shortcutHint(
                icon: "link",
                label: t("One Line", "一文化"),
                key: HotKeyManager.displayString(for: settings.joinLinesShortcut)
            )
            shortcutHint(
                icon: "terminal",
                label: t("Normalize", "整形"),
                key: HotKeyManager.displayString(for: settings.normalizeForCommandShortcut)
            )
        }
    }

    private var standardHeaderPrimaryRow: some View {
        HStack(spacing: 10) {
            shortcutHint(icon: "xmark", label: t("Close", "閉じる"), key: "Esc")
            groupedShortcutHint(
                icons: ["arrow.uturn.backward", "arrow.uturn.forward"],
                label: t("Undo / Redo", "取り消し / やり直し"),
                key: "\(HotKeyManager.displayString(for: settings.undoShortcut)) / \(HotKeyManager.displayString(for: settings.redoShortcut))"
            )
        }
    }

    private var standardHeaderSecondaryRow: some View {
        HStack(spacing: 10) {
            shortcutHint(icon: "square.and.pencil", label: t("New", "新規"), key: HotKeyManager.displayString(for: settings.newNoteShortcut))
            shortcutHint(icon: "pencil", label: t("Edit", "編集"), key: HotKeyManager.displayString(for: settings.editTextShortcut))
            shortcutHint(icon: "star", label: t("Pin", "ピン留め"), key: HotKeyManager.displayString(for: settings.togglePinShortcut))
            shortcutHint(icon: "delete.left", label: t("Delete", "削除"), key: "⌫")
            shortcutHint(icon: "sidebar.right", label: t("Pins", "ピン表示"), key: "Tab")
            shortcutHint(icon: "terminal", label: t("Normalize", "整形"), key: HotKeyManager.displayString(for: settings.copyNormalizedShortcut))
            shortcutHint(icon: "link", label: t("One Line", "一文化"), key: HotKeyManager.displayString(for: settings.copyJoinedShortcut))
        }
    }

    private var insertTargetHint: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: pasteTargetArrowSymbol)
                    .font(.system(size: scaled(10), weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Paste into \(pasteTargetName)")
                    .font(.system(size: scaled(10.5), weight: .medium))
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 3) {
                Image(systemName: "command")
                    .font(.system(size: scaled(9), weight: .semibold))
                Text("↩")
                    .font(.system(size: scaled(10), weight: .semibold))
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, scaled(8))
        .padding(.vertical, scaled(4))
        .background(theme.hintFill)
    }

    private func shortcutHint(icon: String, label: String, key: String) -> some View {
        ShortcutHintView(
            icon: icon,
            label: label,
            key: key,
            zoomScale: zoomScale,
            primaryTextColor: theme.primaryText,
            secondaryTextColor: theme.secondaryText
        )
    }

    private func groupedShortcutHint(icons: [String], label: String, key: String) -> some View {
        GroupedShortcutHintView(
            icons: icons,
            label: label,
            key: key,
            zoomScale: zoomScale,
            primaryTextColor: theme.primaryText,
            secondaryTextColor: theme.secondaryText
        )
    }

    private func t(_ english: String, _ japanese: String) -> String {
        settings.settingsLanguage == .japanese ? japanese : english
    }
}

struct ClipboardHelpCommandDescriptor: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let shortcut: String
    let symbolName: String
    let details: String?

    init(title: String, shortcut: String, symbolName: String, details: String? = nil) {
        self.title = title
        self.shortcut = shortcut
        self.symbolName = symbolName
        self.details = details
    }
}

enum ClipboardHelpCatalog {
    static func panelHeaderCommands(settings: AppSettings) -> [ClipboardHelpCommandDescriptor] {
        [
            .init(title: t("Close", "閉じる", language: settings.settingsLanguage), shortcut: "Esc", symbolName: "xmark"),
            .init(title: t("Undo / Redo", "取り消し / やり直し", language: settings.settingsLanguage), shortcut: "⌘Z / ⌘⇧Z", symbolName: "arrow.uturn.backward.circle"),
            .init(title: t("Paste into current window", "現在のウィンドウにペースト", language: settings.settingsLanguage), shortcut: "⌘↩", symbolName: "arrowshape.turn.up.left.circle"),
            .init(title: t("New", "新規", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.newNoteShortcut), symbolName: "square.and.pencil"),
            .init(title: t("Edit", "編集", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.editTextShortcut), symbolName: "pencil.circle"),
            .init(title: t("Pin", "ピン留め", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.togglePinShortcut), symbolName: "star.circle"),
            .init(title: t("Delete", "削除", language: settings.settingsLanguage), shortcut: "⌫", symbolName: "delete.left.circle"),
            .init(title: t("Pins", "ピン表示", language: settings.settingsLanguage), shortcut: "Tab", symbolName: "sidebar.right"),
            .init(title: t("Normalize", "整形", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.copyNormalizedShortcut), symbolName: "terminal"),
            .init(title: t("One Line", "一文化", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.copyJoinedShortcut), symbolName: "link.circle")
        ]
    }

    static func editorHeaderCommands(settings: AppSettings) -> [ClipboardHelpCommandDescriptor] {
        [
            .init(title: t("Cancel", "キャンセル", language: settings.settingsLanguage), shortcut: "Esc", symbolName: "xmark.circle"),
            .init(title: t("Confirm", "確定", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.commitEditShortcut), symbolName: "checkmark.circle"),
            .init(title: t("Undo / Redo", "取り消し / やり直し", language: settings.settingsLanguage), shortcut: "⌘Z / ⌘⇧Z", symbolName: "arrow.uturn.backward.circle"),
            .init(title: t("Indent", "インデント", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.indentShortcut), symbolName: "increase.indent"),
            .init(title: t("Outdent", "アウトデント", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.outdentShortcut), symbolName: "decrease.indent"),
            .init(title: t("Move Line", "行移動", language: settings.settingsLanguage), shortcut: "\(HotKeyManager.displayString(for: settings.moveLineUpShortcut)) / \(HotKeyManager.displayString(for: settings.moveLineDownShortcut))", symbolName: "arrow.up.arrow.down.circle"),
            .init(title: t("Markdown Preview", "Markdown プレビュー", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.toggleMarkdownPreviewShortcut), symbolName: "doc.richtext"),
            .init(title: t("Normalize", "整形", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.normalizeForCommandShortcut), symbolName: "terminal"),
            .init(title: t("One Line", "一文化", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.joinLinesShortcut), symbolName: "link.circle")
        ]
    }

    static func panelCommands(settings: AppSettings) -> [ClipboardHelpCommandDescriptor] {
        let commands: [ClipboardHelpCommandDescriptor] = [
            .init(title: t("Close", "閉じる", language: settings.settingsLanguage), shortcut: "Esc", symbolName: "xmark"),
            .init(title: t("Undo / Redo", "取り消し / やり直し", language: settings.settingsLanguage), shortcut: "⌘Z / ⌘⇧Z", symbolName: "arrow.uturn.backward.circle"),
            .init(title: t("Paste selected item into current window", "選択中の項目を現在のウィンドウにペースト", language: settings.settingsLanguage), shortcut: "⌘↩", symbolName: "arrowshape.turn.up.left.circle"),
            .init(title: t("Create a new empty note at #1", "#1 に空の新規ノートを追加", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.newNoteShortcut), symbolName: "square.and.pencil"),
            .init(title: t("Edit selected item", "選択中の項目を編集", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.editTextShortcut), symbolName: "pencil.circle"),
            .init(title: t("Pin selected item", "選択中の項目をピン留め", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.togglePinShortcut), symbolName: "star.circle"),
            .init(title: t("Delete selected item", "選択中の項目を削除", language: settings.settingsLanguage), shortcut: "⌫", symbolName: "delete.left.circle"),
            .init(title: t("Show or hide pinned items", "ピン留めした項目の表示 / 非表示", language: settings.settingsLanguage), shortcut: "Tab", symbolName: "sidebar.right"),
            .init(title: t("Normalize whitespace on selected item", "選択中の項目の空白を整形", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.copyNormalizedShortcut), symbolName: "terminal"),
            .init(title: t("Join selected item into one sentence", "選択中の項目を一文に整形", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.copyJoinedShortcut), symbolName: "link.circle")
        ]
        return commands
    }

    static func editorCommands(settings: AppSettings) -> [ClipboardHelpCommandDescriptor] {
        let commands: [ClipboardHelpCommandDescriptor] = [
            .init(title: t("Cancel", "キャンセル", language: settings.settingsLanguage), shortcut: "Esc", symbolName: "xmark.circle"),
            .init(title: t("Confirm current edit", "現在の編集を確定", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.commitEditShortcut), symbolName: "checkmark.circle"),
            .init(title: t("Undo / Redo", "取り消し / やり直し", language: settings.settingsLanguage), shortcut: "⌘Z / ⌘⇧Z", symbolName: "arrow.uturn.backward.circle"),
            .init(title: t("Indent selected lines", "まとめてインデント", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.indentShortcut), symbolName: "increase.indent"),
            .init(title: t("Outdent selected lines", "まとめてアウトデント", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.outdentShortcut), symbolName: "decrease.indent"),
            .init(title: t("Move line up / down", "行単位で移動", language: settings.settingsLanguage), shortcut: "\(HotKeyManager.displayString(for: settings.moveLineUpShortcut)) / \(HotKeyManager.displayString(for: settings.moveLineDownShortcut))", symbolName: "arrow.up.arrow.down.circle"),
            .init(title: t("Markdown preview", "Markdown プレビュー", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.toggleMarkdownPreviewShortcut), symbolName: "doc.richtext"),
            .init(title: t("Normalize selection whitespace", "選択中の項目の空白を整形", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.normalizeForCommandShortcut), symbolName: "terminal"),
            .init(title: t("Join selection into one sentence", "選択中の項目を一文に整形", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.joinLinesShortcut), symbolName: "link.circle")
        ]
        return commands
    }

    static func copyCommands(settings: AppSettings) -> [ClipboardHelpCommandDescriptor] {
        [
            .init(title: t("Copy normalized selected item", "選択中の項目の空白を整形してコピー", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.copyNormalizedShortcut), symbolName: "terminal"),
            .init(title: t("Copy selected item as one sentence", "選択中の項目を一文に整形してコピー", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.copyJoinedShortcut), symbolName: "link.circle")
        ]
    }

    private static func t(_ english: String, _ japanese: String, language: SettingsLanguage) -> String {
        language == .japanese ? japanese : english
    }
}

struct ClipboardHelpPanelContent: View {

    let settings: AppSettings
    let isEditingSelectedText: Bool
    let onClose: () -> Void
    @State private var isMarkdownSyntaxExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("Keyboard Help", "キーボードヘルプ"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(isEditingSelectedText ? t("Editor commands", "編集コマンド") : t("Panel commands", "通常画面コマンド"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    helpSection(title: t("Standard Window", "標準ウィンドウ"), commands: panelCommands)
                    helpSection(title: t("Editor Window", "編集ウィンドウ"), commands: editorCommands)
                    helpSection(title: t("Copy Commands", "コピー系コマンド"), commands: copyCommands)
                    markdownSyntaxSection
                }
            }
            .scrollIndicators(.visible)
        }
        .padding(16)
        .frame(minWidth: 320, idealWidth: 400, maxWidth: 440, minHeight: 260, idealHeight: 420, maxHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var panelCommands: [ClipboardHelpCommandDescriptor] {
        ClipboardHelpCatalog.panelCommands(settings: settings)
    }

    private var editorCommands: [ClipboardHelpCommandDescriptor] {
        ClipboardHelpCatalog.editorCommands(settings: settings)
    }

    private var copyCommands: [ClipboardHelpCommandDescriptor] {
        ClipboardHelpCatalog.copyCommands(settings: settings)
    }

    private func helpSection(title: String, commands: [ClipboardHelpCommandDescriptor]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            ForEach(Array(commands.enumerated()), id: \.offset) { _, command in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(command.title)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(nil)
                        if let details = command.details, !details.isEmpty {
                            Text(details)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(command.shortcut)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var markdownSyntaxSection: some View {
        DisclosureGroup(
            isExpanded: $isMarkdownSyntaxExpanded,
            content: {
                VStack(alignment: .leading, spacing: 8) {
                    markdownExample("# Heading")
                    markdownExample("## Subheading")
                    markdownExample("**bold**")
                    markdownExample("*italic*")
                    markdownExample("- item")
                    markdownExample("1. item")
                    markdownExample("- [ ] task")
                    markdownExample("`code`")
                    markdownExample("[clipboard](https://github.com/ksmkzs/clipboard)")
                    markdownExample("```md\\ncode block\\n```")
                }
                .padding(.top, 6)
            },
            label: {
                Text(t("Markdown Syntax", "Markdown 構文"))
                    .font(.system(size: 12, weight: .semibold))
            }
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func markdownExample(_ syntax: String) -> some View {
        let source = syntax.replacingOccurrences(of: "\\n", with: "\n")
        return HStack(alignment: .top, spacing: 12) {
            Text(source)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(minWidth: 120, alignment: .leading)
            Text("→")
                .foregroundStyle(.secondary)
            MarkdownWebPreview(markdown: source, fontScale: 0.84, scrollProgress: nil)
                .frame(width: 178)
                .frame(height: markdownExamplePreviewHeight(for: source), alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )
        }
    }

    private func markdownExamplePreviewHeight(for source: String) -> CGFloat {
        if source.contains("```") {
            return 88
        }
        if source.contains("\n") {
            return 52
        }
        return 34
    }

    private func t(_ english: String, _ japanese: String) -> String {
        settings.settingsLanguage == .japanese ? japanese : english
    }
}

struct StandaloneNoteEditorView: View {
    enum CommitMode {
        case pasteToTarget
        case returnToCodex
        case orphanedCodex
    }

    private static let markdownPreviewSidebarWidth: CGFloat = 260

    let initialText: String
    @ObservedObject var appDelegate: AppDelegate
    let codexContext: AppDelegate.CodexDraftContext?
    let commitMode: CommitMode
    let onDraftChange: (String) -> Void
    let onCommit: (String) -> Void
    let onClose: () -> Void
    let onDiscardOrphanCodex: (() -> Void)?

    @State private var draftText = ""
    @State private var committedText = ""
    @State private var isMarkdownPreviewVisible = false
    @State private var editorSelectionLocation = 0
    @State private var markdownPreviewScrollProgress: CGFloat = 0

    private var zoomScale: CGFloat {
        CGFloat(appDelegate.settings.clampedInterfaceZoomScale)
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        value * zoomScale
    }

    private var theme: InterfaceThemeDefinition {
        appDelegate.settings.interfaceTheme
    }

    private var pasteTargetName: String {
        appDelegate.currentPasteTargetAppName() ?? t("previous app", "前のアプリ")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            editorBody
        }
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                theme.panelOverlay
            }
        )
        .overlay(alignment: .bottom) {
            WindowResizeCue(text: "↕")
                .padding(.bottom, 6)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .trailing) {
            WindowResizeCue(text: "↔")
                .padding(.trailing, 12)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            WindowResizeCue(text: "⤡")
                .padding(.trailing, 8)
                .padding(.bottom, 6)
                .allowsHitTesting(false)
        }
        .animation(nil, value: appDelegate.settings.interfaceThemePreset.rawValue)
        .onAppear(perform: loadCurrentText)
        .onChange(of: draftText) { _, newValue in
            onDraftChange(newValue)
            markdownPreviewScrollProgress = MarkdownPreviewScrollSync.progress(
                for: newValue,
                selectionLocation: editorSelectionLocation
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let codexContext, commitMode != .pasteToTarget {
                codexMetadataRow(codexContext)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    primaryHeaderRow
                    secondaryHeaderRow
                }

                VStack(alignment: .leading, spacing: 6) {
                    primaryHeaderRow
                    secondaryHeaderRow
                }
            }
        }
        .padding(.horizontal, scaled(12))
        .padding(.vertical, scaled(6))
        .background(theme.headerFill)
    }

    private func codexMetadataRow(_ codexContext: AppDelegate.CodexDraftContext) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                codexMetadataPill(
                    icon: "folder",
                    title: t("Project", "プロジェクト"),
                    value: codexContext.projectDisplayPath
                )
                codexMetadataPill(
                    icon: "number",
                    title: t("Chat ID", "チャットID"),
                    value: codexContext.shortSessionID
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    codexMetadataPill(
                        icon: "folder",
                        title: t("Project", "プロジェクト"),
                        value: codexContext.projectDisplayPath
                    )
                    codexMetadataPill(
                        icon: "number",
                        title: t("Chat ID", "チャットID"),
                        value: codexContext.shortSessionID
                    )
                }
            }
        }
    }

    private func codexMetadataPill(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: scaled(9), weight: .semibold))
            Text("\(title): \(value)")
                .font(.system(size: scaled(10.5), weight: .semibold))
        }
        .foregroundStyle(theme.primaryText)
        .padding(.horizontal, scaled(8))
        .padding(.vertical, scaled(4))
        .background(theme.hintFill)
    }

    private var primaryHeaderRow: some View {
        HStack(spacing: 10) {
            ShortcutHintView(
                icon: "xmark.circle",
                label: t("Close", "閉じる"),
                key: "Esc",
                zoomScale: zoomScale,
                primaryTextColor: theme.primaryText,
                secondaryTextColor: theme.secondaryText
            )
            GroupedShortcutHintView(
                icons: ["arrow.uturn.backward", "arrow.uturn.forward"],
                label: t("Undo / Redo", "取り消し / やり直し"),
                key: "⌘Z / ⌘⇧Z",
                zoomScale: zoomScale,
                primaryTextColor: theme.primaryText,
                secondaryTextColor: theme.secondaryText
            )
            standaloneCommitHint
        }
    }

    private var secondaryHeaderRow: some View {
        HStack(spacing: 10) {
            ShortcutHintView(
                icon: "increase.indent",
                label: t("Indent", "インデント"),
                key: HotKeyManager.displayString(for: appDelegate.settings.indentShortcut),
                zoomScale: zoomScale,
                primaryTextColor: theme.primaryText,
                secondaryTextColor: theme.secondaryText
            )
            ShortcutHintView(
                icon: "decrease.indent",
                label: t("Outdent", "アウトデント"),
                key: HotKeyManager.displayString(for: appDelegate.settings.outdentShortcut),
                zoomScale: zoomScale,
                primaryTextColor: theme.primaryText,
                secondaryTextColor: theme.secondaryText
            )
            GroupedShortcutHintView(
                icons: ["arrow.up", "arrow.down"],
                label: t("Move Line", "行移動"),
                key: "\(HotKeyManager.displayString(for: appDelegate.settings.moveLineUpShortcut)) / \(HotKeyManager.displayString(for: appDelegate.settings.moveLineDownShortcut))",
                zoomScale: zoomScale,
                primaryTextColor: theme.primaryText,
                secondaryTextColor: theme.secondaryText
            )
            ShortcutHintView(
                icon: "doc.richtext",
                label: t("Markdown Preview", "Markdown プレビュー"),
                key: HotKeyManager.displayString(for: appDelegate.settings.toggleMarkdownPreviewShortcut),
                zoomScale: zoomScale,
                primaryTextColor: theme.primaryText,
                secondaryTextColor: theme.secondaryText
            )
            ShortcutHintView(
                icon: "terminal",
                label: t("Normalize", "整形"),
                key: HotKeyManager.displayString(for: appDelegate.settings.normalizeForCommandShortcut),
                zoomScale: zoomScale,
                primaryTextColor: theme.primaryText,
                secondaryTextColor: theme.secondaryText
            )
            ShortcutHintView(
                icon: "link",
                label: t("One Line", "一文化"),
                key: HotKeyManager.displayString(for: appDelegate.settings.joinLinesShortcut),
                zoomScale: zoomScale,
                primaryTextColor: theme.primaryText,
                secondaryTextColor: theme.secondaryText
            )
        }
    }

    private var editorBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if commitMode == .orphanedCodex {
                orphanedCodexBanner
            }

            if isMarkdownPreviewVisible {
                HStack {
                    Spacer(minLength: 0)
                    Text(t("Markdown Preview", "Markdown プレビュー"))
                        .font(.system(size: scaled(11), weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: scaled(Self.markdownPreviewSidebarWidth), alignment: .leading)
                }
            }

            HStack(alignment: .top, spacing: 10) {
                EditorTextView(
                    text: $draftText,
                    fontSize: scaled(12),
                    commitShortcut: appDelegate.settings.commitEditShortcut,
                    indentShortcut: appDelegate.settings.indentShortcut,
                    outdentShortcut: appDelegate.settings.outdentShortcut,
                    moveLineUpShortcut: appDelegate.settings.moveLineUpShortcut,
                    moveLineDownShortcut: appDelegate.settings.moveLineDownShortcut,
                    toggleMarkdownPreviewShortcut: appDelegate.settings.toggleMarkdownPreviewShortcut,
                    joinLinesShortcut: appDelegate.settings.joinLinesShortcut,
                    normalizeForCommandShortcut: appDelegate.settings.normalizeForCommandShortcut,
                    orphanCodexDiscardShortcut: appDelegate.settings.orphanCodexDiscardShortcut,
                    onEscape: cancelAndClose,
                    onCommit: commitDraft,
                    onDiscardOrphanCodex: onDiscardOrphanCodex,
                    onToggleMarkdownPreview: toggleMarkdownPreview,
                    onToggleHelp: {},
                    onZoomIn: { appDelegate.increaseInterfaceZoom() },
                    onZoomOut: { appDelegate.decreaseInterfaceZoom() },
                    onResetZoom: { appDelegate.resetInterfaceZoom() },
                    onSelectionChange: updateEditorSelectionLocation
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.07))
                        .overlay(theme.cardFill.opacity(0.45))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                )

                if isMarkdownPreviewVisible {
                    MarkdownPreviewSidebar(
                        title: nil,
                        markdown: draftText,
                        width: scaled(Self.markdownPreviewSidebarWidth),
                        minHeight: scaled(180),
                        fontScale: zoomScale,
                        scrollProgress: markdownPreviewScrollProgress
                    )
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .padding(scaled(12))
    }

    private var orphanedCodexBanner: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(t("Codex session disconnected", "Codex セッションの接続が切れました"))
                    .font(.system(size: scaled(11), weight: .semibold))
                    .foregroundStyle(.primary)
                if let codexContext {
                    Text("\(codexContext.projectDisplayName) • \(codexContext.shortSessionID)")
                        .font(.system(size: scaled(10.5), weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text(t(
                    "You can keep editing, then copy to clipboard or discard this draft.",
                    "編集は継続できます。内容をクリップボードへ保存するか、この下書きを削除してください。"
                ))
                .font(.system(size: scaled(10)))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button {
                commitDraft()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard")
                    Text(t("Copy", "保存"))
                }
                .font(.system(size: scaled(10.5), weight: .semibold))
            }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive) {
                onDiscardOrphanCodex?()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text(t("Delete", "削除"))
                }
                .font(.system(size: scaled(10.5), weight: .semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, scaled(10))
        .padding(.vertical, scaled(8))
        .background(theme.hintFill.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var standaloneCommitHint: some View {
        switch commitMode {
        case .pasteToTarget:
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.left")
                        .font(.system(size: scaled(10), weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("\(t("Paste into", "ペースト先")) \(pasteTargetName)")
                        .font(.system(size: scaled(10.5), weight: .medium))
                        .foregroundStyle(.primary)
                }

                HStack(spacing: 3) {
                    Image(systemName: "command")
                        .font(.system(size: scaled(9), weight: .semibold))
                    Text("↩")
                        .font(.system(size: scaled(10), weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, scaled(8))
            .padding(.vertical, scaled(4))
            .background(theme.hintFill)
        case .returnToCodex:
            ShortcutHintView(
                icon: "arrowshape.turn.up.left",
                label: t("Return to Codex", "Codexへ戻す"),
                key: "⌘↩",
                zoomScale: zoomScale,
                primaryTextColor: theme.primaryText,
                secondaryTextColor: theme.secondaryText
            )
        case .orphanedCodex:
            HStack(spacing: 10) {
                ShortcutHintView(
                    icon: "doc.on.clipboard",
                    label: t("Copy to Clipboard", "クリップボードに保存"),
                    key: "⌘↩",
                    zoomScale: zoomScale,
                    primaryTextColor: theme.primaryText,
                    secondaryTextColor: theme.secondaryText
                )
                ShortcutHintView(
                    icon: "trash",
                    label: t("Delete", "削除"),
                    key: HotKeyManager.displayString(for: appDelegate.settings.orphanCodexDiscardShortcut),
                    zoomScale: zoomScale,
                    primaryTextColor: theme.primaryText,
                    secondaryTextColor: theme.secondaryText
                )
            }
        }
    }

    private func loadCurrentText() {
        let text = initialText
        committedText = text
        draftText = text
        editorSelectionLocation = 0
        markdownPreviewScrollProgress = MarkdownPreviewScrollSync.progress(for: text, selectionLocation: 0)
        onDraftChange(text)
    }

    private func commitDraft() {
        committedText = draftText
        onCommit(draftText)
    }

    private func cancelAndClose() {
        guard commitMode != .orphanedCodex else { return }
        onClose()
    }

    private func toggleMarkdownPreview() {
        isMarkdownPreviewVisible.toggle()
    }

    private func updateEditorSelectionLocation(_ location: Int) {
        editorSelectionLocation = location
        markdownPreviewScrollProgress = MarkdownPreviewScrollSync.progress(
            for: draftText,
            selectionLocation: location
        )
    }

    private func t(_ english: String, _ japanese: String) -> String {
        appDelegate.settings.settingsLanguage == .japanese ? japanese : english
    }
}

private struct HistoryListSection: View {
    let historyItems: [ClipboardItem]
    let pinLabelsByID: [UUID: String]
    let selectedItemID: UUID?
    let focusedItemID: UUID?
    let isHistoryFocus: Bool
    let historyDetailItemID: UUID?
    let editingItemID: UUID?
    let settings: AppSettings
    let theme: InterfaceThemeDefinition
    let interfaceZoomScale: CGFloat
    @Binding var editorDraftText: String
    let isMarkdownPreviewVisible: Bool
    @Binding var pendingScrollTargetID: UUID?
    let imageLoader: (String) -> NSImage?
    let onSelect: (UUID) -> Void
    let onToggleDetail: (UUID) -> Void
    let onBeginEditing: (UUID) -> Void
    let onCommitEditor: (UUID) -> Void
    let onCancelEditor: (UUID) -> Void
    let onToggleMarkdownPreview: () -> Void
    let onCopyRaw: (ClipboardItem) -> Void
    let onToggleHelp: () -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onResetZoom: () -> Void
    let onRenamePin: (UUID, String) -> Void
    let onTogglePinned: (ClipboardItem) -> Void
    let onDelete: (UUID) -> Void
    let onFirstAppear: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if historyItems.isEmpty {
                    EmptyStateView(
                        title: "No clipboard history yet",
                        message: "Copy text or images and they will appear here.",
                        zoomScale: interfaceZoomScale
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(historyItems.enumerated()), id: \.element.id) { index, item in
                                HistoryRowView(
                                    item: item,
                                    isSelected: item.id == selectedItemID,
                                    isFocused: isHistoryFocus && item.id == focusedItemID,
                                    theme: theme,
                                    isCompact: false,
                                    badgeText: "#\(index + 1)",
                                    pinLabel: pinLabelsByID[item.id],
                                    showPinLabelEditor: false,
                                    showsMetadata: false,
                                    isDetailPresented: historyDetailItemID == item.id,
                                    isEditingText: editingItemID == item.id,
                                    pinnedDropIndicatorPosition: nil,
                                    imageLoader: imageLoader,
                                    onSelect: { onSelect(item.id) },
                                    onToggleDetail: { onToggleDetail(item.id) },
                                    onBeginEditing: { onBeginEditing(item.id) },
                                    onCommitEditor: { onCommitEditor(item.id) },
                                    onCancelEditor: { onCancelEditor(item.id) },
                                    onCopyRaw: { onCopyRaw(item) },
                                    onToggleHelp: onToggleHelp,
                                    onZoomIn: onZoomIn,
                                    onZoomOut: onZoomOut,
                                    onResetZoom: onResetZoom,
                                    interfaceZoomScale: interfaceZoomScale,
                                    commitEditShortcut: settings.commitEditShortcut,
                                    indentShortcut: settings.indentShortcut,
                                    outdentShortcut: settings.outdentShortcut,
                                    moveLineUpShortcut: settings.moveLineUpShortcut,
                                    moveLineDownShortcut: settings.moveLineDownShortcut,
                                    toggleMarkdownPreviewShortcut: settings.toggleMarkdownPreviewShortcut,
                                    joinLinesShortcut: settings.joinLinesShortcut,
                                    normalizeForCommandShortcut: settings.normalizeForCommandShortcut,
                                    editorText: Binding(
                                        get: { editingItemID == item.id ? editorDraftText : (item.textContent ?? "") },
                                        set: { editorDraftText = $0 }
                                    ),
                                    isMarkdownPreviewVisible: editingItemID == item.id && isMarkdownPreviewVisible,
                                    onRenamePin: { name in onRenamePin(item.id, name) },
                                    onTabFromPinLabel: {},
                                    onToggleMarkdownPreview: onToggleMarkdownPreview,
                                    onTogglePinned: { onTogglePinned(item) },
                                    onDelete: { onDelete(item.id) }
                                )
                                .equatable()
                                .id(item.id)
                            }
                        }
                        .padding(5)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear(perform: onFirstAppear)
            .onChange(of: pendingScrollTargetID) { _, newID in
                guard let newID else { return }
                proxy.scrollTo(newID)
                pendingScrollTargetID = nil
            }
        }
    }
}

private struct PinnedSidebarSection: View {
    private static let sidebarWidth: CGFloat = 132

    let pinnedItems: [ClipboardItem]
    let pinLabelsByID: [UUID: String]
    let selectedItemID: UUID?
    let focusedItemID: UUID?
    let isPinnedFocus: Bool
    let pinnedDetailItemID: UUID?
    let editingItemID: UUID?
    let settings: AppSettings
    let theme: InterfaceThemeDefinition
    let interfaceZoomScale: CGFloat
    @Binding var editorDraftText: String
    let isMarkdownPreviewVisible: Bool
    @Binding var draggedPinnedItemID: UUID?
    @Binding var pinnedDropTargetIndex: Int?
    @Binding var pinnedRowFrames: [UUID: CGRect]
    @Binding var pendingPinnedScrollTargetID: UUID?
    let imageLoader: (String) -> NSImage?
    let onSelect: (UUID) -> Void
    let onToggleDetail: (UUID) -> Void
    let onBeginEditing: (UUID) -> Void
    let onCommitEditor: (UUID) -> Void
    let onCancelEditor: (UUID) -> Void
    let onToggleMarkdownPreview: () -> Void
    let onCopyRaw: (ClipboardItem) -> Void
    let onToggleHelp: () -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onResetZoom: () -> Void
    let onRenamePin: (UUID, String) -> Void
    let onTabFromPinLabel: () -> Void
    let onTogglePinned: (ClipboardItem) -> Void
    let onDelete: (UUID) -> Void
    let makeDropTargets: (CGSize) -> [PinnedDropTarget]
    let onPerformMove: (UUID, [UUID]) -> Void

    private var sidebarWidth: CGFloat {
        Self.sidebarWidth * interfaceZoomScale
    }

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if pinnedItems.isEmpty {
                    EmptyStateView(
                        title: "No pinned items",
                        message: "Pin items with the star to keep them easy to reach.",
                        zoomScale: interfaceZoomScale
                    )
                    .frame(width: sidebarWidth)
                } else {
                    GeometryReader { geometry in
                        let dropTargets = makeDropTargets(geometry.size)
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(pinnedItems, id: \.id) { item in
                                    pinnedRow(item)
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
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 5)
                            .coordinateSpace(name: "PinnedListArea")
                            .onPreferenceChange(PinnedRowFramePreferenceKey.self) { pinnedRowFrames = $0 }
                            .onDrop(
                                of: [UTType.text.identifier],
                                delegate: PinnedListDropDelegate(
                                    pinnedItems: pinnedItems,
                                    dropTargets: dropTargets,
                                    draggedPinnedItemID: $draggedPinnedItemID,
                                    activeTargetIndex: $pinnedDropTargetIndex,
                                    onPerformMove: onPerformMove
                                )
                            )
                        }
                        .overlay(alignment: .topLeading) {
                            if let activeTarget = dropTargets.first(where: { $0.index == pinnedDropTargetIndex }) {
                                PinnedDropGapView(isActive: true)
                                    .frame(width: activeTarget.lineWidth)
                                    .position(x: activeTarget.lineMidX, y: activeTarget.lineY)
                            }
                        }
                    }
                    .background(theme.pinnedSidebarFill)
                    .frame(width: sidebarWidth)
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

    private func pinnedRow(_ item: ClipboardItem) -> some View {
            HistoryRowView(
                item: item,
            isSelected: item.id == selectedItemID,
            isFocused: isPinnedFocus && item.id == focusedItemID,
            theme: theme,
            isCompact: true,
            badgeText: nil,
            pinLabel: pinLabelsByID[item.id],
            showPinLabelEditor: true,
            showsMetadata: false,
            isDetailPresented: pinnedDetailItemID == item.id,
            isEditingText: editingItemID == item.id,
            pinnedDropIndicatorPosition: nil,
            imageLoader: imageLoader,
            onSelect: { onSelect(item.id) },
            onToggleDetail: { onToggleDetail(item.id) },
            onBeginEditing: { onBeginEditing(item.id) },
            onCommitEditor: { onCommitEditor(item.id) },
            onCancelEditor: { onCancelEditor(item.id) },
            onCopyRaw: { onCopyRaw(item) },
            onToggleHelp: onToggleHelp,
            onZoomIn: onZoomIn,
            onZoomOut: onZoomOut,
            onResetZoom: onResetZoom,
            interfaceZoomScale: interfaceZoomScale,
            commitEditShortcut: settings.commitEditShortcut,
            indentShortcut: settings.indentShortcut,
            outdentShortcut: settings.outdentShortcut,
                moveLineUpShortcut: settings.moveLineUpShortcut,
                moveLineDownShortcut: settings.moveLineDownShortcut,
                toggleMarkdownPreviewShortcut: settings.toggleMarkdownPreviewShortcut,
                joinLinesShortcut: settings.joinLinesShortcut,
                normalizeForCommandShortcut: settings.normalizeForCommandShortcut,
                editorText: Binding(
                    get: { editingItemID == item.id ? editorDraftText : (item.textContent ?? "") },
                    set: { editorDraftText = $0 }
                ),
                isMarkdownPreviewVisible: editingItemID == item.id && isMarkdownPreviewVisible,
                onRenamePin: { name in onRenamePin(item.id, name) },
                onTabFromPinLabel: onTabFromPinLabel,
                onToggleMarkdownPreview: onToggleMarkdownPreview,
                onTogglePinned: { onTogglePinned(item) },
                onDelete: { onDelete(item.id) }
            )
        .equatable()
    }
}

private struct EmptyStateView: View {
    let title: String
    let message: String
    var zoomScale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13 * zoomScale, weight: .semibold))
            Text(message)
                .font(.system(size: 11.5 * zoomScale))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16 * zoomScale)
    }
}

private struct ShortcutHintView: View {
    let icon: String
    let label: String
    let key: String
    var zoomScale: CGFloat = 1
    var primaryTextColor: Color = .primary
    var secondaryTextColor: Color = .secondary

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10 * zoomScale, weight: .semibold))
                .foregroundStyle(primaryTextColor)
            Text(label)
                .font(.system(size: 10 * zoomScale, weight: .medium))
                .foregroundStyle(primaryTextColor)
            Text(key)
                .font(.system(size: 9.5 * zoomScale, weight: .semibold, design: .monospaced))
                .foregroundStyle(secondaryTextColor)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct GroupedShortcutHintView: View {
    let icons: [String]
    let label: String
    let key: String
    var zoomScale: CGFloat = 1
    var primaryTextColor: Color = .primary
    var secondaryTextColor: Color = .secondary

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 2) {
                ForEach(icons, id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 10 * zoomScale, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                }
            }
            Text(label)
                .font(.system(size: 10 * zoomScale, weight: .medium))
                .foregroundStyle(primaryTextColor)
            Text(key)
                .font(.system(size: 9.5 * zoomScale, weight: .semibold, design: .monospaced))
                .foregroundStyle(secondaryTextColor)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct WindowResizeCue: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary.opacity(0.9))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.14))
            .clipShape(Capsule())
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

    static func makeTargets(
        orderedFrames: [CGRect],
        rowSpacing: CGFloat,
        listWidth: CGFloat,
        minimumTriggerHeight: CGFloat,
        triggerHeightScale: CGFloat = 1
    ) -> [PinnedDropTarget] {
        guard !orderedFrames.isEmpty else { return [] }

        let lineWidth = max(0, listWidth - 2)
        let lineMidX = listWidth * 0.5

        func makeTarget(index: Int, gapTop: CGFloat, gapBottom: CGFloat) -> PinnedDropTarget {
            let lineY = (gapTop + gapBottom) * 0.5
            let gapHeight = max(0, gapBottom - gapTop)
            let triggerHeight = max(minimumTriggerHeight, gapHeight * triggerHeightScale)
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

private struct PinnedListDropDelegate: DropDelegate {
    let pinnedItems: [ClipboardItem]
    let dropTargets: [PinnedDropTarget]
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
        dropTargets.first(where: { $0.triggerRect.contains(location) })?.index
    }
}

extension Notification.Name {
    static let clipboardPanelWillOpen = Notification.Name("clipboardPanelWillOpen")
    static let clipboardPanelWillClose = Notification.Name("clipboardPanelWillClose")
    static let clipboardHelpRequested = Notification.Name("clipboardHelpRequested")
    static let clipboardManualNoteCreated = Notification.Name("clipboardManualNoteCreated")
}
