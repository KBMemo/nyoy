# LLM サンプリングプリセット

接続のプロンプト変換設定と、チャット／MCP エージェントが共有する推奨サンプリングです。

## データ

- テーブル: `llm_sampling_presets`
- Seed: `LlmSamplingPresetSeeds`（例: Qwen3.5 9B）
- UI: 設定 → サンプリング / 接続編集の「推奨プリセット」/ チャット設定ダイアログ

`enable_thinking` は接続のプロンプト変換（`chat_template_kwargs`）向け。チャットの `llm_params` には載せない。

`reasoning_effort` は `low` / `medium` / `high` の列挙値として扱う。未指定または不正値はリクエストへ含めないため、対応していないモデルでは設定しない。

## API（エージェント向け土台）

```
GET /llm_sampling_presets.json
GET /llm_sampling_presets/:id.json
```

返却例（一覧）:

```json
{
  "presets": [
    {
      "key": "qwen3_5_9b",
      "name": "Qwen3.5 9B（コミュニティ推奨）",
      "model_name_match": "qwen3",
      "params": {
        "temperature": 0.7,
        "top_p": 0.8,
        "enable_thinking": false
      }
    }
  ]
}
```

接続のサーバ既定は別経路:

```
POST /service_connections/:id/load_sampling.json
```

`GET {base_url}/props` の `default_generation_settings.params` を返す（コミュニティ推奨とは別物）。

## Chat / MCP ツール

`ChatTools`（`ToolBridge` 経由で MCP にも公開）:

| ツール | 役割 |
|--------|------|
| `list_sampling_presets` | 有効プリセット一覧（`as_api_json`） |
| `apply_sampling_preset` | `preset_key` で会話の `llm_params` を上書き。Chat UI は現在の会話、MCP は `chat_id` 必須 |

チャット設定ダイアログでも同一プリセットをフォームへ流し込み、「設定を更新」で `chats.llm_params` に保存する。

## 用途assignment連携

設定 → LLM用途で用途ごとに`LlmSamplingPreset`を選べる。通常Chatの既定値は`chat.default` assignmentから解決する。

優先順位（後勝ち）:

1. アプリ既定プリセット（`AppSetting.default_chat_llm_params`）
2. 接続プロファイルのサンプリング（モデルの `metadata.connection_key` → `ServiceConnection.settings.prompt_conversion`）
3. チャット個別の `chats.llm_params`

- 新規チャット作成時・生成時の `ChatLlmSettings.effective_for` / `defaults_for` がこの合成を使う
- 接続の `enable_thinking` / `json_schema` はチャットへは流さない（プロンプト変換専用）
