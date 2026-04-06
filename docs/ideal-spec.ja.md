# ClipboardHistory 理想仕様書

この文書は、ClipboardHistory の「理想的な完成形」を定義する草案である。

目的は次の 2 つ。

- 現在の実装や暫定挙動から独立して、守るべき仕様を固定する
- 後から赤入れしやすいように、論点を 1 本の文書にまとめる

この文書はレビュー用の草案であり、今後の修正を前提とする。

## 1. 製品定義

ClipboardHistory は、macOS 向けのローカル専用 clipboard history / text workspace / Codex external editor 統合アプリである。

主目的は次の 4 つ。

1. クリップボード履歴を安定して保持する
2. 履歴項目を素早く再利用する
3. テキストを軽量に整形・編集する
4. LLM / CLI 作業用の軽量な編集面を提供する

次は対象外とする。

- cloud sync
- account sync
- collaborative editing
- cross-device sync の独自実装
- binary file editor

## 2. 基本原則

### 2.1 クリップボード履歴は「実際に clipboard に入ったもの」を記録する

- `Cmd+C` の検出は補助であって、本体ではない
- source of truth は system clipboard change である
- 右クリックコピー、メニューコピー、Universal Clipboard、remote relay でも履歴に残るべき

### 2.2 native macOS behavior を壊さない

次は first responder の native behavior を優先する。

- `⌘A`
- `⌘C`
- `⌘X`
- `⌘V`
- `⌘Z`
- `⌘⇧Z`
- `⌘← / ⌘→`
- `⌘⇧← / ⌘⇧→`
- `⌥← / ⌥→`
- 通常の delete 群
- 通常のテキスト選択拡張

override はアプリ固有の機能に必要なものだけに限定する。

### 2.3 1 つの目的に 1 つの経路

次を避ける。

- 同じ操作を複数箇所で横取りすること
- shell view と child view が同じ command を奪い合うこと
- native route と custom route が同時に存在すること

### 2.4 UI は低ノイズであること

- restrained
- monochrome / near-monochrome
- keyboard-friendly
- compact
- 必要な時だけ secondary surface を開く

## 3. 起動経路

ClipboardHistory の起動経路は次の 3 系統を持つ。

### 3.1 スタートアップ常駐

- Launch at Login が有効な場合、ログイン時に menu bar app として起動する
- 起動時に通常の main window は表示しない
- menu bar status item だけが現れる

### 3.2 アプリを通常起動した時

- Finder / Launchpad / Spotlight / `/Applications/ClipboardHistory.app` から起動できる
- 起動後は menu bar に常駐する
- その時点では標準ウィンドウを自動表示しない

### 3.3 file open 経由

次の file を「このアプリケーションで開く」から開ける。

- `.md`
- `.txt`
- plain text として読めるその他の file

この経路で起動した場合:

- app 本体が未起動なら起動する
- 対象 file の editor window を開く
- menu bar app としても常駐する

## 4. 常駐中のバックグラウンド動作

アプリ起動中は、バックグラウンドで次を行う。

- クリップボード履歴の監視
- text / image の履歴保存
- スクリーンショットが clipboard に入った場合の image 履歴保存
- pinned item や各種設定の保持

ここでいうスクリーンショット保存とは「clipboard に入った image を履歴保存する」ことを意味し、画面全体を常時監視することではない。

## 5. clipboard capture 仕様

### 5.1 source of truth

clipboard history の source of truth は `NSPasteboard.changeCount` 監視とする。

次の経路はすべて capture 対象。

- `⌘C`
- `⌘X`
- 右クリックコピー
- メニューコピー
- アプリ独自コピー
- Apple Universal Clipboard による流入
- Deskflow 等の clipboard relay
- Remote Desktop 系経由の clipboard relay

### 5.2 取得対象

- text
- image

unsupported payload は無視してよい。

### 5.3 text の受理条件

- 空文字は無視
- whitespace / newline のみも無視
- それ以外は original form のまま保持する

### 5.4 image の受理条件

- image payload を persistent storage 可能な形で保存する
- backing file が壊れても app は crash しない

### 5.5 自己ループ防止

次によって不必要な duplicate history を生成してはならない。

- app 自身の copy-back
- app 自身の internal paste
- app 自身の transform copy

## 6. 履歴データモデル

各履歴 item は少なくとも次を持つ。

