#!/usr/bin/env bash
# 迁移脚本：把本项目从构建工作区部署到 fnOS 开发目录并建仓。
#
# 背景：当前会话的沙箱只能写入工作区，无法直接写 /vol1/1000。
#       以有权限的用户（如 yangyu）执行本脚本即可完成迁移。
#
# 用法：
#   bash scripts/migrate-to-fnos-dev.sh              # 拷贝到 fnOS Dev 并建仓
#   bash scripts/migrate-to-fnos-dev.sh --push       # 额外推送到 GitHub
#
# 目标：
#   项目  -> /vol1/1000/fnOS Dev/opencode-fnos
#   产物  -> /vol1/1000/fnOS App/fpk/opencode
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${DEST:-/vol1/1000/fnOS Dev/opencode-fnos}"
FPK_DIR="${FPK_DIR:-/vol1/1000/fnOS App/fpk/opencode}"
OLDFPK_DIR="${OLDFPK_DIR:-/vol1/1000/fnOS App/fpk/oldfpk}"
GIT_REMOTE="${GIT_REMOTE:-https://github.com/techysy/opencode-fnos.git}"

echo "源  ：$SRC"
echo "目标：$DEST"

mkdir -p "$DEST"

# 用 rsync 保留结构；--exclude 掉二进制与构建产物（由 .gitignore/CI 管理）
if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
        --exclude '.git/' \
        --exclude 'app/bin/opencode' \
        --exclude 'app/bin/ttyd' \
        --exclude 'dist/' \
        --exclude '*.fpk' \
        --exclude 'deliver/' \
        "$SRC/" "$DEST/"
else
    cp -a "$SRC/." "$DEST/"
    rm -rf "$DEST/.git" "$DEST/dist" "$DEST/deliver"
    rm -f  "$DEST/app/bin/opencode" "$DEST/app/bin/ttyd" "$DEST"/*.fpk
fi
echo "✓ 已同步文件"

# 保留 .gitkeep，确保 app/bin 目录存在于仓库中
touch "$DEST/app/bin/.gitkeep"

# --- 规范化权限 ---
# 构建工作区里由工具写入的文件可能是 0600（仅属主可读），
# 迁移到 fnOS 目录后会导致 git status 告警、其他用户无法读取。
# 这里统一为：目录 755 / 普通文件 644 / 脚本与二进制 755。
chmod 755 "$DEST" 2>/dev/null || true
find "$DEST" -path "$DEST/.git" -prune -o -type d -print0 2>/dev/null | xargs -0 -r chmod 755 2>/dev/null || true
find "$DEST" -path "$DEST/.git" -prune -o -type f -print0 2>/dev/null | xargs -0 -r chmod 644 2>/dev/null || true
# 生命周期脚本与打包脚本必须可执行
find "$DEST/cmd" "$DEST/scripts" -type f -print0 2>/dev/null | xargs -0 -r chmod 755 2>/dev/null || true
# app/bin 下若已有二进制，保持可执行
[ -d "$DEST/app/bin" ] && chmod 755 "$DEST/app/bin"/* 2>/dev/null || true
echo "✓ 权限已规范化（目录 755 / 文件 644 / 脚本 755）"

# --- 初始化/更新 git 仓库 ---
cd "$DEST"
if [ ! -d .git ]; then
    git init -q .
    git branch -M master 2>/dev/null || true
    git remote add origin "$GIT_REMOTE" 2>/dev/null || git remote set-url origin "$GIT_REMOTE"
    echo "✓ 已初始化 git 仓库（origin = $GIT_REMOTE）"
else
    echo "ℹ️  已是 git 仓库，跳过初始化"
fi

# --- 交付产物（若本地已有 dist/*.fpk）---
if compgen -G "$SRC/dist/*.fpk" >/dev/null 2>&1; then
    mkdir -p "$FPK_DIR" "$OLDFPK_DIR"
    for f in "$SRC"/dist/*.fpk; do
        base="$(basename "$f")"
        if [ -f "$FPK_DIR/$base" ]; then
            mv "$FPK_DIR/$base" "$OLDFPK_DIR/$base"
            echo "✓ 同名旧包已归档：$OLDFPK_DIR/$base"
        fi
        cp "$f" "$FPK_DIR/"
        echo "✓ 已交付：$FPK_DIR/$base"
    done
else
    echo "ℹ️  未发现 dist/*.fpk，跳过产物交付"
fi

# --- 可选：推送 ---
if [ "${1:-}" = "--push" ]; then
    cd "$DEST"
    git add -A
    git diff --cached --quiet || git commit -m "chore: sync from build workspace"
    git push -u origin master
    echo "✓ 已推送到 origin/master"
fi

echo
echo "✅ 迁移完成"
echo "   项目：$DEST"
echo "   下一步："
echo "     cd \"$DEST\" && git add -A && git commit -m 'feat: initial'"
echo "     git remote add origin $GIT_REMOTE && git push -u origin master"
echo "     git tag v$(tr -d '[:space:]' < "$DEST/VERSION") && git push origin --tags"
