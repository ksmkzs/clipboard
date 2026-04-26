import XCTest
import AppKit
import Carbon
@testable import ClipboardHistory

@MainActor
final class PanelKeyboardRoutingTests: XCTestCase {
    func testTabCallsPinnedAreaToggleHandlerInPanelMode() {
        let view = CustomKeyView(frame: .init(x: 0, y: 0, width: 240, height: 120))
        var didTogglePins = false
        view.togglePinnedAreaShortcut = AppSettings.default.togglePinnedAreaShortcut
        view.onTogglePinnedArea = {
            didTogglePins = true
        }

        view.keyDown(with: keyEvent(keyCode: 48, characters: "\t"))

        XCTAssertTrue(didTogglePins)
    }

    func testEditorActiveCustomKeyViewDoesNotInterceptTabShortcut() {
        let view = CustomKeyView(frame: .init(x: 0, y: 0, width: 240, height: 120))
        var didTogglePins = false
        view.isEditorActive = true
        view.togglePinnedAreaShortcut = AppSettings.default.togglePinnedAreaShortcut
        view.onTogglePinnedArea = {
            didTogglePins = true
        }

        view.keyDown(with: keyEvent(keyCode: 48, characters: "\t"))

        XCTAssertFalse(didTogglePins)
    }

    func testEditorActiveCustomKeyViewDoesNotInterceptTogglePinShortcut() {
        let view = CustomKeyView(frame: .init(x: 0, y: 0, width: 240, height: 120))
        var didTogglePin = false
        view.isEditorActive = true
        view.togglePinShortcut = AppSettings.default.togglePinShortcut
        view.onTogglePin = {
            didTogglePin = true
        }

        view.keyDown(with: keyEvent(keyCode: Int(kVK_ANSI_P), characters: "p"))

        XCTAssertFalse(didTogglePin)
    }

    func testCommandQuestionMarkCallsHelpHandler() {
        let view = CustomKeyView(frame: .init(x: 0, y: 0, width: 240, height: 120))
        var didToggleHelp = false
        view.onToggleHelp = {
            didToggleHelp = true
        }

        let handled = view.performKeyEquivalent(
            with: keyEvent(keyCode: 44, characters: "?", modifiers: [.command, .shift])
        )

        XCTAssertTrue(handled)
        XCTAssertTrue(didToggleHelp)
    }

    func testCommandSlashCallsHelpHandler() {
        let view = CustomKeyView(frame: .init(x: 0, y: 0, width: 240, height: 120))
        var didToggleHelp = false
        view.onToggleHelp = {
            didToggleHelp = true
        }

        let handled = view.performKeyEquivalent(
            with: keyEvent(keyCode: 44, characters: "/", modifiers: .command)
        )

        XCTAssertTrue(handled)
        XCTAssertTrue(didToggleHelp)
    }

    func testReturnCallsSelectionCommitHandler() {
        let view = CustomKeyView(frame: .init(x: 0, y: 0, width: 240, height: 120))
        var didCommitSelection = false
        view.onEnter = {
            didCommitSelection = true
        }

        view.keyDown(with: keyEvent(keyCode: 36, characters: "\r"))

        XCTAssertTrue(didCommitSelection)
    }

    func testCommandReturnCallsPasteHandler() {
        let view = CustomKeyView(frame: .init(x: 0, y: 0, width: 240, height: 120))
        var didPaste = false
        view.onPasteSelection = {
            didPaste = true
        }

        let handled = view.performKeyEquivalent(
            with: keyEvent(keyCode: 36, characters: "\r", modifiers: .command)
        )

        XCTAssertTrue(handled)
        XCTAssertTrue(didPaste)
    }

