# Agent Graph（Research Graph）

LangGraph 型の薄い Workflow ランタイム。最初の 1 Graph は調査フロー。

## 現状（R2）

```
plan_research → recall_memos → search_web → fetch_urls → synthesize_draft → await_approval → finalize_answer
```

各 Node は plan / 結果に応じてスキップされる（例: `need_web=false` なら search/fetch へ進まない）。

- 入口: `ChatResponseJob` がユーザー質問を `AgentGraph::ResearchIntent` で判定し、一致したら `ResearchGraphRunner` に委譲
- `synthesize_draft` は根拠からドラフトを合成（`EvidenceSynthesizer` / RubyLLM）。チャットにはまだ書かない
- `await_approval` は Interrupt → `status=awaiting_approval`。UI で承認 / 却下
- 承認後: `AgentGraphResumeJob` → `finalize_answer` がアシスタントメッセージを作成
- 却下: 却下メッセージを出して完了
- 既存 Chat tool loop はそのまま残る（意図が一致しない通常会話）
- `search_web` / `fetch_urls` は既存 `ChatTools::WebSearch` / `FetchUrl` + `WebToolBudget`（state の budget で復元）

## テーブル

| テーブル | 役割 |
|----------|------|
| `agent_runs` | Graph 実行 1 回分（state jsonb） |
| `agent_checkpoints` | Node 完了ごとの再開可能スナップショット |
| `agent_node_runs` | Node 単位の実行ログ |

## Intent

キーワードヒューリスティック（調査 / 根拠 / 出典 / research 等）。誤判定したら通常 Chat に戻すだけでよい段階。

## Plan ヒューリスティック

- `need_memo`: 常に true（メモ根拠を優先）
- `need_web`: 最新・公式・調べ・調査 など
- `fetch_urls`: 質問文中の `http(s)://...` を抽出

## 承認 UI

- ルート: `POST /chats/:chat_id/agent_runs/:id/approve` / `reject`
- Cable: `approval_panel` で `#research_approval` を差し替え

## 次（R3+）

- MCP `run_research_graph`
- `plan.sensitive` での条件付き承認（現在は常に Interrupt）
- 却下後の再計画ループ
