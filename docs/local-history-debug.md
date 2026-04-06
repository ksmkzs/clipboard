# Local History Debug File

このファイルは、ClipboardHistory の file local history と Markdown preview を手動確認するためのデバッグ用サンプルです。

使い方:
- このファイルを ClipboardHistory で開く
- 数行だけ編集して保存する
- `Saved •N` から履歴を開く
- snapshot を選んで preview / restore を試す

---

## Quick Edit Targets

- edit target A: `alpha`
- edit target B: `beta`
- edit target C: `gamma`
この段落は短く保っています。末尾を少しずつ変えるだけで history の差分を作りやすくしています。

---

## Checklist

- [ ] first pass
- [ ] second pass
- [ ] restore check
- [ ] preview check

---

## Table
| Key | Value | Notes |
| --- | --- | --- |
| mode | local-history | minimal debug surface |
| preview | shared-pane | preview / history are exclusive |
| state | saved | click the status pill |

---

## Quote

> Keep the default UI quiet.
> Expand only when the user asks for detail.

---

## Code

```swift
struct DebugSnapshot {
    let revision: Int
    let title: String
}

let sample = DebugSnapshot(revision: 1, title: "draft")
print(sample)
```

---

## Long Line

This line is intentionally a little longer so wrapping behavior can be checked while editing and previewing the same document in the shared right-side pane.

---

## Japanese

ローカル履歴の確認用として、ここを何度か書き換えて保存してください。短い文を 1 つ追加して保存、別の行を削除して保存、という流れで試すと見やすいです。

---

## Scratch

- revision note 1:
- revision note 2:
- revision note 3:
