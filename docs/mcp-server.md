# Nyoy MCP サーバー

如意（Nyoy）の Chat ツール（`ChatTools::*`）を [Model Context Protocol](https://modelcontextprotocol.io/) 経由で外部クライアント（Cursor 等）から利用する。

Chat UI と MCP は同じツール実装を共有する（`Mcp::ToolBridge` が `ChatTools::Registry` を橋渡し）。

---

## 有効化

`MCP_API_TOKEN` を設定すると MCP が有効になる。未設定時は HTTP `/mcp` は 404、`bin/mcp-stdio` は終了コード 1。

```bash
export MCP_API_TOKEN="your-secret-token"
```

認可は当面 **Bearer トークン 1 本**（個人利用想定）。HTTP トランスポートのみリクエストごとに検証する。stdio はローカルプロセス起動を信頼する。

---

## トランスポート

| 方式 | エントリ | 用途 |
|------|----------|------|
| Streamable HTTP | `GET/POST/DELETE /mcp` | リモートまたはローカル HTTP |
| stdio | `bin/mcp-stdio` | Cursor 等が子プロセスとして起動 |

公開ツールは `ServiceConnection` の有効状態に応じて動的（Chat と同じ）。

| ツール | 条件 |
|--------|------|
| `web_search` | `searfront` 有効 |
| `fetch_url` / `search_fetched_page` | 常時 |
| `search_memos` / `get_memo` / `create_memo` / `update_memo` | `kbmemo` 有効 |
| `recall_memos` | `kbmemo` かつ `MEMO_RAG_MODE=tool` |
| `list_albums` / `get_media` | `tsuzura` 有効 |
| `analyze_image` | `vision_llama` 有効（MCP では `tsuzura_media_id` 指定） |
| `list_sampling_presets` / `apply_sampling_preset` | 常時（後者は MCP では `chat_id` 必須） |
| `list_prompt_styles` | `sd_cpp` 有効 |
| `generate_image` / `get_image_generation` / `refine_image` | `sd_cpp` 有効（非同期・ポーリング） |
| `run_research_graph` / `get_research_graph` / `retry_research_graph` | 常時（Research Graph） |
| `run_memo_write_graph` / `get_memo_write_graph` / `resume_memo_write_graph` | 常時（MemoWrite Graph） |
| `run_memo_update_graph` / `get_memo_update_graph` / `resume_memo_update_graph` | 常時（MemoUpdate Graph） |

---

## Cursor 設定例

### stdio（推奨・ローカル開発）

`.cursor/mcp.json` または Cursor Settings → MCP:

```json
{
  "mcpServers": {
    "nyoy": {
      "command": "/home/kensei/work/localai/nyoy/bin/mcp-stdio",
      "env": {
        "MCP_API_TOKEN": "your-secret-token",
        "RAILS_ENV": "development"
      }
    }
  }
}
```

`command` は絶対パスにする。雛形は [examples/cursor-mcp-stdio.json](./examples/cursor-mcp-stdio.json)。

### Streamable HTTP

Nyoy を起動したうえで:

```json
{
  "mcpServers": {
    "nyoy": {
      "url": "http://localhost:3000/mcp",
      "headers": {
        "Authorization": "Bearer your-secret-token",
        "Accept": "application/json"
      }
    }
  }
}
```

本番（`nyoy.kbmemo.net`）では HTTPS URL に差し替える。雛形は [examples/cursor-mcp-http.json](./examples/cursor-mcp-http.json)。

---

## 実装構成

```
Chat UI ──┐
          ├── ChatTools::* ── ServiceConnection / 徒然 API / 葛籠 API
MCP ──────┘   ↑
              Mcp::ToolBridge（ChatTools → MCP::Tool）
              Mcp::ExtensionTools（SD: list_prompt_styles / generate_image / …）
              Mcp::ResearchGraphTools（run_research_graph / get_research_graph / retry_research_graph）
              Mcp::MemoWriteGraphTools（run_memo_write_graph / get_memo_write_graph / resume_memo_write_graph）
```

| ファイル | 役割 |
|----------|------|
| `app/controllers/mcp_controller.rb` | HTTP エンドポイント・認証 |
| `app/services/mcp/tool_bridge.rb` | ツール変換・実行委譲 |
| `app/services/mcp/extension_tools.rb` | SD パイプライン用 MCP ツール |
| `app/services/mcp/research_graph_tools.rb` | Research Graph MCP ツール |
| `app/services/mcp/memo_write_graph_tools.rb` | MemoWrite Graph MCP ツール |
| `app/services/mcp/tool_catalog.rb` | Chat + Extension + Graph ツール統合 |
| `bin/mcp-stdio` | stdio トランスポート |

本番では `MCP_API_TOKEN` を Kamal secrets（`.kamal/secrets`）に追加する（`config/deploy.yml` の `env.secret` に登録済み）。

```bash
# ローカルで公開ツール名を確認
MCP_API_TOKEN=your-token bin/mcp-list-tools
```

### 接続確認

stdio は Cursor が子プロセスとして起動する経路に近い形で、JSON-RPC を標準入出力に流して確認できる。

```bash
printf '%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"stdio-smoke","version":"0.1"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  | MCP_API_TOKEN=your-token RAILS_ENV=development bin/mcp-stdio
```

HTTP は Nyoy を起動したうえで、Bearer 認証付きで `initialize` / `tools/list` を確認する。

```bash
curl -sS -X POST http://127.0.0.1:3000/mcp \
  -H 'Authorization: Bearer your-token' \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"curl","version":"0.1"}}}'

curl -sS -X POST http://127.0.0.1:3000/mcp \
  -H 'Authorization: Bearer your-token' \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  --data '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

期待結果:

- `initialize` の `serverInfo.name` が `nyoy`
- `tools/list` に `run_research_graph` / `retry_research_graph` / `run_memo_write_graph` / `run_memo_update_graph` が含まれる
- 認証なしの HTTP `/mcp` は `401 Unauthorized`
- `MCP_API_TOKEN` 未設定時は HTTP `/mcp` が `404 Not Found`、`bin/mcp-stdio` が終了コード 1

---

## 制約・注意

- **Web 予算**: `web_search` / `fetch_url` はリクエスト（stdio）または HTTP リクエスト単位で `WebToolBudget` を共有する。
- **fetch キャッシュ**: `search_fetched_page` はプロセス内メモリの `FetchedPageCache` に依存。マルチプロセス Puma では HTTP リクエスト間で共有されない。
- **画像解析**: Chat 添付がない MCP セッションでは `analyze_image` に `tsuzura_media_id` を渡す。
- **画像生成フロー**: `generate_image` → `get_image_generation`（`awaiting_selection`）→ `refine_image`（`draft_index`）→ `get_image_generation`（`completed`）。
- **調査フロー**: `run_research_graph`（ドラフト承認なしで最終回答まで実行）。状態は `get_research_graph`。failed の Research Graph は `retry_research_graph` で最後の成功 checkpoint から複製 run として再実行できる。
- **メモ新規保存フロー**: `run_memo_write_graph`（既定 `auto_approve=true`）。HITL 時は `resume_memo_write_graph`。状態は `get_memo_write_graph`。Chat UI では常に承認待ち。
- **徒然 Agent Chat（既知の課題）**: 上記のうち **ラフ案生成〜`awaiting_selection` まで** は in-app で動作。**`refine_image` 以降は未接続**（ドラフト 1〜4 の選択 UI・仕上げポーリングなし）。当面は `show_path` の Nyoy UI で手動 refine。詳細は徒然 `docs/architecture/chat-agent-roadmap.adoc` §12。
- **メモ保存**: `create_memo` / `update_memo` はユーザー明示依頼時のみ（Chat と同じ運用）。明示的な「徒然に保存」は MemoWrite Graph が優先。

---

## 関連

- [エコシステム構成（Nyoy MCP 前提）](./architecture/nyoy-mcp.adoc)
- [エコシステム ロードマップ](./ecosystem-roadmap.md)
- [徒然 API 要件](./tsuredure-api-requirements.md)
