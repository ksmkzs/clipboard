# UI Specification

[English version](./ui-spec.md)

この文書は、SwiftUI 実装差分がさらに増える前に、ClipboardHistory の最初の public release で意図する UI を定義します。

## 1. UI Principles

UI は次を守るべきです。

- restrained、monochrome、low-noise
- scan しやすく keyboard-friendly
- 初期状態では compact で、secondary surface は必要になるまで隠す
- custom UI が実益を生まない部分では standard macOS behavior を優先する

明示的な意味:

- accent-heavy styling より grayscale / neutral surface を優先
- decorative gradient、glass-heavy treatment、colorful status state は避ける
- typography は simple / system-native
- hierarchy は ornament ではなく structure、spacing、icon で作る

## 2. Primary Surfaces

app の primary surface は 3 つです。

1. menu bar status item
2. history panel
3. settings window

MVP では document-style の main window はありません。

## 3. Menu Bar Status Item

menu bar item は minimal に保ちます。

Behavior:

- left click で history panel を開閉
- right click で status menu

Status menu contents:

- show / hide history panel
- run translation now
- configure panel shortcut
- configure translation shortcut
- open settings
- quit

Notes:

- menu bar item は dashboard ではなく utility-first
- counter、badge、noisy indicator は MVP では出さない

## 4. History Panel Overview

history panel が core product UI です。

Panel goals:

- recent history をすばやく呼び戻せる
- 頻用操作を keyboard から使える
- pinned item を見せつつ main list を恒常的に狭めない

Panel size baseline:

- 現在の baseline はおおむね `420 x 560`
- resize は許可するが、default size でも usability を保つ

Panel structure:

1. header
2. main content region
3. 右側の hidden / collapsible pinned region

Placement behavior:

- 安全に解決できる時は active text insertion caret の近傍を優先
- 近傍配置できる時は insertion point を覆わない
- caret-aware placement が unavailable / unstable / off-screen になる時は active screen 中央へ fall back
- placement は theatrical ではなく utility-first であるべき

## 5. Header

header は small and quiet に保ちます。

Required contents:

- app title: `Clipboard History`
- compact keyboard help text
- `Paste to Cursor in VS Code` のような compact paste-target hint
- 右側の pinned-area open / close affordance

Header behavior:

- MVP では search field を入れない
- 大きい control や濃い chrome は置かない
- pinned items の open / close affordance は interactive だと分かるが dominant ではない
- paste-target hint は secondary で quiet、banner 的に大きくしない

推奨 copy:

- 1 行目: product title
- 2 行目: `↑↓ Select  Cmd+C Copy  Enter Paste  P Pin  Tab Pins  Del Delete  Esc Close` のような compact legend

## 6. Main Content Region

main content region には ordinary history item のみを表示します。

Rules:

- unpinned history は reverse chronological order
- 各 row は selectable
- selected row は明確に分かる
- keyboard navigation で selected row が view 内に入るよう scroll する
- panel を開くたびに最新の visible unpinned item を選択し直し、前回 scroll 位置は復元しない

Empty state:

- history が無い時は quiet empty-state message を出す
- copied text / image が自動で現れることを短く示す
- illustration-heavy design は使わない

## 7. Pinned Region

pinned region は permanent split view ではなく secondary surface です。

Rules:

- default では collapsed
- panel 右側から開く
- ordinary history とは視覚的に分離
- pinned item のみを表示
- recency ではなく persistent manual order を使う

Open / close behavior:

- button は panel 右上付近
- `Tab` で pinned region を開閉
- 開いても ordinary history list を置き換えない
- 閉じると current selection model に戻る

Width behavior:

- open 時は text scan 可能な narrow side width
- ordinary history list より広く取りすぎない
- pinned row は ordinary history row より少し compact にしてよい

Animation:

- animation を使うなら subtle で short
- springy や decorative な motion は避ける

## 8. Row Design

row は compact で readable であるべきです。

Shared row rules:

- monochrome か near-monochrome
- rounded rectangle hit target は可
- selected state は clear
- pinned state は visible だが row 全体を支配しない
- star affordance は top-right

### 8.1 Text Row

Required elements:

- text preview
- pin star

Behavior:

- main history list では概ね 3 行まで表示
- line break は可能な限り視覚的に保つ
- copied text preview 自体を decorative bracket で囲まない
- 先頭 / 末尾に意味のある whitespace がある時だけ compact hint を追加してよい
  - 例: `start ␠×2`, `end ␠×1`, `⇥ start`, `↵ end`
- row を過度に広げず overflow は truncate

### 8.2 Image Row

Required elements:

- image preview
- pin star

Behavior:

