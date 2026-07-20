# Chat 高速化 — 現状と検討案件

Chat（`chats` / `messages` / `ChatResponseJob`）の応答レイテンシ改善について、実装済みの内容・計測結果・未着手の検討案件をまとめる。

関連コードの入口:

| 領域 | 主なファイル |
|------|----------------|
| リクエスト組み立て | `app/models/chat.rb`（`#to_llm`） |
| llama.cpp キャッシュ | `app/services/chat_llama_cache.rb` |
| メモ RAG | `app/services/chat_memo_rag_injector.rb`, `app/services/chat_tools/recall_memos.rb` |
| 計測 | `app/services/chat_response_timer.rb`, `messages` の timing カラム |
| ツール配線 | `app/services/chat_tools/registry.rb` |

---

## 1. 背景

体感の遅さは「TTFT（Time To First Token）が長い」として報告された。当初の仮説は次のとおり。

1. llama.cpp の prompt KV cache / slot が効いていない
2. 毎ターンのメモ RAG 前処理（embeddings + 徒然キーワード検索）がブロッキングしている
3. 会話要約を system 先頭に載せ替えており、キャッシュプレフィックスが毎ターン無効化されている
4. アイドル明けの cold start（モデル／CUDA グラフのウォームアップ）

計測を入れたうえで切り分けし、アプリ側で効く項目は実装済み。残ボトルネックは主に **gpt-oss の思考トークン生成** である。

---

## 2. 実装済み

### 2.1 llama.cpp prompt cache / sticky slot

- `ChatLlamaCache` が `cache_prompt: true` と `id_slot = chat.id % total_slots` を `with_params` で付与する
- `total_slots` は `GET /props` から取得（TTL キャッシュ）。失敗時のみ `LLAMA_SLOT_COUNT` フォールバック
- RubyLLM は履歴全文を送る契約のまま。キャッシュは **プレフィックス一致時の prefill 再計算を省略**するだけで、ペイロードサイズは減らない

設定: `LLAMA_CACHE_PROMPT`（既定 `true`）、`LLAMA_SLOT_COUNT`（既定 `0` = props のみ）、`LLAMA_AUX_SLOT_COUNT`（既定 `1`）

### 2.2 キャッシュフレンドリなメッセージ順

`Chat#to_llm` の方針:

1. 安定した system プレフィックス（ツール指示など）を先に載せる
2. 履歴メッセージ
3. **変動する要約・RAG は system に載せない**（最新ユーザーメッセージへ prepend）

これにより会話が伸びても、共有プレフィックスがバイト一致しやすくなり KV cache が再利用される。

### 2.3 メモ RAG のツール化（既定）

| `MEMO_RAG_MODE` | 動作 |
|-----------------|------|
| **`tool`（既定）** | 毎ターンの自動注入なし。モデルが必要時に `recall_memos` を呼ぶ |
| `inject` | 従来どおり毎ターンハイブリッド RAG を同期実行し、最新ユーザーメッセージへ注入 |

- パイプライン本体は `ChatMemoRagInjector.context_for`（vector + 徒然キーワード RRF → 圧縮 → 整形）
- `search_memos` はキーワード一覧探索、`recall_memos` は意味検索による関連抜粋、`get_memo` は全文取得

通常チャット（メモ参照不要）では embeddings / 徒然 API 往復が **前処理から消える**。メモが必要なターンはツール往復が増えるトレードオフ。

### 2.4 TTFT / 前処理の計測

assistant メッセージに保存し、Chat UI のメタに表示する。

| カラム / UI ラベル | 意味 |
|--------------------|------|
| `context_build_elapsed_ms` / **前処理** | `Chat#to_llm` 全体（RAG・要約・props 等） |
| `first_chunk_elapsed_ms` / **初回応答** | ジョブ開始〜最初の content/thinking チャンク（TTFT 近似） |
| `thinking_elapsed_ms` / **思考** | thinking チャンク開始〜本文開始 |
| `response_elapsed_ms` / **経過** | ジョブ全体 |

