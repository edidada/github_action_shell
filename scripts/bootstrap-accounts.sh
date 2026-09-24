#!/usr/bin/env bash
# 在 config/accounts.env 列出的所有账号下，确保存在同名 public 仓库，
# 并打印每个仓库需要配置的 Secrets / Variables 清单。
#
# 用法：
#   bash scripts/bootstrap-accounts.sh          # 只检查，不操作
#   bash scripts/bootstrap-accounts.sh --yes    # 缺失的仓库自动创建
#   bash scripts/bootstrap-accounts.sh --set-vars   # 同时写入仓库级变量（需要先登录对应账号）
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

need_cmd gh

AUTO_CREATE=0
SET_VARS=0
for a in "$@"; do
  case "$a" in
    --yes)       AUTO_CREATE=1 ;;
    --set-vars)  SET_VARS=1 ;;
    *) log_warn "未知参数: $a" ;;
  esac
done

REPO_NAME="${REPO_NAME:-$(basename "$GAS_ROOT")}"
PRIMARY="$(primary_account)"
PREV_ACTIVE="$(gh api user --jq '.login' 2>/dev/null || true)"
trap '[[ -n "$PREV_ACTIVE" ]] && gh auth switch --user "$PREV_ACTIVE" >/dev/null 2>&1' EXIT

GUIDE=()

while read -r acct; do
  [[ -z "$acct" ]] && continue
  full="${acct}/${REPO_NAME}"
  log_step "账号 ${acct}"

  if gh auth switch --user "$acct" >/dev/null 2>&1; then
    log_info "  已切换到 gh 账号 ${acct}"
  else
    log_warn "  gh 未登录账号 ${acct}，请先执行: gh auth login"
    continue
  fi

  if gh repo view "$full" --json name,visibility >/dev/null 2>&1; then
    vis="$(gh repo view "$full" --json visibility --jq .visibility 2>/dev/null)"
    log_ok "  仓库已存在 (${vis})"
  else
    log_warn "  仓库不存在"
    if (( AUTO_CREATE )); then
      if gh repo create "$REPO_NAME" --public --description "Public CI driver for private source repos" --confirm >/dev/null 2>&1; then
        log_ok "  已创建 ${full} (public)"
      else
        log_err "  创建失败 ${full}"
      fi
    else
      log_info "  ↳ 需创建时加 --yes，或手动: gh repo create ${REPO_NAME} --public --confirm"
    fi
  fi

  (( SET_VARS )) && { gh variable set VARIANTS --repo "$full" --body '[{ "name": "default", "extra": "" }]' >/dev/null 2>&1 || true; }

  GUIDE+=( "── ${full} ───────────────────────────────
  Secrets（Settings → Secrets and variables → Actions → New repository secret）
    SOURCE_REPO_TOKEN  只对 *本账号* 下 cpp_ecshop 私有仓库授权的 PAT
                       fine-grained：Contents=Read、Metadata=Read、Actions=Read
                       classic：勾选 repo
    $( [[ "$acct" == "$PRIMARY" ]] && echo "MIRROR_TOKEN         仅主账号需要：其余 3 个仓库的 Contents=Read and write" || echo "MIRROR_TOKEN         （镜像仓无需此 secret，留空即可）" )

  Variables（Settings → Secrets and variables → Actions → Variables）
    SOURCE_REPO        可选，默认 cpp_ecshop
    VARIANTS           可选，JSON 数组，多套构建参数
                       例：[{\"name\":\"crow\",\"extra\":\"-DECSHOP_HTTP_SERVER=crow\"}]
    ENABLE_VCPKG       可选，auto|true|false" )
done < <(read_accounts)

echo
echo "==================== 配置清单 ===================="
printf '%s\n' "${GUIDE[@]}"
echo
echo "==================== 快捷命令 ===================="
echo "设置 secret（在对应账号下执行）："
echo "  gh auth switch --user <账号> && gh secret set SOURCE_REPO_TOKEN --repo <账号>/${REPO_NAME} --body '<PAT>'"
echo
echo "手动触发一次运行："
echo "  gh workflow run run-source.yml --repo ${PRIMARY}/${REPO_NAME} -f source_repo=cpp_ecshop"
echo
echo "远程派发（私有源无 Actions 时长时的推荐方式）："
echo "  gh api repos/${PRIMARY}/${REPO_NAME}/dispatches -f event_type=run-source-script \\"
echo "      -f 'client_payload[source_repo]=cpp_ecshop' -f 'client_payload[source_ref]=main'"
