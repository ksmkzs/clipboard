import AppKit
import CryptoKit
import Foundation

extension Notification.Name {
    static let fileLocalHistoryDidChange = Notification.Name("FileLocalHistoryDidChange")
}

final class FileLocalHistoryManager {
    struct Settings: Equatable {
        var isEnabled: Bool
        var trackOpenedFiles: Bool
        var watchedDirectoryPath: String
        var watchedExtensions: String
        var watchDirectoryRecursively: Bool
        var maxSnapshotsPerFile: Int
        var deletedSourceBehavior: FileLocalHistoryDeletedSourceBehavior
        var orphanGracePeriodDays: Int
        var pollingInterval: TimeInterval

        static let `default` = Settings(
            isEnabled: true,
            trackOpenedFiles: true,
            watchedDirectoryPath: "",
            watchedExtensions: "txt,md,markdown",
            watchDirectoryRecursively: true,
            maxSnapshotsPerFile: 30,
            deletedSourceBehavior: .keepAsOrphan,
            orphanGracePeriodDays: 30,
            pollingInterval: 2.0
        )

        var normalizedWatchedDirectoryPath: String {
            watchedDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var normalizedExtensions: Set<String> {
            Set(
                watchedExtensions
                    .split(whereSeparator: { $0 == "," || $0.isWhitespace || $0 == ";" })
                    .map { token in
                        token.trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased()
                            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    }
                    .filter { !$0.isEmpty }
            )
        }

        var clampedMaxSnapshotsPerFile: Int {
            min(200, max(1, maxSnapshotsPerFile))
        }

        var clampedOrphanGracePeriodDays: Int {
            min(365, max(1, orphanGracePeriodDays))
        }
    }

    struct SnapshotEntry: Codable, Equatable, Identifiable {
        let id: String
        let createdAt: Date
        let snapshotFileName: String
        let contentHash: String
        let byteCount: Int
    }

    struct TrackingInfo: Equatable {
        let isTrackedByOpenedFile: Bool
        let isTrackedByWatchedDirectory: Bool
        let historyEntryCount: Int
        let sourceFileExists: Bool

        var isTracked: Bool {
            isTrackedByOpenedFile || isTrackedByWatchedDirectory
        }

        var isOrphanedHistory: Bool {
            historyEntryCount > 0 && !sourceFileExists
        }
    }

    private struct FileManifest: Codable {
        var fileID: String
        var sourceIdentity: String?
        var sourceBookmarkData: Data?
        var originalFilePath: String
        var displayName: String
        var pathExtension: String
        var sourceDeletedAt: Date?
        var entries: [SnapshotEntry]
    }

    private struct ObservedFileState {
        var modificationDate: Date?
        var fileSize: Int?
        var contentHash: String?
        var lastContentReadAt: Date?
    }

    private struct WatchedDirectoryState: Equatable {
        var exists: Bool
        var modificationDate: Date?
    }

    private struct WatchedCandidateSnapshot {
        var fileURLs: Set<URL>
        var directoryStatesByPath: [String: WatchedDirectoryState]
    }

    private struct ExplicitlyTrackedFileState: Equatable {
        var sourceIdentity: String?
        var sourceBookmarkData: Data?
    }

    private let storePaths: ClipboardStorePaths
    private let fileManager: FileManager
    private let workerQueue = DispatchQueue(label: "ClipboardHistory.FileLocalHistoryManager")
    private let scanStartHandler: (() -> Void)?
    private var settings: Settings
    private var timer: DispatchSourceTimer?
    private var explicitlyTrackedFiles: [URL: ExplicitlyTrackedFileState] = [:]
    private var watchedTrackedFiles: Set<URL> = []
    private var watchedDirectoryStatesByPath: [String: WatchedDirectoryState] = [:]
    private var observedStatesByPath: [String: ObservedFileState] = [:]
    private var lastWatchedDirectoryRefreshAt: Date?
    private var lastDeletedSourcePruneAt: Date?

    init(
        storePaths: ClipboardStorePaths = .default(),
        fileManager: FileManager = .default,
        settings: Settings = .default,
        scanStartHandler: (() -> Void)? = nil
    ) {
        self.storePaths = storePaths
        self.fileManager = fileManager
        self.settings = settings
        self.scanStartHandler = scanStartHandler
        try? storePaths.ensureDirectories(fileManager: fileManager)
    }

    deinit {
        timer?.cancel()
    }

    func apply(settings: Settings) {
        let shouldScheduleScan = workerQueue.sync {
            let shouldClearExplicitTracking = !settings.isEnabled || !settings.trackOpenedFiles
            self.settings = settings
            if shouldClearExplicitTracking {
                explicitlyTrackedFiles = [:]
            }
            watchedTrackedFiles = []
            watchedDirectoryStatesByPath = [:]
            lastWatchedDirectoryRefreshAt = nil
            lastDeletedSourcePruneAt = nil
            restartTimerIfNeededLocked()
            return settings.isEnabled
        }

        guard shouldScheduleScan else { return }
        workerQueue.async { [weak self] in
            self?.scanLocked()
        }
    }

    func registerOpenedFile(_ fileURL: URL, waitUntilFinished: Bool = false) {
        let standardizedURL = fileURL.standardizedFileURL
        let work = { [self] in
            guard self.settings.isEnabled else {
                return
            }
            let inserted: Bool
            if self.settings.trackOpenedFiles {
                inserted = self.explicitlyTrackedFiles[standardizedURL] == nil
                self.explicitlyTrackedFiles[standardizedURL] = self.explicitTrackingStateLocked(for: standardizedURL)
            } else {
                inserted = false
            }
            if inserted {
                self.restartTimerIfNeededLocked()
            }
            let captured = self.captureIfNeededLocked(at: standardizedURL, forceRead: true)
            if inserted || captured {
                self.postHistoryDidChangeLocked(for: standardizedURL)
            }
        }
        if waitUntilFinished {
            workerQueue.sync(execute: work)
        } else {
            workerQueue.async(execute: work)
        }
    }

    func captureNowIfNeeded(for fileURL: URL, waitUntilFinished: Bool = false) {
        let standardizedURL = fileURL.standardizedFileURL
        let work = { [self] in
            if self.captureIfNeededLocked(at: standardizedURL, forceRead: true) {
                self.postHistoryDidChangeLocked(for: standardizedURL)
            }
        }
        if waitUntilFinished {
            workerQueue.sync(execute: work)
        } else {
            workerQueue.async(execute: work)
        }
    }

