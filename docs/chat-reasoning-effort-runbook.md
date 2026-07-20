# Chat reasoning_effort 実運用確認 Runbook

Chat の `reasoning_effort` が対応モデルへ渡り、思考時間を短縮できるかを通常の UI 経路で比較する。速度だけでなく回答品質も確認し、既定値の変更は比較後に判断する。

## 1. 前提

- Nyoy development が起動している
- `gpt_oss` 接続が有効で、接続先 llama-server に gpt-oss がロードされている
- `MEMO_RAG_MODE=tool` など、比較中の環境設定が同一である
- Web 検索やメモ参照を必要としない質問を使う

接続 URL を確認する。

```bash
GPT_OSS_URL="$(bin/rails runner 'puts ServiceConnection.find_by!(key: "gpt_oss").base_url')"
printf '%s\n' "$GPT_OSS_URL"
curl -fsS "$GPT_OSS_URL/health"
curl -fsS "$GPT_OSS_URL/props" | ruby -rjson -e '
  props = JSON.parse(STDIN.read)
  puts JSON.pretty_generate(
    model_path: props["model_path"],
    model_alias: props["model_alias"],
    model: props.dig("default_generation_settings", "params", "model")
  )
'
```

`model_path`、`model_alias`、`model` のいずれからも gpt-oss と確認できない場合は測定しない。別モデルの結果を gpt-oss の `reasoning_effort` の効果として記録できないため、先に llama-server のロードモデルまたは接続 URL を直す。

## 2. 比較条件

同じ質問で次の4回を実行する。各回は新しいチャットにし、モデルは gpt-oss を選ぶ。

| 順序 | `reasoning_effort` | 目的 |
| --- | --- | --- |
| A1 | 未指定 | サーバー既定、cold寄り |
| A2 | `low` | low、warm寄り |
| B1 | `low` | low、cold寄り |
| B2 | 未指定 | サーバー既定、warm寄り |

順序を反転した2組で、モデルのウォームアップや一時的な負荷を一方の設定だけが受ける偏りを減らす。ほかのサンプリング値はすべて同じにする。

推奨質問:

```text
Ruby on RailsのActive Jobで、失敗したジョブを再試行する設計上の注意点を3点、簡潔に説明してください。
```

チャット設定ダイアログで `reasoning_effort` だけを変更して送信する。回答後、UI に表示される `前処理`、`初回応答`、`思考`、`経過` と回答本文を記録する。

## 3. DBから結果を抽出

計測用チャットの ID を空白区切りで指定する。

```bash
CHAT_IDS="101 102 103 104" bin/rails runner - <<'RUBY'
ids = ENV.fetch("CHAT_IDS").split.map { |value| Integer(value, 10) }
rows = Chat.where(id: ids).order(:id).map do |chat|
  answer = chat.messages.where(role: :assistant).where.not(content: [nil, ""]).order(:id).last
  {
    chat_id: chat.id,
    reasoning_effort: chat.llm_params["reasoning_effort"] || "unset",
    context_build_ms: answer&.context_build_elapsed_ms,
    first_chunk_ms: answer&.first_chunk_elapsed_ms,
    thinking_ms: answer&.thinking_elapsed_ms,
    response_ms: answer&.response_elapsed_ms,
    answer: answer&.content
  }
end
puts JSON.pretty_generate(rows)
RUBY
```

## 4. 判定

次をすべて確認する。

1. `low` のチャットだけ `chats.llm_params["reasoning_effort"] == "low"` になっている
2. 全回答がエラーや token 上限による尻切れなしで完了する
3. A組とB組の両方で、`low` の `thinking_ms` または `response_ms` が短くなる
4. `low` でも質問へ直接答え、重要な注意点や正確性が失われていない
5. llama-server ログまたはリクエストログで `reasoning_effort: low` を確認できる

1回ずつの差だけでは既定値を変更しない。差が小さい、順序で逆転する、品質が不安定な場合は各条件を3回以上追加し、中央値で比較する。

## 5. 記録形式

| run | effort | 初回応答 | 思考 | 経過 | 品質メモ |
| --- | --- | ---: | ---: | ---: | --- |
| A1 | unset | | | | |
| A2 | low | | | | |
| B1 | low | | | | |
| B2 | unset | | | | |

`low` の短縮が再現し品質を維持できた場合に限り、gpt-oss 接続プロファイルまたはアプリ既定プリセットへの設定を検討する。全モデル共通の既定にはせず、`reasoning_effort` 対応モデルのプロファイルへ限定する。

## 6. 実機確認記録

### 2026-07-20 保留

`gpt_oss` 接続 `http://balvenie:10011` の `/health` は成功したが、`/props` の `model_path` は `gemma-4-E4B-it-qat` を示していたため測定しなかった。

### 2026-07-21 GPT-OSS

`gpt_oss`を`http://balvenie:10014`の`gpt-oss-20b`へbindingした後、switchd定義を`SLOTS=2`へ変更・再起動した。Runtimeは`model_alias=gpt-oss-20b`、`total_slots=2`で、Nyoyの割当は通常Chat=`slot 0 / chat`、AgentGraph補助LLM=`slot 1 / auxiliary`となった。

UIの表示処理を含まないモデル単体比較として、同一質問をOpenAI互換streaming APIへA1/A2/B1/B2順で送信した。

| run | effort | 最初の生成chunk | 経過 | 品質メモ |
| --- | --- | ---: | ---: | --- |
| A1 | unset | 1,999 ms | 17,099 ms | 3点を回答、cold影響あり |
| A2 | low | 701 ms | 15,800 ms | A1と同内容 |
| B1 | low | 664 ms | 14,919 ms | 3点を回答 |
| B2 | unset | 729 ms | 15,975 ms | B1と同等 |

全runは`finish_reason=stop`で完了した。coldなA1を除くと最初の生成chunkは664–729 ms、総時間は14.9–16.0秒であり、`low`と未指定に再現性のある差は確認できなかった。回答はいずれも冪等性、backoff・試行上限、監視を挙げたが、Rails API名として厳密でない表現も含まれた。速度差が小さく品質改善も確認できないため、既定`reasoning_effort`は変更しない。

この値はモデル単体の基準値である。Nyoy UI全経路の`context_build_ms`、`first_chunk_ms`、`thinking_ms`、`response_ms`は、体感遅延を再調査するときに第2–3節の手順で追加計測する。
