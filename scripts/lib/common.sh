#!/bin/bash
# 公共工具函数。source 此文件使用。

# shellcheck source=log.sh
source "$(dirname "${BASH_SOURCE[0]}")/log.sh"

repo_root() {
    git rev-parse --show-toplevel
}

# device_get <device-name> <yq-expression>
device_get() {
    local dev="$1" key="$2"
    local file
    file="$(repo_root)/devices/${dev}/device.yaml"
    [[ -f ${file} ]] || log_fatal "设备配置不存在：${file}"
    yq "${key}" "${file}"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || log_fatal "缺少必要命令：$1"
}

require_env() {
    [[ -n ${!1:-} ]] || log_fatal "缺少必要环境变量：$1"
}

# 绑定 EXIT 信号自动销毁临时目录，确保不会残留构建文件
make_tmpdir() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '${tmpdir}'" EXIT
    echo "${tmpdir}"
}

make_snapshot_id() {
    echo "$(date -u +%Y-%m-%d)_${GITHUB_SHA:0:7}"
}

# 生成 GitHub Actions 步骤总结 Markdown 表格
# 用法: emit_summary_table <标题> <维度1> <值1> [维度2] [值2] ...
emit_summary_table() {
    local title="$1"
    shift
    [[ -n ${GITHUB_STEP_SUMMARY:-} ]] || return 0

    {
        echo "### ${title}"
        echo ""
        echo "| 项目 | 详细信息 |"
        echo "| :--- | :--- |"
        while [[ $# -ge 2 ]]; do
            echo "| $1 | $2 |"
            shift 2
        done
        echo ""
    } >>"$GITHUB_STEP_SUMMARY"
}
