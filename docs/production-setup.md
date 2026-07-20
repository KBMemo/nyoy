# 本番環境セットアップ（bowmore:sites/nyoy）

Nyoy を `bowmore` サーバーの `~/sites/nyoy` に配置し、systemd + nginx で運用する手順です。

PostgreSQL・SearXNG・readability は既に bowmore 上で動作している前提です（README のデフォルト接続先と同じ）。

## 構成概要

```
[ブラウザ]
    ↓ HTTPS
[nginx on bowmore]  →  proxy_pass → 127.0.0.1:3009
                                        ↓
                              [Puma + Solid Queue in Puma]
                                        ↓
                    PostgreSQL (bowmore.artif.org:5432)
                    nyoy_production / _cache / _queue / _cable
```

| 項目 | 値 |
|------|-----|
| デプロイ先 | `bowmore:~/sites/nyoy` |
| デプロイユーザー | `kensei` |
| 待受ポート | `3009`（`.env.production` の `PORT`） |
| systemd ユニット | `~/.config/systemd/user/nyoy.service`（`systemctl --user`） |
| 公開 URL | `https://nyoy.kbmemo.net` |

## 1. bowmore 側の事前準備

### 1.1 パッケージ

```bash
# bowmore に SSH
ssh bowmore

# Ruby ビルド用（rbenv 利用時）
sudo apt-get update
sudo apt-get install -y build-essential libssl-dev libreadline-dev zlib1g-dev \
  libpq-dev libvips-dev libyaml-dev git curl nodejs npm

# rbenv + ruby-build が未導入ならインストール（既存環境に合わせて省略可）
```

system packageのNodeを使わずNVMで管理する場合は、default aliasを設定する。`scripts/production_env.sh`はsystem Nodeが見つからないときだけ `~/.nvm/nvm.sh` を読み込む。

```bash
nvm alias default 22
```

### 1.2 Ruby 4.0.3

```bash
rbenv install 4.0.3   # 未インストールの場合
rbenv global 4.0.3    # または local で sites/nyoy 配下のみ
ruby -v               # => 4.0.3
gem install bundler
```

### 1.3 PostgreSQL データベース

bowmore の PostgreSQL に接続し、本番用 DB とユーザーを作成します。

```sql
-- psql -h bowmore.artif.org -U postgres など管理者で接続

CREATE USER nyoy WITH PASSWORD '***';
CREATE DATABASE nyoy_production OWNER nyoy;
CREATE DATABASE nyoy_production_cache OWNER nyoy;
CREATE DATABASE nyoy_production_queue OWNER nyoy;
CREATE DATABASE nyoy_production_cable OWNER nyoy;

-- primary DB に pgvector（マイグレーションでも有効化されますが、事前作成推奨）
\c nyoy_production
CREATE EXTENSION IF NOT EXISTS vector;
```

`config/database.yml` の production は上記 4 DB を使います。認証情報は Rails credentials に登録します。

## 2. アプリケーションの初回配置

### 2.1 リポジトリのクローン

```bash
ssh bowmore
mkdir -p ~/sites
cd ~/sites
git clone <リポジトリURL> nyoy
cd nyoy
git checkout main   # デプロイブランチ
```

### 2.2 秘密情報

**開発マシン**で credentials を編集し、本番 DB ユーザーを登録します。

```bash
bin/rails credentials:edit
```

```yaml
database:
  username: nyoy
  password: "***"
```

**bowmore** に `config/master.key` を配置します（git 管理外のため手動コピー）。

```bash
# 開発マシンから
scp config/master.key kensei@bowmore:~/sites/nyoy/config/master.key
```

### 2.3 本番環境変数

bowmore 上で `.env.production` を作成します（git 管理外）。

```bash
cd ~/sites/nyoy
cp .env.example .env.production
$EDITOR .env.production
```

最低限設定する項目:

