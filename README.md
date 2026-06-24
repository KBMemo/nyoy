# Nyoy

日本語テキストから Stable Diffusion 画像を生成する Rails アプリです。  
llama.cpp でプロンプトを翻訳・計画し、sd.cpp サーバーで txt2img を実行します。

## 機能

- **メモ挿絵** — 短文メモとプロンプトスキルから JSON 形式の生成計画を作成し、画像を生成
- **画像生成** — 日本語プロンプトを英語 SD プロンプトに翻訳し、モデル・LoRA・sampler 等を指定して生成
- **プロンプトスキル** — llama.cpp 向け system prompt を CRUD で管理。デフォルト negative も設定可能
- **生成プリセット** — SD モデル、解像度、LoRA、sampler、VAE tiling、スキル、デフォルト negative をセットで保存
- **リアルタイム進捗** — Turbo Streams でステータスパネルを自動更新
- **フェーズ別タイム計測** — プロンプト生成時間と画像生成時間を分けて表示

## 前提条件

- Ruby 4.0.3（`.ruby-version` 参照）
- Node.js（Vite 用）
- 外部サービス
  - **llama.cpp** — プロンプト翻訳・計画（`LLAMA_CPP_URL`）
  - **sd.cpp server** — 画像生成（`SDCPP_SERVER_URL`）
  - **sdcpp-switchd** — SD モデル切り替え（`SDCPP_SWITCHD_URL` / `SDCPP_SWITCHD_TOKEN`）

## セットアップ

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

| 変数 | 説明 | デフォルト |
|------|------|-----------|
| `LLAMA_CPP_URL` | llama.cpp の URL | `http://balvenie:10010` |
| `LLAMA_MODEL` | 使用する LLM モデル名 | `gemma-4-12b-it-vision-mtp` |
| `SDCPP_SERVER_URL` | sd.cpp サーバーの URL | `http://balvenie:11234` |
| `SDCPP_SWITCHD_URL` | モデル切り替え API の URL | `http://balvenie:11334` |
| `SDCPP_SWITCHD_TOKEN` | switchd 認証トークン | （未設定） |
| `SDCPP_DEFAULT_MODELS` | UI に表示する SD モデル（カンマ区切り） | `flat2d,anythingv5,dreamshaper8,pony-v6` |

## 使い方

### メモ挿絵

1. トップページ（`/memo_illustrations`）で文章とプロンプトスキルを入力
2. 生成完了までステータスが自動更新される
3. 結果ページで positive / negative プロンプトと画像を確認

JSON 出力スキル（例: 鳥獣戯画プロンプト (JSON)）向けの機能です。

### 画像生成

1. `/image_generations/new` で日本語プロンプトを入力
2. 生成プリセットを選ぶと、モデル・LoRA・ネガティブプロンプト等が自動入力される
3. 必要ならネガティブプロンプトや seed を調整して生成

翻訳スキル（例: 鳥獣戯画プロンプト (翻訳)）は positive のみ出力します。  
negative はプリセット / スキルのデフォルトとフォーム入力を `NegativePromptResolver` がマージします。

### 鳥獣戯画プリセット

seed で以下が登録されます。

- **生成プリセット**: `鳥獣戯画 (Illustrious + ChojuGiga)` — pony-v6, 768×768, ChojuGiga LoRA
- **スキル**: 鳥獣戯画プロンプト (翻訳) / (JSON)
- **デフォルト negative**: 文字・花押・水印などを抑制するタグ群

## テスト

```bash
bin/rails test
```

## 技術スタック

- Rails 8.1, SQLite, Solid Queue, Solid Cable
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
| `/generation_presets` | 生成プリセット管理 |

## 開発メモ

- ジョブは `image_generation` キューで実行（開発時は Puma 内蔵 Solid Queue）
- Turbo Stream 更新時の画像 URL は相対パス（`/rails/active_storage/...`）を使用。`ApplicationHelper#nyoy_blob_image_tag` 参照
- スキル seed の定義: `lib/prompt_skill_seeds.rb`, `lib/generation_preset_seeds.rb`
- seed 再適用: `bin/rails db:seed`
