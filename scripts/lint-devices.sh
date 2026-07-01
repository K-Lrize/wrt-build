#!/bin/bash
#
# 用法：
#   lint-devices.sh                      校验 devices/ 下全部设备配置
#   lint-devices.sh devices/mt3600be     校验单个设备目录

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEVICES_DIR="${REPO_ROOT}/devices"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

errors=0
warnings=0

log_err() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    ((errors++)) || true
}
log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
    ((warnings++)) || true
}
log_ok() { echo -e "${GREEN}[ OK ]${NC} $*"; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        log_err "缺少必要命令: $1"
        exit 1
    }
}
require_cmd yq

if [[ $# -ge 1 ]]; then
    targets=("$@")
else
    targets=()
    while IFS= read -r d; do
        targets+=("$d")
    done < <(find "${DEVICES_DIR}" -mindepth 1 -maxdepth 1 -type d | sort)
fi

for dev_dir in "${targets[@]}"; do
    dev_name="$(basename "${dev_dir}")"
    dev_err=0

    # 特殊处理 _common 通用配置
    if [[ ${dev_name} == "_common" ]]; then
        common_file="${dev_dir}/common.yaml"
        if [[ ! -f ${common_file} ]]; then
            log_err "${dev_name} [L01]: 未找到 common.yaml 配置文件"
            continue
        fi
        if ! yq . "${common_file}" >/dev/null 2>&1; then
            log_err "${dev_name} [L02]: common.yaml 语法解析失败"
            continue
        fi
        add_pkgs="$(yq '.packages.add[]? // ""' "${common_file}" | sed '/^$/d;/^null$/d' | sort -u || true)"
        rm_pkgs="$(yq '.packages.remove[]? // ""' "${common_file}" | sed '/^$/d;/^null$/d' | sort -u || true)"
        if [[ -n ${add_pkgs} && -n ${rm_pkgs} ]]; then
            overlap="$(comm -12 <(echo "${add_pkgs}") <(echo "${rm_pkgs}") || true)"
            if [[ -n ${overlap} ]]; then
                while IFS= read -r c_pkg; do
                    [[ -n ${c_pkg} ]] || continue
                    log_err "${dev_name} [L06]: 软件包 ${c_pkg} 同时存在于 add 与 remove 列表中"
                    dev_err=1
                done <<<"${overlap}"
            fi
        fi
        ((dev_err == 0)) && log_ok "${dev_name} (common)"
        continue
    fi

    yaml_file="${dev_dir}/device.yaml"
    if [[ ! -f ${yaml_file} ]]; then
        log_err "${dev_name} [L01]: 未找到 device.yaml 配置文件"
        continue
    fi

    if ! yq . "${yaml_file}" >/dev/null 2>&1; then
        log_err "${dev_name} [L02]: device.yaml 语法解析失败"
        continue
    fi

    # 校验 name 一致性
    yaml_name="$(yq '.name // ""' "${yaml_file}")"
    if [[ ${yaml_name} != "${dev_name}" ]]; then
        log_err "${dev_name} [L03]: 配置字段 name (${yaml_name}) 与目录名 (${dev_name}) 不匹配"
        dev_err=1
    fi

    # 必填基础字段检查
    for field in target subtarget profile arch; do
        val="$(yq ".${field} // \"\"" "${yaml_file}")"
        if [[ -z ${val} || ${val} == "null" ]]; then
            log_err "${dev_name} [L04]: 缺少必填基础字段 ${field}"
            dev_err=1
        fi
    done

    # 校验 source 分发参数
    channel="$(yq '.source.channel // ""' "${yaml_file}")"
    mode="$(yq '.source.mode // ""' "${yaml_file}")"
    if [[ -z ${channel} || ${channel} == "null" ]]; then
        log_err "${dev_name} [L05]: source.channel 不能为空"
        dev_err=1
    fi

    upstream="$(yq '.source.upstream // ""' "${yaml_file}")"
    if [[ ! ${upstream} =~ ^https?:// ]]; then
        log_err "${dev_name} [L05]: source.upstream 必须为有效的 HTTP/HTTPS 链接（官方上游源根地址）"
        dev_err=1
    fi

    if [[ ${mode} == "build" ]]; then
        repo="$(yq '.source.repo // ""' "${yaml_file}")"
        ref="$(yq '.source.ref // ""' "${yaml_file}")"
        if [[ -z ${repo} || -z ${ref} || ${repo} == "null" || ${ref} == "null" ]]; then
            log_err "${dev_name} [L05]: mode=build 时 source.repo 与 source.ref 不能为空"
            dev_err=1
        fi
    elif [[ ${mode} != "download" ]]; then
        log_err "${dev_name} [L05]: source.mode 仅支持 download 或 build (当前配置: ${mode})"
        dev_err=1
    fi

    kmod_source="$(yq '.source.kmod_source // ""' "${yaml_file}")"
    if [[ -n ${kmod_source} && ${kmod_source} != "null" && ${kmod_source} != "download" && ${kmod_source} != "build" ]]; then
        log_err "${dev_name} [L05]: source.kmod_source 仅支持 download 或 build (当前配置: ${kmod_source})"
        dev_err=1
    fi

    # 校验软件包添加/移除自我矛盾
    add_pkgs="$(yq '.packages.add[]? // ""' "${yaml_file}" | sed '/^$/d;/^null$/d' | sort -u || true)"
    rm_pkgs="$(yq '.packages.remove[]? // ""' "${yaml_file}" | sed '/^$/d;/^null$/d' | sort -u || true)"
    if [[ -n ${add_pkgs} && -n ${rm_pkgs} ]]; then
        overlap="$(comm -12 <(echo "${add_pkgs}") <(echo "${rm_pkgs}") || true)"
        if [[ -n ${overlap} ]]; then
            while IFS= read -r c_pkg; do
                [[ -n ${c_pkg} ]] || continue
                log_err "${dev_name} [L06]: 软件包 ${c_pkg} 同时存在于 add 与 remove 列表中"
                dev_err=1
            done <<<"${overlap}"
        fi
    fi

    # 校验分区大小参数
    partsize="$(yq '.image.rootfs_partsize // 0' "${yaml_file}")"
    if [[ ${partsize} != "0" && ${partsize} != "null" ]]; then
        if [[ ! ${partsize} =~ ^[0-9]+$ ]] || ((partsize <= 0)); then
            log_err "${dev_name} [L07]: image.rootfs_partsize 必须为正整数 (当前值: ${partsize})"
            dev_err=1
        fi
    fi

    ((dev_err == 0)) && log_ok "${dev_name}"
done

echo
echo "检查完成: ${errors} 个错误, ${warnings} 个警告"
((errors == 0))
