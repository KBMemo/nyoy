# AgentGraph Evidence Evaluator Profile 実運用 Runbook

対象: Research Graph の `evidence_evaluator.heuristic` と `evidence_evaluator.llm` を比較し、十分性判定、安全境界、fallback、llama.cpp cacheを確認する。

## 1. 事前確認

```bash
set -a
source env.development
set +a

bin/rails runner 'a=LlmUsageAssignment.find_by(usage_key: "agent.evidence_evaluator"); puts JSON.pretty_generate(profile: AgentGraph::RoleServices.profile_for(:evidence_evaluator), model: a&.model&.model_id)'
bin/rails runner 'puts({profile: AgentGraph::RoleServices.profile_for(:evidence_evaluator), profiles: AgentGraph::RoleServices.profile_names(:evidence_evaluator)}.to_json)'
```

設定画面 `/app_settings/edit` の「根拠十分性判定方式」と「根拠十分性判定用モデル」で切り替える。比較後は必ず元へ戻す。

## 2. 安全境界

`evidence_evaluator.llm` はheuristicを先に実行する。LLMが変更できるのは、取得済みページまたはメモがあり、heuristicが`sufficient`としたreviewを`sufficient`のまま維持するか`limited`へ落とすかだけ。

- `needs_web` / `needs_fetch` / `limited` はLLMを呼ばず維持する
- 検索語、取得URL、予算、次nodeをLLMに生成させない
- 出力はbooleanの`sufficient`だけ
- model未設定、接続失敗、不正JSONではheuristicへ戻る
- promptへ渡す根拠JSONは12,000文字まで

## 3. 内容判定とcache確認

同じChatで、関連根拠を2回、無関係根拠を1回判定する。stateには取得済みページと消費済みfetch budgetを設定し、LLM十分性判定だけを測る。

```bash
bin/rails runner - <<'RUBY'
settings = AppSetting.instance
original_profiles = settings.agent_graph_role_profiles.deep_dup
assignment = LlmUsageAssignment.find_by!(usage_key: "agent.evidence_evaluator")
original_model = assignment.model
chat = nil
begin
  chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "qwen3.5-4b"))
  settings.update!(agent_graph_evidence_evaluator_profile: "llm")
  assignment.update!(model: Model.find_by!(provider: "openai", model_id: "qwen3.5-4b"))
  base = {
    "question" => "Rails Active Jobのretry_onは何を設定する機能ですか？",
    "plan" => { "need_web" => true },
    "memo_context" => nil,
    "search_results" => [],
    "evidence_review" => {},
    "budget" => { "searches_used" => 1, "max_searches" => 2, "fetches_used" => 1, "max_fetches" => 2 },
    "errors" => []
  }
  cases = {
    relevant_1: "retry_onは指定した例外が発生したjobを待機時間と試行回数の設定に従って再実行するための宣言です。",
    relevant_2: "retry_onは指定した例外が発生したjobを待機時間と試行回数の設定に従って再実行するための宣言です。",
    irrelevant: "Active Jobはバックグラウンドjobを宣言するためのframeworkです。"
  }
  results = cases.map do |name, content|
    state = base.merge("fetched_pages" => [ { "url" => "https://example.com/docs", "content_preview" => content } ])
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    review, metadata = AgentGraph::RoleServices.fetch(:evidence_evaluator).call(state: state, run: nil, chat: chat)
    {
      case: name,
      elapsed: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3),
      status: review[:status],
      reason: review[:reason],
      metadata: metadata
    }
  end
  puts JSON.pretty_generate(results)
ensure
  settings.update!(agent_graph_role_profiles: original_profiles)
  assignment.update!(model: original_model)
  chat&.destroy!
end
RUBY
```

期待値:

- 関連根拠は`sufficient`
- 無関係根拠は`limited`
- 2回目の同一入力で同じslotを使い、`cached_tokens`が正数
- metadataに`source=light`、model、cache、usageがある

