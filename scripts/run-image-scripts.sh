#!/bin/bash
# 依次执行通用与设备专属脚本，在构建 rootfs 前动态调整系统配置与权限
# 用法：run-image-scripts.sh <device> <files_dir>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

DEVICE="${1:?用法: $0 <device> <files_dir>}"
FILES_DIR="${2:?用法: $0 <device> <files_dir>}"

ROOT="$(repo_root)"
COMMON_DIR="${ROOT}/devices/_common"
DEVICE_DIR="${ROOT}/devices/${DEVICE}"

[[ -d ${DEVICE_DIR} ]] || log_fatal "设备目录不存在：${DEVICE_DIR}"

mkdir -p "${FILES_DIR}"
FILES_DIR="$(cd "${FILES_DIR}" && pwd)"

export DEVICE FILES_DIR DEVICE_DIR COMMON_DIR
export REPO_ROOT="${ROOT}"

run_script_dir() {
    local label="$1" dir="$2"
    [[ -d ${dir} ]] || return 0

    local scripts=()
    while IFS= read -r -d '' f; do
        scripts+=("$f")
    done < <(find "${dir}" -maxdepth 1 -type f -name '*.sh' -print0 | sort -z)

    [[ ${#scripts[@]} -gt 0 ]] || return 0

    echo "::group::执行${label}脚本"
    for script in "${scripts[@]}"; do
        echo "运行：$(basename "${script}")"
        bash "${script}"
    done
    echo "::endgroup::"
}

run_script_dir "通用" "${COMMON_DIR}/scripts"
run_script_dir "设备[${DEVICE}]" "${DEVICE_DIR}/scripts"

log_ok "image-scripts 完成（${DEVICE}）"
