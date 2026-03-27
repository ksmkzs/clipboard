//
//  ClipbordItem.swift
//  ClipboardHistory
//
//  Created by あいちゅ on 2026/02/27.
//

import SwiftData
import Foundation

// クリップボードのデータ種別
enum ClipboardItemType: Int, Codable {
    case text = 0
    case image = 1
}

@Model
final class ClipboardItem {
    // 検索・ソート用のメタデータ
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var type: ClipboardItemType
    var isPinned: Bool
    var pinOrder: Int?
    
    // データ本体（どちらかがnilになる想定）
    var textContent: String?
    var imageFileName: String? // フルパスではなくファイル名のみ保持
    
    init(
        type: ClipboardItemType,
        isPinned: Bool = false,
        pinOrder: Int? = nil,
        textContent: String? = nil,
        imageFileName: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.isPinned = isPinned
        self.pinOrder = pinOrder
        self.textContent = textContent
        self.imageFileName = imageFileName
    }
}
