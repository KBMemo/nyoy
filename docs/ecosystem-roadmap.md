# kbmemo エコシステム — 現状・方針・ロードマップ

徒然（メモ）・葛籠（ファイル保管）・如意（AI 集約）の 3 アプリ構成と、如意を MCP サーバーとしても活用する方針を整理する。

---

## 1. 全体構成

| アプリ | URL（想定） | 読み / コード名 | 役割 |
|--------|-------------|----------------|------|
| **徒然** | kbmemo.net | tsuredure / `Tsurezure` | メモの正本。作成・編集・閲覧・検索 |
| **葛籠** | media.kbmemo.net（現行） | tsuzura | ファイル・画像の保管庫。バイナリの正本 |
| **如意** | nyoy.kbmemo.net | nyoy | AI 機能の集約、各機能の試験 UI、将来は MCP サーバー |

- 徒然リポジトリ: [gitea.artif.org/Artif.org/kbmemo_site](https://gitea.artif.org/Artif.org/kbmemo_site)（ローカル `~/work/kbmemo/site`）
- 葛籠は同一モノレポ内の `kbmemo-media/`。本番は現状 `media.kbmemo.net`
- **別 Workspace 開発:** 徒然は `site`、如意は `nyoy`。連携は **HTTP API 契約**（`docs/openapi/kbmemo-v1.yaml`）が正本。マルチルート Workspace に両方を追加すると Agent が横断参照しやすい

ローマ字表記の詳細は [徒然 API 要件 §0](./tsuredure-api-requirements.md#0-名称ローマ字表記) を参照。

```mermaid
flowchart LR
  subgraph user [ユーザー]
    U[ブラウザ / Cursor 等]
  end

  subgraph apps [kbmemo エコシステム]
    T[徒然<br/>メモ本体]
    Z[葛籠<br/>ファイル・画像保管]
    N[如意<br/>AI 集約・試験 UI]
  end

  subgraph ai [ローカル AI / 外部]
    L[llama.cpp]
    V[vision llama]
    E[embeddings]
    SD[sd.cpp]
    S[SearXNG]
    R[readability-js-server]
  end

  U --> T
  U --> Z
  U --> N
  N -->|API| T
  N -->|API| Z
  N --> L & V & E & SD & S & R
  T -.->|参照| Z
```

### 設計原則

1. **正本の分離** — メモは徒然、バイナリは葛籠。如意は AI 処理とオーケストレーションに専念する。
2. **ツール層の共有** — Chat ツールと MCP ツールは同じ実装を使い回す。
3. **接続の一元管理** — 外部 AI サービスは `ServiceConnection` + `NyoyConnectionStore` 経由。
4. **試験 UI を如意に置く** — 画像生成・Chat など各 AI 機能は如意で先に試し、成熟したら他アプリや MCP から呼ぶ。
5. **API 契約で疎結合** — 徒然の検索エンジン（LIKE → Groonga 等）を差し替えても、HTTP 形状を維持すれば如意側は変更不要。

---

## 2. 如意（Nyoy）の現状

### 2.1 概要

日本語テキストから Stable Diffusion 画像を生成する Rails 8.1 アプリ。  
llama.cpp で `style_id` ベースの最小 JSON 計画を作成し、`SdPromptStyleResolver` で実行設定を解決して sd.cpp で txt2img を実行する。

**スタック:** Rails 8.1, PostgreSQL + pgvector, Neighbor, Solid Queue/Cache/Cable, Hotwire, Slim, Vite, `ruby_llm` gem。

### 2.2 機能一覧

| 機能 | ルート / モデル | 状態 |
|------|----------------|------|
| メモ挿絵 | `memo_illustrations` | 運用中 |
| 画像生成（draft → 選択 → refine） | `image_generations` | 運用中 |
| img2img | `img2img_generations` | 運用中 |
| 部分修正（inpaint） | `memo_illustrations#inpaint` | 運用中 |
| 画像理解 | `image_understandings` + `VisionChatService` | 運用中（独立 UI） |
| プロンプトナレッジ CRUD | `prompt_knowledge_chunks` | 運用中 |
| Chat | `chats` / `messages` | **運用中** |
| 接続管理 | `service_connections` | 運用中 |
| 徒然連携 | `TsurezureClient` + `ChatTools::*` | **運用中**（本番確認済み） |
| Web 検索 / URL 取得 | `web_search` / `fetch_url` | **実装済み** |
| メモ RAG | export 取込 + pgvector + Chat 注入 | **実装済み** |
| MCP サーバー | — | **未実装** |
| 葛籠連携 | — | **未実装** |

### 2.3 接続管理（ServiceConnection）

組み込みバックエンド **9 種** を DB で管理。環境変数へのフォールバックあり。

| key | 用途 |
|-----|------|
| `llama_cpp` | テキスト LLM（style 計画等） |
| `gpt_oss` | テキスト LLM（GPT-OSS 系、Chat） |
| `vision_llama` | 画像理解 |
| `embeddings` | bge-m3 埋め込み |
| `sd_cpp` | sd.cpp 画像生成 |
| `sd_switchd` | SD モデル切り替え |
| `kbmemo` | **徒然 API**（メモツール・RAG 取込） |
| `searxng` | **SearXNG**（`web_search`） |
| `readability` | **readability-js-server**（`fetch_url` 本文抽出） |

Chat バックエンド保存時に `ChatModelCatalog.seed!` で `Model` レコードを同期する。

### 2.4 Chat

- `ruby_llm` の `acts_as_chat` / `acts_as_message` / `acts_as_model`
- `ChatResponseJob` が `chat.ask` を実行し、Turbo Stream で Markdown 再レンダリング
- `ChatModelCatalog.context_for` で llama.cpp OpenAI 互換 API に接続
- **`ChatTools::Registry`** — 接続状態に応じてツールを動的配線
- **コンテキスト制御** — `ChatContextBuilder`（ターン制限 + 要約キャッシュ）、`ChatContextBudget`（トークン予算）、UI で推定 tokens・メモ RAG チャンク数

| ツール | 用途 | 条件 |
|--------|------|------|
| `search_memos` | 徒然キーワード検索 | `kbmemo` |
| `get_memo` / `create_memo` / `update_memo` | メモ CRUD | `kbmemo` |
| `web_search` | Web 検索 | `searxng` |
| `fetch_url` | URL 本文取得 | 常時（readability 優先、未設定時は直接取得） |

**メモ RAG（自動）:** ユーザー発話ごとに pgvector + 徒然キーワード検索（RRF）→ 関連チャンクを system instructions に注入。`get_memo` は全文が必要なときの補助。

実装: `app/services/chat_tools/`, `app/services/tsurezure_client.rb`, `app/services/memo_knowledge_*`, `app/services/chat_memo_rag_injector.rb`

### 2.5 RAG

| source | 用途 | 検索 |
|--------|------|------|
| `prompt`（既定） | 画風・LoRA・inpaint 等 | `PromptKnowledgeRetriever` |
| `memo` | 徒然メモチャンク | `MemoKnowledgeRetriever` + Chat 自動注入 |

- `PromptKnowledgeChunk` — pgvector + `neighbor`、HNSW index
- 取込: `GET /api/v1/memos/export` → `MemoKnowledgeIngestJob` / `bin/rails kbmemo:rag:ingest`
- チャンク ID: `kbmemo:{uid}:chunk:{n}`（`external_id` 列）

### 2.6 外部連携の現状

| 連携先 | 状態 |
|--------|------|
| llama.cpp / sd.cpp / embeddings | HTTP（ServiceConnection 経由） |
| **徒然（kbmemo.net）** | **`/api/v1` 接続済み** |
| **SearXNG** | **接続済み**（`web_search`） |
| **readability-js-server** | **接続済み**（`fetch_url`） |
| 葛籠（media.kbmemo.net） | **未接続** |
| MCP | **未実装** |

---

## 3. 今後の方針

### 3.1 如意の位置づけ

- **AI ハブ** — ローカル LLM / SD / embeddings / 検索を束ね、徒然・葛籠・MCP クライアントから利用可能にする
- **試験場** — 新 AI 機能は如意 UI で先に検証し、安定後にツール化・MCP 化
- **RAG 管理** — プロンプトナレッジ + 徒然メモチャンク。将来 URL / 葛籠文書も `source` で拡張

### 3.2 Chat — 残タスク

| 機能 | 概要 | 状態 |
|------|------|------|
| Web 検索 | SearXNG | **完了** |
| URL 取得 | SSRF + readability | **完了** |
| メモ RAG | export 取込 + 注入 + 要約 | **完了**（Groonga は徒然側） |
| 画像理解 | Chat 添付 + `analyze_image` ツール | **未着手** |
| MCP 公開 | `ChatTools::*` の再公開 | **未着手** |

### 3.3 徒然側（site Workspace）との連携

| 変更 | 如意 API 変更 | 備考 |
|------|--------------|------|
| Groonga 検索（`GET /memos?q=` 内部差し替え） | **不要** | 検索精度のみ向上 |
| `export/deletions` 実装 | 取込ジョブが削除同期可能に | 徒然 **501** |
| webhook 通知 | 将来リアルタイム re-embed | 未設計 |

### 3.4 ツール層アーキテクチャ（目標）

```
Chat UI ──┐
          ├── ChatTools::* ── ServiceConnection / 徒然 API / 葛籠 API
MCP Server ┘
```

### 3.5 MCP サーバー化（将来）

| ツール | 由来 |
|--------|------|
| `web_search` / `fetch_url` | 実装済み |
| `search_memos` / `create_memo` / … | 徒然 API |
| `analyze_image` | `VisionChatService`（未統合） |
| `generate_image` 等 | SD パイプライン（将来） |

---

## 4. 段階的ロードマップ

| Phase | 内容 | 状態 |
|-------|------|------|
| **0** | 徒然 API 要件整理 | **完了** |
| **0b** | OpenAPI 草案 | **完了** |
| **4a** | 徒然 `/api/v1` 実装 | **完了** |
| **4b** | 如意 Client + Chat メモツール | **完了** |
| **1** | Web 検索 + URL 取得 | **完了** |
| **3a** | メモ RAG 取込 + Chat 注入 | **完了** |
| **3b** | 動的 top_k・キーワード併用・チャンク圧縮 | **完了** |
| **3c** | 会話要約・トークン警告 UI | **完了** |
| **3d** | 要約キャッシュ・トークン予算・RAG ステータス | **完了** |
| **2** | Chat への画像理解統合 | **次** |
| **5** | 葛籠連携 | 未着手 |
| **6** | MCP サーバー公開 | 未着手 |

```mermaid
gantt
  title 如意 開発フェーズ
  dateFormat YYYY-MM
  section 完了
  徒然 API + Client           :done, p4, 2026-07, 1M
  Web 検索 + URL 取得          :done, p1, 2026-07, 1M
  メモ RAG + コンテキスト管理   :done, p3, 2026-07, 1M
  section 次
  画像理解を Chat に統合        :active, p2, 2026-07, 1M
  section 将来
  葛籠連携                     :p5, after p2, 1M
  MCP サーバー公開             :p6, after p5, 1M
```

---

## 5. 未決事項

| # | 論点 | 影響 | 備考 |
|---|------|------|------|
| 1 | ~~徒然 API 認証~~ | — | **決定:** 当面 `clip_api_token` 流用 |
| 2 | 葛籠への画像移行タイミング | 生成物の保管 | |
| 3 | メモ RAG 削除同期 | 鮮度 | `export/deletions` 徒然側未実装 |
| 4 | 徒然 Groonga 検索 | キーワード RAG 精度 | **徒然内部変更で足りる**（API 形状維持） |
| 5 | MCP 利用者 | 認可設計 | 個人利用のため当面は API キー 1 本 |
| 6 | マルチ Workspace 開発 | site + nyoy | OpenAPI 契約 + マルチルート推奨 |

---

## 6. 次の作業

### 推奨（Phase 2）

- Chat メッセージへの画像添付
- `VisionChatService` を `analyze_image` ツール化
- 必要なら葛籠 URL 参照の設計

### 運用・メンテ

```bash
# メモ RAG 初回 / 差分取込
bin/rails kbmemo:rag:ingest
UPDATED_SINCE=2026-07-01T00:00:00Z bin/rails kbmemo:rag:ingest
```

- Chat 画面で推定 tokens・メモ RAG チャンク数を確認
- 徒然 `export/deletions` 実装後、取込ジョブに削除同期を追加

### 徒然（site）側

- Groonga 全文検索（`GET /memos?q=` の内部実装差し替え）
- `export/deletions` エンドポイント

---

## 7. 関連ドキュメント

- [徒然（tsuredure）API 要件](./tsuredure-api-requirements.md)
- [徒然 API OpenAPI 草案](./openapi/kbmemo-v1.yaml)
- [徒然リポジトリ](https://gitea.artif.org/Artif.org/kbmemo_site)
- [プロンプト設計 再構築案](./prompt-architecture-redesign.md)
- [README](../README.md)
