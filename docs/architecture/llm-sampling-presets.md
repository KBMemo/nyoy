# LLM サンプリングプリセット

接続のプロンプト変換設定と、将来のチャットエージェントが共有する推奨サンプリングです。

## データ

- テーブル: `llm_sampling_presets`
- Seed: `LlmSamplingPresetSeeds`（例: Qwen3.5 9B）
- UI: 設定 → サンプリング / 接続編集の「推奨プリセット」

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

## 後続

- チャット設定ダイアログから同一プリセットを適用
- MCP / チャットツールで `list_sampling_presets` → 会話の `llm_params` に反映
