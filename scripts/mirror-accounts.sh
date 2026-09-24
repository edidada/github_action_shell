#!/usr/bin/env bash
# 把当前仓库单向镜像到其余 GitHub 账号下的同名仓库。
# 在 Actions 中被 .github/workflows/mirror.yml 调用，也可本地执行。
#
# 环境变量：
#   MIRROR_TOKEN  具备目标仓库写权限的 PAT（必需）
#   INPUT_TARGETS 逗号分隔的目标账号（可选，覆盖 accounts.env）
#   REPO_NAME     仓库名（可选，默认取当前 git 目录名）
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

need_cmd git

TOKEN="${MIRROR_TOKEN:-}"
if [[ -z "$TOKEN" ]]; then
  log_warn "未设置 MIRROR_TOKEN，跳过镜像同步"
  exit 0
fi
mask "$TOKEN"

REPO_NAME="${REPO_NAME:-$(basename "$GAS_ROOT")}"
PRIMARY="$(primary_account)"

# 目标账号列表
targets=()
if [[ -n "${INPUT_TARGETS:-}" ]]; then
  IFS=',' read -r -a raw <<< "$INPUT_TARGETS"
  for t in "${raw[@]}"; do
    t="$(trim "$t")"
    [[ -n "$t" && "$t" != "$PRIMARY" ]] && targets+=( "$t" )
  done
else
  # 云端走 HTTPS，只需要账号名，忽略 SSH 别名列
  while read -r entry; do
    [[ -z "$entry" ]] && continue
    t="$(account_field "$entry")"
    [[ -n "$t" && "$t" != "$PRIMARY" ]] && targets+=( "$t" )
  done < <(read_accounts)
fi

if (( ${#targets[@]} == 0 )); then
  log_warn "没有需要同步的目标账号"
  exit 0
fi

log_step "开始镜像: ${REPO_NAME} -> ${targets[*]}"

failed=0
for t in "${targets[@]}"; do
  url="https://x-access-token:${TOKEN}@github.com/${t}/${REPO_NAME}.git"
  log_info "推送到 ${t}/${REPO_NAME}"
  if git push --mirror --quiet "$url" 2>&1 | sed "s|${TOKEN}|***|g"; then
    log_ok "  ✓ ${t} 同步完成"
    set_summary_line "- ✅ \`${t}/${REPO_NAME}\` 已同步"
  else
    failed=1
    log_err "  ✗ ${t} 同步失败（请确认该账号下已存在同名空仓库，且 PAT 有写权限）"
    set_summary_line "- ❌ \`${t}/${REPO_NAME}\` 同步失败"
  fi
done

exit $failed
