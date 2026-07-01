#!/bin/bash
# 合并 _common + per-device 配置，输出构建参数。
#
# 用法：
#   resolve-device.sh <device> export            输出 export VAR=...
#   resolve-device.sh <device> files <dest>      合并 files 到 dest
#   resolve-device.sh <device> packages          输出 export PACKAGES=...
#
# 包列表合并（IB make image PACKAGES 变量规范）：
#   _common/common.yaml packages.add  +  device.yaml packages.add
#   - device.yaml packages.remove（加 "-" 前缀）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

require_cmd yq

ROOT="$(repo_root)"
DEVICE="${1:?用法: resolve-device.sh <device> <mode> [args]}"
MODE="${2:?用法: resolve-device.sh <device> <mode> [args]}"

DEVICE_DIR="${ROOT}/devices/${DEVICE}"
COMMON_DIR="${ROOT}/devices/_common"
COMMON_YAML="${COMMON_DIR}/common.yaml"
DEVICE_YAML="${DEVICE_DIR}/device.yaml"

[[ -d ${DEVICE_DIR} ]] || log_fatal "设备目录不存在：${DEVICE_DIR}"
[[ -f ${DEVICE_YAML} ]] || log_fatal "device.yaml 不存在：${DEVICE_YAML}"
TARGET="$(yq '.target' "${DEVICE_YAML}")"
SUBTARGET="$(yq '.subtarget' "${DEVICE_YAML}")"
PROFILE="$(yq '.profile' "${DEVICE_YAML}")"
ARCH="$(yq '.arch' "${DEVICE_YAML}")"
SOURCE_CHANNEL="$(yq '.source.channel // ""' "${DEVICE_YAML}")"
SOURCE_MODE="$(yq '.source.mode // ""' "${DEVICE_YAML}")"
SOURCE_UPSTREAM="$(yq '.source.upstream // ""' "${DEVICE_YAML}")"
SOURCE_REPO="$(yq '.source.repo // ""' "${DEVICE_YAML}")"
SOURCE_REF="$(yq '.source.ref // ""' "${DEVICE_YAML}")"
ROOTFS_PARTSIZE="$(yq '.image.rootfs_partsize // 0' "${DEVICE_YAML}")"

SOURCE_KMOD_SOURCE="$(yq '.source.kmod_source // ""' "${DEVICE_YAML}")"
[[ -z ${SOURCE_KMOD_SOURCE} ]] && SOURCE_KMOD_SOURCE="${SOURCE_MODE}"

[[ -n ${SOURCE_CHANNEL} ]] || log_fatal "${DEVICE}: source.channel 必填"
[[ -n ${SOURCE_MODE} ]] || log_fatal "${DEVICE}: source.mode 必填"
if [[ ${SOURCE_KMOD_SOURCE} != "download" && ${SOURCE_KMOD_SOURCE} != "build" ]]; then
    log_fatal "${DEVICE}: source.kmod_source 必须为 download 或 build"
fi

# source.upstream 为官方上游源根地址，download/build 两种模式均需（L3 社区 feed / 官方直下）
[[ -n ${SOURCE_UPSTREAM} ]] || log_fatal "${DEVICE}: source.upstream 必填"

if [[ ${SOURCE_MODE} == "build" ]]; then
    [[ -n ${SOURCE_REPO} && -n ${SOURCE_REF} ]] || log_fatal "${DEVICE}: mode=build 时 source.repo/ref 必填"
elif [[ ${SOURCE_MODE} != "download" ]]; then
    log_fatal "${DEVICE}: source.mode 必须为 download 或 build"
fi
OPENWRT_MAJOR="${SOURCE_CHANNEL}"

yaml_packages_add() {
    local file="$1"
    [[ -f ${file} ]] || return 0
    local count
    count="$(yq '.packages.add | length // 0' "${file}")"
    local i
    for ((i = 0; i < count; i++)); do
        yq ".packages.add[$i]" "${file}"
    done
}

build_package_list() {
    local pkgs=()

    while IFS= read -r pkg; do
        [[ -n ${pkg} && ${pkg} != "null" ]] && pkgs+=("${pkg}")
    done < <(yaml_packages_add "${COMMON_YAML}")

    while IFS= read -r pkg; do
        [[ -n ${pkg} && ${pkg} != "null" ]] && pkgs+=("${pkg}")
    done < <(yaml_packages_add "${DEVICE_YAML}")

    local rm_count
    rm_count="$(yq '.packages.remove | length // 0' "${DEVICE_YAML}")"
    local i
    for ((i = 0; i < rm_count; i++)); do
        local pkg
        pkg="$(yq ".packages.remove[$i]" "${DEVICE_YAML}")"
        pkgs+=("-${pkg}")
    done

    echo "${pkgs[*]}"
}

case "${MODE}" in
export)
    echo "export TARGET='${TARGET}'"
    echo "export SUBTARGET='${SUBTARGET}'"
    echo "export PROFILE='${PROFILE}'"
    echo "export ARCH='${ARCH}'"
    echo "export SOURCE_CHANNEL='${SOURCE_CHANNEL}'"
    echo "export SOURCE_ID='${SOURCE_CHANNEL}'"
    echo "export SOURCE_MODE='${SOURCE_MODE}'"
    echo "export SOURCE_KMOD_SOURCE='${SOURCE_KMOD_SOURCE}'"
    echo "export SOURCE_UPSTREAM='${SOURCE_UPSTREAM}'"
    echo "export SOURCE_REPO='${SOURCE_REPO}'"
    echo "export SOURCE_REF='${SOURCE_REF}'"
    echo "export OPENWRT_MAJOR='${OPENWRT_MAJOR}'"
    echo "export IMAGE_ROOTFS_PARTSIZE='${ROOTFS_PARTSIZE}'"
    ;;

files)
    DEST="${3:?files 模式需要第三个参数 <dest>}"
    mkdir -p "${DEST}"
    [[ -d "${COMMON_DIR}/files" ]] && cp -r "${COMMON_DIR}/files/." "${DEST}/"
    [[ -d "${DEVICE_DIR}/files" ]] && cp -r "${DEVICE_DIR}/files/." "${DEST}/"
    log_ok "files 合并 → ${DEST}"
    ;;

packages)
    echo "export PACKAGES='$(build_package_list)'"
    ;;

*)
    log_fatal "未知模式：${MODE}（支持 export / files / packages）"
    ;;
esac
