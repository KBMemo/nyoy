# llama-switchd 運用 Runbook

## 1. 前提

Nyoy は `llama-switchd` をcontrol plane、各 `llama-server`をdata planeとして
扱う。Nyoyからsystemdを直接操作しない。

```bash
LLAMA_SWITCHD_URL=http://llm-control.example.com:11335
LLAMA_SWITCHD_TOKEN=replace-with-secret
LLAMA_SERVER_ADMIN_TOKEN=replace-with-a-separate-secret
```

トークンはdevelopment envまたはproduction secretへ設定し、Git管理対象へ
入れない。`LLAMA_SERVER_ADMIN_TOKEN`は接続設定とLLMサーバー管理画面の認証に
使い、switchd API tokenとは別の値にする。未設定時は移行互換として
`MCP_API_TOKEN`を使う。認証済みセッションの既定期限は12時間で、
`LLAMA_SERVER_ADMIN_SESSION_TTL`（秒）により変更できる。

Kamalでは`LLAMA_SERVER_ADMIN_TOKEN`を`.kamal/secrets`から解決する。
remote hostから使う場合、switchdの`LLAMA_SWITCHD_LISTEN`はNyoy hostから
到達できるIPを指定する。

## 2. 疎通確認

```bash
curl -fsS "$LLAMA_SWITCHD_URL/health"
curl -fsS \
  -H "Authorization: Bearer $LLAMA_SWITCHD_TOKEN" \
  "$LLAMA_SWITCHD_URL/v1/servers"
```

Nyoyでは「設定 → 接続」を開き、管理トークンで認証してから「LLMサーバー」を
開く。トークンはブラウザセッションへ保存せず、認証時刻とfingerprintだけを
暗号化Cookieへ保持する。トークン変更後は再認証が必要になる。

### Control APIとdata planeが別hostの場合

`llama_switchd`接続の編集画面で「公開ホスト」に、Nyoyから各llama-serverへ
到達するhost名またはIPを設定する。

```text
管理API URL: https://switchd.internal.example:11335
公開ホスト:  llm-data.example.net
server PORT: 10010
実効URL:     https://llm-data.example.net:10010
```

公開ホストにはscheme、port、pathを含めない。未設定時は管理API URLのhostを
使う。設定後は次の順で確認する。

1. 「LLMサーバー」でready serverのRuntime欄を取得できる
2. 管理対象接続の「URL・Aliasを同期」を実行する
3. 接続URLが公開ホストとserver portの組み合わせになる
4. 「整合チェック」で`runtime_probe_failed`と`port_drift`がない

切り戻す場合は公開ホストを空欄にして更新し、再度「URL・Aliasを同期」する。
llama-server定義やswitchd control URLは変更されない。

### 管理認証のスモークテスト

デプロイ後、Nyoyへ到達できる端末から非破壊の認証確認を実行する。

```bash
export NYOY_URL=https://nyoy.example.com
: "${LLAMA_SERVER_ADMIN_TOKEN:?Set LLAMA_SERVER_ADMIN_TOKEN in the environment}"
bin/verify-llama-server-admin
```

次の4項目が`PASS`になればよい。

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

- Nyoy URLのportとswitchd portが一致
- Nyoy `server_model`とswitchd aliasが一致
- `/props.model_alias`とswitchd aliasが一致

portだけが一致する場合は自動判断しない。複数接続が同じportを指す場合は、
用途とRuntime Aliasを確認してから個別にbindingする。

大きな未キャッシュモデルではstart APIがtimeoutしても、直ちにstopや再startを
行わない。server detailの`active`、systemd状態、対象unitのjournal、
download中ファイル、data plane portを確認し、processが進行中ならready化を待つ。

接続を無効化またはserverを停止する前に、既定用途、実行中operation、他接続の
bindingを監査する。接続keyは履歴やmodel metadata参照を壊すため、用途を外した
後も安易に変更しない。

## 4. Lifecycle smoke test

既存ワークロードへ影響しないstopped / disabledの小型モデルを使う。

1. 元の`state`、`active`、`enabled`を記録する
2. 管理画面から「起動」を実行する
3. operation履歴が「成功」、server状態が`ready`になる
4. 「再起動」を実行し、再び`ready`になる
5. 「停止」を実行する
6. 元のstopped / disabled状態へ戻す

停止または定義削除の対象が有効なNyoy接続へ紐付いている場合、確認ダイアログに
接続と影響用途を表示する。画面を経由しないHTTP要求も、影響用途がある場合は
`acknowledge_usage=1`がなければ拒否される。