- `id`
- `kind`
- `createdAt`
- `updatedAt`
- `textContent` または `imageReference`
- `isPinned`
- `pinOrder`
- `optionalLabel`

### 6.1 並び順

- 通常履歴は新しい順
- pinned item は `pinOrder` のみで並ぶ
- pinned item は通常履歴と分離する

### 6.2 duplicate handling

- unpinned duplicate は新しい capture を authoritative とする
- 古い unpinned duplicate は置き換えてよい
- pinned duplicate は削除しない
- pinned item と一致する新規 capture が来た場合、pinned item を authoritative とし通常 duplicate は増やさない

### 6.3 最大件数

- history は設定された最大件数を持つ
- trimming は oldest-first
- trimming 対象は unpinned のみ

## 7. menu bar / status menu 仕様

### 7.1 status item

- menu bar に常駐する
- left click で標準ウィンドウを開閉
- right click で status menu

### 7.2 status menu

最低限次を持つ。

- show / hide clipboard history
- new note
- open file
- settings
- quit

## 8. 標準ウィンドウを開く経路

標準ウィンドウは次の経路で開く。

- status item 左クリック
- global shortcut `⌘⇧V`

`⌘⇧V` は、どの window 状態であっても標準ウィンドウの open / close に使えるべきである。

例:

- 外部 app 使用中
- 新規テキストウィンドウ使用中
- 編集ウィンドウ使用中
- file-backed editor 使用中
- Codex window 使用中

## 9. 標準ウィンドウが閉じる時

標準ウィンドウは一般に、他 window が前面になった時に閉じる。

ただし次は例外とする。

- Settings を開いた時
- Help を開いた時

この 2 つでは標準ウィンドウは消えない。

## 10. 標準ウィンドウの配置仕様

- 起動時、現在の作業 window を邪魔しない位置に出す
- exact caret 追従や極端な四隅配置は不要
- utility-first の「近すぎず遠すぎない」配置を優先する
- frontmost window box が取得できるならそれを基準にする
- 取得できない場合は active screen 中央

## 11. 標準ウィンドウの構成

標準ウィンドウは次で構成する。

1. header
2. main history list
3. 右側の pinned 領域

pinned 領域はデフォルトで閉じる。

## 12. 標準ウィンドウの基本役割

標準ウィンドウでは設定された数までの履歴を保管・一覧表示する。

- 起動直後の `#1` は最新 item
- text と image を扱う
- スクリーンショットが clipboard に入った場合は image item として一覧に入る

履歴項目に対して次の操作ができる。

- ピン留め
- 削除
- 編集
- 整形
- コピー
- 現在のウィンドウにペースト

## 13. 標準ウィンドウにおける項目状態モデル

各履歴 item は次の 3 状態を持つ。

### 13.1 選択状態

- 現在の主対象 item
- paste / copy / edit / transform の主対象
- 起動時は最新 item が選択状態

### 13.2 toggle 状態

- 矢印キー移動で一時的に移動中の候補
- 選択とは別に存在する
- 色で視覚的に区別する

### 13.3 どちらでもない状態

- 選択でも toggle でもない通常項目

## 14. 選択と toggle の遷移規則

### 14.1 起動時

- 最新 item が選択状態
- toggle 状態は存在しない

### 14.2 toggle の発生

- 基本的に矢印キー移動でのみ発生する
- `↑ / ↓` で toggle 候補を移動する
- `← / →` は pinned 領域表示時のみ機能する

### 14.3 選択確定

toggle 状態の item は次の操作で選択状態になる。

- `Enter`
- 特殊操作ボタン以外の row 領域をクリック

## 15. pinned 領域仕様

### 15.1 開閉

- デフォルト shortcut は `Tab`
- status / header からも開閉可能

### 15.2 pinned の作成

次で pin できる。

- row 右上の star を押す
- 標準ウィンドウ操作時のデフォルト `P`

新規に pin された item は pinned 領域の末尾に追加する。

### 15.3 pinned item の追加仕様

- pinned item は通常履歴とは別領域に表示
- recency ではなく persistent manual order
- rename 可能

## 16. 標準ウィンドウの各操作仕様

### 16.1 ピン留め

- row 右上の星
- または `P`

### 16.2 削除

- 選択 item に対して `⌫`
- または row 右下の削除ボタン

