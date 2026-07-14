# Agent Graph（Research Graph）

LangGraph 型の薄い Workflow ランタイム。最初の 1 Graph は調査フロー。

## 現状（R5）

```
plan_research → recall_memos → search_web → fetch_urls → synthesize_draft
  → (plan.sensitive ?) await_approval → finalize_answer
                              └ rejected（上限まで）→ plan_research
```

各 Node は plan / 結果に応じてスキップされる（例: `need_web=false` なら search/fetch へ進まない）。

- 入口: `ChatResponseJob` がユーザー質問を `AgentGraph::ResearchIntent` で判定し、一致したら `ResearchGraphRunner` に委譲
- `synthesize_draft` は根拠からドラフトを合成（`EvidenceSynthesizer`）。**既定モデル設定**の「調査ドラフト用モデル」があればそれを優先し、失敗時は「メイン再試行」または「テンプレのみ」にフォールバック（`AppSetting.research_draft_*`）
- **条件付き承認**: `plan.sensitive=true` かつ `auto_approve` でないときだけ `await_approval` で Interrupt
- 非 sensitive: `approval=not_required` でそのまま `finalize_answer`
- 承認後: `AgentGraphResumeJob` / MCP `resume_research_graph` → `finalize_answer`
- **却下**: `replan_count < 2` なら `plan_research` へ戻る（根拠・budget は保持）。`rejection_notes` と `plan.revision_hints` を Plan / Synthesizer が参照して書き直す。上限超過で終了メッセージ
- **進捗表示**: Node 実行中は Cable `research_progress` で短いステータス行を差し替え（完了・失敗・承認待ちで消す）
- 既存 Chat tool loop はそのまま残る（意図が一致しない通常会話）
- `search_web` / `fetch_urls` は既存 `ChatTools::WebSearch` / `FetchUrl` + `WebToolBudget`

## MCP

| ツール | 役割 |
|--------|------|
| `run_research_graph` | 調査実行（`question` 必須、`chat_id` / `auto_approve` 任意） |
| `get_research_graph` | `agent_run_id` の状態取得 |
| `resume_research_graph` | `approved` / `rejected` で再開 |

実装: `Mcp::ResearchGraphTools`（Chat tool loop には載せない）。

## テーブル

| テーブル | 役割 |
|----------|------|
| `agent_runs` | Graph 実行 1 回分（state jsonb） |
| `agent_checkpoints` | Node 完了ごとの再開可能スナップショット |
| `agent_node_runs` | Node 単位の実行ログ |

## Intent

スコア付きキーワード判定（LLM なし）。

- **否定優先**: 挨拶・画像生成・「この画像は」などは Graph に入れない
- **強シグナル 1 つで採用**: 調べて / 出典 / 根拠 / research / 最新情報 等
- **弱シグナル**: 確認して・公式・ニュース等は単独では不採用。2 つ以上、または URL＋調査フレーミングで採用
- 誤判定したら通常 Chat tool loop に戻るだけでよい段階

## Plan ヒューリスティック

- `need_memo`: 常に true（メモ根拠を優先）
- `need_web`: 最新・公式・調べ・調査 など
- `fetch_urls`: 質問文中の `http(s)://...` を抽出
- `sensitive`: 保存・メモ/徒然・公開・確認してから 等（HITL 対象）

## 承認 UI

- ルート: `POST /chats/:chat_id/agent_runs/:id/approve` / `reject`
- Cable: `approval_panel` で `#research_approval` を差し替え

## 次

- MemoWrite Graph（create）: [agent-graph-memo-write.md](./agent-graph-memo-write.md)
- MemoWrite v2: `update_memo` / 楽観ロック
