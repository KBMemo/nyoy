# ImageUnderstanding Graph 実機確認 Runbook

対象: ImageUnderstanding Graph の UI / Chat / MCP / retry 経路を実機で確認する。

関連設計: [Agent Graph Image Understanding](./architecture/agent-graph-image-understanding.md)

## 前提

- Nyoy が起動している
- `vision_llama` の `ServiceConnection` が有効
- vision LLM が画像解析できる状態
- MCP を確認する場合は `MCP_API_TOKEN` が設定済み
- 葛籠経路を確認する場合は `tsuzura` の `ServiceConnection` が有効

起動例:

```bash
bin/dev
```

ローカル開発の MCP 接続先と token:

```bash
export NYOY_MCP_URL="${NYOY_MCP_URL:-http://127.0.0.1:3109/mcp}"
export MCP_API_TOKEN="your-token"
```

MCP ツール確認:

```bash
bin/mcp-list-tools
```

期待:

- `run_image_understanding_graph`
- `get_image_understanding_graph`
- `retry_image_understanding_graph`

## 1. 独立 UI 経路

目的: `/image_understandings/new` のアップロードが AgentRun 履歴に残ることを確認する。

手順:

1. ブラウザで `/image_understandings/new` を開く
2. PNG / JPEG / WebP の画像を選択する
3. プロンプトに `この画像を説明して` を入力する
4. 送信する
5. 回答欄に画像説明が表示されることを確認する
6. 回答下の AgentRun リンクを開く

期待:

- `agent_runs.graph_name` は `image_understanding`
- status は `completed`
- node 履歴に次が順に表示される
  - `plan_image_understanding`
  - `resolve_image_source`
  - `analyze_image`
  - `finalize_image_answer`
- `state.image_source.kind` は `chat_attachment`
- `state.final_answer` と表示された回答が一致する

## 2. Chat 添付経路

目的: Chat で画像理解 intent が選ばれ、通常の Chat tool loop ではなく Graph として実行されることを確認する。

手順:

1. Chat を開く
2. 画像を添付する
3. 本文を空、または `この画像を説明して` にして送信する
4. 回答が返るまで待つ
5. AgentRun / node 履歴を開く

期待:

- ImageUnderstanding Graph の AgentRun が作成される
- `state.question` は本文、または添付のみの場合は `画像を説明してください`
- `state.image_source.kind` は `chat_attachment`
- assistant message が通常の回答として Chat に投稿される

除外確認:

- `画像を生成して` のような生成依頼は ImageUnderstanding Graph に入れない
- メモ保存・更新が主目的の依頼は MemoWrite / MemoUpdate が優先される

## 3. MCP `tsuzura_media_id` 経路

目的: Chat 添付を持たない MCP クライアントから、葛籠 media を指定して解析できることを確認する。

`tsuzura_media_id` は、葛籠に保存済みの画像 media ID を使う。Chat 添付から確認する場合は Rails console で取得できる。

```bash
bin/rails console
```

```ruby
ActiveStorage::Attachment
  .where(record_type: "Message", name: "attachments")
  .order(id: :desc)
  .find { |attachment| attachment.metadata["tsuzura_media_id"].present? }
  &.metadata
  &.fetch("tsuzura_media_id")
```

HTTP MCP 例:

```bash
bin/mcp-call-tool run_image_understanding_graph \
  '{"question":"この画像を説明して","tsuzura_media_id":"01J..."}'
```

既定では MCP の `result.content[0].text` に入っている Graph payload を展開して表示する。外側の JSON-RPC レスポンスを確認したい場合は `--raw` を付ける。

返却された `agent_run_id` を控える。UI で確認する場合は、同じ payload の `agent_run_path` を開く。

```bash
bin/mcp-call-tool get_image_understanding_graph '{"agent_run_id":123}'
```

期待:

- `status` は `completed`
- `image_source.kind` は `tsuzura_media`
- `image_source.tsuzura_media_id` は指定値
- `analysis` / `final_answer` が空ではない
- node 履歴に `analyze_image` が含まれる
- `agent_run_path` から AgentRun 詳細を開ける

