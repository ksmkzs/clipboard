import AppKit
import Carbon
import CryptoKit
import ServiceManagement
import SwiftData
import SwiftUI
import WebKit

enum SettingsMutationError: Error {
    case invalidShortcutFormat
    case duplicateShortcut
    case unavailableShortcut(String)
    case launchAtLoginUnavailable(String)
}

enum HotKeyRegistrationState: Equatable {
    case notRegistered
    case registered
    case failed(OSStatus)

    var isRegistered: Bool {
        if case .registered = self {
            return true
        }
        return false
    }
}

enum EditorSaveDestination: Equatable {
    case clipboard
    case file
}

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, NSWindowDelegate {
    typealias CodexIntegrationStatus = ClipboardCodexIntegrationStatus

    final class EditorSaveStatusState: ObservableObject {
        @Published var lastSaveDestination: EditorSaveDestination?
        @Published var saveRevision: Int = 0
        @Published var lastPersistedText: String = ""
    }

    private enum UnsavedEditorCloseDecision {
        case saveAndClose
        case discardAndClose
        case cancel
    }

    enum FileBackedDocumentKind: Equatable {
        case markdown
        case text

        var supportsMarkdownPreview: Bool {
            self == .markdown
        }
    }

    enum ExternalEditorMode: Equatable {
        case codex
        case fileBacked(FileBackedDocumentKind)

        var isCodex: Bool {
            if case .codex = self { return true }
            return false
        }

        var fileKind: FileBackedDocumentKind? {
            if case let .fileBacked(kind) = self { return kind }
            return nil
        }
    }

    enum StandaloneDiscardAction: Equatable {
        case restoreOriginal
        case deletePlaceholder
    }

    enum PanelToggleAction: Equatable {
        case showOrRaise
        case close
    }

    struct CodexDraftContext: Equatable {
        let sessionID: String
        let projectRootURL: URL?

        var shortSessionID: String {
            String(sessionID.prefix(8)).uppercased()
        }

        var projectDisplayName: String {
            projectRootURL?.lastPathComponent ?? "Unknown"
        }

        var projectDisplayPath: String {
            guard let path = projectRootURL?.path else {
                return "~"
            }
            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            if path == homePath {
                return "~"
            }
            if path.hasPrefix(homePath + "/") {
                return "~" + path.dropFirst(homePath.count)
            }
            return path
        }
    }

    struct CodexOpenRequest: Equatable {
        let sessionID: String
        let fileURL: URL
        let projectRootURL: URL?
        let sessionStateURL: URL?
    }

    private enum LaunchArgument {
        static let openPanelOnLaunch = "--codex-open-panel-on-launch"
        static let openHelpOnLaunch = "--codex-open-help-on-launch"
        static let validationHooks = "--validation-hooks"
    }

    private enum ValidationCommandAction: String {
        case openPanel
        case togglePanelFromStatusItem
        case captureSnapshot
        case captureWindowImage
        case openFile
        case openNewNote
        case openSettings
        case openHelp
        case movePanelSelectionDown
        case movePanelSelectionUp
        case movePanelSelectionLeft
        case movePanelSelectionRight
        case commitPanelSelection
        case togglePanelPinnedArea
        case togglePinSelectedPanelItem
        case togglePinFocusedPanelItem
        case deleteSelectedPanelItem
        case deleteFocusedPanelItem
        case openSelectedPanelEditor
        case openFocusedPanelEditor
        case copySelectedPanelItem
        case pasteSelectedPanelItem
        case joinSelectedPanelItem
        case normalizeSelectedPanelItem
        case setPanelEditorText
        case commitPanelEditor
        case cancelPanelEditor
        case toggleCurrentEditorMarkdownPreview
        case setCurrentEditorText
        case setCurrentEditorSelection
        case setCurrentPreviewWidth
        case setCurrentPreviewScroll
        case syncCurrentPreviewScroll
        case selectCurrentPreviewText
        case selectCurrentPreviewCodeBlock
        case copyCurrentPreviewSelection
        case measureCurrentPreviewHorizontalOverflow
        case clickCurrentPreviewFirstLink
        case respondToPreviewLinkPrompt
        case saveCurrentEditor
        case saveCurrentEditorAs
        case saveCurrentEditorToFile
        case closeCurrentEditor
        case commitCurrentEditor
        case respondToAttachedSheet
        case increaseZoom
        case decreaseZoom
        case resetZoom
        case setSettingsLanguage
        case setThemePreset
        case setPanelShortcut
        case setToggleMarkdownPreviewShortcut
        case setGlobalCopyJoinedEnabled
        case setGlobalCopyNormalizedEnabled
        case runGlobalCopyJoined
        case runGlobalCopyNormalized
        case inspectCodexIntegration
        case resetValidationState
        case syncClipboardCapture
        case seedHistoryText
    }

    private enum ValidationAttachedSheetContext: String {
        case closeUnsavedEditor
        case closeUnsavedManualNote
        case fileSaveDestination
        case manualNoteSaveDestination
        case externalFileChange
    }

    private struct ValidationSnapshot: Codable {
        let statusItemPresent: Bool
        let panelVisible: Bool
        let panelFrontmost: Bool
        let panelPinnedAreaVisible: Bool
        let panelSelectionScope: String
        let highlightedPanelItemID: String?
        let highlightedPanelItemText: String?
        let focusedPanelItemID: String?
        let focusedPanelItemText: String?
        let panelInlineEditorItemID: String?
        let panelInlineEditorDirty: Bool
        let panelInlineEditorPreviewVisible: Bool
        let historyCount: Int
        let pinnedCount: Int
        let latestHistoryItemID: String?
        let latestHistoryItemText: String?
        let clipboardText: String?
        let selectedMatchesLatest: Bool
        let focusedMatchesLatest: Bool
        let fileEditorVisible: Bool
        let noteEditorVisible: Bool
        let noteEditorDraftText: String
        let noteEditorDirty: Bool
        let noteEditorSaveDestination: String?
        let noteEditorRepresentedPath: String?
        let noteEditorAttachedSheetVisible: Bool
        let noteEditorWindowTitle: String?
        let noteEditorPreviewVisible: Bool
        let noteEditorPreviewWidth: Double?
        let standaloneNoteVisible: Bool
        let standaloneNoteDraftText: String
        let standaloneNoteDirty: Bool
        let standaloneNoteSaveDestination: String?
        let standaloneNoteAttachedSheetVisible: Bool
        let standaloneNoteWindowTitle: String?
        let standaloneNotePreviewVisible: Bool
        let standaloneNotePreviewWidth: Double?
        let settingsVisible: Bool
        let helpVisible: Bool
        let interfaceZoomScale: Double
        let settingsLanguage: String
        let interfaceThemePreset: String
        let panelShortcutDisplay: String
        let toggleMarkdownPreviewShortcutDisplay: String
        let globalCopyJoinedEnabled: Bool
        let globalCopyNormalizedEnabled: Bool
        let selectedFillDiffersFromCardFill: Bool
        let previewSelectedText: String?
        let previewScrollFraction: Double?
        let previewHasHorizontalOverflow: Bool?
        let previewLinkPromptVisible: Bool
        let previewLinkPromptURL: String?
        let previewLastOpenedURL: String?
        let validationAttachedSheetContext: String?
        let codexIntegrationInspectable: Bool
    }

    private enum Layout {
        static let panelWidth: CGFloat = 320
        static let panelHeight: CGFloat = 420
        static let screenMargin: CGFloat = 20
        static let anchorGap: CGFloat = 8
        static let panelTopAnchorOffset: CGFloat = 28
    }

    private enum WindowDefaultsKey {
        static let width = "panel.frame.width"
        static let height = "panel.frame.height"
    }
    private let showsAnchorDebugMarkers = false
    
    private enum MenuTag: Int {
        case togglePanel = 100
        case openSettings = 101
        case newNote = 102
        case openFile = 103
        case quit = 199
    }
    
    var panel: ClipboardPanel!
    var dataManager: ClipboardDataManager!
    var clipboardController: ClipboardController!
    var sharedContainer: ModelContainer!
    
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private var previouslyActiveApp: NSRunningApplication?
    private var placementTargetApp: NSRunningApplication?
    private var highlightedPanelItem: ClipboardItem?
    private var focusedPanelItem: ClipboardItem?
    private var panelInlineEditingItemID: UUID?
    private var panelInlineEditorDirty = false
    private var panelInlineEditorPreviewVisible = false
    private var settingsWindowController: NSWindowController?
    private var settingsWindowCloseObserver: NSObjectProtocol?
    private var standaloneNoteWindowController: NSWindowController?
    private var standaloneNoteItemID: UUID?
    private var standaloneNoteDraftText = ""
    private var standaloneNoteLastPersistedText = ""
    private var standaloneNoteIsPlaceholderManualNote = false
    private var standaloneNoteAutosaveWorkItem: DispatchWorkItem?
    private var standaloneNoteMarkdownPreviewVisible = false
    private var noteEditorWindowController: NSWindowController?
    private var noteEditorItemID: UUID?
    private var noteEditorExternalFileURL: URL?
    private var noteEditorExternalMode: ExternalEditorMode?
    private var noteEditorCompletionMarkerURL: URL?
    private var noteEditorSessionStateURL: URL?
    private var noteEditorDraftText = ""
    private var noteEditorLastPersistedText = ""
    private var noteEditorIsPlaceholderManualNote = false
    private var noteEditorObservedFileModificationDate: Date?
    private var noteEditorObservedFileContentSnapshot = ""
    private var noteEditorExternalFileMonitor: DispatchSourceTimer?
    private var noteEditorExternalChangePromptActive = false
    private var noteEditorAutosaveWorkItem: DispatchWorkItem?
    private var noteEditorMarkdownPreviewVisible = false
    private var noteEditorHistoryPaneVisible = false
    private var noteEditorShouldCommitExternalDraft = false
    private var noteEditorIsOrphanedCodexDraft = false
    private var noteEditorCodexSessionID: String?
    private var noteEditorCodexProjectRootURL: URL?
    private var lastClosedNoteEditorItemID: UUID?
    private var helpPanel: NSPanel?
    private var floatingFeedbackPanel: NSPanel?
    private var floatingFeedbackRootView: NSView?
    private var floatingFeedbackLabel: NSTextField?
    private var floatingFeedbackBackgroundView: NSView?
    private var floatingFeedbackDismissTask: DispatchWorkItem?
    private var helpRequestObserver: NSObjectProtocol?
    private var validationCommandObserver: NSObjectProtocol?
    private var validationAttachedSheetContext: ValidationAttachedSheetContext?
    private var codexOpenRequestTimer: DispatchSourceTimer?
    private var codexSessionStateMonitor: DispatchSourceTimer?
    private var suppressPanelAutoClose = false
    private var panelAutoCloseSuppressionTask: DispatchWorkItem?
    private var panelPinnedAreaVisible = false
    private weak var panelReturnWindow: NSWindow?
    private var launchAutomationAutoCloseSuppressionTask: DispatchWorkItem?
    private var anchorDebugWindows: [String: NSWindow] = [:]
    private var anchorDebugHideTask: DispatchWorkItem?
    private var lastAnchorPoint: NSPoint?
    private var pendingAnchorDebugCandidates: [AnchorDebugCandidate] = []
    private let storePaths = ClipboardStorePaths.default()
    private let settingsStore: AppSettingsStore = UserDefaultsAppSettingsStore()
    private let standaloneNoteSaveStatus = EditorSaveStatusState()
    private let externalEditorSaveStatus = EditorSaveStatusState()
    private var fileLocalHistoryManager: FileLocalHistoryManager?
    @Published private(set) var settings = AppSettings.default
    @Published private(set) var panelHotKeyState: HotKeyRegistrationState = .notRegistered
    @Published private(set) var translationHotKeyState: HotKeyRegistrationState = .notRegistered
    
    private var panelHotKeyShortcut = AppSettings.default.panelShortcut
    private var translateHotKeyShortcut = AppSettings.default.translationShortcut
    private var panelHotKeyRegistrationID: UInt32?
    private var translateHotKeyRegistrationID: UInt32?
    private var globalNewNoteHotKeyRegistrationID: UInt32?
    private var globalCopyJoinedHotKeyRegistrationID: UInt32?
    private var globalCopyNormalizedHotKeyRegistrationID: UInt32?
    private var hasPresentedPanelThisLaunch = false
    private var isRunningValidationHooks: Bool {
        ProcessInfo.processInfo.arguments.contains(LaunchArgument.validationHooks)
    }

    private var hasAnyClipboardWindowVisible: Bool {
        panel?.isVisible == true
            || standaloneNoteWindowController?.window?.isVisible == true
            || noteEditorWindowController?.window?.isVisible == true
            || settingsWindowController?.window?.isVisible == true
            || helpPanel?.isVisible == true
    }

    private struct PanelPresentationContext {
        let finalFrame: NSRect
        let anchorPoint: NSPoint?
        let anchorDescription: String?
        let targetArrowSymbol: String
        let anchorDebugCandidates: [AnchorDebugCandidate]
    }

    private struct AnchorDebugCandidate {
        let id: String
        let point: NSPoint
        let label: String
        let color: NSColor
        let isDraggable: Bool
    }

    struct TargetAppDecision: Equatable {
        let frontmostPID: pid_t?
        let placementPID: pid_t?
        let previousPID: pid_t?
        let currentPID: pid_t
        let frontmostTerminated: Bool
        let placementTerminated: Bool
        let previousTerminated: Bool
    }

    struct HelpPanelPlacement: Equatable {
        enum Side: Equatable {
            case right
            case left
            case centered
        }

        let frame: NSRect
        let side: Side
    }

    static func preferredTargetPID(for decision: TargetAppDecision) -> pid_t? {
        if let frontmostPID = decision.frontmostPID,
           frontmostPID != decision.currentPID,
           !decision.frontmostTerminated {
            return frontmostPID
        }

        if let placementPID = decision.placementPID,
           placementPID != decision.currentPID,
           !decision.placementTerminated {
            return placementPID
        }

        if let previousPID = decision.previousPID,
           previousPID != decision.currentPID,
           !decision.previousTerminated {
            return previousPID
        }

        return nil
    }

    static var isRunningAutomatedTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
    }

    static func shouldStartLocalHistoryServices(isRunningAutomatedTests: Bool) -> Bool {
        !isRunningAutomatedTests
    }

    static func supportsStandaloneEditorLocalHistory(
        externalMode: ExternalEditorMode?,
        hasFileURL: Bool,
        isOrphanedCodexDraft: Bool
    ) -> Bool {
        guard hasFileURL else {
            return false
        }

        switch externalMode {
        case .fileBacked:
            return true
        case .codex:
            return !isOrphanedCodexDraft
        case nil:
            return false
        }
    }

    static func shouldBootstrapCurrentEditorOpenedFileTracking(
        isEnabled: Bool,
        trackOpenedFiles: Bool,
        externalMode: ExternalEditorMode?,
        hasFileURL: Bool,
        isOrphanedCodexDraft: Bool
    ) -> Bool {
        guard isEnabled, trackOpenedFiles else {
            return false
        }

        return supportsStandaloneEditorLocalHistory(
            externalMode: externalMode,
            hasFileURL: hasFileURL,
            isOrphanedCodexDraft: isOrphanedCodexDraft
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @discardableResult
    private func handleTextDocumentOpenURLs(_ urls: [URL]) -> Bool {
        var didOpenAny = false
        for fileURL in urls.map(\.standardizedFileURL) {
            if openTextDocumentFromSystem(for: fileURL) {
                didOpenAny = true
            }
        }
        return didOpenAny
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        handleTextDocumentOpenURLs([URL(fileURLWithPath: filename)])
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if handleTextDocumentOpenURLs(filenames.map { URL(fileURLWithPath: $0) }) {
            sender.reply(toOpenOrPrint: .success)
        } else {
            sender.reply(toOpenOrPrint: .failure)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        _ = handleTextDocumentOpenURLs(urls)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = settingsStore.load()
        panelHotKeyShortcut = settings.panelShortcut
        translateHotKeyShortcut = settings.translationShortcut

        sharedContainer = getModelContainer()
        dataManager = ClipboardDataManager(
            modelContext: ModelContext(sharedContainer),
            maxHistoryItems: settings.historyLimit,
            storePaths: storePaths
        )
        clipboardController = ClipboardController(dataManager: dataManager)
        clipboardController.onExternalCapture = nil
        clipboardController.shouldHandleKeyboardCopyEvent = { [weak self] in
            self != nil
        }

        setupPanel()
        observeHelpRequests()

        guard Self.shouldStartLocalHistoryServices(isRunningAutomatedTests: Self.isRunningAutomatedTests) else {
            return
        }

        fileLocalHistoryManager = FileLocalHistoryManager(storePaths: storePaths)
        applyLocalFileHistorySettings()
        requestAccessibilityPermissions()
        syncLaunchAtLoginState()
        setupStatusItem()
        setupValidationCommandObserverIfRequested()
        registerHotKeys()
        clipboardController.startMonitoring()
        startCodexOpenRequestMonitor()
        performLaunchAutomationIfRequested()

        let launchFileURLs = ProcessInfo.processInfo.arguments
            .dropFirst()
            .filter { !$0.hasPrefix("-") }
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if !launchFileURLs.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self else { return }
                _ = self.handleTextDocumentOpenURLs(launchFileURLs)
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard settingsWindowController?.window?.isVisible != true else { return }
        registerHotKeys()
    }

    private func startCodexOpenRequestMonitor() {
        codexOpenRequestTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 0.2, repeating: 0.25)
        timer.setEventHandler { [weak self] in
            self?.consumeCodexOpenRequestIfNeeded()
        }
        codexOpenRequestTimer = timer
        timer.resume()
    }

    private func setupValidationCommandObserverIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains(LaunchArgument.validationHooks) else {
            return
        }

        let center = DistributedNotificationCenter.default()
        validationCommandObserver = center.addObserver(
            forName: Notification.Name("ClipboardHistoryValidationCommand"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            DispatchQueue.main.async {
                self?.handleValidationCommand(notification)
            }
        }
    }

    private func handleValidationCommand(_ notification: Notification) {
        guard
            let actionRaw = notification.userInfo?["action"] as? String,
            let action = ValidationCommandAction(rawValue: actionRaw)
        else {
            return
        }

        switch action {
        case .openPanel:
            showPanel()
            reassertForegroundForValidationIfNeeded()
        case .togglePanelFromStatusItem:
            togglePanelFromStatusItem()
            reassertForegroundForValidationIfNeeded()
        case .captureSnapshot:
            guard let path = notification.userInfo?["path"] as? String else { return }
            writeValidationSnapshot(to: URL(fileURLWithPath: path))
        case .captureWindowImage:
            guard let path = notification.userInfo?["path"] as? String,
                  let windowKind = notification.userInfo?["window"] as? String else { return }
            captureValidationWindowImage(kind: windowKind, to: URL(fileURLWithPath: path))
        case .openFile:
            guard let path = notification.userInfo?["path"] as? String else { return }
            _ = handleTextDocumentOpenURLs([URL(fileURLWithPath: path)])
            reassertForegroundForValidationIfNeeded()
        case .openNewNote:
            createNewNoteFromAnyState()
            reassertForegroundForValidationIfNeeded()
        case .openSettings:
            openSettingsWindow()
            reassertForegroundForValidationIfNeeded()
        case .openHelp:
            toggleHelpPanel(isEditingSelectedText: false)
            reassertForegroundForValidationIfNeeded()
        case .movePanelSelectionDown:
            postPanelValidationAction("moveDown")
        case .movePanelSelectionUp:
            postPanelValidationAction("moveUp")
        case .movePanelSelectionLeft:
            postPanelValidationAction("moveLeft")
        case .movePanelSelectionRight:
            postPanelValidationAction("moveRight")
        case .commitPanelSelection:
            postPanelValidationAction("commitSelection")
        case .togglePanelPinnedArea:
            postPanelValidationAction("togglePinnedArea")
        case .togglePinSelectedPanelItem:
            postPanelValidationAction("togglePin")
        case .togglePinFocusedPanelItem:
            postPanelValidationAction("togglePinFocused")
        case .deleteSelectedPanelItem:
            postPanelValidationAction("deleteSelected")
        case .deleteFocusedPanelItem:
            postPanelValidationAction("deleteFocused")
        case .openSelectedPanelEditor:
            postPanelValidationAction("toggleEditor")
        case .openFocusedPanelEditor:
            postPanelValidationAction("openFocusedEditor")
        case .copySelectedPanelItem:
            postPanelValidationAction("copySelected")
        case .pasteSelectedPanelItem:
            postPanelValidationAction("pasteSelected")
        case .joinSelectedPanelItem:
            postPanelValidationAction("joinSelected")
        case .normalizeSelectedPanelItem:
            postPanelValidationAction("normalizeSelected")
        case .setPanelEditorText:
            guard let path = notification.userInfo?["path"] as? String else { return }
            let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            postPanelValidationAction("setEditorText", text: text)
        case .commitPanelEditor:
            postPanelValidationAction("commitEditor")
        case .cancelPanelEditor:
            postPanelValidationAction("cancelEditor")
        case .toggleCurrentEditorMarkdownPreview:
            postEditorCommand(.toggleMarkdownPreview)
        case .setCurrentEditorText:
            guard let path = notification.userInfo?["path"] as? String else { return }
            let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            postEditorCommand(.setText, text: text)
        case .setCurrentEditorSelection:
            guard let rawValue = notification.userInfo?["path"] as? String else { return }
            postEditorCommand(.setSelectionLocation, text: rawValue)
        case .setCurrentPreviewWidth:
            guard let rawValue = notification.userInfo?["path"] as? String,
                  let width = Double(rawValue) else { return }
            NotificationCenter.default.post(
                name: .editorViewValidationRequested,
                object: nil,
                userInfo: ["action": "setPreviewWidth", "value": width]
            )
        case .setCurrentPreviewScroll:
            guard let rawValue = notification.userInfo?["path"] as? String,
                  let progress = Double(rawValue) else { return }
            validationSetCurrentPreviewScroll(progress)
        case .syncCurrentPreviewScroll:
            validationSyncCurrentPreviewScroll()
        case .selectCurrentPreviewText:
            guard let rawValue = notification.userInfo?["path"] as? String else { return }
            validationSelectCurrentPreviewText(containing: rawValue, preferCodeBlock: false)
        case .selectCurrentPreviewCodeBlock:
            guard let rawValue = notification.userInfo?["path"] as? String else { return }
            validationSelectCurrentPreviewText(containing: rawValue, preferCodeBlock: true)
        case .copyCurrentPreviewSelection:
            validationCopyCurrentPreviewSelection()
        case .measureCurrentPreviewHorizontalOverflow:
            validationMeasureCurrentPreviewHorizontalOverflow()
        case .clickCurrentPreviewFirstLink:
            validationClickCurrentPreviewFirstLink()
        case .respondToPreviewLinkPrompt:
            guard let rawValue = notification.userInfo?["path"] as? String else { return }
            validationRespondToPreviewLinkPrompt(rawValue)
        case .saveCurrentEditor:
            if standaloneNoteWindowController?.window?.isVisible == true {
                _ = saveStandaloneManualNoteEditor()
            } else if noteEditorWindowController?.window?.isVisible == true {
                _ = saveStandaloneEditor()
            }
        case .saveCurrentEditorAs:
            if standaloneNoteWindowController?.window?.isVisible == true {
                _ = saveStandaloneManualNoteEditorAs()
            } else if noteEditorWindowController?.window?.isVisible == true {
                _ = saveStandaloneEditorAs()
            }
        case .saveCurrentEditorToFile:
            guard let path = notification.userInfo?["path"] as? String else { return }
            _ = validationSaveCurrentEditorToFile(URL(fileURLWithPath: path))
        case .closeCurrentEditor:
            if standaloneNoteWindowController?.window?.isVisible == true {
                closeStandaloneManualNoteEditor()
            } else if noteEditorWindowController?.window?.isVisible == true {
                closeStandaloneNoteEditor()
            }
        case .commitCurrentEditor:
            postEditorCommand(.commit)
        case .respondToAttachedSheet:
            guard let rawChoice = notification.userInfo?["path"] as? String else { return }
            respondToValidationAttachedSheet(choice: rawChoice)
        case .increaseZoom:
            increaseInterfaceZoom()
        case .decreaseZoom:
            decreaseInterfaceZoom()
        case .resetZoom:
            resetInterfaceZoom()
        case .setSettingsLanguage:
            guard let rawValue = notification.userInfo?["path"] as? String,
                  let language = SettingsLanguage(rawValue: rawValue) else { return }
            updateSettingsLanguage(language)
        case .setThemePreset:
            guard let rawValue = notification.userInfo?["path"] as? String,
                  let theme = InterfaceThemePreset(rawValue: rawValue) else { return }
            updateInterfaceThemePreset(theme)
        case .setPanelShortcut:
            guard let rawValue = notification.userInfo?["path"] as? String else { return }
            validationSetPanelShortcut(rawValue)
        case .setToggleMarkdownPreviewShortcut:
            guard let rawValue = notification.userInfo?["path"] as? String else { return }
            validationSetToggleMarkdownPreviewShortcut(rawValue)
        case .setGlobalCopyJoinedEnabled:
            validationSetGlobalSpecialCopyEnabled(
                joined: (notification.userInfo?["path"] as? String).flatMap(Bool.init) ?? false
            )
        case .setGlobalCopyNormalizedEnabled:
            validationSetGlobalSpecialCopyEnabled(
                normalized: (notification.userInfo?["path"] as? String).flatMap(Bool.init) ?? false
            )
        case .runGlobalCopyJoined:
            copySelectedTextFromCurrentContext(
                feedbackMessage: "One Line",
                transform: joinLinesText
            )
        case .runGlobalCopyNormalized:
            copySelectedTextFromCurrentContext(
                feedbackMessage: "Normalized",
                transform: normalizeCommandText
            )
        case .inspectCodexIntegration:
            _ = codexIntegrationStatus(inspectShellConfig: true)
        case .resetValidationState:
            resetValidationState()
        case .syncClipboardCapture:
            clipboardController.syncNow()
        case .seedHistoryText:
            guard let rawValue = notification.userInfo?["path"] as? String else { return }
            validationSeedHistoryText(rawValue)
        }
    }

    private func validationSeedHistoryText(_ text: String) {
        guard !text.isEmpty else { return }
        let capture = ClipboardDataManager.ClipboardCapture(
            payload: .text(text),
            dedupeKey: ClipboardDedupeKey.text(text)
        )
        dataManager.storeCapture(capture)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        clipboardController.resetCaptureState()
    }

    private func resetValidationState() {
        noteEditorAutosaveWorkItem?.cancel()
        standaloneNoteAutosaveWorkItem?.cancel()
        noteEditorExternalFileMonitor?.cancel()
        noteEditorExternalFileMonitor = nil
        stopCodexSessionStateMonitor()

        if let window = noteEditorWindowController?.window {
            window.delegate = nil
            window.contentViewController = NSViewController()
            window.orderOut(nil)
        }
        noteEditorWindowController = nil

        if let window = standaloneNoteWindowController?.window {
            window.delegate = nil
            window.contentViewController = NSViewController()
            window.orderOut(nil)
        }
        standaloneNoteWindowController = nil

        let allItems = dataManager.allItems()
        for item in allItems {
            try? FileManager.default.removeItem(at: dataManager.workingNoteFileURL(for: item.id))
            _ = dataManager.deleteItem(id: item.id)
        }

        highlightedPanelItem = nil
        focusedPanelItem = nil
        panelPinnedAreaVisible = false
        panelInlineEditingItemID = nil
        panelInlineEditorDirty = false
        panelInlineEditorPreviewVisible = false

        noteEditorItemID = nil
        noteEditorDraftText = ""
        noteEditorLastPersistedText = ""
        noteEditorExternalFileURL = nil
        noteEditorExternalMode = nil
        noteEditorCompletionMarkerURL = nil
        noteEditorSessionStateURL = nil
        noteEditorObservedFileModificationDate = nil
        noteEditorObservedFileContentSnapshot = ""
        noteEditorExternalChangePromptActive = false
        noteEditorAutosaveWorkItem = nil
        noteEditorMarkdownPreviewVisible = false
        noteEditorHistoryPaneVisible = false
        noteEditorShouldCommitExternalDraft = false
        noteEditorIsOrphanedCodexDraft = false
        noteEditorCodexSessionID = nil
        noteEditorCodexProjectRootURL = nil
        noteEditorIsPlaceholderManualNote = false
        externalEditorSaveStatus.lastSaveDestination = nil
        externalEditorSaveStatus.lastPersistedText = ""
        externalEditorSaveStatus.saveRevision = 0

        standaloneNoteItemID = nil
        standaloneNoteDraftText = ""
        standaloneNoteLastPersistedText = ""
        standaloneNoteIsPlaceholderManualNote = false
        standaloneNoteAutosaveWorkItem = nil
        standaloneNoteMarkdownPreviewVisible = false
        standaloneNoteSaveStatus.lastSaveDestination = nil
        standaloneNoteSaveStatus.lastPersistedText = ""
        standaloneNoteSaveStatus.saveRevision = 0
        lastClosedNoteEditorItemID = nil

        if panel?.isVisible == true {
            panel.orderOut(nil)
        }

        if settings.settingsLanguage != .english {
            updateSettingsLanguage(.english)
        }
        if settings.interfaceThemePreset != .graphite {
            updateInterfaceThemePreset(.graphite)
        }
        if abs(settings.interfaceZoomScale - AppSettings.defaultInterfaceZoomScale) > 0.001 {
            resetInterfaceZoom()
        }
        if settings.panelShortcut != AppSettings.default.panelShortcut
            || settings.toggleMarkdownPreviewShortcut != AppSettings.default.toggleMarkdownPreviewShortcut
            || settings.globalCopyJoinedShortcut != AppSettings.default.globalCopyJoinedShortcut
            || settings.globalCopyNormalizedShortcut != AppSettings.default.globalCopyNormalizedShortcut
            || settings.globalCopyJoinedEnabled != AppSettings.default.globalCopyJoinedEnabled
            || settings.globalCopyNormalizedEnabled != AppSettings.default.globalCopyNormalizedEnabled {
            mutateSettings { settings in
                settings.panelShortcut = AppSettings.default.panelShortcut
                settings.toggleMarkdownPreviewShortcut = AppSettings.default.toggleMarkdownPreviewShortcut
                settings.globalCopyJoinedEnabled = AppSettings.default.globalCopyJoinedEnabled
                settings.globalCopyNormalizedEnabled = AppSettings.default.globalCopyNormalizedEnabled
                settings.globalCopyJoinedShortcut = AppSettings.default.globalCopyJoinedShortcut
                settings.globalCopyNormalizedShortcut = AppSettings.default.globalCopyNormalizedShortcut
            }
            saveSettings()
            panelHotKeyShortcut = settings.panelShortcut
            registerHotKeys()
        }

        validationAttachedSheetContext = nil
        MarkdownPreviewValidationState.shared.reset()
        PanelValidationState.shared.reset()
        dataManager.resetValidationStore()
        NSPasteboard.general.clearContents()
        clipboardController.resetCaptureState()
    }

    private func postPanelValidationAction(_ action: String, text: String? = nil) {
        var userInfo: [String: Any] = ["action": action]
        if let text {
            userInfo["text"] = text
        }
        NotificationCenter.default.post(
            name: .clipboardPanelValidationRequested,
            object: nil,
            userInfo: userInfo
        )
    }

    private func writeValidationSnapshot(to url: URL) {
        let latestHistoryItem = dataManager.historyItems().first
        let latestHistoryText = latestHistoryItem.flatMap { dataManager.resolvedText(for: $0) }
        let highlightedText = highlightedPanelItem.flatMap { dataManager.resolvedText(for: $0) }
        let focusedText = focusedPanelItem.flatMap { dataManager.resolvedText(for: $0) }
        let clipboardText = NSPasteboard.general.string(forType: .string)
        let noteEditorWindow = noteEditorWindowController?.window
        let standaloneWindow = standaloneNoteWindowController?.window
        let theme = settings.interfaceTheme
        let pinnedIDs = Set(dataManager.pinnedItems().map(\.id))
        let panelSelectionScope = PanelValidationState.shared.selectionScopeRaw ?? {
            guard let focusedPanelItem else { return "history" }
            return pinnedIDs.contains(focusedPanelItem.id) ? "pinned" : "history"
        }()
        let snapshot = ValidationSnapshot(
            statusItemPresent: statusItem != nil,
            panelVisible: panel.isVisible,
            panelFrontmost: isPanelFrontmost(),
            panelPinnedAreaVisible: panelPinnedAreaVisible,
            panelSelectionScope: panelSelectionScope,
            highlightedPanelItemID: highlightedPanelItem?.id.uuidString,
            highlightedPanelItemText: highlightedText,
            focusedPanelItemID: focusedPanelItem?.id.uuidString,
            focusedPanelItemText: focusedText,
            panelInlineEditorItemID: panelInlineEditingItemID?.uuidString,
            panelInlineEditorDirty: panelInlineEditorDirty,
            panelInlineEditorPreviewVisible: panelInlineEditorPreviewVisible,
            historyCount: dataManager.historyItems().count,
            pinnedCount: dataManager.pinnedItems().count,
            latestHistoryItemID: latestHistoryItem?.id.uuidString,
            latestHistoryItemText: latestHistoryText,
            clipboardText: clipboardText,
            selectedMatchesLatest: highlightedPanelItem?.id == latestHistoryItem?.id,
            focusedMatchesLatest: focusedPanelItem?.id == latestHistoryItem?.id,
            fileEditorVisible: noteEditorWindowController?.window?.isVisible == true && isCurrentEditorFileBacked,
            noteEditorVisible: noteEditorWindowController?.window?.isVisible == true,
            noteEditorDraftText: noteEditorDraftText,
            noteEditorDirty: noteEditorWindowController?.window?.isVisible == true && noteEditorDraftText != externalEditorSaveStatus.lastPersistedText,
            noteEditorSaveDestination: validationSaveDestinationString(externalEditorSaveStatus.lastSaveDestination),
            noteEditorRepresentedPath: noteEditorWindow?.representedURL?.path,
            noteEditorAttachedSheetVisible: noteEditorWindow?.attachedSheet != nil,
            noteEditorWindowTitle: noteEditorWindow?.title,
            noteEditorPreviewVisible: noteEditorMarkdownPreviewVisible,
            noteEditorPreviewWidth: validationCurrentPreviewWebView(in: noteEditorWindow).map { Double($0.frame.width) },
            standaloneNoteVisible: standaloneNoteWindowController?.window?.isVisible == true,
            standaloneNoteDraftText: standaloneNoteDraftText,
            standaloneNoteDirty: standaloneNoteWindowController?.window?.isVisible == true && standaloneNoteDraftText != standaloneNoteSaveStatus.lastPersistedText,
            standaloneNoteSaveDestination: validationSaveDestinationString(standaloneNoteSaveStatus.lastSaveDestination),
            standaloneNoteAttachedSheetVisible: standaloneWindow?.attachedSheet != nil,
            standaloneNoteWindowTitle: standaloneWindow?.title,
            standaloneNotePreviewVisible: standaloneNoteMarkdownPreviewVisible,
            standaloneNotePreviewWidth: validationCurrentPreviewWebView(in: standaloneWindow).map { Double($0.frame.width) },
            settingsVisible: settingsWindowController?.window?.isVisible == true,
            helpVisible: helpPanel?.isVisible == true,
            interfaceZoomScale: settings.clampedInterfaceZoomScale,
            settingsLanguage: settings.settingsLanguage.rawValue,
            interfaceThemePreset: settings.interfaceThemePreset.rawValue,
            panelShortcutDisplay: HotKeyManager.displayString(for: settings.panelShortcut),
            toggleMarkdownPreviewShortcutDisplay: HotKeyManager.displayString(for: settings.toggleMarkdownPreviewShortcut),
            globalCopyJoinedEnabled: settings.globalCopyJoinedEnabled,
            globalCopyNormalizedEnabled: settings.globalCopyNormalizedEnabled,
            selectedFillDiffersFromCardFill: validationResolvedColorDescription(theme.selectedFill) != validationResolvedColorDescription(theme.cardFill),
            previewSelectedText: MarkdownPreviewValidationState.shared.selectedText,
            previewScrollFraction: MarkdownPreviewValidationState.shared.scrollFraction,
            previewHasHorizontalOverflow: MarkdownPreviewValidationState.shared.hasHorizontalOverflow,
            previewLinkPromptVisible: MarkdownPreviewValidationState.shared.promptVisible,
            previewLinkPromptURL: MarkdownPreviewValidationState.shared.promptURL,
            previewLastOpenedURL: MarkdownPreviewValidationState.shared.lastOpenedURL,
            validationAttachedSheetContext: validationAttachedSheetContext?.rawValue,
            codexIntegrationInspectable: codexIntegrationStatus().shellConfigURL != nil
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            fputs("Failed to write validation snapshot: \(error)\n", stderr)
        }
    }

    private func captureValidationWindowImage(kind rawKind: String, to url: URL) {
        let window: NSWindow?
        switch rawKind {
        case "panel":
            window = panel
        case "standaloneNote":
            window = standaloneNoteWindowController?.window
        case "noteEditor":
            window = noteEditorWindowController?.window
        case "settings":
            window = settingsWindowController?.window
        case "help":
            window = helpPanel
        default:
            window = nil
        }

        guard let window, window.isVisible else { return }
        window.displayIfNeeded()

        let targetView = window.contentView?.superview ?? window.contentView
        guard let targetView else { return }

        targetView.layoutSubtreeIfNeeded()
        let bounds = targetView.bounds.integral
        guard bounds.width > 0, bounds.height > 0,
              let representation = targetView.bitmapImageRepForCachingDisplay(in: bounds) else {
            return
        }

        targetView.cacheDisplay(in: bounds, to: representation)
        guard let pngData = representation.representation(using: .png, properties: [:]) else {
            return
        }

        do {
            try pngData.write(to: url, options: .atomic)
        } catch {
            fputs("Failed to write validation window image: \(error)\n", stderr)
        }
    }

    private func reassertForegroundForValidationIfNeeded() {
        guard isRunningValidationHooks else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.activateCurrentApp(unhideAllWindows: false)
        }
    }

    private func validationSaveDestinationString(_ destination: EditorSaveDestination?) -> String? {
        switch destination {
        case .clipboard:
            return "clipboard"
        case .file:
            return "file"
        case .none:
            return nil
        }
    }

    private func validationResolvedColorDescription(_ color: Color) -> String {
        let nsColor = NSColor(color)
        guard let converted = nsColor.usingColorSpace(.deviceRGB) else {
            return nsColor.description
        }
        return String(
            format: "%.4f,%.4f,%.4f,%.4f",
            converted.redComponent,
            converted.greenComponent,
            converted.blueComponent,
            converted.alphaComponent
        )
    }

    private func validationCurrentEditorWindow() -> NSWindow? {
        if let window = NSApp.keyWindow,
           window == noteEditorWindowController?.window || window == standaloneNoteWindowController?.window {
            return window
        }
        if let window = noteEditorWindowController?.window, window.isVisible {
            return window
        }
        if let window = standaloneNoteWindowController?.window, window.isVisible {
            return window
        }
        return nil
    }

    private func validationCurrentPreviewWebView(in window: NSWindow? = nil) -> WKWebView? {
        guard let rootView = (window ?? validationCurrentEditorWindow())?.contentView else {
            return nil
        }
        return validationFindPreviewWebView(in: rootView)
    }

    private func validationFindPreviewWebView(in view: NSView) -> WKWebView? {
        if let webView = view as? WKWebView {
            return webView
        }
        for subview in view.subviews {
            if let webView = validationFindPreviewWebView(in: subview) {
                return webView
            }
        }
        return nil
    }

    private func validationEvaluatePreviewJavaScript(_ script: String, completion: ((Any?) -> Void)? = nil) {
        guard let webView = validationCurrentPreviewWebView() else {
            completion?(nil)
            return
        }
        webView.evaluateJavaScript(script) { result, _ in
            completion?(result)
        }
    }

    private func validationSelectCurrentPreviewText(containing needle: String, preferCodeBlock: Bool) {
        let quotedNeedle = (try? JSONEncoder().encode(needle))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        let selector = preferCodeBlock ? "pre code" : "body *"
        let quotedSelector = (try? JSONEncoder().encode(selector))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\"body *\""
        let script = """
        (function() {
          const needle = \(quotedNeedle);
          const nodes = Array.from(document.querySelectorAll(\(quotedSelector)));
          let target = null;
          for (const node of nodes) {
            const text = (node.textContent || '');
            if (text.includes(needle)) {
              target = node;
              break;
            }
          }
          if (!target) { return ''; }
          const range = document.createRange();
          range.selectNodeContents(target);
          const selection = window.getSelection();
          if (!selection) { return ''; }
          selection.removeAllRanges();
          selection.addRange(range);
          target.scrollIntoView({block: 'center', inline: 'nearest'});
          return selection.toString();
        })();
        """
        validationEvaluatePreviewJavaScript(script) { result in
            MarkdownPreviewValidationState.shared.selectedText = result as? String
        }
    }

    private func validationCopyCurrentPreviewSelection() {
        let script = "window.getSelection ? window.getSelection().toString() : '';"
        validationEvaluatePreviewJavaScript(script) { [weak self] result in
            guard let self, let text = result as? String, !text.isEmpty else { return }
            MarkdownPreviewValidationState.shared.selectedText = text
            _ = self.copyTextToClipboard(text, feedbackMessage: "Copied", storeInHistory: false)
        }
    }

    private func validationMeasureCurrentPreviewHorizontalOverflow() {
        let script = """
        (function() {
          const root = document.scrollingElement || document.documentElement || document.body;
          if (!root) { return null; }
          return (root.scrollWidth - root.clientWidth) > 1;
        })();
        """
        validationEvaluatePreviewJavaScript(script) { result in
            MarkdownPreviewValidationState.shared.hasHorizontalOverflow = result as? Bool
        }
    }

    private func validationSetCurrentPreviewScroll(_ progress: Double) {
        let clamped = min(1.0, max(0.0, progress))
        let script = """
        (function() {
          const root = document.scrollingElement || document.documentElement || document.body;
          if (!root) { return 0; }
          const maxScroll = Math.max(0, root.scrollHeight - window.innerHeight);
          root.scrollTop = maxScroll * \(clamped);
          return maxScroll > 0 ? root.scrollTop / maxScroll : 0;
        })();
        """
        validationEvaluatePreviewJavaScript(script) { result in
            MarkdownPreviewValidationState.shared.scrollFraction = result as? Double
        }
    }

    private func validationSyncCurrentPreviewScroll() {
        let script = """
        (function() {
          const root = document.scrollingElement || document.documentElement || document.body;
          if (!root) { return null; }
          const maxScroll = Math.max(0, root.scrollHeight - window.innerHeight);
          return maxScroll > 0 ? root.scrollTop / maxScroll : 0;
        })();
        """
        validationEvaluatePreviewJavaScript(script) { result in
            MarkdownPreviewValidationState.shared.scrollFraction = result as? Double
        }
    }

    private func validationClickCurrentPreviewFirstLink() {
        MarkdownPreviewValidationState.shared.resetPrompt()
        let script = """
        (function() {
          const link = document.querySelector('a');
          if (!link) { return false; }
          link.click();
          return true;
        })();
        """
        validationEvaluatePreviewJavaScript(script, completion: nil)
    }

    private func validationRespondToPreviewLinkPrompt(_ rawChoice: String) {
        switch rawChoice.lowercased() {
        case "1", "first", "open":
            MarkdownPreviewValidationState.shared.respondToPrompt(open: true)
        default:
            MarkdownPreviewValidationState.shared.respondToPrompt(open: false)
        }
    }

    private func validationSetPanelShortcut(_ rawValue: String) {
        guard let shortcut = try? parseShortcutInput(rawValue) else { return }
        do {
            try validateGlobalHotKeyAvailability(
                panelShortcut: shortcut,
                translationShortcut: settings.translationShortcut,
                additionalShortcuts: [
                    ("New Note", settings.globalNewNoteShortcut),
                    ("Copy Joined", settings.globalCopyJoinedEnabled ? settings.globalCopyJoinedShortcut : nil),
                    ("Copy Normalized", settings.globalCopyNormalizedEnabled ? settings.globalCopyNormalizedShortcut : nil)
                ]
            )
            applyPanelShortcut(shortcut)
        } catch {
            return
        }
    }

    private func validationSetToggleMarkdownPreviewShortcut(_ rawValue: String) {
        guard let shortcut = try? parseShortcutInput(rawValue) else { return }
        mutateSettings { $0.toggleMarkdownPreviewShortcut = shortcut }
        saveSettings()
    }

    private func validationSetGlobalSpecialCopyEnabled(joined: Bool? = nil, normalized: Bool? = nil) {
        let previous = settings
        mutateSettings { settings in
            if let joined {
                settings.globalCopyJoinedEnabled = joined
            }
            if let normalized {
                settings.globalCopyNormalizedEnabled = normalized
            }
        }
        saveSettings()
        refreshVisibleWindowsAfterApplyingSettings(from: previous, to: settings)
        registerHotKeys()
    }

    private func validationRespondToAttachedSheetSavingToFile(_ destinationURL: URL) {
        guard let context = validationAttachedSheetContext else { return }
        let observedExternalFileURL = noteEditorExternalFileURL

        let parentWindow = noteEditorWindowController?.window?.attachedSheet != nil
            ? noteEditorWindowController?.window
            : standaloneNoteWindowController?.window?.attachedSheet != nil
                ? standaloneNoteWindowController?.window
                : settingsWindowController?.window?.attachedSheet != nil
                    ? settingsWindowController?.window
                    : nil
        if let parentWindow, let sheet = parentWindow.attachedSheet {
            parentWindow.endSheet(sheet, returnCode: .cancel)
            sheet.orderOut(nil)
        }

        let didSave = validationSaveCurrentEditorToFile(destinationURL)
        guard didSave else {
            validationAttachedSheetContext = nil
            return
        }

        switch context {
        case .closeUnsavedEditor:
            dismissStandaloneNoteEditorWindow(copyToClipboard: false)
        case .closeUnsavedManualNote:
            dismissStandaloneManualNoteEditorWindow(copyToClipboard: false)
        case .fileSaveDestination, .manualNoteSaveDestination:
            break
        case .externalFileChange:
            if let observedExternalFileURL,
               let diskText = try? String(contentsOf: observedExternalFileURL, encoding: .utf8) {
                reloadFileBackedEditorFromDisk(text: diskText, fileURL: observedExternalFileURL)
            }
        }
        validationAttachedSheetContext = nil
    }

    private func consumeCodexOpenRequestIfNeeded() {
        let storePaths = ClipboardStorePaths.default()
        let requestURL = storePaths.codexOpenRequestURL

        guard FileManager.default.fileExists(atPath: requestURL.path),
              let requestText = try? String(contentsOf: requestURL, encoding: .utf8)
        else {
            return
        }

        guard let request = Self.parseCodexOpenRequest(requestText) else {
            try? FileManager.default.removeItem(at: requestURL)
            return
        }

        try? FileManager.default.removeItem(at: requestURL)
        DispatchQueue.main.async { [weak self] in
            self?.openExternalCodexEditor(
                for: request.fileURL,
                sessionID: request.sessionID,
                projectRootURL: request.projectRootURL,
                sessionStateURL: request.sessionStateURL
            )
        }
    }
    
    @MainActor
    private func getModelContainer() -> ModelContainer {
        if Self.isRunningAutomatedTests {
            let schema = Schema([ClipboardItem.self])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [configuration])
        }
        return try! ClipboardStoreBootstrapper.makeContainer()
    }
    
    private func requestAccessibilityPermissions() {
        let promptStateKey = "app.accessibility.prompted"
        if AXIsProcessTrusted() {
            return
        }

        guard !UserDefaults.standard.bool(forKey: promptStateKey) else {
            print("Accessibility permission is required for Enter-to-paste and selected-text translation.")
            return
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)

        if !isTrusted {
            UserDefaults.standard.set(true, forKey: promptStateKey)
            print("Accessibility permission is required for Enter-to-paste and selected-text translation.")
        }
    }
    
    private func setupPanel() {
        let initialSize = preferredPanelSize()
        panel = ClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: initialSize.width, height: initialSize.height)
        )
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: makePanelRootView())
    }

    private func makePanelRootView() -> some View {
        ClipboardHistoryView(
            appDelegate: self,
            dataManager: dataManager,
            onCopyRequest: { [weak self] item in
                self?.copyToClipboard(item) ?? false
            },
            onCopyTextRequest: { [weak self] text, message in
                self?.copyTextToClipboard(text, feedbackMessage: message, storeInHistory: true) ?? false
            },
            onPasteRequest: { [weak self] item in
                self?.pasteSelectedItem(item)
            },
            onOpenSettings: { [weak self] in
                self?.openSettingsWindow()
            },
            onClosePanel: { [weak self] in
                self?.closePanelAndReactivate()
            },
            onPinnedAreaVisibilityChanged: { [weak self] isVisible in
                self?.panelPinnedAreaVisible = isVisible
            },
            onFocusChanged: { [weak self] item in
                self?.focusedPanelItem = item
            },
            onSelectionChanged: { [weak self] item in
                self?.highlightedPanelItem = item
            },
            onInlineEditorStateChanged: { [weak self] itemID, isDirty, isPreviewVisible in
                self?.panelInlineEditingItemID = itemID
                self?.panelInlineEditorDirty = isDirty
                self?.panelInlineEditorPreviewVisible = isPreviewVisible
            }
        )
        .modelContainer(sharedContainer)
    }

    private func performLaunchAutomationIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(LaunchArgument.openPanelOnLaunch) || arguments.contains(LaunchArgument.openHelpOnLaunch) else {
            return
        }

        suppressPanelAutoClose = true
        launchAutomationAutoCloseSuppressionTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.suppressPanelAutoClose = false
            self?.launchAutomationAutoCloseSuppressionTask = nil
        }
        launchAutomationAutoCloseSuppressionTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: task)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }

            if arguments.contains(LaunchArgument.openPanelOnLaunch) {
                self.togglePanel()
            }

            if arguments.contains(LaunchArgument.openHelpOnLaunch) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    NotificationCenter.default.post(
                        name: .clipboardHelpRequested,
                        object: nil,
                        userInfo: ["isEditingSelectedText": false]
                    )
                }
            }
        }
    }
    
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clipboard History")
            button.target = self
            button.action = #selector(statusItemButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        statusItem = item
        rebuildStatusMenu()
        updateStatusItemToolTip()
    }
    
    private func registerHotKeys() {
        suspendGlobalHotKeys()
        
        let panelResult = HotKeyManager.shared.registerDetailed(shortcut: panelHotKeyShortcut) { [weak self] in
            self?.togglePanel()
        }
        panelHotKeyRegistrationID = panelResult.registrationID
        panelHotKeyState = panelResult.isSuccess ? .registered : .failed(panelResult.status)
        
        let translateResult = HotKeyManager.shared.registerDetailed(shortcut: translateHotKeyShortcut) { [weak self] in
            self?.translateCurrentContext()
        }
        translateHotKeyRegistrationID = translateResult.registrationID
        translationHotKeyState = translateResult.isSuccess ? .registered : .failed(translateResult.status)

        if let shortcut = settings.globalNewNoteShortcut {
            let result = HotKeyManager.shared.registerDetailed(shortcut: shortcut) { [weak self] in
                self?.createNewNoteFromAnyState()
            }
            globalNewNoteHotKeyRegistrationID = result.registrationID
        }

        if settings.globalCopyJoinedEnabled,
           let shortcut = settings.globalCopyJoinedShortcut {
            let result = HotKeyManager.shared.registerDetailed(shortcut: shortcut) { [weak self] in
                guard let self, self.settings.globalCopyJoinedEnabled else { return }
                if self.currentEditorCommandTargetWindowNumber() != nil {
                    self.postEditorCommand(.joinLines)
                    return
                }
                if self.panel.isVisible {
                    NotificationCenter.default.post(
                        name: .clipboardTransformRequested,
                        object: nil,
                        userInfo: ["action": "join"]
                    )
                    return
                }
                let targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                self.copySelectedTextFromCurrentContext(
                    feedbackMessage: "Joined",
                    targetPID: targetPID,
                    transform: joinLinesText
                )
            }
            globalCopyJoinedHotKeyRegistrationID = result.registrationID
        }

        if settings.globalCopyNormalizedEnabled,
           let shortcut = settings.globalCopyNormalizedShortcut {
            let result = HotKeyManager.shared.registerDetailed(shortcut: shortcut) { [weak self] in
                guard let self, self.settings.globalCopyNormalizedEnabled else { return }
                if self.currentEditorCommandTargetWindowNumber() != nil {
                    self.postEditorCommand(.normalizeForCommand)
                    return
                }
                if self.panel.isVisible {
                    NotificationCenter.default.post(
                        name: .clipboardTransformRequested,
                        object: nil,
                        userInfo: ["action": "normalize"]
                    )
                    return
                }
                let targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                self.copySelectedTextFromCurrentContext(
                    feedbackMessage: "Normalized",
                    targetPID: targetPID,
                    transform: normalizeCommandText
                )
            }
            globalCopyNormalizedHotKeyRegistrationID = result.registrationID
        }
        
        updateStatusItemToolTip()
        rebuildStatusMenu()
    }

    private func suspendGlobalHotKeys() {
        if let id = panelHotKeyRegistrationID {
            HotKeyManager.shared.unregister(registrationID: id)
            panelHotKeyRegistrationID = nil
            panelHotKeyState = .notRegistered
        }
        if let id = translateHotKeyRegistrationID {
            HotKeyManager.shared.unregister(registrationID: id)
            translateHotKeyRegistrationID = nil
            translationHotKeyState = .notRegistered
        }
        if let id = globalNewNoteHotKeyRegistrationID {
            HotKeyManager.shared.unregister(registrationID: id)
            globalNewNoteHotKeyRegistrationID = nil
        }
        if let id = globalCopyJoinedHotKeyRegistrationID {
            HotKeyManager.shared.unregister(registrationID: id)
            globalCopyJoinedHotKeyRegistrationID = nil
        }
        if let id = globalCopyNormalizedHotKeyRegistrationID {
            HotKeyManager.shared.unregister(registrationID: id)
            globalCopyNormalizedHotKeyRegistrationID = nil
        }
    }
    
    private func updateStatusItemToolTip() {
        guard let button = statusItem?.button else { return }
        let panelShortcutLabel = HotKeyManager.displayString(for: panelHotKeyShortcut)
        let translateShortcutLabel = HotKeyManager.displayString(for: translateHotKeyShortcut)
        button.toolTip = "Clipboard History (\(panelShortcutLabel)) / Translate (\(translateShortcutLabel))"
    }
    
    private func rebuildStatusMenu() {
        statusMenu.removeAllItems()
        
        let toggleItem = NSMenuItem(
            title: "Show / Hide Clipboard History",
            action: #selector(togglePanelFromMenu),
            keyEquivalent: ""
        )
        toggleItem.tag = MenuTag.togglePanel.rawValue
        toggleItem.target = self
        statusMenu.addItem(toggleItem)

        let newNoteItem = NSMenuItem(
            title: "New Note (\(HotKeyManager.displayString(for: settings.newNoteShortcut)))",
            action: #selector(createNewNoteFromMenu),
            keyEquivalent: ""
        )
        newNoteItem.tag = MenuTag.newNote.rawValue
        newNoteItem.target = self
        statusMenu.addItem(newNoteItem)

        let openFileItem = NSMenuItem(
            title: "Open File…",
            action: #selector(openFileFromMenu),
            keyEquivalent: ""
        )
        openFileItem.tag = MenuTag.openFile.rawValue
        openFileItem.target = self
        statusMenu.addItem(openFileItem)

        statusMenu.addItem(.separator())
        
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.tag = MenuTag.openSettings.rawValue
        settingsItem.target = self
        statusMenu.addItem(settingsItem)
        
        statusMenu.addItem(.separator())
        
        let quitItem = NSMenuItem(title: "Quit Clipboard History", action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.tag = MenuTag.quit.rawValue
        quitItem.target = self
        statusMenu.addItem(quitItem)
    }
    
    private func showStatusMenu(using event: NSEvent) {
        guard let button = statusItem?.button else { return }
        rebuildStatusMenu()
        NSMenu.popUpContextMenu(statusMenu, with: event, for: button)
    }
    
    private func showPanel() {
        temporarilySuppressPanelAutoClose(for: 0.45)
        if NSApp.isActive,
           let activeWindow = NSApp.keyWindow ?? NSApp.mainWindow,
           activeWindow != panel,
           activeWindow.isVisible {
            panelReturnWindow = activeWindow
        } else {
            panelReturnWindow = nil
        }
        let targetApp = preferredPlacementTargetApp() ?? currentPlacementTargetApp()
        if let targetApp, targetApp != NSRunningApplication.current {
            previouslyActiveApp = targetApp
            placementTargetApp = targetApp
        }
        let presentationContext = panelPresentationContext()
        NotificationCenter.default.post(
            name: .clipboardPanelWillOpen,
            object: nil,
            userInfo: [
                "targetAppName": previouslyActiveApp?.localizedName ?? "",
                "targetArrowSymbol": presentationContext.targetArrowSymbol
            ]
        )
        if showsAnchorDebugMarkers, let anchorPoint = presentationContext.anchorPoint {
            showAnchorDebugMarkers(
                presentationContext.anchorDebugCandidates,
                fallbackPoint: anchorPoint,
                description: presentationContext.anchorDescription ?? ""
            )
        }
        NSApp.setActivationPolicy(.regular)
        panel.alphaValue = 1
        panel.setFrame(presentationContext.finalFrame, display: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        activateCurrentApp(unhideAllWindows: false)
        DispatchQueue.main.async { [weak self] in
            self?.panel.orderFrontRegardless()
            self?.panel.makeKeyAndOrderFront(nil)
        }
        hasPresentedPanelThisLaunch = true
        DispatchQueue.main.async { [weak self] in
            self?.clipboardController.syncNow()
        }
    }

    private func temporarilySuppressPanelAutoClose(for duration: TimeInterval) {
        suppressPanelAutoClose = true
        panelAutoCloseSuppressionTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.suppressPanelAutoClose = false
            self?.panelAutoCloseSuppressionTask = nil
        }
        panelAutoCloseSuppressionTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
    }

    private func togglePanel() {
        if Self.panelToggleAction(isVisible: panel.isVisible, isFrontmost: isPanelFrontmost()) == .close {
            closePanelAndReactivate()
            return
        }

        showPanel()
    }
    
    private func isPanelFrontmost() -> Bool {
        panel.isVisible && NSApp.isActive && panel.isKeyWindow
    }
    
    private func panelPresentationContext() -> PanelPresentationContext {
        if !hasPersistedPanelSize() || !hasPresentedPanelThisLaunch {
            return presentationContextAtScreenCenter()
        }
        if let context = presentationContextForFrontmostWindow() {
            return context
        }
        return presentationContextAtScreenCenter()
    }

    private func presentationContextAtScreenCenter() -> PanelPresentationContext {
        let screen = preferredPlacementTargetApp()
            .flatMap(frontmostWindowFrame(for:))
            .flatMap(screen(containing:))
            ?? panel.screen
            ?? NSScreen.main
        guard let screen else {
            let preferredSize = preferredPanelSize()
            let fallback = NSRect(x: 120, y: 120, width: preferredSize.width, height: preferredSize.height)
            return PanelPresentationContext(finalFrame: fallback, anchorPoint: nil, anchorDescription: nil, targetArrowSymbol: "arrow.down.left", anchorDebugCandidates: [])
        }
        
        let visibleFrame = screen.visibleFrame
        let preferredSize = preferredPanelSize()
        let panelWidth = min(preferredSize.width, visibleFrame.width - (Layout.screenMargin * 2))
        let panelHeight = min(preferredSize.height, visibleFrame.height - (Layout.screenMargin * 2))
        
        let finalFrame = NSRect(
            x: visibleFrame.midX - (panelWidth / 2),
            y: visibleFrame.midY - (panelHeight / 2),
            width: panelWidth,
            height: panelHeight
        )
        return PanelPresentationContext(finalFrame: finalFrame, anchorPoint: nil, anchorDescription: nil, targetArrowSymbol: "arrow.down.left", anchorDebugCandidates: [])
    }

    private func presentationContextForFrontmostWindow() -> PanelPresentationContext? {
        let placementApp = currentPlacementTargetApp()
        placementTargetApp = placementApp
        let windowRect = frontmostWindowFrame(for: placementApp)
        guard let windowRect,
              let screen = screen(containing: windowRect) else {
            let appName = placementApp?.localizedName ?? "unknown"
            print("Panel placement: no window frame for target app \(appName), falling back to center")
            return nil
        }

        let visibleFrame = screen.visibleFrame.insetBy(dx: Layout.screenMargin, dy: Layout.screenMargin)
        let preferredSize = preferredPanelSize()
        let panelSize = NSSize(
            width: min(preferredSize.width, visibleFrame.width),
            height: min(preferredSize.height, visibleFrame.height)
        )

        let rightThreshold = visibleFrame.minX + (visibleFrame.width * (2.0 / 3.0))
        let shouldUseLeftTop = windowRect.midX > rightThreshold
        let shouldUseBottomEdge = windowRect.midY > visibleFrame.midY

        let finalX = shouldUseLeftTop
            ? visibleFrame.minX
            : visibleFrame.maxX - panelSize.width
        let finalY = shouldUseBottomEdge
            ? visibleFrame.minY
            : visibleFrame.maxY - panelSize.height
        let finalFrame = NSRect(x: finalX, y: finalY, width: panelSize.width, height: panelSize.height)

        let screenCenter = NSPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        let anchorPoint = screenCenter
        let appName = placementApp?.localizedName ?? "unknown"
        let targetArrowSymbol: String
        switch (windowRect.midX < finalFrame.midX, windowRect.midY < finalFrame.midY) {
        case (true, true):
            targetArrowSymbol = "arrow.down.left"
        case (false, true):
            targetArrowSymbol = "arrow.down.right"
        case (true, false):
            targetArrowSymbol = "arrow.up.left"
        case (false, false):
            targetArrowSymbol = "arrow.up.right"
        }
        print("Panel placement: app=\(appName) window=\(windowRect.debugDescription) screen=\(screen.frame.debugDescription) visible=\(visibleFrame.debugDescription) final=\(finalFrame.debugDescription)")
        let finalCandidate = AnchorDebugCandidate(
            id: "final",
            point: anchorPoint,
            label: "F",
            color: .systemRed,
            isDraggable: true
        )
        return PanelPresentationContext(
            finalFrame: finalFrame,
            anchorPoint: anchorPoint,
            anchorDescription: shouldUseBottomEdge
                ? (shouldUseLeftTop ? "Screen left bottom" : "Screen right bottom")
                : (shouldUseLeftTop ? "Screen left top" : "Screen right top"),
            targetArrowSymbol: targetArrowSymbol,
            anchorDebugCandidates: pendingAnchorDebugCandidates + [finalCandidate]
        )
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == panel else {
            return
        }
        persistPanelSize(window.frame.size)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }
        if window == helpPanel {
            closeHelpPanel(refocusClipboardPanel: false)
            return
        }
        guard window == panel, panel.isVisible else {
            return
        }
        if helpPanel?.isVisible == true {
            return
        }
        if suppressPanelAutoClose || settingsWindowController?.window?.isVisible == true {
            return
        }
        closePanelAndReactivate()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        if window == standaloneNoteWindowController?.window {
            return
        }

        if window == noteEditorWindowController?.window {
            return
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender == standaloneNoteWindowController?.window {
            closeStandaloneManualNoteEditor()
            return false
        }
        guard sender == noteEditorWindowController?.window else {
            return true
        }
        closeStandaloneNoteEditor()
        return false
    }

    private func closePanelAndReactivate() {
        NotificationCenter.default.post(name: .clipboardPanelWillClose, object: nil)
        closeHelpPanel(refocusClipboardPanel: false)
        panel.orderOut(nil)
        hideAnchorDebugMarker()
        if let returnWindow = panelReturnWindow, returnWindow.isVisible {
            panelReturnWindow = nil
            activateCurrentApp()
            returnWindow.windowController?.showWindow(nil)
            returnWindow.orderFrontRegardless()
            returnWindow.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async {
                returnWindow.makeKeyAndOrderFront(nil)
            }
            restoreAccessoryActivationPolicyIfNeeded()
            return
        }
        panelReturnWindow = nil
        reactivatePreviouslyActiveApp()
        restoreAccessoryActivationPolicyIfNeeded()
    }

    func createNewNoteFromAnyState() {
        if let window = standaloneNoteWindowController?.window, window.isVisible {
            if NSApp.keyWindow == window || NSApp.mainWindow == window {
                dismissStandaloneManualNoteEditorWindow(copyToClipboard: true)
            } else {
                activateCurrentApp()
                standaloneNoteWindowController?.showWindow(nil)
                window.orderFront(nil)
                window.makeKeyAndOrderFront(nil)
            }
            return
        }

        let targetApp = currentPlacementTargetApp()
        previouslyActiveApp = targetApp
        placementTargetApp = targetApp

        let itemID: UUID
        let createdPlaceholderManualNote: Bool
        if settings.newNoteReopenBehavior == .restoreLastDraft,
           let lastClosedNoteEditorItemID,
           dataManager.snapshotItem(id: lastClosedNoteEditorItemID) != nil {
            itemID = lastClosedNoteEditorItemID
            createdPlaceholderManualNote = false
        } else if let item = dataManager.createManualNote(text: "") {
            itemID = item.id
            createdPlaceholderManualNote = true
        } else {
            return
        }

        NotificationCenter.default.post(
            name: .clipboardManualNoteCreated,
            object: nil,
            userInfo: ["itemID": itemID]
        )
        openStandaloneNoteEditor(for: itemID, isPlaceholderManualNote: createdPlaceholderManualNote)
    }

    private func observeHelpRequests() {
        guard helpRequestObserver == nil else { return }
        helpRequestObserver = NotificationCenter.default.addObserver(
            forName: .clipboardHelpRequested,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let isEditingSelectedText = notification.userInfo?["isEditingSelectedText"] as? Bool ?? false
            self?.toggleHelpPanel(isEditingSelectedText: isEditingSelectedText)
        }
    }

    private func toggleHelpPanel(isEditingSelectedText: Bool) {
        if helpPanel?.isVisible == true {
            closeHelpPanel(refocusClipboardPanel: true)
            return
        }
        showHelpPanel(isEditingSelectedText: isEditingSelectedText)
    }

    private func showHelpPanel(isEditingSelectedText: Bool) {
        let panel = helpPanel ?? makeHelpPanel()
        let panelWasVisible = self.panel.isVisible
        suppressPanelAutoClose = panelWasVisible
        let targetFrame = helpPanelFrame(for: panel)
        if let hostingController = panel.contentViewController as? NSHostingController<ClipboardHelpPanelContent> {
            hostingController.rootView = ClipboardHelpPanelContent(
                settings: settings,
                isEditingSelectedText: isEditingSelectedText,
                onClose: { [weak self] in
                    self?.closeHelpPanel(refocusClipboardPanel: true)
                }
            )
        }
        panel.setFrame(targetFrame, display: true)
        if panel.parent != self.panel {
            self.panel.addChildWindow(panel, ordered: .above)
        }
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        helpPanel = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.suppressPanelAutoClose = false
        }
    }

    private func makeHelpPanel() -> NSPanel {
        let hostingController = NSHostingController(
            rootView: ClipboardHelpPanelContent(
                settings: settings,
                isEditingSelectedText: false,
                onClose: { [weak self] in
                    self?.closeHelpPanel(refocusClipboardPanel: true)
                }
            )
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 440),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Keyboard Help"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.moveToActiveSpace]
        panel.delegate = self
        panel.contentViewController = hostingController
        return panel
    }

    private func helpPanelFrame(for helpPanel: NSPanel) -> NSRect {
        let screen = screen(containing: panel.frame) ?? panel.screen ?? NSScreen.main
        let visibleFrame = (screen?.visibleFrame ?? panel.frame).insetBy(dx: Layout.screenMargin, dy: Layout.screenMargin)
        let desiredWidth = min(420, max(320, visibleFrame.width - 40))
        let desiredHeight = min(520, max(280, visibleFrame.height - 40))
        return Self.helpPanelPlacement(
            for: panel.frame,
            within: visibleFrame,
            helpSize: NSSize(width: desiredWidth, height: desiredHeight),
            gap: 14
        ).frame
    }

    static func helpPanelPlacement(
        for panelFrame: NSRect,
        within visibleFrame: NSRect,
        helpSize: NSSize,
        gap: CGFloat
    ) -> HelpPanelPlacement {
        let alignedY = min(
            max(panelFrame.maxY - helpSize.height, visibleFrame.minY),
            visibleFrame.maxY - helpSize.height
        )

        let rightX = panelFrame.maxX + gap
        if rightX + helpSize.width <= visibleFrame.maxX {
            return HelpPanelPlacement(
                frame: clampedAuxiliaryFrame(
                    NSRect(x: rightX, y: alignedY, width: helpSize.width, height: helpSize.height),
                    within: visibleFrame
                ),
                side: .right
            )
        }

        let leftX = panelFrame.minX - gap - helpSize.width
        if leftX >= visibleFrame.minX {
            return HelpPanelPlacement(
                frame: clampedAuxiliaryFrame(
                    NSRect(x: leftX, y: alignedY, width: helpSize.width, height: helpSize.height),
                    within: visibleFrame
                ),
                side: .left
            )
        }

        return HelpPanelPlacement(
            frame: clampedAuxiliaryFrame(
                NSRect(
                    x: visibleFrame.midX - (helpSize.width / 2),
                    y: visibleFrame.midY - (helpSize.height / 2),
                    width: helpSize.width,
                    height: helpSize.height
                ),
                within: visibleFrame
            ),
            side: .centered
        )
    }

    static func auxiliaryWindowPlacement(
        anchorFrame: NSRect,
        visibleFrame: NSRect,
        windowSize: NSSize,
        gap: CGFloat
    ) -> NSRect {
        let alignedY = min(
            max(anchorFrame.maxY - windowSize.height, visibleFrame.minY),
            visibleFrame.maxY - windowSize.height
        )

        let rightFrame = NSRect(
            x: anchorFrame.maxX + gap,
            y: alignedY,
            width: windowSize.width,
            height: windowSize.height
        )
        if rightFrame.maxX <= visibleFrame.maxX {
            return clampedAuxiliaryFrame(rightFrame, within: visibleFrame)
        }

        let leftFrame = NSRect(
            x: anchorFrame.minX - gap - windowSize.width,
            y: alignedY,
            width: windowSize.width,
            height: windowSize.height
        )
        if leftFrame.minX >= visibleFrame.minX {
            return clampedAuxiliaryFrame(leftFrame, within: visibleFrame)
        }

        return clampedAuxiliaryFrame(
            NSRect(
                x: visibleFrame.midX - (windowSize.width / 2),
                y: visibleFrame.midY - (windowSize.height / 2),
                width: windowSize.width,
                height: windowSize.height
            ),
            within: visibleFrame
        )
    }

    static func clampedAuxiliaryFrame(_ frame: NSRect, within visibleFrame: NSRect) -> NSRect {
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        let x = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - width)
        let y = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func closeHelpPanel(refocusClipboardPanel: Bool) {
        guard let helpPanel else { return }
        panel.removeChildWindow(helpPanel)
        helpPanel.orderOut(nil)
        if refocusClipboardPanel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func reactivatePreviouslyActiveApp() {
        guard let app = previouslyActiveApp,
              app != NSRunningApplication.current else {
            return
        }
        activateTargetApp(app)
    }
    
    @discardableResult
    private func copyToClipboard(_ item: ClipboardItem) -> Bool {
        clipboardController.prepareForInternalPaste()
        var didWrite = false
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        if item.type == .text, let text = dataManager.resolvedText(for: item) {
            didWrite = pasteboard.setString(text, forType: .string)
                && pasteboard.string(forType: .string) == text
        } else if item.type == .image, let fileName = item.imageFileName,
                  let image = dataManager.loadImage(fileName: fileName),
                  let tiffData = image.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            let didWritePNG = pasteboard.setData(pngData, forType: .png)
            let didWriteTIFF = pasteboard.setData(tiffData, forType: .tiff)
            didWrite = didWritePNG || didWriteTIFF
        }
        
        clipboardController.finishInternalPaste()
        if didWrite, !panel.isVisible {
            showFloatingFeedback(message: "Copied", style: .copy)
        }
        return didWrite
    }

    @discardableResult
    private func copyTextToClipboard(
        _ text: String,
        feedbackMessage: String? = nil,
        forceFloatingFeedback: Bool = false,
        storeInHistory: Bool = false,
        feedbackStyle: FloatingFeedbackStyle = .copy
    ) -> Bool {
        clipboardController.prepareForInternalPaste()

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let didWrite = pasteboard.setString(text, forType: .string)
            && pasteboard.string(forType: .string) == text

        clipboardController.finishInternalPaste()
        guard didWrite else {
            return false
        }
        if storeInHistory {
            dataManager.storeCapture(
                .init(payload: .text(text), dedupeKey: ClipboardDedupeKey.text(text))
            )
        }
        if forceFloatingFeedback || !panel.isVisible {
            showFloatingFeedback(message: feedbackMessage ?? "Copied", style: feedbackStyle)
        }
        return true
    }

    func pasteTextToFrontApp(_ text: String) {
        copyTextToClipboard(text, feedbackMessage: "Copied")
        let targetApp = resolvedPasteTargetApp()

        if panel.isVisible {
            closePanelAndReactivate()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if let targetApp {
                self.activateTargetApp(targetApp)
            } else {
                self.reactivatePreviouslyActiveApp()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                PasteSynthesizer.simulateCmdV()
            }
        }
    }

    private func copySelectedTextFromCurrentContext(
        feedbackMessage: String,
        targetPID: pid_t? = nil,
        transform: @escaping (String) -> String
    ) {
        let panelText: String?
        if panel.isVisible,
           let item = highlightedPanelItem,
           item.type == .text {
            panelText = dataManager.resolvedText(for: item)
        } else {
            panelText = nil
        }

        if let sourceText = Self.resolvedSpecialCopySourceText(
            panelText: panelText,
            clipboardText: NSPasteboard.general.string(forType: .string)
        ) {
            _ = copyTextToClipboard(
                transform(sourceText),
                feedbackMessage: feedbackMessage,
                forceFloatingFeedback: true,
                storeInHistory: true,
                feedbackStyle: floatingFeedbackStyle(for: feedbackMessage)
            )
            return
        }

        let _ = targetPID
        NSSound.beep()
    }
    
    private func pasteSelectedItem(_ item: ClipboardItem) {
        if item.type == .text, let text = dataManager.resolvedText(for: item) {
            pasteTextToFrontApp(text)
            return
        }

        copyToClipboard(item)
        let targetApp = resolvedPasteTargetApp()

        closePanelAndReactivate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let targetApp {
                self.activateTargetApp(targetApp)
            } else {
                self.reactivatePreviouslyActiveApp()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                PasteSynthesizer.simulateCmdV()
            }
        }
    }

    private func activateCurrentApp(unhideAllWindows: Bool = true) {
        if unhideAllWindows {
            NSApp.unhide(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
    }

    private func refreshGlobalHotKeysIfNeeded() {
        guard settingsWindowController?.window?.isVisible != true else { return }
        registerHotKeys()
    }

    private func promoteAppForExternalEditorIfNeeded() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshGlobalHotKeysIfNeeded()
    }

    private func restoreAccessoryActivationPolicyIfNeeded() {
        guard Self.shouldRestoreAccessoryActivationPolicy(
            currentEditorHasFileURL: noteEditorExternalFileURL != nil,
            hasAnyClipboardWindowVisible: hasAnyClipboardWindowVisible
        ) else { return }
        NSApp.setActivationPolicy(.accessory)
        refreshGlobalHotKeysIfNeeded()
    }

    static func shouldRestoreAccessoryActivationPolicy(
        currentEditorHasFileURL: Bool,
        hasAnyClipboardWindowVisible: Bool
    ) -> Bool {
        !currentEditorHasFileURL && !hasAnyClipboardWindowVisible
    }

    private func activateTargetApp(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: app)
            _ = app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func currentEditorCommandTargetWindowNumber() -> Int? {
        guard let keyWindow = NSApp.keyWindow else {
            if let window = noteEditorWindowController?.window, window.isVisible {
                return window.windowNumber
            }
            if let window = standaloneNoteWindowController?.window, window.isVisible {
                return window.windowNumber
            }
            return nil
        }
        if keyWindow == standaloneNoteWindowController?.window || keyWindow == noteEditorWindowController?.window {
            return keyWindow.windowNumber
        }
        if let window = noteEditorWindowController?.window, window.isVisible {
            return window.windowNumber
        }
        if let window = standaloneNoteWindowController?.window, window.isVisible {
            return window.windowNumber
        }
        return nil
    }

    private func postEditorCommand(_ command: EditorCommand, text: String? = nil) {
        var userInfo: [String: Any] = ["command": command.rawValue]
        if let targetWindowNumber = currentEditorCommandTargetWindowNumber() {
            userInfo["targetWindowNumber"] = targetWindowNumber
        }
        if let text {
            userInfo["text"] = text
        }
        NotificationCenter.default.post(
            name: .editorCommandRequested,
            object: nil,
            userInfo: userInfo
        )
    }

    @discardableResult
    private func validationSaveCurrentEditorToFile(_ destinationURL: URL) -> Bool {
        let standardizedDestinationURL = destinationURL.standardizedFileURL
        if standaloneNoteWindowController?.window?.isVisible == true {
            let draftText = standaloneNoteDraftText
            let destinationKind = inferredFileBackedDocumentKind(for: standardizedDestinationURL)
            let preservedFrame = standaloneNoteWindowController?.window?.frame
            guard saveExternalEditorText(draftText, to: standardizedDestinationURL) else {
                return false
            }
            markStandaloneManualNoteSaved(text: draftText, destination: .file)
            dismissStandaloneManualNoteEditorWindow(copyToClipboard: false)
            openFileBackedEditor(
                for: standardizedDestinationURL,
                kind: destinationKind,
                initialText: draftText,
                preferredFrame: preservedFrame
            )
            return true
        }

        guard noteEditorWindowController?.window?.isVisible == true else {
            return false
        }

        let destinationKind = inferredFileBackedDocumentKind(
            for: standardizedDestinationURL,
            preferredKind: currentFileBackedDocumentKind
        )
        guard saveExternalEditorText(noteEditorDraftText, to: standardizedDestinationURL) else {
            return false
        }

        if !isCurrentExternalEditorCodex {
            if Self.shouldConvertManualNoteToFileBackedEditor(
                currentMode: noteEditorExternalMode,
                itemIDPresent: noteEditorItemID != nil
            ) {
                convertCurrentManualNoteEditorToFileBacked(
                    fileURL: standardizedDestinationURL,
                    kind: destinationKind
                )
            } else {
                noteEditorExternalFileURL = standardizedDestinationURL
                noteEditorExternalMode = Self.standaloneEditorModeAfterSavingFile(
                    currentMode: noteEditorExternalMode,
                    destinationKind: destinationKind
                )
                syncStandaloneNoteItemWithSavedFileTextIfNeeded(noteEditorDraftText)
                markCurrentNoteEditorSaved(text: noteEditorDraftText, destination: .file)
                noteEditorObservedFileModificationDate = fileModificationDate(for: standardizedDestinationURL)
                noteEditorObservedFileContentSnapshot = noteEditorDraftText
                noteEditorWindowController?.window?.representedURL = standardizedDestinationURL
                noteEditorWindowController?.window?.title = externalEditorWindowTitle(
                    for: standardizedDestinationURL,
                    kind: currentFileBackedDocumentKind,
                    isOrphaned: false,
                    codexContext: nil
                )
                fileLocalHistoryManager?.registerOpenedFile(standardizedDestinationURL)
                startExternalFileMonitorIfNeeded()
            }
        }
        return true
    }

    private func respondToValidationAttachedSheet(choice rawChoice: String) {
        if rawChoice.lowercased().hasPrefix("file:") {
            let path = String(rawChoice.dropFirst("file:".count))
            validationRespondToAttachedSheetSavingToFile(URL(fileURLWithPath: path))
            return
        }

        let response: NSApplication.ModalResponse
        switch rawChoice {
        case "1", "first":
            response = .alertFirstButtonReturn
        case "2", "second":
            response = .alertSecondButtonReturn
        case "3", "third":
            response = .alertThirdButtonReturn
        case "4", "fourth":
            response = NSApplication.ModalResponse(
                rawValue: NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 1
            )
        default:
            response = .cancel
        }

        let parentWindow = noteEditorWindowController?.window?.attachedSheet != nil
            ? noteEditorWindowController?.window
            : standaloneNoteWindowController?.window?.attachedSheet != nil
                ? standaloneNoteWindowController?.window
                : settingsWindowController?.window?.attachedSheet != nil
                    ? settingsWindowController?.window
                    : nil

        guard let parentWindow, let sheet = parentWindow.attachedSheet else {
            return
        }

        parentWindow.endSheet(sheet, returnCode: response)
        sheet.orderOut(nil)
        validationAttachedSheetContext = nil
    }
    
    private func translateCurrentContext() {
        guard let sourceText = textForTranslation() else {
            NSSound.beep()
            return
        }
        
        var components = URLComponents(string: "https://translate.google.com/")!
        components.queryItems = [
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: settings.translationTargetLanguage),
            URLQueryItem(name: "text", value: sourceText),
            URLQueryItem(name: "op", value: "translate")
        ]
        
        guard let url = components.url else {
            NSSound.beep()
            return
        }
        
        NSWorkspace.shared.open(url)
    }
    
    private func textForTranslation() -> String? {
        if panel.isVisible,
           let item = highlightedPanelItem,
           item.type == .text,
           let text = dataManager.resolvedText(for: item),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        
        if let selectedText = selectedTextFromFocusedElement(),
           !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return selectedText
        }
        
        if let clipboardText = NSPasteboard.general.string(forType: .string),
           !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return clipboardText
        }
        
        return nil
    }
    
    private func selectedTextFromFocusedElement() -> String? {
        guard let focusedElement = focusedElement() else {
            return nil
        }
        
        var selectedTextRef: CFTypeRef?
        let selectedTextResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedTextRef
        )
        
        guard selectedTextResult == .success else {
            return nil
        }
        
        return selectedTextRef as? String
    }

    private func focusedElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?

        let focusedResult = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )

        guard focusedResult == .success,
              let focusedElementRef,
              CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID() else {
            return nil
        }

        let element = (focusedElementRef as! AXUIElement)
        if let resolved = resolvedFocusableTextElement(from: element) {
            return resolved
        }
        if let window = focusedWindow(),
           let resolved = resolvedFocusableTextElement(from: window) {
            return resolved
        }
        if let application = focusedApplicationElement(),
           let resolved = resolvedFocusableTextElement(from: application) {
            return resolved
        }
        return element
    }

    private func focusedApplicationElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        return AXUIElementCreateApplication(app.processIdentifier)
    }

    private func resolvedFocusableTextElement(from element: AXUIElement) -> AXUIElement? {
        var visited: Set<UnsafeRawPointer> = []
        return resolvedFocusableTextElement(from: element, depth: 0, visited: &visited)
    }

    private func resolvedFocusableTextElement(
        from element: AXUIElement,
        depth: Int,
        visited: inout Set<UnsafeRawPointer>
    ) -> AXUIElement? {
        guard depth < 12 else { return nil }

        let opaque = UnsafeRawPointer(Unmanaged.passUnretained(element).toOpaque())
        guard visited.insert(opaque).inserted else { return nil }

        if isFocusedTextCandidate(element) {
            return element
        }

        if let explicitlyFocused = uiElementAttribute(kAXFocusedUIElementAttribute as CFString, of: element),
           explicitlyFocused != element,
           let resolved = resolvedFocusableTextElement(from: explicitlyFocused, depth: depth + 1, visited: &visited) {
            return resolved
        }

        let candidateAttributes: [CFString] = [
            kAXChildrenAttribute as CFString,
            kAXContentsAttribute as CFString
        ]

        for attribute in candidateAttributes {
            guard let children = uiElementArrayAttribute(attribute, of: element) else {
                continue
            }

            if let focusedChild = children.first(where: { boolAttribute(kAXFocusedAttribute as CFString, of: $0) == true }),
               let resolved = resolvedFocusableTextElement(from: focusedChild, depth: depth + 1, visited: &visited) {
                return resolved
            }

            for child in children {
                if let resolved = resolvedFocusableTextElement(from: child, depth: depth + 1, visited: &visited) {
                    return resolved
                }
            }
        }

        return nil
    }

    private func isFocusedTextCandidate(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(kAXRoleAttribute as CFString, of: element) ?? ""
        let isTextRole = role == kAXTextAreaRole as String
            || role == kAXTextFieldRole as String
            || role == "AXSearchField"
            || role == "AXWebArea"
            || role == "AXComboBox"

        let hasSelectionRange = selectedTextRange(of: element) != nil
        let hasInsertionLine = integerAttribute(kAXInsertionPointLineNumberAttribute as CFString, of: element) != nil
        let isFocused = boolAttribute(kAXFocusedAttribute as CFString, of: element) ?? false

        return (isTextRole || hasSelectionRange || hasInsertionLine) && isFocused
    }

    private func uiElementAttribute(_ attribute: CFString, of element: AXUIElement) -> AXUIElement? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)

        guard result == .success,
              let valueRef,
              CFGetTypeID(valueRef) == AXUIElementGetTypeID() else {
            return nil
        }

        return (valueRef as! AXUIElement)
    }

    private func uiElementArrayAttribute(_ attribute: CFString, of element: AXUIElement) -> [AXUIElement]? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard result == .success,
              let values = valueRef as? [Any] else {
            return nil
        }

        return values.compactMap { value in
            guard CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() else {
                return nil
            }
            return (value as! AXUIElement)
        }
    }

    private func stringAttribute(_ attribute: CFString, of element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard result == .success else {
            return nil
        }
        return valueRef as? String
    }

    private func integerAttribute(_ attribute: CFString, of element: AXUIElement) -> Int? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard result == .success,
              let number = valueRef as? NSNumber else {
            return nil
        }
        return number.intValue
    }

    private func boolAttribute(_ attribute: CFString, of element: AXUIElement) -> Bool? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard result == .success,
              let number = valueRef as? NSNumber else {
            return nil
        }
        return number.boolValue
    }

    private func focusedWindow() -> AXUIElement? {
        if let element = focusedElement(),
           let owningWindow = uiElementAttribute(kAXWindowAttribute as CFString, of: element) {
            return owningWindow
        }

        if let application = focusedApplicationElement(),
           let focusedWindow = uiElementAttribute(kAXFocusedWindowAttribute as CFString, of: application) {
            return focusedWindow
        }

        let systemWideElement = AXUIElementCreateSystemWide()
        return uiElementAttribute(kAXFocusedWindowAttribute as CFString, of: systemWideElement)
    }

    private func preferredPlacementTargetApp() -> NSRunningApplication? {
        let currentApp = NSRunningApplication.current
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let decision = TargetAppDecision(
            frontmostPID: frontmostApp?.processIdentifier,
            placementPID: placementTargetApp?.processIdentifier,
            previousPID: previouslyActiveApp?.processIdentifier,
            currentPID: currentApp.processIdentifier,
            frontmostTerminated: frontmostApp?.isTerminated ?? true,
            placementTerminated: placementTargetApp?.isTerminated ?? true,
            previousTerminated: previouslyActiveApp?.isTerminated ?? true
        )

        let targetPID = Self.preferredTargetPID(for: decision)
        if targetPID == frontmostApp?.processIdentifier {
            return frontmostApp
        }
        if targetPID == placementTargetApp?.processIdentifier {
            return placementTargetApp
        }
        if targetPID == previouslyActiveApp?.processIdentifier {
            return previouslyActiveApp
        }
        return nil
    }

    private func currentPlacementTargetApp() -> NSRunningApplication? {
        if let windowOwnerApp = frontmostWindowOwnerApp() {
            return windowOwnerApp
        }
        return preferredPlacementTargetApp()
    }

    func currentPasteTargetAppName() -> String? {
        resolvedPasteTargetApp()?.localizedName ?? currentPlacementTargetApp()?.localizedName
    }

    private func resolvedPasteTargetApp() -> NSRunningApplication? {
        if let previous = previouslyActiveApp,
           previous != NSRunningApplication.current,
           !previous.isTerminated {
            return previous
        }

        if let placement = placementTargetApp,
           placement != NSRunningApplication.current,
           !placement.isTerminated {
            return placement
        }

        return currentPlacementTargetApp()
    }

    private func frontmostWindowOwnerApp() -> NSRunningApplication? {
        let currentPID = NSRunningApplication.current.processIdentifier
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for windowInfo in windowList {
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != currentPID,
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let alpha = windowInfo[kCGWindowAlpha as String] as? Double,
                  alpha > 0,
                  let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                  !ownerName.isEmpty else {
                continue
            }

            if let app = NSRunningApplication(processIdentifier: ownerPID), !app.isTerminated {
                return app
            }
        }

        return nil
    }

    private func frontmostWindowFrame(for targetApp: NSRunningApplication?) -> CGRect? {
        guard let targetApp else {
            print("Panel placement: no target app")
            return nil
        }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            print("Panel placement: CGWindowListCopyWindowInfo returned nil")
            return nil
        }

        for windowInfo in windowList {
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == targetApp.processIdentifier,
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let boundsRef = windowInfo[kCGWindowBounds as String] else {
                continue
            }

            let rect: CGRect
            if let boundsDict = boundsRef as? NSDictionary,
                      let decoded = CGRect(dictionaryRepresentation: boundsDict) {
                rect = convertCGWindowBoundsToAppKitCoordinates(decoded)
            } else {
                print("Panel placement: failed to decode kCGWindowBounds for \(targetApp.localizedName ?? "unknown")")
                continue
            }

            if isUsableFallbackFrame(rect) {
                print("Panel placement fallback: app=\(targetApp.localizedName ?? "unknown") bounds=\(rect.debugDescription)")
                return rect
            }
        }

        print("Panel placement: no usable frontmost CGWindow frame for \(targetApp.localizedName ?? "unknown")")
        return nil
    }

    private func convertCGWindowBoundsToAppKitCoordinates(_ cgWindowBounds: CGRect) -> CGRect {
        let screens = NSScreen.screens
        guard let desktopMaxY = screens.map(\.frame.maxY).max() else {
            return cgWindowBounds
        }

        let convertedY = desktopMaxY - cgWindowBounds.minY - cgWindowBounds.height
        let converted = CGRect(
            x: cgWindowBounds.minX,
            y: convertedY,
            width: cgWindowBounds.width,
            height: cgWindowBounds.height
        )

        print("Panel placement convert: cg=\(cgWindowBounds.debugDescription) -> appKit=\(converted.debugDescription) desktopMaxY=\(desktopMaxY)")
        return converted
    }

    private func focusedInsertionRect() -> CGRect? {
        guard let focusedElement = focusedElement() else {
            return nil
        }
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        pendingAnchorDebugCandidates = []
        let focusedWindowFrame = focusedWindow().flatMap { frameForFocusedElement($0, focusedWindowFrame: nil) }
        let role = stringAttribute(kAXRoleAttribute as CFString, of: focusedElement) ?? "unknown"
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, of: focusedElement) ?? "-"
        let insertionLine = integerAttribute(kAXInsertionPointLineNumberAttribute as CFString, of: focusedElement)
        let appName = frontmostApp?.localizedName ?? "unknown"
        let bundleID = frontmostApp?.bundleIdentifier ?? "unknown"
        print("Frontmost app: \(appName) (\(bundleID))")
        if let focusedWindowFrame {
            print("Focused window frame: \(focusedWindowFrame.debugDescription)")
        } else {
            print("Focused window frame: unavailable")
        }
        if let insertionLine {
            print("Focused element role: \(role) subrole: \(subrole) insertionLine: \(insertionLine)")
        } else {
            print("Focused element role: \(role) subrole: \(subrole) insertionLine: unavailable")
        }

        if let caretRect = boundsForSelectedTextRange(of: focusedElement, focusedWindowFrame: focusedWindowFrame) {
            return caretRect
        }

        if let elementFrame = frameForFocusedElement(focusedElement, focusedWindowFrame: focusedWindowFrame),
           isUsableFallbackFrame(elementFrame) {
            let fallbackRect = fallbackInsertionRect(from: elementFrame)
            print("Caret anchor fallback: focused element frame \(elementFrame.debugDescription) -> \(fallbackRect.debugDescription)")
            return fallbackRect
        }

        if let focusedWindowFrame, isUsableFallbackFrame(focusedWindowFrame) {
            let fallbackRect = fallbackInsertionRect(from: focusedWindowFrame)
            print("Caret anchor fallback: focused window frame \(focusedWindowFrame.debugDescription) -> \(fallbackRect.debugDescription)")
            return fallbackRect
        }

        return nil
    }

    private func boundsForSelectedTextRange(of element: AXUIElement, focusedWindowFrame: CGRect?) -> CGRect? {
        guard let selectedRange = selectedTextRange(of: element) else {
            return nil
        }

        let insertionLine = selectedRange.length == 0
            ? integerAttribute(kAXInsertionPointLineNumberAttribute as CFString, of: element)
            : nil
        let lineBounds = insertionLine.flatMap {
            boundsForLine($0, of: element, focusedWindowFrame: focusedWindowFrame)
        }
        if let insertionLine, let lineBounds {
            print("Caret anchor line bounds: line \(insertionLine) -> \(lineBounds.debugDescription)")
            pendingAnchorDebugCandidates.append(
                AnchorDebugCandidate(
                    id: "line",
                    point: NSPoint(x: lineBounds.minX, y: lineBounds.midY),
                    label: "L",
                    color: .systemBlue,
                    isDraggable: false
                )
            )
        }

        if selectedRange.length == 0,
           let lineBounds,
           let positionalCaret = caretRectByPositionSearch(
                insertionLocation: selectedRange.location,
                lineBounds: lineBounds,
                of: element
           ) {
            pendingAnchorDebugCandidates.append(
                AnchorDebugCandidate(
                    id: "position",
                    point: NSPoint(x: positionalCaret.midX, y: positionalCaret.midY),
                    label: "P",
                    color: .systemPink,
                    isDraggable: false
                )
            )
            print("Caret anchor positional: selected range \(selectedRange.location),\(selectedRange.length) -> \(positionalCaret.debugDescription)")
            return positionalCaret
        }

        if let directBounds = boundsForRange(selectedRange, of: element, focusedWindowFrame: focusedWindowFrame) {
            if selectedRange.length == 0, isUsableAccessibilityBounds(directBounds) {
                let rawCaret = caretRect(from: directBounds, for: selectedRange)
                pendingAnchorDebugCandidates.append(
                    AnchorDebugCandidate(
                        id: "char",
                        point: NSPoint(x: rawCaret.midX, y: rawCaret.midY),
                        label: "C",
                        color: .systemYellow,
                        isDraggable: false
                    )
                )
                let synthesized = alignedCaretRect(from: rawCaret, lineBounds: lineBounds)
                print("Caret anchor direct: selected range \(selectedRange.location),\(selectedRange.length) -> \(synthesized.debugDescription)")
                return synthesized
            }
            if selectedRange.length > 0, isUsableAccessibilityBounds(directBounds) {
                pendingAnchorDebugCandidates.append(
                    AnchorDebugCandidate(
                        id: "selection",
                        point: NSPoint(x: directBounds.midX, y: directBounds.midY),
                        label: "S",
                        color: .systemGreen,
                        isDraggable: false
                    )
                )
                print("Caret anchor selection: selected range \(selectedRange.location),\(selectedRange.length) -> \(directBounds.debugDescription)")
                return normalizedAnchorRect(from: directBounds)
            }
            print("Caret anchor direct unusable: selected range \(selectedRange.location),\(selectedRange.length) -> \(directBounds.debugDescription)")
        }

        guard selectedRange.length == 0,
              let synthesizedBounds = synthesizedCaretRect(for: selectedRange, of: element, focusedWindowFrame: focusedWindowFrame) else {
            return nil
        }

        pendingAnchorDebugCandidates.append(
            AnchorDebugCandidate(
                id: "char",
                point: NSPoint(x: synthesizedBounds.midX, y: synthesizedBounds.midY),
                label: "C",
                color: .systemYellow,
                isDraggable: false
            )
        )
        let alignedBounds = alignedCaretRect(from: synthesizedBounds, lineBounds: lineBounds)
        print("Caret anchor synthesized: selected range \(selectedRange.location),\(selectedRange.length) -> \(alignedBounds.debugDescription)")
        return alignedBounds
    }

    private func selectedTextRange(of element: AXUIElement) -> CFRange? {
        var rangeRef: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        )

        guard rangeResult == .success,
              let rangeValue = rangeRef,
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }

        var selectedRange = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &selectedRange) else {
            return nil
        }

        return selectedRange
    }

    private func boundsForRange(_ range: CFRange, of element: AXUIElement, focusedWindowFrame: CGRect?) -> CGRect? {
        var mutableRange = range
        guard let axRange = AXValueCreate(.cfRange, &mutableRange) else {
            return nil
        }

        var boundsRef: CFTypeRef?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            axRange,
            &boundsRef
        )

        guard boundsResult == .success,
              let boundsValue = boundsRef,
              CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
            return nil
        }

        var axRect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &axRect) else {
            return nil
        }

        return normalizedAccessibilityRect(axRect, focusedWindowFrame: focusedWindowFrame)
    }

    private func boundsForLine(_ line: Int, of element: AXUIElement, focusedWindowFrame: CGRect?) -> CGRect? {
        var rangeRef: CFTypeRef?
        let rangeResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXRangeForLineParameterizedAttribute as CFString,
            NSNumber(value: line),
            &rangeRef
        )

        guard rangeResult == .success,
              let rangeValue = rangeRef,
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }

        var lineRange = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &lineRange) else {
            return nil
        }

        return boundsForRange(lineRange, of: element, focusedWindowFrame: focusedWindowFrame)
    }

    private func rangeForPosition(_ point: CGPoint, of element: AXUIElement) -> CFRange? {
        var mutablePoint = point
        guard let axPoint = AXValueCreate(.cgPoint, &mutablePoint) else {
            return nil
        }

        var rangeRef: CFTypeRef?
        let rangeResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXRangeForPositionParameterizedAttribute as CFString,
            axPoint,
            &rangeRef
        )

        guard rangeResult == .success,
              let rangeValue = rangeRef,
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else {
            return nil
        }
        return range
    }

    private func synthesizedCaretRect(for selectedRange: CFRange, of element: AXUIElement, focusedWindowFrame: CGRect?) -> CGRect? {
        let candidateRanges = candidateRangesAroundInsertionPoint(selectedRange)

        for candidate in candidateRanges {
            guard let characterBounds = boundsForRange(candidate, of: element, focusedWindowFrame: focusedWindowFrame),
                  isUsableAccessibilityBounds(characterBounds) else {
                continue
            }

            return caretRect(
                from: characterBounds,
                for: candidate,
                insertionLocation: selectedRange.location
            )
        }

        return nil
    }

    private func candidateRangesAroundInsertionPoint(_ selectedRange: CFRange) -> [CFRange] {
        guard selectedRange.length == 0 else {
            return [selectedRange]
        }

        var candidates: [CFRange] = [CFRange(location: selectedRange.location, length: 1)]
        if selectedRange.location > 0 {
            candidates.append(CFRange(location: selectedRange.location - 1, length: 1))
        }
        return candidates
    }

    private func caretRectByPositionSearch(
        insertionLocation: Int,
        lineBounds: CGRect,
        of element: AXUIElement
    ) -> CGRect? {
        guard lineBounds.width >= 8, lineBounds.height >= 8 else {
            return nil
        }

        let y = lineBounds.midY
        let minX = lineBounds.minX + 1
        let maxX = lineBounds.maxX - 1
        guard minX < maxX else {
            return nil
        }

        func location(atX x: CGFloat) -> Int? {
            rangeForPosition(CGPoint(x: x, y: y), of: element)?.location
        }

        let stepCount = max(6, min(40, Int(lineBounds.width / 8)))
        var samples: [(x: CGFloat, location: Int)] = []
        for step in 0...stepCount {
            let progress = CGFloat(step) / CGFloat(stepCount)
            let x = minX + ((maxX - minX) * progress)
            if let location = location(atX: x) {
                samples.append((x, location))
            }
        }

        guard !samples.isEmpty else {
            return nil
        }

        if let firstAtOrAfter = samples.first(where: { $0.location >= insertionLocation }) {
            var low = minX
            var high = firstAtOrAfter.x
            for _ in 0..<18 {
                let mid = (low + high) / 2
                guard let midLocation = location(atX: mid) else {
                    break
                }
                if midLocation >= insertionLocation {
                    high = mid
                } else {
                    low = mid
                }
            }
            return CGRect(
                x: high - 2,
                y: lineBounds.minY,
                width: 4,
                height: max(lineBounds.height, 16)
            )
        }

        if let lastBefore = samples.last(where: { $0.location < insertionLocation }) {
            var low = lastBefore.x
            var high = maxX
            for _ in 0..<18 {
                let mid = (low + high) / 2
                guard let midLocation = location(atX: mid) else {
                    break
                }
                if midLocation < insertionLocation {
                    low = mid
                } else {
                    high = mid
                }
            }
            return CGRect(
                x: low - 2,
                y: lineBounds.minY,
                width: 4,
                height: max(lineBounds.height, 16)
            )
        }

        return nil
    }

    private func caretRect(
        from bounds: CGRect,
        for range: CFRange,
        insertionLocation: Int? = nil
    ) -> CGRect {
        let width = max(2, min(4, bounds.width))
        let resolvedInsertionLocation = insertionLocation ?? range.location
        let x: CGFloat

        if range.location < resolvedInsertionLocation {
            x = bounds.maxX - (width / 2)
        } else {
            x = bounds.minX - (width / 2)
        }

        return CGRect(
            x: x,
            y: bounds.minY,
            width: width,
            height: max(bounds.height, 16)
        )
    }

    private func alignedCaretRect(from caret: CGRect, lineBounds: CGRect?) -> CGRect {
        guard let lineBounds, isUsableAccessibilityBounds(lineBounds) else {
            return caret
        }

        return CGRect(
            x: caret.minX,
            y: lineBounds.minY,
            width: caret.width,
            height: max(lineBounds.height, caret.height)
        )
    }

    private func normalizedAnchorRect(from rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: rect.minY,
            width: max(rect.width, 36),
            height: max(rect.height, 18)
        )
    }

    private func fallbackInsertionRect(from frame: CGRect) -> CGRect {
        let height = min(22, max(16, frame.height * 0.08))
        let width: CGFloat = 18

        return CGRect(
            x: frame.midX - (width / 2),
            y: frame.maxY - height - 24,
            width: width,
            height: height
        )
    }

    private func isUsableAccessibilityBounds(_ rect: CGRect) -> Bool {
        rect.width >= 1 && rect.height >= 1
    }

    private func isUsableFallbackFrame(_ rect: CGRect) -> Bool {
        rect.width >= 80 && rect.height >= 40
    }

    private func frameForFocusedElement(_ element: AXUIElement, focusedWindowFrame: CGRect?) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef,
              let sizeValue = sizeRef,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        return normalizedAccessibilityRect(CGRect(origin: point, size: size), focusedWindowFrame: focusedWindowFrame)
    }

    private func normalizedAccessibilityRect(_ axRect: CGRect, focusedWindowFrame: CGRect?) -> CGRect {
        let rawRect = axRect

        guard let focusedWindowFrame else {
            print("Caret anchor normalize: raw=\(rawRect.debugDescription)")
            return rawRect
        }

        let adjustedRect = CGRect(
            x: focusedWindowFrame.minX + rawRect.minX,
            y: focusedWindowFrame.minY + rawRect.minY,
            width: rawRect.width,
            height: rawRect.height
        )

        let rawInsideWindow = focusedWindowFrame.intersects(rawRect)
        let adjustedInsideWindow = focusedWindowFrame.intersects(adjustedRect)
        let resolvedRect = (!rawInsideWindow && adjustedInsideWindow) ? adjustedRect : rawRect

        print("Caret anchor normalize: raw=\(rawRect.debugDescription) adjusted=\(adjustedRect.debugDescription) window=\(focusedWindowFrame.debugDescription) -> \(resolvedRect.debugDescription)")
        return resolvedRect
    }

    private func screen(containing rect: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        let bestByIntersection = screens.max { lhs, rhs in
            lhs.frame.intersection(rect).area < rhs.frame.intersection(rect).area
        }

        if let bestByIntersection,
           bestByIntersection.frame.intersection(rect).area > 0 {
            return bestByIntersection
        }

        let midPoint = NSPoint(x: rect.midX, y: rect.midY)
        return screens.first { $0.frame.contains(midPoint) } ?? NSScreen.main
    }

    private func clamped(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minValue), maxValue)
    }

    private func showAnchorDebugMarkers(_ candidates: [AnchorDebugCandidate], fallbackPoint: NSPoint, description: String) {
        anchorDebugHideTask?.cancel()
        let resolvedCandidates = candidates.isEmpty
            ? [AnchorDebugCandidate(id: "final", point: fallbackPoint, label: "F", color: .systemRed, isDraggable: true)]
            : candidates

        let markerSize = NSSize(width: 42, height: 42)
        var activeIDs = Set<String>()

        for candidate in resolvedCandidates {
            activeIDs.insert(candidate.id)
            let frame = NSRect(
                x: candidate.point.x - (markerSize.width / 2),
                y: candidate.point.y - (markerSize.height / 2),
                width: markerSize.width,
                height: markerSize.height
            )

            let window: NSWindow
            if let existing = anchorDebugWindows[candidate.id] {
                window = existing
            } else {
                let createdWindow = NSWindow(
                    contentRect: frame,
                    styleMask: .borderless,
                    backing: .buffered,
                    defer: false
                )
                createdWindow.isOpaque = false
                createdWindow.backgroundColor = .clear
                createdWindow.hasShadow = false
                createdWindow.level = .floating
                createdWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                createdWindow.contentView = AnchorDebugView(frame: NSRect(origin: .zero, size: markerSize))
                anchorDebugWindows[candidate.id] = createdWindow
                window = createdWindow
            }

            window.setFrame(frame, display: true)
            if let debugView = window.contentView as? AnchorDebugView {
                debugView.label = candidate.label
                debugView.referencePoint = candidate.point
                debugView.strokeColor = candidate.color
                debugView.isDraggable = candidate.isDraggable
                debugView.onDragEnded = candidate.isDraggable
                    ? { [weak self] correctedPoint in self?.handleAnchorDebugDragEnded(correctedPoint) }
                    : nil
            }
            window.orderFrontRegardless()
        }

        for (id, window) in anchorDebugWindows where !activeIDs.contains(id) {
            window.orderOut(nil)
        }

        lastAnchorPoint = fallbackPoint
        print("Anchor debug markers: \(resolvedCandidates.map { "\($0.label)=\(Int($0.point.x)),\(Int($0.point.y))" }.joined(separator: " ")) \(description)")
    }

    private func hideAnchorDebugMarker() {
        anchorDebugHideTask?.cancel()
        anchorDebugHideTask = nil
        for window in anchorDebugWindows.values {
            window.orderOut(nil)
        }
    }

    private func handleAnchorDebugDragEnded(_ correctedPoint: NSPoint) {
        guard let lastAnchorPoint else {
            print("Anchor debug corrected point: (\(Int(correctedPoint.x)), \(Int(correctedPoint.y)))")
            return
        }

        let deltaX = Int(correctedPoint.x - lastAnchorPoint.x)
        let deltaY = Int(correctedPoint.y - lastAnchorPoint.y)
        print(
            "Anchor debug corrected point: original=(\(Int(lastAnchorPoint.x)), \(Int(lastAnchorPoint.y))) corrected=(\(Int(correctedPoint.x)), \(Int(correctedPoint.y))) delta=(\(deltaX), \(deltaY))"
        )
    }

    private func preferredPanelSize() -> NSSize {
        let defaults = UserDefaults.standard
        let width = defaults.object(forKey: WindowDefaultsKey.width) as? Double
        let height = defaults.object(forKey: WindowDefaultsKey.height) as? Double

        return NSSize(
            width: max(260, CGFloat(width ?? Double(Layout.panelWidth))),
            height: max(320, CGFloat(height ?? Double(Layout.panelHeight)))
        )
    }

    private func hasPersistedPanelSize() -> Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: WindowDefaultsKey.width) != nil
            || defaults.object(forKey: WindowDefaultsKey.height) != nil
    }

    private func persistPanelSize(_ size: NSSize) {
        UserDefaults.standard.set(Double(size.width), forKey: WindowDefaultsKey.width)
        UserDefaults.standard.set(Double(size.height), forKey: WindowDefaultsKey.height)
    }
    private func saveSettings() {
        settingsStore.save(settings)
    }

    private func mutateSettings(_ mutate: (inout AppSettings) -> Void) {
        var updated = settings
        mutate(&updated)
        settings = updated
    }

    func updateSettingsLanguage(_ language: SettingsLanguage) {
        guard settings.settingsLanguage != language else { return }
        mutateSettings { $0.settingsLanguage = language }
        saveSettings()
    }

    func updateInterfaceThemePreset(_ preset: InterfaceThemePreset) {
        guard settings.interfaceThemePreset != preset else { return }
        let previousSettings = settings
        mutateSettings { $0.interfaceThemePreset = preset }
        saveSettings()
        refreshVisibleWindowsAfterApplyingSettings(from: previousSettings, to: settings)
    }

    func increaseInterfaceZoom() {
        updateInterfaceZoom(settings.interfaceZoomScale + 0.1)
    }

    func decreaseInterfaceZoom() {
        updateInterfaceZoom(settings.interfaceZoomScale - 0.1)
    }

    func resetInterfaceZoom() {
        updateInterfaceZoom(AppSettings.defaultInterfaceZoomScale)
    }

    private func updateInterfaceZoom(_ proposedScale: Double) {
        let clamped = min(AppSettings.maxInterfaceZoomScale, max(AppSettings.minInterfaceZoomScale, proposedScale))
        guard abs(settings.interfaceZoomScale - clamped) > 0.001 else { return }
        mutateSettings { $0.interfaceZoomScale = clamped }
        saveSettings()
    }

    private func shortcutsAreUnique(_ shortcuts: [HotKeyManager.Shortcut]) -> Bool {
        let ids = shortcuts.map { "\($0.keyCode):\($0.modifiers)" }
        return Set(ids).count == ids.count
    }

    private func validateShortcutScopes(in draft: AppSettings) throws {
        let baseGlobalShortcuts = [
            draft.panelShortcut,
            draft.translationShortcut
        ] + [
            draft.globalNewNoteShortcut
        ].compactMap { $0 }
        let enabledGlobalCopyShortcuts = [
            draft.globalCopyJoinedEnabled ? draft.globalCopyJoinedShortcut : nil,
            draft.globalCopyNormalizedEnabled ? draft.globalCopyNormalizedShortcut : nil
        ].compactMap { $0 }
        let globalShortcuts = baseGlobalShortcuts + enabledGlobalCopyShortcuts
        let standardPanelShortcuts = [
            draft.newNoteShortcut,
            draft.togglePinShortcut,
            draft.togglePinnedAreaShortcut,
            draft.editTextShortcut,
            draft.deleteItemShortcut,
            draft.undoShortcut,
            draft.redoShortcut,
            draft.copyJoinedShortcut,
            draft.copyNormalizedShortcut
        ]
        let editorShortcuts = [
            draft.commitEditShortcut,
            draft.indentShortcut,
            draft.outdentShortcut,
            draft.moveLineUpShortcut,
            draft.moveLineDownShortcut,
            draft.toggleMarkdownPreviewShortcut,
            draft.joinLinesShortcut,
            draft.normalizeForCommandShortcut
        ]
        let codexShortcuts = [
            draft.orphanCodexDiscardShortcut
        ]

        guard shortcutsAreUnique(globalShortcuts),
              shortcutsAreUnique(standardPanelShortcuts),
              shortcutsAreUnique(editorShortcuts),
              shortcutsAreUnique(codexShortcuts) else {
            throw SettingsMutationError.duplicateShortcut
        }

        let localShortcuts = standardPanelShortcuts + editorShortcuts
        let localIdentifiers = Set(localShortcuts.map { "\($0.keyCode):\($0.modifiers)" })
        let exemptGlobalIdentifiers = Set([
            draft.globalCopyJoinedEnabled ? draft.globalCopyJoinedShortcut : nil,
            draft.globalCopyNormalizedEnabled ? draft.globalCopyNormalizedShortcut : nil
        ].compactMap { $0 }.map { "\($0.keyCode):\($0.modifiers)" })

        if globalShortcuts.contains(where: {
            let identifier = "\($0.keyCode):\($0.modifiers)"
            return !exemptGlobalIdentifiers.contains(identifier) && localIdentifiers.contains(identifier)
        }) {
            throw SettingsMutationError.duplicateShortcut
        }
    }

    func applySettingsDraft(_ draft: AppSettings) throws {
        try validateShortcutScopes(in: draft)

        try validateGlobalHotKeyAvailability(
            panelShortcut: draft.panelShortcut,
            translationShortcut: draft.translationShortcut,
            additionalShortcuts: [
                ("New Note", draft.globalNewNoteShortcut),
                ("Copy Joined", draft.globalCopyJoinedEnabled ? draft.globalCopyJoinedShortcut : nil),
                ("Copy Normalized", draft.globalCopyNormalizedEnabled ? draft.globalCopyNormalizedShortcut : nil)
            ]
        )

        if settings.launchAtLogin != draft.launchAtLogin {
            try updateLaunchAtLogin(draft.launchAtLogin)
        }

        let sanitizedTranslationTarget = SupportedTranslationLanguages.contains(code: draft.translationTargetLanguage)
            ? draft.translationTargetLanguage
            : settings.translationTargetLanguage
        let sanitizedHistoryLimit = max(1, draft.historyLimit)
        let previousSettings = settings

        mutateSettings { settings in
            settings.settingsLanguage = draft.settingsLanguage
            settings.translationTargetLanguage = sanitizedTranslationTarget
            settings.historyLimit = sanitizedHistoryLimit
            settings.globalNewNoteShortcut = draft.globalNewNoteShortcut
            settings.globalCopyJoinedShortcut = draft.globalCopyJoinedShortcut
            settings.globalCopyNormalizedShortcut = draft.globalCopyNormalizedShortcut
            settings.globalCopyJoinedEnabled = draft.globalCopyJoinedEnabled
            settings.globalCopyNormalizedEnabled = draft.globalCopyNormalizedEnabled
            settings.newNoteShortcut = draft.newNoteShortcut
            settings.togglePinShortcut = draft.togglePinShortcut
            settings.togglePinnedAreaShortcut = draft.togglePinnedAreaShortcut
            settings.editTextShortcut = draft.editTextShortcut
            settings.commitEditShortcut = draft.commitEditShortcut
            settings.deleteItemShortcut = draft.deleteItemShortcut
            settings.undoShortcut = draft.undoShortcut
            settings.redoShortcut = draft.redoShortcut
            settings.indentShortcut = draft.indentShortcut
            settings.outdentShortcut = draft.outdentShortcut
            settings.moveLineUpShortcut = draft.moveLineUpShortcut
            settings.moveLineDownShortcut = draft.moveLineDownShortcut
            settings.copyJoinedShortcut = draft.copyJoinedShortcut
            settings.copyNormalizedShortcut = draft.copyNormalizedShortcut
            settings.toggleMarkdownPreviewShortcut = draft.toggleMarkdownPreviewShortcut
            settings.joinLinesShortcut = draft.joinLinesShortcut
            settings.normalizeForCommandShortcut = draft.normalizeForCommandShortcut
            settings.orphanCodexDiscardShortcut = draft.orphanCodexDiscardShortcut
            settings.interfaceZoomScale = draft.clampedInterfaceZoomScale
            settings.newNoteReopenBehavior = draft.newNoteReopenBehavior
            settings.interfaceThemePreset = draft.interfaceThemePreset
            settings.localFileHistoryEnabled = draft.localFileHistoryEnabled
            settings.localFileHistoryTrackOpenedFiles = draft.localFileHistoryTrackOpenedFiles
            settings.localFileHistoryWatchedDirectoryPath = draft.localFileHistoryWatchedDirectoryPath
            settings.localFileHistoryWatchedExtensions = draft.localFileHistoryWatchedExtensions
            settings.localFileHistoryWatchRecursively = draft.localFileHistoryWatchRecursively
            settings.localFileHistoryMaxSnapshotsPerFile = max(1, draft.localFileHistoryMaxSnapshotsPerFile)
            settings.localFileHistoryDeletedSourceBehavior = draft.localFileHistoryDeletedSourceBehavior
            settings.localFileHistoryOrphanGracePeriodDays = max(1, draft.localFileHistoryOrphanGracePeriodDays)
            settings.localFileHistoryConfirmDestructiveActions = draft.localFileHistoryConfirmDestructiveActions
        }
        dataManager?.updateMaxHistoryItems(sanitizedHistoryLimit)

        applyPanelShortcut(draft.panelShortcut)
        applyTranslationShortcut(draft.translationShortcut)
        saveSettings()
        applyLocalFileHistorySettings()
        refreshVisibleWindowsAfterApplyingSettings(from: previousSettings, to: settings)
    }

    private func applyLocalFileHistorySettings() {
        guard Self.shouldStartLocalHistoryServices(isRunningAutomatedTests: Self.isRunningAutomatedTests) else {
            return
        }
        let manager = fileLocalHistoryManager ?? FileLocalHistoryManager(storePaths: storePaths)
        fileLocalHistoryManager = manager
        manager.apply(
            settings: FileLocalHistoryManager.Settings(
                isEnabled: settings.localFileHistoryEnabled,
                trackOpenedFiles: settings.localFileHistoryTrackOpenedFiles,
                watchedDirectoryPath: settings.localFileHistoryWatchedDirectoryPath,
                watchedExtensions: settings.localFileHistoryWatchedExtensions,
                watchDirectoryRecursively: settings.localFileHistoryWatchRecursively,
                maxSnapshotsPerFile: settings.localFileHistoryMaxSnapshotsPerFile,
                deletedSourceBehavior: settings.localFileHistoryDeletedSourceBehavior,
                orphanGracePeriodDays: settings.localFileHistoryOrphanGracePeriodDays,
                pollingInterval: FileLocalHistoryManager.Settings.default.pollingInterval
            )
        )
        registerCurrentEditorForLocalHistoryIfNeeded()
    }

    private func registerCurrentEditorForLocalHistoryIfNeeded() {
        guard Self.shouldBootstrapCurrentEditorOpenedFileTracking(
            isEnabled: settings.localFileHistoryEnabled,
            trackOpenedFiles: settings.localFileHistoryTrackOpenedFiles,
            externalMode: noteEditorExternalMode,
            hasFileURL: noteEditorExternalFileURL != nil,
            isOrphanedCodexDraft: noteEditorIsOrphanedCodexDraft
        ),
        let fileURL = noteEditorExternalFileURL?.standardizedFileURL else {
            return
        }

        fileLocalHistoryManager?.registerOpenedFile(fileURL)
    }

    private func refreshVisibleWindowsAfterApplyingSettings(from previousSettings: AppSettings, to currentSettings: AppSettings) {
        let shouldRebuildVisibleWindows =
            previousSettings.interfaceThemePreset != currentSettings.interfaceThemePreset ||
            abs(previousSettings.clampedInterfaceZoomScale - currentSettings.clampedInterfaceZoomScale) > 0.001 ||
            previousSettings.settingsLanguage != currentSettings.settingsLanguage

        guard shouldRebuildVisibleWindows else { return }

        let panelWasVisible = panel.isVisible
        let panelFrame = panel.frame
        let helpWasVisible = helpPanel?.isVisible == true
        let settingsWasVisible = settingsWindowController?.window?.isVisible == true
        let standaloneNoteWasVisible = standaloneNoteWindowController?.window?.isVisible == true
        let standaloneNoteFrame = standaloneNoteWindowController?.window?.frame
        let standaloneItemID = standaloneNoteItemID
        let standaloneDraft = standaloneNoteDraftText
        let standaloneLastPersistedText = standaloneNoteLastPersistedText
        let standaloneIsPlaceholder = standaloneNoteIsPlaceholderManualNote
        let standaloneLastSaveDestination = standaloneNoteSaveStatus.lastSaveDestination
        let noteWasVisible = noteEditorWindowController?.window?.isVisible == true
        let noteFrame = noteEditorWindowController?.window?.frame
        let noteItemID = noteEditorItemID
        let noteExternalFileURL = noteEditorExternalFileURL
        let noteExternalMode = noteEditorExternalMode
        let noteDraft = noteEditorDraftText
        let noteLastPersistedText = noteEditorLastPersistedText
        let noteLastSaveDestination = externalEditorSaveStatus.lastSaveDestination
        let noteIsOrphanedCodexDraft = noteEditorIsOrphanedCodexDraft
        let noteIsPlaceholderManualNote = noteEditorIsPlaceholderManualNote
        let noteCodexSessionID = noteEditorCodexSessionID
        let noteCodexProjectRootURL = noteEditorCodexProjectRootURL
        let notePreviewVisible = noteEditorMarkdownPreviewVisible
        let noteHistoryVisible = noteEditorHistoryPaneVisible

        if let itemID = standaloneItemID, standaloneNoteWasVisible {
            _ = dataManager.updateTextContent(standaloneDraft, for: itemID)
        }

        if let itemID = noteItemID, noteWasVisible {
            _ = dataManager.updateTextContent(noteDraft, for: itemID)
        }

        if panelWasVisible {
            panel.orderOut(nil)
            panel.contentView = NSHostingView(rootView: makePanelRootView())
        }

        if let helpPanel,
           let hostingController = helpPanel.contentViewController as? NSHostingController<ClipboardHelpPanelContent> {
            helpPanel.orderOut(nil)
            hostingController.rootView = ClipboardHelpPanelContent(
                settings: settings,
                isEditingSelectedText: false,
                onClose: { [weak self] in
                    self?.closeHelpPanel(refocusClipboardPanel: true)
                }
            )
        }

        if settingsWasVisible, let settingsWindow = settingsWindowController?.window {
            settingsWindow.orderOut(nil)
            let rootView = SettingsView(appDelegate: self)
                .modelContainer(sharedContainer)
            settingsWindow.contentViewController = NSHostingController(rootView: rootView)
        }

        if standaloneNoteWasVisible, let itemID = standaloneItemID {
            standaloneNoteWindowController?.window?.orderOut(nil)
            standaloneNoteWindowController = nil
            standaloneNoteItemID = itemID
            standaloneNoteDraftText = standaloneDraft
            let controller = makeNoteEditorWindowController(
                itemID: itemID,
                isPlaceholderManualNote: standaloneIsPlaceholder
            )
            standaloneNoteLastPersistedText = standaloneLastPersistedText
            standaloneNoteSaveStatus.lastPersistedText = standaloneLastPersistedText
            standaloneNoteSaveStatus.lastSaveDestination = standaloneLastSaveDestination
            if let standaloneNoteFrame, let window = controller.window {
                window.setFrame(standaloneNoteFrame, display: false)
            }
        }

        if noteWasVisible, let itemID = noteItemID {
            noteEditorWindowController?.window?.orderOut(nil)
            noteEditorWindowController = nil
            noteEditorItemID = itemID
            noteEditorDraftText = noteDraft
            let controller = makeNoteEditorWindowController(
                itemID: itemID,
                isPlaceholderManualNote: noteIsPlaceholderManualNote
            )
            if let noteFrame, let window = controller.window {
                window.setFrame(noteFrame, display: false)
            }
        } else if noteWasVisible, noteExternalMode?.fileKind != nil || noteExternalFileURL != nil {
            noteEditorWindowController?.window?.orderOut(nil)
            noteEditorWindowController = nil
            let controller: NSWindowController
            if let fileKind = noteExternalMode?.fileKind {
                controller = makeFileBackedEditorWindowController(
                    fileURL: noteExternalFileURL,
                    initialText: noteDraft,
                    kind: fileKind,
                    initialPreviewVisible: notePreviewVisible,
                    initialHistoryVisible: noteHistoryVisible
                )
            } else {
                guard let externalFileURL = noteExternalFileURL else { return }
                controller = makeExternalFileEditorWindowController(
                    fileURL: externalFileURL,
                    initialText: noteDraft,
                    isOrphaned: noteIsOrphanedCodexDraft,
                    codexContext: noteCodexSessionID.map {
                        CodexDraftContext(sessionID: $0, projectRootURL: noteCodexProjectRootURL)
                    },
                    initialPreviewVisible: notePreviewVisible,
                    initialHistoryVisible: noteHistoryVisible
                )
            }
            noteEditorLastPersistedText = noteLastPersistedText
            externalEditorSaveStatus.lastPersistedText = noteLastPersistedText
            externalEditorSaveStatus.lastSaveDestination = noteLastSaveDestination
            if let noteFrame, let window = controller.window {
                window.setFrame(noteFrame, display: false)
            }
            if noteExternalMode?.isCodex == true, !noteIsOrphanedCodexDraft {
                startCodexSessionStateMonitor()
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if panelWasVisible {
                self.panel.setFrame(panelFrame, display: false)
                self.panel.orderFrontRegardless()
                self.panel.makeKeyAndOrderFront(nil)
            }
            if helpWasVisible {
                self.showHelpPanel(isEditingSelectedText: false)
            }
            if settingsWasVisible {
                self.settingsWindowController?.showWindow(nil)
                self.settingsWindowController?.window?.makeKeyAndOrderFront(nil)
            }
            if standaloneNoteWasVisible {
                self.standaloneNoteWindowController?.showWindow(nil)
                self.standaloneNoteWindowController?.window?.orderFront(nil)
                self.standaloneNoteWindowController?.window?.makeKeyAndOrderFront(nil)
            }
            if noteWasVisible {
                self.noteEditorWindowController?.showWindow(nil)
                self.noteEditorWindowController?.window?.orderFront(nil)
                self.noteEditorWindowController?.window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    func updateHistoryLimit(_ historyLimit: Int) {
        let sanitizedLimit = max(1, historyLimit)
        guard settings.historyLimit != sanitizedLimit else { return }

        mutateSettings { $0.historyLimit = sanitizedLimit }
        dataManager?.updateMaxHistoryItems(sanitizedLimit)
        saveSettings()
    }

    func updateTranslationTargetLanguage(_ languageCode: String) {
        guard SupportedTranslationLanguages.contains(code: languageCode) else { return }
        guard settings.translationTargetLanguage != languageCode else { return }

        mutateSettings { $0.translationTargetLanguage = languageCode }
        saveSettings()
    }

    func resetPanelShortcutToDefault() {
        applyPanelShortcut(AppSettings.default.panelShortcut)
    }

    func resetTranslationShortcutToDefault() {
        applyTranslationShortcut(AppSettings.default.translationShortcut)
    }

    func updatePanelShortcut(from input: String) throws {
        let shortcut = try parseShortcutInput(input)
        guard shortcut != translateHotKeyShortcut else {
            throw SettingsMutationError.duplicateShortcut
        }
        applyPanelShortcut(shortcut)
    }

    func updateTranslationShortcut(from input: String) throws {
        let shortcut = try parseShortcutInput(input)
        guard shortcut != panelHotKeyShortcut else {
            throw SettingsMutationError.duplicateShortcut
        }
        applyTranslationShortcut(shortcut)
    }

    func updateLaunchAtLogin(_ isEnabled: Bool) throws {
        guard settings.launchAtLogin != isEnabled else { return }

        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            let status = service.status

            if isEnabled {
                if status == .enabled || status == .requiresApproval {
                    mutateSettings { $0.launchAtLogin = true }
                    saveSettings()
                    return
                }
                do {
                    try service.register()
                } catch {
                    throw SettingsMutationError.launchAtLoginUnavailable(error.localizedDescription)
                }
            } else {
                if status == .notRegistered {
                    mutateSettings { $0.launchAtLogin = false }
                    saveSettings()
                    return
                }
                do {
                    try service.unregister()
                } catch {
                    throw SettingsMutationError.launchAtLoginUnavailable(error.localizedDescription)
                }
            }

            mutateSettings { $0.launchAtLogin = isEnabled }
            saveSettings()
            return
        }

        throw SettingsMutationError.launchAtLoginUnavailable("Launch at login requires macOS 13 or later.")
    }

    func openSettingsWindow() {
        let panelWasVisible = panel.isVisible
        suppressPanelAutoClose = panelWasVisible
        suspendGlobalHotKeys()
        NSApp.activate(ignoringOtherApps: true)
        let controller = makeSettingsWindowController()
        if let window = controller.window {
            let desiredFrame: NSRect
            if panelWasVisible {
                let screen = screen(containing: panel.frame) ?? panel.screen ?? NSScreen.main
                let visibleFrame = (screen?.visibleFrame ?? window.frame).insetBy(dx: Layout.screenMargin, dy: Layout.screenMargin)
                desiredFrame = Self.auxiliaryWindowPlacement(
                    anchorFrame: panel.frame,
                    visibleFrame: visibleFrame,
                    windowSize: window.frame.size,
                    gap: 16
                )
            } else {
                let screen = NSScreen.main
                let visibleFrame = (screen?.visibleFrame ?? window.frame).insetBy(dx: Layout.screenMargin, dy: Layout.screenMargin)
                desiredFrame = NSRect(
                    x: visibleFrame.midX - (window.frame.width / 2),
                    y: visibleFrame.midY - (window.frame.height / 2),
                    width: window.frame.width,
                    height: window.frame.height
                )
            }
            window.setFrame(desiredFrame, display: false)
        }
        controller.showWindow(nil)
        controller.window?.orderFrontRegardless()
        controller.window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.suppressPanelAutoClose = false
        }
    }

    private var isCurrentExternalEditorCodex: Bool {
        noteEditorExternalMode?.isCodex == true
    }

    private var currentFileBackedDocumentKind: FileBackedDocumentKind? {
        noteEditorExternalMode?.fileKind
    }

    private var isCurrentEditorFileBacked: Bool {
        currentFileBackedDocumentKind != nil
    }

    private var currentLocalHistoryFileURL: URL? {
        guard Self.supportsStandaloneEditorLocalHistory(
            externalMode: noteEditorExternalMode,
            hasFileURL: noteEditorExternalFileURL != nil,
            isOrphanedCodexDraft: noteEditorIsOrphanedCodexDraft
        ) else {
            return nil
        }
        return noteEditorExternalFileURL?.standardizedFileURL
    }

    private var noteEditorHasUnsavedFileChanges: Bool {
        isCurrentEditorFileBacked && noteEditorDraftText != noteEditorLastPersistedText
    }

    private func inferredFileBackedDocumentKind(for fileURL: URL, preferredKind: FileBackedDocumentKind? = nil) -> FileBackedDocumentKind {
        if let preferredKind {
            return preferredKind
        }

        switch fileURL.pathExtension.lowercased() {
        case "md", "markdown", "mdown", "mkd":
            return .markdown
        default:
            return .text
        }
    }

    private func readPlainTextDocument(at fileURL: URL, preferredKind: FileBackedDocumentKind? = nil) -> (kind: FileBackedDocumentKind, text: String)? {
        var encoding = String.Encoding.utf8
        guard let text = try? String(contentsOf: fileURL, usedEncoding: &encoding) else {
            return nil
        }
        return (inferredFileBackedDocumentKind(for: fileURL, preferredKind: preferredKind), text)
    }

    @discardableResult
    private func openTextDocumentFromSystem(for fileURL: URL) -> Bool {
        guard let document = readPlainTextDocument(at: fileURL) else {
            presentPlainTextOpenFailure(for: fileURL)
            return false
        }
        NSApp.unhide(nil)
        promoteAppForExternalEditorIfNeeded()
        openFileBackedEditor(for: fileURL, kind: document.kind, initialText: document.text)
        return true
    }

    private func openTextDocumentViaPanel(preferredKind: FileBackedDocumentKind? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        switch preferredKind {
        case .markdown:
            panel.prompt = uiText("Open Markdown", "Markdown を開く")
            panel.allowedFileTypes = ["md", "markdown", "mdown", "mkd"]
        case .text:
            panel.prompt = uiText("Open Text", "テキストを開く")
        case nil:
            panel.prompt = uiText("Open File", "ファイルを開く")
        }

        guard panel.runModal() == .OK, let fileURL = panel.url else {
            return
        }

        guard let document = readPlainTextDocument(at: fileURL, preferredKind: preferredKind) else {
            presentPlainTextOpenFailure(for: fileURL)
            return
        }
        openFileBackedEditor(for: fileURL, kind: document.kind, initialText: document.text)
    }

    private func presentPlainTextOpenFailure(for fileURL: URL) {
        let alert = NSAlert()
        alert.messageText = uiText("Could not open text file", "テキストファイルを開けませんでした")
        alert.informativeText = uiText(
            "\(fileURL.lastPathComponent) could not be decoded as plain text.",
            "\(fileURL.lastPathComponent) をプレーンテキストとして読み込めませんでした。"
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func openUntitledFileBackedEditor(kind: FileBackedDocumentKind) {
        requestStandaloneEditorReplacement { [weak self] canOpen in
            guard let self, canOpen else { return }
            self.noteEditorExternalFileURL = nil
            self.noteEditorExternalMode = .fileBacked(kind)
            self.noteEditorCompletionMarkerURL = nil
            self.noteEditorSessionStateURL = nil
            self.noteEditorItemID = nil
            self.noteEditorDraftText = ""
            self.noteEditorLastPersistedText = ""
            self.noteEditorObservedFileModificationDate = nil
            self.noteEditorObservedFileContentSnapshot = ""
            self.noteEditorShouldCommitExternalDraft = false
            self.noteEditorIsOrphanedCodexDraft = false
            self.noteEditorCodexSessionID = nil
            self.noteEditorCodexProjectRootURL = nil

            self.suppressPanelAutoClose = true
            self.promoteAppForExternalEditorIfNeeded()
            self.activateCurrentApp()
            let controller = self.makeFileBackedEditorWindowController(
                fileURL: nil,
                initialText: "",
                kind: kind
            )
            if let window = controller.window {
                if self.panel.isVisible {
                    let referenceFrame = self.panel.frame
                    let screen = self.screen(containing: referenceFrame) ?? self.panel.screen ?? window.screen ?? NSScreen.main
                    let visibleFrame = (screen?.visibleFrame ?? window.frame).insetBy(dx: Layout.screenMargin, dy: Layout.screenMargin)
                    let desiredFrame = Self.auxiliaryWindowPlacement(
                        anchorFrame: referenceFrame,
                        visibleFrame: visibleFrame,
                        windowSize: window.frame.size,
                        gap: 16
                    )
                    window.setFrame(desiredFrame, display: false)
                } else {
                    window.center()
                }
            }
            controller.showWindow(nil)
            controller.window?.orderFrontRegardless()
            controller.window?.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.suppressPanelAutoClose = false
            }
        }
    }

    private func requestStandaloneEditorReplacement(completion: @escaping (Bool) -> Void) {
        guard noteEditorWindowController?.window?.isVisible == true else {
            completion(true)
            return
        }

        if isCurrentEditorFileBacked, noteEditorHasUnsavedFileChanges {
            promptToCloseUnsavedEditor { [weak self] decision in
                guard let self else {
                    completion(false)
                    return
                }
                switch decision {
                case .saveAndClose:
                    self.dismissStandaloneNoteEditorWindow(copyToClipboard: false)
                case .discardAndClose:
                    self.dismissStandaloneNoteEditorWindow(
                        copyToClipboard: false,
                        persistStandaloneDraft: false
                    )
                case .cancel:
                    completion(false)
                    return
                }
                DispatchQueue.main.async {
                    completion(true)
                }
            }
            return
        }

        if noteEditorExternalFileURL != nil {
            dismissStandaloneNoteEditorWindow(copyToClipboard: false)
        } else {
            dismissStandaloneNoteEditorWindow(copyToClipboard: true)
        }
        DispatchQueue.main.async {
            completion(true)
        }
    }

    private func promptToCloseUnsavedEditor(completion: @escaping (UnsavedEditorCloseDecision) -> Void) {
        guard let window = noteEditorWindowController?.window else {
            completion(.saveAndClose)
            return
        }

        let alert = NSAlert()
        alert.messageText = uiText("Save changes before closing?", "閉じる前に保存しますか？")
        alert.informativeText = uiText(
            "Choose whether to save the current text to your clipboard, save it as a file, or discard it before closing.",
            "閉じる前に、現在のテキストをクリップボードへ保存するか、ファイルとして保存するか、保存せず破棄するかを選んでください。"
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: uiText("Save to Clipboard", "クリップボードに保存"))
        alert.addButton(withTitle: uiText("Save File", "ファイルとして保存"))
        alert.addButton(withTitle: uiText("Don't Save", "保存しない"))
        alert.addButton(withTitle: uiText("Cancel", "キャンセル"))

        validationAttachedSheetContext = .closeUnsavedEditor
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else {
                completion(.cancel)
                return
            }
            self.validationAttachedSheetContext = nil

            switch response {
            case .alertFirstButtonReturn:
                _ = self.copyTextToClipboard(
                    self.noteEditorDraftText,
                    feedbackMessage: "Copied",
                    storeInHistory: true
                )
                completion(.saveAndClose)
            case .alertSecondButtonReturn:
                completion(self.saveCurrentEditorTextToFile() ? .saveAndClose : .cancel)
            case .alertThirdButtonReturn:
                completion(.discardAndClose)
            default:
                completion(.cancel)
            }
        }
    }

    private func promptToCloseUnsavedManualNote(completion: @escaping (UnsavedEditorCloseDecision) -> Void) {
        guard let window = standaloneNoteWindowController?.window else {
            completion(.saveAndClose)
            return
        }

        let alert = NSAlert()
        alert.messageText = uiText("Save changes before closing?", "閉じる前に保存しますか？")
        alert.informativeText = uiText(
            "Choose whether to save the current text to your clipboard, save it as a file, or discard it before closing.",
            "閉じる前に、現在のテキストをクリップボードへ保存するか、ファイルとして保存するか、保存せず破棄するかを選んでください。"
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: uiText("Save to Clipboard", "クリップボードに保存"))
        alert.addButton(withTitle: uiText("Save File", "ファイルとして保存"))
        alert.addButton(withTitle: uiText("Don't Save", "保存しない"))
        alert.addButton(withTitle: uiText("Cancel", "キャンセル"))

        validationAttachedSheetContext = .closeUnsavedManualNote
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else {
                completion(.cancel)
                return
            }
            self.validationAttachedSheetContext = nil

            switch response {
            case .alertFirstButtonReturn:
                _ = self.saveStandaloneManualNoteEditor()
                completion(.saveAndClose)
            case .alertSecondButtonReturn:
                completion(self.saveStandaloneManualNoteToFile() ? .saveAndClose : .cancel)
            case .alertThirdButtonReturn:
                completion(.discardAndClose)
            default:
                completion(.cancel)
            }
        }
    }

    private func promptFileBackedSaveDestination(forceSaveAs: Bool) {
        guard let window = noteEditorWindowController?.window else {
            return
        }

        let alert = NSAlert()
        alert.messageText = uiText("Choose how to save", "保存方法を選んでください")
        alert.informativeText = uiText(
            "You can save the current text to your clipboard or save it as a file.",
            "現在のテキストをクリップボードへ保存するか、ファイルとして保存するかを選べます。"
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: uiText("Save to Clipboard", "クリップボードに保存"))
        alert.addButton(withTitle: uiText("Save File", "ファイルとして保存"))
        alert.addButton(withTitle: uiText("Cancel", "キャンセル"))

        validationAttachedSheetContext = .fileSaveDestination
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.validationAttachedSheetContext = nil

            switch response {
            case .alertFirstButtonReturn:
                if self.copyTextToClipboard(
                    self.noteEditorDraftText,
                    feedbackMessage: "Copied",
                    storeInHistory: true
                ) {
                    self.markCurrentNoteEditorSaved(text: self.noteEditorDraftText, destination: .clipboard)
                }
            case .alertSecondButtonReturn:
                _ = self.saveCurrentEditorTextToFile(forceSaveAs: forceSaveAs)
            default:
                break
            }
        }
    }

    private func promptStandaloneManualNoteSaveDestination(forceSaveAs: Bool) {
        guard let window = standaloneNoteWindowController?.window else {
            return
        }

        let alert = NSAlert()
        alert.messageText = uiText("Choose how to save", "保存方法を選んでください")
        alert.informativeText = uiText(
            "You can save the current text to your clipboard or save it as a file.",
            "現在のテキストをクリップボードへ保存するか、ファイルとして保存するかを選べます。"
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: uiText("Save to Clipboard", "クリップボードに保存"))
        alert.addButton(withTitle: uiText("Save File", "ファイルとして保存"))
        alert.addButton(withTitle: uiText("Cancel", "キャンセル"))

        validationAttachedSheetContext = .manualNoteSaveDestination
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.validationAttachedSheetContext = nil

            switch response {
            case .alertFirstButtonReturn:
                _ = self.saveStandaloneManualNoteEditor()
            case .alertSecondButtonReturn:
                _ = self.saveStandaloneManualNoteToFile(forceSaveAs: forceSaveAs)
            default:
                break
            }
        }
    }

    @discardableResult
    private func saveCurrentEditorTextToFile(forceSaveAs: Bool = false) -> Bool {
        if let fileURL = noteEditorExternalFileURL, !forceSaveAs {
            let didSave = saveExternalEditorText(noteEditorDraftText, to: fileURL)
            if didSave {
                syncStandaloneNoteItemWithSavedFileTextIfNeeded(noteEditorDraftText)
                markCurrentNoteEditorSaved(text: noteEditorDraftText, destination: .file)
                noteEditorObservedFileModificationDate = fileModificationDate(for: fileURL)
                noteEditorObservedFileContentSnapshot = noteEditorDraftText
            }
            return didSave
        }

        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.nameFieldStringValue = defaultSavePanelFileName()
        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else {
            return false
        }

        let didSave = saveExternalEditorText(noteEditorDraftText, to: destinationURL)
        if didSave {
            let standardizedDestinationURL = destinationURL.standardizedFileURL
            let destinationKind = inferredFileBackedDocumentKind(
                for: standardizedDestinationURL,
                preferredKind: currentFileBackedDocumentKind
            )

            if !isCurrentExternalEditorCodex {
                if Self.shouldConvertManualNoteToFileBackedEditor(
                    currentMode: noteEditorExternalMode,
                    itemIDPresent: noteEditorItemID != nil
                ) {
                    convertCurrentManualNoteEditorToFileBacked(
                        fileURL: standardizedDestinationURL,
                        kind: destinationKind
                    )
                } else {
                    noteEditorExternalFileURL = standardizedDestinationURL
                    noteEditorExternalMode = Self.standaloneEditorModeAfterSavingFile(
                        currentMode: noteEditorExternalMode,
                        destinationKind: destinationKind
                    )
                    syncStandaloneNoteItemWithSavedFileTextIfNeeded(noteEditorDraftText)
                    markCurrentNoteEditorSaved(text: noteEditorDraftText, destination: .file)
                    noteEditorObservedFileModificationDate = fileModificationDate(for: standardizedDestinationURL)
                    noteEditorObservedFileContentSnapshot = noteEditorDraftText
                    noteEditorWindowController?.window?.representedURL = standardizedDestinationURL
                    noteEditorWindowController?.window?.title = externalEditorWindowTitle(
                        for: standardizedDestinationURL,
                        kind: currentFileBackedDocumentKind,
                        isOrphaned: false,
                        codexContext: nil
                    )
                    fileLocalHistoryManager?.registerOpenedFile(standardizedDestinationURL)
                    startExternalFileMonitorIfNeeded()
                }
            }
        }
        return didSave
    }

    @discardableResult
    private func saveStandaloneEditor() -> EditorSaveDestination? {
        if isCurrentEditorFileBacked {
            if noteEditorExternalFileURL != nil {
                return saveCurrentEditorTextToFile() ? .file : nil
            } else {
                guard copyTextToClipboard(
                    noteEditorDraftText,
                    feedbackMessage: "Copied",
                    storeInHistory: true
                ) else {
                    return nil
                }
                markCurrentNoteEditorSaved(text: noteEditorDraftText, destination: .clipboard)
                return .clipboard
            }
        }
        guard copyTextToClipboard(
            noteEditorDraftText,
            feedbackMessage: "Copied",
            storeInHistory: true
        ) else {
            return nil
        }
        markCurrentNoteEditorSaved(text: noteEditorDraftText, destination: .clipboard)
        return .clipboard
    }

    @discardableResult
    private func saveStandaloneEditorAs() -> EditorSaveDestination? {
        promptFileBackedSaveDestination(forceSaveAs: true)
        return nil
    }

    @discardableResult
    private func saveStandaloneManualNoteEditor() -> EditorSaveDestination? {
        guard copyTextToClipboard(
            standaloneNoteDraftText,
            feedbackMessage: "Copied",
            storeInHistory: true
        ) else {
            return nil
        }
        markStandaloneManualNoteSaved(text: standaloneNoteDraftText, destination: .clipboard)
        return .clipboard
    }

    @discardableResult
    private func saveStandaloneManualNoteEditorAs() -> EditorSaveDestination? {
        promptStandaloneManualNoteSaveDestination(forceSaveAs: true)
        return nil
    }

    @discardableResult
    private func saveStandaloneManualNoteToFile(forceSaveAs: Bool = false) -> Bool {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.nameFieldStringValue = defaultManualNoteSavePanelFileName()
        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else {
            return false
        }

        let standardizedDestinationURL = destinationURL.standardizedFileURL
        let destinationKind = inferredFileBackedDocumentKind(for: standardizedDestinationURL)
        let draftText = standaloneNoteDraftText
        let preservedFrame = standaloneNoteWindowController?.window?.frame
        let didSave = saveExternalEditorText(draftText, to: standardizedDestinationURL)
        guard didSave else {
            return false
        }

        markStandaloneManualNoteSaved(text: draftText, destination: .file)
        dismissStandaloneManualNoteEditorWindow(copyToClipboard: false)
        openFileBackedEditor(
            for: standardizedDestinationURL,
            kind: destinationKind,
            initialText: draftText,
            preferredFrame: preservedFrame
        )
        return true
    }

    private func defaultSavePanelFileName() -> String {
        if let fileURL = noteEditorExternalFileURL {
            return fileURL.lastPathComponent
        }
        switch currentFileBackedDocumentKind {
        case .markdown:
            return "Untitled.md"
        case .text, .none:
            return "Untitled.txt"
        }
    }

    private func defaultManualNoteSavePanelFileName() -> String {
        "Untitled.txt"
    }

    private func syncStandaloneNoteItemWithSavedFileTextIfNeeded(_ text: String) {
        guard let itemID = noteEditorItemID else {
            return
        }

        _ = dataManager.updateTextContent(text, for: itemID)
        _ = dataManager.saveWorkingNoteText(text, for: itemID)
        noteEditorIsPlaceholderManualNote = false
    }

    private func convertCurrentManualNoteEditorToFileBacked(
        fileURL: URL,
        kind: FileBackedDocumentKind
    ) {
        let standardizedFileURL = fileURL.standardizedFileURL
        let preservedFrame = noteEditorWindowController?.window?.frame
        let draftText = noteEditorDraftText
        let preservedPreviewVisible = noteEditorMarkdownPreviewVisible

        syncStandaloneNoteItemWithSavedFileTextIfNeeded(draftText)
        noteEditorAutosaveWorkItem?.cancel()
        noteEditorAutosaveWorkItem = nil

        noteEditorItemID = nil
        noteEditorIsPlaceholderManualNote = false
        noteEditorWindowController?.window?.orderOut(nil)
        noteEditorWindowController = nil

        let controller = makeFileBackedEditorWindowController(
            fileURL: standardizedFileURL,
            initialText: draftText,
            kind: kind,
            initialPreviewVisible: preservedPreviewVisible,
            initialHistoryVisible: false
        )
        if let preservedFrame, let window = controller.window {
            window.setFrame(preservedFrame, display: false)
        }
        controller.showWindow(nil)
        controller.window?.orderFrontRegardless()
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func fileModificationDate(for fileURL: URL) -> Date? {
        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    private func uiText(_ english: String, _ japanese: String) -> String {
        settings.settingsLanguage == .japanese ? japanese : english
    }

    func openStandaloneNoteEditor(for itemID: UUID, isPlaceholderManualNote: Bool = false) {
        requestStandaloneManualNoteReplacement { [weak self] canOpen in
            guard let self, canOpen else { return }
            if let currentItemID = self.standaloneNoteItemID,
               currentItemID != itemID {
                self.dismissStandaloneManualNoteEditorWindow(copyToClipboard: false)
            }
            self.suppressPanelAutoClose = true
            self.promoteAppForExternalEditorIfNeeded()
            NSApp.activate(ignoringOtherApps: true)
            let controller = self.makeNoteEditorWindowController(
                itemID: itemID,
                isPlaceholderManualNote: isPlaceholderManualNote
            )
            if let window = controller.window {
                let referenceFrame = self.panel.isVisible ? self.panel.frame : window.frame
                let screen = self.screen(containing: referenceFrame) ?? self.panel.screen ?? window.screen ?? NSScreen.main
                let visibleFrame = (screen?.visibleFrame ?? window.frame).insetBy(dx: Layout.screenMargin, dy: Layout.screenMargin)
                let desiredFrame = Self.auxiliaryWindowPlacement(
                    anchorFrame: referenceFrame,
                    visibleFrame: visibleFrame,
                    windowSize: window.frame.size,
                    gap: 16
                )
                window.setFrame(desiredFrame, display: false)
            }
            controller.showWindow(nil)
            controller.window?.orderFrontRegardless()
            controller.window?.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.suppressPanelAutoClose = false
            }
        }
    }

    private func requestStandaloneManualNoteReplacement(completion: @escaping (Bool) -> Void) {
        guard standaloneNoteWindowController?.window?.isVisible == true else {
            completion(true)
            return
        }

        let trimmedDraft = standaloneNoteDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDraft.isEmpty {
            dismissStandaloneManualNoteEditorWindow(
                copyToClipboard: false,
                persistStandaloneDraft: false
            )
            DispatchQueue.main.async { completion(true) }
            return
        }

        let hasUnsavedStandaloneDraft = Self.standaloneEditorHasUnsavedChanges(
            draftText: standaloneNoteDraftText,
            lastPersistedText: standaloneNoteLastPersistedText
        )
        if hasUnsavedStandaloneDraft {
            promptToCloseUnsavedManualNote { [weak self] decision in
                guard let self else { return }
                switch decision {
                case .saveAndClose:
                    self.dismissStandaloneManualNoteEditorWindow(copyToClipboard: false)
                case .discardAndClose:
                    self.dismissStandaloneManualNoteEditorWindow(
                        copyToClipboard: false,
                        persistStandaloneDraft: false
                    )
                case .cancel:
                    completion(false)
                    return
                }
                DispatchQueue.main.async { completion(true) }
            }
            return
        }

        dismissStandaloneManualNoteEditorWindow(copyToClipboard: false)
        DispatchQueue.main.async { completion(true) }
    }

    private func openExternalCodexEditor(
        for fileURL: URL,
        sessionID: String,
        projectRootURL: URL?,
        sessionStateURL: URL?
    ) {
        let standardizedURL = fileURL.standardizedFileURL
        let standardizedProjectRootURL = (projectRootURL ?? standardizedURL.deletingLastPathComponent()).standardizedFileURL
        let resolvedSessionStateURL = (sessionStateURL ?? codexSessionStateURL(for: sessionID)).standardizedFileURL
        do {
            try FileManager.default.createDirectory(
                at: standardizedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: standardizedURL.path) {
                try "".write(to: standardizedURL, atomically: true, encoding: .utf8)
            }
        } catch {
            return
        }

        let targetApp = currentPlacementTargetApp()
        previouslyActiveApp = targetApp
        placementTargetApp = targetApp

        if noteEditorExternalMode?.isCodex == true,
           let currentURL = noteEditorExternalFileURL,
           currentURL == standardizedURL,
           let window = noteEditorWindowController?.window,
           window.isVisible {
            noteEditorCodexSessionID = sessionID
            noteEditorCodexProjectRootURL = standardizedProjectRootURL
            noteEditorSessionStateURL = resolvedSessionStateURL
            startCodexSessionStateMonitor()
            window.title = externalEditorWindowTitle(
                for: standardizedURL,
                isOrphaned: noteEditorIsOrphanedCodexDraft,
                codexContext: currentCodexDraftContext()
            )
            activateCurrentApp()
            noteEditorWindowController?.showWindow(nil)
            window.orderFront(nil)
            window.makeKeyAndOrderFront(nil)
            return
        }

        requestStandaloneEditorReplacement { [weak self] canOpen in
            guard let self, canOpen else { return }
            self.noteEditorExternalFileURL = standardizedURL
            self.noteEditorExternalMode = .codex
            self.noteEditorCompletionMarkerURL = codexCompletionMarkerURL(for: standardizedURL)
            self.noteEditorSessionStateURL = resolvedSessionStateURL
            self.noteEditorItemID = nil
            self.noteEditorDraftText = (try? String(contentsOf: standardizedURL, encoding: .utf8)) ?? ""
            self.noteEditorLastPersistedText = self.noteEditorDraftText
            self.noteEditorShouldCommitExternalDraft = false
            self.noteEditorIsOrphanedCodexDraft = false
            self.noteEditorCodexSessionID = sessionID
            self.noteEditorCodexProjectRootURL = standardizedProjectRootURL

            self.suppressPanelAutoClose = true
            self.promoteAppForExternalEditorIfNeeded()
            NSApp.unhide(nil)
            self.activateCurrentApp()
            let controller = self.makeExternalFileEditorWindowController(
                fileURL: standardizedURL,
                codexContext: self.currentCodexDraftContext()
            )
            if let window = controller.window {
                if self.panel.isVisible {
                    let referenceFrame = self.panel.frame
                    let screen = self.screen(containing: referenceFrame) ?? self.panel.screen ?? window.screen ?? NSScreen.main
                    let visibleFrame = (screen?.visibleFrame ?? window.frame).insetBy(dx: Layout.screenMargin, dy: Layout.screenMargin)
                    let desiredFrame = Self.auxiliaryWindowPlacement(
                        anchorFrame: referenceFrame,
                        visibleFrame: visibleFrame,
                        windowSize: window.frame.size,
                        gap: 16
                    )
                    window.setFrame(desiredFrame, display: false)
                } else {
                    window.center()
                }
            }
            controller.showWindow(nil)
            controller.window?.orderFrontRegardless()
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.startCodexSessionStateMonitor()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.suppressPanelAutoClose = false
            }
        }
    }

    private func openFileBackedEditor(
        for fileURL: URL,
        kind: FileBackedDocumentKind,
        initialText: String,
        preferredFrame: NSRect? = nil
    ) {
        let standardizedURL = fileURL.standardizedFileURL
        if noteEditorExternalMode?.fileKind == kind,
           let currentURL = noteEditorExternalFileURL,
           currentURL == standardizedURL,
           let window = noteEditorWindowController?.window,
           window.isVisible {
            promoteAppForExternalEditorIfNeeded()
            activateCurrentApp()
            noteEditorWindowController?.showWindow(nil)
            window.orderFront(nil)
            window.makeKeyAndOrderFront(nil)
            return
        }
        requestStandaloneEditorReplacement { [weak self] canOpen in
            guard let self, canOpen else { return }
            self.noteEditorExternalFileURL = standardizedURL
            self.noteEditorExternalMode = .fileBacked(kind)
            self.noteEditorCompletionMarkerURL = nil
            self.noteEditorSessionStateURL = nil
            self.noteEditorItemID = nil
            self.noteEditorDraftText = initialText
            self.noteEditorLastPersistedText = initialText
            self.noteEditorShouldCommitExternalDraft = false
            self.noteEditorIsOrphanedCodexDraft = false
            self.noteEditorCodexSessionID = nil
            self.noteEditorCodexProjectRootURL = nil

            self.suppressPanelAutoClose = true
            self.promoteAppForExternalEditorIfNeeded()
            self.activateCurrentApp()
            let controller = self.makeFileBackedEditorWindowController(
                fileURL: standardizedURL,
                initialText: initialText,
                kind: kind
            )
            if let window = controller.window {
                if let preferredFrame {
                    window.setFrame(preferredFrame, display: false)
                } else if self.panel.isVisible {
                    let referenceFrame = self.panel.frame
                    let screen = self.screen(containing: referenceFrame) ?? self.panel.screen ?? window.screen ?? NSScreen.main
                    let visibleFrame = (screen?.visibleFrame ?? window.frame).insetBy(dx: Layout.screenMargin, dy: Layout.screenMargin)
                    let desiredFrame = Self.auxiliaryWindowPlacement(
                        anchorFrame: referenceFrame,
                        visibleFrame: visibleFrame,
                        windowSize: window.frame.size,
                        gap: 16
                    )
                    window.setFrame(desiredFrame, display: false)
                } else {
                    window.center()
                }
            }
            controller.showWindow(nil)
            controller.window?.orderFrontRegardless()
            controller.window?.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.suppressPanelAutoClose = false
            }
        }
    }

    func closeSettingsWindow() {
        settingsWindowController?.close()
        suppressPanelAutoClose = false
        registerHotKeys()
    }

    func revealLocalHistoryStorageRoot() {
        guard fileLocalHistoryManager?.revealStorageRootInFinder() == true else {
            presentLocalHistoryAlert(
                title: uiText("Local history storage is unavailable", "ローカル履歴フォルダを開けませんでした"),
                message: uiText(
                    "ClipboardHistory could not open the local history storage directory.",
                    "ローカル履歴の保存先ディレクトリを開けませんでした。"
                )
            )
            return
        }
    }

    func revealLocalHistoryForCurrentEditor() {
        guard let fileURL = currentLocalHistoryFileURL else {
            presentLocalHistoryAlert(
                title: uiText("Save this file first", "先にファイルとして保存してください"),
                message: uiText(
                    "Local history is available after this editor is backed by a real file path.",
                    "ローカル履歴は、このエディタが実ファイルに紐づいた後に利用できます。"
                )
            )
            return
        }

        guard fileLocalHistoryManager?.revealHistoryInFinder(for: fileURL) == true else {
            presentLocalHistoryAlert(
                title: uiText("No local history yet", "まだローカル履歴がありません"),
                message: uiText(
                    "Open or save the file once, or enable directory watching in Settings, then try again.",
                    "一度ファイルを開くか保存するか、設定でディレクトリ監視を有効にしてから再度実行してください。"
                )
            )
            return
        }
    }

    func currentEditorLocalHistoryEntries() -> [FileLocalHistoryManager.SnapshotEntry] {
        guard let fileURL = currentLocalHistoryFileURL else {
            return []
        }

        return (fileLocalHistoryManager?.historyEntries(for: fileURL) ?? [])
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.snapshotFileName > rhs.snapshotFileName
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    func currentEditorLocalHistoryFileURLForUI() -> URL? {
        currentLocalHistoryFileURL
    }

    func currentEditorLocalHistoryText(for entry: FileLocalHistoryManager.SnapshotEntry) -> String? {
        guard let fileURL = currentLocalHistoryFileURL else {
            return nil
        }
        return fileLocalHistoryManager?.snapshotText(for: entry, fileURL: fileURL)
    }

    func currentEditorLocalHistoryTrackingInfo() -> FileLocalHistoryManager.TrackingInfo? {
        guard let fileURL = currentLocalHistoryFileURL else {
            return nil
        }
        return fileLocalHistoryManager?.trackingInfo(for: fileURL)
    }

    @discardableResult
    func deleteCurrentEditorLocalHistoryEntry(_ entry: FileLocalHistoryManager.SnapshotEntry) -> Bool {
        guard let fileURL = currentLocalHistoryFileURL else {
            return false
        }

        let timestamp = DateFormatter.localizedString(from: entry.createdAt, dateStyle: .medium, timeStyle: .short)
        let confirmed = confirmLocalHistoryDestructiveAction(
            title: uiText("Delete this snapshot?", "このスナップショットを削除しますか？"),
            message: uiText(
                "The snapshot from \(timestamp) will be removed from local history.",
                "\(timestamp) のスナップショットをローカル履歴から削除します。"
            ),
            actionTitle: uiText("Delete Snapshot", "スナップショットを削除")
        )
        guard confirmed else {
            return false
        }

        return fileLocalHistoryManager?.deleteSnapshot(entry, for: fileURL) == true
    }

    @discardableResult
    func deleteAllCurrentEditorLocalHistory() -> Bool {
        guard let fileURL = currentLocalHistoryFileURL else {
            return false
        }

        let fileName = fileURL.lastPathComponent
        let confirmed = confirmLocalHistoryDestructiveAction(
            title: uiText("Delete all local history for this file?", "このファイルのローカル履歴をすべて削除しますか？"),
            message: uiText(
                "All stored snapshots for \(fileName) will be removed. Future edits can create new snapshots again while tracking remains enabled.",
                "\(fileName) の保存済みスナップショットをすべて削除します。追跡が有効なままなら、今後の編集で新しいスナップショットは再び作成されます。"
            ),
            actionTitle: uiText("Delete All History", "履歴をすべて削除")
        )
        guard confirmed else {
            return false
        }

        return fileLocalHistoryManager?.deleteHistory(for: fileURL) == true
    }

    private func presentLocalHistoryAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func confirmLocalHistoryDestructiveAction(title: String, message: String, actionTitle: String) -> Bool {
        guard settings.localFileHistoryConfirmDestructiveActions else {
            return true
        }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: uiText("Cancel", "キャンセル"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func makeSettingsWindowController() -> NSWindowController {
        if let settingsWindowController {
            return settingsWindowController
        }

        let rootView = SettingsView(appDelegate: self)
            .modelContainer(sharedContainer)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 580, height: 470))
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .normal

        let controller = NSWindowController(window: window)
        if settingsWindowCloseObserver == nil {
            settingsWindowCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.suppressPanelAutoClose = false
                self?.registerHotKeys()
            }
        }
        settingsWindowController = controller
        return controller
    }

    private enum FloatingFeedbackStyle {
        case copy
        case joined
        case normalized

        var backgroundColor: NSColor {
            switch self {
            case .copy:
                return NSColor(calibratedRed: 0.77, green: 0.60, blue: 0.14, alpha: 0.97)
            case .joined:
                return NSColor(calibratedRed: 0.76, green: 0.44, blue: 0.13, alpha: 0.97)
            case .normalized:
                return NSColor(calibratedRed: 0.19, green: 0.49, blue: 0.64, alpha: 0.97)
            }
        }
    }

    private func floatingFeedbackStyle(for message: String) -> FloatingFeedbackStyle {
        switch message {
        case "Joined", "Copied joined text":
            return .joined
        case "Normalized", "Copied normalized text":
            return .normalized
        default:
            return .copy
        }
    }

    private func showFloatingFeedback(message: String, style: FloatingFeedbackStyle) {
        floatingFeedbackDismissTask?.cancel()

        let panel = floatingFeedbackPanel ?? makeFloatingFeedbackPanel()
        let displayMessage = message.hasSuffix("!") ? message : "\(message)!"
        let fittedWidth = floatingFeedbackWidth(for: displayMessage)
        let panelSize = NSSize(width: fittedWidth, height: 30)
        if let rootView = floatingFeedbackRootView {
            rootView.frame = NSRect(x: 0, y: 0, width: fittedWidth, height: 30)
        }
        if let label = floatingFeedbackLabel {
            label.stringValue = displayMessage
            label.frame = NSRect(x: 10, y: 6, width: fittedWidth - 20, height: 18)
        }
        if let backgroundView = floatingFeedbackBackgroundView {
            backgroundView.layer?.backgroundColor = style.backgroundColor.cgColor
            backgroundView.frame = NSRect(x: 0, y: 0, width: fittedWidth, height: 30)
        }

        panel.setContentSize(panelSize)
        panel.setFrame(floatingFeedbackFrame(for: panelSize), display: false)
        panel.orderFrontRegardless()

        let dismissTask = DispatchWorkItem { [weak self] in
            self?.floatingFeedbackPanel?.orderOut(nil)
            self?.floatingFeedbackDismissTask = nil
        }
        floatingFeedbackDismissTask = dismissTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: dismissTask)
    }

    private func makeFloatingFeedbackPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 128, height: 30),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 128, height: 30))
        rootView.wantsLayer = true

        let backgroundView = NSView(frame: rootView.bounds)
        backgroundView.autoresizingMask = [.width, .height]
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 15
        backgroundView.layer?.masksToBounds = true
        rootView.addSubview(backgroundView)

        let label = NSTextField(labelWithString: "")
        label.frame = NSRect(x: 10, y: 6, width: 108, height: 18)
        label.autoresizingMask = [.width]
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = NSColor.white
        label.lineBreakMode = .byClipping
        backgroundView.addSubview(label)

        panel.contentView = rootView
        floatingFeedbackRootView = rootView
        floatingFeedbackBackgroundView = backgroundView
        floatingFeedbackLabel = label
        floatingFeedbackPanel = panel
        return panel
    }

    private func floatingFeedbackWidth(for message: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let measuredWidth = ceil((message as NSString).size(withAttributes: attributes).width)
        return min(max(measuredWidth + 28, 100), 220)
    }

    private func floatingFeedbackFrame(for size: NSSize) -> NSRect {
        let targetApp = NSWorkspace.shared.frontmostApplication
        let targetFrame = frontmostWindowFrame(for: targetApp)
        let screen = targetFrame.flatMap(screen(containing:)) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let referenceFrame = targetFrame ?? visibleFrame

        let x = clamped(referenceFrame.midX - (size.width / 2), min: visibleFrame.minX + 10, max: visibleFrame.maxX - size.width - 10)
        let preferredY = referenceFrame.minY + 18
        let y = clamped(preferredY, min: visibleFrame.minY + 12, max: visibleFrame.maxY - size.height - 12)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func makeNoteEditorWindowController(itemID: UUID, isPlaceholderManualNote: Bool) -> NSWindowController {
        standaloneNoteItemID = itemID
        standaloneNoteIsPlaceholderManualNote = isPlaceholderManualNote
        let initialText = dataManager.loadWorkingNoteText(for: itemID)
            ?? dataManager.allItems().first(where: { $0.id == itemID }).flatMap(dataManager.resolvedText(for:))
            ?? ""
        standaloneNoteDraftText = initialText
        standaloneNoteLastPersistedText = initialText
        standaloneNoteMarkdownPreviewVisible = false
        standaloneNoteSaveStatus.lastPersistedText = initialText
        standaloneNoteSaveStatus.lastSaveDestination = nil
        standaloneNoteSaveStatus.saveRevision += 1
        _ = dataManager.saveWorkingNoteText(initialText, for: itemID)

        let rootView = StandaloneNoteEditorView(
            initialText: initialText,
            appDelegate: self,
            saveStatusState: standaloneNoteSaveStatus,
            codexContext: nil,
            commitMode: .pasteToTarget,
            initialMarkdownPreviewVisible: false,
            onDraftChange: { [weak self] text in
                self?.standaloneNoteDraftText = text
                self?.scheduleStandaloneNoteAutosave(itemID: itemID, text: text)
            },
            onCommit: { [weak self] text in
                self?.commitStandaloneManualNoteDraft(text, for: itemID)
            },
            onSave: { [weak self] in
                self?.saveStandaloneManualNoteEditor()
            },
            onSaveAs: { [weak self] in
                self?.saveStandaloneManualNoteEditorAs()
            },
            onClose: { [weak self] in
                self?.closeStandaloneManualNoteEditor()
            },
            onMarkdownPreviewVisibilityChanged: { [weak self] isVisible in
                self?.standaloneNoteMarkdownPreviewVisible = isVisible
            },
            onDiscardOrphanCodex: nil
        )
        .modelContainer(sharedContainer)

        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "New Note"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 420))
        window.contentMinSize = NSSize(width: 620, height: 320)
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.representedURL = dataManager.workingNoteFileURL(for: itemID)
        window.delegate = self

        let controller = NSWindowController(window: window)
        standaloneNoteWindowController = controller
        return controller
    }

    private func makeExternalFileEditorWindowController(
        fileURL: URL,
        initialText: String? = nil,
        isOrphaned: Bool = false,
        codexContext: CodexDraftContext? = nil,
        initialPreviewVisible: Bool? = nil,
        initialHistoryVisible: Bool = false
    ) -> NSWindowController {
        if !isOrphaned {
            fileLocalHistoryManager?.registerOpenedFile(fileURL.standardizedFileURL)
        }
        noteEditorItemID = nil
        noteEditorExternalFileURL = fileURL
        noteEditorExternalMode = .codex
        noteEditorCompletionMarkerURL = isOrphaned ? nil : codexCompletionMarkerURL(for: fileURL)
        noteEditorShouldCommitExternalDraft = false
        noteEditorIsOrphanedCodexDraft = isOrphaned
        noteEditorIsPlaceholderManualNote = false
        let resolvedInitialText = initialText ?? ((try? String(contentsOf: fileURL, encoding: .utf8)) ?? "")
        let resolvedInitialPreviewVisible = initialPreviewVisible ?? true
        noteEditorDraftText = resolvedInitialText
        noteEditorLastPersistedText = resolvedInitialText
        noteEditorMarkdownPreviewVisible = resolvedInitialPreviewVisible
        noteEditorHistoryPaneVisible = initialHistoryVisible
        externalEditorSaveStatus.lastPersistedText = resolvedInitialText
        externalEditorSaveStatus.lastSaveDestination = nil
        externalEditorSaveStatus.saveRevision += 1

        let rootView = StandaloneNoteEditorView(
            initialText: resolvedInitialText,
            appDelegate: self,
            saveStatusState: externalEditorSaveStatus,
            codexContext: codexContext,
            commitMode: isOrphaned ? .orphanedCodex : .returnToCodex,
            initialMarkdownPreviewVisible: resolvedInitialPreviewVisible,
            initialHistoryVisible: initialHistoryVisible,
            onDraftChange: { [weak self] text in
                self?.noteEditorDraftText = text
            },
            onCommit: { [weak self] text in
                if isOrphaned {
                    self?.copyOrphanedCodexDraftToClipboardAndClose(text)
                } else {
                    self?.commitExternalCodexDraft(text, fileURL: fileURL)
                }
            },
            onSave: { [weak self] in
                self?.saveStandaloneEditor()
            },
            onSaveAs: { [weak self] in
                self?.saveStandaloneEditorAs()
            },
            onClose: { [weak self] in
                self?.closeStandaloneNoteEditor()
            },
            onMarkdownPreviewVisibilityChanged: { [weak self] isVisible in
                self?.noteEditorMarkdownPreviewVisible = isVisible
            },
            onHistoryPaneVisibilityChanged: { [weak self] isVisible in
                self?.noteEditorHistoryPaneVisible = isVisible
            },
            onDiscardOrphanCodex: isOrphaned ? { [weak self] in
                self?.discardOrphanedCodexDraft()
            } : nil
        )
        .modelContainer(sharedContainer)

        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = externalEditorWindowTitle(for: fileURL, isOrphaned: isOrphaned, codexContext: codexContext)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 420))
        window.contentMinSize = NSSize(width: 620, height: 320)
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.representedURL = fileURL
        window.delegate = self

        let controller = NSWindowController(window: window)
        noteEditorWindowController = controller
        return controller
    }

    private func makeFileBackedEditorWindowController(
        fileURL: URL?,
        initialText: String,
        kind: FileBackedDocumentKind,
        initialPreviewVisible: Bool? = nil,
        initialHistoryVisible: Bool = false
    ) -> NSWindowController {
        if let fileURL {
            fileLocalHistoryManager?.registerOpenedFile(fileURL.standardizedFileURL)
        }
        let resolvedInitialPreviewVisible = initialPreviewVisible ?? kind.supportsMarkdownPreview
        noteEditorItemID = nil
        noteEditorExternalFileURL = fileURL
        noteEditorExternalMode = .fileBacked(kind)
        noteEditorCompletionMarkerURL = nil
        noteEditorSessionStateURL = nil
        noteEditorShouldCommitExternalDraft = false
        noteEditorIsOrphanedCodexDraft = false
        noteEditorIsPlaceholderManualNote = false
        noteEditorCodexSessionID = nil
        noteEditorCodexProjectRootURL = nil
        noteEditorDraftText = initialText
        noteEditorLastPersistedText = initialText
        noteEditorMarkdownPreviewVisible = resolvedInitialPreviewVisible
        noteEditorHistoryPaneVisible = initialHistoryVisible
        externalEditorSaveStatus.lastPersistedText = initialText
        externalEditorSaveStatus.lastSaveDestination = fileURL == nil ? nil : .file
        externalEditorSaveStatus.saveRevision += 1
        noteEditorObservedFileModificationDate = fileURL.flatMap(fileModificationDate(for:))
        noteEditorObservedFileContentSnapshot = initialText

        let rootView = StandaloneNoteEditorView(
            initialText: initialText,
            appDelegate: self,
            saveStatusState: externalEditorSaveStatus,
            codexContext: nil,
            commitMode: kind == .markdown ? .fileBackedMarkdown : .fileBackedText,
            initialMarkdownPreviewVisible: resolvedInitialPreviewVisible,
            initialHistoryVisible: initialHistoryVisible,
            onDraftChange: { [weak self] text in
                self?.noteEditorDraftText = text
            },
            onCommit: { _ in },
            onSave: { [weak self] in
                self?.saveStandaloneEditor()
            },
            onSaveAs: { [weak self] in
                self?.saveStandaloneEditorAs()
            },
            onClose: { [weak self] in
                self?.closeStandaloneNoteEditor()
            },
            onMarkdownPreviewVisibilityChanged: { [weak self] isVisible in
                self?.noteEditorMarkdownPreviewVisible = isVisible
            },
            onHistoryPaneVisibilityChanged: { [weak self] isVisible in
                self?.noteEditorHistoryPaneVisible = isVisible
            },
            onDiscardOrphanCodex: nil
        )
        .modelContainer(sharedContainer)

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = externalEditorWindowTitle(for: fileURL, kind: kind, isOrphaned: false, codexContext: nil)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 420))
        window.contentMinSize = NSSize(width: 620, height: 320)
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.representedURL = fileURL
        window.delegate = self

        let controller = NSWindowController(window: window)
        noteEditorWindowController = controller
        startExternalFileMonitorIfNeeded()
        return controller
    }

    private func closeStandaloneNoteEditor() {
        if isCurrentEditorFileBacked, noteEditorHasUnsavedFileChanges {
            promptToCloseUnsavedEditor { [weak self] decision in
                guard let self else { return }
                switch decision {
                case .saveAndClose:
                    self.dismissStandaloneNoteEditorWindow(copyToClipboard: false)
                case .discardAndClose:
                    self.dismissStandaloneNoteEditorWindow(
                        copyToClipboard: false,
                        persistStandaloneDraft: false
                    )
                case .cancel:
                    break
                }
            }
            return
        }

        if isCurrentEditorFileBacked {
            dismissStandaloneNoteEditorWindow(copyToClipboard: false)
            return
        }

        if noteEditorExternalFileURL != nil {
            if noteEditorIsOrphanedCodexDraft {
                discardOrphanedCodexDraft()
            } else {
                dismissStandaloneNoteEditorWindow(copyToClipboard: false)
            }
            return
        }

        let trimmedDraft = noteEditorDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDraft.isEmpty {
            dismissStandaloneNoteEditorWindow(copyToClipboard: false)
            return
        }

        let hasUnsavedStandaloneDraft = Self.standaloneEditorHasUnsavedChanges(
            draftText: noteEditorDraftText,
            lastPersistedText: noteEditorLastPersistedText
        )
        if hasUnsavedStandaloneDraft {
            promptToCloseUnsavedEditor { [weak self] decision in
                guard let self else { return }
                switch decision {
                case .saveAndClose:
                    self.dismissStandaloneNoteEditorWindow(copyToClipboard: false)
                case .discardAndClose:
                    self.dismissStandaloneNoteEditorWindow(
                        copyToClipboard: false,
                        persistStandaloneDraft: false
                    )
                case .cancel:
                    break
                }
            }
            return
        }

        dismissStandaloneNoteEditorWindow(copyToClipboard: false)
    }

    private func closeStandaloneManualNoteEditor() {
        let trimmedDraft = standaloneNoteDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDraft.isEmpty {
            dismissStandaloneManualNoteEditorWindow(
                copyToClipboard: false,
                persistStandaloneDraft: false
            )
            return
        }

        let hasUnsavedStandaloneDraft = Self.standaloneEditorHasUnsavedChanges(
            draftText: standaloneNoteDraftText,
            lastPersistedText: standaloneNoteLastPersistedText
        )
        if hasUnsavedStandaloneDraft {
            promptToCloseUnsavedManualNote { [weak self] decision in
                guard let self else { return }
                switch decision {
                case .saveAndClose:
                    self.dismissStandaloneManualNoteEditorWindow(copyToClipboard: false)
                case .discardAndClose:
                    self.dismissStandaloneManualNoteEditorWindow(
                        copyToClipboard: false,
                        persistStandaloneDraft: false
                    )
                case .cancel:
                    break
                }
            }
            return
        }

        dismissStandaloneManualNoteEditorWindow(copyToClipboard: false)
    }

    private func finalizeNoteEditorSession(copyToClipboard: Bool) {
        if let externalFileURL = noteEditorExternalFileURL,
           isCurrentExternalEditorCodex {
            let finalText = noteEditorDraftText
            _ = saveExternalEditorText(finalText, to: externalFileURL)
            if let completionMarkerURL = noteEditorCompletionMarkerURL {
                signalCodexCompletionMarker(at: completionMarkerURL)
            }
            return
        }
        guard let itemID = noteEditorItemID else {
            return
        }

        let finalText = noteEditorDraftText
        _ = dataManager.updateTextContent(finalText, for: itemID)
        _ = dataManager.saveWorkingNoteText(finalText, for: itemID)

        if copyToClipboard {
            copyTextToClipboard(finalText, feedbackMessage: "Copied", storeInHistory: true)
        }
    }

    private func persistClosedStandaloneManualNoteDraft(itemID: UUID?, finalText: String, copyToClipboard: Bool) {
        guard let itemID else {
            return
        }

        _ = dataManager.updateTextContent(finalText, for: itemID)
        _ = dataManager.saveWorkingNoteText(finalText, for: itemID)

        if copyToClipboard,
           !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copyTextToClipboard(finalText, feedbackMessage: "Copied", storeInHistory: true)
        }
    }

    private func persistClosedNoteEditorDraft(itemID: UUID?, finalText: String, copyToClipboard: Bool) {
        guard let itemID else {
            return
        }

        _ = dataManager.updateTextContent(finalText, for: itemID)
        _ = dataManager.saveWorkingNoteText(finalText, for: itemID)

        if copyToClipboard,
           !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copyTextToClipboard(finalText, feedbackMessage: "Copied", storeInHistory: true)
        }
    }

    private func dismissStandaloneNoteEditorWindow(
        copyToClipboard: Bool,
        saveOrphanedCodexDraftToClipboard: Bool = false,
        persistStandaloneDraft: Bool = true
    ) {
        guard let controller = noteEditorWindowController,
              let window = controller.window else {
            return
        }

        let itemID = noteEditorItemID
        let externalFileURL = noteEditorExternalFileURL
        let externalMode = noteEditorExternalMode
        let completionMarkerURL = noteEditorCompletionMarkerURL
        let sessionStateURL = noteEditorSessionStateURL
        let shouldCommitExternalDraft = noteEditorShouldCommitExternalDraft
        let isOrphanedCodexDraft = noteEditorIsOrphanedCodexDraft
        let isPlaceholderManualNote = noteEditorIsPlaceholderManualNote
        let finalText = noteEditorDraftText
        let lastPersistedText = noteEditorLastPersistedText
        let lastSaveDestination = externalEditorSaveStatus.lastSaveDestination
        noteEditorAutosaveWorkItem?.cancel()
        noteEditorAutosaveWorkItem = nil
        stopExternalFileMonitor()
        lastClosedNoteEditorItemID = itemID
        noteEditorItemID = nil
        noteEditorExternalFileURL = nil
        noteEditorExternalMode = nil
        noteEditorCompletionMarkerURL = nil
        noteEditorSessionStateURL = nil
        noteEditorShouldCommitExternalDraft = false
        noteEditorIsOrphanedCodexDraft = false
        noteEditorIsPlaceholderManualNote = false
        noteEditorCodexSessionID = nil
        noteEditorCodexProjectRootURL = nil
        noteEditorDraftText = ""
        noteEditorLastPersistedText = ""
        noteEditorMarkdownPreviewVisible = false
        noteEditorHistoryPaneVisible = false
        externalEditorSaveStatus.lastPersistedText = ""
        externalEditorSaveStatus.lastSaveDestination = nil
        externalEditorSaveStatus.saveRevision += 1
        noteEditorWindowController = nil

        window.contentViewController = NSViewController()
        window.orderOut(nil)

        DispatchQueue.main.async { [weak self] in
            if let externalFileURL {
                self?.stopCodexSessionStateMonitor()
                if externalMode?.isCodex == true {
                    let closeOutcome = Self.externalEditorCloseOutcome(
                        commitRequested: shouldCommitExternalDraft,
                        isOrphaned: isOrphanedCodexDraft
                    )
                    switch closeOutcome {
                    case .persistAndSignal:
                        _ = self?.saveExternalEditorText(finalText, to: externalFileURL)
                        if let completionMarkerURL {
                            self?.signalCodexCompletionMarker(at: completionMarkerURL)
                        }
                    case .discardOrphan:
                        if saveOrphanedCodexDraftToClipboard,
                           !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            self?.copyTextToClipboard(finalText, feedbackMessage: "Copied", storeInHistory: true)
                        }
                    case .signalOnly:
                        if let completionMarkerURL {
                            self?.signalCodexCompletionMarker(at: completionMarkerURL)
                        }
                    }
                    if let sessionStateURL {
                        try? FileManager.default.removeItem(at: sessionStateURL)
                    }
                    self?.restoreAccessoryActivationPolicyIfNeeded()
                    if closeOutcome == .persistAndSignal {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                            self?.reactivatePreviouslyActiveApp()
                        }
                    }
                } else {
                    self?.restoreAccessoryActivationPolicyIfNeeded()
                    if let sessionStateURL {
                        try? FileManager.default.removeItem(at: sessionStateURL)
                    }
                }
            } else if persistStandaloneDraft {
                self?.persistClosedNoteEditorDraft(itemID: itemID, finalText: finalText, copyToClipboard: copyToClipboard)
            } else {
                let discardAction = Self.standaloneDiscardAction(
                    isPlaceholderManualNote: isPlaceholderManualNote,
                    hasSavedContent: lastSaveDestination != nil || !lastPersistedText.isEmpty
                )
                self?.restoreDiscardedNoteEditorDraft(
                    itemID: itemID,
                    originalText: lastPersistedText,
                    deletePlaceholder: discardAction == .deletePlaceholder
                )
            }
            self?.registerHotKeys()
        }
    }

    private func dismissStandaloneManualNoteEditorWindow(
        copyToClipboard: Bool,
        persistStandaloneDraft: Bool = true
    ) {
        guard let controller = standaloneNoteWindowController,
              let window = controller.window else {
            return
        }

        let itemID = standaloneNoteItemID
        let isPlaceholderManualNote = standaloneNoteIsPlaceholderManualNote
        let finalText = standaloneNoteDraftText
        let lastPersistedText = standaloneNoteLastPersistedText
        let lastSaveDestination = standaloneNoteSaveStatus.lastSaveDestination
        standaloneNoteAutosaveWorkItem?.cancel()
        standaloneNoteAutosaveWorkItem = nil
        lastClosedNoteEditorItemID = itemID
        standaloneNoteItemID = nil
        standaloneNoteIsPlaceholderManualNote = false
        standaloneNoteDraftText = ""
        standaloneNoteLastPersistedText = ""
        standaloneNoteMarkdownPreviewVisible = false
        standaloneNoteSaveStatus.lastPersistedText = ""
        standaloneNoteSaveStatus.lastSaveDestination = nil
        standaloneNoteSaveStatus.saveRevision += 1
        standaloneNoteWindowController = nil

        window.contentViewController = NSViewController()
        window.orderOut(nil)

        DispatchQueue.main.async { [weak self] in
            if persistStandaloneDraft {
                self?.persistClosedStandaloneManualNoteDraft(
                    itemID: itemID,
                    finalText: finalText,
                    copyToClipboard: copyToClipboard
                )
            } else {
                let discardAction = Self.standaloneDiscardAction(
                    isPlaceholderManualNote: isPlaceholderManualNote,
                    hasSavedContent: lastSaveDestination != nil || !lastPersistedText.isEmpty
                )
                self?.restoreDiscardedStandaloneManualNoteDraft(
                    itemID: itemID,
                    originalText: lastPersistedText,
                    deletePlaceholder: discardAction == .deletePlaceholder
                )
            }
            self?.registerHotKeys()
        }
    }

    private func restoreDiscardedNoteEditorDraft(
        itemID: UUID?,
        originalText: String,
        deletePlaceholder: Bool
    ) {
        guard let itemID else {
            return
        }

        if deletePlaceholder {
            _ = dataManager.deleteItem(id: itemID)
            try? FileManager.default.removeItem(at: dataManager.workingNoteFileURL(for: itemID))
            if lastClosedNoteEditorItemID == itemID {
                lastClosedNoteEditorItemID = nil
            }
            return
        }

        _ = dataManager.updateTextContent(originalText, for: itemID)
        _ = dataManager.saveWorkingNoteText(originalText, for: itemID)
    }

    private func restoreDiscardedStandaloneManualNoteDraft(
        itemID: UUID?,
        originalText: String,
        deletePlaceholder: Bool
    ) {
        guard let itemID else {
            return
        }

        if deletePlaceholder {
            _ = dataManager.deleteItem(id: itemID)
            try? FileManager.default.removeItem(at: dataManager.workingNoteFileURL(for: itemID))
            if lastClosedNoteEditorItemID == itemID {
                lastClosedNoteEditorItemID = nil
            }
            return
        }

        _ = dataManager.updateTextContent(originalText, for: itemID)
        _ = dataManager.saveWorkingNoteText(originalText, for: itemID)
    }

    private func scheduleNoteEditorAutosave(itemID: UUID, text: String) {
        noteEditorAutosaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            _ = self.dataManager.updateTextContent(text, for: itemID)
            _ = self.dataManager.saveWorkingNoteText(text, for: itemID)
            self.noteEditorAutosaveWorkItem = nil
        }
        noteEditorAutosaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: workItem)
    }

    private func scheduleStandaloneNoteAutosave(itemID: UUID, text: String) {
        standaloneNoteAutosaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            _ = self.dataManager.updateTextContent(text, for: itemID)
            _ = self.dataManager.saveWorkingNoteText(text, for: itemID)
            self.standaloneNoteAutosaveWorkItem = nil
        }
        standaloneNoteAutosaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: workItem)
    }

    private func commitManualNoteDraft(_ text: String, for itemID: UUID) {
        _ = dataManager.updateTextContent(text, for: itemID)
        _ = dataManager.saveWorkingNoteText(text, for: itemID)
        noteEditorLastPersistedText = text
        noteEditorIsPlaceholderManualNote = false
        externalEditorSaveStatus.lastPersistedText = text
        externalEditorSaveStatus.saveRevision += 1
        pasteTextToFrontApp(text)
    }

    private func commitStandaloneManualNoteDraft(_ text: String, for itemID: UUID) {
        _ = dataManager.updateTextContent(text, for: itemID)
        _ = dataManager.saveWorkingNoteText(text, for: itemID)
        standaloneNoteLastPersistedText = text
        standaloneNoteIsPlaceholderManualNote = false
        standaloneNoteSaveStatus.lastPersistedText = text
        standaloneNoteSaveStatus.saveRevision += 1
        pasteTextToFrontApp(text)
    }

    private func commitExternalCodexDraft(_ text: String, fileURL: URL) {
        noteEditorShouldCommitExternalDraft = true
        _ = saveExternalEditorText(text, to: fileURL)
        dismissStandaloneNoteEditorWindow(copyToClipboard: false)
    }

    private func copyOrphanedCodexDraftToClipboardAndClose(_ text: String) {
        noteEditorDraftText = text
        dismissStandaloneNoteEditorWindow(
            copyToClipboard: false,
            saveOrphanedCodexDraftToClipboard: true
        )
    }

    private func discardOrphanedCodexDraft() {
        dismissStandaloneNoteEditorWindow(copyToClipboard: false)
    }

    private func orphanCurrentCodexDraftWindow() {
        guard let externalFileURL = noteEditorExternalFileURL,
              !noteEditorIsOrphanedCodexDraft,
              let controller = noteEditorWindowController,
              let window = controller.window else {
            return
        }

        let preservedFrame = window.frame
        stopCodexSessionStateMonitor()
        if let completionMarkerURL = noteEditorCompletionMarkerURL {
            signalCodexCompletionMarker(at: completionMarkerURL)
        }
        noteEditorCompletionMarkerURL = nil
        noteEditorSessionStateURL = nil
        noteEditorShouldCommitExternalDraft = false
        noteEditorIsOrphanedCodexDraft = true
        noteEditorHistoryPaneVisible = false
        let codexContext = currentCodexDraftContext()
        let preservedPreviewVisibility = noteEditorMarkdownPreviewVisible

        let hostingController = NSHostingController(
            rootView: AnyView(
                StandaloneNoteEditorView(
                    initialText: noteEditorDraftText,
                    appDelegate: self,
                    saveStatusState: externalEditorSaveStatus,
                    codexContext: codexContext,
                    commitMode: .orphanedCodex,
                    initialMarkdownPreviewVisible: preservedPreviewVisibility,
                    onDraftChange: { [weak self] text in
                        self?.noteEditorDraftText = text
                    },
                    onCommit: { [weak self] text in
                        self?.copyOrphanedCodexDraftToClipboardAndClose(text)
                    },
                    onSave: { [weak self] in
                        self?.saveStandaloneEditor()
                    },
                    onSaveAs: { [weak self] in
                        self?.saveStandaloneEditorAs()
                    },
                    onClose: { [weak self] in
                        self?.closeStandaloneNoteEditor()
                    },
                    onMarkdownPreviewVisibilityChanged: { [weak self] isVisible in
                        self?.noteEditorMarkdownPreviewVisible = isVisible
                    },
                    onHistoryPaneVisibilityChanged: { [weak self] isVisible in
                        self?.noteEditorHistoryPaneVisible = isVisible
                    },
                    onDiscardOrphanCodex: { [weak self] in
                        self?.discardOrphanedCodexDraft()
                    }
                )
                .modelContainer(sharedContainer)
            )
        )
        window.contentViewController = hostingController
        window.title = externalEditorWindowTitle(for: externalFileURL, isOrphaned: true, codexContext: codexContext)
        window.setFrame(preservedFrame, display: false)
        activateCurrentApp()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    @discardableResult
    private func saveExternalEditorText(_ text: String, to fileURL: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            fileLocalHistoryManager?.captureNowIfNeeded(for: fileURL.standardizedFileURL)
            return true
        } catch {
            return false
        }
    }

    private func codexCompletionMarkerURL(for fileURL: URL) -> URL {
        let standardizedPath = fileURL.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(standardizedPath.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        let storePaths = ClipboardStorePaths.default()
        try? storePaths.ensureDirectories()
        return storePaths.codexCompletionDirectory.appendingPathComponent("\(hash).done")
    }

    private func signalCodexCompletionMarker(at markerURL: URL) {
        do {
            try FileManager.default.createDirectory(
                at: markerURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: markerURL, options: .atomic)
        } catch {
            return
        }
    }

    private func codexSessionStateURL(for sessionID: String) -> URL {
        let storePaths = ClipboardStorePaths.default()
        try? storePaths.ensureDirectories()
        return storePaths.codexSessionStateDirectory.appendingPathComponent("\(sessionID).alive")
    }

    private func startCodexSessionStateMonitor() {
        stopCodexSessionStateMonitor()
        guard noteEditorExternalFileURL != nil,
              !noteEditorIsOrphanedCodexDraft,
              let sessionStateURL = noteEditorSessionStateURL else {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.noteEditorExternalFileURL != nil,
                  !self.noteEditorIsOrphanedCodexDraft else {
                self.stopCodexSessionStateMonitor()
                return
            }

            if !FileManager.default.fileExists(atPath: sessionStateURL.path) {
                self.orphanCurrentCodexDraftWindow()
            }
        }
        codexSessionStateMonitor = timer
        timer.resume()
    }

    private func stopCodexSessionStateMonitor() {
        codexSessionStateMonitor?.cancel()
        codexSessionStateMonitor = nil
    }

    private func startExternalFileMonitorIfNeeded() {
        stopExternalFileMonitor()
        guard currentFileBackedDocumentKind != nil,
              let fileURL = noteEditorExternalFileURL else {
            return
        }

        noteEditorObservedFileModificationDate = fileModificationDate(for: fileURL)
        noteEditorObservedFileContentSnapshot = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? noteEditorDraftText

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.8, repeating: 0.8)
        timer.setEventHandler { [weak self] in
            self?.checkForExternalFileChanges()
        }
        noteEditorExternalFileMonitor = timer
        timer.resume()
    }

    private func stopExternalFileMonitor() {
        noteEditorExternalFileMonitor?.cancel()
        noteEditorExternalFileMonitor = nil
        noteEditorExternalChangePromptActive = false
    }

    private func checkForExternalFileChanges() {
        guard currentFileBackedDocumentKind != nil,
              let fileURL = noteEditorExternalFileURL,
              noteEditorWindowController?.window?.isVisible == true,
              !noteEditorExternalChangePromptActive else {
            return
        }

        let currentDate = fileModificationDate(for: fileURL)
        guard currentDate != noteEditorObservedFileModificationDate else {
            return
        }

        guard let diskText = try? String(contentsOf: fileURL, encoding: .utf8) else {
            noteEditorObservedFileModificationDate = currentDate
            return
        }

        if diskText == noteEditorObservedFileContentSnapshot {
            noteEditorObservedFileModificationDate = currentDate
            return
        }

        noteEditorObservedFileModificationDate = currentDate
        noteEditorObservedFileContentSnapshot = diskText
        promptForExternalFileChange(diskText: diskText, fileURL: fileURL)
    }

    private func promptForExternalFileChange(diskText: String, fileURL: URL) {
        guard let window = noteEditorWindowController?.window else { return }
        noteEditorExternalChangePromptActive = true

        let alert = NSAlert()
        alert.messageText = uiText("File changed outside ClipboardHistory", "外部でファイル内容が変更されました")
        alert.informativeText = uiText(
            "Choose whether to sync this window with the external file, or preserve the current draft separately first.",
            "このウィンドウを外部ファイルの内容に同期するか、現在の下書きを別に保存してから同期するかを選んでください。"
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: uiText("Sync from File", "ファイル内容に同期"))
        alert.addButton(withTitle: uiText("Save Current to Clipboard", "現在内容をクリップボードに保存"))
        alert.addButton(withTitle: uiText("Save Current as File", "現在内容を別ファイルとして保存"))
        alert.addButton(withTitle: uiText("Cancel", "キャンセル"))

        validationAttachedSheetContext = .externalFileChange
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.noteEditorExternalChangePromptActive = false
            self.validationAttachedSheetContext = nil

            switch response {
            case .alertFirstButtonReturn:
                self.reloadFileBackedEditorFromDisk(text: diskText, fileURL: fileURL)
            case .alertSecondButtonReturn:
                _ = self.copyTextToClipboard(self.noteEditorDraftText, feedbackMessage: "Copied")
                self.reloadFileBackedEditorFromDisk(text: diskText, fileURL: fileURL)
            case .alertThirdButtonReturn:
                if self.saveCurrentEditorTextToFile(forceSaveAs: true) {
                    self.reloadFileBackedEditorFromDisk(text: diskText, fileURL: fileURL)
                }
            default:
                break
            }
        }
    }

    private func reloadFileBackedEditorFromDisk(text: String, fileURL: URL) {
        noteEditorDraftText = text
        noteEditorLastPersistedText = text
        externalEditorSaveStatus.lastPersistedText = text
        externalEditorSaveStatus.lastSaveDestination = .file
        externalEditorSaveStatus.saveRevision += 1
        noteEditorObservedFileContentSnapshot = text
        noteEditorObservedFileModificationDate = fileModificationDate(for: fileURL)
        noteEditorWindowController?.window?.title = externalEditorWindowTitle(
            for: fileURL,
            kind: currentFileBackedDocumentKind,
            isOrphaned: false,
            codexContext: nil
        )
        let preservedPreviewVisibility = noteEditorMarkdownPreviewVisible
        let preservedHistoryVisibility = noteEditorHistoryPaneVisible

        if let window = noteEditorWindowController?.window {
            window.contentViewController = NSHostingController(
                rootView: AnyView(
                    StandaloneNoteEditorView(
                        initialText: text,
                        appDelegate: self,
                        saveStatusState: externalEditorSaveStatus,
                        codexContext: nil,
                        commitMode: currentFileBackedDocumentKind == .markdown ? .fileBackedMarkdown : .fileBackedText,
                        initialMarkdownPreviewVisible: preservedPreviewVisibility,
                        initialHistoryVisible: preservedHistoryVisibility,
                        onDraftChange: { [weak self] updatedText in
                            self?.noteEditorDraftText = updatedText
                        },
                        onCommit: { _ in },
                        onSave: { [weak self] in
                            self?.saveStandaloneEditor()
                        },
                        onSaveAs: { [weak self] in
                            self?.saveStandaloneEditorAs()
                        },
                        onClose: { [weak self] in
                            self?.closeStandaloneNoteEditor()
                        },
                        onMarkdownPreviewVisibilityChanged: { [weak self] isVisible in
                            self?.noteEditorMarkdownPreviewVisible = isVisible
                        },
                        onHistoryPaneVisibilityChanged: { [weak self] isVisible in
                            self?.noteEditorHistoryPaneVisible = isVisible
                        },
                        onDiscardOrphanCodex: nil
                    )
                    .modelContainer(sharedContainer)
                )
            )
        }
    }

    private func markCurrentNoteEditorSaved(text: String, destination: EditorSaveDestination) {
        noteEditorLastPersistedText = text
        externalEditorSaveStatus.lastPersistedText = text
        externalEditorSaveStatus.lastSaveDestination = destination
        noteEditorIsPlaceholderManualNote = false
        externalEditorSaveStatus.saveRevision += 1
    }

    private func markStandaloneManualNoteSaved(text: String, destination: EditorSaveDestination) {
        standaloneNoteLastPersistedText = text
        standaloneNoteSaveStatus.lastPersistedText = text
        standaloneNoteSaveStatus.lastSaveDestination = destination
        standaloneNoteIsPlaceholderManualNote = false
        standaloneNoteSaveStatus.saveRevision += 1
    }

    enum ExternalEditorCloseOutcome: Equatable {
        case persistAndSignal
        case signalOnly
        case discardOrphan
    }

    static func externalEditorCloseOutcome(commitRequested: Bool, isOrphaned: Bool) -> ExternalEditorCloseOutcome {
        if commitRequested {
            return .persistAndSignal
        }
        if isOrphaned {
            return .discardOrphan
        }
        return .signalOnly
    }

    private func currentCodexDraftContext() -> CodexDraftContext? {
        guard let noteEditorCodexSessionID else {
            return nil
        }
        return CodexDraftContext(
            sessionID: noteEditorCodexSessionID,
            projectRootURL: noteEditorCodexProjectRootURL
        )
    }

    private func externalEditorWindowTitle(
        for fileURL: URL?,
        kind: FileBackedDocumentKind? = nil,
        isOrphaned: Bool,
        codexContext: CodexDraftContext?
    ) -> String {
        if let codexContext {
            let prefix = isOrphaned ? "Codex Disconnected" : "Codex"
            return "\(prefix) • \(codexContext.projectDisplayName) • \(codexContext.shortSessionID)"
        }
        if let fileURL {
            return isOrphaned ? "Disconnected - \(fileURL.lastPathComponent)" : fileURL.lastPathComponent
        }
        switch kind {
        case .markdown:
            return "Untitled.md"
        case .text, .none:
            return "Untitled.txt"
        }
    }

    static func parseCodexOpenRequest(_ requestText: String) -> CodexOpenRequest? {
        let lines = requestText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard lines.count >= 2 else {
            return nil
        }

        let sessionID = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let filePath = lines[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionID.isEmpty, !filePath.isEmpty else {
            return nil
        }

        let projectRootPath = lines.count >= 3 ? lines[2].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let sessionStatePath = lines.count >= 4 ? lines[3].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return CodexOpenRequest(
            sessionID: sessionID,
            fileURL: URL(fileURLWithPath: filePath).standardizedFileURL,
            projectRootURL: projectRootPath.isEmpty ? nil : URL(fileURLWithPath: projectRootPath).standardizedFileURL,
            sessionStateURL: sessionStatePath.isEmpty ? nil : URL(fileURLWithPath: sessionStatePath).standardizedFileURL
        )
    }

    static func standaloneEditorModeAfterSavingFile(
        currentMode: ExternalEditorMode?,
        destinationKind: FileBackedDocumentKind
    ) -> ExternalEditorMode {
        if let currentMode {
            return currentMode
        }
        return .fileBacked(destinationKind)
    }

    static func shouldConvertManualNoteToFileBackedEditor(
        currentMode: ExternalEditorMode?,
        itemIDPresent: Bool
    ) -> Bool {
        itemIDPresent && currentMode == nil
    }

    static func panelToggleAction(isVisible: Bool, isFrontmost: Bool) -> PanelToggleAction {
        (isVisible && isFrontmost) ? .close : .showOrRaise
    }

    static func standaloneDiscardAction(
        isPlaceholderManualNote: Bool,
        hasSavedContent: Bool
    ) -> StandaloneDiscardAction {
        (isPlaceholderManualNote && !hasSavedContent) ? .deletePlaceholder : .restoreOriginal
    }

    static func standaloneEditorHasUnsavedChanges(
        draftText: String,
        lastPersistedText: String
    ) -> Bool {
        draftText != lastPersistedText
    }

    static func resolvedSpecialCopySourceText(
        panelText: String?,
        clipboardText: String?
    ) -> String? {
        if let panelText,
           !panelText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return panelText
        }

        if let clipboardText,
           !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return clipboardText
        }

        return nil
    }

    func codexIntegrationStatus(inspectShellConfig: Bool = false) -> CodexIntegrationStatus {
        makeCodexIntegrationManager().status(inspectShellConfig: inspectShellConfig)
    }

    func installCodexIntegration() throws -> CodexIntegrationStatus {
        try makeCodexIntegrationManager().install()
    }

    func removeCodexIntegration() throws -> CodexIntegrationStatus {
        try makeCodexIntegrationManager().remove()
    }

    private func makeCodexIntegrationManager() -> CodexIntegrationManager {
        CodexIntegrationManager(
            storePaths: ClipboardStorePaths.default(),
            shellPath: ProcessInfo.processInfo.environment["SHELL"] ?? "",
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    private func syncLaunchAtLoginState() {
        guard #available(macOS 13.0, *) else { return }
        let status = SMAppService.mainApp.status
        mutateSettings { $0.launchAtLogin = (status == .enabled || status == .requiresApproval) }
        saveSettings()
    }

    private func parseShortcutInput(_ input: String) throws -> HotKeyManager.Shortcut {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let shortcut = HotKeyManager.parseShortcutString(trimmed) else {
            throw SettingsMutationError.invalidShortcutFormat
        }
        return shortcut
    }

    private func validateGlobalHotKeyAvailability(
        panelShortcut: HotKeyManager.Shortcut,
        translationShortcut: HotKeyManager.Shortcut,
        additionalShortcuts: [(String, HotKeyManager.Shortcut?)] = []
    ) throws {
        suspendGlobalHotKeys()
        defer { registerHotKeys() }

        let panelResult = HotKeyManager.shared.registerDetailed(shortcut: panelShortcut) {}
        if let registrationID = panelResult.registrationID {
            HotKeyManager.shared.unregister(registrationID: registrationID)
        }
        guard panelResult.isSuccess else {
            throw SettingsMutationError.unavailableShortcut("Panel: \(HotKeyManager.displayString(for: panelShortcut))")
        }

        let translationResult = HotKeyManager.shared.registerDetailed(shortcut: translationShortcut) {}
        if let registrationID = translationResult.registrationID {
            HotKeyManager.shared.unregister(registrationID: registrationID)
        }
        guard translationResult.isSuccess else {
            throw SettingsMutationError.unavailableShortcut("Translation: \(HotKeyManager.displayString(for: translationShortcut))")
        }

        for (label, shortcut) in additionalShortcuts {
            guard let shortcut else { continue }
            let result = HotKeyManager.shared.registerDetailed(shortcut: shortcut) {}
            if let registrationID = result.registrationID {
                HotKeyManager.shared.unregister(registrationID: registrationID)
            }
            guard result.isSuccess else {
                throw SettingsMutationError.unavailableShortcut("\(label): \(HotKeyManager.displayString(for: shortcut))")
            }
        }
    }

    private func applyPanelShortcut(_ shortcut: HotKeyManager.Shortcut) {
        panelHotKeyShortcut = shortcut
        mutateSettings { $0.panelShortcut = shortcut }
        saveSettings()
        registerHotKeys()
    }

    private func applyTranslationShortcut(_ shortcut: HotKeyManager.Shortcut) {
        translateHotKeyShortcut = shortcut
        mutateSettings { $0.translationShortcut = shortcut }
        saveSettings()
        registerHotKeys()
    }
    
    @objc
    private func statusItemButtonClicked(_ sender: NSStatusBarButton) {
        guard let currentEvent = NSApp.currentEvent else {
            togglePanelFromStatusItem()
            return
        }
        
        if currentEvent.type == .rightMouseUp {
            showStatusMenu(using: currentEvent)
            return
        }
        
        togglePanelFromStatusItem()
    }

    private func togglePanelFromStatusItem() {
        if Self.panelToggleAction(isVisible: panel.isVisible, isFrontmost: isPanelFrontmost()) == .close {
            closePanelAndReactivate()
            return
        }
        showPanelFromStatusItem()
    }

    private func showPanelFromStatusItem() {
        suppressPanelAutoClose = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.showPanel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.suppressPanelAutoClose = false
            }
        }
    }
    
    @objc
    private func togglePanelFromMenu() {
        togglePanel()
    }
    
    @objc
    private func translateNowFromMenu() {
        translateCurrentContext()
    }
    
    @objc
    private func openSettingsFromMenu() {
        openSettingsWindow()
    }

    @objc
    private func newMarkdownFileFromMenu() {
        openUntitledFileBackedEditor(kind: .markdown)
    }

    @objc
    private func newTextFileFromMenu() {
        openUntitledFileBackedEditor(kind: .text)
    }

    @objc
    private func createNewNoteFromMenu() {
        createNewNoteFromAnyState()
    }

    @objc
    private func openMarkdownFileFromMenu() {
        openTextDocumentViaPanel(preferredKind: .markdown)
    }

    @objc
    private func openTextFileFromMenu() {
        openTextDocumentViaPanel(preferredKind: .text)
    }

    @objc
    private func openFileFromMenu() {
        openTextDocumentViaPanel()
    }
    
    @objc
    private func quitFromMenu() {
        NSApp.terminate(nil)
    }
}

