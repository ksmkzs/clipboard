# ClipboardHistory

[English README](./README.md)

ClipboardHistory は、コード、プロンプト、シェルコマンド、文章、画像を何度も使い回す人のための、キーボード中心の macOS クリップボードアプリです。

クリップボードを「いま入っている 1 件だけ」ではなく、すぐ呼び戻せる履歴、手元に固定できる pinned、貼り付け前に整えられる editor mode を持つ作業面として扱います。

## 何がうれしいか

一般的な clipboard manager は「保存する」ところまではできても、「再利用する」場面の気持ちよさが弱いことが多いです。

ClipboardHistory は、次のような場面を楽にするために作っています。

- 20 分前にコピーした有用な断片をもう一度使いたい
- 毎日使う数個の snippet だけは常に見える場所へ置いておきたい
- コピーした文章やコマンドを、別のエディタを開かず少しだけ整えたい
- いま使っているアプリへ、そのまま戻して貼り付けたい

## 独自性

- `Pinned workspace`
  通常履歴とは別に、よく使う項目を手動順序付きで保持できます。
- `Editor mode`
  テキスト項目をその場で開き、undo / redo、indent / outdent、行移動、join、normalize まで行えます。
- `Paste-back workflow`
  panel から選んだ項目を、その直前に使っていたアプリへ戻して貼り付けられます。
- `Text + image history`
  テキストと画像を同じ panel で扱えます。
- `Local-first`
  アカウント不要、同期不要、クラウド不要です。

## 基本の使い方

1. いつも通りテキストや画像をコピーします。
2. `⌘⇧V` で panel を開きます。
3. 履歴を選ぶ、pin する、必要なら editor mode で整えます。
4. `Return` で、その項目を直前のアプリへ貼り戻します。

## 主な機能

### 履歴と再利用

- テキストと画像の clipboard history
- 手動並び替え対応の pinned 項目
- 再コピーと paste-back
- delete / pin / reorder / join / normalize に対する undo / redo

### テキスト編集

- テキスト項目専用の editor mode
- macOS らしい標準的なテキスト編集挙動
- indent / outdent
- 行の上下移動
- 行の結合
- コマンド用 normalize
- 編集系ショートカットのカスタマイズ

### アプリ動作

- グローバル shortcut と in-app shortcut の設定
- Launch at Login
- 翻訳先言語を設定できる experimental Google Translate shortcut

## キーボードの要点

### 通常 panel

- panel を開く: `⌘⇧V`
- 翻訳: `⌘⇧T`
- 選択項目を再コピー: `⌘C`
- 選択項目を貼り付け: `Return`
- 選択項目を削除: `Delete`
- pinned pane の開閉: `Tab`

### editor mode

- 保存: `⌘↩`
- キャンセル: `Esc`
- indent / outdent: `Tab` / `⇧Tab`
- 行の上下移動: `⌥↑` / `⌥↓`
- 行の結合: `⌘J`
- コマンド用 normalize: `⌘⇧J`

## ダウンロード

- 配布ページ: https://ksmkzs.github.io/clipboard/
- 最新 release: https://github.com/ksmkzs/clipboard/releases/latest

利用できる配布物:

- `ClipboardHistory-mac-universal.zip`
- `ClipboardHistory-mac-apple-silicon.zip`
- `ClipboardHistory-mac-intel.zip`
- `SHA256SUMS.txt`

## インストール

1. 自分の Mac に合う build をダウンロードします。
2. `ClipboardHistory.app` を展開します。
3. `/Applications` に移動します。
4. 一度起動します。
5. macOS に求められた場合は Accessibility 権限を許可します。
6. Settings で shortcut や Launch at Login を調整します。

## 対応環境

- macOS 14 以降
- Apple Silicon / Intel 向け release target
- ローカル利用を前提とした設計で、同期前提の cross-device workflow には寄せていません

## 権限

ClipboardHistory では次の権限が必要になることがあります。

- global hotkey と paste-back のための Accessibility 権限
- クリップボード履歴監視に伴う通常の clipboard access

## 開発

repository から build:

```sh
xcodebuild -project ClipboardHistory.xcodeproj -scheme ClipboardHistory -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

配布用 release artifact を build:

```sh
./scripts/package_release.sh
```

生成されるファイル:

- `ClipboardHistory-mac-universal.zip`
- `ClipboardHistory-mac-apple-silicon.zip`
- `ClipboardHistory-mac-intel.zip`
- `SHA256SUMS.txt`

## 検証

現在の自動検証対象:

- editor keyboard command handling
- editor 専用 undo / redo routing
- 非テキスト項目の persistence undo / redo logic
- 実際の TextEdit ウィンドウに対する `Enter` paste smoke test
- TextEdit と Script Editor を切り替えた paste-target switching smoke test

手元の Mac で追加確認したほうがよい項目:

- logout / login をまたぐ Launch at Login
- 複数の Mac / macOS バージョンでの最終挙動
- zip 展開後の packaged build の初回起動

## Repository 構成

- `App/`: app lifecycle、settings state、app delegate
- `Managers/`: clipboard capture、persistence、paste、hotkeys
- `Models/`: SwiftData model
- `Views/`: panel UI、editor UI、AppKit bridge
- `ClipboardHistoryTests/`: keyboard / editing 周りの focused tests
- `docs/`: product / UI / quality 関連の文書

## 文書

- [English README](./README.md)
- [配布ページ 英語版](./docs/index.html)
- [配布ページ 日本語版](./docs/index.ja.html)
- [Product Specification 日本語版](./docs/product-spec.ja.md)
- [UI Specification 日本語版](./docs/ui-spec.ja.md)
- [Quality Plan 日本語版](./docs/quality-plan.ja.md)
- [Data Model Design 日本語版](./docs/data-model-design.ja.md)

## License

[MIT](./LICENSE)
