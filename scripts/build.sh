#!/usr/bin/env bash
# OpenCode TUI 飞牛打包脚本 — fnpack build + 交付
#
# 用法（在项目根目录运行）：
#   bash scripts/build.sh                          # 用当前 app/bin 二进制直接打包
#   BUILD_AUTO=1 bash scripts/build.sh             # 跳过确认（CI 用）
#   bash scripts/build.sh --from-source            # 从源码全量构建引擎
#   UPSTREAM_VERSION=1.18.32 bash scripts/build.sh --from-source
#
# 前置条件：
#   - app/bin/opencode  官方引擎二进制（--from-source 时自动构建）
#   - app/bin/ttyd      Web 终端网关（缺失时自动下载）
#   - fnpack >= 1.2.4
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FPK_DIR="${FPK_DELIVER_DIR:-/vol1/1000/fnOS App/fpk/opencode}"
OLDFPK_DIR="${FPK_OLD_DIR:-/vol1/1000/fnOS App/fpk/oldfpk}"
UPSTREAM_VERSION="${UPSTREAM_VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || echo 1.18.31)}"
ARCH="${ARCH:-x86}"

# ARCH 决定：上游构建目标目录 + manifest 的 platform 字段
# 注意：fnOS 只接受 x86 / arm / loongarch / risc-v / all
case "$ARCH" in
    x86|x86_64) BIN_ARCH="linux-x64";   PLATFORM="x86"; TTYD_ASSET="ttyd.x86_64" ;;
    arm|arm64)  BIN_ARCH="linux-arm64"; PLATFORM="arm"; TTYD_ASSET="ttyd.aarch64" ;;
    *) echo "ERROR: 不支持的架构 $ARCH（可选 x86 / arm）" >&2; exit 1 ;;
esac

# --- 可选：从源码全量构建引擎 ---
if [ "${1:-}" = "--from-source" ]; then
    WORK="${WORK:-/tmp/opencode-build}"
    echo "=== 从源码构建 OpenCode v${UPSTREAM_VERSION} ==="
    rm -rf "$WORK"; mkdir -p "$WORK/src"

    # 用 tarball 而非 git clone：体积更小、速度快，且无需完整历史
    curl -fSL --retry 3 -o "$WORK/opencode.tar.gz" \
        "https://codeload.github.com/anomalyco/opencode/tar.gz/refs/tags/v${UPSTREAM_VERSION}"
    tar xzf "$WORK/opencode.tar.gz" -C "$WORK/src" --strip-components=1

    echo "--- 应用飞牛适配补丁 ---"
    (cd "$WORK/src" && patch -p1 --forward < "$ROOT/docs/patches/fnos-adaptation.patch")

    echo "--- 安装依赖 ---"
    (cd "$WORK/src" && bun install --ignore-scripts)

    echo "--- 构建引擎（内嵌 Web UI） ---"
    # 用 git init 提供 build 脚本需要的分支信息（tarball 不含 .git）
    (cd "$WORK/src" && git init -q . 2>/dev/null || true)
    (cd "$WORK/src/packages/opencode" && \
        OPENCODE_CHANNEL=local OPENCODE_VERSION=local \
        bun run script/build.ts --single --skip-install)

    mkdir -p "$ROOT/app/bin"
    cp "$WORK/src/packages/opencode/dist/opencode-${BIN_ARCH}/bin/opencode" "$ROOT/app/bin/opencode"
    echo "✓ 引擎已构建（${BIN_ARCH}）"
fi

# --- 依赖准备 ---
mkdir -p "$ROOT/app/bin"

if [ ! -x "$ROOT/app/bin/opencode" ]; then
    echo "ERROR: app/bin/opencode 缺失。请先运行：bash scripts/build.sh --from-source" >&2
    exit 1
fi

if [ ! -x "$ROOT/app/bin/ttyd" ]; then
    echo "ℹ️  ttyd 缺失，自动下载..."
    curl -fL --retry 3 -o "$ROOT/app/bin/ttyd" \
        "https://github.com/tsl0922/ttyd/releases/download/1.7.7/${TTYD_ASSET}"
    chmod +x "$ROOT/app/bin/ttyd"
    echo "✓ ttyd 已下载"
fi
chmod +x "$ROOT/app/bin/"* 2>/dev/null || true

# --- 同步版本号与 platform ---
bash "$ROOT/scripts/sync-version.sh"
if grep -qE '^platform[[:space:]]*=' "$ROOT/manifest"; then
    sed -i "s/^platform[[:space:]]*=.*/platform              = ${PLATFORM}/" "$ROOT/manifest"
else
    sed -i "/^version/a platform              = ${PLATFORM}" "$ROOT/manifest"
fi
echo "✓ platform = ${PLATFORM}"

echo "📦 即将打包：opencode-tui v${UPSTREAM_VERSION} (${PLATFORM})"

# --- 页面脚本语法校验 ---
# app/web/index.html 由 ttyd 官方页面字符串替换而来。替换若破坏压缩 JS，
# 浏览器会 SyntaxError 导致整页白屏，而 HTTP / WebSocket 全正常，极难排查。
if [ -f "$ROOT/app/web/index.html" ]; then
    node "$ROOT/scripts/check-web-syntax.js" "$ROOT/app/web/index.html" \
        || { echo "ERROR: 页面脚本语法校验失败" >&2; exit 1; }
fi

if [ "${BUILD_AUTO:-0}" != "1" ]; then
    read -r -p "确认打包? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { echo "已取消"; exit 1; }
fi

# --- fnpack build ---
cd "$ROOT"
# fnpack 以 manifest 的 appname 命名产物，这里动态读取，避免改名后失效
APPNAME=$(sed -n 's/^appname[[:space:]]*=[[:space:]]*\([^[:space:]]*\)/\1/p' "$ROOT/manifest" | head -1)
[ -n "$APPNAME" ] || { echo 'ERROR: 无法从 manifest 解析 appname' >&2; exit 1; }
rm -f "$APPNAME.fpk"
fnpack build >/dev/null
[ -f "$APPNAME.fpk" ] || { echo 'ERROR: 打包失败（未生成 $APPNAME.fpk）' >&2; exit 1; }

OUT="opencode-tui-${UPSTREAM_VERSION}-${PLATFORM}.fpk"
mv "$APPNAME.fpk" "$OUT"
echo "✓ 构建完成：$OUT ($(du -h "$OUT" | cut -f1))"

# --- 生成校验和 ---
mkdir -p "$ROOT/dist"
mv "$OUT" "$ROOT/dist/$OUT"
(cd "$ROOT/dist" && sha256sum "$OUT" > "SHA256SUMS-${PLATFORM}")
echo "✓ 校验和：$(cat "$ROOT/dist/SHA256SUMS-${PLATFORM}")"

# --- 交付（仅本地环境存在该路径时）---
if [ -d "$(dirname "$FPK_DIR")" ]; then
    mkdir -p "$FPK_DIR" "$OLDFPK_DIR"
    # 同名旧包先归档，避免覆盖后无法回滚
    if [ -f "$FPK_DIR/$OUT" ]; then
        mv "$FPK_DIR/$OUT" "$OLDFPK_DIR/$OUT"
        echo "✓ 同名旧包已归档：$OLDFPK_DIR/$OUT"
    fi
    cp "$ROOT/dist/$OUT" "$FPK_DIR/"
    echo "✓ 已交付：$FPK_DIR/$OUT"
fi

echo "✅ 全部完成"
