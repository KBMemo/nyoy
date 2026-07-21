# AgentGraph Planner Profile 実運用 Runbook

対象: Research Graph の `planner.deterministic` と `planner.llm` を比較し、分類、検索経路、fallback、llama.cpp cacheを確認する。

## 1. 事前確認

developmentでは環境変数を読み込み、設定値を控える。

```bash
set -a
source env.development
set +a

bin/rails runner 'a=LlmUsageAssignment.find_by(usage_key: "agent.planner"); puts JSON.pretty_generate(profile: AgentGraph::RoleServices.profile_for(:planner), model: a&.model&.model_id)'
bin/rails runner 'puts({profile: AgentGraph::RoleServices.profile_for(:planner), profiles: AgentGraph::RoleServices.profile_names(:planner)}.to_json)'
```

設定画面 `/app_settings/edit` の「調査計画方式」でprofileを、「調査計画用モデル」で軽量modelを選べる。比較後は必ず控えた値へ戻す。

## 2. 比較質問

少なくとも次の3種類を同じ組で比較する。

1. 外部技術文書が必要な質問
2. 過去のユーザーメモだけで答える質問
3. 明示URLの取得を求める質問

期待例:

| 質問種別 | need_web | need_memo | sensitive |
| --- | --- | --- | --- |
| Rails等の外部仕様 | true | false | false |
| 過去に保存したメモ | false | true | false |
| 明示URLの確認 | true | false | false |

`planner.llm` は要否だけを分類する。`queries`、`fetch_urls`、`sensitive` は決定規則の結果であり、LLMが生成した固有名詞を検索語へ混入させない。

## 3. AgentRun確認

実行後、AgentRun詳細の `plan_research` 行で次を確認する。

- `profile: planner.llm`
- 軽量model成功時: `source: light` とmodel名
- fallback時: `source: deterministic / fallback: deterministic`
- llama.cpp利用時: `cache_prompt`、slot、input/output/cached tokens

state JSONでは `planning` と `plan` を確認する。

```bash
RUN_ID=84 bin/rails runner '
  run = AgentRun.find(ENV.fetch("RUN_ID"))
  node = run.agent_node_runs.find_by!(node_name: "plan_research")
  puts JSON.pretty_generate(
    planning: run.state["planning"],
    plan: run.state["plan"],
    nodes: run.agent_node_runs.order(:id).pluck(:node_name),
    node_summary: node.output_summary
  )
'
```

明示URL質問は `plan_research → fetch_urls → evaluate_evidence` と進み、取得ページが十分なら `search_web` を通らないことを確認する。

## 4. cache確認

同じChat、同じ質問を連続実行する。`planning.usage.cached_tokens` が正数で、同じslotを使うことを確認する。slot共有数が1の場合は他の処理ですでにprefixがcacheされていることがあるため、1回目と2回目の差だけでなく `cached_tokens / input_tokens` も記録する。

2026-07-20 のrun 88〜89では、両方ともslot `0/1`、input 121、cached 95、output 20だった。

## 5. fallback障害注入

planner modelの接続だけを一時的に到達不能にする。`KEY` は対象modelの `service_connection.key` を使う。

```bash
KEY="$(bin/rails runner 'puts LlmUsageResolver.resolve("agent.planner")&.connection&.key')"
test -n "$KEY"
bin/with-service-connection-url "$KEY" http://127.0.0.1:9 -- \
  bin/rails runner - <<'RUBY'
settings = AppSetting.instance
original_profiles = settings.agent_graph_role_profiles.deep_dup
assignment = LlmUsageAssignment.find_by!(usage_key: "agent.planner")
original_model = assignment.model
settings.update!(agent_graph_planner_profile: "llm")
assignment.update!(model: Model.find_by!(provider: "openai", model_id: "qwen3.5-4b"))
AgentGraph::FinalAnswerSynthesizer.force_passthrough = true

begin
  run = AgentGraph::ResearchGraphRunner.call_for_mcp(
    question: "Rails 8.1 Active Job retry を調べて"
  )
  puts JSON.pretty_generate(
    run_id: run.id,
    status: run.status,
    planning: run.state["planning"],
    error: run.error_message
  )
ensure
  settings.update!(
    agent_graph_role_profiles: original_profiles
  )
  assignment.update!(model: original_model)
  AgentGraph::FinalAnswerSynthesizer.force_passthrough = false
end
RUBY
```

`bin/with-service-connection-url` はコマンド終了時に元のURLへ復旧する。実際のGraph実行では次を確認する。

- AgentRunは `completed`
- `planning.profile=llm`
- `planning.source=deterministic`
- `planning.fallback=deterministic`
- `planning.error` に接続失敗理由がある

2026-07-20 のrun 90でこの経路を確認した。接続URLとAppSettingはいずれも復旧済み。

## 6. 復旧確認

```bash
bin/rails runner 'a=LlmUsageAssignment.find_by(usage_key: "agent.planner"); puts JSON.pretty_generate(profile: AgentGraph::RoleServices.profile_for(:planner), model: a&.model&.model_id)'
bin/rails runner 'puts AgentGraph::RoleServices.profile_for(:planner)'
```

期待する設定と異なる場合は、AppSetting、`AGENT_GRAPH_PLANNER_PROFILE`、対象ServiceConnectionの `base_url` を確認する。
