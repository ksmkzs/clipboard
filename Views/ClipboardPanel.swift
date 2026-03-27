import AppKit

class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        titleVisibility = .hidden
        titlebarAppearsTransparent = false
        isMovableByWindowBackground = false
        
        isOpaque = false
        backgroundColor = .windowBackgroundColor
        hasShadow = true
    }
}
