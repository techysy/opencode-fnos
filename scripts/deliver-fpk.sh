#!/usr/bin/env bash
# 把 CI 构建好的 fpk 交付到本地 fnOS 目录。
# 用法：bash scripts/deliver-fpk.sh [版本] [架构]
set -euo pipefail

VERSION="${1:-$(tr -d "[:space:]" < "$(dirname "$0")/../VERSION")}"
ARCH="${2:-x86}"
# 文件名前缀必须等于 manifest 的 appname，否则 fnOS 报「不符合系统要求」
FILE="${APPNAME:-oc}-${VERSION}-${ARCH}.fpk"

DEST="${FPK_DELIVER_DIR:-/vol1/1000/fnOS App/fpk/${APPNAME:-oc}}"
OLD="${FPK_OLD_DIR:-/vol1/1000/fnOS App/fpk/oldfpk}"

mkdir -p "$DEST" "$OLD"

# 同名旧包先归档，避免覆盖丢失
if [ -f "$DEST/$FILE" ]; then
    mv "$DEST/$FILE" "$OLD/$FILE"
    echo "✓ 同名旧包已归档：$OLD/$FILE"
fi

# 从 Release 下载（若本地 dist/ 已有则直接用）
if [ -f "dist/$FILE" ]; then
    cp "dist/$FILE" "$DEST/$FILE"
    echo "✓ 由本地 dist/ 交付"
else
    command -v gh >/dev/null || { echo "ERROR: 需要 gh 或先本地构建" >&2; exit 1; }
    gh release download "v${VERSION}" --repo techysy/opencode-fnos \
        --pattern "$FILE" --dir "$DEST" --clobber
    echo "✓ 已从 GitHub Release v${VERSION} 下载"
fi

echo "  位置：$DEST/$FILE"
ls -lh "$DEST/$FILE" | awk '{print "  大小：" $5}'
sha256sum "$DEST/$FILE" | sed 's/^/  SHA256: /'