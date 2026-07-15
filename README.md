# Nyoy

日本語テキストから Stable Diffusion 画像を生成する Rails アプリです。  
llama.cpp で `style_id` ベースの最小 JSON 計画を作成し、`SdPromptStyleResolver` で実行設定を解決して sd.cpp で txt2img を実行します。

加えて **Chat**（GPT-OSS + 徒然連携）、**Web 検索 / URL 取得**、**メモ RAG** を備え、ローカル AI サービスを `ServiceConnection` で束ねます。

## 機能

### 画像生成

- **メモ挿絵** — 短文メモから style 計画（`style_id` + `subject_prompt`）を作成し、画像を生成
- **画像生成** — 日本語プロンプトを style 計画に変換し、案出し → 選択 → 仕上げ（Hires）のパイプラインで生成
- **プロンプトスタイル** — 見た目（prefix/suffix/固定ネガ/LoRA/モデル）を `prompt_styles` で管理（seed）
- **描画プリセット** — draft / refine / single のパイプライン設定を `render_presets` で管理（seed）
- **プロンプトナレッジ** — 画風・LoRA・ネガティブ方針を chunk 化し、pgvector + neighbor で RAG 検索
- **リアルタイム進捗** — Turbo Streams でステータスパネルを自動更新
- **フェーズ別タイム計測** — プロンプト生成時間と画像生成時間を分けて表示

### Chat（徒然・Web・RAG）

- **徒然メモツール** — `search_memos` / `get_memo` / `create_memo` / `update_memo`（書込は Markdown → 徒然で AsciiDoc 変換、読取は AsciiDoc）
- **Web 検索** — searfront 経由の `web_search`
- **URL 取得** — `fetch_url`（SSRF 対策 + readability-js-server で本文抽出）
- **メモ RAG** — 徒然 `export` 取込 → pgvector チャンク → 質問に関連する抜粋を Chat に自動注入
- **コンテキスト管理** — 直近 N ターン制限、古い会話の要約（DB キャッシュ）、推定トークン表示、メモ RAG チャンク数
- **画像理解** — Chat への画像添付 + `analyze_image` ツール（`vision_llama` 接続）
- **葛籠連携** — Chat 添付の葛籠アーカイブ + `list_albums` / `get_media` ツール（`tsuzura` 接続）

### その他

- **画像理解（独立 UI）** — `/image_understandings`（`VisionChatService` 単体ページ）
- **接続管理** — 設定 → 接続（`/service_connections`）で LLM / SD / 徒然 / searfront 等を編集

## 前提条件

- Ruby 4.0.3（`.ruby-version` 参照）
- Node.js（Vite 用）
- PostgreSQL 16 + pgvector（`bowmore.artif.org:5432`）
- 外部サービス（任意）
  - **llama.cpp** — style 計画・Chat（`LLAMA_CPP_URL` / `GPT_OSS_*`）
  - **sd.cpp server** — 画像生成（`SDCPP_SERVER_URL`）
  - **sdcpp-switchd** — SD モデル切り替え（`SDCPP_SWITCHD_URL` / `SDCPP_SWITCHD_TOKEN`）
  - **embeddings API** — bge-m3（`EMBEDDINGS_URL`）
  - **徒然 API** — メモ CRUD・export（`KBMEMO_*`）
  - **searfront** — Web 検索（`SEARFRONT_*`（互換: `SEARXNG_*`））
  - **readability-js-server** — ページ本文抽出（`READABILITY_URL`）

## セットアップ

PostgreSQL は `bowmore.artif.org:5432` を使用します。接続ユーザー名・パスワードは credentials に登録してください。

```bash
bin/rails credentials:edit
```

```yaml
database:
  username: your_username
  password: your_password
```

その後:

```bash
bin/setup
```

初回は DB 作成・seed・依存関係インストールのあと `bin/dev` が起動します。  
サーバーだけ起動したい場合:

```bash
bundle install
npm install
bin/rails db:prepare
bin/rails db:seed
bin/dev
```

`http://localhost:3009` を開きます（`bin/dev` の既定。`env.development` の `PORT` で変更可）。

## 環境変数

`bin/dev` は `env.development` を読み込みます。`.env.example` をコピーして編集してください。

PostgreSQL のホスト・認証情報は `config/database.yml` と Rails credentials（`database.username` / `database.password`）で管理します。CI のみ `DB_*` 環境変数で上書きします。

接続は **設定 → 接続**（`/service_connections`）でも管理できます。`bin/rails db:seed` で DB 登録されます。

### LLM / SD / 埋め込み

| 変数 | 説明 | デフォルト |
|------|------|-----------|
| `LLAMA_CPP_URL` | llama.cpp の URL | `http://balvenie:10010` |
| `LLAMA_MODEL` | style 計画等のモデル名 | `gemma-4-12b-it-vision-mtp` |
| `GPT_OSS_MODEL` | Chat 用 GPT-OSS モデル名 | `gpt-oss` |
| `GPT_OSS_LLAMA_CPP_URL` | GPT-OSS 専用 URL（省略時は `LLAMA_CPP_URL`） | （未設定） |
| `LLAMA_JSON_SCHEMA` | llama.cpp へ JSON Schema 制約を送る | `true` |
| `LLAMA_READ_TIMEOUT` | llama.cpp 読み取りタイムアウト（秒） | `300` |
| `LLAMA_SLOT_COUNT` | `/props` の `total_slots` 取得失敗時のフォールバック（0 で無効） | `0` |
| `LLAMA_CACHE_PROMPT` | `cache_prompt: true` を送り KV cache を再利用 | `true` |
| `VISION_LLAMA_CPP_URL` | 画像理解用 llama.cpp | `http://balvenie:10021` |
| `VISION_LLAMA_MODEL` | 画像理解モデル | `qwen2.5-vl-3b` |
| `EMBEDDINGS_URL` | bge-m3 embeddings API | `http://balvenie:10020` |
| `EMBEDDINGS_MODEL` | 埋め込みモデル名 | `groonga/bge-m3-Q4_K_M-GGUF` |
| `EMBEDDINGS_DIMENSIONS` | ベクトル次元数 | `1024` |
| `EMBEDDING_MAX_CHARS` | embedding API へ送る最大文字数 | `1000` |
| `SDCPP_SERVER_URL` | sd.cpp サーバーの URL | `http://balvenie:11234` |
| `SDCPP_SWITCHD_URL` | モデル切り替え API | `http://balvenie:11334` |
| `SDCPP_SWITCHD_TOKEN` | switchd 認証トークン | （未設定） |
| `SDCPP_DEFAULT_MODELS` | UI に表示する SD モデル | カンマ区切り一覧 |

### 徒然・Chat ツール

| 変数 | 説明 | デフォルト |
|------|------|-----------|
| `KBMEMO_URL` | 徒然 API ベース URL | `https://kbmemo.net` |
| `KBMEMO_API_TOKEN` | clip API トークン（`kbmemo_...`） | （未設定） |
| `TSUZURA_URL` | 葛籠 API ベース URL | `http://localhost:3008` |
| `TSUZURA_API_TOKEN` | 葛籠 API トークン（`tsuzura_...`） | （未設定） |
| `SEARFRONT_URL` | searfront ベース URL（接続キー `searfront`） | `http://bowmore:13000` |
| `SEARFRONT_TOKEN` | searfront Bearer トークン（必須） | （未設定） |
| `SEARXNG_URL` / `SEARXNG_API_TOKEN` | 上記の互換エイリアス | （未設定） |
| `READABILITY_URL` | readability-js-server | `http://bowmore:8030` |

Web 検索は searfront（`/v1/search`）経由です。接続画面で URL・トークン・件数上限などを変更できます。エンジン選択・CAPTCHA フォールバックは searfront 側が担います。PDF は取得対象外です。