- compact maximum height に収める
- aspect ratio を保つ
- load failure 時は quiet text fallback

### 8.3 Pin Star

Rules:

- unpinned item は hollow star
- pinned item は filled か clearly active な star
- star は row selection とは独立して click できる
- star click で toggle し、paste / copy は発火しない

## 9. Selection And Keyboard Model

panel は keyboard-first です。

Required keyboard behavior:

- `Up` / `Down`: active region 内の selection 移動
- `Enter`: selected item を paste
- `Cmd+C`: selected item を clipboard に戻す
- `Esc`: panel を閉じる
- `P`: selected item の pin state を切り替える
- `Tab`: pinned region の開閉
- `Delete`: selected item 削除
- `Option+Up` / `Option+Down`: selected pinned item の manual order 移動

Selection rules:

- ordinary history は single active selection
- pinned region が focusable になるなら、そちらにも独立した active selection が必要
- ambiguous dual selection は避ける

推奨 MVP selection model:

- 一度に focus は一つの region のみに置く
- pinned region を開いても、明示的に region を切り替えるまでは current region の focus を維持する

Open question:

- pinned region open 中に、どの keyboard action で ordinary history と pinned items の focus を移すか

## 10. Pinned Reordering UI

pinned item は manual ordering をサポートするが、最初の実装は simple に保つべきです。

推奨段階:

1. data model と persistence
2. visible pinned list
3. reordering UI

推奨 eventual UI:

- pinned region open 中に lightweight な reorder mode
- drag-and-drop と `Option+Up / Option+Down` keyboard movement を優先
- complex kanban-like interaction は入れない

MVP note:

- data layer はすでに manual pin order に対応
- 最初の UI iteration では elaborate drag affordance より keyboard reorder を先に ship する

## 11. Settings Window

settings window は standard macOS settings conventions を使います。

初期版は single-page settings window で十分です。

Required sections:

### 11.1 General

- settings-window language
- launch at login
- history size limit

### 11.2 Shortcuts

- panel toggle shortcut
- translation shortcut

### 11.3 Translation

- target language selector
- translation が experimental である短い説明

Settings principles:

- standard toggle、picker、stepper / numeric field を使う
- crowded になるまでは custom settings navigation を入れない
- settings window は English / Japanese 切り替え可
- app 本体は MVP では English-first
- account / sign-in / cross-device-linking control は入れない

## 12. Visual Tokens

default では near-monochrome を保つべきです。

推奨方向:

- background: macOS window background / control background family
- row background: subtle neutral contrast
- text: primary / secondary semantic color
- border: faint gray
- active accent: minimal / desaturated

避けるもの:

- row 全体への saturated accent fill
- purple-heavy default
- panel を glossy / inflated に見せる heavy shadow

## 13. Feedback And Deletion

重要操作は認識できるが noisy ではない feedback にします。

Rules:

- copy、paste、pin、unpin、reorder、delete に対して brief monochrome toast / HUD を出してよい
- feedback は text-first、short-lived、system warning に見えない程度の low contrast
- delete は ordinary history / pinned region どちらでも single selected item に適用
- MVP では modal confirmation を必須にしない

推奨 copy:

- `Copied`
- `Pasted`
- `Pinned`
- `Unpinned`
- `Deleted`

## 14. Accessibility And Usability Notes

- selected state は light / dark の両 appearance で readable
- star と pinned toggle affordance の hit target は mouse use に十分な大きさ
- pinning の discoverability を keyboard help だけに依存しない
- image-only item も load failure 時は textual fallback が必要

## 15. Current Implementation Notes

現在の実装には次が含まれます。

- manual ordering 付き pinned region
- row 単位の pin / delete action
- settings UI
- text item editor mode
- feedback toast
- frontmost-window-based panel placement

残っているのは core surface の欠如ではなく、compatibility verification、public packaging、UI refinement が中心です。

## 16. Recommended UI Build Order

1. `ClipboardHistoryView` を header / main list / pinned region shell に分割
2. reopen 時の selection / scroll をリセットして最新 history item を選択
3. row に pin star を追加
4. pinned-region open / close state と layout を追加
5. list を ordinary history と pinned item に分離
6. `P`、`Tab`、`Delete`、pinned-item reorder の keyboard action を追加
7. caret-aware placement と target hinting を追加
8. lightweight feedback toast / HUD を追加
9. settings window を追加
10. keyboard model だけで不足する場合に drag-and-drop reorder を追加

## 17. Open Questions

まだ user intent が必要な点:

1. pinned region open 中、keyboard focus は ordinary history と pinned item の間をどう移すべきか
2. drag-and-drop は `Option+Up / Option+Down` 以上に意味のある改善になるか
