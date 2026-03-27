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
  - editor normalize for command: `⌘⇧J`

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

## 4. Execution Order

1. repository structure を整え、source control checkout から build できることを確認する
2. MVP scope を固定する
3. testability 向けに refactor する
4. pure logic / persistence rules の unit test を追加する
5. pasteboard capture と startup / relaunch behavior の integration test を追加する
6. manual compatibility checklist と release checklist を追加する
