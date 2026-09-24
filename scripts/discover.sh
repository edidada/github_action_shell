#!/usr/bin/env bash
# 探测私有源仓库的构建方式（profile）与执行入口。
# 输出（写入 GITHUB_OUTPUT）：profile、entrypoint、has_vcpkg、has_submodules
#
# profile 优先级：
#   1. 环境变量 GAS_PROFILE 显式指定（cmake|script|make|skip）
#   2. 源仓库内 .gas/profile 文件
#   3. 自动探测：CMakeLists.txt -> cmake ; Makefile -> make ; 否则 -> script
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

SRC_DIR="${1:?需要提供源仓库目录}"

profile=""; entrypoint=""; has_vcpkg="false"; has_submodules="false"

# 1) 环境变量显式指定
profile="${GAS_PROFILE:-}"

# 2) 源仓库内约定文件 override
if [[ -f "${SRC_DIR}/.gas/profile" ]]; then
  profile="$(trim "$(head -1 "${SRC_DIR}/.gas/profile")")"
  log_info "源仓库自带 profile 声明: ${profile}"
fi

# 3) 自动探测
if [[ -z "$profile" || "$profile" == "auto" ]]; then
  if [[ -f "${SRC_DIR}/CMakeLists.txt" ]]; then
    profile="cmake"
  elif [[ -f "${SRC_DIR}/Makefile" ]] || [[ -f "${SRC_DIR}/GNUmakefile" ]]; then
    profile="make"
  elif [[ -f "${SRC_DIR}/package.json" ]]; then
    profile="npm"
  else
    profile="script"
  fi
  log_info "自动探测到 profile: ${profile}"
fi

# 入口脚本定位
if [[ -n "${GAS_ENTRYPOINT:-}" && "${GAS_ENTRYPOINT}" != "auto" ]]; then
  entrypoint="${GAS_ENTRYPOINT}"
  profile="${GAS_PROFILE:-script}"
  log_info "使用显式入口: ${entrypoint}"
fi

# vcpkg / submodules 探测
[[ -f "${SRC_DIR}/vcpkg.json" ]] && has_vcpkg="true"
[[ -f "${SRC_DIR}/.gitmodules" ]] && has_submodules="true"

log_step "profile=${profile} vcpkg=${has_vcpkg} submodules=${has_submodules}"

set_output "profile"        "$profile"
set_output "entrypoint"     "$entrypoint"
set_output "has_vcpkg"      "$has_vcpkg"
set_output "has_submodules" "$has_submodules"
