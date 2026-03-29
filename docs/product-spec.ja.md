# Product Specification

[English version](./product-spec.md)

この文書は、ClipboardHistory を公開 macOS OSS アプリとして出すための MVP 仕様を定義します。

## 1. Product Summary

ClipboardHistory は、最近の clipboard history を保存し、フローティングパネルから過去のテキストや画像をすばやく呼び戻せる macOS メニューバーアプリです。

最初の public release では、実験的機能を一部含みつつも、まず信頼できる clipboard-history 体験を最優先にします。

## 2. Product Goals

MVP は次を満たすべきです。

- macOS 上で最近の clipboard change を安定して取得する
- テキストと画像の履歴を保持する
- pinned item を保持し、重要な項目へすぐ戻れるようにする
- コンパクトなフローティングパネルから最近の項目を再利用できる
- 項目を clipboard に戻せる
- 選択した項目を直前に使っていたアプリへ貼り付けられる
- settings UI から最低限の app behavior を変更できる
- 通常利用、relaunch、中程度の clipboard volume に対して安定している

## 3. Non-Goals For MVP

MVP で全部を解く必要はありません。

明示的に昇格しない限り、次は対象外です。

- account creation / sign-in
- account-based preference sync
- cloud sync
- cross-device sync
- device-to-device clipboard linking
- text / image 以外の clipboard category
- advanced search
- history export / import UI

## 4. Target Users

主な対象:

- Windows の clipboard history 相当を macOS でも使いたい人
- コピーしたテキストや画像を繰り返し再利用する individual developer、writer、一般 desktop user

MVP は single-user の local desktop workflow 向けであり、shared machine や enterprise deployment は前提にしません。

インストールや初回起動時に account setup、remote service、multi-device pairing を必要としないことを前提にします。

## 5. Supported Environment

互換性 matrix はまだ確定途中ですが、MVP の対象は次です。

- macOS 14 以降
- Apple Silicon / Intel
- local single-user usage
- Xcode 実行または app bundle 実行の menu bar app

## 6. Core User Stories

1. ユーザーとして、最近コピーしたテキストを自動保存して後で再利用したい。
2. ユーザーとして、最近コピーした画像を自動保存して後で再利用したい。
3. ユーザーとして、global shortcut で履歴パネルを開きたい。
4. ユーザーとして、キーボードで履歴リストを移動したい。
5. ユーザーとして、選択中の履歴項目を clipboard に戻したい。
6. ユーザーとして、選択中の履歴項目をパネルを開く前に使っていたアプリへ貼り付けたい。
7. ユーザーとして、重要な項目を pin して後から見つけやすくしたい。
8. ユーザーとして、起動設定や shortcut などの基本設定を settings UI から変更したい。
9. ユーザーとして、翻訳先言語を settings から変えられる experimental translation helper を使いたい。
10. ユーザーとして、長文テキストを再利用前に整えるための focused text-only editor mode がほしい。
11. ユーザーとして、空の manual note を新規作成し、main panel が閉じていても編集を続けたい。

## 7. MVP Functional Requirements

### 7.1 Application Lifecycle

- app は menu bar app として起動する
- 起動時に通常の main window は開かない
- 起動後に clipboard monitoring を開始する
- relaunch 後も history が残る
- user login 時起動を設定できる

### 7.2 Clipboard Capture

- app 実行中は system clipboard を継続監視する
- 空でない text clipboard content を取り込む
- image clipboard content を取り込む
- MVP では unsupported clipboard payload は無視する
- app 自身の paste-back 操作で重複 history entry を作らない

### 7.3 History Storage

- history item はローカルマシン上に保存する
- text history と image history は relaunch 後も残る
- 最大保持件数は固定上限を持つ
- 上限超過時は古い項目から削除する
- image item を削除したら backing image file も削除する
- pinned item は relaunch 後も残る
- pinned item は通常の trimming では削除されない

### 7.4 Pinning

- UI から pin / unpin できる
- 通常 history が増えても pinned item は見つけやすく残る
- pinned state は見た目で明確に分かる
- pinned item は recent unpinned activity に依存しない安定した表示領域を持つ
- pinned item は recency と独立した persistent manual order を持つ
- 各 row の右上に star affordance を表示する
- unpinned item は hollow star を使う
- star を押すと pinned / unpinned を切り替える
- 初回 pin 時は pinned order の末尾に追加する
- pinned item の manual reorder をサポートする