    func scanNow() {
        workerQueue.sync {
            scanLocked(forceReadTrackedFiles: true)
        }
    }

    func historyEntries(for fileURL: URL) -> [SnapshotEntry] {
        let standardizedURL = fileURL.standardizedFileURL
        return workerQueue.sync {
            loadManifestLocked(for: standardizedURL)?.entries ?? []
        }
    }

    func snapshotText(for entry: SnapshotEntry, fileURL: URL) -> String? {
        let standardizedURL = fileURL.standardizedFileURL
        return workerQueue.sync {
            let snapshotURL = historyDirectoryURLLocked(for: standardizedURL)
                .appendingPathComponent("Snapshots", isDirectory: true)
                .appendingPathComponent(entry.snapshotFileName)
            return try? String(contentsOf: snapshotURL, encoding: .utf8)
        }
    }

    func historyDirectoryURL(for fileURL: URL) -> URL {
        let standardizedURL = fileURL.standardizedFileURL
        return workerQueue.sync {
            historyDirectoryURLLocked(for: standardizedURL)
        }
    }

    func trackingInfo(for fileURL: URL) -> TrackingInfo {
        let standardizedURL = fileURL.standardizedFileURL
        return workerQueue.sync {
            trackingInfoLocked(for: standardizedURL)
        }
    }

    @discardableResult
    func deleteSnapshot(_ entry: SnapshotEntry, for fileURL: URL) -> Bool {
        let standardizedURL = fileURL.standardizedFileURL
        return workerQueue.sync {
            let didDelete = deleteSnapshotLocked(entry, for: standardizedURL)
            if didDelete {
                postHistoryDidChangeLocked(for: standardizedURL)
            }
            return didDelete
        }
    }

    @discardableResult
    func deleteHistory(for fileURL: URL) -> Bool {
        let standardizedURL = fileURL.standardizedFileURL
        return workerQueue.sync {
            let didDelete = deleteHistoryLocked(for: standardizedURL)
            if didDelete {
                postHistoryDidChangeLocked(for: standardizedURL)
            }
            return didDelete
        }
    }

    @discardableResult
    func revealHistoryInFinder(for fileURL: URL) -> Bool {
        let standardizedURL = fileURL.standardizedFileURL
        let directoryURL = workerQueue.sync {
            let historyURL = historyDirectoryURLLocked(for: standardizedURL)
            return fileManager.fileExists(atPath: historyURL.path) ? historyURL : nil
        }

        guard let directoryURL else {
            return false
        }

        DispatchQueue.main.async {
            NSWorkspace.shared.activateFileViewerSelecting([directoryURL])
        }
        return true
    }

    @discardableResult
    func revealStorageRootInFinder() -> Bool {
        let directoryURL = workerQueue.sync {
            try? storePaths.ensureDirectories(fileManager: fileManager)
            return storePaths.localHistoryDirectory
        }

        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return false
        }

        DispatchQueue.main.async {
            NSWorkspace.shared.activateFileViewerSelecting([directoryURL])
        }
        return true
    }

    private func restartTimerIfNeededLocked() {
        timer?.cancel()
        timer = nil

        guard shouldRunTimerLocked() else {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: workerQueue)
        let pollingInterval = effectivePollingIntervalLocked()
        timer.schedule(deadline: .now() + pollingInterval, repeating: pollingInterval)
        timer.setEventHandler { [weak self] in
            self?.scanLocked()
        }
        self.timer = timer
        timer.resume()
    }

    private func scanLocked(forceReadTrackedFiles: Bool = false) {
        guard settings.isEnabled else {
            return
        }

        let now = Date()
        scanStartHandler?()
        let candidateURLs = trackedCandidateFileURLsLocked(now: now, forceRefreshWatchedCandidates: forceReadTrackedFiles)
        let shouldPruneDeletedSources = forceReadTrackedFiles || shouldPruneDeletedSourceHistoriesLocked(now: now)
        let pruneResult = shouldPruneDeletedSources
            ? pruneDeletedSourceHistoriesLocked(candidateURLs: candidateURLs)
            : (relocatedCandidateURLs: Set<URL>(), changedURLs: Set<URL>())
        if shouldPruneDeletedSources {
            lastDeletedSourcePruneAt = now
        }
        let allCandidateURLs = Set(candidateURLs).union(pruneResult.relocatedCandidateURLs).sorted { $0.path < $1.path }
        var changedURLs = pruneResult.changedURLs
        for fileURL in allCandidateURLs {
            if captureIfNeededLocked(at: fileURL, forceRead: forceReadTrackedFiles) {
                changedURLs.insert(fileURL.standardizedFileURL)
            }
        }
        for fileURL in changedURLs {
            postHistoryDidChangeLocked(for: fileURL)
        }
        if !shouldRunTimerLocked() {
            restartTimerIfNeededLocked()
        }
    }

    private func trackedCandidateFileURLsLocked(now: Date, forceRefreshWatchedCandidates: Bool) -> [URL] {
        var results = Set<URL>()

        if settings.trackOpenedFiles {
            results.formUnion(
                activeExplicitlyTrackedFileURLsLocked().filter { !isExcludedManagedURLLocked($0) }
            )
        }

        results.formUnion(
            watchedCandidateFileURLsLocked(now: now, forceRefresh: forceRefreshWatchedCandidates)
        )

        return results.sorted { $0.path < $1.path }
    }

    private func shouldRunTimerLocked() -> Bool {
        guard settings.isEnabled else {
            return false
        }

        if hasWatchedDirectoryConfigurationLocked {
            return true
        }

        return settings.trackOpenedFiles && !activeExplicitlyTrackedFileURLsLocked().isEmpty
    }

    private func effectivePollingIntervalLocked() -> TimeInterval {
        if hasWatchedDirectoryConfigurationLocked {
            return max(settings.pollingInterval, Self.minimumWatchedDirectoryPollingInterval)
        }
        return settings.pollingInterval
    }

    private var hasWatchedDirectoryConfigurationLocked: Bool {
        !settings.normalizedWatchedDirectoryPath.isEmpty && !settings.normalizedExtensions.isEmpty
    }

