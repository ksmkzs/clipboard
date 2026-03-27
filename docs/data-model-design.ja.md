# Data Model Design

[English version](./data-model-design.md)

この文書は、UI と test を増やす前の ClipboardHistory における次の implementation decision をまとめたものです。

## 1. Immediate Decisions

次を推奨 implementation direction として扱います。

- `ClipboardItem` に `isPinned` を含める
- `ClipboardItem` に `pinOrder` を含める
- model と logic boundary が安定するまでは UI work を後回しにする
- logic が AppKit-facing code から分離されるまでは automated test を後回しにする

## 2. ClipboardItem Model

現在の `ClipboardItem` model は次を持っています。

- `id`
- `timestamp`
- `type`
- `textContent`
- `imageFileName`

次の revision で追加すべきもの:

- `isPinned: Bool`
- `pinOrder: Int?`

推奨近未来 model:

```swift
@Model
final class ClipboardItem {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var type: ClipboardItemType
    var isPinned: Bool
    var pinOrder: Int?
    var textContent: String?
    var imageFileName: String?
}
```

理由:

- pinning は derived UI state ではなく first-class product behavior
- pin persistence は relaunch をまたぐ必要がある
- trimming と duplicate resolution が pin state を直接参照する
- pinned-item ordering も transient UI state ではなく durable storage が必要

## 3. Settings Model

user-configurable behavior が増えているので、settings は durable application state として扱うべきです。

最初の settings group:

- panel toggle shortcut
- translation shortcut
- startup at login
- translation target language
- history size limit

推奨 storage approach:

- 初期段階では `UserDefaults`
- ただし read / write は `AppDelegate` に散らさず dedicated settings type に閉じ込める

推奨 shape:

```swift
struct AppSettings {
    var panelShortcut: HotKeyManager.Shortcut
    var translationShortcut: HotKeyManager.Shortcut
    var launchAtLogin: Bool
    var translationTargetLanguage: String
    var historyLimit: Int
}
```

また、dedicated persistence wrapper を用意します。

```swift
protocol SettingsStore {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}
```

## 4. Duplicate Detection Recommendation

現実的に最も良い方針:

- text dedupe: normalized text hash
- image dedupe: normalized image hash

visible preview string や byte prefix だけに頼るより良いです。

### 4.1 Text Recommendation

duplicate 比較には canonical normalized text form を使います。

- `\r\n` を `\n` に統一
- product behavior が必要なら trailing newline noise だけ調整
- ordinary space 自体は意味を持つ
- normalized string を hash 化

推奨 rule:

- normalized text hash が完全一致したら duplicate

prefix-based comparison を避ける理由:

- prefix だけでは collision しやすい
- history が大きくなると false duplicate が user-visible data loss になる

hash なし raw-string comparison を避ける理由:

- exact string comparison 自体は論理的には問題ない
- ただし stable dedupe key として再利用しにくい

### 4.2 Image Recommendation

normalize 済み PNG data を duplicate basis にします。

- incoming image を persistence 用の normalized PNG へ変換
- normalized PNG bytes を hash 化

推奨 rule:

- normalized-image hash が完全一致したら duplicate

理由:

- persisted behavior と一致する
- TIFF と PNG のような format difference による false mismatch を避けられる
- user が後で reopen するものと dedupe rule を揃えられる

## 5. Recommended Internal Separation

UI work の前に、current logic を小さな責務に分けるべきです。

### 5.1 Clipboard Capture Layer

責務:

- `NSPasteboard` と話す
- raw text / image payload を抜き出す
- AppKit-facing のままにする

ここで決めないもの:

- pinning
- history trimming
- duplicate removal
- settings persistence

### 5.2 History Logic Layer

責務:

- capture を保存対象にするか決める
- duplicate を解決する
- pin-aware rule を適用する
- history limit を守る

これは platform-independent logic に近づけるべきです。

Suggested types:

- `HistoryDeduplicator`
- `HistoryTrimmer`
- `ClipboardFingerprint` or `DedupeKey`

### 5.3 Persistence Layer

責務:

- `ClipboardItem` の save / fetch
- image file lifecycle の管理
- application-support directory layout の統一

明確な operation を持つべきです。

- insert item
- delete item
- delete duplicate items
- fetch pinned items
- fetch unpinned items ordered by timestamp
- pin item
- unpin item
- reorder pinned items

### 5.4 Settings Layer

責務:

- typed access to defaults
- settings key の隔離
- default shortcut value の所有

## 6. Recommended Next Coding Step

次の implementation step:

1. `ClipboardItem` に `isPinned` と `pinOrder` を追加
2. typed settings wrapper を導入
3. duplicate-key generation を dedicated helper に抽出
4. 弱い fingerprint logic を hash-based dedupe key に置き換える
5. pin / unpin / pinned-item reorder 用 persistence API を追加

その後に進むもの:

- pinning UI
- settings UI
- automated tests

## 7. Short Answers To Current Questions

### `isPinned` を追加すべきか

はい。

現在の product direction では durable state なので、stored model に置くべきです。

### pinned item に persistent manual order は必要か

はい。

推奨:

- `pinOrder: Int?` を追加
- unpinned item には `nil`
- newly pinned item は末尾に追加
- unpin / reorder 後は sequence を normalize

### 推奨 duplicate detection は何か

推奨:

- text: normalized text hash
- image: image normalization 後の normalized image hash

correctness、implementation cost、future testability のバランスが最も良いです。
