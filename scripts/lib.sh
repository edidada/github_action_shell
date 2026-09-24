#!/usr/bin/env bash
# github_action_shell - 公共函数库
# 所有脚本通过 source 本文件获得统一的日志、计时、配置解析能力。
# 在 GitHub Actions 与本地 Git Bash / Linux 均可运行。

set -uo pipefail

GAS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAS_ROOT="$(cd "$GAS_LIB_DIR/.." && pwd)"

CONFIG_DIR="${GAS_ROOT}/config"
RESULTS_DIR="${GAS_RESULTS_DIR:-${GAS_ROOT}/results}"

# ---------------------------------------------------------------- 日志输出
_c() { # _c <颜色码> <文本> ; 无 TTY 时不输出颜色，避免在 Actions 日志里产生转义字符
  local code="$1"; shift
  if [[ -t 1 ]]; then printf '\033[%sm%s\033[0m\n' "$code" "$*"; else printf '%s\n' "$*"; fi
}
log_info()  { _c '36' "[INFO ] $*"; }
log_ok()    { _c '32' "[ OK  ] $*"; }
log_warn()  { _c '33' "[WARN ] $*" >&2; }
log_err()   { _c '31' "[ERR  ] $*" >&2; }
log_step()  { _c '35' "[STEP ] $*"; }
die()       { log_err "$*"; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少必需命令: $1"
}

# 把敏感串注册到 GitHub Actions 掩码，避免泄露到公开日志
mask() {
  [[ -n "${1:-}" ]] && echo "::add-mask::${1}" 2>/dev/null || true
}

# ---------------------------------------------------------------- 计时
_now_ms() {
  if date +%s%3N >/dev/null 2>&1 && [[ "$(date +%s%3N)" != *N* ]]; then
    date +%s%3N
  else
    # macOS date 不支持 %3N
    echo $(( $(date +%s) * 1000 ))
  fi
}

# 用法: start=$(_now_ms) ; ... ; elapsed=$(($( _now_ms ) - start))
human_ms() {
  local ms="$1"
  local s=$(( ms / 1000 ))
  printf '%dm%02ds' $(( s / 60 )) $(( s % 60 ))
}

# ---------------------------------------------------------------- 配置解析
# 单CAID段提取：account_field "wiseism:wiseism126_github.com" -> wiseism
account_field() { printf '%s' "${1%%:*}"; }
# SSH 别名提取：account_host "wiseism:wiseism126_github.com" -> wiseism126_github.com
#               未指定时回退到 github.com
account_host() {
  if [[ "$1" == *:* ]]; then printf '%s' "${1#*:}"; else printf 'github.com'; fi
}
# lookup <key> <file>  ->  输出 value；文件为 KEY=VALUE 风格，支持行尾注释
lookup() {
  local key="$1" file="$2"
  [[ -f "$file" ]] || return 1
  local line val
  while IFS= read -r line; do
    line="${line%%#*}"                 # 去注释
    line="${line%%[[:space:]]}"        # 去行尾空白
    line="${line#"${line%%[![:space:]]*}"}"  # 去行首空白
    [[ -z "$line" ]] && continue
    [[ "$line" != *=* ]] && continue
    if [[ "${line%%=*}" == "$key" ]]; then
      val="${line#*=}"
      printf '%s' "$(trim "$val")"
      return 0
    fi
  done < "$file"
  return 1
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# 读取账号清单（去掉注释和空行，按序输出）
read_accounts() {
  local file="${CONFIG_DIR}/accounts.env"
  [[ -f "$file" ]] || die "找不到账号清单: $file"
  local line out=""
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(trim "${line}")"
    [[ -z "$line" ]] && continue
    out+="${line}"$'\n'
  done < "$file"
  printf '%s' "$out"
}

primary_account() { local l; l="$(read_accounts | head -1)"; account_field "$l"; }
mirror_accounts() {
  local l
  while IFS= read -r l; do [[ -n "$l" ]] && account_field "$l"; done < <(read_accounts | tail -n +2)
}

# 解析 owner=repo[@ref]
# usage: resolve_source <owner>  ->  设置全局变量 GAS_SOURCE_REPO / GAS_SOURCE_REF / GAS_SOURCE_FULL
#
# 两级 lookup：账号私有 overlay 优先于共享基线。
#   config/sources.<owner>.env   ← 只在该账号的 acct/<owner> 分支上维护
#   config/sources.env           ← 共享基线，只在 main 上维护
# 两者文件互不重叠，因此「main -> acct/*」合并时不会产生配置冲突。
# 详见 docs/BRANCHING.md §5。
resolve_source() {
  local owner="$1"
  local entry=""
  local overlay="${CONFIG_DIR}/sources.${owner}.env"

  [[ -f "$overlay" ]] && entry="$(lookup "$owner" "$overlay" || true)"
  [[ -z "$entry" ]] && entry="$(lookup "$owner" "${CONFIG_DIR}/sources.env" || true)"
  entry="${entry:-${GAS_SOURCE_REPO_DEFAULT:-cpp_ecshop}}"

  # 显式禁用标记：<owner>=none / <owner>=-
  # 该账号下并不存在这个源仓库，返回非零让调用方跳过。
  # 注意不能简单地「删掉那一行」——没有匹配时会回退到上面的默认值，
  # runner 照样会去 checkout 一个不存在的仓库。
  if [[ "$entry" == "none" || "$entry" == "-" ]]; then
    GAS_SOURCE_REPO=""; GAS_SOURCE_REF=""; GAS_SOURCE_FULL=""
    export GAS_SOURCE_REPO GAS_SOURCE_REF GAS_SOURCE_FULL
    return 1
  fi

  GAS_SOURCE_REPO="${entry%%@*}"
  GAS_SOURCE_REF="${entry#*@}"
  [[ "$GAS_SOURCE_REF" == "$GAS_SOURCE_REPO" ]] && GAS_SOURCE_REF=""
  GAS_SOURCE_FULL="${owner}/${GAS_SOURCE_REPO}"
  export GAS_SOURCE_REPO GAS_SOURCE_REF GAS_SOURCE_FULL
}

# ---------------------------------------------------------------- Actions 集成
set_output() { [[ -n "${GITHUB_OUTPUT:-}" ]] && printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT" || true; }
set_summary_line() { [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && printf '%s\n' "$*" >>"$GITHUB_STEP_SUMMARY" || true; }

export GAS_LIB_DIR GAS_ROOT CONFIG_DIR RESULTS_DIR