    func testPlainNCallsNewNoteHandler() {
        let view = CustomKeyView(frame: .init(x: 0, y: 0, width: 240, height: 120))
        var didCreateNote = false
        view.newNoteShortcut = AppSettings.default.newNoteShortcut
        view.onCreateNewNote = {
            didCreateNote = true
        }

        view.keyDown(with: keyEvent(keyCode: Int(kVK_ANSI_N), characters: "n"))

        XCTAssertTrue(didCreateNote)
    }

    func testCopyJoinedShortcutCallsJoinedCopyHandlerInPanelMode() {
        let view = CustomKeyView(frame: .init(x: 0, y: 0, width: 240, height: 120))
        var didCopyJoined = false
        var didCopyRaw = false
        view.copyJoinedShortcut = AppSettings.default.copyJoinedShortcut
        view.onCopyJoinedCommand = {
            didCopyJoined = true
        }
        view.onCopyCommand = {
            didCopyRaw = true
        }

        let handled = view.performKeyEquivalent(
            with: keyEvent(keyCode: Int(view.copyJoinedShortcut.keyCode), characters: "c", modifiers: [.command, .option])
        )

        XCTAssertTrue(handled)
        XCTAssertTrue(didCopyJoined)
        XCTAssertFalse(didCopyRaw)
    }

    func testCopyNormalizedShortcutCallsNormalizedCopyHandlerInPanelMode() {
        let view = CustomKeyView(frame: .init(x: 0, y: 0, width: 240, height: 120))
        var didCopyNormalized = false
        var didCopyRaw = false
        view.copyNormalizedShortcut = AppSettings.default.copyNormalizedShortcut
        view.onCopyNormalizedCommand = {
            didCopyNormalized = true
        }
        view.onCopyCommand = {
            didCopyRaw = true
        }

        let handled = view.performKeyEquivalent(
            with: keyEvent(keyCode: Int(view.copyNormalizedShortcut.keyCode), characters: "C", modifiers: [.command, .shift])
        )

        XCTAssertTrue(handled)
        XCTAssertTrue(didCopyNormalized)
        XCTAssertFalse(didCopyRaw)
    }

    func testCopyJoinedWithSpacesShortcutCallsSpaceJoinHandlerInPanelMode() {
        let view = CustomKeyView(frame: .init(x: 0, y: 0, width: 240, height: 120))
        var didCopyJoinedWithSpaces = false
        var didCopyRaw = false
        view.copyJoinedWithSpacesShortcut = AppSettings.default.copyJoinedWithSpacesShortcut
        view.onCopyJoinedWithSpacesCommand = {
            didCopyJoinedWithSpaces = true
        }
        view.onCopyCommand = {
            didCopyRaw = true
        }

        view.keyDown(with: keyEvent(keyCode: Int(view.copyJoinedWithSpacesShortcut.keyCode), characters: "C", modifiers: [.option, .shift]))

        XCTAssertTrue(didCopyJoinedWithSpaces)
        XCTAssertFalse(didCopyRaw)
    }

    func testPlainCommandCOnlyCallsRawCopyHandler() {
        let view = CustomKeyView(frame: .init(x: 0, y: 0, width: 240, height: 120))
        var didCopyRaw = false
        var didCopyJoined = false
        var didCopyNormalized = false
        view.onCopyCommand = {
            didCopyRaw = true
        }
        view.onCopyJoinedCommand = {
            didCopyJoined = true
        }
        view.onCopyNormalizedCommand = {
            didCopyNormalized = true
        }

        let handled = view.performKeyEquivalent(
            with: keyEvent(keyCode: Int(kVK_ANSI_C), characters: "c", modifiers: .command)
        )

        XCTAssertTrue(handled)
        XCTAssertTrue(didCopyRaw)
        XCTAssertFalse(didCopyJoined)
        XCTAssertFalse(didCopyNormalized)
    }

