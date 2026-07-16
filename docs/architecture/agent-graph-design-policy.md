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

`ResearchGraph` / `MemoWriteGraph` / `MemoUpdateGraph` は `GraphDefinition` を継承し、`nodes` と `edges` を Graph 側に宣言する。固定遷移も条件付き遷移も、Runner ではなく Graph / Routing helper で読めるようにする。

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
| UI broadcast | `AssistantMessagePublisher` / Broadcaster に委譲し、Node は「要求」レベルに留める |
| Approval | write 系 Graph では共通 `ApprovalGate` が `interrupt` と `approval` state を扱い、resume は同じ Runner に戻す |

## 入口設計

入口は 3 層に分ける。

1. `AgentGraph::Router`
   ユーザー入力から起動すべき Graph を決める。`memo_write` を `research` より優先するなどの順序もここに集約する。

2. `GraphRunner`
   Graph 固有の初期 state を作り、共通 `RunLauncher` / `RunResumer` を呼ぶ。Chat / MCP の入力差分は `UserTurnResolver` / `McpRunRequest` に委譲し、runner 自体は state factory と Graph 実行の接続役に留める。

3. `Runner`
   Graph を 1 step ずつ進める共通実行エンジン。

補助として `AgentGraph::Registry` を置く。Graph 名から graph class、runner、summary presenter、失敗ラベル、承認 UI partial、承認 UI copy、承認/却下 notice、supersede reason、MCP resume tool を引くための一覧であり、controller / job / broadcaster / view / MCP tools に Graph 名の case 文を増やさない。

Graph 実行周辺の共通 helper:

| Helper | 役割 |
| --- | --- |
| `RunLauncher` | `AgentRun` 作成、未決 run の supersede、`Runner` 起動 |
| `RunResumer` | 承認 decision の検証、state 反映、`Runner` 再開 |
| `UserTurnResolver` | Chat 入口の直近 user 入力解決と、明示入力の履歴追加 |
| `McpRunRequest` | MCP 入口の必須文字列検証と MCP 用 Chat 解決 |
| `RunSummaryBase` | MCP summary の共通フィールド生成 |
| `Mcp::AgentGraphResponse` | MCP response、run lookup、承認待ち検証、Registry 連動 summary 生成 |

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
  -> evaluate_evidence
  -> synthesize_draft
  -> finalize_answer
```

方針:

- メモ検索を優先する
- Web 検索と URL fetch は budget 管理する
- 最終回答の前に `evaluate_evidence` で十分性を確認し、不足時は追加検索 / 追加取得へ戻す
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
- 承認待ちは共通 `ApprovalGate` で扱う
- `commit_memo` は `memo_uid` によって冪等にする
- reject は終了。自動 replan はしない
- update は扱わない。`MemoUpdate Graph` に渡す

### MemoUpdate Graph

役割は「既存メモ更新を承認付きで実行する」こと。新規保存とは別 Graph として、`get_memo` → 草案 → 承認 → `update_memo` を明示する。

基本フロー:

```text
plan_memo_update
  -> draft_memo_update
  -> await_approval
  -> commit_memo_update
  -> finalize_update_reply
```

方針:

- Chat 入口では常に承認を挟む
- MCP 入口では `memo_ref` 必須、`auto_approve` を許す
- 承認待ちは共通 `ApprovalGate` で扱う
- `plan_memo_update` で `get_memo` し、`updated_at` を state に固定する
- `commit_memo_update` は `memo_uid` によって冪等にする
- `mode` は `append` / `replace`。既定は `append`
- 対象メモが曖昧な場合は推測更新しない

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
- `evidence_review`
- `draft`
- `budget`

MemoWrite:

- `instruction`
- `source_body`
- `source_title`
- `memo_draft`
- `memo_uid`
- `memo_result`

MemoUpdate:

- `instruction`
- `memo_ref`
- `source_body`
- `source_title`
- `original_memo`
- `memo_draft`
- `memo_uid`
- `memo_result`

新しい Graph を足すときは、まずこの一覧に状態名を追加する。Node 内だけで暗黙のキーを増やさない。

## 実装の整理順

1. `AgentGraph::Router` を追加し、`ChatResponseJob` から Intent 判定を移す（完了）
2. Graph ごとの `InitialState` / `StateSchema` を追加し、初期 state を runner から分離する（完了）
3. Graph 定義に edge を持たせ、Node 内の遷移文字列を減らす（完了）
4. Approval を共通 interrupt として整理し、Research legacy approval を削る（完了）
5. Broadcaster 呼び出しを Node から薄くし、Node は state updates を主語にする（完了）
6. `summary_for` を Graph ごとの presenter に切り出す（完了）
7. `update_memo` は MemoWrite create の拡張ではなく、新しい明示フローとして設計する（完了）

## 次の優先ロードマップ

Graph の骨子は成立したため、次は新しい抽象を増やすより先に observability を固める。目的は、実行中・失敗時・再開時に「どの node が、どの state から、何を返したか」を UI から追えるようにすること。

1. `AgentRun` 詳細ページを追加する（完了）
   - チャット画面から直近の AgentRun を開ける
   - graph 名、status、current node、開始/終了時刻、error を表示する
   - まず読み取り専用にし、運用中の調査に使える状態を優先する
   - Router が Graph を起動しなかった通常チャット（例: 画像説明のみ）は AgentRun を作らない。UI は画像付き通常応答であることと「Graph 実行履歴なし」を明示し、存在しない run を擬似的に作らない

2. node 履歴を見える化する（完了）
   - `AgentNodeRun` を時系列で表示する
   - node ごとの status、elapsed、error、input/output snapshot の概要を確認できるようにする

3. state / checkpoint を確認可能にする（完了）
   - `AgentRun.state` と `AgentCheckpoint` を collapsible な JSON 表示にする
   - 再開・retry を入れる前に、checkpoint の実用性を確認する

4. LLM 呼び出し metadata を node に寄せる（完了）
   - draft / final で使った model、prompt、thinking、truncated、cache slot、token usage を `AgentNodeRun.output_snapshot` または state meta に統一的に残す
   - 通常チャットの message stats と Graph 実行 stats の見え方を揃える
   - `final_synthesis`: `source`、`model_id`、`thinking`、`system_prompt`、`user_prompt`、`llama_cache`、`usage` を保存する
   - `draft_synthesis`: 現行の `evidence_pack` 実装では LLM を呼ばないため、`source` と evidence 件数（memo/search/fetched/errors）を保存する
   - `AgentNodeRun#output_summary` は synthesis metadata を要約し、詳細 JSON を開く前に model/cache/token/evidence の概要を見せる

