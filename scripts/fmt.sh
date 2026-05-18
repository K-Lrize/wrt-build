#!/bin/bash
#
# 用法：
#   fmt.sh          自动格式化项目全量 YAML、JSON、Markdown 及 Shell 脚本

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

echo "[INFO] 执行 Prettier 格式化 (YAML / JSON / Markdown)..."
if command -v npx >/dev/null 2>&1; then
    npx -y prettier@latest --write "**/*.{yml,yaml,json,md}"
else
    echo "[WARN] 未检测到 npx 命令，跳过 Prettier 格式化。" >&2
fi

echo "[INFO] 执行 shfmt 格式化 (Shell 脚本)..."
if command -v shfmt >/dev/null 2>&1; then
    find scripts -name "*.sh" -exec shfmt -l -w -i 4 -s {} +
else
    echo "[WARN] 未检测到 shfmt 命令，跳过 Shell 脚本格式化 (可通过 brew install shfmt 安装)。" >&2
fi

echo "[ OK ] 格式化排版完成。"
