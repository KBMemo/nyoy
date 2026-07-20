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

2026-07-21 本番確認:

- deploy revision: `4464d4c`
- `https://nyoy.kbmemo.net/up`: HTTP 200
- 未認証拒否、ログイン画面、認証後アクセス、ログアウト後拒否: 4項目すべてPASS
- 専用 `LLAMA_SERVER_ADMIN_TOKEN` は未設定のため、移行fallbackの `MCP_API_TOKEN` で確認

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

2026-07-21 本番初回inventory:

- productionへ `llama_switchd` 接続ID 15を作成
- switchd health成功、11 servers取得
- reconciliation ID 4は`warning`、findingは既存6接続の`connection_unbound`のみ
- 6接続はすべてport一致・Alias不一致（`port_only`）のため自動binding・同期は未実施

| Nyoy接続 | port | 現在Alias | Runtime / switchd Alias |
| --- | ---: | --- | --- |
| `llama_cpp` | 10011 | `gemma-4-12b-it-mtp` | `gemma-4-e4b-it-qat-ud-q4-k-xl` |
| `gpt_oss` | 10012 | `gpt-oss-20b` | `gemma-4-12b-it-qat-ud-q4-k-xl` |
| `vision_llama` | 10021 | `qwen2.5-vl-3b` | `qwen3vl-4b-instruct-q4-k-m` |
| `embeddings` | 10020 | `bge-m3` | `lfm2.5-embedding-350m-q4-k-m` |
| `llm_qwythos_9b_mtp_q4` | 10013 | `qwythos-9b-mtp-q4` | `qwythos-9b-claude-mythos-5-1m-q4-k-m` |
| `llm_gemma4_e4b_mtp` | 10014 | `gemma-4-e4b-it-mtp` | `gpt-oss-20b`（stopped / disabled） |

用途確認後、正しいserver IDへbindingし「URL・Aliasを同期」する。特に`gpt_oss`と`llm_gemma4_e4b_mtp`は用途と実体が入れ替わって見えるため、portだけで確定しない。

2026-07-21 `gpt_oss` 切替:

- `gpt-oss-20b` serverをport `10014`で自動起動有効化・起動
- 初回起動は約11.8 GBのGGUF取得に約18分を要し、switchdの120秒ready待ちはHTTP 504になったが、systemd processは取得と起動を継続した
- `/health`、`/props.model_alias=gpt-oss-20b`、`total_slots=1`を確認後、`gpt_oss`をserverへbindingしてURL・Aliasを同期
- `gpt_oss`は`http://balvenie:10014`、Alias `gpt-oss-20b`、有効
- `llm_gemma4_e4b_mtp`接続は無効化。現在この接続が参照しているLFM2.5 serverは、他用途への影響を避けて停止していない
- reconciliation ID 8は`healthy`、findingなし

大きな未キャッシュモデルではstart APIがtimeoutしても、直ちにstopや再startを行わない。server detailの`active`、systemd状態、対象unitのjournal、download中ファイル、data plane portを確認し、processが進行中ならready化を待つ。

2026-07-21 production切替:

- production DBの`gpt_oss`を`gpt-oss-20b`へbindingし、`http://balvenie:10014`、Alias `gpt-oss-20b`へ同期
- productionの`llm_gemma4_e4b_mtp`接続を無効化
- RuntimeのAlias一致と`total_slots=2`を確認
- reconciliation ID 9は`warning`。`gpt_oss`のfindingはなく、既存の`llama_cpp`、`vision_llama`、`embeddings`、`llm_qwythos_9b_mtp_q4`が未bindingであることだけを検出

残る4接続はportだけで自動bindingせず、各Runtime Aliasを確認して個別に同期する。

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

2026-07-21の起動直後Runtime検証:

| server | operation | 結果 | Runtime | 所要時間 |
| --- | --- | --- | --- | --- |
| `qwen3.5-2b-ud-q4-k-xl` | `start`（ID 10） | `succeeded` / ready | Alias一致、`total_slots=1` | 4.09秒 |
| 同上 | `stop`（ID 11） | `succeeded` / stopped | 対象外 | 0.18秒 |

対象はbindingなし、開始時 `stopped / active=false / enabled=false`。definitionに明示的な`SLOTS`がないため、runtime slot数が正であることを確認する経路を実行した。start operationのsnapshotはserverのallowlist済み状態と `runtime.model_alias` / `runtime.total_slots`だけを保持し、model pathやsystemd出力を含まない。終了時は `stopped / active=false / enabled=false`へ復元済み。

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

2026-07-21 本番runtime E2E:

- 本番revision `00fde05` 上でlocalhost一時HTTP受信器を起動
- DB transaction内で一時 `llama_switchd` 接続と `healthy -> warning -> healthy` 履歴を作成
- `llama_server.reconciliation.warning` と `llama_server.reconciliation.recovered` を各1件受信
- 両requestのBearer認証と `nyoy-llama-reconciliation-<id>` 冪等キーを確認
- transaction rollback後、一時 `llama_switchd` 接続は0件

これは本番runtimeでの配送経路確認であり、常設の外部通知先確認ではない。`LLAMA_SERVER_ALERT_WEBHOOK_URL` / `LLAMA_SERVER_ALERT_WEBHOOK_TOKEN` は未設定のため、通知先選定後に実障害または管理された障害注入で再確認する。

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
