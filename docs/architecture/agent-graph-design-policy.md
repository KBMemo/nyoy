# Agent Graph 設計方針

LangGraph の思想を Rails 内に持ち込む目的は、「LLM が自由に振る舞うチャットループ」を増やすことではなく、AI agent を観測可能で再開可能な状態機械として扱うことにある。

このアプリでは `AgentRun.state` を唯一の実行状態、Node を状態変換、Graph を遷移定義、Runner を実行エンジンとして固定する。副作用は必要最小限に閉じ込め、どの入力状態からどの出力状態へ進んだかを `agent_node_runs` と `agent_checkpoints` で追える形を優先する。

## 目標

- Graph の流れをファイル 1 つで読める
- Node は「状態を読んで、更新と次ノードを返す」単位に保つ
- 承認待ち、失敗、キャンセル、再開を明示的な状態として扱う
- チャット UI、MCP、ジョブ入口が同じ Graph 実行モデルを使う
- ツール呼び出し、LLM 呼び出し、メモ保存などの副作用を監査できる

## 非目標

- LangGraph 本体を Ruby に完全移植しない
- LLM の tool calling だけで長い業務フローを組まない
- Graph ごとに独自 runner / 独自 checkpoint / 独自 approval 実装を増やさない
- `AgentRun.state` に UI 表示都合だけの一時値を無制限に詰め込まない

## 基本モデル

### Graph

Graph は状態機械の宣言であり、次を持つ。

- `name`
- `start_node`
- `state_schema`
- `nodes`
- `edges`
- `interrupts`

現状の `ResearchGraph` / `MemoWriteGraph` は `nodes` 登録だけを持っている。今後は遷移を Node 内の文字列分岐に閉じ込めず、Graph 側で読めるように寄せる。

推奨形:

```ruby
edge "plan_research", to: ->(state) { ResearchRouting.after_plan(state["plan"]) }
edge "recall_memos", to: ->(state) { ResearchRouting.after_recall(state) }
edge "finalize_answer", end: true
```

### State

State は Graph の唯一のメモリである。Node 間の受け渡しは原則として `AgentRun.state` に集約する。

State は次の層に分ける。

- `input`: ユーザー入力、MCP 入力、起動時パラメータ
- `plan`: 実行計画、必要な証拠、承認方針
- `working`: 検索結果、取得ページ、草案などの中間生成物
- `decisions`: approval、routing などの明示的判断
- `outputs`: 最終回答、作成した memo uid、assistant message id
- `errors`: 復旧可能なエラーの配列
- `meta`: budget、model、timing、互換用フラグ

Graph ごとに初期 state を factory に切り出し、Runner 起動前に形をそろえる。

### Node

Node は小さな状態変換である。

Node がやること:

- state を読む
- 必要な外部サービスを 1 種類だけ呼ぶ
- `NodeResult` で `updates`、`goto`、`interrupt`、`error` を返す

Node が避けること:

- 複数の責務をまとめる
- 入口判定を持つ
- Graph 全体の状態名を勝手に増やす
- UI partial や Cable の詳細を知る
- 直接 `AgentRun` を大きく更新する

副作用が必要な Node は、冪等キーを state に残す。例: `memo_uid` があれば `commit_memo` は再実行しない。

### Edge

Edge は「次にどこへ進むか」の決定である。LangGraph 的には Node と Edge を分けて読むことが重要なので、遷移ロジックは Graph / Routing に寄せる。

許容:

- Node が固定の次ノードを返す
- Routing helper が state から次ノードを返す

避ける:

- 複数 Node に同じ遷移条件を重複させる
- Node 内で Graph 全体の手順を知りすぎる

### Runner

Runner は Graph 実行の共通エンジンである。

Runner の責務:

- `AgentRun` を running にする
- current node を実行する
- input / output snapshot を保存する
- state を merge して checkpoint を作る
- `interrupt` / `failed` / `completed` / `cancelled` を確定する

Runner が持たない責務:

- Intent 判定
- Graph 固有の初期 state 作成
- UI 文言生成
- MCP 用 summary 生成

## 副作用の扱い

副作用は state transition の外にあるが、Graph の一部として監査できる必要がある。