同じチャットを 2 回投げて比較すると、前処理・キャッシュミス・生成のどれが支配的か切り分けられる。

---

## 3. 計測結果（参考）

条件: 検索なし・画像なし・メモ RAG ツール化前の計測（前処理は既に小さい）。同一チャットの 1 回目（cold 寄り）と 2 回目（warm）。

| 指標 | 1 回目 | 2 回目 | 読み取り |
|------|--------|--------|----------|
| 前処理 | 0.2s | 0.2s | RAG/要約は主因ではない |
| 初回応答 (TTFT) | 8.0s | 4.1s | prompt cache / slot が効いている |
| 思考 | 18.3s | 10.3s | gpt-oss reasoning が支配的 |
| 経過（合計） | 32.4s | 20.7s | 残りはほぼ生成スループット |

結論:

- **アプリ側のキャッシュ／前処理まわりは意図どおり動いている**
- warm 時の体感遅さの大半は **思考トークン生成**（キャッシュでは縮まらない）
- cold の約 1.5〜2 倍ペナルティは、サーバ側の常駐設定で扱う（§4.4）。Nyoy からの定期 ping は廃止済み

`MEMO_RAG_MODE=tool` 後は、メモ不要ターンの前処理はさらに小さくなる想定。メモ参照ありターンはツール往復分が増える。

---

## 4. 改善施策と検討案件

優先度は「体感への影響」ベース。実装判断は別途。

### 4.1 `reasoning_effort` の設定化（実装・GPT-OSS実測済み）

| 項目 | 内容 |
|------|------|
| 狙い | gpt-oss の思考時間（現状 warm で約 10s）を削減 |
| 実装 | `low` / `medium` / `high` をサンプリングプリセット、接続プロファイル、チャット個別設定から指定 |
| トレードオフ | 回答品質・推論の深さ |
| メモ | 未指定時はリクエストへ含めず、サーバー既定を維持。対応モデルでのみ指定する |

優先順位は既存サンプリング設定と同じく、アプリ既定プリセット → 接続プロファイル → チャット個別設定（後勝ち）。`FinalAnswerSynthesizer` の main profile にも有効なチャット設定として伝播する。比較手順と記録方法は [Chat reasoning_effort 実運用確認 Runbook](./chat-reasoning-effort-runbook.md) を参照する。

2026-07-21に`gpt_oss`をport `10014`の`gpt-oss-20b`へ切り替え、A1/A2/B1/B2を実測した。coldなA1を除くと最初の生成chunkは664–729 ms、総時間は14.9–16.0秒で、`low`と未指定に再現性のある差はなかった。既定値は変更しない。詳細は [Chat reasoning_effort 実運用確認 Runbook](./chat-reasoning-effort-runbook.md) を参照する。

### 4.2 ツール往復コストの抑制

| 項目 | 内容 |
|------|------|
| 狙い | `recall_memos` / `web_search` / `fetch_url` 利用時の「ツール呼び出し生成 → 実行 → 本回答」往復を抑える |
| 案 | ツール結果の長さ上限、オーケストレーション指示の調整、不要な連続呼び出しの抑制（Web は既に per-turn budget あり） |
| メモ | 通常チャットは速くなる一方、メモ／Web 依存ターンは遅くなるのは仕様 |

第一段階として、同一ターン内の同一 URL 再取得に加え、空白・大文字小文字・Unicode 表記を正規化した同一検索クエリの再実行も拒否する。AgentGraph では検索済みクエリを budget snapshot に保存し、checkpoint 再開後も重複を防ぐ。ユーザーが URL を明示した場合は `web_search` を挟まず `fetch_url` を直接使うよう orchestration prompt に明記した。

