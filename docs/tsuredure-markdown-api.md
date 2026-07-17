# 徒然 — API 書込 Markdown → AsciiDoc（P3c）

如意 Chat / MCP から徒然 API へメモを書くとき、本文は **Markdown** で送り、徒然側で **AsciiDoc** に変換して `memos.body` に保存する。

**2026-07 実装:** site `MemoBodyConverter` + `PandocMarkdownToAsciidoc`（Pandoc 利用）

---

## 1. API 契約

### リクエスト

```json
POST /api/v1/memos
{
  "title": "Chat から保存",
  "body": "## 見出し\n\n本文",
  "body_format": "markdown"
}
```

| 値 | 意味 |
|----|------|
| `markdown` | Pandoc で AsciiDoc 変換してから保存 |
| `asciidoc` | 従来どおり（省略時デフォルト） |

`PATCH` の `body` / `append_body` も同様。`append_body` は変換後に既存 AsciiDoc 末尾へ `\n\n` 連結。

### レスポンス

- `body` — 保存後の **AsciiDoc** 正本
- `body_format` — 常に `"asciidoc"`

---

## 2. 実装（site）

| ファイル | 役割 |
|----------|------|
| `app/services/pandoc_markdown_to_asciidoc.rb` | Pandoc `markdown` → `asciidoc` |
| `app/services/api/v1/memo_body_converter.rb` | `body_format` 解釈・変換 |
| `app/services/api/v1/memo_writer.rb` | 保存前に `normalize!` |
| `app/controllers/api/v1/memos_controller.rb` | `body_format` 許可・エラー返却 |

変換失敗（Pandoc 未インストール等）は `422 validation_error`。

---

## 3. 如意側

`TsurezureClient#create_memo` / `#update_memo` は既定で `body_format: "markdown"` を送る。

Chat ツール説明は Markdown 書込 / AsciiDoc 読取。

---

## 4. 制限

- Pandoc 変換は **AI 生成 Markdown → 徒然 AsciiDoc** が主用途
- 徒然固有マクロの完全な逆変換は保証しない
- 本番サーバーに **pandoc** が必要（clip HTML 変換と同様）

---

## 5. チェックリスト

- [x] site 実装 + テスト
- [x] 如意 `TsurezureClient` に `body_format: markdown`
- [x] 本番 deploy + Pandoc 確認（2026-07-03）
- [x] API `body_format: markdown` → AsciiDoc 変換確認
- [x] 如意 `TsurezureClient#create_memo` smoke 確認（2026-07-17、`commit=false` の一時メモを作成し、AsciiDoc 変換後に API DELETE）

---

## 6. 関連

- [徒然 API 要件 §3.1.1](./tsuredure-api-requirements.md#311-本文フォーマット方針2026-07-決定)
- [OpenAPI 草案](./openapi/kbmemo-v1.yaml)
