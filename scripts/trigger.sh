#!/usr/bin/env bash
# 触发 driver 仓库执行私有源仓库的 CI。
#
# 用法：
#   bash scripts/trigger.sh driver  [source_repo] [source_ref] [profile] [entrypoint]
#   bash scripts/trigger.sh dispatch [source_repo] [source_ref] [driver_owner/repo]
#
#   manual   -> gh workflow run，等价于页面上点 Run workflow
#   dispatch -> repository_dispatch，模拟外部系统/webhook 触发
#               私有源仓库 Actions 时长耗尽时，推荐用它从本地或任何能联网的地方发起构建
# 提示：dispatch 需要 gh token 具备 repo scope（默认登录 token 已含）
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

need_cmd gh

MODE="${1:-driver}"
SRC_REPO="${2:-cpp_ecshop}"
SRC_REF="${3:-}"
PROFILE="${4:-auto}"
ENTRYPOINT="${5:-auto}"
REPO_NAME="${REPO_NAME:-$(basename "$GAS_ROOT")}"
PRIMARY="$(primary_account)"

case "$MODE" in
  driver|manual)
    [[ "$MODE" == "manual" ]] && SRC_REPO="${2:-cpp_ecshop}" && SRC_REF="${3:-}"
    args=( --repo "${PRIMARY}/${REPO_NAME}" -f "source_repo=${SRC_REPO}" -f "profile=${PROFILE}" -f "entrypoint=${ENTRYPOINT}" )
    [[ -n "$SRC_REF" ]] && args+=( -f "source_ref=${SRC_REF}" )
    log_step "gh workflow run run-source.yml ${args[*]}"
    gh workflow run run-source.yml "${args[@]}"
    log_ok "已触发。查看：https://github.com/${PRIMARY}/${REPO_NAME}/actions"
    ;;
  dispatch)
    full="${4:-${PRIMARY}/${REPO_NAME}}"
    payload=( -f "event_type=run-source-script" -f "client_payload[source_repo]=${SRC_REPO}" )
    [[ -n "$SRC_REF" ]] && payload+=( -f "client_payload[source_ref]=${SRC_REF}" )
    log_step "gh api repos/${full}/dispatches ${payload[*]}"
    gh api "repos/${full}/dispatches" "${payload[@]}" --silent
    log_ok "已派发到 ${full}。查看：https://github.com/${full}/actions"
    ;;
  *)
    die "未知模式: ${MODE}（可选 driver / dispatch）"
    ;;
esac
