# Data Model Design

This document captures the next implementation decisions for ClipboardHistory before UI and tests are added.

## 1. Immediate Decisions

The following are now treated as the recommended implementation direction:

- `ClipboardItem` should include `isPinned`
- `ClipboardItem` should include `pinOrder`
- UI work is deferred until the model and logic boundaries are stable
- automated tests are deferred until the logic has been separated from AppKit-facing code

## 2. ClipboardItem Model

The current `ClipboardItem` model stores:

- `id`
- `timestamp`
- `type`
- `textContent`
- `imageFileName`

The next revision should add:

- `isPinned: Bool`
- `pinOrder: Int?`

Recommended near-term model:

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

Reasoning:

- pinning is a first-class product behavior, not derived UI state
- pin persistence must survive relaunch
- trimming and duplicate resolution both need direct access to pin state
- pinned-item ordering also needs durable storage, not transient UI state

## 3. Settings Model

The app now has enough user-configurable behavior that settings should be treated as durable application state.

The first settings group should include:

- panel toggle shortcut
- translation shortcut
- startup at login
- translation target language
- history size limit

Recommended storage approach:

- keep settings in `UserDefaults` initially
- wrap all reads and writes behind a dedicated settings type instead of spreading keys through `AppDelegate`

Recommended shape:

```swift
struct AppSettings {
    var panelShortcut: HotKeyManager.Shortcut
    var translationShortcut: HotKeyManager.Shortcut
    var launchAtLogin: Bool
    var translationTargetLanguage: String
    var historyLimit: Int
}
```

And a dedicated persistence wrapper, for example:

```swift
protocol SettingsStore {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}
```

## 4. Duplicate Detection Recommendation

The best practical approach here is:

- text dedupe: normalized text hash
- image dedupe: normalized image hash

This is better than using only a visible preview string or a byte prefix.

### 4.1 Text Recommendation

Use a canonical normalized text form for duplicate comparison:

- convert `\r\n` to `\n`
- optionally trim only trailing newline noise if product behavior wants that
- keep ordinary spaces meaningful
- hash the normalized string

Recommended rule:

- two text items are duplicates if their normalized text hashes match exactly

Why not prefix-based comparison:

- prefix-only comparison can collide easily
- once history becomes larger, false duplicates become user-visible data loss

Why not global raw-string comparison without hashing:

- exact string comparison is logically fine
- but a hash is easier to reuse as a stable dedupe key and easier to store alongside item metadata later if needed

### 4.2 Image Recommendation

Use the normalized stored PNG data as the duplicate basis:

- convert the incoming image to the same normalized PNG format used for persistence
- hash the normalized PNG bytes

Recommended rule:

- two image items are duplicates if their normalized-image hashes match exactly

Why this is the best default:

- it matches persisted behavior
- it avoids false mismatches from format differences like TIFF vs PNG
- it keeps the dedupe rule aligned with what the user will actually reopen later

## 5. Recommended Internal Separation

Before UI work, the current logic should be split into smaller responsibilities.

### 5.1 Clipboard Capture Layer

Responsibility:

- talk to `NSPasteboard`
- extract raw text or image payloads
- stay AppKit-facing

This layer should not decide:

- pinning
- history trimming
- duplicate removal
- settings persistence

### 5.2 History Logic Layer

Responsibility:

- decide whether a capture should be stored
- resolve duplicates
- apply pin-aware rules
- enforce history limits

This should become mostly platform-independent logic.

Suggested types:

- `HistoryDeduplicator`
- `HistoryTrimmer`
- `ClipboardFingerprint` or `DedupeKey`

### 5.3 Persistence Layer

Responsibility:

- save and fetch `ClipboardItem`
- manage image file lifecycle
- unify the application-support directory layout

This layer should expose clear operations such as:

- insert item
- delete item
- delete duplicate items
- fetch pinned items
- fetch unpinned items ordered by timestamp
- pin item
- unpin item
- reorder pinned items

### 5.4 Settings Layer

Responsibility:

- provide typed access to defaults
- isolate all settings keys
- own default shortcut values

## 6. Recommended Next Coding Step

The next implementation step should be:

1. add `isPinned` and `pinOrder` to `ClipboardItem`
2. introduce a typed settings wrapper
3. extract duplicate-key generation into a dedicated helper
4. replace the current weak fingerprint logic with hash-based dedupe keys
5. add persistence APIs for pin, unpin, and pinned-item reorder

Only after that should the project move on to:

- pinning UI
- settings UI
- automated tests

## 7. Short Answers To Current Questions

### Should `isPinned` be added?

Yes.

There is no good reason to avoid it given the current product direction. Pinning is durable state, so it belongs in the stored model.

### Should pinned items have a persistent manual order?

Yes.

Recommended:

- add `pinOrder: Int?`
- use `nil` for unpinned items
- append newly pinned items to the end
- normalize the sequence after unpin and reorder operations

### What duplicate detection is recommended?

Recommended:

- text: normalized text hash
- image: normalized image hash after image normalization

This is the best balance of correctness, implementation cost, and future testability.
