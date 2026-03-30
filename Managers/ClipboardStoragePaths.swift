import Foundation

struct ClipboardStorePaths {
    let appSupportDirectory: URL
    let storeURL: URL
    let imageDirectory: URL
    let largeTextDirectory: URL
    let noteDraftDirectory: URL
    let codexIntegrationDirectory: URL
    let codexCompletionDirectory: URL
    let codexSessionStateDirectory: URL
    let codexRequestDirectory: URL
    let codexOpenRequestURL: URL
    let codexHelperScriptURL: URL

    static func `default`(fileManager: FileManager = .default) -> ClipboardStorePaths {
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let storeDirectory = supportDirectory.appendingPathComponent("ClipboardHistory", isDirectory: true)
        let imageDirectory = supportDirectory.appendingPathComponent("ClipboardHistoryApp/Images", isDirectory: true)
        let largeTextDirectory = storeDirectory.appendingPathComponent("LargeText", isDirectory: true)
        let noteDraftDirectory = storeDirectory.appendingPathComponent("Notes", isDirectory: true)
        let codexIntegrationDirectory = homeDirectory.appendingPathComponent(".clipboardhistory/bin", isDirectory: true)
        let codexRequestDirectory = storeDirectory.appendingPathComponent("Codex", isDirectory: true)
        let codexCompletionDirectory = codexRequestDirectory.appendingPathComponent("Sessions", isDirectory: true)
        let codexSessionStateDirectory = codexRequestDirectory.appendingPathComponent("State", isDirectory: true)
        let codexOpenRequestURL = codexRequestDirectory.appendingPathComponent("open-request.txt")
        let codexHelperScriptURL = codexIntegrationDirectory.appendingPathComponent("clipboardhistory-codex-editor")
        return ClipboardStorePaths(
            appSupportDirectory: supportDirectory,
            storeURL: storeDirectory.appendingPathComponent("ClipboardHistory.store"),
            imageDirectory: imageDirectory,
            largeTextDirectory: largeTextDirectory,
            noteDraftDirectory: noteDraftDirectory,
            codexIntegrationDirectory: codexIntegrationDirectory,
            codexCompletionDirectory: codexCompletionDirectory,
            codexSessionStateDirectory: codexSessionStateDirectory,
            codexRequestDirectory: codexRequestDirectory,
            codexOpenRequestURL: codexOpenRequestURL,
            codexHelperScriptURL: codexHelperScriptURL
        )
    }

    func ensureDirectories(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: imageDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: largeTextDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: noteDraftDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: codexIntegrationDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: codexRequestDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: codexCompletionDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: codexSessionStateDirectory,
            withIntermediateDirectories: true
        )
    }
}
