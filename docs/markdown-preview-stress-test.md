# Markdown Preview Stress Test

このファイルは、ClipboardHistory の Markdown preview を手動確認するための総合サンプルです。

確認したいポイント:
- 見出し、強調、打ち消し、インラインコードが見た目として区別されるか
- 箇条書き、番号付きリスト、タスクリスト、引用、コードブロック、表が崩れないか
- 長文、長い単語、深いネストでレイアウトやスクロールが破綻しないか
- リンクが視認でき、クリック確認ダイアログを経て外部ブラウザで開くか
- HTML と画像は未対応として扱われるか

---

## 1. Inline Elements

これは通常の本文です。`inline code`、**strong**、*emphasis*、***strong + emphasis***、~~strikethrough~~ を含みます。

日本語と English が混ざる文。A/B テスト、snake_case、camelCase、kebab-case、`SELECT * FROM clips WHERE id = 42;`

リンク:
- [OpenAI](https://openai.com/)
- [GitHub](https://github.com/)
- <https://example.com/>

エスケープ:
\*これは italic ではない\*
\# これは見出しではない
\[link\](https://example.com)

---

## 2. Headings

# H1 Heading
## H2 Heading
### H3 Heading
#### H4 Heading
##### H5 Heading
###### H6 Heading

---

## 3. Paragraphs And Line Breaks

これは soft break を確認する段落です。
この行は同じ段落の続きとして扱われる想定です。

これは hard break を確認する段落です。  
この行は改行されて見える想定です。

これは backslash hard break の確認です。\
この行も改行されて見える想定です。

---

## 4. Unordered Lists

- top level item A
- top level item B
  - nested item B.1
  - nested item B.2
    - nested item B.2.a
    - nested item B.2.b with `inline code`
- top level item C

---

## 5. Ordered Lists

1. first
2. second
3. third
   1. third.1
   2. third.2
4. fourth

---

## 6. Mixed Lists

1. ordered
2. ordered
   - unordered nested
   - unordered nested
3. ordered again

- unordered
- unordered
  1. ordered nested
  2. ordered nested
- unordered again

---

## 7. Task Lists

- [ ] unchecked task
- [x] checked task
- [ ] task with **strong**
  - [ ] nested unchecked
  - [x] nested checked
- [ ] task with `inline code`

---

## 8. Blockquotes

> 単一引用です。
> 2 行目も引用です。

> 引用の中に list
> - item 1
> - item 2
>
> > nested quote
> > with another line

---

## 9. Code Fences

```swift
struct ClipboardItem: Identifiable {
    let id: UUID
    let text: String
    let createdAt: Date
}

let sample = ClipboardItem(id: UUID(), text: "Hello", createdAt: .now)
print(sample)
```

```json
{
  "kind": "markdown",
  "supports_task_lists": true,
  "supports_images": false,
  "supports_html": false
}
```

```bash
#!/usr/bin/env bash
set -euo pipefail
echo "ClipboardHistory preview stress test"
```

コードブロック内でバッククォートを含むケース:

````markdown
```swift
print("nested fence example")
```
````

---

## 10. Tables

| Column A | Column B | Column C |
| --- | ---: | :---: |
| left | right | center |
| short | 123 | ok |
| very long text in a table cell to check wrapping | 987654321 | maybe |
| `inline code` | **bold** | ~~strike~~ |

---

## 11. Horizontal Rules

before

---

between

***

between

___

after

---

## 12. Long Paragraph For Wrapping

This is a deliberately long paragraph intended to verify wrapping, spacing, selection, and scroll independence in the preview pane. It contains mixed punctuation, quoted text like "clipboard history", path-like fragments such as `/Users/example/Documents/project/file.md`, and a verylongunbrokenidentifierthatisintentionallyannoyingandshouldtestwrappingbehaviorwithoutcrashingthelayoutengine.

---

## 13. Mixed Japanese And English

Markdown プレビューが、日本語の段落、English sentences, `inline code`, **強調**, *斜体* を同時に含むときに崩れないかを見ます。

リスト:
- 日本語だけの項目
- English only item
- 日本語 and English mixed item

---

## 14. Nested Structure Stress

1. level 1
   - level 2 bullet
     1. level 3 ordered
        - level 4 bullet
          - [ ] level 5 task
            > nested quote under task
            >
            > ```text
            > quoted code
            > ```
2. back to level 1

---

## 15. Unsupported HTML

以下は未対応の観測用です。

<div class="warning">
  <strong>raw HTML block</strong>
  <p>この内容は HTML として完全対応しない想定です。</p>
</div>

<span style="color: red;">inline HTML span</span>

---

## 16. Unsupported Images

以下は未対応の観測用です。

![Sample image alt text](./nonexistent-preview-image.png)

---

## 17. Reference Style Links

[OpenAI][openai]
[GitHub][github]

[openai]: https://openai.com/
[github]: https://github.com/

---

## 18. Footnote-Like Text

脚注風の記法も観測用に入れておきます。[^note]

[^note]: 実装によってはそのまま文字列として見える可能性があります。

---

## 19. Selection Copy Area

このセクションは preview 上でドラッグ選択してコピーを試すための専用エリアです。

alpha bravo charlie
delta echo foxtrot
golf hotel india

```text
copy this code block if selection works
line two
line three
```

---

## 20. End Marker

ここまで表示されていれば、長文スクロールと末尾描画は通っています。
