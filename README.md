# Nyoy

日本語テキストから Stable Diffusion 画像を生成する Rails アプリです。  
llama.cpp でプロンプトを翻訳・計画し、sd.cpp サーバーで txt2img を実行します。

## 機能

- **メモ挿絵** — 短文メモとプロンプトスキルから JSON 形式の生成計画を作成し、画像を生成
- **画像生成** — 日本語プロンプトを英語 SD プロンプトに翻訳し、モデル・LoRA・sampler 等を指定して生成
- **プロンプトスキル** — llama.cpp 向け LLM 作法 (system prompt) を CRUD で管理。実行時固定ネガティブも設定可能
- **プロンプトナレッジ** — 画風・LoRA・ネガティブ方針を chunk 化し、pgvector + neighbor で RAG 検索（可変知識）
- **生成プリセット** — SD モデル、解像度、LoRA、sampler、VAE tiling、スキル、実行時固定ネガティブをセットで保存
- **リアルタイム進捗** — Turbo Streams でステータスパネルを自動更新
- **フェーズ別タイム計測** — プロンプト生成時間と画像生成時間を分けて表示

## 前提条件

- Ruby 4.0.3（`.ruby-version` 参照）
- Node.js（Vite 用）
- PostgreSQL 16 + pgvector（`bowmore.artif.org:5432`）
- 外部サービス
  - **llama.cpp** — プロンプト翻訳・計画（`LLAMA_CPP_URL`）
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

1. トップページ（`/memo_illustrations`）で文章とプロンプトスキルを入力
2. 入力文章からプロンプトナレッジ (RAG) を検索し、llama.cpp が JSON 生成計画を作成
3. 生成完了までステータスが自動更新される
4. 結果ページで positive / negative プロンプト、参照ナレッジ、画像を確認

JSON 出力スキル（例: 鳥獣戯画プロンプト (JSON)）向けの機能です。`/prompt_knowledge_chunks` でナレッジを管理できます。

### 画像生成

1. `/image_generations/new` で日本語プロンプトを入力
2. 案出しプリセットを選ぶと、モデル・LoRA 等が自動入力される
3. 必要なら追加ネガティブや seed を調整して生成

日本語プロンプトのみの場合、RAG（プロンプトナレッジ）→ llama.cpp → JSON `PromptSpec` → sd.cpp の流れで SD プロンプトを生成します。`/prompt_knowledge_chunks` でナレッジを管理できます。

翻訳スキル（例: 鳥獣戯画プロンプト (翻訳)）は positive のみ出力します。

### プロンプト設計の役割分担

| レイヤ | 役割 | いつ使う |
|--------|------|----------|
| **スキル** (`body`) | LLM 作法（出力形式・翻訳ルール） | llama.cpp の system prompt |
| **実行時固定ネガティブ** | スキル / 生成プリセットの `default_negative_prompt` | sd.cpp 呼び出し時に `NegativePromptResolver` が常にマージ |
| **追加ネガティブ** | フォーム入力、RAG `PromptSpec` の `negative_prompt` | 固定 tag に上乗せ（重複は uniq で除去） |
| **ナレッジ / テンプレ** | 画風・LoRA 方針・シーン向け negative の**指針** | RAG コンテキストのみ。tag リストの固定コピー源にしない |

RAG の LLM には「固定ネガティブは実行時適用済み」と指示し、`negative_prompt` には situational な追加 tag のみを出力させます。

### 鳥獣戯画プリセット

seed で以下が登録されます。

- **生成プリセット**: `鳥獣戯画 (Illustrious + ChojuGiga)` — pony-v6, 768×768, ChojuGiga LoRA
- **スキル**: 鳥獣戯画プロンプト (翻訳) / (JSON) — LLM 作法のみ
- **実行時固定ネガティブ**: 生成プリセットに鳥獣戯画向け tag 群（文字・花押・水印など）
- **RAG ナレッジ**: 画風・追加 negative の**方針**（固定 tag リストのコピーではない）

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
| `/prompt_skills` | プロンプトスキル管理 |
| `/prompt_knowledge_chunks` | プロンプトナレッジ (RAG) |
| `/prompt_loras` | LoRA 辞書 |
| `/prompt_presets` | プロンプトテンプレート (RAG) |
| `/generation_presets` | 生成プリセット管理 |

## 開発メモ

- ジョブは `image_generation` キューで実行（開発時は Puma 内蔵 Solid Queue）
- Turbo Stream 更新時の画像 URL は相対パス（`/rails/active_storage/...`）を使用。`ApplicationHelper#nyoy_blob_image_tag` 参照
- スキル seed の定義: `lib/prompt_skill_seeds.rb`, `lib/generation_preset_seeds.rb`
- seed 再適用: `bin/rails db:seed`
