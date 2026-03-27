import AppKit
import Carbon

final class HotKeyManager {
    struct RegistrationResult {
        let registrationID: UInt32?
        let status: OSStatus

        var isSuccess: Bool {
            status == noErr && registrationID != nil
        }
    }

    struct Shortcut: Codable, Equatable {
        let keyCode: UInt32
        let modifiers: UInt32
    }
    
    typealias Action = () -> Void
    
    static let shared = HotKeyManager()
    
    private static let signature = OSType("CLPB".utf8.reduce(0) { ($0 << 8) | UInt32($1) })
    
    private var nextID: UInt32 = 1
    private var actions: [UInt32: Action] = [:]
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    
    private lazy var eventHandlerUPP: EventHandlerUPP = { (_, event, userData) -> OSStatus in
        guard let userData else { return OSStatus(eventNotHandledErr) }
        let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
        return manager.handleHotKeyEvent(event)
    }
    
    private init() {
        installEventHandlerIfNeeded()
    }
    
    @discardableResult
    func register(shortcut: Shortcut, action: @escaping Action) -> UInt32? {
        let result = registerDetailed(shortcut: shortcut, action: action)
        return result.registrationID
    }

    @discardableResult
    func registerDetailed(shortcut: Shortcut, action: @escaping Action) -> RegistrationResult {
        installEventHandlerIfNeeded()
        
        let registrationID = nextID
        nextID += 1
        
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: registrationID)
        var hotKeyRef: EventHotKeyRef?
        
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        guard status == noErr, let hotKeyRef else {
            print("Failed to register hotkey \(Self.displayString(for: shortcut)) (\(status))")
            return RegistrationResult(registrationID: nil, status: status)
        }
        