### Chat コンテキスト・メモ RAG

| 変数 | 説明 | デフォルト |
|------|------|-----------|
| `CHAT_CONTEXT_TURNS` | LLM に送る直近ユーザー発話ターン数（0=無制限） | `10` |
| `CHAT_SUMMARY_ENABLED` | 古いターンを要約して注入 | `true` |
| `CHAT_SUMMARY_MAX_CHARS` | 要約テキスト上限（文字） | `1200` |
| `CHAT_SUMMARY_MAX_TOKENS` | 要約トークン予算 | `300` |
| `CHAT_SUMMARY_LLM` | 要約に llama.cpp を使う | `false` |
| `CHAT_CONTEXT_TOKEN_WARN_RATIO` | 推定 tokens が context の何割で警告するか | `0.75` |
| `CHAT_RESPONSE_TOKEN_RESERVE` | 回答用に空ける tokens | `2000` |
| `STYLE_PLAN_CONNECTION_KEY` | プロンプト変換の既定接続（UI 未設定時のフォールバック） | `llama_cpp` |
| `DEFAULT_CHAT_CONNECTION_KEY` | チャットの既定接続（UI 未設定時のフォールバック） | `llama_cpp` |
| `MEMO_RAG_ENABLED` | メモ RAG（有効化） | `true` |
| `MEMO_RAG_MODE` | `tool`=recall_memos ツールで必要時取得 / `inject`=毎ターン自動注入 | `tool` |
| `MEMO_RAG_TOP_K_SIMPLE` / `_NORMAL` / `_COMPLEX` | 質問複雑度別 top_k | `3` / `5` / `10` |
| `MEMO_RAG_MAX_CHARS` | RAG 注入全体の文字上限 | `12000` |
| `MEMO_RAG_MAX_TOKENS` | RAG トークン予算 | `1500` |
| `MEMO_CHUNK_MAX_CHARS` | 取込時のチャンク最大文字数 | `1500` |
| `MEMO_INGEST_PAGE_LIMIT` | export 1 ページ件数 | `100` |
| `MEMO_RAG_LLM_COMPRESS` | チャンクを llama で圧縮 | `false` |

メモ RAG の初回取込:

```bash
bin/rails kbmemo:rag:ingest
# 差分のみ: UPDATED_SINCE=2026-07-01T00:00:00Z bin/rails kbmemo:rag:ingest
```

Solid Queue recurring で `MemoKnowledgeIngestJob` が定期実行されます（`config/recurring.yml`）。

## 使い方

### チャット（徒然・Web・RAG）

1. `/chats` で新規チャットを作成
2. 接続が有効なツールが自動配線されます
   - `kbmemo` — 徒然メモ CRUD + メモ RAG 注入
   - `searfront` — Web 検索
   - `readability` — URL 本文抽出（`fetch_url` は常に利用可、readability 未設定時は直接取得）
3. 例:
   - 「過去の旅行メモを探して」（RAG + `search_memos`）
   - 「この URL を読んで要約して」（`fetch_url`）
   - 「最新の Ruby ニュースを調べて」（`web_search` → `fetch_url`）
   - 「この回答を徒然に保存して」（`create_memo`）

詳細: [`docs/ecosystem-roadmap.md`](docs/ecosystem-roadmap.md)

### メモ挿絵

1. トップページ（`/memo_illustrations`）で文章と任意のスタイル（`style_id`）を入力
2. RAG でナレッジを検索し、llama.cpp が最小 JSON（`style_id` + `subject_prompt` + `negative_extra` + `aspect_ratio`）を出力
3. `SdPromptStyleResolver` が prefix/suffix/LoRA/解像度を解決し、single 用 render preset で生成
4. 結果ページで subject プロンプト、実行時ネガティブ、参照ナレッジ、画像を確認

