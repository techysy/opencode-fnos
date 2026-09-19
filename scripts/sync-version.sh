#!/usr/bin/env bash
# 版本号同步脚本：把 VERSION 单一来源写入 manifest 的 version 字段。
#
# 本项目版本号**跟随上游 OpenCode 官方版本**，因此本脚本仅做同步，
# 不做自动累加。
#
# 用法：
#   bash scripts/sync-version.sh            # VERSION -> manifest
#   bash scripts/sync-version.sh 1.18.32    # 指定版本并同步
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER_FILE="$ROOT/VERSION"
MANIFEST="$ROOT/manifest"

# 可选：命令行传入版本则先写入 VERSION
if [ $# -ge 1 ] && [ -n "$1" ]; then
    echo "$1" | tr -d '[:space:]' > "$VER_FILE"
    echo "✓ VERSION 已更新为 $1"
fi

if [ ! -f "$VER_FILE" ]; then
    echo "ERROR: $VER_FILE 不存在" >&2
    exit 1
fi

VERSION="$(tr -d '[:space:]' < "$VER_FILE")"
if [ -z "$VERSION" ]; then
    echo "ERROR: $VER_FILE 为空" >&2
    exit 1
fi

# 校验版本号格式（fnOS 要求 x.y.z 或 x.y.z-r）
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]]; then
    echo "ERROR: 版本号格式非法：$VERSION（应为 x.y.z 或 x.y.z-rc.1）" >&2
    exit 1
fi

if grep -q '^version' "$MANIFEST"; then
    sed -i "s/^version.*/version               = $VERSION/" "$MANIFEST"
else
    echo "ERROR: manifest 中找不到 version 行" >&2
    exit 1
fi

# 顺带同步 manifest 的 desc 中出现的版本号，避免两者不一致
if grep -qE '^desc[[:space:]]*=' "$MANIFEST"; then
    sed -i "s/（TUI）飞牛版 — 内置官方 v[0-9.]* 引擎/（TUI）飞牛版 — 内置官方 v$VERSION 引擎/" "$MANIFEST"
fi

echo "✓ 版本号已同步：VERSION = $VERSION → manifest"
