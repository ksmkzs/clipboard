import Carbon
import Foundation
import SwiftUI

enum SettingsLanguage: String, Codable, CaseIterable, Identifiable {
    case english = "en"
    case japanese = "ja"

    var id: String { rawValue }
}

enum NewNoteReopenBehavior: String, Codable, CaseIterable, Identifiable {
    case reset
    case restoreLastDraft

    var id: String { rawValue }
}

enum InterfaceThemePreset: String, Codable, CaseIterable, Identifiable {
    case graphite
    case terminal
    case amber
    case frost
    case nord
    case cobalt
    case sakura
    case forest

    var id: String { rawValue }
}

struct TranslationLanguageOption: Identifiable, Hashable {
    let code: String
    let englishName: String
    let japaneseName: String

    var id: String { code }

    func displayName(for language: SettingsLanguage) -> String {
        language == .japanese ? japaneseName : englishName
    }
}

struct AppSettings: Equatable {
    static let minInterfaceZoomScale = 0.8
    static let maxInterfaceZoomScale = 1.6
    static let defaultInterfaceZoomScale = 1.0
    static let defaultPanelShortcut = HotKeyManager.Shortcut(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(shiftKey | cmdKey)
    )
    static let defaultTranslationShortcut = HotKeyManager.Shortcut(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: UInt32(shiftKey | cmdKey)
    )
    static let defaultGlobalNewNoteShortcut = HotKeyManager.Shortcut(
        keyCode: UInt32(kVK_ANSI_N),
        modifiers: UInt32(controlKey | cmdKey)
    )
    static let defaultGlobalCopyJoinedShortcut = HotKeyManager.Shortcut(
        keyCode: UInt32(kVK_ANSI_C),
        modifiers: UInt32(optionKey | cmdKey)
    )
    static let defaultGlobalCopyNormalizedShortcut = HotKeyManager.Shortcut(
        keyCode: UInt32(kVK_ANSI_C),
        modifiers: UInt32(shiftKey | cmdKey)
    )
    static let defaultOrphanCodexDiscardShortcut = HotKeyManager.Shortcut(
        keyCode: UInt32(kVK_ANSI_D),
        modifiers: UInt32(shiftKey | cmdKey)
    )
    static let legacyPanelShortcut = HotKeyManager.Shortcut(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(controlKey | optionKey | shiftKey)
    )
    static let legacyTranslationShortcut = HotKeyManager.Shortcut(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: UInt32(controlKey | optionKey | shiftKey)
    )
    static let previousDefaultPanelShortcut = HotKeyManager.Shortcut(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(controlKey | optionKey)
    )
    static let previousDefaultTranslationShortcut = HotKeyManager.Shortcut(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: UInt32(controlKey | optionKey)
    )
    static let legacyLocalNewNoteShortcut = HotKeyManager.Shortcut(
        keyCode: UInt32(kVK_ANSI_N),
        modifiers: UInt32(cmdKey)
    )
    static let legacyJoinLinesShortcut = HotKeyManager.Shortcut(
        keyCode: UInt32(kVK_ANSI_J),
        modifiers: UInt32(cmdKey)
    )
    static let legacyNormalizeForCommandShortcut = HotKeyManager.Shortcut(
        keyCode: UInt32(kVK_ANSI_J),
        modifiers: UInt32(cmdKey | shiftKey)
    )
    static let previousLocalNewNoteShortcut = HotKeyManager.Shortcut(
        keyCode: UInt32(kVK_ANSI_N),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    var panelShortcut: HotKeyManager.Shortcut
    var translationShortcut: HotKeyManager.Shortcut
    var globalNewNoteShortcut: HotKeyManager.Shortcut?
    var globalCopyJoinedShortcut: HotKeyManager.Shortcut?
    var globalCopyNormalizedShortcut: HotKeyManager.Shortcut?
    var globalCopyJoinedEnabled: Bool
    var globalCopyNormalizedEnabled: Bool
    var togglePinShortcut: HotKeyManager.Shortcut
    var togglePinnedAreaShortcut: HotKeyManager.Shortcut
    var newNoteShortcut: HotKeyManager.Shortcut
    var editTextShortcut: HotKeyManager.Shortcut
    var commitEditShortcut: HotKeyManager.Shortcut
    var deleteItemShortcut: HotKeyManager.Shortcut
    var undoShortcut: HotKeyManager.Shortcut
    var redoShortcut: HotKeyManager.Shortcut
    var indentShortcut: HotKeyManager.Shortcut
    var outdentShortcut: HotKeyManager.Shortcut
    var moveLineUpShortcut: HotKeyManager.Shortcut
    var moveLineDownShortcut: HotKeyManager.Shortcut
    var copyJoinedShortcut: HotKeyManager.Shortcut
    var copyNormalizedShortcut: HotKeyManager.Shortcut
    var toggleMarkdownPreviewShortcut: HotKeyManager.Shortcut
    var joinLinesShortcut: HotKeyManager.Shortcut
    var normalizeForCommandShortcut: HotKeyManager.Shortcut
    var orphanCodexDiscardShortcut: HotKeyManager.Shortcut
    var launchAtLogin: Bool
    var translationTargetLanguage: String
    var historyLimit: Int
    var settingsLanguage: SettingsLanguage
    var interfaceZoomScale: Double
    var newNoteReopenBehavior: NewNoteReopenBehavior
    var interfaceThemePreset: InterfaceThemePreset

    static let `default` = AppSettings(
        panelShortcut: defaultPanelShortcut,
        translationShortcut: defaultTranslationShortcut,
        globalNewNoteShortcut: defaultGlobalNewNoteShortcut,
        globalCopyJoinedShortcut: defaultGlobalCopyJoinedShortcut,
        globalCopyNormalizedShortcut: defaultGlobalCopyNormalizedShortcut,
        globalCopyJoinedEnabled: true,
        globalCopyNormalizedEnabled: true,
        togglePinShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: 0
        ),
        togglePinnedAreaShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_Tab),
            modifiers: 0
        ),
        newNoteShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_N),
            modifiers: 0
        ),
        editTextShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_E),
            modifiers: 0
        ),
        commitEditShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_Return),
            modifiers: UInt32(cmdKey)
        ),
        deleteItemShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_Delete),
            modifiers: 0
        ),
        undoShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_Z),
            modifiers: UInt32(cmdKey)
        ),
        redoShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_Z),
            modifiers: UInt32(cmdKey | shiftKey)
        ),
        indentShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_Tab),
            modifiers: 0
        ),
        outdentShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_Tab),
            modifiers: UInt32(shiftKey)
        ),
        moveLineUpShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_UpArrow),
            modifiers: UInt32(optionKey)
        ),
        moveLineDownShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_DownArrow),
            modifiers: UInt32(optionKey)
        ),
        copyJoinedShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(cmdKey | optionKey)
        ),
        copyNormalizedShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(cmdKey | shiftKey)
        ),
        toggleMarkdownPreviewShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: UInt32(cmdKey | optionKey)
        ),
        joinLinesShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(cmdKey | optionKey)
        ),
        normalizeForCommandShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(cmdKey | shiftKey)
        ),
        orphanCodexDiscardShortcut: defaultOrphanCodexDiscardShortcut,
        launchAtLogin: false,
        translationTargetLanguage: "ja",
        historyLimit: 150,
        settingsLanguage: .english,
        interfaceZoomScale: defaultInterfaceZoomScale,
        newNoteReopenBehavior: .reset,
        interfaceThemePreset: .graphite
    )

    var clampedInterfaceZoomScale: Double {
        min(Self.maxInterfaceZoomScale, max(Self.minInterfaceZoomScale, interfaceZoomScale))
    }
}

