#!/usr/bin/env bash
# 在 public runner 上执行私有源仓库的构建/脚本，并把每一步的结果与日志落盘。
#
# 用法：
#   scripts/run-source.sh <源仓库目录> <输出目录> <profile> [entrypoint]
#
# 产物：
#   <输出目录>/steps.tsv       每一步的名称/状态/退出码/耗时
#   <输出目录>/logs/*.log      每一步的完整日志
#   <输出目录>/status          最终状态 success|failure|skipped
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

SRC_DIR="${1:?源仓库目录}"
OUT_DIR="${2:?输出目录}"
PROFILE="${3:-auto}"
ENTRYPOINT="${4:-}"

LOGS="${OUT_DIR}/logs"
mkdir -p "$LOGS"
: >"${OUT_DIR}/steps.tsv"

STEP_N=0
FINAL_STATUS="success"

slug() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g'; }

# 敏感串脱敏：从 GAS_REDACT_FILE 逐行读取需要替换的内容
redact() {
  if [[ -n "${GAS_REDACT_FILE:-}" && -f "${GAS_REDACT_FILE}" ]]; then
    local args=() line
    while IFS= read -r line; do
      [[ -n "$line" ]] && args+=( -e "s|${line}|***REDACTED***|g" )
    done < "$GAS_REDACT_FILE"
    if (( ${#args[@]} )); then sed "${args[@]}"; else cat; fi
  else
    cat
  fi
}

# run_step <名称> <命令...>   返回原始退出码，但不中断整体流程
run_step() {
  local name="$1"; shift
  STEP_N=$(( STEP_N + 1 ))
  local lf="${LOGS}/$(printf '%02d' "$STEP_N")-$(slug "$name").log"
  local start end code dur_ms fileName

  log_step "▸ ${name}"
  start="$(_now_ms)"
  ( cd "$SRC_DIR" && "$@" ) > >(tee "$lf") 2>&1
  code=$?
  end="$(_now_ms)"
  dur_ms=$(( end - start ))

  # 脱敏写回日志
  local tmpf; tmpf="$(mktemp)"
  if redact < "$lf" > "$tmpf"; then mv "$tmpf" "$lf"; else rm -f "$tmpf"; fi

  if (( code == 0 )); then
    log_ok "  ✓ ${name} (${dur_ms}ms)"
  else
    log_warn "  ✗ ${name} 退出码=${code} (${dur_ms}ms)"
    FINAL_STATUS="failure"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$([ $code -eq 0 ] && echo ok || echo fail)" "$code" "$(human_ms "$dur_ms")" "$(basename "$lf")" >>"${OUT_DIR}/steps.tsv"
  return $code
}

# run_optional_step <名称> <命令...>  失败不影响最终状态（用于探针/可选步骤）
run_optional_step() {
  local name="$1"; shift
  local prev="$FINAL_STATUS"
  run_step "$name" "$@" || true
  FINAL_STATUS="$prev"
}

log_info "=================================================================="
log_info " profile    : ${PROFILE}"
log_info " source dir : ${SRC_DIR}"
log_info " output dir : ${OUT_DIR}"
log_info "=================================================================="

case "$PROFILE" in
  cmake)
    CMAKE_ARGS=( -S . -B build -DCMAKE_BUILD_TYPE="${GAS_BUILD_TYPE:-Debug}" )
    # vcpkg toolchain（若仓库声明了 vcpkg.json 且已 checkout .vcpkg）
    if [[ -f "${SRC_DIR}/vcpkg.json" && -d "${SRC_DIR}/.vcpkg/scripts/buildsystems" ]]; then
      if [[ "${GAS_ENABLE_VCPKG:-auto}" != "false" ]]; then
        run_step "vcpkg bootstrap" bash ./.vcpkg/bootstrap-vcpkg.sh -disableMetrics
        CMAKE_ARGS+=( -DCMAKE_TOOLCHAIN_FILE="${SRC_DIR}/.vcpkg/scripts/buildsystems/vcpkg.cmake" )
      fi
    fi
    # 项目自定义 extras（cpp_ecshop 用它切换 crow / httplib）
    [[ -n "${GAS_CMAKE_EXTRA:-}" ]] && CMAKE_ARGS+=( ${GAS_CMAKE_EXTRA} )
    run_step "cmake configure" cmake "${CMAKE_ARGS[@]}"
    run_step "cmake build"     cmake --build build --config "${GAS_BUILD_TYPE:-Debug}" --parallel
    run_step "ctest"           ctest --test-dir build -C "${GAS_BUILD_TYPE:-Debug}" --output-on-failure
    ;;
  make)
    run_step "make"      make -j"$(nproc 2>/dev/null || echo 2)"
    run_step "make test" make test
    ;;
  npm)
    run_step "npm ci"      npm ci
    run_step "npm run build" npm run build
    run_step "npm test"    npm test
    ;;
  script)
    if [[ -z "$ENTRYPOINT" ]]; then
      # 未在仓库里声明入口时，退而求其次：列出可执行脚本供人工确认，但不失败
      log_warn "未指定执行入口，自动发现 scripts/ 下候选脚本"
      if [[ -d "${SRC_DIR}/scripts" ]]; then
        ls -1 "${SRC_DIR}/scripts" | sed 's/^/    - scripts\//' || true
      fi
      FINAL_STATUS="skipped"
    else
      run_step "run ${ENTRYPOINT}" bash "$ENTRYPOINT"
    fi
    ;;
  skip)
    log_warn "profile=skip，跳过执行"
    FINAL_STATUS="skipped"
    ;;
  *)
    die "未知 profile: ${PROFILE}"
    ;;
esac

# 可选：额外执行源仓库内的某个脚本（例如冒烟测试脚本）
if [[ -n "${GAS_EXTRA_SCRIPT:-}" ]]; then
  if [[ -f "${SRC_DIR}/${GAS_EXTRA_SCRIPT}" ]]; then
    run_optional_step "extra ${GAS_EXTRA_SCRIPT}" bash "${GAS_EXTRA_SCRIPT}"
  else
    log_warn "额外的脚本不存在，已忽略: ${GAS_EXTRA_SCRIPT}"
  fi
fi

echo "$FINAL_STATUS" > "${OUT_DIR}/status"
log_step "最终状态: ${FINAL_STATUS}"

# 失败时把摘要塞进 Actions Step Summary，方便一眼看到
if [[ "$FINAL_STATUS" == "failure" ]]; then
  set_summary_line "### ❌ 构建失败"
  set_summary_line '```'
  set_summary_line "$(cat "${OUT_DIR}/steps.tsv")"
  set_summary_line '```'
fi
