# Agent Graph（MemoWrite Graph）

共通設計方針: [agent-graph-design-policy.md](./agent-graph-design-policy.md)

Research と同じ薄い Workflow ランタイム上の 2 本目。**create_memo のみ**（update は未実装）。

## フロー

```
plan_memo_write → draft_memo → await_approval → commit_memo → finalize_reply
                              └ rejected → 終了メッセージ（再計画なし）
```

- 入口: `ChatResponseJob` が `AgentGraph::MemoWriteIntent` を **Research より先** に判定
- 調査フレーミング付きの「調べてから保存」は Intent が弾き、Research に回す
- 本文ソース優先順: MCP `body` → 直近非 tool assistant → 指示文から保存フレーズを除いた残り
- **常に HITL**（`auto_approve` でない限り）。承認前に `create_memo` しない
- 承認後: `AgentGraphResumeJob` / MCP `resume_memo_write_graph` → commit → 完了メッセージ
- 冪等: state に `memo_uid` があれば `commit_memo` をスキップ
- 既存 Chat の `create_memo` ツールは残置（Intent 不一致時のフォールバック）

## MCP

| ツール | 役割 |
|--------|------|
| `run_memo_write_graph` | 新規保存（`instruction` 必須、`body` / `title` / `chat_id` / `auto_approve` 任意） |
| `get_memo_write_graph` | 状態取得 |
| `resume_memo_write_graph` | `approved` / `rejected` |

実装: `Mcp::MemoWriteGraphTools`（Chat tool loop には載せない）。MCP の `auto_approve` 既定は true。

## 承認 UI

- ルートは Research と共有: `POST .../agent_runs/:id/approve|reject`
- Cable partial: `chats/memo_write_approval`（`ApprovalBroadcaster` が `graph_name` で切替）

## 次

- `update_memo`（get_memo → draft diff → 楽観ロック）
- 承認パネル内の草案編集
