# AgentGraph Final Answer Profile 実運用 Runbook

対象: Research Graphの`final_answer.main`と`final_answer.light`を比較し、回答品質、速度、llama.cpp cache、main fallbackを確認する。

## 1. 事前確認

```bash
set -a
source env.development
set +a

bin/rails runner 'a=LlmUsageAssignment.find_by(usage_key: "agent.final_answer"); puts JSON.pretty_generate(profile: AgentGraph::RoleServices.profile_for(:final_answer), model: a&.model&.model_id)'
bin/rails runner 'puts({profile: AgentGraph::RoleServices.profile_for(:final_answer), profiles: AgentGraph::RoleServices.profile_names(:final_answer)}.to_json)'
```

設定画面`/app_settings/edit`の「最終回答方式」と「最終回答用軽量モデル」で切り替える。比較後は必ず元へ戻す。

## 2. 実行契約

`final_answer.light`は、Research Graphが収集・評価した同じevidence packから完成回答を生成する。

- 軽量modelではmodel既定samplingを使う
- llama.cpp slot keyは`agent_graph:final_light:<chat_id>:<model_id>`
- `enable_thinking=false`を強制し、思考文の本文混入と不要なtoken生成を防ぐ
- model未設定、接続失敗、空応答時は`final_answer.main`を1回だけ実行する
- mainも失敗した場合だけ`finalize_answer` nodeを失敗させる
- 既定profileは`main`を維持する

## 3. main / light比較

同じChatとstateを使い、mainを1回、lightを2回実行する。stateには質問、draft、取得ページ、evidence reviewを含める。

```bash
bin/rails runner - <<'RUBY'
settings = AppSetting.instance
original_profiles = settings.agent_graph_role_profiles.deep_dup
assignment = LlmUsageAssignment.find_by!(usage_key: "agent.final_answer")
original_model = assignment.model
chat = nil
begin
  chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  state = {
    "question" => "Rails Active Jobのretry_onは何を設定する機能ですか？",
    "draft" => "retry_onは、指定した例外が起きたジョブを設定に従って再実行するための宣言です。",
    "draft_truncated" => false,
    "memo_context" => nil,
    "plan" => { "need_web" => true },
    "search_results" => [],
    "fetched_pages" => [ {
      "title" => "Active Job Basics",
      "url" => "https://guides.rubyonrails.org/active_job_basics.html",
      "content_preview" => "retry_on can configure an Active Job to retry when a specific exception is raised. The wait interval and number of attempts can be configured."
    } ],
    "evidence_review" => { "status" => "sufficient", "reason" => "fetched pages are available" },
    "budget" => {},
    "errors" => []
  }
  cases = [ [ :main, "main", nil ], [ :light_1, "light", "qwen3.5-4b" ], [ :light_2, "light", "qwen3.5-4b" ] ]
  results = cases.map do |name, profile, model_id|
    settings.update!(agent_graph_final_answer_profile: profile)
    assignment.update!(model: Model.find_by!(provider: "openai", model_id: model_id)) if model_id
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    answer, truncated, metadata = AgentGraph::RoleServices.fetch(:final_answer).call(state: state, run: nil, chat: chat)
    {
      case: name,
      elapsed: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3),
      truncated: truncated,
      answer: answer,
      metadata: metadata.except("system_prompt", "user_prompt", "thinking")
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

確認項目:

- 結論が質問へ直接答えている
- evidenceにない具体値、class、API構文を補っていない
- `<think>`や`Thinking Process:`が本文にない
- metadataにprofile相当のsource、model、cache、usageがある
- 同じlight入力で同じslotを使い、cached tokensが正数になる

## 4. development実測

2026-07-20、main=`gpt-oss`、light=`qwen3.5-4b`で確認した。

| profile | elapsed | input | output | cached | 結果 |
| --- | ---: | ---: | ---: | ---: | --- |
| main | 32.386秒 | 397 | 738 | 0 | 回答品質は安定 |
| light 1 | 16.348秒 | 398 | 308 | 215 | 思考漏れなし |
| light 2 | 21.013秒 | 398 | 434 | 215 | 思考漏れなし |

初期実装ではlight初回が152.665秒・output 3215となり、2回目の本文に`Thinking Process:`が混入した。原因はQwenのthinkingが有効だったことで、light経路へ`enable_thinking=false`を追加して解消した。

thinking無効化後はmainより11〜16秒短縮した。一方、evidenceにない既定待機秒数、例外class、API例を補う回答があり、同じ入力でも具体値が揺れた。速度改善は確認できたが、品質上の理由から既定profileは`main`を維持する。lightはmodel比較とprompt評価用のopt-inとする。

## 5. fallback障害注入

light modelの接続だけを一時的に到達不能にし、第3節と同じstateで実行する。

```bash
KEY="$(bin/rails runner 'puts LlmUsageResolver.resolve("agent.final_answer")&.connection&.key')"
test -n "$KEY"
bin/with-service-connection-url "$KEY" http://127.0.0.1:9 -- \
  bin/rails runner - <<'RUBY'
