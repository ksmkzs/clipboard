import AppKit
import SwiftUI

struct WindowShellAnchorDebugCandidate {
    let point: NSPoint
    let label: String
    let color: NSColor
    let isDraggable: Bool
}

struct WindowShellPanelPresentation {
    let finalFrame: NSRect
    let anchorPoint: NSPoint?
    let anchorDescription: String?
    let anchorDebugCandidates: [WindowShellAnchorDebugCandidate]
}

enum WindowShellFrontmostWindowKind: String {
    case panel
    case settings
    case help
    case none
}

struct WindowShellValidationState {
    let statusItemPresent: Bool
    let panelVisible: Bool
    let panelFrontmost: Bool
    let settingsVisible: Bool
    let helpVisible: Bool
    let frontmostWindowKind: WindowShellFrontmostWindowKind
}

enum WindowShellPolicy {
    static func panelToggleAction(isVisible: Bool, isFrontmost: Bool) -> AppDelegate.PanelToggleAction {
        (isVisible && isFrontmost) ? .close : .showOrRaise
    }

    static func panelHotKeyRouting(
        settingsVisible: Bool,
        settingsShortcutCaptureActive: Bool
    ) -> AppDelegate.PanelHotKeyRouting {
        if settingsShortcutCaptureActive {
            return .suspendRegistration
        }
        if settingsVisible {
            return .bringSettingsToFront
        }
        return .togglePanel
    }

    static func helpPanelPlacement(
        for panelFrame: NSRect,
        within visibleFrame: NSRect,
        helpSize: NSSize,
        gap: CGFloat
    ) -> AppDelegate.HelpPanelPlacement {
        let alignedY = min(
            max(panelFrame.maxY - helpSize.height, visibleFrame.minY),
            visibleFrame.maxY - helpSize.height
        )

        let rightX = panelFrame.maxX + gap
        if rightX + helpSize.width <= visibleFrame.maxX {
            return AppDelegate.HelpPanelPlacement(
                frame: clampedAuxiliaryFrame(
                    NSRect(x: rightX, y: alignedY, width: helpSize.width, height: helpSize.height),
                    within: visibleFrame
                ),
                side: .right
            )
        }

        let leftX = panelFrame.minX - gap - helpSize.width
        if leftX >= visibleFrame.minX {
            return AppDelegate.HelpPanelPlacement(
                frame: clampedAuxiliaryFrame(
                    NSRect(x: leftX, y: alignedY, width: helpSize.width, height: helpSize.height),
                    within: visibleFrame
                ),
                side: .left
            )
        }

        return AppDelegate.HelpPanelPlacement(
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
}

final class WindowShellCoordinator: NSObject, NSWindowDelegate {
    final class State {
        var panel: ClipboardPanel!
        var statusItem: NSStatusItem?
        let statusMenu = NSMenu()
        var settingsWindowController: NSWindowController?
        var settingsShortcutCaptureActive = false
        var settingsWindowCloseObserver: NSObjectProtocol?
        var helpPanel: NSPanel?
        var helpRequestObserver: NSObjectProtocol?
        weak var panelReturnWindow: NSWindow?
        var hasPresentedPanelThisLaunch = false
    }

    struct Callbacks {
        let makePanelContentView: () -> NSView
        let makeSettingsViewController: () -> NSViewController
        let currentSettings: () -> AppSettings
        let panelShortcutDisplay: () -> String
        let translateShortcutDisplay: () -> String
        let newNoteShortcutDisplay: () -> String
        let initialPanelSize: () -> NSSize
        let preparePanelPresentation: () -> WindowShellPanelPresentation
        let shouldShowAnchorDebugMarkers: () -> Bool
        let showAnchorDebugMarkers: (_ candidates: [WindowShellAnchorDebugCandidate], _ fallbackPoint: NSPoint, _ description: String) -> Void
        let panelCanAutoClose: () -> Bool
        let setPanelAutoCloseSuppressed: (Bool) -> Void
        let syncClipboardNow: () -> Void
        let activateCurrentApp: (_ unhideAllWindows: Bool) -> Void
        let closePanelAndReactivate: () -> Void
        let persistPanelSize: (_ size: NSSize) -> Void
        let suspendNonPanelHotKeys: () -> Void
        let registerHotKeys: () -> Void
        let settingsDesiredFrame: (_ window: NSWindow, _ panelWasVisible: Bool) -> NSRect
        let helpPanelFrame: (_ helpPanel: NSPanel) -> NSRect
        let onTranslateRequested: () -> Void
        let onCreateNewNoteRequested: () -> Void
        let onOpenFileRequested: (_ preferredKind: AppDelegate.FileBackedDocumentKind?) -> Void
    }

    private let state: State
    private let callbacks: Callbacks
    private var panelAutoCloseSuppressionTask: DispatchWorkItem?
    private var launchAutomationSuppressionTask: DispatchWorkItem?

    init(state: State, callbacks: Callbacks) {
        self.state = state
        self.callbacks = callbacks
        super.init()
    }

    var panel: ClipboardPanel! { state.panel }
    var statusItem: NSStatusItem? { state.statusItem }
    var settingsWindowController: NSWindowController? { state.settingsWindowController }
    var settingsShortcutCaptureActive: Bool {
        get { state.settingsShortcutCaptureActive }
        set { state.settingsShortcutCaptureActive = newValue }
    }
    var helpPanel: NSPanel? { state.helpPanel }
    var hasPresentedPanelThisLaunch: Bool {
        get { state.hasPresentedPanelThisLaunch }
        set { state.hasPresentedPanelThisLaunch = newValue }
    }

    func setupPanel() {
        let initialSize = callbacks.initialPanelSize()
        let panel = ClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: initialSize.width, height: initialSize.height)
        )
        panel.delegate = self
        panel.contentView = callbacks.makePanelContentView()
        state.panel = panel
    }

