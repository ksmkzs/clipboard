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
        case globalNewNote
        case globalCopyJoined
        case globalCopyNormalized
        case newNote
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
        case copyJoined
        case copyNormalized
        case toggleMarkdownPreview
        case joinLines
        case normalizeForCommand
        case orphanCodexDiscard

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
    @State private var hoveredHelpTarget: ShortcutTarget?
    @State private var expandedHelpTarget: ShortcutTarget?
    @State private var codexIntegrationStatus: AppDelegate.CodexIntegrationStatus?
    @State private var showCodexRemovalConfirmation = false

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
                codexSection
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
                    hoveredHelpTarget = nil
                    expandedHelpTarget = nil
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
        .frame(width: 620, height: 640)
        .onAppear {
            syncDraftFromSettings()
            refreshCodexIntegrationStatus()
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
        .confirmationDialog(
            t("Remove Codex integration?", "Codex 連携を削除しますか？"),
            isPresented: $showCodexRemovalConfirmation,
            titleVisibility: .visible
        ) {
            Button(t("Remove and edit shell config", "削除してシェル設定を編集"), role: .destructive) {
                removeCodexIntegration()
            }
            Button(t("Cancel", "キャンセル"), role: .cancel) {}
        } message: {
            Text(t(
                "This will read your shell config file and remove the ClipboardHistory-managed EDITOR / VISUAL block.",
                "シェル設定ファイルを読み込み、ClipboardHistory が管理している EDITOR / VISUAL のブロックを削除します。"
            ))
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
                Picker(
                    t("Reopen closed note", "新規作成ウィンドウの再オープン"),
                    selection: $draftSettings.newNoteReopenBehavior
                ) {
                    Text(t("Reset", "初期化")).tag(NewNoteReopenBehavior.reset)
                    Text(t("Restore last draft", "前回の下書きを復元")).tag(NewNoteReopenBehavior.restoreLastDraft)
                }
                Stepper(value: $draftSettings.historyLimit, in: 25...500, step: 25) {
                    HStack {
                        Text(t("History limit", "履歴保持数"))
                        Spacer()
                        Text("\(draftSettings.historyLimit)")
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(t("Theme preset", "テーマプリセット"))
                    Picker("", selection: $draftSettings.interfaceThemePreset) {
                        ForEach(InterfaceThemePreset.allCases) { preset in
                            Text(themeTitle(for: preset)).tag(preset)
                        }
                    }
                    .labelsHidden()
                    themePreviewStrip
                }
            },
            header: { Text(t("General", "一般")) }
        )
    }

    private var codexSection: some View {
        Section(
            content: {
                VStack(alignment: .leading, spacing: 10) {
                    Text(t(
                        "Install ClipboardHistory as Codex CLI's Ctrl+G editor with one click.",
                        "ClipboardHistory を Codex CLI の Ctrl+G エディタとしてワンクリックで登録します。"
                    ))
                    .font(.subheadline)

                    Text(t(
                        "ClipboardHistory edits ~/.zshrc or ~/.bashrc only when you explicitly install, inspect, or remove this integration.",
                        "この連携は、明示的にインストール・確認・削除した時だけ ~/.zshrc または ~/.bashrc を読み書きします。"
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    ForEach(codexStatusLines, id: \.self) { line in
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack {
                        Button(t("Install / Update Codex integration", "Codex 連携をインストール / 更新")) {
                            installCodexIntegration()
                        }
                        Button(t("Inspect shell config", "シェル設定を確認")) {
                            inspectCodexIntegration()
                        }
                        Button(t("Remove Codex integration", "Codex 連携を削除")) {
                            showCodexRemovalConfirmation = true
                        }
                        Spacer()
                    }
                }
            },
            header: { Text("Codex") }
        )
    }

    private var shortcutsSection: some View {
        Section(
            content: {
                shortcutGroup(title: t("Global", "グローバル")) {
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
                    optionalShortcutRow(
                        title: t("New note from anywhere", "どこからでも新規作成"),
                        target: .globalNewNote,
                        shortcut: optionalBinding(for: .globalNewNote)
                    )
                    Toggle(
                        t("Enable global joined copy", "グローバルの一文化コピーを有効化"),
                        isOn: $draftSettings.globalCopyJoinedEnabled
                    )
                    Toggle(
                        t("Enable global normalized copy", "グローバルの整形コピーを有効化"),
                        isOn: $draftSettings.globalCopyNormalizedEnabled
                    )
                    optionalShortcutRow(
                        title: t("Copy joined selection from anywhere", "どこからでも一文化してコピー"),
                        target: .globalCopyJoined,
                        shortcut: optionalBinding(for: .globalCopyJoined)
                    )
                    optionalShortcutRow(
                        title: t("Copy normalized selection from anywhere", "どこからでも整形してコピー"),
                        target: .globalCopyNormalized,
                        shortcut: optionalBinding(for: .globalCopyNormalized)
                    )
                }

                shortcutGroup(title: t("Standard Window", "標準ウィンドウ")) {
                    shortcutRow(
                        title: t("New note inside panel", "通常ウィンドウ内で新規作成"),
                        target: .newNote,
                        shortcut: binding(for: .newNote)
                    )
                    shortcutRow(
                        title: t("Pin selected item", "選択中の項目をピン留め"),
                        target: .togglePin,
                        shortcut: binding(for: .togglePin)
                    )
                    shortcutRow(
                        title: t("Show or hide pinned items", "ピン留めした項目の表示 / 非表示"),
                        target: .togglePinnedArea,
                        shortcut: binding(for: .togglePinnedArea)
                    )
                    shortcutRow(
                        title: t("Edit selected item", "選択中の項目を編集"),
                        target: .editText,
                        shortcut: binding(for: .editText)
                    )
                    shortcutRow(
                        title: t("Delete selected item", "選択中の項目を削除"),
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
                        title: t("Join selected item into one sentence", "選択中の項目を一文に整形"),
                        target: .copyJoined,
                        shortcut: binding(for: .copyJoined)
                    )
                    shortcutRow(
                        title: t("Normalize selected item whitespace", "選択中の項目の空白を整形"),
                        target: .copyNormalized,
                        shortcut: binding(for: .copyNormalized)
                    )
                }

                shortcutGroup(title: t("Editor Window", "編集ウィンドウ")) {
                    shortcutRow(
                        title: t("Commit", "確定"),
                        target: .commitEdit,
                        shortcut: binding(for: .commitEdit)
                    )
                    shortcutRow(
                        title: t("Indent", "まとめてインデント"),
                        target: .indent,
                        shortcut: binding(for: .indent)
                    )
                    shortcutRow(
                        title: t("Outdent", "まとめてアウトデント"),
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
                        title: t("Markdown preview", "Markdown プレビュー"),
                        target: .toggleMarkdownPreview,
                        shortcut: binding(for: .toggleMarkdownPreview)
                    )
                    shortcutRow(
                        title: t("Join into one sentence", "選択中の項目を一文に整形"),
                        target: .joinLines,
                        shortcut: binding(for: .joinLines)
                    )
                    shortcutRow(
                        title: t("Normalize whitespace", "選択中の項目の空白を整形"),
                        target: .normalizeForCommand,
                        shortcut: binding(for: .normalizeForCommand)
                    )
                }

                shortcutGroup(title: t("Codex Window", "Codex ウィンドウ")) {
                    shortcutRow(
                        title: t("Discard orphaned draft", "切断された下書きを削除"),
                        target: .orphanCodexDiscard,
                        shortcut: binding(for: .orphanCodexDiscard)
                    )
                }
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

    private var themePreviewStrip: some View {
        let columns = [
            GridItem(.adaptive(minimum: 110, maximum: 150), spacing: 12, alignment: .top)
        ]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(InterfaceThemePreset.allCases) { preset in
                let definition = preset.definition
                VStack(alignment: .leading, spacing: 6) {
                    Text(themeTitle(for: preset))
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        ForEach(Array(definition.previewColors.enumerated()), id: \.offset) { _, color in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(color)
                                .frame(width: 18, height: 18)
                        }
                    }
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(definition.cardFill)
                            .overlay(
                                Rectangle()
                                    .stroke(draftSettings.interfaceThemePreset == preset ? Color.accentColor : Color.white.opacity(0.18), lineWidth: draftSettings.interfaceThemePreset == preset ? 1.3 : 0.8)
                            )

                        Rectangle()
                            .fill(definition.headerFill)
                            .frame(height: 9)

                        Rectangle()
                            .fill(definition.selectedFill)
                            .frame(width: 34, height: 10)
                            .padding(.leading, 6)
                            .padding(.top, 15)

                        Circle()
                            .fill(definition.toggleAccent)
                            .frame(width: 8, height: 8)
                            .padding(.leading, 52)
                            .padding(.top, 17)

                        Text("Aa")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(definition.primaryText)
                            .padding(.leading, 6)
                            .padding(.top, 28)

                        Text("..")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(definition.secondaryText)
                            .padding(.leading, 28)
                            .padding(.top, 28)
                    }
                    .frame(width: 96, height: 48)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    draftSettings.interfaceThemePreset = preset
                }
            }
        }
    }

    private func themeTitle(for preset: InterfaceThemePreset) -> String {
        settingsLanguage == .japanese ? preset.definition.titleJapanese : preset.definition.titleEnglish
    }

    @ViewBuilder
    private func shortcutGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            content()
        }
        .padding(.bottom, 4)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Text(title)
                    shortcutHelpButton(for: target)
                }
                .contentShape(Rectangle())
                .onTapGesture { toggleShortcutHelp(for: target) }
                .onHover { isHovering in
                    if isHovering {
                        hoveredHelpTarget = target
                    } else if hoveredHelpTarget == target {
                        hoveredHelpTarget = nil
                    }
                }
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

            if expandedHelpTarget == target || hoveredHelpTarget == target {
                shortcutHelpCard(for: target)
            }
        }
        .padding(.vertical, 2)
    }

    private func optionalShortcutRow(
        title: String,
        target: ShortcutTarget,
        shortcut: Binding<HotKeyManager.Shortcut?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Text(title)
                    shortcutHelpButton(for: target)
                }
                .contentShape(Rectangle())
                .onTapGesture { toggleShortcutHelp(for: target) }
                .onHover { isHovering in
                    if isHovering {
                        hoveredHelpTarget = target
                    } else if hoveredHelpTarget == target {
                        hoveredHelpTarget = nil
                    }
                }
                Spacer()
                Button {
                    captureTarget = target
                    capturedShortcut = nil
                    messageText = t(
                        "Press keys, then press Space to confirm. Esc cancels.",
                        "キーを入力して、Space で確定します。Esc でキャンセルします。"
                    )
                } label: {
                    Text(optionalShortcutLabel(for: target, current: shortcut.wrappedValue))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(shortcut.wrappedValue == nil ? .secondary : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(captureTarget == target ? Color.accentColor.opacity(0.18) : Color.black.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    shortcut.wrappedValue = nil
                    if captureTarget == target {
                        capturedShortcut = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help(t("Clear this shortcut", "このショートカットを未設定にする"))
            }

            if expandedHelpTarget == target || hoveredHelpTarget == target {
                shortcutHelpCard(for: target)
            }
        }
        .padding(.vertical, 2)
    }

    private func shortcutHelpButton(for target: ShortcutTarget) -> some View {
        return Button {
            toggleShortcutHelp(for: target)
        } label: {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .frame(width: 22, height: 22)
                .background(Color.black.opacity(0.06), in: Circle())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering {
                hoveredHelpTarget = target
            } else if hoveredHelpTarget == target {
                hoveredHelpTarget = nil
            }
        }
    }

    private func shortcutHelpCard(for target: ShortcutTarget) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(shortcutHelpTitle(for: target))
                    .font(.headline)
                Spacer(minLength: 0)
                if expandedHelpTarget == target {
                    Button {
                        expandedHelpTarget = nil
                        if hoveredHelpTarget == target {
                            hoveredHelpTarget = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(shortcutDescriptionItems(for: target), id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(item)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private func toggleShortcutHelp(for target: ShortcutTarget) {
        if expandedHelpTarget == target {
            expandedHelpTarget = nil
        } else {
            expandedHelpTarget = target
            hoveredHelpTarget = target
        }
    }

    private func shortcutHelpTitle(for target: ShortcutTarget) -> String {
        switch target {
        case .panel:
            return t("Open clipboard panel", "履歴パネルを開く")
        case .translation:
            return t("Translate selection", "選択テキストを翻訳")
        case .globalNewNote:
            return t("Create new note from anywhere", "どこからでも新規ノートを作成")
        case .globalCopyJoined:
            return t("Copy joined selection from anywhere", "どこからでも選択テキストを一文化してコピー")
        case .globalCopyNormalized:
            return t("Copy normalized selection from anywhere", "どこからでも選択テキストを整形してコピー")
        case .newNote:
            return t("Create new note", "新規ノートを作成")
        case .togglePin:
            return t("Pin or unpin item", "項目のピンを切り替え")
        case .togglePinnedArea:
            return t("Show or hide pinned items", "ピン留めした項目の表示 / 非表示")
        case .editText:
            return t("Edit selected item", "選択中の項目を編集")
        case .commitEdit:
            return t("Commit", "確定")
        case .deleteItem:
            return t("Delete selected item", "選択中の項目を削除")
        case .undo:
            return t("Undo / Redo", "取り消し / やり直し")
        case .redo:
            return t("Undo / Redo", "取り消し / やり直し")
        case .indent:
            return t("Indent", "まとめてインデント")
        case .outdent:
            return t("Outdent", "まとめてアウトデント")
        case .moveLineUp:
            return t("Move line", "行単位で移動")
        case .moveLineDown:
            return t("Move line", "行単位で移動")
        case .copyJoined:
            return t("Join into one sentence", "選択中の項目を一文に整形")
        case .copyNormalized:
            return t("Normalize whitespace", "選択中の項目の空白を整形")
        case .toggleMarkdownPreview:
            return t("Markdown preview", "Markdown プレビュー")
        case .joinLines:
            return t("Join into one sentence", "選択中の項目を一文に整形")
        case .normalizeForCommand:
            return t("Normalize whitespace", "選択中の項目の空白を整形")
        case .orphanCodexDiscard:
            return t("Discard orphaned draft", "切断された下書きを削除")
        }
    }

    private func shortcutDescriptionItems(for target: ShortcutTarget) -> [String] {
        switch target {
        case .panel:
            return items(
                en: ["Scope: global", "Action: open the clipboard window"],
                ja: ["対象: グローバル", "動作: クリップボードウィンドウを開く"]
            )
        case .translation:
            return items(
                en: ["Scope: global", "Action: open Google Translate"],
                ja: ["対象: グローバル", "動作: Google Translate を開く"]
            )
        case .globalNewNote:
            let shortcut = HotKeyManager.displayString(for: AppSettings.defaultGlobalNewNoteShortcut)
            return items(
                en: ["Scope: global", "Action: open a new standalone note editor", "Default: \(shortcut)"],
                ja: ["対象: グローバル", "動作: 単独の新規ノート編集ウィンドウを開く", "初期値: \(shortcut)"]
            )
        case .globalCopyJoined:
            return items(
                en: ["Scope: global", "Action: copy the current selection after trimming each line edge and removing line breaks", "Source: selected text in the front app", "Default: \(HotKeyManager.displayString(for: AppSettings.defaultGlobalCopyJoinedShortcut))", "Default state: on"],
                ja: ["対象: グローバル", "動作: 前面アプリの選択テキストを、各行の端を削ってから改行を消してコピーする", "入力: 前面アプリの選択テキスト", "初期値: \(HotKeyManager.displayString(for: AppSettings.defaultGlobalCopyJoinedShortcut))", "初期状態: オン"]
            )
        case .globalCopyNormalized:
            return items(
                en: ["Scope: global", "Action: copy the current selection while keeping line breaks and trimming each line edge", "Source: selected text in the front app", "Default: \(HotKeyManager.displayString(for: AppSettings.defaultGlobalCopyNormalizedShortcut))", "Default state: on"],
                ja: ["対象: グローバル", "動作: 前面アプリの選択テキストを、改行は維持したまま各行の端を削ってコピーする", "入力: 前面アプリの選択テキスト", "初期値: \(HotKeyManager.displayString(for: AppSettings.defaultGlobalCopyNormalizedShortcut))", "初期状態: オン"]
            )
        case .newNote:
            return items(
                en: ["Scope: panel window", "Action: insert an empty note at #1 and start editing it"],
                ja: ["対象: 通常ウィンドウ", "動作: #1 に空ノートを追加して編集を始める"]
            )
        case .togglePin:
            return items(
                en: ["Scope: standard window", "Action: pin or unpin the selected item"],
                ja: ["対象: 標準ウィンドウ", "動作: 選択中の項目を pin / unpin する"]
            )
        case .togglePinnedArea:
            return items(
                en: ["Scope: standard window", "Action: show or hide pinned items"],
                ja: ["対象: 標準ウィンドウ", "動作: ピン留めした項目を表示 / 非表示にする"]
            )
        case .editText:
            return items(
                en: ["Scope: standard window", "Action: open editor mode for the selected text item"],
                ja: ["対象: 標準ウィンドウ", "動作: 選択中の text item を editor mode で開く"]
            )
        case .commitEdit:
            return items(
                en: ["Scope: editor window", "Action: save the current draft"],
                ja: ["対象: 編集ウィンドウ", "動作: 現在の draft を保存する"]
            )
        case .deleteItem:
            return items(
                en: ["Scope: standard window", "Action: delete the selected item"],
                ja: ["対象: 標準ウィンドウ", "動作: 選択中の項目を削除する"]
            )
        case .undo:
            return items(
                en: ["Scope: standard or editor window", "Action: undo the latest change"],
                ja: ["対象: 標準ウィンドウ / 編集ウィンドウ", "動作: 直前の変更を取り消す"]
            )
        case .redo:
            return items(
                en: ["Scope: standard or editor window", "Action: redo the latest undone change"],
                ja: ["対象: 標準ウィンドウ / 編集ウィンドウ", "動作: 取り消した変更をやり直す"]
            )
        case .indent:
            return items(
                en: ["Scope: editor window", "Action: indent the current line or selected lines"],
                ja: ["対象: 編集ウィンドウ", "動作: 現在行または選択行をインデントする"]
            )
        case .outdent:
            return items(
                en: ["Scope: editor window", "Action: outdent the current line or selected lines"],
                ja: ["対象: 編集ウィンドウ", "動作: 現在行または選択行をアウトデントする"]
            )
        case .moveLineUp:
            return items(
                en: ["Scope: editor window", "Action: move the current line or selected lines up"],
                ja: ["対象: 編集ウィンドウ", "動作: 現在行または選択行を上へ移動する"]
            )
        case .moveLineDown:
            return items(
                en: ["Scope: editor window", "Action: move the current line or selected lines down"],
                ja: ["対象: 編集ウィンドウ", "動作: 現在行または選択行を下へ移動する"]
            )
        case .copyJoined:
            return items(
                en: ["Scope: standard window", "Action: copy a single-line variant of the selected text item"],
                ja: ["対象: 標準ウィンドウ", "動作: 選択中の text item を一文化した結果だけコピーする"]
            )
        case .copyNormalized:
            return items(
                en: ["Scope: standard window", "Action: copy a whitespace-normalized variant of the selected text item"],
                ja: ["対象: 標準ウィンドウ", "動作: 選択中の text item を整形した結果だけコピーする"]
            )
        case .toggleMarkdownPreview:
            return items(
                en: ["Scope: editor window", "Action: show or hide the Markdown preview beside the editor"],
                ja: ["対象: 編集ウィンドウ", "動作: editor の横に Markdown プレビューを表示 / 非表示にする"]
            )
        case .joinLines:
            return items(
                en: ["Scope: editor window", "Action: remove line breaks after trimming each line edge"],
                ja: ["対象: 編集ウィンドウ", "動作: 各行の端を削ってから改行を消す"]
            )
        case .normalizeForCommand:
            return items(
                en: ["Scope: editor window", "Action: keep line breaks and trim each line edge"],
                ja: ["対象: 編集ウィンドウ", "動作: 改行は維持しつつ各行の端を削る"]
            )
        case .orphanCodexDiscard:
            return items(
                en: ["Scope: orphaned Codex window", "Action: discard the disconnected draft and close the window", "Default: \(HotKeyManager.displayString(for: AppSettings.defaultOrphanCodexDiscardShortcut))"],
                ja: ["対象: 切断済みの Codex ウィンドウ", "動作: 接続が切れた下書きを破棄して閉じる", "初期値: \(HotKeyManager.displayString(for: AppSettings.defaultOrphanCodexDiscardShortcut))"]
            )
        }
    }

    private func items(en: [String], ja: [String]) -> [String] {
        settingsLanguage == .japanese ? ja : en
    }

    private func binding(for target: ShortcutTarget) -> Binding<HotKeyManager.Shortcut> {
        Binding(
            get: {
                switch target {
                case .panel:
                    return draftSettings.panelShortcut
                case .translation:
                    return draftSettings.translationShortcut
                case .globalNewNote, .globalCopyJoined, .globalCopyNormalized:
                    return AppSettings.default.panelShortcut
                case .newNote:
                    return draftSettings.newNoteShortcut
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
                case .copyJoined:
                    return draftSettings.copyJoinedShortcut
                case .copyNormalized:
                    return draftSettings.copyNormalizedShortcut
                case .toggleMarkdownPreview:
                    return draftSettings.toggleMarkdownPreviewShortcut
                case .joinLines:
                    return draftSettings.joinLinesShortcut
                case .normalizeForCommand:
                    return draftSettings.normalizeForCommandShortcut
                case .orphanCodexDiscard:
                    return draftSettings.orphanCodexDiscardShortcut
                }
            },
            set: { newValue in
                switch target {
                case .panel:
                    draftSettings.panelShortcut = newValue
                case .translation:
                    draftSettings.translationShortcut = newValue
                case .globalNewNote, .globalCopyJoined, .globalCopyNormalized:
                    break
                case .newNote:
                    draftSettings.newNoteShortcut = newValue
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
                case .copyJoined:
                    draftSettings.copyJoinedShortcut = newValue
                case .copyNormalized:
                    draftSettings.copyNormalizedShortcut = newValue
                case .toggleMarkdownPreview:
                    draftSettings.toggleMarkdownPreviewShortcut = newValue
                case .joinLines:
                    draftSettings.joinLinesShortcut = newValue
                case .normalizeForCommand:
                    draftSettings.normalizeForCommandShortcut = newValue
                case .orphanCodexDiscard:
                    draftSettings.orphanCodexDiscardShortcut = newValue
                }
            }
        )
    }

    private func optionalBinding(for target: ShortcutTarget) -> Binding<HotKeyManager.Shortcut?> {
        Binding(
            get: {
                switch target {
                case .globalNewNote:
                    return draftSettings.globalNewNoteShortcut
                case .globalCopyJoined:
                    return draftSettings.globalCopyJoinedShortcut
                case .globalCopyNormalized:
                    return draftSettings.globalCopyNormalizedShortcut
                default:
                    return nil
                }
            },
            set: { newValue in
                switch target {
                case .globalNewNote:
                    draftSettings.globalNewNoteShortcut = newValue
                case .globalCopyJoined:
                    draftSettings.globalCopyJoinedShortcut = newValue
                case .globalCopyNormalized:
                    draftSettings.globalCopyNormalizedShortcut = newValue
                default:
                    break
                }
            }
        )
    }

    private func syncDraftFromSettings() {
        draftSettings = settings
        captureTarget = nil
        capturedShortcut = nil
        hoveredHelpTarget = nil
        expandedHelpTarget = nil
        messageText = nil
        messageSeverity = .info
        alertText = nil
    }

    private var codexStatusLines: [String] {
        guard let status = codexIntegrationStatus else {
            return items(
                en: ["Status: checking..."],
                ja: ["状態: 確認中..."]
            )
        }

        let shellLine = status.shellConfigURL.map {
            if let shellConfigured = status.shellConfigured {
                if status.unmanagedShellExportsDetected == true {
                    return t(
                        "Shell config: another editor is already registered. Install is blocked until you clean up that EDITOR / VISUAL export.",
                        "シェル設定: 別のエディタがすでに登録されています。EDITOR / VISUAL の設定を整理するまでインストールできません。"
                    )
                }

                return shellConfigured
                    ? t("Shell config: ClipboardHistory-managed Codex block is installed in \($0.lastPathComponent).", "シェル設定: \($0.lastPathComponent) に ClipboardHistory 管理の Codex ブロックが入っています。")
                    : t("Shell config: ClipboardHistory-managed Codex block is not installed in \($0.lastPathComponent).", "シェル設定: \($0.lastPathComponent) に ClipboardHistory 管理の Codex ブロックは入っていません。")
            }

            return t(
                "Shell config: not inspected yet. Use Inspect or Remove to read \($0.lastPathComponent).",
                "シェル設定: まだ確認していません。確認または削除を押すと \($0.lastPathComponent) を読みます。"
            )
        } ?? t("Shell config: unsupported shell", "シェル設定: 未対応のシェル")

        let helperLine = t(
            "Helper script: \(status.helperScriptURL.path)",
            "ヘルパースクリプト: \(status.helperScriptURL.path)"
        )
        let installLine = status.helperInstalled && status.shellConfigured == true
            ? t("State: ready. Restart your terminal or run `source` once.", "状態: 準備完了。ターミナルを再起動するか一度 `source` を実行してください。")
            : t("State: not installed yet.", "状態: まだインストールされていません。")

        return [installLine, shellLine, helperLine]
    }

    private func refreshCodexIntegrationStatus() {
        codexIntegrationStatus = appDelegate.codexIntegrationStatus()
    }

    private func installCodexIntegration() {
        do {
            codexIntegrationStatus = try appDelegate.installCodexIntegration()
            messageText = t(
                "Codex integration installed. Restart the terminal or run `source` for the shell config file.",
                "Codex 連携をインストールしました。ターミナルを再起動するか、シェル設定ファイルを `source` してください。"
            )
            messageSeverity = .success
        } catch let error as SettingsMutationError {
            messageText = message(for: error)
            alertText = messageText
            messageSeverity = .error
        } catch {
            messageText = t(
                "Could not install Codex integration.",
                "Codex 連携をインストールできませんでした。"
            )
            alertText = error.localizedDescription
            messageSeverity = .error
        }
    }

    private func inspectCodexIntegration() {
        codexIntegrationStatus = appDelegate.codexIntegrationStatus(inspectShellConfig: true)
        messageText = t("Shell config checked.", "シェル設定を確認しました。")
        messageSeverity = .info
    }

    private func removeCodexIntegration() {
        do {
            let previousStatus = appDelegate.codexIntegrationStatus(inspectShellConfig: true)
            codexIntegrationStatus = try appDelegate.removeCodexIntegration()
            if previousStatus.shellConfigured == true || previousStatus.helperInstalled {
                messageText = t(
                    "Codex integration removed. Open a new terminal if your current shell still has old EDITOR / VISUAL values.",
                    "Codex 連携を削除しました。現在のシェルに古い EDITOR / VISUAL が残っている場合は、新しいターミナルを開いてください。"
                )
                messageSeverity = .success
            } else {
                messageText = t(
                    "Nothing to remove. ClipboardHistory-managed Codex integration was not installed.",
                    "削除対象はありません。ClipboardHistory 管理の Codex 連携は入っていませんでした。"
                )
                messageSeverity = .info
            }
        } catch let error as SettingsMutationError {
            messageText = message(for: error)
            alertText = messageText
            messageSeverity = .error
        } catch {
            messageText = t(
                "Could not remove Codex integration.",
                "Codex 連携を削除できませんでした。"
            )
            alertText = error.localizedDescription
            messageSeverity = .error
        }
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
                ] + [
                    (t("New note from anywhere", "どこからでも新規作成"), draft.globalNewNoteShortcut),
                    (t("Copy joined selection from anywhere", "どこからでも一文化してコピー"), draft.globalCopyJoinedEnabled ? draft.globalCopyJoinedShortcut : nil),
                    (t("Copy normalized selection from anywhere", "どこからでも整形してコピー"), draft.globalCopyNormalizedEnabled ? draft.globalCopyNormalizedShortcut : nil)
                ].compactMap { title, shortcut in
                    shortcut.map { (title, $0) }
                }
            ),
            (
                t("Panel commands", "通常画面コマンド"),
                [
                    (t("New note", "新規作成"), draft.newNoteShortcut),
                    (t("Pin selected item", "選択中の項目をピン留め"), draft.togglePinShortcut),
                    (t("Show or hide pinned items", "ピン留めした項目の表示 / 非表示"), draft.togglePinnedAreaShortcut),
                    (t("Edit selected item", "選択中の項目を編集"), draft.editTextShortcut),
                    (t("Delete selected item", "選択中の項目を削除"), draft.deleteItemShortcut),
                    (t("Undo", "元に戻す"), draft.undoShortcut),
                    (t("Redo", "やり直し"), draft.redoShortcut),
                    (t("Join selected item into one sentence", "選択中の項目を一文に整形"), draft.copyJoinedShortcut),
                    (t("Normalize selected item whitespace", "選択中の項目の空白を整形"), draft.copyNormalizedShortcut)
                ]
            ),
            (
                t("Editor commands", "編集画面コマンド"),
                [
                    (t("Commit", "確定"), draft.commitEditShortcut),
                    (t("Indent", "まとめてインデント"), draft.indentShortcut),
                    (t("Outdent", "まとめてアウトデント"), draft.outdentShortcut),
                    (t("Move line up", "行を上へ移動"), draft.moveLineUpShortcut),
                    (t("Move line down", "行を下へ移動"), draft.moveLineDownShortcut),
                    (t("Markdown preview", "Markdown プレビュー"), draft.toggleMarkdownPreviewShortcut),
                    (t("Join into one sentence", "選択中の項目を一文に整形"), draft.joinLinesShortcut),
                    (t("Normalize whitespace", "選択中の項目の空白を整形"), draft.normalizeForCommandShortcut)
                ]
            ),
            (
                t("Codex commands", "Codex コマンド"),
                [
                    (t("Discard orphaned draft", "切断された下書きを削除"), draft.orphanCodexDiscardShortcut)
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
                    if self.isOptionalTarget(captureTarget) {
                        self.optionalBinding(for: captureTarget).wrappedValue = capturedShortcut
                    } else {
                        self.binding(for: captureTarget).wrappedValue = capturedShortcut
                    }
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
                "This setting could not be applied. \(details)",
                "この設定は適用できませんでした。\(details)"
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

    private func optionalShortcutLabel(for target: ShortcutTarget, current: HotKeyManager.Shortcut?) -> String {
        if captureTarget == target, let capturedShortcut {
            return HotKeyManager.displayString(for: capturedShortcut)
        }
        if captureTarget == target {
            return t("Press shortcut…", "入力待ち…")
        }
        guard let current else {
            return t("Not assigned", "未設定")
        }
        return HotKeyManager.displayString(for: current)
    }

    private func isOptionalTarget(_ target: ShortcutTarget) -> Bool {
        switch target {
        case .globalNewNote, .globalCopyJoined, .globalCopyNormalized:
            return true
        default:
            return false
        }
    }

    private func defaultShortcut(for target: ShortcutTarget) -> HotKeyManager.Shortcut {
        switch target {
        case .panel:
            return AppSettings.default.panelShortcut
        case .translation:
            return AppSettings.default.translationShortcut
        case .globalNewNote, .globalCopyJoined, .globalCopyNormalized:
            switch target {
            case .globalNewNote:
                return AppSettings.defaultGlobalNewNoteShortcut
            case .globalCopyJoined:
                return AppSettings.defaultGlobalCopyJoinedShortcut
            case .globalCopyNormalized:
                return AppSettings.defaultGlobalCopyNormalizedShortcut
            default:
                return AppSettings.default.panelShortcut
            }
        case .newNote:
            return AppSettings.default.newNoteShortcut
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
        case .copyJoined:
            return AppSettings.default.copyJoinedShortcut
        case .copyNormalized:
            return AppSettings.default.copyNormalizedShortcut
        case .toggleMarkdownPreview:
            return AppSettings.default.toggleMarkdownPreviewShortcut
        case .joinLines:
            return AppSettings.default.joinLinesShortcut
        case .normalizeForCommand:
            return AppSettings.default.normalizeForCommandShortcut
        case .orphanCodexDiscard:
            return AppSettings.default.orphanCodexDiscardShortcut
        }
    }
}
