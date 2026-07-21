#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/production_env.sh
source "${APP_ROOT}/scripts/production_env.sh"

bin/rails db:prepare
bin/rails runner "LlmUsageAssignmentSeeds.seed!"
STRICT=1 bin/rails llm_usages:audit

exec bundle exec puma -C config/puma.rb