### 画像生成

1. `/image_generations/new` で日本語プロンプトとスタイル（任意）を入力
2. 案出し / 本番の render preset を選び、ラフ枚数などを調整して生成
3. ラフ案を選んで仕上げ（img2img + 任意 Hires）

日本語プロンプトのみの場合、RAG → llama.cpp → `StylePlanGenerator` → `SdPromptStyleResolver` → sd.cpp の流れです。

### プロンプト設計の役割分担

| レイヤ | 役割 | いつ使う |
|--------|------|----------|
| **スタイル** (`prompt_styles`) | 見た目: prefix/suffix、固定 negative、LoRA、モデル、解像度プリセット | `SdPromptStyleResolver` が LLM 出力を実行設定に変換 |
| **描画** (`render_presets`) | パイプライン: draft batch/steps、refine denoise/hires | 生成フォーム・ジョブが適用 |
| **ナレッジ** | どの `style_id` を選ぶか / subject に何を書くかの**指針** | RAG コンテキスト（`kind=style` は `style_ref` 必須） |
| **作法** | flow ごとの固定 system prompt（コード） | LLM に最小 JSON 契約を守らせる |
| **記録** | `resolved_*` スナップショット | 再現用に生成レコードへ保存 |

固定ネガティブは style に集約され、`negative_extra` は situational な追加 tag のみです。

### 鳥獣戯画（seed 例）

- **スタイル**: `chojugiga_emaki` — prefix/suffix、固定ネガ、ChojuGiga LoRA、Illustrious Pencil XL
- **render preset**: 案出し / 本番 / メモ single
- **RAG ナレッジ**: 画風指針（`style_ref: chojugiga_emaki`）、LoRA 方針、追加ネガの書き方

## テスト

```bash
bin/rails test
```

## 技術スタック

- Rails 8.1, PostgreSQL (pgvector), Neighbor, Solid Queue, Solid Cable
- Hotwire (Turbo / Stimulus), Slim, Vite, Open Props
- `ruby_llm` gem（Chat / ツール呼び出し）
- Active Storage（生成画像の保存）

## 主な画面

| パス | 内容 |
|------|------|
| `/` | メモ挿絵一覧 |
| `/memo_illustrations/new` | メモ挿絵の新規生成 |
| `/image_generations` | 画像生成履歴 |
| `/image_generations/new` | 画像の新規生成 |
| `/chats` | Chat（徒然・Web 検索・RAG） |
| `/service_connections` | 接続管理（設定 → 接続） |
| `/prompt_knowledge_chunks` | プロンプトナレッジ (RAG) |
| `/prompt_styles` | プロンプトスタイル |
| `/sd_model_profiles` | SD モデルプロファイル |
| `/lora_profiles` | LoRA プロファイル |

## 開発メモ

- ジョブは `image_generation` / `default` キューで実行（開発時は Puma 内蔵 Solid Queue）
- Turbo Stream 更新時の画像 URL は相対パス（`/rails/active_storage/...`）を使用。`ApplicationHelper#nyoy_blob_image_tag` 参照
- スタイル / render preset / 能力の seed: `lib/prompt_style_seeds.rb`, `lib/render_preset_seeds.rb`, `lib/capability_seeds.rb`
- Chat ツール: `app/services/chat_tools/`, 徒然 API: `app/services/tsurezure_client.rb`
- メモ RAG 取込: `bin/rails kbmemo:rag:ingest`, `MemoKnowledgeIngestJob`
- 設計詳細: `docs/prompt-architecture-redesign.md`
- kbmemo エコシステム方針: `docs/ecosystem-roadmap.md`
- Chat 高速化（現状・検討案件）: `docs/chat-performance.md`
- 徒然 API 要件: `docs/tsuredure-api-requirements.md`
- 徒然 PGroonga 検索: `docs/tsuredure-pgroonga-search.md`
- seed 再適用: `bin/rails db:seed`