struct InterfaceThemeDefinition {
    let titleEnglish: String
    let titleJapanese: String
    let previewColors: [Color]
    let panelOverlay: Color
    let headerFill: Color
    let hintFill: Color
    let cardFill: Color
    let focusFill: Color
    let selectedFill: Color
    let pinnedSidebarFill: Color
    let toggleAccent: Color
    let primaryText: Color
    let secondaryText: Color
}

extension InterfaceThemePreset {
    var definition: InterfaceThemeDefinition {
        switch self {
        case .graphite:
            return InterfaceThemeDefinition(
                titleEnglish: "Graphite",
                titleJapanese: "グラファイト",
                previewColors: [Color(hex: 0x5B6675), Color(hex: 0x9099A5), Color(hex: 0xD8DEE6)],
                panelOverlay: Color.white.opacity(0.12),
                headerFill: Color.black.opacity(0.08),
                hintFill: Color.black.opacity(0.16),
                cardFill: Color.white.opacity(0.20),
                focusFill: Color.white.opacity(0.27),
                selectedFill: Color(red: 0.72, green: 0.80, blue: 0.90).opacity(0.34),
                pinnedSidebarFill: Color(red: 0.98, green: 0.96, blue: 0.76).opacity(0.18),
                toggleAccent: Color(red: 0.78, green: 0.64, blue: 0.28),
                primaryText: Color.white.opacity(0.96),
                secondaryText: Color.white.opacity(0.72)
            )
        case .terminal:
            return InterfaceThemeDefinition(
                titleEnglish: "Terminal",
                titleJapanese: "ターミナル",
                previewColors: [Color(hex: 0x0D1B12), Color(hex: 0x21C55D), Color(hex: 0xC2F5D3)],
                panelOverlay: Color(red: 0.04, green: 0.11, blue: 0.07).opacity(0.32),
                headerFill: Color(red: 0.03, green: 0.10, blue: 0.06).opacity(0.60),
                hintFill: Color(red: 0.06, green: 0.16, blue: 0.09).opacity(0.72),
                cardFill: Color(red: 0.10, green: 0.17, blue: 0.12).opacity(0.70),
                focusFill: Color(red: 0.14, green: 0.24, blue: 0.16).opacity(0.78),
                selectedFill: Color(red: 0.20, green: 0.42, blue: 0.24).opacity(0.88),
                pinnedSidebarFill: Color(red: 0.09, green: 0.17, blue: 0.11).opacity(0.54),
                toggleAccent: Color(hex: 0x32D074),
                primaryText: Color(hex: 0xD6F5E1),
                secondaryText: Color(hex: 0x9FD7B5)
            )
        case .amber:
            return InterfaceThemeDefinition(
                titleEnglish: "Amber",
                titleJapanese: "アンバー",
                previewColors: [Color(hex: 0x24160A), Color(hex: 0xF59E0B), Color(hex: 0xF9DFA7)],
                panelOverlay: Color(red: 0.19, green: 0.12, blue: 0.03).opacity(0.26),
                headerFill: Color(red: 0.17, green: 0.10, blue: 0.03).opacity(0.58),
                hintFill: Color(red: 0.22, green: 0.14, blue: 0.04).opacity(0.70),
                cardFill: Color(red: 0.28, green: 0.19, blue: 0.07).opacity(0.56),
                focusFill: Color(red: 0.34, green: 0.22, blue: 0.08).opacity(0.64),
                selectedFill: Color(red: 0.62, green: 0.41, blue: 0.08).opacity(0.76),
                pinnedSidebarFill: Color(red: 0.30, green: 0.19, blue: 0.06).opacity(0.42),
                toggleAccent: Color(hex: 0xF8B84A),
                primaryText: Color(hex: 0xFFF1D2),
                secondaryText: Color(hex: 0xE0C089)
            )
        case .frost:
            return InterfaceThemeDefinition(
                titleEnglish: "Frost",
                titleJapanese: "フロスト",
                previewColors: [Color(hex: 0x152330), Color(hex: 0x60A5FA), Color(hex: 0xD9EEFF)],
                panelOverlay: Color(red: 0.10, green: 0.17, blue: 0.24).opacity(0.24),
                headerFill: Color(red: 0.09, green: 0.15, blue: 0.21).opacity(0.52),
                hintFill: Color(red: 0.11, green: 0.19, blue: 0.26).opacity(0.64),
                cardFill: Color(red: 0.78, green: 0.87, blue: 0.96).opacity(0.24),
                focusFill: Color(red: 0.83, green: 0.92, blue: 0.99).opacity(0.32),
                selectedFill: Color(red: 0.47, green: 0.71, blue: 0.96).opacity(0.42),
                pinnedSidebarFill: Color(red: 0.78, green: 0.87, blue: 0.96).opacity(0.28),
                toggleAccent: Color(hex: 0x7DBDFF),
                primaryText: Color(hex: 0xF1F8FF),
                secondaryText: Color(hex: 0xC7DCEF)
            )
        case .nord:
            return InterfaceThemeDefinition(
                titleEnglish: "Nord",
                titleJapanese: "ノルド",
                previewColors: [Color(hex: 0x2E3440), Color(hex: 0x88C0D0), Color(hex: 0xE5E9F0)],
                panelOverlay: Color(hex: 0x2E3440).opacity(0.20),
                headerFill: Color(hex: 0x2B313C).opacity(0.62),
                hintFill: Color(hex: 0x35404D).opacity(0.72),
                cardFill: Color(hex: 0x434C5E).opacity(0.55),
                focusFill: Color(hex: 0x4C566A).opacity(0.68),
                selectedFill: Color(hex: 0x88C0D0).opacity(0.46),
                pinnedSidebarFill: Color(hex: 0x3B4252).opacity(0.50),
                toggleAccent: Color(hex: 0x81A1C1),
                primaryText: Color(hex: 0xECEFF4),
                secondaryText: Color(hex: 0xD8DEE9)
            )
        case .cobalt:
            return InterfaceThemeDefinition(
                titleEnglish: "Cobalt",
                titleJapanese: "コバルト",
                previewColors: [Color(hex: 0x10203F), Color(hex: 0x4FB3FF), Color(hex: 0xE6F4FF)],
                panelOverlay: Color(hex: 0x0F1C36).opacity(0.24),
                headerFill: Color(hex: 0x10203F).opacity(0.60),
                hintFill: Color(hex: 0x15305C).opacity(0.68),
                cardFill: Color(hex: 0x1F3A66).opacity(0.52),
                focusFill: Color(hex: 0x274A84).opacity(0.62),
                selectedFill: Color(hex: 0x4FB3FF).opacity(0.50),
                pinnedSidebarFill: Color(hex: 0x183155).opacity(0.44),
                toggleAccent: Color(hex: 0x79C6FF),
                primaryText: Color(hex: 0xF3FAFF),
                secondaryText: Color(hex: 0xD2E9FF)
            )
        case .sakura:
            return InterfaceThemeDefinition(
                titleEnglish: "Sakura",
                titleJapanese: "サクラ",
                previewColors: [Color(hex: 0x3C2230), Color(hex: 0xF38BA8), Color(hex: 0xFFE5EE)],
                panelOverlay: Color(hex: 0x3C2230).opacity(0.18),
                headerFill: Color(hex: 0x402634).opacity(0.58),
                hintFill: Color(hex: 0x563345).opacity(0.66),
                cardFill: Color(hex: 0x694459).opacity(0.48),
                focusFill: Color(hex: 0x7D536B).opacity(0.60),
                selectedFill: Color(hex: 0xF38BA8).opacity(0.42),
                pinnedSidebarFill: Color(hex: 0x583949).opacity(0.40),
                toggleAccent: Color(hex: 0xFFC2D4),
                primaryText: Color(hex: 0xFFF4F8),
                secondaryText: Color(hex: 0xF4D6E0)
            )
        case .forest:
            return InterfaceThemeDefinition(
                titleEnglish: "Forest",
                titleJapanese: "フォレスト",
                previewColors: [Color(hex: 0x102416), Color(hex: 0x34D399), Color(hex: 0xDDF9ED)],
                panelOverlay: Color(hex: 0x102416).opacity(0.22),
                headerFill: Color(hex: 0x132A1A).opacity(0.62),
                hintFill: Color(hex: 0x173522).opacity(0.72),
                cardFill: Color(hex: 0x1F4630).opacity(0.54),
                focusFill: Color(hex: 0x295840).opacity(0.68),
                selectedFill: Color(hex: 0x34D399).opacity(0.44),
                pinnedSidebarFill: Color(hex: 0x173926).opacity(0.44),
                toggleAccent: Color(hex: 0x6BE5B5),
                primaryText: Color(hex: 0xEFFBF4),
                secondaryText: Color(hex: 0xCBEED9)
            )
        }
    }
}

