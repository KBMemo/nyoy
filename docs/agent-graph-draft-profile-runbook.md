# AgentGraph Draft Profile 比較 Runbook

対象: Research Graph の `draft.evidence_pack` と `draft.llm` を同じ質問で比較し、実効profile、model、fallback、所要時間、最終回答品質を確認する。

関連設計: [Agent Graph 設計方針](./architecture/agent-graph-design-policy.md#role-service-registry)

## 前提

- Nyoy が `http://127.0.0.1:3109` で起動している
- Research Graphで使うLLM、検索、ページ取得の接続が有効
- `env.development` に `MCP_API_TOKEN` が設定されている
- migrationが適用済み

shellへ開発環境設定を読み込む。

```bash
set -a
source env.development
set +a
export NYOY_MCP_URL="${NYOY_MCP_URL:-http://127.0.0.1:3109/mcp}"
```

接続と公開toolを確認する。

```bash
bin/mcp-list-tools | rg 'run_research_graph|get_research_graph'
```

## 1. 比較前の設定を記録する

設定画面 `/app_settings/edit` の次の値を控える。

- 調査ドラフト方式
- 調査ドラフト用model
- 調査ドラフト失敗時

consoleで確認する場合:

```bash
bin/rails runner 'puts JSON.pretty_generate(AppSetting.instance.attributes.slice("agent_graph_role_profiles", "research_draft_model_id", "research_draft_fallback"))'
```

確認終了後にこの値へ戻す。

## 2. 比較質問を決める

2回とも完全に同じ質問を使う。Webの変化を減らすため、短い間隔で実行し、可能なら確認対象のURLを質問に含める。

```bash
export RESEARCH_QUESTION='https://example.com/ の内容を確認し、要点と注意点を根拠付きで説明して'
```

`bin/mcp-call-tool` の応答待ち時間は既定で300秒。長い調査では必要に応じて延長する。

```bash
export MCP_HTTP_READ_TIMEOUT=600
```

比較対象はdraft生成だけであり、検索結果や取得ページが変わったrunは品質比較から除外する。AgentRun詳細の `search_results` / `fetched_pages` 件数とURLも確認する。

## 3. `evidence_pack` を実行する

設定画面で「調査ドラフト方式」を「根拠パック」にして保存する。

```bash
PACK_RUN_ID=$(bin/mcp-call-tool --field agent_run_id run_research_graph \
  "{\"question\":$(ruby -rjson -e 'print ENV.fetch("RESEARCH_QUESTION").to_json')}" )
echo "$PACK_RUN_ID"
bin/mcp-call-tool get_research_graph "{\"agent_run_id\":$PACK_RUN_ID}"
```

期待:

- runは `completed`
- `draft_synthesis.role` は `draft`
- `draft_synthesis.profile` は `evidence_pack`
- `draft_synthesis.source` は `evidence_pack`
- `draft_synthesis.model_id` と `fallback` は空

## 4. `llm` を実行する

設定画面で次を保存する。

- 調査ドラフト方式: `LLM ドラフト`
- 調査ドラフト用model: 比較する軽量model
- 調査ドラフト失敗時: `メインモデルで再試行` または `テンプレのみ`

```bash
LLM_RUN_ID=$(bin/mcp-call-tool --field agent_run_id run_research_graph \
  "{\"question\":$(ruby -rjson -e 'print ENV.fetch("RESEARCH_QUESTION").to_json')}" )
echo "$LLM_RUN_ID"
bin/mcp-call-tool get_research_graph "{\"agent_run_id\":$LLM_RUN_ID}"
```

期待:

- runは `completed`
- `draft_synthesis.profile` は `llm`
- 軽量model成功時は `source=light`、`model_id` は選択model、`fallback` は空
- main modelへ再試行した場合は `source=main`、`fallback=main`
- templateへ移った場合は `source=template`、`fallback=template`

## 5. 2 runを比較する

```bash
RUN_IDS="$PACK_RUN_ID,$LLM_RUN_ID" bin/rails runner '
  AgentRun.where(id: ENV.fetch("RUN_IDS").split(",")).order(:id).each do |run|
    node = run.agent_node_runs.find_by(node_name: "synthesize_draft")
    meta = run.state.fetch("draft_synthesis", {})
    puts({
      run_id: run.id,
      status: run.status,
      total_seconds: run.started_at && run.finished_at ? (run.finished_at - run.started_at).round(3) : nil,
      draft_seconds: node&.elapsed_seconds&.round(3),
      profile: meta["profile"],
      model_id: meta["model_id"],
      source: meta["source"],
      fallback: meta["fallback"],
      truncated: run.state["draft_truncated"],
      evidence: {
        memo: run.state["memo_context"].to_s.empty? ? 0 : 1,
        search_results: Array(run.state["search_results"]).sum { |item| Array(item["results"]).size },
        fetched_pages: Array(run.state["fetched_pages"]).size,
        errors: Array(run.state["errors"]).size
      },
      error: run.error_message
    }.to_json)
  end
'
```

AgentRun詳細も開き、`synthesize_draft` 行の要約とstate JSONが一致することを確認する。

比較表へ次を記録する。

| 項目 | evidence_pack | llm |
| --- | --- | --- |
| AgentRun ID |  |  |
| total seconds |  |  |
| synthesize_draft seconds |  |  |
| model_id |  |  |
| source / fallback |  |  |
| final answerの事実誤認 |  |  |
| 根拠・URLの保持 |  |  |
| 冗長さ・読みやすさ |  |  |

採用判断では1回の速度だけを見ず、少なくとも異なる質問を3件実行する。`llm` が最終回答品質を改善しない、またはfallback率が高い場合は `evidence_pack` を維持する。

## 6. fallback経路を確認する

任意確認。`LLM ドラフト` と軽量modelを選択した状態で、そのmodelの接続先を一時停止または到達不能にして実行する。

- fallback設定が `main` の場合: `fallback=main` とmain modelの `model_id`
- fallback設定が `template` の場合: `fallback=template` と空の `model_id`
- runが失敗した場合: `synthesize_draft` のsnapshotと `errors` を確認する

接続先を変更した場合は必ず元に戻す。軽量modelとmain modelが同じ接続を共有する場合、接続全体を停止すると両方失敗するため `main` fallbackの確認には使わない。

## 7. 設定を復旧する

手順1で控えた値へ設定画面から戻す。最後に実効profileを確認する。

```bash
bin/rails runner 'puts AgentGraph::RoleServices.profile_for(:draft)'
```

期待するprofileと一致しない場合は、`AppSetting.instance.agent_graph_role_profiles` と `AGENT_GRAPH_DRAFT_PROFILE` の両方を確認する。

## 実測記録（2026-07-20、development）

`qwen3.5-4b` を軽量modelに指定し、上記3質問で比較した。run 71〜76は検索・取得・draft生成を通常どおり実行し、比較対象外の最終回答だけ `FinalAnswerSynthesizer.force_passthrough` で省略した。設定は比較後に `evidence_pack` へ復旧済み。

| 質問 | evidence_pack | llm | llm draft時間 | 判定 |
| --- | --- | --- | ---: | --- |
| ヤマレコ 天城山 | run 71 / 0.006秒 | run 74 / 11.006秒 | 11.006秒 | llmが標高・地域・起点を根拠なく補完 |
| Rails 8.1 Active Job retry | run 72 / 0.005秒 | run 75 / 16.786秒 | 16.786秒 | llmが存在しない、または不正確なAPI例を生成 |
| llama.cpp prompt cache | run 73 / 0.005秒 | run 76 / 5.027秒 | 5.027秒 | llmは根拠不足を正しく明示 |

全llm runで `profile=llm`、`model_id=qwen3.5-4b`、`source=light`、fallbackなしを確認した。速度は `evidence_pack` が約0.005秒、llmは約5〜17秒だった。3件中2件で根拠のない具体化があり、現時点では `evidence_pack` を既定のまま維持する。

HTTP MCPの通常経路も run 70 で確認した。`evidence_pack` から最終回答まで完了したが、全体242.95秒のうち最終回答生成が242.27秒（5,023 output tokens）を占めた。長い調査では `MCP_HTTP_READ_TIMEOUT=600` を使用する。この実測で判明した思考ストリームの過剰な累積broadcastには、ライブ更新を1秒間隔、送信本文を末尾16,000文字に制限する対策を追加した。保存される最終的な思考全文は制限しない。