```bash
PORT=3009
RAILS_ENV=production
RAILS_LOG_LEVEL=info
SOLID_QUEUE_IN_PUMA=true
RAILS_MASTER_KEY=<config/master.key と同じ値>

# PostgreSQL（本番では DB_* を明示推奨）
DB_HOST=127.0.0.1
DB_USERNAME=nyoy
DB_PASSWORD=***
DB_NAME=nyoy_production
DB_CACHE_NAME=nyoy_production_cache
DB_QUEUE_NAME=nyoy_production_queue
DB_CABLE_NAME=nyoy_production_cable

# 外部 AI サービス（balvenie 等、ネットワーク到達可能な URL に変更）
LLAMA_CPP_URL=http://balvenie:10010
LLAMA_SWITCHD_URL=http://balvenie:11335
LLAMA_SWITCHD_TOKEN=...
LLAMA_SERVER_ADMIN_TOKEN=...
# LLAMA_SERVER_ALERT_WEBHOOK_URL=https://alerts.example.com/hooks/nyoy
# LLAMA_SERVER_ALERT_WEBHOOK_TOKEN=...
GPT_OSS_LLAMA_CPP_URL=http://balvenie:10014
VISION_LLAMA_CPP_URL=http://balvenie:10021
EMBEDDINGS_URL=http://balvenie:10020
SDCPP_SERVER_URL=http://balvenie:11234
SDCPP_SWITCHD_URL=http://balvenie:11334
# SDCPP_SWITCHD_TOKEN=...

# bowmore 上の既存サービス
SEARFRONT_URL=http://bowmore:13000
SEARFRONT_TOKEN=...
# 互換（非推奨）: SEARXNG_URL / SEARXNG_API_TOKEN
READABILITY_URL=http://bowmore:8030

# 徒然・葛籠（本番トークンを設定）
KBMEMO_URL=https://kbmemo.net
# KBMEMO_API_TOKEN=kbmemo_...
# TSUZURA_URL=...
# TSUZURA_API_TOKEN=tsuzura_...
```

`RAILS_MASTER_KEY` は `config/master.key` の内容と同じ値です（`.env.production` に書くか、手動実行時は `bin/prod` を使います）。

bowmore 上で `bin/rails` を直接叩く場合は、徒然（kbmemo）と同様に `scripts/production_env.sh` を読み込んでください。`.env.production` だけでは変数が子プロセスに export されず、rbenv も有効になりません。

```bash
# 推奨
bin/prod dbconsole

# または手動で（set -a が必須）
source scripts/production_env.sh
bin/rails dbconsole
```

`bin/prod` は `scripts/production_env.sh` 経由で rbenv / `.env.production` / `RAILS_MASTER_KEY` を設定してから `rails` を実行します。

`.env.production` の `DB_PASSWORD` など `!` を含む値は、クォート推奨です。

```bash
DB_PASSWORD='Hoge3Gou!33'
```

### 2.4 初回ビルド

```bash
cd ~/sites/nyoy

bundle config set --local deployment 'true'
bundle config set --local without 'development test'
bundle install
npm ci

set -a && source .env.production && set +a
export RAILS_ENV=production

bundle exec rails db:prepare
bundle exec rails db:seed          # 初回のみ（スタイル・接続 seed）
bundle exec rails assets:precompile
```

`db:prepare` で primary / cache / queue / cable のマイグレーションが走ります。

### 2.5 storage ディレクトリ

Active Storage はローカルディスク（`storage/`）を使います。永続化のため権限を確認してください。

```bash
mkdir -p storage tmp/pids log
chmod 755 storage
```

## 3. systemd ユーザーユニット

システム全体（`/etc/systemd/system/`）ではなく、**ユーザー `kensei` の systemd**（`~/.config/systemd/user/`）に登録します。`sudo` は不要です。

リポジトリの `config/systemd/user/nyoy.service` をコピーします。

```bash
mkdir -p ~/.config/systemd/user
cp ~/sites/nyoy/config/systemd/user/nyoy.service ~/.config/systemd/user/nyoy.service
```

ユニットの例（`%h` はホームディレクトリ）:

