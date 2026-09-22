#!/usr/bin/env bash
# OpenCode 飞牛打包脚本 — fnpack build + 交付
#
# 用法（在项目根目录运行）：
#   bash scripts/build.sh                          # 用当前 app/bin 二进制直接打包
#   BUILD_AUTO=1 bash scripts/build.sh             # 跳过确认（CI 用）
#   bash scripts/build.sh --from-source            # 从源码全量构建引擎
#   UPSTREAM_VERSION=2.0.13 bash scripts/build.sh --from-source
#
# 前置条件：
#   - app/bin/opencode  官方引擎二进制（--from-source 时自动构建）
#   - bun 1.4.2+        v2 必需（可用 BUN_BIN 指定路径）
#   - fnpack >= 1.2.4
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# 应用标识：fnOS 要求 fpk 文件名前缀必须等于它，因此全局只在此处解析一次
APPNAME=$(sed -n 's/^appname[[:space:]]*=[[:space:]]*\([^[:space:]]*\)/\1/p' "$ROOT/manifest" | head -1)
[ -n "$APPNAME" ] || { echo "ERROR: 无法从 manifest 解析 appname" >&2; exit 1; }
FPK_DIR="${FPK_DELIVER_DIR:-/vol1/1000/fnOS App/fpk/${APPNAME}}"
OLDFPK_DIR="${FPK_OLD_DIR:-/vol1/1000/fnOS App/fpk/oldfpk}"
UPSTREAM_VERSION="${UPSTREAM_VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || echo 2.0.12)}"
ARCH="${ARCH:-x86}"

# ARCH 决定：上游构建目标目录 + manifest 的 platform 字段
# 注意：fnOS 只接受 x86 / arm / loongarch / risc-v / all
case "$ARCH" in
    x86|x86_64) BIN_ARCH="linux-x64";   PLATFORM="x86" ;;
    arm|arm64)  BIN_ARCH="linux-arm64"; PLATFORM="arm" ;;
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
    (cd "$WORK/src" && \
        BUN_TMPDIR="$WORK/tmp" BUN_INSTALL_CACHE_DIR="$WORK/bun-cache" \
        "${BUN_BIN:-bun}" install --ignore-scripts)

    echo "--- 构建引擎（内嵌 Web UI） ---"
    # 用 git init 提供 build 脚本需要的分支信息（tarball 不含 .git）
    (cd "$WORK/src" && git init -q . 2>/dev/null || true)
    (cd "$WORK/src/packages/cli" && \
        OPENCODE_CHANNEL=local OPENCODE_VERSION=local \
        BUN_TMPDIR="$WORK/tmp" BUN_INSTALL_CACHE_DIR="$WORK/bun-cache" \
        "${BUN_BIN:-bun}" run script/build.ts --single --skip-install)

    mkdir -p "$ROOT/app/bin"
    cp "$WORK/src/packages/cli/dist/cli-${BIN_ARCH}/bin/opencode" "$ROOT/app/bin/opencode"
    echo "✓ 引擎已构建（${BIN_ARCH}）"
fi

# --- 依赖准备 ---
mkdir -p "$ROOT/app/bin"

if [ ! -x "$ROOT/app/bin/opencode" ]; then
    echo "ERROR: app/bin/opencode 缺失。请先运行：bash scripts/build.sh --from-source" >&2
    exit 1
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

echo "📦 即将打包：${APPNAME} v${UPSTREAM_VERSION} (${PLATFORM})"

# --- 校验：ui/config 的 auth_token 必须与 cmd/main 的内置密码一致 ---
# 二者不一致会导致飞牛桌面 iframe 打开后 401（白屏），且没有任何日志线索。
if [ -f "$ROOT/app/ui/config" ]; then
    python3 - "$ROOT" <<'PYEOF'
import base64, json, re, sys, os
root = sys.argv[1]
cfg = json.load(open(os.path.join(root, "app/ui/config")))
entry = list(cfg[".url"].values())[0]
url = entry["url"]
m = re.search(r"auth_token=([A-Za-z0-9+/=]+)", url)
if not m:
    sys.exit("ERROR: app/ui/config 的 url 缺少 auth_token")
decoded = base64.b64decode(m.group(1)).decode()
user, pw = decoded.split(":", 1)
main = open(os.path.join(root, "cmd/main"), encoding="utf-8").read()
mm = re.search(r"OPENCODE_SERVER_PASSWORD:-([^}]*)", main)
if not mm:
    sys.exit("ERROR: cmd/main 未找到内置密码")
if pw != mm.group(1):
    sys.exit("ERROR: ui/config 的 token 密码(%s) 与 cmd/main 内置密码(%s) 不一致" % (pw, mm.group(1)))
print("✓ auth_token 与内置密码一致")
PYEOF
fi

if [ "${BUILD_AUTO:-0}" != "1" ]; then
    read -r -p "确认打包? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { echo "已取消"; exit 1; }
fi

# --- fnpack build ---
cd "$ROOT"
rm -f "$APPNAME.fpk"
fnpack build >/dev/null
[ -f "$APPNAME.fpk" ] || { echo 'ERROR: 打包失败（未生成 $APPNAME.fpk）' >&2; exit 1; }

OUT="${APPNAME}-${UPSTREAM_VERSION}-${PLATFORM}.fpk"
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
