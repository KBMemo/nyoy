# Memo RAG Webhook 設計

## 目的

徒然のメモ作成・更新・削除を Nyoy へ低遅延で通知し、`PromptKnowledgeChunk(source=memo)` を速やかに re-embed / delete する。

既存の `MemoKnowledgeIngestJob` による checkpoint 定期同期は残す。Webhook は即時化の補助であり、欠落・順序入れ替わり・一時障害からの最終的な収束は `export` / `export/deletions` に任せる。

## 現状

- Nyoy は `GET /api/v1/memos/export` を `MemoKnowledgeIngestJob` で取り込み、`AppSetting.memo_knowledge_last_ingested_at` を checkpoint にする。
- 削除は `GET /api/v1/memos/export/deletions` の tombstone feed で同期する。
- 初回全件取込では export に存在しない stale chunk を削除する。
- 徒然 API は Bearer token の account に対する `MemoPolicy::Scope` を通す。Nyoy RAG は `ServiceConnection(kbmemo)` の token account から見える committed メモだけを対象にする。

## 方針

1. **webhook は account scoped**
   - event には `account_id` と `memo_uid` を含める。
   - Nyoy 側は現状単一 `kbmemo` 接続の token account を前提にする。将来 multi account RAG にする場合は `account_id` ごとに接続・chunk namespace を分ける。

2. **payload は最小**
   - `created` / `updated` は UID と timestamp だけを送る。
   - Nyoy は webhook payload 本文を正本にせず、`TsurezureClient#get_memo(uid)` で最新本文を取得して embed する。
   - `deleted` は UID だけで `MemoKnowledgeIngester#delete_memo!` を実行する。

3. **冪等**
   - `event_id` を必須にする。
   - Nyoy は `memo_rag_webhook_events(event_id)` を記録し、同じ event は二重処理しない。
   - `updated_at` が古い webhook は無害にする。chunk metadata の `memo_updated_at` より古ければ skip 可能。

4. **署名検証**
   - 徒然は共有 secret で HMAC-SHA256 を付ける。
   - Nyoy は `X-KBMemo-Webhook-Timestamp` と `X-KBMemo-Signature` を検証する。
   - 署名対象は `timestamp + "." + raw_body`。
   - 許容 clock skew は 5 分。

5. **非同期処理**
   - Nyoy controller は検証と event record 作成だけ行い、`MemoKnowledgeWebhookJob` を enqueue して `202 Accepted` を返す。
   - job が `created` / `updated` / `deleted` を処理する。
   - 失敗時は Solid Queue retry に任せる。

## HTTP 契約

### 徒然 -> Nyoy

`POST /webhooks/kbmemo/memos`

Headers:

```http
Content-Type: application/json
X-KBMemo-Webhook-Timestamp: 2026-07-17T12:34:56.000000Z
X-KBMemo-Signature: sha256=<hex hmac>
```

Payload:

```json
{
  "event_id": "01KXQ...",
  "event_type": "memo.updated",
  "account_id": 1,
  "memo_uid": "01J8X2K3M4N5P6Q7R8S9T0UVWX",
  "memo_id": 42,
  "occurred_at": "2026-07-17T12:34:56Z",
  "memo_updated_at": "2026-07-17T12:34:55Z"
}
```

Event types:

| event_type | Nyoy action |
|------------|-------------|
| `memo.created` | `get_memo(uid)` -> `MemoKnowledgeIngester#ingest!` |
| `memo.updated` | `get_memo(uid)` -> `MemoKnowledgeIngester#ingest!` |
| `memo.deleted` | `MemoKnowledgeIngester#delete_memo!(uid)` |

Response:

```json
{
  "accepted": true,
  "event_id": "01KXQ..."
}
```

## Nyoy 実装案

Status: **受信側は実装済み**（`POST /webhooks/kbmemo/memos`、HMAC 検証、event table、`MemoKnowledgeWebhookJob`）。
残りは徒然側の delivery job / signer / `Memo` callback。

### 設定

- `MEMO_RAG_WEBHOOK_SECRET`
- `MEMO_RAG_WEBHOOK_ENABLED=true`

