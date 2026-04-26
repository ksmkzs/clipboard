import AppKit
import Foundation

enum ValidationEditorSurfaceKind: Equatable {
    case noteEditor
    case standaloneNote
    case none
}

struct ValidationEditorSurfaceSnapshot: Equatable {
    let keyOrMainWindowKind: ValidationEditorSurfaceKind
    let noteEditorVisible: Bool
    let standaloneNoteVisible: Bool
}

enum ValidationEditorSurfacePolicy {
    static func resolve(_ snapshot: ValidationEditorSurfaceSnapshot) -> ValidationEditorSurfaceKind {
        if snapshot.keyOrMainWindowKind != .none {
            return snapshot.keyOrMainWindowKind
        }
        if snapshot.noteEditorVisible {
            return .noteEditor
        }
        if snapshot.standaloneNoteVisible {
            return .standaloneNote
        }
        return .none
    }
}

final class ValidationCoordinator {
    enum ApplicationAction: String {
        case openPanel
        case togglePanelFromStatusItem
        case captureSnapshot
        case captureWindowImage
        case openFile
        case openNewNote
        case openSettings
        case openHelp
        case runGlobalCopyJoined
        case runGlobalCopyJoinedWithSpaces
        case runGlobalCopyNormalized
        case inspectCodexIntegration
        case resetValidationState
        case syncClipboardCapture
        case seedHistoryText
    }

    enum PanelAction: String {
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
    }

    enum EditorAction: String {
        case toggleCurrentEditorMarkdownPreview
        case setCurrentEditorText
        case setCurrentEditorSelection
        case saveCurrentEditor
        case saveCurrentEditorAs
        case saveCurrentEditorToFile
        case closeCurrentEditor
        case commitCurrentEditor
        case respondToAttachedSheet
    }

    enum PreviewAction: String {
        case setCurrentPreviewWidth
        case setCurrentPreviewScroll
        case syncCurrentPreviewScroll
        case selectCurrentPreviewText
        case selectCurrentPreviewCodeBlock
        case copyCurrentPreviewSelection
        case measureCurrentPreviewHorizontalOverflow
        case clickCurrentPreviewFirstLink
        case respondToPreviewLinkPrompt
    }

    enum SettingsAction: String {
        case increaseZoom
        case decreaseZoom
        case resetZoom
        case setSettingsLanguage
        case setThemePreset
        case setPanelShortcut
        case setToggleMarkdownPreviewShortcut
        case setGlobalCopyJoinedEnabled
        case setGlobalCopyJoinedWithSpacesEnabled
        case setGlobalCopyNormalizedEnabled
    }

    struct EditorCallbacks {
        let currentSurface: () -> ValidationEditorSurfaceKind
        let readTextFile: (_ path: String) -> String
        let postEditorCommand: (_ command: EditorCommand, _ text: String?) -> Void
        let saveNoteEditor: () -> Bool
        let saveStandaloneNote: () -> Bool
        let saveNoteEditorAs: () -> Bool
        let saveStandaloneNoteAs: () -> Bool
        let saveCurrentEditorToFile: (_ url: URL) -> Bool
        let closeNoteEditor: () -> Void
        let closeStandaloneNote: () -> Void
        let respondToAttachedSheet: (_ rawChoice: String) -> Void
    }

    struct PanelCallbacks {
        let postPanelAction: (_ action: String, _ text: String?) -> Void
        let readTextFile: (_ path: String) -> String
    }

    struct ApplicationCallbacks {
        let openPanel: () -> Void
        let togglePanelFromStatusItem: () -> Void
        let captureSnapshot: (_ url: URL) -> Void
        let captureWindowImage: (_ rawKind: String, _ url: URL) -> Void
        let openFile: (_ url: URL) -> Void
        let openNewNote: () -> Void
        let openSettings: () -> Void
        let openHelp: () -> Void
        let runGlobalCopyJoined: () -> Void
        let runGlobalCopyJoinedWithSpaces: () -> Void
        let runGlobalCopyNormalized: () -> Void
        let inspectCodexIntegration: () -> Void
        let resetValidationState: () -> Void
        let syncClipboardCapture: () -> Void
        let seedHistoryText: (_ text: String) -> Void
        let reassertForegroundIfNeeded: () -> Void
    }

