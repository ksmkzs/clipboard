# ClipboardHistory

[English README](./README.md)

ClipboardHistory は、最近コピーしたテキストや画像を記録し、コンパクトなフローティングパネルから再表示、ピン留め、編集、再コピー、貼り付けできる macOS のメニューバーアプリです。

## 主な機能

- テキストと画像のクリップボード履歴
- 手動並び替えに対応した pinned 項目
- キーボード編集コマンド付きのテキスト編集モード
- 直前に使っていたアプリへの copy-back / paste-back
- 変更可能なショートカットとログイン時起動
- 翻訳先言語を設定できる実験的な Google Translate ショートカット

## スコープ

ClipboardHistory はローカルファーストです。

- アカウント作成なし
- クラウド同期なし
- 他デバイスとのクリップボード同期なし
- リモートサービス依存なし

## 対応環境

現在の対象:

- macOS 14 以降
- Apple Silicon / Intel 両対応

現在の確認状況:

- terminal からの repository build を確認済み
- editor keyboard command harness を確認済み
- Intel macOS 環境で runtime behavior を繰り返し確認済み
- Intel / Apple Silicon 向けの build 設定と release artifact は確認済みだが、複数マシンでの runtime 検証は公開前にさらに行う余地があります

## キーボード概要

デフォルトショートカット:

- パネル表示: `⌘⇧V`
- 翻訳: `⌘⇧T`
- 選択項目の再コピー: `⌘C`
- 選択項目の貼り付け: `Return`
- 選択項目の削除: `Delete`
- pinned pane の開閉: `Tab`

編集モードで追加:

- 保存: `⌘↩`
- キャンセル: `Esc`
- indent / outdent: `Tab` / `⇧Tab`
- 行の上下移動: `⌥↑` / `⌥↓`
- 行の結合: `⌘J`
- コマンド用 normalize: `⌘⇧J`

## Build

```sh
xcodebuild -project ClipboardHistory.xcodeproj -scheme ClipboardHistory -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

## 配布物の作成

署名済みの release artifact を作るには:

```sh
./scripts/package_release.sh
```

生成されるファイル:

- `ClipboardHistory-mac-universal.zip`
- `ClipboardHistory-mac-apple-silicon.zip`
- `ClipboardHistory-mac-intel.zip`
- `SHA256SUMS.txt`

配布ページは [`docs/index.ja.html`](./docs/index.ja.html) にあります。GitHub Pages を `main` ブランチの `docs/` から有効にすると、そのまま公開ページとして使えます。

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
4. 一度アプリを起動します。
5. macOS から求められた場合は Accessibility 権限を許可します。
6. Settings を開き、ショートカットやログイン時起動を調整します。

## テスト

現在の自動検証対象:

- editor keyboard command handling
- editor 専用 undo / redo routing
- 非テキスト項目の persistence undo / redo logic
- 実際の TextEdit ウィンドウに対する `Enter` paste smoke test
- TextEdit と Script Editor を切り替えた paste target switch smoke test

なお、以下は依然として UI レベルの手動確認が必要です。

- logout / login をまたぐ launch at login
- 複数の Mac / macOS バージョンでの最終動作
- 配布された署名済み build の挙動

## 権限

ClipboardHistory では次の権限が必要になることがあります。

- パネル用 hotkey と paste-back のための Accessibility 権限
- 通常のクリップボード監視に伴う clipboard access

## 既知の制約

- 現在の runtime 検証は Intel macOS 上が最も厚く、Apple Silicon については universal / thin release artifact を確認済みです。
- Launch at login は実装・登録済みですが、実用上は `/Applications` から起動する packaged app を前提にします。
- 一部の動作は macOS の Accessibility API に依存し、前面アプリによって差が出ることがあります。

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
