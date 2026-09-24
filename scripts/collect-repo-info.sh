#!/usr/bin/env bash
# 用 gh CLI 采集私有源仓库的信息，生成可读的 markdown 与原始 json。
#
# 用法：
#   SOURCE_REPO_TOKEN=<能读该私有仓库的 PAT> scripts/collect-repo-info.sh <owner/repo> <输出目录>
#
# 产物：
#   <输出目录>/repo-info.json
#   <输出目录>/repo-info.md
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

FULL="${1:?需要提供 owner/repo}"
OUT="${2:?需要提供输出目录}"
mkdir -p "$OUT"

TOKEN="${SOURCE_REPO_TOKEN:-${GH_TOKEN:-}}"
if [[ -n "$TOKEN" ]]; then
  export GH_TOKEN="$TOKEN"
else
  log_warn "未提供 SOURCE_REPO_TOKEN，将使用 gh 当前登录身份采集"
fi
need_cmd gh

OWNER="${FULL%%/*}"
INFO_JSON="${OUT}/repo-info.json"
INFO_MD="${OUT}/repo-info.md"

log_step "采集仓库信息: ${FULL}"

# 带降级的查询：失败不中断整个流程
q() { local desc="$1"; shift; gh api "$@" 2>/dev/null || echo "__UNAVAILABLE__(${desc})"; }

meta="$(gh api "repos/${FULL}" --jq '{
  full_name, html_url, private, archived, default_branch, size_kb: .size,
  language, forks: .forks_count, open_issues: .open_issues_count,
  stargazers: .stargazers_count, created_at, pushed_at, updated_at,
  description, license: (.license.spdx_id // "none")
}' 2>/dev/null || echo '{}')"

default_branch="$(printf '%s' "$meta" | grep -o '"default_branch": *"[^"]*"' | head -1 | sed 's/.*: *"//; s/"$//')"
default_branch="${default_branch:-main}"

commits="$(q commits "repos/${FULL}/commits?per_page=5" --jq '.[] | (.sha[0:7]) + " | " + (.commit.author.name) + " | " + (.commit.author.date) + " | " + (.commit.message | split("\n")[0] | .[0:80])' || true)"

branches="$(q branches "repos/${FULL}/branches?per_page=20" --jq '.[].name' || true)"

workflows="$(q workflows "repos/${FULL}/actions/workflows" --jq '.total_count as $n | (["total=" + ($n|tostring)] + [.workflows[] | "  - " + .name + " [" + .state + "]"]) | join("\n")' || true)"

runs="$(q runs "repos/${FULL}/actions/runs?per_page=5" --jq '.workflow_runs[] | "  - " + .name + " #" + (.run_number|tostring) + " → " + (.conclusion // .status) + " @ " + .created_at' || true)"

contributors="$(q contributors "repos/${FULL}/contributors?per_page=5&anon=false" --jq '.[] | "  - " + .login + " (" + (.contributions|tostring) + " commits)"' || true)"

# Actions 配额：查出「时长为什么没了」的直接证据。
# 需要 token 具备对该账号的 billing/settings 读取权限，无权限时降级。
BILLING_UNAVAILABLE="Actions 配额信息不可用（需要 PAT 具备对该账号的 Actions 计费读权限）"
if ! billing="$(gh api "users/${OWNER}/settings/billing/actions" --jq '"Action minutes used: " + (.total_minutes_used|tostring) + " / included: " + (.included_minutes|tostring)' 2>/dev/null)"; then
  billing="$BILLING_UNAVAILABLE"
fi
[[ -z "$billing" || "$billing" == *'"message"'* ]] && billing="$BILLING_UNAVAILABLE"

# ---------------------------------------------------------------- JSON 归档
{
  printf '{\n'
  printf '  "repository": %s,\n' "$meta"
  printf '  "recent_commits": %s,\n' "$(gh api "repos/${FULL}/commits?per_page=5" --jq '[.[] | {sha: (.sha[0:7]), author: .commit.author.name, date: .commit.author.date, message: (.commit.message | split("\n")[0])}]' 2>/dev/null || echo '[]')"
  printf '  "collected_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "billing": "%s"\n' "$(printf '%s' "$billing" | sed 's/"/\\"/g')"
  printf '}\n'
} > "$INFO_JSON"

# ---------------------------------------------------------------- Markdown
{
  printf '#### 仓库元信息\n\n'
  printf '| 项 | 值 |\n|---|---|\n'
  printf '| 仓库 | [%s](https://github.com/%s) |\n' "$FULL" "$FULL"
  printf '| 可见性 | %s |\n' "$(printf '%s' "$meta" | grep -q '"private": *true' && echo '私有 🔒' || echo '公开 🌐')"
  printf '| 默认分支 | `%s` |\n' "$default_branch"
  printf '| 主语言 | %s |\n' "$(printf '%s' "$meta" | grep -o '"language": *"[^"]*"' | sed 's/.*: *"//; s/"$//')"
  desc="$(printf '%s' "$meta" | grep -o '"description": *"[^"]*"' | sed 's/.*: *"//; s/"$//')"
  printf '| 描述 | %s |\n' "${desc:--}"
  printf '| 大小 | %s KB |\n' "$(printf '%s' "$meta" | grep -o '"size_kb": *[0-9]*' | grep -o '[0-9]*$')"
  printf '| 最后推送 | %s |\n' "$(printf '%s' "$meta" | grep -o '"pushed_at": *"[^"]*"' | sed 's/.*: *"//; s/"$//')"
  printf '| 分支数 | %s |\n' "$(printf '%s\n' "$branches" | grep -c . )"
  printf '\n> Actions 配额：%s\n\n' "$billing"

  printf '#### 分支\n\n```\n%s\n```\n\n' "$branches"

  printf '#### 最近的提交\n\n'
  printf '| SHA | 作者 | 时间 | 说明 |\n|---|---|---|---|\n'
  printf '%s\n' "$commits" | awk -F'\\|' '
    function t(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    {
      msg=""
      for (i = 4; i <= NF; i++) msg = (i == 4 ? t($i) : msg "|" t($i))
      gsub(/\|/, "\\|", msg)
      printf "| `%s` | %s | %s | %s |\n", t($1), t($2), t($3), msg
    }'

  printf '\n#### 源仓库自带 Workflow\n\n```\n%s\n```\n\n' "$workflows"
  printf '#### 源仓库最近的 Actions 运行\n\n```\n%s\n```\n\n' "$runs"
  printf '#### 贡献者\n\n```\n%s\n```\n' "$contributors"
} > "$INFO_MD"

log_ok "仓库信息已写入: ${INFO_MD}"
set_output "repo_info_md" "$INFO_MD"
set_output "repo_info_json" "$INFO_JSON"
set_output "default_branch" "$default_branch"