    private func watchedCandidateFileURLsLocked(now: Date, forceRefresh: Bool) -> Set<URL> {
        guard hasWatchedDirectoryConfigurationLocked else {
            watchedTrackedFiles = []
            watchedDirectoryStatesByPath = [:]
            lastWatchedDirectoryRefreshAt = nil
            return []
        }

        if forceRefresh
            || watchedTrackedFiles.isEmpty
            || watchedDirectoryContentsChangedLocked()
            || now.timeIntervalSince(lastWatchedDirectoryRefreshAt ?? .distantPast) >= Self.watchedDirectoryRefreshInterval {
            let snapshot = enumeratedWatchedCandidateSnapshotLocked()
            watchedTrackedFiles = snapshot.fileURLs
            watchedDirectoryStatesByPath = snapshot.directoryStatesByPath
            lastWatchedDirectoryRefreshAt = now
        } else {
            watchedTrackedFiles = Set(watchedTrackedFiles.filter(isWatchedFileTrackedLocked))
        }

        return watchedTrackedFiles
    }

    private func watchedDirectoryContentsChangedLocked() -> Bool {
        guard hasWatchedDirectoryConfigurationLocked else {
            return false
        }

        let rootURL = watchedRootDirectoryURLLocked()
        guard !watchedDirectoryStatesByPath.isEmpty else {
            return true
        }

        let currentRootState = watchedDirectoryStateLocked(for: rootURL)
        if watchedDirectoryStatesByPath[rootURL.path] != currentRootState {
            return true
        }

        for (path, cachedState) in watchedDirectoryStatesByPath where path != rootURL.path {
            let currentState = watchedDirectoryStateLocked(
                for: URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            )
            if currentState != cachedState {
                return true
            }
        }

        return false
    }

    private func enumeratedWatchedCandidateSnapshotLocked() -> WatchedCandidateSnapshot {
        let directoryPath = settings.normalizedWatchedDirectoryPath
        let extensions = settings.normalizedExtensions
        guard !directoryPath.isEmpty, !extensions.isEmpty else {
            return WatchedCandidateSnapshot(fileURLs: [], directoryStatesByPath: [:])
        }

        let rootURL = watchedRootDirectoryURLLocked()
        var directoryStatesByPath: [String: WatchedDirectoryState] = [
            rootURL.path: watchedDirectoryStateLocked(for: rootURL)
        ]
        guard let enumerator = directoryEnumeratorLocked(rootURL: rootURL) else {
            return WatchedCandidateSnapshot(fileURLs: [], directoryStatesByPath: directoryStatesByPath)
        }

        var results = Set<URL>()
        for case let fileURL as URL in enumerator {
            let standardizedURL = fileURL.standardizedFileURL
            let resourceValues = try? standardizedURL.resourceValues(
                forKeys: [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey]
            )
            if resourceValues?.isDirectory == true {
                directoryStatesByPath[standardizedURL.path] = WatchedDirectoryState(
                    exists: true,
                    modificationDate: resourceValues?.contentModificationDate
                )
                continue
            }
            guard resourceValues?.isRegularFile == true else {
                continue
            }
            guard !isExcludedManagedURLLocked(standardizedURL) else { continue }
            guard matchesTrackedExtensionsLocked(standardizedURL, extensions: extensions) else { continue }
            results.insert(standardizedURL)
        }
        return WatchedCandidateSnapshot(fileURLs: results, directoryStatesByPath: directoryStatesByPath)
    }

    private func shouldPruneDeletedSourceHistoriesLocked(now: Date) -> Bool {
        now.timeIntervalSince(lastDeletedSourcePruneAt ?? .distantPast) >= Self.deletedSourcePruneInterval
    }