extension AppSettings {
    var interfaceTheme: InterfaceThemeDefinition {
        interfaceThemePreset.definition
    }
}

private extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

enum SupportedTranslationLanguages {
    static let all: [TranslationLanguageOption] = [
        .init(code: "ar", englishName: "Arabic", japaneseName: "アラビア語"),
        .init(code: "bn", englishName: "Bengali", japaneseName: "ベンガル語"),
        .init(code: "bg", englishName: "Bulgarian", japaneseName: "ブルガリア語"),
        .init(code: "ca", englishName: "Catalan", japaneseName: "カタロニア語"),
        .init(code: "zh-CN", englishName: "Chinese (Simplified)", japaneseName: "中国語（簡体字）"),
        .init(code: "zh-TW", englishName: "Chinese (Traditional)", japaneseName: "中国語（繁体字）"),
        .init(code: "hr", englishName: "Croatian", japaneseName: "クロアチア語"),
        .init(code: "cs", englishName: "Czech", japaneseName: "チェコ語"),
        .init(code: "da", englishName: "Danish", japaneseName: "デンマーク語"),
        .init(code: "nl", englishName: "Dutch", japaneseName: "オランダ語"),
        .init(code: "en", englishName: "English", japaneseName: "英語"),
        .init(code: "et", englishName: "Estonian", japaneseName: "エストニア語"),
        .init(code: "fi", englishName: "Finnish", japaneseName: "フィンランド語"),
        .init(code: "fr", englishName: "French", japaneseName: "フランス語"),
        .init(code: "de", englishName: "German", japaneseName: "ドイツ語"),
        .init(code: "el", englishName: "Greek", japaneseName: "ギリシャ語"),
        .init(code: "gu", englishName: "Gujarati", japaneseName: "グジャラート語"),
        .init(code: "iw", englishName: "Hebrew", japaneseName: "ヘブライ語"),
        .init(code: "hi", englishName: "Hindi", japaneseName: "ヒンディー語"),
        .init(code: "hu", englishName: "Hungarian", japaneseName: "ハンガリー語"),
        .init(code: "id", englishName: "Indonesian", japaneseName: "インドネシア語"),
        .init(code: "it", englishName: "Italian", japaneseName: "イタリア語"),
        .init(code: "ja", englishName: "Japanese", japaneseName: "日本語"),
        .init(code: "ko", englishName: "Korean", japaneseName: "韓国語"),
        .init(code: "lv", englishName: "Latvian", japaneseName: "ラトビア語"),
        .init(code: "lt", englishName: "Lithuanian", japaneseName: "リトアニア語"),
        .init(code: "ms", englishName: "Malay", japaneseName: "マレー語"),
        .init(code: "ml", englishName: "Malayalam", japaneseName: "マラヤーラム語"),
        .init(code: "mr", englishName: "Marathi", japaneseName: "マラーティー語"),
        .init(code: "no", englishName: "Norwegian", japaneseName: "ノルウェー語"),
        .init(code: "fa", englishName: "Persian", japaneseName: "ペルシャ語"),
        .init(code: "pl", englishName: "Polish", japaneseName: "ポーランド語"),
        .init(code: "pt", englishName: "Portuguese", japaneseName: "ポルトガル語"),
        .init(code: "pa", englishName: "Punjabi", japaneseName: "パンジャブ語"),
        .init(code: "ro", englishName: "Romanian", japaneseName: "ルーマニア語"),
        .init(code: "ru", englishName: "Russian", japaneseName: "ロシア語"),
        .init(code: "sr", englishName: "Serbian", japaneseName: "セルビア語"),
        .init(code: "sk", englishName: "Slovak", japaneseName: "スロバキア語"),
        .init(code: "sl", englishName: "Slovenian", japaneseName: "スロベニア語"),
        .init(code: "es", englishName: "Spanish", japaneseName: "スペイン語"),
        .init(code: "sw", englishName: "Swahili", japaneseName: "スワヒリ語"),
        .init(code: "sv", englishName: "Swedish", japaneseName: "スウェーデン語"),
        .init(code: "ta", englishName: "Tamil", japaneseName: "タミル語"),
        .init(code: "te", englishName: "Telugu", japaneseName: "テルグ語"),
        .init(code: "th", englishName: "Thai", japaneseName: "タイ語"),
        .init(code: "tr", englishName: "Turkish", japaneseName: "トルコ語"),
        .init(code: "uk", englishName: "Ukrainian", japaneseName: "ウクライナ語"),
        .init(code: "ur", englishName: "Urdu", japaneseName: "ウルドゥー語"),
        .init(code: "vi", englishName: "Vietnamese", japaneseName: "ベトナム語")
    ]

