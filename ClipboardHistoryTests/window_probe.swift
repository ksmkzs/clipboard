#!/usr/bin/swift

import CoreGraphics
import Foundation

struct WindowSummary: Codable {
    let id: Int
    let ownerName: String
    let name: String
    let layer: Int
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

func parseArguments() -> (owner: String, countOnly: Bool) {
    var owner = "ClipboardHistory"
    var countOnly = false
    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let argument = iterator.next() {
        switch argument {
        case "--owner":
            if let value = iterator.next() {
                owner = value
            }
        case "--count":
            countOnly = true
        default:
            continue
        }
    }
    return (owner, countOnly)
}

func loadWindows(ownerName: String) -> [WindowSummary] {
    guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        return []
    }

    return info.compactMap { entry in
        guard
            let owner = entry[kCGWindowOwnerName as String] as? String,
            owner == ownerName,
            let id = entry[kCGWindowNumber as String] as? Int,
            let layer = entry[kCGWindowLayer as String] as? Int,
            let bounds = entry[kCGWindowBounds as String] as? [String: Any]
        else {
            return nil
        }

        let x = bounds["X"] as? Double ?? 0
        let y = bounds["Y"] as? Double ?? 0
        let width = bounds["Width"] as? Double ?? 0
        let height = bounds["Height"] as? Double ?? 0
        guard width > 0, height > 0 else {
            return nil
        }

        let name = entry[kCGWindowName as String] as? String ?? ""
        return WindowSummary(
            id: id,
            ownerName: owner,
            name: name,
            layer: layer,
            x: x,
            y: y,
            width: width,
            height: height
        )
    }
}

let options = parseArguments()
let windows = loadWindows(ownerName: options.owner)

if options.countOnly {
    print(windows.count)
} else {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(windows)
    FileHandle.standardOutput.write(data)
}