    private func directoryEnumeratorLocked(rootURL: URL) -> FileManager.DirectoryEnumerator? {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return nil
        }

        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey]
        let options: FileManager.DirectoryEnumerationOptions = settings.watchDirectoryRecursively
            ? [.skipsHiddenFiles, .skipsPackageDescendants]
            : [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants]
        return fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: resourceKeys,
            options: options
        )
    }

    private func matchesTrackedExtensionsLocked(_ fileURL: URL, extensions: Set<String>) -> Bool {
        let pathExtension = fileURL.pathExtension.lowercased()
        return !pathExtension.isEmpty && extensions.contains(pathExtension)
    }

    @discardableResult
    private func captureIfNeededLocked(at fileURL: URL, forceRead: Bool) -> Bool {
        guard shouldTrackFileLocked(fileURL) else {
            return false
        }

        guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
              resourceValues.isRegularFile == true else {
            return false
        }

        let path = fileURL.path
        let modificationDate = resourceValues.contentModificationDate
        let fileSize = resourceValues.fileSize
        let previousState = observedStatesByPath[path]
        let now = Date()
        if Self.shouldSkipContentRead(
            forceRead: forceRead,
            previousModificationDate: previousState?.modificationDate,
            previousFileSize: previousState?.fileSize,
            previousContentHash: previousState?.contentHash,
            lastContentReadAt: previousState?.lastContentReadAt,
            currentModificationDate: modificationDate,
            currentFileSize: fileSize,
            now: now
        ) {
            return false
        }

        var encoding = String.Encoding.utf8
        guard let text = try? String(contentsOf: fileURL, usedEncoding: &encoding) else {
            observedStatesByPath[path] = ObservedFileState(
                modificationDate: modificationDate,
                fileSize: fileSize,
                contentHash: previousState?.contentHash,
                lastContentReadAt: now
            )
            return false
        }

        let contentHash = sha256Hex(for: text)
        if previousState?.contentHash == contentHash {
            observedStatesByPath[path] = ObservedFileState(
                modificationDate: modificationDate,
                fileSize: fileSize,
                contentHash: contentHash,
                lastContentReadAt: now
            )
            return false
        }

        let didPersist = persistSnapshotLocked(
            text: text,
            contentHash: contentHash,
            byteCount: text.lengthOfBytes(using: encoding),
            for: fileURL
        )
        observedStatesByPath[path] = ObservedFileState(
            modificationDate: modificationDate,
            fileSize: fileSize,
            contentHash: contentHash,
            lastContentReadAt: now
        )
        return didPersist
    }

    @discardableResult
    private func persistSnapshotLocked(text: String, contentHash: String, byteCount: Int, for fileURL: URL) -> Bool {
        try? storePaths.ensureDirectories(fileManager: fileManager)
        let historyDirectoryURL = historyDirectoryURLLocked(for: fileURL)
        let snapshotsDirectoryURL = historyDirectoryURL.appendingPathComponent("Snapshots", isDirectory: true)
        try? fileManager.createDirectory(at: snapshotsDirectoryURL, withIntermediateDirectories: true)

        let sourceIdentity = sourceIdentityLocked(for: fileURL)
        let fileID = fileIdentifier(for: fileURL)
        var manifest = loadManifestLocked(for: fileURL) ?? FileManifest(
            fileID: fileID,
            sourceIdentity: sourceIdentity,
            sourceBookmarkData: bookmarkDataLocked(for: fileURL),
            originalFilePath: fileURL.path,
            displayName: fileURL.lastPathComponent,
            pathExtension: fileURL.pathExtension.lowercased(),
            sourceDeletedAt: nil,
            entries: []
        )

        if manifest.entries.last?.contentHash == contentHash {
            updateManifestMetadataLocked(
                &manifest,
                for: fileURL,
                fileID: fileID,
                sourceIdentity: sourceIdentity,
                clearDeletedAt: true
            )
            saveManifestLocked(manifest, directoryURL: historyDirectoryURL)
            return false
        }

        let snapshotFileName = snapshotFileName(for: fileURL, contentHash: contentHash)
        let snapshotFileURL = snapshotsDirectoryURL.appendingPathComponent(snapshotFileName)
        do {
            try text.write(to: snapshotFileURL, atomically: true, encoding: .utf8)
        } catch {
            return false
        }

        updateManifestMetadataLocked(
            &manifest,
            for: fileURL,
            fileID: fileID,
            sourceIdentity: sourceIdentity,
            clearDeletedAt: true
        )
        manifest.entries.append(
            SnapshotEntry(
                id: snapshotFileName,
                createdAt: Date(),
                snapshotFileName: snapshotFileName,
                contentHash: contentHash,
                byteCount: byteCount
            )
        )

        let excessEntries = manifest.entries.count - settings.clampedMaxSnapshotsPerFile
        if excessEntries > 0 {
            let removedEntries = manifest.entries.prefix(excessEntries)
            for entry in removedEntries {
                let obsoleteURL = snapshotsDirectoryURL.appendingPathComponent(entry.snapshotFileName)
                try? fileManager.removeItem(at: obsoleteURL)
            }
            manifest.entries.removeFirst(excessEntries)
        }

        saveManifestLocked(manifest, directoryURL: historyDirectoryURL)
        return true
    }

    private func shouldTrackFileLocked(_ fileURL: URL) -> Bool {
        guard settings.isEnabled else {
            return false
        }
        guard !isExcludedManagedURLLocked(fileURL) else {
            return false
        }

        return isOpenedFileTrackedLocked(fileURL) || isWatchedFileTrackedLocked(fileURL)
    }

    private func isExcludedManagedURLLocked(_ fileURL: URL) -> Bool {
        let standardizedPath = fileURL.standardizedFileURL.path
        let excludedRoots = [
            storePaths.localHistoryDirectory,
            storePaths.largeTextDirectory,
            storePaths.noteDraftDirectory,
            storePaths.codexRequestDirectory,
            storePaths.codexCompletionDirectory,
            storePaths.codexSessionStateDirectory,
            storePaths.imageDirectory,
            storePaths.codexIntegrationDirectory
        ]

        return excludedRoots.contains { rootURL in
            let rootPath = rootURL.standardizedFileURL.path
            return standardizedPath == rootPath || standardizedPath.hasPrefix(rootPath + "/")
        }
    }

    private func historyDirectoryURLLocked(for fileURL: URL) -> URL {
        let standardizedURL = fileURL.standardizedFileURL
        let sourceFileExists = fileManager.fileExists(atPath: standardizedURL.path)
        let sourceIdentity = sourceFileExists ? sourceIdentityLocked(for: standardizedURL) : nil
        let pathDirectoryURL = pathHistoryDirectoryURLLocked(for: standardizedURL)

        if fileManager.fileExists(atPath: pathDirectoryURL.path) {
            if sourceFileExists,
               let manifest = loadManifestLocked(directoryURL: pathDirectoryURL),
               shouldDisplacePathHistoryLocked(
                   manifest: manifest,
                   sourceURL: standardizedURL,
                   currentSourceIdentity: sourceIdentity
               ) {
                displaceOrphanHistoryLocked(at: pathDirectoryURL, manifest: manifest)
            }

            if !fileManager.fileExists(atPath: pathDirectoryURL.path) {
                return historyDirectoryURLLocked(for: standardizedURL)
            }

            if sourceFileExists {
                refreshManifestMetadataLocked(
                    at: pathDirectoryURL,
                    for: standardizedURL,
                    sourceIdentity: sourceIdentity,
                    clearDeletedAt: true
                )
            }
            return pathDirectoryURL
        }

        if let sourceIdentity,
           let matchedDirectoryURL = existingHistoryDirectoryLocked(matchingSourceIdentity: sourceIdentity) {
            if matchedDirectoryURL != pathDirectoryURL {
                migrateHistoryDirectoryLocked(
                    from: matchedDirectoryURL,
                    to: pathDirectoryURL,
                    for: standardizedURL,
                    sourceIdentity: sourceIdentity
                )
                return fileManager.fileExists(atPath: pathDirectoryURL.path)
                    ? pathDirectoryURL
                    : matchedDirectoryURL
            }

            refreshManifestMetadataLocked(
                at: matchedDirectoryURL,
                for: standardizedURL,
                sourceIdentity: sourceIdentity,
                clearDeletedAt: true
            )
            return matchedDirectoryURL
        }

        return pathDirectoryURL
    }

    private func manifestURLLocked(for fileURL: URL) -> URL {
        historyDirectoryURLLocked(for: fileURL).appendingPathComponent("manifest.json")
    }

    private func loadManifestLocked(for fileURL: URL) -> FileManifest? {
        loadManifestLocked(directoryURL: historyDirectoryURLLocked(for: fileURL))
    }

    private func saveManifestLocked(_ manifest: FileManifest, directoryURL: URL) {
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(manifest) else {
            return
        }
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        try? data.write(to: manifestURL, options: .atomic)
    }

    private func loadManifestLocked(directoryURL: URL) -> FileManifest? {
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            return nil
        }
        return try? JSONDecoder().decode(FileManifest.self, from: data)
    }

    private func trackingInfoLocked(for fileURL: URL) -> TrackingInfo {
        TrackingInfo(
            isTrackedByOpenedFile: isOpenedFileTrackedLocked(fileURL),
            isTrackedByWatchedDirectory: isWatchedFileTrackedLocked(fileURL),
            historyEntryCount: loadManifestLocked(for: fileURL)?.entries.count ?? 0,
            sourceFileExists: fileManager.fileExists(atPath: fileURL.path)
        )
    }

    @discardableResult
    private func deleteSnapshotLocked(_ entry: SnapshotEntry, for fileURL: URL) -> Bool {
        let historyDirectoryURL = historyDirectoryURLLocked(for: fileURL)
        let snapshotsDirectoryURL = historyDirectoryURL.appendingPathComponent("Snapshots", isDirectory: true)
        guard var manifest = loadManifestLocked(for: fileURL) else {
            return false
        }

        let originalCount = manifest.entries.count
        manifest.entries.removeAll { $0.snapshotFileName == entry.snapshotFileName }
        guard manifest.entries.count != originalCount else {
            return false
        }

        try? fileManager.removeItem(at: snapshotsDirectoryURL.appendingPathComponent(entry.snapshotFileName))
        if manifest.entries.isEmpty {
            try? fileManager.removeItem(at: historyDirectoryURL)
        } else {
            saveManifestLocked(manifest, directoryURL: historyDirectoryURL)
        }
        preserveObservedFileStateAfterHistoryDeletionLocked(for: fileURL)
        return true
    }

    @discardableResult
    private func deleteHistoryLocked(for fileURL: URL) -> Bool {
        let historyDirectoryURL = historyDirectoryURLLocked(for: fileURL)
        guard fileManager.fileExists(atPath: historyDirectoryURL.path) else {
            return false
        }
        try? fileManager.removeItem(at: historyDirectoryURL)
        preserveObservedFileStateAfterHistoryDeletionLocked(for: fileURL)
        return !fileManager.fileExists(atPath: historyDirectoryURL.path)
    }

    private func isOpenedFileTrackedLocked(_ fileURL: URL) -> Bool {
        settings.trackOpenedFiles && activeExplicitlyTrackedFileURLsLocked().contains(fileURL.standardizedFileURL)
    }

    private func isWatchedFileTrackedLocked(_ fileURL: URL) -> Bool {
        let directoryPath = settings.normalizedWatchedDirectoryPath
        let extensions = settings.normalizedExtensions
        guard !directoryPath.isEmpty, !extensions.isEmpty else {
            return false
        }

        let rootURL = URL(fileURLWithPath: directoryPath, isDirectory: true).standardizedFileURL
        let isInsideRoot: Bool
        if settings.watchDirectoryRecursively {
            isInsideRoot = fileURL.path == rootURL.path || fileURL.path.hasPrefix(rootURL.path + "/")
        } else {
            isInsideRoot = fileURL.deletingLastPathComponent().standardizedFileURL == rootURL
        }
        guard isInsideRoot else {
            return false
        }

        return matchesTrackedExtensionsLocked(fileURL, extensions: extensions)
    }

    private func pruneDeletedSourceHistoriesLocked(candidateURLs: [URL]) -> (relocatedCandidateURLs: Set<URL>, changedURLs: Set<URL>) {
        guard let directoryURLs = try? fileManager.contentsOfDirectory(
            at: storePaths.localHistoryDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ([], [])
        }

        var candidateByIdentity: [String: URL] = [:]
        for fileURL in candidateURLs {
            guard let sourceIdentity = sourceIdentityLocked(for: fileURL) else {
                continue
            }
            candidateByIdentity[sourceIdentity] = fileURL
        }

        let now = Date()
        var relocatedCandidateURLs: Set<URL> = []
        var changedURLs: Set<URL> = []
        for directoryURL in directoryURLs {
            guard var manifest = loadManifestLocked(directoryURL: directoryURL) else {
                continue
            }

            let sourceURL = URL(fileURLWithPath: manifest.originalFilePath).standardizedFileURL
            let sourceExists = fileManager.fileExists(atPath: sourceURL.path)
            let sourceIdentity = sourceExists ? sourceIdentityLocked(for: sourceURL) : nil
            let relocatedURLByIdentity = manifest.sourceIdentity
                .flatMap { candidateByIdentity[$0] }
                .map(\.standardizedFileURL)
            if let relocatedURL = relocatedURLByIdentity,
               relocatedURL != sourceURL,
               manifest.sourceIdentity != sourceIdentity {
                let shouldCaptureRelocatedURL = relocateTrackedFileStateLocked(from: sourceURL, to: relocatedURL)
                relocateHistoryLocked(
                    manifestDirectoryURL: directoryURL,
                    manifest: &manifest,
                    to: relocatedURL,
                    sourceIdentity: manifest.sourceIdentity
                )
                if shouldCaptureRelocatedURL {
                    relocatedCandidateURLs.insert(relocatedURL)
                }
                changedURLs.insert(sourceURL)
                changedURLs.insert(relocatedURL)
                continue
            }
            if sourceExists,
               !shouldDisplacePathHistoryLocked(
                   manifest: manifest,
                   sourceURL: sourceURL,
                    currentSourceIdentity: sourceIdentity
                ) {
                let shouldSave =
                    manifest.sourceDeletedAt != nil ||
                    manifest.sourceIdentity != sourceIdentity ||
                    manifest.originalFilePath != sourceURL.path ||
                    manifest.displayName != sourceURL.lastPathComponent ||
                    manifest.pathExtension != sourceURL.pathExtension.lowercased()
                updateManifestMetadataLocked(
                    &manifest,
                    for: sourceURL,
                    fileID: fileIdentifier(for: sourceURL),
                    sourceIdentity: sourceIdentity,
                    clearDeletedAt: true
                )
                if shouldSave {
                    saveManifestLocked(manifest, directoryURL: directoryURL)
                    changedURLs.insert(sourceURL)
                }
                continue
            }

            if let sourceIdentity = manifest.sourceIdentity,
               let relocatedURL = candidateByIdentity[sourceIdentity] {
                let shouldCaptureRelocatedURL = relocateTrackedFileStateLocked(from: sourceURL, to: relocatedURL)
                relocateHistoryLocked(
                    manifestDirectoryURL: directoryURL,
                    manifest: &manifest,
                    to: relocatedURL,
                    sourceIdentity: sourceIdentity
                )
                if shouldCaptureRelocatedURL {
                    relocatedCandidateURLs.insert(relocatedURL.standardizedFileURL)
                }
                changedURLs.insert(sourceURL)
                changedURLs.insert(relocatedURL.standardizedFileURL)
                continue
            }

            if let relocatedURL = resolvedBookmarkedURLLocked(from: manifest),
               fileManager.fileExists(atPath: relocatedURL.path) {
                let shouldCaptureRelocatedURL = relocateTrackedFileStateLocked(from: sourceURL, to: relocatedURL)
                relocateHistoryLocked(
                    manifestDirectoryURL: directoryURL,
                    manifest: &manifest,
                    to: relocatedURL,
                    sourceIdentity: sourceIdentityLocked(for: relocatedURL)
                )
                if shouldCaptureRelocatedURL {
                    relocatedCandidateURLs.insert(relocatedURL.standardizedFileURL)
                }
                changedURLs.insert(sourceURL)
                changedURLs.insert(relocatedURL.standardizedFileURL)
                continue
            }

            switch settings.deletedSourceBehavior {
            case .keepAsOrphan:
                observedStatesByPath.removeValue(forKey: sourceURL.path)
                if manifest.sourceDeletedAt == nil {
                    manifest.sourceDeletedAt = now
                    saveManifestLocked(manifest, directoryURL: directoryURL)
                    changedURLs.insert(sourceURL)
                }
            case .deleteImmediately:
                observedStatesByPath.removeValue(forKey: sourceURL.path)
                try? fileManager.removeItem(at: directoryURL)
                changedURLs.insert(sourceURL)
            case .deleteAfterGracePeriod:
                observedStatesByPath.removeValue(forKey: sourceURL.path)
                let deletedAt = manifest.sourceDeletedAt ?? now
                if manifest.sourceDeletedAt == nil {
                    manifest.sourceDeletedAt = deletedAt
                    saveManifestLocked(manifest, directoryURL: directoryURL)
                    changedURLs.insert(sourceURL)
                }
                let graceInterval = TimeInterval(settings.clampedOrphanGracePeriodDays * 86_400)
                if now.timeIntervalSince(deletedAt) >= graceInterval {
                    try? fileManager.removeItem(at: directoryURL)
                    changedURLs.insert(sourceURL)
                }
            }
        }
        return (relocatedCandidateURLs, changedURLs)
    }

    private func fileIdentifier(for fileURL: URL) -> String {
        sha256Hex(for: fileURL.standardizedFileURL.path)
    }

    private func pathHistoryDirectoryURLLocked(for fileURL: URL) -> URL {
        storePaths.localHistoryDirectory
            .appendingPathComponent(fileIdentifier(for: fileURL), isDirectory: true)
    }

    private func existingHistoryDirectoryLocked(matchingSourceIdentity sourceIdentity: String) -> URL? {
        guard let directoryURLs = try? fileManager.contentsOfDirectory(
            at: storePaths.localHistoryDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for directoryURL in directoryURLs {
            guard let manifest = loadManifestLocked(directoryURL: directoryURL),
                  manifest.sourceIdentity == sourceIdentity else {
                continue
            }
            return directoryURL
        }
        return nil
    }

    private func shouldDisplacePathHistoryLocked(
        manifest: FileManifest,
        sourceURL: URL,
        currentSourceIdentity: String?
    ) -> Bool {
        // Atomic-save and replace-in-place editors can swap in a new inode while
        // the same document remains at the same path, including while
        // ClipboardHistory is not running. Treat that as the same file unless
        // the stored bookmark now resolves somewhere else.
        if let bookmarkedURL = resolvedBookmarkedURLLocked(from: manifest),
           fileManager.fileExists(atPath: bookmarkedURL.path),
           bookmarkedURL.standardizedFileURL != sourceURL.standardizedFileURL {
            return true
        }

        guard manifest.sourceDeletedAt != nil else {
            return false
        }

        guard let currentSourceIdentity,
              let manifestSourceIdentity = manifest.sourceIdentity else {
            return true
        }

        return manifestSourceIdentity != currentSourceIdentity
    }

    private func sourceIdentityLocked(for fileURL: URL) -> String? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let fileNumber = attributes[.systemFileNumber],
              let systemNumber = attributes[.systemNumber] else {
            return nil
        }

        return "dev:\(String(describing: systemNumber))-ino:\(String(describing: fileNumber))"
    }

    private func watchedRootDirectoryURLLocked() -> URL {
        URL(fileURLWithPath: settings.normalizedWatchedDirectoryPath, isDirectory: true).standardizedFileURL
    }

    private func watchedDirectoryStateLocked(for directoryURL: URL) -> WatchedDirectoryState {
        guard
            let resourceValues = try? directoryURL.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey]),
            resourceValues.isDirectory == true
        else {
            return WatchedDirectoryState(exists: false, modificationDate: nil)
        }

        return WatchedDirectoryState(exists: true, modificationDate: resourceValues.contentModificationDate)
    }

    private func bookmarkDataLocked(for fileURL: URL) -> Data? {
        try? fileURL.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func resolvedBookmarkedURLLocked(from bookmarkData: Data?) -> URL? {
        guard let bookmarkData else {
            return nil
        }

        var isStale = false
        guard let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        return resolvedURL.standardizedFileURL
    }

    private func resolvedBookmarkedURLLocked(from manifest: FileManifest) -> URL? {
        resolvedBookmarkedURLLocked(from: manifest.sourceBookmarkData)
    }

    private func explicitTrackingStateLocked(
        for fileURL: URL,
        fallbackState: ExplicitlyTrackedFileState? = nil
    ) -> ExplicitlyTrackedFileState {
        ExplicitlyTrackedFileState(
            sourceIdentity: sourceIdentityLocked(for: fileURL) ?? fallbackState?.sourceIdentity,
            sourceBookmarkData: bookmarkDataLocked(for: fileURL) ?? fallbackState?.sourceBookmarkData
        )
    }

    private func sourceMatchesExplicitTrackingLocked(
        trackedURL: URL,
        fileURL: URL,
        state: ExplicitlyTrackedFileState
    ) -> Bool {
        let standardizedTrackedURL = trackedURL.standardizedFileURL
        let standardizedFileURL = fileURL.standardizedFileURL
        let bookmarkedURL = resolvedBookmarkedURLLocked(from: state.sourceBookmarkData)

        if let trackedIdentity = state.sourceIdentity,
           let currentIdentity = sourceIdentityLocked(for: fileURL),
           trackedIdentity == currentIdentity {
            return true
        }

        if let bookmarkedURL,
           fileManager.fileExists(atPath: bookmarkedURL.path) {
            return bookmarkedURL.standardizedFileURL == standardizedFileURL ||
                standardizedFileURL == standardizedTrackedURL
        }

        return false
    }

    private func relocatedExplicitTrackingURLLocked(
        for trackedURL: URL,
        state: ExplicitlyTrackedFileState
    ) -> URL? {
        let standardizedTrackedURL = trackedURL.standardizedFileURL
        if let trackedIdentity = state.sourceIdentity,
           let relocatedURL = findRelocatedFileLocked(
               matchingSourceIdentity: trackedIdentity,
               preferredFileName: standardizedTrackedURL.lastPathComponent,
               searchRootURL: standardizedTrackedURL.deletingLastPathComponent()
           ),
           relocatedURL != standardizedTrackedURL {
            return relocatedURL
        }

        if let bookmarkedURL = resolvedBookmarkedURLLocked(from: state.sourceBookmarkData),
           fileManager.fileExists(atPath: bookmarkedURL.path),
           bookmarkedURL.standardizedFileURL != standardizedTrackedURL,
           sourceMatchesExplicitTrackingLocked(
               trackedURL: standardizedTrackedURL,
               fileURL: bookmarkedURL,
               state: state
           ) {
            return bookmarkedURL.standardizedFileURL
        }
        
        return nil
    }

    private func findRelocatedFileLocked(
        matchingSourceIdentity sourceIdentity: String,
        preferredFileName: String,
        searchRootURL: URL
    ) -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: searchRootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let candidateURL as URL in enumerator {
            let standardizedCandidateURL = candidateURL.standardizedFileURL
            guard standardizedCandidateURL.lastPathComponent == preferredFileName,
                  let resourceValues = try? standardizedCandidateURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true,
                  sourceIdentityLocked(for: standardizedCandidateURL) == sourceIdentity else {
                continue
            }
            return standardizedCandidateURL
        }

        return nil
    }

    private func activeExplicitlyTrackedFileURLsLocked() -> Set<URL> {
        var activeStates: [URL: ExplicitlyTrackedFileState] = [:]
        let trackedEntries = explicitlyTrackedFiles

        for (trackedURL, state) in trackedEntries {
            let standardizedTrackedURL = trackedURL.standardizedFileURL
            if let relocatedURL = relocatedExplicitTrackingURLLocked(
                for: standardizedTrackedURL,
                state: state
            ) {
                activeStates[relocatedURL.standardizedFileURL] = explicitTrackingStateLocked(
                    for: relocatedURL,
                    fallbackState: state
                )
                continue
            }

            if fileManager.fileExists(atPath: standardizedTrackedURL.path),
               sourceMatchesExplicitTrackingLocked(
                   trackedURL: standardizedTrackedURL,
                   fileURL: standardizedTrackedURL,
                   state: state
               ) {
                activeStates[standardizedTrackedURL] = explicitTrackingStateLocked(
                    for: standardizedTrackedURL,
                    fallbackState: state
                )
            }
        }

        explicitlyTrackedFiles = activeStates
        return Set(activeStates.keys)
    }

    private func refreshManifestMetadataLocked(
        at directoryURL: URL,
        for fileURL: URL,
        sourceIdentity: String?,
        clearDeletedAt: Bool
    ) {
        guard var manifest = loadManifestLocked(directoryURL: directoryURL) else {
            return
        }

        let fileID = fileIdentifier(for: fileURL)
        updateManifestMetadataLocked(
            &manifest,
            for: fileURL,
            fileID: fileID,
            sourceIdentity: sourceIdentity,
            clearDeletedAt: clearDeletedAt
        )
        saveManifestLocked(manifest, directoryURL: directoryURL)
    }

    private func relocateHistoryLocked(
        manifestDirectoryURL: URL,
        manifest: inout FileManifest,
        to fileURL: URL,
        sourceIdentity: String?
    ) {
        let destinationDirectoryURL = pathHistoryDirectoryURLLocked(for: fileURL)
        if destinationDirectoryURL != manifestDirectoryURL {
            migrateHistoryDirectoryLocked(
                from: manifestDirectoryURL,
                to: destinationDirectoryURL,
                for: fileURL,
                sourceIdentity: sourceIdentity
            )
            return
        }

        updateManifestMetadataLocked(
            &manifest,
            for: fileURL,
            fileID: fileIdentifier(for: fileURL),
            sourceIdentity: sourceIdentity,
            clearDeletedAt: true
        )
        saveManifestLocked(manifest, directoryURL: manifestDirectoryURL)
    }

    private func migrateHistoryDirectoryLocked(from oldDirectoryURL: URL, to newDirectoryURL: URL, for fileURL: URL, sourceIdentity: String?) {
        guard oldDirectoryURL != newDirectoryURL else {
            refreshManifestMetadataLocked(
                at: oldDirectoryURL,
                for: fileURL,
                sourceIdentity: sourceIdentity,
                clearDeletedAt: true
            )
            return
        }

        guard fileManager.fileExists(atPath: oldDirectoryURL.path) else {
            return
        }

        if fileManager.fileExists(atPath: newDirectoryURL.path) {
            mergeHistoryDirectoryLocked(from: oldDirectoryURL, into: newDirectoryURL, for: fileURL, sourceIdentity: sourceIdentity)
            return
        }

        try? fileManager.moveItem(at: oldDirectoryURL, to: newDirectoryURL)
        let resolvedDirectoryURL = fileManager.fileExists(atPath: newDirectoryURL.path) ? newDirectoryURL : oldDirectoryURL
        refreshManifestMetadataLocked(
            at: resolvedDirectoryURL,
            for: fileURL,
            sourceIdentity: sourceIdentity,
            clearDeletedAt: true
        )
    }

    private func mergeHistoryDirectoryLocked(from oldDirectoryURL: URL, into newDirectoryURL: URL, for fileURL: URL, sourceIdentity: String?) {
        guard var destinationManifest = loadManifestLocked(directoryURL: newDirectoryURL) else {
            return
        }

        let oldManifest = loadManifestLocked(directoryURL: oldDirectoryURL)
        let destinationSnapshotsDirectoryURL = newDirectoryURL.appendingPathComponent("Snapshots", isDirectory: true)
        let oldSnapshotsDirectoryURL = oldDirectoryURL.appendingPathComponent("Snapshots", isDirectory: true)
        try? fileManager.createDirectory(at: destinationSnapshotsDirectoryURL, withIntermediateDirectories: true)

        if let oldManifest {
            let existingSnapshotNames = Set(destinationManifest.entries.map(\.snapshotFileName))
            for entry in oldManifest.entries where !existingSnapshotNames.contains(entry.snapshotFileName) {
                let oldSnapshotURL = oldSnapshotsDirectoryURL.appendingPathComponent(entry.snapshotFileName)
                let newSnapshotURL = destinationSnapshotsDirectoryURL.appendingPathComponent(entry.snapshotFileName)
                if fileManager.fileExists(atPath: oldSnapshotURL.path),
                   !fileManager.fileExists(atPath: newSnapshotURL.path) {
                    try? fileManager.copyItem(at: oldSnapshotURL, to: newSnapshotURL)
                }
                destinationManifest.entries.append(entry)
            }
        }

        destinationManifest.entries.sort { $0.createdAt < $1.createdAt }
        if destinationManifest.entries.count > settings.clampedMaxSnapshotsPerFile {
            let overflow = destinationManifest.entries.count - settings.clampedMaxSnapshotsPerFile
            let removedEntries = destinationManifest.entries.prefix(overflow)
            for entry in removedEntries {
                let snapshotURL = destinationSnapshotsDirectoryURL.appendingPathComponent(entry.snapshotFileName)
                try? fileManager.removeItem(at: snapshotURL)
            }
            destinationManifest.entries.removeFirst(overflow)
        }

        updateManifestMetadataLocked(
            &destinationManifest,
            for: fileURL,
            fileID: fileIdentifier(for: fileURL),
            sourceIdentity: sourceIdentity,
            clearDeletedAt: true
        )
        saveManifestLocked(destinationManifest, directoryURL: newDirectoryURL)
        try? fileManager.removeItem(at: oldDirectoryURL)
    }

    private func displaceOrphanHistoryLocked(at directoryURL: URL, manifest: FileManifest) {
        let displacedDirectoryURL = displacedHistoryDirectoryURLLocked(for: manifest)
        guard displacedDirectoryURL != directoryURL else {
            return
        }

        if fileManager.fileExists(atPath: displacedDirectoryURL.path) {
            return
        }

        observedStatesByPath.removeValue(forKey: URL(fileURLWithPath: manifest.originalFilePath).standardizedFileURL.path)
        try? fileManager.moveItem(at: directoryURL, to: displacedDirectoryURL)
    }

    private func updateManifestMetadataLocked(
        _ manifest: inout FileManifest,
        for fileURL: URL,
        fileID: String,
        sourceIdentity: String?,
        clearDeletedAt: Bool
    ) {
        manifest.fileID = fileID
        manifest.sourceIdentity = sourceIdentity
        manifest.sourceBookmarkData = bookmarkDataLocked(for: fileURL)
        manifest.originalFilePath = fileURL.path
        manifest.displayName = fileURL.lastPathComponent
        manifest.pathExtension = fileURL.pathExtension.lowercased()
        if clearDeletedAt {
            manifest.sourceDeletedAt = nil
        }
    }

    private func preserveObservedFileStateAfterHistoryDeletionLocked(for fileURL: URL) {
        let standardizedURL = fileURL.standardizedFileURL
        let path = standardizedURL.path
        guard shouldTrackFileLocked(standardizedURL),
              let resourceValues = try? standardizedURL.resourceValues(
                  forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
              ),
              resourceValues.isRegularFile == true else {
            observedStatesByPath.removeValue(forKey: path)
            return
        }

        let now = Date()
        let previousState = observedStatesByPath[path]
        var encoding = String.Encoding.utf8
        let contentHash: String?
        if let text = try? String(contentsOf: standardizedURL, usedEncoding: &encoding) {
            contentHash = sha256Hex(for: text)
        } else {
            contentHash = previousState?.contentHash
        }

        observedStatesByPath[path] = ObservedFileState(
            modificationDate: resourceValues.contentModificationDate,
            fileSize: resourceValues.fileSize,
            contentHash: contentHash,
            lastContentReadAt: now
        )
    }

    @discardableResult
    private func relocateTrackedFileStateLocked(from oldFileURL: URL, to newFileURL: URL) -> Bool {
        let standardizedOldURL = oldFileURL.standardizedFileURL
        let standardizedNewURL = newFileURL.standardizedFileURL

        let previousTrackingState = explicitlyTrackedFiles.removeValue(forKey: standardizedOldURL)
        let wasExplicitlyTracked = previousTrackingState != nil
        if let previousTrackingState {
            explicitlyTrackedFiles[standardizedNewURL] = explicitTrackingStateLocked(
                for: standardizedNewURL,
                fallbackState: previousTrackingState
            )
        }

        if let observedState = observedStatesByPath.removeValue(forKey: standardizedOldURL.path) {
            observedStatesByPath[standardizedNewURL.path] = observedState
        }

        return wasExplicitlyTracked
    }

    private func postHistoryDidChangeLocked(for fileURL: URL) {
        let standardizedURL = fileURL.standardizedFileURL
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .fileLocalHistoryDidChange,
                object: nil,
                userInfo: ["fileURL": standardizedURL]
            )
        }
    }

    private func displacedHistoryDirectoryURLLocked(for manifest: FileManifest) -> URL {
        let discriminator = manifest.sourceIdentity
            ?? manifest.entries.first?.snapshotFileName
            ?? manifest.fileID
        let displacedIdentifier = sha256Hex(for: "orphan:\(manifest.originalFilePath):\(discriminator)")
        return storePaths.localHistoryDirectory
            .appendingPathComponent("\(displacedIdentifier)-orphan", isDirectory: true)
    }

    static func shouldSkipContentRead(
        forceRead: Bool,
        previousModificationDate: Date?,
        previousFileSize: Int?,
        previousContentHash: String?,
        lastContentReadAt: Date?,
        currentModificationDate: Date?,
        currentFileSize: Int?,
        now: Date = Date(),
        unchangedPollingRecheckInterval: TimeInterval = unchangedPollingRecheckInterval
    ) -> Bool {
        guard !forceRead,
              previousModificationDate == currentModificationDate,
              previousFileSize == currentFileSize,
              previousContentHash != nil,
              let lastContentReadAt else {
            return false
        }

        return now.timeIntervalSince(lastContentReadAt) < unchangedPollingRecheckInterval
    }

    private func snapshotFileName(for fileURL: URL, contentHash: String) -> String {
        let timestamp = Self.snapshotDateFormatter.string(from: Date())
        let extensionSuffix: String
        if fileURL.pathExtension.isEmpty {
            extensionSuffix = ".txt"
        } else {
            extensionSuffix = ".\(fileURL.pathExtension.lowercased())"
        }
        return "\(timestamp)-\(contentHash.prefix(12))\(extensionSuffix)"
    }

    private func sha256Hex(for string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static let snapshotDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()

    private static let deletedSourcePruneInterval: TimeInterval = 10
    private static let minimumWatchedDirectoryPollingInterval: TimeInterval = 5
    private static let unchangedPollingRecheckInterval: TimeInterval = 30
    private static let watchedDirectoryRefreshInterval: TimeInterval = 10
}
