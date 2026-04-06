#!/usr/bin/swift

import Foundation

enum CommandError: Error {
    case usage(String)
}

struct ParsedCommand {
    let action: String
    let path: String?
    let windowKind: String?
}

func parseArguments() throws -> ParsedCommand {
    var args = Array(CommandLine.arguments.dropFirst())
    guard let subcommand = args.first else {
        throw CommandError.usage("usage: app_validation_command.swift <dispatch|open-panel|toggle-status-item|snapshot|capture-window|open-file|open-new-note|open-settings|open-help|move-panel-down|move-panel-up|commit-panel-selection|toggle-pin-selected|delete-selected|open-panel-editor|set-panel-editor-text|toggle-current-editor-preview> [path]")
    }
    args.removeFirst()

    switch subcommand {
    case "open-panel":
        return ParsedCommand(action: "openPanel", path: nil, windowKind: nil)
    case "dispatch":
        guard let action = args.first else {
            throw CommandError.usage("usage: app_validation_command.swift dispatch <raw-action> [path]")
        }
        let payload = args.count > 1 ? args[1] : nil
        return ParsedCommand(action: action, path: payload, windowKind: nil)
    case "toggle-status-item":
        return ParsedCommand(action: "togglePanelFromStatusItem", path: nil, windowKind: nil)
    case "snapshot":
        guard let path = args.first else {
            throw CommandError.usage("usage: app_validation_command.swift snapshot <output-path>")
        }
        return ParsedCommand(action: "captureSnapshot", path: path, windowKind: nil)
    case "capture-window":
        guard args.count >= 2 else {
            throw CommandError.usage("usage: app_validation_command.swift capture-window <panel|standaloneNote|noteEditor|settings|help> <output-path>")
        }
        return ParsedCommand(action: "captureWindowImage", path: args[1], windowKind: args[0])
    case "open-file":
        guard let path = args.first else {
            throw CommandError.usage("usage: app_validation_command.swift open-file <file-path>")
        }
        return ParsedCommand(action: "openFile", path: path, windowKind: nil)
    case "open-new-note":
        return ParsedCommand(action: "openNewNote", path: nil, windowKind: nil)
    case "open-settings":
        return ParsedCommand(action: "openSettings", path: nil, windowKind: nil)
    case "open-help":
        return ParsedCommand(action: "openHelp", path: nil, windowKind: nil)
    case "move-panel-down":
        return ParsedCommand(action: "movePanelSelectionDown", path: nil, windowKind: nil)
    case "move-panel-up":
        return ParsedCommand(action: "movePanelSelectionUp", path: nil, windowKind: nil)
    case "commit-panel-selection":
        return ParsedCommand(action: "commitPanelSelection", path: nil, windowKind: nil)
    case "toggle-pin-selected":
        return ParsedCommand(action: "togglePinSelectedPanelItem", path: nil, windowKind: nil)
    case "delete-selected":
        return ParsedCommand(action: "deleteSelectedPanelItem", path: nil, windowKind: nil)
    case "open-panel-editor":
        return ParsedCommand(action: "openSelectedPanelEditor", path: nil, windowKind: nil)
    case "set-panel-editor-text":
        guard let path = args.first else {
            throw CommandError.usage("usage: app_validation_command.swift set-panel-editor-text <file-path>")
        }
        return ParsedCommand(action: "setPanelEditorText", path: path, windowKind: nil)
    case "toggle-current-editor-preview":
        return ParsedCommand(action: "toggleCurrentEditorMarkdownPreview", path: nil, windowKind: nil)
    default:
        throw CommandError.usage("unknown command: \(subcommand)")
    }
}

do {
    let command = try parseArguments()
    var userInfo: [AnyHashable: Any] = ["action": command.action]
    if let path = command.path {
        userInfo["path"] = path
    }
    if let windowKind = command.windowKind {
        userInfo["window"] = windowKind
    }
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("ClipboardHistoryValidationCommand"),
        object: nil,
        userInfo: userInfo,
        deliverImmediately: true
    )
} catch CommandError.usage(let message) {
    fputs(message + "\n", stderr)
    exit(2)
}
