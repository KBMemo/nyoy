# LLM サンプリングプリセット

接続のプロンプト変換設定と、チャット／MCP エージェントが共有する推奨サンプリングです。

## データ

- テーブル: `llm_sampling_presets`
- Seed: `LlmSamplingPresetSeeds`（例: Qwen3.5 9B）
- UI: 設定 → サンプリング / 接続編集の「推奨プリセット」/ チャット設定ダイアログ

`enable_thinking` は接続のプロンプト変換（`chat_template_kwargs`）向け。チャットの `llm_params` には載せない。

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

## 既定モデル連携

設定 → 既定モデルの「チャット既定サンプリング」で `LlmSamplingPreset` を選べる（`app_settings.default_llm_sampling_preset_key`）。

- 新規チャット作成時に `llm_params` へシード
- チャットの `llm_params` が空のときは生成時に同じ既定を適用（`ChatLlmSettings.effective_for`）

プロンプト変換のサンプリングは接続ごとの `prompt_conversion` 設定を使う（本項目の対象外）。
