# 徒然 — PGroonga 全文検索（実装方針）

徒然（kbmemo_site）のメモ検索を `LIKE` から **PGroonga**（PostgreSQL 拡張）へ移行する。  
**2026-07 決定:** スタンドアロン Groonga サーバーは採用せず、徒然 DB（`bowmore`）への PGroonga インストール **OK**。

---

## 1. スコープ

| 対象 | 内容 |
|------|------|
| **徒然 site** | `Memo.search_text` → PGroonga クエリ、インデックス追加 |
| **如意 nyoy** | **変更なし** — `GET /api/v1/memos?q=` のまま |
| **OpenAPI** | パラメータ形状維持。任意で `search_score` を将来追加 |

検索入口（徒然内）:

- Web UI（サイドバー、ボード、Wiki 補完）
- `GET /api/v1/memos?q=`（如意 `search_memos` / RAG キーワード leg）
- `Notebooks::AvailableMemos` 等、`search_text` を呼ぶ箇所

---

## 2. なぜ PGroonga か（スタンドアロン Groonga 不採用）

| 観点 | PGroonga | スタンドアロン Groonga |
|------|----------|------------------------|
| 正本 | `memos` 行と同一 DB | PG と索引の二重管理 |
| 認可 | `policy_scope` + SQL のまま | visibility を索引側に複製する必要 |
| 同期 | 不要（INSERT/UPDATE で自動） | 作成・更新・削除の同期ジョブ |
| 運用 | PostgreSQL 拡張 1 本 | groonga-httpd + 監視 |
| 日本語 | Groonga エンジン | 同じ |

如意 DB（pgvector / メモ RAG チャンク）には **PGroonga を入れない**。キーワード検索の正本は徒然 API。

---

## 3. インフラ（bowmore）

**対象 DB:** 徒然 site 用 PostgreSQL のみ（nyoy 用 DB には入れない）。

```sql
-- スーパーユーザー（初回のみ）
CREATE EXTENSION IF NOT EXISTS pgroonga;
```

- パッケージ: [PGroonga 公式](https://pgroonga.github.io/) — PostgreSQL バージョンに合わせた `pgroonga` パッケージ
- レプリケーション: PostgreSQL 9.6+ で PGroonga 索引もレプリカへ（通常の PG レプリケーション）
- **注意:** PGroonga はクラッシュセーフではない。PostgreSQL 異常終了時は `REINDEX` が必要な場合あり（下記 §7）

---

## 4. 徒然 site 実装

### 4.1 マイグレーション

```ruby
# db/migrate/XXXX_enable_pgroonga.rb
class EnablePgroonga < ActiveRecord::Migration[8.1]
  def up
    enable_extension "pgroonga" unless extension_enabled?("pgroonga")

    execute <<~SQL.squish
      CREATE INDEX IF NOT EXISTS index_memos_on_title_body_pgroonga
      ON memos
      USING pgroonga ((title || E'\\n' || body))
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS index_memos_on_title_body_pgroonga"
    disable_extension "pgroonga"
  end
end
```

タイトルと本文を連結して 1 インデックスにまとめる（現行 LIKE と同様に両方を対象）。

### 4.2 `Memo.search_text`

```ruby
# app/models/memo.rb
scope :search_text, lambda { |query|
  q = query.to_s.strip
  next all if q.blank?

  if pgroonga_search?
    where("(title || E'\\n' || body) &@~ ?", q)
      .order(Arel.sql("pgroonga_score(tableoid, ctid) DESC"))
  else
    pattern = "%#{sanitize_sql_like(q)}%"
    where("LOWER(title) LIKE LOWER(?) OR LOWER(body) LIKE LOWER(?)", pattern, pattern)
  end
}

def self.pgroonga_search?
  return @pgroonga_search if defined?(@pgroonga_search)

  @pgroonga_search = connection.select_value(
    "SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname = 'pgroonga')"
  )
rescue StandardError
  @pgroonga_search = false
end
```

- `&@~` — PGroonga 全文検索演算子（日本語トークン化）
- `pgroonga_score` — 関連度順（LIKE は順序不定）
- CI / 拡張未導入環境は **LIKE にフォールバック**

### 4.3 テスト

- `memo_test.rb` の `search_text` テストはそのまま通る想定（フォールバック or PGroonga 付き CI）
- 本番相当: PGroonga 有効 DB で日本語・部分語・タグ併用を手動確認

### 4.4 変更しないもの

- `Api::V1::MemosController#filtered_memos` — `search_text(params[:q])` のまま
- OpenAPI / 如意 `TsurezureClient#list_memos` — クエリパラメータ不変

---

## 5. 如意側への効果

| 機能 | 効果 |
|------|------|
| Chat `search_memos` | ヒット精度・順位改善 |
| `MemoKnowledgeRetriever` キーワード leg | `list_memos(q: keyword)` の UID 取得が改善 → RRF 精度向上 |
| nyoy コード変更 | **不要** |

---

## 6. 任意の API 拡張（後方互換）

```json
{
  "memos": [{ "uid": "...", "title": "...", "search_score": 12.3 }],
  "pagination": { ... }
}
```

- `search_score` は PGroonga 利用時のみ付与（LIKE フォールバック時は省略可）
- 如意は無視してよい

---

## 7. 運用

| 事象 | 対応 |
|------|------|
| 検索結果がおかしい / ヒットしない | `REINDEX INDEX index_memos_on_title_body_pgroonga;` |
| PostgreSQL クラッシュ後 | 上記 REINDEX を runbook に記載 |
| 大規模再インデックス | メンテ時間帯に `REINDEX`（ロックに注意） |

---

## 8. 実装チェックリスト（site Workspace）

- [x] bowmore 徒然 DB に `CREATE EXTENSION pgroonga`（本番 2026-07-03）
- [x] マイグレーション `20260703101000_enable_pgroonga_on_memos.rb`
- [x] `Memo.search_text` 差し替え + LIKE フォールバック
- [x] 本番: API `?q=` 確認（旅行/香取/静岡、如意 `TsurezureClient`）
- [x] 本番: `kill -USR2` で Puma 再起動（2026-07-03）
- [ ] 本番: `git pull` で origin/main と同期（`19425c3`。gitea SSH 鍵要）

---

## 9. 関連ドキュメント

- [徒然 API 要件 §9.4](./tsuredure-api-requirements.md#94-検索確認済み)
- [kbmemo エコシステム ロードマップ](./ecosystem-roadmap.md)
- [OpenAPI 草案](./openapi/kbmemo-v1.yaml)
- [PGroonga 公式](https://pgroonga.github.io/)
