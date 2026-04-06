# ClipboardHistory 検証マトリクス

この文書は、手動チェック 200 項目を `XCTest` / `Smoke` / `Hybrid` / `Screenshot` / `Screenshot+State` / `Human-only` に分類したものです。

- `XCTest`: ロジック・renderer・routing をテストコードで自動確認できる
- `Smoke`: このマシン上の実アプリを UI 操作して自動確認できる
- `Hybrid`: ロジックは自動確認できるが、最終的な見た目や体感確認が残る
- `Screenshot`: スクリーンショット比較や UI 表示の観測を中心に自動化できる
- `Screenshot+State`: スクリーンショットに加えて clipboard / file / history / process state の確認が必要
- `Human-only`: 外部デバイス、外部サービス、OS 設定、主観判断が強く残るため人手確認が必要

自動検証の入口:
- [run_validation_suite.sh](/Users/ksmkzs/Documents/codex/projects/clipboard/ClipboardHistoryTests/run_validation_suite.sh)
- [ClipboardWorkflowRegressionTests.swift](/Users/ksmkzs/Documents/codex/projects/clipboard/ClipboardHistoryTests/ClipboardWorkflowRegressionTests.swift)
- [ClipboardDataManagerBehaviorTests.swift](/Users/ksmkzs/Documents/codex/projects/clipboard/ClipboardHistoryTests/ClipboardDataManagerBehaviorTests.swift)
- [EditorNSTextViewKeyboardTests.swift](/Users/ksmkzs/Documents/codex/projects/clipboard/ClipboardHistoryTests/EditorNSTextViewKeyboardTests.swift)
- [PanelKeyboardRoutingTests.swift](/Users/ksmkzs/Documents/codex/projects/clipboard/ClipboardHistoryTests/PanelKeyboardRoutingTests.swift)
- [AppDelegateTargetSelectionTests.swift](/Users/ksmkzs/Documents/codex/projects/clipboard/ClipboardHistoryTests/AppDelegateTargetSelectionTests.swift)

直近の自動実行結果:
- targeted XCTest: pass
- panel toggle smoke: pass
- panel visual top5 smoke: pass
- panel item actions smoke: pass
- editor/file/settings smoke: pass
- clipboard capture/hotkeys smoke: pass
- editor/preview/hotkeys smoke: pass
- file-open variant smoke: pass
- file + note coexistence smoke: pass
- enter/paste smoke: pass
- target-switch smoke: pass

旧 Manual 項目の分類:
- `Screenshot`: 52
- `Screenshot+State`: 51
- `Human-only`: 17

自動化済みの screenshot/state 項目の代表:
- `panel_visual_top5_smoke.sh`: 28, 29, 30, 31, 32, 33, 34, 38, 39, 42, 43, 44, 78, 145, 150, 178, 179, 180, 181
- `panel_item_actions_smoke.sh`: 45, 46, 53, 54, 55, 61, 62, 66, 67, 68, 71, 72, 74, 75, 79, 80, 83, 99
- `editor_file_settings_smoke.sh`: 137, 138, 141, 151, 152, 153, 154, 157, 158, 161, 162, 182, 183, 185, 186, 190
- `clipboard_capture_hotkeys_smoke.sh`: 1, 2, 4, 11, 12, 13, 187, 189, 194, 197, 198
- `editor_preview_hotkeys_smoke.sh`: 101, 104, 105, 106, 107, 108, 109, 110, 111, 132, 133, 134, 136, 139, 140, 142, 143, 144, 155, 156, 159, 160, 163, 164, 165, 188
- `CodexIntegrationManagerTests.swift`: 191, 192, 193

Screenshot 自動化の優先 Top 20:
注記: 1〜13, 18〜20 は `panel_visual_top5_smoke.sh` で自動化済み。
1. `38` 起動時に最新履歴が選択状態
   理由: panel の初期 state の基準で、以降の多くの screenshot テストの前提になる。
2. `39` pinned 領域が default で閉じている
   理由: 初期 layout の基準で、見た目だけで判定しやすい。
3. `28` status item 左クリックで開く
   理由: menu bar 起点の主要導線で、window 出現の有無を screenshot で判定しやすい。
