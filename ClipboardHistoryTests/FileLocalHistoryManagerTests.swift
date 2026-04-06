import XCTest
@testable import ClipboardHistory

final class FileLocalHistoryManagerTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var storePaths: ClipboardStorePaths!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FileLocalHistoryManagerTests.\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        storePaths = ClipboardStorePaths(
            appSupportDirectory: temporaryDirectory,
            storeURL: temporaryDirectory.appendingPathComponent("ClipboardHistory.store"),
            imageDirectory: temporaryDirectory.appendingPathComponent("Images", isDirectory: true),
            largeTextDirectory: temporaryDirectory.appendingPathComponent("LargeText", isDirectory: true),
            noteDraftDirectory: temporaryDirectory.appendingPathComponent("Notes", isDirectory: true),
            localHistoryDirectory: temporaryDirectory.appendingPathComponent("LocalHistory", isDirectory: true),
            codexIntegrationDirectory: temporaryDirectory.appendingPathComponent(".clipboardhistory/bin", isDirectory: true),
            codexCompletionDirectory: temporaryDirectory.appendingPathComponent("Codex/Sessions", isDirectory: true),
            codexSessionStateDirectory: temporaryDirectory.appendingPathComponent("Codex/State", isDirectory: true),
            codexRequestDirectory: temporaryDirectory.appendingPathComponent("Codex", isDirectory: true),
            codexOpenRequestURL: temporaryDirectory.appendingPathComponent("Codex/open-request.txt"),
            codexHelperScriptURL: temporaryDirectory.appendingPathComponent(".clipboardhistory/bin/clipboardhistory-codex-editor")
        )
        try storePaths.ensureDirectories()
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        storePaths = nil
        temporaryDirectory = nil
    }

    func testRegisterOpenedFileCapturesInitialAndUpdatedSnapshots() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("draft.md")
        try "first".write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = FileLocalHistoryManager(storePaths: storePaths)
        manager.apply(
            settings: FileLocalHistoryManager.Settings(
                isEnabled: true,
                trackOpenedFiles: true,
                watchedDirectoryPath: "",
                watchedExtensions: "",
                watchDirectoryRecursively: true,
                maxSnapshotsPerFile: 10,
                deletedSourceBehavior: .keepAsOrphan,
                orphanGracePeriodDays: 30,
                pollingInterval: 10.0
            )
        )

        manager.registerOpenedFile(fileURL, waitUntilFinished: true)
        XCTAssertEqual(manager.historyEntries(for: fileURL).count, 1)

        try "second".write(to: fileURL, atomically: true, encoding: .utf8)
        manager.captureNowIfNeeded(for: fileURL, waitUntilFinished: true)

        let entries = manager.historyEntries(for: fileURL)
        XCTAssertEqual(entries.count, 2)
        XCTAssertNotEqual(entries[0].contentHash, entries[1].contentHash)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.historyDirectoryURL(for: fileURL).path))
    }

    func testOpenedFileTrackingDoesNotFollowReplacementAtSamePath() throws {
        let movedDirectory = temporaryDirectory.appendingPathComponent("Moved", isDirectory: true)
        try FileManager.default.createDirectory(at: movedDirectory, withIntermediateDirectories: true)

        let originalURL = temporaryDirectory.appendingPathComponent("draft.md")
        let movedURL = movedDirectory.appendingPathComponent("draft.md")
        try "first".write(to: originalURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: true,
            watchedDirectoryPath: "",
            watchedExtensions: "",
            deletedSourceBehavior: .keepAsOrphan
        )
        manager.registerOpenedFile(originalURL, waitUntilFinished: true)

        try FileManager.default.moveItem(at: originalURL, to: movedURL)
        try "replacement".write(to: originalURL, atomically: true, encoding: .utf8)

        manager.scanNow()

        XCTAssertTrue(manager.trackingInfo(for: movedURL).isTrackedByOpenedFile)
        XCTAssertFalse(manager.trackingInfo(for: originalURL).isTrackedByOpenedFile)
        XCTAssertEqual(manager.historyEntries(for: movedURL).count, 1)
        XCTAssertEqual(
            manager.snapshotText(for: try XCTUnwrap(manager.historyEntries(for: movedURL).first), fileURL: movedURL),
            "first"
        )
        XCTAssertEqual(manager.historyEntries(for: originalURL).count, 0)

        try "replacement updated".write(to: originalURL, atomically: true, encoding: .utf8)
        manager.scanNow()

        XCTAssertEqual(manager.historyEntries(for: originalURL).count, 0)
    }

    func testReenablingOpenedFileTrackingRequiresReopen() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("draft.md")
        try "first".write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: true,
            watchedDirectoryPath: "",
            watchedExtensions: "",
            deletedSourceBehavior: .keepAsOrphan
        )
        manager.registerOpenedFile(fileURL, waitUntilFinished: true)
        XCTAssertEqual(manager.historyEntries(for: fileURL).count, 1)

        manager.apply(
            settings: FileLocalHistoryManager.Settings(
                isEnabled: true,
                trackOpenedFiles: false,
                watchedDirectoryPath: "",
                watchedExtensions: "",
                watchDirectoryRecursively: true,
                maxSnapshotsPerFile: 10,
                deletedSourceBehavior: .keepAsOrphan,
                orphanGracePeriodDays: 30,
                pollingInterval: 10.0
            )
        )
        XCTAssertFalse(manager.trackingInfo(for: fileURL).isTrackedByOpenedFile)

        manager.apply(
            settings: FileLocalHistoryManager.Settings(
                isEnabled: true,
                trackOpenedFiles: true,
                watchedDirectoryPath: "",
                watchedExtensions: "",
                watchDirectoryRecursively: true,
                maxSnapshotsPerFile: 10,
                deletedSourceBehavior: .keepAsOrphan,
                orphanGracePeriodDays: 30,
                pollingInterval: 10.0
            )
        )

        try "second".write(to: fileURL, atomically: true, encoding: .utf8)
        manager.scanNow()

        XCTAssertEqual(manager.historyEntries(for: fileURL).count, 1)

        manager.registerOpenedFile(fileURL, waitUntilFinished: true)

        XCTAssertEqual(manager.historyEntries(for: fileURL).count, 2)
    }

    func testScanCapturesSameSizeChangesEvenWhenModificationDateIsUnchanged() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("draft.md")
        try "alpha".write(to: fileURL, atomically: true, encoding: .utf8)

        let originalModificationDate = try XCTUnwrap(
            try fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        )

        let manager = makeManager(
            trackOpenedFiles: true,
            watchedDirectoryPath: "",
            watchedExtensions: "",
            deletedSourceBehavior: .keepAsOrphan
        )
        manager.registerOpenedFile(fileURL, waitUntilFinished: true)

        try "bravo".write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: originalModificationDate], ofItemAtPath: fileURL.path)

        manager.scanNow()

        let entries = manager.historyEntries(for: fileURL)
        XCTAssertEqual(entries.count, 2)
        XCTAssertNotEqual(entries[0].contentHash, entries[1].contentHash)
    }

    func testDirectoryWatchCapturesMatchingExtensionsOnly() throws {
        let watchedDirectory = temporaryDirectory.appendingPathComponent("Watched", isDirectory: true)
        try FileManager.default.createDirectory(at: watchedDirectory, withIntermediateDirectories: true)

        let includedFileURL = watchedDirectory.appendingPathComponent("notes.txt")
        let excludedFileURL = watchedDirectory.appendingPathComponent("image.png")
        try "tracked".write(to: includedFileURL, atomically: true, encoding: .utf8)
        try "ignored".write(to: excludedFileURL, atomically: true, encoding: .utf8)

        let manager = FileLocalHistoryManager(storePaths: storePaths)
        manager.apply(
            settings: FileLocalHistoryManager.Settings(
                isEnabled: true,
                trackOpenedFiles: false,
                watchedDirectoryPath: watchedDirectory.path,
                watchedExtensions: "txt,md",
                watchDirectoryRecursively: true,
                maxSnapshotsPerFile: 10,
                deletedSourceBehavior: .keepAsOrphan,
                orphanGracePeriodDays: 30,
                pollingInterval: 10.0
            )
        )

        manager.scanNow()

        XCTAssertEqual(manager.historyEntries(for: includedFileURL).count, 1)
        XCTAssertEqual(manager.historyEntries(for: excludedFileURL).count, 0)
    }

    func testWatchedFileRecreatedAtSamePathWithSameContentCapturesNewBaseline() throws {
        let watchedDirectory = temporaryDirectory.appendingPathComponent("Watched", isDirectory: true)
        try FileManager.default.createDirectory(at: watchedDirectory, withIntermediateDirectories: true)

        let fileURL = watchedDirectory.appendingPathComponent("draft.md")
        try "same".write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: false,
            watchedDirectoryPath: watchedDirectory.path,
            watchedExtensions: "md",
            deletedSourceBehavior: .keepAsOrphan
        )
        manager.scanNow()
        XCTAssertEqual(manager.historyEntries(for: fileURL).count, 1)

        try FileManager.default.removeItem(at: fileURL)
        try "same".write(to: fileURL, atomically: true, encoding: .utf8)

        manager.scanNow()

        let entries = manager.historyEntries(for: fileURL)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(
            manager.snapshotText(for: try XCTUnwrap(entries.first), fileURL: fileURL),
            "same"
        )
    }

    func testRegisterOpenedFileCapturesBaselineForWatchedFileWhenOpenedTrackingIsDisabled() throws {
        let watchedDirectory = temporaryDirectory.appendingPathComponent("Watched", isDirectory: true)
        try FileManager.default.createDirectory(at: watchedDirectory, withIntermediateDirectories: true)

        let manager = makeManager(
            trackOpenedFiles: false,
            watchedDirectoryPath: watchedDirectory.path,
            watchedExtensions: "md",
            deletedSourceBehavior: .keepAsOrphan
        )
        manager.scanNow()

        let fileURL = watchedDirectory.appendingPathComponent("draft.md")
        try "first".write(to: fileURL, atomically: true, encoding: .utf8)

        manager.registerOpenedFile(fileURL, waitUntilFinished: true)

        let info = manager.trackingInfo(for: fileURL)
        XCTAssertTrue(info.isTrackedByWatchedDirectory)
        XCTAssertFalse(info.isTrackedByOpenedFile)
        XCTAssertEqual(manager.historyEntries(for: fileURL).count, 1)
    }

    func testTrackingModeCoverageMatrix() throws {
        struct Scenario {
            let name: String
            let trackOpenedFiles: Bool
            let watchedExtensions: String
            let registerOpenedFile: Bool
            let scanAfterSetup: Bool
            let expectedOpenedTracking: Bool
            let expectedWatchedTracking: Bool
            let expectedHistoryCount: Int
        }

        let watchedDirectory = temporaryDirectory.appendingPathComponent("Watched", isDirectory: true)
        try FileManager.default.createDirectory(at: watchedDirectory, withIntermediateDirectories: true)

        let scenarios: [Scenario] = [
            Scenario(
                name: "opened-only",
                trackOpenedFiles: true,
                watchedExtensions: "",
                registerOpenedFile: true,
                scanAfterSetup: false,
                expectedOpenedTracking: true,
                expectedWatchedTracking: false,
                expectedHistoryCount: 1
            ),
            Scenario(
                name: "watched-only",
                trackOpenedFiles: false,
                watchedExtensions: "md",
                registerOpenedFile: false,
                scanAfterSetup: true,
                expectedOpenedTracking: false,
                expectedWatchedTracking: true,
                expectedHistoryCount: 1
            ),
            Scenario(
                name: "opened-and-watched",
                trackOpenedFiles: true,
                watchedExtensions: "md",
                registerOpenedFile: true,
                scanAfterSetup: true,
                expectedOpenedTracking: true,
                expectedWatchedTracking: true,
                expectedHistoryCount: 1
            ),
            Scenario(
                name: "untracked",
                trackOpenedFiles: false,
                watchedExtensions: "",
                registerOpenedFile: true,
                scanAfterSetup: false,
                expectedOpenedTracking: false,
                expectedWatchedTracking: false,
                expectedHistoryCount: 0
            )
        ]

        for scenario in scenarios {
            let fileURL = watchedDirectory.appendingPathComponent("\(scenario.name).md")
            try "content-\(scenario.name)".write(to: fileURL, atomically: true, encoding: .utf8)

            let manager = makeManager(
                trackOpenedFiles: scenario.trackOpenedFiles,
                watchedDirectoryPath: scenario.watchedExtensions.isEmpty ? "" : watchedDirectory.path,
                watchedExtensions: scenario.watchedExtensions,
                deletedSourceBehavior: .keepAsOrphan
            )

            if scenario.registerOpenedFile {
                manager.registerOpenedFile(fileURL, waitUntilFinished: true)
            }
            if scenario.scanAfterSetup {
                manager.scanNow()
            }

            let info = manager.trackingInfo(for: fileURL)
            XCTAssertEqual(info.isTrackedByOpenedFile, scenario.expectedOpenedTracking, scenario.name)
            XCTAssertEqual(info.isTrackedByWatchedDirectory, scenario.expectedWatchedTracking, scenario.name)
            XCTAssertEqual(manager.historyEntries(for: fileURL).count, scenario.expectedHistoryCount, scenario.name)
        }
    }

    func testDirectoryWatchHonorsRecursionSetting() throws {
        let watchedDirectory = temporaryDirectory.appendingPathComponent("Watched", isDirectory: true)
        let nestedDirectory = watchedDirectory.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)

        let topLevelURL = watchedDirectory.appendingPathComponent("top.md")
        let nestedURL = nestedDirectory.appendingPathComponent("nested.md")
        try "top".write(to: topLevelURL, atomically: true, encoding: .utf8)
        try "nested".write(to: nestedURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: false,
            watchedDirectoryPath: watchedDirectory.path,
            watchedExtensions: "md",
            deletedSourceBehavior: .keepAsOrphan,
            watchDirectoryRecursively: false
        )

        manager.scanNow()
        XCTAssertEqual(manager.historyEntries(for: topLevelURL).count, 1)
        XCTAssertEqual(manager.historyEntries(for: nestedURL).count, 0)

        manager.apply(
            settings: makeSettings(
                trackOpenedFiles: false,
                watchedDirectoryPath: watchedDirectory.path,
                watchedExtensions: "md",
                deletedSourceBehavior: .keepAsOrphan,
                watchDirectoryRecursively: true
            )
        )
        manager.scanNow()

        XCTAssertEqual(manager.historyEntries(for: topLevelURL).count, 1)
        XCTAssertEqual(manager.historyEntries(for: nestedURL).count, 1)
    }

    func testWatchedDirectoryExtensionNormalizationMatchesDotsSpacesAndCase() throws {
        let watchedDirectory = temporaryDirectory.appendingPathComponent("Watched", isDirectory: true)
        try FileManager.default.createDirectory(at: watchedDirectory, withIntermediateDirectories: true)

        let markdownURL = watchedDirectory.appendingPathComponent("note.MD")
        let textURL = watchedDirectory.appendingPathComponent("plain.txt")
        let longMarkdownURL = watchedDirectory.appendingPathComponent("readme.markdown")
        let ignoredURL = watchedDirectory.appendingPathComponent("image.png")
        try "md".write(to: markdownURL, atomically: true, encoding: .utf8)
        try "txt".write(to: textURL, atomically: true, encoding: .utf8)
        try "markdown".write(to: longMarkdownURL, atomically: true, encoding: .utf8)
        try "png".write(to: ignoredURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: false,
            watchedDirectoryPath: watchedDirectory.path,
            watchedExtensions: " .md ; txt markdown ",
            deletedSourceBehavior: .keepAsOrphan
        )

        manager.scanNow()

        XCTAssertEqual(manager.historyEntries(for: markdownURL).count, 1)
        XCTAssertEqual(manager.historyEntries(for: textURL).count, 1)
        XCTAssertEqual(manager.historyEntries(for: longMarkdownURL).count, 1)
        XCTAssertEqual(manager.historyEntries(for: ignoredURL).count, 0)
    }

    func testTrackingInfoDistinguishesOpenedAndWatchedSources() throws {
        let watchedDirectory = temporaryDirectory.appendingPathComponent("Watched", isDirectory: true)
        try FileManager.default.createDirectory(at: watchedDirectory, withIntermediateDirectories: true)
        let fileURL = watchedDirectory.appendingPathComponent("draft.md")
        try "tracked".write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: true,
            watchedDirectoryPath: watchedDirectory.path,
            watchedExtensions: "md",
            deletedSourceBehavior: .keepAsOrphan
        )

        manager.registerOpenedFile(fileURL, waitUntilFinished: true)
        let info = manager.trackingInfo(for: fileURL)

        XCTAssertTrue(info.isTracked)
        XCTAssertTrue(info.isTrackedByOpenedFile)
        XCTAssertTrue(info.isTrackedByWatchedDirectory)
        XCTAssertEqual(info.historyEntryCount, 1)
        XCTAssertTrue(info.sourceFileExists)
    }

    func testRegisterOpenedFileDoesNotTrackWhenOpenedFileTrackingIsDisabled() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("draft.txt")
        try "first".write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: false,
            watchedDirectoryPath: "",
            watchedExtensions: "",
            deletedSourceBehavior: .keepAsOrphan
        )

        manager.registerOpenedFile(fileURL, waitUntilFinished: true)

        XCTAssertEqual(manager.historyEntries(for: fileURL).count, 0)
        XCTAssertFalse(manager.trackingInfo(for: fileURL).isTracked)
    }

    func testRegisterOpenedFileDoesNotTrackWhenHistoryIsDisabled() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("draft.txt")
        try "first".write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = FileLocalHistoryManager(storePaths: storePaths)
        manager.apply(
            settings: FileLocalHistoryManager.Settings(
                isEnabled: false,
                trackOpenedFiles: true,
                watchedDirectoryPath: "",
                watchedExtensions: "",
                watchDirectoryRecursively: true,
                maxSnapshotsPerFile: 10,
                deletedSourceBehavior: .keepAsOrphan,
                orphanGracePeriodDays: 30,
                pollingInterval: 10.0
            )
        )

        manager.registerOpenedFile(fileURL, waitUntilFinished: true)

        XCTAssertEqual(manager.historyEntries(for: fileURL).count, 0)
        XCTAssertFalse(manager.trackingInfo(for: fileURL).isTracked)
    }

    func testDeleteSnapshotRemovesOnlySelectedEntry() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("draft.md")
        try "first".write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: true,
            watchedDirectoryPath: "",
            watchedExtensions: "",
            deletedSourceBehavior: .keepAsOrphan
        )
        manager.registerOpenedFile(fileURL, waitUntilFinished: true)

        try "second".write(to: fileURL, atomically: true, encoding: .utf8)
        manager.captureNowIfNeeded(for: fileURL, waitUntilFinished: true)
        try "third".write(to: fileURL, atomically: true, encoding: .utf8)
        manager.captureNowIfNeeded(for: fileURL, waitUntilFinished: true)

        let entries = manager.historyEntries(for: fileURL)
        XCTAssertEqual(entries.count, 3)

        XCTAssertTrue(manager.deleteSnapshot(entries[1], for: fileURL))

        let remaining = manager.historyEntries(for: fileURL)
        XCTAssertEqual(remaining.count, 2)
        XCTAssertFalse(remaining.contains(where: { $0.snapshotFileName == entries[1].snapshotFileName }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.historyDirectoryURL(for: fileURL).path))
    }

    func testDeleteHistoryRemovesHistoryDirectory() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("draft.md")
        try "first".write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: true,
            watchedDirectoryPath: "",
            watchedExtensions: "",
            deletedSourceBehavior: .keepAsOrphan
        )
        manager.registerOpenedFile(fileURL, waitUntilFinished: true)

        XCTAssertTrue(manager.deleteHistory(for: fileURL))
        XCTAssertEqual(manager.historyEntries(for: fileURL).count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.historyDirectoryURL(for: fileURL).path))
    }

    func testDeletingLatestSnapshotDoesNotRecreateUnchangedContentOnNextScan() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("draft.md")
        try "first".write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: true,
            watchedDirectoryPath: "",
            watchedExtensions: "",
            deletedSourceBehavior: .keepAsOrphan
        )
        manager.registerOpenedFile(fileURL, waitUntilFinished: true)

        try "second".write(to: fileURL, atomically: true, encoding: .utf8)
        manager.captureNowIfNeeded(for: fileURL, waitUntilFinished: true)

        let latestEntry = try XCTUnwrap(manager.historyEntries(for: fileURL).last)
        XCTAssertTrue(manager.deleteSnapshot(latestEntry, for: fileURL))

        XCTAssertEqual(manager.historyEntries(for: fileURL).count, 1)

        manager.scanNow()

        let entries = manager.historyEntries(for: fileURL)
        XCTAssertEqual(entries.count, 1)
    }

    func testDeletingLatestSnapshotCapturesFutureEditsOnly() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("draft.md")
        try "first".write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: true,
            watchedDirectoryPath: "",
            watchedExtensions: "",
            deletedSourceBehavior: .keepAsOrphan
        )
        manager.registerOpenedFile(fileURL, waitUntilFinished: true)

        try "second".write(to: fileURL, atomically: true, encoding: .utf8)
        manager.captureNowIfNeeded(for: fileURL, waitUntilFinished: true)

        let latestEntry = try XCTUnwrap(manager.historyEntries(for: fileURL).last)
        XCTAssertTrue(manager.deleteSnapshot(latestEntry, for: fileURL))

        try "third".write(to: fileURL, atomically: true, encoding: .utf8)
        manager.scanNow()

        let entries = manager.historyEntries(for: fileURL)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(
            manager.snapshotText(for: try XCTUnwrap(entries.last), fileURL: fileURL),
            "third"
        )
    }

    func testDeletingHistoryDoesNotRecreateUnchangedContentOnNextScan() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("draft.md")
        try "first".write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: true,
            watchedDirectoryPath: "",
            watchedExtensions: "",
            deletedSourceBehavior: .keepAsOrphan
        )
        manager.registerOpenedFile(fileURL, waitUntilFinished: true)

        XCTAssertTrue(manager.deleteHistory(for: fileURL))
        XCTAssertEqual(manager.historyEntries(for: fileURL).count, 0)

        manager.scanNow()

        XCTAssertEqual(manager.historyEntries(for: fileURL).count, 0)
    }

    func testDeletingHistoryCapturesFutureEditsOnly() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("draft.md")
        try "first".write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: true,
            watchedDirectoryPath: "",
            watchedExtensions: "",
            deletedSourceBehavior: .keepAsOrphan
        )
        manager.registerOpenedFile(fileURL, waitUntilFinished: true)

        XCTAssertTrue(manager.deleteHistory(for: fileURL))
        XCTAssertEqual(manager.historyEntries(for: fileURL).count, 0)

        try "second".write(to: fileURL, atomically: true, encoding: .utf8)
        manager.scanNow()

        let entries = manager.historyEntries(for: fileURL)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(
            manager.snapshotText(for: try XCTUnwrap(entries.first), fileURL: fileURL),
            "second"
        )
    }

    func testKeepAsOrphanPreservesHistoryWhenSourceFileIsDeleted() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("draft.md")
        try "first".write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: true,
            watchedDirectoryPath: "",
            watchedExtensions: "",
            deletedSourceBehavior: .keepAsOrphan
        )
        manager.registerOpenedFile(fileURL, waitUntilFinished: true)
        try FileManager.default.removeItem(at: fileURL)

        manager.scanNow()

        let info = manager.trackingInfo(for: fileURL)
        XCTAssertEqual(info.historyEntryCount, 1)
        XCTAssertTrue(info.isOrphanedHistory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.historyDirectoryURL(for: fileURL).path))
    }

    func testDeleteImmediatelyPrunesHistoryWhenSourceFileIsDeleted() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("draft.md")
        try "first".write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: true,
            watchedDirectoryPath: "",
            watchedExtensions: "",
            deletedSourceBehavior: .deleteImmediately
        )
        manager.registerOpenedFile(fileURL, waitUntilFinished: true)
        try FileManager.default.removeItem(at: fileURL)

        manager.scanNow()

        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.historyDirectoryURL(for: fileURL).path))
        XCTAssertEqual(manager.historyEntries(for: fileURL).count, 0)
    }

    func testDeleteAfterGracePeriodPrunesOnlyAfterStoredDeletionDateAgesOut() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("draft.md")
        try "first".write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: true,
            watchedDirectoryPath: "",
            watchedExtensions: "",
            deletedSourceBehavior: .deleteAfterGracePeriod,
            orphanGracePeriodDays: 30
        )
        manager.registerOpenedFile(fileURL, waitUntilFinished: true)
        try FileManager.default.removeItem(at: fileURL)

        manager.scanNow()
        let historyDirectoryURL = manager.historyDirectoryURL(for: fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyDirectoryURL.path))

        let manifestURL = historyDirectoryURL.appendingPathComponent("manifest.json")
        let staleDeletedAt = Date(timeIntervalSinceNow: -(31 * 86_400))
        try overwriteManifestDeletionDate(at: manifestURL, deletedAt: staleDeletedAt)

        manager.scanNow()

        XCTAssertFalse(FileManager.default.fileExists(atPath: historyDirectoryURL.path))
    }

    func testReadOnlyHistoryAccessDoesNotResetOrphanGracePeriod() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("draft.md")
        try "first".write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: true,
            watchedDirectoryPath: "",
            watchedExtensions: "",
            deletedSourceBehavior: .deleteAfterGracePeriod,
            orphanGracePeriodDays: 30
        )
        manager.registerOpenedFile(fileURL, waitUntilFinished: true)
        try FileManager.default.removeItem(at: fileURL)

        manager.scanNow()
        let historyDirectoryURL = manager.historyDirectoryURL(for: fileURL)
        let manifestURL = historyDirectoryURL.appendingPathComponent("manifest.json")
        let staleDeletedAt = Date(timeIntervalSinceNow: -(31 * 86_400))
        try overwriteManifestDeletionDate(at: manifestURL, deletedAt: staleDeletedAt)

        _ = manager.historyEntries(for: fileURL)
        _ = manager.trackingInfo(for: fileURL)

        let preservedDeletedAt = try XCTUnwrap(manifestDeletionDate(at: manifestURL))
        XCTAssertEqual(
            preservedDeletedAt.timeIntervalSinceReferenceDate,
            staleDeletedAt.timeIntervalSinceReferenceDate,
            accuracy: 0.001
        )

        manager.scanNow()

        XCTAssertFalse(FileManager.default.fileExists(atPath: historyDirectoryURL.path))
    }

    func testWatchedFileRenamePreservesHistoryContinuity() throws {
        let watchedDirectory = temporaryDirectory.appendingPathComponent("Watched", isDirectory: true)
        try FileManager.default.createDirectory(at: watchedDirectory, withIntermediateDirectories: true)

        let originalURL = watchedDirectory.appendingPathComponent("draft.md")
        let renamedURL = watchedDirectory.appendingPathComponent("renamed.md")
        try "first".write(to: originalURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: false,
            watchedDirectoryPath: watchedDirectory.path,
            watchedExtensions: "md",
            deletedSourceBehavior: .deleteImmediately
        )

        manager.scanNow()
        let initialHistoryDirectoryURL = manager.historyDirectoryURL(for: originalURL)
        XCTAssertEqual(manager.historyEntries(for: originalURL).count, 1)

        try FileManager.default.moveItem(at: originalURL, to: renamedURL)
        manager.scanNow()

        let renamedHistoryDirectoryURL = manager.historyDirectoryURL(for: renamedURL)
        XCTAssertEqual(manager.historyEntries(for: renamedURL).count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedHistoryDirectoryURL.path))
        XCTAssertNotEqual(renamedHistoryDirectoryURL, initialHistoryDirectoryURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: initialHistoryDirectoryURL.path))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: storePaths.localHistoryDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).count,
            1
        )
    }

    func testWatchedFileMovedOutOfScopePreservesExistingHistory() throws {
        let watchedDirectory = temporaryDirectory.appendingPathComponent("Watched", isDirectory: true)
        let outsideDirectory = temporaryDirectory.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: watchedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)

        let originalURL = watchedDirectory.appendingPathComponent("draft.md")
        let movedURL = outsideDirectory.appendingPathComponent("draft.md")
        try "first".write(to: originalURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: false,
            watchedDirectoryPath: watchedDirectory.path,
            watchedExtensions: "md",
            deletedSourceBehavior: .deleteImmediately
        )

        manager.scanNow()
        XCTAssertEqual(manager.historyEntries(for: originalURL).count, 1)

        try FileManager.default.moveItem(at: originalURL, to: movedURL)
        manager.scanNow()

        XCTAssertEqual(manager.historyEntries(for: movedURL).count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.historyDirectoryURL(for: movedURL).path))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: storePaths.localHistoryDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).count,
            1
        )
    }

    func testNewFileAtReusedPathDoesNotInheritOrphanSnapshots() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("draft.md")
        try "first".write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: true,
            watchedDirectoryPath: "",
            watchedExtensions: "",
            deletedSourceBehavior: .keepAsOrphan
        )
        manager.registerOpenedFile(fileURL, waitUntilFinished: true)
        try FileManager.default.removeItem(at: fileURL)

        manager.scanNow()
        XCTAssertEqual(manager.historyEntries(for: fileURL).count, 1)

        try "second".write(to: fileURL, atomically: true, encoding: .utf8)
        manager.registerOpenedFile(fileURL, waitUntilFinished: true)

        let currentEntries = manager.historyEntries(for: fileURL)
        XCTAssertEqual(currentEntries.count, 1)
        XCTAssertEqual(
            manager.snapshotText(for: try XCTUnwrap(currentEntries.first), fileURL: fileURL),
            "second"
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: storePaths.localHistoryDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).count,
            2
        )
    }

    func testOpenedFileMoveKeepsExplicitTrackingForSubsequentSnapshots() throws {
        let movedDirectory = temporaryDirectory.appendingPathComponent("Moved", isDirectory: true)
        try FileManager.default.createDirectory(at: movedDirectory, withIntermediateDirectories: true)

        let originalURL = temporaryDirectory.appendingPathComponent("draft.md")
        let movedURL = movedDirectory.appendingPathComponent("draft.md")
        try "first".write(to: originalURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: true,
            watchedDirectoryPath: "",
            watchedExtensions: "",
            deletedSourceBehavior: .keepAsOrphan
        )
        manager.registerOpenedFile(originalURL, waitUntilFinished: true)

        try FileManager.default.moveItem(at: originalURL, to: movedURL)
        manager.scanNow()

        XCTAssertTrue(manager.trackingInfo(for: movedURL).isTrackedByOpenedFile)

        try "second".write(to: movedURL, atomically: true, encoding: .utf8)
        manager.scanNow()

        XCTAssertEqual(manager.historyEntries(for: movedURL).count, 2)
    }

    func testMaxSnapshotsPerFileRetainsNewestSnapshots() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("draft.md")
        let manager = makeManager(
            trackOpenedFiles: true,
            watchedDirectoryPath: "",
            watchedExtensions: "",
            deletedSourceBehavior: .keepAsOrphan,
            maxSnapshotsPerFile: 2
        )

        try captureOpenedHistory(
            ["first", "second", "third", "fourth"],
            for: fileURL,
            manager: manager
        )

        XCTAssertEqual(snapshotTexts(for: manager, fileURL: fileURL), ["third", "fourth"])
    }

    func testMovedFileRetainsHistoryWhenOriginalPathIsReusedBeforeNextScan() throws {
        let watchedDirectory = temporaryDirectory.appendingPathComponent("Watched", isDirectory: true)
        try FileManager.default.createDirectory(at: watchedDirectory, withIntermediateDirectories: true)

        let originalURL = watchedDirectory.appendingPathComponent("draft.md")
        let movedURL = watchedDirectory.appendingPathComponent("moved.md")
        try "first".write(to: originalURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: false,
            watchedDirectoryPath: watchedDirectory.path,
            watchedExtensions: "md",
            deletedSourceBehavior: .keepAsOrphan
        )
        manager.scanNow()

        try FileManager.default.moveItem(at: originalURL, to: movedURL)
        try "second".write(to: originalURL, atomically: true, encoding: .utf8)

        manager.scanNow()

        let movedEntries = manager.historyEntries(for: movedURL)
        XCTAssertEqual(movedEntries.count, 1)
        XCTAssertEqual(
            manager.snapshotText(for: try XCTUnwrap(movedEntries.first), fileURL: movedURL),
            "first"
        )

        let replacementEntries = manager.historyEntries(for: originalURL)
        XCTAssertEqual(replacementEntries.count, 1)
        XCTAssertEqual(
            manager.snapshotText(for: try XCTUnwrap(replacementEntries.first), fileURL: originalURL),
            "second"
        )
    }

    func testDisablingHistoryPreservesExistingOrphanHistory() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("draft.md")
        try "first".write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            trackOpenedFiles: true,
            watchedDirectoryPath: "",
            watchedExtensions: "",
            deletedSourceBehavior: .deleteImmediately
        )
        manager.registerOpenedFile(fileURL, waitUntilFinished: true)
        try FileManager.default.removeItem(at: fileURL)

        manager.apply(
            settings: FileLocalHistoryManager.Settings(
                isEnabled: false,
                trackOpenedFiles: true,
                watchedDirectoryPath: "",
                watchedExtensions: "",
                watchDirectoryRecursively: true,
                maxSnapshotsPerFile: 10,
                deletedSourceBehavior: .deleteImmediately,
                orphanGracePeriodDays: 30,
                pollingInterval: 10.0
            )
        )
        manager.scanNow()

        let historyDirectoryURL = manager.historyDirectoryURL(for: fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyDirectoryURL.path))
        XCTAssertEqual(manager.historyEntries(for: fileURL).count, 1)
        XCTAssertTrue(manager.trackingInfo(for: fileURL).isOrphanedHistory)
    }

    func testApplyDoesNotBlockWhileInitialScanRuns() throws {
        let watchedDirectory = temporaryDirectory.appendingPathComponent("Watched", isDirectory: true)
        try FileManager.default.createDirectory(at: watchedDirectory, withIntermediateDirectories: true)
        try "tracked".write(
            to: watchedDirectory.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )

        let scanStarted = expectation(description: "scan started")
        let applyReturned = expectation(description: "apply returned")
        let unblockScan = DispatchSemaphore(value: 0)

        let manager = FileLocalHistoryManager(
            storePaths: storePaths,
            scanStartHandler: {
                scanStarted.fulfill()
                _ = unblockScan.wait(timeout: .now() + 1)
            }
        )

        DispatchQueue.global().async {
            manager.apply(
                settings: FileLocalHistoryManager.Settings(
                    isEnabled: true,
                    trackOpenedFiles: false,
                    watchedDirectoryPath: watchedDirectory.path,
                    watchedExtensions: "txt",
                    watchDirectoryRecursively: true,
                    maxSnapshotsPerFile: 10,
                    deletedSourceBehavior: .keepAsOrphan,
                    orphanGracePeriodDays: 30,
                    pollingInterval: 10.0
                )
            )
            applyReturned.fulfill()
        }

        wait(for: [scanStarted], timeout: 1)
        wait(for: [applyReturned], timeout: 0.2)
        unblockScan.signal()
    }

    func testShouldSkipContentReadSkipsRecentUnchangedPollingChecks() {
        let now = Date()

        XCTAssertTrue(
            FileLocalHistoryManager.shouldSkipContentRead(
                forceRead: false,
                previousModificationDate: now,
                previousFileSize: 128,
                previousContentHash: "abc",
                lastContentReadAt: now,
                currentModificationDate: now,
                currentFileSize: 128,
                now: now.addingTimeInterval(5),
                unchangedPollingRecheckInterval: 30
            )
        )
    }

    func testShouldSkipContentReadStillReadsWhenForcedOrStale() {
        let now = Date()

        XCTAssertFalse(
            FileLocalHistoryManager.shouldSkipContentRead(
                forceRead: true,
                previousModificationDate: now,
                previousFileSize: 128,
                previousContentHash: "abc",
                lastContentReadAt: now,
                currentModificationDate: now,
                currentFileSize: 128,
                now: now.addingTimeInterval(5),
                unchangedPollingRecheckInterval: 30
            )
        )

        XCTAssertFalse(
            FileLocalHistoryManager.shouldSkipContentRead(
                forceRead: false,
                previousModificationDate: now,
                previousFileSize: 128,
                previousContentHash: "abc",
                lastContentReadAt: now,
                currentModificationDate: now,
                currentFileSize: 128,
                now: now.addingTimeInterval(31),
                unchangedPollingRecheckInterval: 30
            )
        )
    }

    private func makeManager(
        trackOpenedFiles: Bool,
        watchedDirectoryPath: String,
        watchedExtensions: String,
        deletedSourceBehavior: FileLocalHistoryDeletedSourceBehavior,
        orphanGracePeriodDays: Int = 30,
        watchDirectoryRecursively: Bool = true,
        maxSnapshotsPerFile: Int = 10,
        scanStartHandler: (() -> Void)? = nil
    ) -> FileLocalHistoryManager {
        let manager = FileLocalHistoryManager(
            storePaths: storePaths,
            scanStartHandler: scanStartHandler
        )
        manager.apply(
            settings: makeSettings(
                trackOpenedFiles: trackOpenedFiles,
                watchedDirectoryPath: watchedDirectoryPath,
                watchedExtensions: watchedExtensions,
                deletedSourceBehavior: deletedSourceBehavior,
                orphanGracePeriodDays: orphanGracePeriodDays,
                watchDirectoryRecursively: watchDirectoryRecursively,
                maxSnapshotsPerFile: maxSnapshotsPerFile
            )
        )
        return manager
    }

    private func makeSettings(
        trackOpenedFiles: Bool,
        watchedDirectoryPath: String,
        watchedExtensions: String,
        deletedSourceBehavior: FileLocalHistoryDeletedSourceBehavior,
        orphanGracePeriodDays: Int = 30,
        watchDirectoryRecursively: Bool = true,
        maxSnapshotsPerFile: Int = 10
    ) -> FileLocalHistoryManager.Settings {
        FileLocalHistoryManager.Settings(
            isEnabled: true,
            trackOpenedFiles: trackOpenedFiles,
            watchedDirectoryPath: watchedDirectoryPath,
            watchedExtensions: watchedExtensions,
            watchDirectoryRecursively: watchDirectoryRecursively,
            maxSnapshotsPerFile: maxSnapshotsPerFile,
            deletedSourceBehavior: deletedSourceBehavior,
            orphanGracePeriodDays: orphanGracePeriodDays,
            pollingInterval: 10.0
        )
    }

    private func captureOpenedHistory(
        _ versions: [String],
        for fileURL: URL,
        manager: FileLocalHistoryManager
    ) throws {
        guard let firstVersion = versions.first else { return }
        try firstVersion.write(to: fileURL, atomically: true, encoding: .utf8)
        manager.registerOpenedFile(fileURL, waitUntilFinished: true)

        for version in versions.dropFirst() {
            try version.write(to: fileURL, atomically: true, encoding: .utf8)
            manager.captureNowIfNeeded(for: fileURL, waitUntilFinished: true)
        }
    }

    private func snapshotTexts(
        for manager: FileLocalHistoryManager,
        fileURL: URL
    ) -> [String] {
        manager.historyEntries(for: fileURL).compactMap { entry in
            manager.snapshotText(for: entry, fileURL: fileURL)
        }
    }

    private func overwriteManifestDeletionDate(at manifestURL: URL, deletedAt: Date) throws {
        let data = try Data(contentsOf: manifestURL)
        var jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        jsonObject["sourceDeletedAt"] = deletedAt.timeIntervalSinceReferenceDate
        let updatedData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
        try updatedData.write(to: manifestURL, options: .atomic)
    }

    private func manifestDeletionDate(at manifestURL: URL) throws -> Date? {
        let data = try Data(contentsOf: manifestURL)
        let jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        guard let rawValue = jsonObject["sourceDeletedAt"] as? Double else {
            return nil
        }
        return Date(timeIntervalSinceReferenceDate: rawValue)
    }
}