    static func contains(code: String) -> Bool {
        all.contains { $0.code == code }
    }
}

protocol AppSettingsStore {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

final class UserDefaultsAppSettingsStore: AppSettingsStore {
    private enum Key {
        static let migrationVersion = "app.settings.migrationVersion"
        static let panelShortcut = "hotkey.toggle.panel"
        static let translationShortcut = "hotkey.translate.current"
        static let globalNewNoteShortcut = "hotkey.global.newNote"
        static let globalCopyJoinedShortcut = "hotkey.global.copyJoined"
        static let globalCopyNormalizedShortcut = "hotkey.global.copyNormalized"
        static let globalCopyJoinedEnabled = "hotkey.global.copyJoined.enabled"
        static let globalCopyNormalizedEnabled = "hotkey.global.copyNormalized.enabled"
        static let togglePinShortcut = "hotkey.local.togglePin"
        static let togglePinnedAreaShortcut = "hotkey.local.togglePinnedArea"
        static let newNoteShortcut = "hotkey.local.newNote"
        static let editTextShortcut = "hotkey.local.editText"
        static let commitEditShortcut = "hotkey.local.commitEdit"
        static let deleteItemShortcut = "hotkey.local.delete"
        static let undoShortcut = "hotkey.local.undo"
        static let redoShortcut = "hotkey.local.redo"
        static let indentShortcut = "hotkey.editor.indent"
        static let outdentShortcut = "hotkey.editor.outdent"
        static let moveLineUpShortcut = "hotkey.editor.moveLineUp"
        static let moveLineDownShortcut = "hotkey.editor.moveLineDown"
        static let copyJoinedShortcut = "hotkey.local.copyJoined"
        static let copyNormalizedShortcut = "hotkey.local.copyNormalized"
        static let toggleMarkdownPreviewShortcut = "hotkey.editor.toggleMarkdownPreview"
        static let joinLinesShortcut = "hotkey.editor.joinLines"
        static let normalizeForCommandShortcut = "hotkey.editor.normalizeForCommand"
        static let orphanCodexDiscardShortcut = "hotkey.codex.orphanDiscard"
        static let launchAtLogin = "app.launchAtLogin"
        static let translationTargetLanguage = "translation.targetLanguage"
        static let historyLimit = "history.limit"
        static let settingsLanguage = "settings.language"
        static let interfaceZoomScale = "ui.zoomScale"
        static let newNoteReopenBehavior = "note.reopenBehavior"
        static let interfaceThemePreset = "ui.themePreset"
    }

