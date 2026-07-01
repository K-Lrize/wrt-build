#!/bin/bash
#
# 用法：
#   lint-packages.sh                      校验 packages/ 下全部包
#   lint-packages.sh packages/my-foo      校验单个包

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PACKAGES_DIR="${REPO_ROOT}/packages"

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

if [[ $# -ge 1 ]]; then
    targets=("$@")
else
    targets=()
    while IFS= read -r d; do
        targets+=("$d")
    done < <(find "${PACKAGES_DIR}" -mindepth 1 -maxdepth 1 -type d)
fi

for pkg_dir in "${targets[@]}"; do
    makefile="${pkg_dir}/Makefile"
    pkg_name="$(basename "${pkg_dir}")"
    pkg_err=0

    [[ -f ${makefile} ]] || {
        log_warn "${pkg_name}: Makefile not found"
        continue
    }

    # 声明虚拟包 PROVIDES 时建议设置足够高的优先级参数，以确保能够替代默认提供者
    if grep -q 'PROVIDES\s*:=' "${makefile}"; then
        provides_val="$(sed -E -n 's/^[[:space:]]*PROVIDES[[:space:]]*:=[[:space:]]*([^[:space:]]+).*/\1/p' "${makefile}" | head -1)"
        if [[ ${provides_val} != @* ]]; then
            grep -q 'CONFLICTS\s*:=' "${makefile}" || {
                log_err "${pkg_name} [L04]: 声明了 PROVIDES:=${provides_val} 顶替官方包，必须配置 CONFLICTS 防止双重安装冲突！"
                pkg_err=1
            }

            grep -q 'DEFAULT_VARIANT\s*:=\s*1' "${makefile}" ||
                log_warn "${pkg_name} [W01]: PROVIDES:=${provides_val} 建议配置 DEFAULT_VARIANT:=1"

            if grep -q 'PROVIDER_PRIORITY' "${makefile}"; then
                priority="$(sed -E -n 's/^[[:space:]]*PROVIDER_PRIORITY[[:space:]]*:=[[:space:]]*([0-9]+).*/\1/p' "${makefile}" | head -1)"
                if [[ -n ${priority} ]] && ((priority < 200)); then
                    log_warn "${pkg_name} [W02]: PROVIDER_PRIORITY:=${priority} 小于 200。若需顶替官方默认供应商建议 ≥ 200"
                fi
            else
                log_warn "${pkg_name} [W02]: PROVIDES:=${provides_val} 建议显式声明 PROVIDER_PRIORITY"
            fi
        fi
    fi
    if grep -q 'PKG_SOURCE_URL' "${makefile}" && ! grep -q 'PKG_HASH' "${makefile}"; then
        log_warn "${pkg_name} [W03]: PKG_SOURCE_URL 建议补充 PKG_HASH 校验"
    fi

    # 针对版本发布号的智能友好提示（不阻断构建）
    if grep -q 'PKG_RELEASE\s*:=' "${makefile}"; then
        release_val="$(sed -E -n 's/^[[:space:]]*PKG_RELEASE[[:space:]]*:=[[:space:]]*([^[:space:]]+).*/\1/p' "${makefile}" | head -1)"
        if [[ ${release_val} == '$(AUTORELEASE)' || ${release_val} == *"\$("* ]]; then
            :
        elif [[ ${release_val} =~ ^[0-9]+$ ]] && ((release_val >= 100)); then
            :
        else
            log_warn "${pkg_name} [W04]: PKG_RELEASE:=${release_val} 较低。若旨在覆盖官方同名包建议 >=100；若是纯新自建包请忽略"
        fi
    fi
    grep -qE '\$\(eval\s+\$\(call\s+(BuildPackage|KernelPackage)' "${makefile}" || {
        log_err "${pkg_name} [L01]: 缺 \$(eval \$(call BuildPackage,...)) 或 KernelPackage"
        pkg_err=1
    }

    # 目录名需与 PKG_NAME 一致，确保 CI 编译命令准确定位路径
    if grep -q '^PKG_NAME\s*:=' "${makefile}"; then
        pkg_name_val="$(sed -E -n 's/^PKG_NAME[[:space:]]*:=[[:space:]]*([^[:space:]]+).*/\1/p' "${makefile}" | head -1)"
        if [[ -n ${pkg_name_val} && ${pkg_name_val} != "${pkg_name}" ]]; then
            log_err "${pkg_name} [L02]: 目录名 (${pkg_name}) ≠ PKG_NAME (${pkg_name_val})"
            pkg_err=1
        fi
    fi
    if grep -q '^PKG_VERSION\s*:=' "${makefile}"; then
        pkg_version_val="$(sed -E -n 's/^PKG_VERSION[[:space:]]*:=[[:space:]]*([^[:space:]]+).*/\1/p' "${makefile}" | head -1)"
        apk_regex='^[0-9]+(\.[0-9]+)*[a-z]?(_alpha|_beta|_pre|_rc|_cvs|_svn|_git|_hg|_p)?[0-9]*$'
        if [[ ! ${pkg_version_val} =~ $apk_regex ]]; then
            log_err "${pkg_name} [L03]: PKG_VERSION:=${pkg_version_val} 不符合 apk 规范"
            pkg_err=1
        fi
    fi

    ((pkg_err == 0)) && log_ok "${pkg_name}"
done

echo
echo "结果：${errors} 个错误，${warnings} 个警告"
((errors == 0))
