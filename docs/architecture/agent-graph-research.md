# Agent Graph（Research Graph）

LangGraph 型の薄い Workflow ランタイム。最初の 1 Graph は調査フロー。

## 現状（R1）

```
plan_research → recall_memos → search_web → fetch_urls → finalize_answer
```

各 Node は plan / 結果に応じてスキップされる（例: `need_web=false` なら search/fetch へ進まない）。

- 入口: `ChatResponseJob` がユーザー質問を `AgentGraph::ResearchIntent` で判定し、一致したら `ResearchGraphRunner` に委譲
- 既存 Chat tool loop はそのまま残る（意図が一致しない通常会話）
- Leaf LLM（`FinalizeAnswer`）は RubyLLM 直叩き。ツール付き `chat.to_llm` は使わない
- `search_web` / `fetch_urls` は既存 `ChatTools::WebSearch` / `FetchUrl` + `WebToolBudget`（state の budget で復元）

## テーブル

| テーブル | 役割 |
|----------|------|
| `agent_runs` | Graph 実行 1 回分（state jsonb） |
| `agent_checkpoints` | Node 完了ごとの再開可能スナップショット |
| `agent_node_runs` | Node 単位の実行ログ |

## Intent

キーワードヒューリスティック（調査 / 根拠 / 出典 / research 等）。誤判定したら通常 Chat に戻すだけでよい段階。

## Plan ヒューリスティック（R1）

- `need_memo`: 常に true（メモ根拠を優先）
- `need_web`: 最新・公式・調べ・調査 など
- `fetch_urls`: 質問文中の `http(s)://...` を抽出

## 次（R2+）

- `SynthesizeDraft` と承認 Interrupt
- MCP `run_research_graph`
