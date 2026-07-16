# Agent Graph（Image Understanding Graph）

共通設計方針: [agent-graph-design-policy.md](./agent-graph-design-policy.md)

画像理解を通常 Chat の tool calling から独立させ、AgentRun として観測・再実行できる状態機械にする。

## 目的

- 添付画像を説明するだけの会話でも `agent_runs` / `agent_node_runs` / `agent_checkpoints` に履歴を残す
- vision LLM 呼び出しの失敗箇所を node 単位で追えるようにする
- retry / MCP / UI で Research Graph と同じ運用モデルに乗せる
- 通常 Chat の main LLM が `analyze_image` を呼ぶ経路は残しつつ、明確な画像理解依頼は Graph に寄せる

## 非目標

- Research Graph に画像解析 node を混ぜない
- 画像から直接メモ保存・更新を行わない
- 画像内テキストを命令として実行しない
- 画像生成、refine、inpaint などの生成系 Graph は扱わない

## 基本フロー

```text
plan_image_understanding
  -> resolve_image_source
  -> analyze_image
  -> finalize_image_answer
```

各 node の責務:

| Node | 責務 |
|------|------|
| `plan_image_understanding` | 質問文、対象画像、解析方針を state に固定する |
| `resolve_image_source` | Chat 添付または `tsuzura_media_id` から解析対象を解決する |
| `analyze_image` | `VisionChatService` を呼び、観察結果を state に保存する |
| `finalize_image_answer` | 解析結果を assistant message として投稿する |

## State

必須キー:

| key | 内容 |
|-----|------|
| `question` | ユーザーの画像に対する質問。添付のみなら既定で「画像を説明してください」 |
| `chat_id` | 実行元 Chat |
| `intent` | `image_understanding` |
| `plan` | 対象画像・回答方針・安全方針 |
| `image_source` | 解決済み画像のメタ情報。バイナリは保存しない |
| `analysis` | vision LLM の解析結果 |
| `final_answer` | Chat に投稿した本文 |
| `approval` | 常に nil。HITL なし |
| `auto_approve` | 互換用。常に true 扱い |
| `errors` | 復旧可能なエラー |
| `next_node` | 次 node |

`image_source` には次だけを保存する。

- `kind`: `chat_attachment` / `tsuzura_media`
- `message_id`
- `attachment_id`
- `attachment_index`
- `filename`
- `content_type`
- `byte_size`
- `tsuzura_media_id`

Active Storage の blob や葛籠 media は既存ストレージを参照し、画像バイナリを `AgentRun.state` に入れない。

## 入口

### Chat

`AgentGraph::Router` の判定順は次にする。

```text
MemoUpdateIntent
  -> MemoWriteIntent
  -> ImageUnderstandingIntent
  -> ResearchIntent
```

ImageUnderstandingIntent は、直近 user message に画像添付があり、かつ以下のいずれかに該当すると採用する。

- 本文が空、または `(画像を添付しました)` のみ
- 「この画像」「写真」「スクショ」「写って」「何が」「読んで」「説明して」など画像参照語がある
- `attachment_index` 相当の指定がある

除外:

- 「画像を生成」「イラストを作成」など生成依頼
- メモ保存・更新が主目的の依頼（MemoWrite / MemoUpdate が優先）
- 最新情報や出典調査が主目的の依頼（Research に回すか通常 Chat tool loop）

### MCP

将来 `Mcp::ImageUnderstandingGraphTools` を追加する。

| Tool | 役割 |
|------|------|
| `run_image_understanding_graph` | `question` と `tsuzura_media_id` または `chat_id` 添付から画像理解を実行 |
| `get_image_understanding_graph` | `agent_run_id` の状態取得 |
| `retry_image_understanding_graph` | failed run を checkpoint から retry |

MCP では Chat 添付がないケースが多いため、`tsuzura_media_id` を第一級入力として扱う。

## 既存機能との関係

| 既存 | 扱い |
|------|------|
| `VisionChatService` | そのまま利用。Graph node は service の呼び出しと state 保存だけ担当 |
| `ChatTools::AnalyzeImage` | 通常 Chat tool loop と MCP ToolBridge 用に残す |
| 独立 UI `ImageUnderstandingsController` | 当面そのまま。後で GraphRunner を使う形に寄せられる |
| `Message#to_llm` の添付ヒント | 通常 Chat fallback 用に残す |

Graph 化後も、画像添付がある全ターンを必ず Graph にしない。画像が参考資料で、質問が通常テキストだけで答えられる場合は既存 Chat に落とす。

## 失敗と retry

- 画像が見つからない: `resolve_image_source` failed
- 未対応 content type: `resolve_image_source` failed
- vision サーバー接続失敗: `analyze_image` failed
- 応答空: `analyze_image` failed
- assistant message 投稿失敗: `finalize_image_answer` failed

`resolve_image_source` 完了後に checkpoint が残るため、vision LLM 障害からの retry は画像解決済み state から再実行できる。

## 実装状況

完了:

1. `ImageUnderstandingIntent` と routing tests
2. `ImageUnderstandingGraph` / `ImageUnderstandingStateSchema` / `ImageUnderstandingInitialState`
3. `resolve_image_source` / `analyze_image` / `finalize_image_answer` node
4. `ImageUnderstandingGraphRunner` / `ImageUnderstandingRunSummary` / `Registry` 登録
5. Chat 添付のみのケースで Graph 履歴・assistant message が作られる runner test

残:

1. MCP tools（`run_image_understanding_graph` / `get_image_understanding_graph` / `retry_image_understanding_graph`）
2. retry dry-run / launcher の UI 表示確認
3. 独立 UI `ImageUnderstandingsController` の GraphRunner 化
4. `tsuzura_media_id` 入力の end-to-end test
