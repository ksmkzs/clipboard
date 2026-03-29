import XCTest
import SwiftData
import AppKit
import Carbon
@testable import ClipboardHistory

@MainActor
final class ClipboardWorkflowRegressionTests: XCTestCase {
    private final class TestUndoResponder: NSResponder {
        private let testUndoManager = UndoManager()

        override var undoManager: UndoManager? {
            testUndoManager
        }
    }

    private var container: ModelContainer!
    private var modelContext: ModelContext!
    private var dataManager: ClipboardDataManager!
    private var userDefaults: UserDefaults!
    private var userDefaultsSuiteName: String!
    private var imageFilesToDelete: [URL] = []
    private var undoResponders: [NSResponder] = []

    override func setUpWithError() throws {
        let schema = Schema([ClipboardItem.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        modelContext = ModelContext(container)
        let suiteName = "ClipboardWorkflowRegressionTests.\(UUID().uuidString)"
        userDefaultsSuiteName = suiteName
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        dataManager = ClipboardDataManager(modelContext: modelContext, maxHistoryItems: 2, userDefaults: userDefaults)
    }

    override func tearDownWithError() throws {
        undoResponders.removeAll()
        for fileURL in imageFilesToDelete {
            try? FileManager.default.removeItem(at: fileURL)
        }
        imageFilesToDelete.removeAll()
        if let suiteName = userDefaultsSuiteName {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        userDefaults = nil
        userDefaultsSuiteName = nil
        dataManager = nil
        modelContext = nil
        container = nil
    }

    func testComplexPinnedDeleteRestoreTransformWorkflow() throws {
        let older = makeTextItem("alpha\none", timestamp: Date(timeIntervalSince1970: 10))
        let middle = makeTextItem("beta\n two\nthree", timestamp: Date(timeIntervalSince1970: 20))
        let newest = makeTextItem("gamma", timestamp: Date(timeIntervalSince1970: 30))
        try saveContext()

        XCTAssertEqual(dataManager.historyItems().map(\.id), [newest.id, middle.id, older.id])

        XCTAssertTrue(dataManager.setPinLabel("Primary", for: middle.id))
        XCTAssertTrue(dataManager.setPinned(true, for: middle.id))
        XCTAssertTrue(dataManager.setPinned(true, for: older.id))
        XCTAssertTrue(dataManager.reorderPinnedItems([middle.id, older.id]))
        flushScheduledSave()

        XCTAssertEqual(dataManager.pinnedItems().map(\.id), [middle.id, older.id])
        XCTAssertEqual(dataManager.historyItems().map(\.id), [newest.id])

        let pinSnapshot = dataManager.snapshotPinState()
        let deletedSnapshot = try XCTUnwrap(dataManager.snapshotItem(id: middle.id))
        XCTAssertTrue(dataManager.deleteItem(id: middle.id))
        flushScheduledSave()

        XCTAssertEqual(dataManager.pinnedItems().map(\.id), [older.id])
        XCTAssertNil(dataManager.pinLabel(for: middle.id))

        XCTAssertTrue(dataManager.restoreDeletedItem(deletedSnapshot))
        XCTAssertTrue(dataManager.restorePinState(pinSnapshot))
        flushScheduledSave()

        XCTAssertEqual(dataManager.pinnedItems().map(\.id), [middle.id, older.id])
        XCTAssertEqual(dataManager.pinLabel(for: middle.id), "Primary")

        let originalTimestamp = try XCTUnwrap(fetchItem(id: older.id)?.timestamp)
        XCTAssertTrue(dataManager.updateTextContent("alpha one", for: older.id))
        flushScheduledSave()

        let updatedOlder = try XCTUnwrap(fetchItem(id: older.id))
        XCTAssertEqual(updatedOlder.textContent, "alpha one")
        XCTAssertEqual(updatedOlder.timestamp, originalTimestamp)
        XCTAssertEqual(dataManager.historyItems().map(\.id), [newest.id])
    }

    func testComplexHistoryTrimAndPinnedDedupWorkflow() throws {
        let pinnedKeep = makeTextItem("keep", timestamp: Date(timeIntervalSince1970: 1), pinned: true, pinOrder: 0)
        let oldUnpinned = makeTextItem("old", timestamp: Date(timeIntervalSince1970: 2))
        try saveContext()

        dataManager.storeCapture(.init(payload: .text("keep"), dedupeKey: ClipboardDedupeKey.text("keep")))
        dataManager.storeCapture(.init(payload: .text("new-1"), dedupeKey: ClipboardDedupeKey.text("new-1")))
        dataManager.storeCapture(.init(payload: .text("new-2"), dedupeKey: ClipboardDedupeKey.text("new-2")))
        dataManager.storeCapture(.init(payload: .text("new-2"), dedupeKey: ClipboardDedupeKey.text("new-2")))
        flushScheduledSave()

        let historyTexts = dataManager.historyItems().compactMap(\.textContent)
        XCTAssertEqual(historyTexts, ["new-2", "new-1"])
        XCTAssertEqual(dataManager.pinnedItems().map(\.id), [pinnedKeep.id])
        XCTAssertFalse(dataManager.allItems().contains(where: { $0.id == oldUnpinned.id }))
        XCTAssertEqual(dataManager.allItems().filter { $0.textContent == "keep" }.count, 1)
        XCTAssertEqual(dataManager.allItems().filter { $0.textContent == "new-2" }.count, 1)
    }

    func testComplexImageDeleteRestoreWorkflowPreservesFileAndLabel() throws {
        let imageData = try makePNGData(color: .systemBlue)
        let fileName = "workflow-\(UUID().uuidString).png"
        let fileURL = imageStoreDirectory().appendingPathComponent(fileName)
        try imageData.write(to: fileURL, options: .atomic)
        imageFilesToDelete.append(fileURL)

        let imageItem = ClipboardItem(
            type: .image,
            isPinned: true,
            pinOrder: 0,
            dedupeKey: ClipboardDedupeKey.image(imageData),
            imageFileName: fileName
        )
        imageItem.timestamp = Date(timeIntervalSince1970: 40)
        modelContext.insert(imageItem)
        try saveContext()

        XCTAssertTrue(dataManager.setPinLabel("Diagram", for: imageItem.id))
        let snapshot = try XCTUnwrap(dataManager.snapshotItem(id: imageItem.id))
        XCTAssertNotNil(snapshot.imageData)

        XCTAssertTrue(dataManager.deleteItem(id: imageItem.id))
        flushScheduledSave()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNil(dataManager.pinLabel(for: imageItem.id))

        XCTAssertTrue(dataManager.restoreDeletedItem(snapshot))
        flushScheduledSave()

        let restored = try XCTUnwrap(fetchItem(id: imageItem.id))
        XCTAssertEqual(restored.type, .image)
        XCTAssertEqual(dataManager.pinLabel(for: imageItem.id), "Diagram")
        XCTAssertNotNil(restored.imageFileName)
        let restoredURL = imageStoreDirectory().appendingPathComponent(try XCTUnwrap(restored.imageFileName))
        imageFilesToDelete.append(restoredURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: restoredURL.path))
        XCTAssertNotNil(dataManager.loadImage(fileName: try XCTUnwrap(restored.imageFileName)))
    }

    func testComplexEditorCommandSequenceStaysConsistentAcrossMoveIndentJoin() {
        let editor = makeEditor(
            text: "one\ntwo\nthree",
            selection: NSRange(location: 4, length: 3)
        )

        editor.keyDown(with: keyEvent(keyCode: 125, characters: "\u{F701}", modifiers: .option))
        XCTAssertEqual(editor.string, "one\nthree\ntwo")

        editor.keyDown(with: keyEvent(keyCode: 126, characters: "\u{F700}", modifiers: .option))
        XCTAssertEqual(editor.string, "one\ntwo\nthree")

        editor.setSelectedRange(NSRange(location: 0, length: 13))
        editor.keyDown(with: keyEvent(keyCode: 48, characters: "\t"))
        XCTAssertEqual(editor.string, "\tone\n\ttwo\n\tthree")

        editor.keyDown(with: keyEvent(keyCode: 48, characters: "\t", modifiers: .shift))
        XCTAssertEqual(editor.string, "one\ntwo\nthree")

        _ = editor.performKeyEquivalent(with: keyEvent(matching: AppSettings.default.joinLinesShortcut))
        XCTAssertEqual(editor.string, "onetwothree")
    }

    func testComplexEditorClipboardNormalizeWorkflowPreservesExpectedUndoBoundaries() {
        let editor = makeEditor(
            text: "  brew install \n  git  \n",
            selection: NSRange(location: 0, length: 24)
        )

        _ = editor.performKeyEquivalent(with: keyEvent(matching: AppSettings.default.normalizeForCommandShortcut))
        XCTAssertEqual(editor.string, "brew install\ngit\n")

        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: 6, characters: "z", modifiers: .command))
        XCTAssertEqual(editor.string, "  brew install \n  git  \n")

        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: 6, characters: "Z", modifiers: [.command, .shift]))
        XCTAssertEqual(editor.string, "brew install\ngit\n")
    }

    func testManualNotePersistsWithoutClipboardDedupe() throws {
        let note = try XCTUnwrap(dataManager.createManualNote(text: ""))
        XCTAssertTrue(note.isManualNote)
        XCTAssertEqual(note.textFormat, .plain)

        XCTAssertTrue(dataManager.updateTextContent("# Title\n\nBody", for: note.id))
        flushScheduledSave()

        let restored = try XCTUnwrap(fetchItem(id: note.id))
        XCTAssertTrue(restored.isManualNote)
        XCTAssertEqual(restored.textFormat, .plain)
        XCTAssertEqual(dataManager.resolvedText(for: restored), "# Title\n\nBody")

        dataManager.storeCapture(.init(payload: .text("clipboard"), dedupeKey: ClipboardDedupeKey.text("clipboard")))
        flushScheduledSave()

        XCTAssertEqual(dataManager.allItems().filter { $0.isManualNote }.count, 1)
        XCTAssertEqual(dataManager.allItems().filter { $0.textContent == "clipboard" }.count, 1)
    }

    private func makeTextItem(
        _ text: String,
        timestamp: Date,
        pinned: Bool = false,
        pinOrder: Int? = nil
    ) -> ClipboardItem {
        let item = ClipboardItem(
            type: .text,
            isPinned: pinned,
            pinOrder: pinOrder,
            dedupeKey: ClipboardDedupeKey.text(text),
            textContent: text,
            textByteCount: text.utf8.count
        )
        item.timestamp = timestamp
        modelContext.insert(item)
        return item
    }

    private func fetchItem(id: UUID) -> ClipboardItem? {
        try? modelContext.fetch(FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })).first
    }

    private func saveContext() throws {
        try modelContext.save()
    }

    private func flushScheduledSave() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    private func imageStoreDirectory() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = root.appendingPathComponent("ClipboardHistoryApp/Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makePNGData(color: NSColor) throws -> Data {
        let size = NSSize(width: 8, height: 8)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
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
        editor.string = text
        editor.setSelectedRange(selection)
        let undoResponder = TestUndoResponder()
        editor.nextResponder = undoResponder
        undoResponders.append(undoResponder)
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