## 4. MCP 入力不足

目的: MCP で画像ソースを渡さない場合に、実行失敗が AgentRun として観測できることを確認する。

```bash
bin/mcp-call-tool run_image_understanding_graph '{"question":"この画像を説明して"}'
```

期待:

- MCP レスポンス自体は tool 実行結果として返る
- payload の `status` は `failed`
- `error_message` は画像不足を示す
- `errors[0].code` は `IMAGE_SOURCE_MISSING`
- node 履歴は `resolve_image_source` までで止まる

## 5. vision 障害時 retry

目的: vision LLM 障害で `analyze_image` failed になった run を、復旧後に checkpoint から retry できることを確認する。

手順:

1. vision LLM または `vision_llama` 接続先を停止する
2. Chat 添付経路、または MCP `tsuzura_media_id` 経路で画像理解を実行する
3. failed run の `agent_run_id` を控える
4. node 履歴で `resolve_image_source` が completed、`analyze_image` が failed であることを確認する
5. vision LLM を復旧する
6. retry を実行する

HTTP MCP retry 例:

```bash
bin/mcp-call-tool retry_image_understanding_graph '{"agent_run_id":123}'
```

期待:

- retry 元 run は `failed` のまま残る
- 新しい AgentRun が作成される
- 新 run の `state.retry_of_agent_run_id` は元 run の id
- 新 run の `state.retry_from_node` は `resolve_image_source`
- 新 run は `completed`
- Chat / UI では retry 後の回答が確認できる

## 6. retry 不可の確認

目的: checkpoint がない failed run は retry できないことを確認する。

再現しやすい例:

1. MCP 入力不足の確認を実行する
2. 返却された `agent_run_id` で `retry_image_understanding_graph` を呼ぶ

期待:

- MCP レスポンスは error
- error message は `成功済み checkpoint がありません`
- 新しい retry run は作られない

## 確認後の記録

実機確認後、最低限次を記録する。

- 確認日時
- 環境（development / production）
- vision model / endpoint
- UI 経路の AgentRun id
- Chat 添付経路の AgentRun id
- MCP `tsuzura_media_id` 経路の AgentRun id
- retry 元 AgentRun id と retry 後 AgentRun id
- 失敗した場合の node 名、`error_message`、復旧内容

記録テンプレート:

```markdown
## ImageUnderstanding Graph 実機確認

- 確認日時:
- 環境:
- Nyoy URL:
- vision model / endpoint:
- `vision_llama` ServiceConnection:
- `tsuzura` ServiceConnection:
- 使用画像:
- `tsuzura_media_id`:

| 経路 | AgentRun | 結果 | 確認内容 |
|------|----------|------|----------|
| 独立 UI |  |  | AgentRun リンク / node 履歴 / image_source |
| Chat 添付 |  |  | Graph 選択 / assistant message / image_source |
| MCP `tsuzura_media_id` |  |  | `completed` / `agent_run_path` / `image_source.kind=tsuzura_media` |
| MCP 入力不足 |  |  | `failed` / `IMAGE_SOURCE_MISSING` / retry 不可 |
| vision 障害 retry | 元:  / retry:  |  | `analyze_image` failed / `retry_from_node=resolve_image_source` / retry run completed |

補足:

- 失敗 node:
- `error_message`:
- 復旧内容:
- 次回確認事項:
```

## トラブルシュート

`run_image_understanding_graph` が tools/list に出ない:

- `MCP_API_TOKEN` が設定されているか確認する
- `bin/mcp-list-tools` を実行する
- `Mcp::ToolCatalog` に ImageUnderstanding Graph tools が含まれることを確認する

`tsuzura_media_id` 経路で失敗する:

- `tsuzura` の `ServiceConnection` が有効か確認する
- media ID が画像を指しているか確認する
- 葛籠 API からの download の `content_type` が `image/png` / `image/jpeg` / `image/webp` のいずれかか確認する

retry できない:

- failed run であることを確認する
- `resolve_image_source` など成功済み node と checkpoint があることを確認する
- `analyze_image` 以前で失敗している場合、画像ソース解決前なので retry ではなく入力を直して再実行する
