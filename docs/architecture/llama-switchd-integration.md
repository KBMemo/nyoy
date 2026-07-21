# llama-switchd integration

**実装状況:** Phase 1〜5のコード実装完了（2026-07-21）。残る本番運用確認は [9.2](#92-残課題) を参照。

## 1. 目的

Nyoy のローカル LLM 接続を、手入力した URL と model alias の集合から、`llama-switchd` が管理する server resource への明示参照へ移行する。

対象:

- server definition の検出・作成・更新
- `llama-server@<id>.service` の起動・停止・再起動・enable/disable
- PORT、ALIAS、model source、CTX_SIZE、SLOTS などの同期
- systemd、health、configuration revision、`restart_required` の表示
- Nyoy の Chat / AgentGraph が使う実効 `base_url` と `server_model` の整合

`llama-switchd` 自体は control plane、各 `llama-server` は data plane として分離する。Nyoy は systemd を直接操作せず、Bearer 認証された switchd API だけを使う。

Nyoyの接続設定とLLMサーバー管理UIは `LLAMA_SERVER_ADMIN_TOKEN` で保護する。ブラウザでの照合成功後は、認証時刻とトークンfingerprintを暗号化セッションへ保持する。管理トークンはswitchdへ転送せず、switchd API用の `LLAMA_SWITCHD_TOKEN` と責務を分ける。

Reconciliationの外部通知は汎用JSON Webhook adapterへ分離する。reconciliation保存後に別jobをenqueueし、通知先障害で整合チェック自体を失敗させない。通知判定は直前履歴との状態・finding identity比較で行い、定期実行による同一異常の連続通知を抑止する。

Upstream:

- [llama-tools README](https://github.com/knb/llama-tools)
- [server management design](https://github.com/knb/llama-tools/blob/main/docs/server-management-design.md)

運用確認は [llama-switchd 運用 Runbook](../llama-switchd-runbook.md) を参照する。

## 2. 現状の問題

現在の `ServiceConnection` は次の値を単独で保持する。

- `base_url`: llama-server の固定 URL
- `server_model`: OpenAI compatible API へ渡す model alias
- `settings.prompt_conversion`: sampling defaults

この形では、server definition の PORT / ALIAS を変更しても Nyoy へ反映されない。また、接続名、用途、実モデル、alias が混在している。

2026-07-21 の development DB では `llama_cpp` と `gpt_oss` がともに `http://balvenie:10011` を指している一方、10011 の実体は Gemma 4 だった。`llama_cpp.server_model`、`gpt_oss.server_model`、実 `/props.model_alias` も一致していない。したがって、既存レコードをポートだけで自動 binding してはならない。

同日のinventory確認後、development・productionの`gpt_oss`を`gpt-oss-20b`へbindingし、port `10014`、Alias `gpt-oss-20b`へ同期した。旧`llm_gemma4_e4b_mtp`接続は無効化し、参照がなくなったLFM2.5 serverも停止・自動起動無効化した。

## 3. 責務境界

### 3.1 Control connection

`ServiceConnection` に組み込み key `llama_switchd` を追加する。

| field | 内容 |
| --- | --- |
| `base_url` | switchd API。例: `http://balvenie:11335` |
| `api_token` | `LLAMA_SWITCHD_TOKEN` |
| `enabled` | Nyoy から管理 API を使うか |

環境変数 fallback は `LLAMA_SWITCHD_URL` / `LLAMA_SWITCHD_TOKEN` とする。`GET /health` 以外には常に Bearer token を付ける。

### 3.2 Managed LLM connection

Chat backend の `ServiceConnection` は「用途別接続」のまま維持する。例: intent、draft、main chat。これに switchd server resource への binding を追加する。

推奨カラム:

```text
manager_connection_id  bigint, nullable, FK service_connections
managed_server_id      string, nullable
```

- `manager_connection_id`: `llama_switchd` 接続を指す自己参照
- `managed_server_id`: immutable な switchd server ID
- lookup index: `(manager_connection_id, managed_server_id)`。同じserverを複数用途で共有するためuniqueにはしない
- `base_url` / `server_model` は削除せず、同期済みdata-plane snapshotとして残す
- sampling、role assignment、表示名は用途別接続側に残す

外部resource IDをJSON settingsへ埋める案はmigrationが軽いが、参照整合・検索・管理画面実装が弱くなるため採用しない。

## 4. 値の正本

| 値 | 正本 | Nyoy側 |
| --- | --- | --- |
| server ID | switchd resource | `managed_server_id` |
| model source (`MODEL` / `HF_REPO`) | switchd definition | read-only表示 |
| PORT / HOST / ALIAS | switchd definition | `base_url` / `server_model`へ同期 |
| lifecycle / health | switchd status | 都度取得。DBへ恒久保存しない |
| CTX_SIZE / SLOTS / launch options | switchd definition | typed formからAPI更新 |
| sampling defaults | 用途別 `ServiceConnection` | `settings.prompt_conversion` |
| AgentGraph role assignment | Nyoy | `AppSetting.agent_graph_role_profiles`等 |

実効URLは `switchd.base_url` のscheme、control connectionの `settings.llama_switchd.public_host`、definitionの`PORT`から構成する。`public_host` 未設定時は `switchd.base_url` のhostを使う。definitionの`HOST`はprocessのlisten addressであり、Nyoyからの接続先判定には使わない。

URL構成は `LlamaServerEndpoint` に集約し、接続同期とruntime probeで同じ規則を使う。これにより、switchd control APIと各llama-server data planeが別hostにある構成、DNS名を分離する構成、NAT越しの構成を扱える。`public_host` はhost名またはIPだけを保持し、schemeとportの上書きは許可しない。

## 5. API client

`LlamaSwitchdClient` を追加し、HTTP詳細をcontrollerやmodelへ漏らさない。

```text
health
list_models
list_servers
get_server(id)
server_status(id)
create_server(id: nil, values:)
update_server(id, values:)
start_server(id, timeout_seconds:)
stop_server(id)
restart_server(id, timeout_seconds:)
enable_server(id)
disable_server(id)
delete_server(id)
```

clientは次を保証する。

- open/read timeout
- Bearer header
- URL path component escape
- JSON object検証
- HTTP statusとupstream `error`を保持したtyped error
- token、MODELの絶対path、systemd command outputをRails logへ不用意に出さない

upstreamのvalidationを正本としつつ、Nyoyフォームも同じallowlistと型を使う。任意のCLI文字列や未定義キーは受け付けない。

## 6. Reconciliation

### 6.1 Read-only inventory

最初に `GET /v1/servers` と各 llama-server `/props` を取得し、次を表で比較する。

```text
Nyoy connection key / name
current base_url / server_model
switchd server id / port / alias / source
runtime state / ready / enabled / restart_required
/props model_alias / model_path / total_slots
差分と推奨操作
```

自動binding候補は、`base_url.port == switchd.port` かつ `server_model == switchd.alias` かつ `/props.model_alias == switchd.alias` の場合だけ提示する。1項目でも不一致ならユーザー確認を必須とする。

### 6.2 Binding後の同期

binding済み接続は次の操作を持つ。

- `状態を更新`: statusとdefinitionを再取得
- `接続へ反映`: PORT / ALIASを`base_url` / `server_model`へ保存
- `定義を更新`: typed launch settingsをswitchdへPATCH
- `再起動`: `restart_required`時に明示実行

定義PATCHと接続snapshot更新を同一transactionと見なさない。外部API成功後にDB保存が失敗する可能性があるため、再取得による収束を基本にする。

## 7. Lifecycle operation

start/restartはupstream側でhealth readyまで最大120秒待つ。Web request内で直接待たず、operation recordとjobで実行する。

実装テーブル:

```text
llama_server_operations
  service_connection_id
  action                 # create/update/start/stop/restart/enable/disable/delete
  status                 # queued/running/succeeded/failed
  request_payload        # secretを含まないallowlisted JSON
  response_snapshot      # bounded JSON
  error_message
  started_at / finished_at
```

状態遷移:

```text
queued -> running -> succeeded
                  -> failed
```

- 同じmanaged serverへのmutating operationはNyoy側でも1件に制限
- upstreamもmutationを直列化するが、UIの二重送信防止と監査のためNyoy側operationを持つ
- start/restart成功後はswitchdのready待ちに加えて`/props`のAlias・slot数を即時検証し、安全なruntime snapshotをoperationへ保存する
- stop/deleteは紐付いた有効な接続と既定Chat・AgentGraph role等の用途を確認文へ表示し、controllerでも明示確認値を要求する
- deleteはupstreamの「stoppedかつdisabled」を満たす場合だけ表示する

AgentGraphの状態機械へは入れない。これはAI workflowではなく、管理操作の短いjob state machineとして独立させる。

## 8. UI

設定配下を2層に分ける。

### 8.1 LLM server管理

- switchd health
- discovered local models
- managed servers一覧
- state、ready、enabled、port、alias、source
- CTX_SIZE、SLOTS、GPU、batch、speculative decoding等のtyped設定
- `restart_required`
- start/stop/restart/enable/disable
- operation履歴

### 8.2 LLM用途別接続

- 表示名と用途
- bindingするswitchd server ID
- 同期されたURL / alias
- sampling defaults
- Chat既定、AgentGraph role profileとの関係

server definitionと用途別LLM設定を同じフォームへ混在させない。1つのserverを複数用途で共有しても、samplingやrole assignmentは用途ごとに変えられる。

## 9. 導入状況

### 9.1 Phase別状況

#### Phase 1: read-only

1. [x] `llama_switchd` control connection
2. [x] `LlamaSwitchdClient`
3. [x] server/model inventory画面
4. [x] 現在のNyoy接続との差分表示

DB接続値はinventory表示だけでは更新せず、明示的な同期操作で更新する。

#### Phase 2: bindingと同期

1. [x] `manager_connection_id` / `managed_server_id`
2. [x] 手動binding
3. [x] PORT / ALIASからsnapshot同期
4. [x] `/props`との三者整合チェック
5. [x] control APIとdata planeのhost分離（`public_host`）

#### Phase 3: lifecycle

1. [x] operation table/job
2. [x] start/stop/restart/enable/disable
3. [x] readiness、error、operation履歴UI
4. [x] active operation中の画面自動更新
5. [x] start/restart完了直後の`/props` Alias・slot数検証

#### Phase 4: definition管理

1. [x] model discovery
2. [x] create/PATCH typed form
3. [x] `restart_required`導線
4. [x] stopped + disabled時のdelete

#### Phase 5: 運用自動化

1. [x] 定期reconciliation
2. [x] alias/port driftのWebhook通知と同一異常抑止
3. [x] roleや有効な接続が参照するserverのstop/delete操作前警告
4. [x] freshなreconciliation snapshotによりready serverだけをChat model選択肢へ表示
5. [x] 管理UIのトークン認証
6. [x] operation/reconciliation履歴の定期削除

### 9.2 残課題

| 優先度 | 課題 | 現状 | 完了条件 |
| --- | --- | --- | --- |
| 完了 | production残接続のbinding | 2026-07-22に`llama_cpp`、`vision_llama`、`embeddings`、`llm_qwythos_9b_mtp_q4`を確定済みRuntime Aliasへbinding・同期 | reconciliation `healthy`、findings 0件を確認済み |
| 運用 | Zabbixへの外部alert常設 | 本番runtimeと一時localhost受信器でwarning/recovered、Bearer、冪等キーのE2Eは確認済み。2026-07-22にZabbix導入後へ延期を決定 | Zabbix導入後に受信方式を確定し、本番envへ設定して実際の異常・復旧通知を受信確認 |

`public_host` は実装・自動テスト済みだが、現行の同一host構成では設定不要である。実際にcontrol/data hostを分離するときにrunbookの疎通確認を行う。

コード上のPhase 1〜5残課題は完了した。残る項目は本番環境での運用確認であり、実装課題が追加された場合はこの表へ完了条件とともに追記する。

## 10. 確定した設計判断

- switchd server IDと用途別接続keyを同一視しない
- 固定portをNyoyの識別子にしない
- `server_model`はmodel file名ではなくOpenAI APIのALIAS snapshotとする
- switchd導入後も用途別samplingとAgentGraph role設定はNyoyに残す
- 初回migrationは自動bindingせずinventory差分から手動確定する
- 外部通知失敗はreconciliation保存を失敗させず、別jobで再試行する
- 管理UI認証token、switchd API token、alert Webhook tokenは責務を分ける
- control APIとdata planeのhost解決は`LlamaServerEndpoint`へ集約する