    private let userDefaults: UserDefaults
    private static let currentMigrationVersion = 10

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> AppSettings {
        var settings = AppSettings.default

        if let shortcut = loadShortcut(forKey: Key.panelShortcut) {
            settings.panelShortcut = shortcut
        }
        if let shortcut = loadShortcut(forKey: Key.translationShortcut) {
            settings.translationShortcut = shortcut
        }
        settings.globalNewNoteShortcut = loadShortcut(forKey: Key.globalNewNoteShortcut)
        settings.globalCopyJoinedShortcut = loadShortcut(forKey: Key.globalCopyJoinedShortcut)
        settings.globalCopyNormalizedShortcut = loadShortcut(forKey: Key.globalCopyNormalizedShortcut)
        if userDefaults.object(forKey: Key.globalCopyJoinedEnabled) != nil {
            settings.globalCopyJoinedEnabled = userDefaults.bool(forKey: Key.globalCopyJoinedEnabled)
        }
        if userDefaults.object(forKey: Key.globalCopyNormalizedEnabled) != nil {
            settings.globalCopyNormalizedEnabled = userDefaults.bool(forKey: Key.globalCopyNormalizedEnabled)
        }
        if let shortcut = loadShortcut(forKey: Key.togglePinShortcut) {
            settings.togglePinShortcut = shortcut
        }
        if let shortcut = loadShortcut(forKey: Key.togglePinnedAreaShortcut) {
            settings.togglePinnedAreaShortcut = shortcut
        }
        if let shortcut = loadShortcut(forKey: Key.newNoteShortcut) {
            settings.newNoteShortcut = shortcut
        }
        if let shortcut = loadShortcut(forKey: Key.editTextShortcut) {
            settings.editTextShortcut = shortcut
        }
        if let shortcut = loadShortcut(forKey: Key.commitEditShortcut) {
            settings.commitEditShortcut = shortcut
        }
        if let shortcut = loadShortcut(forKey: Key.deleteItemShortcut) {
            settings.deleteItemShortcut = shortcut
        }
        if let shortcut = loadShortcut(forKey: Key.undoShortcut) {
            settings.undoShortcut = shortcut
        }
        if let shortcut = loadShortcut(forKey: Key.redoShortcut) {
            settings.redoShortcut = shortcut
        }
        if let shortcut = loadShortcut(forKey: Key.indentShortcut) {
            settings.indentShortcut = shortcut
        }
        if let shortcut = loadShortcut(forKey: Key.outdentShortcut) {
            settings.outdentShortcut = shortcut
        }
        if let shortcut = loadShortcut(forKey: Key.moveLineUpShortcut) {
            settings.moveLineUpShortcut = shortcut
        }
        if let shortcut = loadShortcut(forKey: Key.moveLineDownShortcut) {
            settings.moveLineDownShortcut = shortcut
        }
        if let shortcut = loadShortcut(forKey: Key.copyJoinedShortcut) {
            settings.copyJoinedShortcut = shortcut
        }
        if let shortcut = loadShortcut(forKey: Key.copyNormalizedShortcut) {
            settings.copyNormalizedShortcut = shortcut
        }
        if let shortcut = loadShortcut(forKey: Key.toggleMarkdownPreviewShortcut) {
            settings.toggleMarkdownPreviewShortcut = shortcut
        }
        if let shortcut = loadShortcut(forKey: Key.joinLinesShortcut) {
            settings.joinLinesShortcut = shortcut
        }
        if let shortcut = loadShortcut(forKey: Key.normalizeForCommandShortcut) {
            settings.normalizeForCommandShortcut = shortcut
        }
        if let shortcut = loadShortcut(forKey: Key.orphanCodexDiscardShortcut) {
            settings.orphanCodexDiscardShortcut = shortcut
        }
        if userDefaults.object(forKey: Key.launchAtLogin) != nil {
            settings.launchAtLogin = userDefaults.bool(forKey: Key.launchAtLogin)
        }
        if let language = userDefaults.string(forKey: Key.translationTargetLanguage),
           SupportedTranslationLanguages.contains(code: language) {
            settings.translationTargetLanguage = language
        }
        if userDefaults.object(forKey: Key.historyLimit) != nil {
            settings.historyLimit = max(1, userDefaults.integer(forKey: Key.historyLimit))
        }
        if let rawValue = userDefaults.string(forKey: Key.settingsLanguage),
           let language = SettingsLanguage(rawValue: rawValue) {
            settings.settingsLanguage = language
        }
        if userDefaults.object(forKey: Key.interfaceZoomScale) != nil {
            settings.interfaceZoomScale = userDefaults.double(forKey: Key.interfaceZoomScale)
            settings.interfaceZoomScale = settings.clampedInterfaceZoomScale
        }
        if let rawValue = userDefaults.string(forKey: Key.newNoteReopenBehavior),
           let behavior = NewNoteReopenBehavior(rawValue: rawValue) {
            settings.newNoteReopenBehavior = behavior
        }
        if let rawValue = userDefaults.string(forKey: Key.interfaceThemePreset),
           let theme = InterfaceThemePreset(rawValue: rawValue) {
            settings.interfaceThemePreset = theme
        }

        if migrateLegacyGlobalShortcutsIfNeeded(settings: &settings) {
            save(settings)
        }

        return settings
    }