private final class AnchorDebugView: NSView {
    var label: String = "" {
        didSet { needsDisplay = true }
    }
    var referencePoint: NSPoint = .zero {
        didSet { needsDisplay = true }
    }
    var strokeColor: NSColor = .systemRed {
        didSet { needsDisplay = true }
    }
    var isDraggable: Bool = false
    var onDragEnded: ((NSPoint) -> Void)?

    private var dragStartLocation: NSPoint?
    private var dragStartOrigin: NSPoint?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let bounds = self.bounds
        let center = NSPoint(x: bounds.midX, y: bounds.midY)

        let ringRect = NSRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
        let ringPath = NSBezierPath(ovalIn: ringRect)
        strokeColor.withAlphaComponent(0.95).setStroke()
        ringPath.lineWidth = 1.6
        ringPath.stroke()

        let centerDot = NSBezierPath(ovalIn: NSRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3))
        strokeColor.withAlphaComponent(0.95).setFill()
        centerDot.fill()

        let crosshair = NSBezierPath()
        crosshair.move(to: NSPoint(x: center.x, y: center.y - 11))
        crosshair.line(to: NSPoint(x: center.x, y: center.y + 11))
        crosshair.move(to: NSPoint(x: center.x - 11, y: center.y))
        crosshair.line(to: NSPoint(x: center.x + 11, y: center.y))
        NSColor.white.withAlphaComponent(0.88).setStroke()
        crosshair.lineWidth = 1
        crosshair.stroke()

        let textRect = NSRect(x: -18, y: bounds.maxY - 13, width: bounds.width + 36, height: 12)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        label.draw(in: textRect, withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        guard isDraggable else { return }
        guard let window else { return }
        dragStartLocation = event.locationInWindow
        dragStartOrigin = window.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDraggable else { return }
        guard let window,
              let dragStartLocation,
              let dragStartOrigin else { return }

        let currentLocation = event.locationInWindow
        let deltaX = currentLocation.x - dragStartLocation.x
        let deltaY = currentLocation.y - dragStartLocation.y
        window.setFrameOrigin(NSPoint(x: dragStartOrigin.x + deltaX, y: dragStartOrigin.y + deltaY))
    }

    override func mouseUp(with event: NSEvent) {
        guard isDraggable else { return }
        guard let window else { return }
        dragStartLocation = nil
        dragStartOrigin = nil
        let correctedPoint = NSPoint(x: window.frame.midX, y: window.frame.midY)
        onDragEnded?(correctedPoint)
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