第二段階では、実測で5件18,845 bytes、1件最大4,314文字だった `web_search` のスニペットを1件600文字へ制限した。同一検索で変更後は4,562 bytesとなり、約76%削減した。切り詰めた結果には `content_truncated: true` を付け、詳細が必要なページだけ `fetch_url` へ進む。URL、タイトル、検索件数は削らないため、情報源の選定能力を維持しながら次のLLM入力を抑える。

本文・メモ抜粋の上限をさらに減らす変更は回答品質へ直接影響するため、ツール利用ターンの実測後に判断する。

第三段階では `search_fetched_page` の近接ヒットを同一箇所としてまとめる。実測した Rails Guide では4件6,035 bytesのうち、開始位置が11文字しか違わない1,400文字の抜粋が重複していた。抜粋範囲が重なるヒットは先頭だけを残し、変更後は2件3,162 bytes（約48%削減）となった。離れた本文箇所へ返却枠を使うため、同じ段落の重複で有用な箇所が押し出されることも防ぐ。

第四段階では `recall_memos` の同一メモ由来チャンクを1つの見出しへまとめる。本文チャンクは維持し、完全に同一の本文だけを除外する。実測した「登山計画」では3チャンクがすべて同じメモ由来で、見出しを3件から1件へまとめ、1,823 bytesから1,535 bytes（約16%削減）となった。

### 4.3 同一 llama.cpp への他用途競合

| 項目 | 内容 |
|------|------|
| 狙い | Chat 以外の LLM 呼び出しが sticky slot の KV を evict しないようにする |
| リスク源 | `ChatHistorySummarizer` / `MemoKnowledgeChunkCompressor`（LLM 圧縮は既定オフ）、style plan、その他 `LlamaCppClient` |
| 案 | Chat 専用インスタンス、slot 帯の分離、非 Chat 呼び出しに別 `id_slot` 方針 |
| メモ | `gpt_oss`は専用port `10014`へbinding済み。URL未設定時だけ`llama_cpp`へフォールバックする |

`total_slots >= 2` の場合、末尾 `LLAMA_AUX_SLOT_COUNT` slotsをAgentGraphのintent・planner・draft・evidence evaluator・final answer用に予約し、通常Chatは残りのslotだけを使う。補助処理同士の衝突より、対話のsticky cache保護を優先する。`LLAMA_AUX_SLOT_COUNT=0`で従来どおり全slot共有へ戻せる。

2026-07-20 の初回development確認では、登録された全llama-serverが`total_slots=1`だった。その後`--parallel 2`で再起動し、全6接続で`total_slots=2`を確認した。Nyoyの割当は通常Chat=`slot 0 / pool chat`、AgentGraph補助LLM=`slot 1 / pool auxiliary`となり、全接続で分離できた。

再起動や構成変更後は次のコマンドで実効割当を確認する。

```bash
bin/rails runner - <<'RUBY'
ChatLlamaCache.clear_props_cache!
ServiceConnection.chat_backends.enabled.order(:key).each do |connection|
  model = Model.find_by(provider: "openai", model_id: connection.server_model)
  next unless model

  chat = Chat.new(id: 101, model: model)
  normal = ChatLlamaCache.metadata_for(chat, model: model)
  auxiliary = ChatLlamaCache.metadata_for(
    chat,
    model: model,
    slot_key: "agent_graph:final:101:#{model.model_id}"
  )
  puts JSON.generate(
    key: connection.key,
    total_slots: normal[:slot_count],
    chat_slot: normal[:slot_id],
    auxiliary_slot: auxiliary[:slot_id],
    separated: normal[:slot_id] != auxiliary[:slot_id]
  )
end
RUBY
```

### 4.4 サーバ側のモデル常駐

| 項目 | 内容 |
|------|------|
| 狙い | idle unload がある場合の cold start をインフラ側で根絶 |
| 案 | llama-server の常駐設定（unload 無効化等） |
| メモ | サーバ設定は Nyoy リポジトリ外。クライアント側の 5 分 ping（`LlamaWarmupJob`）は廃止済み |

