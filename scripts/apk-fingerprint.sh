#!/bin/bash
# apk 公钥指纹：sha256(公钥 PEM) 的前 16 字节，输出 32 个十六进制字符。
# 说明：apk 验证索引时是通过公钥内容匹配而非文件名。此指纹计算仅用于公钥文件的命名与标识规范。
#
# 用法：
#   printf '%s\n' "${APK_PUB}" | scripts/apk-fingerprint.sh
#   scripts/apk-fingerprint.sh path/to/public-key.pem
set -euo pipefail

if [[ -n ${1:-} && ${1} != "-" ]]; then
    exec <"${1}"
fi

openssl dgst -sha256 -binary | xxd -p -c 256 | head -c 32
echo