2026-07-20 の `qwen3.5-4b` 実測では、関連根拠2件を`sufficient`、無関係根拠を`limited`と判定した。同一入力は1回目3.375秒、input 196、cached 0、output 11、2回目0.987秒、input 196、cached 109、output 11だった。いずれもslot `0/1` を使用した。

## 4. AgentRun確認

通常のResearch Graphを実行後、AgentRun詳細の`evaluate_evidence`行で次を確認する。

- `profile: evidence_evaluator.llm`
- 成功時: `source: light` とmodel名
- fallback時: `source: heuristic / fallback: heuristic`
- llama.cpp利用時: `cache_prompt`、slot、input/output/cached tokens

```bash
RUN_ID=1 bin/rails runner '
  run = AgentRun.find(ENV.fetch("RUN_ID"))
  node = run.agent_node_runs.where(node_name: "evaluate_evidence").order(:id).last
  puts JSON.pretty_generate(
    status: run.status,
    evidence_review: run.state["evidence_review"],
    node_summary: node&.output_summary
  )
'
```

## 5. fallback障害注入

対象modelの接続だけを一時的に到達不能にし、取得済み根拠を判定する。

```bash
KEY="$(bin/rails runner 'puts LlmUsageResolver.resolve("agent.evidence_evaluator")&.connection&.key')"
test -n "$KEY"
bin/with-service-connection-url "$KEY" http://127.0.0.1:9 -- \
  bin/rails runner - <<'RUBY'
settings = AppSetting.instance
original_profiles = settings.agent_graph_role_profiles.deep_dup
assignment = LlmUsageAssignment.find_by!(usage_key: "agent.evidence_evaluator")
original_model = assignment.model
chat = nil
begin
  chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "qwen3.5-4b"))
  settings.update!(agent_graph_evidence_evaluator_profile: "llm")
  assignment.update!(model: Model.find_by!(provider: "openai", model_id: "qwen3.5-4b"))
  state = {
    "question" => "Rails Active Jobのretry_onは何を設定する機能ですか？",
    "plan" => { "need_web" => true },
    "memo_context" => nil,
    "search_results" => [],
    "fetched_pages" => [ { "url" => "https://example.com", "content_preview" => "retry_onは例外時の再実行を設定します。" } ],
    "evidence_review" => {},
    "budget" => { "searches_used" => 1, "max_searches" => 2, "fetches_used" => 1, "max_fetches" => 2 },
    "errors" => []
  }
  review, metadata = AgentGraph::RoleServices.fetch(:evidence_evaluator).call(state: state, run: nil, chat: chat)
  puts JSON.pretty_generate(status: review[:status], metadata: metadata)
ensure
  settings.update!(agent_graph_role_profiles: original_profiles)
  assignment.update!(model: original_model)
  chat&.destroy!
end
RUBY
```

期待値:

- review statusはheuristicの判定を維持する
- `source=heuristic`
- `fallback=heuristic`
- `error`に接続失敗理由がある
- コマンド終了後にServiceConnectionの`base_url`が復旧する

2026-07-20 の障害注入ではstatus `sufficient`、`source=heuristic`、`fallback=heuristic`を確認し、AppSettingと`llm_qwen35_4b`のURLはいずれも復旧した。

## 6. 復旧確認

```bash
bin/rails runner 'a=LlmUsageAssignment.find_by(usage_key: "agent.evidence_evaluator"); puts JSON.pretty_generate(profile: AgentGraph::RoleServices.profile_for(:evidence_evaluator), model: a&.model&.model_id)'
bin/rails runner 'puts AgentGraph::RoleServices.profile_for(:evidence_evaluator)'
bin/rails runner 'puts LlmUsageResolver.resolve("agent.evidence_evaluator")&.connection&.base_url'
```

期待と異なる場合はAppSetting、`AGENT_GRAPH_EVIDENCE_EVALUATOR_PROFILE`、対象ServiceConnectionの`base_url`を確認する。
