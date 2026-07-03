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
| `TsuzuraClient` | `GET /v1/albums`, `GET /v1/media/:id`, `POST /v1/media/batch` |
| `TsuzuraMediaUploader` | Chat 添付 → `Nyoy Chat` アルバムへアップロード |
| `ChatTools::ListAlbums` | アルバム一覧 |
| `ChatTools::GetMedia` | メディアメタデータ取得 |
| `analyze_image` | 結果に `tsuzura_media_id` を含める（アーカイブ済みの場合） |

## Chat ツール

| ツール | 用途 |
|--------|------|
| `list_albums` | 葛籠アルバム一覧 |
| `get_media` | ULID でメタデータ参照 |
| `analyze_image` | 添付画像の vision 解析（従来どおりローカル blob 使用） |

徒然メモへ画像を埋め込むときの AsciiDoc 例（葛籠側 batch API の `asciidoc` フィールドと同型）:

```asciidoc
image::media:01JH…[]
```

## API パス（葛籠側）

如意は `{TSUZURA_URL}/v1/...` を呼ぶ。詳細は kbmemo-media の [README](https://gitea.artif.org/Artif.org/kbmemo_site/src/branch/main/kbmemo-media/README.md) を参照。

## 今後（Phase 5b 以降）

- 生成画像（`image_generations` 等）の葛籠アーカイブ
- Bearer 認証でのバイナリ GET（現状 web 配信はメモ署名 URL のみ）
- 徒然 `create_memo` と連携した `image::media:` 自動挿入
- MCP 公開（Phase 6）で `list_albums` / `get_media` を再掲

## 関連

- [エコシステムロードマップ](./ecosystem-roadmap.md)
- [徒然 API 要件](./tsuredure-api-requirements.md)