    func testEditorActiveDoesNotInterceptPlainCommandC() {
        let view = CustomKeyView(frame: .init(x: 0, y: 0, width: 240, height: 120))
        var didCopyRaw = false
        view.isEditorActive = true
        view.onCopyCommand = {
            didCopyRaw = true
        }

        let handled = view.performKeyEquivalent(
            with: keyEvent(keyCode: Int(kVK_ANSI_C), characters: "c", modifiers: .command)
        )

        XCTAssertFalse(handled)
        XCTAssertFalse(didCopyRaw)
    }

    func testPanelReclaimsFirstResponderFromNonEditablePreviewTextView() {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 240, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        let preview = NSTextView(frame: .init(x: 0, y: 0, width: 120, height: 60))
        preview.isEditable = false

        XCTAssertTrue(CustomKeyView.shouldReclaimPanelFirstResponder(from: preview, in: window))
    }

    func testPanelDoesNotStealFirstResponderFromEditableTextView() {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 240, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        let editor = NSTextView(frame: .init(x: 0, y: 0, width: 120, height: 60))
        editor.isEditable = true

        XCTAssertFalse(CustomKeyView.shouldReclaimPanelFirstResponder(from: editor, in: window))
    }

    func testCommandEqualsCallsZoomInHandler() {
        let view = CustomKeyView(frame: .init(x: 0, y: 0, width: 240, height: 120))
        var didZoom = false
        view.onZoomIn = { didZoom = true }

        let handled = view.performKeyEquivalent(
            with: keyEvent(keyCode: Int(kVK_ANSI_Equal), characters: "=", modifiers: .command)
        )

        XCTAssertTrue(handled)
        XCTAssertTrue(didZoom)
    }

    func testCommandMinusCallsZoomOutHandler() {
        let view = CustomKeyView(frame: .init(x: 0, y: 0, width: 240, height: 120))
        var didZoom = false
        view.onZoomOut = { didZoom = true }

        let handled = view.performKeyEquivalent(
            with: keyEvent(keyCode: Int(kVK_ANSI_Minus), characters: "-", modifiers: .command)
        )

        XCTAssertTrue(handled)
        XCTAssertTrue(didZoom)
    }

    func testCommandZeroCallsResetZoomHandler() {
        let view = CustomKeyView(frame: .init(x: 0, y: 0, width: 240, height: 120))
        var didReset = false
        view.onResetZoom = { didReset = true }

        let handled = view.performKeyEquivalent(
            with: keyEvent(keyCode: Int(kVK_ANSI_0), characters: "0", modifiers: .command)
        )

        XCTAssertTrue(handled)
        XCTAssertTrue(didReset)
    }

    private func keyEvent(keyCode: Int, characters: String, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: String(characters.lowercased()),
            isARepeat: false,
            keyCode: UInt16(keyCode)
        )!
    }
}

final class ClipboardHelpCatalogTests: XCTestCase {
    func testHeaderCatalogIncludesCompactPanelOperations() {
        let commands = ClipboardHelpCatalog.panelHeaderCommands(settings: .default)
        let titles = Set(commands.map(\.title))

        XCTAssertEqual(commands.count, 11)
        XCTAssertTrue(titles.contains("Close"))
        XCTAssertTrue(titles.contains("Undo / Redo"))
        XCTAssertTrue(titles.contains("Paste into current window"))
        XCTAssertTrue(titles.contains("New"))
        XCTAssertTrue(titles.contains("Edit"))
        XCTAssertTrue(titles.contains("Pin"))
        XCTAssertTrue(titles.contains("Delete"))
        XCTAssertTrue(titles.contains("Pins"))
        XCTAssertTrue(titles.contains("One Line"))
        XCTAssertTrue(titles.contains("One Line + Space"))
        XCTAssertTrue(titles.contains("Normalize"))
    }