### 16.3 編集

- デフォルト `E`
- または右側の編集ボタン

発動すると text item の実編集画面に入る。

### 16.4 整形

整形は item を特定の形式に変換する操作である。

種類は 2 つ。

- 各行の行頭・行末空白削除
- 一文化

一文化については、改行を完全に除去するか、半角スペースに置換するかを option で設定可能とする。

### 16.5 コピー

- 選択項目を clipboard に保存する
- これにより最新 `#1` はコピー元になる
- 標準ウィンドウ表示中に外部コピーが発生しても、現在選択中の項目は影響を受けず、`#1` に動的追加されていく
- 編集中 item や選択状態が勝手に cancel されてはならない

### 16.6 現在のウィンドウにペースト

- 標準ウィンドウ表示前の window / cursor 位置に対して行う
- 対象は選択項目、または編集中項目
- paste 後は適切な戻り先に focus を返す

## 17. 編集ウィンドウ仕様

編集ウィンドウは、標準ウィンドウの text item を focused に編集するための画面である。

### 17.1 基本

- plain text 編集
- Markdown source としても扱える
- image item には使わない

### 17.2 編集ウィンドウで override してよいもの

編集画面では、次だけを特殊操作として text box 編集より優先してよい。

- 一括インデント / アウトデント
- 列単位の移動
- 二種類の整形
- Markdown プレビュー表示 / 非表示
- 現在の領域にペースト
- 明示保存
- commit / cancel

native macOS text editing を壊してはならない。

### 17.3 デフォルト shortcut

- `Esc`: cancel
- `⌘↩`: commit
- `Tab / ⇧Tab`: indent / outdent
- `⌥↑ / ⌥↓`: 行移動
- `⌘⌥P`: preview toggle
- `⌘⌥C`: 一文化
- `⌘⇧C`: 整形
- `⌘S`: 明示保存

### 17.4 保存ルール

- `Esc` またはキャンセルボタンで、その編集セッションでの変更をすべて破棄
- それ以外の操作では上書き保存される

上書き保存される例:

- window を閉じる
- 別項目の操作や選択
- 現在のウィンドウにペースト
- 明示的 `⌘S`

### 17.5 preview

- Markdown preview を表示 / 非表示できる
- preview と本文は独立スクロール
- preview は内容更新に追従しても、勝手に scroll position を奪わない
- preview で表示されている文字列は、文字として選択・コピーできなければならない

## 18. 新規テキストウィンドウ仕様

新規テキストウィンドウは、履歴 item に紐付かない独立 draft window である。

### 18.1 開き方

- global shortcut デフォルトは `⌃⌘N`

### 18.2 基本動作

- 空の text draft を開く
- panel とは別 lifecycle を持つ
- `⌘↩` で前面 app に出力する

### 18.3 close 時

空文字または空白のみなら clipboard 保存しない。

未保存で close する時は次を出す。

- クリップボードに保存
- ファイルとして保存
- 保存しない
- キャンセル

## 19. file-backed editor 仕様

### 19.1 開ける file

- `.md`
- `.txt`
- plain text として読める拡張子不明 file

### 19.2 Finder 連携

- Finder の「このアプリケーションで開く」に現れるべき

### 19.3 `.md` の扱い

- source は plain text
- preview を表示可能

### 19.4 `.txt` / plain text の扱い

- plain text editor として扱う
- preview は不要

### 19.5 autosave

- autosave はしない

### 19.6 保存規則

保存先既知の file-backed editor:

- `⌘S`: 上書き保存
- `⌘⇧S`: まず `クリップボードに保存 / ファイルとして保存 / キャンセル` を出す

保存先未指定 editor:

- `⌘S`: クリップボード保存
- `⌘⇧S`: `クリップボードに保存 / ファイルとして保存 / キャンセル`

close 時:

- クリップボードに保存
- ファイルとして保存
- 保存しない
- キャンセル

`ファイルとして保存` は TextEdit に近い Save Panel とする。

### 19.7 外部変更検知

開いている file が外部で変更された場合は、次を表示する。

- ファイル内容に同期
- 現在内容をクリップボードに保存
- 現在内容を別ファイルとして保存
- キャンセル

無言で内容を失ってはならない。

## 20. Codex 用ウィンドウ仕様

ClipboardHistory は Codex CLI の `Ctrl+G` external editor target としても動作する。

