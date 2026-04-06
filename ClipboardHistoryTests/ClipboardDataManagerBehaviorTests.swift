import XCTest
import SwiftData
import AppKit
@testable import ClipboardHistory

@MainActor
final class ClipboardDataManagerBehaviorTests: XCTestCase {
    private var container: ModelContainer!
    private var modelContext: ModelContext!
    private var dataManager: ClipboardDataManager!
    private var userDefaults: UserDefaults!
    private var userDefaultsSuiteName: String!
    private var imageFilesToDelete: [URL] = []
    private var textFilesToDelete: [URL] = []
    private var originalGeneralPasteboardString: String?

    override func setUpWithError() throws {
        let schema = Schema([ClipboardItem.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        modelContext = ModelContext(container)
        let suiteName = "ClipboardDataManagerBehaviorTests.\(UUID().uuidString)"
        userDefaultsSuiteName = suiteName
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        dataManager = ClipboardDataManager(modelContext: modelContext, maxHistoryItems: 2, userDefaults: userDefaults)
        originalGeneralPasteboardString = NSPasteboard.general.string(forType: .string)
    }

    override func tearDownWithError() throws {
        for fileURL in imageFilesToDelete {
            try? FileManager.default.removeItem(at: fileURL)
        }
        imageFilesToDelete.removeAll()
        for fileURL in textFilesToDelete {
            try? FileManager.default.removeItem(at: fileURL)
        }
        textFilesToDelete.removeAll()
        if let suiteName = userDefaultsSuiteName {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let originalGeneralPasteboardString {
            pasteboard.setString(originalGeneralPasteboardString, forType: .string)
        }
        originalGeneralPasteboardString = nil
        userDefaults = nil
        userDefaultsSuiteName = nil
        dataManager = nil
        modelContext = nil
        container = nil
    }

    func testHistoryItemsExcludePinnedAndSortByNewestFirst() throws {
        _ = makeTextItem("old", timestamp: Date(timeIntervalSince1970: 10))
        _ = makeTextItem("middle", timestamp: Date(timeIntervalSince1970: 20), pinned: true, pinOrder: 0)
        _ = makeTextItem("new", timestamp: Date(timeIntervalSince1970: 30))
        try saveContext()

        XCTAssertEqual(dataManager.historyItems().compactMap(\.textContent), ["new", "old"])
    }

    func testPinnedItemsSortByPinOrder() throws {
        let first = makeTextItem("first", timestamp: Date(timeIntervalSince1970: 1), pinned: true, pinOrder: 1)
        let second = makeTextItem("second", timestamp: Date(timeIntervalSince1970: 2), pinned: true, pinOrder: 0)
        try saveContext()

        XCTAssertEqual(dataManager.pinnedItems().map(\.id), [second.id, first.id])
    }

    func testSetPinnedAssignsNextOrderAndUnpinNormalizesRemaining() throws {
        let first = makeTextItem("first", timestamp: Date(timeIntervalSince1970: 1), pinned: true, pinOrder: 0)
        let second = makeTextItem("second", timestamp: Date(timeIntervalSince1970: 2))
        let third = makeTextItem("third", timestamp: Date(timeIntervalSince1970: 3), pinned: true, pinOrder: 1)
        try saveContext()

        XCTAssertTrue(dataManager.setPinned(true, for: second.id))
        flushScheduledSave()
        XCTAssertEqual(dataManager.pinnedItems().map(\.id), [first.id, third.id, second.id])
        XCTAssertEqual(fetchItem(id: second.id)?.pinOrder, 2)

        XCTAssertTrue(dataManager.setPinned(false, for: first.id))
        flushScheduledSave()
        XCTAssertEqual(dataManager.pinnedItems().map(\.id), [third.id, second.id])
        XCTAssertEqual(fetchItem(id: third.id)?.pinOrder, 0)
        XCTAssertEqual(fetchItem(id: second.id)?.pinOrder, 1)
    }

    func testSetPinLabelTrimsWhitespaceAndRemovesEmptyLabels() throws {
        let item = makeTextItem("alpha", timestamp: Date())
        try saveContext()

        XCTAssertTrue(dataManager.setPinLabel("  Focus  ", for: item.id))
        XCTAssertEqual(dataManager.pinLabel(for: item.id), "Focus")

        XCTAssertTrue(dataManager.setPinLabel("   ", for: item.id))
        XCTAssertNil(dataManager.pinLabel(for: item.id))
    }

    func testUpdateTextContentPreservesTimestampUnlessExplicitlyTouched() throws {
        let item = makeTextItem("alpha", timestamp: Date(timeIntervalSince1970: 100))
        try saveContext()
        let originalTimestamp = try XCTUnwrap(fetchItem(id: item.id)?.timestamp)

        XCTAssertTrue(dataManager.updateTextContent("beta", for: item.id))
        flushScheduledSave()
        XCTAssertEqual(fetchItem(id: item.id)?.timestamp, originalTimestamp)

        XCTAssertTrue(dataManager.updateTextContent("gamma", for: item.id, touchTimestamp: true))
        flushScheduledSave()
        XCTAssertNotEqual(fetchItem(id: item.id)?.timestamp, originalTimestamp)
    }

    func testReorderPinnedItemsRejectsInvalidInputs() throws {
        let first = makeTextItem("first", timestamp: Date(), pinned: true, pinOrder: 0)
        let second = makeTextItem("second", timestamp: Date(), pinned: true, pinOrder: 1)
        try saveContext()

        XCTAssertFalse(dataManager.reorderPinnedItems([first.id]))
        XCTAssertFalse(dataManager.reorderPinnedItems([first.id, first.id]))
        XCTAssertFalse(dataManager.reorderPinnedItems([first.id, UUID()]))
        XCTAssertEqual(dataManager.pinnedItems().map(\.id), [first.id, second.id])
    }

    func testDeleteItemRemovesPinLabelAndImageFile() throws {
        let imageData = try makePNGData(color: .systemRed)
        let fileName = "behavior-\(UUID().uuidString).png"
        let fileURL = imageStoreDirectory().appendingPathComponent(fileName)
        try imageData.write(to: fileURL, options: .atomic)
        imageFilesToDelete.append(fileURL)

        let item = ClipboardItem(
            type: .image,
            isPinned: true,
            pinOrder: 0,
            dedupeKey: ClipboardDedupeKey.image(imageData),
            imageFileName: fileName
        )
        modelContext.insert(item)
        try saveContext()
        XCTAssertTrue(dataManager.setPinLabel("Artwork", for: item.id))

        XCTAssertTrue(dataManager.deleteItem(id: item.id))
        flushScheduledSave()

        XCTAssertNil(dataManager.pinLabel(for: item.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testRestoreDeletedItemFailsIfItemAlreadyExists() throws {
        let item = makeTextItem("alpha", timestamp: Date())
        try saveContext()

        let snapshot = try XCTUnwrap(dataManager.snapshotItem(id: item.id))
        XCTAssertFalse(dataManager.restoreDeletedItem(snapshot))
    }

    func testStoreCaptureRejectsDuplicateOfPinnedTextAndTrimsHistory() throws {
        _ = makeTextItem("keep", timestamp: Date(timeIntervalSince1970: 1), pinned: true, pinOrder: 0)
        _ = makeTextItem("old", timestamp: Date(timeIntervalSince1970: 2))
        try saveContext()

        dataManager.storeCapture(.init(payload: .text("keep"), dedupeKey: ClipboardDedupeKey.text("keep")))
        dataManager.storeCapture(.init(payload: .text("new-1"), dedupeKey: ClipboardDedupeKey.text("new-1")))
        dataManager.storeCapture(.init(payload: .text("new-2"), dedupeKey: ClipboardDedupeKey.text("new-2")))
        flushScheduledSave()

        XCTAssertEqual(dataManager.allItems().filter { $0.textContent == "keep" }.count, 1)
        XCTAssertEqual(dataManager.historyItems().compactMap(\.textContent), ["new-2", "new-1"])
    }

    func testLargeTextDedupeKeyIsStableForSameInputAndChangesForDifferentSuffix() {
        let repeated = String(repeating: "abcdefghij", count: 40_000)
        let textA = repeated + "\nfinal-a"
        let textA2 = repeated + "\nfinal-a"
        let textB = repeated + "\nfinal-b"

        let keyA = ClipboardDedupeKey.text(textA)
        let keyA2 = ClipboardDedupeKey.text(textA2)
        let keyB = ClipboardDedupeKey.text(textB)

        XCTAssertEqual(keyA, keyA2)
        XCTAssertNotEqual(keyA, keyB)
    }

    func testLargeTextPreviewAnalysisExpandsWithoutScanningEntireString() {
        let large = "LONGTOKEN-" + String(repeating: "abcdefghij", count: 200_000) + "-END"
        let analysis = HistoryRowView.analyzeTextPreview(large, previewLimit: 420, lineLimit: 4)

        XCTAssertTrue(analysis.shouldShowExpand)
        XCTAssertTrue(analysis.isInlineRestricted)
        XCTAssertEqual(analysis.preview.count, 420)
        XCTAssertTrue(analysis.preview.hasPrefix("LONGTOKEN-"))
    }

    func testStoreCapturePersistsLargeTextAsPreviewAndRawFile() throws {
        let largeText = String(repeating: "abcdefghij", count: 40_000)

        dataManager.storeCapture(.init(payload: .text(largeText), dedupeKey: ClipboardDedupeKey.text(largeText)))
        flushScheduledSave()

        let item = try XCTUnwrap(dataManager.historyItems().first)
        XCTAssertTrue(item.isLargeText)
        XCTAssertEqual(item.textByteCount, largeText.utf8.count)
        XCTAssertNotEqual(item.textContent, largeText)
        XCTAssertEqual(item.textContent, String(largeText.prefix(LargeTextPolicy.storedPreviewCharacterLimit)))
        XCTAssertEqual(dataManager.resolvedText(for: item), largeText)

        let fileName = try XCTUnwrap(item.textStorageFileName)
        let fileURL = largeTextStoreDirectory().appendingPathComponent(fileName)
        textFilesToDelete.append(fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testCaptureFromPasteboardReadsPNGImageData() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipboardDataManagerBehaviorTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let pngData = try makePNGData(color: .systemBlue)
        XCTAssertTrue(pasteboard.setData(pngData, forType: .png))

        let capture = try XCTUnwrap(dataManager.captureFromPasteboard(pasteboard))
        switch capture.payload {
        case .image(let data):
            XCTAssertFalse(data.isEmpty)
            XCTAssertTrue(capture.dedupeKey.hasPrefix("img:"))
        default:
            XCTFail("Expected image payload")
        }
    }

    func testClipboardControllerSyncNowCapturesGeneralPasteboardText() throws {
        let controller = ClipboardController(
            dataManager: dataManager,
            pollingInterval: 0.01,
            copyCapturePollingInterval: 0.005,
            copyCaptureTimeout: 0.2
        )
        let text = "sync-now-\(UUID().uuidString)"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(text, forType: .string))

        controller.syncNow()
        flushScheduledSave()

        XCTAssertEqual(dataManager.historyItems().first?.textContent, text)
    }

    func testClipboardControllerPollingCapturesClipboardChangesWithoutKeyboardEvent() throws {
        var controller: ClipboardController? = ClipboardController(
            dataManager: dataManager,
            pollingInterval: 0.01,
            copyCapturePollingInterval: 0.005,
            copyCaptureTimeout: 0.2
        )
        controller?.shouldHandleKeyboardCopyEvent = { false }
        controller?.startMonitoring()

        let text = "polled-copy-\(UUID().uuidString)"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(text, forType: .string))

        let expectation = expectation(description: "clipboard capture")
        let deadline = Date().addingTimeInterval(1.0)
        pollUntil(deadline: deadline) {
            self.dataManager.historyItems().first?.textContent == text
        } onSuccess: {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.2)
        controller = nil
    }

    func testRestoreDeletedLargeTextRestoresRawTextAndStorageFile() throws {
        let largeText = String(repeating: "abc123XYZ\n", count: 30_000)
        dataManager.storeCapture(.init(payload: .text(largeText), dedupeKey: ClipboardDedupeKey.text(largeText)))
        flushScheduledSave()

        let originalItem = try XCTUnwrap(dataManager.historyItems().first)
        let snapshot = try XCTUnwrap(dataManager.snapshotItem(id: originalItem.id))
        let originalFileURL = largeTextStoreDirectory().appendingPathComponent(try XCTUnwrap(originalItem.textStorageFileName))
        textFilesToDelete.append(originalFileURL)

        XCTAssertTrue(dataManager.deleteItem(id: originalItem.id))
        flushScheduledSave()
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalFileURL.path))

        XCTAssertTrue(dataManager.restoreDeletedItem(snapshot))
        flushScheduledSave()

        let restored = try XCTUnwrap(fetchItem(id: originalItem.id))
        XCTAssertTrue(restored.isLargeText)
        XCTAssertEqual(dataManager.resolvedText(for: restored), largeText)
        let restoredFileURL = largeTextStoreDirectory().appendingPathComponent(try XCTUnwrap(restored.textStorageFileName))
        textFilesToDelete.append(restoredFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: restoredFileURL.path))
    }

    func testManagerInitMigratesExistingLargeInlineTextToFileBackedStorage() throws {
        let largeText = String(repeating: "migrate-me-", count: 35_000)
        let item = ClipboardItem(type: .text, textContent: largeText)
        item.timestamp = Date()
        modelContext.insert(item)
        try saveContext()

        dataManager = ClipboardDataManager(modelContext: modelContext, maxHistoryItems: 2, userDefaults: userDefaults)

        let migrated = try XCTUnwrap(fetchItem(id: item.id))
        XCTAssertTrue(migrated.isLargeText)
        XCTAssertEqual(migrated.textByteCount, largeText.utf8.count)
        XCTAssertEqual(migrated.textContent, String(largeText.prefix(LargeTextPolicy.storedPreviewCharacterLimit)))
        XCTAssertEqual(dataManager.resolvedText(for: migrated), largeText)
        let fileURL = largeTextStoreDirectory().appendingPathComponent(try XCTUnwrap(migrated.textStorageFileName))
        textFilesToDelete.append(fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse((migrated.dedupeKey ?? "").isEmpty)
    }

    func testManagerInitNormalizesLegacyMarkdownTextFormatToPlain() throws {
        let item = ClipboardItem(type: .text, textContent: "# heading", textFormat: .markdown)
        item.textByteCount = "# heading".utf8.count
        modelContext.insert(item)
        try saveContext()

        dataManager = ClipboardDataManager(modelContext: modelContext, maxHistoryItems: 2, userDefaults: userDefaults)

        let migrated = try XCTUnwrap(fetchItem(id: item.id))
        XCTAssertEqual(migrated.textFormat, .plain)
    }

    func testPreviewAnalysisMarksExplicitLineOverflow() {
        let multiline = "line1\nline2\nline3\nline4\nline5"
        let analysis = HistoryRowView.analyzeTextPreview(multiline, previewLimit: 420, lineLimit: 4)

        XCTAssertTrue(analysis.shouldShowExpand)
        XCTAssertTrue(analysis.preview.contains("line4"))
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

    private func pollUntil(deadline: Date, condition: @escaping () -> Bool, onSuccess: @escaping () -> Void) {
        if condition() {
            onSuccess()
            return
        }
        guard Date() < deadline else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard self != nil else { return }
            self?.pollUntil(deadline: deadline, condition: condition, onSuccess: onSuccess)
        }
    }

    private func imageStoreDirectory() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = root.appendingPathComponent("ClipboardHistoryApp/Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func largeTextStoreDirectory() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = root.appendingPathComponent("ClipboardHistory/LargeText", isDirectory: true)
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
}