    func testHeaderCatalogIncludesCompactEditorOperations() {
        let commands = ClipboardHelpCatalog.editorHeaderCommands(settings: .default)
        let titles = Set(commands.map(\.title))

        XCTAssertTrue(titles.contains("Cancel"))
        XCTAssertTrue(titles.contains("Confirm"))
        XCTAssertTrue(titles.contains("Undo / Redo"))
        XCTAssertTrue(titles.contains("Indent"))
        XCTAssertTrue(titles.contains("Outdent"))
        XCTAssertTrue(titles.contains("Move Line"))
        XCTAssertTrue(titles.contains("Markdown Preview"))
        XCTAssertTrue(titles.contains("One Line"))
        XCTAssertTrue(titles.contains("One Line + Space"))
        XCTAssertTrue(titles.contains("Normalize"))
    }

    func testPanelHelpCatalogIncludesFormerHeaderActions() {
        let commands = ClipboardHelpCatalog.panelCommands(settings: .default)
        let titles = Set(commands.map(\.title))

        XCTAssertTrue(titles.contains("Close"))
        XCTAssertTrue(titles.contains("Undo / Redo"))
        XCTAssertTrue(titles.contains("Paste selected item into current window"))
        XCTAssertTrue(titles.contains("Create a new empty note at #1"))
        XCTAssertTrue(titles.contains("Edit selected item"))
        XCTAssertTrue(titles.contains("Pin selected item"))
        XCTAssertTrue(titles.contains("Delete selected item"))
        XCTAssertTrue(titles.contains("Show or hide pinned items"))
        XCTAssertTrue(titles.contains("Normalize the focused item"))
        XCTAssertTrue(titles.contains("Turn the focused item into one line"))
        XCTAssertTrue(titles.contains("Join focused item with spaces"))
    }

    func testEditorHelpCatalogIncludesPrimaryEditorActions() {
        let commands = ClipboardHelpCatalog.editorCommands(settings: .default)
        let titles = Set(commands.map(\.title))

        XCTAssertTrue(titles.contains("Confirm current edit"))
        XCTAssertTrue(titles.contains("Cancel"))
        XCTAssertTrue(titles.contains("Undo / Redo"))
        XCTAssertTrue(titles.contains("Indent selected lines"))
        XCTAssertTrue(titles.contains("Outdent selected lines"))
        XCTAssertTrue(titles.contains("Move line up / down"))
        XCTAssertTrue(titles.contains("Markdown preview"))
        XCTAssertTrue(titles.contains("Normalize selection whitespace"))
        XCTAssertTrue(titles.contains("Join selection into one sentence"))
        XCTAssertTrue(titles.contains("Join selection with spaces"))
    }

    func testOutsideWindowHelpCatalogIncludesCopyTransformsOnly() {
        let commands = ClipboardHelpCatalog.copyCommands(settings: .default)
        let titles = Set(commands.map(\.title))

        XCTAssertEqual(commands.count, 3)
        XCTAssertTrue(titles.contains("Replace clipboard with normalized text"))
        XCTAssertTrue(titles.contains("Replace clipboard with one-line text"))
        XCTAssertTrue(titles.contains("Replace clipboard with space-joined text"))
    }

    func testHelpCatalogLocalizesNormalizeByLanguage() {
        var english = AppSettings.default
        english.settingsLanguage = .english
        var japanese = english
        japanese.settingsLanguage = .japanese

        XCTAssertTrue(ClipboardHelpCatalog.panelCommands(settings: english).contains(where: { $0.title == "Normalize the focused item" }))
        XCTAssertTrue(ClipboardHelpCatalog.panelCommands(settings: japanese).contains(where: { $0.title == "フォーカス中の項目を整形" }))
        XCTAssertTrue(ClipboardHelpCatalog.editorCommands(settings: japanese).contains(where: { $0.title.contains("取り消し") }))
    }
}

final class KeyboardOverrideContractTests: XCTestCase {
    func testUIComponentsDoesNotReintroduceRemovedPreviewCopyAndLocalMonitorOverrides() throws {
        let source = try String(contentsOf: uiComponentsURL(), encoding: .utf8)

        XCTAssertFalse(source.contains("SelectableMarkdownWebView"))
        XCTAssertFalse(source.contains("copyTextHandler"))
        XCTAssertFalse(source.contains("NSEvent.addLocalMonitorForEvents"))
    }

