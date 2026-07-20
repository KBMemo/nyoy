# llama-switchd 運用 Runbook

## 1. 前提

Nyoy は `llama-switchd` をcontrol plane、各 `llama-server`をdata planeとして扱う。Nyoyからsystemdを直接操作しない。

```bash
LLAMA_SWITCHD_URL=http://balvenie:11335
LLAMA_SWITCHD_TOKEN=replace-with-secret
```

トークンは `env.development` またはproduction secretへ設定し、Git管理対象へ入れない。remote hostから使う場合、switchdの `LLAMA_SWITCHD_LISTEN` はNyoy hostから到達できるIPを指定する。

## 2. 疎通確認

```bash
curl -fsS "$LLAMA_SWITCHD_URL/health"
curl -fsS \
  -H "Authorization: Bearer $LLAMA_SWITCHD_TOKEN" \
  "$LLAMA_SWITCHD_URL/v1/servers"
```

Nyoyでは「設定 → 接続 → LLMサーバー」を開く。

確認項目:

- switchd server一覧が表示される
- ready serverのRuntime欄にalias、model path、slotsが表示される
- Runtime Alias不一致またはRuntime取得失敗がない

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

start/restartはswitchdのready待ちに最大120秒を使う。NyoyのHTTP timeoutは130秒なので、画面requestではなくSolid Queue jobが完了を待つ。

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