4. `29` status item 左クリックで閉じる
   理由: 3 と対になる基本 toggle で、window 消失も screenshot 差分で判定しやすい。
5. `33` file editor を開いたまま `⌘⇧V` で panel だけ前面化
   理由: window 干渉の重要ケースで、frontmost window の見た目比較が有効。
6. `34` 新規テキストを開いたまま `⌘⇧V` で panel だけ前面化
   理由: 5 の sibling で、single-controller 退行を検出しやすい。
7. `30` 別 app を前面にすると標準ウィンドウが閉じる
   理由: auto-dismiss の代表ケースで、他 app 前面 screenshot で観測しやすい。
8. `31` Settings 起動中は自動で消えない
   理由: 例外仕様の代表で、Settings + panel の共存を画像で判定できる。
9. `32` Help 起動中は自動で消えない
   理由: 8 と同系統で、例外分岐の退行を検出しやすい。
10. `41` 選択状態の色が通常状態と異なる
   理由: panel state 表現の基礎で、将来の OCR/画像比較の anchor になる。
11. `42` `↓` で toggle が下へ移動
   理由: keyboard navigation の最小ケースで、選択ハイライト位置の比較で判定できる。
12. `43` `↑` で toggle が上へ移動
   理由: 11 の逆方向で、上下移動の対称性を確認できる。
13. `44` `Enter` で選択確定
   理由: toggle と selected の見た目差を固定できると、以後の panel 操作全体の基準になる。
14. `45` 項目本文クリックで選択確定
   理由: pointer 経路の基本で、キーボード経路との整合確認になる。
15. `78` `E` で編集ウィンドウを開く
   理由: panel から editor への主要導線で、window 出現だけでまず検出できる。
16. `79` 編集ボタンでも開く
   理由: 15 の button 経路で、command と button の等価性確認になる。
17. `80` 編集後 header が `未保存`
   理由: save state 表示の要で、OCR しやすいテキスト oracle がある。
18. `145` 新規テキストで preview を開ける
   理由: preview pane の有無は画像比較で判定しやすく、editor 系の代表ケースになる。
19. `150` `.md` は preview あり、`.txt` は preview なし
   理由: file kind ごとの差異が明確で、二枚の screenshot 比較に向く。
20. `180` Settings と panel が共存する
   理由: 複数 window coexistence の代表ケースで、以後の settings 系 screenshot automation の起点になる。

この 20 件は、まず screenshot oracle だけで pass/fail を取りやすい順に並べている。
次段ではこれらを `window_probe.swift` と OS-level screenshot capture に接続して自動化する。

## 1. 起動・常駐

1. 起動後に status item が出る: Screenshot+State / pass / `clipboard_capture_hotkeys_smoke.sh`
2. 起動直後に不要な main window が出ない: Screenshot+State / pass / `clipboard_capture_hotkeys_smoke.sh`
3. 起動直後から clipboard 監視が始まる: Hybrid / pass / [ClipboardDataManagerBehaviorTests.swift](/Users/ksmkzs/Documents/codex/projects/clipboard/ClipboardHistoryTests/ClipboardDataManagerBehaviorTests.swift)
4. アプリ終了で status item が消える: Screenshot+State / pass / `clipboard_capture_hotkeys_smoke.sh`
5. 再起動後に履歴が残る: Hybrid / pass / data layer tests
6. Launch at Login を有効化できる: Human-only / 未自動化 / 外部連携・主観判断のため人手確認
7. Launch at Login を無効化できる: Human-only / 未自動化 / 外部連携・主観判断のため人手確認
8. Finder から `.md` を開ける: Smoke / pass / [run_validation_suite.sh](/Users/ksmkzs/Documents/codex/projects/clipboard/ClipboardHistoryTests/run_validation_suite.sh)
9. Finder から `.txt` を開ける: Smoke / pass / [run_validation_suite.sh](/Users/ksmkzs/Documents/codex/projects/clipboard/ClipboardHistoryTests/run_validation_suite.sh)
10. 拡張子なし text file を開ける: Smoke / pass / [run_validation_suite.sh](/Users/ksmkzs/Documents/codex/projects/clipboard/ClipboardHistoryTests/run_validation_suite.sh)