将来 UI 管理する場合は `ServiceConnection(kbmemo).settings["webhook_secret"]` に移せるが、初期は secret env のほうが運用が単純。

### DB

`memo_rag_webhook_events`

| column | type | note |
|--------|------|------|
| `event_id` | string | unique |
| `event_type` | string | `memo.created` 等 |
| `account_id` | bigint | 徒然 account |
| `memo_uid` | string | ULID |
| `memo_id` | bigint | optional |
| `memo_updated_at` | datetime | optional |
| `occurred_at` | datetime | event timestamp |
| `status` | string | `pending` / `processing` / `completed` / `failed` / `skipped` |
| `error_message` | text | failed reason |
| `processed_at` | datetime | complete/skipped time |

### Controller

- `Webhooks::Kbmemo::MemosController#create`
- `ActionController::API` ベース
- raw body で署名検証
- event_type / memo_uid / event_id を validation
- duplicate event は `200 OK` または `202 Accepted` で冪等応答

### Job

`MemoKnowledgeWebhookJob.perform(event_id)`

- pending event を `processing` にする。
- `memo.deleted`:
  - `MemoKnowledgeIngester#delete_memo!(memo_uid)`
  - status completed
- `memo.created` / `memo.updated`:
  - `TsurezureClient#get_memo(memo_uid)`
  - レスポンスが `draft=true` なら `delete_memo!` して skipped/completed。Nyoy RAG は committed のみ対象。
  - token account から見えない / 404 の場合は `delete_memo!` して skipped。visibility 変更で見えなくなったケースを収束させる。
  - `memo_updated_at` が既存 chunk metadata より古ければ skipped。
  - `MemoKnowledgeIngester#ingest!(memo)`
  - status completed

## 徒然 実装

### 設定

- `NYOY_MEMO_WEBHOOK_URL`
- `NYOY_MEMO_WEBHOOK_SECRET`
- `NYOY_MEMO_WEBHOOK_ENABLED=true`

### 発火点

site 側実装:

- `NyoyMemoWebhookJob`
- `NyoyMemoWebhook::Client`
- `NyoyMemoWebhook::Signature`
- `Memo` の `after_commit` / `after_destroy_commit`

`Memo` の callback:

- create/update: committed メモのみ送る。
  - `file_committed_at` が nil の draft 保存は送らない。
  - draft から committed になったら `memo.updated` として送る。Nyoy 側は created / updated とも get+ingest なので処理は同じ。
- destroy: `memo.deleted` を送る。
  - 既存 `MemoDeletionRecord` 作成後に UID が残るので同じ情報を使う。

`after_commit` 内で直接 HTTP は叩かず、`NyoyMemoWebhookJob` を enqueue する。

### payload 生成

- `event_id`: UUID
- `occurred_at`: `Time.current.utc.iso8601`
- `memo_updated_at`: memo の `updated_at.utc.iso8601`
- `account_id`, `memo_id`, `memo_uid`

### retry

- job retry は指数 backoff。
- Nyoy 側が duplicate を許容するため、徒然側 retry は安全。
- 長期障害時は Nyoy の checkpoint 定期同期で最終的に収束する。

## セキュリティ

- HMAC secret は Nyoy MCP token とは分ける。
- timestamp skew を検証して replay を抑制する。
- Nyoy は webhook payload の本文を信頼せず、既存 `kbmemo` ServiceConnection token で徒然 API から正本を取り直す。
- visibility 変更で token account から見えなくなった場合、Nyoy は該当 chunk を削除する。

## 運用

- 既存の `MemoKnowledgeIngestJob` は削除しない。
- recurring schedule は残す。Webhook は低遅延化、定期 job は修復・監査用。
- webhook 処理件数、失敗件数、最終処理時刻を log / status UI に出すとよい。

## development E2E 確認手順

前提:

- Nyoy は `http://localhost:3109` で起動する
- site は通常の development 環境で起動する
- Nyoy の `kbmemo` ServiceConnection は site API を読める token を持つ
- `MEMO_RAG_WEBHOOK_SECRET` と `NYOY_MEMO_WEBHOOK_SECRET` は同じ値にする