    struct PreviewCallbacks {
        let setPreviewWidth: (_ width: Double) -> Void
        let setPreviewScroll: (_ progress: Double) -> Void
        let syncPreviewScroll: () -> Void
        let selectPreviewText: (_ needle: String, _ preferCodeBlock: Bool) -> Void
        let copyPreviewSelection: () -> Void
        let measurePreviewHorizontalOverflow: () -> Void
        let clickPreviewFirstLink: () -> Void
        let respondToPreviewLinkPrompt: (_ rawChoice: String) -> Void
    }

    struct SettingsCallbacks {
        let increaseZoom: () -> Void
        let decreaseZoom: () -> Void
        let resetZoom: () -> Void
        let setSettingsLanguage: (_ language: SettingsLanguage) -> Void
        let setThemePreset: (_ theme: InterfaceThemePreset) -> Void
        let setPanelShortcut: (_ rawValue: String) -> Void
        let setToggleMarkdownPreviewShortcut: (_ rawValue: String) -> Void
        let setGlobalCopyJoinedEnabled: (_ enabled: Bool) -> Void
        let setGlobalCopyJoinedWithSpacesEnabled: (_ enabled: Bool) -> Void
        let setGlobalCopyNormalizedEnabled: (_ enabled: Bool) -> Void
    }

    private let applicationCallbacks: ApplicationCallbacks
    private let panelCallbacks: PanelCallbacks
    private let editorCallbacks: EditorCallbacks
    private let previewCallbacks: PreviewCallbacks
    private let settingsCallbacks: SettingsCallbacks

    init(
        applicationCallbacks: ApplicationCallbacks,
        panelCallbacks: PanelCallbacks,
        editorCallbacks: EditorCallbacks,
        previewCallbacks: PreviewCallbacks,
        settingsCallbacks: SettingsCallbacks
    ) {
        self.applicationCallbacks = applicationCallbacks
        self.panelCallbacks = panelCallbacks
        self.editorCallbacks = editorCallbacks
        self.previewCallbacks = previewCallbacks
        self.settingsCallbacks = settingsCallbacks
    }

    func handleAction(
        rawAction: String,
        userInfo: [AnyHashable: Any]
    ) -> Bool {
        handleApplicationAction(rawAction: rawAction, userInfo: userInfo)
            || handlePanelAction(rawAction: rawAction, userInfo: userInfo)
            || handleEditorAction(rawAction: rawAction, userInfo: userInfo)
            || handlePreviewAction(rawAction: rawAction, userInfo: userInfo)
            || handleSettingsAction(rawAction: rawAction, userInfo: userInfo)
    }

    func handleApplicationAction(
        rawAction: String,
        userInfo: [AnyHashable: Any]
    ) -> Bool {
        guard let action = ApplicationAction(rawValue: rawAction) else {
            return false
        }

        switch action {
        case .openPanel:
            applicationCallbacks.openPanel()
            applicationCallbacks.reassertForegroundIfNeeded()
        case .togglePanelFromStatusItem:
            applicationCallbacks.togglePanelFromStatusItem()
            applicationCallbacks.reassertForegroundIfNeeded()
        case .captureSnapshot:
            guard let path = userInfo["path"] as? String else { return true }
            applicationCallbacks.captureSnapshot(URL(fileURLWithPath: path))
        case .captureWindowImage:
            guard let path = userInfo["path"] as? String,
                  let windowKind = userInfo["window"] as? String else { return true }
            applicationCallbacks.captureWindowImage(windowKind, URL(fileURLWithPath: path))
        case .openFile:
            guard let path = userInfo["path"] as? String else { return true }
            applicationCallbacks.openFile(URL(fileURLWithPath: path))
            applicationCallbacks.reassertForegroundIfNeeded()
        case .openNewNote:
            applicationCallbacks.openNewNote()
            applicationCallbacks.reassertForegroundIfNeeded()
        case .openSettings:
            applicationCallbacks.openSettings()
            applicationCallbacks.reassertForegroundIfNeeded()
        case .openHelp:
            applicationCallbacks.openHelp()
            applicationCallbacks.reassertForegroundIfNeeded()
        case .runGlobalCopyJoined:
            applicationCallbacks.runGlobalCopyJoined()
        case .runGlobalCopyJoinedWithSpaces:
            applicationCallbacks.runGlobalCopyJoinedWithSpaces()
        case .runGlobalCopyNormalized:
            applicationCallbacks.runGlobalCopyNormalized()
        case .inspectCodexIntegration:
            applicationCallbacks.inspectCodexIntegration()
        case .resetValidationState:
            applicationCallbacks.resetValidationState()
        case .syncClipboardCapture:
            applicationCallbacks.syncClipboardCapture()
        case .seedHistoryText:
            guard let rawValue = userInfo["path"] as? String else { return true }
            applicationCallbacks.seedHistoryText(rawValue)
        }

        return true
    }

