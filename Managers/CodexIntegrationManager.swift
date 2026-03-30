import Foundation

struct ClipboardCodexIntegrationStatus {
    let helperScriptURL: URL
    let shellConfigURL: URL?
    let helperInstalled: Bool
    let shellConfigured: Bool?
    let unmanagedShellExportsDetected: Bool?
}

struct CodexIntegrationManager {
    static let managedBlockStart = "# >>> ClipboardHistory Codex integration >>>"
    static let managedBlockEnd = "# <<< ClipboardHistory Codex integration <<<"

    private struct ShellInspection {
        let hasManagedBlock: Bool
        let hasUnmanagedEditorExport: Bool
    }

    private let storePaths: ClipboardStorePaths
    private let shellPath: String
    private let homeDirectory: URL
    private let fileManager: FileManager

    init(
        storePaths: ClipboardStorePaths,
        shellPath: String,
        homeDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.storePaths = storePaths
        self.shellPath = shellPath
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    func status(inspectShellConfig: Bool = false) -> ClipboardCodexIntegrationStatus {
        let shellConfigURL = preferredShellConfigURL()
        let helperInstalled = fileManager.isExecutableFile(atPath: storePaths.codexHelperScriptURL.path)
        let shellConfigured: Bool?
        let unmanagedShellExportsDetected: Bool?

        if inspectShellConfig, let shellConfigURL {
            let content = (try? String(contentsOf: shellConfigURL, encoding: .utf8)) ?? ""
            let inspection = inspectShellConfigContent(content)
            shellConfigured = inspection.hasManagedBlock
            unmanagedShellExportsDetected = inspection.hasUnmanagedEditorExport
        } else {
            shellConfigured = nil
            unmanagedShellExportsDetected = nil
        }

        return ClipboardCodexIntegrationStatus(
            helperScriptURL: storePaths.codexHelperScriptURL,
            shellConfigURL: shellConfigURL,
            helperInstalled: helperInstalled,
            shellConfigured: shellConfigured,
            unmanagedShellExportsDetected: unmanagedShellExportsDetected
        )
    }

    func install() throws -> ClipboardCodexIntegrationStatus {
        try storePaths.ensureDirectories()
        try installHelperScript(at: storePaths.codexHelperScriptURL)
        try installShellBlock(helperScriptURL: storePaths.codexHelperScriptURL)
        return status(inspectShellConfig: true)
    }

    func remove() throws -> ClipboardCodexIntegrationStatus {
        if fileManager.fileExists(atPath: storePaths.codexHelperScriptURL.path) {
            try? fileManager.removeItem(at: storePaths.codexHelperScriptURL)
        }
        try removeShellBlock()
        return status(inspectShellConfig: true)
    }

    private func installHelperScript(at helperURL: URL) throws {
        let script = """
        #!/bin/zsh
        set -eu

        if [ "$#" -lt 1 ]; then
          echo "ClipboardHistory Codex helper requires a file path." >&2
          exit 1
        fi

        FILE_INPUT="$1"
        if [ "${FILE_INPUT#/}" = "$FILE_INPUT" ]; then
          FILE_INPUT="$PWD/$FILE_INPUT"
        fi
        FILE_DIR="$(cd "$(dirname "$FILE_INPUT")" && pwd)"
        FILE_PATH="$FILE_DIR/$(basename "$FILE_INPUT")"

        SUPPORT_DIR="$HOME/Library/Application Support/ClipboardHistory/Codex/Sessions"
        /bin/mkdir -p "$SUPPORT_DIR"
        HASH="$(printf '%s' "$FILE_PATH" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
        DONE_FILE="$SUPPORT_DIR/$HASH.done"
        /bin/rm -f "$DONE_FILE"

        STATE_DIR="$HOME/Library/Application Support/ClipboardHistory/Codex/State"
        /bin/mkdir -p "$STATE_DIR"

        if [ ! -f "$FILE_PATH" ]; then
          : > "$FILE_PATH"
        fi

        REQUEST_FILE="$HOME/Library/Application Support/ClipboardHistory/Codex/open-request.txt"
        REQUEST_ID="$(/usr/bin/uuidgen)"
        PROJECT_ROOT="$PWD"
        STATE_FILE="$STATE_DIR/$REQUEST_ID.alive"
        : > "$STATE_FILE"
        cleanup() {
          /bin/rm -f "$STATE_FILE"
        }
        trap cleanup EXIT HUP INT TERM
        printf '%s\\n%s\\n%s\\n%s\\n' "$REQUEST_ID" "$FILE_PATH" "$PROJECT_ROOT" "$STATE_FILE" > "$REQUEST_FILE"

        if ! /usr/bin/open -b "kazushi-koshimo.ClipboardHistory"; then
          if [ -d "/Applications/ClipboardHistory.app" ]; then
            /usr/bin/open -a "/Applications/ClipboardHistory.app"
          else
            /usr/bin/open -a "ClipboardHistory"
          fi
        fi

        while [ ! -f "$DONE_FILE" ]; do
          /bin/sleep 0.2
        done

        /bin/rm -f "$DONE_FILE"
        """

        try script.write(to: helperURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: helperURL.path
        )
    }

    private func installShellBlock(helperScriptURL: URL) throws {
        guard let shellConfigURL = preferredShellConfigURL() else {
            throw SettingsMutationError.unavailableShortcut("Codex integration currently supports zsh or bash.")
        }

        let existingContent = (try? String(contentsOf: shellConfigURL, encoding: .utf8)) ?? ""
        let inspection = inspectShellConfigContent(existingContent)
        if inspection.hasUnmanagedEditorExport {
            throw SettingsMutationError.unavailableShortcut(
                "Shell config already defines EDITOR or VISUAL outside ClipboardHistory's managed block. Inspect and clean it manually before installing Codex integration."
            )
        }

        let helperPathQuoted = shellSingleQuoted(helperScriptURL.path)
        let block = """
        \(Self.managedBlockStart)
        export EDITOR=\(helperPathQuoted)
        export VISUAL=\(helperPathQuoted)
        \(Self.managedBlockEnd)
        """

        let updatedContent = replacingManagedShellBlock(in: existingContent, with: block)
        try updatedContent.write(to: shellConfigURL, atomically: true, encoding: .utf8)
    }

    private func removeShellBlock() throws {
        guard let shellConfigURL = preferredShellConfigURL() else {
            throw SettingsMutationError.unavailableShortcut("Codex integration currently supports zsh or bash.")
        }

        let existingContent = (try? String(contentsOf: shellConfigURL, encoding: .utf8)) ?? ""
        let inspection = inspectShellConfigContent(existingContent)
        guard inspection.hasManagedBlock else {
            return
        }

        let updatedContent = replacingManagedShellBlock(in: existingContent, with: "")
        try updatedContent.write(to: shellConfigURL, atomically: true, encoding: .utf8)
    }

    private func preferredShellConfigURL() -> URL? {
        if shellPath.contains("bash") {
            return homeDirectory.appendingPathComponent(".bashrc")
        }
        if shellPath.contains("zsh") || shellPath.isEmpty {
            return homeDirectory.appendingPathComponent(".zshrc")
        }
        return nil
    }

    private func replacingManagedShellBlock(in existingContent: String, with block: String) -> String {
        let normalizedBlock = block.isEmpty ? "" : (block.hasSuffix("\n") ? block : "\(block)\n")
        guard let startRange = existingContent.range(of: Self.managedBlockStart),
              let endRange = existingContent.range(of: Self.managedBlockEnd) else {
            guard !normalizedBlock.isEmpty else {
                return existingContent
            }
            if existingContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return normalizedBlock
            }
            return existingContent.trimmingCharacters(in: .newlines) + "\n\n" + normalizedBlock
        }

        let replacementRange = startRange.lowerBound..<endRange.upperBound
        var updated = existingContent
        if normalizedBlock.isEmpty {
            updated.replaceSubrange(replacementRange, with: "")
            updated = updated.replacingOccurrences(of: "\n\n\n", with: "\n\n")
            return updated.trimmingCharacters(in: .newlines) + "\n"
        }

        updated.replaceSubrange(replacementRange, with: normalizedBlock.trimmingCharacters(in: .newlines))
        if !updated.hasSuffix("\n") {
            updated.append("\n")
        }
        return updated
    }

    private func inspectShellConfigContent(_ content: String) -> ShellInspection {
        let hasManagedBlock = content.contains(Self.managedBlockStart)

        var stripped = content
        if let startRange = stripped.range(of: Self.managedBlockStart),
           let endRange = stripped.range(of: Self.managedBlockEnd) {
            stripped.removeSubrange(startRange.lowerBound..<endRange.upperBound)
        }

        let hasUnmanagedEditorExport = stripped
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .contains { line in
                !line.hasPrefix("#") && (
                    line.hasPrefix("export EDITOR=")
                    || line.hasPrefix("export VISUAL=")
                    || line.hasPrefix("EDITOR=")
                    || line.hasPrefix("VISUAL=")
                )
            }

        return ShellInspection(
            hasManagedBlock: hasManagedBlock,
            hasUnmanagedEditorExport: hasUnmanagedEditorExport
        )
    }

    private func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