## 2. クリップボード履歴取得

11. `⌘C` でコピーした text が履歴に入る: Screenshot+State / pass / `clipboard_capture_hotkeys_smoke.sh`
12. メニュー Copy が履歴に入る: Screenshot+State / pass / `clipboard_capture_hotkeys_smoke.sh`
13. 右クリック Copy が履歴に入る: Screenshot+State / pass / `clipboard_capture_hotkeys_smoke.sh`
14. 同一文字列の duplicate 処理が正しい: XCTest / pass / workflow/data-manager tests
15. 異なる文字列が順に積まれる: XCTest / pass / data-manager tests
16. 空白だけは無視される: XCTest / pass / target-selection/data-manager tests
17. image copy が image item になる: Hybrid / pass / [ClipboardDataManagerBehaviorTests.swift](/Users/ksmkzs/Documents/codex/projects/clipboard/ClipboardHistoryTests/ClipboardDataManagerBehaviorTests.swift)
18. text -> image -> text の順序が保たれる: Hybrid / pass / data-manager tests
19. 長文 copy で固まらない: XCTest / pass / large-text tests
20. Universal Clipboard 流入が履歴化される: Human-only / 未自動化 / 外部連携・主観判断のため人手確認
21. Deskflow / remote desktop 流入が履歴化される: Human-only / 未自動化 / 外部連携・主観判断のため人手確認
22. 自己ループ増殖しない: XCTest / pass / data-manager tests
23. 再起動後も直近履歴が残る: Hybrid / pass / data layer persistence tests
24. 上限超過で古い unpinned から trim される: XCTest / pass / workflow/data-manager tests
25. pinned は trim されない: XCTest / pass / workflow/data-manager tests

## 3. 標準ウィンドウの開閉

26. `⌘⇧V` で標準ウィンドウが開く: Smoke / pass / panel toggle smoke
27. 2 回目の `⌘⇧V` で閉じる: Smoke / pass / panel toggle smoke
28. status item 左クリックで開く: Screenshot / pass / `panel_visual_top5_smoke.sh`
29. status item 左クリックで閉じる: Screenshot / pass / `panel_visual_top5_smoke.sh`
30. 別 app を前面にすると標準ウィンドウが閉じる: Screenshot / pass / `panel_visual_top5_smoke.sh`
31. Settings 起動中は自動で消えない: Screenshot / pass / `panel_visual_top5_smoke.sh`
32. Help 起動中は自動で消えない: Screenshot / pass / `panel_visual_top5_smoke.sh`
33. file editor を開いたまま `⌘⇧V` で panel だけ前面化: Screenshot / pass / `panel_visual_top5_smoke.sh`
34. 新規テキストを開いたまま `⌘⇧V` で panel だけ前面化: Screenshot / pass / `panel_visual_top5_smoke.sh`
35. panel が visible だが非 frontmost の時は 1 回目で前面復帰: Smoke / pass / panel toggle smoke + target-selection contract
36. panel が frontmost の時だけ閉じる: XCTest / pass / [AppDelegateTargetSelectionTests.swift](/Users/ksmkzs/Documents/codex/projects/clipboard/ClipboardHistoryTests/AppDelegateTargetSelectionTests.swift)
37. panel の配置が邪魔しすぎない: Human-only / 未自動化 / 外部連携・主観判断のため人手確認
38. 起動時に最新履歴が選択状態: Screenshot / pass / `panel_visual_top5_smoke.sh`
39. pinned 領域が default で閉じている: Screenshot / pass / `panel_visual_top5_smoke.sh`
40. pinned 領域の初期状態が仕様どおり: Screenshot / pass / `panel_visual_top5_smoke.sh`

## 4. 標準ウィンドウのフォーカス・状態