### 20.1 基本

- helper script 経由で request file を受け取る
- Codex 専用 window を開く

### 20.2 表示情報

header または title に次を示す。

- project root
- session ID

### 20.3 commit

- `⌘↩` の時だけ Codex 側に反映
- close しただけでは反映しない
- commit 後は元の Codex 側 window / app に focus を返す

### 20.4 orphan

orphan は「想定外に接続が切れた時だけ」表示する。

- close しただけで orphan window を後出ししてはならない
- orphan では編集継続可能

orphan 時の明示操作:

- `⌘↩`: クリップボード保存
- `⌘⇧D`: 削除

## 21. Settings window 仕様

Settings は標準ウィンドウとは別の通常 window である。

### 21.1 役割

- shortcut 設定
- appearance 設定
- startup 設定
- Codex integration 設定

### 21.2 categories

少なくとも次を持つ。

- Global
- Standard Window
- Editor Window
- Codex Window
- Appearance / Behavior
- Integration

### 21.3 shortcut 設定

- すべて default を持つ
- reset と clear を持つ
- shortcut 重複は防止する

### 21.4 appearance / behavior

- theme preset
- UI zoom
- language
- launch at login
- global 特殊コピー on / off

### 21.5 Codex integration

- install
- inspect
- remove

shell config は明示操作時のみ読む / 書く。
unmanaged な `EDITOR` / `VISUAL` を勝手に上書きしてはならない。

## 22. Help window 仕様

Help は専用の読み取り window であり、header に常時大量のショートカットを並べる代わりに、詳細操作をここへ集約する。

### 22.1 役割

- keyboard guidance
- 標準ウィンドウ / 編集ウィンドウ / Codex window の主要操作説明
- shortcut 群の整理表示

### 22.2 標準ウィンドウとの関係

- Help を開いている間、標準ウィンドウは閉じない
- Help は補助 window であり、主作業面ではない

## 23. 翻訳仕様

- default global shortcut は `⌘⇧T`
- source priority:
- panel 選択 text
- frontmost app selected text
- clipboard text
- 動作は Google Translate を browser で開くこと
- translation 自体は clipboard history を新規作成しない

## 24. テーマ仕様

少なくとも次をプリセットとして持つ。

- Graphite
- Terminal
- Amber
- Frost
- Nord
- Cobalt
- Sakura
- Forest

テーマ変更は主要 window に反映される。
Settings には preview を持つ。

## 25. 通知仕様

- 小さく短い toast / HUD を使う
- 成功していないのに成功通知を出してはならない
- clipboard 更新や保存は、可能な限り readback で成功確認する

## 26. 権限仕様

Accessibility 権限は次に使う。

- paste-back
- selected text 取得
- translation 補助

必要時のみ案内し、不要な prompt を毎起動時に出してはならない。

## 27. override 最小化仕様

### 27.1 残してよい override

- panel を key / main にするための `NSPanel` override
- editor 固有 command
- panel shell 固有 command
- 純粋な layout / sizing override

### 27.2 残してはならない override

- native copy / paste / select-all を壊すもの
- preview の native selection / copy を壊すもの
- `⌘← / ⌘→ / ⌘⇧← / ⌘⇧→ / ⌥← / ⌥→` を強制変換するもの
- shell が child view より先に `Cmd+C` を奪うもの
- first responder を外枠が恒常的に奪うもの

## 28. 品質保証仕様

### 28.1 contract test

次を source contract として固定する。

- native text editing を壊す override を再導入しない
- local key monitor の乱用を再導入しない
- deprecated custom preview copy hack を再導入しない

### 28.2 regression workflow

少なくとも次を統合的に保証する。

- clipboard capture
- duplicate handling
- trimming
- pinned reorder
- panel routing
- editor command routing
- file save flow
- Codex lifecycle
- Markdown preview selection / copy

### 28.3 release 前実機確認

- `/Applications` に入れた app bundle を起動
- source の最新 build と差異がないことを確認
- panel / editor / Codex / file open / clipboard capture を実機確認

## 29. open question

この草案で今後さらに詰めるべき論点。

- preview copy の最終的な実現方式
- Markdown preview fidelity の優先順位
- file-backed editor と manual note の関係
- Codex multi-session の将来設計
- preview copy を履歴に残すべきかどうか
