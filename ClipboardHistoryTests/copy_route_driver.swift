#!/usr/bin/swift

import AppKit

enum CopyRoute: String {
    case keyboard
    case menu
    case context
}

final class CopyRouteDriver: NSObject, NSApplicationDelegate {
    private let route: CopyRoute
    private let text: String
    private var window: NSWindow?
    private let textView = NSTextView(frame: .init(x: 0, y: 0, width: 360, height: 160))

    init(route: CopyRoute, text: String) {
        self.route = route
        self.text = text
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let scrollView = NSScrollView(frame: .init(x: 0, y: 0, width: 360, height: 160))
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView

        textView.string = text
        textView.isEditable = true
        textView.setSelectedRange(NSRange(location: 0, length: text.utf16.count))

        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 360, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(textView)
        self.window = window

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.performCopyRoute()
        }
    }

    private func performCopyRoute() {
        switch route {
        case .keyboard:
            guard let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window?.windowNumber ?? 0,
                context: nil,
                characters: "c",
                charactersIgnoringModifiers: "c",
                isARepeat: false,
                keyCode: 8
            ) else {
                NSApp.terminate(nil)
                return
            }
            _ = window?.performKeyEquivalent(with: event)
        case .menu:
            let menuItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            menuItem.target = textView
            NSApp.sendAction(#selector(NSText.copy(_:)), to: textView, from: menuItem)
        case .context:
            let menuItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
            textView.copy(menuItem)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
    }
}

func usage() -> Never {
    fputs("usage: copy_route_driver.swift <keyboard|menu|context> <text>\n", stderr)
    exit(2)
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2, let route = CopyRoute(rawValue: args[0]) else {
    usage()
}

let text = args.dropFirst().joined(separator: " ")
let app = NSApplication.shared
let delegate = CopyRouteDriver(route: route, text: text)
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
