import AppKit
import Carbon
import ServiceManagement
import SwiftData
import SwiftUI

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

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, NSWindowDelegate {
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
        case translateNow = 101
        case openSettings = 102
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
    private var settingsWindowController: NSWindowController?
    private var settingsWindowCloseObserver: NSObjectProtocol?
    private var suppressPanelAutoClose = false
    private var anchorDebugWindows: [String: NSWindow] = [:]
    private var anchorDebugHideTask: DispatchWorkItem?
    private var lastAnchorPoint: NSPoint?
    private var pendingAnchorDebugCandidates: [AnchorDebugCandidate] = []
    private let settingsStore: AppSettingsStore = UserDefaultsAppSettingsStore()
    @Published private(set) var settings = AppSettings.default
    @Published private(set) var panelHotKeyState: HotKeyRegistrationState = .notRegistered
    @Published private(set) var translationHotKeyState: HotKeyRegistrationState = .notRegistered
    
    private var panelHotKeyShortcut = AppSettings.default.panelShortcut
    private var translateHotKeyShortcut = AppSettings.default.translationShortcut
    private var panelHotKeyRegistrationID: UInt32?
    private var translateHotKeyRegistrationID: UInt32?

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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        requestAccessibilityPermissions()
        settings = settingsStore.load()
        syncLaunchAtLoginState()
        panelHotKeyShortcut = settings.panelShortcut
        translateHotKeyShortcut = settings.translationShortcut
        
        sharedContainer = getModelContainer()
        dataManager = ClipboardDataManager(
            modelContext: ModelContext(sharedContainer),
            maxHistoryItems: settings.historyLimit
        )
        clipboardController = ClipboardController(dataManager: dataManager)
        
        setupPanel()
        setupStatusItem()
        registerHotKeys()
        clipboardController.startMonitoring()
    }
    
    private func getModelContainer() -> ModelContainer {
        let schema = Schema([ClipboardItem.self])
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDirectory = supportDirectory.appendingPathComponent("ClipboardHistory", isDirectory: true)
        let storeURL = appDirectory.appendingPathComponent("ClipboardHistory.store")
        
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        
        let configuration = ModelConfiguration(schema: schema, url: storeURL, allowsSave: true)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }
    
    private func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        
        if !isTrusted {
            print("Accessibility permission is required for Enter-to-paste and selected-text translation.")
        }
    }
    
    private func setupPanel() {
        let initialSize = preferredPanelSize()
        panel = ClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: initialSize.width, height: initialSize.height)
        )
        panel.delegate = self
        
        let rootView = ClipboardHistoryView(
            appDelegate: self,
            dataManager: dataManager,
            onCopyRequest: { [weak self] item in
                self?.copyToClipboard(item)
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
            onSelectionChanged: { [weak self] item in
                self?.highlightedPanelItem = item
            }
        )
        .modelContainer(sharedContainer)
        
        panel.contentView = NSHostingView(rootView: rootView)
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
        
        let translateItem = NSMenuItem(
            title: "Translate Current Context (\(HotKeyManager.displayString(for: translateHotKeyShortcut)))",
            action: #selector(translateNowFromMenu),
            keyEquivalent: ""
        )
        translateItem.tag = MenuTag.translateNow.rawValue
        translateItem.target = self
        statusMenu.addItem(translateItem)
        
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
    
    private func togglePanel() {
        if isPanelFrontmost() {
            closePanelAndReactivate()
            return
        }
        
        let targetApp = preferredPlacementTargetApp()
        previouslyActiveApp = targetApp
        placementTargetApp = targetApp
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
        panel.alphaValue = 1
        panel.setFrame(presentationContext.finalFrame, display: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func isPanelFrontmost() -> Bool {
        panel.isVisible && NSApp.isActive && panel.isKeyWindow
    }
    
    private func panelPresentationContext() -> PanelPresentationContext {
        if let context = presentationContextForFrontmostWindow() {
            return context
        }
        return presentationContextAtScreenCenter()
    }

    private func presentationContextAtScreenCenter() -> PanelPresentationContext {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
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
        let placementApp = preferredPlacementTargetApp()
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
        guard let window = notification.object as? NSWindow, window == panel, panel.isVisible else {
            return
        }
        if suppressPanelAutoClose || settingsWindowController?.window?.isVisible == true {
            return
        }
        closePanelAndReactivate()
    }

    private func closePanelAndReactivate() {
        NotificationCenter.default.post(name: .clipboardPanelWillClose, object: nil)
        panel.orderOut(nil)
        hideAnchorDebugMarker()
        reactivatePreviouslyActiveApp()
    }

    private func reactivatePreviouslyActiveApp() {
        guard let app = previouslyActiveApp,
              app != NSRunningApplication.current else {
            return
        }

        app.activate(options: [.activateIgnoringOtherApps])
    }
    
    private func copyToClipboard(_ item: ClipboardItem) {
        clipboardController.prepareForInternalPaste()
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        if item.type == .text, let text = item.textContent {
            pasteboard.setString(text, forType: .string)
        } else if item.type == .image, let fileName = item.imageFileName,
                  let image = dataManager.loadImage(fileName: fileName),
                  let tiffData = image.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            pasteboard.setData(pngData, forType: .png)
            pasteboard.setData(tiffData, forType: .tiff)
        }
        
        clipboardController.finishInternalPaste()
    }
    
    private func pasteSelectedItem(_ item: ClipboardItem) {
        copyToClipboard(item)
        let targetPID = previouslyActiveApp?.processIdentifier
        
        closePanelAndReactivate()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.reactivatePreviouslyActiveApp()
            PasteSynthesizer.simulateCmdV(targetPID: targetPID)
        }
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
           let text = item.textContent,
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

    private func persistPanelSize(_ size: NSSize) {
        UserDefaults.standard.set(Double(size.width), forKey: WindowDefaultsKey.width)
        UserDefaults.standard.set(Double(size.height), forKey: WindowDefaultsKey.height)
    }
    private func saveSettings() {
        settingsStore.save(settings)
    }

    func updateSettingsLanguage(_ language: SettingsLanguage) {
        guard settings.settingsLanguage != language else { return }
        settings.settingsLanguage = language
        saveSettings()
    }

    private func shortcutsAreUnique(_ shortcuts: [HotKeyManager.Shortcut]) -> Bool {
        let ids = shortcuts.map { "\($0.keyCode):\($0.modifiers)" }
        return Set(ids).count == ids.count
    }

    private func validateShortcutScopes(in draft: AppSettings) throws {
        let globalShortcuts = [
            draft.panelShortcut,
            draft.translationShortcut
        ]
        let standardPanelShortcuts = [
            draft.togglePinShortcut,
            draft.togglePinnedAreaShortcut,
            draft.editTextShortcut,
            draft.deleteItemShortcut,
            draft.undoShortcut,
            draft.redoShortcut,
            draft.joinLinesShortcut,
            draft.normalizeForCommandShortcut
        ]
        let editorShortcuts = [
            draft.commitEditShortcut,
            draft.indentShortcut,
            draft.outdentShortcut,
            draft.moveLineUpShortcut,
            draft.moveLineDownShortcut,
            draft.joinLinesShortcut,
            draft.normalizeForCommandShortcut
        ]

        guard shortcutsAreUnique(globalShortcuts),
              shortcutsAreUnique(standardPanelShortcuts),
              shortcutsAreUnique(editorShortcuts) else {
            throw SettingsMutationError.duplicateShortcut
        }
    }

    func applySettingsDraft(_ draft: AppSettings) throws {
        try validateShortcutScopes(in: draft)

        try validateGlobalHotKeyAvailability(
            panelShortcut: draft.panelShortcut,
            translationShortcut: draft.translationShortcut
        )

        if settings.launchAtLogin != draft.launchAtLogin {
            try updateLaunchAtLogin(draft.launchAtLogin)
        }

        settings.settingsLanguage = draft.settingsLanguage
        settings.translationTargetLanguage = SupportedTranslationLanguages.contains(code: draft.translationTargetLanguage)
            ? draft.translationTargetLanguage
            : settings.translationTargetLanguage
        settings.historyLimit = max(1, draft.historyLimit)
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
        settings.joinLinesShortcut = draft.joinLinesShortcut
        settings.normalizeForCommandShortcut = draft.normalizeForCommandShortcut
        dataManager?.updateMaxHistoryItems(settings.historyLimit)

        applyPanelShortcut(draft.panelShortcut)
        applyTranslationShortcut(draft.translationShortcut)
        saveSettings()
    }

    func updateHistoryLimit(_ historyLimit: Int) {
        let sanitizedLimit = max(1, historyLimit)
        guard settings.historyLimit != sanitizedLimit else { return }

        settings.historyLimit = sanitizedLimit
        dataManager?.updateMaxHistoryItems(sanitizedLimit)
        saveSettings()
    }

    func updateTranslationTargetLanguage(_ languageCode: String) {
        guard SupportedTranslationLanguages.contains(code: languageCode) else { return }
        guard settings.translationTargetLanguage != languageCode else { return }

        settings.translationTargetLanguage = languageCode
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
                    settings.launchAtLogin = true
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
                    settings.launchAtLogin = false
                    saveSettings()
                    return
                }
                do {
                    try service.unregister()
                } catch {
                    throw SettingsMutationError.launchAtLoginUnavailable(error.localizedDescription)
                }
            }

            settings.launchAtLogin = isEnabled
            saveSettings()
            return
        }

        throw SettingsMutationError.launchAtLoginUnavailable("Launch at login requires macOS 13 or later.")
    }

    func openSettingsWindow() {
        suppressPanelAutoClose = true
        suspendGlobalHotKeys()
        NSApp.activate(ignoringOtherApps: true)
        let controller = makeSettingsWindowController()
        controller.showWindow(nil)
        controller.window?.orderFrontRegardless()
        controller.window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.suppressPanelAutoClose = false
        }
    }

    func closeSettingsWindow() {
        settingsWindowController?.close()
        suppressPanelAutoClose = false
        registerHotKeys()
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
        window.level = .floating

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

    private func syncLaunchAtLoginState() {
        guard #available(macOS 13.0, *) else { return }
        let status = SMAppService.mainApp.status
        settings.launchAtLogin = (status == .enabled || status == .requiresApproval)
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
        translationShortcut: HotKeyManager.Shortcut
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
    }

    private func applyPanelShortcut(_ shortcut: HotKeyManager.Shortcut) {
        panelHotKeyShortcut = shortcut
        settings.panelShortcut = shortcut
        saveSettings()
        registerHotKeys()
    }

    private func applyTranslationShortcut(_ shortcut: HotKeyManager.Shortcut) {
        translateHotKeyShortcut = shortcut
        settings.translationShortcut = shortcut
        saveSettings()
        registerHotKeys()
    }
    
    @objc
    private func statusItemButtonClicked(_ sender: NSStatusBarButton) {
        guard let currentEvent = NSApp.currentEvent else {
            togglePanel()
            return
        }
        
        if currentEvent.type == .rightMouseUp {
            showStatusMenu(using: currentEvent)
            return
        }
        
        togglePanel()
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
