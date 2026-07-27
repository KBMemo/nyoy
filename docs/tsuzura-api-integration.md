# 葛籠（Tsuzura）API 連携 — Phase 5

如意（nyoy）から [葛籠（kbmemo-media）](https://media.kbmemo.net) の REST API を使うための実装メモ。

## 役割分担

| 正本 | アプリ | 如意の扱い |
|------|--------|-----------|
| メモ本文 | 徒然 | `TsurezureClient` + メモツール |
| 画像・ファイル | 葛籠 | `TsuzuraClient` + メディアツール |

Chat に添付した画像は **Active Storage（表示・vision 解析用）** に加え、葛籠が有効なら **`Nyoy Chat` アルバムへ自動アーカイブ** し、添付メタデータに `tsuzura_media_id` を保存する。

## 接続設定

| 項目 | 環境変数 | ServiceConnection key |
|------|----------|----------------------|
| ベース URL | `TSUZURA_URL`（既定 `http://localhost:3008`） | `tsuzura` |
| API トークン | `TSUZURA_API_TOKEN`（`tsuzura_…`） | 同上 |

KBMemo プロフィールで発行した `tsuzura_api_token` を使用。接続画面（`/service_connections`）でも編集可能。

## 実装済み（Phase 5a）

| コンポーネント | 内容 |
|----------------|------|
| `TsuzuraClient` | `GET /v1/albums`, `GET /v1/media/:id`, `GET /v1/media/:id/file`, `POST /v1/media/batch` |
| `TsuzuraMediaUploader` | Chat 添付 → `Nyoy Chat` アルバムへアップロード |
| `ChatTools::ListAlbums` | アルバム一覧 |
| `ChatTools::GetMedia` | メディアメタデータ取得 |
| `analyze_image` | 結果に `tsuzura_media_id` を含める（アーカイブ済みの場合） |
| `create_memo` / `update_memo` | Chat 添付の `image::media:` を本文末尾へ自動追記 |

## Chat ツール

| ツール | 用途 |
|--------|------|
| `list_albums` | 葛籠アルバム一覧 |
| `get_media` | ULID でメタデータ参照 |
| `analyze_image` | 添付画像の vision 解析（従来どおりローカル blob 使用） |
| `create_memo` / `update_memo` | 保存後に `image::media:ULID[]` を AsciiDoc で追記（Markdown 本文とは別リクエスト） |

徒然メモへ `image::media:` を挿入するときの AsciiDoc 例（自動挿入時も同型）:

```asciidoc
image::media:01JH…[]
```

## API パス（葛籠側）

如意は `{TSUZURA_URL}/v1/...` を呼ぶ。詳細は葛籠の
[README](https://github.com/KBMemo/tsuzura/blob/main/README.md)を参照。

## 実装済み（Phase 5b）

生成画像を **明示保存したときだけ** 徒然メモとして残す（一括葛籠アーカイブはしない）。

| コンポーネント | 内容 |
|----------------|------|
| `GeneratedImageMemoSaver` | 画像を `Nyoy 生成` アルバムへ upload → 徒然に Markdown メモ作成 → `image::media:` 追記 |
| `GenerationMemoBodyBuilder` | プロンプト・設定・如意 URL を Markdown 本文に整形 |
| `GenerationMemoSavesController` | 生成画面の「徒然に保存」ボタン |

対象: `image_generations`（仕上がり）、`memo_illustrations`、`img2img_generations`。

## 実装済み（Phase 5c）

| コンポーネント | 内容 |
|----------------|------|
| 葛籠 `GET /v1/media/:id/file` | Bearer 認証でバイナリ配信（`?source=original` で原画） |
| `TsuzuraClient#download_media` | 上記 API のラッパー |
| `analyze_image` | `tsuzura_media_id` 指定時は葛籠から取得して vision 解析 |

`/v1/media/:id/web` は引き続き徒然メモ用の署名 URL のみ（Bearer 不可）。

## 今後（Phase 6）

## 関連

- [エコシステムロードマップ](./ecosystem-roadmap.md)
- [徒然 API 要件](./tsuredure-api-requirements.md)
