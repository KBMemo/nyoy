# kbmemo エコシステム — 現状・方針・ロードマップ

徒然（メモ）・葛籠（ファイル保管）・如意（AI 集約）の 3 アプリ構成と、如意を MCP サーバーとしても活用する方針を整理する。

---

## 1. 全体構成

| アプリ | URL（想定） | 読み / コード名 | 役割 |
|--------|-------------|----------------|------|
| **徒然** | kbmemo.net | tsuredure / `Tsurezure` | メモの正本。作成・編集・閲覧・検索 |
| **葛籠** | media.kbmemo.net（現行） | tsuzura | ファイル・画像の保管庫。バイナリの正本 |
| **如意** | nyoy.kbmemo.net | nyoy | AI 機能の集約、各機能の試験 UI、将来は MCP サーバー |

- 徒然リポジトリ: [gitea.artif.org/Artif.org/kbmemo_site](https://gitea.artif.org/Artif.org/kbmemo_site)（ローカル `~/work/kbmemo`）
- 葛籠は同一モノレポ内の `kbmemo-media/`。本番は現状 `media.kbmemo.net`

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
  end

  U --> T
  U --> Z
  U --> N
  N -->|API| T
  N -->|API| Z
  N --> L & V & E & SD & S
  T -.->|参照| Z
```

### 設計原則

1. **正本の分離** — メモは徒然、バイナリは葛籠。如意は AI 処理とオーケストレーションに専念する。
2. **ツール層の共有** — Chat ツールと MCP ツールは同じ実装を使い回す。
3. **接続の一元管理** — 外部 AI サービスは `ServiceConnection` + `NyoyConnectionStore` 経由。
4. **試験 UI を如意に置く** — 画像生成・Chat など各 AI 機能は如意で先に試し、成熟したら他アプリや MCP から呼ぶ。

---

## 2. 如意（Nyoy）の現状

### 2.1 概要

日本語テキストから Stable Diffusion 画像を生成する Rails 8.1 アプリ。  
llama.cpp で `style_id` ベースの最小 JSON 計画を作成し、`SdPromptStyleResolver` で実行設定を解決して sd.cpp で txt2img を実行する。

**スタック:** Rails 8.1, PostgreSQL + pgvector, Solid Queue/Cache/Cable, Hotwire, Slim, Vite, `ruby_llm` gem。

### 2.2 機能一覧

| 機能 | ルート / モデル | 状態 |
|------|----------------|------|
| メモ挿絵 | `memo_illustrations` | 運用中 |
| 画像生成（draft → 選択 → refine） | `image_generations` | 運用中 |
| img2img | `img2img_generations` | 運用中 |
| 部分修正（inpaint） | `memo_illustrations#inpaint` | 運用中 |
| 画像理解 | `image_understandings` + `VisionChatService` | 運用中（独立 UI） |
| プロンプトナレッジ CRUD | `prompt_knowledge_chunks` | 運用中 |
| Chat | `chats` / `messages` | 運用中（**徒然メモツール配線済み**） |
| 接続管理 | `service_connections` | 運用中（**設定 → 接続**、`/service_connections`） |
| MCP サーバー | — | **未実装** |
| 徒然連携 | `TsurezureClient` + `ChatTools::*` | **運用中**（本番 API 接続確認済み） |
| 葛籠連携 | — | **未実装** |

### 2.3 接続管理（ServiceConnection）

組み込みバックエンド **7 種** を DB で管理。環境変数へのフォールバックあり。

| key | 用途 |
|-----|------|
| `llama_cpp` | テキスト LLM（style 計画、Chat 等） |
| `gpt_oss` | テキスト LLM（GPT-OSS 系、Chat） |
| `vision_llama` | 画像理解 |
| `embeddings` | bge-m3 埋め込み |
| `sd_cpp` | sd.cpp 画像生成 |
| `sd_switchd` | SD モデル切り替え |
| `kbmemo` | **徒然 API**（Chat メモツール、`clip_api_token`） |

Chat バックエンド保存時に `ChatModelCatalog.seed!` で `Model` レコードを同期する。

### 2.4 Chat

- `ruby_llm` の `acts_as_chat` / `acts_as_message` / `acts_as_model`
- `ChatResponseJob` が `chat.ask` を実行し、Turbo Stream でストリーミング
- `ChatModelCatalog.context_for` で llama.cpp の OpenAI 互換 API に接続
- **`ChatTools::Registry`** — `kbmemo` 接続が有効なとき徒然ツールを自動配線

| ツール | 用途 |
|--------|------|
| `search_memos` | 徒然メモ検索 |
| `get_memo` | メモ取得 |
| `create_memo` | メモ作成（AsciiDoc） |
| `update_memo` | 更新・末尾追記 |

実装: `app/services/chat_tools/`, `app/services/tsurezure_client.rb`  
接続設定: **設定 → 接続** の `kbmemo`、または `KBMEMO_URL` / `KBMEMO_API_TOKEN`

### 2.5 RAG

- `PromptKnowledgeChunk` — pgvector + `neighbor` gem
- kind: style / model / lora / negative / composition / camera / lighting / inpaint
- `PromptKnowledgeRetriever` が cosine 近傍検索
- **画風プロンプト専用**。メモ RAG は未対応

### 2.6 外部連携の現状

| 連携先 | 状態 |
|--------|------|
| llama.cpp / sd.cpp / embeddings | HTTP（ServiceConnection 経由） |
| **徒然（kbmemo.net）** | **`/api/v1` 接続済み**（`TsurezureClient`、本番確認済み） |
| SearXNG（bowmore.artif.org:8080） | **未接続** |
| 葛籠（media.kbmemo.net） | **未接続**（徒然 UI から内部 API 経由で利用） |
| MCP | **未実装** |

---

## 3. 今後の方針

### 3.1 如意の位置づけ

- **AI ハブ** — ローカル LLM / SD / embeddings / 検索を束ね、徒然・葛籠・MCP クライアントから利用可能にする
- **試験場** — 新 AI 機能は如意 UI で先に検証し、安定後にツール化・MCP 化
- **RAG 管理** — プロンプトナレッジに加え、徒然メモ由来のナレッジも取り込み・検索可能にする

### 3.2 Chat に追加したい機能

| 機能 | 概要 | 依存 |
|------|------|------|
| Web 検索 | SearXNG（bowmore.artif.org:8080）経由 | ServiceConnection 追加 |
| URL データ取得 | 指定 URL の HTML / テキスト抽出 | SSRF 対策必須 |
| 画像理解 | 添付画像または葛籠 URL から分析 | `VisionChatService` 統合 |
| 徒然メモ書き出し | Chat 結果を徒然に保存 | ✓ `create_memo` |
| 徒然メモ書き支援 | 徒然の下書きを読み、推敲・追記 | ✓ `get_memo` / `update_memo` |
| メモ RAG 生成 | 徒然メモから embedding チャンクを生成 | 徒然 `export` API + RAG 一般化 |

### 3.3 ツール層アーキテクチャ（目標）

```
Chat UI ──┐
          ├── ChatTools::* ── ServiceConnection / 徒然 API / 葛籠 API
MCP Server ┘
```

Chat と MCP で同じツール実装を共有する。徒然メモツールは `ChatTools::*` に実装済み。MCP は JSON-RPC ハンドラから同一クラスを呼ぶ予定。

### 3.4 RAG 拡張方針

現行 `PromptKnowledgeChunk` に `source` 列（`prompt` / `memo` / `url` 等）を追加し、スコープで分離する案を第一候補とする。

- プロンプト用: 既存 kind（style, lora, inpaint 等）
- メモ用: 徒然メモ ID・タイトル・本文チャンク
- 管理 UI: タブまたはフィルタで source 別表示

### 3.5 MCP サーバー化

如意が提供する MCP ツール候補（Chat ツールと共用）:

| ツール | 由来 |
|--------|------|
| `web_search` | SearXNG |
| `fetch_url` | 新規 |
| `analyze_image` | `VisionChatService` |
| `search_knowledge` | RAG |
| `search_memos` / `create_memo` / `update_memo` | 徒然 API |
| `generate_image` 等 | 既存 SD パイプライン（将来） |

実装: HTTP/SSE ベース（`nyoy.kbmemo.net/mcp`）。認証は API トークン。

---

## 4. 段階的ロードマップ

| Phase | 内容 | 状態 |
|-------|------|------|
| **0** | 徒然 API 要件整理 | **完了** |
| **0b** | OpenAPI 草案 | **完了** [`openapi/kbmemo-v1.yaml`](./openapi/kbmemo-v1.yaml) |
| **4a** | 徒然 `/api/v1` 実装 | **完了**（kbmemo_site `32a51c6`、本番デプロイ済み） |
| **4b** | 如意 `TsurezureClient` + Chat メモツール | **完了**（本番接続確認済み） |
| **1** | Web 検索 + URL 取得 | **次** |
| **2** | Chat への画像理解統合 | 未着手 |
| **3** | RAG 一般化 + メモ取込 | 未着手 |
| **5** | 葛籠連携 | 未着手 |
| **6** | MCP サーバー公開 | 未着手 |

```mermaid
gantt
  title 如意 開発フェーズ
  dateFormat YYYY-MM
  section 完了
  徒然 API 要件・OpenAPI     :done, p0, 2026-07, 1M
  徒然 API v1 実装            :done, p4a, 2026-07, 1M
  如意 Client + Chat ツール   :done, p4b, 2026-07, 1M
  section 次
  Web 検索 + URL 取得         :active, p1, 2026-07, 1M
  section 将来
  画像理解を Chat に統合       :p2, after p1, 1M
  RAG 一般化 + メモ取込        :p3, after p2, 1M
  葛籠連携                    :p5, after p3, 1M
  MCP サーバー公開            :p6, after p5, 1M
```

---

## 5. 未決事項

| # | 論点 | 影響 | 備考 |
|---|------|------|------|
| 1 | ~~徒然 API 認証~~ | — | **決定:** 当面 `clip_api_token` 流用 |
| 2 | 葛籠への画像移行タイミング | 生成物の保管 | |
| 3 | メモ RAG の更新方式 | 鮮度・運用コスト | export + 定期 sync が現実的 |
| 4 | Chat モデル切替 | UX・実装 | |
| 5 | MCP 利用者 | 認可設計 | 個人利用のため当面は API キー 1 本 |
| 6 | 徒然 `export/deletions` | RAG 削除同期 | 徒然側 **未実装**（501） |

---

## 6. 次の作業（2026-07 時点）

個人利用前提。優先度順。

### すぐ試せる（検証）

Chat で徒然連携の動作確認:

- 「如意ノートの内容を要約して」（`search_memos` → `get_memo`）
- 「この回答を徒然にメモして」（`create_memo`）
- 「〇〇メモに追記して」（`get_memo` → `update_memo`）

### Phase 1 — Chat ツール拡張（推奨・次）

| タスク | 内容 |
|--------|------|
| SearXNG 接続 | `ServiceConnection` に `searxng` 追加、`ChatTools::WebSearch` |
| URL 取得 | `ChatTools::FetchUrl`（SSRF 対策付き） |
| 接続管理 UI | 設定 → 接続 で編集 |

既存 `ChatTools::Registry` パターンに乗せる。

### Phase 2 — 画像理解を Chat に

- メッセージへの画像添付
- `VisionChatService` を Chat ツール `analyze_image` 化

### Phase 3 — メモ RAG

- `PromptKnowledgeChunk` に `source` 列追加
- 徒然 `GET /api/v1/memos/export` から取込ジョブ
- Chat ツール `search_knowledge`（ベクトル検索）

### 将来

- 葛籠連携（生成画像の保管・参照）
- MCP サーバー（`ChatTools::*` の再公開）

---

## 7. 関連ドキュメント

- [徒然（tsuredure）API 要件](./tsuredure-api-requirements.md) — 如意から見た徒然 API の要求仕様・現状調査（Phase 0 完了）
- [徒然 API OpenAPI 草案](./openapi/kbmemo-v1.yaml) — `kbmemo-v1.yaml`
- [徒然リポジトリ](https://gitea.artif.org/Artif.org/kbmemo_site) — kbmemo_site
- [プロンプト設計 再構築案](./prompt-architecture-redesign.md) — SD プロンプトアーキテクチャ
