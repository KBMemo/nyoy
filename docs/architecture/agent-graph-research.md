# Agent Graph（Research Graph）

共通設計方針: [agent-graph-design-policy.md](./agent-graph-design-policy.md)

LangGraph 型の薄い Workflow ランタイム。最初の 1 Graph は調査フロー。

## 現状（R5）

```
plan_research → recall_memos → search_web → fetch_urls → synthesize_draft → finalize_answer
```

各 Node は plan / 結果に応じてスキップされる（例: `need_web=false` なら search/fetch へ進まない）。

- 入口: `ChatResponseJob` がユーザー質問を `AgentGraph::ResearchIntent` で判定し、一致したら `ResearchGraphRunner` に委譲
- `synthesize_draft` は LLM を使わず根拠パック（出典リスト）を内部 state に載せるだけ
- **承認なし**: そのまま `finalize_answer` へ進む（Chat / MCP 共通）
- `finalize_answer` が **チャット本モデルで最終回答を生成**（`FinalAnswerSynthesizer`）して投稿。モデルサーバー未起動・接続失敗時は run を失敗させ、`ChatErrorBroadcaster` でエラー表示（「モデルサーバーに接続できません…」）
- 最終回答生成中はストリーミングの思考を Cable `research_progress_thinking` で進捗パネル内にライブ表示（完了後は assistant メッセージの「思考」にも残る）
- 最終回答の LLM 呼び出し直前に `research_progress_prompts` でシステム／ユーザープロンプトも進捗パネルへ表示（ドラフト用プロンプト混入の確認用）
- **進捗表示**: Node 実行中は Cable `research_progress` でメッセージ末尾に進捗パネル（ラベル・モデル名・経過時間／合計時間）。完了・失敗で消す
- 既存 Chat tool loop はそのまま残る（意図が一致しない通常会話）
- `search_web` / `fetch_urls` / `recall_memos` は既存 ChatTools を呼び、実行のたびに通常 Chat と同じ **Tool Call / Tool Result** メッセージを履歴へ残す（`ToolTraceRecorder`）
- 検索結果が空のときも出典に警告を載せる。詳細な検索・取得本文はツール履歴側に任せ、最終回答は短い回答＋出典リンク中心

## MCP

| ツール | 役割 |
|--------|------|
| `run_research_graph` | 調査実行（`question` 必須、`chat_id` / `auto_approve` 任意・無視） |
| `get_research_graph` | `agent_run_id` の状態取得 |
| `resume_research_graph` | 旧 `awaiting_approval` ラン向け（新規ランでは不要） |

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
- `queries`: `SearchQueryNormalizer` で検索向けキーワード化（「調べて / 出典 / 根拠」等を落とし、「高尾山 景信山 登山道」形式に。登山道は登山ルートも併用）
- `fetch_urls`: 質問文中の `http(s)://...` を抽出
- `sensitive`: 保存・メモ/徒然・公開・確認してから 等（方針ラベル。HITL そのものは常時）

## 承認 UI

- ルート: `POST /chats/:chat_id/agent_runs/:id/approve` / `reject`
- Cable: `approval_panel` で `#research_approval` を差し替え

## 次

- MemoWrite Graph（create）: [agent-graph-memo-write.md](./agent-graph-memo-write.md)
- MemoWrite v2: `update_memo` / 楽観ロック