| 種類 | 方針 |
| --- | --- |
| LLM 呼び出し | Synthesizer / service に切り出し、Node は結果を state に保存する |
| Tool 呼び出し | 既存 `ChatTools` を使い、`ToolTraceRecorder` で通常チャットと同じ履歴を残す |
| DB 書き込み | 冪等キーを state に保存し、再開時の二重実行を防ぐ |
| UI broadcast | 原則 Broadcaster に委譲し、Node は「要求」レベルに留める |
| Approval | `interrupt` と `approval` state で表現し、resume は同じ Runner に戻す |

## 入口設計

入口は 3 層に分ける。

1. `AgentGraph::Router`
   ユーザー入力から起動すべき Graph を決める。`memo_write` を `research` より優先するなどの順序もここに集約する。

2. `GraphRunner`
   Graph 固有の初期 state を作り、共通 `Runner` を呼ぶ。Chat / MCP の入力差分をここで吸収する。

3. `Runner`
   Graph を 1 step ずつ進める共通実行エンジン。

`ChatResponseJob` は最終的に次の程度に薄くする。

```ruby
if (decision = AgentGraph::Router.route(chat))
  run = decision.runner.call(chat, **decision.args)
  handle_graph_failure(run) if run.failed?
  return
end
```

## Graph ごとの方針

### Research Graph

役割は「根拠を集めて回答する」こと。保存や更新などの write action は担当しない。

基本フロー:

```text
plan_research
  -> recall_memos?
  -> search_web?
  -> fetch_urls?
  -> synthesize_draft
  -> finalize_answer
```

方針:

- メモ検索を優先する
- Web 検索と URL fetch は budget 管理する
- 取得失敗は即 failed ではなく `errors` と出典警告に残す
- 最終回答 LLM の失敗は run failed にする
- Research は原則 HITL しない
- 保存や投稿を含む要求は MemoWrite / 将来の Write Graph に渡す

### MemoWrite Graph

役割は「メモ作成を承認付きで実行する」こと。調査は担当しない。

基本フロー:

```text
plan_memo_write
  -> draft_memo
  -> await_approval
  -> commit_memo
  -> finalize_reply
```

方針:

- Chat 入口では常に承認を挟む
- MCP 入口では `auto_approve` を許す
- `commit_memo` は `memo_uid` によって冪等にする
- reject は終了。自動 replan はしない
- update_memo は create と別 Graph か、明示的な subgraph として扱う

## 状態名の標準

共通:

- `intent`
- `chat_id`
- `approval`
- `auto_approve`
- `errors`
- `assistant_message_id`
- `final_answer`

Research:

- `question`
- `plan.need_memo`
- `plan.need_web`
- `plan.queries`
- `plan.fetch_urls`
- `memo_context`
- `search_results`
- `fetched_pages`
- `draft`
- `budget`

MemoWrite:

- `instruction`
- `source_body`
- `source_title`
- `memo_draft`
- `memo_uid`
- `memo_result`

新しい Graph を足すときは、まずこの一覧に状態名を追加する。Node 内だけで暗黙のキーを増やさない。

## 実装の整理順

1. `AgentGraph::Router` を追加し、`ChatResponseJob` から Intent 判定を移す（完了）
2. Graph ごとの `InitialState` / `StateSchema` を追加し、初期 state を runner から分離する（完了）
3. Graph 定義に edge を持たせ、Node 内の遷移文字列を減らす（進行中）
4. Approval を共通 interrupt として整理し、Research legacy approval を削る（完了）
5. Broadcaster 呼び出しを Node から薄くし、Node は state updates を主語にする
6. `summary_for` を Graph ごとの presenter に切り出す
7. `update_memo` は MemoWrite create の拡張ではなく、新しい明示フローとして設計する

## 判断基準

迷ったら次で判断する。

- その値は再開に必要か。必要なら state、不要なら UI 側の一時値。
- その処理は状態変換か。状態変換なら Node、起動判定なら Router、実行制御なら Runner。
- その副作用は再実行されても安全か。安全でないなら state に冪等キーを残す。
- その分岐は Graph を読む人に見えるべきか。見えるべきなら Edge / Routing に出す。
- その Graph は write action を含むか。含むなら HITL と冪等性を先に設計する。