```ini
[Unit]
Description=Nyoy Rails app
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=%h/sites/nyoy
ExecStart=%h/sites/nyoy/start.sh
ExecReload=/bin/kill -USR1 $MAINPID
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

環境変数は `start.sh` → `scripts/production_env.sh` 経由で読み込みます（`.env.production` を直接ユニットに書く必要はありません）。

ログインセッションなしでも起動し続けるには linger を有効にします（初回のみ）。

```bash
loginctl enable-linger "${USER}"
```

有効化・起動:

```bash
systemctl --user daemon-reload
systemctl --user enable nyoy
systemctl --user start nyoy
systemctl --user status nyoy
```

ログ確認:

```bash
journalctl --user -u nyoy -f
```

## 4. nginx リバースプロキシ

`/etc/nginx/sites-available/nyoy` の例:

```nginx
server {
    listen 80;
    server_name nyoy.kbmemo.net;

    client_max_body_size 50M;

    location / {
        proxy_pass http://127.0.0.1:3009;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/nyoy /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

HTTPS は certbot 等で `nyoy.kbmemo.net` に証明書を設定してください。証明書導入後は `config/environments/production.rb` の `config.assume_ssl` / `config.force_ssl` のコメントを外すことを検討してください。

## 5. 動作確認

```bash
# ヘルスチェック
curl -s http://127.0.0.1:3009/up

# メモ RAG 初回取込（任意）
cd ~/sites/nyoy
bin/prod kbmemo:rag:ingest
```

ブラウザで `https://nyoy.kbmemo.net` を開き、メモ挿絵・Chat・画像生成が動くことを確認します。

## 6. 2 回目以降のデプロイ

**bowmore 上**で実行します（`ssh` は不要）。

```bash
cd ~/sites/nyoy
bin/deploy
```

オプション:

```bash
bin/deploy --check          # 環境確認のみ
bin/deploy --branch main    # 指定ブランチを pull
bin/deploy --no-seed        # db:seed をスキップ（通常デプロイ）
bin/deploy --seed           # db:seed を実行（seed 更新時）
bin/deploy --skip-restart   # git pull〜assets まで。再起動は手動
```

環境変数:

```bash
NYOY_SYSTEMD_UNIT=nyoy \
NYOY_HEALTH_URL=https://nyoy.kbmemo.net/up \
bin/deploy
```

LLMサーバー管理認証を変更した場合は、デプロイ後に非破壊スモークテストを実行します。

```bash
set -a
source .env.production
set +a
NYOY_URL=https://nyoy.kbmemo.net bin/verify-llama-server-admin
```

詳細は [llama-switchd 運用 Runbook](./llama-switchd-runbook.md) を参照してください。

2026-07-21、NVM default `v22.14.0` を `scripts/production_env.sh` が自動解決する状態で、PATHの手動補完なしにrevision `00fde05` のdeploy、npm ci、assets precompile、systemd再起動、health checkが完走した。

## 7. トラブルシュート

| 症状 | 確認 |
|------|------|
| `no password supplied` | `.env.production` に `DB_USERNAME` / `DB_PASSWORD` があるか。bowmore の credentials が `database:` ではなく `db:` 形式だと `config/database.yml` から読めない |
| `127.0.1.1` に接続している | `bowmore.artif.org` が `/etc/hosts` で 127.0.1.1 に解決されている（正常）。`DB_HOST=127.0.0.1` で明示可 |
| `key must be 16 bytes` | `.env.production` の `RAILS_MASTER_KEY` が `config/master.key` と一致しているか（改行・欠損なし） |
| 502 Bad Gateway | `systemctl --user status nyoy`、ポート `PORT` と nginx の `proxy_pass` が一致しているか |
| DB 接続エラー | credentials の `database.username/password`、`pg_hba.conf`、DB 存在 |
| アセット 404 | `RAILS_ENV=production bundle exec rails assets:precompile` を再実行 |
| ジョブが動かない | `.env.production` に `SOLID_QUEUE_IN_PUMA=true`、`journalctl --user -u nyoy` で Solid Queue ログ |
| ログアウト後に停止する | `loginctl enable-linger "${USER}"` を実行しているか |
| pgvector エラー | `nyoy_production` で `CREATE EXTENSION vector;` |
| 画像が保存されない | `storage/` の書き込み権限、ディスク容量 |

## 8. Kamal（Docker）でのデプロイ（代替）

リポジトリには Kamal 設定（`config/deploy.yml`）も含まれています。コンテナ運用に切り替える場合:

1. `config/deploy.yml` の `servers.web` を bowmore の IP/ホストに変更
2. `.kamal/secrets` に `RAILS_MASTER_KEY` を設定
3. `bin/kamal setup && bin/kamal deploy`

従来型（`sites/nyoy`）と Kamal は併用しないでください。
