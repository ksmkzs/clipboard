# ClipboardHistory

[English README](./README.md)

今 macOS を使っている皆様は、以下の悩みを抱えているはずです。

- コピーをしたけど、前コピーしたやつなんだったっけ... Windows なら遡れるのに...
- チャットエージェントにテキストを送りたいけど VSCode は重いな...
- md 形式ってなんでプレビューしづらいんだろう...
- そもそも mac のリマインド、メモ系の純正アプリ多すぎてよくわからない...
- ターミナルで長文を消すのに `ctrl+k` を連打することはなんて非効率なんだろう...
- 文章をコピーして Google 翻訳に投げる作業の繰り返し...
- 私はコピーした文章の空白を消すために生きてるのかな...

このアプリは、あなたの悩みをとても簡単に解決します。

---

## 主な機能

- [x] クリップボード履歴の自動保存 / 読み返し
- [x] 雑に使えるテキストボックス
- [x] なんとなくいつも使う文章はピン留め可能
- [x] テキストの空白を自動整形
- [x] 一文化も One Command
- [x] 簡単操作で Markdown プレビュー
- [x] `.md` / `.txt` / 拡張子不明の plain text を直接開いて編集
- [x] 保存済み file と監視 directory 向けの local history
- [x] そもそもコピーする文章が整形済み
- [x] Codex CLI 連携で CLI に送る文章をいつものように作成できる

---

## 画面構成

### 標準ウィンドウ

通常のクリップボード履歴を扱う画面です。

できること:

- クリップボード履歴一覧の表示
- コピー / 前面アプリへの貼り付け
- 履歴の個別ピン留め / 削除 / 名前付け
- One Command で文章を整形
- 直接履歴を編集可能
- Markdown プレビュー

### 新規テキストウィンドウ

新しくテキストを書くための独立ウィンドウです。  
ワンコマンドでどこからでもメモを取り出せます。  
クリップボードに自動保存。`名称未設定(12).txt` はもういりません。

できること:

- 新規テキストの作成
- Markdown プレビュー
- `⌘↩` で前面アプリへ出力

### ファイルを開いて編集

`.md`、`.txt`、または plain text として読めるファイルをそのまま開いて編集できます。

- `.md` は Markdown プレビュー付き
- autosave はしません
- `⌘S` で保存
  - 保存先あり: その file に保存
  - 保存先なし: クリップボードに保存
- 未保存のまま閉じる時は
  - クリップボードに保存
  - ファイルとして保存
  - キャンセル
  を選べます

Codex 連携を設定すると:

- Codex CLI で `Ctrl+G` を押すだけで、現在の入力をこのウィンドウで編集できます

### ローカル履歴

保存済み file には、この Mac 上だけで保持する snapshot 履歴を付けられます。

- snapshot があると editor に `Saved •N` pill が表示されます
- history pane から現在の下書きとの差分を見て、その snapshot を下書きへ復元できます
- 個別 snapshot の削除と、その file の local history 全削除ができます
- tracking 対象は次のどちらでも構いません
  - ClipboardHistory で開いた file
  - watch 対象 directory 配下で、拡張子条件に一致する file
- source file が消えた後の履歴は、orphan として残すか、猶予後に削除するかを選べます

---

## どこでも使えるショートカット

- クリップボード履歴を開く / 閉じる: `⌘⇧V`
- 現在の選択 / コピー済みコンテキストを Google 翻訳: `⌘⇧T`
- 新規テキストウィンドウを開く: `⌃⌘N`
- クリップボード内容を一文化して上書き: `⌘⌥C`
- クリップボード内容の余分な空白を除いて上書き: `⌘⇧C`

---

## 標準ウィンドウの操作

- 閉じる: `Esc`
- 取り消し / やり直し: `⌘Z / ⌘⇧Z`
- 選択中の項目を現在のウィンドウにペースト: `⌘↩`
- 選択中の項目を編集: `E`
- 選択中の項目をピン留め: `P`
- 選択中の項目を削除: `⌫`
- ピン留めした項目の表示 / 非表示: `Tab`
- 選択中の項目の空白を整形: `⌘⇧C`
- 選択中の項目を一文化: `⌘⌥C`

