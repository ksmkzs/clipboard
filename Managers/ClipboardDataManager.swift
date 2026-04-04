import AppKit
import SwiftData

class ClipboardDataManager {
    private enum DefaultsKey {
        static let pinLabels = "pin.labels"
    }

    private struct PreparedTextStorage {
        let displayText: String
        let isLargeText: Bool
        let textByteCount: Int
        let textStorageFileName: String?
        let dedupeKey: String
    }

    struct PinStateSnapshot {
        let itemID: UUID
        let isPinned: Bool
        let pinOrder: Int?
    }

    struct ItemSnapshot {
        let id: UUID
        let timestamp: Date
        let type: ClipboardItemType
        let isPinned: Bool
        let pinOrder: Int?
        let isManualNote: Bool
        let textContent: String?
        let textFormat: ClipboardTextFormat
        let dedupeKey: String
        let imageData: Data?
        let pinLabel: String?
    }

    struct ClipboardCapture {
        enum Payload {
            case text(String)
            case image(Data)
        }
        
        let payload: Payload
        let dedupeKey: String
    }
    
    let modelContext: ModelContext
    private var maxHistoryItems: Int
    private let imageMemoryCache = NSCache<NSString, NSImage>()
    private let userDefaults: UserDefaults
    private let storePaths: ClipboardStorePaths
    private var pendingSaveWorkItem: DispatchWorkItem?
    private var cachedPinLabels: [String: String]
    private var cachedPinLabelsByID: [UUID: String]
    
    private var imageCacheDirectory: URL {
        storePaths.imageDirectory
    }

    private var largeTextDirectory: URL {
        storePaths.largeTextDirectory
    }

    private var noteDraftDirectory: URL {
        storePaths.noteDraftDirectory
    }
    
    init(
        modelContext: ModelContext,
        maxHistoryItems: Int = 150,
        userDefaults: UserDefaults = .standard,
        storePaths: ClipboardStorePaths = .default()
    ) {
        self.modelContext = modelContext
        self.maxHistoryItems = max(1, maxHistoryItems)
        self.userDefaults = userDefaults
        self.storePaths = storePaths
        let labels = userDefaults.dictionary(forKey: DefaultsKey.pinLabels) as? [String: String] ?? [:]
        self.cachedPinLabels = labels
        self.cachedPinLabelsByID = Self.makePinLabelsByID(from: labels)
        try? storePaths.ensureDirectories()
        migrateStoredItemsIfNeeded()
    }

    func updateMaxHistoryItems(_ maxHistoryItems: Int) {
        self.maxHistoryItems = max(1, maxHistoryItems)
        trimHistoryIfNeeded()
        scheduleSave()
    }
    
    func captureFromPasteboard(_ pasteboard: NSPasteboard) -> ClipboardCapture? {
        if let imageData = extractRawImageData(from: pasteboard) {
            guard let normalizedImageData = prepareImageDataForStorage(rawData: imageData) else {
                return nil
            }
            return ClipboardCapture(
                payload: .image(normalizedImageData),
                dedupeKey: ClipboardDedupeKey.image(normalizedImageData)
            )
        }
        
        if let textString = pasteboard.string(forType: .string) {
            if containsMeaningfulText(textString) {
                return ClipboardCapture(
                    payload: .text(textString),
                    dedupeKey: ClipboardDedupeKey.text(textString)
                )
            }
        }
        
        return nil
    }

    private func containsMeaningfulText(_ text: String) -> Bool {
        text.unicodeScalars.contains { !CharacterSet.whitespacesAndNewlines.contains($0) }
    }
    