41. 選択状態の色が通常状態と異なる: Screenshot+State / pass / `panel_visual_top5_smoke.sh`
42. `↓` で toggle が下へ移動: Screenshot / pass / `panel_visual_top5_smoke.sh`
43. `↑` で toggle が上へ移動: Screenshot / pass / `panel_visual_top5_smoke.sh`
44. `Enter` で選択確定: Screenshot / pass / `panel_visual_top5_smoke.sh`
45. 項目本文クリックで選択確定: Screenshot+State / pass / `panel_item_actions_smoke.sh`
46. 星クリックは pin だけ走る: Screenshot+State / pass / `panel_item_actions_smoke.sh`
47. 削除ボタンは delete だけ走る: Screenshot+State / pass / `panel_item_actions_smoke.sh`
48. 編集ボタンで edit が走る: Screenshot+State / pass / `panel_item_actions_smoke.sh`
49. `Tab` で pinned 領域を開く: XCTest / pass / [PanelKeyboardRoutingTests.swift](/Users/ksmkzs/Documents/codex/projects/clipboard/ClipboardHistoryTests/PanelKeyboardRoutingTests.swift)
50. 再度 `Tab` で pinned 領域を閉じる: Hybrid / pass / panel routing contract + manual final
51. pinned 閉時の `←/→` が無効: Screenshot+State / pass / `panel_item_actions_smoke.sh`
52. pinned 開時の `←/→` が仕様どおり: Screenshot+State / pass / `panel_item_actions_smoke.sh`

## 5. 標準ウィンドウの item 操作

53. `P` で pin: Screenshot+State / pass / `panel_item_actions_smoke.sh`
54. `P` で unpin: Screenshot+State / pass / `panel_item_actions_smoke.sh`
55. 星ボタンで pin: Screenshot+State / pass / `panel_item_actions_smoke.sh`
56. 新規 pin が末尾に入る: XCTest / pass / data-manager tests
57. pinned item を rename できる: XCTest / pass / data-manager tests
58. rename を空文字に戻すとラベルが消える: XCTest / pass / [ClipboardDataManagerBehaviorTests.swift](/Users/ksmkzs/Documents/codex/projects/clipboard/ClipboardHistoryTests/ClipboardDataManagerBehaviorTests.swift)
59. pinned item を `⌥↑` で上へ移動: XCTest / pass / workflow/data-manager tests
60. pinned item を `⌥↓` で下へ移動: XCTest / pass / workflow/data-manager tests
61. `Backspace` で削除: Screenshot+State / pass / `panel_item_actions_smoke.sh`
62. 削除ボタンで削除: Screenshot+State / pass / `panel_item_actions_smoke.sh`
63. text item 削除で履歴から消える: XCTest / pass / workflow/data-manager tests
64. image item 削除で file も消える: XCTest / pass / [ClipboardDataManagerBehaviorTests.swift](/Users/ksmkzs/Documents/codex/projects/clipboard/ClipboardHistoryTests/ClipboardDataManagerBehaviorTests.swift)
65. pinned 削除で pin 順序が正規化される: XCTest / pass / data-manager tests
66. `⌘C` で選択 item を clipboard へ戻す: Screenshot+State / pass / `panel_item_actions_smoke.sh`
67. `⌘C` 後も選択状態が壊れない: Screenshot+State / pass / `panel_item_actions_smoke.sh`
68. panel 表示中に新規 copy が #1 に積まれる: Screenshot+State / pass / `panel_item_actions_smoke.sh`
69. `⌘↩` で前面 app へ paste: Smoke / pass / `enter_paste_smoke.sh`
70. paste 後に前面 app へ戻る: Smoke / pass / `enter_paste_target_switch_smoke.sh`

## 6. 標準ウィンドウの整形

71. `⌘⌥C` で一文化: Screenshot+State / pass / `panel_item_actions_smoke.sh`
72. `⌘⇧C` で各行 trim: Screenshot+State / pass / `panel_item_actions_smoke.sh`
73. 整形は同一 item 更新: XCTest / pass / workflow tests
74. 改行削除設定が有効なら改行を消す: Screenshot+State / pass / `panel_item_actions_smoke.sh`
75. スペース挿入設定が有効なら半角スペースで連結: Screenshot+State / pass / `panel_item_actions_smoke.sh`
76. 整形後に undo: XCTest / pass / editor/workflow tests
77. 整形後に redo: XCTest / pass / editor/workflow tests

## 7. 編集ウィンドウ

