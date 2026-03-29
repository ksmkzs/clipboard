import Foundation
import SQLite3
import SwiftData

enum ClipboardStoreBootstrapper {
    private struct LegacyClipboardRow {
        let id: UUID
        let timestamp: Date
        let type: ClipboardItemType
        let isPinned: Bool
        let pinOrder: Int?
        let textContent: String?
        let imageFileName: String?
    }

    private static let requiredModernColumns: Set<String> = [
        "ZDEDUPEKEY",
        "ZISLARGETEXT",
        "ZTEXTBYTECOUNT",
        "ZTEXTSTORAGEFILENAME",
        "ZISMANUALNOTE",
        "ZTEXTFORMATRAWVALUE"
    ]

    @MainActor
    static func makeContainer(
        storePaths: ClipboardStorePaths = .default(),
        fileManager: FileManager = .default
    ) throws -> ModelContainer {
        let schema = Schema([ClipboardItem.self])
        try storePaths.ensureDirectories(fileManager: fileManager)

        if try requiresLegacyMigration(at: storePaths.storeURL) {
            return try migrateLegacyStore(schema: schema, storePaths: storePaths, fileManager: fileManager)
        }

        do {
            return try buildContainer(schema: schema, storeURL: storePaths.storeURL)
        } catch {
            return try recoverFromBrokenStore(
                originalError: error,
                schema: schema,
                storePaths: storePaths,
                fileManager: fileManager
            )
        }
    }

    private static func buildContainer(schema: Schema, storeURL: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, url: storeURL, allowsSave: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func requiresLegacyMigration(at storeURL: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return false
        }
        let columns = try loadColumnNames(from: storeURL)
        guard !columns.isEmpty else {
            return false
        }
        return !requiredModernColumns.isSubset(of: columns)
    }

    @MainActor
    private static func migrateLegacyStore(
        schema: Schema,
        storePaths: ClipboardStorePaths,
        fileManager: FileManager
    ) throws -> ModelContainer {
        let legacyRows = try loadLegacyRows(from: storePaths.storeURL)
        let backup = try moveStoreAside(storeURL: storePaths.storeURL, fileManager: fileManager)
        do {
            let container = try buildContainer(schema: schema, storeURL: storePaths.storeURL)
            try importLegacyRows(
                legacyRows,
                into: container.mainContext,
                storePaths: storePaths,
                fileManager: fileManager
            )
            try deleteStoreBackup(backup, fileManager: fileManager)
            return container
        } catch {
            try? removeStoreFiles(at: storePaths.storeURL, fileManager: fileManager)
            try restoreStoreBackup(backup, originalStoreURL: storePaths.storeURL, fileManager: fileManager)
            throw error
        }
    }

    @MainActor
    private static func recoverFromBrokenStore(
        originalError: Error,
        schema: Schema,
        storePaths: ClipboardStorePaths,
        fileManager: FileManager
    ) throws -> ModelContainer {
        let backup = try moveStoreAside(storeURL: storePaths.storeURL, fileManager: fileManager)
        do {
            let container = try buildContainer(schema: schema, storeURL: storePaths.storeURL)
            return container
        } catch {
            try? removeStoreFiles(at: storePaths.storeURL, fileManager: fileManager)
            try? restoreStoreBackup(backup, originalStoreURL: storePaths.storeURL, fileManager: fileManager)
            throw originalError
        }
    }

    @MainActor
    private static func importLegacyRows(
        _ rows: [LegacyClipboardRow],
        into context: ModelContext,
        storePaths: ClipboardStorePaths,
        fileManager: FileManager
    ) throws {
        for row in rows {
            let item: ClipboardItem
            switch row.type {
            case .text:
                let rawText = row.textContent ?? ""
                let textByteCount = rawText.utf8.count
                let dedupeKey = ClipboardDedupeKey.text(rawText)
                if textByteCount > LargeTextPolicy.inlineThresholdBytes {
                    let fileName = "\(UUID().uuidString).txt"
                    let fileURL = storePaths.largeTextDirectory.appendingPathComponent(fileName)
                    try rawText.write(to: fileURL, atomically: true, encoding: .utf8)
                    item = ClipboardItem(
                        type: .text,
                        isPinned: row.isPinned,
                        pinOrder: row.pinOrder,
                        dedupeKey: dedupeKey,
                        isManualNote: false,
                        textContent: String(rawText.prefix(LargeTextPolicy.storedPreviewCharacterLimit)),
                        isLargeText: true,
                        textByteCount: textByteCount,
                        textStorageFileName: fileName,
                        textFormat: .plain
                    )
                } else {
                    item = ClipboardItem(
                        type: .text,
                        isPinned: row.isPinned,
                        pinOrder: row.pinOrder,
                        dedupeKey: dedupeKey,
                        isManualNote: false,
                        textContent: rawText,
                        isLargeText: false,
                        textByteCount: textByteCount,
                        textStorageFileName: nil,
                        textFormat: .plain
                    )
                }
            case .image:
                let dedupeKey = imageDedupeKey(fileName: row.imageFileName, storePaths: storePaths) ?? "img-missing:\(row.id.uuidString)"
                item = ClipboardItem(
                    type: .image,
                    isPinned: row.isPinned,
                    pinOrder: row.pinOrder,
                    dedupeKey: dedupeKey,
                    isManualNote: false,
                    imageFileName: row.imageFileName
                )
            }
            item.id = row.id
            item.timestamp = row.timestamp
            context.insert(item)
        }

        try context.save()
    }