settings = AppSetting.instance
original_profiles = settings.agent_graph_role_profiles.deep_dup
assignment = LlmUsageAssignment.find_by!(usage_key: "agent.final_answer")
original_model = assignment.model
chat = nil
begin
  chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  settings.update!(agent_graph_final_answer_profile: "light")
  assignment.update!(model: Model.find_by!(provider: "openai", model_id: "qwen3.5-4b"))
  state = {
    "question" => "retry_onとは？",
    "draft" => "retry_onは例外発生時のジョブ再試行を設定します。",
    "draft_truncated" => false,
    "memo_context" => nil,
    "plan" => {},
    "search_results" => [],
    "fetched_pages" => [],
    "evidence_review" => { "status" => "sufficient", "reason" => "draft is available" },
    "budget" => {},
    "errors" => []
  }
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  answer, truncated, metadata = AgentGraph::RoleServices.fetch(:final_answer).call(state: state, run: nil, chat: chat)
  puts JSON.pretty_generate(
    elapsed: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3),
    answer_present: answer.present?,
    truncated: truncated,
    metadata: metadata.except("system_prompt", "user_prompt", "thinking")
  )
ensure
  settings.update!(agent_graph_role_profiles: original_profiles)
  assignment.update!(model: original_model)
  chat&.destroy!
end
RUBY
```

確認項目:

- answerが空でない
- `metadata.source=main`
- `metadata.fallback=main`
- `metadata.light_model_id=qwen3.5-4b`
- `metadata.fallback_error`にlight接続失敗理由がある
- mainのcacheとusageが残る

2026-07-20の障害注入では41.539秒でmain回答を生成し、input 326、output 920、cached 216だった。AppSettingと`llm_qwen35_4b`の接続URLはいずれも復旧した。

## 6. AgentRun確認

通常のResearch Graph実行後、AgentRun詳細の`finalize_answer`行とstateの`final_synthesis`を確認する。

```bash
RUN_ID=1 bin/rails runner '
  run = AgentRun.find(ENV.fetch("RUN_ID"))
  node = run.agent_node_runs.where(node_name: "finalize_answer").order(:id).last
  puts JSON.pretty_generate(final_synthesis: run.state["final_synthesis"], node_summary: node&.output_summary)
'
```

light成功時は`profile: final_answer.light / source: light`、fallback時は`profile: final_answer.light / source: main / fallback: main`を期待する。

## 7. 復旧確認

```bash
bin/rails runner 'a=LlmUsageAssignment.find_by(usage_key: "agent.final_answer"); puts JSON.pretty_generate(profile: AgentGraph::RoleServices.profile_for(:final_answer), model: a&.model&.model_id)'
bin/rails runner 'puts AgentGraph::RoleServices.profile_for(:final_answer)'
bin/rails runner 'puts LlmUsageResolver.resolve("agent.final_answer")&.connection&.base_url'
```

期待と異なる場合はAppSetting、`AGENT_GRAPH_FINAL_ANSWER_PROFILE`、対象ServiceConnectionの`base_url`を確認する。
