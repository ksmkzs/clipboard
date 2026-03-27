import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    private enum MessageSeverity {
        case info
        case success
        case error
    }

    private enum ShortcutTarget: CaseIterable, Identifiable {
        case panel
        case translation
        case togglePin
        case togglePinnedArea
        case editText
        case commitEdit
        case deleteItem
        case undo
        case redo
        case indent
        case outdent
        case moveLineUp
        case moveLineDown
        case joinLines
        case normalizeForCommand

        var id: Self { self }
    }

    @ObservedObject var appDelegate: AppDelegate

    @State private var draftSettings = AppSettings.default
    @State private var captureTarget: ShortcutTarget?
    @State private var capturedShortcut: HotKeyManager.Shortcut?
    @State private var messageText: String?
    @State private var messageSeverity: MessageSeverity = .info
    @State private var alertText: String?
    @State private var eventMonitor: Any?

    private var settings: AppSettings {
        appDelegate.settings
    }

    private var settingsLanguage: SettingsLanguage {
        draftSettings.settingsLanguage
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                generalSection
                shortcutsSection
                translationSection

                if let messageText, !messageText.isEmpty {
                    Section {
                        Text(messageText)
                            .font(.footnote)
                            .foregroundStyle(messageColor)
                    }
                }
            }
            .formStyle(.grouped)
            .padding(20)

            Divider()

            HStack {
                Button(t("Restore Defaults", "初期値に戻す")) {
                    draftSettings = .default
                    captureTarget = nil
                    capturedShortcut = nil
                    messageText = nil
                    messageSeverity = .info
                    alertText = nil
                }

                Spacer()

                Button(t("Cancel", "キャンセル")) {
                    syncDraftFromSettings()
                    appDelegate.closeSettingsWindow()
                }

                Button(t("Apply", "適用")) {
                    applyDraft()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 620, height: 560)
        .onAppear {
            syncDraftFromSettings()
            installShortcutCaptureMonitor()
        }
        .onDisappear {
            removeShortcutCaptureMonitor()
        }
        .alert(
            t("Could not apply settings", "設定を適用できませんでした"),
            isPresented: Binding(
                get: { alertText != nil },
                set: { isPresented in
                    if !isPresented {
                        alertText = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                alertText = nil
            }
        } message: {
            Text(alertText ?? "")
        }
    }

    private var generalSection: some View {
        Section(
            content: {
                Picker(
                    t("Settings language", "設定画面の言語"),
                    selection: $draftSettings.settingsLanguage
                ) {
                    Text("English").tag(SettingsLanguage.english)
                    Text("日本語").tag(SettingsLanguage.japanese)
                }

                Toggle(t("Launch at login", "ログイン時に起動"), isOn: $draftSettings.launchAtLogin)

                Stepper(value: $draftSettings.historyLimit, in: 25...500, step: 25) {
                    HStack {
                        Text(t("History limit", "履歴保持数"))
                        Spacer()
                        Text("\(draftSettings.historyLimit)")
                            .foregroundStyle(.secondary)
                    }
                }
            },
            header: { Text(t("General", "一般")) }
        )
    }

    private var shortcutsSection: some View {
        Section(
            content: {
                shortcutRow(
                    title: t("Panel shortcut", "履歴パネル表示"),
                    target: .panel,
                    shortcut: binding(for: .panel)
                )
                shortcutRow(
                    title: t("Translation shortcut", "翻訳"),
                    target: .translation,
                    shortcut: binding(for: .translation)
                )
                shortcutRow(
                    title: t("Toggle pin", "ピン切り替え"),
                    target: .togglePin,
                    shortcut: binding(for: .togglePin)
                )
                shortcutRow(
                    title: t("Toggle pins pane", "ピン領域の開閉"),
                    target: .togglePinnedArea,
                    shortcut: binding(for: .togglePinnedArea)
                )
                shortcutRow(
                    title: t("Edit text item", "テキスト編集モード"),
                    target: .editText,
                    shortcut: binding(for: .editText)
                )
                shortcutRow(
                    title: t("Commit edit", "編集を確定"),
                    target: .commitEdit,
                    shortcut: binding(for: .commitEdit)
                )
                shortcutRow(
                    title: t("Delete item", "項目削除"),
                    target: .deleteItem,
                    shortcut: binding(for: .deleteItem)
                )
                shortcutRow(
                    title: t("Undo", "元に戻す"),
                    target: .undo,
                    shortcut: binding(for: .undo)
                )
                shortcutRow(
                    title: t("Redo", "やり直し"),
                    target: .redo,
                    shortcut: binding(for: .redo)
                )
                shortcutRow(
                    title: t("Indent", "インデント追加"),
                    target: .indent,
                    shortcut: binding(for: .indent)
                )
                shortcutRow(
                    title: t("Outdent", "インデント除去"),
                    target: .outdent,
                    shortcut: binding(for: .outdent)
                )
                shortcutRow(
                    title: t("Move line up", "行を上へ移動"),
                    target: .moveLineUp,
                    shortcut: binding(for: .moveLineUp)
                )
                shortcutRow(
                    title: t("Move line down", "行を下へ移動"),
                    target: .moveLineDown,
                    shortcut: binding(for: .moveLineDown)
                )
                shortcutRow(
                    title: t("Join lines", "行を結合"),
                    target: .joinLines,
                    shortcut: binding(for: .joinLines)
                )
                shortcutRow(
                    title: t("Normalize for command", "コマンド向け整形"),
                    target: .normalizeForCommand,
                    shortcut: binding(for: .normalizeForCommand)
                )
            },
            header: { Text(t("Shortcuts", "ショートカット")) },
            footer: {
                Text(t(
                    "Click a shortcut, press keys as many times as needed, then press Space to confirm. Esc cancels.",
                    "ショートカットを押してから、納得いくまで何度でもキー入力し、Space で確定します。Esc でキャンセルします。"
                ))
            }
        )
    }

    private var translationSection: some View {
        Section(
            content: {
                Picker(
                    t("Target language", "翻訳先言語"),
                    selection: $draftSettings.translationTargetLanguage
                ) {
                    ForEach(SupportedTranslationLanguages.all) { option in
                        Text(option.displayName(for: settingsLanguage)).tag(option.code)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(t("Experimental feature", "実験的機能"))
                        .font(.subheadline.weight(.semibold))
                    Text(t(
                        "Translation opens Google Translate with the selected text or clipboard text when available.",
                        "翻訳は、選択テキストまたはクリップボードのテキストを Google 翻訳で開きます。"
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            },
            header: { Text(t("Translation", "翻訳")) }
        )
    }

    private func shortcutRow(
        title: String,
        target: ShortcutTarget,
        shortcut: Binding<HotKeyManager.Shortcut>
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                captureTarget = target
                capturedShortcut = nil
                messageText = t(
                    "Press keys, then press Space to confirm. Esc cancels.",
                    "キーを入力して、Space で確定します。Esc でキャンセルします。"
                )
            } label: {
                Text(shortcutLabel(for: target, current: shortcut.wrappedValue))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(captureTarget == target ? Color.accentColor.opacity(0.18) : Color.black.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)

            Button {
                binding(for: target).wrappedValue = defaultShortcut(for: target)
                if captureTarget == target {
                    capturedShortcut = defaultShortcut(for: target)
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help(t("Restore default for this shortcut", "このショートカットを初期値に戻す"))
        }
        .padding(.vertical, 2)
    }

    private func binding(for target: ShortcutTarget) -> Binding<HotKeyManager.Shortcut> {
        Binding(
            get: {
                switch target {
                case .panel:
                    return draftSettings.panelShortcut
                case .translation:
                    return draftSettings.translationShortcut
                case .togglePin:
                    return draftSettings.togglePinShortcut
                case .togglePinnedArea:
                    return draftSettings.togglePinnedAreaShortcut
                case .editText:
                    return draftSettings.editTextShortcut
                case .commitEdit:
                    return draftSettings.commitEditShortcut
                case .deleteItem:
                    return draftSettings.deleteItemShortcut
                case .undo:
                    return draftSettings.undoShortcut
                case .redo:
                    return draftSettings.redoShortcut
                case .indent:
                    return draftSettings.indentShortcut
                case .outdent:
                    return draftSettings.outdentShortcut
                case .moveLineUp:
                    return draftSettings.moveLineUpShortcut
                case .moveLineDown:
                    return draftSettings.moveLineDownShortcut
                case .joinLines:
                    return draftSettings.joinLinesShortcut
                case .normalizeForCommand:
                    return draftSettings.normalizeForCommandShortcut
                }
            },
            set: { newValue in
                switch target {
                case .panel:
                    draftSettings.panelShortcut = newValue
                case .translation:
                    draftSettings.translationShortcut = newValue
                case .togglePin:
                    draftSettings.togglePinShortcut = newValue
                case .togglePinnedArea:
                    draftSettings.togglePinnedAreaShortcut = newValue
                case .editText:
                    draftSettings.editTextShortcut = newValue
                case .commitEdit:
                    draftSettings.commitEditShortcut = newValue
                case .deleteItem:
                    draftSettings.deleteItemShortcut = newValue
                case .undo:
                    draftSettings.undoShortcut = newValue
                case .redo:
                    draftSettings.redoShortcut = newValue
                case .indent:
                    draftSettings.indentShortcut = newValue
                case .outdent:
                    draftSettings.outdentShortcut = newValue
                case .moveLineUp:
                    draftSettings.moveLineUpShortcut = newValue
                case .moveLineDown:
                    draftSettings.moveLineDownShortcut = newValue
                case .joinLines:
                    draftSettings.joinLinesShortcut = newValue
                case .normalizeForCommand:
                    draftSettings.normalizeForCommandShortcut = newValue
                }
            }
        )
    }

    private func syncDraftFromSettings() {
        draftSettings = settings
        captureTarget = nil
        capturedShortcut = nil
        messageText = nil
        messageSeverity = .info
        alertText = nil
    }

    private var messageColor: Color {
        switch messageSeverity {
        case .info:
            return .secondary
        case .success:
            return .green
        case .error:
            return .red
        }
    }

    private func shortcutIdentifier(_ shortcut: HotKeyManager.Shortcut) -> String {
        "\(shortcut.keyCode):\(shortcut.modifiers)"
    }

    private func scopedShortcuts(for draft: AppSettings) -> [(scope: String, entries: [(title: String, shortcut: HotKeyManager.Shortcut)])] {
        [
            (
                t("Global shortcuts", "グローバルショートカット"),
                [
                    (t("Panel shortcut", "履歴パネル表示"), draft.panelShortcut),
                    (t("Translation shortcut", "翻訳"), draft.translationShortcut)
                ]
            ),
            (
                t("Panel commands", "通常画面コマンド"),
                [
                    (t("Toggle pin", "ピン切り替え"), draft.togglePinShortcut),
                    (t("Toggle pins pane", "ピン領域の開閉"), draft.togglePinnedAreaShortcut),
                    (t("Edit text item", "テキスト編集モード"), draft.editTextShortcut),
                    (t("Delete item", "項目削除"), draft.deleteItemShortcut),
                    (t("Undo", "元に戻す"), draft.undoShortcut),
                    (t("Redo", "やり直し"), draft.redoShortcut),
                    (t("Join lines", "行を結合"), draft.joinLinesShortcut),
                    (t("Normalize for command", "コマンド向け整形"), draft.normalizeForCommandShortcut)
                ]
            ),
            (
                t("Editor commands", "編集画面コマンド"),
                [
                    (t("Commit edit", "編集を確定"), draft.commitEditShortcut),
                    (t("Indent", "インデント追加"), draft.indentShortcut),
                    (t("Outdent", "インデント除去"), draft.outdentShortcut),
                    (t("Move line up", "行を上へ移動"), draft.moveLineUpShortcut),
                    (t("Move line down", "行を下へ移動"), draft.moveLineDownShortcut),
                    (t("Join lines", "行を結合"), draft.joinLinesShortcut),
                    (t("Normalize for command", "コマンド向け整形"), draft.normalizeForCommandShortcut)
                ]
            )
        ]
    }

    private func installShortcutCaptureMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let captureTarget else { return event }

            if event.keyCode == UInt16(kVK_Escape) {
                self.captureTarget = nil
                self.capturedShortcut = nil
                self.messageText = nil
                self.messageSeverity = .info
                self.alertText = nil
                return nil
            }

            if event.keyCode == UInt16(kVK_Space) && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                if let capturedShortcut = self.capturedShortcut {
                    self.binding(for: captureTarget).wrappedValue = capturedShortcut
                    self.captureTarget = nil
                    self.capturedShortcut = nil
                    self.messageText = nil
                    self.messageSeverity = .info
                    self.alertText = nil
                }
                return nil
            }

            guard let shortcut = HotKeyManager.shortcut(for: event) else {
                return nil
            }

            self.capturedShortcut = shortcut
            self.messageText = t(
                "Captured \(HotKeyManager.displayString(for: shortcut)). Press Space to confirm.",
                "\(HotKeyManager.displayString(for: shortcut)) を取得しました。Space で確定してください。"
            )
            self.messageSeverity = .info
            return nil
        }
    }

    private func removeShortcutCaptureMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func applyDraft() {
        let duplicates = scopedShortcuts(for: draftSettings).compactMap { scope, entries -> String? in
            let grouped = Dictionary(grouping: entries, by: { shortcutIdentifier($0.shortcut) })
            let conflicts = grouped.values.filter { $0.count > 1 }
            guard !conflicts.isEmpty else { return nil }

            let details = conflicts
                .map { group in
                    let commandNames = group.map(\.title).joined(separator: " / ")
                    let shortcutLabel = HotKeyManager.displayString(for: group[0].shortcut)
                    return "\(scope): \(commandNames) (\(shortcutLabel))"
                }
                .joined(separator: "\n")
            return details
        }
        guard duplicates.isEmpty else {
            let header = t(
                "Shortcuts in the same context must be unique.",
                "同じ画面内で使うショートカットは重複しないようにしてください。"
            )
            messageText = header
            messageSeverity = .error
            alertText = header + "\n\n" + duplicates.joined(separator: "\n")
            return
        }

        do {
            try appDelegate.applySettingsDraft(draftSettings)
            messageText = t("Applied.", "適用しました。")
            messageSeverity = .success
            alertText = nil
            appDelegate.closeSettingsWindow()
        } catch let error as SettingsMutationError {
            messageText = message(for: error)
            messageSeverity = .error
            alertText = messageText
        } catch {
            messageText = error.localizedDescription
            messageSeverity = .error
            alertText = messageText
        }
    }

    private func message(for error: SettingsMutationError) -> String {
        switch error {
        case .invalidShortcutFormat:
            return t(
                "Shortcut format is invalid.",
                "ショートカット形式が不正です。"
            )
        case .duplicateShortcut:
            return t(
                "This shortcut is already in use by another command.",
                "このショートカットは別のコマンドですでに使われています。"
            )
        case .unavailableShortcut(let details):
            return t(
                "This shortcut conflicts with another app or system shortcut. \(details)",
                "このショートカットは他のアプリまたはシステムと競合しています。\(details)"
            )
        case .launchAtLoginUnavailable(let details):
            return t(
                "Launch at login could not be updated. \(details)",
                "ログイン時起動を更新できませんでした。\(details)"
            )
        }
    }

    private func t(_ english: String, _ japanese: String) -> String {
        settingsLanguage == .japanese ? japanese : english
    }

    private func shortcutLabel(for target: ShortcutTarget, current: HotKeyManager.Shortcut) -> String {
        if captureTarget == target, let capturedShortcut {
            return HotKeyManager.displayString(for: capturedShortcut)
        }
        if captureTarget == target {
            return t("Press shortcut…", "入力待ち…")
        }
        return HotKeyManager.displayString(for: current)
    }

    private func defaultShortcut(for target: ShortcutTarget) -> HotKeyManager.Shortcut {
        switch target {
        case .panel:
            return AppSettings.default.panelShortcut
        case .translation:
            return AppSettings.default.translationShortcut
        case .togglePin:
            return AppSettings.default.togglePinShortcut
        case .togglePinnedArea:
            return AppSettings.default.togglePinnedAreaShortcut
        case .editText:
            return AppSettings.default.editTextShortcut
        case .commitEdit:
            return AppSettings.default.commitEditShortcut
        case .deleteItem:
            return AppSettings.default.deleteItemShortcut
        case .undo:
            return AppSettings.default.undoShortcut
        case .redo:
            return AppSettings.default.redoShortcut
        case .indent:
            return AppSettings.default.indentShortcut
        case .outdent:
            return AppSettings.default.outdentShortcut
        case .moveLineUp:
            return AppSettings.default.moveLineUpShortcut
        case .moveLineDown:
            return AppSettings.default.moveLineDownShortcut
        case .joinLines:
            return AppSettings.default.joinLinesShortcut
        case .normalizeForCommand:
            return AppSettings.default.normalizeForCommandShortcut
        }
    }
}