    func handlePanelAction(
        rawAction: String,
        userInfo: [AnyHashable: Any]
    ) -> Bool {
        guard let action = PanelAction(rawValue: rawAction) else {
            return false
        }

        switch action {
        case .movePanelSelectionDown:
            panelCallbacks.postPanelAction("moveDown", nil)
        case .movePanelSelectionUp:
            panelCallbacks.postPanelAction("moveUp", nil)
        case .movePanelSelectionLeft:
            panelCallbacks.postPanelAction("moveLeft", nil)
        case .movePanelSelectionRight:
            panelCallbacks.postPanelAction("moveRight", nil)
        case .commitPanelSelection:
            panelCallbacks.postPanelAction("commitSelection", nil)
        case .togglePanelPinnedArea:
            panelCallbacks.postPanelAction("togglePinnedArea", nil)
        case .togglePinSelectedPanelItem:
            panelCallbacks.postPanelAction("togglePin", nil)
        case .togglePinFocusedPanelItem:
            panelCallbacks.postPanelAction("togglePinFocused", nil)
        case .deleteSelectedPanelItem:
            panelCallbacks.postPanelAction("deleteSelected", nil)
        case .deleteFocusedPanelItem:
            panelCallbacks.postPanelAction("deleteFocused", nil)
        case .openSelectedPanelEditor:
            panelCallbacks.postPanelAction("toggleEditor", nil)
        case .openFocusedPanelEditor:
            panelCallbacks.postPanelAction("openFocusedEditor", nil)
        case .copySelectedPanelItem:
            panelCallbacks.postPanelAction("copySelected", nil)
        case .pasteSelectedPanelItem:
            panelCallbacks.postPanelAction("pasteSelected", nil)
        case .joinSelectedPanelItem:
            panelCallbacks.postPanelAction("joinSelected", nil)
        case .normalizeSelectedPanelItem:
            panelCallbacks.postPanelAction("normalizeSelected", nil)
        case .setPanelEditorText:
            guard let path = userInfo["path"] as? String else { return true }
            panelCallbacks.postPanelAction("setEditorText", panelCallbacks.readTextFile(path))
        case .commitPanelEditor:
            panelCallbacks.postPanelAction("commitEditor", nil)
        case .cancelPanelEditor:
            panelCallbacks.postPanelAction("cancelEditor", nil)
        }

        return true
    }

    func handleEditorAction(
        rawAction: String,
        userInfo: [AnyHashable: Any]
    ) -> Bool {
        guard let action = EditorAction(rawValue: rawAction) else {
            return false
        }

        switch action {
        case .toggleCurrentEditorMarkdownPreview:
            editorCallbacks.postEditorCommand(.toggleMarkdownPreview, nil)
        case .setCurrentEditorText:
            guard let path = userInfo["path"] as? String else { return true }
            editorCallbacks.postEditorCommand(.setText, editorCallbacks.readTextFile(path))
        case .setCurrentEditorSelection:
            guard let rawValue = userInfo["path"] as? String else { return true }
            editorCallbacks.postEditorCommand(.setSelectionLocation, rawValue)
        case .saveCurrentEditor:
            switch editorCallbacks.currentSurface() {
            case .noteEditor:
                _ = editorCallbacks.saveNoteEditor()
            case .standaloneNote:
                _ = editorCallbacks.saveStandaloneNote()
            case .none:
                break
            }
        case .saveCurrentEditorAs:
            switch editorCallbacks.currentSurface() {
            case .noteEditor:
                _ = editorCallbacks.saveNoteEditorAs()
            case .standaloneNote:
                _ = editorCallbacks.saveStandaloneNoteAs()
            case .none:
                break
            }
        case .saveCurrentEditorToFile:
            guard let path = userInfo["path"] as? String else { return true }
            _ = editorCallbacks.saveCurrentEditorToFile(URL(fileURLWithPath: path))
        case .closeCurrentEditor:
            switch editorCallbacks.currentSurface() {
            case .noteEditor:
                editorCallbacks.closeNoteEditor()
            case .standaloneNote:
                editorCallbacks.closeStandaloneNote()
            case .none:
                break
            }
        case .commitCurrentEditor:
            editorCallbacks.postEditorCommand(.commit, nil)
        case .respondToAttachedSheet:
            guard let rawChoice = userInfo["path"] as? String else { return true }
            editorCallbacks.respondToAttachedSheet(rawChoice)
        }

        return true
    }

