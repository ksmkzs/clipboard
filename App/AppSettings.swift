import Carbon
import Foundation

enum SettingsLanguage: String, Codable, CaseIterable, Identifiable {
    case english = "en"
    case japanese = "ja"

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
    var panelShortcut: HotKeyManager.Shortcut
    var translationShortcut: HotKeyManager.Shortcut
    var togglePinShortcut: HotKeyManager.Shortcut
    var togglePinnedAreaShortcut: HotKeyManager.Shortcut
    var editTextShortcut: HotKeyManager.Shortcut
    var commitEditShortcut: HotKeyManager.Shortcut
    var deleteItemShortcut: HotKeyManager.Shortcut
    var undoShortcut: HotKeyManager.Shortcut
    var redoShortcut: HotKeyManager.Shortcut
    var indentShortcut: HotKeyManager.Shortcut
    var outdentShortcut: HotKeyManager.Shortcut
    var moveLineUpShortcut: HotKeyManager.Shortcut
    var moveLineDownShortcut: HotKeyManager.Shortcut
    var joinLinesShortcut: HotKeyManager.Shortcut
    var normalizeForCommandShortcut: HotKeyManager.Shortcut
    var launchAtLogin: Bool
    var translationTargetLanguage: String
    var historyLimit: Int
    var settingsLanguage: SettingsLanguage

    static let `default` = AppSettings(
        panelShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(shiftKey | cmdKey)
        ),
        translationShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_T),
            modifiers: UInt32(shiftKey | cmdKey)
        ),
        togglePinShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: 0
        ),
        togglePinnedAreaShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_Tab),
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
        joinLinesShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_J),
            modifiers: UInt32(cmdKey)
        ),
        normalizeForCommandShortcut: HotKeyManager.Shortcut(
            keyCode: UInt32(kVK_ANSI_J),
            modifiers: UInt32(cmdKey | shiftKey)
        ),
        launchAtLogin: false,
        translationTargetLanguage: "ja",
        historyLimit: 150,
        settingsLanguage: .english
    )
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
        static let panelShortcut = "hotkey.toggle.panel"
        static let translationShortcut = "hotkey.translate.current"
        static let togglePinShortcut = "hotkey.local.togglePin"
        static let togglePinnedAreaShortcut = "hotkey.local.togglePinnedArea"
        static let editTextShortcut = "hotkey.local.editText"
        static let commitEditShortcut = "hotkey.local.commitEdit"
        static let deleteItemShortcut = "hotkey.local.delete"
        static let undoShortcut = "hotkey.local.undo"
        static let redoShortcut = "hotkey.local.redo"
        static let indentShortcut = "hotkey.editor.indent"
        static let outdentShortcut = "hotkey.editor.outdent"
        static let moveLineUpShortcut = "hotkey.editor.moveLineUp"
        static let moveLineDownShortcut = "hotkey.editor.moveLineDown"
        static let joinLinesShortcut = "hotkey.editor.joinLines"
        static let normalizeForCommandShortcut = "hotkey.editor.normalizeForCommand"
        static let launchAtLogin = "app.launchAtLogin"
        static let translationTargetLanguage = "translation.targetLanguage"
        static let historyLimit = "history.limit"
        static let settingsLanguage = "settings.language"
    }

    private let userDefaults: UserDefaults

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
        if let shortcut = loadShortcut(forKey: Key.togglePinShortcut) {
            settings.togglePinShortcut = shortcut
        }
        if let shortcut = loadShortcut(forKey: Key.togglePinnedAreaShortcut) {
            settings.togglePinnedAreaShortcut = shortcut
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
        if let shortcut = loadShortcut(forKey: Key.joinLinesShortcut) {
            settings.joinLinesShortcut = shortcut
        }
        if let shortcut = loadShortcut(forKey: Key.normalizeForCommandShortcut) {
            settings.normalizeForCommandShortcut = shortcut
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

        return settings
    }

    func save(_ settings: AppSettings) {
        saveShortcut(settings.panelShortcut, forKey: Key.panelShortcut)
        saveShortcut(settings.translationShortcut, forKey: Key.translationShortcut)
        saveShortcut(settings.togglePinShortcut, forKey: Key.togglePinShortcut)
        saveShortcut(settings.togglePinnedAreaShortcut, forKey: Key.togglePinnedAreaShortcut)
        saveShortcut(settings.editTextShortcut, forKey: Key.editTextShortcut)
        saveShortcut(settings.commitEditShortcut, forKey: Key.commitEditShortcut)
        saveShortcut(settings.deleteItemShortcut, forKey: Key.deleteItemShortcut)
        saveShortcut(settings.undoShortcut, forKey: Key.undoShortcut)
        saveShortcut(settings.redoShortcut, forKey: Key.redoShortcut)
        saveShortcut(settings.indentShortcut, forKey: Key.indentShortcut)
        saveShortcut(settings.outdentShortcut, forKey: Key.outdentShortcut)
        saveShortcut(settings.moveLineUpShortcut, forKey: Key.moveLineUpShortcut)
        saveShortcut(settings.moveLineDownShortcut, forKey: Key.moveLineDownShortcut)
        saveShortcut(settings.joinLinesShortcut, forKey: Key.joinLinesShortcut)
        saveShortcut(settings.normalizeForCommandShortcut, forKey: Key.normalizeForCommandShortcut)
        userDefaults.set(settings.launchAtLogin, forKey: Key.launchAtLogin)
        userDefaults.set(settings.translationTargetLanguage, forKey: Key.translationTargetLanguage)
        userDefaults.set(max(1, settings.historyLimit), forKey: Key.historyLimit)
        userDefaults.set(settings.settingsLanguage.rawValue, forKey: Key.settingsLanguage)
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
}
