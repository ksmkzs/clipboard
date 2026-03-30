# Quality Plan

[English version](./quality-plan.md)

この文書は、ClipboardHistory を OSS として公開する前の初期 hardening plan を定義します。

## 1. Compatibility

次が明示・検証されるまで、repository は support を強く主張しません。

- supported macOS versions
- supported CPU architectures: Apple Silicon / Intel
- required permissions: Accessibility と、それに準ずるもの
- expected packaging path: debug run、unsigned app、signed app、notarized build

現在の compatibility status:

- release build settings は `arm64 x86_64`
- deployment target は `macOS 14.0`
- 現在の runtime verification は Intel のみ

Remaining compatibility tasks:

1. Xcode deployment target と build settings を揃える
2. repository checkout から clean build を確認する
3. Apple Silicon machine で app を起動し、permission prompt を記録する
4. startup、menu bar presence、panel toggle、clipboard capture、paste-back を確認する
5. sleep / wake、launch-at-login、app relaunch を確認する

## 2. Functionality

最初の public MVP は scope を狭く定義するべきです。

Candidate MVP:

- text clipboard history
- image clipboard history
- item pinning
- pinned item の manual ordering
- single-item deletion
- floating panel からの history recall
- copy-back to clipboard
- paste into the previously active app
- panel toggle 用 configurable global shortcut
- startup at login
- core preference 用 settings UI
- keyboard editing command 付き text-item editor mode
- configurable experimental translation

public release 前に明示判断が必要な点:

- search
- text / image の exact duplicate-detection algorithm
- clear-history action を MVP に入れるか

Initial functionality tasks:

1. MVP と non-goal を product spec にまとめる
2. clipboard-history behavior と optional helper feature を分離する
3. duplicate、empty text、image normalization、history trimming の expected behavior を定義する
4. pinned-item behavior と settings behavior を定義する
5. 合意した behavior の regression test を追加する

すでに選んでいる UI constraints:

- default visual style は monochrome / near-monochrome
- pinned item は row ごとの star affordance で示す
- pinned area は default で collapsed、明示的に開く
- pinned item は recency と独立した persistent manual order を使う
- pinned item は ordinary history より少し compact でよい
- panel reopen 時は前回 state より最新 visible history item を選ぶ
- panel placement は exact caret ではなく frontmost window box を使う
- paste target は restrained に示す
- copy / paste / pin / delete / undo / redo / save は small green feedback response を持つ
- translation target language は Google Translate の supported set に従う
- keyboard shortcut は default を持ちつつ user-editable
- default shortcut:
  - panel toggle: `⌘⇧V`
  - translation: `⌘⇧T`
  - panel pin toggle: `P`
  - panel pinned-area open / close: `Tab`
  - pinned reorder: `⌥↑ / ⌥↓`
  - panel delete: `Delete`
  - editor save: `⌘↩`
  - editor indent / outdent: `Tab / ⇧Tab`
  - editor line up / down: `⌥↑ / ⌥↓`
  - editor join lines: `⌘J`
  - editor normalize: `⌘⇧J`

## 3. Robustness

public app では failure / edge case に対する明確な behavior が必要です。

現在見えている primary risk:

- SwiftData store と image cache の persistence path が一貫していない
- model container creation に force unwrap がある
- duplicate detection の fingerprint が弱い
- persistence / failure mode の自動 test が無い

Robustness test matrix:

- 異なる text payload の rapid repeated copies
- identical text / identical image の repeated copies
- pinned item と一致する repeated copy
- pin / unpin / pin-order normalization
- large text payload
- large image と image downscaling
- corrupted / missing image file
- corrupted SwiftData store
- filesystem issue による save failure
- stored history がある状態での app relaunch
- internal paste operation が capture に戻らないこと
- history limit trimming と image deletion
- pinned-area collapsed / expanded state
- pinned / unpinned item の delete、image cleanup、pin-order normalization
- close / reopen 後の selection reset
- caret location を取れない場合の placement fallback

Initial robustness tasks:

1. clipboard access と persistence を system pasteboard なしで test できる seam を入れる
2. crash-prone startup を recoverable error handling に置き換える
3. application-support directory structure を統一する
4. duplicate detection と persistence invariant を強化する
5. 高リスク case の自動 test を追加する

## 4. Test Specification Inventory