start/restartはswitchdのready待ちに最大120秒を使い、Solid Queue jobが完了を
待つ。ready後はdata planeの`/props`を取得し、aliasとslot数をdefinitionと
比較する。不一致または取得失敗時はoperationを失敗とする。

実機結果にはserver ID、model path、operation IDが含まれるため、公開repository
ではなくアクセス制限された運用記録へ保存する。

## 5. Definition CRUD smoke test

未使用portと一時server IDを使い、モデルは起動しない。

1. 定義を作成する
2. `CTX_SIZE`または`SLOTS`を更新する
3. `restart_required`と定義値を確認する
4. stopped / disabledのまま定義を削除する
5. server一覧から一時IDが消えたことを確認する

削除はstoppedかつdisabledの場合だけ許可される。

## 6. Reconciliation

productionでは15分ごと、developmentでは1時間ごとに実行する。手動実行も
可能とし、自動同期・自動再起動は行わない。

| code | 対応 |
|------|------|
| `connection_unbound` | 用途を確認してserver IDへbindingする |
| `server_missing` | switchd定義の削除・ID変更を確認する |
| `port_drift` / `alias_drift` | 「URL・Aliasを同期」を実行する |
| `server_not_ready` | operation履歴とsystemd statusを確認する |
| `runtime_probe_failed` | llama-server `/props`の到達性を確認する |
| `runtime_alias_drift` | port上の別processまたは古い定義を確認する |
| `restart_required` | 影響を確認して明示的に再起動する |

operation履歴は完了後30日かつ最新1000件、reconciliation履歴は最新100件を
保持する。queued / running operationはmaintenanceの削除対象外。

### 外部アラート

`LLAMA_SERVER_ALERT_WEBHOOK_URL`を設定すると、reconciliation結果を汎用JSON
Webhookへ非同期通知する。

```bash
LLAMA_SERVER_ALERT_WEBHOOK_URL=https://alerts.example.com/hooks/nyoy
LLAMA_SERVER_ALERT_WEBHOOK_TOKEN=replace-with-secret
```

Zabbix 7.0以降ではsender protocolを使い、Zabbix serverのtrapperへ直接通知
できる。frontendのHTTP portではなくserver port（既定`10051`）を指定する。

```bash
LLAMA_SERVER_ALERT_ZABBIX_SERVER=zabbix.example.com
LLAMA_SERVER_ALERT_ZABBIX_PORT=10051
LLAMA_SERVER_ALERT_ZABBIX_HOST=nyoy-production
LLAMA_SERVER_ALERT_ZABBIX_KEY_PREFIX=nyoy.llama_server.reconciliation
```

trapper itemは数値statusとJSON payloadの2件を作成する。

| Key | Type of information |
|-----|---------------------|
| `nyoy.llama_server.reconciliation.status` | Numeric (unsigned) |
| `nyoy.llama_server.reconciliation.payload` | Text |

statusは`0=healthy`、`1=warning`、`2=failed`。異常への変化、finding内容の変化、
正常への復旧時に通知する。同一内容のwarningと連続するfailedは再通知しない。
配送は別のSolid Queue jobで最大5回再試行する。

Webhook受信側はBearer token、JSON payload、`Idempotency-Key`を受理し、
再試行を重複排除できることを確認する。Zabbixと汎用Webhookを両方設定した場合は
両方へ配送する。

## 7. 障害時

### switchdへ接続できない

```bash
ssh llm-admin@llm-control.example.com \
  'systemctl --user status llama-switchd.service --no-pager'
ssh llm-admin@llm-control.example.com \
  'ss -ltn | grep 11335'
```

loopbackだけでlistenしている場合は`LLAMA_SWITCHD_LISTEN`を確認する。

### start/restartが失敗する

1. Nyoyのoperation履歴でerrorを確認する
2. switchdのserver statusを取得する
3. systemd user unitのログを確認する
4. activeになっている場合はstopして元状態へ戻す

```bash
ssh llm-admin@llm-control.example.com \
  'journalctl --user -u llama-server@SERVER_ID.service -n 100 --no-pager'
```

### operationが実行待ちのまま

Solid Queue workerが起動しているか確認する。Web process内でstart/restartを
同期実行しない。

### 外部アラートが届かない

1. 実行環境にalert URLがexportされている
2. Solid Queueのdefault queue workerが動いている
3. Nyoyログでalert jobとHTTP statusを確認する
4. 受信側が認証とJSON payloadを受理している
5. 同一異常の継続が通知抑止対象でないか最新2件を比較する
