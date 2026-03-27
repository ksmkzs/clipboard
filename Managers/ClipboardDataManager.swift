import AppKit
import SwiftData

// UIへの強制再描画シグナル
extension Notification.Name {
    static let clipboardUpdated = Notification.Name("clipboardUpdated")
}

class ClipboardDataManager {
    private enum DefaultsKey {
        static let pinLabels = "pin.labels"
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
        let textContent: String?
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
    
    private var imageCacheDirectory: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appDir = paths[0].appendingPathComponent("ClipboardHistoryApp/Images", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: appDir.path) {
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        return appDir
    }
    
    init(modelContext: ModelContext, maxHistoryItems: Int = 150, userDefaults: UserDefaults = .standard) {
        self.modelContext = modelContext
        self.maxHistoryItems = max(1, maxHistoryItems)
        self.userDefaults = userDefaults
    }

    func updateMaxHistoryItems(_ maxHistoryItems: Int) {
        self.maxHistoryItems = max(1, maxHistoryItems)
        trimHistoryIfNeeded()
        saveModelContextAsync(postNotification: true)
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
            let normalized = textString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                return ClipboardCapture(
                    payload: .text(textString),
                    dedupeKey: ClipboardDedupeKey.text(textString)
                )
            }
        }
        
        return nil
    }
    
    func storeCapture(_ capture: ClipboardCapture) {
        switch capture.payload {
        case .text(let text):
            _ = persist(
                item: ClipboardItem(type: .text, textContent: text),
                dedupeKey: capture.dedupeKey
            )
        case .image(let normalizedData):
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                self.saveImageItem(normalizedData, dedupeKey: capture.dedupeKey)
            }
        }
    }

    func pinnedItems() -> [ClipboardItem] {
        fetchAllItems()
            .filter(\.isPinned)
            .sorted(by: pinnedSortComparator)
    }

    func historyItems() -> [ClipboardItem] {
        fetchAllItems()
            .filter { !$0.isPinned }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func pinLabel(for itemID: UUID) -> String? {
        let label = pinLabels()[itemID.uuidString]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return label.isEmpty ? nil : label
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
        saveModelContextAsync(postNotification: true)
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
            textContent: item.textContent,
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
        } else {
            restoredImageFileName = nil
        }

        let item = ClipboardItem(
            type: snapshot.type,
            isPinned: snapshot.isPinned,
            pinOrder: snapshot.pinOrder,
            textContent: snapshot.textContent,
            imageFileName: restoredImageFileName
        )
        item.id = snapshot.id
        item.timestamp = snapshot.timestamp
        modelContext.insert(item)

        if let pinLabel = snapshot.pinLabel {
            _ = setPinLabel(pinLabel, for: snapshot.id)
        }

        normalizePinnedOrder()
        return saveModelContext(postNotification: true)
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
        userDefaults.set(labels, forKey: DefaultsKey.pinLabels)
        NotificationCenter.default.post(name: .clipboardUpdated, object: nil)
        return true
    }

    @discardableResult
    func setPinned(_ isPinned: Bool, for itemID: UUID) -> Bool {
        let allItems = fetchAllItems()
        guard let item = allItems.first(where: { $0.id == itemID }) else {
            return false
        }

        if isPinned {
            if item.isPinned {
                return true
            }
            item.isPinned = true
            item.pinOrder = nextPinOrder(from: allItems)
        } else {
            if !item.isPinned {
                return true
            }
            item.isPinned = false
            item.pinOrder = nil
            normalizePinnedOrder(items: allItems)
        }

        saveModelContextAsync(postNotification: true)
        return true
    }

    @discardableResult
    func updateTextContent(_ text: String, for itemID: UUID, touchTimestamp: Bool = false) -> Bool {
        guard let item = fetchItem(id: itemID), item.type == .text else {
            return false
        }

        item.textContent = text
        if touchTimestamp {
            item.timestamp = Date()
        }
        saveModelContextAsync(postNotification: true)
        return true
    }

    @discardableResult
    func reorderPinnedItems(_ orderedIDs: [UUID]) -> Bool {
        let pinnedItems = self.pinnedItems()
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

        saveModelContextAsync(postNotification: true)
        return true
    }

    @discardableResult
    func deleteItem(id: UUID) -> Bool {
        let allItems = fetchAllItems()
        guard let item = allItems.first(where: { $0.id == id }) else {
            return false
        }

        let wasPinned = item.isPinned
        deleteImageFileIfNeeded(for: item)
        modelContext.delete(item)
        removePinLabel(for: id)

        if wasPinned {
            normalizePinnedOrder(items: allItems.filter { $0.id != id })
        }

        saveModelContextAsync(postNotification: true)
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
                    item: ClipboardItem(type: .image, imageFileName: fileName),
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
            modelContext.delete(duplicate)
        }
        
        modelContext.insert(item)
        trimHistoryIfNeeded()

        return saveModelContext(postNotification: true)
    }
    
    private func trimHistoryIfNeeded() {
        let unpinnedItems = historyItems()
        guard unpinnedItems.count > maxHistoryItems else {
            return
        }
        
        for item in unpinnedItems.dropFirst(maxHistoryItems) {
            deleteImageFileIfNeeded(for: item)
            modelContext.delete(item)
        }
    }
    
    private func matchingItems(for dedupeKey: String) -> [ClipboardItem] {
        fetchAllItems().filter { item in
            ClipboardDedupeKey.forItem(item, imageDataLoader: loadImageData(fileName:)) == dedupeKey
        }
    }

    private func fetchAllItems() -> [ClipboardItem] {
        let descriptor = FetchDescriptor<ClipboardItem>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchItem(id: UUID) -> ClipboardItem? {
        fetchAllItems().first { $0.id == id }
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

    private func saveModelContextAsync(postNotification: Bool) {
        if postNotification {
            NotificationCenter.default.post(name: .clipboardUpdated, object: nil)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            _ = self.saveModelContext(postNotification: false)
        }
    }

    private func pinLabels() -> [String: String] {
        userDefaults.dictionary(forKey: DefaultsKey.pinLabels) as? [String: String] ?? [:]
    }

    private func removePinLabel(for itemID: UUID) {
        var labels = pinLabels()
        guard labels.removeValue(forKey: itemID.uuidString) != nil else {
            return
        }
        userDefaults.set(labels, forKey: DefaultsKey.pinLabels)
    }

    @discardableResult
    private func saveModelContext(postNotification: Bool) -> Bool {
        do {
            try modelContext.save()
            if postNotification {
                NotificationCenter.default.post(name: .clipboardUpdated, object: nil)
            }
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
