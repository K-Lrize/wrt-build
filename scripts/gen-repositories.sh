#!/bin/bash
# 生成 ImageBuilder 构建期与路由器运行期的 repositories 配置文件。
#
# 用法：
#   gen-repositories.sh --device <name> --output <path> --repo-base <url>
#                       [--runtime-output <path>]
#                       [--original <ib/repositories>]
#                       [--kmod-vermagic <vermagic>]
#
# repositories 文件格式：每行一个完整 URL 或 file:// 路径，指向 packages.adb。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

require_cmd yq

DEVICE=""
OUTPUT=""
RUNTIME_OUTPUT=""
REPO_BASE=""
ORIGINAL=""
KMOD_VERMAGIC=""

while [[ $# -gt 0 ]]; do
    case "$1" in
    --device)
        DEVICE="$2"
        shift 2
        ;;
    --output)
        OUTPUT="$2"
        shift 2
        ;;
    --runtime-output)
        RUNTIME_OUTPUT="$2"
        shift 2
        ;;
    --repo-base)
        REPO_BASE="$2"
        shift 2
        ;;
    --original)
        ORIGINAL="$2"
        shift 2
        ;;
    --kmod-vermagic)
        KMOD_VERMAGIC="$2"
        shift 2
        ;;
    *) log_fatal "未知参数：$1" ;;
    esac
done

[[ -n ${DEVICE} ]] || log_fatal "--device 必须指定"
[[ -n ${OUTPUT} ]] || log_fatal "--output 必须指定"
[[ -n ${REPO_BASE} ]] || log_fatal "--repo-base 必须指定"

ROOT="$(repo_root)"
eval "$(bash "${SCRIPT_DIR}/resolve-device.sh" "${DEVICE}" export)"
DEVICE_YAML="${ROOT}/devices/${DEVICE}/device.yaml"

log_info "生成 repositories：device=${DEVICE} channel=${SOURCE_CHANNEL} arch=${ARCH} kmod_source=${SOURCE_KMOD_SOURCE}"

# 1. 上游通用基础源根地址 (UPSTREAM_BASE) —— 来自 device.yaml 显式配置的 source.upstream
UPSTREAM_BASE="${SOURCE_UPSTREAM}"
[[ -n ${UPSTREAM_BASE} ]] || log_fatal "无法确定上游源：device.yaml 未配置 source.upstream"
log_info "解析后的上游基础源基准地址: ${UPSTREAM_BASE}"

# 2. 提取内核驱动魔数 (KMOD_VERMAGIC)
if [[ -z ${KMOD_VERMAGIC} && -n ${ORIGINAL} && -f ${ORIGINAL} ]]; then
    KMOD_VERMAGIC="$(grep -oE '/kmods/[^/]+/' "${ORIGINAL}" | head -1 | sed 's|/kmods/||;s|/||' || true)"
fi
if [[ -z ${KMOD_VERMAGIC} && -d "${ROOT}/ib" ]]; then
    KMOD_VERMAGIC="$(find "${ROOT}/ib" -path '*/kmods/*' | grep -oE '/kmods/[^/]+' | head -1 | sed 's|/kmods/||' || true)"
fi
[[ -n ${KMOD_VERMAGIC} ]] && log_info "解析后的内核驱动 Vermagic: ${KMOD_VERMAGIC}"

# 3. 规范化声明装配构建期与运行期仓库列表
BUILD_REPOS=()
RUNTIME_REPOS=()

# ─── L1: 自建业务包层 (Custom Packages) ───
L1_ONLINE="${REPO_BASE}/${SOURCE_CHANNEL}/packages/${ARCH}/packages.adb"
# 自有包预同步至独立目录 ib/custom，避免覆盖 IB 自带本地源
if [[ -f "${ROOT}/ib/custom/packages.adb" ]]; then
    BUILD_REPOS+=("file://${ROOT}/ib/custom/packages.adb")
