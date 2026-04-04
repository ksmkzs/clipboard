//
//  ClipboardController.swift
//  ClipboardHistory
//
//  Created by あいちゅ on 2026/02/27.
//

import AppKit
import Carbon

class ClipboardController {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private let dataManager: ClipboardDataManager
    private var lastCapturedDedupeKey: String?
    private let pollingInterval: TimeInterval
    private let copyCapturePollingInterval: TimeInterval
    private let copyCaptureTimeout: TimeInterval
    var onExternalCapture: (() -> Void)?
    var shouldHandleKeyboardCopyEvent: (() -> Bool)?
    private var suppressNextExternalCapture = false
    private var suppressNextCopyKeyCapture = false
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var pasteboardPollingTimer: DispatchSourceTimer?
    private var pendingCopyCaptureTimer: DispatchSourceTimer?
    
    // 自アプリからのペースト（書き戻し）時に発生するイベントを無視するためのフラグ
    var isPastingInternally = false

    init(
        dataManager: ClipboardDataManager,
        pollingInterval: TimeInterval = 0.2,
        copyCapturePollingInterval: TimeInterval = 0.01,
        copyCaptureTimeout: TimeInterval = 1.2
    ) {
        self.dataManager = dataManager
        self.lastChangeCount = pasteboard.changeCount
        self.pollingInterval = pollingInterval
        self.copyCapturePollingInterval = copyCapturePollingInterval
        self.copyCaptureTimeout = copyCaptureTimeout
    }

    func startMonitoring() {
        startPasteboardPollingIfNeeded()
        installCopyEventTapIfNeeded()
    }

    func syncNow() {
        capturePasteboardIfNeeded()
    }

    func resetCaptureState() {
        lastChangeCount = pasteboard.changeCount
        lastCapturedDedupeKey = nil
        suppressNextExternalCapture = false
        suppressNextCopyKeyCapture = false
        isPastingInternally = false
        pendingCopyCaptureTimer?.cancel()
        pendingCopyCaptureTimer = nil
    }

    deinit {
        if let runLoopSource = eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        pasteboardPollingTimer?.cancel()
        pendingCopyCaptureTimer?.cancel()
    }

    private func startPasteboardPollingIfNeeded() {
        guard pasteboardPollingTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + pollingInterval, repeating: pollingInterval)
        timer.setEventHandler { [weak self] in
            self?.capturePasteboardIfNeeded()
        }
        pasteboardPollingTimer = timer
        timer.resume()
    }

    private func installCopyEventTapIfNeeded() {
        guard eventTap == nil else { return }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passRetained(event)
            }

            let controller = Unmanaged<ClipboardController>.fromOpaque(userInfo).takeUnretainedValue()
            return controller.handleEventTap(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        eventTapRunLoopSource = runLoopSource
    }

    private func handleEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passRetained(event)
        }

        if suppressNextCopyKeyCapture {
            suppressNextCopyKeyCapture = false
            return Unmanaged.passRetained(event)
        }

        guard shouldHandleKeyboardCopyEvent?() ?? true else {
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags
        guard flags.contains(.maskCommand),
              !flags.contains(.maskShift),
              !flags.contains(.maskAlternate),
              !flags.contains(.maskControl) else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == CGKeyCode(kVK_ANSI_C) || keyCode == CGKeyCode(kVK_ANSI_X) else {
            return Unmanaged.passRetained(event)
        }

        beginAwaitingExternalCopy()
        return Unmanaged.passRetained(event)
    }

    private func beginAwaitingExternalCopy() {
        pendingCopyCaptureTimer?.cancel()

        let previousChangeCount = pasteboard.changeCount
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        let maxAttempts = max(1, Int(ceil(copyCaptureTimeout / copyCapturePollingInterval)))
        var attemptsRemaining = maxAttempts
        timer.schedule(deadline: .now() + copyCapturePollingInterval, repeating: copyCapturePollingInterval)
        timer.setEventHandler { [weak self] in
            guard let self else {
                timer.cancel()
                return
            }

            if self.pasteboard.changeCount != previousChangeCount {
                timer.cancel()
                self.pendingCopyCaptureTimer = nil
                self.capturePasteboardIfNeeded()
                return
            }

            attemptsRemaining -= 1
            if attemptsRemaining <= 0 {
                timer.cancel()
                self.pendingCopyCaptureTimer = nil
            }
        }
        pendingCopyCaptureTimer = timer
        timer.resume()
    }

    private func capturePasteboardIfNeeded() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        
        guard !isPastingInternally else { return }
        if suppressNextExternalCapture {
            suppressNextExternalCapture = false
            return
        }
        guard let capture = dataManager.captureFromPasteboard(pasteboard) else { return }
        
        let isDuplicateCapture = capture.dedupeKey == lastCapturedDedupeKey
        if !isDuplicateCapture {
            lastCapturedDedupeKey = capture.dedupeKey
            dataManager.storeCapture(capture)
        }
        DispatchQueue.main.async { [weak self] in
            self?.onExternalCapture?()
        }
    }
    
    func prepareForInternalPaste() {
        isPastingInternally = true
    }

    func suppressNextCapturedExternalCopy() {
        suppressNextExternalCapture = true
    }

    func suppressNextCapturedCopyKeystroke() {
        suppressNextCopyKeyCapture = true
    }
    
    func finishInternalPaste() {
        // ペースト処理完了後、自身の書き込みによるchangeCountを最新として記憶
        lastChangeCount = pasteboard.changeCount
        isPastingInternally = false
    }
}