        hotKeyRefs[registrationID] = hotKeyRef
        actions[registrationID] = action
        print("Registered hotkey \(Self.displayString(for: shortcut))")
        return RegistrationResult(registrationID: registrationID, status: status)
    }
    
    func unregister(registrationID: UInt32) {
        if let ref = hotKeyRefs.removeValue(forKey: registrationID) {
            UnregisterEventHotKey(ref)
        }
        actions.removeValue(forKey: registrationID)
    }
    
    static func parseShortcutString(_ input: String) -> Shortcut? {
        let tokens = input
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        
        guard !tokens.isEmpty else { return nil }
        
        var modifiers: UInt32 = 0
        var keyCode: UInt32?
        
        for token in tokens {
            if let modifier = modifierValue(for: token) {
                modifiers |= modifier
                continue
            }
            
            guard keyCode == nil, let parsedKeyCode = keyCodeMap[token] else {
                return nil
            }
            
            keyCode = parsedKeyCode
        }
        
        guard let keyCode else {
            return nil
        }
        
        return Shortcut(keyCode: keyCode, modifiers: modifiers)
    }
    
    static func displayString(for shortcut: Shortcut) -> String {
        var parts: [String] = []
        
        if shortcut.modifiers & UInt32(cmdKey) != 0 {
            parts.append("⌘")
        }
        if shortcut.modifiers & UInt32(shiftKey) != 0 {
            parts.append("⇧")
        }
        if shortcut.modifiers & UInt32(optionKey) != 0 {
            parts.append("⌥")
        }
        if shortcut.modifiers & UInt32(controlKey) != 0 {
            parts.append("⌃")
        }
        
        let key = keyDisplayMap[shortcut.keyCode] ?? "KeyCode(\(shortcut.keyCode))"
        return parts.joined() + key
    }

    static func shortcut(for event: NSEvent) -> Shortcut? {
        let modifiers = normalizedModifiers(from: event.modifierFlags)
        guard isCapturableKeyCode(event.keyCode) else {
            return nil
        }

        return Shortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers
        )
    }

    static func event(_ event: NSEvent, matches shortcut: Shortcut) -> Bool {
        UInt32(event.keyCode) == shortcut.keyCode &&
        normalizedModifiers(from: event.modifierFlags) == shortcut.modifiers
    }
    
    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            eventHandlerUPP,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        
        if status != noErr {
            print("Failed to install hotkey event handler (\(status))")
        }
    }
    
    private func handleHotKeyEvent(_ event: EventRef?) -> OSStatus {
        guard let event else { return OSStatus(eventNotHandledErr) }
        
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        
        guard status == noErr, hotKeyID.signature == Self.signature else {
            return OSStatus(eventNotHandledErr)
        }
        
        guard let action = actions[hotKeyID.id] else {
            return OSStatus(eventNotHandledErr)
        }
        
        DispatchQueue.main.async {
            action()
        }
        
        return noErr
    }
    
    private static func modifierValue(for token: String) -> UInt32? {
        switch token {
        case "cmd", "command", "⌘":
            return UInt32(cmdKey)
        case "shift", "⇧":
            return UInt32(shiftKey)
        case "opt", "option", "alt", "⌥":
            return UInt32(optionKey)
        case "ctrl", "control", "⌃":
            return UInt32(controlKey)
        default:
            return nil
        }
    }

    private static func normalizedModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let relevant = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if relevant.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        if relevant.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if relevant.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if relevant.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        return modifiers
    }

    private static func isCapturableKeyCode(_ keyCode: UInt16) -> Bool {
        keyDisplayMap[UInt32(keyCode)] != nil || keyCodeMap.values.contains(UInt32(keyCode))
    }
    
    private static let keyCodeMap: [String: UInt32] = [
        "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C), "d": UInt32(kVK_ANSI_D),
        "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F), "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H),
        "i": UInt32(kVK_ANSI_I), "j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
        "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O), "p": UInt32(kVK_ANSI_P),
        "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R), "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T),
        "u": UInt32(kVK_ANSI_U), "v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
        "y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2), "3": UInt32(kVK_ANSI_3),
        "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5), "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7),
        "8": UInt32(kVK_ANSI_8), "9": UInt32(kVK_ANSI_9),
        "space": UInt32(kVK_Space),
        "return": UInt32(kVK_Return), "enter": UInt32(kVK_Return),
        "tab": UInt32(kVK_Tab),
        "escape": UInt32(kVK_Escape), "esc": UInt32(kVK_Escape),
        "delete": UInt32(kVK_Delete), "backspace": UInt32(kVK_Delete),
        "left": UInt32(kVK_LeftArrow), "right": UInt32(kVK_RightArrow),
        "up": UInt32(kVK_UpArrow), "down": UInt32(kVK_DownArrow),
        "f1": UInt32(kVK_F1), "f2": UInt32(kVK_F2), "f3": UInt32(kVK_F3), "f4": UInt32(kVK_F4),
        "f5": UInt32(kVK_F5), "f6": UInt32(kVK_F6), "f7": UInt32(kVK_F7), "f8": UInt32(kVK_F8),
        "f9": UInt32(kVK_F9), "f10": UInt32(kVK_F10), "f11": UInt32(kVK_F11), "f12": UInt32(kVK_F12)
    ]
    
    private static let keyDisplayMap: [UInt32: String] = {
        var map: [UInt32: String] = [:]
        for (token, keyCode) in keyCodeMap where token.count == 1 || token.hasPrefix("f") {
            map[keyCode] = token.uppercased()
        }
        
        map[UInt32(kVK_Space)] = "Space"
        map[UInt32(kVK_Return)] = "Enter"
        map[UInt32(kVK_Tab)] = "Tab"
        map[UInt32(kVK_Escape)] = "Esc"
        map[UInt32(kVK_Delete)] = "Delete"
        map[UInt32(kVK_LeftArrow)] = "Left"
        map[UInt32(kVK_RightArrow)] = "Right"
        map[UInt32(kVK_UpArrow)] = "Up"
        map[UInt32(kVK_DownArrow)] = "Down"
        return map
    }()
}