else
    BUILD_REPOS+=("${L1_ONLINE}")
fi
RUNTIME_REPOS+=("${L1_ONLINE}")

# ─── L2: 内核驱动包层 (Kernel Modules) ───
if [[ ${SOURCE_KMOD_SOURCE} == "build" ]]; then
    [[ -n ${KMOD_VERMAGIC} ]] || log_fatal "kmod_source=build 时无法获取 kmod vermagic"
    L2_KMOD_ONLINE="${REPO_BASE}/${SOURCE_CHANNEL}/targets/${TARGET}/${SUBTARGET}/kmods/${KMOD_VERMAGIC}/packages.adb"
    if [[ -f "${ROOT}/ib/packages/kernel/packages.adb" ]]; then
        BUILD_REPOS+=("file://${ROOT}/ib/packages/kernel/packages.adb")
    else
        BUILD_REPOS+=("${L2_KMOD_ONLINE}")
    fi
    RUNTIME_REPOS+=("${L2_KMOD_ONLINE}")
elif [[ -n ${KMOD_VERMAGIC} ]]; then
    L2_KMOD_ONLINE="${UPSTREAM_BASE}/targets/${TARGET}/${SUBTARGET}/kmods/${KMOD_VERMAGIC}/packages.adb"
    BUILD_REPOS+=("${L2_KMOD_ONLINE}")
    RUNTIME_REPOS+=("${L2_KMOD_ONLINE}")
fi

# ─── L2 base: target 核心包层 (libc/libgcc/fstools/kernel...) ───
# mode=build：源码自有、官方无对应产物，用自有 R2；mode=download：借官方
if [[ ${SOURCE_MODE} == "build" ]]; then
    L2_BASE_ONLINE="${REPO_BASE}/${SOURCE_CHANNEL}/targets/${TARGET}/${SUBTARGET}/packages/packages.adb"
else
    L2_BASE_ONLINE="${UPSTREAM_BASE}/targets/${TARGET}/${SUBTARGET}/packages/packages.adb"
fi
BUILD_REPOS+=("${L2_BASE_ONLINE}")
RUNTIME_REPOS+=("${L2_BASE_ONLINE}")

# ─── L3: 上游社区 feed (arch 通用，统一借官方) ───
for feed in "packages/${ARCH}/base" \
    "packages/${ARCH}/luci" \
    "packages/${ARCH}/packages" \
    "packages/${ARCH}/routing" \
    "packages/${ARCH}/telephony"; do
    url="${UPSTREAM_BASE}/${feed}/packages.adb"
    BUILD_REPOS+=("${url}")
    RUNTIME_REPOS+=("${url}")
done

# ─── Extra: device.yaml 追加配置的外部源 ───
repos_count="$(yq '.repos | length // 0' "${DEVICE_YAML}")"
for ((i = 0; i < repos_count; i++)); do
    custom_repo="$(yq -r ".repos[$i]" "${DEVICE_YAML}")"
    [[ -n ${custom_repo} && ${custom_repo} != "null" ]] || continue
    BUILD_REPOS+=("${custom_repo}")
    RUNTIME_REPOS+=("${custom_repo}")
done

# 写入构建期仓库列表
mkdir -p "$(dirname "${OUTPUT}")"
printf "%s\n" "${BUILD_REPOS[@]}" >"${OUTPUT}"
log_ok "构建期 repositories 写入 ${OUTPUT}（$(wc -l <"${OUTPUT}") 行）"

# 写入运行期仓库列表（若指定）
if [[ -n ${RUNTIME_OUTPUT} ]]; then
    mkdir -p "$(dirname "${RUNTIME_OUTPUT}")"
    printf "%s\n" "${RUNTIME_REPOS[@]}" >"${RUNTIME_OUTPUT}"
    log_ok "运行期 repositories 写入 ${RUNTIME_OUTPUT}（$(wc -l <"${RUNTIME_OUTPUT}") 行）"
fi
