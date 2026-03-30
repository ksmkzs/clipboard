import XCTest
import SQLite3
import SwiftData
@testable import ClipboardHistory

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
final class ClipboardStoreBootstrapperTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var storePaths: ClipboardStorePaths!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardStoreBootstrapperTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        temporaryDirectory = base
        storePaths = ClipboardStorePaths(
            appSupportDirectory: base,
            storeURL: base.appendingPathComponent("ClipboardHistory.store"),
            imageDirectory: base.appendingPathComponent("Images", isDirectory: true),
            largeTextDirectory: base.appendingPathComponent("LargeText", isDirectory: true),
            noteDraftDirectory: base.appendingPathComponent("Notes", isDirectory: true),
            codexIntegrationDirectory: base.appendingPathComponent(".clipboardhistory/bin", isDirectory: true),
            codexCompletionDirectory: base.appendingPathComponent("Codex/Sessions", isDirectory: true),
            codexSessionStateDirectory: base.appendingPathComponent("Codex/State", isDirectory: true),
            codexRequestDirectory: base.appendingPathComponent("Codex", isDirectory: true),
            codexOpenRequestURL: base.appendingPathComponent("Codex/open-request.txt"),
            codexHelperScriptURL: base.appendingPathComponent(".clipboardhistory/bin/clipboardhistory-codex-editor")
        )
        try storePaths.ensureDirectories()
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        storePaths = nil
    }

    func testMigratesLegacyStoreIntoModernContainer() throws {
        let largeText = String(repeating: "legacy-text-", count: 35_000)
        let id = UUID()
        try createLegacyStore(
            at: storePaths.storeURL,
            rows: [
                LegacyRow(
                    id: id,
                    timestamp: Date(timeIntervalSinceReferenceDate: 123_456),
                    type: .text,
                    isPinned: true,
                    pinOrder: 0,
                    textContent: largeText,
                    imageFileName: nil
                )
            ]
        )

        let container = try ClipboardStoreBootstrapper.makeContainer(storePaths: storePaths)
        let context = ModelContext(container)
        let items = try context.fetch(FetchDescriptor<ClipboardItem>())
        let item = try XCTUnwrap(items.first)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(item.id, id)
        XCTAssertTrue(item.isPinned)
        XCTAssertEqual(item.pinOrder, 0)
        XCTAssertTrue(item.isLargeText)
        XCTAssertEqual(item.textByteCount, largeText.utf8.count)
        XCTAssertEqual(item.textContent, String(largeText.prefix(LargeTextPolicy.storedPreviewCharacterLimit)))
        XCTAssertEqual(item.dedupeKey, ClipboardDedupeKey.text(largeText))

        let fileName = try XCTUnwrap(item.textStorageFileName)
        let fileURL = storePaths.largeTextDirectory.appendingPathComponent(fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let restoredText = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(restoredText, largeText)
    }

    private func createLegacyStore(at url: URL, rows: [LegacyRow]) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw SQLiteTestError.openDatabase
        }
        defer { sqlite3_close(database) }

        try execute(
            """
            CREATE TABLE ZCLIPBOARDITEM (
                Z_PK INTEGER PRIMARY KEY,
                Z_ENT INTEGER,
                Z_OPT INTEGER,
                ZISPINNED INTEGER,
                ZPINORDER INTEGER,
                ZTYPE INTEGER,
                ZTIMESTAMP TIMESTAMP,
                ZIMAGEFILENAME VARCHAR,
                ZTEXTCONTENT VARCHAR,
                ZID BLOB
            );
            """,
            database: database
        )

        try execute(
            """
            INSERT INTO ZCLIPBOARDITEM
            (Z_PK, Z_ENT, Z_OPT, ZISPINNED, ZPINORDER, ZTYPE, ZTIMESTAMP, ZIMAGEFILENAME, ZTEXTCONTENT, ZID)
            VALUES (?, 1, 1, ?, ?, ?, ?, ?, ?, ?);
            """,
            database: database,
            rows: rows
        )
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteTestError.exec(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func execute(_ sql: String, database: OpaquePointer, rows: [LegacyRow]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteTestError.exec(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        for (index, row) in rows.enumerated() {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_int(statement, 1, Int32(index + 1))
            sqlite3_bind_int(statement, 2, row.isPinned ? 1 : 0)
            if let pinOrder = row.pinOrder {
                sqlite3_bind_int(statement, 3, Int32(pinOrder))
            } else {
                sqlite3_bind_null(statement, 3)
            }
            sqlite3_bind_int(statement, 4, Int32(row.type.rawValue))
            sqlite3_bind_double(statement, 5, row.timestamp.timeIntervalSinceReferenceDate)
            bindText(row.imageFileName, to: 6, statement: statement)
            bindText(row.textContent, to: 7, statement: statement)
            bindUUID(row.id, to: 8, statement: statement)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteTestError.exec(String(cString: sqlite3_errmsg(database)))
            }
        }
    }

    private func bindText(_ string: String?, to index: Int32, statement: OpaquePointer) {
        guard let string else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, string, -1, SQLITE_TRANSIENT)
    }

    private func bindUUID(_ uuid: UUID, to index: Int32, statement: OpaquePointer) {
        var value = uuid.uuid
        withUnsafeBytes(of: &value) { rawBuffer in
            sqlite3_bind_blob(statement, index, rawBuffer.baseAddress, Int32(rawBuffer.count), SQLITE_TRANSIENT)
        }
    }

    private struct LegacyRow {
        let id: UUID
        let timestamp: Date
        let type: ClipboardItemType
        let isPinned: Bool
        let pinOrder: Int?
        let textContent: String?
        let imageFileName: String?
    }

    private enum SQLiteTestError: Error {
        case openDatabase
        case exec(String)
    }
}