    func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clipboard History")
            button.target = self
            button.action = #selector(statusItemButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        state.statusItem = item
        refreshStatusItemUI()
    }

    func refreshStatusItemUI() {
        updateStatusItemToolTip()
        rebuildStatusMenu()
    }

    func observeHelpRequestsIfNeeded() {
        guard state.helpRequestObserver == nil else { return }
        state.helpRequestObserver = NotificationCenter.default.addObserver(
            forName: .clipboardHelpRequested,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let isEditingSelectedText = notification.userInfo?["isEditingSelectedText"] as? Bool ?? false
            self?.toggleHelpPanel(isEditingSelectedText: isEditingSelectedText)
        }
    }

    func beginLaunchAutomationSuppression(duration: TimeInterval) {
        callbacks.setPanelAutoCloseSuppressed(true)
        launchAutomationSuppressionTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.callbacks.setPanelAutoCloseSuppressed(false)
            self?.launchAutomationSuppressionTask = nil
        }
        launchAutomationSuppressionTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
    }

    func handlePanelHotKey() {
        switch WindowShellPolicy.panelHotKeyRouting(
            settingsVisible: state.settingsWindowController?.window?.isVisible == true,
            settingsShortcutCaptureActive: state.settingsShortcutCaptureActive
        ) {
        case .togglePanel:
            togglePanel()
        case .bringSettingsToFront:
            bringSettingsWindowToFront()
        case .suspendRegistration:
            break
        }
    }

    func togglePanel() {
        if WindowShellPolicy.panelToggleAction(
            isVisible: state.panel?.isVisible == true,
            isFrontmost: isPanelFrontmost()
        ) == .close {
            callbacks.closePanelAndReactivate()
            return
        }

        showPanel()
    }

    func togglePanelFromStatusItem() {
        if WindowShellPolicy.panelToggleAction(
            isVisible: state.panel?.isVisible == true,
            isFrontmost: isPanelFrontmost()
        ) == .close {
            callbacks.closePanelAndReactivate()
            return
        }
        showPanelFromStatusItem()
    }

    func showPanel() {
        temporarilySuppressPanelAutoClose(for: 0.45)
        if NSApp.isActive,
           let activeWindow = NSApp.keyWindow ?? NSApp.mainWindow,
           activeWindow != state.panel,
           activeWindow.isVisible {
            state.panelReturnWindow = activeWindow
        } else {
            state.panelReturnWindow = nil
        }

        let presentation = callbacks.preparePanelPresentation()
        if callbacks.shouldShowAnchorDebugMarkers(),
           let anchorPoint = presentation.anchorPoint {
            callbacks.showAnchorDebugMarkers(
                presentation.anchorDebugCandidates,
                anchorPoint,
                presentation.anchorDescription ?? ""
            )
        }

        state.panel.alphaValue = 1
        state.panel.setFrame(presentation.finalFrame, display: true)
        state.panel.orderFrontRegardless()
        state.panel.makeKeyAndOrderFront(nil)
        callbacks.activateCurrentApp(false)
        DispatchQueue.main.async { [weak self] in
            self?.state.panel.orderFrontRegardless()
            self?.state.panel.makeKeyAndOrderFront(nil)
        }
        state.hasPresentedPanelThisLaunch = true
        DispatchQueue.main.async { [weak self] in
            self?.callbacks.syncClipboardNow()
        }
    }

    func showPanelFromStatusItem() {
        callbacks.setPanelAutoCloseSuppressed(true)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.showPanel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.callbacks.setPanelAutoCloseSuppressed(false)
            }
        }
    }

    func openSettingsWindow() {
        let panelWasVisible = state.panel?.isVisible == true
        callbacks.setPanelAutoCloseSuppressed(panelWasVisible)
        callbacks.suspendNonPanelHotKeys()
        callbacks.activateCurrentApp(false)
        let controller = makeSettingsWindowController()
        if let window = controller.window {
            window.setFrame(callbacks.settingsDesiredFrame(window, panelWasVisible), display: false)
        }
        bringSettingsWindowToFront()
        callbacks.registerHotKeys()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.callbacks.setPanelAutoCloseSuppressed(false)
        }
    }

    func bringSettingsWindowToFront() {
        let controller = makeSettingsWindowController()
        controller.showWindow(nil)
        callbacks.activateCurrentApp(false)
        controller.window?.orderFrontRegardless()
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func closeSettingsWindow() {
        state.settingsShortcutCaptureActive = false
        state.settingsWindowController?.close()
        callbacks.setPanelAutoCloseSuppressed(false)
        callbacks.registerHotKeys()
    }

    func validationState() -> WindowShellValidationState {
        WindowShellValidationState(
            statusItemPresent: state.statusItem != nil,
            panelVisible: state.panel?.isVisible == true,
            panelFrontmost: isPanelFrontmost(),
            settingsVisible: state.settingsWindowController?.window?.isVisible == true,
            helpVisible: state.helpPanel?.isVisible == true,
            frontmostWindowKind: frontmostWindowKind()
        )
    }

    func isPanelFrontmost() -> Bool {
        state.panel?.isVisible == true && NSApp.isActive && state.panel?.isKeyWindow == true
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == state.panel else {
            return
        }
        callbacks.persistPanelSize(window.frame.size)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }
        if window == state.helpPanel {
            closeHelpPanel(refocusClipboardPanel: false)
            return
        }
        guard window == state.panel, state.panel?.isVisible == true else {
            return
        }
        if state.helpPanel?.isVisible == true {
            return
        }
        if !callbacks.panelCanAutoClose() || state.settingsWindowController?.window?.isVisible == true {
            return
        }
        callbacks.closePanelAndReactivate()
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

    @objc
    private func togglePanelFromMenu() {
        togglePanel()
    }

    @objc
    private func openSettingsFromMenu() {
        openSettingsWindow()
    }

    @objc
    private func createNewNoteFromMenu() {
        callbacks.onCreateNewNoteRequested()
    }

    @objc
    private func openFileFromMenu() {
        callbacks.onOpenFileRequested(nil)
    }

    @objc
    private func translateNowFromMenu() {
        callbacks.onTranslateRequested()
    }

    @objc
    private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    private func temporarilySuppressPanelAutoClose(for duration: TimeInterval) {
        callbacks.setPanelAutoCloseSuppressed(true)
        panelAutoCloseSuppressionTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.callbacks.setPanelAutoCloseSuppressed(false)
            self?.panelAutoCloseSuppressionTask = nil
        }
        panelAutoCloseSuppressionTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
    }

    private func updateStatusItemToolTip() {
        guard let button = state.statusItem?.button else { return }
        button.toolTip = "Clipboard History (\(callbacks.panelShortcutDisplay())) / Translate (\(callbacks.translateShortcutDisplay()))"
    }

    private func rebuildStatusMenu() {
        state.statusMenu.removeAllItems()

        let toggleItem = NSMenuItem(
            title: "Show / Hide Clipboard History",
            action: #selector(togglePanelFromMenu),
            keyEquivalent: ""
        )
        toggleItem.target = self
        state.statusMenu.addItem(toggleItem)

        let newNoteItem = NSMenuItem(
            title: "New Note (\(callbacks.newNoteShortcutDisplay()))",
            action: #selector(createNewNoteFromMenu),
            keyEquivalent: ""
        )
        newNoteItem.target = self
        state.statusMenu.addItem(newNoteItem)

        let openFileItem = NSMenuItem(
            title: "Open File…",
            action: #selector(openFileFromMenu),
            keyEquivalent: ""
        )
        openFileItem.target = self
        state.statusMenu.addItem(openFileItem)

        state.statusMenu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        state.statusMenu.addItem(settingsItem)

        state.statusMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Clipboard History", action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        state.statusMenu.addItem(quitItem)
    }

    private func showStatusMenu(using event: NSEvent) {
        guard let button = state.statusItem?.button else { return }
        rebuildStatusMenu()
        NSMenu.popUpContextMenu(state.statusMenu, with: event, for: button)
    }

    private func makeSettingsWindowController() -> NSWindowController {
        if let settingsWindowController = state.settingsWindowController {
            return settingsWindowController
        }

        let window = NSWindow(contentViewController: callbacks.makeSettingsViewController())
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 580, height: 470))
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self

        let controller = NSWindowController(window: window)
        if state.settingsWindowCloseObserver == nil {
            state.settingsWindowCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.state.settingsShortcutCaptureActive = false
                self.callbacks.setPanelAutoCloseSuppressed(false)
                self.callbacks.registerHotKeys()
            }
        }
        state.settingsWindowController = controller
        return controller
    }

    func toggleHelpPanel(isEditingSelectedText: Bool) {
        if state.helpPanel?.isVisible == true {
            closeHelpPanel(refocusClipboardPanel: true)
            return
        }
        showHelpPanel(isEditingSelectedText: isEditingSelectedText)
    }

    func showHelpPanel(isEditingSelectedText: Bool) {
        let panel = state.helpPanel ?? makeHelpPanel()
        let panelWasVisible = state.panel?.isVisible == true
        callbacks.setPanelAutoCloseSuppressed(panelWasVisible)
        let targetFrame = callbacks.helpPanelFrame(panel)
        if let hostingController = panel.contentViewController as? NSHostingController<ClipboardHelpPanelContent> {
            hostingController.rootView = makeHelpPanelRootView(isEditingSelectedText: isEditingSelectedText)
        }
        panel.setFrame(targetFrame, display: true)
        if panel.parent != state.panel {
            state.panel.addChildWindow(panel, ordered: .above)
        }
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        state.helpPanel = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.callbacks.setPanelAutoCloseSuppressed(false)
        }
    }

    private func makeHelpPanel() -> NSPanel {
        let hostingController = NSHostingController(
            rootView: makeHelpPanelRootView(isEditingSelectedText: false)
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
        state.helpPanel = panel
        return panel
    }

    private func makeHelpPanelRootView(isEditingSelectedText: Bool) -> ClipboardHelpPanelContent {
        ClipboardHelpPanelContent(
            settings: callbacks.currentSettings(),
            isEditingSelectedText: isEditingSelectedText,
            onClose: { [weak self] in
                self?.closeHelpPanel(refocusClipboardPanel: true)
            }
        )
    }

    func closeHelpPanel(refocusClipboardPanel: Bool) {
        guard let helpPanel = state.helpPanel else { return }
        state.panel.removeChildWindow(helpPanel)
        helpPanel.orderOut(nil)
        if refocusClipboardPanel, state.panel?.isVisible == true {
            state.panel.makeKeyAndOrderFront(nil)
        }
    }

    private func frontmostWindowKind() -> WindowShellFrontmostWindowKind {
        if state.settingsWindowController?.window?.isVisible == true,
           NSApp.keyWindow == state.settingsWindowController?.window || NSApp.mainWindow == state.settingsWindowController?.window {
            return .settings
        }
        if state.helpPanel?.isVisible == true,
           NSApp.keyWindow == state.helpPanel || NSApp.mainWindow == state.helpPanel {
            return .help
        }
        if isPanelFrontmost() {
            return .panel
        }
        return .none
    }
}