78. `E` で編集ウィンドウを開く: Screenshot / pass / `panel_visual_top5_smoke.sh`
79. 編集ボタンでも開く: Screenshot+State / pass / `panel_item_actions_smoke.sh`
80. 編集後 header が `未保存`: Screenshot+State / pass / `panel_item_actions_smoke.sh`
81. `⌘S` で保存状態が更新: Hybrid / pass / save handler tests + manual header確認
82. `Esc` で今回の編集をキャンセル: XCTest / pass / editor tests
83. キャンセルボタンでもキャンセル: Screenshot+State / pass / `panel_item_actions_smoke.sh`
84. `Tab` でインデント: XCTest / pass / editor tests
85. `⇧Tab` でアウトデント: XCTest / pass / editor tests
86. `⌥↑` で行を上へ移動: XCTest / pass / editor tests
87. `⌥↓` で行を下へ移動: XCTest / pass / editor tests
88. `⌘Z` で undo: XCTest / pass / editor/workflow tests
89. `⌘⇧Z` で redo: XCTest / pass / editor/workflow tests
90. `⌘A` で全選択: XCTest / pass / editor tests
91. `⌘C` で本文選択コピー: XCTest / pass / editor tests
92. `⌘X` で本文選択切り取り: XCTest / pass / editor tests
93. `⌘V` で貼り付け: XCTest / pass / editor tests
94. `⌘⇧←` で行頭まで選択拡張: XCTest / pass / editor tests
95. `⌘⇧→` で行末まで選択拡張: XCTest / pass / editor tests
96. `⌥←` で単語単位移動: XCTest / pass / editor tests
97. `⌥→` で単語単位移動: XCTest / pass / editor tests
98. `⌘↩` で commit: XCTest / pass / editor tests
99. commit 後に panel item へ反映: Screenshot+State / pass / `panel_item_actions_smoke.sh`
100. 編集中に別 item 選択で仕様どおり遷移: Screenshot+State / pass / `panel_item_actions_smoke.sh`
101. 編集中の `現在のウィンドウにペースト` が編集中 text を使う: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
102. `⌘⌥P` で preview 表示: XCTest / pass / editor tests
103. `⌘⌥P` で preview 非表示: Hybrid / pass / handler test + manual final
104. preview と本文が独立スクロール: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
105. preview 幅をドラッグで変更: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
106. preview 内テキストをドラッグ選択: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
107. preview 内通常文を `⌘C` でコピー: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
108. preview 内 code block を `⌘C` でコピー: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
109. preview link クリックで確認ダイアログ: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
110. link 確認 cancel で browser を開かない: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
111. link 確認 open で browser を開く: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`

## 8. Markdown preview stress file

112. inline code / strong / emphasis / strike が見分けられる: Hybrid / pass / renderer tests + manual visual
113. H1〜H6 の差が出る: Hybrid / pass / attributed-preview test + manual visual
114. soft break / hard break の差がある: Hybrid / pass / renderer tests + manual visual
115. unordered list のネストが崩れない: Hybrid / pass / renderer tests + manual visual
116. ordered list のネストが崩れない: Hybrid / pass / renderer tests + manual visual
117. mixed list が崩れない: Hybrid / pass / renderer tests + manual visual
118. task list の checkbox が出る: Hybrid / pass / renderer tests + manual visual
119. blockquote / nested quote が見える: Hybrid / pass / renderer tests + manual visual
120. 複数 code fence が壊れない: Hybrid / pass / renderer tests + manual visual
121. 長い outer fence が inner fence を保持する: Hybrid / pass / renderer tests + manual visual
122. table として描画される: Hybrid / pass / renderer tests + manual visual
123. horizontal rule が出る: Hybrid / pass / renderer tests + manual visual
124. 長文折り返しが壊れない: Hybrid / pass / renderer tests + manual visual
125. 日英混在が崩れない: Hybrid / pass / renderer tests + manual visual
126. 深いネスト構造が大崩れしない: Hybrid / pass / renderer tests + manual visual
127. unsupported HTML が未対応扱い: Hybrid / pass / renderer tests + manual visual
128. unsupported image が placeholder 扱い: Hybrid / pass / [EditorNSTextViewKeyboardTests.swift](/Users/ksmkzs/Documents/codex/projects/clipboard/ClipboardHistoryTests/EditorNSTextViewKeyboardTests.swift)
129. reference-style link が link になる: Hybrid / pass / renderer tests + manual visual
130. footnote 参照が本文中に出る: Hybrid / pass / renderer tests + manual visual
131. footnote 本文が末尾に出る: Hybrid / pass / renderer tests + manual visual
132. Selection Copy Area の通常文がコピーできる: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
133. Selection Copy Area の code block がコピーできる: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
134. End Marker まで描画される: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`

