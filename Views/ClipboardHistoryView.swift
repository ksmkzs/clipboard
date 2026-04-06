//
//  ClipboardHistoryView.swift
//  ClipboardHistory
//
//  Created by あいちゅ on 2026/02/27.
//
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

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
    var onCopyRequest: (ClipboardItem) -> Bool
    var onCopyTextRequest: (String, String) -> Bool
    var onPasteRequest: (ClipboardItem) -> Void
    var onOpenSettings: () -> Void
    var onClosePanel: () -> Void
    var onPinnedAreaVisibilityChanged: (Bool) -> Void = { _ in }
    var onFocusChanged: (ClipboardItem?) -> Void = { _ in }
    var onSelectionChanged: (ClipboardItem?) -> Void = { _ in }
    var onInlineEditorStateChanged: (UUID?, Bool, Bool) -> Void = { _, _, _ in }
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
        decoratedBody
    }

    private var baseBody: some View {
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
    }

    private var decoratedBody: some View {
        baseBody
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
        .onReceive(
            NotificationCenter.default.publisher(for: .clipboardPanelWillOpen),
            perform: handlePanelWillOpen
        )
        .onReceive(
            NotificationCenter.default.publisher(for: .clipboardPanelWillClose),
            perform: handlePanelWillClose
        )
        .onAppear(perform: handlePanelValidationAppear)
        .onChange(of: isPinnedAreaVisible, perform: handlePinnedAreaVisibilityChanged)
        .onChange(of: selectionScope, perform: handleSelectionScopeChanged)
        .onReceive(
            NotificationCenter.default.publisher(for: .clipboardItemsDidChange),
            perform: handleClipboardItemsDidChange
        )
        .onReceive(
            NotificationCenter.default.publisher(for: .clipboardTransformRequested),
            perform: handleClipboardTransformRequested
        )
        .onReceive(
            NotificationCenter.default.publisher(for: .clipboardManualNoteCreated),
            perform: handleClipboardManualNoteCreated
        )
        .onReceive(
            NotificationCenter.default.publisher(for: .clipboardPanelValidationRequested),
            perform: handlePanelValidationNotification
        )
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
            onCopyJoinedCommand: { joinSelectedItemLines() },
            onCopyNormalizedCommand: { normalizeSelectedItemForCommand() },
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
            toastOverlay
        }
        .overlay(alignment: .trailing) {
            pinHandle
        }
        .overlay(alignment: .bottom) {
            verticalResizeCue
        }
        .overlay(alignment: .trailing) {
            horizontalResizeCue
        }
        .overlay(alignment: .bottomTrailing) {
            diagonalResizeCue
        }
        .animation(.easeOut(duration: 0.14), value: toastEntries)
        .onAppear(perform: handleAppear)
        .onChange(of: selectedItemID, perform: handleSelectedItemIDChanged)
        .onChange(of: focusedItemID, perform: handleFocusedItemIDChanged)
        .onChange(of: editingItemID, perform: handleEditingItemIDChanged)
        .onChange(of: isMarkdownPreviewVisible, perform: handleMarkdownPreviewVisibilityChanged)
        .onChange(of: editorDraftText, perform: handleEditorDraftTextChanged)
    }

    private func handleAppear() {
        refreshItemsFromStore()
        notifyInlineEditorStateChanged()
    }

    private func handlePanelWillOpen(_ notification: Notification) {
        isPinnedAreaVisible = false
        historyDetailItemID = nil
        pinnedDetailItemID = nil
        editingItemID = nil
        editorDraftText = ""
        isMarkdownPreviewVisible = false
        refreshItemsFromStore()
        resetSelection(shouldScroll: true)

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

    private func handlePanelWillClose(_: Notification) {
        commitActiveEditorIfNeeded()
    }

    private func handlePanelValidationAppear() {
        onPinnedAreaVisibilityChanged(isPinnedAreaVisible)
        PanelValidationState.shared.pinnedAreaVisible = isPinnedAreaVisible
        PanelValidationState.shared.selectionScopeRaw = selectionScope == .pinned ? "pinned" : "history"
    }

    private func handlePinnedAreaVisibilityChanged(_ newValue: Bool) {
        onPinnedAreaVisibilityChanged(newValue)
        PanelValidationState.shared.pinnedAreaVisible = newValue
    }

    private func handleSelectionScopeChanged(_ newValue: SelectionScope) {
        PanelValidationState.shared.selectionScopeRaw = newValue == .pinned ? "pinned" : "history"
    }

    private func handleSelectedItemIDChanged(_: ClipboardItem.ID?) {
        onSelectionChanged(selectedItem())
    }

    private func handleFocusedItemIDChanged(_: ClipboardItem.ID?) {
        onFocusChanged(focusedItem())
    }

    private func handleEditingItemIDChanged(_ newValue: ClipboardItem.ID?) {
        onInlineEditorStateChanged(newValue, isInlineEditorDirty, isMarkdownPreviewVisible)
    }

    private func handleMarkdownPreviewVisibilityChanged(_ newValue: Bool) {
        onInlineEditorStateChanged(editingItemID, isInlineEditorDirty, newValue)
    }

    private func handleEditorDraftTextChanged(_: String) {
        notifyInlineEditorStateChanged()
    }

    private func notifyInlineEditorStateChanged() {
        onInlineEditorStateChanged(editingItemID, isInlineEditorDirty, isMarkdownPreviewVisible)
    }

    private func handleClipboardItemsDidChange(_: Notification) {
        refreshItemsFromStore()
    }

    private func handleClipboardTransformRequested(_ notification: Notification) {
        guard let action = notification.userInfo?["action"] as? String else { return }
        switch action {
        case "join":
            if editingItemID != nil {
                NotificationCenter.default.post(
                    name: .editorCommandRequested,
                    object: nil,
                    userInfo: ["command": EditorCommand.joinLines.rawValue]
                )
            } else {
                joinSelectedItemLines()
            }
        case "normalize":
            if editingItemID != nil {
                NotificationCenter.default.post(
                    name: .editorCommandRequested,
                    object: nil,
                    userInfo: ["command": EditorCommand.normalizeForCommand.rawValue]
                )
            } else {
                normalizeSelectedItemForCommand()
            }
        default:
            break
        }
    }

    private func handleClipboardManualNoteCreated(_ notification: Notification) {
        guard let itemID = notification.userInfo?["itemID"] as? UUID else { return }
        refreshItemsFromStore()
        isPinnedAreaVisible = false
        selectionScope = .history
        commitSelection(itemID, in: .history, shouldScroll: true)
        showToast("New note")
    }

    private func handlePanelValidationNotification(_ notification: Notification) {
        guard let action = notification.userInfo?["action"] as? String else { return }
        switch action {
        case "moveDown":
            moveSelection(by: 1)
        case "moveUp":
            moveSelection(by: -1)
        case "moveLeft":
            moveSelectionHorizontally(to: .history)
        case "moveRight":
            moveSelectionHorizontally(to: .pinned)
        case "commitSelection":
            commitFocusedSelection()
        case "togglePinnedArea":
            togglePinnedAreaFromKeyboard()
        case "togglePin":
            togglePinnedForSelectedItem()
        case "togglePinFocused":
            togglePinnedForFocusedItem()
        case "deleteSelected":
            deleteSelectedItem()
        case "deleteFocused":
            deleteFocusedItem()
        case "toggleEditor":
            toggleEditorForSelectedItem()
        case "openFocusedEditor":
            openEditorForFocusedItem()
        case "copySelected":
            copySelectedItem()
        case "pasteSelected":
            pasteSelectedItem()
        case "joinSelected":
            joinSelectedItemLines()
        case "normalizeSelected":
            normalizeSelectedItemForCommand()
        case "setEditorText":
            guard let text = notification.userInfo?["text"] as? String, editingItemID != nil else { return }
            editorDraftText = text
        case "commitEditor":
            if let editingItemID {
                commitEditorIfNeeded(for: editingItemID)
            }
        case "cancelEditor":
            if let editingItemID {
                cancelEditorIfNeeded(for: editingItemID)
            }
        default:
            return
        }
    }

    private var isInlineEditorDirty: Bool {
        guard let editingItemID,
              let item = allItemsByID[editingItemID],
              let originalText = dataManager.resolvedText(for: item) else {
            return false
        }
        return editorDraftText != originalText
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if !toastEntries.isEmpty {
            VStack(spacing: 6) {
                ForEach(toastEntries.suffix(Self.maxVisibleToasts)) { toast in
                    toastChip(for: toast)
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func toastChip(for toast: ToastEntry) -> some View {
        Text(toast.message)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(toast.style.backgroundColor)
            .clipShape(Capsule())
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var verticalResizeCue: some View {
        WindowResizeCue(text: "↕")
            .padding(.bottom, 6)
            .allowsHitTesting(false)
    }

    private var horizontalResizeCue: some View {
        WindowResizeCue(text: "↔")
            .padding(.trailing, 28)
            .allowsHitTesting(false)
    }

    private var diagonalResizeCue: some View {
        WindowResizeCue(text: "⤡")
            .padding(.trailing, 8)
            .padding(.bottom, 6)
            .allowsHitTesting(false)
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
            onBeginEditing: { beginEditing($0, adoptSelection: true) },
            onCommitEditor: commitEditorIfNeeded,
            onCancelEditor: cancelEditorIfNeeded,
            onToggleMarkdownPreview: toggleMarkdownPreview,
            onCopyRaw: { item in
                _ = onCopyRequest(item)
            },
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
            onBeginEditing: { beginEditing($0, adoptSelection: true) },
            onCommitEditor: commitEditorIfNeeded,
            onCancelEditor: cancelEditorIfNeeded,
            onToggleMarkdownPreview: toggleMarkdownPreview,
            onCopyRaw: { item in
                _ = onCopyRequest(item)
            },
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
        let willBePinned = !item.isPinned
        let before = currentPinStateSnapshot()
        _ = dataManager.setPinned(willBePinned, for: item.id)
        refreshItemsFromStore()
        let after = currentPinStateSnapshot()
        pushUndo(.pinTransition(before: before, after: after))
        showToast(willBePinned ? "Pinned" : "Unpinned")
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

    private func togglePinnedForFocusedItem() {
        guard let item = focusedItem() else { return }
        togglePinned(item)
    }

    private func deleteSelectedItem() {
        guard let selectedItemID else { return }
        commitActiveEditorIfNeeded()
        deleteItem(selectedItemID)
    }

    private func deleteFocusedItem() {
        guard let focusedItemID else { return }
        commitActiveEditorIfNeeded()
        deleteItem(focusedItemID)
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
        guard let item = actionableItem() else { return }
        if onCopyRequest(item) {
            showToast("Copied", style: .copy)
        }
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

    private func actionableItem() -> ClipboardItem? {
        if let focused = focusedItem() {
            return focused
        }
        return selectedItem()
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
        cachedHistoryItemIndexByID = Dictionary(uniqueKeysWithValues: historyItems.enumerated().map { ($0.element.id, $0.offset) })
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
            commitActiveEditorIfNeeded()
            beginEditing(item.id, adoptSelection: true)
        }
    }

    private func openEditorForFocusedItem() {
        guard let item = focusedItem(), item.type == .text else { return }
        if editingItemID == item.id {
            commitEditorIfNeeded(for: item.id)
        } else {
            commitActiveEditorIfNeeded()
            beginEditing(item.id, adoptSelection: false)
        }
    }

    private func applyTextTransformToSelectedItem(actionName: String, transform: (String) -> String) {
        guard editingItemID == nil,
              let item = actionableItem(),
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
        guard let item = actionableItem(),
              item.type == .text,
              let beforeText = dataManager.resolvedText(for: item) else {
            return
        }

        guard onCopyTextRequest(transform(beforeText), actionName) else {
            return
        }
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

    private func beginEditing(_ itemID: UUID, adoptSelection: Bool) {
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
        let scope = pinnedItemIDs.contains(itemID) ? SelectionScope.pinned : .history
        if adoptSelection {
            commitSelection(itemID, in: scope, shouldScroll: false)
        } else {
            focusItem(itemID, in: scope, shouldScroll: false)
        }
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
            .init(title: t("Normalize the focused item", "フォーカス中の項目を整形", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.copyNormalizedShortcut), symbolName: "terminal"),
            .init(title: t("Turn the focused item into one line", "フォーカス中の項目を一文化", language: settings.settingsLanguage), shortcut: HotKeyManager.displayString(for: settings.copyJoinedShortcut), symbolName: "link.circle")
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
            .init(
                title: t("Replace clipboard with normalized text", "クリップボード内容を整形して上書き", language: settings.settingsLanguage),
                shortcut: displayString(for: settings.globalCopyNormalizedShortcut, enabled: settings.globalCopyNormalizedEnabled, language: settings.settingsLanguage),
                symbolName: "terminal"
            ),
            .init(
                title: t("Replace clipboard with one-line text", "クリップボード内容を一文化して上書き", language: settings.settingsLanguage),
                shortcut: displayString(for: settings.globalCopyJoinedShortcut, enabled: settings.globalCopyJoinedEnabled, language: settings.settingsLanguage),
                symbolName: "link.circle"
            )
        ]
    }

    private static func displayString(for shortcut: HotKeyManager.Shortcut?, enabled: Bool, language: SettingsLanguage) -> String {
        guard enabled, let shortcut else { return t("Off", "オフ", language: language) }
        return HotKeyManager.displayString(for: shortcut)
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
                    helpSection(title: t("Global Clipboard Commands", "グローバルのクリップボード操作"), commands: copyCommands)
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
            MarkdownWebPreview(markdown: source, fontScale: 0.84, scrollProgress: nil, scrollRequestID: 0)
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
        case fileBackedMarkdown
        case fileBackedText
    }

    private enum RightPaneMode {
        case none
        case preview
        case history
    }

    struct LocalHistoryEntryBadge {
        let title: String
        let tint: Color
    }

    private static let markdownPreviewSidebarWidth: CGFloat = 260
    private static let markdownPreviewSidebarMinWidth: CGFloat = 180
    private static let markdownPreviewSidebarMaxWidth: CGFloat = 520
    private static let initialHistorySummaryRequestLimit = 20
    private static let localHistoryComputationQueue = DispatchQueue(
        label: "ClipboardHistory.StandaloneNoteEditorView.LocalHistoryComputation",
        qos: .userInitiated
    )

    let initialText: String
    @ObservedObject var appDelegate: AppDelegate
    @ObservedObject var saveStatusState: AppDelegate.EditorSaveStatusState
    let codexContext: AppDelegate.CodexDraftContext?
    let commitMode: CommitMode
    let initialMarkdownPreviewVisible: Bool
    let initialHistoryVisible: Bool
    let onDraftChange: (String) -> Void
    let onCommit: (String) -> Void
    let onSave: () -> Void
    let onSaveAs: () -> Void
    let onClose: () -> Void
    let onMarkdownPreviewVisibilityChanged: (Bool) -> Void
    let onHistoryPaneVisibilityChanged: (Bool) -> Void
    let onDiscardOrphanCodex: (() -> Void)?

    init(
        initialText: String,
        appDelegate: AppDelegate,
        saveStatusState: AppDelegate.EditorSaveStatusState,
        codexContext: AppDelegate.CodexDraftContext?,
        commitMode: CommitMode,
        initialMarkdownPreviewVisible: Bool,
        initialHistoryVisible: Bool = false,
        onDraftChange: @escaping (String) -> Void,
        onCommit: @escaping (String) -> Void,
        onSave: @escaping () -> Void,
        onSaveAs: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onMarkdownPreviewVisibilityChanged: @escaping (Bool) -> Void,
        onHistoryPaneVisibilityChanged: @escaping (Bool) -> Void = { _ in },
        onDiscardOrphanCodex: (() -> Void)?
    ) {
        self.initialText = initialText
        self.appDelegate = appDelegate
        self.saveStatusState = saveStatusState
        self.codexContext = codexContext
        self.commitMode = commitMode
        self.initialMarkdownPreviewVisible = initialMarkdownPreviewVisible
        self.initialHistoryVisible = initialHistoryVisible
        self.onDraftChange = onDraftChange
        self.onCommit = onCommit
        self.onSave = onSave
        self.onSaveAs = onSaveAs
        self.onClose = onClose
        self.onMarkdownPreviewVisibilityChanged = onMarkdownPreviewVisibilityChanged
        self.onHistoryPaneVisibilityChanged = onHistoryPaneVisibilityChanged
        self.onDiscardOrphanCodex = onDiscardOrphanCodex
    }

    @State private var draftText = ""
    @State private var committedText = ""
    @State private var rightPaneMode: RightPaneMode = .none
    @State private var markdownPreviewWidth: CGFloat = 0
    @State private var historyEntries: [FileLocalHistoryManager.SnapshotEntry] = []
    @State private var selectedHistoryEntryID: String?
    @State private var historyDiffSummaries: [String: LocalHistoryDiffEngine.Summary] = [:]
    @State private var selectedHistoryDiff: LocalHistoryDiffEngine.Result?
    @State private var selectedHistoryDiffEntryID: String?
    @State private var historySnapshotTextCache: [String: String] = [:]
    @State private var pendingHistorySummaryEntryIDs: Set<String> = []
    @State private var visibleHistoryEntryIDs: Set<String> = []
    @State private var localHistoryTrackingInfoState: FileLocalHistoryManager.TrackingInfo?
    @State private var currentDraftHashState = ""
    @State private var lastPersistedHashState: String?
    @State private var historyComputationRevision = 0

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

    private var supportsMarkdownPreview: Bool {
        commitMode != .fileBackedText
    }

    private var supportsLocalHistory: Bool {
        commitMode == .fileBackedMarkdown || commitMode == .fileBackedText
    }

    private var isRightPaneVisible: Bool {
        switch rightPaneMode {
        case .none:
            return false
        case .preview:
            return supportsMarkdownPreview
        case .history:
            return supportsLocalHistory
        }
    }

    private var isDirty: Bool {
        _ = saveStatusState.saveRevision
        return draftText != saveStatusState.lastPersistedText
    }

    private var saveStatusText: String {
        if isDirty {
            return t("Unsaved", "未保存")
        }
        switch saveStatusState.lastSaveDestination {
        case .clipboard:
            return t("Saved to Clipboard", "クリップボード保存済み")
        case .file:
            return t("Saved", "保存済み")
        case .none:
            return t("Unsaved", "未保存")
        }
    }

    private var saveStatusIcon: String {
        if isDirty {
            return "circle.fill"
        }
        switch saveStatusState.lastSaveDestination {
        case .clipboard:
            return "doc.on.clipboard"
        case .file:
            return "checkmark.circle.fill"
        case .none:
            return "circle.fill"
        }
    }

    private var saveStatusColor: Color {
        if isDirty {
            return .orange
        }
        switch saveStatusState.lastSaveDestination {
        case .clipboard:
            return Color(red: 0.77, green: 0.60, blue: 0.14)
        case .file:
            return Color(red: 0.22, green: 0.67, blue: 0.34)
        case .none:
            return .orange
        }
    }

    private var historyAccentColor: Color {
        Color(red: 0.18, green: 0.49, blue: 0.94)
    }

    private var localHistoryTrackingInfo: FileLocalHistoryManager.TrackingInfo? {
        localHistoryTrackingInfoState
    }

    private var localHistoryStatusTitle: String {
        if !appDelegate.settings.localFileHistoryEnabled {
            return t("History Off", "履歴オフ")
        }
        if let info = localHistoryTrackingInfo, info.isTracked {
            return t("Tracked", "追跡中")
        }
        return t("Untracked", "未追跡")
    }

    private var localHistoryStatusDetail: String {
        if !appDelegate.settings.localFileHistoryEnabled {
            return t("Disabled in Settings", "設定で無効")
        }

        switch commitMode {
        case .fileBackedMarkdown, .fileBackedText:
            guard let info = localHistoryTrackingInfo else {
                return t("Save as file to track", "ファイル保存で追跡開始")
            }
            switch (info.isTrackedByOpenedFile, info.isTrackedByWatchedDirectory) {
            case (true, true):
                return t("Opened here + Watched", "このアプリ + 監視")
            case (true, false):
                return t("Opened here", "このアプリで開いた")
            case (false, true):
                return t("Watched directory", "監視ディレクトリ")
            case (false, false):
                if info.historyEntryCount > 0 {
                    return t("Existing snapshots only", "既存履歴のみ")
                }
                return t("Outside tracked scope", "追跡対象外")
            }
        case .pasteToTarget, .returnToCodex, .orphanedCodex:
            return t("Save as file to track", "ファイル保存で追跡開始")
        }
    }

    private var localHistoryStatusColor: Color {
        if !appDelegate.settings.localFileHistoryEnabled {
            return theme.secondaryText
        }
        if localHistoryTrackingInfo?.isTracked == true {
            return historyAccentColor
        }
        return Color(red: 0.80, green: 0.54, blue: 0.18)
    }

    private var localHistoryEmptyTitle: String {
        if !appDelegate.settings.localFileHistoryEnabled {
            return t("Local history is disabled", "ローカル履歴は無効です")
        }
        if localHistoryTrackingInfo?.isTracked == false {
            return t("This file is currently untracked", "このファイルは現在未追跡です")
        }
        return t("No local history yet", "まだローカル履歴がありません")
    }

    private var localHistoryEmptyMessage: String {
        if !appDelegate.settings.localFileHistoryEnabled {
            return t(
                "Enable file local history in Settings to start collecting snapshots.",
                "設定でファイルのローカル履歴を有効にすると、スナップショットの収集が始まります。"
            )
        }
        switch commitMode {
        case .fileBackedMarkdown, .fileBackedText:
            guard let info = localHistoryTrackingInfo else {
                return t(
                    "Save this document to a real file path to start collecting snapshots.",
                    "この文書を実ファイルとして保存すると、スナップショットの収集が始まります。"
                )
            }
            if info.isTracked {
                return t(
                    "This file is tracked. Save or reopen it once to create the first snapshot.",
                    "このファイルは追跡対象です。一度保存するか再オープンすると最初のスナップショットが作成されます。"
                )
            }
            return t(
                "This file is outside the current tracking scope. Open it here with opened-file tracking enabled, or move it under the watched directory with a matching extension.",
                "このファイルは現在の追跡対象外です。「ClipboardHistory で開いたファイルも追跡」を有効にするか、監視ディレクトリ配下の対象拡張子に置くと追跡されます。"
            )
        case .pasteToTarget, .returnToCodex, .orphanedCodex:
            return t(
                "Local history starts after this draft is saved as a real file.",
                "ローカル履歴は、この下書きを実ファイルとして保存した後に始まります。"
            )
        }
    }

    private var rightPaneTitle: String {
        switch rightPaneMode {
        case .none:
            return t("Local History", "ローカル履歴")
        case .history:
            if selectedHistoryEntry != nil {
                return t("History Diff", "履歴差分")
            }
            return t("Local History", "ローカル履歴")
        case .preview:
            return t("Markdown Preview", "Markdown プレビュー")
        }
    }

    private var rightPaneSummary: String {
        switch rightPaneMode {
        case .preview:
            return t("Live preview of the current draft", "現在の下書きのライブプレビュー")
        case .none:
            if isDirty {
                return t("Draft has unsaved changes", "下書きに未保存の変更があります")
            }
            return t("Latest saved snapshot matches the current draft", "最新の保存スナップショットが現在の下書きと一致しています")
        case .history:
            if let selectedHistoryEntry {
                if resolvedSelectedHistoryDiff?.isUnavailable == true {
                    return t("Snapshot content is unavailable", "スナップショット内容を読み込めませんでした")
                }
                let summary = resolvedSelectedHistoryDiff?.summary ?? historyDiffSummary(for: selectedHistoryEntry)
                if let summary {
                    return "\(Self.localizedTimestampFormatter.string(from: selectedHistoryEntry.createdAt))  +\(summary.additions) / -\(summary.removals)"
                }
                return Self.localizedTimestampFormatter.string(from: selectedHistoryEntry.createdAt)
            }
            if historyEntries.isEmpty {
                return localHistoryStatusDetail
            }
            return t("Select a snapshot to open its diff", "スナップショットを選んで差分を開きます")
        }
    }

    private static let localizedTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var selectedHistoryEntry: FileLocalHistoryManager.SnapshotEntry? {
        guard let selectedHistoryEntryID else { return nil }
        return historyEntries.first { $0.id == selectedHistoryEntryID }
    }

    private var resolvedSelectedHistoryDiff: LocalHistoryDiffEngine.Result? {
        guard selectedHistoryDiffEntryID == selectedHistoryEntryID else { return nil }
        return selectedHistoryDiff
    }

    private var isShowingHistoryDiff: Bool {
        rightPaneMode == .history && selectedHistoryEntry != nil
    }

    private var currentDraftHash: String {
        currentDraftHashState
    }

    private var lastPersistedHash: String? {
        lastPersistedHashState
    }

    private var resolvedMarkdownPreviewWidth: CGFloat {
        let fallback = scaled(Self.markdownPreviewSidebarWidth)
        let currentWidth = markdownPreviewWidth > 0 ? markdownPreviewWidth : fallback
        return min(
            max(currentWidth, scaled(Self.markdownPreviewSidebarMinWidth)),
            scaled(Self.markdownPreviewSidebarMaxWidth)
        )
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
        .onAppear {
            loadCurrentText()
            refreshLocalHistoryTrackingInfo()
            refreshLocalHistorySelection(preserveSelection: false)
            if initialHistoryVisible && supportsLocalHistory {
                rightPaneMode = .history
            } else {
                rightPaneMode = initialMarkdownPreviewVisible && supportsMarkdownPreview ? .preview : .none
            }
            onMarkdownPreviewVisibilityChanged(rightPaneMode == .preview)
            onHistoryPaneVisibilityChanged(rightPaneMode == .history)
            if markdownPreviewWidth == 0 {
                markdownPreviewWidth = scaled(Self.markdownPreviewSidebarWidth)
            }
            refreshLocalHistoryDiffState()
        }
        .onChange(of: draftText) { _, newValue in
            onDraftChange(newValue)
            refreshLocalHistoryHashes()
            guard rightPaneMode == .history else { return }
            invalidateHistoryDiffWork(clearSnapshotCache: false)
            if selectedHistoryEntryID != nil {
                requestSelectedLocalHistoryDiff()
            } else {
                requestVisibleLocalHistorySummaries()
            }
        }
        .onChange(of: rightPaneMode) { _, newValue in
            if newValue == .history {
                refreshLocalHistorySelection(preserveSelection: true)
                refreshLocalHistoryDiffState()
            } else {
                clearLocalHistoryDiffState()
            }
            onMarkdownPreviewVisibilityChanged(newValue == .preview)
            onHistoryPaneVisibilityChanged(newValue == .history)
        }
        .onChange(of: saveStatusState.saveRevision) { _, _ in
            refreshLocalHistoryHashes()
            refreshLocalHistoryTrackingInfo()
            refreshLocalHistorySelection(preserveSelection: true)
            if rightPaneMode == .history {
                refreshLocalHistoryDiffState()
            }
        }
        .onChange(of: appDelegate.settings) { _, _ in
            guard supportsLocalHistory else { return }
            refreshLocalHistoryTrackingInfo()
            refreshLocalHistorySelection(preserveSelection: true)
            if rightPaneMode == .history {
                refreshLocalHistoryDiffState()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fileLocalHistoryDidChange)) { notification in
            guard supportsLocalHistory else { return }
            if let changedFileURL = notification.userInfo?["fileURL"] as? URL,
               let currentFileURL = appDelegate.currentEditorLocalHistoryFileURLForUI(),
               changedFileURL.standardizedFileURL != currentFileURL.standardizedFileURL {
                return
            }
            refreshLocalHistoryTrackingInfo()
            refreshLocalHistorySelection(preserveSelection: true)
            if rightPaneMode == .history {
                refreshLocalHistoryDiffState()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorViewValidationRequested)) { notification in
            guard let action = notification.userInfo?["action"] as? String else { return }
            switch action {
            case "setPreviewWidth":
                guard let rawValue = notification.userInfo?["value"] as? Double else { return }
                markdownPreviewWidth = CGFloat(rawValue)
            default:
                break
            }
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
            if commitMode == .fileBackedMarkdown || commitMode == .fileBackedText {
                ShortcutHintView(
                    icon: "square.and.arrow.down",
                    label: t("Save", "保存"),
                    key: "⌘S",
                    zoomScale: zoomScale,
                    primaryTextColor: theme.primaryText,
                    secondaryTextColor: theme.secondaryText
                )
                ShortcutHintView(
                    icon: "square.and.arrow.down.on.square",
                    label: t("Save As", "別名で保存"),
                    key: "⌘⇧S",
                    zoomScale: zoomScale,
                    primaryTextColor: theme.primaryText,
                    secondaryTextColor: theme.secondaryText
                )
            }
            Spacer(minLength: 0)
            localHistoryStatusPill
            saveStatusPill
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
            if supportsMarkdownPreview {
                ShortcutHintView(
                    icon: "doc.richtext",
                    label: t("Markdown Preview", "Markdown プレビュー"),
                    key: HotKeyManager.displayString(for: appDelegate.settings.toggleMarkdownPreviewShortcut),
                    zoomScale: zoomScale,
                    primaryTextColor: theme.primaryText,
                    secondaryTextColor: theme.secondaryText
                )
            }
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

    @ViewBuilder
    private var localHistoryStatusPill: some View {
        HStack(spacing: 6) {
            Image(systemName: localHistoryTrackingInfo?.isTracked == true ? "clock.arrow.trianglehead.counterclockwise.rotate.90" : "clock.badge.xmark")
                .font(.system(size: scaled(9), weight: .semibold))
            Text(localHistoryStatusTitle)
                .font(.system(size: scaled(10.5), weight: .semibold))
            Text(localHistoryStatusDetail)
                .font(.system(size: scaled(9.5), weight: .medium))
                .foregroundStyle(theme.secondaryText)
        }
        .foregroundStyle(localHistoryStatusColor)
        .padding(.horizontal, scaled(8))
        .padding(.vertical, scaled(4))
        .background(theme.hintFill)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder
    private var saveStatusPill: some View {
        let content = HStack(spacing: 8) {
            Image(systemName: saveStatusIcon)
                .font(.system(size: scaled(9), weight: .semibold))
            Text(saveStatusText)
                .font(.system(size: scaled(10.5), weight: .semibold))
            if supportsLocalHistory {
                HStack(spacing: 4) {
                    Circle()
                        .fill(historyAccentColor)
                        .frame(width: scaled(5.5), height: scaled(5.5))
                    Text("\(historyEntries.count)")
                        .font(.system(size: scaled(10), weight: .semibold))
                        .foregroundStyle(historyAccentColor)
                }
            }
        }
        .foregroundStyle(saveStatusColor)
        .padding(.horizontal, scaled(8))
        .padding(.vertical, scaled(4))
        .background(theme.hintFill)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(
                    supportsLocalHistory && rightPaneMode == .history
                        ? historyAccentColor.opacity(0.42)
                        : Color.clear,
                    lineWidth: 0.8
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))

        if supportsLocalHistory {
            Button(action: toggleHistoryPane) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    @ViewBuilder
    private var rightPaneContent: some View {
        switch rightPaneMode {
        case .none:
            EmptyView()
        case .preview:
            MarkdownPreviewSidebar(
                title: nil,
                markdown: draftText,
                width: resolvedMarkdownPreviewWidth,
                minHeight: scaled(180),
                fontScale: zoomScale,
                scrollProgress: nil,
                scrollRequestID: 0
            )
        case .history:
            LocalHistorySidebar(
                entries: historyEntries,
                selectedEntryID: selectedHistoryEntryID,
                selectedDiff: resolvedSelectedHistoryDiff,
                width: resolvedMarkdownPreviewWidth,
                minHeight: scaled(180),
                fontScale: zoomScale,
                theme: theme,
                emptyTitle: localHistoryEmptyTitle,
                emptyMessage: localHistoryEmptyMessage,
                openFolderLabel: t("Open Folder", "フォルダを開く"),
                currentDraftLabel: t("Current Draft", "現在の下書き"),
                diffIdenticalLabel: t("Selected snapshot matches the current draft.", "選択したスナップショットは現在の下書きと同一です。"),
                diffLoadingLabel: t("Loading snapshot diff…", "差分を読み込み中…"),
                diffUnavailableLabel: t("Snapshot content is unavailable.", "スナップショット内容を読み込めませんでした。"),
                diffTruncatedLabel: t("This diff is too large to render inline. Restore it or open the history folder if needed.", "差分が大きいためインライン表示を省略しました。必要なら復元するか履歴フォルダを開いてください。"),
                onSelectEntry: selectLocalHistoryEntry,
                onOpenFolder: {
                    appDelegate.revealLocalHistoryForCurrentEditor()
                },
                onAppearEntry: historyEntryDidAppear(_:),
                onDisappearEntry: historyEntryDidDisappear(_:),
                badgeProvider: historyBadge(for:),
                diffSummaryProvider: historyDiffSummary(for:)
            )
        }
    }

    private var editorBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if commitMode == .orphanedCodex {
                orphanedCodexBanner
            }

            if rightPaneMode == .history {
                HStack(spacing: 10) {
                    Text(rightPaneTitle)
                        .font(.system(size: scaled(11), weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(rightPaneSummary)
                        .font(.system(size: scaled(9.5), weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 6)

                    if isShowingHistoryDiff {
                        Button {
                            selectedHistoryEntryID = nil
                            selectedHistoryDiff = nil
                            selectedHistoryDiffEntryID = nil
                            requestVisibleLocalHistorySummaries()
                        } label: {
                            Label(t("Back to List", "一覧へ戻る"), systemImage: "chevron.left")
                                .font(.system(size: scaled(9.5), weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                    }

                    if isShowingHistoryDiff {
                        Button(role: .destructive) {
                            deleteSelectedLocalHistoryEntry()
                        } label: {
                            Label(t("Delete Snapshot", "この履歴を削除"), systemImage: "trash")
                                .font(.system(size: scaled(9.5), weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        appDelegate.revealLocalHistoryForCurrentEditor()
                    } label: {
                        Label(t("Open Folder", "フォルダを開く"), systemImage: "folder")
                            .font(.system(size: scaled(9.5), weight: .semibold))
                    }
                    .buttonStyle(.bordered)

                    if isShowingHistoryDiff {
                        Button {
                            restoreSelectedLocalHistoryEntry()
                        } label: {
                            Label(t("Restore to Draft", "下書きへ復元"), systemImage: "arrow.uturn.backward")
                                .font(.system(size: scaled(9.5), weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if !historyEntries.isEmpty {
                        Button(role: .destructive) {
                            deleteAllLocalHistory()
                        } label: {
                            Label(t("Delete All", "履歴を全削除"), systemImage: "trash.slash")
                                .font(.system(size: scaled(9.5), weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        rightPaneMode = .none
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: scaled(11), weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else if isRightPaneVisible {
                HStack {
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rightPaneTitle)
                                    .font(.system(size: scaled(11), weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text(rightPaneSummary)
                                    .font(.system(size: scaled(9.5), weight: .medium))
                                    .foregroundStyle(theme.secondaryText)
                            }
                            Spacer(minLength: 6)
                            Button {
                                rightPaneMode = .none
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: scaled(11), weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: resolvedMarkdownPreviewWidth, alignment: .leading)
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
                    onSave: onSave,
                    onSaveAs: onSaveAs,
                    onDiscardOrphanCodex: onDiscardOrphanCodex,
                    onToggleMarkdownPreview: toggleMarkdownPreview,
                    onToggleHelp: {},
                    onZoomIn: { appDelegate.increaseInterfaceZoom() },
                    onZoomOut: { appDelegate.decreaseInterfaceZoom() },
                    onResetZoom: { appDelegate.resetInterfaceZoom() },
                    onSelectionChange: { _ in }
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

                if isRightPaneVisible {
                    MarkdownPreviewResizeHandle { delta in
                        markdownPreviewWidth = min(
                            max(resolvedMarkdownPreviewWidth - delta, scaled(Self.markdownPreviewSidebarMinWidth)),
                            scaled(Self.markdownPreviewSidebarMaxWidth)
                        )
                    }

                    rightPaneContent
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
                    "The Codex-side connection was lost unexpectedly. You can keep editing, then copy to clipboard or discard this draft.",
                    "Codex 側との接続が想定外に切れました。編集は継続できます。内容をクリップボードへ保存するか、この下書きを削除してください。"
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
        case .fileBackedMarkdown, .fileBackedText:
            EmptyView()
        }
    }

    private func loadCurrentText() {
        let text = initialText
        committedText = text
        draftText = text
        onDraftChange(text)
        refreshLocalHistoryHashes()
    }

    private func commitDraft() {
        committedText = draftText
        onCommit(draftText)
    }

    private func cancelAndClose() {
        guard commitMode != .orphanedCodex else { return }
        onClose()
    }

    private func toggleHistoryPane() {
        guard supportsLocalHistory else { return }
        if rightPaneMode == .history {
            rightPaneMode = .none
            return
        }
        refreshLocalHistorySelection(preserveSelection: false)
        rightPaneMode = .history
    }

    private func toggleMarkdownPreview() {
        guard supportsMarkdownPreview else { return }
        rightPaneMode = rightPaneMode == .preview ? .none : .preview
    }

    private func refreshLocalHistorySelection(preserveSelection: Bool) {
        guard supportsLocalHistory else {
            localHistoryTrackingInfoState = nil
            historyEntries = []
            selectedHistoryEntryID = nil
            clearLocalHistoryDiffState()
            return
        }

        refreshLocalHistoryTrackingInfo()
        let entries = appDelegate.currentEditorLocalHistoryEntries()
        historyEntries = entries
        synchronizeLocalHistoryCaches(with: entries)

        guard !entries.isEmpty else {
            selectedHistoryEntryID = nil
            clearLocalHistoryDiffState()
            return
        }

        if preserveSelection,
           let selectedHistoryEntryID,
           entries.contains(where: { $0.id == selectedHistoryEntryID }) {
            return
        }

        selectedHistoryEntryID = nil
    }

    private func selectLocalHistoryEntry(_ entry: FileLocalHistoryManager.SnapshotEntry) {
        selectedHistoryEntryID = entry.id
        selectedHistoryDiff = nil
        selectedHistoryDiffEntryID = nil
        requestSelectedLocalHistoryDiff()
    }

    private func restoreSelectedLocalHistoryEntry() {
        guard let selectedHistoryEntry,
              let snapshotText = cachedLocalHistorySnapshotText(for: selectedHistoryEntry) else { return }
        draftText = snapshotText
    }

    private func deleteSelectedLocalHistoryEntry() {
        guard let selectedHistoryEntry else { return }
        guard appDelegate.deleteCurrentEditorLocalHistoryEntry(selectedHistoryEntry) else { return }
        selectedHistoryEntryID = nil
        refreshLocalHistorySelection(preserveSelection: false)
        clearLocalHistoryDiffState()
    }

    private func deleteAllLocalHistory() {
        guard appDelegate.deleteAllCurrentEditorLocalHistory() else { return }
        selectedHistoryEntryID = nil
        refreshLocalHistorySelection(preserveSelection: false)
        clearLocalHistoryDiffState()
    }

    private func clearLocalHistoryDiffState() {
        historyComputationRevision += 1
        historyDiffSummaries = [:]
        selectedHistoryDiff = nil
        selectedHistoryDiffEntryID = nil
        historySnapshotTextCache = [:]
        pendingHistorySummaryEntryIDs = []
    }

    private func refreshLocalHistoryDiffState() {
        guard supportsLocalHistory, rightPaneMode == .history else {
            clearLocalHistoryDiffState()
            return
        }

        invalidateHistoryDiffWork(clearSnapshotCache: false)
        requestVisibleLocalHistorySummaries()
        requestSelectedLocalHistoryDiff()
    }

    private func refreshLocalHistoryTrackingInfo() {
        localHistoryTrackingInfoState = appDelegate.currentEditorLocalHistoryTrackingInfo()
    }

    private func refreshLocalHistoryHashes() {
        currentDraftHashState = sha256Hex(for: draftText)
        if !saveStatusState.lastPersistedText.isEmpty || saveStatusState.lastSaveDestination != nil {
            lastPersistedHashState = sha256Hex(for: saveStatusState.lastPersistedText)
        } else {
            lastPersistedHashState = nil
        }
    }

    private func invalidateHistoryDiffWork(clearSnapshotCache: Bool) {
        historyComputationRevision += 1
        historyDiffSummaries = [:]
        pendingHistorySummaryEntryIDs = []
        selectedHistoryDiff = nil
        selectedHistoryDiffEntryID = nil
        if clearSnapshotCache {
            historySnapshotTextCache = [:]
        }
    }

    private func requestInitialLocalHistorySummaries() {
        for entry in historyEntries.prefix(Self.initialHistorySummaryRequestLimit) {
            requestHistorySummary(for: entry)
        }
    }

    private func requestVisibleLocalHistorySummaries() {
        let visibleEntries = historyEntries.filter { visibleHistoryEntryIDs.contains($0.id) }
        if visibleEntries.isEmpty {
            requestInitialLocalHistorySummaries()
            return
        }

        for entry in visibleEntries {
            requestHistorySummary(for: entry)
        }
    }

    private func requestHistorySummary(for entry: FileLocalHistoryManager.SnapshotEntry) {
        guard supportsLocalHistory, rightPaneMode == .history else { return }
        guard historyDiffSummaries[entry.id] == nil, !pendingHistorySummaryEntryIDs.contains(entry.id) else { return }

        let revision = historyComputationRevision
        let snapshotCache = historySnapshotTextCache
        let currentText = draftText
        let currentHash = currentDraftHash
        pendingHistorySummaryEntryIDs.insert(entry.id)

        Self.localHistoryComputationQueue.async { [appDelegate] in
            let resolved = Self.resolveLocalHistorySnapshotText(
                entry: entry,
                snapshotCache: snapshotCache,
                appDelegate: appDelegate
            )
            let result = Self.computeLocalHistoryDiff(
                entry: entry,
                currentDraftHash: currentHash,
                currentText: currentText,
                snapshotText: resolved
            )
            DispatchQueue.main.async {
                guard revision == historyComputationRevision else { return }
                pendingHistorySummaryEntryIDs.remove(entry.id)
                if let resolved {
                    historySnapshotTextCache[entry.id] = resolved
                }
                guard historyEntries.contains(where: { $0.id == entry.id }) else { return }
                if !result.isUnavailable {
                    historyDiffSummaries[entry.id] = result.summary
                }
            }
        }
    }

    private func requestSelectedLocalHistoryDiff() {
        guard supportsLocalHistory, rightPaneMode == .history, let selectedHistoryEntry else {
            selectedHistoryDiff = nil
            selectedHistoryDiffEntryID = nil
            return
        }

        selectedHistoryDiff = nil
        selectedHistoryDiffEntryID = nil
        let revision = historyComputationRevision
        let selectedEntryID = selectedHistoryEntry.id
        let snapshotCache = historySnapshotTextCache
        let currentText = draftText
        let currentHash = currentDraftHash

        Self.localHistoryComputationQueue.async { [appDelegate] in
            let resolved = Self.resolveLocalHistorySnapshotText(
                entry: selectedHistoryEntry,
                snapshotCache: snapshotCache,
                appDelegate: appDelegate
            )
            let result = Self.computeLocalHistoryDiff(
                entry: selectedHistoryEntry,
                currentDraftHash: currentHash,
                currentText: currentText,
                snapshotText: resolved
            )
            DispatchQueue.main.async {
                guard revision == historyComputationRevision else { return }
                guard self.selectedHistoryEntryID == selectedEntryID else { return }
                if let resolved {
                    historySnapshotTextCache[selectedEntryID] = resolved
                }
                selectedHistoryDiff = result
                selectedHistoryDiffEntryID = selectedEntryID
                if !result.isUnavailable {
                    historyDiffSummaries[selectedEntryID] = result.summary
                }
            }
        }
    }

    private func localHistoryDiffResult(for entry: FileLocalHistoryManager.SnapshotEntry) -> LocalHistoryDiffEngine.Result {
        Self.computeLocalHistoryDiff(
            entry: entry,
            currentDraftHash: currentDraftHash,
            currentText: draftText,
            snapshotText: cachedLocalHistorySnapshotText(for: entry)
        )
    }

    private func historyDiffSummary(for entry: FileLocalHistoryManager.SnapshotEntry) -> LocalHistoryDiffEngine.Summary? {
        historyDiffSummaries[entry.id]
    }

    private func cachedLocalHistorySnapshotText(for entry: FileLocalHistoryManager.SnapshotEntry) -> String? {
        if let cached = historySnapshotTextCache[entry.id] {
            return cached
        }

        guard let snapshotText = Self.resolveLocalHistorySnapshotText(
            entry: entry,
            snapshotCache: historySnapshotTextCache,
            appDelegate: appDelegate
        ) else {
            return nil
        }

        historySnapshotTextCache[entry.id] = snapshotText
        return snapshotText
    }

    private func synchronizeLocalHistoryCaches(with entries: [FileLocalHistoryManager.SnapshotEntry]) {
        let validEntryIDs = Set(entries.map(\.id))
        historyDiffSummaries = historyDiffSummaries.filter { validEntryIDs.contains($0.key) }
        historySnapshotTextCache = historySnapshotTextCache.filter { validEntryIDs.contains($0.key) }
        pendingHistorySummaryEntryIDs = Set(pendingHistorySummaryEntryIDs.filter { validEntryIDs.contains($0) })
        visibleHistoryEntryIDs = Set(visibleHistoryEntryIDs.filter { validEntryIDs.contains($0) })
        if let selectedHistoryDiffEntryID, !validEntryIDs.contains(selectedHistoryDiffEntryID) {
            selectedHistoryDiff = nil
            self.selectedHistoryDiffEntryID = nil
        }
    }

    private func historyEntryDidAppear(_ entry: FileLocalHistoryManager.SnapshotEntry) {
        visibleHistoryEntryIDs.insert(entry.id)
        requestHistorySummary(for: entry)
    }

    private func historyEntryDidDisappear(_ entry: FileLocalHistoryManager.SnapshotEntry) {
        visibleHistoryEntryIDs.remove(entry.id)
    }

    private func historyBadge(for entry: FileLocalHistoryManager.SnapshotEntry) -> LocalHistoryEntryBadge? {
        if entry.contentHash == currentDraftHash {
            return LocalHistoryEntryBadge(
                title: t("Current", "現在"),
                tint: historyAccentColor
            )
        }

        if let lastPersistedHash, entry.contentHash == lastPersistedHash {
            return LocalHistoryEntryBadge(
                title: t("Saved", "保存済み"),
                tint: Color(red: 0.22, green: 0.67, blue: 0.34)
            )
        }

        if historyEntries.first?.id == entry.id {
            return LocalHistoryEntryBadge(
                title: t("Latest", "最新"),
                tint: Color(red: 0.35, green: 0.40, blue: 0.48)
            )
        }

        return nil
    }

    private func sha256Hex(for text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func resolveLocalHistorySnapshotText(
        entry: FileLocalHistoryManager.SnapshotEntry,
        snapshotCache: [String: String],
        appDelegate: AppDelegate
    ) -> String? {
        if let cached = snapshotCache[entry.id] {
            return cached
        }
        return appDelegate.currentEditorLocalHistoryText(for: entry)
    }

    private static func computeLocalHistoryDiff(
        entry: FileLocalHistoryManager.SnapshotEntry,
        currentDraftHash: String,
        currentText: String,
        snapshotText: String?
    ) -> LocalHistoryDiffEngine.Result {
        if entry.contentHash == currentDraftHash {
            return .identical
        }

        guard let snapshotText else {
            return .unavailable
        }

        return LocalHistoryDiffEngine.compare(snapshotText: snapshotText, currentText: currentText)
    }

    private func t(_ english: String, _ japanese: String) -> String {
        appDelegate.settings.settingsLanguage == .japanese ? japanese : english
    }
}

struct LocalHistoryDiffEngine {
    struct Summary: Equatable {
        let additions: Int
        let removals: Int

        static let zero = Summary(additions: 0, removals: 0)

        var hasChanges: Bool {
            additions > 0 || removals > 0
        }
    }

    enum LineKind: Equatable {
        case unchanged
        case added
        case removed
    }

    struct Line: Equatable, Identifiable {
        let id: Int
        let kind: LineKind
        let oldLineNumber: Int?
        let newLineNumber: Int?
        let text: String
    }

    struct Result: Equatable {
        let summary: Summary
        let lines: [Line]
        let isTruncated: Bool
        let isUnavailable: Bool

        static let identical = Result(summary: .zero, lines: [], isTruncated: false, isUnavailable: false)
        static let unavailable = Result(summary: .zero, lines: [], isTruncated: false, isUnavailable: true)
    }

    static func compare(
        snapshotText: String,
        currentText: String,
        maximumComparableLines: Int = 400,
        maximumCellCount: Int = 160_000
    ) -> Result {
        let snapshotLines = normalizedLines(in: snapshotText)
        let currentLines = normalizedLines(in: currentText)

        if snapshotLines == currentLines {
            return .identical
        }

        let comparableLineCount = max(snapshotLines.count, currentLines.count)
        let cellCount = snapshotLines.count * currentLines.count
        if comparableLineCount > maximumComparableLines || cellCount > maximumCellCount {
            let fallbackDifference = Array(currentLines.difference(from: snapshotLines))
            return Result(
                summary: Summary(
                    additions: fallbackDifference.reduce(into: 0) { count, change in
                        if case .insert = change { count += 1 }
                    },
                    removals: fallbackDifference.reduce(into: 0) { count, change in
                        if case .remove = change { count += 1 }
                    }
                ),
                lines: [],
                isTruncated: true,
                isUnavailable: false
            )
        }

        let table = lcsTable(snapshotLines: snapshotLines, currentLines: currentLines)
        var lines: [Line] = []
        var snapshotIndex = 0
        var currentIndex = 0
        var nextID = 0
        var additions = 0
        var removals = 0

        while snapshotIndex < snapshotLines.count || currentIndex < currentLines.count {
            if snapshotIndex < snapshotLines.count,
               currentIndex < currentLines.count,
               snapshotLines[snapshotIndex] == currentLines[currentIndex] {
                lines.append(
                    Line(
                        id: nextID,
                        kind: .unchanged,
                        oldLineNumber: snapshotIndex + 1,
                        newLineNumber: currentIndex + 1,
                        text: snapshotLines[snapshotIndex]
                    )
                )
                snapshotIndex += 1
                currentIndex += 1
                nextID += 1
                continue
            }

            let preferInsertion =
                currentIndex < currentLines.count &&
                (snapshotIndex == snapshotLines.count || table[snapshotIndex][currentIndex + 1] > table[snapshotIndex + 1][currentIndex])

            if preferInsertion {
                lines.append(
                    Line(
                        id: nextID,
                        kind: .added,
                        oldLineNumber: nil,
                        newLineNumber: currentIndex + 1,
                        text: currentLines[currentIndex]
                    )
                )
                currentIndex += 1
                additions += 1
            } else if snapshotIndex < snapshotLines.count {
                lines.append(
                    Line(
                        id: nextID,
                        kind: .removed,
                        oldLineNumber: snapshotIndex + 1,
                        newLineNumber: nil,
                        text: snapshotLines[snapshotIndex]
                    )
                )
                snapshotIndex += 1
                removals += 1
            }
            nextID += 1
        }

        return Result(
            summary: Summary(additions: additions, removals: removals),
            lines: lines,
            isTruncated: false,
            isUnavailable: false
        )
    }

    static func normalizedLines(in text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !normalized.isEmpty else {
            return []
        }
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if normalized.hasSuffix("\n"), lines.last == "" {
            lines.removeLast()
        }
        return lines
    }

    private static func lcsTable(snapshotLines: [String], currentLines: [String]) -> [[Int]] {
        var table = Array(
            repeating: Array(repeating: 0, count: currentLines.count + 1),
            count: snapshotLines.count + 1
        )

        guard !snapshotLines.isEmpty, !currentLines.isEmpty else {
            return table
        }

        for snapshotIndex in stride(from: snapshotLines.count - 1, through: 0, by: -1) {
            for currentIndex in stride(from: currentLines.count - 1, through: 0, by: -1) {
                if snapshotLines[snapshotIndex] == currentLines[currentIndex] {
                    table[snapshotIndex][currentIndex] = table[snapshotIndex + 1][currentIndex + 1] + 1
                } else {
                    table[snapshotIndex][currentIndex] = max(
                        table[snapshotIndex + 1][currentIndex],
                        table[snapshotIndex][currentIndex + 1]
                    )
                }
            }
        }

        return table
    }
}

struct MarkdownPreviewResizeHandle: View {
    let onDrag: (CGFloat) -> Void

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 8)
            .overlay(
                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 3)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        onDrag(value.translation.width)
                    }
            )
            .help("Resize side pane")
    }
}

private struct LocalHistorySidebar: View {
    let entries: [FileLocalHistoryManager.SnapshotEntry]
    let selectedEntryID: String?
    let selectedDiff: LocalHistoryDiffEngine.Result?
    let width: CGFloat
    let minHeight: CGFloat
    let fontScale: CGFloat
    let theme: InterfaceThemeDefinition
    let emptyTitle: String
    let emptyMessage: String
    let openFolderLabel: String
    let currentDraftLabel: String
    let diffIdenticalLabel: String
    let diffLoadingLabel: String
    let diffUnavailableLabel: String
    let diffTruncatedLabel: String
    let onSelectEntry: (FileLocalHistoryManager.SnapshotEntry) -> Void
    let onOpenFolder: () -> Void
    let onAppearEntry: (FileLocalHistoryManager.SnapshotEntry) -> Void
    let onDisappearEntry: (FileLocalHistoryManager.SnapshotEntry) -> Void
    let badgeProvider: (FileLocalHistoryManager.SnapshotEntry) -> StandaloneNoteEditorView.LocalHistoryEntryBadge?
    let diffSummaryProvider: (FileLocalHistoryManager.SnapshotEntry) -> LocalHistoryDiffEngine.Summary?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private let historyAccentColor = Color(red: 0.18, green: 0.49, blue: 0.94)

    private var selectedEntry: FileLocalHistoryManager.SnapshotEntry? {
        guard let selectedEntryID else { return nil }
        return entries.first { $0.id == selectedEntryID }
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                emptyState
            } else if let selectedEntry {
                diffView(for: selectedEntry, diff: selectedDiff)
            } else {
                entryListView
            }
        }
        .frame(width: width)
        .frame(minHeight: minHeight, alignment: .topLeading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.94, green: 0.95, blue: 0.98).opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(emptyTitle)
                .font(.system(size: 11 * fontScale, weight: .semibold))
                .foregroundStyle(.primary)
            Text(emptyMessage)
                .font(.system(size: 10 * fontScale, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onOpenFolder) {
                Label(openFolderLabel, systemImage: "folder")
                    .font(.system(size: 10.5 * fontScale, weight: .semibold))
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
    }

    private var entryListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        historyListRow(entry)
                        if index < entries.count - 1 {
                            Divider()
                                .overlay(Color.white.opacity(0.06))
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 8) {
                Text("\(entries.count) snapshot\(entries.count == 1 ? "" : "s")")
                    .font(.system(size: 9.5 * fontScale, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }

    private func historyListRow(_ entry: FileLocalHistoryManager.SnapshotEntry) -> some View {
        let badge = badgeProvider(entry)
        let diffSummary = diffSummaryProvider(entry)

        return Button {
            onSelectEntry(entry)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(historyAccentColor)
                    .frame(width: 6 * fontScale, height: 6 * fontScale)

                Text(Self.relativeFormatter.localizedString(for: entry.createdAt, relativeTo: Date()))
                    .font(.system(size: 10.5 * fontScale, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let badge {
                    Text(badge.title)
                        .font(.system(size: 9 * fontScale, weight: .semibold))
                        .foregroundStyle(badge.tint)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if let diffSummary {
                    diffSummaryView(diffSummary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear {
            onAppearEntry(entry)
        }
        .onDisappear {
            onDisappearEntry(entry)
        }
    }

    private func diffView(
        for selectedEntry: FileLocalHistoryManager.SnapshotEntry,
        diff: LocalHistoryDiffEngine.Result?
    ) -> some View {
        diffCanvas(for: selectedEntry, diff: diff)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func diffCanvas(
        for selectedEntry: FileLocalHistoryManager.SnapshotEntry,
        diff: LocalHistoryDiffEngine.Result?
    ) -> some View {
        Group {
            if let diff {
                if diff.isUnavailable {
                    Text(diffUnavailableLabel)
                        .font(.system(size: 10 * fontScale, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(12)
                } else if !diff.summary.hasChanges {
                    Text(diffIdenticalLabel)
                        .font(.system(size: 10 * fontScale, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(12)
                } else if diff.isTruncated {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Self.timestampFormatter.string(from: selectedEntry.createdAt))
                            .font(.system(size: 9.5 * fontScale, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                        Text(diffTruncatedLabel)
                            .font(.system(size: 10 * fontScale, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
                } else {
                    AttributedEditorPreviewTextView(
                        attributedText: diffAttributedText(for: diff),
                        fontSize: 12 * fontScale
                    )
                }
            } else {
                Text(diffLoadingLabel)
                    .font(.system(size: 10 * fontScale, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.07))
                .overlay(theme.cardFill.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
        )
    }

    private func diffSummaryView(_ summary: LocalHistoryDiffEngine.Summary) -> some View {
        HStack(spacing: 4) {
            Text("+\(summary.additions)")
                .font(.system(size: 9.5 * fontScale, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 0.38, green: 0.86, blue: 0.47))
            Text("-\(summary.removals)")
                .font(.system(size: 9.5 * fontScale, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 0.98, green: 0.48, blue: 0.48))
        }
    }

    private func summaryHeaderText(
        for selectedEntry: FileLocalHistoryManager.SnapshotEntry,
        summary: LocalHistoryDiffEngine.Summary
    ) -> String {
        "\(currentDraftLabel) vs \(Self.timestampFormatter.string(from: selectedEntry.createdAt))  +\(summary.additions) / -\(summary.removals)"
    }

    private func lineBackgroundColor(for kind: LocalHistoryDiffEngine.LineKind) -> NSColor {
        switch kind {
        case .unchanged:
            return .clear
        case .added:
            return NSColor(calibratedRed: 0.19, green: 0.52, blue: 0.25, alpha: 0.22)
        case .removed:
            return NSColor(calibratedRed: 0.62, green: 0.19, blue: 0.19, alpha: 0.22)
        }
    }

    private func diffAttributedText(for diff: LocalHistoryDiffEngine.Result) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let textFont = NSFont.systemFont(ofSize: 12 * fontScale)
        let gutterFont = NSFont.monospacedDigitSystemFont(ofSize: 10 * fontScale, weight: .medium)
        let markerFont = NSFont.monospacedSystemFont(ofSize: 10.5 * fontScale, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.tabStops = [
            NSTextTab(textAlignment: .left, location: 18 * fontScale),
            NSTextTab(textAlignment: .right, location: 48 * fontScale),
            NSTextTab(textAlignment: .right, location: 82 * fontScale),
            NSTextTab(textAlignment: .left, location: 96 * fontScale)
        ]
        paragraph.defaultTabInterval = 96 * fontScale
        paragraph.headIndent = 96 * fontScale

        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let gutterAttributes: [NSAttributedString.Key: Any] = [
            .font: gutterFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]

        for (index, line) in diff.lines.enumerated() {
            let attributedLine = NSMutableAttributedString()
            attributedLine.append(NSAttributedString(
                string: diffMarker(for: line.kind),
                attributes: [
                    .font: markerFont,
                    .foregroundColor: diffMarkerColor(for: line.kind),
                    .paragraphStyle: paragraph
                ]
            ))
            attributedLine.append(NSAttributedString(string: "\t", attributes: gutterAttributes))
            attributedLine.append(NSAttributedString(
                string: line.oldLineNumber.map(String.init) ?? "",
                attributes: gutterAttributes
            ))
            attributedLine.append(NSAttributedString(string: "\t", attributes: gutterAttributes))
            attributedLine.append(NSAttributedString(
                string: line.newLineNumber.map(String.init) ?? "",
                attributes: gutterAttributes
            ))
            attributedLine.append(NSAttributedString(string: "\t", attributes: gutterAttributes))
            attributedLine.append(NSAttributedString(
                string: line.text.isEmpty ? " " : line.text,
                attributes: textAttributes
            ))
            if line.kind != .unchanged {
                attributedLine.addAttribute(
                    .backgroundColor,
                    value: lineBackgroundColor(for: line.kind),
                    range: NSRange(location: 0, length: attributedLine.length)
                )
            }
            result.append(attributedLine)
            if index < diff.lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: textAttributes))
            }
        }

        return result
    }

    private func diffMarker(for kind: LocalHistoryDiffEngine.LineKind) -> String {
        switch kind {
        case .unchanged:
            return " "
        case .added:
            return "+"
        case .removed:
            return "-"
        }
    }

    private func diffMarkerColor(for kind: LocalHistoryDiffEngine.LineKind) -> NSColor {
        switch kind {
        case .unchanged:
            return .secondaryLabelColor
        case .added:
            return NSColor(calibratedRed: 0.38, green: 0.86, blue: 0.47, alpha: 1)
        case .removed:
            return NSColor(calibratedRed: 0.98, green: 0.48, blue: 0.48, alpha: 1)
        }
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
    static let clipboardPanelValidationRequested = Notification.Name("clipboardPanelValidationRequested")
    static let clipboardTransformRequested = Notification.Name("clipboardTransformRequested")
}