### 7.5 Panel Interaction

- global shortcut で history panel を開閉できる
- デフォルト global shortcut は `⌘⇧V`
- panel の表示位置は exact caret ではなく frontmost window box を使う
- frontmost window box を安全に取れない場合は active screen 中央へ fall back する
- pinned area は初期状態では閉じている
- 右側に pinned area の open / close control を持つ
- keyboard command でも pinned area の開閉ができる
- デフォルトの開閉キーは panel focus 中の `Tab`
- pinned item は通常 history と分離した領域に表示する
- dedicated command で先頭に空の manual note を追加できる
- 通常 history は reverse chronological order
- panel を開き直すたびに最新の unpinned item を初期選択し、前回 scroll 位置は復元しない
- `↑↓` で selection 移動
- `Esc` で panel を閉じる
- `⌘C` で選択項目を clipboard に戻す
- stored history を変えずに、選択 text item を「連結してコピー」できる
- stored history を変えずに、選択 text item を「整形してコピー」できる
- `Return` / `Enter` で選択項目を貼り付ける
- panel focus 中の `P` で pin / unpin
- panel focus 中の `⌥↑ / ⌥↓` で pinned order 内の selected pinned item を移動
- `Delete` で selected item を削除

### 7.5.1 Text Editor Mode

- text item は row action から dedicated editor mode に入れる
- editor mode は text-only で、image item には適用しない
- row chrome が混ざらない focused text box 内に item content を表示する
- text は常に plain text として編集する
- standard text selection、copy、paste、undo、redo に対応する
- indent、outdent、line move、join lines、normalize などの command-oriented editing action を持つ
- join lines は各行の行頭・行末空白を削ってから改行を消し、1 本の文字列へ連結する
- normalize は改行を維持したまま、各行の行頭・行末空白だけを削る
- 必要な時だけ plain-text draft の横に Markdown プレビューを表示できる
- `⌘Return` で commit
- `Escape` で draft を保存せず cancel
- main panel が見えていない時は、新規ノート用の editor-only window を開ける

### 7.6 Clipboard Reuse

- panel から copy すると、その item を system clipboard に戻す
- panel から paste すると、可能なら previously active app に focus を戻す
- focus 復帰後に synthesize paste command を送る
- panel open 中は header の compact target label などで paste target を控えめに示す
- 詳しい keyboard guidance は `Cmd+?` で開く dedicated help surface に置き、header を command 一覧で埋めない
- paste 完了時は短い monochrome toast / HUD を使ってもよいが、大きく派手な通知にはしない

### 7.7 Settings UI

- user-configurable behavior のための settings UI を提供する
- macOS 標準に近い settings-window conventions を使う
- 最低限必要な項目:
  - panel toggle shortcut
  - translation shortcut
  - startup at login
  - translation target language
  - history size limit
  - settings-window language
  - editor command shortcuts
- 各 shortcut は default value を持ち、変更可能
- app settings shortcut の default は macOS 慣習どおり `⌘,`
- experimental feature は settings で明示表示する
- main clipboard-history UI は English-first、settings window は English / Japanese 切り替え可

### 7.8 Experimental Translation Feature

- translation は public application に含めるが experimental 扱い
- 専用 shortcut で trigger できる
- default global shortcut は `⌘⇧T`
- translation target language は settings で変更できる
- target language は Google Translate が対応する language set から選ぶ
- source priority は「panel で現在選択中の text item → focused app の selected text → clipboard text」
- 可能なら currently selected text を優先
- selected text が使えない時は clipboard text に fallback してよい
- translation は browser で Google Translate を開き、それ自体では clipboard history entry を新規作成・上書きしない
- experimental とは「app が crash しないことは守るが、正確な挙動や保証は core feature より速く変わり得る」という意味

## 8. Data Rules

これらは test を左右するので明示します。

### 8.1 Text

- whitespace / newline だけの text は無視する
- 受理した text は original form のまま保存する
- duplicate handling は deterministic で documented であること

提案ルール:

- 新規 text item が既存 history entry と一致した場合、既存 item が pinned でなければ古い duplicate を削除し、新しい capture を残す

### 8.2 Images

- image payload は persistent storage 用に normalize して保存する
- 大きな画像は保存前に downscale してよい
- image file が missing / unreadable でも app は crash しない

提案ルール:

