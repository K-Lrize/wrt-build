#!/bin/bash
# 日志工具。source 此文件使用。CI 上自动切换为 GitHub Actions 注解格式。

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC}  $(date -u +%H:%M:%S) $*"; }
log_ok() { echo -e "${GREEN}[ OK ]${NC}  $(date -u +%H:%M:%S) $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  $(date -u +%H:%M:%S) $*" >&2; }
log_fatal() {
    echo -e "${RED}[FATAL]${NC} $(date -u +%H:%M:%S) $*" >&2
    exit 1
}

if [[ ${GITHUB_ACTIONS:-false} == "true" ]]; then
    log_info() { echo "::notice::$*"; }
    log_ok() { echo "::notice::$*"; }
    log_warn() { echo "::warning::$*" >&2; }
    log_fatal() {
        echo "::error::$*" >&2
        exit 1
    }
fi
