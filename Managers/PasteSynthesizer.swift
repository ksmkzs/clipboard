//
//  PasteSynthesizer.swift
//  ClipboardHistory
//
//  Created by あいちゅ on 2026/02/27.
//

import CoreGraphics
import Foundation

class PasteSynthesizer {
    /// Cmd + V のキーストロークを合成してシステムに送信します
    static func simulateCmdV(targetPID: pid_t? = nil) {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            print("Failed to create CGEventSource")
            return
        }

        source.localEventsSuppressionInterval = 0

        let commandKeyCode: CGKeyCode = 55
        let vKeyCode: CGKeyCode = 9

        guard
            let commandDown = CGEvent(keyboardEventSource: source, virtualKey: commandKeyCode, keyDown: true),
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false),
            let commandUp = CGEvent(keyboardEventSource: source, virtualKey: commandKeyCode, keyDown: false)
        else {
            print("Failed to create CGEvents")
            return
        }

        commandDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        commandUp.flags = []

        let events = [commandDown, vDown, vUp, commandUp]
        if let targetPID {
            for event in events {
                event.postToPid(targetPID)
            }
        } else {
            for event in events {
                event.post(tap: .cghidEventTap)
            }
        }
    }

    static func simulateCmdC(targetPID: pid_t? = nil) {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            print("Failed to create CGEventSource")
            return
        }

        source.localEventsSuppressionInterval = 0

        let commandKeyCode: CGKeyCode = 55
        let cKeyCode: CGKeyCode = 8

        guard
            let commandDown = CGEvent(keyboardEventSource: source, virtualKey: commandKeyCode, keyDown: true),
            let cDown = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true),
            let cUp = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false),
            let commandUp = CGEvent(keyboardEventSource: source, virtualKey: commandKeyCode, keyDown: false)
        else {
            print("Failed to create CGEvents")
            return
        }

        commandDown.flags = .maskCommand
        cDown.flags = .maskCommand
        cUp.flags = .maskCommand
        commandUp.flags = []

        let events = [commandDown, cDown, cUp, commandUp]
        if let targetPID {
            for event in events {
                event.postToPid(targetPID)
            }
        } else {
            for event in events {
                event.post(tap: .cghidEventTap)
            }
        }
    }
}