    private static func imageDedupeKey(fileName: String?, storePaths: ClipboardStorePaths) -> String? {
        guard let fileName else { return nil }
        let fileURL = storePaths.imageDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return ClipboardDedupeKey.image(data)
    }

    private static func loadColumnNames(from storeURL: URL) throws -> Set<String> {
        var database: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
            throw SQLiteError.openDatabase
        }
        defer { sqlite3_close(database) }

        let statement = try prepareStatement("PRAGMA table_info(ZCLIPBOARDITEM);", database: database)
        defer { sqlite3_finalize(statement) }

        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) {
                columns.insert(String(cString: name))
            }
        }
        return columns
    }

    private static func loadLegacyRows(from storeURL: URL) throws -> [LegacyClipboardRow] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
            throw SQLiteError.openDatabase
        }
        defer { sqlite3_close(database) }

        let statement = try prepareStatement(
            """
            SELECT ZTYPE, ZISPINNED, ZPINORDER, ZTIMESTAMP, ZIMAGEFILENAME, ZTEXTCONTENT, ZID
            FROM ZCLIPBOARDITEM
            ORDER BY ZTIMESTAMP DESC
            """,
            database: database
        )
        defer { sqlite3_finalize(statement) }

        var rows: [LegacyClipboardRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let typeValue = Int(sqlite3_column_int(statement, 0))
            guard let type = ClipboardItemType(rawValue: typeValue) else { continue }
            let isPinned = sqlite3_column_int(statement, 1) != 0
            let pinOrder = sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 2))
            let timestamp = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 3))
            let imageFileName = stringValue(statement: statement, column: 4)
            let textContent = stringValue(statement: statement, column: 5)
            guard let id = uuidValue(statement: statement, column: 6) else { continue }

            rows.append(
                LegacyClipboardRow(
                    id: id,
                    timestamp: timestamp,
                    type: type,
                    isPinned: isPinned,
                    pinOrder: pinOrder,
                    textContent: textContent,
                    imageFileName: imageFileName
                )
            )
        }

        return rows
    }

    private static func prepareStatement(_ sql: String, database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteError.prepareStatement(message: String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    private static func stringValue(statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: pointer)
    }

    private static func uuidValue(statement: OpaquePointer, column: Int32) -> UUID? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let bytes = sqlite3_column_blob(statement, column) else {
            return nil
        }
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count == 16 else { return nil }
        let data = Data(bytes: bytes, count: count)
        return data.withUnsafeBytes { rawBuffer in
            let b = rawBuffer.bindMemory(to: UInt8.self)
            guard b.count == 16 else { return nil }
            return UUID(uuid: (
                b[0], b[1], b[2], b[3],
                b[4], b[5], b[6], b[7],
                b[8], b[9], b[10], b[11],
                b[12], b[13], b[14], b[15]
            ))
        }
    }

    private static func moveStoreAside(storeURL: URL, fileManager: FileManager) throws -> [URL: URL] {
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        var movedFiles: [URL: URL] = [:]
        for originalURL in storeSidecarURLs(for: storeURL) where fileManager.fileExists(atPath: originalURL.path) {
            let backupURL = originalURL.deletingLastPathComponent().appendingPathComponent("\(originalURL.lastPathComponent).backup-\(timestamp)")
            try fileManager.moveItem(at: originalURL, to: backupURL)
            movedFiles[originalURL] = backupURL
        }
        return movedFiles
    }

    private static func restoreStoreBackup(_ backup: [URL: URL], originalStoreURL: URL, fileManager: FileManager) throws {
        try removeStoreFiles(at: originalStoreURL, fileManager: fileManager)
        for (originalURL, backupURL) in backup {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.moveItem(at: backupURL, to: originalURL)
            }
        }
    }

    private static func deleteStoreBackup(_ backup: [URL: URL], fileManager: FileManager) throws {
        for backupURL in backup.values where fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
    }

    private static func removeStoreFiles(at storeURL: URL, fileManager: FileManager) throws {
        for url in storeSidecarURLs(for: storeURL) where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private static func storeSidecarURLs(for storeURL: URL) -> [URL] {
        [
            storeURL,
            storeURL.appendingPathExtension("shm"),
            storeURL.appendingPathExtension("wal")
        ]
    }

    private enum SQLiteError: Error {
        case openDatabase
        case prepareStatement(message: String)
    }
}