    func handlePreviewAction(
        rawAction: String,
        userInfo: [AnyHashable: Any]
    ) -> Bool {
        guard let action = PreviewAction(rawValue: rawAction) else {
            return false
        }

        switch action {
        case .setCurrentPreviewWidth:
            guard let rawValue = userInfo["path"] as? String,
                  let width = Double(rawValue) else { return true }
            previewCallbacks.setPreviewWidth(width)
        case .setCurrentPreviewScroll:
            guard let rawValue = userInfo["path"] as? String,
                  let progress = Double(rawValue) else { return true }
            previewCallbacks.setPreviewScroll(progress)
        case .syncCurrentPreviewScroll:
            previewCallbacks.syncPreviewScroll()
        case .selectCurrentPreviewText:
            guard let rawValue = userInfo["path"] as? String else { return true }
            previewCallbacks.selectPreviewText(rawValue, false)
        case .selectCurrentPreviewCodeBlock:
            guard let rawValue = userInfo["path"] as? String else { return true }
            previewCallbacks.selectPreviewText(rawValue, true)
        case .copyCurrentPreviewSelection:
            previewCallbacks.copyPreviewSelection()
        case .measureCurrentPreviewHorizontalOverflow:
            previewCallbacks.measurePreviewHorizontalOverflow()
        case .clickCurrentPreviewFirstLink:
            previewCallbacks.clickPreviewFirstLink()
        case .respondToPreviewLinkPrompt:
            guard let rawValue = userInfo["path"] as? String else { return true }
            previewCallbacks.respondToPreviewLinkPrompt(rawValue)
        }

        return true
    }

    func handleSettingsAction(
        rawAction: String,
        userInfo: [AnyHashable: Any]
    ) -> Bool {
        guard let action = SettingsAction(rawValue: rawAction) else {
            return false
        }

        switch action {
        case .increaseZoom:
            settingsCallbacks.increaseZoom()
        case .decreaseZoom:
            settingsCallbacks.decreaseZoom()
        case .resetZoom:
            settingsCallbacks.resetZoom()
        case .setSettingsLanguage:
            guard let rawValue = userInfo["path"] as? String,
                  let language = SettingsLanguage(rawValue: rawValue) else { return true }
            settingsCallbacks.setSettingsLanguage(language)
        case .setThemePreset:
            guard let rawValue = userInfo["path"] as? String,
                  let theme = InterfaceThemePreset(rawValue: rawValue) else { return true }
            settingsCallbacks.setThemePreset(theme)
        case .setPanelShortcut:
            guard let rawValue = userInfo["path"] as? String else { return true }
            settingsCallbacks.setPanelShortcut(rawValue)
        case .setToggleMarkdownPreviewShortcut:
            guard let rawValue = userInfo["path"] as? String else { return true }
            settingsCallbacks.setToggleMarkdownPreviewShortcut(rawValue)
        case .setGlobalCopyJoinedEnabled:
            let enabled = (userInfo["path"] as? String).flatMap(Bool.init) ?? false
            settingsCallbacks.setGlobalCopyJoinedEnabled(enabled)
        case .setGlobalCopyJoinedWithSpacesEnabled:
            let enabled = (userInfo["path"] as? String).flatMap(Bool.init) ?? false
            settingsCallbacks.setGlobalCopyJoinedWithSpacesEnabled(enabled)
        case .setGlobalCopyNormalizedEnabled:
            let enabled = (userInfo["path"] as? String).flatMap(Bool.init) ?? false
            settingsCallbacks.setGlobalCopyNormalizedEnabled(enabled)
        }

        return true
    }
}