    func save(_ settings: AppSettings) {
        saveShortcut(settings.panelShortcut, forKey: Key.panelShortcut)
        saveShortcut(settings.translationShortcut, forKey: Key.translationShortcut)
        saveOptionalShortcut(settings.globalNewNoteShortcut, forKey: Key.globalNewNoteShortcut)
        saveOptionalShortcut(settings.globalCopyJoinedShortcut, forKey: Key.globalCopyJoinedShortcut)
        saveOptionalShortcut(settings.globalCopyNormalizedShortcut, forKey: Key.globalCopyNormalizedShortcut)
        userDefaults.set(settings.globalCopyJoinedEnabled, forKey: Key.globalCopyJoinedEnabled)
        userDefaults.set(settings.globalCopyNormalizedEnabled, forKey: Key.globalCopyNormalizedEnabled)
        saveShortcut(settings.togglePinShortcut, forKey: Key.togglePinShortcut)
        saveShortcut(settings.togglePinnedAreaShortcut, forKey: Key.togglePinnedAreaShortcut)
        saveShortcut(settings.newNoteShortcut, forKey: Key.newNoteShortcut)
        saveShortcut(settings.editTextShortcut, forKey: Key.editTextShortcut)
        saveShortcut(settings.commitEditShortcut, forKey: Key.commitEditShortcut)
        saveShortcut(settings.deleteItemShortcut, forKey: Key.deleteItemShortcut)
        saveShortcut(settings.undoShortcut, forKey: Key.undoShortcut)
        saveShortcut(settings.redoShortcut, forKey: Key.redoShortcut)
        saveShortcut(settings.indentShortcut, forKey: Key.indentShortcut)
        saveShortcut(settings.outdentShortcut, forKey: Key.outdentShortcut)
        saveShortcut(settings.moveLineUpShortcut, forKey: Key.moveLineUpShortcut)
        saveShortcut(settings.moveLineDownShortcut, forKey: Key.moveLineDownShortcut)
        saveShortcut(settings.copyJoinedShortcut, forKey: Key.copyJoinedShortcut)
        saveShortcut(settings.copyNormalizedShortcut, forKey: Key.copyNormalizedShortcut)
        saveShortcut(settings.toggleMarkdownPreviewShortcut, forKey: Key.toggleMarkdownPreviewShortcut)
        saveShortcut(settings.joinLinesShortcut, forKey: Key.joinLinesShortcut)
        saveShortcut(settings.normalizeForCommandShortcut, forKey: Key.normalizeForCommandShortcut)
        saveShortcut(settings.orphanCodexDiscardShortcut, forKey: Key.orphanCodexDiscardShortcut)
        userDefaults.set(settings.launchAtLogin, forKey: Key.launchAtLogin)
        userDefaults.set(settings.translationTargetLanguage, forKey: Key.translationTargetLanguage)
        userDefaults.set(max(1, settings.historyLimit), forKey: Key.historyLimit)
        userDefaults.set(settings.settingsLanguage.rawValue, forKey: Key.settingsLanguage)
        userDefaults.set(settings.clampedInterfaceZoomScale, forKey: Key.interfaceZoomScale)
        userDefaults.set(settings.newNoteReopenBehavior.rawValue, forKey: Key.newNoteReopenBehavior)
        userDefaults.set(settings.interfaceThemePreset.rawValue, forKey: Key.interfaceThemePreset)
        userDefaults.set(Self.currentMigrationVersion, forKey: Key.migrationVersion)
    }