5. failure 時の復旧導線を作る（表示は完了）
   - failed run に、失敗 node、最後の checkpoint、再実行候補を表示する
   - failed node の error message は復旧確認パネルにも表示し、詳細 JSON を開く前に原因を読めるようにする
   - AgentRun 詳細では、復旧確認パネルから該当 node snapshot と checkpoint へ移動できる
   - failed run の該当 node snapshot と最後の checkpoint は初期展開し、失敗情報をすぐ読めるようにする
   - チャット画面の直近 AgentRun 履歴でも、failed run は失敗 node、最後の checkpoint、エラー要約を表示する
   - 実際の retry ボタンは、失敗パターンを観測してから追加する

6. retry / resume API を検討する
   - 任意 node からの再実行、最後の checkpoint からの再開、failed run の複製実行を比較する
   - 副作用 node は冪等キーがある場合だけ自動 retry 対象にする

   方針案:

   - **既存 run の巻き戻しはしない。** `Runner` は現在の `AgentRun.state` と `current_node` を前進させる実行器であり、node 履歴・checkpoint 履歴を保持したまま巻き戻すと監査ログの意味が曖昧になる。
   - **failed run の retry は「複製 run」として作る。** 元 run は failed のまま保存し、最後の checkpoint state を初期 state とする新しい `AgentRun` を作る。新 run の state には `retry_of_agent_run_id`、`retry_from_checkpoint_id`、`retry_from_node` を残す。
   - **複製 run の lineage を UI に表示する。** AgentRun 詳細とチャット画面の直近履歴では、retry 元 run、起点 checkpoint、起点 node を表示し、元 run の監査ログへ戻れるようにする。元 run 側にも retry 子 run の一覧または件数を表示し、双方向に辿れるようにする。
   - **再開 node は checkpoint の次 node を使う。** checkpoint は node 完了後の state なので、同じ node を再実行すると副作用が二重になる可能性がある。次 node は `graph.next_node_for(checkpoint.node_name, checkpoint.state)` で求める。失敗 node そのものを再実行したい場合は、該当 node が副作用なし、または冪等キーで保護されていることを UI/API で明示条件にする。
   - **write 系 Graph は既定で自動 retry しない。** `commit_memo` / `commit_memo_update` は `memo_uid` による冪等ガードを持つが、外部 API の部分成功があり得るため、まずは読み取り専用の復旧情報表示に留める。retry API を開く場合も、承認済み state と冪等キーの有無を検証する。
   - **Research Graph は最初の対象にしやすい。** Web 検索・URL 取得・最終回答生成は失敗しても保存系副作用が少ない。ただし `ToolTraceRecorder` による tool message は増えるため、複製 run であることを state と UI に表示する。
   - **MCP/Chat UI 共通の service を作る。** `AgentGraph::RunRetryPlanner` が可否・起点 checkpoint・次 node・理由を返し、実行する場合は `AgentGraph::RunRetryLauncher` が複製 run を作る。controller / MCP tool はこの service の結果だけを見る。
   - **最初の実装は Research Graph の複製 retry に限定する。** `AgentGraph::RunRetryPlanner` による dry-run を failed run 詳細で表示し、「retry 可能性」「起点 checkpoint」「次 node」「ブロック理由」を確認できるようにする。`AgentGraph::RunRetryLauncher` は複製 run を作成し、UI の retry ボタンと MCP `retry_research_graph` は `retryable` な dry-run の場合だけ実行できる。write 系 Graph は引き続き保留表示に留める。

## 判断基準

迷ったら次で判断する。

- その値は再開に必要か。必要なら state、不要なら UI 側の一時値。
- その処理は状態変換か。状態変換なら Node、起動判定なら Router、実行制御なら Runner。
- その副作用は再実行されても安全か。安全でないなら state に冪等キーを残す。
- その分岐は Graph を読む人に見えるべきか。見えるべきなら Edge / Routing に出す。
- その Graph は write action を含むか。含むなら HITL と冪等性を先に設計する。
