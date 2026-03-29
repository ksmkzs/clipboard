import XCTest
@testable import ClipboardHistory

final class CodexIntegrationManagerTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var homeDirectory: URL!
    private var supportDirectory: URL!
    private var shellConfigURL: URL!
    private var storePaths: ClipboardStorePaths!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("CodexIntegrationManagerTests.\(UUID().uuidString)", isDirectory: true)
        homeDirectory = temporaryDirectory.appendingPathComponent("home", isDirectory: true)
        supportDirectory = temporaryDirectory.appendingPathComponent("Application Support", isDirectory: true)
        shellConfigURL = homeDirectory.appendingPathComponent(".zshrc")

        try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)

        storePaths = ClipboardStorePaths(
            appSupportDirectory: supportDirectory,
            storeURL: supportDirectory.appendingPathComponent("ClipboardHistory/ClipboardHistory.store"),
            imageDirectory: supportDirectory.appendingPathComponent("ClipboardHistoryApp/Images", isDirectory: true),
            largeTextDirectory: supportDirectory.appendingPathComponent("ClipboardHistory/LargeText", isDirectory: true),
            noteDraftDirectory: supportDirectory.appendingPathComponent("ClipboardHistory/Notes", isDirectory: true),
            codexIntegrationDirectory: homeDirectory.appendingPathComponent(".clipboardhistory/bin", isDirectory: true),
            codexCompletionDirectory: supportDirectory.appendingPathComponent("ClipboardHistory/Codex/Sessions", isDirectory: true),
            codexRequestDirectory: supportDirectory.appendingPathComponent("ClipboardHistory/Codex", isDirectory: true),
            codexOpenRequestURL: supportDirectory.appendingPathComponent("ClipboardHistory/Codex/open-request.txt"),
            codexHelperScriptURL: homeDirectory.appendingPathComponent(".clipboardhistory/bin/clipboardhistory-codex-editor")
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        storePaths = nil
        shellConfigURL = nil
        supportDirectory = nil
        homeDirectory = nil
        temporaryDirectory = nil
    }

    func testInstallWritesManagedShellBlockAndHelper() throws {
        try "# existing alias\nalias ll='ls -l'\n".write(to: shellConfigURL, atomically: true, encoding: .utf8)

        let manager = makeManager()
        let status = try manager.install()

        let shellContent = try String(contentsOf: shellConfigURL, encoding: .utf8)
        XCTAssertTrue(shellContent.contains(CodexIntegrationManager.managedBlockStart))
        XCTAssertTrue(shellContent.contains("export EDITOR='"))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: storePaths.codexHelperScriptURL.path))
        XCTAssertTrue(status.helperInstalled)
        XCTAssertEqual(status.shellConfigured, true)
        XCTAssertEqual(status.unmanagedShellExportsDetected, false)
    }

    func testInstallRejectsUnmanagedEditorExport() throws {
        try "export EDITOR='/usr/bin/vim'\n".write(to: shellConfigURL, atomically: true, encoding: .utf8)

        let manager = makeManager()

        XCTAssertThrowsError(try manager.install()) { error in
            guard case let SettingsMutationError.unavailableShortcut(message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("Shell config already defines EDITOR or VISUAL"))
        }
    }

    func testRemoveWithoutManagedBlockLeavesShellConfigUntouched() throws {
        let original = "export PATH=\"$HOME/bin:$PATH\"\n"
        try original.write(to: shellConfigURL, atomically: true, encoding: .utf8)

        let manager = makeManager()
        let status = try manager.remove()

        let shellContent = try String(contentsOf: shellConfigURL, encoding: .utf8)
        XCTAssertEqual(shellContent, original)
        XCTAssertEqual(status.shellConfigured, false)
        XCTAssertEqual(status.unmanagedShellExportsDetected, false)
    }

    func testStatusReportsUnmanagedEditorExportWhenRequested() throws {
        try "VISUAL='/usr/bin/nvim'\n".write(to: shellConfigURL, atomically: true, encoding: .utf8)

        let manager = makeManager()
        let status = manager.status(inspectShellConfig: true)

        XCTAssertEqual(status.shellConfigured, false)
        XCTAssertEqual(status.unmanagedShellExportsDetected, true)
    }

    private func makeManager() -> CodexIntegrationManager {
        CodexIntegrationManager(
            storePaths: storePaths,
            shellPath: "/bin/zsh",
            homeDirectory: homeDirectory
        )
    }
}
