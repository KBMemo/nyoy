# AgentGraph Intent Profile 実運用 Runbook

対象: `intent.deterministic` と `intent.hybrid_llm` を比較し、Research Graph昇格、通常chat維持、cache、障害時fallbackを確認する。

## 1. 事前確認

```bash
set -a
source env.development
set +a

bin/rails runner 'puts JSON.pretty_generate(AppSetting.instance.attributes.slice("agent_graph_role_profiles", "agent_graph_intent_model_id"))'
bin/rails runner 'puts({profile: AgentGraph::RoleServices.profile_for(:intent), profiles: AgentGraph::RoleServices.profile_names(:intent)}.to_json)'
```

設定画面 `/app_settings/edit` の「Graph起動判定方式」と「Graph起動判定用モデル」で切り替える。比較後は必ず元へ戻す。

## 2. 安全境界

`hybrid_llm` は決定規則を先に実行する。LLMが判断できるのは、未判定の通常テキストをResearch Graphへ昇格するかだけ。

- メモ書込・更新・画像理解Graphは決定規則だけで選ぶ
- 添付turnはLLMへ送らない
- 挨拶・画像生成等の明示的な非調査turnはLLMへ送らない
- model未設定、接続失敗、不正JSONではnilを返して通常chatへ戻る
- LLMに任せる出力はbooleanの `use_research_graph` だけ

## 3. 比較ケース

少なくとも次を含める。

| 種別 | 期待 |
| --- | --- |
| framework / library / API仕様 | Researchへ昇格 |
| 天気・最新version等の変動情報 | Researchへ昇格 |
| 文章の書き直し | 通常chat |
| 創作 | 通常chat |
| 挨拶 | 通常chat、LLM呼出なし |
| 添付を使う画像生成 | 通常chat、LLM呼出なし |

2026-07-20 に `qwen3.5-4b` で8ケースを確認し、期待との一致は8/8だった。LLM判定は約0.94〜1.61秒、挨拶の短絡は約0.005秒。各LLM判定のcached tokensは114だった。

## 4. Research Graph昇格の確認

昇格時はRouterの `intent_decision` がResearch初期stateの `routing` へ保存される。AgentRun詳細またはrunnerで確認する。

```bash
RUN_ID=91 bin/rails runner '
  run = AgentRun.find(ENV.fetch("RUN_ID"))
  puts JSON.pretty_generate(
    status: run.status,
    routing: run.state["routing"],
    summary_routing: AgentGraph::ResearchRunSummary.build(run)[:routing]
  )
'
```

期待:

- `routing.reason=llm_research_escalation`
- `routing.profile=hybrid_llm`
- `routing.source=light`
- model、llama cache、token usageがある

run 91では `qwen3.5-4b`、input 139、cached 114、output 13を確認した。

## 5. 障害注入

intent modelの接続だけを一時的に到達不能にする。設定画面で `hybrid_llm` と対象modelを選んだ状態で、別shellから次を実行してもよい。コマンド終了後に接続URLは自動復旧する。

```bash
KEY=llm_qwen35_4b
bin/with-service-connection-url "$KEY" http://127.0.0.1:9 -- \
  bin/rails runner '
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "qwen3.5-4b"))
    Message.suppressing_turbo_broadcasts do
      chat.messages.create!(role: :user, content: "Rails Active Job retry設計の要点は？")
    end
    decision = AgentGraph::Router.route(chat)
    puts({ decision: decision, normal_chat_fallback: decision.nil? }.to_json)
    chat.destroy!
  '
```

期待値は `decision=null`、`normal_chat_fallback=true`。2026-07-20 のdevelopment障害注入で確認済み。

## 6. 復旧確認

```bash
bin/rails runner 'puts JSON.pretty_generate(AppSetting.instance.attributes.slice("agent_graph_role_profiles", "agent_graph_intent_model_id"))'
bin/rails runner 'puts AgentGraph::RoleServices.profile_for(:intent)'
```

期待と異なる場合はAppSetting、`AGENT_GRAPH_INTENT_PROFILE`、対象ServiceConnectionの `base_url` を確認する。