- 保存画像は PNG に normalize
- 最大 dimension は 2000 px
- 新規 image item が既存 history entry と一致した場合、既存 item が pinned でなければ古い duplicate を削除し、新しい capture を残す

### 8.3 History Limit

提案ルール:

- default history limit は 150
- trimming は oldest-first
- trimming 対象は unpinned item のみ

### 8.4 Pinning And Duplicates

提案ルール:

- duplicate removal は ordinary history 全体に対して行い、連続 capture のみには限定しない
- pinned item も duplicate comparison に含める
- pinned item は user が明示的に unpin / delete しない限り duplicate cleanup で消さない
- 新規 capture が pinned item と一致した場合、pinned item を authoritative とし、duplicate の unpinned item は追加しない

### 8.5 Pin Ordering

提案ルール:

- pinned item は capture timestamp ではなく persistent manual order で並べる
- unpinned item を pin すると pinned order の末尾に追加
- unpin すると pinned order から削除し gap を詰める
- manual reorder は persistent pin order を deterministic に書き換える
- 初期 UI では drag-and-drop と `⌥↑ / ⌥↓` の両方を許容してよい

### 8.6 Deletion

提案ルール:

- ordinary history と pinned region のどちらからでも single selected item を削除できる
- pinned item 削除時は persistent pinned order からも除く
- image item 削除時は backing image file も削除する
- MVP では clear-all-history action は必須ではない

## 9. Visual And Interaction Direction

public MVP は decorative より restrained を優先します。

- default look は monochrome または near-monochrome
- grayscale surface と最小限の accent
- rich gradient、glass-heavy styling、colorful card treatment には依存しない
- default history list は compact で low-noise
- pinned item の discoverability は loud styling ではなく structure と icon で示す
- settings UI は custom visual system ではなく standard macOS control / layout を使う
- copy、paste、pin、delete confirmation は brief monochrome toast-style でよい

## 10. Permissions

MVP では permission 前提を明示するべきです。

- clipboard capture 自体は通常の platform behavior 以上の special prompt を必要としない
- synthetic paste と selected-text access には Accessibility permission が必要
- 必要 permission が欠けていても、その permission を使わない機能までは利用できるべき

## 11. Error Handling Expectations

想定内の local failure case で public MVP が crash しないことを目標にします。

最低限の期待:

- startup persistence error は uncontrolled crash にせず surfaced / handled する
- image read failure は UI 上で graceful に degrade する
- write failure で unrelated stored history を壊さない
- unsupported clipboard format は安全に無視する

## 12. Observability Expectations

重い telemetry は不要ですが、developer-visible diagnostics は必要です。

- important persistence failure は log に出る
- permission-related limitation は開発中に理解できる
- failure path は manual clipboard interaction なしでも test できる

## 13. Proposed Test Strategy

### 13.1 Unit Tests

- text acceptance と whitespace rejection
- duplicate detection rules
- history trimming behavior
- pinned-item retention rules
- image normalization policy
- shortcut parsing と rendering

### 13.2 Integration Tests

- text item の persistence round-trip
- image item の persistence round-trip
- stored history がある状態での relaunch
- item trim 時の image file deletion
- pinned / unpinned item に対する duplicate capture
- startup setting persistence
- internal paste-back が再 capture に入らないこと

### 13.3 Manual Compatibility Checks

- first launch behavior
- menu bar icon presence
- global shortcut で panel が開閉できること
- keyboard navigation
- pinned item が visible / actionable であること
- text / image の copy-back
- previously active app への paste-back
- startup at login
- translation target language change
- sleep / wake 後の behavior

## 14. Explicitly Deferred Decisions

spec を最終確定する前に user intent が必要な主な判断:

1. text duplicate detection は exact-content、normalized-content、hash-based のどれにするか
2. image duplicate detection は normalization 後の content-hash にするか
3. MVP に manual deletion / clear-history UI を入れるか、あとに回すか

## 15. Recommended Initial Decisions

現時点の推奨:

- translation は explicitly experimental のままにする
- ordinary history 全体で duplicate を collapse し、古い duplicate を削除する
- macOS 14+ を target にする
- startup at login を含める
- pinning を含める
- 早い段階で小さな settings UI を入れる
- deletion UI は core storage / pinning model が安定するまで後回しでもよい

これにより、public promise を狭く保ちつつ、実際に test と guarantee がしやすくなります。
