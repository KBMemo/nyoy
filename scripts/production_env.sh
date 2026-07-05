# shellcheck shell=bash
# 本番サーバー向け: rbenv / PATH と .env.production を読み込む。
# bin/prod / bin/deploy から source する。

if [[ -z "${APP_ROOT:-}" ]]; then
  APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
cd "${APP_ROOT}"

export PATH="${HOME}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

export RBENV_ROOT="${HOME}/.rbenv"
if [[ -d "${RBENV_ROOT}/bin" ]]; then
  export PATH="${RBENV_ROOT}/bin:${PATH}"
  eval "$(rbenv init - bash)"
fi

ENV_FILE="${APP_ROOT}/.env.production"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "missing ${ENV_FILE}" >&2
  return 1 2>/dev/null || exit 1
fi

set -a
# shellcheck source=/dev/null
source "${ENV_FILE}"
set +a

export RAILS_ENV="${RAILS_ENV:-production}"
export RAILS_MASTER_KEY="${RAILS_MASTER_KEY:-$(cat "${APP_ROOT}/config/master.key")}"
export SOLID_QUEUE_IN_PUMA="${SOLID_QUEUE_IN_PUMA:-true}"
export PORT="${PORT:-3009}"