---

## 編集ウィンドウの操作

- キャンセル: `Esc`
- 確定: `⌘↩`
- 取り消し / やり直し: `⌘Z / ⌘⇧Z`
- まとめてインデント: `Tab`
- まとめてアウトデント: `⇧Tab`
- 行単位で移動: `⌥↑ / ⌥↓`
- Markdown プレビュー: `⌘⌥P`
- 選択中の項目の空白を整形: `⌘⇧C`
- 選択中の項目を一文化: `⌘⌥C`

---

## テキスト整形仕様

### 選択項目の余分な空白を除く

各行の先頭と末尾の空白を削除し、改行は維持します。

例:

```txt
"  a b   c  
    d"
```

→

```txt
"a b   c
d"
```

### 選択項目を一文に

各行の先頭と末尾の空白を削除してから、改行を消します。

例:

```txt
"  a b   c  
 d"
```

→

```txt
"a b   cd"
```

---

## Codex CLI 連携

ClipboardHistory は、Codex CLI の `Ctrl+G` 外部エディタ先として使えます。

想定フロー:

1. Codex CLI で `Ctrl+G`
2. ClipboardHistory の Codex 用ウィンドウが開く
3. 現在の Codex 入力内容がそのまま表示される
4. 編集する
5. `⌘↩` で Codex に反映する

補足:

- Codex 用ウィンドウでは autosave しません
- `⌘↩` した時だけ Codex 側へ反映します
- ウィンドウを閉じただけでは Codex に反映しません
- orphan 状態は、Codex 側との接続が想定外に切れた時だけ表示されます

---

## Markdown プレビューの範囲

- task list / code block / link / quote などの基本要素に対応
- HTML は未対応
- image は未対応
- link は毎回確認してからデフォルトブラウザで開きます

---

## Settings

Settings では主に以下を設定できます。

- グローバルショートカット
- 標準ウィンドウのショートカット
- 編集ウィンドウのショートカット
- ローカル履歴の tracking / 保持ポリシー
- グローバル特殊コピーの on / off
- テーマ
- UI ズーム
- 表示言語
- Launch at Login
- Codex 連携の導入 / 確認 / 削除

---

## テーマ

複数のテーマプリセットを用意しています。  
Settings ではプレビューを見ながら切り替えられます。

例:

- Graphite
- Terminal
- Amber
- Frost
- Nord
- Cobalt
- Sakura
- Forest

---

## アクセシビリティ権限について

以下の機能にはアクセシビリティ権限が必要です。

- 前面アプリへの paste-back
- 他アプリ上の選択テキスト取得
- 翻訳
- グローバル特殊コピー

未許可の場合、一部機能は動作しません。

---

## ビルド

```zsh
xcodebuild -project ClipboardHistory.xcodeproj -scheme ClipboardHistory -configuration Debug build
```

---

## 検証

- 自動テストを全体で通す:

```zsh
xcodebuild test -project ClipboardHistory.xcodeproj -scheme ClipboardHistory -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''
```

- smoke / hybrid を含む検証入口:

```zsh
./ClipboardHistoryTests/run_validation_suite.sh
```

- 手動確認に使う補助文書:
  - [local history debug file](./docs/local-history-debug.md)
  - [Markdown preview stress test](./docs/markdown-preview-stress-test.md)
  - [検証マトリクス](./docs/validation-matrix.ja.md)

---

## リリースビルド

```zsh
./scripts/package_release.sh
```

生成されるファイル:

- `build/release/ClipboardHistory.dmg`
- `build/release/ClipboardHistory-mac-universal.zip`
- `build/release/ClipboardHistory-mac-apple-silicon.zip`
- `build/release/ClipboardHistory-mac-intel.zip`
- `build/release/SHA256SUMS.txt`

---

## 状態

ClipboardHistory は現在も改善中です。  
ショートカット、外部エディタ連携、ウィンドウ挙動、テーマ、補助機能まわりは今後も調整される可能性があります。

---

## License

[MIT](./LICENSE)