## 9. 新規テキストウィンドウ

135. `⌃⌘N` で新規テキストが開く: Smoke / pass / file + note coexistence smoke
136. 空のまま閉じると clipboard 保存しない: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
137. 本文ありで閉じると保存ダイアログ: Screenshot+State / pass / `editor_file_settings_smoke.sh`
138. close -> クリップボードに保存: Screenshot+State / pass / `editor_file_settings_smoke.sh`
139. close -> ファイルとして保存: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
140. close -> 保存しない: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
141. close -> キャンセル: Screenshot+State / pass / `editor_file_settings_smoke.sh`
142. 保存先未指定の `⌘S` で clipboard 保存: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
143. 保存先未指定の `⌘⇧S` で保存方法選択: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
144. `⌘↩` で前面 app へ出力: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
145. 新規テキストで preview を開ける: Screenshot / pass / `panel_visual_top5_smoke.sh`
146. file editor が開いていても別で新規テキストを開ける: Smoke / pass / file + note coexistence smoke

## 10. file-backed editor

147. status/menu から `.md` を開ける: Smoke / pass / file-open variant smoke
148. status/menu から `.txt` を開ける: Smoke / pass / file-open variant smoke
149. plain text file を開ける: Smoke / pass / file-open variant smoke
150. `.md` は preview あり、`.txt` は preview なし: Screenshot / pass / `panel_visual_top5_smoke.sh`
151. 未変更 file を閉じても prompt が出ない: Screenshot+State / pass / `editor_file_settings_smoke.sh`
152. 既存 file で `⌘S` が上書き保存: Screenshot+State / pass / `editor_file_settings_smoke.sh`
153. 既存 file で `⌘⇧S` が保存方法選択: Screenshot+State / pass / `editor_file_settings_smoke.sh`
154. `⌘⇧S` -> クリップボードに保存: Screenshot+State / pass / `editor_file_settings_smoke.sh`
155. `⌘⇧S` -> ファイルとして保存: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
156. Save Panel で別名保存できる: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
157. close 時に 4 択が出る: Screenshot+State / pass / `editor_file_settings_smoke.sh`
158. close -> 保存しない で元 file が変わらない: Screenshot+State / pass / `editor_file_settings_smoke.sh`
159. close -> クリップボードに保存: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
160. close -> ファイルとして保存: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
161. 外部変更で警告が出る: Screenshot+State / pass / `editor_file_settings_smoke.sh`
162. 警告 -> ファイル内容に同期: Screenshot+State / pass / `editor_file_settings_smoke.sh`
163. 警告 -> 現在内容をクリップボードに保存: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
164. 警告 -> 現在内容を別ファイルとして保存: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
165. 警告 -> キャンセル: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`

## 11. Codex window

166. `Ctrl+G` で専用 window が開く: Human-only / 未自動化 / 外部連携・主観判断のため人手確認
167. header に project root と session ID が出る: Human-only / 未自動化 / 外部連携・主観判断のため人手確認
168. 現在の Codex 入力が入っている: Human-only / 未自動化 / 外部連携・主観判断のため人手確認
169. `⌘↩` で Codex へ反映: Human-only / 未自動化 / 外部連携・主観判断のため人手確認
170. `⌘↩` 後に Codex 側へ focus return: Human-only / 未自動化 / 外部連携・主観判断のため人手確認
171. close だけでは Codex に反映しない: Human-only / 未自動化 / 外部連携・主観判断のため人手確認
172. close 後に不要 orphan window が出ない: Human-only / 未自動化 / 外部連携・主観判断のため人手確認
173. 異常切断時に同じ window が orphan 化: Human-only / 未自動化 / 外部連携・主観判断のため人手確認
174. orphan 状態で編集継続できる: Human-only / 未自動化 / 外部連携・主観判断のため人手確認
175. orphan 状態の `⌘↩` で clipboard 保存: Human-only / 未自動化 / 外部連携・主観判断のため人手確認
176. orphan 状態の `⌘⇧D` で削除: Human-only / 未自動化 / 外部連携・主観判断のため人手確認
177. 複数 Codex session が共存できる: Human-only / 未自動化 / 外部連携・主観判断のため人手確認

## 12. Settings / Help / 連携

178. Settings を開ける: Screenshot / pass / `panel_visual_top5_smoke.sh`
179. Help を開ける: Screenshot / pass / `panel_visual_top5_smoke.sh`
180. Settings と panel が共存する: Screenshot / pass / `panel_visual_top5_smoke.sh`
181. Help と panel が共存する: Screenshot / pass / `panel_visual_top5_smoke.sh`
182. interface zoom を上げる: Screenshot+State / pass / `editor_file_settings_smoke.sh`
183. interface zoom を下げる: Screenshot+State / pass / `editor_file_settings_smoke.sh`
184. zoom reset: XCTest / pass / [PanelKeyboardRoutingTests.swift](/Users/ksmkzs/Documents/codex/projects/clipboard/ClipboardHistoryTests/PanelKeyboardRoutingTests.swift)
185. テーマ変更が全 window に反映: Screenshot+State / pass / `editor_file_settings_smoke.sh`
186. 言語切替が主要 UI に反映: Screenshot+State / pass / `editor_file_settings_smoke.sh`
187. panel hotkey を変更できる: Screenshot+State / pass / `clipboard_capture_hotkeys_smoke.sh`
188. 編集系 shortcut を変更できる: Screenshot+State / pass / `editor_preview_hotkeys_smoke.sh`
189. グローバル特殊コピー on/off を切れる: Screenshot+State / pass / `clipboard_capture_hotkeys_smoke.sh`
190. Codex integration inspect が見える: Screenshot+State / pass / `editor_file_settings_smoke.sh`
191. Codex integration install/update が動く: XCTest / pass / [CodexIntegrationManagerTests.swift](/Users/ksmkzs/Documents/codex/projects/clipboard/ClipboardHistoryTests/CodexIntegrationManagerTests.swift)
192. unmanaged `EDITOR` / `VISUAL` を勝手に上書きしない: XCTest / pass / [CodexIntegrationManagerTests.swift](/Users/ksmkzs/Documents/codex/projects/clipboard/ClipboardHistoryTests/CodexIntegrationManagerTests.swift)
193. Codex integration remove が managed block だけ消す: XCTest / pass / [CodexIntegrationManagerTests.swift](/Users/ksmkzs/Documents/codex/projects/clipboard/ClipboardHistoryTests/CodexIntegrationManagerTests.swift)

## 13. グローバル特殊コピー

194. 複数行 text を clipboard に入れる前提を作れる: Screenshot+State / pass / `clipboard_capture_hotkeys_smoke.sh`
195. `⌘⌥C` で clipboard を一文化: XCTest / pass / target-selection + workflow tests
196. `⌘⇧C` で clipboard 各行 trim: XCTest / pass / target-selection + workflow tests
197. 成功時に clipboard が実際に変わる: Screenshot+State / pass / `clipboard_capture_hotkeys_smoke.sh`
198. 成功時に履歴にも入る: Screenshot+State / pass / `clipboard_capture_hotkeys_smoke.sh`
199. clipboard に text が無い時は成功扱いしない: XCTest / pass / [AppDelegateTargetSelectionTests.swift](/Users/ksmkzs/Documents/codex/projects/clipboard/ClipboardHistoryTests/AppDelegateTargetSelectionTests.swift)
200. panel 表示中は item 整形として動く: XCTest / pass / [PanelKeyboardRoutingTests.swift](/Users/ksmkzs/Documents/codex/projects/clipboard/ClipboardHistoryTests/PanelKeyboardRoutingTests.swift)