    private func loadShortcut(forKey key: String) -> HotKeyManager.Shortcut? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(HotKeyManager.Shortcut.self, from: data)
    }
    private func saveShortcut(_ shortcut: HotKeyManager.Shortcut, forKey key: String) {
        guard let encoded = try? JSONEncoder().encode(shortcut) else {
            return
        }

        userDefaults.set(encoded, forKey: key)
    }

    private func saveOptionalShortcut(_ shortcut: HotKeyManager.Shortcut?, forKey key: String) {
        guard let shortcut else {
            userDefaults.removeObject(forKey: key)
            return
        }
        saveShortcut(shortcut, forKey: key)
    }

    private func migrateLegacyGlobalShortcutsIfNeeded(settings: inout AppSettings) -> Bool {
        let storedVersion = userDefaults.integer(forKey: Key.migrationVersion)
        guard storedVersion < Self.currentMigrationVersion else {
            return false
        }

        var didMigrate = false
        if settings.panelShortcut == AppSettings.legacyPanelShortcut {
            settings.panelShortcut = AppSettings.defaultPanelShortcut
            didMigrate = true
        }
        if settings.panelShortcut == AppSettings.previousDefaultPanelShortcut {
            settings.panelShortcut = AppSettings.defaultPanelShortcut
            didMigrate = true
        }
        if settings.translationShortcut == AppSettings.legacyTranslationShortcut {
            settings.translationShortcut = AppSettings.defaultTranslationShortcut
            didMigrate = true
        }
        if settings.translationShortcut == AppSettings.previousDefaultTranslationShortcut {
            settings.translationShortcut = AppSettings.defaultTranslationShortcut
            didMigrate = true
        }
        if settings.newNoteShortcut == AppSettings.legacyLocalNewNoteShortcut {
            settings.newNoteShortcut = AppSettings.default.newNoteShortcut
            didMigrate = true
        }
        if settings.newNoteShortcut == AppSettings.previousLocalNewNoteShortcut {
            settings.newNoteShortcut = AppSettings.default.newNoteShortcut
            didMigrate = true
        }
        if settings.globalNewNoteShortcut == nil {
            settings.globalNewNoteShortcut = AppSettings.defaultGlobalNewNoteShortcut
            didMigrate = true
        }
        if settings.globalCopyJoinedShortcut == nil {
            settings.globalCopyJoinedShortcut = AppSettings.defaultGlobalCopyJoinedShortcut
            didMigrate = true
        }
        if settings.globalCopyNormalizedShortcut == nil {
            settings.globalCopyNormalizedShortcut = AppSettings.defaultGlobalCopyNormalizedShortcut
            didMigrate = true
        }
        if settings.copyJoinedShortcut == AppSettings.legacyJoinLinesShortcut {
            settings.copyJoinedShortcut = AppSettings.default.copyJoinedShortcut
            didMigrate = true
        }
        if settings.copyNormalizedShortcut == AppSettings.legacyNormalizeForCommandShortcut {
            settings.copyNormalizedShortcut = AppSettings.default.copyNormalizedShortcut
            didMigrate = true
        }
        if settings.joinLinesShortcut == AppSettings.legacyJoinLinesShortcut {
            settings.joinLinesShortcut = AppSettings.default.joinLinesShortcut
            didMigrate = true
        }
        if settings.normalizeForCommandShortcut == AppSettings.legacyNormalizeForCommandShortcut {
            settings.normalizeForCommandShortcut = AppSettings.default.normalizeForCommandShortcut
            didMigrate = true
        }
        settings.globalCopyJoinedEnabled = true
        settings.globalCopyNormalizedEnabled = true
        if loadShortcut(forKey: Key.orphanCodexDiscardShortcut) == nil {
            settings.orphanCodexDiscardShortcut = AppSettings.defaultOrphanCodexDiscardShortcut
            didMigrate = true
        }

        userDefaults.set(Self.currentMigrationVersion, forKey: Key.migrationVersion)
        return didMigrate
    }
}
