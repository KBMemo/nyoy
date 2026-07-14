# Agent Graph（Research Graph R0）

LangGraph 型の薄い Workflow ランタイム。最初の 1 Graph は調査フロー。

## 現状（R0）

```
plan_research → recall_memos → finalize_answer
```

- 入口: `ChatResponseJob` がユーザー質問を `AgentGraph::ResearchIntent` で判定し、一致したら `ResearchGraphRunner` に委譲
- 既存 Chat tool loop はそのまま残る（意図が一致しない通常会話）
- Leaf LLM（`FinalizeAnswer`）は RubyLLM 直叩き。ツール付き `chat.to_llm` は使わない

## テーブル

| テーブル | 役割 |
|----------|------|
| `agent_runs` | Graph 実行 1 回分（state jsonb） |
| `agent_checkpoints` | Node 完了ごとの再開可能スナップショット |
| `agent_node_runs` | Node 単位の実行ログ |

## Intent（R0）

キーワードヒューリスティック（調査 / 根拠 / 出典 / research 等）。誤判定したら通常 Chat に戻すだけでよい段階。

## 次（R1+）

- `search_web` / `fetch_urls` Node
- `SynthesizeDraft` と承認 Interrupt
- MCP `run_research_graph`
