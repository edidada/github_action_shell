#!/usr/bin/env bash
# 本地一键把本仓库 push 到 config/accounts.env 中列出的所有 GitHub 账号。
#
# 用法：
#   bash scripts/push-all-remotes.sh                # 推送当前分支到所有账号
#   bash scripts/push-all-remotes.sh --all-branches # 推送所有分支与标签
#   bash scripts/push-all-remotes.sh --dry-run      # 只打印将要执行的动作
#
# 远端说明：
#   - 若某账号对应的 remote 已存在（比如你用 SSH alias 配过 ~/.ssh/config），脚本直接使用
#   - 否则自动创建 HTTPS remote，并借助本机 `gh auth switch` 切换到对应账号推送
#   - 结束后会把 gh 的 active 账号恢复原状
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

need_cmd git

DRY_RUN=0
ALL_BRANCHES=0
for a in "$@"; do
  case "$a" in
    --dry-run)      DRY_RUN=1 ;;
    --all-branches) ALL_BRANCHES=1 ;;
    *) log_warn "未知参数: $a" ;;
  esac
done

REPO_NAME="${REPO_NAME:-$(basename "$GAS_ROOT")}"
BRANCH="${BRANCH:-$(git -C "$GAS_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"

# 记录 gh 当前 active 账号，结束时恢复
PREV_ACTIVE=""
if need_cmd gh 2>/dev/null; then
  PREV_ACTIVE="$(gh api user --jq '.login' 2>/dev/null || true)"
fi
restore_gh() {
  if [[ -n "$PREV_ACTIVE" ]] && need_cmd gh 2>/dev/null; then
    gh auth switch --user "$PREV_ACTIVE" >/dev/null 2>&1 || true
    log_info "已恢复 gh active 账号为: $PREV_ACTIVE"
  fi
}
trap restore_gh EXIT

PUSH_SPEC=( "$BRANCH" )
(( ALL_BRANCHES )) && PUSH_SPEC=( --all --tags )

failed=0
while read -r acct; do
  [[ -z "$acct" ]] && continue
  remote_url="https://github.com/${acct}/${REPO_NAME}.git"

  # remote 不存在则自动添加
  if ! git -C "$GAS_ROOT" remote get-url "$acct" >/dev/null 2>&1; then
    log_info "添加 remote ${acct} -> ${remote_url}"
    (( DRY_RUN )) || git -C "$GAS_ROOT" remote add "$acct" "$remote_url"
  else
    log_info "remote ${acct} 已存在: $(git -C "$GAS_ROOT" remote get-url "$acct")"
  fi

  log_step "推送 -> ${acct}/${REPO_NAME} (${BRANCH})"
  if (( DRY_RUN )); then
    echo "    git push ${acct} ${PUSH_SPEC[*]}"
    continue
  fi

  # 切到对应账号，让 gh credential helper 使用该账号的 token
  if need_cmd gh 2>/dev/null; then
    gh auth switch --user "$acct" >/dev/null 2>&1 \
      && log_info "  已切换 gh 账号: ${acct}" \
      || log_warn "  无法切换 gh 到 ${acct}（未登录？），将沿用当前凭证"
  fi

  if git -C "$GAS_ROOT" push "$acct" "${PUSH_SPEC[@]}"; then
    log_ok "  ✓ ${acct} 完成"
  else
    failed=1
    log_err "  ✗ ${acct} 失败。"
    log_err "    排查：该账号下是否已存在 ${REPO_NAME} 仓库？PAT 是否含 'repo' scope？"
    log_err "    也可改用 SSH：git remote set-url ${acct} git@github.com-${acct}:${acct}/${REPO_NAME}.git"
  fi
done < <(read_accounts)

exit $failed
