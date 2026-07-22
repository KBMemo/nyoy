# Agent guide (nyoy)

このリポジトリでエージェント／コントリビュータが参照する実装方針です。Nyoy は LLM、画像生成、MCP、KBMemo 連携を状態機械型 Agent Graph で統合する Rails アプリです。

## 現在の構成

- Rails 8.1 / PostgreSQL + pgvector / Solid Queue / Solid Cable
- Turbo + Stimulus + Action Cable。asset build は Vite
- View は Slim
- CSS は `app/javascript/entrypoints/application.css` と `app/javascript/styles/` の通常 CSS。**Tailwind CSS は使用していない**
- LLM client は `ruby_llm` と llama.cpp 互換 API。server lifecycle は llama-switchd と連携
- MCP server / client、KBMemo（徒然）API、Tsuzura API、画像生成 backend を外部接続として扱う
- graph engine の再利用部分は path gem `packages/agent_graph-core`
- 本番は Puma + systemd user service。デプロイ入口は `bin/deploy`

## 主なディレクトリ

- `app/services/agent_graph`: Nyoy 固有 graph、runner、runtime context、registry、永続化 adapter
- `packages/agent_graph-core`: Rails に依存しない graph primitive と contract
- `app/services/chat_tools`: main LLM に許可する tool、policy、budget
- `app/services`: LLM client、prompt、RAG、画像生成、外部 API adapter
- `app/models/agent_*`: AgentRun、node run、checkpoint の永続状態
- `app/jobs`: graph resume / retry、chat response、画像生成、同期・監視処理
- `app/controllers/mcp_controller.rb`: MCP JSON-RPC 入口
- `app/javascript/controllers`: streaming、進捗表示、画像操作、管理画面の Stimulus controller
- `app/javascript/styles`: theme、chrome component、互換 utility
- `docs/architecture`: graph 設計方針と workflow ごとの契約
- `docs/*runbook.md`: model profile、障害注入、実運用確認

## Agent Graph

- 設計の正は `docs/architecture/agent-graph-design-policy.md`。Research、MemoWrite、MemoUpdate、ImageUnderstanding の個別文書も先に確認する。
- node は state を入力し `NodeResult` を返す。遷移判断、状態更新、副作用を暗黙に混在させない。
- graph definition と runner、Nyoy の runtime context、Active Record run store の境界を保つ。
- retry / resume は `AgentRun`、`AgentNodeRun`、checkpoint の永続状態から再開できることを前提にする。process memory だけに進行状態を置かない。
- tool call、承認待ち、progress、final answer は既存 broadcaster / publisher を経由し、UI への直接依存を node に持ち込まない。
- `agent_graph-core` に移すのは host 非依存の primitive と protocol に限る。Active Record、Rails job、Action Cable、Nyoy の service object は app 側に残す。
- workflow を追加するときは registry、initial state、state schema、graph、runner、run summary、entrypoint、履歴表示、retry 契約を一式で確認する。

## LLM と Prompt

- 用途から model を選ぶ設定は `LlmUsageAssignment`、接続先と稼働状態は llama server definition / service connection が担当する。用途設定と server lifecycle を再結合しない。
- intent、planner、draft、evidence evaluator、final answer など role ごとの service は registry / configuration 経由で差し替える。
- llama.cpp prompt cache を維持するため、安定した system / knowledge prefix を前方に置き、turn ごとの差分を後方に置く。message 順序を不用意に変えない。
- main LLM の tool 利用は `ChatTools::MainLlmToolPolicy` と budget を通す。registry に存在するだけで無制限に許可しない。
- prompt の変更は出力品質だけでなく、JSON schema、parser、fallback、cache、model profile runbook への影響を確認する。

## CSS と JavaScript

- Tailwind の runtime、compiler、設定ファイルはない。既存の `ny-*` / component class、theme token、`utility-compat.css` を優先する。
- utility 風 class は通常 CSS に明示定義されている。Tailwind class を追加しただけでは style は生成されない。
- UI の DOM 状態は Stimulus controller、非同期進捗は Turbo / Action Cable の既存経路に置く。
- icon は `lucide` の既存 loader を使い、手書き SVG を増やさない。
- streaming 中、reload 後、job 継続中の表示を分けて確認する。client memory だけを最終状態の正にしない。

## 外部接続と秘密情報

- llama server、llama-switchd、Stable Diffusion、KBMemo、Tsuzura は service / settings class を介して接続する。controller や node から URL を直書きしない。
- `.env.example` / `env.development.example` は名前と説明だけを持つ。実 token、API key、admin token を commit しない。
- MCP tool は公開名、input schema、認証、重複、deprecated 状態を確認する。互換性を壊す rename / remove は文書と client を同時に更新する。
- URL fetch、検索結果、画像、memo 本文は外部入力として扱い、size、encoding、content type、SSRF、安全な表示境界を維持する。

## テストと検証

- Rails test: `bin/rails test`
- 対象 test: `bin/rails test test/path/to/test.rb`
- AgentGraph Core: `bundle exec rake -C packages/agent_graph-core test`
- Ruby style: `bin/rubocop`
- 全体確認: `bin/ci`

`bin/ci` は Vite test asset build、Ruby / npm security audit、Rails test、core gem test、seed、test DB cleanup を含む。LLM や外部 server を使う実運用確認は自動 test と分け、対応する runbook に結果を記録する。

## Migration と運用

- graph state や設定の migration は進行中 run と既存 assignment の互換性を考慮する。
- model 接続変更では database 設定、health、reconciliation、operation job、alert を一緒に確認する。
- `bin/deploy` は systemd user service `nyoy` を restart し、startup delay 後に health check する。
- deploy 前確認は `bin/deploy --check`、command 確認は `bin/deploy --dry-run` を使う。
- 本番の秘密情報と環境変数は `scripts/production_env.sh` の契約に従う。
