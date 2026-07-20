# llama-switchd 運用 Runbook

## 1. 前提

Nyoy は `llama-switchd` をcontrol plane、各 `llama-server`をdata planeとして扱う。Nyoyからsystemdを直接操作しない。

```bash
LLAMA_SWITCHD_URL=http://balvenie:11335
LLAMA_SWITCHD_TOKEN=replace-with-secret
LLAMA_SERVER_ADMIN_TOKEN=replace-with-a-separate-secret
```

トークンは `env.development` またはproduction secretへ設定し、Git管理対象へ入れない。`LLAMA_SERVER_ADMIN_TOKEN` は接続設定とLLMサーバー管理画面の認証に使い、switchd API tokenとは別の値にする。未設定時は移行互換として `MCP_API_TOKEN` を使う。認証済みセッションの既定期限は12時間で、`LLAMA_SERVER_ADMIN_SESSION_TTL`（秒）により変更できる。

Kamalでは `LLAMA_SERVER_ADMIN_TOKEN` を `.kamal/secrets` から解決する。`config/deploy.yml` の `env.secret` には登録済みである。remote hostから使う場合、switchdの `LLAMA_SWITCHD_LISTEN` はNyoy hostから到達できるIPを指定する。

## 2. 疎通確認

```bash
curl -fsS "$LLAMA_SWITCHD_URL/health"
curl -fsS \
  -H "Authorization: Bearer $LLAMA_SWITCHD_TOKEN" \
  "$LLAMA_SWITCHD_URL/v1/servers"
```

Nyoyでは「設定 → 接続」を開き、管理トークンで認証してから「LLMサーバー」を開く。トークンはブラウザセッションへ保存せず、認証時刻とトークンのfingerprintだけを暗号化Cookieへ保持する。トークン変更後は再認証が必要になる。

### Control APIとdata planeが別hostの場合

`llama_switchd` 接続の編集画面で「公開ホスト」に、Nyoyから各llama-serverへ到達するhost名またはIPを設定する。

```text
管理API URL: https://switchd.internal.example:11335
公開ホスト:  llm-data.example.net
server PORT: 10010
実効URL:     https://llm-data.example.net:10010
```

公開ホストにはscheme、port、pathを含めない。未設定時は管理API URLのhostを使う。設定後は次の順で確認する。

1. 「LLMサーバー」を開き、ready serverのRuntime欄が取得できることを確認する
2. 管理対象接続の「URL・Aliasを同期」を実行する
3. 接続URLが公開ホストとserver PORTの組み合わせになったことを確認する
4. 「整合チェック」を実行し、`runtime_probe_failed` と `port_drift` がないことを確認する

切り戻す場合は公開ホストを空欄にして更新し、再度「URL・Aliasを同期」を実行する。llama-server定義やswitchd control URLは変更されない。

確認項目:

- switchd server一覧が表示される
- ready serverのRuntime欄にalias、model path、slotsが表示される
- Runtime Alias不一致またはRuntime取得失敗がない

### 管理認証のスモークテスト

デプロイ後、Nyoyへ到達できる端末から非破壊の認証確認を実行する。

```bash
export NYOY_URL=https://nyoy.kbmemo.net
export LLAMA_SERVER_ADMIN_TOKEN='production-admin-token'
bin/verify-llama-server-admin
```

`LLAMA_SERVER_ADMIN_TOKEN` が未設定の場合、スクリプトもアプリと同様に `MCP_API_TOKEN` へfallbackする。トークンは `curl` のコマンドライン引数へ渡さない。次の4項目が `PASS` になればよい。

- 未認証の管理画面アクセスが拒否される
- ログイン画面とCSRF tokenを取得できる
- 認証後に接続管理画面へ到達できる
- ログアウト後に管理画面が再度拒否される

## 3. 接続binding

1. Nyoy接続の現在のportとswitchd server候補を比較する
2. 用途とモデル実体を確認する
3. server IDを選び「紐付け」を実行する
4. 「URL・Aliasを同期」を実行する
5. 「整合チェック」を実行する

完全一致条件:

- Nyoy URLのportとswitchd PORTが一致
- Nyoy `server_model` とswitchd ALIASが一致
- `/props.model_alias` とswitchd ALIASが一致

portだけが一致する場合は自動判断しない。複数接続が同じportを指す場合は、用途を確認してからbindingする。

## 4. Lifecycle smoke test

既存ワークロードへ影響しないstopped / disabledの小型モデルを使う。

1. 元の `state`、`active`、`enabled` を記録する
2. 管理画面から「起動」を実行する
3. operation履歴が「成功」、server状態が `ready` になることを確認する
4. 「再起動」を実行し、再び `ready` になることを確認する
5. 「停止」を実行する
6. 元のstopped / disabled状態へ戻ったことを確認する

停止または定義削除の対象が有効なNyoy接続へ紐付いている場合、確認ダイアログに接続名/keyと既定Chat・画像理解・埋め込み・AgentGraph role等の影響用途を表示する。画面を経由しないHTTP要求も、影響用途がある場合は `acknowledge_usage=1` がなければ拒否される。

start/restartはswitchdのready待ちに最大120秒を使う。NyoyのHTTP timeoutは130秒なので、画面requestではなくSolid Queue jobが完了を待つ。

