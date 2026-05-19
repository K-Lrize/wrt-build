#!/usr/bin/env bash

set -euo pipefail

: "${FILES_DIR:?需由 run-image-scripts.sh 注入}"
: "${DEVICE:?需由 run-image-scripts.sh 注入}"
: "${REPO_ROOT:?需由 run-image-scripts.sh 注入}"

# 解析设备最终包列表，未启用 zsh 则跳过
eval "$(bash "${REPO_ROOT}/scripts/resolve-device.sh" "${DEVICE}" packages)"
case " ${PACKAGES} " in
    *" zsh "*) ;;
    *)
        echo "    - ${DEVICE} 未启用 zsh，跳过插件准备"
        exit 0
        ;;
esac

ZSH_PLUGIN_DIR="${FILES_DIR}/root/.zsh"
mkdir -p "${ZSH_PLUGIN_DIR}"

clone_plugin() {
    local name="$1" url="$2"
    if [[ ! -d "${ZSH_PLUGIN_DIR}/${name}" ]]; then
        echo "    - 正在下载插件: ${name}"
        git clone --depth 1 --quiet "${url}" "${ZSH_PLUGIN_DIR}/${name}"
        rm -rf "${ZSH_PLUGIN_DIR}/${name}/.git"
    else
        echo "    - 插件已存在: ${name}"
    fi
}

clone_plugin "zsh-autosuggestions"     "https://github.com/zsh-users/zsh-autosuggestions"
clone_plugin "zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting"