Nyoy 側:

```bash
MEMO_RAG_WEBHOOK_ENABLED=true \
MEMO_RAG_WEBHOOK_SECRET=dev-webhook-secret \
bin/rails server -p 3109
```

site 側:

```bash
NYOY_MEMO_WEBHOOK_ENABLED=true \
NYOY_MEMO_WEBHOOK_URL=http://localhost:3109/webhooks/kbmemo/memos \
NYOY_MEMO_WEBHOOK_SECRET=dev-webhook-secret \
bin/rails server
```

確認 1: update

1. site で committed メモ本文を更新する
2. site job が `NyoyMemoWebhookJob` を実行する
3. Nyoy console で次を確認する

```ruby
event = MemoRagWebhookEvent.order(id: :desc).first
[event.event_type, event.status, event.memo_uid, event.error_message]
MemoKnowledgeChunk.where(memo_uid: event.memo_uid).count
```

期待:

- `event_type` は `memo.updated`
- `status` は `completed`
- chunk が存在し、`metadata["memo_updated_at"]` が更新後時刻になる

確認 2: delete

1. site で同じメモを削除する
2. Nyoy console で同じ `memo_uid` の event と chunk を確認する

```ruby
event = MemoRagWebhookEvent.where(memo_uid: "対象UID").order(id: :desc).first
[event.event_type, event.status, event.error_message]
MemoKnowledgeChunk.where(memo_uid: event.memo_uid).count
```

期待:

- `event_type` は `memo.deleted`
- `status` は `completed`
- chunk count は `0`

確認 3: draft

1. site で `file_committed_at` が nil の draft メモを保存する
2. `NyoyMemoWebhookJob` が enqueue されないことを確認する

補足:

- site 側の job 実行方式が async でない場合は Solid Queue worker を起動する
- webhook が失敗した場合、Nyoy 側は `MemoRagWebhookEvent.status=failed` と `error_message` に残す
- 取りこぼし・長期障害時は既存 `MemoKnowledgeIngestJob` の checkpoint 同期で収束する

## 確認ログ

### 2026-07-17 development E2E

環境:

- Nyoy: `http://127.0.0.1:3110`（`MEMO_RAG_WEBHOOK_ENABLED=true` / `SOLID_QUEUE_IN_PUMA=true`）
- site: `http://localhost:3000`
- webhook URL: `http://127.0.0.1:3110/webhooks/kbmemo/memos`
- 対象 UID: `01KXQK2N4SPM1YWWAPJ8PDZX3X`（確認後 site 側で削除済み）

結果:

| 操作 | event_type | status | chunk |
|---|---|---|---|
| create | `memo.created` | `completed` | `PromptKnowledgeChunk` 2 件作成 |
| update | `memo.updated` | `completed` | `metadata["memo_updated_at"]` が更新後時刻へ反映 |
| delete | `memo.deleted` | `completed` | chunk count `0` |

発見と対応:

- site 送信側が `X-KBMemo-Webhook-Timestamp` に epoch 秒を送っており、Nyoy 受信側の ISO8601 検証で 401 になった。
- site 側 `NyoyMemoWebhook::Client` を UTC ISO8601 (`iso8601(6)`) に修正し、再確認で 202 / completed まで通過した。

## 実装順

1. ~~Nyoy: webhook event table / verifier / controller / job~~
2. ~~Nyoy: `MemoKnowledgeIngester` に「既存 memo_updated_at より古いか」の helper を追加~~
3. ~~徒然: webhook delivery job / signer / Memo after_commit enqueue~~
4. ~~徒然: settings env と docs~~
5. ~~development で create/update/delete の実機確認~~
6. 本番投入後も `MemoKnowledgeIngestJob` の定期同期ログで収束を確認

## 未決

- multi account RAG を行うか。現状は単一 `kbmemo` ServiceConnection token account の視界を Nyoy RAG に取り込む。
- webhook delivery の管理 UI を作るか。初期は env 設定で十分。