start/restartのready待ち後、Nyoyはdata planeの`/props`を取得し、switchd Aliasとruntime `model_alias`、definition SLOTSとruntime `total_slots`を比較する。検証成功時は操作履歴にAliasとslot数を表示する。不一致または取得失敗時はoperationを「失敗」とし、switchdから取得済みのserver状態はresponse snapshotへ残す。

操作が `待機中` または `実行中` の間、管理画面は4秒ごとに整合状態・サーバー状態・接続差分・モデル・操作履歴を自動更新する。操作が完了すると自動更新は停止し、ブラウザタブが非表示の間もpollingしない。更新ボタンで手動更新もできる。

サーバー数が多い場合は「サーバー検索」でIDまたはAliasを絞り込み、操作履歴は「操作状態」で待機中・実行中・成功・失敗を絞り込む。自動更新後も入力中の条件は維持される。

2026-07-21の実機確認:

| server | 操作 | 結果 | 所要時間 |
| --- | --- | --- | --- |
| `qwen3.5-2b-ud-q4-k-xl` | start | ready | 7.93秒 |
| 同上 | restart | ready | 3.42秒 |
| 同上 | stop | stopped | 0.13秒 |

終了時は `active=false`、`enabled=false` へ復元済み。

## 5. Definition CRUD smoke test

未使用portと一時server IDを使い、モデルは起動しない。

1. 定義を作成する
2. CTX_SIZEまたはSLOTSを更新する
3. `restart_required` と定義値を確認する
4. stopped / disabledのまま定義を削除する
5. server一覧から一時IDが消えたことを確認する

削除はstoppedかつdisabledの場合だけ許可される。

## 6. Reconciliation

productionでは15分ごと、developmentでは1時間ごとに実行する。手動実行も可能。

主なfinding:

| code | 対応 |
| --- | --- |
| `connection_unbound` | 用途を確認してserver IDへbindingする |
| `server_missing` | switchd定義の削除・ID変更を確認する |
| `port_drift` / `alias_drift` | 「URL・Aliasを同期」を実行する |
| `server_not_ready` | operation履歴とsystemd statusを確認する |
| `runtime_probe_failed` | llama-server `/props` の到達性を確認する |
| `runtime_alias_drift` | port上の別プロセスまたは古い起動定義を確認する |
| `restart_required` | 影響を確認して明示的に再起動する |

自動同期・自動再起動は行わない。

operation履歴は完了後30日かつ最新1000件、reconciliation履歴は最新100件を保持する。queued/running operationはmaintenanceの削除対象外。

### 外部アラート

`LLAMA_SERVER_ALERT_WEBHOOK_URL` を設定すると、定期・手動reconciliationの結果を汎用JSON Webhookへ非同期通知する。Bearer認証が必要な通知先では `LLAMA_SERVER_ALERT_WEBHOOK_TOKEN` も設定する。

```bash
LLAMA_SERVER_ALERT_WEBHOOK_URL=https://alerts.example.com/hooks/nyoy
LLAMA_SERVER_ALERT_WEBHOOK_TOKEN=replace-with-secret
```

通知条件:

- 初回チェックが `warning` または `failed`
- `healthy` / `warning` / `failed` の状態が変化
- `warning` の finding code・接続key・server IDが変化
- 異常状態から `healthy` へ復旧

同一内容の `warning` と連続する `failed` は再通知しない。配信は別のSolid Queue jobで最大5回再試行し、失敗してもreconciliation履歴の保存には影響しない。受信側は `Idempotency-Key: nyoy-llama-reconciliation-<id>` を使って再試行を重複排除できる。

payload例:

```json
{
  "event": "llama_server.reconciliation.warning",
  "environment": "production",
  "reconciliation_id": 123,
  "status": "warning",
  "previous_status": "healthy",
  "checked_at": "2026-07-21T04:30:00+09:00",
  "findings": [
    {
      "code": "server_not_ready",
      "connection_key": "llama_cpp",
      "server_id": "main",
      "message": "server状態はstoppedです",
      "usages": ["既定Chat"]
    }
  ],
  "error_message": null,
  "management_path": "/service_connections/llama_servers"
}
```

通知を停止するときは `LLAMA_SERVER_ALERT_WEBHOOK_URL` を削除してNyoyを再起動する。reconciliation自体は継続する。

## 7. 障害時

### switchdへ接続できない

```bash
ssh balvenie 'systemctl --user status llama-switchd.service --no-pager'
ssh balvenie 'ss -ltn | grep 11335'
```

loopbackだけでlistenしている場合は `LLAMA_SWITCHD_LISTEN` を確認する。

### start/restartが失敗する

1. Nyoyのoperation履歴でerrorを確認する
2. switchdのserver statusを取得する
3. systemd user unitのログを確認する
4. activeになっている場合はstopして元状態へ戻す

```bash
ssh balvenie 'journalctl --user -u llama-server@SERVER_ID.service -n 100 --no-pager'
```

### operationが実行待ちのまま

Solid Queue workerが起動しているか確認する。Web process内でstart/restartを同期実行しない。

### 外部アラートが届かない

1. 実行環境に `LLAMA_SERVER_ALERT_WEBHOOK_URL` がexportされているか確認する
2. Solid Queueのdefault queue workerが動いているか確認する
3. Nyoyログで `LlamaServerAlertJob` とHTTP statusを確認する
4. 受信側がBearer tokenとJSON payloadを受理しているか確認する
5. 同一異常の継続は意図的に抑止されるため、最新2件のreconciliationを比較する
