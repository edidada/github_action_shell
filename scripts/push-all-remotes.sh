#!/usr/bin/env bash
# 本地一键把本仓库 push 到 config/accounts.env 中列出的所有 GitHub 账号。
#
# 默认走 SSH：alias 来自 config/accounts.env 的第二列，对应 ~/.ssh/config 的 Host。
# 这条路不经过本机代理，也不依赖 gh 凭证，是最稳的方式。
#
# 用法：
#   bash scripts/push-all-remotes.sh                # 推送当前分支到所有账号
#   bash scripts/push-all-remotes.sh --all-branches # 推送所有分支与标签
#   bash scripts/push-all-remotes.sh --dry-run      # 只打印将要执行的动作
#   bash scripts/push-all-remotes.sh --https        # 改用 HTTPS + gh 凭证推送
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

need_cmd git

DRY_RUN=0; ALL_BRANCHES=0; USE_HTTPS=0; FORCE=0
for a in "$@"; do
  case "$a" in
    --dry-run)      DRY_RUN=1 ;;
    --all-branches) ALL_BRANCHES=1 ;;
    --https)        USE_HTTPS=1 ;;
    --force)        FORCE=1 ;;
    *) log_warn "未知参数: $a" ;;
  esac
done

# 主仓上 CI 会自行提交 results/ 归档，镜像仓没有这些提交，
# 因此单向同步镜像仓时需要 --force（镜像仓本就是只读副本，不存在覆盖他人改动的风险）
(( FORCE )) && PUSH_FORCE=( --force ) || PUSH_FORCE=()

REPO_NAME="${REPO_NAME:-$(basename "$GAS_ROOT")}"
BRANCH="${BRANCH:-$(git -C "$GAS_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"

PREV_ACTIVE=""
if (( USE_HTTPS )) && need_cmd gh 2>/dev/null; then
  PREV_ACTIVE="$(gh api user --jq '.login' 2>/dev/null || true)"
fi
trap 'if [[ -n "$PREV_ACTIVE" ]] && need_cmd gh 2>/dev/null; then gh auth switch --user "$PREV_ACTIVE" >/dev/null 2>&1 || true; log_info "已恢复 gh active 账号为: $PREV_ACTIVE"; fi' EXIT

PUSH_SPEC=( "$BRANCH" )
(( ALL_BRANCHES )) && PUSH_SPEC=( --all --tags )

failed=0
while read -r entry; do
  [[ -z "$entry" ]] && continue
  acct="$(account_field "$entry")"
  host="$(account_host "$entry")"

  if (( USE_HTTPS )); then
    remote_url="https://github.com/${acct}/${REPO_NAME}.git"
  else
    remote_url="git@${host}:${acct}/${REPO_NAME}.git"
  fi

  if git -C "$GAS_ROOT" remote get-url "$acct" >/dev/null 2>&1; then
    log_info "remote ${acct} 已存在: $(git -C "$GAS_ROOT" remote get-url "$acct")"
  else
    log_info "添加 remote ${acct} -> ${remote_url}"
    (( DRY_RUN )) || git -C "$GAS_ROOT" remote add "$acct" "$remote_url"
  fi

  log_step "推送 -> ${acct}/${REPO_NAME} (${BRANCH})"
  if (( DRY_RUN )); then echo "    git push ${acct} ${PUSH_SPEC[*]}"; continue; fi

  if (( USE_HTTPS )) && need_cmd gh 2>/dev/null; then
    gh auth switch --user "$acct" >/dev/null 2>&1 \
      && log_info "  已切换 gh 账号: ${acct}" \
      || log_warn "  无法切换 gh 到 ${acct}，沿用当前凭证"
  fi

  if git -C "$GAS_ROOT" push "${PUSH_FORCE[@]}" "$acct" "${PUSH_SPEC[@]}"; then
    log_ok "  ✓ ${acct} 完成"
  else
    failed=1
    log_err "  ✗ ${acct} 失败。"
    log_err "    排查 1：确认该账号下已存在 ${REPO_NAME} 仓库"
    log_err "    排查 2：确认 ~/.ssh/config 有名为 ${host} 的 Host，且 ssh -T git@${host} 返回 Hi ${acct}!"
    log_err "    排查 3：目标仓库若有独立提交，需先合并或用 --force-with-lease"
  fi
done < <(read_accounts)

exit $failed
