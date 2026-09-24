#!/usr/bin/env bash
# 汇总本次运行的所有中间产物，生成最终的 summary.md。
#
# 用法：
#   scripts/gen-report.sh <本次输出目录>
#
# 所需上下文尽量从 GitHub Actions 环境变量读取，本地运行时自动降级为 "local"。
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

OUT_DIR="${1:?需要提供本次输出目录}"
SUMMARY="${OUT_DIR}/summary.md"

SERVER="${GITHUB_SERVER_URL:-https://github.com}"
DRIVER_REPO="${GITHUB_REPOSITORY:-local/github_action_shell}"
RUN_ID="${GITHUB_RUN_ID:-local}"
RUN_NUM="${GITHUB_RUN_NUMBER:-0}"
EVENT="${GITHUB_EVENT_NAME:-manual}"
ACTOR="${GITHUB_ACTOR:-local}"
SRC_FULL="${GAS_SOURCE_FULL:-unknown/unknown}"
SRC_REF="${GAS_SOURCE_REF:-<默认分支>}"
SRC_SHA="${GAS_SOURCE_SHA:-unknown}"
PROFILE="${GAS_PROFILE:-auto}"
RUNNER="${RUNNER_OS:-unknown}-${RUNNER_ARCH:-unknown}"
FINISHED="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

STATUS="$(cat "${OUT_DIR}/status" 2>/dev/null || echo unknown)"
case "$STATUS" in
  success) ICON="✅"; TEXT="成功" ;;
  failure) ICON="❌"; TEXT="失败" ;;
  skipped) ICON="⏭️ "; TEXT="跳过" ;;
  *)        ICON="❔"; TEXT="未知" ;;
esac

# ---------------------------------------------------------------- 头部
{
  printf '# %s CI 报告 · #%s\n\n' "$SRC_FULL" "$RUN_NUM"
  printf '## %s %s\n\n' "$ICON" "$TEXT"
  printf '| 项 | 值 |\n|---|---|\n'
  printf '| 源仓库（私有） | [`%s`](%s/%s) |\n' "$SRC_FULL" "$SERVER" "$SRC_FULL"
  printf '| 分支 / Ref | `%s` |\n' "$SRC_REF"
  printf '| Commit | `%s` |\n' "$SRC_SHA"
  printf '| 构建类型 | `%s` |\n' "$PROFILE"
  printf '| 驱动器仓库（本仓库） | [`%s`](%s/%s) |\n' "$DRIVER_REPO" "$SERVER" "$DRIVER_REPO"
  printf '| Run | [#%s](%s/%s/actions/runs/%s) |\n' "$RUN_NUM" "$SERVER" "$DRIVER_REPO" "$RUN_ID"
  printf '| 触发方式 | `%s` |\n' "$EVENT"
  printf '| 触发者 | `%s` |\n' "$ACTOR"
  printf '| Runner | `%s` |\n' "$RUNNER"
  printf '| 完成时间 | %s |\n' "$FINISHED"
  printf '\n'

  # -------------------------------------------------------------- 步骤表
  printf '## 执行步骤\n\n'
  if [[ -s "${OUT_DIR}/steps.tsv" ]]; then
    printf '| 步骤 | 状态 | 退出码 | 耗时 | 日志 |\n|---|---|---|---|---|\n'
    while IFS=$'\t' read -r name st code dur lf; do
      mark=$([[ "$st" == "ok" ]] && echo "✅" || echo "❌")
      printf '| %s | %s %s | %s | %s | [%s](logs/%s) |\n' "$name" "$mark" "$st" "$code" "$dur" "$lf" "$lf"
    done < "${OUT_DIR}/steps.tsv"
  else
    printf '_没有执行任何步骤。_\n'
  fi
  printf '\n'

  # 失败步骤的日志尾部直接内联，便于不用点开就能看到原因
  if [[ "$STATUS" == "failure" ]]; then
    printf '## 失败日志摘要\n\n'
    while IFS=$'\t' read -r name st code dur lf; do
      if [[ "$st" != "ok" && -f "${OUT_DIR}/logs/${lf}" ]]; then
        printf '<details><summary>❌ %s (exit=%s)</summary>\n\n```\n' "$name" "$code"
        tail -n 40 "${OUT_DIR}/logs/${lf}"
        printf '\n```\n\n</details>\n\n'
      fi
    done < "${OUT_DIR}/steps.tsv"
  fi

  # -------------------------------------------------------------- 仓库信息
  if [[ -f "${OUT_DIR}/repo-info.md" ]]; then
    printf '## 源仓库信息（gh 采集）\n\n'
    cat "${OUT_DIR}/repo-info.md"
    printf '\n'
  fi

  # -------------------------------------------------------------- 日志索引
  printf '## 日志\n\n'
  if [[ -d "${OUT_DIR}/logs" ]] && ls "${OUT_DIR}/logs"/*.log >/dev/null 2>&1; then
    for lf in "${OUT_DIR}/logs"/*.log; do
      printf -- '- [%s](logs/%s) · %s 行\n' "$(basename "$lf")" "$(basename "$lf")" "$(wc -l < "$lf" | tr -d ' ')"
    done
  else
    printf '_无日志。_\n'
  fi
  printf '\n---\n\n_由 [%s](%s/%s) 自动生成，请勿手工编辑。_\n' "$DRIVER_REPO" "$SERVER" "$DRIVER_REPO"
} > "$SUMMARY"

log_ok "报告已生成: ${SUMMARY}"
set_output "summary" "$SUMMARY"
set_output "status" "$STATUS"
