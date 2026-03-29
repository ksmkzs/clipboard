//
//  ClipbordItem.swift
//  ClipboardHistory
//
//  Created by あいちゅ on 2026/02/27.
//

import SwiftData
import Foundation

enum LargeTextPolicy {
    static let inlineThresholdBytes = 256 * 1024
    static let storedPreviewCharacterLimit = 2_048
}

// クリップボードのデータ種別
enum ClipboardItemType: Int, Codable {
    case text = 0
    case image = 1
}

enum ClipboardTextFormat: Int, Codable, CaseIterable {
    case plain = 0
    case markdown = 1
}

@Model
final class ClipboardItem {
    // 検索・ソート用のメタデータ
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var type: ClipboardItemType
    var isPinned: Bool
    var pinOrder: Int?
    var dedupeKey: String?
    var isManualNote: Bool
    
    // データ本体（どちらかがnilになる想定）
    var textContent: String?
    var isLargeText: Bool
    var textByteCount: Int
    var textStorageFileName: String?
    var textFormatRawValue: Int
    var imageFileName: String? // フルパスではなくファイル名のみ保持
    
    init(
        type: ClipboardItemType,
        isPinned: Bool = false,
        pinOrder: Int? = nil,
        dedupeKey: String? = nil,
        isManualNote: Bool = false,
        textContent: String? = nil,
        isLargeText: Bool = false,
        textByteCount: Int = 0,
        textStorageFileName: String? = nil,
        textFormat: ClipboardTextFormat = .plain,
        imageFileName: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.isPinned = isPinned
        self.pinOrder = pinOrder
        self.dedupeKey = dedupeKey
        self.isManualNote = isManualNote
        self.textContent = textContent
        self.isLargeText = isLargeText
        self.textByteCount = textByteCount
        self.textStorageFileName = textStorageFileName
        self.textFormatRawValue = textFormat.rawValue
        self.imageFileName = imageFileName
    }

    var textFormat: ClipboardTextFormat {
        get { ClipboardTextFormat(rawValue: textFormatRawValue) ?? .plain }
        set { textFormatRawValue = newValue.rawValue }
    }
}