    func testEditorTextViewDoesNotOverrideNativeCommandArrowOrWordNavigation() throws {
        let source = try String(contentsOf: uiComponentsURL(), encoding: .utf8)

        XCTAssertFalse(source.contains("moveToBeginningOfLine(nil)"))
        XCTAssertFalse(source.contains("moveToEndOfLine(nil)"))
        XCTAssertFalse(source.contains("deleteToBeginningOfLine(nil)"))
        XCTAssertFalse(source.contains("moveWordLeft(nil)"))
        XCTAssertFalse(source.contains("moveWordRight(nil)"))
        XCTAssertFalse(source.contains("deleteWordBackward(nil)"))
    }

    private func uiComponentsURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/UIComponents.swift")
    }
}

final class AppSettingsStoreTests: XCTestCase {
    func testSettingsStoreLoadsDefaultGlobalShortcuts() {
        let suiteName = "AppSettingsStoreTests.Defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = UserDefaultsAppSettingsStore(userDefaults: defaults)

        let loaded = store.load()

        XCTAssertEqual(loaded.globalNewNoteShortcut, AppSettings.defaultGlobalNewNoteShortcut)
        XCTAssertEqual(loaded.globalCopyJoinedShortcut, AppSettings.defaultGlobalCopyJoinedShortcut)
        XCTAssertEqual(loaded.globalCopyNormalizedShortcut, AppSettings.defaultGlobalCopyNormalizedShortcut)
        XCTAssertEqual(loaded.globalCopyJoinedWithSpacesShortcut, AppSettings.defaultGlobalCopyJoinedWithSpacesShortcut)
        XCTAssertEqual(loaded.orphanCodexDiscardShortcut, AppSettings.defaultOrphanCodexDiscardShortcut)
        XCTAssertTrue(loaded.globalCopyJoinedEnabled)
        XCTAssertTrue(loaded.globalCopyNormalizedEnabled)
        XCTAssertTrue(loaded.globalCopyJoinedWithSpacesEnabled)
        XCTAssertEqual(loaded.joinLineBreakStrategy, .removeBreaks)
        XCTAssertTrue(loaded.localFileHistoryEnabled)
        XCTAssertTrue(loaded.localFileHistoryTrackOpenedFiles)
        XCTAssertEqual(loaded.localFileHistoryWatchedExtensions, "txt,md,markdown")
        XCTAssertTrue(loaded.localFileHistoryWatchRecursively)
        XCTAssertEqual(loaded.localFileHistoryMaxSnapshotsPerFile, 30)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testSettingsStorePersistsNormalizeShortcut() {
        let suiteName = "AppSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = UserDefaultsAppSettingsStore(userDefaults: defaults)

        var settings = AppSettings.default
        settings.normalizeForCommandShortcut = HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_J),
            modifiers: UInt32(cmdKey | optionKey)
        )
        settings.copyJoinedShortcut = HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(cmdKey | optionKey)
        )
        settings.copyNormalizedShortcut = HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        settings.copyJoinedWithSpacesShortcut = HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(optionKey | shiftKey)
        )
        settings.globalNewNoteShortcut = HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_N),
            modifiers: UInt32(controlKey | shiftKey)
        )
        settings.globalCopyJoinedShortcut = HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(controlKey | optionKey | shiftKey)
        )
        settings.globalCopyNormalizedShortcut = HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(controlKey | shiftKey)
        )
        settings.globalCopyJoinedWithSpacesShortcut = HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(optionKey | shiftKey)
        )
        settings.globalCopyJoinedEnabled = false
        settings.globalCopyNormalizedEnabled = false
        settings.globalCopyJoinedWithSpacesEnabled = false
        settings.orphanCodexDiscardShortcut = HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_Backslash),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        settings.joinLineBreakStrategy = .replaceWithSpace
        settings.localFileHistoryEnabled = true
        settings.localFileHistoryTrackOpenedFiles = false
        settings.localFileHistoryWatchedDirectoryPath = "/tmp/watched"
        settings.localFileHistoryWatchedExtensions = "txt,md,log"
        settings.localFileHistoryWatchRecursively = false
        settings.localFileHistoryMaxSnapshotsPerFile = 55

        store.save(settings)
        let loaded = store.load()

        XCTAssertEqual(loaded.normalizeForCommandShortcut, settings.normalizeForCommandShortcut)
        XCTAssertEqual(loaded.copyJoinedShortcut, settings.copyJoinedShortcut)
        XCTAssertEqual(loaded.copyNormalizedShortcut, settings.copyNormalizedShortcut)
        XCTAssertEqual(loaded.copyJoinedWithSpacesShortcut, settings.copyJoinedWithSpacesShortcut)
        XCTAssertEqual(loaded.globalNewNoteShortcut, settings.globalNewNoteShortcut)
        XCTAssertEqual(loaded.globalCopyJoinedShortcut, settings.globalCopyJoinedShortcut)
        XCTAssertEqual(loaded.globalCopyNormalizedShortcut, settings.globalCopyNormalizedShortcut)
        XCTAssertEqual(loaded.globalCopyJoinedWithSpacesShortcut, settings.globalCopyJoinedWithSpacesShortcut)
        XCTAssertEqual(loaded.orphanCodexDiscardShortcut, settings.orphanCodexDiscardShortcut)
        XCTAssertEqual(loaded.joinLineBreakStrategy, .replaceWithSpace)
        XCTAssertFalse(loaded.globalCopyJoinedEnabled)
        XCTAssertFalse(loaded.globalCopyNormalizedEnabled)
        XCTAssertFalse(loaded.globalCopyJoinedWithSpacesEnabled)
        XCTAssertTrue(loaded.localFileHistoryEnabled)
        XCTAssertFalse(loaded.localFileHistoryTrackOpenedFiles)
        XCTAssertEqual(loaded.localFileHistoryWatchedDirectoryPath, "/tmp/watched")
        XCTAssertEqual(loaded.localFileHistoryWatchedExtensions, "txt,md,log")
        XCTAssertFalse(loaded.localFileHistoryWatchRecursively)
        XCTAssertEqual(loaded.localFileHistoryMaxSnapshotsPerFile, 55)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testSettingsStoreMigratesMissingOptionalGlobalsToDefaults() {
        let suiteName = "AppSettingsStoreTests.Migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(4, forKey: "app.settings.migrationVersion")
        let store = UserDefaultsAppSettingsStore(userDefaults: defaults)

        let loaded = store.load()

        XCTAssertEqual(loaded.globalNewNoteShortcut, AppSettings.defaultGlobalNewNoteShortcut)
        XCTAssertEqual(loaded.globalCopyJoinedShortcut, AppSettings.defaultGlobalCopyJoinedShortcut)
        XCTAssertEqual(loaded.globalCopyNormalizedShortcut, AppSettings.defaultGlobalCopyNormalizedShortcut)
        XCTAssertEqual(loaded.globalCopyJoinedWithSpacesShortcut, AppSettings.defaultGlobalCopyJoinedWithSpacesShortcut)
        XCTAssertEqual(loaded.orphanCodexDiscardShortcut, AppSettings.defaultOrphanCodexDiscardShortcut)
        XCTAssertTrue(loaded.globalCopyJoinedEnabled)
        XCTAssertTrue(loaded.globalCopyNormalizedEnabled)
        XCTAssertTrue(loaded.globalCopyJoinedWithSpacesEnabled)
        XCTAssertEqual(defaults.integer(forKey: "app.settings.migrationVersion"), 11)

        defaults.removePersistentDomain(forName: suiteName)
    }
}