この repository では、次の behavior を「あればよい挙動」ではなく明示的な test target として扱います。

### 4.1 Core data / persistence rules

- history item は timestamp 降順
- pinned item は `pinOrder` のみで並ぶ
- pinned item は通常 history list から除外される
- pin は現在の pinned 最後尾へ追加される
- unpin 時は残りの `pinOrder` が正規化される
- pin label は trim され、永続化され、空文字で削除できる
- item delete 時は image file と pin label も消える
- deleted item restore 時は timestamp / pin state / pin label が復元される
- text edit は明示的に指定しない限り timestamp を動かさない
- history trimming は unpinned item のみに適用される
- duplicate capture は unpinned duplicate を置き換えるが pinned duplicate は置き換えない

### 4.2 Text editing rules

- editor mode は editor 自身の undo/redo を持つ
- `Tab` のように通常画面と編集画面で共有されるキーは、編集中に通常画面側へ漏れない
- indent / outdent は選択行単位で動く
- line up / down は selection と順序を壊さない
- join / normalize for command は undo 可能
- normalize for command は行構造を維持し、改行を潰すのは join の役割とする
- clipboard 系 command は editor state boundary を壊さない
- commit / cancel / help の shortcut は editor に正しく届き、通常の text editing 挙動を壊さない
- `⌘A`, `⌘C`, `⌘X`, `⌘V`, `⌘←→`, `⌥←→`, 各 delete, `Esc` は標準 macOS text editing に十分近い

### 4.3 Panel workflow rules

- Enter は選択 item を現在の target app に paste する
- panel invocation 間で target app を変えると実際の paste target も変わる
- panel-level undo/redo は pin / delete / reorder / 非 editor text transform を扱う
- 通常 panel mode の join / normalize は新規 item を作らず、既存 item を in-place で更新する

## 5. Complex Regression Workflows

複数 subsystem が同時に正しく動かないと pass しない、大型 regression workflow を 5 本維持します。

1. pinned delete / restore / transform workflow
   - label、pin、reorder、delete、restore、pin state restore、text edit をまとめて確認
2. history trim / duplicate workflow
   - pinned duplicate reject、unpinned duplicate replace、max-history trimming をまとめて確認
3. image delete / restore workflow
   - image file persistence、pin label persistence、delete cleanup、restore rehydration、image loading を確認
4. editor command round-trip workflow
   - indent、line move、join の後、段階的 undo/redo で exact text を確認
5. editor clipboard + normalize workflow
   - cut、paste、normalize の後、undo/redo boundary を exact text で確認

## 6. Diagnostic Breakdown Suites

大型 regression が落ちた時に fault domain を切り分けるための小さい suite を維持します。

- `ClipboardDataManagerBehaviorTests`
  - ordering、pinning、trimming、delete、restore、label、duplicate handling
- `EditorNSTextViewKeyboardTests`
  - 標準 text-editing key と editor command routing
- `PanelKeyboardRoutingTests`
  - 通常画面 / 編集画面の routing 境界と help command 表示メタデータ
- `AppDelegateTargetSelectionTests`
  - paste target selection と frontmost-app routing
- smoke scripts
  - `enter_paste_smoke.sh`
  - `enter_paste_target_switch_smoke.sh`

## 6.1 Markdown Preview Backlog

現在の Markdown preview は、実用優先であり、完全な GitHub Flavored Markdown clone ではありません。

現時点で実装済み:

- heading
- paragraph
- soft break / hard break
- unordered / ordered list
- task-list checkbox
- blockquote
- fenced code block
- inline code
- link / image
- bold / italic / strikethrough
- editor の現在行に基づく概算 auto-scroll

まだ gap がある、または完全保証していない項目:

- table
- nested list の fidelity
- ordered list の start number
- Markdown 内の raw HTML 混在
- quote / code の edge case
- image size / layout fidelity
- editor と preview の pixel-perfect scroll sync
- GitHub / Qiita と完全一致する rendering

## 7. Execution Order

1. 上の specification inventory を固定する
2. 5 本の complex workflow regression を green に保つ
3. diagnostic breakdown suite は narrow / fast に保つ
4. panel routing 変更時は target-selection / paste smoke を回す
5. editor command 変更時は editor keyboard test を回す
6. その後に compatibility / release check を広げる
