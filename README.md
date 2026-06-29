# Nyoy

日本語テキストから Stable Diffusion 画像を生成する Rails アプリです。  
llama.cpp で `style_id` ベースの最小 JSON 計画を作成し、`SdPromptStyleResolver` で実行設定を解決して sd.cpp で txt2img を実行します。

## 機能

- **メモ挿絵** — 短文メモから style 計画（`style_id` + `subject_prompt`）を作成し、画像を生成
- **画像生成** — 日本語プロンプトを style 計画に変換し、案出し → 選択 → 仕上げ（Hires）のパイプラインで生成
- **プロンプトスタイル** — 見た目（prefix/suffix/固定ネガ/LoRA/モデル）を `prompt_styles` で管理（seed）
- **描画プリセット** — draft / refine / single のパイプライン設定を `render_presets` で管理（seed）
- **プロンプトナレッジ** — 画風・LoRA・ネガティブ方針を chunk 化し、pgvector + neighbor で RAG 検索
- **リアルタイム進捗** — Turbo Streams でステータスパネルを自動更新
- **フェーズ別タイム計測** — プロンプト生成時間と画像生成時間を分けて表示

## 前提条件

- Ruby 4.0.3（`.ruby-version` 参照）
- Node.js（Vite 用）
- PostgreSQL 16 + pgvector（`bowmore.artif.org:5432`）
- 外部サービス
  - **llama.cpp** — style 計画（`LLAMA_CPP_URL`）
  - **sd.cpp server** — 画像生成（`SDCPP_SERVER_URL`）
  - **sdcpp-switchd** — SD モデル切り替え（`SDCPP_SWITCHD_URL` / `SDCPP_SWITCHD_TOKEN`）

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

`http://localhost:3000` を開きます。

## 環境変数

`bin/dev` は `env.development` を読み込みます。必要に応じてコピーして編集してください。

PostgreSQL のホスト・認証情報は `config/database.yml` と Rails credentials（`database.username` / `database.password`）で管理します。CI のみ `DB_*` 環境変数で上書きします。

| 変数 | 説明 | デフォルト |
|------|------|-----------|
| `EMBEDDINGS_URL` | bge-m3 embeddings API | `http://balvenie:10020` |
| `EMBEDDINGS_MODEL` | 埋め込みモデル名 | `groonga/bge-m3-Q4_K_M-GGUF` |
| `EMBEDDING_DIMENSIONS` | ベクトル次元数 | `1024` |
| `EMBEDDING_MAX_CHARS` | embedding API へ送る最大文字数（サーバ batch 512 tokens 向け） | `1000` |
| `LLAMA_JSON_SCHEMA` | llama.cpp へ JSON Schema 制約を送る | `true` |
| `LLAMA_CPP_URL` | llama.cpp の URL | `http://balvenie:10010` |
| `LLAMA_MODEL` | 使用する LLM モデル名 | `gemma-4-12b-it-vision-mtp` |
| `SDCPP_SERVER_URL` | sd.cpp サーバーの URL | `http://balvenie:11234` |
| `SDCPP_SWITCHD_URL` | モデル切り替え API の URL | `http://balvenie:11334` |
| `SDCPP_SWITCHD_TOKEN` | switchd 認証トークン | （未設定） |
| `SDCPP_DEFAULT_MODELS` | UI に表示する SD モデル（カンマ区切り） | `flat2d,anythingv5,dreamshaper8,pony-v6,illustrious_pencil-XL` |

## 使い方

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
- Active Storage（生成画像の保存）

## 主な画面

| パス | 内容 |
|------|------|
| `/` | メモ挿絵一覧 |
| `/memo_illustrations/new` | メモ挿絵の新規生成 |
| `/image_generations` | 画像生成履歴 |
| `/image_generations/new` | 画像の新規生成 |
| `/prompt_knowledge_chunks` | プロンプトナレッジ (RAG) |
| `/sd_model_profiles` | SD モデルプロファイル |

## 開発メモ

- ジョブは `image_generation` キューで実行（開発時は Puma 内蔵 Solid Queue）
- Turbo Stream 更新時の画像 URL は相対パス（`/rails/active_storage/...`）を使用。`ApplicationHelper#nyoy_blob_image_tag` 参照
- スタイル / render preset / 能力の seed: `lib/prompt_style_seeds.rb`, `lib/render_preset_seeds.rb`, `lib/capability_seeds.rb`
- 設計詳細: `docs/prompt-architecture-redesign.md`
- seed 再適用: `bin/rails db:seed`
