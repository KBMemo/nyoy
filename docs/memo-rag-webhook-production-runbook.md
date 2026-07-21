# Memo RAG Webhook 本番有効化 Runbook

## 目的

徒然（kbmemo.net）のメモ作成・更新・削除を Nyoy へ webhook 通知し、`PromptKnowledgeChunk(source=memo)` を低遅延で更新する。

Webhook は即時化の経路であり、既存の `MemoKnowledgeIngestJob` checkpoint 同期は修復・監査用として残す。

## 前提

- Nyoy と徒然の本番に、memo RAG webhook 受信・送信実装が deploy 済み。
- Nyoy の `kbmemo` ServiceConnection が `https://kbmemo.net/api/v1` を読める。
- Nyoy は `SOLID_QUEUE_IN_PUMA=true` などで `MemoKnowledgeWebhookJob` を実行できる。
- 徒然は `NyoyMemoWebhookJob` を実行できる。
- 共有 secret は Nyoy MCP token とは別に生成する。

```bash
openssl rand -hex 32
```

以後、この値を `<shared-secret>` とする。

## 設定

### Nyoy

`~/sites/nyoy/.env.production` に追加する。

```bash
MEMO_RAG_WEBHOOK_ENABLED=true
MEMO_RAG_WEBHOOK_SECRET=<shared-secret>
```

Kamal 運用の場合、`config/deploy.yml` の `env.secret` に `MEMO_RAG_WEBHOOK_SECRET` は登録済み。`MEMO_RAG_WEBHOOK_ENABLED=true` は clear env に追加する。

### 徒然

`/home/kensei/sites/kbmemo/.env.production` に追加する。

```bash
NYOY_MEMO_WEBHOOK_ENABLED=true
NYOY_MEMO_WEBHOOK_URL=https://nyoy.kbmemo.net/webhooks/kbmemo/memos
NYOY_MEMO_WEBHOOK_SECRET=<shared-secret>
```

Kamal 運用の場合、`config/deploy.yml` の `env.secret` に `NYOY_MEMO_WEBHOOK_SECRET` は登録済み。`NYOY_MEMO_WEBHOOK_ENABLED` と `NYOY_MEMO_WEBHOOK_URL` は clear env のコメントを外す。

## 有効化手順

1. Nyoy と徒然の deploy 済み revision を確認する。

```bash
cd ~/sites/nyoy
git rev-parse --short HEAD

cd /home/kensei/sites/kbmemo
git rev-parse --short HEAD
```

2. Nyoy 側を先に有効化し、再起動または deploy する。

```bash
cd ~/sites/nyoy
$EDITOR .env.production
bin/deploy
curl -fsS https://nyoy.kbmemo.net/up
```

3. Nyoy の queue が動いていることを確認する。

```bash
journalctl --user -u nyoy -n 100 --no-pager
```

4. 徒然側を有効化し、再起動または deploy する。

```bash
cd /home/kensei/sites/kbmemo
$EDITOR .env.production
bin/deploy
curl -fsS https://kbmemo.net/up
```

5. 徒然ログで webhook 設定エラーが出ていないことを確認する。

```bash
sudo journalctl -u kbmemo -n 100 --no-pager
```

## スモークテスト

本番データを壊さないよう、UI から一時メモを 1 件作成して確認する。確認後に削除する。

1. Nyoy console で徒然 API 接続が有効か確認する。

```bash
cd ~/sites/nyoy
bin/prod console
```

```ruby
connection = ServiceConnection.resolve(:kbmemo)
[connection&.enabled?, connection&.base_url, connection&.api_token.present?, TsurezureClient.new.configured?]
```

すべて有効でなければ、先に「設定 > 接続」で `kbmemo` の URL、API token、有効状態を設定する。webhook secret はイベントの認証用であり、メモ本文を取得する API token の代わりにはならない。

2. 徒然 UI で committed メモを作成または更新する。
3. Nyoy console で最新 event を確認する。

```ruby
event = MemoRagWebhookEvent.order(id: :desc).first
[event.event_type, event.status, event.memo_uid, event.error_message, event.processed_at]
PromptKnowledgeChunk.from_memo.where("metadata->>'memo_uid' = ?", event.memo_uid).count
```

期待:

- `event_type` は `memo.created` または `memo.updated`
- `status` は `completed`
- chunk count は `1` 以上
- `error_message` は `nil`

4. 同じメモを徒然 UI から削除する。
5. Nyoy console で削除 event と chunk 削除を確認する。

```ruby
event = MemoRagWebhookEvent.where(memo_uid: "<対象UID>").order(id: :desc).first
[event.event_type, event.status, event.error_message, event.processed_at]
PromptKnowledgeChunk.from_memo.where("metadata->>'memo_uid' = ?", event.memo_uid).count
```

期待:

- `event_type` は `memo.deleted`
- `status` は `completed`
- chunk count は `0`

## 監視

Nyoy の webhook 状態:

```bash
cd ~/sites/nyoy
bin/prod kbmemo:rag:webhook_status
```

詳細を console で確認する場合:

```ruby
MemoRagWebhookEvent.order(id: :desc).limit(10).pluck(
  :event_type, :status, :memo_uid, :error_message, :processed_at
)
```

失敗 event:

```ruby
MemoRagWebhookEvent.where(status: "failed").order(id: :desc).limit(10).pluck(
  :event_type, :memo_uid, :error_message, :updated_at
)
```

ログ:

```bash
journalctl --user -u nyoy -f
sudo journalctl -u kbmemo -f
```

定期同期は継続する。webhook 有効化後も、必要に応じて checkpoint 同期で収束を確認する。

```bash
cd ~/sites/nyoy
bin/prod kbmemo:rag:ingest
```

## 切り戻し

送信側の徒然から止める。

```bash
cd /home/kensei/sites/kbmemo
$EDITOR .env.production
# NYOY_MEMO_WEBHOOK_ENABLED=false
bin/deploy
```

必要なら Nyoy 受信側も止める。

```bash
cd ~/sites/nyoy
$EDITOR .env.production
# MEMO_RAG_WEBHOOK_ENABLED=false
bin/deploy
```

切り戻し後は checkpoint 同期を実行し、webhook 停止中の差分を収束させる。

```bash
cd ~/sites/nyoy
bin/prod kbmemo:rag:ingest
```

## よくある失敗

| 症状 | 確認 |
|------|------|
| 徒然から 404 | Nyoy の URL が `/webhooks/kbmemo/memos` か、Nyoy が最新 revision か |
| 徒然から 401 | `MEMO_RAG_WEBHOOK_SECRET` と `NYOY_MEMO_WEBHOOK_SECRET` の不一致、または時刻ずれ |
| 徒然から 422 | payload の必須項目欠落。徒然側 revision と Nyoy 側 revision を確認 |
| event が `failed` | `error_message` を確認。Nyoy の `kbmemo` ServiceConnection token で対象メモが読めるか確認 |
| event が `pending` のまま | Nyoy の Solid Queue 実行状態を `journalctl --user -u nyoy` で確認 |
| 徒然の job が `UnknownJobClassError` | 徒然を最新 revision で再起動したか確認し、再起動境界で失敗した `NyoyMemoWebhookJob` を再実行する |
| chunk が増えない | 対象メモが draft、または Nyoy token account から見えない可能性 |

## 完了条件

- create/update/delete の本番スモークテストがすべて `completed`。
- 対象 memo UID の chunk が作成・更新・削除される。
- `MemoRagWebhookEvent.where(status: "failed")` に新規失敗が残らない。
- `MemoKnowledgeIngestJob` の checkpoint 同期を実行しても大きな未同期差分が出ない。
