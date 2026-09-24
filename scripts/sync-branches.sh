#!/usr/bin/env bash
# 多账号分支同步工具 —— main -> 各账号 acct/<owner> 长期分支。
#
# 背景：4 个 GitHub 账号下有同名仓库 github_action_shell，但用途可能不同。
# 单条 main 强推会导致「某账号的定制被下一次同步覆盖」，故改为：
#     main (公共基线)  --merge-->  acct/<owner> (各仓库的 default branch)
# 策略见 docs/BRANCHING.md。
#
# 用法：
#   bash scripts/sync-branches.sh --init         # 从 main 创建 4 条 acct 分支并推送
#   bash scripts/sync-branches.sh --set-default  # 把各仓库 default branch 切到 acct/<owner>
#   bash scripts/sync-branches.sh                # 日常同步：main -> 4 条 acct/*
#   bash scripts/sync-branches.sh --dry-run      # 只打印，不执行
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

need_cmd git

INIT=0; SET_DEFAULT=0; DRY_RUN=0
for a in "$@"; do
  case "$a" in
    --init)        INIT=1 ;;
    --set-default) SET_DEFAULT=1 ;;
    --dry-run)     DRY_RUN=1 ;;
    *) log_warn "未知参数: $a" ;;
  esac
done

REPO_NAME="${REPO_NAME:-$(basename "$GAS_ROOT")}"
BRANCH_PREFIX="${BRANCH_PREFIX:-acct}"

cd "$GAS_ROOT" || die "无法进入仓库目录: $GAS_ROOT"

# 工作区必须干净：脚本会反复 switch 分支
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  die "工作区有未提交改动，请先提交或 stash：$(git status --short | head -5)"
fi

PREV_ACTIVE=""
if need_cmd gh 2>/dev/null; then
  PREV_ACTIVE="$(gh api user --jq '.login' 2>/dev/null || true)"
fi
trap 'if [[ -n "$PREV_ACTIVE" ]] && need_cmd gh 2>/dev/null; then gh auth switch --user "$PREV_ACTIVE" >/dev/null 2>&1 || true; fi' EXIT

# ------------------------------------------------------------ remote 准备
ensure_remote() { # ensure_remote <acct> <ssh_host>
  local acct="$1" host="$2"
  local url="git@${host}:${acct}/${REPO_NAME}.git"
  if git remote get-url "$acct" >/dev/null 2>&1; then
    local cur; cur="$(git remote get-url "$acct")"
    [[ "$cur" != "$url" ]] && { (( DRY_RUN )) || git remote set-url "$acct" "$url"; log_info "  remote ${acct} 更新为 ${url}"; }
    return 0
  fi
  log_info "  添加 remote ${acct} -> ${url}"
  (( DRY_RUN )) || git remote add "$acct" "$url"
}

failed=0

while read -r entry; do
  [[ -z "$entry" ]] && continue
  acct="$(account_field "$entry")"
  host="$(account_host "$entry")"
  branch="${BRANCH_PREFIX}/${acct}"

  log_step "账号 ${acct}  (${acct}/${REPO_NAME} -> ${branch})"
  ensure_remote "$acct" "$host"

  # ---------------------------------------------------------- 1) 初始化
  if (( INIT )); then
    log_info "  创建分支 ${branch} 并指向 main"
    if (( DRY_RUN )); then
      echo "    git branch -f ${branch} main && git push ${acct} ${branch}"
    else
      if git branch -f "$branch" main 2>/dev/null \
         && git push "$acct" "$branch" 2>/dev/null; then
        log_ok "  ✓ ${branch} 已推送"
      else
        failed=1; log_err "  ✗ ${branch} 推送失败"
      fi
    fi
    continue
  fi

  # ---------------------------------------------------------- 2) 切默认分支
  if (( SET_DEFAULT )); then
    if (( DRY_RUN )); then
      echo "    gh api -X PATCH repos/${acct}/${REPO_NAME} -f default_branch=${branch}"
      continue
    fi
    if ! need_cmd gh 2>/dev/null; then
      failed=1; log_err "  ✗ 需要 gh CLI 才能改 default branch"; continue
    fi
    gh auth switch --user "$acct" >/dev/null 2>&1 \
      || log_warn "  无法切换 gh 到 ${acct}，沿用当前凭证"

    # 目标分支必须先存在于远端，否则 PATCH 会 422
    if ! git ls-remote --exit-code --heads "$acct" "$branch" >/dev/null 2>&1; then
      failed=1
      log_err "  ✗ 远端尚无分支 ${branch}，请先执行：bash scripts/sync-branches.sh --init"
      continue
    fi

    if gh api -X PATCH "repos/${acct}/${REPO_NAME}" \
         -f "default_branch=${branch}" >/dev/null 2>&1; then
      log_ok "  ✓ ${acct}/${REPO_NAME} default branch -> ${branch}"
    else
      failed=1; log_err "  ✗ 设置 default branch 失败（检查该账号 token 是否具备 repo 权限）"
    fi
    continue
  fi

  # ---------------------------------------------------------- 3) 日常同步
  if ! git rev-parse --verify "$branch" >/dev/null 2>&1; then
    failed=1
    log_err "  ✗ 本地无分支 ${branch}，先执行：bash scripts/sync-branches.sh --init"
    continue
  fi

  log_info "  merge main -> ${branch}"
  if (( DRY_RUN )); then
    echo "    git switch ${branch} && git merge --no-edit main && git push ${acct} ${branch}"
    continue
  fi

  git switch -q "$branch" || { failed=1; log_err "  ✗ 无法切到 ${branch}"; continue; }

  if git merge --no-edit main >/dev/null 2>&1; then
    log_ok "    ✓ merge 干净"
  else
    failed=1
    log_err "    ✗ merge 冲突，需人工处理："
    log_err "       git switch ${branch} && git merge main   # 解决冲突后 git merge --continue"
    log_err "       然后重跑本脚本。**绝不要**用 --force 覆盖 ${branch}"
    git merge --abort 2>/dev/null || true
    git switch -q main
    continue
  fi

  if git push "$acct" "$branch" 2>/dev/null; then
    log_ok "    ✓ 已推送 ${acct} ${branch}"
  else
    failed=1
    log_err "    ✗ 推送失败。若远端有本地没有的提交：git pull --no-rebase ${acct} ${branch}"
  fi

  git switch -q main
done < <(read_accounts)

git switch -q main 2>/dev/null || true
exit $failed
