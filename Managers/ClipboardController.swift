//
//  ClipboardController.swift
//  ClipboardHistory
//
//  Created by あいちゅ on 2026/02/27.
//

import AppKit

class ClipboardController {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private let dataManager: ClipboardDataManager
    private var lastCapturedDedupeKey: String?
    
    // 自アプリからのペースト（書き戻し）時に発生するイベントを無視するためのフラグ
    var isPastingInternally = false

    init(dataManager: ClipboardDataManager) {
        self.dataManager = dataManager
        self.lastChangeCount = pasteboard.changeCount
    }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
        // メインスレッドのRunLoopに登録し、UI操作中もタイマーが止まらないようにする
        RunLoop.current.add(timer!, forMode: .common)
    }

    private func checkForChanges() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        
        guard !isPastingInternally else { return }
        guard let capture = dataManager.captureFromPasteboard(pasteboard) else { return }
        
        if capture.dedupeKey == lastCapturedDedupeKey {
            return
        }
        
        lastCapturedDedupeKey = capture.dedupeKey
        dataManager.storeCapture(capture)
    }
    
    func prepareForInternalPaste() {
        isPastingInternally = true
    }
    
    func finishInternalPaste() {
        // ペースト処理完了後、自身の書き込みによるchangeCountを最新として記憶
        lastChangeCount = pasteboard.changeCount
        isPastingInternally = false
    }
}