    func storeCapture(_ capture: ClipboardCapture) {
        switch capture.payload {
        case .text(let text):
            if text.utf8.count > LargeTextPolicy.inlineThresholdBytes {
                let dedupeKey = capture.dedupeKey
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self else { return }
                    guard let prepared = self.prepareTextStorage(for: text, dedupeKey: dedupeKey) else { return }
                    let preparedFileURL = prepared.textStorageFileName.map { self.largeTextDirectory.appendingPathComponent($0) }
                    DispatchQueue.main.async { [weak self] in
                        guard let self else {
                            if let preparedFileURL {
                                try? FileManager.default.removeItem(at: preparedFileURL)
                            }
                            return
                        }
                        let didPersist = self.persistPreparedTextStorage(prepared)
                        if !didPersist {
                            if let preparedFileURL {
                                try? FileManager.default.removeItem(at: preparedFileURL)
                            }
                        }
                    }
                }
            } else {
                _ = persistText(text, dedupeKey: capture.dedupeKey)
            }
        case .image(let normalizedData):
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                self.saveImageItem(normalizedData, dedupeKey: capture.dedupeKey)
            }
        }
    }

    func pinnedItems() -> [ClipboardItem] {
        fetchPinnedItems()
    }

    func historyItems() -> [ClipboardItem] {
        fetchHistoryItems()
    }

    func allItems() -> [ClipboardItem] {
        fetchAllItems()
    }

    func resetValidationStore() {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil

        for item in fetchAllItems() {
            deleteImageFileIfNeeded(for: item)
            deleteLargeTextFileIfNeeded(for: item)
            modelContext.delete(item)
        }

        updatePinLabels([:])
        clearDirectoryContents(at: noteDraftDirectory)
        clearDirectoryContents(at: largeTextDirectory)
        clearDirectoryContents(at: imageCacheDirectory)
        _ = saveModelContext()
    }

    func pinLabel(for itemID: UUID) -> String? {
        let label = pinLabels()[itemID.uuidString]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return label.isEmpty ? nil : label
    }

    func pinLabelsByID() -> [UUID: String] {
        cachedPinLabelsByID
    }

    func snapshotPinState() -> [PinStateSnapshot] {
        fetchAllItems().map {
            PinStateSnapshot(itemID: $0.id, isPinned: $0.isPinned, pinOrder: $0.pinOrder)
        }
    }

    @discardableResult
    func restorePinState(_ snapshots: [PinStateSnapshot]) -> Bool {
        let allItems = fetchAllItems()
        let statesByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.itemID, $0) })

        for item in allItems {
            if let state = statesByID[item.id] {
                item.isPinned = state.isPinned
                item.pinOrder = state.pinOrder
            } else {
                item.isPinned = false
                item.pinOrder = nil
            }
        }

        normalizePinnedOrder(items: allItems)
        scheduleSave()
        return true
    }

    func snapshotItem(id: UUID) -> ItemSnapshot? {
        guard let item = fetchItem(id: id) else {
            return nil
        }

        return ItemSnapshot(
            id: item.id,
            timestamp: item.timestamp,
            type: item.type,
            isPinned: item.isPinned,
            pinOrder: item.pinOrder,
            isManualNote: item.isManualNote,
            textContent: item.type == .text ? resolvedText(for: item) : nil,
            textFormat: item.textFormat,
            dedupeKey: item.dedupeKey
                ?? {
                    switch item.type {
                    case .text:
                        return resolvedText(for: item).map(ClipboardDedupeKey.text)
                    case .image:
                        return item.imageFileName.flatMap(loadImageData(fileName:)).map(ClipboardDedupeKey.image)
                    }
                }() ?? "",
            imageData: item.imageFileName.flatMap(loadImageData(fileName:)),
            pinLabel: pinLabel(for: item.id)
        )
    }

    @discardableResult
    func restoreDeletedItem(_ snapshot: ItemSnapshot) -> Bool {
        guard fetchItem(id: snapshot.id) == nil else {
            return false
        }

        let restoredImageFileName: String?
        let restoredTextStorage: PreparedTextStorage?
        if snapshot.type == .image {
            guard let imageData = snapshot.imageData else {
                return false
            }
            let fileName = "\(UUID().uuidString).png"
            let fileURL = imageCacheDirectory.appendingPathComponent(fileName)
            do {
                try imageData.write(to: fileURL, options: .atomic)
                if let image = NSImage(data: imageData) {
                    imageMemoryCache.setObject(image, forKey: fileName as NSString)
                }
                restoredImageFileName = fileName
            } catch {
                print("Failed to restore image item: \(error)")
                return false
            }
            restoredTextStorage = nil
        } else {
            restoredImageFileName = nil
            guard let rawText = snapshot.textContent,
                  let prepared = prepareTextStorage(for: rawText, dedupeKey: snapshot.dedupeKey) else {
                return false
            }
            restoredTextStorage = prepared
        }

        let item = ClipboardItem(
            type: snapshot.type,
            isPinned: snapshot.isPinned,
            pinOrder: snapshot.pinOrder,
            dedupeKey: snapshot.dedupeKey,
            isManualNote: snapshot.isManualNote,
            textContent: restoredTextStorage?.displayText,
            isLargeText: restoredTextStorage?.isLargeText ?? false,
            textByteCount: restoredTextStorage?.textByteCount ?? 0,
            textStorageFileName: restoredTextStorage?.textStorageFileName,
            textFormat: snapshot.textFormat,
            imageFileName: restoredImageFileName
        )
        item.id = snapshot.id
        item.timestamp = snapshot.timestamp
        modelContext.insert(item)

        if let pinLabel = snapshot.pinLabel {
            _ = setPinLabel(pinLabel, for: snapshot.id)
        }

        normalizePinnedOrder()
        return saveModelContext()
    }

    @discardableResult
    func setPinLabel(_ label: String, for itemID: UUID) -> Bool {
        var labels = pinLabels()
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            labels.removeValue(forKey: itemID.uuidString)
        } else {
            labels[itemID.uuidString] = normalized
        }
        updatePinLabels(labels)
        return true
    }

    @discardableResult
    func setPinned(_ isPinned: Bool, for itemID: UUID) -> Bool {
        guard let item = fetchItem(id: itemID) else {
            return false
        }

        if isPinned {
            if item.isPinned {
                return true
            }
            item.isPinned = true
            item.pinOrder = nextPinOrder(from: fetchPinnedItems())
        } else {
            if !item.isPinned {
                return true
            }
            item.isPinned = false
            item.pinOrder = nil
            normalizePinnedOrder(items: fetchPinnedItems())
        }

        scheduleSave()
        return true
    }

    @discardableResult
    func updateTextContent(_ text: String, for itemID: UUID, touchTimestamp: Bool = false) -> Bool {
        guard let item = fetchItem(id: itemID), item.type == .text else {
            return false
        }
        let previousTextFile = item.textStorageFileName
        guard let prepared = prepareTextStorage(for: text) else {
            return false
        }
        item.dedupeKey = prepared.dedupeKey
        item.textContent = prepared.displayText
        item.isLargeText = prepared.isLargeText
        item.textByteCount = prepared.textByteCount
        item.textStorageFileName = prepared.textStorageFileName
        if touchTimestamp {
            item.timestamp = Date()
        }
        if previousTextFile != prepared.textStorageFileName {
            deleteLargeTextFile(named: previousTextFile)
        }
        scheduleSave()
        return true
    }

    @discardableResult
    func createManualNote(text: String = "") -> ClipboardItem? {
        guard let prepared = prepareTextStorage(for: text, dedupeKey: "note:\(UUID().uuidString)") else {
            return nil
        }

        let item = ClipboardItem(
            type: .text,
            dedupeKey: prepared.dedupeKey,
            isManualNote: true,
            textContent: prepared.displayText,
            isLargeText: prepared.isLargeText,
            textByteCount: prepared.textByteCount,
            textStorageFileName: prepared.textStorageFileName
        )
        modelContext.insert(item)
        guard saveModelContext() else {
            deleteLargeTextFile(named: prepared.textStorageFileName)
            modelContext.delete(item)
            return nil
        }
        return item
    }

    func workingNoteFileURL(for itemID: UUID) -> URL {
        noteDraftDirectory.appendingPathComponent("\(itemID.uuidString).md")
    }

    func loadWorkingNoteText(for itemID: UUID) -> String? {
        let fileURL = workingNoteFileURL(for: itemID)
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    @discardableResult
    func saveWorkingNoteText(_ text: String, for itemID: UUID) -> Bool {
        let fileURL = workingNoteFileURL(for: itemID)
        do {
            try storePaths.ensureDirectories()
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            print("Failed to save note working file: \(error)")
            return false
        }
    }

    @discardableResult
    func reorderPinnedItems(_ orderedIDs: [UUID]) -> Bool {
        let pinnedItems = fetchPinnedItems()
        guard pinnedItems.count == orderedIDs.count else {
            return false
        }

        let itemsByID = Dictionary(uniqueKeysWithValues: pinnedItems.map { ($0.id, $0) })
        guard Set(itemsByID.keys) == Set(orderedIDs) else {
            return false
        }

        for (index, id) in orderedIDs.enumerated() {
            itemsByID[id]?.pinOrder = index
        }

        scheduleSave()
        return true
    }

    @discardableResult
    func deleteItem(id: UUID) -> Bool {
        guard let item = fetchItem(id: id) else {
            return false
        }

        let wasPinned = item.isPinned
        deleteImageFileIfNeeded(for: item)
        deleteLargeTextFileIfNeeded(for: item)
        modelContext.delete(item)
        removePinLabel(for: id)

        if wasPinned {
            normalizePinnedOrder(items: fetchPinnedItems())
        }

        scheduleSave()
        return true
    }
    
    func loadImage(fileName: String) -> NSImage? {
        if let cached = imageMemoryCache.object(forKey: fileName as NSString) {
            return cached
        }
        
        let fileURL = imageCacheDirectory.appendingPathComponent(fileName)
        guard let image = NSImage(contentsOf: fileURL) else {
            return nil
        }
        imageMemoryCache.setObject(image, forKey: fileName as NSString)
        return image
    }
    
    private func loadImageData(fileName: String) -> Data? {
        let fileURL = imageCacheDirectory.appendingPathComponent(fileName)
        return try? Data(contentsOf: fileURL)
    }
    
    private func saveImageItem(_ imageData: Data, dedupeKey: String) {
        let fileName = "\(UUID().uuidString).png"
        let fileURL = imageCacheDirectory.appendingPathComponent(fileName)
        
        do {
            try imageData.write(to: fileURL, options: .atomic)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let image = NSImage(data: imageData) {
                    self.imageMemoryCache.setObject(image, forKey: fileName as NSString)
                }
                let didPersist = self.persist(
                    item: ClipboardItem(type: .image, dedupeKey: dedupeKey, imageFileName: fileName),
                    dedupeKey: dedupeKey
                )
                if !didPersist {
                    self.imageMemoryCache.removeObject(forKey: fileName as NSString)
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
        } catch {
            print("Failed to write image: \(error)")
        }
    }
    
    @discardableResult
    private func persist(item: ClipboardItem, dedupeKey: String) -> Bool {
        let duplicates = matchingItems(for: dedupeKey)
        if duplicates.contains(where: \.isPinned) {
            return false
        }
        
        for duplicate in duplicates {
            deleteImageFileIfNeeded(for: duplicate)
            deleteLargeTextFileIfNeeded(for: duplicate)
            modelContext.delete(duplicate)
        }
        
        modelContext.insert(item)
        trimHistoryIfNeeded()

        return saveModelContext()
    }

    @discardableResult
    private func persistText(_ text: String, dedupeKey: String) -> Bool {
        guard let prepared = prepareTextStorage(for: text, dedupeKey: dedupeKey) else {
            return false
        }
        let didPersist = persistPreparedTextStorage(prepared)
        if !didPersist {
            deleteLargeTextFile(named: prepared.textStorageFileName)
        }
        return didPersist
    }

    @discardableResult
    private func persistPreparedTextStorage(_ prepared: PreparedTextStorage) -> Bool {
        let item = ClipboardItem(
            type: .text,
            dedupeKey: prepared.dedupeKey,
            textContent: prepared.displayText,
            isLargeText: prepared.isLargeText,
            textByteCount: prepared.textByteCount,
            textStorageFileName: prepared.textStorageFileName
        )

        return persist(item: item, dedupeKey: prepared.dedupeKey)
    }
    
    private func trimHistoryIfNeeded() {
        let unpinnedItems = historyItems()
        guard unpinnedItems.count > maxHistoryItems else {
            return
        }
        
        for item in unpinnedItems.dropFirst(maxHistoryItems) {
            deleteImageFileIfNeeded(for: item)
            deleteLargeTextFileIfNeeded(for: item)
            modelContext.delete(item)
        }
    }
    
    private func matchingItems(for dedupeKey: String) -> [ClipboardItem] {
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.dedupeKey == dedupeKey && $0.isManualNote == false }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchAllItems() -> [ClipboardItem] {
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchPinnedItems() -> [ClipboardItem] {
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.isPinned == true }
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).sorted(by: pinnedSortComparator)
    }

    private func fetchHistoryItems() -> [ClipboardItem] {
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.isPinned == false },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchItem(id: UUID) -> ClipboardItem? {
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func nextPinOrder(from items: [ClipboardItem]? = nil) -> Int {
        let currentMax = (items ?? fetchAllItems())
            .filter(\.isPinned)
            .compactMap(\.pinOrder)
            .max() ?? -1
        return currentMax + 1
    }

    private func normalizePinnedOrder(items: [ClipboardItem]? = nil) {
        let sortedPinnedItems = (items ?? fetchAllItems())
            .filter(\.isPinned)
            .sorted(by: pinnedSortComparator)
        for (index, item) in sortedPinnedItems.enumerated() {
            item.pinOrder = index
        }
    }

    private func scheduleSave() {
        pendingSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSaveWorkItem = nil
            _ = self.saveModelContext()
        }
        pendingSaveWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func pinLabels() -> [String: String] {
        cachedPinLabels
    }

    private func removePinLabel(for itemID: UUID) {
        var labels = pinLabels()
        guard labels.removeValue(forKey: itemID.uuidString) != nil else {
            return
        }
        updatePinLabels(labels)
    }

    private func updatePinLabels(_ labels: [String: String]) {
        cachedPinLabels = labels
        cachedPinLabelsByID = Self.makePinLabelsByID(from: labels)
        userDefaults.set(labels, forKey: DefaultsKey.pinLabels)
        NotificationCenter.default.post(name: .clipboardItemsDidChange, object: nil)
    }

    private static func makePinLabelsByID(from labels: [String: String]) -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: labels.compactMap { key, value in
            guard let itemID = UUID(uuidString: key) else { return nil }
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return nil }
            return (itemID, normalized)
        })
    }

    @discardableResult
    private func saveModelContext() -> Bool {
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .clipboardItemsDidChange, object: nil)
            return true
        } catch {
            print("Failed to save clipboard item: \(error)")
            return false
        }
    }

    private var pinnedSortComparator: (ClipboardItem, ClipboardItem) -> Bool {
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
    
    private func deleteImageFileIfNeeded(for item: ClipboardItem) {
        guard item.type == .image, let fileName = item.imageFileName else {
            return
        }
        
        imageMemoryCache.removeObject(forKey: fileName as NSString)
        let fileURL = imageCacheDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func deleteLargeTextFileIfNeeded(for item: ClipboardItem) {
        guard item.type == .text else {
            return
        }
        deleteLargeTextFile(named: item.textStorageFileName)
    }

    private func deleteLargeTextFile(named fileName: String?) {
        guard let fileName else { return }
        let fileURL = largeTextDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func clearDirectoryContents(at directoryURL: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    private func extractRawImageData(from pasteboard: NSPasteboard) -> Data? {
        if let rawData = pasteboard.data(forType: .png) {
            return rawData
        }
        
        if let tiffData = pasteboard.data(forType: .tiff) {
            return tiffData
        }
        
        if let image = NSImage(pasteboard: pasteboard) {
            return image.tiffRepresentation
        }
        
        if let fileURLString = pasteboard.string(forType: .fileURL),
           let fileURL = URL(string: fileURLString),
           fileURL.isFileURL,
           let raw = try? Data(contentsOf: fileURL) {
            return raw
        }
        
        if let items = pasteboard.pasteboardItems {
            for item in items {
                for type in item.types {
                    if let data = item.data(forType: type), NSImage(data: data) != nil {
                        return data
                    }
                }
            }
        }
        
        return nil
    }
    
    private func prepareImageDataForStorage(rawData: Data) -> Data? {
        guard let image = NSImage(data: rawData) else {
            return nil
        }
        return image.normalizedPNGData(maxDimension: 2000)
    }

    func resolvedText(for item: ClipboardItem) -> String? {
        guard item.type == .text else { return nil }
        if item.isLargeText, let fileName = item.textStorageFileName {
            let fileURL = largeTextDirectory.appendingPathComponent(fileName)
            if let data = try? Data(contentsOf: fileURL),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
        }
        return item.textContent
    }

    private func prepareTextStorage(for text: String, dedupeKey: String? = nil) -> PreparedTextStorage? {
        let key = dedupeKey ?? ClipboardDedupeKey.text(text)
        let textByteCount = text.utf8.count
        if textByteCount <= LargeTextPolicy.inlineThresholdBytes {
            return PreparedTextStorage(
                displayText: text,
                isLargeText: false,
                textByteCount: textByteCount,
                textStorageFileName: nil,
                dedupeKey: key
            )
        }

        let fileName = "\(UUID().uuidString).txt"
        let fileURL = largeTextDirectory.appendingPathComponent(fileName)
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            return PreparedTextStorage(
                displayText: Self.storedPreviewText(for: text),
                isLargeText: true,
                textByteCount: textByteCount,
                textStorageFileName: fileName,
                dedupeKey: key
            )
        } catch {
            print("Failed to write large text: \(error)")
            return nil
        }
    }

    private static func storedPreviewText(for text: String) -> String {
        String(text.prefix(LargeTextPolicy.storedPreviewCharacterLimit))
    }

    private func migrateStoredItemsIfNeeded() {
        let allItems = fetchAllItems()
        var didMutate = false

        for item in allItems {
            if item.textFormat != .plain {
                item.textFormat = .plain
                didMutate = true
            }

            if (item.dedupeKey ?? "").isEmpty {
                switch item.type {
                case .text:
                    if let rawText = resolvedText(for: item) {
                        item.dedupeKey = ClipboardDedupeKey.text(rawText)
                        didMutate = true
                    }
                case .image:
                    if let fileName = item.imageFileName,
                       let imageData = loadImageData(fileName: fileName) {
                        item.dedupeKey = ClipboardDedupeKey.image(imageData)
                        didMutate = true
                    }
                }
            }

            guard item.type == .text, let rawText = resolvedText(for: item) else {
                continue
            }

            let rawTextByteCount = rawText.utf8.count
            let shouldBeLarge = rawTextByteCount > LargeTextPolicy.inlineThresholdBytes
            if shouldBeLarge {
                if !item.isLargeText || item.textStorageFileName == nil || item.textContent == rawText {
                    let previousFileName = item.textStorageFileName
                    guard let prepared = prepareTextStorage(for: rawText, dedupeKey: item.dedupeKey) else {
                        continue
                    }
                    item.textContent = prepared.displayText
                    item.isLargeText = true
                    item.textByteCount = prepared.textByteCount
                    item.textStorageFileName = prepared.textStorageFileName
                    item.dedupeKey = prepared.dedupeKey
                    if previousFileName != prepared.textStorageFileName {
                        deleteLargeTextFile(named: previousFileName)
                    }
                    didMutate = true
                }
            } else if item.isLargeText || item.textStorageFileName != nil || item.textByteCount != rawTextByteCount {
                let previousFileName = item.textStorageFileName
                item.textContent = rawText
                item.isLargeText = false
                item.textByteCount = rawTextByteCount
                item.textStorageFileName = nil
                deleteLargeTextFile(named: previousFileName)
                didMutate = true
            }
        }

        if didMutate {
            _ = saveModelContext()
        }
    }
}

extension Notification.Name {
    static let clipboardItemsDidChange = Notification.Name("clipboardItemsDidChange")
}

private extension NSImage {
    func normalizedPNGData(maxDimension: CGFloat) -> Data? {
        guard let tiffRepresentation else { return nil }
        guard let sourceRep = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        
        let sourceSize = NSSize(width: sourceRep.pixelsWide, height: sourceRep.pixelsHigh)
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        
        let scale = min(1, maxDimension / max(sourceSize.width, sourceSize.height))
        let targetSize = NSSize(
            width: max(1, floor(sourceSize.width * scale)),
            height: max(1, floor(sourceSize.height * scale))
        )
        
        guard let outputRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: outputRep)
        context?.imageInterpolation = .high
        NSGraphicsContext.current = context
        draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        
        return outputRep.representation(using: .png, properties: [:])
    }
}
