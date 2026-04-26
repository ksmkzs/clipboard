import AppKit
import Foundation

struct PasteTargetSnapshot {
    let targetAppPID: pid_t
    let targetAppBundleIdentifier: String?
    let focusedElement: AXUIElement?
    let focusedWindow: AXUIElement?
    let selectedTextRange: CFRange?
}

struct PasteTargetDecision: Equatable {
    let snapshotPID: pid_t?
    let previousPID: pid_t?
    let placementPID: pid_t?
    let currentPID: pid_t
    let snapshotTerminated: Bool
    let previousTerminated: Bool
    let placementTerminated: Bool
}

struct PlacementTargetDecision: Equatable {
    let frontmostPID: pid_t?
    let placementPID: pid_t?
    let previousPID: pid_t?
    let currentPID: pid_t
    let frontmostTerminated: Bool
    let placementTerminated: Bool
    let previousTerminated: Bool
}

final class PasteTargetingService {
    static func preferredTargetPID(for decision: PasteTargetDecision) -> pid_t? {
        if let snapshotPID = decision.snapshotPID,
           snapshotPID != decision.currentPID,
           !decision.snapshotTerminated {
            return snapshotPID
        }

        if let previousPID = decision.previousPID,
           previousPID != decision.currentPID,
           !decision.previousTerminated {
            return previousPID
        }

        if let placementPID = decision.placementPID,
           placementPID != decision.currentPID,
           !decision.placementTerminated {
            return placementPID
        }

        return nil
    }

    static func preferredPlacementTargetPID(for decision: PlacementTargetDecision) -> pid_t? {
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

    func captureSnapshot(for targetApp: NSRunningApplication?) -> PasteTargetSnapshot? {
        guard let targetApp,
              targetApp != NSRunningApplication.current,
              !targetApp.isTerminated else {
            return nil
        }

        let focusedElement = focusedElement(in: targetApp)
        let focusedWindow = focusedWindow(in: targetApp)
        return PasteTargetSnapshot(
            targetAppPID: targetApp.processIdentifier,
            targetAppBundleIdentifier: targetApp.bundleIdentifier,
            focusedElement: focusedElement,
            focusedWindow: focusedWindow,
            selectedTextRange: focusedElement.flatMap(selectedTextRange)
        )
    }

    func resolvedSnapshot(from snapshot: PasteTargetSnapshot?) -> PasteTargetSnapshot? {
        guard let snapshot,
              let app = NSRunningApplication(processIdentifier: snapshot.targetAppPID),
              app != NSRunningApplication.current,
              !app.isTerminated else {
            return nil
        }

        if let bundleIdentifier = snapshot.targetAppBundleIdentifier,
           app.bundleIdentifier != bundleIdentifier {
            return nil
        }

        return snapshot
    }

    func resolvedTargetApp(
        snapshot: PasteTargetSnapshot?,
        previousApp: NSRunningApplication?,
        placementApp: NSRunningApplication?,
        fallbackApp: NSRunningApplication?
    ) -> NSRunningApplication? {
        let currentPID = NSRunningApplication.current.processIdentifier
        let snapshotApp = resolvedSnapshot(from: snapshot).flatMap {
            NSRunningApplication(processIdentifier: $0.targetAppPID)
        }

        let decision = PasteTargetDecision(
            snapshotPID: snapshotApp?.processIdentifier,
            previousPID: previousApp?.processIdentifier,
            placementPID: placementApp?.processIdentifier,
            currentPID: currentPID,
            snapshotTerminated: snapshotApp?.isTerminated ?? true,
            previousTerminated: previousApp?.isTerminated ?? true,
            placementTerminated: placementApp?.isTerminated ?? true
        )

        let targetPID = Self.preferredTargetPID(for: decision)
        if targetPID == snapshotApp?.processIdentifier {
            return snapshotApp
        }
        if targetPID == previousApp?.processIdentifier {
            return previousApp
        }
        if targetPID == placementApp?.processIdentifier {
            return placementApp
        }

        return fallbackApp
    }

    @discardableResult
    func restoreState(_ snapshot: PasteTargetSnapshot) -> Bool {
        var didRestore = false

        if let focusedWindow = snapshot.focusedWindow {
            didRestore = performAXAction(kAXRaiseAction as CFString, on: focusedWindow) || didRestore
            didRestore = setAXBooleanAttribute(kAXMainAttribute as CFString, value: true, on: focusedWindow) || didRestore
        }

        if let focusedElement = snapshot.focusedElement {
            didRestore = setAXBooleanAttribute(kAXFocusedAttribute as CFString, value: true, on: focusedElement) || didRestore
            if let selectedTextRange = snapshot.selectedTextRange {
                didRestore = setAXRangeAttribute(
                    kAXSelectedTextRangeAttribute as CFString,
                    value: selectedTextRange,
                    on: focusedElement
                ) || didRestore
            }
            didRestore = setAXBooleanAttribute(kAXFocusedAttribute as CFString, value: true, on: focusedElement) || didRestore
        }

        return didRestore
    }

    private func focusedElement(in app: NSRunningApplication) -> AXUIElement? {
        let application = AXUIElementCreateApplication(app.processIdentifier)

        if let explicitlyFocused = uiElementAttribute(kAXFocusedUIElementAttribute as CFString, of: application),
           let resolved = resolvedFocusableTextElement(from: explicitlyFocused) {
            return resolved
        }

        if let window = focusedWindow(in: app),
           let resolved = resolvedFocusableTextElement(from: window) {
            return resolved
        }

        if let resolved = resolvedFocusableTextElement(from: application) {
            return resolved
        }

        return uiElementAttribute(kAXFocusedUIElementAttribute as CFString, of: application)
    }

    private func focusedWindow(in app: NSRunningApplication) -> AXUIElement? {
        let application = AXUIElementCreateApplication(app.processIdentifier)

        if let element = uiElementAttribute(kAXFocusedUIElementAttribute as CFString, of: application),
           let owningWindow = uiElementAttribute(kAXWindowAttribute as CFString, of: element) {
            return owningWindow
        }

        return uiElementAttribute(kAXFocusedWindowAttribute as CFString, of: application)
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

    private func setAXBooleanAttribute(_ attribute: CFString, value: Bool, on element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(
            element,
            attribute,
            (value ? kCFBooleanTrue : kCFBooleanFalse)
        ) == .success
    }

    private func setAXRangeAttribute(_ attribute: CFString, value: CFRange, on element: AXUIElement) -> Bool {
        var mutableRange = value
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else {
            return false
        }

        return AXUIElementSetAttributeValue(element, attribute, rangeValue) == .success
    }

    private func performAXAction(_ action: CFString, on element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, action) == .success
    }
}
