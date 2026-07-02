# 徒然（tsuredure）API 要件 — 如意連携

如意（Nyoy）から徒然（kbmemo.net）のメモを読み書きし、Chat ツール・RAG 取込・書き支援に使うための API 要件を整理する。

**ステータス:** Phase 4b + 如意 Chat 拡張完了 — 徒然 API v1 本番、如意 Client / メモツール / Web 検索 / URL 取得 / メモ RAG 接続確認済み  
**前提:** 徒然側の実装は [kbmemo_site](https://gitea.artif.org/Artif.org/kbmemo_site)（ローカル: `~/work/kbmemo/site`）を正とする。

---

## 0. 名称・ローマ字表記

| 項目 | 表記 |
|------|------|
| 日本語名 | 徒然 |
| 読み | **tsuredure**（つれづれ） |
| ドメイン | kbmemo.net |
| 英語名（任意） | Tsuredure |

### ローマ字表記の使い分け（案）

正確な読みは **tsuredure** だが、英語圏の開発者・識別子では次のように使い分ける。

| 用途 | 推奨表記 | 理由 |
|------|----------|------|
| ドキュメント・対話 | **tsuredure** | 正式な読み。日本語名と併記 |
| URL・API パス | **kbmemo** | 既存ドメインと一致。`https://kbmemo.net/api/v1` |
| コード（モジュール名） | **Tsurezure** | 促音を省略した一般的ローマ字。`TsurezureClient` 等 |
| 外部 ID プレフィックス | **kbmemo** | `kbmemo:memo:{id}:chunk:{n}` — ドメインと揃える |
| 設定キー（如意） | **kbmemo** | `ServiceConnection` の `key: "kbmemo"` |

### 英語圏向けローマ字の候補

| 表記 | 例 | 長所 | 短所 |
|------|-----|------|------|
| **tsuredure** | Tsuredure API | 読みが正確 | `dure` が英語として紛らわしい |
| **tsurezure** | TsurezureClient | ローマ字として自然、コード向き | 読みがやや不明瞭 |
| **tsure-zure** | tsure-zure API | 音節が分かりやすい | ハイフン入り識別子は避けたい場面あり |
| **kbmemo** | kbmemo API | 既存ドメインと一致、最も無難 | 日本語名との対応が直感できない |

**推奨:** 対人・文書は **徒然（tsuredure）**、技術識別子は **kbmemo** を主とし、Ruby 等のコードでは **Tsurezure** を使う。

---

## 1. 目的

### 1.1 なぜ API が必要か

如意は AI 機能の集約点として、以下のユースケースで徒然のメモデータにアクセスする。

| ユースケース | 方向 | 概要 |
|-------------|------|------|
| **メモ検索** | 徒然 → 如意 | Chat / RAG が関連メモを参照 |
| **メモ作成** | 如意 → 徒然 | Chat の回答をメモとして保存 |
| **メモ更新** | 如意 → 徒然 | 書き支援（推敲・追記・要約の反映） |
| **RAG 取込** | 徒然 → 如意 | メモ本文をチャンク化・embedding して pgvector に格納 |
| **変更通知** | 徒然 → 如意 | メモ更新時に RAG を再生成（将来） |

### 1.2 スコープ

**本書の対象:**

- REST JSON API（第一候補）
- 認証・認可
- メモ CRUD + 検索
- RAG 取込に必要な一覧・差分取得
- 如意 Chat ツールから呼ぶ操作

**本書の対象外（別途）:**

- 葛籠 API（添付ファイル参照は葛籠側要件）
- 徒然 Web UI の変更
- MCP プロトコル自体（如意側で徒然 API をラップ）

---

## 2. 如意側ユースケース詳細

### UC-1: Chat からメモ検索

**アクター:** ユーザー（Chat 経由）、如意 LLM  
**流れ:**

1. ユーザーが「先月の旅行メモを探して」と入力
2. LLM が `search_memos` ツールを呼ぶ
3. 如意が徒然 API で検索
4. 結果を LLM コンテキストに注入し、回答を生成

**要求:**

- 全文検索またはセマンティック検索（初期はキーワードで可）
- タイトル・本文スニペット・更新日時・メモ ID を返す
- ページネーション

### UC-2: Chat 結果のメモ保存

**アクター:** ユーザー、LLM  
**流れ:**

1. LLM が回答を生成
2. ユーザーが「これを徒然に保存して」または LLM が `create_memo` を提案
3. 如意が徒然 API でメモ作成
4. 作成されたメモ URL / ID をユーザーに返す

**要求:**

- タイトル（自動生成可）+ 本文（**Markdown** — 徒然側で AsciiDoc に変換して保存）
- タグ・カテゴリ（徒然が持っていれば任意指定）
- 作成者・作成日時の記録

### UC-3: メモ書き支援

**アクター:** ユーザー、LLM  
**流れ:**

1. ユーザーが徒然メモ ID を指定、または検索で特定
2. 如意が `get_memo` で本文取得
3. LLM が推敲・要約・追記案を生成
4. ユーザー確認後、`update_memo` で反映（または diff 提示）

**要求:**

- 単一メモの全文取得（**AsciiDoc** — 正本のまま返す）
- 部分更新（append / replace）— 追記・置換 payload は **Markdown**（徒然側で AsciiDoc に変換）
- **楽観的ロック**（更新競合検知）— 徒然 UI と同時編集があり得る
- 更新前の `updated_at` による競合チェック（`lock_version` 未実装のため）

### UC-4: RAG 取込（バッチ）

**アクター:** 如意バックグラウンドジョブ  
**流れ:**

1. ジョブが `list_memos`（または `export_memos`）で対象メモ一覧を取得
2. 各メモをチャンク分割 → `EmbeddingClient` でベクトル化
3. `KnowledgeChunk`（source: memo）として pgvector に保存
4. 次回以降は `updated_since` で差分のみ再取込

**要求（実装済み / 残）:**

- [x] 一覧・export API、`updated_since` 差分 — **実装済み**
- [ ] 削除されたメモの検知 — **`export/deletions` 未実装**
- [x] レート制限・ページサイズ — export は `MEMO_INGEST_PAGE_LIMIT` でページング

### UC-5: RAG 取込（リアルタイム、将来）

**アクター:** 徒然 → 如意 webhook  
**流れ:**

1. 徒然でメモ保存・更新・削除
2. webhook で如意に通知
3. 如意が該当メモのみ re-embed

**要求（将来）:**

- webhook エンドポイント（如意側）
- イベント種別: created / updated / deleted
- HMAC 署名検証

---

## 3. API 設計案

### 3.1 基本方針

| 項目 | 案 |
|------|-----|
| 形式 | REST JSON |
| ベース URL | `https://kbmemo.net/api/v1`（仮） |
| 認証 | Bearer トークン（API キン） |
| エラー形式 | `{ "error": { "code": "...", "message": "..." } }` |
| 日時 | ISO 8601 UTC |
| 本文（保存） | **AsciiDoc**（`memos.body` 正本） |
| 本文（API 書込） | **Markdown**（`body_format: markdown` — 徒然側で AsciiDoc 変換） |
| 本文（API 読取） | **AsciiDoc**（`body_format: asciidoc`）。将来 Markdown 変換は徒然側オプション |
| 安定 ID | **ULID**（`uid` 列、26 桁）。数値 `id` も併用可 |

### 3.1.1 本文フォーマット方針（2026-07 決定）

AI 連携（Chat / 将来 MCP）は出力が **Markdown** 中心のため、書き込みと読み取りで役割を分ける。

| 方向 | フォーマット | 理由 |
|------|-------------|------|
| **如意 → 徒然**（`POST` / `PATCH` の `body`, `append_body`） | Markdown | LLM・Chat の自然な出力。如意側で AsciiDoc を生成させない |
| **徒然 → 如意**（`GET`, `export`） | AsciiDoc（当面） | DB 正本そのまま。テキストとして LLM は読める |
| **徒然 → 如意**（将来オプション） | Markdown | 徒然側で Pandoc 変換して返す。如意は変換しない |

**徒然側実装（site Workspace）:**

1. リクエストに `body_format: "markdown"`（省略時は従来どおり AsciiDoc として解釈 — 後方互換）
2. `PandocRunner`（既存 clip 用 HTML 変換と同系）で Markdown → AsciiDoc
3. 変換後の AsciiDoc を `memos.body` に保存し Git コミット
4. レスポンスの `body_format` は常に `"asciidoc"`（正本を示す）

**如意側:**

- `create_memo` / `update_memo` は Markdown を生成
- `TsurezureClient` は `body_format: "markdown"` を付与（**徒然側変換デプロイと同時**に有効化）
- `get_memo` / RAG export は AsciiDoc のまま利用

**Markdown 読取を将来足す場合の条件:**

- LLM が AsciiDoc マクロ（`image::`, `link:`, checklist 等）を誤解するケースが増えたとき
- 徒然 API に `Accept` または `?body_format=markdown` を追加し、**徒然側**で AsciiDoc → Markdown 変換
- 如意側は変換ロジックを持たない（正本は AsciiDoc のまま）

**注意:**

- Markdown → AsciiDoc は Pandoc 経由のため、徒然固有マクロの完全な逆変換は保証しない（AI 生成メモが主対象）
- `append_body` も Markdown 片を変換してから AsciiDoc 末尾に連結

### 3.2 認証

```
Authorization: Bearer <api_token>
```

徒然には **既存の Bearer トークン基盤** がある（`Api::BaseController`、`Account#clip_api_token_*`）。如意連携用 API はこれを拡張する案を第一候補とする。

| 要求 | 詳細 | 徒然現状 |
|------|------|----------|
| トークン発行 | プロフィール UI でユーザーごとに発行 | ✓ `clip_api_token`（`kbmemo_<base64>`）が既存 |
| 保存方式 | SHA256 ダイジェスト + prefix | ✓ `Account#digest_clip_api_token` |
| 認可 | Pundit policy | ✓ `Api::ClipsController` で利用中 |
| スコープ | `memos:read`, `memos:write` | ✗ 未実装（トークン種別で代替可） |
| 如意側保管 | Rails credentials または `ServiceConnection` | — |

**実装案:**

1. **短期:** 既存 `clip_api_token` を如意でも流用（メモ作成はクリップと同権限）
2. **中期:** `nyoy_api_token`（または汎用 `api_token`）を追加し、read/write スコープを分離
3. **認可:** 既存 `MemoPolicy` を `api/v1/memos` でもそのまま適用

**未決:** clip トークンと nyoy 専用トークンを分けるか、1 トークンに統合するか。

### 3.3 エンドポイント一覧（案）

#### メモ

| Method | Path | 用途 | UC | 徒然現状 |
|--------|------|------|-----|----------|
| `GET` | `/memos` | 一覧・検索 | UC-1, UC-4 | ✗ HTML のみ |
| `GET` | `/memos/:id` | 単体取得（`id` または `uid`） | UC-3 | ✗ HTML のみ |
| `POST` | `/memos` | 新規作成 | UC-2 | △ `POST /api/clips` のみ |
| `PATCH` | `/memos/:id` | 部分更新 | UC-3 | ✗ |
| `PUT` | `/memos/:id` | 全文置換 | UC-3 | ✗ |
| `DELETE` | `/memos/:id` | 削除 | UC-4 | ✗ |

#### 検索・エクスポート

| Method | Path | 用途 | UC |
|--------|------|------|-----|
| `GET` | `/memos/search` | 全文検索（`q`, `limit`, `offset`） | UC-1 |
| `GET` | `/memos/export` | RAG 用一括 export（`updated_since`, `fields`） | UC-4 |

#### メタ

| Method | Path | 用途 |
|--------|------|------|
| `GET` | `/health` | 疎通確認 |
| `GET` | `/me` | トークンに紐づくユーザー情報 |

---

## 4. リソース定義（案）

### 4.1 Memo

```json
{
  "id": 42,
  "uid": "01J8X2K3M4N5P6Q7R8S9T0UVWX",
  "slug": "kyoto-trip-01J8X2K3M4N5P6Q7R8S9T0UVWX",
  "title": "京都旅行メモ",
  "body": "== 1日目\n\n清水寺...",
  "body_format": "asciidoc",
  "tags": ["旅行", "2026"],
  "visibility": "owner_read_write",
  "properties": {},
  "created_at": "2026-03-15T10:00:00Z",
  "updated_at": "2026-06-20T14:30:00Z",
  "file_committed_at": "2026-06-20T14:30:00Z",
  "url": "https://kbmemo.net/memos/42",
  "draft": false
}
```

| フィールド | 必須 | 説明 |
|-----------|------|------|
| `id` | ✓ | 数値 PK（bigint） |
| `uid` | ✓ | **ULID**（26 桁、安定 ID。API の主キーとして推奨） |
| `slug` | | `{stem}-{uid}` 形式。Git ファイル名にも使用 |
| `title` | ✓ | タイトル |
| `body` | ✓ | 本文ソース。`body_format` に応じて Markdown または AsciiDoc |
| `body_format` | | レスポンスは常に `asciidoc`（正本）。書込時は `markdown` 可 |
| `tags` | | タグ名の配列 |
| `visibility` | | `public_everyone` / `group_read` / `group_read_write` / `owner_read_write` |
| `properties` | | jsonb（`scheduled_on`, `media_album_id` 等） |
| `updated_at` | ✓ | DB 更新時刻 |
| `file_committed_at` | | Git コミット時刻。`null` なら下書き |
| `draft` | | `file_committed_at` が `null` かどうかの派生 |
| `url` | | Web UI へのリンク |

**格納ディレクトリ:**

API では公開しない。作成・更新時の格納先は徒然側の既定ロジック（アカウントの Home 等）に任せる。

**楽観的ロック（更新時）:**

徒然に `lock_version` は無い。第一案は `updated_at` または `If-Unmodified-Since` ヘッダによる競合検知。将来 `revision` 整数列を追加してもよい。

**添付・メディア:**

- Git 内アセット: Active Storage → `{slug}.assets/`（API では URL 参照のみ）
- 葛籠: 本文中の `album::` / `image::media:` マクロ + `properties.media_album_id`。バイナリは [葛籠 API](https://media.kbmemo.net) 経由

### 4.2 一覧レスポンス

```json
{
  "memos": [ { "...": "Memo 省略" } ],
  "pagination": {
    "total": 142,
    "limit": 50,
    "offset": 0,
    "has_more": true
  }
}
```

**クエリパラメータ（`GET /memos`）:**

|  param | 型 | 説明 |
|--------|-----|------|
| `q` | string | キーワード検索 |
| `tag` | string | タグフィルタ |
| `updated_since` | ISO8601 | 差分 sync 用 |
| `limit` | int | デフォルト 50、最大 200 |
| `offset` | int | ページネーション |
| `fields` | string | `id,title,updated_at` 等。RAG 用に軽量取得 |

### 4.3 作成リクエスト

```json
POST /memos
{
  "title": "Chat から保存したメモ",
  "body": "## 見出し\n\nLLM が生成した本文...",
  "body_format": "markdown",
  "tags": ["ai-generated"]
}
```

`body_format` 省略時は `asciidoc`（従来互換）。如意 Chat からは `markdown` を送る。

**レスポンス:** `201 Created` + Memo オブジェクト

### 4.4 更新リクエスト

```json
PATCH /memos/:uid
{
  "updated_at": "2026-06-20T14:30:00Z",
  "body": "推敲後の AsciiDoc 本文...",
  "title": "更新タイトル（任意）"
}
```

**競合時:** `409 Conflict` + 最新 Memo オブジェクト

```json
{
  "error": {
    "code": "stale_memo",
    "message": "メモは他で更新されています",
    "current": { "...": "最新 Memo" }
  }
}
```

---

## 5. 如意 Chat ツール映射

徒然 API を如意の Chat ツールとして公開する際の対応表。

| Chat ツール名 | API | 説明 |
|--------------|-----|------|
| `search_memos` | `GET /memos/search?q=` | キーワード検索 |
| `get_memo` | `GET /memos/:id` | 単体取得 |
| `create_memo` | `POST /memos` | 新規作成 |
| `update_memo` | `PATCH /memos/:uid` | 更新（`updated_at` 必須） |
| `append_memo` | `PATCH /memos/:id` + append 操作 | 末尾追記（PATCH の sugar 案） |

**LLM 向け説明文（例）:**

- `search_memos`: 徒然（tsuredure）に保存されたメモをキーワード検索する。旅行、技術メモなど過去の記録を探すときに使う。
- `create_memo`: 会話の内容を徒然に新規メモとして保存する。ユーザーが明示的に保存を求めたときのみ使う。
- `update_memo`: 既存メモを更新する。`updated_at` を必ず get_memo で取得してから使う。

---

## 6. RAG 取込仕様（如意側）

徒然 API が提供すべき最小要件と、如意側の処理。**2026-07 実装済み。**

### 6.1 取込フロー

```
徒然 API                         如意
─────────                        ────
GET /memos/export          →     MemoKnowledgeIngestJob
  ?updated_since=...             ├─ MemoTextChunker（~1500 文字）
  &page=&limit=                  ├─ EmbeddingClient.embed
                                 └─ PromptKnowledgeChunk upsert (source: memo)

Solid Queue recurring / bin/rails kbmemo:rag:ingest
```

Chat 利用時（ユーザー発話ごと）:

```
MemoRagQueryAnalyzer → MemoKnowledgeRetriever (pgvector + 徒然 list_memos RRF)
  → MemoKnowledgeChunkCompressor → ChatMemoRagInjector
```

### 6.2 チャンク設計（如意側・実装）

| 項目 | 内容 |
|------|------|
| モデル | `PromptKnowledgeChunk`（`source: memo`） |
| external_id | `kbmemo:{uid}:chunk:{index}` |
| metadata | title, tags, updated_at, chunk_index 等 |
| 削除 | **未同期** — `export/deletions` 徒然 501 のため全件 re-ingest または将来 webhook |

実装: `app/services/memo_text_chunker.rb`, `memo_knowledge_ingester.rb`, `memo_knowledge_retriever.rb`, `chat_memo_rag_injector.rb`

### 6.3 徒然 API への要求（残）

- [x] `GET /memos/export?updated_since=` — **提供済み**
- [ ] 削除メモ ID リスト（`export/deletions` — **501**）
- [ ] 1 メモあたりの最大サイズ上限の明示（任意）

---

## 7. 非機能要件

| 項目 | 要求 |
|------|------|
| **可用性** | 如意 Chat からの呼び出しは 5s 以内（検索）。RAG export は非同期可 |
| **レート制限** | レスポンスヘッダ `X-RateLimit-*`。429 時 Retry-After |
| **HTTPS** | 必須 |
| **CORS** | 如意 origin のみ（ブラウザ直呼びは想定しない） |
| **監査** | API 経由の作成・更新ログ（徒然側） |
| **バージョニング** | URL `/api/v1`。破壊的変更は v2 |

---

## 8. セキュリティ

| リスク | 対策 |
|--------|------|
| トークン漏洩 | スコープ最小化、ローテーション、credentials 保管 |
| 過剰なデータ取得 | export の rate limit、fields 指定 |
| 如意経由の不正更新 | revision チェック、write スコープ分離 |
| SSRF（如意 → 徒然） | 徒然 URL 固定。ユーザー入力 URL ではない |

---

## 9. 徒然現状調査（kbmemo_site）

リポジトリ: [Artif.org/kbmemo_site](https://gitea.artif.org/Artif.org/kbmemo_site)  
ローカル: `~/work/kbmemo/site`（モノレポ内の徒然アプリ。葛籠は `kbmemo-media/`）

### 9.1 スタック・概要

| 項目 | 内容 |
|------|------|
| フレームワーク | Rails 8.1 |
| 認証 | **Rodauth**（Devise ではない） |
| 認可 | Pundit |
| DB | PostgreSQL |
| 本文 | **AsciiDoc**（Asciidoctor でレンダリング） |
| Git 連携 | コミット済みメモは `.adoc` + YAML front-matter として Git 作業ツリーに書き出し |
| 本番 URL | https://kbmemo.net |

### 9.2 データモデル（確認済み）

| 項目 | 結果 |
|------|------|
| メモ ID | 数値 `id`（bigint PK）+ **ULID `uid`**（26 桁、unique、クライアント生成可）+ `slug` |
| 本文フォーマット | **AsciiDoc**（`memos.body`） |
| タグ | ✓ `tags` / `memo_tags` |
| フォルダ | ✓ `memo_directories`（階層、`full_path`） |
| その他分類 | notebooks（目次ツリー）、boards（カンバン）、memo_groups（共有） |
| 添付 | (1) Active Storage → Git `{slug}.assets/`、(2) 葛籠は本文マクロ `album::` / `image::media:` + `properties.media_album_id` |
| 削除 | **物理削除**（soft-delete / tombstone なし） |
| 楽観的ロック | **未実装**（`lock_version` なし）。`updated_at` + `file_committed_at` のみ |
| 下書き | `file_committed_at` が `null` の間は下書き状態 |

参照: `site/app/models/memo.rb`, `site/db/schema.rb`

### 9.3 既存 API（確認済み → 2026-07 実装済み）

| エンドポイント | 用途 | 認証 |
|---------------|------|------|
| `POST /api/clips` | Web クリッパー → メモ作成 | Bearer `clip_api_token` |
| `GET /api/v1/me` | アカウント情報 | 同上 |
| `GET/POST/PATCH/DELETE /api/v1/memos` | メモ CRUD + 検索 | 同上 |
| `GET /api/v1/memos/export` | RAG 用 export | 同上 |
| `GET /api/v1/memos/export/deletions` | 削除フィード | **501 未実装** |
| `GET /internal/tsuzura/*` | 葛籠（Web UI 内部） | セッション / 内部シークレット |

参照: `site/app/controllers/api/v1/`, `site/test/controllers/api/v1/`

### 9.4 検索（確認済み）

PostgreSQL の `LIKE` のみ（`Memo.search_text`）。Groonga / `to_tsvector` / ベクトル検索は**徒然側未使用**。

```ruby
# site/app/models/memo.rb
where("LOWER(title) LIKE LOWER(?) OR LOWER(body) LIKE LOWER(?)", pattern, pattern)
```

**如意側:**

- Chat ツール `search_memos` → `GET /api/v1/memos?q=`
- メモ RAG キーワード leg → 同上（pgvector と RRF で併用）
- 徒然メモ本文のベクトル検索は **如意 DB**（`PromptKnowledgeChunk` `source=memo`）で実施

**Groonga 導入時（徒然 site Workspace）:**

| 項目 | 内容 |
|------|------|
| HTTP API 変更 | **不要**（推奨）— `GET /memos?q=` の JSON 形状を維持し内部のみ Groonga 化 |
| 如意変更 | **不要** — `TsurezureClient#list_memos` はそのまま |
| 任意拡張 | `search_score` フィールド、 `?search=hybrid` 等（後方互換） |

如意 Chat のメモ検索・RAG キーワード leg の精度は Groonga 化で向上する。export API は RAG 取込の正本。

### 9.5 認証・トークン（確認済み）

| 項目 | 結果 |
|------|------|
| Web ログイン | Rodauth セッション |
| API トークン | `clip_api_token`（`kbmemo_<base64>`）、`tsuzura_api_token`（`tsuzura_<base64>`） |
| 保存 | SHA256 ダイジェスト + prefix + created_at |
| 発行 UI | プロフィール画面（`resource :profile`） |
| スコープ | トークン種別で暗黙分離。明示スコープは未実装 |
| マルチユーザー | ✓ `accounts` + `visibility` enum + `memo_groups` |

参照: `site/app/models/account.rb`, `site/app/controllers/api/base_controller.rb`

### 9.6 エクスポート（確認済み）

| 手段 | 説明 |
|------|------|
| Git 作業ツリー | `MemoRepository` がコミット時に `.adoc` を書き出し |
| Rake | `kbmemo:notebook:export`, `kbmemo:docs:sync` |
| HTTP API | **`GET /api/v1/memos/export`**（RAG 取込用。`updated_since` ページング） |
| 削除フィード | **`GET /api/v1/memos/export/deletions`** — **501 未実装** |

如意側: `TsurezureClient#export_memos` → `MemoKnowledgeIngestJob` / `bin/rails kbmemo:rag:ingest`

### 9.7 ギャップ分析（2026-07 更新）

| 如意の要求 | 徒然 | 如意 |
|-----------|------|------|
| `GET /api/v1/memos` 検索 | ✓ 実装・本番 | ✓ `TsurezureClient#list_memos` |
| `GET /api/v1/memos/:uid` | ✓ | ✓ `get_memo` |
| `POST /api/v1/memos` | ✓ | ✓ `create_memo` ツール |
| `PATCH` + 競合検知 | ✓ `stale_memo` | ✓ `update_memo` ツール |
| `export?updated_since=` | ✓ | ✓ `MemoKnowledgeIngestJob` / `kbmemo:rag:ingest` |
| 削除フィード | ✗ 501 | ✗ 未同期 |
| Bearer 認証 | ✓ `clip_api_token` | ✓ `ServiceConnection` `kbmemo` |
| DB 接続登録 | — | ✓ 設定 → 接続 |

### 9.8 徒然側への残確認事項

- [x] ~~如意用トークンを `clip_api_token` と分離するか~~ — **当面 clip 流用**
- [x] ~~API 作成メモの格納先ディレクトリ~~ — API 非公開。徒然側 Home 既定
- [ ] 下書きメモを export / 検索対象に含めるか（`include_drafts`）
- [ ] 削除メモの RAG 同期方式（`export/deletions` 実装）
- [ ] `visibility` が group のメモを API でどう扱うか
- [ ] Groonga 全文検索（**徒然内部**。API 形状維持なら如意変更不要）

---

## 10. 実装優先度（2026-07 更新）

| 優先 | 項目 | 状態 |
|------|------|------|
| P0 | 徒然 API v1 CRUD + 検索 | **完了** |
| P0 | 如意 `TsurezureClient` + Chat ツール | **完了** |
| P1 | SearXNG + URL 取得ツール | **完了** |
| P2 | メモ RAG 取込（`export` + pgvector） | **完了** |
| P2b | RAG 注入・コンテキスト要約・トークン管理 | **完了** |
| P3 | `export/deletions` + webhook | 徒然側未実装 |
| P3b | 徒然 Groonga 検索 | 徒然 site Workspace |
| P3c | API 書込 Markdown → AsciiDoc 変換 | 徒然 site Workspace |

---

## 11. 次のアクション

1. ~~徒然 API v1 実装~~ — 完了
2. ~~如意 Client + Chat ツール~~ — 完了
3. ~~本番接続確認・DB 登録~~ — 完了
4. ~~SearXNG + `fetch_url`~~ — 完了
5. ~~メモ RAG 取込 + Chat 注入~~ — 完了（`bin/rails kbmemo:rag:ingest`）
6. **Phase 2** — Chat への画像理解（`analyze_image`）
7. **徒然 site** — API 書込 Markdown → AsciiDoc、Groonga 検索、`export/deletions`
8. **Phase 6** — MCP サーバー（`ChatTools::*` 再公開）

---

## 12. 関連ドキュメント

- [kbmemo エコシステム — 現状・方針・ロードマップ](./ecosystem-roadmap.md)
- [OpenAPI 3.1 草案](./openapi/kbmemo-v1.yaml) — `kbmemo-v1.yaml`