2026-07-20、`--parallel 2`での再起動後に5つのユニークなサーバーURLを確認し、すべて`is_sleeping=false`、`endpoint_slots=true`、`total_slots=2`だった。起動直後の常駐・slot endpointは正常。idle unloadが無効であることの確定には、サーバー設定の確認または長時間アイドル後に`is_sleeping=false`のままかと1通目のTTFTを再確認する。

### 4.5 効果の小さい項目

- ストリーム毎の Turbo `broadcast_rendered_content!` の間引き
- `CHAT_CONTEXT_TURNS` のさらなる削減（prefill はキャッシュで緩和済み）
- `max_tokens` / thinking 上限の明示

計測上は主因ではない。必要になったら検討。

### 4.6 OpenAI 接続設定の整理

| 項目 | 内容 |
|------|------|
| 狙い | ローカル llama-server 互換用のダミー API キーと、実 OpenAI API キーの扱いを分離する |
| 対応 | 実OpenAI用を `OPENAI_CHAT_API_KEY`、llama-server互換用を `OPENAI_API_KEY=local` に分離 |
| 互換性 | `OPENAI_CHAT_API_KEY` 未設定時は、`local` 以外の従来 `OPENAI_API_KEY` を実OpenAIキーとして受け付ける |
| seed | `local` はOpenAI接続のtokenとして保存せず、新規接続を有効化しない |
| env-only | `OPENAI_CHAT_API_KEY` があればDB `api_token` が空でも有効化でき、接続画面には秘密値を出さず「環境変数」と表示する |

### 4.7 再計測チェックリスト

施策後やモデル差し替え後に確認する項目:

1. 同一チャットを 2 回連投し、UI の **前処理 / 初回応答 / 思考 / 経過** を記録
2. 長時間アイドル後の 1 通目が warm 相当か（サーバ常駐の効果）
3. `recall_memos` を使う質問と使わない質問で前処理・往復回数の差
4. llama-server の prompt eval / cache hit ログ（可能なら）

---

## 5. 設定早見

| 環境変数 | 既定 | 役割 |
|----------|------|------|
| `LLAMA_CACHE_PROMPT` | `true` | KV cache 再利用 |
| `LLAMA_SLOT_COUNT` | `0` | `/props` 失敗時の slot 数フォールバック |
| `LLAMA_AUX_SLOT_COUNT` | `1` | 複数 slot 時に補助 LLM へ予約する末尾 slot 数 |
| `MEMO_RAG_ENABLED` | `true` | メモ RAG 全体の有効化 |
| `MEMO_RAG_MODE` | `tool` | `tool` / `inject` |
| `MAIN_LLM_TOOL_MODE` | `restricted` | 通常 Chat のメインLLMに渡すツール範囲（既定は読み取り系のみ） |
| `MAIN_LLM_TOOL_ALLOWLIST` | | カンマ区切りでメインLLM用ツールを明示指定 |
| `CHAT_CONTEXT_TURNS` | `10` | 送信する直近ターン数 |

リコールを優先して毎ターンメモを載せたい場合は `MEMO_RAG_MODE=inject`。

---

## 6. まとめ

| 区分 | 状態 |
|------|------|
| prompt cache / sticky slot | **実装済み** |
| 要約・RAG をプレフィックス外へ | **実装済み** |
| RAG ツール化（既定） | **実装済み** |
| TTFT / 前処理計測 | **実装済み** |
| アイドルウォームアップ（5 分 ping） | **廃止**（サーバ常駐は §4.4） |
| `reasoning_effort` | **実装済み・実測待ち**（§4.1） |
| ツール往復・slot 競合・サーバ常駐 | **検討案件**（§4.2–4.4） |
| OpenAI 接続設定整理 | **検討案件**（§4.6） |

アプリ側で効く「キャッシュが効かない／毎ターン重い前処理」系は完了。追加の体感改善は **生成側（reasoning）と運用・インフラ** が中心。
